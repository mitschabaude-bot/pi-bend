import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/file-fold.bend as Fold
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/stable-sort.bend as Sort
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as W
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/collation.bend as Collation
import ./messages.bend as Messages
import ./session-manager.bend as S
import ./session-json.bend as SJ

# The upstream SessionManager class: sessions as append-only trees in JSONL
# files. The tree operations live in session-manager.bend as immutable state;
# this module owns the file: creation, discovery, loading with migration,
# the flush-on-first-assistant persistence rule, rewriting and forking.
# Callers query the state through `stateOf` and the state module's functions
# rather than through forwarding methods.

def Decoded(-A: Data) -> Data: Result<&2, &2, Decode.Error, A>

type Error is Data:
  InvalidSessionId{}
  NotASession{path: String}
  EntryNotFound{id: String}
  EmptySource{path: String}
  NoSourceHeader{path: String}
  ScanLimit{path: String}
  Filesystem{path: String, cause: FS.Error}
  State{cause: S.Error}
  Identity{message: String}
  Clock{}

def SESSION_HEADER_READ_BUFFER_SIZE() -> U32: 4096
def MAX_SESSION_HEADER_SCAN_BYTES() -> Nat: Nat.mul(1024n, 1024n)

def stateMessage(error: S.Error) -> String:
  match error:
    case S.DuplicateId{+id}: "Duplicate entry id " ++ id
    case S.EmptyId{}: "Entry id must not be empty"
    case S.Cycle{id}: "Entry " ++ id ++ " is its own ancestor"
    case S.EntryNotFound{id}: "Entry " ++ id ++ " not found"
    case S.InvalidMessage{}: "Compaction and branch summaries must be appended as entries"
    case S.LabelIdCount{}: "Wrong number of label ids"
    case S.InvalidTimestamp{id, _}: "Entry " ++ id ++ " has an invalid timestamp"
    case S.NotOnActiveBranch{id}: "Entry " ++ id ++ " is not on the active branch"
    case S.NotEditable{id}: "Entry " ++ id ++ " does not contribute editable model content"
    case S.UnfitContextEdit{id}: "Context edit " ++ id ++ " replaces content with blocks its target role cannot hold"

def fileMessage(error: FS.Error) -> String:
  match error:
    case FS.System{_, text}: text
    case FS.InvalidPathEncoding{_}: "invalid path encoding"
    case FS.WriteAndClose{_, text, _, _}: text
    case FS.ReadAndClose{_, text, _, _}: text

# The upstream error texts, place upstream throws.
def message(error: Error) -> String:
  match error:
    case InvalidSessionId{}: "Session id must be non-empty, contain only alphanumeric characters, '-', '_', and '.', and start and end with an alphanumeric character"
    case NotASession{path}: "Session file is not a valid pi session: " ++ path
    case EntryNotFound{id}: "Entry " ++ id ++ " not found"
    case EmptySource{path}: "Cannot fork: source session file is empty or invalid: " ++ path
    case NoSourceHeader{path}: "Cannot fork: source session has no header: " ++ path
    case ScanLimit{+path}: "Session header exceeds " ++ Nat.show(MAX_SESSION_HEADER_SCAN_BYTES()) ++ "-byte scan limit: " ++ path
    case Filesystem{+path, cause}: path ++ ": " ++ fileMessage(cause)
    case State{cause}: stateMessage(cause)
    case Identity{text}: text
    case Clock{}: "Could not format the current time"

def Outcome(-A: Data) -> Data: Result<&2, &2, Error, A>

type NewSessionOptions is Data:
  NewSessionOptions{id: Maybe<&2, String>, parentSession: Maybe<&2, String>}

def noOptions() -> NewSessionOptions: NewSessionOptions{None{}, None{}}

# Session ids
# -----------

def alphanumeric(+code: U32) -> Bool:
  (U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))

def interior(+code: U32) -> Bool:
  alphanumeric(code) || U32.is_eq(code, 45) || U32.is_eq(code, 95) || U32.is_eq(code, 46)

def validTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, SNil{}}: alphanumeric(code)
    case SCon{Chr{+code}, rest}: interior(code) && validTail(rest)

# /^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/
def validSessionId(id: String) -> Bool:
  match id:
    case SNil{}: False{}
    case SCon{Chr{+code}, rest}: alphanumeric(code) && validTail(rest)

def assertValidSessionId(+id: String) -> Outcome(Unit):
  Bool.pick(Outcome(Unit), validSessionId(id), Done{Unit{}}, Fail{InvalidSessionId{}})

def identity(result: Result<&2, &2, Uuid.Error, String>) -> Outcome(String):
  match result:
    case Done{id}: Done{id}
    case Fail{error}: Fail{Identity{Uuid.errorMessage(error)}}

# upstream createSessionId: a UUIDv7 from the process generator.
def createSessionId(ids: Uuid.Generator) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    result : Result<&2, &2, Uuid.Error, String> <- Uuid.uuidv7(ids, None{})
    return identity(result)

def chosenId(ids: Uuid.Generator, requested: Maybe<&2, String>) -> IO(Outcome(String)):
  match requested:
    case Some{+id}: IO.pure(Outcome(String), Result.map(&2, &2, Error, Unit, String, _ => id, assertValidSessionId(id)))
    case None{}: createSessionId(ids)

def hexDigit(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hexBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{hexDigit(U32.shrn(byte, 4n)), SCon{hexDigit(U32.and(byte, 15)), hexBytes(rest)}}

def shortId(random: Result<&1, &1, U32 & String, List<&2, U32>>) -> Maybe<&2, String>:
  match random:
    case Done{bytes}: Some{hexBytes(bytes)}
    case Fail{_}: None{}

def fullId() -> IO(String):
  do IO<String>:
    result : Result<&2, &2, Uuid.Error, String> <- Uuid.randomUUID()
    return Result.default(&2, &2, Uuid.Error, String, result, "00000000")

def attempt(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>, candidate: Maybe<&2, String>, retry: Unit -> IO(String)) -> IO(String):
  match candidate:
    case None{}: retry(Unit{})
    case Some{+id}: Bool.pick(Unit -> IO(String), Maybe.is_none(&2, S.SessionEntry<D, T, C>, S.getEntry(D, T, C, state, id)), _ => IO.pure(String, id), retry)(Unit{})

# A short 8-hex-digit id, collision-checked; a full UUID after 100 collisions.
def generateId(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>, attempts: Nat) -> IO(String):
  match attempts:
    case 0n: fullId()
    case 1n+remaining:
      do IO<String>:
        random : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(4)
        attempt(D, T, C, state, shortId(random), _ => generateId(D, T, C, state, remaining))

def isoNow() -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    now : F64 <- Date.now()
    return Maybe.default(&2, Outcome(String), Maybe.map(&2, String, Outcome(String), text => Done{text}, Date.formatIso(now)), Fail{Clock{}})

def stampWith(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>, timestamp: Outcome(String)) -> IO(Outcome(S.EntryStamp)):
  match timestamp:
    case Fail{error}: IO.pure(Outcome(S.EntryStamp), Fail{error})
    case Done{time}:
      do IO<Outcome(S.EntryStamp)>:
        id : String <- generateId(D, T, C, state, 100n)
        return Done{S.EntryStamp{id, time}}

def freshStamp(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>) -> IO(Outcome(S.EntryStamp)):
  do IO<Outcome(S.EntryStamp)>:
    timestamp : Outcome(String) <- isoNow()
    stampWith(D, T, C, state, timestamp)

# Files
# -----

def fileTimestamp(timestamp: String) -> String:
  match timestamp:
    case SNil{}: ""
    case SCon{':', rest}: SCon{'-', fileTimestamp(rest)}
    case SCon{'.', rest}: SCon{'-', fileTimestamp(rest)}
    case SCon{char, rest}: SCon{char, fileTimestamp(rest)}

def sessionFileName(timestamp: String, id: String) -> String:
  fileTimestamp(timestamp) ++ "_" ++ id ++ ".jsonl"

def fileError(-A: Data, path: String, result: Result<&2, &2, FS.Error, A>) -> Outcome(A):
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{Filesystem{path, cause}}

def textOf(result: Result<&2, &2, Utf8.Error, String>) -> Maybe<&2, String>:
  match result:
    case Done{text}: Some{text}
    case Fail{_}: None{}

def decodedText(bytes: List<&2, U32>) -> Maybe<&2, String>: textOf(Utf8.decodeWith(Utf8.Preserve{}, bytes))

# The default session directory encodes the working directory in its name:
# ~/.pi/agent/sessions/--path-to-cwd--
def encodedCwd(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'/', rest}: SCon{'-', encodedCwd(rest)}
    case SCon{'\\', rest}: SCon{'-', encodedCwd(rest)}
    case SCon{':', rest}: SCon{'-', encodedCwd(rest)}
    case SCon{char, rest}: SCon{char, encodedCwd(rest)}

def withoutLeadingSlash(text: String) -> String:
  match text:
    case SCon{'/', rest}: rest
    case SCon{'\\', rest}: rest
    case other: other

def getDefaultSessionDirPath(cwd: String, agentDir: String) -> String:
  Path.join(Path.join(Path.normalize(agentDir), "sessions"), "--" ++ encodedCwd(withoutLeadingSlash(Path.normalize(cwd))) ++ "--")

def getDefaultSessionDir(cwd: String, agentDir: String) -> IO(Outcome(String)):
  +dir = getDefaultSessionDirPath(cwd, agentDir)
  do IO<Outcome(String)>:
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(dir)
    return Result.map(&2, &2, Error, Unit, String, _ => dir, fileError(Unit, dir, made))

def chosenDir(sessionDir: Maybe<&2, String>, cwd: String, agentDir: String) -> IO(Outcome(String)):
  match sessionDir:
    case Some{dir}: IO.pure(Outcome(String), Done{Path.normalize(dir)})
    case None{}: getDefaultSessionDir(cwd, agentDir)

# A custom session directory other than the default one is shared between
# projects; its listings and continuation are then scoped by cwd.
def filtersCwd(sessionDir: Maybe<&2, String>, dir: String, cwd: String, agentDir: String) -> Bool:
  match sessionDir:
    case None{}: False{}
    case Some{_}: Bool.not(String.eq(dir, getDefaultSessionDirPath(cwd, agentDir)))

def sessionCwdMatches(+cwd: String, resolvedCwd: String) -> Bool:
  Bool.not(String.is_empty(cwd)) && String.eq(Path.normalize(cwd), Path.normalize(resolvedCwd))

# Loading
# -------

type Loaded<-D: Data, -T: Data, -C: Data> is Data:
  Loaded{entries: List<&2, S.FileEntry<D, T, C>>, migrated: Bool}

def afterLastNewline(text: String, +pending: String) -> String:
  match text:
    case SNil{}: pending
    case SCon{'\n', rest}: afterLastNewline(rest, "")
    case SCon{char, rest}: afterLastNewline(rest, SCon{char, pending})

# The text after the final newline (reversed, only emptiness matters).
def unterminated(content: String) -> Bool:
  Bool.not(String.is_empty(afterLastNewline(content, "")))

def validHeader(-D: Data, -T: Data, -C: Data, entries: List<&2, S.FileEntry<D, T, C>>) -> Bool:
  match entries:
    case S.Header{_} <> _: True{}
    case _: False{}

def repaired(-D: Data, -T: Data, -C: Data, +path: String, +loaded: Loaded<D, T, C>, valid: Bool, pending: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  match valid pending:
    case False{} _: IO.pure(Outcome(Loaded<D, T, C>), Done{Loaded{Nil{}, False{}}})
    case True{} False{}: IO.pure(Outcome(Loaded<D, T, C>), Done{loaded})
    case True{} True{}:
      do IO<Outcome(Loaded<D, T, C>)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.appendFile(path, "\n")
        return Result.map(&2, &2, Error, Unit, Loaded<D, T, C>, _ => loaded, fileError(Unit, path, result))

def loadedMigration(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), path: String, pending: Bool, migration: SJ.Migration) -> IO(Outcome(Loaded<D, T, C>)):
  match migration:
    case SJ.Migration{migrated, values}:
      +entries = SJ.decodeValues(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, values)
      repaired(D, T, C, path, Loaded{entries, migrated}, validHeader(D, T, C, entries), pending)

def migratedIf(migrate: Bool, values: List<&2, V.Value>) -> IO(SJ.Migration):
  match migrate:
    case True{}: SJ.migrated(values)
    case False{}: IO.pure(SJ.Migration, SJ.Migration{False{}, values})

def loadedValues(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), path: String, +content: String, migrate: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  do IO<Outcome(Loaded<D, T, C>)>:
    migration : SJ.Migration <- migratedIf(migrate, SJ.parsedLines(String.split(content, '\n'), Nil{}))
    loadedMigration(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, unterminated(content), migration)

def loadedText(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), path: String, text: Maybe<&2, String>, migrate: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  match text:
    case None{}: IO.pure(Outcome(Loaded<D, T, C>), Done{Loaded{Nil{}, False{}}})
    case Some{content}: loadedValues(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, content, migrate)

def loadedBytes(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +path: String, bytes: Result<&2, &2, FS.Error, List<&2, U32>>, migrate: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  match bytes:
    case Fail{cause}: IO.pure(Outcome(Loaded<D, T, C>), Fail{Filesystem{path, cause}})
    case Done{content}: loadedText(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, decodedText(content), migrate)

def loadExisting(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +path: String, present: Bool, migrate: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  match present:
    case False{}: IO.pure(Outcome(Loaded<D, T, C>), Done{Loaded{Nil{}, False{}}})
    case True{}:
      do IO<Outcome(Loaded<D, T, C>)>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        loadedBytes(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, bytes, migrate)

# Entries of a session file, migrated to the current version; a file whose
# first entry is not a session header yields none. A valid file without a
# final newline gains one, so later appends start on their own line.
def loadFileWith(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +path: String, migrate: Bool) -> IO(Outcome(Loaded<D, T, C>)):
  do IO<Outcome(Loaded<D, T, C>)>:
    present : Bool <- FS.accessible(path, 0)
    loadExisting(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, present, migrate)

def loadFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), path: String) -> IO(Outcome(Loaded<D, T, C>)):
  loadFileWith(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, True{})

def entriesOf(-D: Data, -T: Data, -C: Data, loaded: Outcome(Loaded<D, T, C>)) -> List<&2, S.FileEntry<D, T, C>>:
  match loaded:
    case Done{Loaded{entries, _}}: entries
    case Fail{_}: Nil{}

def loadEntriesFromFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), path: String) -> IO(List<&2, S.FileEntry<D, T, C>>):
  do IO<List<&2, S.FileEntry<D, T, C>>>:
    loaded : Outcome(Loaded<D, T, C>) <- loadFileWith(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, path, False{})
    return entriesOf(D, T, C, loaded)

