import Base
import ./agent-session.bend as Fx
import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/agent-session-runtime.bend as Host
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/schema-value.bend as V

# AgentSessionRuntime over the faux-provider fixture: each runtime the
# factory creates is a fresh agent and AgentSession for the requested session
# (suite/agent-session-runtime.test.ts, agent-session-runtime-events.test.ts).

def Services() -> Type: Fx.Fixture
def Runtime() -> Data: Host.AgentSessionRuntime<Services()>

def quotedOr(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, value), "null")

def reasonName(reason: Host.StartReason) -> String:
  match reason:
    case Host.NewStart{}: "new"
    case Host.ResumeStart{}: "resume"
    case Host.ForkStart{}: "fork"

def startText(start: Maybe<&2, Host.SessionStart>) -> String:
  match start:
    case None{}: "null"
    case Some{Host.SessionStart{reason, previous}}: "{\"reason\":\"" ++ reasonName(reason) ++ "\",\"previousSessionFile\":" ++ quotedOr(previous) ++ "}"

def created(+fixture: Fx.Fixture) -> Result<&1, &1, String, Host.Created<Services()>>: Done{Host.Created{fixture, Fx.sessionOf(fixture)}}

def factory(agentDir: String, request: Host.Request) -> IO(Result<&1, &1, String, Host.Created<Services()>>):
  match request:
    case Host.Request{+cwd, +stored, start}:
      do IO<Result<&1, &1, String, Host.Created<Services()>>>:
        IO.print("{\"type\":\"factory\",\"cwd\":" ++ Decode.quote(cwd) ++ ",\"sessionFile\":" ++ quotedOr(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)) ++ ",\"start\":" ++ startText(start) ++ "}")
        +fixture : Fx.Fixture <- Fx.fixture(stored, cwd, agentDir, "answer" <> "again" <> Nil{}, Nil{})
        return created(fixture)

# The session itself is disposed by the host before its services.
def release(env: Unit, fixture: Services()) -> IO(Unit):
  match fixture:
    case Fx.Fixture{+session, listener, stream, validator, converter, registry, Fx.Faux{responses, streams, gates}}:
      do IO<Unit>:
        C.dispose(Session.AgentSessionEvent, Unit, listener)
        Agent.dispose(Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit, Session.agentOf(session))
        StreamFn.dispose(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError, registry)
        Loop.disposeValidation(Tools.ToolError, validator)
        Runtime.disposeConverter(converter)
        C.dispose(Fx.Input(), Fx.Output(), stream)
        remaining : List<&2, String> <- R.dispose(List<&2, String>, responses)
        opened : List<&2, Fx.EventStream()> <- R.dispose(List<&2, Fx.EventStream()>, streams)
        Fx.disposeStreams(opened)
        unused : List<&2, Fx.Gate> <- R.dispose(List<&2, Fx.Gate>, gates)
        return Unit{}

def rebind(env: Unit, session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"rebind\",\"sessionId\":" ++ Decode.quote(Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, stored)) ++ "}")

def parentOf(header: S.SessionHeader) -> Maybe<&2, String>:
  match header:
    case S.SessionHeader{_, _, _, _, parent}: parent

def headerParent(stored: Session.Session()) -> Maybe<&2, String>: parentOf(S.getHeader(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))

def reportLive(+label: String, live: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match live:
    case None{}: IO.print("{\"type\":\"current\",\"label\":" ++ Decode.quote(label) ++ ",\"session\":null}")
    case Some{+session}:
      do IO<Unit>:
        +stored : Session.Session() <- Session.sessionOf(session)
        IO.print("{\"type\":\"current\",\"label\":" ++ Decode.quote(label) ++ ",\"sessionId\":" ++ Decode.quote(Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, stored)) ++ ",\"sessionFile\":" ++ quotedOr(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)) ++ ",\"cwd\":" ++ Decode.quote(Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, stored)) ++ ",\"parentSession\":" ++ quotedOr(headerParent(stored)) ++ ",\"entries\":" ++ Nat.show(List.length(&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>, S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))) ++ "}")

def reportCurrent(+label: String, runtime: Runtime()) -> IO(Unit):
  do IO<Unit>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    reportLive(label, live)

