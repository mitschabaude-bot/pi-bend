import Base
import ./cli/args.bend as Args
import ./cli/auth-login.bend as AuthLogin
import ./cli/file-processor.bend as Files
import ./cli/list-models.bend as ModelList
import ./cli/session-picker.bend as Picker
import ./cli/startup-selector.bend as StartupSelector
import ./config.bend as Config
import ./core/agent-runtime.bend as Runtime
import ./core/model-runtime.bend as Models
import ./core/auth-storage.bend as AuthStorage
import ./core/session-manager.bend as S
import ./core/session-persistence.bend as Sessions
import ./core/agent-session.bend as AgentSession
import ./core/agent-session-runtime.bend as SessionRuntime
import ./core/export-html/index.bend as Export
import ./core/settings-manager.bend as Settings
import ./core/project-trust.bend as ProjectTrust
import ./core/trust-manager.bend as Trust
import ./core/tools/index.bend as Tools
import ./modes/print-mode.bend as Print
import ./modes/rpc.bend as Rpc
import ./modes/interactive/session-controller.bend as Controller
import ./modes/interactive/run.bend as InteractiveRun
import ./utils/paths.bend as Paths
import ./utils/tools-manager.bend as Manager
import ../../agent/src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/auth/types.bend as Auth
import ../../ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../../ai/src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../../ai/src/utils/thinking-levels.bend as Levels
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/posix-path.bend as Path
import ../../runtime/src/url.bend as URL
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as Record
import ../../runtime/src/abort.bend as Abort

# The pi entry point: argument parsing, mode selection, session selection,
# initial message assembly, runtime creation and exit behavior. Extensions
# and package commands remain to be ported.

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

# --no-tools disables everything; --tools allowlists; --exclude-tools denylists;
# otherwise the settings' defaultTools, else read/bash/edit/write.
def selectedTools(noTools: Maybe<&2, Bool>, allow: Maybe<&2, List<&2, String>>, exclude: Maybe<&2, List<&2, String>>, defaults: Maybe<&2, List<&2, String>>) -> List<&2, Tools.ToolName>:
  match noTools allow exclude defaults:
    case Some{True{}} _ _ _: Nil{}
    case _ Some{names} excluded _: without(parseNames(names), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))
    case _ None{} excluded Some{configured}: without(parseNames(configured), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))
    case _ None{} excluded None{}: without(Tools.allToolNames(), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))

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

def Session() -> Data: AgentSession.Session()
def Appended() -> Data: AgentSession.Appended()

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

# --session-dir, else PI_CODING_AGENT_SESSION_DIR, else the settings' sessionDir.
def sessionDirectory(requested: Maybe<&2, String>, env: Result<&1, &1, U32 & String, String>, +home: String, +cwd: String, configured: Maybe<&2, String>) -> Maybe<&2, String>:
  match requested env:
    case Some{dir} _: Some{Config.expanded(home, cwd, dir)}
    case None{} Done{SCon{first, rest}}: Some{Config.expanded(home, cwd, SCon{first, rest})}
    case None{} _: configured

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
        forked : Sessions.Outcome(Session()) <- AgentSession.forkSession(path, cwd, sessionDir, agentDir, Sessions.noOptions())
        return selected(forked)

def openResolved(resolved: Resolved, +cwd: String, +sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Selected()):
  match resolved:
    case ResolvedPath{path}:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- AgentSession.openSession(path, sessionDir, cwd)
        return selected(opened)
    case ResolvedLocal{path}:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- AgentSession.openSession(path, sessionDir, cwd)
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
        forked : Sessions.Outcome(Session()) <- AgentSession.forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(forked)
    case ResolvedLocal{path}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- AgentSession.forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
        return selected(forked)
    case ResolvedGlobal{path, _}:
      do IO<Selected()>:
        forked : Sessions.Outcome(Session()) <- AgentSession.forkSession(path, cwd, sessionDir, agentDir, Sessions.NewSessionOptions{sessionId, None{}})
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
        opened : Sessions.Outcome(Session()) <- AgentSession.openSession(path, sessionDir, cwd)
        return selected(opened)
    case None{} Some{+id}:
      do IO<Selected()>:
        IO.print_err("Warning: No project session found with id '" ++ id ++ "'; creating a new session with that id.")
        created : Sessions.Outcome(Session()) <- AgentSession.createSession(cwd, sessionDir, agentDir, Sessions.NewSessionOptions{Some{id}, None{}})
        return selected(created)
    case None{} None{}:
      do IO<Selected()>:
        created : Sessions.Outcome(Session()) <- AgentSession.createSession(cwd, sessionDir, agentDir, Sessions.noOptions())
        return selected(created)

def picked(result: Picker.Outcome(),cwd: String,sessionDir: Maybe<&2,String>) -> IO(Selected()):
  match result:
    case Fail{message}: IO.pure(Selected(),Fail{Failed{message}})
    case Done{None{}}: IO.pure(Selected(),Fail{Aborted{"No session selected"}})
    case Done{Some{path}}:
      do IO<Selected()>:
        opened : Sessions.Outcome(Session()) <- AgentSession.openSession(path,sessionDir,cwd)
        return selected(opened)

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
    case _ True{} None{} None{}:
      do IO<Selected()>:
        choice : Picker.Outcome() <- Picker.selectSession(cwd,sessionDir,agentDir,sessionsDir)
        picked(choice,cwd,sessionDir)
    case True{} False{} None{} None{}:
      do IO<Selected()>:
        continued : Sessions.Outcome(Session()) <- AgentSession.continueSession(cwd, sessionDir, agentDir)
        return selected(continued)
    case False{} False{} None{} None{}:
      do IO<Selected()>:
        existing : Maybe<&2, String> <- existingById(sessionId, cwd, sessionDir, agentDir)
        openOrCreateById(existing, cwd, sessionDir, agentDir, sessionId)

def inMemoryOrSelected(ephemeral: Bool, continue: Bool, resume: Bool, session: Maybe<&2, String>, +sessionId: Maybe<&2, String>, fork: Maybe<&2, String>, environment: Paths.Environment, +cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, sessionsDir: String) -> IO(Selected()):
  match ephemeral:
    case True{}:
      do IO<Selected()>:
        memory : Sessions.Outcome(Session()) <- AgentSession.memorySession(cwd, Sessions.NewSessionOptions{sessionId, None{}})
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
        outcome : Sessions.Outcome(Appended()) <- AgentSession.recordName(session, value)
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

def seedOf(id: String, context: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>, branch: Result<&2, &2, S.Error, List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>>) -> Result<&2, &2, Stop, Runtime.SessionSeed>:
  match context branch:
    case Fail{error} _: Fail{Failed{"Error: " ++ Sessions.message(Sessions.State{error})}}
    case _ Fail{error}: Fail{Failed{"Error: " ++ Sessions.message(Sessions.State{error})}}
    case Done{S.SessionContext{messages, thinkingLevel, model}} Done{entries}: Done{Runtime.SessionSeed{id, messages, model, Bool.pick(Maybe<&2, String>, hasThinkingEntry(entries), Some{thinkingLevel}, None{})}}

# The session context seeds the agent: its messages, model and thinking level.
def sessionSeed(+session: Session()) -> Result<&2, &2, Stop, Runtime.SessionSeed>:
  +state = Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session)
  seedOf(S.getSessionId(Unit, Tools.ToolDetails, V.Value, state), S.sessionContext(Unit, Tools.ToolDetails, V.Value, state), S.getBranch(Unit, Tools.ToolDetails, V.Value, state, S.Latest{}))

def seedMessages(seed: Runtime.SessionSeed) -> Bool:
  match seed:
    case Runtime.SessionSeed{_, Nil{}, _, _}: False{}
    case _: True{}

def seedThinking(seed: Runtime.SessionSeed) -> Bool:
  match seed:
    case Runtime.SessionSeed{_, _, _, Some{_}}: True{}
    case _: False{}

def recordedThinking(session: Selected(), thinking: Ai.ModelThinkingLevel) -> IO(Selected()):
  match session:
    case Fail{stop}: IO.pure(Selected(), Fail{stop})
    case Done{value}:
      do IO<Selected()>:
        outcome : Sessions.Outcome(Appended()) <- AgentSession.recordThinking(value, thinking)
        return appendedSession(outcome)