# Header scan
# -----------
# Discovery reads at most one megabyte to find the first parsed line: a header
# or, for a non-session file, some other entry. Larger prefixes report the
# scan limit; a full load then remains authoritative.

type Scan is Data:
  Scan{scanned: Nat, pending: List<&2, U32>, decision: Maybe<&2, Maybe<&2, S.SessionHeader>>, overLimit: Bool}

def headerKind(isSession: Bool, fields: R.Record<V.Value>) -> Maybe<&2, Maybe<&2, S.SessionHeader>>:
  match isSession:
    case False{}: Some{None{}}
    case True{}: Some{SJ.maybeOf(Decode.Error, S.SessionHeader, SJ.headerFields(fields))}

def headerOf(value: Maybe<&2, V.Value>) -> Maybe<&2, Maybe<&2, S.SessionHeader>>:
  match value:
    case None{}: None{}
    case Some{V.ObjectValue{+fields}}: headerKind(String.eq(SJ.textField(R.get(V.Value, fields, "type")), "session"), fields)
    case Some{_}: Some{None{}}

def parsedBytes(bytes: List<&2, U32>) -> Maybe<&2, V.Value>:
  Maybe.bind(&2, String, V.Value, decodedText(bytes), text => SJ.parsedLine(text))

# Undefined keeps scanning, Some None is a non-header entry, Some Some the header.
def candidate(reversed: List<&2, U32>) -> Maybe<&2, Maybe<&2, S.SessionHeader>>:
  headerOf(parsedBytes(List.reverse(&2, U32, reversed)))

def scanStep(withinLimit: Bool, newline: Bool, +scanned: Nat, +pending: List<&2, U32>, byte: U32, +overLimit: Bool) -> Scan:
  match withinLimit newline:
    case False{} _: Scan{scanned, pending, None{}, True{}}
    case True{} False{}: Scan{1n + scanned, byte <> pending, None{}, overLimit}
    case True{} True{}: Scan{1n + scanned, Nil{}, candidate(pending), overLimit}

def scanByte(state: Scan, +byte: U32) -> Scan:
  match state:
    case Scan{scanned, pending, Some{decision}, overLimit}: Scan{scanned, pending, Some{decision}, overLimit}
    case Scan{+scanned, pending, None{}, overLimit}: scanStep(Nat.is_lt(scanned, MAX_SESSION_HEADER_SCAN_BYTES()), U32.is_eq(byte, 10), scanned, pending, byte, overLimit)

def scanBytes(bytes: List<&2, U32>, +state: Scan) -> Scan:
  match bytes:
    case Nil{}: state
    case byte <> rest: scanBytes(rest, scanByte(state, byte))

def scanControl(state: Scan) -> Fold.Control<Scan>:
  match state:
    case Scan{scanned, pending, None{}, False{}}: Fold.Continue{Scan{scanned, pending, None{}, False{}}}
    case other: Fold.Stop{other}

def scanChunk(state: Scan, bytes: List<&2, U32>) -> Fold.Control<Scan>:
  scanControl(scanBytes(bytes, state))

def scanOutcome(+path: String, outcome: Fold.Outcome<Scan>) -> Outcome(Maybe<&2, S.SessionHeader>):
  match outcome:
    case Fold.Outcome{_, Fail{Fold.Open{code, text}}}: Fail{Filesystem{path, FS.System{code, text}}}
    case Fold.Outcome{_, Fail{Fold.Read{code, text}}}: Fail{Filesystem{path, FS.System{code, text}}}
    case Fold.Outcome{_, Fail{Fold.Close{code, text}}}: Fail{Filesystem{path, FS.System{code, text}}}
    case Fold.Outcome{_, Fail{Fold.ReadAndClose{code, text, _, _}}}: Fail{Filesystem{path, FS.System{code, text}}}
    case Fold.Outcome{_, Fail{Fold.InvalidReadSize{}}}: Fail{Filesystem{path, FS.System{22, "invalid read size"}}}
    case Fold.Outcome{Scan{_, _, Some{decision}, _}, Done{_}}: Done{decision}
    case Fold.Outcome{Scan{_, _, None{}, True{}}, Done{_}}: Fail{ScanLimit{path}}
    case Fold.Outcome{Scan{_, pending, None{}, False{}}, Done{_}}: Done{Maybe.default(&2, Maybe<&2, S.SessionHeader>, candidate(pending), None{})}

def readSessionHeader(+path: String) -> IO(Outcome(Maybe<&2, S.SessionHeader>)):
  do IO<Outcome(Maybe<&2, S.SessionHeader>)>:
    outcome : Fold.Outcome<Scan> <- Fold.read(~Scan, ~scanChunk, path, SESSION_HEADER_READ_BUFFER_SIZE(), Scan{0n, Nil{}, None{}, False{}})
    return scanOutcome(path, outcome)

# Discovery is best-effort: unreadable or oversized files are not sessions.
def readSessionHeaderForDiscovery(path: String) -> IO(Maybe<&2, S.SessionHeader>):
  do IO<Maybe<&2, S.SessionHeader>>:
    result : Outcome(Maybe<&2, S.SessionHeader>) <- readSessionHeader(path)
    return Result.default(&2, &2, Error, Maybe<&2, S.SessionHeader>, result, None{})

def headerCwd(header: S.SessionHeader) -> String:
  match header:
    case S.SessionHeader{_, _, _, cwd, _}: cwd

def headerId(header: S.SessionHeader) -> String:
  match header:
    case S.SessionHeader{_, id, _, _, _}: id

# Discovery
# ---------

def isJsonl(name: String) -> Bool: String.ends_with(name, ".jsonl")

def jsonlFiles(+dir: String, entries: List<&2, FS.DirectoryEntry>, +reversed: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}: List.reverse(&2, String, reversed)
    case FS.DirectoryEntry{+name, _} <> rest: jsonlFiles(dir, rest, Bool.pick(List<&2, String>, isJsonl(name), Path.join(dir, name) <> reversed, reversed))

def listedFiles(dir: String, result: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>) -> Maybe<&2, List<&2, String>>:
  match result:
    case Fail{_}: None{}
    case Done{entries}: Some{jsonlFiles(dir, entries, Nil{})}

def sessionFiles(+dir: String) -> IO(Maybe<&2, List<&2, String>>):
  do IO<Maybe<&2, List<&2, String>>>:
    result : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(dir)
    return listedFiles(dir, result)

type Timed is Data:
  Timed{path: String, modified: F64}

def newerFirst(left: Timed, right: Timed) -> Bool:
  match left right:
    case Timed{_, a} Timed{_, b}: F.isAtLeast(F.compare(a, b))

def matchesCwd(cwd: Maybe<&2, String>, header: S.SessionHeader) -> Bool:
  match cwd:
    case None{}: True{}
    case Some{resolved}: sessionCwdMatches(headerCwd(header), resolved)

def withTime(timed: Maybe<&2, List<&2, Timed>>, path: String, modified: Result<&2, &2, FS.Error, F64>) -> Maybe<&2, List<&2, Timed>>:
  match timed modified:
    case Some{values} Done{time}: Some{Timed{path, time} <> values}
    case _ _: None{}