def reportResult(+label: String, result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("{\"type\":\"result\",\"label\":" ++ Decode.quote(label) ++ ",\"ok\":true}")
    case Fail{error}: IO.print("{\"type\":\"result\",\"label\":" ++ Decode.quote(label) ++ ",\"ok\":false,\"error\":" ++ Decode.quote(error) ++ "}")

def promptLive(+label: String, live: Maybe<&2, Session.AgentSession>, text: String) -> IO(Unit):
  match live:
    case None{}: reportResult(label, Fail{"no session"})
    case Some{session}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
        reportResult(label, result)

def promptCurrent(+label: String, runtime: Runtime(), text: String) -> IO(Unit):
  do IO<Unit>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    promptLive(label, live, text)

def fileOf(live: Maybe<&2, Session.AgentSession>) -> IO(Maybe<&2, String>):
  match live:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{session}:
      do IO<Maybe<&2, String>>:
        stored : Session.Session() <- Session.sessionOf(session)
        return Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)

def currentFile(runtime: Runtime()) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    fileOf(live)

def switchTo(+runtime: Runtime(), +label: String, file: Maybe<&2, String>) -> IO(Unit):
  match file:
    case None{}: reportResult(label, Fail{"no file"})
    case Some{path}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Host.switchSession(Services(), runtime, path, None{})
        reportResult(label, result)
        reportCurrent(label, runtime)

def firstEntryId(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> String:
  match entries:
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, _} <> _: id
    case _: "missing"

def storedOf(live: Maybe<&2, Session.AgentSession>) -> IO(Maybe<&2, Session.Session()>):
  match live:
    case None{}: IO.pure(Maybe<&2, Session.Session()>, None{})
    case Some{session}:
      do IO<Maybe<&2, Session.Session()>>:
        stored : Session.Session() <- Session.sessionOf(session)
        return Some{stored}

def idsOf(stored: Maybe<&2, Session.Session()>) -> String & String:
  match stored:
    case None{}: ("missing", "missing")
    case Some{session}:
      +state = Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session)
      (firstEntryId(S.getEntries(Unit, Tools.ToolDetails, V.Value, state)), Maybe.default(&2, String, S.getLeafId(Unit, Tools.ToolDetails, V.Value, state), "missing"))

def currentIds(runtime: Runtime()) -> IO(String & String):
  do IO<String & String>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    stored : Maybe<&2, Session.Session()> <- storedOf(live)
    return idsOf(stored)

def reportFork(+label: String, result: Result<&2, &2, String, Maybe<&2, String>>) -> IO(Unit):
  match result:
    case Done{text}: IO.print("{\"type\":\"result\",\"label\":" ++ Decode.quote(label) ++ ",\"ok\":true,\"selectedText\":" ++ quotedOr(text) ++ "}")
    case Fail{error}: IO.print("{\"type\":\"result\",\"label\":" ++ Decode.quote(label) ++ ",\"ok\":false,\"error\":" ++ Decode.quote(error) ++ "}")

def forkAll(+runtime: Runtime(), +prefix: String, ids: String & String) -> IO(Unit):
  match ids:
    case (first, leaf):
      do IO<Unit>:
        invalid : Result<&2, &2, String, Maybe<&2, String>> <- Host.fork(Services(), runtime, "nope", Host.ForkBefore{})
        reportFork(prefix ++ "fork_invalid", invalid)
        cloned : Result<&2, &2, String, Maybe<&2, String>> <- Host.fork(Services(), runtime, leaf, Host.ForkAt{})
        reportFork(prefix ++ "clone", cloned)
        reportCurrent(prefix ++ "clone", runtime)
        before : Result<&2, &2, String, Maybe<&2, String>> <- Host.fork(Services(), runtime, first, Host.ForkBefore{})
        reportFork(prefix ++ "fork_before", before)
        reportCurrent(prefix ++ "fork_before", runtime)

def forkScenario(+runtime: Runtime(), +prefix: String) -> IO(Unit):
  do IO<Unit>:
    ids : String & String <- currentIds(runtime)
    forkAll(runtime, prefix, ids)