# upstream: a resumed session records its thinking level once; a new one
# records its model and thinking level so a later resume restores them.
def recordSelection(+session: Session(), hasExisting: Bool, hasThinking: Bool, selection: Runtime.Selection) -> IO(Selected()):
  match hasExisting hasThinking selection:
    case True{} False{} Runtime.Selection{_, thinking}: recordedThinking(Done{session}, thinking)
    case True{} True{} Runtime.Selection{_, _}: IO.pure(Selected(), Done{session})
    case False{} _ Runtime.Selection{None{}, thinking}: recordedThinking(Done{session}, thinking)
    case False{} _ Runtime.Selection{Some{model}, thinking}:
      do IO<Selected()>:
        first : Sessions.Outcome(Appended()) <- AgentSession.recordModel(session, model)
        recordedThinking(appendedSession(first), thinking)

# Runs
# ----

def queuedMessages(messages: List<&2,String>) -> List<&2,Controller.Submission>:
  match messages:
    case Nil{}: Nil{}
    case text <> rest: Controller.Submission{text,Nil{},None{}} <> queuedMessages(rest)

def initialSubmissions(initial: InitialMessage) -> List<&2,Controller.Submission>:
  match initial:
    case InitialMessage{None{},Nil{},remaining}: queuedMessages(remaining)
    case InitialMessage{None{},images,remaining}: Controller.Submission{"",images,None{}} <> queuedMessages(remaining)
    case InitialMessage{Some{text},images,remaining}: Controller.Submission{text,images,None{}} <> queuedMessages(remaining)

def outputMode(mode: AppMode) -> Args.Mode:
  match mode:
    case PrintJson{}: Args.Json{}
    case _: Args.Text{}

def optionalHome(result: Result<&2,&2,FS.Error,String>) -> Maybe<&2,String>:
  match result:
    case Fail{_}: None{}
    case Done{path}: Some{path}

# RPC owns framing and command dispatch; this loop owns the blocking stdin
# file and strict UTF-8 decoding across arbitrary read boundaries.
type RpcInput is Type:
  Read{file: File,decoder: Utf8.State}
  Bytes{pair: File & Result<&1,&1,U32 & String,List<&2,U32>>,decoder: Utf8.State}
  Checked{file: File,decoded: Result<&2,&2,Utf8.Error,Utf8.State>}
  Text{file: File,chunk: Utf8.Chunk}
  End{file: File,decoded: Result<&2,&2,Utf8.Error,String>}
  ReadFailure{file: File,message: String}

def rpcFileError(error: U32 & String) -> String:
  match error:
    case (code,message): "RPC stdin error " ++ U32.show(code) ++ ": " ++ message
def rpcClosed(result: Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,String,Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{rpcFileError(error)}
@unsafe def rpcRead(+handle: Rpc.Handle,phase: RpcInput) -> IO(Result<&2,&2,String,Unit>):
  match phase:
    case Read{file,decoder}:
      do IO<Result<&2,&2,String,Unit>>:
        pair : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,4096)
        rpcRead(handle,Bytes{pair,decoder})
    case Bytes{(file,Fail{error}),_}: rpcRead(handle,ReadFailure{file,rpcFileError(error)})
    case Bytes{(file,Done{Nil{}}),decoder}: rpcRead(handle,End{file,Utf8.finishStrict(Done{decoder})})
    case Bytes{(file,Done{bytes}),decoder}: rpcRead(handle,Checked{file,Utf8.feed(bytes,Done{decoder})})
    case Checked{file,Fail{_}}: rpcRead(handle,ReadFailure{file,"Invalid UTF-8 on RPC stdin"})
    case Checked{file,Done{decoder}}: rpcRead(handle,Text{file,Utf8.drain(decoder)})
    case Text{file,Utf8.Chunk{decoder,text}}:
      do IO<Result<&2,&2,String,Unit>>:
        Rpc.feed(handle,text)
        rpcRead(handle,Read{file,decoder})
    case End{file,Fail{_}}: rpcRead(handle,ReadFailure{file,"Incomplete UTF-8 on RPC stdin"})
    case End{file,Done{text}}:
      do IO<Result<&2,&2,String,Unit>>:
        Rpc.feed(handle,text)
        Rpc.finish(handle)
        closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return rpcClosed(closed)
    case ReadFailure{file,message}:
      do IO<Result<&2,&2,String,Unit>>:
        closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return Fail{message}

def rpcOpened(handle: Rpc.Handle,result: Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&2,String,Unit>,Fail{rpcFileError(error)})
    case Done{file}: rpcRead(handle,Read{file,Utf8.initial(Utf8.Preserve{})})

def rpcStdin(handle: Rpc.Handle) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    opened : Result<&1,&1,U32 & String,File> <- File.open("/dev/stdin","r")
    rpcOpened(handle,opened)

