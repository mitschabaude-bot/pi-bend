import Base
import ./cli/args.bend as Args
import ./cli/file-processor.bend as Files
import ./config.bend as Config
import ./core/agent-runtime.bend as Runtime
import ./core/session-manager.bend as S
import ./core/session-persistence.bend as Sessions
import ./core/tools/index.bend as Tools
import ./modes/json-event.bend as JsonEvent
import ./modes/print-mode.bend as Print
import ./utils/paths.bend as Paths
import ../../agent/src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/thinking-levels.bend as Levels
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/posix-path.bend as Path
import ../../runtime/src/url.bend as URL
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json.bend as Decode

# The pi entry point: argument parsing, mode selection, session selection,
# initial message assembly, runtime creation and exit behavior. Interactive
# and RPC modes, extensions and package commands are not ported yet; new
# messages are not yet written to the selected session (AgentSession).

type AppMode is Data:
  Interactive{}
  PrintText{}
  PrintJson{}
  Rpc{}

def resolveAppMode(mode: Maybe<&2, Args.Mode>, print: Bool, stdinTty: Bool, stdoutTty: Bool) -> AppMode:
  match mode:
    case Some{Args.Rpc{}}: Rpc{}
    case Some{Args.Json{}}: PrintJson{}
    case _: Bool.pick(AppMode, print || Bool.not(stdinTty) || Bool.not(stdoutTty), PrintText{}, Interactive{})

def reportDiagnostics(diagnostics: List<&2, Args.Diagnostic>) -> IO(Unit):
  match diagnostics:
    case Nil{}: IO.pure(Unit, Unit{})
    case Args.Error{message} <> rest:
      do IO<Unit>:
        IO.print_err("Error: " ++ message)
        reportDiagnostics(rest)
    case Args.Warning{message} <> rest:
      do IO<Unit>:
        IO.print_err("Warning: " ++ message)
        reportDiagnostics(rest)

def hasError(diagnostics: List<&2, Args.Diagnostic>) -> Bool:
  match diagnostics:
    case Nil{}: False{}
    case Args.Error{_} <> _: True{}
    case _ <> rest: hasError(rest)