# Every candidate is stat'ed first (Stats.mtimeMs); a failed stat makes
# discovery unavailable, as a directory access race does upstream.
def timedFiles(files: List<&2, String>, timed: Maybe<&2, List<&2, Timed>>) -> IO(Maybe<&2, List<&2, Timed>>):
  match files:
    case Nil{}: IO.pure(Maybe<&2, List<&2, Timed>>, Maybe.map(&2, List<&2, Timed>, List<&2, Timed>, values => List.reverse(&2, Timed, values), timed))
    case +path <> rest:
      do IO<Maybe<&2, List<&2, Timed>>>:
        modified : Result<&2, &2, FS.Error, F64> <- FS.modifiedExact(path)
        timedFiles(rest, withTime(timed, path, modified))

# Newest first, the first file whose header belongs to the working directory.
def firstMatching(files: List<&2, Timed>, +cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match files:
    case Nil{}: IO.pure(Maybe<&2, String>, None{})
    case Timed{+path, _} <> rest:
      do IO<Maybe<&2, String>>:
        header : Maybe<&2, S.SessionHeader> <- readSessionHeaderForDiscovery(path)
        Bool.pick(Unit -> IO(Maybe<&2, String>), Maybe.default(&2, Bool, Maybe.map(&2, S.SessionHeader, Bool, found => matchesCwd(cwd, found), header), False{}), _ => IO.pure(Maybe<&2, String>, Some{path}), _ => firstMatching(rest, cwd))(Unit{})

def newestMatching(timed: Maybe<&2, List<&2, Timed>>, cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match timed:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{files}: firstMatching(Sort.sort(~Timed, ~newerFirst, files), cwd)

def mostRecent(files: Maybe<&2, List<&2, String>>, cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match files:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{paths}:
      do IO<Maybe<&2, String>>:
        timed : Maybe<&2, List<&2, Timed>> <- timedFiles(paths, Some{Nil{}})
        newestMatching(timed, cwd)

# The most recently modified session file in a directory, optionally only
# sessions of one working directory; None when the directory is unavailable.
def findMostRecentSession(dir: String, cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    files : Maybe<&2, List<&2, String>> <- sessionFiles(Path.normalize(dir))
    mostRecent(files, cwd)

def matchingHeader(+found: S.SessionHeader, id: String, cwd: Maybe<&2, String>) -> Bool:
  String.eq(headerId(found), id) && matchesCwd(cwd, found)

def identified(header: Maybe<&2, S.SessionHeader>, id: String, cwd: Maybe<&2, String>) -> Bool:
  Maybe.default(&2, Bool, Maybe.map(&2, S.SessionHeader, Bool, found => matchingHeader(found, id, cwd), header), False{})

def matchingId(files: List<&2, String>, +id: String, +cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match files:
    case Nil{}: IO.pure(Maybe<&2, String>, None{})
    case +path <> rest:
      do IO<Maybe<&2, String>>:
        header : Maybe<&2, S.SessionHeader> <- readSessionHeaderForDiscovery(path)
        Bool.pick(Unit -> IO(Maybe<&2, String>), identified(header, id, cwd), _ => IO.pure(Maybe<&2, String>, Some{path}), _ => matchingId(rest, id, cwd))(Unit{})

def foundById(files: Maybe<&2, List<&2, String>>, id: String, cwd: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match files:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{paths}: matchingId(paths, id, cwd)

# An exact session id, found without loading transcript bodies.
def findIn(chosen: Outcome(String), +cwd: String, id: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Maybe<&2, String>):
  match chosen:
    case Fail{_}: IO.pure(Maybe<&2, String>, None{})
    case Done{+dir}:
      do IO<Maybe<&2, String>>:
        files : Maybe<&2, List<&2, String>> <- sessionFiles(dir)
        foundById(files, id, Bool.pick(Maybe<&2, String>, filtersCwd(sessionDir, dir, cwd, agentDir), Some{cwd}, None{}))

def findById(+cwd: String, id: String, +sessionDir: Maybe<&2, String>, +agentDir: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    chosen : Outcome(String) <- chosenDir(sessionDir, cwd, agentDir)
    findIn(chosen, cwd, id, sessionDir, agentDir)

# Session info
# ------------
# A listing reads each file's raw JSON lines: the header, the latest name,
# the message count, the first user text and the latest user/assistant
# activity time. No typed decoding is needed for this summary.

type Summary is Data:
  Summary{header: Maybe<&2, S.SessionHeader>, invalid: Bool, count: Nat, first: String, texts: List<&2, String>, name: Maybe<&2, String>, activity: Maybe<&2, F64>}

def emptySummary() -> Summary: Summary{None{}, False{}, 0n, "", Nil{}, None{}, None{}}

def textBlock(isText: Bool, fields: R.Record<V.Value>, +reversed: List<&2, String>) -> List<&2, String>:
  match isText:
    case True{}: SJ.textField(R.get(V.Value, fields, "text")) <> reversed
    case False{}: reversed

def blockTexts(values: List<&2, V.Value>, +reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, reversed)
    case V.ObjectValue{+fields} <> rest: blockTexts(rest, textBlock(String.eq(SJ.textField(R.get(V.Value, fields, "type")), "text"), fields, reversed))
    case _ <> rest: blockTexts(rest, reversed)

def extractTextContent(content: Maybe<&2, V.Value>) -> String:
  match content:
    case Some{V.Text{text}}: text
    case Some{V.ArrayValue{values}}: String.join(blockTexts(values, Nil{}), " ")
    case _: ""

def conversational(+role: String) -> Bool: String.eq(role, "user") || String.eq(role, "assistant")

def parsedTime(timestamp: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match timestamp:
    case Some{V.Text{text}}: SJ.maybeOf(Date.ParseError, F64, Date.parseIso(text))
    case _: None{}

def numberOrParsed(found: Maybe<&2, V.Value>, entryTimestamp: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match found:
    case Some{V.Number{scalar}}: Some{scalar}
    case _: parsedTime(entryTimestamp)

def activityTime(message: R.Record<V.Value>, entryTimestamp: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  numberOrParsed(R.get(V.Value, message, "timestamp"), entryTimestamp)

def later(+current: Maybe<&2, F64>, found: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match current found:
    case _ None{}: current
    case None{} Some{time}: Some{F.maximum(U32.to_f64(0), time)}
    case Some{previous} Some{time}: Some{F.maximum(previous, time)}

def firstUser(+first: String, role: String, text: String) -> String:
  Bool.pick(String, String.is_empty(first) && String.eq(role, "user"), text, first)

def summarizeMessage(summary: Summary, +message: R.Record<V.Value>, entryTimestamp: Maybe<&2, V.Value>) -> Summary:
  match summary:
    case Summary{header, invalid, count, +first, +texts, name, +activity}:
      +role = SJ.textField(R.get(V.Value, message, "role"))
      +text = extractTextContent(R.get(V.Value, message, "content"))
      +spoken = conversational(role)
      +kept = spoken && Bool.not(String.is_empty(text))
      Summary{header, invalid, 1n + count, Bool.pick(String, kept, firstUser(first, role, text), first), Bool.pick(List<&2, String>, kept, text <> texts, texts), name, Bool.pick(Maybe<&2, F64>, spoken, later(activity, activityTime(message, entryTimestamp)), activity)}

def summarizeMessageValue(+summary: Summary, found: Maybe<&2, V.Value>, entryTimestamp: Maybe<&2, V.Value>) -> Summary:
  match found:
    case Some{V.ObjectValue{body}}: summarizeMessage(summary, body, entryTimestamp)
    case _: summary

def summarizeEntry(summary: Summary, kind: String, +fields: R.Record<V.Value>) -> Summary:
  match summary kind:
    case Summary{header, invalid, count, first, texts, _, activity} "session_info":
      +named = String.trim(SJ.textField(R.get(V.Value, fields, "name")))
      Summary{header, invalid, count, first, texts, Bool.pick(Maybe<&2, String>, String.is_empty(named), None{}, Some{named}), activity}
    case current "message": summarizeMessageValue(current, R.get(V.Value, fields, "message"), R.get(V.Value, fields, "timestamp"))
    case current _: current

def summarizeHeader(summary: Summary, isSession: Bool, fields: R.Record<V.Value>) -> Summary:
  match summary isSession:
    case Summary{_, _, count, first, texts, name, activity} False{}: Summary{None{}, True{}, count, first, texts, name, activity}
    case Summary{_, _, count, first, texts, name, activity} True{}: Summary{SJ.maybeOf(Decode.Error, S.SessionHeader, SJ.headerFields(fields)), False{}, count, first, texts, name, activity}

def summarizeValue(summary: Summary, value: V.Value) -> Summary:
  match summary value:
    case Summary{None{}, False{}, count, first, texts, name, activity} V.ObjectValue{+fields}: summarizeHeader(Summary{None{}, False{}, count, first, texts, name, activity}, String.eq(SJ.textField(R.get(V.Value, fields, "type")), "session"), fields)
    case Summary{Some{header}, invalid, count, first, texts, name, activity} V.ObjectValue{+fields}: summarizeEntry(Summary{Some{header}, invalid, count, first, texts, name, activity}, SJ.textField(R.get(V.Value, fields, "type")), fields)
    case other _: other

def summarize(values: List<&2, V.Value>, summary: Summary) -> Summary:
  match values summary:
    case _ Summary{None{}, True{}, count, first, texts, name, activity}: Summary{None{}, True{}, count, first, texts, name, activity}
    case Nil{} done: done
    case value <> rest current: summarize(rest, summarizeValue(current, value))

def positive(time: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match time:
    case Some{+value}: Bool.pick(Maybe<&2, F64>, F.isGreater(F.compare(value, U32.to_f64(0))), Some{value}, None{})
    case None{}: None{}

def modifiedTime(activity: Maybe<&2, F64>, created: Maybe<&2, F64>, mtime: F64) -> F64:
  Maybe.default(&2, F64, Maybe.or(&2, F64, positive(activity), created), mtime)

def infoOf(path: String, summary: Summary, mtime: F64) -> Maybe<&2, S.SessionInfo>:
  match summary:
    case Summary{Some{S.SessionHeader{_, id, timestamp, cwd, parentSession}}, _, count, +first, texts, name, activity}:
      +created = SJ.maybeOf(Date.ParseError, F64, Date.parseIso(timestamp))
      Some{S.SessionInfo{path, id, cwd, name, parentSession, Maybe.default(&2, F64, created, F.nan()), modifiedTime(activity, created, mtime), count, Bool.pick(String, String.is_empty(first), "(no messages)", first), String.join(List.reverse(&2, String, texts), " ")}}
    case _: None{}

# Session metadata is a fold over JSONL records. A long session should not
# materialize its entire file, its lines, and all parsed values just to draw a
# row in the picker.
type InfoScan is Data: InfoScan{pending: List<&2, U32>, summary: Summary}
def summarizedValue(value: Maybe<&2, V.Value>, summary: Summary) -> Summary:
  match value:
    case None{}: summary
    case Some{value}: summarizeValue(summary, value)
def summarizedLine(pending: List<&2, U32>, summary: Summary) -> Summary:
  summarizedValue(parsedBytes(List.reverse(&2, U32, pending)), summary)
def scannedBytes(bytes: List<&2, U32>, scan: InfoScan) -> InfoScan:
  match bytes scan:
    case Nil{} current: current
    case 10 <> rest InfoScan{pending, summary}: scannedBytes(rest, InfoScan{Nil{}, summarizedLine(pending, summary)})
    case byte <> rest InfoScan{pending, summary}: scannedBytes(rest, InfoScan{byte <> pending, summary})
def consumeInfo(scan: InfoScan, bytes: List<&2, U32>) -> Fold.Control<InfoScan>:
  Fold.Continue{scannedBytes(bytes, scan)}
def scannedInfo(path: String, outcome: Fold.Outcome<InfoScan>, modified: Result<&2, &2, FS.Error, F64>) -> Maybe<&2, S.SessionInfo>:
  match outcome modified:
    case Fold.Outcome{InfoScan{pending, summary}, Done{_}} Done{mtime}: infoOf(path, summarizedLine(pending, summary), mtime)
    case _ _: None{}

def buildSessionInfo(+path: String) -> IO(Maybe<&2, S.SessionInfo>):
  do IO<Maybe<&2, S.SessionInfo>>:
    modified : Result<&2, &2, FS.Error, F64> <- FS.modified(path)
    scan : Fold.Outcome<InfoScan> <- Fold.read(~InfoScan, ~consumeInfo, path, 4096, InfoScan{Nil{}, emptySummary()})
    return scannedInfo(path, scan, modified)

# A candidate stat'ed during discovery (its Stats.mtimeMs) is not stat'ed again.
def buildSessionInfoWith(+path: String, known: Maybe<&2, F64>) -> IO(Maybe<&2, S.SessionInfo>):
  match known:
    case None{}: buildSessionInfo(path)
    case Some{exact}:
      do IO<Maybe<&2, S.SessionInfo>>:
        scan : Fold.Outcome<InfoScan> <- Fold.read(~InfoScan, ~consumeInfo, path, 4096, InfoScan{Nil{}, emptySummary()})
        return scannedInfo(path, scan, Done{FS.roundedMilliseconds(exact)})

def infoModified(info: S.SessionInfo) -> F64:
  match info:
    case S.SessionInfo{_, _, _, _, _, _, modified, _, _, _}: modified

def infoCwd(info: S.SessionInfo) -> String:
  match info:
    case S.SessionInfo{_, _, cwd, _, _, _, _, _, _, _}: cwd

def recentFirst(left: S.SessionInfo, right: S.SessionInfo) -> Bool:
  F.isAtLeast(F.compare(infoModified(left), infoModified(right)))

# upstream sortSessionInfos: most recently modified first; ties keep their order.
def sortSessionInfos(sessions: List<&2, S.SessionInfo>) -> List<&2, S.SessionInfo>:
  Sort.sort(~S.SessionInfo, ~recentFirst, sessions)

def isDirectoryLike(kind: FS.FileKind) -> Bool:
  match kind:
    case FS.Directory{}: True{}
    case FS.SymbolicLink{}: True{}
    case _: False{}

def projectDirs(+parent: String, entries: List<&2, FS.DirectoryEntry>, +reversed: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}: List.reverse(&2, String, reversed)
    case FS.DirectoryEntry{name, kind} <> rest: projectDirs(parent, rest, Bool.pick(List<&2, String>, isDirectoryLike(kind), Path.join(parent, name) <> reversed, reversed))

# File order
# ----------
# upstream orders session file names with localeCompare. With a collator
# (loadFileOrder: the installed ICU root data) names compare as Node's default
# collation does; without one they compare by code points, as the ls tool
# falls back.
def FileOrder() -> Data: Maybe<&2, Collation.Collator>

def loadedOrder(loaded: Result<&2, &2, Collation.LoadError, Collation.Collator>) -> FileOrder():
  match loaded:
    case Done{collator}: Some{collator}
    case Fail{_}: None{}

def loadFileOrder(packageDir: String) -> IO(FileOrder()):
  do IO<FileOrder()>:
    loaded : Result<&2, &2, Collation.LoadError, Collation.Collator> <- Collation.load(Path.join(packageDir, "packages/runtime/data"))
    return loadedOrder(loaded)

# A session file found by discovery: its path, the collation key of its name
# and, once stat'ed, its Stats.mtimeMs.
type Candidate is Data:
  Candidate{path: String, key: Maybe<&2, Collation.Key>, modified: Maybe<&2, F64>}

def candidateOf(+order: FileOrder(), +path: String, modified: Maybe<&2, F64>) -> Candidate:
  Candidate{path, Maybe.map(&2, Collation.Collator, Collation.Key, collator => Collation.key(collator, Path.basename(path)), order), modified}

def nameOrder(left: String, leftKey: Maybe<&2, Collation.Key>, right: String, rightKey: Maybe<&2, Collation.Key>) -> Cmp:
  match leftKey rightKey:
    case Some{a} Some{b}: Collation.compareKeys(a, b)
    case _ _: String.order(Path.basename(left), Path.basename(right))

# `b.localeCompare(a)`: later names first; equal names keep their order.
def laterName(left: Candidate, right: Candidate) -> Bool:
  match left right:
    case Candidate{a, ka, _} Candidate{b, kb, _}: Bool.not(Cmp.is_lt(nameOrder(a, ka, b, kb)))

# A missing time is -Infinity; two of them subtract to NaN, which falls
# through to the name as an equal time does.
def timeOrder(left: Maybe<&2, F64>, right: Maybe<&2, F64>) -> Maybe<&2, Cmp>:
  match left right:
    case Some{a} Some{b}: F.compare(a, b)
    case Some{_} None{}: Some{GT{}}
    case None{} Some{_}: Some{LT{}}
    case None{} None{}: None{}

def byTime(order: Maybe<&2, Cmp>, byName: Bool) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case Some{LT{}}: False{}
    case _: byName

# listAll's candidate order: newest mtimeMs first, then later names first.
def newerCandidate(left: Candidate, right: Candidate) -> Bool:
  match left right:
    case Candidate{a, ka, ma} Candidate{b, kb, mb}: byTime(timeOrder(ma, mb), Bool.not(Cmp.is_lt(nameOrder(a, ka, b, kb))))

def namedCandidates(+order: FileOrder(), paths: List<&2, String>) -> List<&2, Candidate>:
  match paths:
    case Nil{}: Nil{}
    case path <> rest: candidateOf(order, path, None{}) <> namedCandidates(order, rest)

# Listing
# -------
# upstream list and listAll take an optional progress callback and abort
# signal. Progress reports every loaded file; the first, every interval-th
# and the last also carry the sessions loaded so far, sorted. An aborted
# listing fails with the signal's reason (upstream rejects with it).
# Cancellation is checked before each directory, stat and file, one after
# another; upstream runs up to 64 discoveries and ten reads concurrently and
# also stops a read in progress.
type ListProgress is Data: ListProgress{loaded: Nat, total: Nat, sessions: Maybe<&2, List<&2, S.SessionInfo>>}
type Observer is Data: Observer{signal: Maybe<&2, Abort.AbortSignal<Unit>>, publish: Maybe<&2, Callback.Callback<ListProgress, Unit>>}
def Listing() -> Data: Result<&2, &2, Abort.AbortReason<Unit>, List<&2, S.SessionInfo>>
def Checked() -> Data: Result<&2, &2, Abort.AbortReason<Unit>, Unit>

def unobserved() -> Observer: Observer{None{}, None{}}

def signalOf(observer: Observer) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match observer:
    case Observer{signal, _}: signal

def checkAborted(signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Checked()):
  match signal:
    case None{}: IO.pure(Checked(), Done{Unit{}})
    case Some{value}: Abort.throwIfAborted(Unit, value)

# Continue unless the check found the signal aborted.
def unlessAborted(-A: Data, check: Checked(), next: Unit -> IO(Result<&2, &2, Abort.AbortReason<Unit>, A>)) -> IO(Result<&2, &2, Abort.AbortReason<Unit>, A>):
  match check:
    case Fail{reason}: IO.pure(Result<&2, &2, Abort.AbortReason<Unit>, A>, Fail{reason})
    case Done{_}: next(Unit{})

def selectedIf(include: Bool, value: S.SessionInfo, found: List<&2, S.SessionInfo>) -> List<&2, S.SessionInfo>:
  match include:
    case True{}: value <> found
    case False{}: found

def selectedInfo(info: Maybe<&2, S.SessionInfo>, cwd: Maybe<&2, String>, found: List<&2, S.SessionInfo>) -> List<&2, S.SessionInfo>:
  match info:
    case None{}: found
    case Some{+value}:
      selectedIf(Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, expected => sessionCwdMatches(infoCwd(value), expected), cwd), True{}), value, found)

# `found` holds the loaded sessions newest-loaded first.
def partialSnapshot(publish: Bool, found: List<&2, S.SessionInfo>) -> Maybe<&2, List<&2, S.SessionInfo>>:
  match publish:
    case True{}: Some{sortSessionInfos(List.reverse(&2, S.SessionInfo, found))}
    case False{}: None{}

def report(observer: Observer, +loaded: Nat, +total: Nat, +interval: Nat, found: List<&2, S.SessionInfo>) -> IO(Unit):
  match observer:
    case Observer{_, None{}}: IO.pure(Unit, Unit{})
    case Observer{_, Some{publish}}: Callback.call(ListProgress, Unit, publish, ListProgress{loaded, total, partialSnapshot(Nat.is_eq(loaded, 1n) || Nat.is_eq(loaded, total) || Nat.is_eq(loaded % interval, 0n), found)})

def loadInfos(candidates: List<&2, Candidate>, +loaded: Nat, +total: Nat, +interval: Nat, +cwd: Maybe<&2, String>, +observer: Observer, found: List<&2, S.SessionInfo>) -> IO(Listing()):
  match candidates:
    case Nil{}: IO.pure(Listing(), Done{sortSessionInfos(List.reverse(&2, S.SessionInfo, found))})
    case Candidate{+path, _, modified} <> rest:
      do IO<Listing()>:
        check : Checked() <- checkAborted(signalOf(observer))
        unlessAborted(List<&2, S.SessionInfo>, check, _ => do IO<Listing()>:
          info : Maybe<&2, S.SessionInfo> <- buildSessionInfoWith(path, modified)
          +next : List<&2, S.SessionInfo> <- IO.pure(List<&2, S.SessionInfo>, selectedInfo(info, cwd, found))
          report(observer, loaded + 1n, total, interval, next)
          loadInfos(rest, loaded + 1n, total, interval, cwd, observer, next))

def loadCandidates(+candidates: List<&2, Candidate>, interval: Nat, cwd: Maybe<&2, String>, observer: Observer) -> IO(Listing()):
  loadInfos(candidates, 0n, List.length(&2, Candidate, candidates), interval, cwd, observer, Nil{})

def loadDirectory(files: Maybe<&2, List<&2, String>>, +order: FileOrder(), cwd: Maybe<&2, String>, observer: Observer) -> IO(Listing()):
  match files:
    case None{}: IO.pure(Listing(), Done{Nil{}})
    case Some{paths}: loadCandidates(Sort.sort(~Candidate, ~laterName, namedCandidates(order, paths)), 10n, cwd, observer)

def directoryListing(check: Checked(), +dir: String, order: FileOrder(), cwd: Maybe<&2, String>, observer: Observer) -> IO(Listing()):
  match check:
    case Fail{reason}: IO.pure(Listing(), Fail{reason})
    case Done{_}:
      do IO<Listing()>:
        files : Maybe<&2, List<&2, String>> <- sessionFiles(dir)
        loadDirectory(files, order, cwd, observer)

# upstream listSessionsFromDir: file names in reverse collation order, only
# sessions of `cwd` when given.
def listSessionsFromDir(+dir: String, order: FileOrder(), cwd: Maybe<&2, String>, +observer: Observer) -> IO(Listing()):
  do IO<Listing()>:
    check : Checked() <- checkAborted(signalOf(observer))
    directoryListing(check, dir, order, cwd, observer)

def listIn(chosen: Outcome(String), +sessionDir: Maybe<&2, String>, +cwd: String, agentDir: String, order: FileOrder(), observer: Observer) -> IO(Listing()):
  match chosen:
    case Fail{_}: IO.pure(Listing(), Done{Nil{}})
    case Done{+dir}: listSessionsFromDir(dir, order, Bool.pick(Maybe<&2, String>, filtersCwd(sessionDir, dir, cwd, agentDir), Some{cwd}, None{}), observer)

# upstream SessionManager.list: the sessions of a working directory, most
# recently modified first.
def listObserved(+cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, order: FileOrder(), observer: Observer) -> IO(Listing()):
  do IO<Listing()>:
    chosen : Outcome(String) <- chosenDir(sessionDir, cwd, agentDir)
    listIn(chosen, sessionDir, cwd, agentDir, order, observer)

def unaborted(listing: Listing()) -> List<&2, S.SessionInfo>:
  Result.default(&2, &2, Abort.AbortReason<Unit>, List<&2, S.SessionInfo>, listing, Nil{})

def list(+cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, order: FileOrder()) -> IO(List<&2, S.SessionInfo>):
  do IO<List<&2, S.SessionInfo>>:
    listing : Listing() <- listObserved(cwd, sessionDir, agentDir, order, unobserved())
    return unaborted(listing)

def listProgress(+cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, order: FileOrder(), signal: Abort.AbortSignal<Unit>, publish: Callback.Callback<ListProgress, Unit>) -> IO(Listing()):
  listObserved(cwd, sessionDir, agentDir, order, Observer{Some{signal}, Some{publish}})

# The session files of each project directory; an unreadable one has none.
def pathsInDirs(dirs: List<&2, String>, +signal: Maybe<&2, Abort.AbortSignal<Unit>>, reversed: List<&2, String>) -> IO(Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>>):
  match dirs:
    case Nil{}: IO.pure(Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>>, Done{List.reverse(&2, String, reversed)})
    case +dir <> rest:
      do IO<Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>>>:
        check : Checked() <- checkAborted(signal)
        unlessAborted(List<&2, String>, check, _ => do IO<Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>>>:
          files : Maybe<&2, List<&2, String>> <- sessionFiles(dir)
          pathsInDirs(rest, signal, List.append(&2, String, List.reverse(&2, String, Maybe.default(&2, List<&2, String>, files, Nil{})), reversed)))

def statedTime(modified: Result<&2, &2, FS.Error, F64>) -> Maybe<&2, F64>:
  match modified:
    case Done{time}: Some{time}
    case Fail{_}: None{}

# Every file is stat'ed first; a failed stat leaves the candidate without a time.
def statCandidates(paths: List<&2, String>, +order: FileOrder(), +signal: Maybe<&2, Abort.AbortSignal<Unit>>, reversed: List<&2, Candidate>) -> IO(Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>>):
  match paths:
    case Nil{}: IO.pure(Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>>, Done{List.reverse(&2, Candidate, reversed)})
    case +path <> rest:
      do IO<Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>>>:
        check : Checked() <- checkAborted(signal)
        unlessAborted(List<&2, Candidate>, check, _ => do IO<Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>>>:
          modified : Result<&2, &2, FS.Error, F64> <- FS.modifiedExact(path)
          statCandidates(rest, order, signal, candidateOf(order, path, statedTime(modified)) <> reversed))

def loadStated(stated: Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>>, observer: Observer) -> IO(Listing()):
  match stated:
    case Fail{reason}: IO.pure(Listing(), Fail{reason})
    case Done{candidates}: loadCandidates(Sort.sort(~Candidate, ~newerCandidate, candidates), 100n, None{}, observer)

def statFound(found: Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>>, order: FileOrder(), +observer: Observer) -> IO(Listing()):
  match found:
    case Fail{reason}: IO.pure(Listing(), Fail{reason})
    case Done{paths}:
      do IO<Listing()>:
        stated : Result<&2, &2, Abort.AbortReason<Unit>, List<&2, Candidate>> <- statCandidates(paths, order, signalOf(observer), Nil{})
        loadStated(stated, observer)

def listedProjects(sessionsDir: String, result: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>, order: FileOrder(), +observer: Observer) -> IO(Listing()):
  match result:
    case Fail{_}: IO.pure(Listing(), Done{Nil{}})
    case Done{entries}:
      do IO<Listing()>:
        found : Result<&2, &2, Abort.AbortReason<Unit>, List<&2, String>> <- pathsInDirs(projectDirs(sessionsDir, entries, Nil{}), signalOf(observer), Nil{})
        statFound(found, order, observer)

def allListing(check: Checked(), sessionDir: Maybe<&2, String>, +sessionsDir: String, order: FileOrder(), observer: Observer) -> IO(Listing()):
  match check sessionDir:
    case Fail{reason} _: IO.pure(Listing(), Fail{reason})
    case Done{_} Some{custom}: listSessionsFromDir(Path.normalize(custom), order, None{}, observer)
    case Done{_} None{}:
      do IO<Listing()>:
        result : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(sessionsDir)
        listedProjects(sessionsDir, result, order, observer)

# upstream SessionManager.listAll: all sessions across project directories
# (or of one custom directory), most recently modified first. Project
# sessions load newest file first, so the first rows are the recent ones.
def listAllObserved(sessionDir: Maybe<&2, String>, +sessionsDir: String, order: FileOrder(), +observer: Observer) -> IO(Listing()):
  do IO<Listing()>:
    check : Checked() <- checkAborted(signalOf(observer))
    allListing(check, sessionDir, sessionsDir, order, observer)

def listAll(sessionDir: Maybe<&2, String>, +sessionsDir: String, order: FileOrder()) -> IO(List<&2, S.SessionInfo>):
  do IO<List<&2, S.SessionInfo>>:
    listing : Listing() <- listAllObserved(sessionDir, sessionsDir, order, unobserved())
    return unaborted(listing)

def listAllProgress(sessionDir: Maybe<&2, String>, sessionsDir: String, order: FileOrder(), signal: Abort.AbortSignal<Unit>, publish: Callback.Callback<ListProgress, Unit>) -> IO(Listing()):
  listAllObserved(sessionDir, sessionsDir, order, Observer{Some{signal}, Some{publish}})

# The session
# -----------

type Session<-D: Data, -T: Data, -C: Data> is Data:
  Session{state: S.SessionManager<D, T, C>, cwd: String, sessionDir: String, sessionFile: Maybe<&2, String>, persist: Bool, flushed: Bool, idGenerator: Uuid.Generator}

def stateOf(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> S.SessionManager<D, T, C>:
  match session:
    case Session{state, _, _, _, _, _, _}: state

def getSessionFile(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> Maybe<&2, String>:
  match session:
    case Session{_, _, _, file, _, _, _}: file

# The process UUIDv7 generator new session ids come from.
def getIdGenerator(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> Uuid.Generator:
  match session:
    case Session{_, _, _, _, _, _, ids}: ids

def getSessionDir(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> String:
  match session:
    case Session{_, _, dir, _, _, _, _}: dir

def isPersisted(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> Bool:
  match session:
    case Session{_, _, _, _, persist, _, _}: persist

def isFlushed(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> Bool:
  match session:
    case Session{_, _, _, _, _, flushed, _}: flushed

# The effective working directory: an opened session may override its header's.
def getCwd(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> String:
  match session:
    case Session{_, place, _, _, _, _, _}: place

def getSessionId(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> String:
  S.getSessionId(D, T, C, stateOf(D, T, C, session))

def usesDefaultSessionDir(-D: Data, -T: Data, -C: Data, +session: Session<D, T, C>, agentDir: String) -> Bool:
  String.eq(getSessionDir(D, T, C, session), getDefaultSessionDirPath(getCwd(D, T, C, session), agentDir))

def stateError(-A: Data, result: Result<&2, &2, S.Error, A>) -> Outcome(A):
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{State{cause}}

# Replace the state through a pure transition (branch, resetLeaf).
def modify(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, transition: S.SessionManager<D, T, C> -> Result<&2, &2, S.Error, S.SessionManager<D, T, C>>) -> Outcome(Session<D, T, C>):
  match session:
    case Session{state, place, dir, file, persist, flushed, ids}: Result.map(&2, &2, Error, S.SessionManager<D, T, C>, Session<D, T, C>, next => Session{next, place, dir, file, persist, flushed, ids}, stateError(S.SessionManager<D, T, C>, transition(state)))

# Writing
# -------

def entryLines(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, entries: List<&2, S.SessionEntry<D, T, C>>, +reversed: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}: List.reverse(&2, String, reversed)
    case entry <> rest: entryLines(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, rest, SJ.entryLine(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, S.Entry{entry}) <> reversed)

def fileContent(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +state: S.SessionManager<D, T, C>) -> String:
  SJ.entryLine(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, S.Header{S.getHeader(D, T, C, state)}) ++ String.join(entryLines(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, S.getEntries(D, T, C, state), Nil{}), "")

def branchLines(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, entries: List<&2,S.SessionEntry<D,T,C>>, parent: Maybe<&2,String>, +reversed: List<&2,String>) -> List<&2,String>:
  match entries:
    case Nil{}: List.reverse(&2,String,reversed)
    case entry <> rest:
      +linked = S.reparent(D,T,C,entry,parent,Map.new(&2,Maybe<&2,String>))
      +line = SJ.entryLine(~D,~T,~C,~diagnostic,~tool,~custom,S.Entry{linked})
      branchLines(~D,~T,~C,~diagnostic,~tool,~custom,rest,Some{S.entryId(D,T,C,linked)},line <> reversed)
def branchContentFrom(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +state: S.SessionManager<D,T,C>, +timestamp: String, result: Result<&2,&2,S.Error,List<&2,S.SessionEntry<D,T,C>>>) -> Outcome(String):
  match result:
    case Fail{error}: Fail{State{error}}
    case Done{entries}:
      +header = {S.SessionHeader{Some{S.CURRENT_SESSION_VERSION()},S.getSessionId(D,T,C,state),timestamp,S.getCwd(D,T,C,state),None{}} : S.SessionHeader}
      Done{SJ.entryLine(~D,~T,~C,~diagnostic,~tool,~custom,S.Header{header}) ++ String.join(branchLines(~D,~T,~C,~diagnostic,~tool,~custom,entries,None{},Nil{}),"")}
def branchContent(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +state: S.SessionManager<D,T,C>, timestamp: String) -> Outcome(String):
  branchContentFrom(~D,~T,~C,~diagnostic,~tool,~custom,state,timestamp,S.getBranch(D,T,C,state,S.Latest{}))

def writeOutcome(path: String, result: Result<&2, &2, FS.Error, Unit>) -> Outcome(Unit):
  fileError(Unit, path, result)

# Rewrite the whole file (migration, an initialized empty file, a persisted fork).
def rewriteFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>) -> IO(Outcome(Unit)):
  match session:
    case Session{_, _, _, None{}, _, _, _}: IO.pure(Outcome(Unit), Done{Unit{}})
    case Session{_, _, _, Some{_}, False{}, _, _}: IO.pure(Outcome(Unit), Done{Unit{}})
    case Session{state, _, _, Some{+path}, True{}, _, _}:
      do IO<Outcome(Unit)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, fileContent(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, state))
        return writeOutcome(path, result)

def isAssistant(-D: Data, -T: Data, -C: Data, entry: S.SessionEntry<D, T, C>) -> Bool:
  match entry:
    case S.SessionMessageEntry{_, Agent.LlmMessage{Ai.Assistant{_}}}: True{}
    case _: False{}

def hasAssistant(-D: Data, -T: Data, -C: Data, entries: List<&2, S.SessionEntry<D, T, C>>) -> Bool:
  match entries:
    case Nil{}: False{}
    case entry <> rest: isAssistant(D, T, C, entry) || hasAssistant(D, T, C, rest)

def appendLine(+path: String, content: String) -> IO(Outcome(Unit)):
  do IO<Outcome(Unit)>:
    result : Result<&2, &2, FS.Error, Unit> <- FS.appendFile(path, content)
    return writeOutcome(path, result)

def flushedSession(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, flushed: Bool) -> Session<D, T, C>:
  match session:
    case Session{state, place, dir, file, persist, _, ids}: Session{state, place, dir, file, persist, flushed, ids}

def afterWrite(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, flushed: Bool, result: Outcome(Unit)) -> Outcome(Session<D, T, C>):
  Result.map(&2, &2, Error, Unit, Session<D, T, C>, _ => flushedSession(D, T, C, session, flushed), result)

# Create the file with every entry once the first assistant message exists.
def flushAll(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, +path: String) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    result : Result<&2, &2, FS.Error, Unit> <- FS.writeFileExclusive(path, fileContent(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, stateOf(D, T, C, session)))
    return afterWrite(D, T, C, session, True{}, writeOutcome(path, result))

def persistWith(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, +path: String, flushed: Bool, assistant: Bool, entry: S.SessionEntry<D, T, C>) -> IO(Outcome(Session<D, T, C>)):
  match flushed assistant:
    case True{} _:
      do IO<Outcome(Session<D, T, C>)>:
        result : Outcome(Unit) <- appendLine(path, SJ.entryLine(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, S.Entry{entry}))
        return afterWrite(D, T, C, session, True{}, result)
    case False{} False{}: IO.pure(Outcome(Session<D, T, C>), Done{flushedSession(D, T, C, session, False{})})
    case False{} True{}: flushAll(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, path)

# Upstream's _persist: nothing is written before the first assistant message
# (a session of only user prompts leaves no file); the first assistant
# message flushes every entry, later entries append.
def persistEntry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, entry: S.SessionEntry<D, T, C>) -> IO(Outcome(Session<D, T, C>)):
  match session:
    case Session{state, place, dir, None{}, persist, flushed, ids}: IO.pure(Outcome(Session<D, T, C>), Done{Session{state, place, dir, None{}, persist, flushed, ids}})
    case Session{state, place, dir, Some{path}, False{}, flushed, ids}: IO.pure(Outcome(Session<D, T, C>), Done{Session{state, place, dir, Some{path}, False{}, flushed, ids}})
    case Session{+state, place, dir, Some{+path}, True{}, +flushed, ids}:
      persistWith(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, Session{state, place, dir, Some{path}, True{}, flushed, ids}, path, flushed, hasAssistant(D, T, C, S.getEntries(D, T, C, state)), entry)

# Appending
# ---------

type Appended<-D: Data, -T: Data, -C: Data> is Data:
  Appended{session: Session<D, T, C>, id: String}

def appendedEntry(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>) -> Outcome(S.SessionEntry<D, T, C>):
  Maybe.default(&2, Outcome(S.SessionEntry<D, T, C>), Maybe.map(&2, S.SessionEntry<D, T, C>, Outcome(S.SessionEntry<D, T, C>), entry => Done{entry}, S.getLeafEntry(D, T, C, state)), Fail{State{S.EntryNotFound{"leaf"}}})

def persistLeaf(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, id: String, leaf: Outcome(S.SessionEntry<D, T, C>)) -> IO(Outcome(Appended<D, T, C>)):
  match leaf:
    case Fail{error}: IO.pure(Outcome(Appended<D, T, C>), Fail{error})
    case Done{entry}:
      do IO<Outcome(Appended<D, T, C>)>:
        written : Outcome(Session<D, T, C>) <- persistEntry(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, entry)
        return Result.map(&2, &2, Error, Session<D, T, C>, Appended<D, T, C>, stored => Appended{stored, id}, written)

def persistAppended(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, id: String, next: Outcome(S.SessionManager<D, T, C>)) -> IO(Outcome(Appended<D, T, C>)):
  match session next:
    case _ Fail{error}: IO.pure(Outcome(Appended<D, T, C>), Fail{error})
    case Session{_, place, dir, file, persist, flushed, ids} Done{+state}: persistLeaf(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, Session{state, place, dir, file, persist, flushed, ids}, id, appendedEntry(D, T, C, state))

def appendStamped(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, stamp: Outcome(S.EntryStamp), append: S.EntryStamp -> Result<&2, &2, S.Error, S.SessionManager<D, T, C>>) -> IO(Outcome(Appended<D, T, C>)):
  match stamp:
    case Fail{error}: IO.pure(Outcome(Appended<D, T, C>), Fail{error})
    case Done{S.EntryStamp{+id, time}}: persistAppended(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, id, stateError(S.SessionManager<D, T, C>, append(S.EntryStamp{id, time})))

# Every append: a fresh id and timestamp, the pure transition, then persistence.
def append(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, transition: S.EntryStamp -> Result<&2, &2, S.Error, S.SessionManager<D, T, C>>) -> IO(Outcome(Appended<D, T, C>)):
  do IO<Outcome(Appended<D, T, C>)>:
    stamp : Outcome(S.EntryStamp) <- freshStamp(D, T, C, stateOf(D, T, C, session))
    appendStamped(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp, transition)

def appendMessage(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, message: Agent.AgentMessage<D, T, Messages.CodingMessage<C>>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendMessage(D, T, C, state, stamp, message))

def appendThinkingLevelChange(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, level: String) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendThinkingLevelChange(D, T, C, state, stamp, level))

def appendModelChange(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, provider: String, model: String) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendModelChange(D, T, C, state, stamp, provider, model))

def appendUsage(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, kind: String, provider: String, model: String, usage: Ai.Usage, note: Maybe<&2, String>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendUsage(D, T, C, state, stamp, kind, provider, model, usage, note))

def appendCompaction(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, summary: String, firstKeptEntryId: Maybe<&2, String>, tokensBefore: Nat, details: Maybe<&2, C>, fromHook: Maybe<&2, Bool>, usage: Maybe<&2, Ai.Usage>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendCompaction(D, T, C, state, stamp, summary, firstKeptEntryId, tokensBefore, details, fromHook, usage))

def appendContextEdit(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, targetId: String, replacement: Maybe<&2, S.ContextEditableContent>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendContextEdit(D, T, C, state, stamp, targetId, replacement))

def appendCustomEntry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, customType: String, data: Maybe<&2, C>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendCustomEntry(D, T, C, state, stamp, customType, data))

def appendCustomMessageEntry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2, C>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendCustomMessageEntry(D, T, C, state, stamp, customType, content, display, details))

def appendSessionInfo(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, name: String) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendSessionInfo(D, T, C, state, stamp, name))

def appendLabelChange(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, targetId: String, label: Maybe<&2, String>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.appendLabelChange(D, T, C, state, stamp, targetId, label))

def branchWithSummary(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, branchFromId: Maybe<&2, String>, summary: String, details: Maybe<&2, C>, fromHook: Maybe<&2, Bool>, usage: Maybe<&2, Ai.Usage>) -> IO(Outcome(Appended<D, T, C>)):
  +state = stateOf(D, T, C, session)
  append(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, stamp => S.branchWithSummary(D, T, C, state, stamp, branchFromId, summary, details, fromHook, usage))

def branch(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, id: String) -> Outcome(Session<D, T, C>):
  modify(D, T, C, session, state => S.branch(D, T, C, state, id))

def resetLeaf(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>) -> Outcome(Session<D, T, C>):
  modify(D, T, C, session, state => Done{S.resetLeaf(D, T, C, state)})

# New sessions
# ------------

def headerFor(id: String, timestamp: String, cwd: String, parentSession: Maybe<&2, String>) -> S.SessionHeader:
  S.SessionHeader{Some{S.CURRENT_SESSION_VERSION()}, id, timestamp, cwd, parentSession}

def started(-D: Data, -T: Data, -C: Data, ids: Uuid.Generator, +cwd: String, +dir: String, +persist: Bool, +id: Outcome(String), timestamp: Outcome(String), parentSession: Maybe<&2, String>) -> Outcome(Session<D, T, C>):
  match id timestamp:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{+id} Done{+time}:
      Result.map(&2, &2, Error, S.SessionManager<D, T, C>, Session<D, T, C>, state => Session{state, cwd, dir, Bool.pick(Maybe<&2, String>, persist, Some{Path.join(dir, sessionFileName(time, id))}, None{}), persist, False{}, ids}, stateError(S.SessionManager<D, T, C>, S.inMemory(D, T, C, headerFor(id, time, cwd, parentSession))))

# A fresh header (and, when persisting, the file path the session will use).
def startSession(-D: Data, -T: Data, -C: Data, +ids: Uuid.Generator, cwd: String, dir: String, persist: Bool, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  match options:
    case NewSessionOptions{requested, parentSession}:
      do IO<Outcome(Session<D, T, C>)>:
        id : Outcome(String) <- chosenId(ids, requested)
        timestamp : Outcome(String) <- isoNow()
        return started(D, T, C, ids, cwd, dir, persist, id, timestamp, parentSession)

# Start a new session in the same directory and mode.
def newSession(-D: Data, -T: Data, -C: Data, +session: Session<D, T, C>, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  startSession(D, T, C, getIdGenerator(D, T, C, session), getCwd(D, T, C, session), getSessionDir(D, T, C, session), isPersisted(D, T, C, session), options)

# Loading entries into a session
# ------------------------------

def firstHeader(-D: Data, -T: Data, -C: Data, entries: List<&2, S.FileEntry<D, T, C>>) -> Maybe<&2, S.SessionHeader>:
  match entries:
    case Nil{}: None{}
    case S.Header{header} <> _: Some{header}
    case S.Entry{_} <> rest: firstHeader(D, T, C, rest)

def bodyEntries(-D: Data, -T: Data, -C: Data, entries: List<&2, S.FileEntry<D, T, C>>, +reversed: List<&2, S.SessionEntry<D, T, C>>) -> List<&2, S.SessionEntry<D, T, C>>:
  match entries:
    case Nil{}: List.reverse(&2, S.SessionEntry<D, T, C>, reversed)
    case S.Header{_} <> rest: bodyEntries(D, T, C, rest, reversed)
    case S.Entry{entry} <> rest: bodyEntries(D, T, C, rest, entry <> reversed)

def currentVersion(header: S.SessionHeader) -> Bool:
  match header:
    case S.SessionHeader{Some{version}, _, _, _, _}: Nat.is_le(S.CURRENT_SESSION_VERSION(), version)
    case S.SessionHeader{None{}, _, _, _, _}: False{}

# Typed entries are already current; an older header only needs its version.
def restored(-D: Data, -T: Data, -C: Data, header: S.SessionHeader, entries: List<&2, S.SessionEntry<D, T, C>>) -> Outcome(S.SessionManager<D, T, C>):
  Result.map(&2, &2, Error, S.SessionManager<D, T, C>, S.SessionManager<D, T, C>, state => S.withVersion(D, T, C, state, S.CURRENT_SESSION_VERSION()), stateError(S.SessionManager<D, T, C>, S.restore(D, T, C, header, entries)))

def withState(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, +state: Outcome(S.SessionManager<D, T, C>)) -> Outcome(Session<D, T, C>):
  match session state:
    case _ Fail{error}: Fail{error}
    case Session{_, place, dir, file, persist, flushed, ids} Done{state}: Done{Session{state, place, dir, file, persist, flushed, ids}}

def rewriteIf(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Outcome(Session<D, T, C>), needed: Bool) -> IO(Outcome(Session<D, T, C>)):
  match session needed:
    case Fail{error} _: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{value} False{}: IO.pure(Outcome(Session<D, T, C>), Done{value})
    case Done{+value} True{}:
      do IO<Outcome(Session<D, T, C>)>:
        result : Outcome(Unit) <- rewriteFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, value)
        return Result.map(&2, &2, Error, Unit, Session<D, T, C>, _ => value, result)

# Entries with a header adopt its identity (rewriting the file when the JSON
# layer migrated it); headerless entries continue a new session.
def continuedFresh(-D: Data, -T: Data, -C: Data, fresh: Outcome(Session<D, T, C>), entries: List<&2, S.SessionEntry<D, T, C>>) -> Outcome(Session<D, T, C>):
  match fresh:
    case Fail{error}: Fail{error}
    case Done{+begun}: withState(D, T, C, begun, stateError(S.SessionManager<D, T, C>, S.restoreEntries(D, T, C, entries, Done{stateOf(D, T, C, begun)})))

def loadWithHeader(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, found: Maybe<&2, S.SessionHeader>, +entries: List<&2, S.SessionEntry<D, T, C>>, migrated: Bool, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  match found:
    case Some{+header}: rewriteIf(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, withState(D, T, C, session, restored(D, T, C, header, entries)), migrated || Bool.not(currentVersion(header)))
    case None{}:
      do IO<Outcome(Session<D, T, C>)>:
        fresh : Outcome(Session<D, T, C>) <- newSession(D, T, C, session, options)
        return continuedFresh(D, T, C, fresh, entries)

def loadEntries(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, +entries: List<&2, S.FileEntry<D, T, C>>, migrated: Bool, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  loadWithHeader(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, firstHeader(D, T, C, entries), bodyEntries(D, T, C, entries, Nil{}), migrated, options)

def withFile(-D: Data, -T: Data, -C: Data, session: Session<D, T, C>, file: Maybe<&2, String>, flushed: Bool) -> Session<D, T, C>:
  match session:
    case Session{state, place, dir, _, persist, _, ids}: Session{state, place, dir, file, persist, flushed, ids}

def initializedAt(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, fresh: Outcome(Session<D, T, C>), path: String) -> IO(Outcome(Session<D, T, C>)):
  match fresh:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{begun}:
      +explicit = withFile(D, T, C, begun, Some{path}, True{})
      do IO<Outcome(Session<D, T, C>)>:
        result : Outcome(Unit) <- rewriteFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, explicit)
        return Result.map(&2, &2, Error, Unit, Session<D, T, C>, _ => explicit, result)

def initializedEmpty(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, path: String) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    fresh : Outcome(Session<D, T, C>) <- newSession(D, T, C, session, noOptions())
    initializedAt(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, fresh, path)

def sizeOf(result: Result<&2, &2, FS.Error, W.U64>) -> W.U64:
  Result.default(&2, &2, FS.Error, W.U64, result, W.zero())

# An empty existing file is initialized with a header; a non-empty file that
# is not a pi session is left untouched and reported.
def initializeIfEmpty(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, +path: String, empty: Bool) -> IO(Outcome(Session<D, T, C>)):
  match empty:
    case False{}: IO.pure(Outcome(Session<D, T, C>), Fail{NotASession{path}})
    case True{}: initializedEmpty(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, path)

def emptyOrInvalid(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, +path: String) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    size : Result<&2, &2, FS.Error, W.U64> <- FS.size(path)
    initializeIfEmpty(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, path, W.equal(sizeOf(size), W.zero()))

def loadedIntoFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, +path: String, loaded: Outcome(Loaded<D, T, C>)) -> IO(Outcome(Session<D, T, C>)):
  match loaded:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{Loaded{Nil{}, _}}: emptyOrInvalid(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, path)
    case Done{Loaded{entries, migrated}}: loadEntries(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, withFile(D, T, C, session, Some{path}, True{}), entries, migrated, noOptions())

def preloadedOrRead(~D: Data, ~T: Data, ~C: Data, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), path: String, preloaded: Maybe<&2, Loaded<D, T, C>>) -> IO(Outcome(Loaded<D, T, C>)):
  match preloaded:
    case Some{loaded}: IO.pure(Outcome(Loaded<D, T, C>), Done{loaded})
    case None{}: loadFile(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, path)

def existingFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +session: Session<D, T, C>, +path: String, preloaded: Maybe<&2, Loaded<D, T, C>>, present: Bool) -> IO(Outcome(Session<D, T, C>)):
  match present:
    case True{}:
      do IO<Outcome(Session<D, T, C>)>:
        loaded : Outcome(Loaded<D, T, C>) <- preloadedOrRead(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, path, preloaded)
        loadedIntoFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, path, loaded)
    case False{}:
      do IO<Outcome(Session<D, T, C>)>:
        fresh : Outcome(Session<D, T, C>) <- newSession(D, T, C, session, noOptions())
        return Result.map(&2, &2, Error, Session<D, T, C>, Session<D, T, C>, begun => withFile(D, T, C, begun, Some{path}, False{}), fresh)

# Switch to a session file (resume, branching): load it if it exists, else
# start a new session that will be written there.
def setSessionFile(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), session: Session<D, T, C>, +path: String, preloaded: Maybe<&2, Loaded<D, T, C>>) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    present : Bool <- FS.accessible(path, 0)
    existingFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, session, path, preloaded, present)

# Constructors
# ------------

def ensuredDir(+dir: String, persist: Bool) -> IO(Outcome(Unit)):
  match persist:
    case False{}: IO.pure(Outcome(Unit), Done{Unit{}})
    case True{}:
      do IO<Outcome(Unit)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(dir)
        return fileError(Unit, dir, result)

def placeholder(-D: Data, -T: Data, -C: Data, ids: Uuid.Generator, +cwd: String, +dir: String, +persist: Bool) -> Outcome(Session<D, T, C>):
  stateError(Session<D, T, C>, Result.map(&2, &2, S.Error, S.SessionManager<D, T, C>, Session<D, T, C>, state => Session{state, cwd, dir, None{}, persist, False{}, ids}, S.inMemory(D, T, C, headerFor("pending", "1970-01-01T00:00:00.000Z", cwd, None{}))))

# Upstream's constructor: an explicit file loads or initializes it, preloaded
# entries restore in memory, otherwise a new session starts.
def construct(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +ids: Uuid.Generator, +cwd: String, +dir: String, sessionFile: Maybe<&2, String>, +persist: Bool, +options: NewSessionOptions, preloaded: Maybe<&2, Loaded<D, T, C>>, ensured: Outcome(Unit), blank: Outcome(Session<D, T, C>)) -> IO(Outcome(Session<D, T, C>)):
  match sessionFile preloaded ensured blank:
    case _ _ Fail{error} _: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case _ _ _ Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Some{path} loaded Done{Unit{}} Done{empty}: setSessionFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, empty, path, loaded)
    case None{} Some{Loaded{Nil{}, _}} Done{Unit{}} Done{_}: startSession(D, T, C, ids, cwd, dir, persist, options)
    case None{} Some{Loaded{entries, migrated}} Done{Unit{}} Done{empty}: loadEntries(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, empty, entries, migrated, options)
    case None{} None{} Done{Unit{}} Done{_}: startSession(D, T, C, ids, cwd, dir, persist, options)

def build(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +ids: Uuid.Generator, +cwd: String, +dir: String, sessionFile: Maybe<&2, String>, +persist: Bool, options: NewSessionOptions, preloaded: Maybe<&2, Loaded<D, T, C>>) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    ensured : Outcome(Unit) <- ensuredDir(dir, persist)
    construct(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, dir, sessionFile, persist, options, preloaded, ensured, placeholder(D, T, C, ids, cwd, dir, persist))

def inDir(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, cwd: String, dir: Outcome(String), sessionFile: Maybe<&2, String>, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  match dir:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{chosen}: build(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, chosen, sessionFile, True{}, options, None{})

# Create a new persisted session for a working directory.
def create(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    dir : Outcome(String) <- chosenDir(sessionDir, cwd, agentDir)
    inDir(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, dir, None{}, options)

def parentDir(path: String) -> String: Path.join(path, "..")

def openWith(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +path: String, sessionDir: Maybe<&2, String>, cwd: String, preloaded: Maybe<&2, Loaded<D, T, C>>) -> IO(Outcome(Session<D, T, C>)):
  build(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, Maybe.default(&2, String, Maybe.map(&2, String, String, dir => Path.normalize(dir), sessionDir), parentDir(path)), Some{path}, True{}, noOptions(), preloaded)

# What opening learns before loading: the stored cwd and, when the bounded
# scan could not decide, the full load that replaces it.
type Discovery<-D: Data, -T: Data, -C: Data> is Data:
  Discovery{cwd: Maybe<&2, String>, preloaded: Maybe<&2, Loaded<D, T, C>>}

def fullyLoaded(-D: Data, -T: Data, -C: Data, +full: Loaded<D, T, C>) -> Discovery<D, T, C>:
  Discovery{Maybe.map(&2, S.SessionHeader, String, headerCwd, firstHeader(D, T, C, entriesOf(D, T, C, Done{full}))), Some{full}}

def headerOrLoad(~D: Data, ~T: Data, ~C: Data, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +path: String, scanned: Outcome(Maybe<&2, S.SessionHeader>)) -> IO(Outcome(Discovery<D, T, C>)):
  match scanned:
    case Done{header}: IO.pure(Outcome(Discovery<D, T, C>), Done{Discovery{Maybe.map(&2, S.SessionHeader, String, headerCwd, header), None{}}})
    case Fail{ScanLimit{_}}:
      do IO<Outcome(Discovery<D, T, C>)>:
        loaded : Outcome(Loaded<D, T, C>) <- loadFile(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, path)
        return Result.map(&2, &2, Error, Loaded<D, T, C>, Discovery<D, T, C>, full => fullyLoaded(D, T, C, full), loaded)
    case Fail{error}: IO.pure(Outcome(Discovery<D, T, C>), Fail{error})

def discovered(~D: Data, ~T: Data, ~C: Data, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +path: String, cwdOverride: Maybe<&2, String>, present: Bool) -> IO(Outcome(Discovery<D, T, C>)):
  match cwdOverride present:
    case Some{_} _: IO.pure(Outcome(Discovery<D, T, C>), Done{Discovery{None{}, None{}}})
    case None{} False{}: IO.pure(Outcome(Discovery<D, T, C>), Done{Discovery{None{}, None{}}})
    case None{} True{}:
      do IO<Outcome(Discovery<D, T, C>)>:
        scanned : Outcome(Maybe<&2, S.SessionHeader>) <- readSessionHeader(path)
        headerOrLoad(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, path, scanned)

def opened(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, path: String, sessionDir: Maybe<&2, String>, cwdOverride: Maybe<&2, String>, processCwd: String, found: Outcome(Discovery<D, T, C>)) -> IO(Outcome(Session<D, T, C>)):
  match found:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{Discovery{storedCwd, preloaded}}: openWith(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, path, sessionDir, Maybe.default(&2, String, Maybe.or(&2, String, cwdOverride, storedCwd), processCwd), preloaded)

# Open a session file. The working directory comes from the override, the
# stored header, or the process; the session directory from the argument or
# the file's parent.
def open(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +path: String, sessionDir: Maybe<&2, String>, +cwdOverride: Maybe<&2, String>, processCwd: String) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    present : Bool <- FS.accessible(path, 0)
    found : Outcome(Discovery<D, T, C>) <- discovered(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, path, cwdOverride, present)
    opened(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, Path.normalize(path), sessionDir, cwdOverride, processCwd, found)

def continued(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, dir: Outcome(String)) -> IO(Outcome(Session<D, T, C>)):
  match dir:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{+chosen}:
      do IO<Outcome(Session<D, T, C>)>:
        recent : Maybe<&2, String> <- findMostRecentSession(chosen, Bool.pick(Maybe<&2, String>, filtersCwd(sessionDir, chosen, cwd, agentDir), Some{cwd}, None{}))
        build(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, chosen, recent, True{}, noOptions(), None{})

# Continue the most recent session of the directory, or start a new one.
def continueRecent(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    dir : Outcome(String) <- chosenDir(sessionDir, cwd, agentDir)
    continued(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, sessionDir, agentDir, dir)

# An in-memory session without file persistence, optionally restoring
# entries held outside the filesystem.
def inMemory(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, cwd: String, options: NewSessionOptions, entries: Maybe<&2, List<&2, S.FileEntry<D, T, C>>>) -> IO(Outcome(Session<D, T, C>)):
  build(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, cwd, "", None{}, False{}, options, Maybe.map(&2, List<&2, S.FileEntry<D, T, C>>, Loaded<D, T, C>, restoredEntries => Loaded{restoredEntries, False{}}, entries))

# Forking
# -------

def forkedContent(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, header: S.SessionHeader, entries: List<&2, S.FileEntry<D, T, C>>) -> String:
  SJ.entryLine(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, S.Header{header}) ++ String.join(entryLines(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, bodyEntries(D, T, C, entries, Nil{}), Nil{}), "")

def forkWritten(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, targetCwd: String, dir: String, path: String, written: Outcome(Unit)) -> IO(Outcome(Session<D, T, C>)):
  match written:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{Unit{}}: build(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, targetCwd, dir, Some{path}, True{}, noOptions(), None{})

def forkInto(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, sourcePath: String, +targetCwd: String, +dir: String, entries: List<&2, S.FileEntry<D, T, C>>, id: Outcome(String), timestamp: Outcome(String)) -> IO(Outcome(Session<D, T, C>)):
  match id timestamp:
    case Fail{error} _: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case _ Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{+newId} Done{+time}:
      +path = Path.join(dir, sessionFileName(time, newId))
      do IO<Outcome(Session<D, T, C>)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.writeFileExclusive(path, forkedContent(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, headerFor(newId, time, targetCwd, Some{sourcePath}), entries))
        forkWritten(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, targetCwd, dir, path, writeOutcome(path, result))

def forkSource(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), +ids: Uuid.Generator, +sourcePath: String, targetCwd: String, dir: Outcome(String), options: NewSessionOptions, entries: List<&2, S.FileEntry<D, T, C>>) -> IO(Outcome(Session<D, T, C>)):
  match dir options entries:
    case _ _ Nil{}: IO.pure(Outcome(Session<D, T, C>), Fail{EmptySource{sourcePath}})
    case Fail{error} _ _: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case _ _ S.Entry{_} <> _: IO.pure(Outcome(Session<D, T, C>), Fail{NoSourceHeader{sourcePath}})
    case Done{+chosen} NewSessionOptions{requested, _} S.Header{_} <> rest:
      do IO<Outcome(Session<D, T, C>)>:
        made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(chosen)
        id : Outcome(String) <- chosenId(ids, requested)
        timestamp : Outcome(String) <- isoNow()
        forkInto(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, sourcePath, targetCwd, chosen, rest, Result.bind(&2, &2, Error, Unit, String, fileError(Unit, chosen, made), _ => id), timestamp)

# Fork a session file into a working directory: a new file with a new id,
# the source as parent session, and every source entry copied.
def forkFrom(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, ~diagnosticIn: V.Value -> Decoded(D), ~toolIn: V.Value -> Decoded(T), ~customIn: V.Value -> Decoded(C), ids: Uuid.Generator, +sourcePath: String, +targetCwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: NewSessionOptions) -> IO(Outcome(Session<D, T, C>)):
  do IO<Outcome(Session<D, T, C>)>:
    loaded : Outcome(Loaded<D, T, C>) <- loadFile(~D, ~T, ~C, ~diagnosticIn, ~toolIn, ~customIn, sourcePath)
    dir : Outcome(String) <- chosenDir(sessionDir, targetCwd, agentDir)
    forkSource(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, ~diagnosticIn, ~toolIn, ~customIn, ids, Path.normalize(sourcePath), Path.normalize(targetCwd), dir, options, entriesOf(D, T, C, loaded))

# Branched sessions
# -----------------

def labelCount(-D: Data, -T: Data, -C: Data, state: S.SessionManager<D, T, C>) -> Nat:
  match state:
    case S.SessionManager{_, _, _, _, _, order, _}: List.length(&2, S.LabelPosition, order)

def labelIds(-D: Data, -T: Data, -C: Data, +state: S.SessionManager<D, T, C>, count: Nat, +reversed: List<&2, String>) -> IO(List<&2, String>):
  match count:
    case 0n: IO.pure(List<&2, String>, reversed)
    case 1n+remaining:
      do IO<List<&2, String>>:
        id : String <- generateId(D, T, C, state, 100n)
        labelIds(D, T, C, state, remaining, id <> reversed)

def branchedFile(-D: Data, -T: Data, -C: Data, previous: Session<D, T, C>, +state: S.SessionManager<D, T, C>, stamp: S.EntryStamp) -> Session<D, T, C>:
  match previous stamp:
    case Session{_, place, dir, file, False{}, flushed, ids} _: Session{state, place, dir, file, False{}, flushed, ids}
    case Session{_, place, +dir, file, True{}, _, ids} S.EntryStamp{id, time}: Session{S.withParentSession(D, T, C, state, file), place, dir, Some{Path.join(dir, sessionFileName(time, id))}, True{}, False{}, ids}

def branchWrite(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, write: Bool) -> IO(Outcome(Session<D, T, C>)):
  match write:
    case False{}: IO.pure(Outcome(Session<D, T, C>), Done{session})
    case True{}:
      do IO<Outcome(Session<D, T, C>)>:
        result : Outcome(Unit) <- rewriteFile(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session)
        return afterWrite(D, T, C, session, True{}, result)

def branchWritten(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>) -> IO(Outcome(Session<D, T, C>)):
  branchWrite(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, isPersisted(D, T, C, session) && hasAssistant(D, T, C, S.getEntries(D, T, C, stateOf(D, T, C, session))))

def branchState(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, session: Session<D, T, C>, fresh: S.EntryStamp, next: Outcome(S.SessionManager<D, T, C>)) -> IO(Outcome(Session<D, T, C>)):
  match next:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{state}: branchWritten(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, branchedFile(D, T, C, session, state, fresh))

def branched(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, stamp: Outcome(S.EntryStamp), ids: List<&2, String>, leaf: String) -> IO(Outcome(Session<D, T, C>)):
  match stamp:
    case Fail{error}: IO.pure(Outcome(Session<D, T, C>), Fail{error})
    case Done{+fresh}: branchState(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, fresh, stateError(S.SessionManager<D, T, C>, S.createBranchedSession(D, T, C, stateOf(D, T, C, session), leaf, fresh, ids)))

# A new session holding only the path to a leaf (labels recreated). Persisted
# sessions get a new file, written now only if the path has an assistant
# message; otherwise the first assistant message writes it.
def createBranchedSession(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +session: Session<D, T, C>, leaf: String) -> IO(Outcome(Session<D, T, C>)):
  +state = stateOf(D, T, C, session)
  do IO<Outcome(Session<D, T, C>)>:
    id : Outcome(String) <- createSessionId(getIdGenerator(D, T, C, session))
    timestamp : Outcome(String) <- isoNow()
    ids : List<&2, String> <- labelIds(D, T, C, state, labelCount(D, T, C, state), Nil{})
    branched(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, session, Result.bind(&2, &2, Error, String, S.EntryStamp, id, newId => Result.map(&2, &2, Error, String, S.EntryStamp, time => S.EntryStamp{newId, time}, timestamp)), ids, leaf)