def interactiveFinished(result: Result<&2,&2,InteractiveRun.Error,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{error}: fail(InteractiveRun.errorMessage(error))

def selectedTheme(override: Maybe<&2,String>, settings: Settings.SettingsManager) -> Maybe<&2,String>:
  match override:
    case Some{name}: Some{name}
    case None{}: Settings.getThemeSetting(settings)

def rpcWrite(_: Unit,text: String) -> IO(Unit): IO.write(text)
def rpcFinished(result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{message}: fail(message)
def rpcInput(pair: Rpc.Owner & Rpc.Handle) -> IO(Result<&2,&2,String,Unit>):
  match pair:
    case (owner,handle):
      do IO<Result<&2,&2,String,Unit>>:
        result : Result<&2,&2,String,Unit> <- rpcStdin(handle)
        Rpc.stop(owner)
        return result
def modelsOf(runtime: Runtime.AgentRuntime) -> Runtime.AgentRuntime & Models.ModelRuntime:
  match runtime:
    case Runtime.AgentRuntime{transport,storage,storageStore,credentials,credentialStore,+models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout}:
      (Runtime.AgentRuntime{transport,storage,storageStore,credentials,credentialStore,models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout},models)
def createOptions(parsed: Args.Args, cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String, seed: Runtime.SessionSeed, +settings: Settings.SettingsManager) -> Runtime.CreateOptions:
  match parsed:
    case Args.Args{provider, model, apiKey, systemPrompt, appendSystemPrompt, thinking, _, _, _, _, _, _, _, _, _, _, _, _, tools, excludeTools, noTools, _, _, _, _, _, noSkills, skills, promptTemplates, noPromptTemplates, _, _, _, noContextFiles, _, _, _, _, _, _, _, _, _}:
      Runtime.CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, Maybe.default(&2, List<&2, String>, appendSystemPrompt, Nil{}), selectedTools(noTools, tools, excludeTools, Settings.getDefaultTools(settings)), Bool.not(Maybe.default(&2, Bool, noContextFiles, False{})), seed, settings, Runtime.ResourceOptions{Maybe.default(&2, List<&2, String>, skills, Nil{}), Maybe.default(&2, Bool, noSkills, False{}), Maybe.default(&2, List<&2, String>, promptTemplates, Nil{}), Maybe.default(&2, Bool, noPromptTemplates, False{})}}

type ScopeFlags is Data: ScopeFlags{patterns: List<&2,String>,explicitModel: Bool,thinking: Maybe<&2,Ai.ModelThinkingLevel>}
def scopeFlags(parsed: Args.Args,settings: Settings.SettingsManager) -> ScopeFlags:
  match parsed:
    case Args.Args{_, model, _, _, _, thinking, _, _, _, _, _, _, _, _, _, _, _, patterns, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ScopeFlags{Maybe.default(&2,List<&2,String>,Maybe.or(&2,List<&2,String>,patterns,Settings.getEnabledModels(settings)),Nil{}),Maybe.is_some(&2,String,model),thinking}
def sameScopeModel(+left: Models.Model(),+right: Models.Model()) -> Bool:
  String.eq(Models.modelProvider(left),Models.modelProvider(right)) && String.eq(Models.modelId(left),Models.modelId(right))
def scopeEntry(items: List<&2,Models.ScopedModel>,+model: Models.Model()) -> Maybe<&2,Models.ScopedModel>:
  match items:
    case Nil{}: None{}
    case Models.ScopedModel{+candidate,+level} <> rest:
      Bool.pick(Maybe<&2,Models.ScopedModel>,sameScopeModel(candidate,model),Some{Models.ScopedModel{candidate,level}},scopeEntry(rest,model))
def preferredScope(+items: List<&2,Models.ScopedModel>,model: Models.Model()) -> Maybe<&2,Models.ScopedModel>:
  Maybe.or(&2,Models.ScopedModel,scopeEntry(items,model),List.get(&2,Models.ScopedModel,items,0n))
def preferredSelection(+items: List<&2,Models.ScopedModel>,selected: Maybe<&2,Models.Model()>) -> Maybe<&2,Models.ScopedModel>:
  match selected:
    case None{}: List.get(&2,Models.ScopedModel,items,0n)
    case Some{model}: preferredScope(items,model)
def startupScopeChosen(runtime: Runtime.AgentRuntime,seed: Runtime.SessionSeed,settings: Settings.SettingsManager,requested: Maybe<&2,Ai.ModelThinkingLevel>,entry: Maybe<&2,Models.ScopedModel>) -> IO(Runtime.AgentRuntime):
  match entry:
    case None{}: IO.pure(Runtime.AgentRuntime,runtime)
    case Some{Models.ScopedModel{+model,level}}:
      Runtime.selectStartup(runtime,model,Runtime.thinkingLevel(Maybe.or(&2,Ai.ModelThinkingLevel,requested,level),seed,model,settings))
def startupSelected(seed: Runtime.SessionSeed,settings: Settings.SettingsManager,requested: Maybe<&2,Ai.ModelThinkingLevel>,scope: List<&2,Models.ScopedModel>,pair: Runtime.AgentRuntime & Runtime.Selection) -> IO(Runtime.AgentRuntime):
  match pair:
    case (runtime,Runtime.Selection{model,_}): startupScopeChosen(runtime,seed,settings,requested,preferredSelection(scope,model))
def startupDecision(runtime: Runtime.AgentRuntime,scope: List<&2,Models.ScopedModel>,seed: Runtime.SessionSeed,settings: Settings.SettingsManager,thinking: Maybe<&2,Ai.ModelThinkingLevel>,named: Bool,hasExisting: Bool) -> IO(Runtime.AgentRuntime):
  match named hasExisting:
    case True{} _: IO.pure(Runtime.AgentRuntime,runtime)
    case _ True{}: IO.pure(Runtime.AgentRuntime,runtime)
    case False{} False{}: startupSelected(seed,settings,thinking,scope,Runtime.selectionOf(runtime))
def startupWithScope(runtime: Runtime.AgentRuntime,scope: List<&2,Models.ScopedModel>,seed: Runtime.SessionSeed,settings: Settings.SettingsManager,flags: ScopeFlags,hasExisting: Bool) -> IO(Runtime.AgentRuntime):
  match flags:
    case ScopeFlags{_,named,thinking}: startupDecision(runtime,scope,seed,settings,thinking,named,hasExisting)
def startupScope(runtime: Runtime.AgentRuntime,scope: List<&2,Models.ScopedModel>,seed: Runtime.SessionSeed,settings: Settings.SettingsManager,flags: ScopeFlags,hasExisting: Bool) -> IO(Runtime.AgentRuntime):
  match scope:
    case Nil{}: IO.pure(Runtime.AgentRuntime,runtime)
    case items: startupWithScope(runtime,items,seed,settings,flags,hasExisting)

# Settings
# --------

def segmentText(segment: Decode.Segment) -> String:
  match segment:
    case Decode.Field{name}: "." ++ name
    case Decode.Index{index}: "[" ++ Nat.show(index) ++ "]"

def pathText(path: List<&2, Decode.Segment>) -> String:
  match path:
    case Nil{}: ""
    case segment <> rest: segmentText(segment) ++ pathText(rest)

def decodeText(error: Decode.Error) -> String:
  match error:
    case Decode.MissingField{path}: "missing " ++ pathText(path)
    case Decode.WrongType{path, expected}: "expected " ++ expected ++ " at " ++ pathText(path)
    case Decode.InvalidValue{path, expected}: "expected " ++ expected ++ " at " ++ pathText(path)

def settingsErrorText(error: Settings.Error) -> String:
  match error:
    case Settings.InvalidJson{_}: "invalid JSON"
    case Settings.InvalidSetting{cause}: decodeText(cause)
    case Settings.DuplicateSetting{path}: "duplicate setting " ++ path
    case Settings.UntrustedProject{}: "project settings are not trusted"
    case Settings.StorageFailure{message}: message
    case Settings.FileFailure{_}: "could not read the settings file"
    case Settings.InvalidEncoding{_}: "the settings file is not valid UTF-8"
    case Settings.LockFailure{_}: "could not lock the settings file"
    case Settings.CleanupFailure{_, _}: "could not release the settings lock"

def scopeText(scope: Settings.SettingsScope) -> String:
  match scope:
    case Settings.Global{}: "global"
    case Settings.Project{}: "project"

# upstream collectSettingsDiagnostics: each load error is a warning.
def settingsWarning(error: Settings.SettingsError) -> String:
  match error:
    case Settings.SettingsError{_, Some{path}, cause}: "Warning: Invalid settings file " ++ path ++ ": " ++ settingsErrorText(cause)
    case Settings.SettingsError{scope, None{}, cause}: "Warning: Invalid " ++ scopeText(scope) ++ " settings: " ++ settingsErrorText(cause)

def seenBefore(seen: List<&2, String>, +text: String) -> Bool:
  match seen:
    case Nil{}: False{}
    case previous <> rest: String.eq(previous, text) || seenBefore(rest, text)

# Startup and runtime settings managers can report the same file error once.
def reportSettings(errors: List<&2, Settings.SettingsError>, +seen: List<&2, String>) -> IO(Unit):
  match errors:
    case Nil{}: IO.pure(Unit, Unit{})
    case error <> +rest:
      +text = settingsWarning(error)
      Bool.pick(Unit -> IO(Unit), seenBefore(seen, text), _ => reportSettings(rest, seen), _ => IO.bind(Unit, Unit, IO.print_err(text), unused => reportSettings(rest, text <> seen)))(Unit{})

def drained(loaded: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager & List<&2, Settings.SettingsError>:
  match loaded:
    case Tuple{_, manager}: Settings.drainErrors(manager)

def reported(pair: Settings.SettingsManager & List<&2, Settings.SettingsError>) -> IO(Settings.SettingsManager):
  match pair:
    case Tuple{manager, errors}:
      do IO<Settings.SettingsManager>:
        reportSettings(errors, Nil{})
        return manager

def loadSettings(cwd: String, agentDir: String) -> IO(Settings.SettingsManager):
  do IO<Settings.SettingsManager>:
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
    reported(drained(loaded))

def themeOverride(parsed: Args.Args) -> Maybe<&2,String>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, useTheme, _, _, _, _, _, _, _, _, _, _, _}: useTheme

def resolveFlags(flags: ScopeFlags,available: List<&2,Models.Model()>) -> Result<&2,&2,String,List<&2,Models.ScopedModel>>:
  match flags:
    case ScopeFlags{patterns,_,_}: Models.resolveScope(patterns,available,Nil{})
# Runtime factory
# ---------------

# upstream main's createRuntime: the services and AgentSession for a session,
# with settings loaded for its cwd and the model, thinking level and scope
# resolved from the CLI arguments as at startup. AgentSessionRuntime calls it
# for the initial session and for every replacement.
type Services is Type:
  Services{runtime: Runtime.AgentRuntime, scope: List<&2, Models.ScopedModel>}

def Created() -> Type: SessionRuntime.Created<Services>
def Host() -> Data: SessionRuntime.AgentSessionRuntime<Services>

type FactoryEnv is Data:
  FactoryEnv{parsed: Args.Args, agentDir: String, authPath: String, bundlePath: String, packageDir: String, mode: AppMode, trust: Ref.Ref<Record.Record<Bool>>}
type StartupSelect is Data: StartupSelect{agentDir: String,assetsRoot: String}
def selectedTrust(context: StartupSelect,request: ProjectTrust.SelectRequest) -> IO(Maybe<&2,String>):
  match context:
    case StartupSelect{agentDir,assetsRoot}: StartupSelector.select(request,agentDir,assetsRoot)
def initialRequest(start: Maybe<&2,SessionRuntime.SessionStart>) -> Bool:
  match start:
    case None{}: True{}
    case Some{_}: False{}
def interactive(mode: AppMode) -> Bool:
  match mode:
    case Interactive{}: True{}
    case _: False{}

def releaseServices(env: Unit, services: Services) -> IO(Unit):
  match services:
    case Services{runtime, _}: Runtime.dispose(runtime)

def factoryFailed(runtime: Runtime.AgentRuntime, message: String) -> IO(Result<&1, &1, String, Created()>):
  do IO<Result<&1, &1, String, Created()>>:
    Runtime.dispose(runtime)
    return Fail{message}

def sessionWithLoadout(cwd: String, +settings: Settings.SettingsManager, +scope: List<&2, Models.ScopedModel>, session: Session(), agent: Runtime.Owner(), models: Models.ModelRuntime, pair: Runtime.AgentRuntime & Runtime.Loadout) -> IO(Result<&1, &1, String, Created()>):
  match pair:
    case (runtime, loadout):
      do IO<Result<&1, &1, String, Created()>>:
        live : AgentSession.AgentSession <- AgentSession.create(agent, session, settings, cwd, loadout, models, scope)
        return Done{SessionRuntime.Created{Services{runtime, scope}, live}}

def sessionWithModels(cwd: String, settings: Settings.SettingsManager, scope: List<&2, Models.ScopedModel>, session: Session(), agent: Runtime.Owner(), pair: Runtime.AgentRuntime & Models.ModelRuntime) -> IO(Result<&1, &1, String, Created()>):
  match pair:
    case (runtime, models): sessionWithLoadout(cwd, settings, scope, session, agent, models, Runtime.loadoutOf(runtime))

def sessionWithAgent(cwd: String, settings: Settings.SettingsManager, scope: List<&2, Models.ScopedModel>, session: Session(), pair: Runtime.AgentRuntime & Runtime.Owner()) -> IO(Result<&1, &1, String, Created()>):
  match pair:
    case (runtime, agent): sessionWithModels(cwd, settings, scope, session, agent, modelsOf(runtime))

def createdSession(cwd: String, settings: Settings.SettingsManager, scope: List<&2, Models.ScopedModel>, recorded: Selected(), runtime: Runtime.AgentRuntime) -> IO(Result<&1, &1, String, Created()>):
  match recorded:
    case Fail{Failed{message}}: factoryFailed(runtime, message)
    case Fail{Aborted{note}}: factoryFailed(runtime, note)
    case Done{session}: sessionWithAgent(cwd, settings, scope, session, Runtime.agentOf(runtime))

def selectionRecorded(cwd: String, session: Session(), hasExisting: Bool, hasThinking: Bool, settings: Settings.SettingsManager, scope: List<&2, Models.ScopedModel>, pair: Runtime.AgentRuntime & Runtime.Selection) -> IO(Result<&1, &1, String, Created()>):
  match pair:
    case (runtime, selection):
      do IO<Result<&1, &1, String, Created()>>:
        recorded : Selected() <- recordSelection(session, hasExisting, hasThinking, selection)
        createdSession(cwd, settings, scope, recorded, runtime)

def scopeApplied(cwd: String, session: Session(), +hasExisting: Bool, hasThinking: Bool, +settings: Settings.SettingsManager, seed: Runtime.SessionSeed, flags: ScopeFlags, +scope: List<&2, Models.ScopedModel>, runtime: Runtime.AgentRuntime) -> IO(Result<&1, &1, String, Created()>):
  do IO<Result<&1, &1, String, Created()>>:
    selected : Runtime.AgentRuntime <- startupScope(runtime, scope, seed, settings, flags, hasExisting)
    selectionRecorded(cwd, session, hasExisting, hasThinking, settings, scope, Runtime.selectionOf(selected))

def scopeResolved(cwd: String, session: Session(), hasExisting: Bool, hasThinking: Bool, settings: Settings.SettingsManager, seed: Runtime.SessionSeed, flags: ScopeFlags, runtime: Runtime.AgentRuntime, result: Result<&2, &2, String, List<&2, Models.ScopedModel>>) -> IO(Result<&1, &1, String, Created()>):
  match result:
    case Fail{message}: factoryFailed(runtime, message)
    case Done{scope}: scopeApplied(cwd, session, hasExisting, hasThinking, settings, seed, flags, scope, runtime)

def catalogScoped(cwd: String, session: Session(), hasExisting: Bool, hasThinking: Bool, settings: Settings.SettingsManager, seed: Runtime.SessionSeed, +flags: ScopeFlags, pair: Runtime.AgentRuntime & Models.ModelRuntime) -> IO(Result<&1, &1, String, Created()>):
  match pair:
    case (runtime, models):
      do IO<Result<&1, &1, String, Created()>>:
        available : List<&2, Models.Model()> <- Models.getAvailable(models)
        scopeResolved(cwd, session, hasExisting, hasThinking, settings, seed, flags, runtime, resolveFlags(flags, available))

def runtimeCreated(cwd: String, session: Session(), hasExisting: Bool, hasThinking: Bool, settings: Settings.SettingsManager, seed: Runtime.SessionSeed, flags: ScopeFlags, created: Runtime.Outcome(Runtime.AgentRuntime)) -> IO(Result<&1, &1, String, Created()>):
  match created:
    case Fail{error}: IO.pure(Result<&1, &1, String, Created()>, Fail{error})
    case Done{runtime}: catalogScoped(cwd, session, hasExisting, hasThinking, settings, seed, flags, modelsOf(runtime))

def dashed(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: ("--" ++ name) <> dashed(rest)

# agent-session-services checks CLI flags against the flags extensions
# register; with no extension registry every unclaimed flag is unknown.
def unknownOptions(names: List<&2, String>) -> Maybe<&2, String>:
  match names:
    case Nil{}: None{}
    case _ <> Nil{}: Some{"Error: Unknown option: " ++ String.join(dashed(names), ", ")}
    case _: Some{"Error: Unknown options: " ++ String.join(dashed(names), ", ")}

# upstream main createRuntime: project settings and resources load only for a
# trusted project (resolveProjectTrusted); the startup settings stay trusted.
def loadSettingsTrusted(cwd: String, agentDir: String, trusted: Bool) -> IO(Settings.SettingsManager):
  do IO<Settings.SettingsManager>:
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{trusted})
    reported(drained(loaded))
def envHome(value: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match value:
    case Done{home}: Some{home}
    case Fail{_}: None{}
def runtimeWithSettings(env: FactoryEnv, +cwd: String, +session: Session(), +value: Runtime.SessionSeed, +settings: Settings.SettingsManager) -> IO(Result<&1, &1, String, Created()>):
  match env:
    case FactoryEnv{+parsed, agentDir, authPath, bundlePath, packageDir,_,_}:
      do IO<Result<&1, &1, String, Created()>>:
        created : Runtime.Outcome(Runtime.AgentRuntime) <- Runtime.create(createOptions(parsed, cwd, agentDir, authPath, bundlePath, packageDir, value, settings))
        runtimeCreated(cwd, session, seedMessages(value), seedThinking(value), settings, value, scopeFlags(parsed, settings), created)
def trustedRuntime(env: FactoryEnv, +cwd: String, +session: Session(), +value: Runtime.SessionSeed, startup: Settings.SettingsManager, trust: Result<&2, &2, String, Bool>) -> IO(Result<&1, &1, String, Created()>):
  match env trust:
    case _ Fail{message}: IO.pure(Result<&1, &1, String, Created()>, Fail{"Error: " ++ message})
    case env Done{True{}}: runtimeWithSettings(env, cwd, session, value, startup)
    case FactoryEnv{parsed, +agentDir, authPath, bundlePath, packageDir,mode,cache} Done{False{}}:
      do IO<Result<&1, &1, String, Created()>>:
        +untrusted : Settings.SettingsManager <- loadSettingsTrusted(cwd, agentDir, False{})
        runtimeWithSettings(FactoryEnv{parsed, agentDir, authPath, bundlePath, packageDir,mode,cache}, cwd, session, value, untrusted)
def overrideFor(explicit: Maybe<&2,Bool>,cached: Maybe<&2,Bool>) -> Maybe<&2,Bool>:
  match explicit:
    case Some{value}: Some{value}
    case None{}: cached
def resolvedTrust(options: ProjectTrust.ResolveProjectTrustedOptions,prompt: Bool,agentDir: String,assetsRoot: String) -> IO(Result<&2,&2,String,Bool>):
  match prompt:
    case False{}: ProjectTrust.resolveProjectTrusted(options,None{})
    case True{}:
      do IO<Result<&2,&2,String,Bool>>:
        +selector : Callback.Callback<ProjectTrust.SelectRequest,Maybe<&2,String>> <- Callback.create(~StartupSelect,~ProjectTrust.SelectRequest,~Maybe<&2,String>,~selectedTrust,StartupSelect{agentDir,assetsRoot})
        answer : Result<&2,&2,String,Bool> <- ProjectTrust.resolveProjectTrusted(options,Some{selector})
        Callback.dispose(ProjectTrust.SelectRequest,Maybe<&2,String>,selector)
        return answer
def rememberTrust(cache: Ref.Ref<Record.Record<Bool>>,cwd: String,result: Result<&2,&2,String,Bool>) -> IO(Unit):
  match result:
    case Done{trusted}: Ref.modify(Record.Record<Bool>,Unit,cache,current => (Record.set(Bool,current,cwd,trusted),Unit{}))
    case Fail{_}: IO.pure(Unit,Unit{})
def flaggedRuntime(env: FactoryEnv, +cwd: String, +session: Session(), +value: Runtime.SessionSeed, unknown: Maybe<&2, String>,initial: Bool) -> IO(Result<&1, &1, String, Created()>):
  match env unknown:
    case _ Some{message}: IO.pure(Result<&1, &1, String, Created()>, Fail{message})
    case FactoryEnv{+parsed, +agentDir, authPath, bundlePath, +packageDir,+mode,+cache} None{}:
      do IO<Result<&1, &1, String, Created()>>:
        +startup : Settings.SettingsManager <- loadSettings(cwd, agentDir)
        home : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
        known : Record.Record<Bool> <- Ref.read(Record.Record<Bool>,cache)
        +trust : Result<&2, &2, String, Bool> <- resolvedTrust(ProjectTrust.ResolveProjectTrustedOptions{cwd, envHome(home), Trust.create(agentDir), overrideFor(Args.projectTrustOverrideOf(parsed),Record.get(Bool,known,cwd)), Settings.getDefaultProjectTrust(startup)},initial && interactive(mode),agentDir,packageDir)
        rememberTrust(cache,cwd,trust)
        trustedRuntime(FactoryEnv{parsed, agentDir, authPath, bundlePath, packageDir,mode,cache}, cwd, session, value, startup, trust)

def seededRuntime(env: FactoryEnv, +cwd: String, +session: Session(), seed: Result<&2, &2, Stop, Runtime.SessionSeed>,initial: Bool) -> IO(Result<&1, &1, String, Created()>):
  match env seed:
    case _ Fail{Failed{message}}: IO.pure(Result<&1, &1, String, Created()>, Fail{message})
    case _ Fail{Aborted{note}}: IO.pure(Result<&1, &1, String, Created()>, Fail{note})
    case FactoryEnv{+parsed, agentDir, authPath, bundlePath, packageDir,mode,cache} Done{value}: flaggedRuntime(FactoryEnv{parsed, agentDir, authPath, bundlePath, packageDir,mode,cache}, cwd, session, value, unknownOptions(Args.unknownFlagNames(parsed)),initial)

def createRuntime(env: FactoryEnv, request: SessionRuntime.Request) -> IO(Result<&1, &1, String, Created()>):
  match request:
    case SessionRuntime.Request{cwd, +session, start}: seededRuntime(env, cwd, session, sessionSeed(session),initialRequest(start))

# Modes
# -----

def activeSession(live: Maybe<&2, AgentSession.AgentSession>) -> IO(AgentSession.AgentSession):
  match live:
    case Some{session}: IO.pure(AgentSession.AgentSession, session)
    case None{}: IO.die(AgentSession.AgentSession, 1, "No active session")

def printSelected(options: Print.PrintModeOptions, host: Host(), live: AgentSession.AgentSession, selected: Maybe<&2, Models.Model()>) -> IO(Unit):
  match selected:
    case None{}:
      do IO<Unit>:
        SessionRuntime.dispose(Services, host)
        fail(Runtime.noModels())
    case Some{_}:
      do IO<Unit>:
        code : U32 <- Print.runPrintMode(live, options)
        SessionRuntime.dispose(Services, host)
        exitWith(code)
def printHosted(options: Print.PrintModeOptions, +host: Host()) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2, AgentSession.AgentSession> <- SessionRuntime.session(Services, host)
    +live : AgentSession.AgentSession <- activeSession(current)
    state : AgentSession.AgentState() <- AgentSession.state(live)
    printSelected(options, host, live, AgentSession.stateModel(state))

type Catalog is Data:
  Catalog{available: List<&2,Models.Model()>, scope: List<&2,Models.ScopedModel>}
def catalogPair(+scope: List<&2,Models.ScopedModel>, pair: Runtime.AgentRuntime & Models.ModelRuntime) -> IO(Services & Catalog):
  match pair:
    case (runtime, models):
      do IO<Services & Catalog>:
        available : List<&2,Models.Model()> <- Models.getAvailable(models)
        return (Services{runtime, scope}, Catalog{available, scope})
def catalogOf(services: Services) -> IO(Services & Catalog):
  match services:
    case Services{runtime, scope}: catalogPair(scope, modelsOf(runtime))
def catalogModels(catalog: Catalog) -> List<&2,Models.Model()>:
  match catalog: case Catalog{available,_}: available

type InteractiveRebind is Data:
  InteractiveRebind{current: Ref.Ref<AgentSession.AgentSession>,hook: Ref.Ref<Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>>}
def callInteractiveRebind(callback: Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>,live: AgentSession.AgentSession) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(AgentSession.AgentSession,Unit,value,live)
def rebindInteractiveCopied(binding: InteractiveRebind,+live: AgentSession.AgentSession) -> IO(Unit):
  match binding:
    case InteractiveRebind{current,hook}:
      do IO<Unit>:
        Ref.write(AgentSession.AgentSession,current,live)
        callback : Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>,hook)
        callInteractiveRebind(callback,live)
def rebindInteractive(binding: InteractiveRebind,live: AgentSession.AgentSession) -> IO(Unit):
  rebindInteractiveCopied(binding,live)
def newInteractive(host: Host(),_: Unit) -> IO(Result<&2,&2,String,Unit>):
  SessionRuntime.newSession(Services,host,None{})
def loginInteractive(_: Unit,request: InteractiveRun.LoginRequest) -> IO(AuthLogin.Outcome()):
  match request:
    case InteractiveRun.LoginRequest{provider,signal,notice,manual,manualDone}:
      match provider:
        case "anthropic": AuthLogin.authenticateAnthropic(AuthLogin.BrowserInteraction{signal,manual,manualDone})
        case _: AuthLogin.authenticate(CodexOAuth.deviceEndpoints(),signal,notice)
def refreshInteractive(host: Host(),_: Unit) -> IO(List<&2,Models.Model()>):
  do IO<List<&2,Models.Model()>>:
    catalog : Catalog <- SessionRuntime.withServices(Services,Catalog,host,catalogOf,Catalog{Nil{},Nil{}})
    return catalogModels(catalog)
def importInteractive(host: Host(),request: InteractiveRun.ImportRequest) -> IO(SessionRuntime.ImportOutcome):
  match request:
    case InteractiveRun.ImportRequest{path,cwdOverride}: SessionRuntime.importFromJsonl(Services,host,path,cwdOverride)
type InteractiveSessionSource is Data: InteractiveSessionSource{host: Host(),agentDir: String}
def sessionOverride(default: Bool,directory: String) -> Maybe<&2,String>:
  match default:
    case True{}: None{}
    case False{}: Some{directory}
def listInteractive(source: InteractiveSessionSource,_: Unit) -> IO(InteractiveRun.SessionChoices):
  match source:
    case InteractiveSessionSource{host,+agentDir}:
      do IO<InteractiveRun.SessionChoices>:
        current : Maybe<&2,AgentSession.AgentSession> <- SessionRuntime.session(Services,host)
        +live : AgentSession.AgentSession <- activeSession(current)
        +stored : AgentSession.Session() <- AgentSession.sessionOf(live)
        +cwd : String <- IO.pure(String,Sessions.getCwd(Unit,Tools.ToolDetails,V.Value,stored))
        +directory : String <- IO.pure(String,Sessions.getSessionDir(Unit,Tools.ToolDetails,V.Value,stored))
        +override : Maybe<&2,String> <- IO.pure(Maybe<&2,String>,sessionOverride(Sessions.usesDefaultSessionDir(Unit,Tools.ToolDetails,V.Value,stored,agentDir),directory))
        local : List<&2,S.SessionInfo> <- Sessions.list(cwd,override,agentDir)
        all : List<&2,S.SessionInfo> <- Sessions.listAll(override,Path.join(agentDir,"sessions"))
        return InteractiveRun.SessionChoices{local,all}
def resumeInteractive(host: Host(),request: InteractiveRun.ResumeRequest) -> IO(SessionRuntime.ResumeOutcome):
  match request:
    case InteractiveRun.ResumeRequest{path,cwdOverride}: SessionRuntime.resumeSession(Services,host,path,cwdOverride)

def forkHosted(host: Host(), request: SessionRuntime.ForkRequest) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  match request:
    case SessionRuntime.ForkRequest{entryId, position}: SessionRuntime.fork(Services, host, entryId, position)
def managedInRuntime(scope: List<&2,Models.ScopedModel>,pair: Runtime.AgentRuntime & Manager.ToolsManager) -> IO(Services & Maybe<&2,Manager.ToolsManager>):
  match pair:
    case (runtime,manager):
      IO.pure(Services & Maybe<&2,Manager.ToolsManager>,(Services{runtime,scope},Some{manager}))
def managedInServices(agentDir: String,services: Services) -> IO(Services & Maybe<&2,Manager.ToolsManager>):
  match services:
    case Services{runtime,scope}: managedInRuntime(scope,Runtime.managedTools(runtime,agentDir))

def interactiveHosted(initial: InitialMessage, themeOverride: Maybe<&2,String>, +cwd: String, +agentDir: String, packageDir: String, +host: Host()) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2, AgentSession.AgentSession> <- SessionRuntime.session(Services, host)
    +live : AgentSession.AgentSession <- activeSession(current)
    settings : Settings.SettingsManager <- Ref.read(Settings.SettingsManager, AgentSession.settingsOf(live))
    home : Result<&2,&2,FS.Error,String> <- FS.homedir()
    catalog : Catalog <- SessionRuntime.withServices(Services,Catalog,host,catalogOf,Catalog{Nil{},Nil{}})
    +current : Ref.Ref<AgentSession.AgentSession> <- Ref.new(AgentSession.AgentSession,live)
    +onRebind : Ref.Ref<Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>,None{})
    +rebinder : Callback.Callback<AgentSession.AgentSession,Unit> <- Callback.create(~InteractiveRebind,~AgentSession.AgentSession,~Unit,~rebindInteractive,InteractiveRebind{current,onRebind})
    +startNew : Callback.Callback<Unit,Result<&2,&2,String,Unit>> <- Callback.create(~Host(),~Unit,~Result<&2,&2,String,Unit>,~newInteractive,host)
    +forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>> <- Callback.create(~Host(),~SessionRuntime.ForkRequest,~Result<&2,&2,String,Maybe<&2,String>>,~forkHosted,host)
    +login : Callback.Callback<InteractiveRun.LoginRequest,AuthLogin.Outcome()> <- Callback.create(~Unit,~InteractiveRun.LoginRequest,~AuthLogin.Outcome(),~loginInteractive,Unit{})
    +refresh : Callback.Callback<Unit,List<&2,Models.Model()>> <- Callback.create(~Host(),~Unit,~List<&2,Models.Model()>,~refreshInteractive,host)
    +importer : Callback.Callback<InteractiveRun.ImportRequest,SessionRuntime.ImportOutcome> <- Callback.create(~Host(),~InteractiveRun.ImportRequest,~SessionRuntime.ImportOutcome,~importInteractive,host)
    +sessions : Callback.Callback<Unit,InteractiveRun.SessionChoices> <- Callback.create(~InteractiveSessionSource,~Unit,~InteractiveRun.SessionChoices,~listInteractive,InteractiveSessionSource{host,agentDir})
    +resume : Callback.Callback<InteractiveRun.ResumeRequest,SessionRuntime.ResumeOutcome> <- Callback.create(~Host(),~InteractiveRun.ResumeRequest,~SessionRuntime.ResumeOutcome,~resumeInteractive,host)
    tools : Maybe<&2,Manager.ToolsManager> <- SessionRuntime.withServices(Services,Maybe<&2,Manager.ToolsManager>,host,services => managedInServices(agentDir,services),None{})
    SessionRuntime.setRebindSession(Services,host,Some{rebinder})
    result : Result<&2,&2,InteractiveRun.Error,Unit> <- InteractiveRun.runBound(live,InteractiveRun.Binding{current,Controller.Replacement{startNew,forking},onRebind,login,refresh,importer,sessions,resume,tools},initialSubmissions(initial),cwd,optionalHome(home),agentDir,packageDir,selectedTheme(themeOverride,settings),catalogModels(catalog))
    SessionRuntime.setRebindSession(Services,host,None{})
    Callback.dispose(InteractiveRun.LoginRequest,AuthLogin.Outcome(),login)
    Callback.dispose(Unit,List<&2,Models.Model()>,refresh)
    Callback.dispose(InteractiveRun.ImportRequest,SessionRuntime.ImportOutcome,importer)
    Callback.dispose(Unit,InteractiveRun.SessionChoices,sessions)
    Callback.dispose(InteractiveRun.ResumeRequest,SessionRuntime.ResumeOutcome,resume)
    Callback.dispose(Unit,Result<&2,&2,String,Unit>,startNew)
    Callback.dispose(SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>,forking)
    Callback.dispose(AgentSession.AgentSession,Unit,rebinder)
    oldHook : Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<AgentSession.AgentSession,Unit>>,onRebind)
    oldSession : AgentSession.AgentSession <- Ref.dispose(AgentSession.AgentSession,current)
    SessionRuntime.dispose(Services, host)
    interactiveFinished(result)