def nonempty(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case value: Some{value}

def trimmed(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, String>:
  match bytes:
    case Fail{_}: None{}
    case Done{octets}: nonempty(String.trim(Utf8.decodeBytes(octets)))

# Piped stdin becomes prompt text; a terminal stdin is left alone.
def readPipedStdin(stdinTty: Bool) -> IO(Maybe<&2, String>):
  match stdinTty:
    case True{}: IO.pure(Maybe<&2, String>, None{})
    case False{}:
      do IO<Maybe<&2, String>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("/dev/stdin")
        return trimmed(bytes)

type InitialMessage is Data:
  InitialMessage{text: Maybe<&2, String>, images: List<&2, Ai.ImageContent>, remaining: List<&2, String>}

def joined(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case values: Some{String.join(values, "")}

def optionalPart(value: Maybe<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  match value:
    case None{}: rest
    case Some{text}: text <> rest

# stdin content, @file text and the first CLI message form the initial prompt.
def buildInitialMessage(+stdin: Maybe<&2, String>, +fileText: Maybe<&2, String>, +images: List<&2, Ai.ImageContent>, messages: List<&2, String>) -> InitialMessage:
  match messages:
    case Nil{}: InitialMessage{joined(optionalPart(stdin, optionalPart(fileText, Nil{}))), images, Nil{}}
    case first <> rest: InitialMessage{joined(optionalPart(stdin, optionalPart(fileText, [first]))), images, rest}

def processedText(files: Files.ProcessedFiles) -> Maybe<&2, String>:
  match files:
    case Files.ProcessedFiles{text, _}: nonempty(text)

def processedImages(files: Files.ProcessedFiles) -> List<&2, Ai.ImageContent>:
  match files:
    case Files.ProcessedFiles{_, images}: images

def fileError(error: Files.Error) -> String:
  match error:
    case Files.InvalidPath{input, _}: "Invalid file path: " ++ input
    case Files.NotFound{path, _}: "File not found: " ++ path
    case Files.Stat{path, _}: "Could not stat " ++ path
    case Files.Read{path, _}: "Could not read " ++ path
    case Files.InvalidEncoding{path, _}: "File is not valid UTF-8: " ++ path

# Tools
# -----

def prependName(+name: Maybe<&2, Tools.ToolName>, +rest: List<&2, Tools.ToolName>) -> List<&2, Tools.ToolName>:
  match name:
    case None{}: rest
    case Some{name}: name <> rest

def parseNames(names: List<&2, String>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: prependName(Tools.parseToolName(name), parseNames(rest))

def sameName(+left: Tools.ToolName, +right: Tools.ToolName) -> Bool:
  String.eq(Tools.toolName(left), Tools.toolName(right))

def containsName(names: List<&2, Tools.ToolName>, +name: Tools.ToolName) -> Bool:
  match names:
    case Nil{}: False{}
    case +first <> rest: sameName(first, name) || containsName(rest, name)

def without(names: List<&2, Tools.ToolName>, +excluded: List<&2, Tools.ToolName>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = without(rest, excluded)
      Bool.pick(List<&2, Tools.ToolName>, containsName(excluded, name), tail, name <> tail)

# --no-tools disables everything; --tools allowlists; --exclude-tools denylists.
def selectedTools(noTools: Maybe<&2, Bool>, allow: Maybe<&2, List<&2, String>>, exclude: Maybe<&2, List<&2, String>>) -> List<&2, Tools.ToolName>:
  match noTools allow exclude:
    case Some{True{}} _ _: Nil{}
    case _ Some{names} excluded: without(parseNames(names), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))
    case _ None{} excluded: without(Tools.allToolNames(), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))

# Paths
# -----

def envOr(value: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match value:
    case Done{SCon{first, rest}}: SCon{first, rest}
    case _: fallback

def located(value: Result<&2, &2, FS.Error, String>, fallback: String) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: fallback

# Exit
# ----

def exitWith(code: U32) -> IO(Unit):
  match code:
    case 0: IO.pure(Unit, Unit{})
    case failure: IO.die(Unit, failure, "")

def fail(message: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(message)
    IO.die(Unit, 1, "")

# Sessions
# --------
# The session codecs of the CLI: no diagnostic details, tool details
# rendered as the JSON events do (restored ones kept raw), extension
# payloads as JSON values.

def Session() -> Data: Sessions.Session<Unit, Tools.ToolDetails, V.Value>
def State() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Appended() -> Data: Sessions.Appended<Unit, Tools.ToolDetails, V.Value>

def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def readUnit(value: V.Value) -> Result<&2, &2, Decode.Error, Unit>: Done{Unit{}}
def readRaw(value: V.Value) -> Result<&2, &2, Decode.Error, V.Value>: Done{value}
def readDetails(value: V.Value) -> Result<&2, &2, Decode.Error, Tools.ToolDetails>: Done{Tools.RawDetails{value}}

def createSession(cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.create(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, sessionDir, agentDir, options)

def openSession(path: String, sessionDir: Maybe<&2, String>, cwd: String) -> IO(Sessions.Outcome(Session())):
  Sessions.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, ~readUnit, ~readDetails, ~readRaw, path, sessionDir, None{}, cwd)

def continueSession(cwd: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Sessions.Outcome(Session())):
  Sessions.continueRecent(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, sessionDir, agentDir)

def memorySession(cwd: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.inMemory(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, options, None{})

def forkSession(source: String, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.forkFrom(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, ~readUnit, ~readDetails, ~readRaw, source, cwd, sessionDir, agentDir, options)

def recordName(session: Session(), name: String) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendSessionInfo(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, session, name)

def recordThinking(session: Session(), level: Ai.ModelThinkingLevel) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendThinkingLevelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, session, Levels.name(level))

def recordModel(session: Session(), model: Ai.Model<Ai.JsonValue>) -> IO(Sessions.Outcome(Appended())):
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _}: Sessions.appendModelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~JsonEvent.toolDetails, ~rawValue, session, provider, id)

# The session-related arguments, by name.
type SessionFlags is Data:
  SessionFlags{continue: Bool, resume: Bool, help: Bool, listModels: Bool, name: Maybe<&2, String>, noSession: Bool, session: Maybe<&2, String>, sessionId: Maybe<&2, String>, fork: Maybe<&2, String>, sessionDir: Maybe<&2, String>}

def flag(value: Maybe<&2, Bool>) -> Bool: Maybe.default(&2, Bool, value, False{})

def sessionFlags(parsed: Args.Args) -> SessionFlags:
  match parsed:
    case Args.Args{_, _, _, _, _, _, continue, resume, help, _, _, name, noSession, session, sessionId, fork, sessionDir, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, listModels, _, _, _, _, _, _, _, _}:
      SessionFlags{flag(continue), flag(resume), flag(help), Maybe.is_some(&2, Args.ListModels, listModels), name, flag(noSession), session, sessionId, fork, sessionDir}

def flagIf(present: Bool, text: String, +rest: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, present, text <> rest, rest)

def conflicts(flags: SessionFlags, withNoSession: Bool) -> List<&2, String>:
  match flags:
    case SessionFlags{+continue, +resume, _, _, _, noSession, +session, _, _, _}:
      flagIf(Maybe.is_some(&2, String, session), "--session", flagIf(continue, "--continue", flagIf(resume, "--resume", flagIf(withNoSession && noSession, "--no-session", Nil{}))))

def combined(option: String, conflicting: List<&2, String>) -> Maybe<&2, String>:
  match conflicting:
    case Nil{}: None{}
    case names: Some{"Error: " ++ option ++ " cannot be combined with " ++ String.join(names, ", ")}

def validId(id: Maybe<&2, String>) -> Maybe<&2, String>:
  match id:
    case None{}: None{}
    case Some{value}: Bool.pick(Maybe<&2, String>, Sessions.validSessionId(value), None{}, Some{"Error: " ++ Sessions.message(Sessions.InvalidSessionId{})})

# upstream validateForkFlags and validateSessionIdFlags
def validateSessionFlags(+flags: SessionFlags) -> Maybe<&2, String>:
  match flags:
    case SessionFlags{_, _, _, _, _, _, _, +sessionId, +fork, _}:
      Maybe.or(&2, String, Maybe.bind(&2, String, String, fork, _ => combined("--fork", conflicts(flags, True{}))), Maybe.or(&2, String, Maybe.bind(&2, String, String, sessionId, _ => combined("--session-id", conflicts(flags, False{}))), validId(sessionId)))

# --session-dir, else PI_CODING_AGENT_SESSION_DIR, else the default (settings are not ported).
def sessionDirectory(requested: Maybe<&2, String>, env: Result<&1, &1, U32 & String, String>, +home: String, +cwd: String) -> Maybe<&2, String>:
  match requested env:
    case Some{dir} _: Some{Config.expanded(home, cwd, dir)}
    case None{} Done{SCon{first, rest}}: Some{Config.expanded(home, cwd, SCon{first, rest})}
    case None{} _: None{}

type Resolved is Data:
  ResolvedPath{path: String}
  ResolvedLocal{path: String}
  ResolvedGlobal{path: String, cwd: String}
  NotFound{arg: String}

def hasChar(text: String, +wanted: Char) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char, rest}: Char.is_eq(char, wanted) || hasChar(rest, wanted)

def looksLikePath(+arg: String) -> Bool:
  hasChar(arg, '/') || hasChar(arg, '\\') || String.ends_with(arg, ".jsonl")

def infoId(info: S.SessionInfo) -> String:
  match info:
    case S.SessionInfo{_, id, _, _, _, _, _, _, _, _}: id

def matching(sessions: List<&2, S.SessionInfo>, +arg: String, +exact: Bool) -> Maybe<&2, S.SessionInfo>:
  match sessions:
    case Nil{}: None{}
    case +info <> rest: Bool.pick(Unit -> Maybe<&2, S.SessionInfo>, Bool.pick(Bool, exact, String.eq(infoId(info), arg), String.starts_with(infoId(info), arg)), _ => Some{info}, _ => matching(rest, arg, exact))(Unit{})

# An exact id match first, then a prefix match, as upstream.
def matched(+sessions: List<&2, S.SessionInfo>, +arg: String) -> Maybe<&2, S.SessionInfo>:
  Maybe.or(&2, S.SessionInfo, matching(sessions, arg, True{}), matching(sessions, arg, False{}))

def globalMatch(found: Maybe<&2, S.SessionInfo>, arg: String) -> Resolved:
  match found:
    case Some{S.SessionInfo{path, _, cwd, _, _, _, _, _, _, _}}: ResolvedGlobal{path, cwd}
    case None{}: NotFound{arg}

def localOrGlobal(found: Maybe<&2, S.SessionInfo>, +arg: String, sessionDir: Maybe<&2, String>, sessionsDir: String) -> IO(Resolved):
  match found:
    case Some{S.SessionInfo{path, _, _, _, _, _, _, _, _, _}}: IO.pure(Resolved, ResolvedLocal{path})
    case None{}:
      do IO<Resolved>:
        everywhere : List<&2, S.SessionInfo> <- Sessions.listAll(sessionDir, sessionsDir)
        return globalMatch(matched(everywhere, arg), arg)

def resolvedArgument(+arg: String, environment: Paths.Environment, cwd: String) -> String:
  Result.default(&2, &2, Paths.Error, String, Paths.resolveToCwd(environment, arg, cwd), arg)

# A path-like argument is used as a file; otherwise the id is matched in the
# project's sessions, then across all projects.
def resolveWhen(pathLike: Bool, +arg: String, environment: Paths.Environment, +cwd: String, +sessionDir: Maybe<&2, String>, agentDir: String, sessionsDir: String) -> IO(Resolved):
  match pathLike:
    case True{}: IO.pure(Resolved, ResolvedPath{resolvedArgument(arg, environment, cwd)})
    case False{}:
      do IO<Resolved>:
        local : List<&2, S.SessionInfo> <- Sessions.list(cwd, sessionDir, agentDir)
        localOrGlobal(matched(local, arg), arg, sessionDir, sessionsDir)

def resolveSessionPath(+arg: String, environment: Paths.Environment, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, sessionsDir: String) -> IO(Resolved):
  resolveWhen(looksLikePath(arg), arg, environment, cwd, sessionDir, agentDir, sessionsDir)

# How session selection ends without a session: a failure (stderr, exit 1)
# or a user abort (stdout, exit 0).
type Stop is Data:
  Failed{message: String}
  Aborted{note: String}

def Selected() -> Data: Result<&2, &2, Stop, Session()>

def selected(outcome: Sessions.Outcome(Session())) -> Selected():
  match outcome:
    case Done{session}: Done{session}
    case Fail{error}: Fail{Failed{"Error: " ++ Sessions.message(error)}}

def affirmative(+answer: String) -> Bool:
  String.eq(answer, "y") || String.eq(answer, "Y") || String.eq(answer, "yes") || String.eq(answer, "YES") || String.eq(answer, "Yes")

def firstLine(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'\n', _}: ""
    case SCon{char, rest}: SCon{char, firstLine(rest)}

# Reads the answer from standard input (to end of input; no line primitive).
def promptConfirm(message: String) -> IO(Bool):
  do IO<Bool>:
    IO.write(message ++ " [y/N] ")
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("/dev/stdin")
    return affirmative(String.trim(firstLine(Maybe.default(&2, String, trimmed(bytes), ""))))

def forkedIf(confirmed: Bool, path: String, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Selected()):
  match confirmed:
    case False{}: IO.pure(Selected(), Fail{Aborted{"Aborted."}})
    case True{}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- forkSession(path, cwd, sessionDir, agentDir, Sessions.noOptions())
        return selected(forked)

def openResolved(resolved: Resolved, +cwd: String, +sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Selected()):
  match resolved:
    case ResolvedPath{path}:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- openSession(path, sessionDir, cwd)
        return selected(opened)
    case ResolvedLocal{path}:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- openSession(path, sessionDir, cwd)
        return selected(opened)
    case ResolvedGlobal{path, other}:
      do IO<Selected()>:
        IO.print("Session found in different project: " ++ other)
        confirmed : Bool <- promptConfirm("Fork this session into current directory?")
        forkedIf(confirmed, path, cwd, sessionDir, agentDir)
    case NotFound{arg}: IO.pure(Selected(), Fail{Failed{"No session found matching '" ++ arg ++ "'"}})

def forkResolved(resolved: Resolved, +cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, +sessionId: Maybe<&2, String>) -> IO(Selected()):
  match resolved:
    case NotFound{arg}: IO.pure(Selected(), Fail{Failed{"No session found matching '" ++ arg ++ "'"}})
    case ResolvedPath{path}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(forked)
    case ResolvedLocal{path}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(forked)
    case ResolvedGlobal{path, _}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(forked)

def forkUnlessExisting(existing: Maybe<&2, String>, arg: String, environment: Paths.Environment, +cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, sessionsDir: String, +sessionId: Maybe<&2, String>) -> IO(Selected()):
  match existing sessionId:
    case Some{_} Some{+id}: IO.pure(Selected(), Fail{Failed{"Session already exists with id '" ++ id ++ "'"}})
    case _ _:
      do IO<Selected()>:
        resolved : Resolved <- resolveSessionPath(arg, environment, cwd, sessionDir, agentDir, sessionsDir)
        forkResolved(resolved, cwd, sessionDir, agentDir, sessionId)

def existingById(sessionId: Maybe<&2, String>, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Maybe<&2, String>):
  match sessionId:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{id}: Sessions.findById(cwd, id, sessionDir, agentDir)

def openOrCreateById(existing: Maybe<&2, String>, +cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, sessionId: Maybe<&2, String>) -> IO(Selected()):
  match existing sessionId:
    case Some{path} _:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- openSession(path, sessionDir, cwd)
        return selected(opened)
    case None{} Some{+id}:
      do IO<Selected()>:
        IO.print_err("Warning: No project session found with id '" ++ id ++ "'; creating a new session with that id.")
        created : Sessions.Outcome(Session()) <- createSession(cwd, sessionDir, agentDir, Sessions.NewSessionOptions{Some{id}, None{}})
        return selected(created)
    case None{} None{}:
      do IO<Selected()>:
        created : Sessions.Outcome(Session()) <- createSession(cwd, sessionDir, agentDir, Sessions.noOptions())
        return selected(created)

# upstream createSessionManager: --no-session (and help/model listing) stay
# in memory; --fork and --session resolve their argument; --continue takes
# the latest session; --session-id reopens or names a new session.
def selectSession(continue: Bool, +resume: Bool, +session: Maybe<&2, String>, +sessionId: Maybe<&2, String>, fork: Maybe<&2, String>, +environment: Paths.Environment, +cwd: String, +sessionDir: Maybe<&2, String>, +agentDir: String, +sessionsDir: String) -> IO(Selected()):
  match continue resume session fork:
    case _ _ _ Some{arg}:
      do IO<Selected()>:
        existing : Maybe<&2, String> <- existingById(sessionId, cwd, sessionDir, agentDir)
        forkUnlessExisting(existing, arg, environment, cwd, sessionDir, agentDir, sessionsDir, sessionId)
    case _ _ Some{arg} None{}:
      do IO<Selected()>:
        resolved : Resolved <- resolveSessionPath(arg, environment, cwd, sessionDir, agentDir, sessionsDir)
        openResolved(resolved, cwd, sessionDir, agentDir)
    case _ True{} None{} None{}: IO.pure(Selected(), Fail{Failed{"Error: --resume needs the interactive session selector, which this port does not have yet."}})
    case True{} False{} None{} None{}:
      do IO<Selected()>:
        continued : Sessions.Outcome(Session()) <- continueSession(cwd, sessionDir, agentDir)
        return selected(continued)
    case False{} False{} None{} None{}:
      do IO<Selected()>:
        existing : Maybe<&2, String> <- existingById(sessionId, cwd, sessionDir, agentDir)
        openOrCreateById(existing, cwd, sessionDir, agentDir, sessionId)

def inMemoryOrSelected(ephemeral: Bool, continue: Bool, resume: Bool, session: Maybe<&2, String>, +sessionId: Maybe<&2, String>, fork: Maybe<&2, String>, environment: Paths.Environment, +cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, sessionsDir: String) -> IO(Selected()):
  match ephemeral:
    case True{}:
      do IO<Selected()>:
        memory : Sessions.Outcome(Session()) <- memorySession(cwd, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(memory)
    case False{}: selectSession(continue, resume, session, sessionId, fork, environment, cwd, sessionDir, agentDir, sessionsDir)

def createSessionManager(flags: SessionFlags, environment: Paths.Environment, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, sessionsDir: String) -> IO(Selected()):
  match flags:
    case SessionFlags{continue, resume, help, listModels, _, noSession, session, sessionId, fork, _}: inMemoryOrSelected(noSession || help || listModels, continue, resume, session, sessionId, fork, environment, cwd, sessionDir, agentDir, sessionsDir)

def directoryExists(path: String) -> IO(Bool):
  do IO<Bool>:
    result : Result<&1, &1, U32 & String, Unit> <- File.access(path, 0)
    return Result.is_done(&1, &1, U32 & String, Unit, result)

# upstream getMissingSessionCwdIssue / MissingSessionCwdError (print mode exits).
def missingCwdMessage(sessionCwd: String, sessionFile: String, fallback: String) -> String:
  "Stored session working directory does not exist: " ++ sessionCwd ++ "\nSession file: " ++ sessionFile ++ "\nCurrent working directory: " ++ fallback

def missingCwdFor(sessionFile: Maybe<&2, String>, +sessionCwd: String, fallback: String) -> IO(Maybe<&2, String>):
  match sessionFile:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{file}:
      do IO<Maybe<&2, String>>:
        present : Bool <- directoryExists(sessionCwd)
        return Bool.pick(Maybe<&2, String>, String.is_empty(sessionCwd) || present, None{}, Some{missingCwdMessage(sessionCwd, file, fallback)})

def missingCwdIssue(+session: Session(), fallback: String) -> IO(Maybe<&2, String>):
  missingCwdFor(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, session), Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, session), fallback)

def appendedSession(outcome: Sessions.Outcome(Appended())) -> Selected():
  match outcome:
    case Done{Sessions.Appended{session, _}}: Done{session}
    case Fail{error}: Fail{Failed{"Error: " ++ Sessions.message(error)}}

def namedWith(session: Session(), normalized: Maybe<&2, String>) -> IO(Selected()):
  match normalized:
    case None{}: IO.pure(Selected(), Fail{Failed{"Error: --name requires a non-empty value"}})
    case Some{value}:
      do IO<Selected()>:
        outcome : Sessions.Outcome(Appended()) <- recordName(session, value)
        return appendedSession(outcome)

def named(+session: Session(), name: Maybe<&2, String>) -> IO(Selected()):
  match name:
    case None{}: IO.pure(Selected(), Done{session})
    case Some{value}: namedWith(session, Args.normalizeSessionName(value))

def hasThinkingEntry(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.ThinkingLevelChangeEntry{_, _} <> _: True{}
    case _ <> rest: hasThinkingEntry(rest)

def seedOf(context: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>, branch: Result<&2, &2, S.Error, List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>>) -> Result<&2, &2, Stop, Runtime.SessionSeed>:
  match context branch:
    case Fail{error} _: Fail{Failed{"Error: " ++ Sessions.message(Sessions.State{error})}}
    case _ Fail{error}: Fail{Failed{"Error: " ++ Sessions.message(Sessions.State{error})}}
    case Done{S.SessionContext{messages, thinkingLevel, model}} Done{entries}: Done{Runtime.SessionSeed{messages, model, Bool.pick(Maybe<&2, String>, hasThinkingEntry(entries), Some{thinkingLevel}, None{})}}

# The session context seeds the agent: its messages, model and thinking level.
def sessionSeed(+session: Session()) -> Result<&2, &2, Stop, Runtime.SessionSeed>:
  +state = Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session)
  seedOf(S.sessionContext(Unit, Tools.ToolDetails, V.Value, state), S.getBranch(Unit, Tools.ToolDetails, V.Value, state, S.Latest{}))

def seedMessages(seed: Runtime.SessionSeed) -> Bool:
  match seed:
    case Runtime.SessionSeed{Nil{}, _, _}: False{}
    case _: True{}

def seedThinking(seed: Runtime.SessionSeed) -> Bool:
  match seed:
    case Runtime.SessionSeed{_, _, Some{_}}: True{}
    case _: False{}

def recordedThinking(session: Selected(), thinking: Ai.ModelThinkingLevel) -> IO(Selected()):
  match session:
    case Fail{stop}: IO.pure(Selected(), Fail{stop})
    case Done{value}:
      do IO<Selected()>:
        outcome : Sessions.Outcome(Appended()) <- recordThinking(value, thinking)
        return appendedSession(outcome)

# upstream: a resumed session records its thinking level once; a new one
# records its model and thinking level so a later resume restores them.
def recordSelection(+session: Session(), hasExisting: Bool, hasThinking: Bool, selection: Runtime.Selection) -> IO(Selected()):
  match hasExisting hasThinking selection:
    case True{} False{} Runtime.Selection{_, thinking}: recordedThinking(Done{session}, thinking)
    case True{} True{} Runtime.Selection{_, _}: IO.pure(Selected(), Done{session})
    case False{} _ Runtime.Selection{model, thinking}:
      do IO<Selected()>:
        first : Sessions.Outcome(Appended()) <- recordModel(session, model)
        recordedThinking(appendedSession(first), thinking)

# Runs
# ----

def printWith(options: Print.PrintModeOptions, pair: Runtime.AgentRuntime & Runtime.Owner()) -> IO(Unit):
  match pair:
    case Tuple{runtime, agent}:
      do IO<Unit>:
        code : U32 <- Print.runPrintMode(agent, options)
        Runtime.dispose(runtime)
        exitWith(code)

def outputMode(mode: AppMode) -> Args.Mode:
  match mode:
    case PrintJson{}: Args.Json{}
    case _: Args.Text{}

def headerOf(+session: Session()) -> S.SessionHeader:
  S.getHeader(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session))

def printRecorded(mode: Args.Mode, initial: InitialMessage, recorded: Selected(), runtime: Runtime.AgentRuntime) -> IO(Unit):
  match initial recorded:
    case _ Fail{Failed{message}}:
      do IO<Unit>:
        Runtime.dispose(runtime)
        fail(message)
    case _ Fail{Aborted{note}}:
      do IO<Unit>:
        Runtime.dispose(runtime)
        IO.print(note)
    case InitialMessage{text, images, remaining} Done{+session}: printWith(Print.PrintModeOptions{mode, remaining, text, images, headerOf(session)}, Runtime.agentOf(runtime))

def printWithSelection(mode: Args.Mode, initial: InitialMessage, session: Session(), hasExisting: Bool, hasThinking: Bool, pair: Runtime.AgentRuntime & Runtime.Selection) -> IO(Unit):
  match pair:
    case Tuple{kept, selection}:
      do IO<Unit>:
        recorded : Selected() <- recordSelection(session, hasExisting, hasThinking, selection)
        printRecorded(mode, initial, recorded, kept)

def printSelected(mode: Args.Mode, initial: InitialMessage, session: Session(), hasExisting: Bool, hasThinking: Bool, created: Runtime.Outcome(Runtime.AgentRuntime)) -> IO(Unit):
  match created:
    case Fail{error}: fail(error)
    case Done{runtime}: printWithSelection(mode, initial, session, hasExisting, hasThinking, Runtime.selectionOf(runtime))

def createOptions(parsed: Args.Args, cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String, seed: Runtime.SessionSeed) -> Runtime.CreateOptions:
  match parsed:
    case Args.Args{provider, model, apiKey, systemPrompt, appendSystemPrompt, thinking, _, _, _, _, _, _, _, _, _, _, _, _, tools, excludeTools, noTools, _, _, _, _, _, _, _, _, _, _, _, _, noContextFiles, _, _, _, _, _, _, _, _, _}:
      Runtime.CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, Maybe.default(&2, List<&2, String>, appendSystemPrompt, Nil{}), selectedTools(noTools, tools, excludeTools), Bool.not(Maybe.default(&2, Bool, noContextFiles, False{})), seed}

def runSeeded(parsed: Args.Args, mode: AppMode, initial: InitialMessage, +session: Session(), agentDir: String, authPath: String, bundlePath: String, packageDir: String, seed: Result<&2, &2, Stop, Runtime.SessionSeed>) -> IO(Unit):
  match seed:
    case Fail{Failed{message}}: fail(message)
    case Fail{Aborted{note}}: IO.print(note)
    case Done{+value}:
      do IO<Unit>:
        created : Runtime.Outcome(Runtime.AgentRuntime) <- Runtime.create(createOptions(parsed, Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, session), agentDir, authPath, bundlePath, packageDir, value))
        printSelected(outputMode(mode), initial, session, seedMessages(value), seedThinking(value), created)