def scenario(+runtime: Runtime(), +dir: String, missing: String) -> IO(Unit):
  do IO<Unit>:
    +rebinder : Host.Rebind() <- C.create(~Unit, ~Session.AgentSession, ~Unit, ~rebind, Unit{})
    Host.setRebindSession(Services(), runtime, Some{rebinder})
    reportCurrent("initial", runtime)
    promptCurrent("first_prompt", runtime, "hello")
    +first : Maybe<&2, String> <- currentFile(runtime)
    created : Result<&2, &2, String, Unit> <- Host.newSession(Services(), runtime, None{})
    reportResult("new", created)
    reportCurrent("new", runtime)
    promptCurrent("second_prompt", runtime, "again")
    +second : Maybe<&2, String> <- currentFile(runtime)
    switchTo(runtime, "resume_first", first)
    parented : Result<&2, &2, String, Unit> <- Host.newSession(Services(), runtime, Some{"parent.jsonl"})
    reportResult("new_parented", parented)
    reportCurrent("new_parented", runtime)
    refused : Result<&2, &2, String, Unit> <- Host.switchSession(Services(), runtime, missing, None{})
    reportResult("missing_cwd", refused)
    reportCurrent("missing_cwd", runtime)
    switchTo(runtime, "resume_second", second)
    forkScenario(runtime, "")
    Host.dispose(Services(), runtime)
    C.dispose(Session.AgentSession, Unit, rebinder)

def started(+dir: String, missing: String, result: Result<&2, &2, String, Runtime()>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{runtime}: scenario(runtime, dir, missing)

def persisted(+dir: String, +agentDir: String, missing: String) -> IO(Unit):
  do IO<Unit>:
    opened : Sessions.Outcome(Session.Session()) <- Session.createSession(dir, Some{dir}, agentDir, Sessions.noOptions())
    stored : Session.Session() <- Fx.requireSession(opened)
    +make : Host.Factory(Services()) <- C.create(~String, ~Host.Request, ~Result<&1, &1, String, Host.Created<Services()>>, ~factory, agentDir)
    +free : C.Callback<Services(), Unit> <- C.create(~Unit, ~Services(), ~Unit, ~release, Unit{})
    result : Result<&2, &2, String, Runtime()> <- Host.create(Services(), make, free, agentDir, dir, stored)
    started(dir, missing, result)
    C.dispose(Host.Request, Result<&1, &1, String, Host.Created<Services()>>, make)
    C.dispose(Services(), Unit, free)

def memoryScenario(+runtime: Runtime()) -> IO(Unit):
  do IO<Unit>:
    reportCurrent("memory_initial", runtime)
    created : Result<&2, &2, String, Unit> <- Host.newSession(Services(), runtime, None{})
    reportResult("memory_new", created)
    reportCurrent("memory_new", runtime)
    promptCurrent("memory_prompt", runtime, "hello")
    forkScenario(runtime, "memory_")
    Host.dispose(Services(), runtime)

def memoryStarted(result: Result<&2, &2, String, Runtime()>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{runtime}: memoryScenario(runtime)

def inMemory(+dir: String, +agentDir: String) -> IO(Unit):
  do IO<Unit>:
    opened : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- Fx.requireSession(opened)
    +make : Host.Factory(Services()) <- C.create(~String, ~Host.Request, ~Result<&1, &1, String, Host.Created<Services()>>, ~factory, agentDir)
    +free : C.Callback<Services(), Unit> <- C.create(~Unit, ~Services(), ~Unit, ~release, Unit{})
    result : Result<&2, &2, String, Runtime()> <- Host.create(Services(), make, free, agentDir, dir, stored)
    memoryStarted(result)
    C.dispose(Host.Request, Result<&1, &1, String, Host.Created<Services()>>, make)
    C.dispose(Services(), Unit, free)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "persisted" <> dir <> agentDir <> missing <> Nil{}: persisted(dir, agentDir, missing)
    case "memory" <> dir <> agentDir <> Nil{}: inMemory(dir, agentDir)
    case _: IO.die(Unit, 1, "usage: agent-session-runtime persisted <dir> <agentDir> <missing-cwd-session> | memory <dir> <agentDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