def rpcNewSession(host: Host(), parent: Maybe<&2,String>) -> IO(Result<&2,&2,String,Unit>):
  SessionRuntime.newSession(Services, host, parent)
def rpcSwitchSession(host: Host(), path: String) -> IO(Result<&2,&2,String,Unit>):
  SessionRuntime.switchSession(Services, host, path, None{})
def rpcRebind(handle: Rpc.Handle, live: AgentSession.AgentSession) -> IO(Unit): Rpc.rebind(handle, live)

def disposeRpcHost(rpcHost: Rpc.Host) -> IO(Unit):
  match rpcHost:
    case Rpc.Host{opening, switching, forking}:
      do IO<Unit>:
        Callback.dispose(Maybe<&2,String>,Result<&2,&2,String,Unit>,opening)
        Callback.dispose(String,Result<&2,&2,String,Unit>,switching)
        Callback.dispose(SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>,forking)

def rpcServed(+host: Host(), rpcHost: Rpc.Host, pair: Rpc.Owner & Rpc.Handle) -> IO(Result<&2,&2,String,Unit>):
  match pair:
    case (owner, +handle):
      do IO<Result<&2,&2,String,Unit>>:
        +rebinder : Callback.Callback<AgentSession.AgentSession,Unit> <- Callback.create(~Rpc.Handle,~AgentSession.AgentSession,~Unit,~rpcRebind,handle)
        SessionRuntime.setRebindSession(Services, host, Some{rebinder})
        result : Result<&2,&2,String,Unit> <- rpcInput((owner, handle))
        SessionRuntime.setRebindSession(Services, host, None{})
        Callback.dispose(AgentSession.AgentSession,Unit,rebinder)
        disposeRpcHost(rpcHost)
        return result