def runNamed(parsed: Args.Args, mode: AppMode, initial: InitialMessage, named: Selected(), agentDir: String, authPath: String, bundlePath: String, packageDir: String) -> IO(Unit):
  match named:
    case Fail{Failed{message}}: fail(message)
    case Fail{Aborted{note}}: IO.print(note)
    case Done{+session}: runSeeded(parsed, mode, initial, session, agentDir, authPath, bundlePath, packageDir, sessionSeed(session))

def runChecked(parsed: Args.Args, mode: AppMode, initial: InitialMessage, +session: Session(), issue: Maybe<&2, String>, name: Maybe<&2, String>, agentDir: String, authPath: String, bundlePath: String, packageDir: String) -> IO(Unit):
  match issue:
    case Some{message}: fail(message)
    case None{}:
      do IO<Unit>:
        result : Selected() <- named(session, name)
        runNamed(parsed, mode, initial, result, agentDir, authPath, bundlePath, packageDir)

def runSelected(parsed: Args.Args, mode: AppMode, initial: InitialMessage, cwd: String, selection: Selected(), name: Maybe<&2, String>, agentDir: String, authPath: String, bundlePath: String, packageDir: String) -> IO(Unit):
  match selection:
    case Fail{Failed{message}}: fail(message)
    case Fail{Aborted{note}}: IO.print(note)
    case Done{+session}:
      do IO<Unit>:
        issue : Maybe<&2, String> <- missingCwdIssue(session, cwd)
        runChecked(parsed, mode, initial, session, issue, name, agentDir, authPath, bundlePath, packageDir)

