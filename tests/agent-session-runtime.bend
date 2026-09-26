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
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as T
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/runtime/src/record.bend as Rec
import ./model-runtime-fixture.bend as ModelFixture

# AgentSessionRuntime over the faux-provider fixture: each runtime the
# factory creates is a fresh agent and AgentSession for the requested session
# (suite/agent-session-runtime.test.ts, agent-session-runtime-events.test.ts).

def Services() -> Type: Fx.Fixture
def Runtime() -> Data: Host.AgentSessionRuntime<Services()>

def quotedOr(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, value), "null")

def reasonName(reason: Ext.SessionStartReason) -> String:
  match reason:
    case Ext.StartupStart{}: "startup"
    case Ext.ReloadStart{}: "reload"
    case Ext.NewStart{}: "new"
    case Ext.ResumeStart{}: "resume"
    case Ext.ForkStart{}: "fork"

def startText(start: Maybe<&2, Ext.SessionStartEvent>) -> String:
  match start:
    case None{}: "null"
    case Some{Ext.SessionStartEvent{reason, previous}}: "{\"reason\":\"" ++ reasonName(reason) ++ "\",\"previousSessionFile\":" ++ quotedOr(previous) ++ "}"

def created(+fixture: Fx.Fixture) -> Result<&1, &1, String, Host.Created<Services()>>: Done{Host.Created{fixture, Fx.sessionOf(fixture)}}

def factory(agentDir: String, request: Host.Request) -> IO(Result<&1, &1, String, Host.Created<Services()>>):
  match request:
    case Host.Request{+cwd, +stored, start}:
      do IO<Result<&1, &1, String, Host.Created<Services()>>>:
        IO.print("{\"type\":\"factory\",\"cwd\":" ++ Decode.quote(cwd) ++ ",\"sessionFile\":" ++ quotedOr(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)) ++ ",\"start\":" ++ startText(start) ++ "}")
        +fixture : Fx.Fixture <- Fx.fixture(stored, cwd, agentDir, "answer" <> "again" <> Nil{}, Nil{})
        return created(fixture)

def factoryNoModel(agentDir: String, request: Host.Request) -> IO(Result<&1, &1, String, Host.Created<Services()>>):
  match request:
    case Host.Request{+cwd,+stored,_}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        +fixture : Fx.Fixture <- Fx.fixtureNoModel(stored,cwd,agentDir,"answer" <> "again" <> Nil{},Nil{})
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
    uuids : Uuid.Generator <- Uuid.generator()
    opened : Sessions.Outcome(Session.Session()) <- Session.createSession(uuids, dir, Some{dir}, agentDir, Sessions.noOptions())
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
    uuids : Uuid.Generator <- Uuid.generator()
    opened : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    stored : Session.Session() <- Fx.requireSession(opened)
    +make : Host.Factory(Services()) <- C.create(~String, ~Host.Request, ~Result<&1, &1, String, Host.Created<Services()>>, ~factory, agentDir)
    +free : C.Callback<Services(), Unit> <- C.create(~Unit, ~Services(), ~Unit, ~release, Unit{})
    result : Result<&2, &2, String, Runtime()> <- Host.create(Services(), make, free, agentDir, dir, stored)
    memoryStarted(result)
    C.dispose(Host.Request, Result<&1, &1, String, Host.Created<Services()>>, make)
    C.dispose(Services(), Unit, free)

# agent-session-branching.test.ts over the faux provider (upstream runs it
# live): prompts, the user messages offered for forking, then a fork before
# the chosen one. The factory loads the stored context into the agent, as
# createAgentSessionFromServices does.
def branchFactory(agentDir: String, request: Host.Request) -> IO(Result<&1, &1, String, Host.Created<Services()>>):
  match request:
    case Host.Request{+cwd, +stored, _}:
      do IO<Result<&1, &1, String, Host.Created<Services()>>>:
        +fixture : Fx.Fixture <- Fx.fixture(stored, cwd, agentDir, "one" <> "two" <> "three" <> Nil{}, Nil{})
        Session.refreshSessionContext(Fx.sessionOf(fixture))
        return created(fixture)