def rpcSelected(live: AgentSession.AgentSession, assetsRoot: String, +host: Host(), selected: Maybe<&2,Models.Model()>) -> IO(Unit):
  match selected:
    case None{}:
      do IO<Unit>:
        SessionRuntime.dispose(Services, host)
        fail(Runtime.noModels())
    case Some{_}:
      do IO<Unit>:
        +sink : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~rpcWrite,Unit{})
        opening : Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Unit>> <- Callback.create(~Host(),~Maybe<&2,String>,~Result<&2,&2,String,Unit>,~rpcNewSession,host)
        switching : Callback.Callback<String,Result<&2,&2,String,Unit>> <- Callback.create(~Host(),~String,~Result<&2,&2,String,Unit>,~rpcSwitchSession,host)
        forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>> <- Callback.create(~Host(),~SessionRuntime.ForkRequest,~Result<&2,&2,String,Maybe<&2,String>>,~forkHosted,host)
        +rpcHost : Rpc.Host = Rpc.Host{opening, switching, forking}
        endpoint : Rpc.Owner & Rpc.Handle <- Rpc.start(live,sink,Some{Path.join(assetsRoot,"packages/coding-agent/src/core/export-html")},rpcHost)
        result : Result<&2,&2,String,Unit> <- rpcServed(host, rpcHost, endpoint)
        Callback.dispose(String,Unit,sink)
        SessionRuntime.dispose(Services, host)
        rpcFinished(result)