def flagName(flags: SessionFlags) -> Maybe<&2, String>:
  match flags:
    case SessionFlags{_, _, _, _, name, _, _, _, _, _}: name

def flagSessionDir(flags: SessionFlags) -> Maybe<&2, String>:
  match flags:
    case SessionFlags{_, _, _, _, _, _, _, _, _, sessionDir}: sessionDir

def runConfigured(parsed: Args.Args, mode: AppMode, initial: InitialMessage, +flags: SessionFlags, +cwd: String, +home: String, url: URL.Context, agentDirLocated: Result<&2, &2, FS.Error, String>, authPath: Result<&2, &2, FS.Error, String>, bundle: Result<&1, &1, U32 & String, String>, packageDir: Result<&1, &1, U32 & String, String>, sessionEnv: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  +agentDir = located(agentDirLocated, Path.join(cwd, ".pi"))
  do IO<Unit>:
    selection : Selected() <- createSessionManager(flags, Paths.Environment{cwd, home, url}, cwd, sessionDirectory(flagSessionDir(flags), sessionEnv, home, cwd), agentDir, Path.join(agentDir, "sessions"))
    runSelected(parsed, mode, initial, cwd, selection, flagName(flags), agentDir, located(authPath, Path.join(cwd, "auth.json")), envOr(bundle, "/etc/ssl/certs/ca-certificates.crt"), envOr(packageDir, cwd))

def runWithFiles(+parsed: Args.Args, mode: AppMode, stdin: Maybe<&2, String>, messages: List<&2, String>, environment: Paths.Environment, files: Files.ResultOf(Files.ProcessedFiles)) -> IO(Unit):
  match environment files:
    case _ Fail{error}: fail(fileError(error))
    case Paths.Environment{cwd, home, url} Done{+processed}:
      do IO<Unit>:
        agentDirLocated : Result<&2, &2, FS.Error, String> <- Config.getAgentDir()
        authPath : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
        bundle : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
        packageDir : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_PACKAGE_DIR")
        sessionEnv : Result<&1, &1, U32 & String, String> <- IO.get_env(Config.envSessionDir())
        runConfigured(parsed, mode, buildInitialMessage(stdin, processedText(processed), processedImages(processed), messages), sessionFlags(parsed), cwd, home, url, agentDirLocated, authPath, bundle, packageDir, sessionEnv)

def runPrint(+parsed: Args.Args, mode: AppMode, stdinTty: Bool, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match parsed environment:
    case _ Fail{_}: fail("Could not resolve the working directory")
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, messages, fileArgs, _, _} Done{Paths.Environment{+cwd, +home, +url}}:
      do IO<Unit>:
        stdin : Maybe<&2, String> <- readPipedStdin(stdinTty)
        files : Files.ResultOf(Files.ProcessedFiles) <- Files.processFileArguments(Paths.Environment{cwd, home, url}, fileArgs, Files.defaults())
        runWithFiles(parsed, mode, stdin, messages, Paths.Environment{cwd, home, url}, files)

def runMode(parsed: Args.Args, +mode: AppMode, stdinTty: Bool) -> IO(Unit):
  match mode:
    case Interactive{}: fail("Interactive mode is not available in this port yet. Use --print/-p or --mode json.")
    case Rpc{}: fail("RPC mode is not available in this port yet.")
    case _:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        runPrint(parsed, mode, stdinTty, environment)

def modeOf(parsed: Args.Args) -> Maybe<&2, Args.Mode>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, mode, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: mode

def printFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def diagnosticsOf(parsed: Args.Args) -> List<&2, Args.Diagnostic>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, diagnostics}: diagnostics

def helpFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def versionFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def dispatch(+parsed: Args.Args, help: Bool, version: Bool, invalid: Bool, +stdinTty: Bool, stdoutTty: Bool, flagError: Maybe<&2, String>) -> IO(Unit):
  match help version invalid flagError:
    case True{} _ _ _: IO.print(Args.helpText(Config.appName()))
    case _ True{} _ _: IO.print(Config.version())
    case _ _ True{} _: IO.die(Unit, 1, "")
    case _ _ _ Some{message}: fail(message)
    case _ _ _ None{}: runMode(parsed, resolveAppMode(modeOf(parsed), printFlag(parsed), stdinTty, stdoutTty), stdinTty)

def run(+parsed: Args.Args) -> IO(Unit):
  do IO<Unit>:
    reportDiagnostics(diagnosticsOf(parsed))
    stdinTty : Bool <- IO.isTerminal(0)
    stdoutTty : Bool <- IO.isTerminal(1)
    dispatch(parsed, helpFlag(parsed), versionFlag(parsed), hasError(diagnosticsOf(parsed)), stdinTty, stdoutTty, validateSessionFlags(sessionFlags(parsed)))

# The runtime hands over an affine argv list; the parser reads a shared one.
def shared(values: List<&1, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> shared(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(Args.parseArgs(shared(values)))