def forkValues(messages: List<&2, Session.ForkMessage>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case Session.ForkMessage{entryId, text} <> rest: ("{\"entryId\":" ++ Decode.quote(entryId) ++ ",\"text\":" ++ Decode.quote(text) ++ "}") <> forkValues(rest)

def roleNames(messages: List<&2, Session.Message()>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.System{_}} <> rest: "\"system\"" <> roleNames(rest)
    case T.LlmMessage{Ai.User{_}} <> rest: "\"user\"" <> roleNames(rest)
    case T.LlmMessage{Ai.Assistant{_}} <> rest: "\"assistant\"" <> roleNames(rest)
    case T.LlmMessage{Ai.ToolResult{_}} <> rest: "\"toolResult\"" <> roleNames(rest)
    case _ <> rest: "\"other\"" <> roleNames(rest)

def reportBranchState(+label: String, live: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match live:
    case None{}: IO.print("{\"type\":\"branch_state\",\"label\":" ++ Decode.quote(label) ++ ",\"session\":null}")
    case Some{+session}:
      do IO<Unit>:
        forking : List<&2, Session.ForkMessage> <- Session.getUserMessagesForForking(session)
        current : List<&2, Session.Message()> <- Session.messages(session)
        IO.print("{\"type\":\"branch_state\",\"label\":" ++ Decode.quote(label) ++ ",\"forking\":[" ++ String.join(forkValues(forking), ",") ++ "],\"roles\":[" ++ String.join(roleNames(current), ",") ++ "]}")

def branchState(+label: String, runtime: Runtime()) -> IO(Unit):
  do IO<Unit>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    reportBranchState(label, live)

def promptAll(+runtime: Runtime(), texts: List<&2, String>) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit, Unit{})
    case +text <> rest:
      do IO<Unit>:
        promptCurrent("prompt", runtime, text)
        promptAll(runtime, rest)

def forkAtIndex(messages: List<&2, Session.ForkMessage>, index: Nat) -> String:
  match messages index:
    case Session.ForkMessage{entryId, _} <> _ 0n: entryId
    case _ <> rest 1n+next: forkAtIndex(rest, next)
    case Nil{} _: "missing"

def forkChosen(+runtime: Runtime(), index: Nat, live: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match live:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+session}:
      do IO<Unit>:
        forking : List<&2, Session.ForkMessage> <- Session.getUserMessagesForForking(session)
        result : Result<&2, &2, String, Maybe<&2, String>> <- Host.fork(Services(), runtime, forkAtIndex(forking, index), Host.ForkBefore{})
        reportFork("fork", result)
        reportCurrent("forked", runtime)
        branchState("forked", runtime)

def branchScenario(+runtime: Runtime(), texts: List<&2, String>, index: Nat) -> IO(Unit):
  do IO<Unit>:
    reportCurrent("initial", runtime)
    promptAll(runtime, texts)
    branchState("prompted", runtime)
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    forkChosen(runtime, index, live)
    Host.dispose(Services(), runtime)

def branchStarted(texts: List<&2, String>, index: Nat, result: Result<&2, &2, String, Runtime()>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{runtime}: branchScenario(runtime, texts, index)

def openedWith(uuids: Uuid.Generator, +dir: String, agentDir: String, memory: Bool) -> IO(Sessions.Outcome(Session.Session())):
  match memory:
    case True{}: Session.memorySession(uuids, dir, Sessions.noOptions())
    case False{}: Session.createSession(uuids, dir, Some{dir}, agentDir, Sessions.noOptions())

def branchOpened(+dir: String, agentDir: String, memory: Bool) -> IO(Sessions.Outcome(Session.Session())):
  do IO<Sessions.Outcome(Session.Session())>:
    uuids : Uuid.Generator <- Uuid.generator()
    openedWith(uuids, dir, agentDir, memory)

def branching(+dir: String, +agentDir: String, +kind: String) -> IO(Unit):
  +memory = String.eq(kind, "memory")
  +middle = String.eq(kind, "middle")
  do IO<Unit>:
    opened : Sessions.Outcome(Session.Session()) <- branchOpened(dir, agentDir, memory)
    stored : Session.Session() <- Fx.requireSession(opened)
    +make : Host.Factory(Services()) <- C.create(~String, ~Host.Request, ~Result<&1, &1, String, Host.Created<Services()>>, ~branchFactory, agentDir)
    +free : C.Callback<Services(), Unit> <- C.create(~Unit, ~Services(), ~Unit, ~release, Unit{})
    result : Result<&2, &2, String, Runtime()> <- Host.create(Services(), make, free, agentDir, dir, stored)
    branchStarted(Bool.pick(List<&2, String>, middle, ["Say one", "Say two", "Say three"], [Bool.pick(String, memory, "Say hi", "Say hello")]), Bool.pick(Nat, middle, 1n, 0n), result)
    C.dispose(Host.Request, Result<&1, &1, String, Host.Created<Services()>>, make)
    C.dispose(Services(), Unit, free)

# agent-session-runtime-events.test.ts: every session the factory creates
# loads one inline extension that prints the lifecycle events it sees
# (`ext_event` lines). session_before_switch cancels when `cancelSwitch`;
# session_before_fork cancels once each time `cancelFork` is set.
type EventsEnv is Data:
  EventsEnv{agentDir: String, cancelSwitch: Bool, cancelFork: R.Ref<Bool>, runners: R.Ref<List<&2, Runner.ExtensionRunner>>}

def fileText(file: Maybe<&2, String>) -> String: quotedOr(file)

def shutdownName(reason: Ext.SessionShutdownReason) -> String:
  match reason:
    case Ext.QuitShutdown{}: "quit"
    case Ext.ReloadShutdown{}: "reload"
    case Ext.NewShutdown{}: "new"
    case Ext.ResumeShutdown{}: "resume"
    case Ext.ForkShutdown{}: "fork"

def switchName(reason: Ext.SessionSwitchReason) -> String:
  match reason:
    case Ext.SwitchNew{}: "new"
    case Ext.SwitchResume{}: "resume"

def positionName(position: Ctx.ForkPosition) -> String:
  match position:
    case Ctx.ForkBefore{}: "before"
    case Ctx.ForkAt{}: "at"

def onStart(env: Unit, call: Ext.HandlerCall<Ext.SessionStartEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{Ext.SessionStartEvent{reason, previous}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        IO.print("{\"type\":\"ext_event\",\"event\":\"session_start\",\"reason\":\"" ++ reasonName(reason) ++ "\",\"previousSessionFile\":" ++ fileText(previous) ++ "}")
        return Done{None{}}

def onShutdown(env: Unit, call: Ext.HandlerCall<Ext.SessionShutdownEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{Ext.SessionShutdownEvent{reason, target}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        IO.print("{\"type\":\"ext_event\",\"event\":\"session_shutdown\",\"reason\":\"" ++ shutdownName(reason) ++ "\",\"targetSessionFile\":" ++ fileText(target) ++ "}")
        return Done{None{}}

def onBeforeSwitch(cancel: Bool, call: Ext.HandlerCall<Ext.SessionBeforeSwitchEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeSwitchResult>>):
  match call:
    case Ext.HandlerCall{Ext.SessionBeforeSwitchEvent{reason, target}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeSwitchResult>>>:
        IO.print("{\"type\":\"ext_event\",\"event\":\"session_before_switch\",\"reason\":\"" ++ switchName(reason) ++ "\",\"targetSessionFile\":" ++ fileText(target) ++ "}")
        return Done{Bool.pick(Maybe<&2, Ext.SessionBeforeSwitchResult>, cancel, Some{Ext.SessionBeforeSwitchResult{Some{True{}}}}, None{})}

def onBeforeFork(cancelNext: R.Ref<Bool>, call: Ext.HandlerCall<Ext.SessionBeforeForkEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeForkResult>>):
  match call:
    case Ext.HandlerCall{Ext.SessionBeforeForkEvent{entryId, position}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeForkResult>>>:
        IO.print("{\"type\":\"ext_event\",\"event\":\"session_before_fork\",\"entryId\":" ++ Decode.quote(entryId) ++ ",\"position\":\"" ++ positionName(position) ++ "\"}")
        cancel : Bool <- R.modify(Bool, Bool, cancelNext, value => (False{}, value))
        return Done{Bool.pick(Maybe<&2, Ext.SessionBeforeForkResult>, cancel, Some{Ext.SessionBeforeForkResult{Some{True{}}, None{}}}, None{})}

def subscribedAll(results: List<&2, Result<&2, &2, String, Loader.Unsubscribe>>) -> Result<&2, &2, String, Unit>:
  match results:
    case Nil{}: Done{Unit{}}
    case Fail{error} <> _: Fail{error}
    case Done{_} <> rest: subscribedAll(rest)

def eventsFactory(env: EventsEnv, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case EventsEnv{_, cancelSwitch, cancelFork, _}:
      do IO<Result<&2, &2, String, Unit>>:
        start : Ext.ExtensionHandler(Ext.SessionStartEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionStartEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onStart, Unit{})
        shutdown : Ext.ExtensionHandler(Ext.SessionShutdownEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionShutdownEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onShutdown, Unit{})
        switching : Ext.ExtensionHandler(Ext.SessionBeforeSwitchEvent, Ext.SessionBeforeSwitchResult) <- C.create(~Bool, ~Ext.HandlerCall<Ext.SessionBeforeSwitchEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeSwitchResult>>, ~onBeforeSwitch, cancelSwitch)
        forking : Ext.ExtensionHandler(Ext.SessionBeforeForkEvent, Ext.SessionBeforeForkResult) <- C.create(~R.Ref<Bool>, ~Ext.HandlerCall<Ext.SessionBeforeForkEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeForkResult>>, ~onBeforeFork, cancelFork)
        a : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionBeforeSwitch{switching})
        b : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionShutdown{shutdown})
        c : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionStart{start})
        d : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionBeforeFork{forking})
        return subscribedAll([a, b, c, d])

def runnersOf(env: EventsEnv) -> R.Ref<List<&2, Runner.ExtensionRunner>>:
  match env:
    case EventsEnv{_, _, _, runners}: runners

def disposeRunners(runners: List<&2, Runner.ExtensionRunner>) -> IO(Unit):
  match runners:
    case Nil{}: IO.pure(Unit, Unit{})
    case runner <> rest:
      do IO<Unit>:
        Runner.dispose(runner)
        disposeRunners(rest)

def eventsLoadout(+env: EventsEnv, +cwd: String) -> IO(Runtime.Loadout):
  do IO<Runtime.Loadout>:
    +runtime : Ext.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2, Ext.LoadError> <- Loader.loadExtensionFactories(runtime, [Ext.InlineExtension{"events", api => eventsFactory(env, api), False{}}])
    models : Models.ModelRuntime <- ModelFixture.create(Fx.fauxSources())
    +runner : Runner.ExtensionRunner <- Runner.create(runtime, cwd, models)
    R.modify(List<&2, Runner.ExtensionRunner>, Unit, runnersOf(env), created => (runner <> created, Unit{}))
    return Runtime.Loadout{Rec.new(String), Nil{}, Nil{}, Nil{}, Some{runner}, Nil{}, None{}, Nil{}}

def eventsFactoryCall(env: EventsEnv, request: Host.Request) -> IO(Result<&1, &1, String, Host.Created<Services()>>):
  match env request:
    case EventsEnv{+agentDir, cancelSwitch, cancelFork, runners} Host.Request{+cwd, +stored, _}:
      do IO<Result<&1, &1, String, Host.Created<Services()>>>:
        loadout : Runtime.Loadout <- eventsLoadout(EventsEnv{agentDir, cancelSwitch, cancelFork, runners}, cwd)
        +fixture : Fx.Fixture <- Fx.fixtureWithModel(stored, cwd, agentDir, "one" <> "two" <> "three" <> Nil{}, Nil{}, loadout, Some{Fx.fauxModel()}, Fx.fauxSources())
        return created(fixture)

def phase(name: String, unit: Unit) -> IO(Unit): IO.print("{\"type\":\"phase\",\"name\":" ++ Decode.quote(name) ++ "}")
def phaseRebind(env: Unit, session: Session.AgentSession) -> IO(Unit): phase("rebindSession", Unit{})

def reportChange(+label: String, result: Result<&2, &2, String, Ctx.SessionChange>) -> IO(Unit):
  match result:
    case Done{Ctx.SessionChange{cancelled}}: IO.print("{\"type\":\"change\",\"label\":" ++ Decode.quote(label) ++ ",\"cancelled\":" ++ Bool.pick(String, cancelled, "true", "false") ++ "}")
    case Fail{error}: IO.print("{\"type\":\"change\",\"label\":" ++ Decode.quote(label) ++ ",\"error\":" ++ Decode.quote(error) ++ "}")

def reportForkOutcome(+label: String, result: Result<&2, &2, String, Host.ForkOutcome>) -> IO(Unit):
  match result:
    case Done{Host.ForkOutcome{cancelled, text}}: IO.print("{\"type\":\"change\",\"label\":" ++ Decode.quote(label) ++ ",\"cancelled\":" ++ Bool.pick(String, cancelled, "true", "false") ++ ",\"selectedText\":" ++ quotedOr(text) ++ "}")
    case Fail{error}: IO.print("{\"type\":\"change\",\"label\":" ++ Decode.quote(label) ++ ",\"error\":" ++ Decode.quote(error) ++ "}")

def switchBack(+runtime: Runtime(), file: Maybe<&2, String>) -> IO(Unit):
  match file:
    case None{}: IO.pure(Unit, Unit{})
    case Some{path}:
      do IO<Unit>:
        result : Result<&2, &2, String, Ctx.SessionChange> <- Host.switchSessionCancellable(Services(), runtime, path, None{})
        reportChange("switch", result)
        reportCurrent("switched", runtime)

def firstForkId(live: Maybe<&2, Session.AgentSession>) -> IO(String):
  match live:
    case None{}: IO.pure(String, "missing")
    case Some{session}:
      do IO<String>:
        forking : List<&2, Session.ForkMessage> <- Session.getUserMessagesForForking(session)
        return forkAtIndex(forking, 0n)

def forkEvents(+runtime: Runtime(), +cancelFork: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    live : Maybe<&2, Session.AgentSession> <- Host.session(Services(), runtime)
    +entryId : String <- firstForkId(live)
    IO.print("{\"type\":\"fork_entry\",\"entryId\":" ++ Decode.quote(entryId) ++ "}")
    forked : Result<&2, &2, String, Host.ForkOutcome> <- Host.forkCancellable(Services(), runtime, entryId, Host.ForkBefore{})
    reportForkOutcome("fork", forked)
    reportCurrent("forked", runtime)
    R.write(Bool, cancelFork, True{})
    again : Result<&2, &2, String, Host.ForkOutcome> <- Host.forkCancellable(Services(), runtime, entryId, Host.ForkBefore{})
    reportForkOutcome("fork_cancelled", again)
    R.write(Bool, cancelFork, True{})
    missing : Result<&2, &2, String, Host.ForkOutcome> <- Host.forkCancellable(Services(), runtime, "missing-entry", Host.ForkAt{})
    reportForkOutcome("fork_at_cancelled", missing)

def eventsScenario(+runtime: Runtime(), +kind: String, +cancelFork: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    reportCurrent("initial", runtime)
    IO.print("{\"type\":\"phase\",\"name\":\"prompt\"}")
    promptCurrent("prompt", runtime, "hello")
    reportCurrent("prompted", runtime)
    +first : Maybe<&2, String> <- currentFile(runtime)
    +invalidate : C.Callback<Unit, Unit> <- C.create(~String, ~Unit, ~Unit, ~phase, "beforeSessionInvalidate")
    +rebinder : Host.Rebind() <- C.create(~Unit, ~Session.AgentSession, ~Unit, ~phaseRebind, Unit{})
    Bool.pick(Unit -> IO(Unit), String.eq(kind, "invalidate"), _ => IO.bind(Unit, Unit, Host.setBeforeSessionInvalidate(Services(), runtime, Some{invalidate}), _ => Host.setRebindSession(Services(), runtime, Some{rebinder})), _ => IO.pure(Unit, Unit{}))(Unit{})
    Bool.pick(Unit -> IO(Unit), String.eq(kind, "fork"), _ => forkEvents(runtime, cancelFork), _ => IO.bind(Result<&2, &2, String, Ctx.SessionChange>, Unit, Host.newSessionCancellable(Services(), runtime, None{}), result => IO.bind(Unit, Unit, reportChange("new", result), _ => reportCurrent("new", runtime))))(Unit{})
    Bool.pick(Unit -> IO(Unit), String.eq(kind, "lifecycle"), _ => switchBack(runtime, first), _ => IO.pure(Unit, Unit{}))(Unit{})
    Host.setBeforeSessionInvalidate(Services(), runtime, None{})
    Host.setRebindSession(Services(), runtime, None{})
    IO.print("{\"type\":\"phase\",\"name\":\"dispose\"}")
    Host.dispose(Services(), runtime)
    C.dispose(Unit, Unit, invalidate)
    C.dispose(Session.AgentSession, Unit, rebinder)

def eventsStarted(+kind: String, cancelFork: R.Ref<Bool>, result: Result<&2, &2, String, Runtime()>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{runtime}: eventsScenario(runtime, kind, cancelFork)

def runtimeEvents(+dir: String, +agentDir: String, +kind: String) -> IO(Unit):
  do IO<Unit>:
    uuids : Uuid.Generator <- Uuid.generator()
    opened : Sessions.Outcome(Session.Session()) <- Session.createSession(uuids, dir, Some{dir}, agentDir, Sessions.noOptions())
    stored : Session.Session() <- Fx.requireSession(opened)
    +cancelFork : R.Ref<Bool> <- R.new(Bool, False{})
    +runners : R.Ref<List<&2, Runner.ExtensionRunner>> <- R.new(List<&2, Runner.ExtensionRunner>, Nil{})
    +make : Host.Factory(Services()) <- C.create(~EventsEnv, ~Host.Request, ~Result<&1, &1, String, Host.Created<Services()>>, ~eventsFactoryCall, EventsEnv{agentDir, String.eq(kind, "cancel_switch"), cancelFork, runners})
    +free : C.Callback<Services(), Unit> <- C.create(~Unit, ~Services(), ~Unit, ~release, Unit{})
    result : Result<&2, &2, String, Runtime()> <- Host.create(Services(), make, free, agentDir, dir, stored)
    eventsStarted(kind, cancelFork, result)
    C.dispose(Host.Request, Result<&1, &1, String, Host.Created<Services()>>, make)
    C.dispose(Services(), Unit, free)
    created : List<&2, Runner.ExtensionRunner> <- R.dispose(List<&2, Runner.ExtensionRunner>, runners)
    disposeRunners(created)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "persisted" <> dir <> agentDir <> missing <> Nil{}: persisted(dir, agentDir, missing)
    case "memory" <> dir <> agentDir <> Nil{}: inMemory(dir, agentDir)
    case "branching" <> dir <> agentDir <> kind <> Nil{}: branching(dir, agentDir, kind)
    case "events" <> dir <> agentDir <> kind <> Nil{}: runtimeEvents(dir, agentDir, kind)
    case _: IO.die(Unit, 1, "usage: agent-session-runtime persisted <dir> <agentDir> <missing-cwd-session> | memory <dir> <agentDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