def rpcHosted(assetsRoot: String, +host: Host()) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2, AgentSession.AgentSession> <- SessionRuntime.session(Services, host)
    +live : AgentSession.AgentSession <- activeSession(current)
    state : AgentSession.AgentState() <- AgentSession.state(live)
    rpcSelected(live, assetsRoot, host, AgentSession.stateModel(state))
def runHosted(mode: AppMode, initial: InitialMessage, themeOverride: Maybe<&2,String>, cwd: String, agentDir: String, packageDir: String, started: Result<&2, &2, String, Host()>) -> IO(Unit):
  match mode initial started:
    case _ _ Fail{message}: fail(message)
    case Interactive{} _ Done{host}: interactiveHosted(initial, themeOverride, cwd, agentDir, packageDir, host)
    case Rpc{} _ Done{host}: rpcHosted(packageDir, host)
    case _ InitialMessage{text, images, remaining} Done{host}: printHosted(Print.PrintModeOptions{outputMode(mode), remaining, text, images}, host)

def runSeeded(+parsed: Args.Args, +mode: AppMode, initial: InitialMessage, +session: Session(), +agentDir: String, authPath: String, bundlePath: String, +packageDir: String) -> IO(Unit):
  +sessionCwd = Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, session)
  do IO<Unit>:
    +trust : Ref.Ref<Record.Record<Bool>> <- Ref.new(Record.Record<Bool>,Record.new(Bool))
    +factory : SessionRuntime.Factory(Services) <- Callback.create(~FactoryEnv, ~SessionRuntime.Request, ~Result<&1, &1, String, Created()>, ~createRuntime, FactoryEnv{parsed, agentDir, authPath, bundlePath, packageDir,mode,trust})
    +release : Callback.Callback<Services, Unit> <- Callback.create(~Unit, ~Services, ~Unit, ~releaseServices, Unit{})
    started : Result<&2, &2, String, Host()> <- SessionRuntime.create(Services, factory, release, agentDir, sessionCwd, session)
    runHosted(mode, initial, themeOverride(parsed), sessionCwd, agentDir, packageDir, started)
    Callback.dispose(SessionRuntime.Request, Result<&1, &1, String, Created()>, factory)
    Callback.dispose(Services, Unit, release)
    decision : Record.Record<Bool> <- Ref.dispose(Record.Record<Bool>,trust)
    return Unit{}

