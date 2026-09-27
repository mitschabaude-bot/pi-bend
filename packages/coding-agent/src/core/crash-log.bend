import Base
import ../config.bend as Config
import ./skills.bend as Skills
import ../../../ai/src/utils/json.bend as Render
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/case-map.bend as CaseMap
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/uri-component.bend as URI
import ../../../runtime/src/utf8.bend as Utf8

# upstream core/crash-log.ts: the last five crashes in <agentDir>/crashes.json,
# kept for a week. Upstream records them so that /bug can attach them and
# announces an unreported crash at the next start with a /bug notice; /bug and
# that notice are excluded (docs/scope-decisions.md), so the log is written
# and pruned but nothing announces it.
#
# Records are typed. A record in the file counts when its timestamp and
# message are strings (upstream's filter); its other fields are kept when they
# have their declared types and dropped otherwise, and `notified` is JSON
# truthiness, so rewriting the log normalizes malformed records. Timestamps
# are ISO strings: they are written with Date.formatIso and read with
# Date.parseIso, where upstream's Date.parse also accepts other formats.

type CrashKind is Data:
  UncaughtException{}
  FatalError{}

type CrashRecord is Data:
  CrashRecord{timestamp: String, version: Maybe<&2, String>, kind: Maybe<&2, CrashKind>, message: String, stack: Maybe<&2, String>, sessionFile: Maybe<&2, String>, cwd: Maybe<&2, String>, notified: Bool}

# upstream recordCrash's argument. Bend errors are values, not exceptions: the
# caller gives the message (upstream error.message || error.name) and a stack
# where one exists.
type Crash is Data:
  Crash{kind: CrashKind, message: String, stack: Maybe<&2, String>, sessionFile: Maybe<&2, String>, cwd: String}

def MAX_CRASH_RECORDS() -> Nat: 5n
def MAX_AGE() -> F64: F.fromU32(604800000)

def crashLogPath(agentDir: String) -> String: Path.join(agentDir, "crashes.json")

# <agentDir>/crashes.json
def defaultCrashLogPath() -> IO(Result<&2, &2, FS.Error, String>): Config.inAgentDir("crashes.json")

# Records
# -------

def kindName(kind: CrashKind) -> String:
  match kind:
    case UncaughtException{}: "uncaught_exception"
    case FatalError{}: "fatal_error"

def kindOf(value: Maybe<&2, V.Value>) -> Maybe<&2, CrashKind>:
  match value:
    case Some{V.Text{"uncaught_exception"}}: Some{UncaughtException{}}
    case Some{V.Text{"fatal_error"}}: Some{FatalError{}}
    case _: None{}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

# JavaScript truthiness of a JSON value.
def truthy(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: False{}
    case Some{V.Null{}}: False{}
    case Some{V.Boolean{flag}}: flag
    case Some{V.Number{+number}}: Bool.not(F.isNaN(number)) && Bool.not(F64.is_eq(number, F.fromU32(0)))
    case Some{V.Text{text}}: Bool.not(String.is_empty(text))
    case Some{_}: True{}

def recordOf(+fields: R.Record<V.Value>, timestamp: String, message: String) -> CrashRecord:
  CrashRecord{timestamp, textOf(R.get(V.Value, fields, "version")), kindOf(R.get(V.Value, fields, "kind")), message, textOf(R.get(V.Value, fields, "stack")), textOf(R.get(V.Value, fields, "sessionFile")), textOf(R.get(V.Value, fields, "cwd")), truthy(R.get(V.Value, fields, "notified"))}

def recordWith(+fields: R.Record<V.Value>, timestamp: Maybe<&2, V.Value>, message: Maybe<&2, V.Value>) -> Maybe<&2, CrashRecord>:
  match timestamp message:
    case Some{V.Text{time}} Some{V.Text{text}}: Some{recordOf(fields, time, text)}
    case _ _: None{}

def decodedRecord(value: V.Value) -> Maybe<&2, CrashRecord>:
  match value:
    case V.ObjectValue{+fields}: recordWith(fields, R.get(V.Value, fields, "timestamp"), R.get(V.Value, fields, "message"))
    case _: None{}

def prepended(record: Maybe<&2, CrashRecord>, tail: List<&2, CrashRecord>) -> List<&2, CrashRecord>:
  match record:
    case Some{found}: found <> tail
    case None{}: tail

def decodedRecords(values: List<&2, V.Value>) -> List<&2, CrashRecord>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prepended(decodedRecord(value), decodedRecords(rest))

def parsedLog(result: Result<&2, &2, Json.ParseError, V.Value>) -> List<&2, CrashRecord>:
  match result:
    case Done{V.ArrayValue{values}}: decodedRecords(values)
    case _: Nil{}

def optionalText(+name: String, value: Maybe<&2, String>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{text}: [R.Property{name, V.Text{text}}]
    case None{}: Nil{}

def nullableText(+name: String, value: Maybe<&2, String>) -> R.Property<V.Value>:
  match value:
    case Some{text}: R.Property{name, V.Text{text}}
    case None{}: R.Property{name, V.Null{}}

def optionalKind(kind: Maybe<&2, CrashKind>) -> List<&2, R.Property<V.Value>>:
  match kind:
    case Some{value}: [R.Property{"kind", V.Text{kindName(value)}}]
    case None{}: Nil{}

def notifiedField(notified: Bool) -> List<&2, R.Property<V.Value>>:
  match notified:
    case True{}: [R.Property{"notified", V.Boolean{True{}}}]
    case False{}: Nil{}

# Upstream's field order: timestamp, version, kind, message, stack,
# sessionFile, cwd, notified.
def encodedRecord(record: CrashRecord) -> V.Value:
  match record:
    case CrashRecord{timestamp, version, kind, message, stack, sessionFile, cwd, notified}:
      V.ObjectValue{R.Record{List.concat(&2, R.Property<V.Value>, [[R.Property{"timestamp", V.Text{timestamp}}], optionalText("version", version), optionalKind(kind), [R.Property{"message", V.Text{message}}, nullableText("stack", stack), nullableText("sessionFile", sessionFile)], optionalText("cwd", cwd), notifiedField(notified)])}}

def encodedRecords(records: List<&2, CrashRecord>) -> List<&2, V.Value>:
  match records:
    case Nil{}: Nil{}
    case record <> rest: encodedRecord(record) <> encodedRecords(rest)

# File access
# -----------

def contentOf(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, String>:
  match result:
    case Done{bytes}: Some{Utf8.decodeBuffer(bytes)}
    case Fail{_}: None{}

# upstream readCrashLog: [] when the file is missing or not a JSON array.
def readCrashLog(path: String) -> IO(List<&2, CrashRecord>):
  do IO<List<&2, CrashRecord>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return Maybe.default(&2, List<&2, CrashRecord>, Maybe.map(&2, String, List<&2, CrashRecord>, text => parsedLog(Json.parse(text)), contentOf(bytes)), Nil{})

def serialized(records: List<&2, CrashRecord>) -> String:
  Maybe.default(&2, String, Render.stringifyPretty(SchemaJson.toJson(V.ArrayValue{encodedRecords(records)})), "[]") ++ "\n"

def writtenAfter(+path: String, +content: String, parent: Result<&2, &2, FS.Error, Unit>) -> IO(Result<&2, &2, FS.Error, Unit>):
  match parent:
    case Fail{error}: IO.pure(Result<&2, &2, FS.Error, Unit>, Fail{error})
    case Done{_}: FS.writeFile(path, content)

# upstream writeCrashLog: the parent directory, then the pretty-printed
# records and a newline.
def writeCrashLog(records: List<&2, CrashRecord>, +path: String) -> IO(Result<&2, &2, FS.Error, Unit>):
  do IO<Result<&2, &2, FS.Error, Unit>>:
    parent : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(Path.join(path, ".."))
    writtenAfter(path, serialized(records), parent)

# Recording
# ---------

def lastRecords(+records: List<&2, CrashRecord>) -> List<&2, CrashRecord>:
  +length = List.length(&2, CrashRecord, records)
  Bool.pick(Unit -> List<&2, CrashRecord>, Nat.is_gt(length, MAX_CRASH_RECORDS()), _ => List.drop(&2, CrashRecord, records, Nat.sub(length, MAX_CRASH_RECORDS())), _ => records)(Unit{})

def recorded(+record: CrashRecord, written: Result<&2, &2, FS.Error, Unit>) -> Maybe<&2, CrashRecord>:
  match written:
    case Done{_}: Some{record}
    case Fail{_}: None{}

def newRecord(time: String, crash: Crash) -> CrashRecord:
  match crash:
    case Crash{kind, message, stack, sessionFile, cwd}: CrashRecord{time, Some{Config.version()}, Some{kind}, message, stack, sessionFile, Some{cwd}, False{}}

def appended(+path: String, +record: CrashRecord) -> IO(Maybe<&2, CrashRecord>):
  do IO<Maybe<&2, CrashRecord>>:
    records : List<&2, CrashRecord> <- readCrashLog(path)
    written : Result<&2, &2, FS.Error, Unit> <- writeCrashLog(lastRecords(List.append(&2, CrashRecord, records, [record])), path)
    return recorded(record, written)

def recordAt(+path: String, crash: Crash, timestamp: Maybe<&2, String>) -> IO(Maybe<&2, CrashRecord>):
  match timestamp:
    case None{}: IO.pure(Maybe<&2, CrashRecord>, None{})
    case Some{time}: appended(path, newRecord(time, crash))

# upstream recordCrash: best effort for callers that are already crashing;
# None when nothing was written.
def recordCrash(crash: Crash, +path: String) -> IO(Maybe<&2, CrashRecord>):
  do IO<Maybe<&2, CrashRecord>>:
    now : F64 <- Date.now()
    recordAt(path, crash, Date.formatIso(now))

def notifiedOf(record: CrashRecord) -> Bool:
  match record:
    case CrashRecord{_, _, _, _, _, _, _, notified}: notified

def recent(+now: F64, record: CrashRecord) -> Bool:
  match record:
    case CrashRecord{timestamp, _, _, _, _, _, _, False{}}: Result.default(&2, &2, Date.ParseError, Bool, Result.map(&2, &2, Date.ParseError, F64, Bool, time => F64.is_le(F.subtract(now, time), MAX_AGE()), Date.parseIso(timestamp)), False{})
    case CrashRecord{_, _, _, _, _, _, _, True{}}: False{}

def newestRecent(+now: F64, records: List<&2, CrashRecord>, +found: Maybe<&2, CrashRecord>) -> Maybe<&2, CrashRecord>:
  match records:
    case Nil{}: found
    case +record <> rest: newestRecent(now, rest, Bool.pick(Maybe<&2, CrashRecord>, recent(now, record), Some{record}, found))

def announced(record: CrashRecord) -> CrashRecord:
  match record:
    case CrashRecord{timestamp, version, kind, message, stack, sessionFile, cwd, _}: CrashRecord{timestamp, version, kind, message, stack, sessionFile, cwd, True{}}

def allAnnounced(records: List<&2, CrashRecord>) -> List<&2, CrashRecord>:
  match records:
    case Nil{}: Nil{}
    case record <> rest: announced(record) <> allAnnounced(rest)

def markedAnnounced(+path: String, records: List<&2, CrashRecord>, crash: Maybe<&2, CrashRecord>) -> IO(Maybe<&2, CrashRecord>):
  match crash:
    case None{}: IO.pure(Maybe<&2, CrashRecord>, None{})
    case Some{found}:
      do IO<Maybe<&2, CrashRecord>>:
        # A failed write only means the crash is announced again.
        written : Result<&2, &2, FS.Error, Unit> <- writeCrashLog(allAnnounced(records), path)
        return Some{found}

# upstream takeUnnotifiedCrash: the newest crash of the last week that was
# not announced yet; every record is then marked announced. (Nothing calls it
# while the /bug notice is excluded.)
def takeUnnotifiedCrash(+path: String, +now: F64) -> IO(Maybe<&2, CrashRecord>):
  do IO<Maybe<&2, CrashRecord>>:
    +records : List<&2, CrashRecord> <- readCrashLog(path)
    markedAnnounced(path, records, newestRecent(now, records, None{}))

# upstream clearCrashLog: failures are ignored.
def clearCrashLog(path: String) -> IO(Unit):
  do IO<Unit>:
    removed : Result<&2, &2, FS.Error, Unit> <- FS.remove(path, False{}, True{})
    return Unit{}

# Extension attribution
# ---------------------

# upstream Pick<Extension, "path" | "resolvedPath" | "sourceInfo">.
type ExtensionStackMetadata is Data:
  ExtensionStackMetadata{path: String, resolvedPath: String, sourceInfo: Skills.SourceInfo}

def slashes(text: String) -> String: Strings.replaceAll(text, "\\", "/")

def dropSlashes(text: String) -> String:
  match text:
    case SCon{'/', rest}: dropSlashes(rest)
    case other: other

def withoutTrailingSlashes(text: String) -> String: String.reverse(dropSlashes(String.reverse(text)))

# upstream normalizeStackPath: forward slashes, no trailing slash.
def normalizeStackPath(value: String) -> String: withoutTrailingSlashes(slashes(value))

def whitespaceChar(char: Char) -> Bool:
  match char:
    case Chr{code}: Text.whitespace(code)

def atFrame(text: String) -> Bool:
  match text:
    case SCon{'a', SCon{'t', SCon{char, _}}}: whitespaceChar(char)
    case _: False{}

def dropSpace(text: String) -> String:
  match text:
    case SCon{+char, +rest}: Bool.pick(String, whitespaceChar(char), dropSpace(rest), SCon{char, rest})
    case SNil{}: ""

# /^\s+at\s/
def frameLine(+text: String) -> Bool:
  match text:
    case SCon{+char, _}: whitespaceChar(char) && atFrame(dropSpace(text))
    case SNil{}: False{}

def frames(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest:
      +tail = frames(rest)
      Bool.pick(List<&2, String>, frameLine(line), Maybe.default(&2, String, URI.decodeURI(line), line) <> tail, tail)

def tailLines(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case _ <> rest: rest

# The stack's frame lines (after the message line), each decodeURI'd where
# possible, with forward slashes.
def normalizedStack(stack: String) -> String: slashes(String.join(frames(tailLines(String.split(stack, '\n'))), "\n"))

# /^[a-z]:\//i
def drivePath(text: String) -> Bool:
  match text:
    case SCon{Chr{+code}, SCon{':', SCon{'/', _}}}: (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))
    case _: False{}

def boundary(rest: String) -> Bool:
  match rest:
    case SNil{}: True{}
    case SCon{':', _}: True{}
    case SCon{')', _}: True{}
    case SCon{char, _}: whitespaceChar(char)

# Occurrences of the needle followed by the end, ":", ")" or whitespace.
def containsBounded(haystack: String, +needle: String) -> Bool:
  match haystack:
    case SNil{}: String.is_empty(needle)
    case SCon{+char, +rest}: (String.starts_with(SCon{char, rest}, needle) && boundary(String.drop(SCon{char, rest}, String.length(needle)))) || containsBounded(rest, needle)

def containsIn(haystack: String, +needle: String, includeDescendants: Bool) -> Bool:
  match includeDescendants:
    case True{}: String.contains(haystack, needle ++ "/")
    case False{}: containsBounded(haystack, needle)

def checkedPath(+stack: String, +target: String, +includeDescendants: Bool) -> Bool:
  Bool.pick(Unit -> Bool, drivePath(target),
    _ => containsIn(CaseMap.lower(stack), CaseMap.lower(target), includeDescendants),
    _ => containsIn(stack, target, includeDescendants))(Unit{})

# upstream stackContainsPath
def stackContainsPath(+stack: String, targetPath: String, +includeDescendants: Bool) -> Bool:
  +target = normalizeStackPath(targetPath)
  Bool.pick(Unit -> Bool, String.is_empty(target) || String.starts_with(target, "<"), _ => False{}, _ => checkedPath(stack, target, includeDescendants))(Unit{})

def isPackage(origin: Skills.SourceOrigin) -> Bool:
  match origin:
    case Skills.Package{}: True{}
    case Skills.TopLevel{}: False{}

# /\.[cm]?[jt]s$/
def scriptSuffix(+text: String) -> Bool:
  String.ends_with(text, ".js") || String.ends_with(text, ".ts") || String.ends_with(text, ".cjs") || String.ends_with(text, ".mjs") || String.ends_with(text, ".cts") || String.ends_with(text, ".mts")

# /^(?:npm:|git:|https?:\/\/|ssh:\/\/)/
def remoteSource(+source: String) -> Bool:
  String.starts_with(source, "npm:") || String.starts_with(source, "git:") || String.starts_with(source, "http://") || String.starts_with(source, "https://") || String.starts_with(source, "ssh://")

def lastSlash(text: String, +index: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: found
    case SCon{'/', rest}: lastSlash(rest, Nat.add(index, 1n), Some{index})
    case SCon{_, rest}: lastSlash(rest, Nat.add(index, 1n), found)

# /\/index\.[cm]?[jt]s$/
def directoryEntry(+path: String) -> Bool:
  String.ends_with(path, "/index.js") || String.ends_with(path, "/index.ts") || String.ends_with(path, "/index.cjs") || String.ends_with(path, "/index.mjs") || String.ends_with(path, "/index.cts") || String.ends_with(path, "/index.mts")

def rootIf(eligible: Bool, baseDir: Maybe<&2, String>) -> Maybe<&2, String>:
  match eligible baseDir:
    case True{} Some{SCon{char, rest}}: Some{SCon{char, rest}}
    case _ _: None{}

# A package's base directory, unless the package is a single local script
# file.
def packageRoot(info: Skills.SourceInfo) -> Maybe<&2, String>:
  match info:
    case Skills.SourceInfo{_, +source, _, origin, baseDir}:
      +packaged = isPackage(origin)
      rootIf(packaged && Bool.not(packaged && Bool.not(remoteSource(source)) && scriptSuffix(source)), baseDir)

def entryMatched(+stack: String, +resolvedPath: String, entry: Bool, slash: Maybe<&2, Nat>) -> Bool:
  match entry slash:
    case True{} Some{index}: stackContainsPath(stack, String.take(resolvedPath, index), True{})
    case _ _: stackContainsPath(stack, resolvedPath, False{})

def rootMatched(+stack: String, +resolvedPath: String, root: Maybe<&2, String>) -> Bool:
  match root:
    case Some{path}: stackContainsPath(stack, path, True{})
    case None{}: entryMatched(stack, resolvedPath, directoryEntry(resolvedPath), lastSlash(resolvedPath, 0n, None{}))

def matched(+stack: String, extension: ExtensionStackMetadata) -> Bool:
  match extension:
    case ExtensionStackMetadata{_, resolved, info}: rootMatched(stack, normalizeStackPath(resolved), packageRoot(info))

def labelOf(extension: ExtensionStackMetadata) -> String:
  match extension:
    case ExtensionStackMetadata{path, _, Skills.SourceInfo{_, +source, _, Skills.Package{}, _}}: Bool.pick(String, String.is_empty(source), path, source)
    case ExtensionStackMetadata{path, _, _}: path

def containsLabel(labels: List<&2, String>, +label: String) -> Bool:
  match labels:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, label) || containsLabel(rest, label)

def matches(+stack: String, extensions: List<&2, ExtensionStackMetadata>, +reversed: List<&2, String>) -> List<&2, String>:
  match extensions:
    case Nil{}: List.reverse(&2, String, reversed)
    case +extension <> rest:
      +label = labelOf(extension)
      matches(stack, rest, Bool.pick(List<&2, String>, matched(stack, extension) && Bool.not(containsLabel(reversed, label)), label <> reversed, reversed))

# upstream findExtensionStackMatches: the labels (package source, else path)
# of loaded extensions with source files in the stack's frames, in extension
# order without duplicates. Native Bend errors carry no stack, so the coding
# agent's own failures match nothing; the function serves stacks that exist.
def findExtensionStackMatches(stack: Maybe<&2, String>, extensions: List<&2, ExtensionStackMetadata>) -> List<&2, String>:
  match stack:
    case None{}: Nil{}
    case Some{SNil{}}: Nil{}
    case Some{text}: matches(normalizedStack(text), extensions, Nil{})