def runNamed(parsed: Args.Args, mode: AppMode, initial: InitialMessage, named: Selected(), agentDir: String, authPath: String, bundlePath: String, packageDir: String) -> IO(Unit):
  match named:
    case Fail{Failed{message}}: fail(message)
    case Fail{Aborted{note}}: IO.print(note)
    case Done{+session}: runSeeded(parsed, mode, initial, session, agentDir, authPath, bundlePath, packageDir)

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

def discoveredPackageDir(cwd: String, executable: Result<&2,&2,FS.Error,String>) -> IO(String):
  match executable:
    case Fail{_}: IO.pure(String,cwd)
    case Done{path}:
      +candidate = Path.join(path,"../..")
      do IO<String>:
        found : Bool <- FS.accessible(Path.join(candidate,"packages/runtime/data/icu78-word-rules.bin"),0)
        return Bool.pick(String,found,candidate,cwd)

# A native build under build/ can find its bundled assets from /proc/self/exe.
# The explicit package directory still wins for other installation layouts.
def resolvedPackageDir(cwd: String, configured: Result<&1,&1,U32 & String,String>) -> IO(String):
  match configured:
    case Done{path}: IO.pure(String,path)
    case Fail{_}:
      do IO<String>:
        executable : Result<&2,&2,FS.Error,String> <- FS.realpath("/proc/self/exe")
        discoveredPackageDir(cwd,executable)

def runConfigured(parsed: Args.Args, mode: AppMode, initial: InitialMessage, +flags: SessionFlags, +cwd: String, +home: String, +url: URL.Context, agentDirLocated: Result<&2, &2, FS.Error, String>, authPath: Result<&2, &2, FS.Error, String>, bundle: Result<&1, &1, U32 & String, String>, packageDir: Result<&1, &1, U32 & String, String>, sessionEnv: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  +agentDir = located(agentDirLocated, Path.join(cwd, ".pi"))
  do IO<Unit>:
    startup : Settings.SettingsManager <- loadSettings(cwd, agentDir)
    selection : Selected() <- createSessionManager(flags, Paths.Environment{cwd, home, url}, cwd, sessionDirectory(flagSessionDir(flags), sessionEnv, home, cwd, Result.default(&2, &2, Paths.Error, Maybe<&2, String>, Settings.getSessionDir(Paths.Environment{cwd, home, url}, startup), None{})), agentDir, Path.join(agentDir, "sessions"))
    assets : String <- resolvedPackageDir(cwd,packageDir)
    runSelected(parsed, mode, initial, cwd, selection, flagName(flags), agentDir, located(authPath, Path.join(cwd, "auth.json")), envOr(bundle, "/etc/ssl/certs/ca-certificates.crt"), assets)

def runWithFiles(+parsed: Args.Args, mode: AppMode, stdin: Maybe<&2, String>, messages: List<&2, String>, environment: Paths.Environment, files: Files.ResultOf(Files.ProcessedFiles)) -> IO(Unit):
  match environment files:
    case _ Fail{error}: fail("Error: " ++ fileError(error))
    case Paths.Environment{cwd, home, url} Done{+processed}:
      do IO<Unit>:
        agentDirLocated : Result<&2, &2, FS.Error, String> <- Config.getAgentDir()
        authPath : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
        bundle : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
        packageDir : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_PACKAGE_DIR")
        sessionEnv : Result<&1, &1, U32 & String, String> <- IO.get_env(Config.envSessionDir())
        runConfigured(parsed, mode, buildInitialMessage(stdin, processedText(processed), processedImages(processed), messages), sessionFlags(parsed), cwd, home, url, agentDirLocated, authPath, bundle, packageDir, sessionEnv)

def runInputFiles(parsed: Args.Args,mode: AppMode,stdin: Maybe<&2,String>,messages: List<&2,String>,+environment: Paths.Environment,fileArgs: List<&2,String>) -> IO(Unit):
  match mode fileArgs:
    case Rpc{} _ <> _: fail("Error: @file arguments are not supported in RPC mode")
    case _ args:
      do IO<Unit>:
        files : Files.ResultOf(Files.ProcessedFiles) <- Files.processFileArguments(environment,args,Files.defaults())
        runWithFiles(parsed,mode,stdin,messages,environment,files)

def runWithInput(+parsed: Args.Args, mode: AppMode, stdinTty: Bool, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match parsed environment:
    case _ Fail{_}: fail("Could not resolve the working directory")
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, messages, fileArgs, _, _} Done{Paths.Environment{+cwd, +home, +url}}:
      do IO<Unit>:
        stdin : Maybe<&2, String> <- readPipedStdin(stdinTty)
        runInputFiles(parsed,mode,stdin,messages,Paths.Environment{cwd,home,url},fileArgs)

def runMode(parsed: Args.Args, +mode: AppMode, stdinTty: Bool) -> IO(Unit):
  match mode:
    case Rpc{}:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        runWithInput(parsed,Rpc{},True{},environment)
    case _:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        runWithInput(parsed, mode, stdinTty, environment)

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

type ExportRequest is Data:
  ExportRequest{source: String,output: Maybe<&2,String>}

def firstMessage(messages: List<&2,String>) -> Maybe<&2,String>:
  match messages:
    case Nil{}: None{}
    case first <> _: Some{first}

def exportRequest(parsed: Args.Args) -> Maybe<&2,ExportRequest>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, source, _, _, _, _, _, _, _, _, _, _, _, _, _, messages, _, _, _}:
      match source:
        case None{}: None{}
        case Some{path}: Some{ExportRequest{path,firstMessage(messages)}}

def exported(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Done{path}: IO.print("Exported to: " ++ path)
    case Fail{message}: fail("Error: " ++ message)

def exportAssets(request: ExportRequest, loaded: Result<&2,&2,String,Export.Assets>) -> IO(Unit):
  match request loaded:
    case _ Fail{message}: fail("Error: " ++ message)
    case ExportRequest{source,output} Done{assets}:
      do IO<Unit>:
        result : Result<&2,&2,String,String> <- Export.exportFromFile(assets,source,output)
        exported(result)

def exportLocated(request: ExportRequest,cwd: String,configured: Result<&1,&1,U32 & String,String>) -> IO(Unit):
  do IO<Unit>:
    assetsRoot : String <- resolvedPackageDir(cwd,configured)
    assets : Result<&2,&2,String,Export.Assets> <- Export.loadAssets(Path.join(assetsRoot,"packages/coding-agent/src/core/export-html"))
    exportAssets(request,assets)

def exportCwd(request: ExportRequest,configured: Result<&1,&1,U32 & String,String>,cwd: Result<&2,&2,FS.Error,String>) -> IO(Unit):
  match cwd:
    case Done{path}: exportLocated(request,path,configured)
    case Fail{_}: fail("Error: Could not resolve the working directory")

def exportFile(request: ExportRequest) -> IO(Unit):
  do IO<Unit>:
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    configured : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_BEND_PACKAGE_DIR")
    exportCwd(request,configured,cwd)

def listSearch(parsed: Args.Args) -> Maybe<&2,Maybe<&2,String>>:
  match parsed:
    case Args.Args{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,listModels,_,_,_,_,_,_,_,_}:
      match listModels:
        case None{}: None{}
        case Some{Args.AllModels{}}: Some{None{}}
        case Some{Args.SearchModels{pattern}}: Some{Some{pattern}}

def listed(+runtime: Models.ModelRuntime,store: Auth.CredentialStore,storage: AuthStorage.AuthStorageOwner,transport: Runtime.Transport,search: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    ModelList.listModels(runtime,search)
    Models.dispose(runtime)
    Auth.disposeStore(store)
    AuthStorage.dispose(storage)
    Runtime.disposeTransport(transport)

def listWithStore(transport: Runtime.Transport,storage: AuthStorage.AuthStorageOwner,view: AuthStorage.AuthStorage,search: Maybe<&2,String>) -> IO(Unit):
  match transport:
    case Runtime.Transport{+authorizer,runtime,+fetch}:
      do IO<Unit>:
        +store : Auth.CredentialStore <- AuthStorage.store(view)
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch,Runtime.urlContext())
        anthropic : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch,Runtime.urlContext())
        models : Models.ModelRuntime <- Models.createWithAnthropic(store,oauth,Some{anthropic})
        listed(models,store,storage,Runtime.Transport{authorizer,runtime,fetch},search)

def listBorrowed(transport: Runtime.Transport,pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage,search: Maybe<&2,String>) -> IO(Unit):
  match pair:
    case (owner,view): listWithStore(transport,owner,view,search)

def listWithTransport(transport: Runtime.Transport,path: String,search: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    storage : AuthStorage.AuthStorageOwner <- AuthStorage.create(path)
    listBorrowed(transport,AuthStorage.borrow(storage),search)

def listReady(transport: Runtime.Outcome(Runtime.Transport),authPath: Result<&2,&2,FS.Error,String>,search: Maybe<&2,String>) -> IO(Unit):
  match transport authPath:
    case Fail{error} _: fail(error)
    case Done{transport} Fail{_}:
      do IO<Unit>:
        Runtime.disposeTransport(transport)
        fail("Could not locate the auth file")
    case Done{transport} Done{path}: listWithTransport(transport,path,search)

def listModels(search: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    authPath : Result<&2,&2,FS.Error,String> <- Config.getAuthPath()
    bundle : Result<&1,&1,U32 & String,String> <- IO.get_env("SSL_CERT_FILE")
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(envOr(bundle,"/etc/ssl/certs/ca-certificates.crt"))
    listReady(transport,authPath,search)

def dispatchExport(+parsed: Args.Args,request: Maybe<&2,ExportRequest>,+stdinTty: Bool,stdoutTty: Bool) -> IO(Unit):
  match request:
    case Some{value}: exportFile(value)
    case None{}: runMode(parsed, resolveAppMode(modeOf(parsed), printFlag(parsed), stdinTty, stdoutTty), stdinTty)

def dispatchList(+parsed: Args.Args,search: Maybe<&2,Maybe<&2,String>>,stdinTty: Bool,stdoutTty: Bool) -> IO(Unit):
  match search:
    case Some{pattern}: listModels(pattern)
    case None{}: dispatchExport(parsed,exportRequest(parsed),stdinTty,stdoutTty)

def dispatch(+parsed: Args.Args, help: Bool, version: Bool, invalid: Bool, +stdinTty: Bool, stdoutTty: Bool, flagError: Maybe<&2, String>) -> IO(Unit):
  match help version invalid flagError:
    case True{} _ _ _: IO.print(Args.helpText(Config.appName()))
    case _ True{} _ _: IO.print(Config.version())
    case _ _ True{} _: IO.die(Unit, 1, "")
    case _ _ _ Some{message}: fail(message)
    case _ _ _ None{}: dispatchList(parsed,listSearch(parsed),stdinTty,stdoutTty)

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

def runValues(values: List<&2, String>) -> IO(Unit):
  match values:
    case "auth" <> "login" <> Nil{}: AuthLogin.run()
    case "auth" <> "login" <> "--provider" <> "openai-codex" <> Nil{}: AuthLogin.run()
    case "auth" <> "login" <> _: fail("Usage: pi auth login [--provider openai-codex]")
    case other: run(Args.parseArgs(other))

# upstream cli/setup.ts setupCli and main's offline switch: variables the
# process and every child it spawns see.
def setEnv(name: String, value: String) -> IO(Unit):
  do IO<Unit>:
    set : Result<&1, &1, U32 & String, Unit> <- IO.set_env(name, value)
    return Unit{}

def isTruthyEnvFlag(value: Result<&1, &1, U32 & String, String>) -> Bool:
  match value:
    case Done{+text}: String.eq(text, "1") || String.eq(String.to_lower(text), "true") || String.eq(String.to_lower(text), "yes")
    case Fail{_}: False{}

def hasOffline(values: List<&2, String>) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value, "--offline") || hasOffline(rest)

def offlineMode(offline: Bool) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), offline,
    _ => do IO<Unit>:
      setEnv("PI_OFFLINE", "1")
      setEnv("PI_SKIP_VERSION_CHECK", "1"),
    _ => IO.pure(Unit, Unit{}))(Unit{})

def setupCli(values: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    setEnv("PI_CODING_AGENT", "true")
    setEnv("AI_AGENT", "pi")
    flag : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_OFFLINE")
    offlineMode(hasOffline(values) || isTruthyEnvFlag(flag))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<String> <- IO.args()
    +values : List<&2, String> = shared(raw)
    setupCli(values)
    runValues(values)
