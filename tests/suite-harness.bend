import Base
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/child-process.bend as Child
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/coding-agent/src/core/bash-executor.bend as BashExec
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/session-json.bend as SessionJson
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
import ./agent-session.bend as H
import ./regressions.bend as Reg

# The port of upstream test/suite/harness.ts (createHarness): an AgentSession
# over tests/regressions.bend's faux provider, an in-memory session, the
# settings of the scenario's agent directory, a system prompt (upstream's
# test resource loader) and the scenario's tools, all active (upstream
# baseToolsOverride). Every session event is printed as a JSON line, as
# upstream's `harness.events`. tests/regressions_check.py reads them.

# Tools
# -----
# Tool behaviors the suites use. Echo returns its `text` argument after a
# prefix; Notify sends a custom message without triggering a turn while it
# runs (#8537's background task); Stub is never called.
type ToolKind is Data:
  Echo{prefix: String}
  Notify{}
  Throws{message: String}
  Records{}
  Gated{started: Chan(Unit), release: Chan(Unit)}
  NoContent{}

type ToolSpec is Data:
  ToolSpec{name: String, kind: ToolKind}

type ToolEnv is Data:
  ToolEnv{session: R.Ref<Maybe<&2, Session.AgentSession>>, kind: ToolKind}

def textOf(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def valueArgument(params: V.Value) -> String:
  match params:
    case V.ObjectValue{record}: textOf(Rec.get(V.Value, record, "value"))
    case _: ""

def textArgument(params: V.Value) -> String:
  match params:
    case V.ObjectValue{record}: textOf(Rec.get(V.Value, record, "text"))
    case _: ""

def textResult(+text: String, details: V.Value) -> Tools.Output():
  Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, Some{Tools.RawDetails{details}}, None{}, None{}}}

def notified(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(session, Ext.CustomMessageInput{"subagent-reply", Ai.UserText{"subagent replied"}, True{}, None{}}, Ext.SendMessageOptions{Some{False{}}, None{}})
        return Unit{}

def executeTool(env: ToolEnv, input: Tools.Input()) -> IO(Tools.Output()):
  match env input:
    case ToolEnv{_, Echo{prefix}} T.ToolExecutionInput{_, +params, _, _}:
      +text = textArgument(params)
      IO.pure(Tools.Output(), textResult(prefix ++ text, Json.object(Json.field("text", Json.text(text), Nil{}))))
    case ToolEnv{session, Notify{}} _:
      do IO<Tools.Output()>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, session)
        notified(found)
        return textResult("tool done", Json.object(Nil{}))
    case ToolEnv{_, Throws{message}} _: IO.pure(Tools.Output(), Fail{Tools.failure(message)})
    case ToolEnv{_, NoContent{}} _: IO.pure(Tools.Output(), Done{T.AgentToolResult{Nil{}, Some{Tools.RawDetails{Json.object(Nil{})}}, None{}, None{}}})
    case ToolEnv{_, Gated{started, release}} _:
      do IO<Tools.Output()>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return textResult("released", Json.object(Nil{}))
    case ToolEnv{_, Records{}} T.ToolExecutionInput{_, +params, _, _}:
      +value = valueArgument(params)
      do IO<Tools.Output()>:
        IO.print("{\"type\":\"executed\",\"value\":" ++ Decode.quote(value) ++ "}")
        return textResult(value, Json.object(Json.field("value", Json.text(value), Nil{})))

def textSchema() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Json.field("text", Json.object(Json.field("type", Json.text("string"), Nil{})), Nil{})), Nil{})))

def emptySchema() -> V.Value: Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Nil{}), Nil{})))

def valueSchema() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Json.field("value", Json.object(Json.field("type", Json.text("string"), Nil{})), Nil{})), Nil{})))

def schemaOf(kind: ToolKind) -> V.Value:
  match kind:
    case Echo{_}: textSchema()
    case Throws{_}: textSchema()
    case Records{}: valueSchema()
    case Gated{_, _}: emptySchema()
    case NoContent{}: emptySchema()
    case Notify{}: emptySchema()

type Built is Data:
  Built{tools: List<&2, Tools.Tool()>, executes: List<&2, Tools.Execute()>}

def withTool(tool: Tools.Tool(), execute: Tools.Execute(), built: Built) -> Built:
  match built:
    case Built{tools, executes}: Built{tool <> tools, execute <> executes}

def buildTools(+session: R.Ref<Maybe<&2, Session.AgentSession>>, specs: List<&2, ToolSpec>) -> IO(Built):
  match specs:
    case Nil{}: IO.pure(Built, Built{Nil{}, Nil{}})
    case ToolSpec{+name, +kind} <> rest:
      do IO<Built>:
        +execute : Tools.Execute() <- C.create(~ToolEnv, ~Tools.Input(), ~Tools.Output(), ~executeTool, ToolEnv{session, kind})
        built : Built <- buildTools(session, rest)
        return withTool(T.AgentTool{name, name, schemaOf(kind), None{}, name, None{}, execute, None{}, None{}}, execute, built)

def disposeExecutes(executes: List<&2, Tools.Execute()>) -> IO(Unit):
  match executes:
    case Nil{}: IO.pure(Unit, Unit{})
    case execute <> rest:
      do IO<Unit>:
        C.dispose(Tools.Input(), Tools.Output(), execute)
        disposeExecutes(rest)

# Harness
# -------

type Harness is Data:
  Harness{fixture: Reg.Fixture, session: R.Ref<Maybe<&2, Session.AgentSession>>, executes: List<&2, Tools.Execute()>}

def promptSections() -> Rec.Record<String>: Rec.set(String, Rec.new(String), "base", "You are the suite harness assistant.")

def harnessLoadout(+tools: List<&2, Tools.Tool()>, runner: Maybe<&2, Runner.ExtensionRunner>) -> Runtime.Loadout:
  Runtime.Loadout{promptSections(), tools, Nil{}, Nil{}, runner, Nil{}, None{}, tools}

# upstream createTestExtensionsResult: the inline extensions load into a
# runtime whose runner shares the session's model runtime.
def extensionLoadout(runtime: Maybe<&2, Ext.ExtensionRuntime()>, +cwd: String, +tools: List<&2, Tools.Tool()>, models: Models.ModelRuntime) -> IO(Runtime.Loadout):
  match runtime:
    case None{}: IO.pure(Runtime.Loadout, harnessLoadout(tools, None{}))
    case Some{loaded}:
      do IO<Runtime.Loadout>:
        runner : Runner.ExtensionRunner <- Runner.create(loaded, cwd, models)
        return harnessLoadout(tools, Some{runner})

def loadErrorLines(errors: List<&2, Ext.LoadError>) -> IO(Unit):
  match errors:
    case Nil{}: IO.pure(Unit, Unit{})
    case Ext.LoadError{path, error} <> rest:
      do IO<Unit>:
        IO.print("{\"type\":\"load_error\",\"path\":" ++ Decode.quote(path) ++ ",\"error\":" ++ Decode.quote(error) ++ "}")
        loadErrorLines(rest)

def loadedRuntime(extensions: List<&1, Ext.InlineExtension>) -> IO(Maybe<&2, Ext.ExtensionRuntime()>):
  match extensions:
    case Nil{}: IO.pure(Maybe<&2, Ext.ExtensionRuntime()>, None{})
    case more:
      do IO<Maybe<&2, Ext.ExtensionRuntime()>>:
        +runtime : Ext.ExtensionRuntime() <- Loader.createExtensionRuntime()
        errors : List<&2, Ext.LoadError> <- Loader.loadExtensionFactories(runtime, more)
        loadErrorLines(errors)
        return Some{runtime}

def builtTools(built: Built) -> List<&2, Tools.Tool()>:
  match built:
    case Built{tools, _}: tools

def builtExecutes(built: Built) -> List<&2, Tools.Execute()>:
  match built:
    case Built{_, executes}: executes

# upstream createHarness({ tools, extensionFactories }): `ref` receives the
# session once it exists, for tools and handlers that act on it.
# `seed` is appended to the session first (upstream tests append to
# harness.sessionManager and load the agent from buildSessionContext());
# `others` are further faux models (upstream `models`).
def createHarnessFull(+dir: String, agentDir: String, specs: List<&2, ToolSpec>, setup: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&1, Ext.InlineExtension>, seed: List<&2, Session.Message()>, others: List<&2, Ai.Model<Ai.JsonValue>>) -> IO(Harness):
  do IO<Harness>:
    +runtime : Maybe<&2, Ext.ExtensionRuntime()> <- loadedRuntime(extensions)
    +built : Built <- buildTools(ref, specs)
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    empty : Session.Session() <- H.requireSession(created)
    stored : Session.Session() <- Reg.seeded(seed, empty)
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(dir, agentDir, Settings.options())
    +value : Reg.Fixture <- Reg.fixtureModels(stored, dir, H.settingsOf(loaded), setup, others, models => extensionLoadout(runtime, dir, builtTools(built), models))
    R.write(Maybe<&2, Session.AgentSession>, ref, Some{Reg.sessionOf(value)})
    return Harness{value, ref, builtExecutes(built)}

def createHarnessWith(+dir: String, agentDir: String, specs: List<&2, ToolSpec>, setup: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&1, Ext.InlineExtension>) -> IO(Harness):
  createHarnessFull(dir, agentDir, specs, setup, ref, extensions, Nil{}, Nil{})

def createHarness(+dir: String, agentDir: String, specs: List<&2, ToolSpec>, setup: Reg.Setup) -> IO(Harness):
  do IO<Harness>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    createHarnessWith(dir, agentDir, specs, setup, ref, Nil{})

def harnessFixture(harness: Harness) -> Reg.Fixture:
  match harness:
    case Harness{fixture, _, _}: fixture

def sessionOf(harness: Harness) -> Session.AgentSession:
  match harness:
    case Harness{fixture, _, _}: Reg.sessionOf(fixture)

def disposeRunner(runner: Maybe<&2, Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}: Runner.dispose(found)

def cleanup(harness: Harness) -> IO(Unit):
  match harness:
    case Harness{+fixture, ref, executes}:
      do IO<Unit>:
        found : Maybe<&2, Session.AgentSession> <- R.dispose(Maybe<&2, Session.AgentSession>, ref)
        runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(Reg.sessionOf(fixture))
        Reg.teardown(fixture)
        disposeRunner(runner)
        disposeExecutes(executes)

# Reports
# -------

# upstream sessionManager.getEntries(): each entry's type, with a message
# entry's role.
def roleOf(message: Session.Message()) -> String:
  match message:
    case T.LlmMessage{Ai.System{_}}: "system"
    case T.LlmMessage{Ai.User{_}}: "user"
    case T.LlmMessage{Ai.Assistant{_}}: "assistant"
    case T.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case T.CustomMessage{_}: "custom"

def entryShape(entry: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>) -> V.Value:
  match entry:
    case S.SessionMessageEntry{_, message}: Json.object(Json.field("type", Json.text("message"), Json.field("role", Json.text(roleOf(message)), Nil{})))
    case S.CustomMessageEntry{_, _, _, _, _}: Json.object(Json.field("type", Json.text("custom_message"), Nil{}))
    case S.Compaction{_}: Json.object(Json.field("type", Json.text("compaction"), Nil{}))
    case _: Json.object(Json.field("type", Json.text("other"), Nil{}))

def entryShapes(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: entryShape(entry) <> entryShapes(rest)

def reportEntries(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    H.printed(Done{Json.object(Json.field("type", Json.text(label), Json.field("entries", V.ArrayValue{entryShapes(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))}, Nil{})))})

def reportBranch(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    +branch : List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>> = Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>, S.getBranch(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{})
    H.printed(Done{Json.object(Json.field("type", Json.text("branch"), Json.field("entries", V.ArrayValue{entryShapes(branch)}, Nil{})))})

def prompted(+session: Session.AgentSession, +text: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    H.reportPrompt(result)

def echoCall(+id: String, +text: String) -> Reg.Reply:
  Reg.Call{id, "echo", Json.object(Json.field("text", Json.text(text), Nil{})), "{\"text\":" ++ Decode.quote(text) ++ "}"}

def setup(replies: List<&2, Reg.Reply>) -> Reg.Setup: Reg.Setup{replies, Nil{}, H.fauxModel()}

# suite/agent-session-bash-persistence.test.ts
# ---------------------------------------------

# "persists user, assistant, toolResult, and custom messages in order"
def customOrder(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, [ToolSpec{"echo", Echo{"echo:"}}], setup([echoCall("call_echo", "hello"), Reg.Text{"done"}]))
    sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Ext.CustomMessageInput{"note", Ai.UserText{"hello"}, True{}, Some{Json.object(Json.field("a", V.Number{U32.to_f64(1)}, Nil{}))}}, Session.sendDefaults())
    H.reportOutcome("sent", sent)
    prompted(sessionOf(harness), "start")
    reportEntries("entries", sessionOf(harness))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "does not emit message_end for bash execution messages"
def bashRecorded(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Nil{}, setup(Nil{}))
    IO.print("{\"type\":\"recording\"}")
    Session.recordBashResult(sessionOf(harness), "echo hi", H.hiResult(), None{})
    IO.print("{\"type\":\"recorded\"}")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "cancels running bash commands with abortBash": the operation rejects
# ("aborted") once its signal is aborted.
def ExecResult() -> Data: Result<&2, &2, Bash.OperationError, Maybe<&2, U32>>

def untilSignalled(fuel: Nat, +signal: Maybe<&2, Reg.Signal()>) -> IO(Bool):
  match fuel:
    case 0n: IO.pure(Bool, False{})
    case 1n+rest:
      do IO<Bool>:
        aborted : Bool <- Child.parentAborted(signal)
        Bool.pick(Unit -> IO(Bool), aborted, _ => IO.pure(Bool, True{}), _ => IO.bind(Unit, Bool, IO.sleep(1), _ => untilSignalled(rest, signal)))(Unit{})

def rejectOnAbort(entered: Chan(Unit), input: Bash.BashExecutionInput) -> IO(ExecResult()):
  match input:
    case Bash.BashExecutionInput{_, _, _, signal, _, _}:
      do IO<ExecResult()>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        aborted : Bool <- untilSignalled(10000n, signal)
        return Fail{Bash.Operation{"aborted"}}

def bashInBackground(session: Session.AgentSession, operations: Bash.BashOperations, +done: Chan(H.BashOutcome())) -> IO(Unit):
  do IO<Unit>:
    result : H.BashOutcome() <- Session.executeBash(session, "sleep", None{}, Session.BashOptions{None{}, None{}, Some{operations}})
    sent : Bool <- Chan.send(H.BashOutcome(), done, result)
    R.requireSent(sent)

def bashAbort(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Nil{}, setup(Nil{}))
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    exec : C.Callback<Bash.BashExecutionInput, ExecResult()> <- C.create(~Chan(Unit), ~Bash.BashExecutionInput, ~ExecResult(), ~rejectOnAbort, entered)
    +operations : Bash.BashOperations = Bash.BashOperations{exec}
    IO.spawn(Unit, bashInBackground(sessionOf(harness), operations, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, entered)
    H.reportBashState(sessionOf(harness), "running")
    Session.abortBash(sessionOf(harness))
    finished : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done)
    H.reportReceived("aborted", finished)
    H.reportBashState(sessionOf(harness), "after_abort")
    Bash.disposeOperations(operations)
    Chan.close(Unit, entered)
    Chan.close(H.BashOutcome(), done)
    cleanup(harness)

# "aborts all active bash executions": both invocations are held; abortBash
# runs before either finishes.
def bashAbortAll(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Nil{}, setup(Nil{}))
    +entered1 : Chan(Unit) <- Chan.new(Unit, 1)
    +release1 : Chan(Unit) <- Chan.new(Unit, 1)
    +entered2 : Chan(Unit) <- Chan.new(Unit, 1)
    +release2 : Chan(Unit) <- Chan.new(Unit, 1)
    +done1 : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    +done2 : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    +first : Bash.BashOperations <- H.heldOperations(H.Hold{"first", entered1, release1})
    +second : Bash.BashOperations <- H.heldOperations(H.Hold{"second", entered2, release2})
    IO.spawn(Unit, H.bashInBackground(sessionOf(harness), "first", first, done1))
    began1 : Maybe<&1, Unit> <- Chan.recv(Unit, entered1)
    IO.spawn(Unit, H.bashInBackground(sessionOf(harness), "second", second, done2))
    began2 : Maybe<&1, Unit> <- Chan.recv(Unit, entered2)
    Session.abortBash(sessionOf(harness))
    sent1 : Bool <- Chan.send(Unit, release1, Unit{})
    finished1 : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done1)
    sent2 : Bool <- Chan.send(Unit, release2, Unit{})
    finished2 : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done2)
    H.reportReceived("first", finished1)
    H.reportReceived("second", finished2)
    H.reportBashState(sessionOf(harness), "after_abort")
    Bash.disposeOperations(first)
    Bash.disposeOperations(second)
    Chan.close(Unit, entered1)
    Chan.close(Unit, release1)
    Chan.close(Unit, entered2)
    Chan.close(Unit, release2)
    Chan.close(H.BashOutcome(), done1)
    Chan.close(H.BashOutcome(), done2)
    cleanup(harness)

# "persists aborted assistant messages": the reply waits after its first
# chunk until the run is aborted.
def abortedAssistant(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +harness : Harness <- createHarness(dir, agentDir, Nil{}, setup([Reg.Interrupted{Reg.repeated(20000n), started}]))
    IO.spawn(Unit, Reg.promptLater(sessionOf(harness), "hi", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    Session.abort(sessionOf(harness))
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, done)
    H.reportFinished(finished)
    Reg.reportPersisted(sessionOf(harness))
    cleanup(harness)
    Chan.close(Unit, started)
    Chan.close(Result<&2, &2, String, Unit>, done)

# suite/regressions/8537-custom-message-tool-result-ordering.test.ts
# -----------------------------------------------------------------
# The wait tool sends a custom message (triggerTurn: false) while it runs.
def customDuringTool(+dir: String, agentDir: String, +second: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, [ToolSpec{"wait", Notify{}}], setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"done"}, Reg.Text{"second turn"}]))
    prompted(sessionOf(harness), "hi")
    H.reportMessages(sessionOf(harness))
    reportBranch(sessionOf(harness))
    Bool.pick(Unit -> IO(Unit), String.eq(second, "-"), _ => IO.pure(Unit, Unit{}), _ => IO.bind(Unit, Unit, prompted(sessionOf(harness), second), _ => H.reportMessages(sessionOf(harness))))(Unit{})
    cleanup(harness)

# Extensions
# ----------
# Inline extensions (upstream extensionFactories): each factory subscribes
# handlers through the ExtensionAPI. Handlers print what upstream's tests
# collect in arrays.

def Handled(-R: Data) -> Data: Result<&2, &2, String, Maybe<&2, R>>

def nothing(-R: Data) -> IO(Handled(R)): IO.pure(Handled(R), Done{None{}})

def registered(result: Result<&2, &2, String, Loader.Unsubscribe>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}

def subscribe(api: Ext.ExtensionAPI, handler: Ext.EventHandler) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, handler)
    return registered(result)

def both(first: Result<&2, &2, String, Unit>, second: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: second

def inline(+name: String, factory: Ext.ExtensionFactory()) -> Ext.InlineExtension: Ext.InlineExtension{name, factory, False{}}

def print(+kind: String, fields: List<&2, Rec.Property<V.Value>>) -> IO(Unit):
  H.printed(Done{Json.object(Json.field("type", Json.text(kind), fields))})

# #3982: message_end replaces the assistant's cost total with 0.123.
def costOverride(usage: Ai.Usage) -> Ai.Usage:
  match usage:
    case Ai.Usage{input, output, cacheRead, cacheWrite, a, b, total, Ai.UsageCost{i, o, r, w, _}}: Ai.Usage{input, output, cacheRead, cacheWrite, a, b, total, Ai.UsageCost{i, o, r, w, F64.div(U32.to_f64(123), U32.to_f64(1000))}}

def withCost(message: Session.Message()) -> Maybe<&2, Session.Message()>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}: Some{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, costOverride(usage), stop, e, f, g, h, time}}}}
    case _: None{}

def costHandler(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: IO.pure(Handled(Ext.MessageEndEventResult), Done{Some{Ext.MessageEndEventResult{withCost(message)}}})

def costFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~costHandler, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def messageEndCost(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Nil{}, setup([Reg.Text{"hello"}]), ref, [inline("cost", costFactory)])
    prompted(sessionOf(harness), "hi")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #1717/#2113: a message_end handler that yields for assistant messages.
def isAssistant(message: Session.Message()) -> Bool:
  match message:
    case T.LlmMessage{Ai.Assistant{_}}: True{}
    case _: False{}

def slowEnd(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: Bool.pick(Unit -> IO(Handled(Ext.MessageEndEventResult)), isAssistant(message), _ => IO.bind(Unit, Handled(Ext.MessageEndEventResult), IO.sleep(20), _ => nothing(Ext.MessageEndEventResult)), _ => nothing(Ext.MessageEndEventResult))(Unit{})

def slowEndFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~slowEnd, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def echoCalls(texts: List<&2, String>, +index: Nat) -> List<&2, Ai.ToolCall<V.Value>>:
  match texts:
    case Nil{}: Nil{}
    case +text <> rest: Ai.ToolCall{"call_echo_" ++ Nat.show(index), "echo", Json.object(Json.field("text", Json.text(text), Nil{})), None{}, None{}} <> echoCalls(rest, index + 1n)

def settledOrder(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"echo", Echo{""}}], setup([Reg.Calls{echoCalls(["one", "two"], 1n)}, Reg.Text{"done"}]), ref, [inline("slow-end", slowEndFactory)])
    prompted(sessionOf(harness), "run tools")
    reportBranch(sessionOf(harness))
    cleanup(harness)

# ... and a tool_call handler that reads the session branch.
def branchRoles(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        +stored : Session.Session() <- Session.sessionOf(session)
        +branch : List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>> = Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>, S.getBranch(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{})
        print("roles_at_tool_call", Json.field("entries", V.ArrayValue{entryShapes(branch)}, Nil{}))

def rolesAtToolCall(env: R.Ref<Maybe<&2, Session.AgentSession>>, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  do IO<Handled(Ext.ToolCallEventResult)>:
    found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, env)
    branchRoles(found)
    nothing(Ext.ToolCallEventResult)

def rolesFactory(ref: R.Ref<Maybe<&2, Session.AgentSession>>, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~rolesAtToolCall, ref)
    subscribe(api, Ext.OnToolCall{handler})

def toolCallSettled(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"echo", Echo{""}}], setup([echoCall("call_echo", "hello"), Reg.Text{"done"}]), ref, [inline("roles", api => rolesFactory(ref, api))])
    prompted(sessionOf(harness), "run tool")
    cleanup(harness)

# #5998: a tool_call handler blocks every call and asks to terminate.
def blockAll(env: Unit, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  IO.pure(Handled(Ext.ToolCallEventResult), Done{Some{Ext.ToolCallEventResult{Some{True{}}, Some{"Blocked by terminating policy"}, Some{True{}}}}})

def blockFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~blockAll, Unit{})
    subscribe(api, Ext.OnToolCall{handler})

def blockedTerminate(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"echo", Throws{"tool should have been blocked"}}], setup([echoCall("call_echo", "hello"), Reg.Text{"should not run"}]), ref, [inline("terminate", blockFactory)])
    prompted(sessionOf(harness), "hi")
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #8935: preflight records each call and aborts at the second; tool_result
# records its calls.
def preflight(env: Unit, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ToolCallEvent{_, _, input}, ctx}:
      +value = valueArgument(input)
      do IO<Handled(Ext.ToolCallEventResult)>:
        print("preflight", Json.field("value", Json.text(value), Nil{}))
        Bool.pick(Unit -> IO(Unit), String.eq(value, "second"), _ => Ctx.abort(ctx), _ => IO.pure(Unit, Unit{}))(Unit{})
        nothing(Ext.ToolCallEventResult)

def resultHook(env: Unit, call: Ext.HandlerCall<Ext.ToolResultEvent>) -> IO(Handled(Ext.ToolResultEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ToolResultEvent{id, _, _, _, _, _, _}, _}:
      do IO<Handled(Ext.ToolResultEventResult)>:
        print("result_hook", Json.field("toolCallId", Json.text(id), Nil{}))
        nothing(Ext.ToolResultEventResult)

def preflightFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    calls : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~preflight, Unit{})
    results : Ext.ExtensionHandler(Ext.ToolResultEvent, Ext.ToolResultEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolResultEvent>, ~Handled(Ext.ToolResultEventResult), ~resultHook, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnToolCall{calls})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnToolResult{results})
    return both(first, second)

def preflightFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): preflightFactoryWith(api)

def writeCall(+id: String, +value: String) -> Ai.ToolCall<V.Value>:
  Ai.ToolCall{id, "external_write", Json.object(Json.field("value", Json.text(value), Nil{})), None{}, None{}}

def preflightAbort(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"external_write", Records{}}], setup([Reg.Calls{[writeCall("call_first", "first"), writeCall("call_second", "second")]}]), ref, [inline("preflight", preflightFactory)])
    prompted(sessionOf(harness), "run both writes")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #6363: agent_end and agent_settled handlers; the second extension queues
# one follow-up from agent_end.
def logEnd(env: Unit, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Handled(Unit)):
  do IO<Handled(Unit)>:
    print("extension_event", Json.field("event", Json.text("agent_end"), Nil{}))
    nothing(Unit)

def logSettled(env: Unit, call: Ext.HandlerCall<Ext.AgentSettledEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{_, ctx}:
      do IO<Handled(Unit)>:
        idle : Bool <- Ctx.isIdle(ctx)
        print("extension_event", Json.field("event", Json.text("agent_settled"), Json.field("idle", V.Boolean{idle}, Nil{})))
        nothing(Unit)

def settledFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    ended : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Handled(Unit), ~logEnd, Unit{})
    settled : Ext.ExtensionHandler(Ext.AgentSettledEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentSettledEvent>, ~Handled(Unit), ~logSettled, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentEnd{ended})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentSettled{settled})
    return both(first, second)

def settledFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): settledFactoryWith(api)

type FollowUpEnv is Data:
  FollowUpEnv{api: Ext.ExtensionAPI, queued: R.Ref<Bool>}

def followUpOnce(env: FollowUpEnv, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Handled(Unit)):
  match env:
    case FollowUpEnv{api, queued}:
      do IO<Handled(Unit)>:
        already : Bool <- R.modify(Bool, Bool, queued, previous => (True{}, previous))
        Bool.pick(Unit -> IO(Unit), already, _ => IO.pure(Unit, Unit{}), _ => IO.bind(Result<&2, &2, String, Unit>, Unit, Loader.sendUserMessage(api, Ai.UserText{"status follow-up"}, Some{Ext.UserFollowUp{}}), _ => IO.pure(Unit, Unit{})))(Unit{})
        nothing(Unit)

def followUpFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    queued : R.Ref<Bool> <- R.new(Bool, False{})
    ended : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~FollowUpEnv, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Handled(Unit), ~followUpOnce, FollowUpEnv{api, queued})
    settled : Ext.ExtensionHandler(Ext.AgentSettledEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentSettledEvent>, ~Handled(Unit), ~logSettled, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentEnd{ended})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentSettled{settled})
    return both(first, second)

def followUpFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): followUpFactoryWith(api)

def settledAfterRetry(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Nil{}, setup([Reg.Failed{"overloaded_error"}, Reg.Text{"recovered"}]), ref, [inline("settled", settledFactory)])
    prompted(sessionOf(harness), "test")
    cleanup(harness)

def settledAfterFollowUp(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Nil{}, setup([Reg.Text{"first"}, Reg.Text{"second"}]), ref, [inline("follow-up", followUpFactory)])
    prompted(sessionOf(harness), "hello")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# ... and an extension command whose waitForIdle waits for session-level
# settlement. The command context actions are bound as the upstream test's
# bindExtensions({ commandContextActions }) binds them.
def afterIdle(env: Chan(Unit), call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{_, +ctx}:
      do IO<Result<&2, &2, String, Unit>>:
        sent : Bool <- Chan.send(Unit, env, Unit{})
        Ctx.waitForIdle(ctx)
        idle : Bool <- Ctx.isIdle(Ctx.commandContext(ctx))
        print("command_result", Json.field("idle", V.Boolean{idle}, Nil{}))
        return Done{Unit{}}

def afterIdleFactory(started: Chan(Unit), api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.CommandHandler() <- C.create(~Chan(Unit), ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~afterIdle, started)
    Loader.registerCommand(api, "after-idle", Ext.CommandOptions{Some{"Wait for idle"}, None{}, handler})

def waitFound(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}: Session.waitForIdle(session)

def waitIdle(env: R.Ref<Maybe<&2, Session.AgentSession>>, unit: Unit) -> IO(Unit):
  do IO<Unit>:
    found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, env)
    waitFound(found)

def notCancelled(-A: Data, env: Unit, request: A) -> IO(Ctx.SessionChange): IO.pure(Ctx.SessionChange, Ctx.notCancelled())
def nothingToDo(env: Unit, unit: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def commandActions(ref: R.Ref<Maybe<&2, Session.AgentSession>>) -> IO(Ctx.ExtensionCommandContextActions):
  do IO<Ctx.ExtensionCommandContextActions>:
    idle : C.Callback<Unit, Unit> <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Unit, ~Unit, ~waitIdle, ref)
    fresh : C.Callback<Ctx.NewSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NewSessionRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.NewSessionRequest), Unit{})
    forked : C.Callback<Ctx.ForkRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.ForkRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.ForkRequest), Unit{})
    navigated : C.Callback<Ctx.NavigateTreeRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NavigateTreeRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.NavigateTreeRequest), Unit{})
    switched : C.Callback<Ctx.SwitchSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.SwitchSessionRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.SwitchSessionRequest), Unit{})
    reloaded : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothingToDo, Unit{})
    return Ctx.ExtensionCommandContextActions{idle, fresh, forked, navigated, switched, reloaded}

def bindCommands(runner: Maybe<&2, Runner.ExtensionRunner>, actions: Ctx.ExtensionCommandContextActions) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}: Runner.bindCommandContext(found, Some{actions})

def promptInBackground(session: Session.AgentSession, +text: String, done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    H.reportOutcome("prompted", result)
    sent : Bool <- Chan.send(Unit, done, Unit{})
    return Unit{}

def commandWaitsForIdle(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +toolStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +commandStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +promptDone : Chan(Unit) <- Chan.new(Unit, 1)
    +commandDone : Chan(Unit) <- Chan.new(Unit, 1)
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"wait", Gated{toolStarted, release}}], setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]), ref, [inline("after-idle", api => afterIdleFactory(commandStarted, api))])
    actions : Ctx.ExtensionCommandContextActions <- commandActions(ref)
    runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(sessionOf(harness))
    bindCommands(runner, actions)
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", promptDone))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, toolStarted)
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "/after-idle", commandDone))
    entered : Maybe<&1, Unit> <- Chan.recv(Unit, commandStarted)
    IO.sleep(1)
    print("released", Nil{})
    sent : Bool <- Chan.send(Unit, release, Unit{})
    first : Maybe<&1, Unit> <- Chan.recv(Unit, promptDone)
    second : Maybe<&1, Unit> <- Chan.recv(Unit, commandDone)
    cleanup(harness)

# #3688: session_before_tree cancels the navigation.
def cancelTree(env: Unit, call: Ext.HandlerCall<Ext.SessionBeforeTreeEvent>) -> IO(Handled(Ext.SessionBeforeTreeResult)):
  IO.pure(Handled(Ext.SessionBeforeTreeResult), Done{Some{Ext.SessionBeforeTreeResult{Some{True{}}, None{}, None{}, None{}, None{}}}})

def cancelTreeFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeTreeEvent, Ext.SessionBeforeTreeResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionBeforeTreeEvent>, ~Handled(Ext.SessionBeforeTreeResult), ~cancelTree, Unit{})
    subscribe(api, Ext.OnSessionBeforeTree{handler})

def currentLeaf(+session: Session.AgentSession) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return S.getLeafId(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))

def reportLeafValue(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    leaf : Maybe<&2, String> <- currentLeaf(session)
    IO.print("{\"type\":\"" ++ label ++ "\",\"leafId\":" ++ H.maybeQuoted(leaf) ++ "}")

def firstEntryId(+session: Session.AgentSession) -> IO(String):
  do IO<String>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return Reg.firstUser(stored)

def treeCancelCompacting(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Nil{}, setup(Nil{}), ref, [inline("cancel-tree", cancelTreeFactory)], [Reg.userMsg("first"), Reg.assistantAt("reply", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero()), Reg.userMsg("second")], Nil{})
    reportLeafValue("before", sessionOf(harness))
    +target : String <- firstEntryId(sessionOf(harness))
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(harness), target, Session.noSummary())
    Reg.reportTreeNavigation(result)
    H.reportCompacting(sessionOf(harness))
    reportLeafValue("after", sessionOf(harness))
    cleanup(harness)

# #9178: a navigation waits in session_before_tree while a second one runs.
def waitingTree(env: H.Gate, call: Ext.HandlerCall<Ext.SessionBeforeTreeEvent>) -> IO(Handled(Ext.SessionBeforeTreeResult)):
  do IO<Handled(Ext.SessionBeforeTreeResult)>:
    H.holdAt(Some{env})
    nothing(Ext.SessionBeforeTreeResult)

def waitingTreeFactory(gate: H.Gate, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeTreeEvent, Ext.SessionBeforeTreeResult) <- C.create(~H.Gate, ~Ext.HandlerCall<Ext.SessionBeforeTreeEvent>, ~Handled(Ext.SessionBeforeTreeResult), ~waitingTree, gate)
    subscribe(api, Ext.OnSessionBeforeTree{handler})

def navigateLater(session: Session.AgentSession, +targetId: String, done: Chan(Reg.Navigated)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(session, targetId, Session.noSummary())
    sent : Bool <- Chan.send(Reg.Navigated, done, Reg.Navigated{result})
    return Unit{}

def assistantIdAt(+session: Session.AgentSession, +index: Nat) -> IO(String):
  do IO<String>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return Reg.targetIn(stored, "assistant:" ++ Nat.show(index))

def treeWaiting(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Reg.Navigated) <- Chan.new(Reg.Navigated, 1)
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Nil{}, setup(Nil{}), ref, [inline("waiting-tree", api => waitingTreeFactory(H.Gate{started, release}, api))], [Reg.userMsg("first user"), Reg.assistantAt("first assistant", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero()), Reg.userMsg("second user"), Reg.assistantAt("second assistant", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero())], Nil{})
    reportLeafValue("original", sessionOf(harness))
    +firstTarget : String <- assistantIdAt(sessionOf(harness), 1n)
    +secondTarget : String <- firstEntryId(sessionOf(harness))
    print("targets", Json.field("first", Json.text(firstTarget), Json.field("second", Json.text(secondTarget), Nil{})))
    IO.spawn(Unit, navigateLater(sessionOf(harness), firstTarget, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(harness), secondTarget, Session.noSummary())
    Reg.reportTreeNavigation(second)
    reportLeafValue("during", sessionOf(harness))
    sent : Bool <- Chan.send(Unit, release, Unit{})
    first : Maybe<&1, Reg.Navigated> <- Chan.recv(Reg.Navigated, done)
    Reg.reportNavigated(first)
    reportLeafValue("final", sessionOf(harness))
    cleanup(harness)

# suite/agent-session-compaction-model-overrides.test.ts
# ------------------------------------------------------
# History of two 400-character exchanges whose assistant usage reports
# `total` input tokens (upstream seedHistory).
def padded(+label: String, +fill: String) -> String: label ++ String.repeat(fill, Nat.sub(400n, String.length(label)))

def seededUsage(+total: U32) -> Ai.Usage:
  Ai.Usage{U32.to_f64(total), Reg.zero(), Reg.zero(), Reg.zero(), None{}, None{}, U32.to_f64(total), Ai.UsageCost{Reg.zero(), Reg.zero(), Reg.zero(), Reg.zero(), Reg.zero()}}

def seedHistory(+total: U32, +now: F64) -> List<&2, Session.Message()>:
  [Reg.userAt(padded("old", "x"), Reg.before(now, 2000)), Reg.assistantAt(padded("old", "y"), Ai.Stop{}, seededUsage(total), Reg.before(now, 1000)), Reg.userAt(padded("recent", "x"), Reg.before(now, 2000)), Reg.assistantAt(padded("recent", "y"), Ai.Stop{}, seededUsage(total), Reg.before(now, 1000))]

def reasonName(reason: Ext.CompactionReason) -> String:
  match reason:
    case Ext.ManualReason{}: "manual"
    case Ext.ThresholdReason{}: "threshold"
    case Ext.OverflowReason{}: "overflow"

def preparationFields(preparation: Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>) -> List<&2, Rec.Property<V.Value>>:
  match preparation:
    case Compaction.CompactionPreparation{firstKept, _, _, _, _, _, _, Compaction.CompactionSettings{enabled, reserve, keep}}:
      Json.field("firstKeptEntryId", Json.text(firstKept), Json.field("settings", Json.object(Json.field("enabled", V.Boolean{enabled}, Json.field("reserveTokens", V.Number{reserve}, Json.field("keepRecentTokens", V.Number{keep}, Nil{})))), Nil{}))

def suppliedCompaction(preparation: Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>, +summary: String) -> Compaction.CompactionResult:
  match preparation:
    case Compaction.CompactionPreparation{firstKept, _, _, _, tokensBefore, _, _, _}: Compaction.CompactionResult{summary, firstKept, tokensBefore, None{}, None{}, None{}}

# The handler records each preparation and supplies the compaction.
def supplyCompaction(summary: String, call: Ext.HandlerCall<Ext.SessionBeforeCompactEvent>) -> IO(Handled(Ext.SessionBeforeCompactResult)):
  match call:
    case Ext.HandlerCall{Ext.SessionBeforeCompactEvent{+preparation, _, _, reason, _, _}, _}:
      do IO<Handled(Ext.SessionBeforeCompactResult)>:
        print("preparation", Json.field("reason", Json.text(reasonName(reason)), preparationFields(preparation)))
        return Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{suppliedCompaction(preparation, summary)}}}}

def supplyFactory(summary: String, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeCompactEvent, Ext.SessionBeforeCompactResult) <- C.create(~String, ~Ext.HandlerCall<Ext.SessionBeforeCompactEvent>, ~Handled(Ext.SessionBeforeCompactResult), ~supplyCompaction, summary)
    subscribe(api, Ext.OnSessionBeforeCompact{handler})

def reportSeeded(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    print("seeded", Json.field("userIds", V.ArrayValue{Reg.texts(H.userIds(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))))}, Nil{}))

def compactionShapes(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case S.Compaction{S.CompactionEntry{_, summary, keep, _, _, _, _, _}} <> rest: Json.object(Json.field("summary", Json.text(summary), Json.field("firstKeptEntryId", Json.text(keep), Nil{}))) <> compactionShapes(rest)
    case _ <> rest: compactionShapes(rest)

def reportCompactions(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    print("compactions", Json.field("entries", V.ArrayValue{compactionShapes(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))}, Nil{}))

def overrideReplies(+path: String) -> List<&2, Reg.Reply>:
  match path:
    case "manual": Nil{}
    case "overflow": [Reg.Failed{"prompt is too long"}, Reg.Text{"recovered"}]
    case "post-run": [Reg.Text{String.repeat("z", 8000n)}]
    case _: [Reg.Text{"done"}]

def compactOrPrompt(+path: String, +session: Session.AgentSession) -> IO(Unit):
  match path:
    case "manual":
      do IO<Unit>:
        result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(session, None{})
        H.reportCompact(result)
    case _: prompted(session, "continue")

def compactionOverride(+dir: String, agentDir: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Nil{}, Reg.Setup{overrideReplies(path), Nil{}, Reg.sizedModel(4000, 16384)}, ref, [inline("supply", api => supplyFactory("compacted history", api))], seedHistory(Bool.pick(U32, String.eq(path, "pre-prompt"), 2500, 650), now), Nil{})
    reportSeeded(sessionOf(harness))
    compactOrPrompt(path, sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    cleanup(harness)

# "passes resolved budgets to built-in %s summarization": no extension; the
# summary request's output cap is printed with the request.
def compactionBudget(+dir: String, agentDir: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +replies : List<&2, Reg.Reply> = Bool.pick(List<&2, Reg.Reply>, String.eq(path, "manual"), [Reg.Text{"built-in summary"}], [Reg.Text{"built-in summary"}, Reg.Text{"done"}])
    +harness : Harness <- createHarnessFull(dir, agentDir, Nil{}, Reg.Setup{replies, Nil{}, Reg.sizedModel(4000, 3000)}, ref, Nil{}, seedHistory(2500, now), Nil{})
    reportSeeded(sessionOf(harness))
    compactOrPrompt(Bool.pick(String, String.eq(path, "manual"), "manual", "prompt"), sessionOf(harness))
    reportCompactions(sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    cleanup(harness)

# "uses the newly selected model without changing ordinary settings".
def reportReserve(+label: String, +session: Session.AgentSession, model: Maybe<&2, Settings.ModelIdentity>) -> IO(Unit):
  do IO<Unit>:
    manager : Settings.SettingsManager <- Session.getSettings(session)
    print(label, Json.field("reserveTokens", V.Number{F.fromU64(Settings.getCompactionReserveTokens(manager, model))}, Nil{}))

def switched(+session: Session.AgentSession, +model: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.setModel(session, model, Session.ModelMutationOptions{True{}})
    H.reportOutcome("set_model", result)

def appendAll(+session: Session.AgentSession, messages: List<&2, Session.Message()>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case message <> rest:
      do IO<Unit>:
        appended : Result<&2, &2, String, Unit> <- Session.appendSessionMessage(session, message)
        appendAll(session, rest)

def reseed(+session: Session.AgentSession, +now: F64) -> IO(Unit):
  do IO<Unit>:
    appendAll(session, seedHistory(2500, now))
    Session.refreshSessionContext(session)

def compactionModelSwitch(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +small : Ai.Model<Ai.JsonValue> = Reg.namedModel("small", 4000, 16384)
    +big : Ai.Model<Ai.JsonValue> = Reg.namedModel("big", 10000, 16384)
    +harness : Harness <- createHarnessFull(dir, agentDir, Nil{}, Reg.Setup{[Reg.Text{"small response"}, Reg.Text{"big response"}], Nil{}, small}, ref, [inline("supply", api => supplyFactory("big model summary", api))], seedHistory(2500, now), [big])
    prompted(sessionOf(harness), "continue on small")
    print("small_done", Nil{})
    reseed(sessionOf(harness), now)
    switched(sessionOf(harness), big)
    prompted(sessionOf(harness), "continue on big")
    reportReserve("reserve", sessionOf(harness), None{})
    switched(sessionOf(harness), small)
    reportReserve("reserve_small", sessionOf(harness), Some{Settings.ModelIdentity{"faux", "small"}})
    cleanup(harness)

# suite/lax-message-content.test.ts: session entries with null or missing
# content become context messages with empty content.
def reportContextMessages(result: Result<&2, &2, S.Error, List<&2, Session.Message()>>) -> IO(Unit):
  match result:
    case Done{messages}: print("context_messages", Json.field("messages", V.ArrayValue{JsonEvent.messages(messages)}, Nil{}))
    case Fail{_}: print("entry_invalid", Nil{})

def reportContextOf(entry: Maybe<&2, S.FileEntry<Unit, Tools.ToolDetails, V.Value>>) -> IO(Unit):
  match entry:
    case Some{S.Entry{value}}: reportContextMessages(S.sessionEntryToContextMessages(Unit, Tools.ToolDetails, V.Value, value))
    case _: print("entry_invalid", Nil{})

def entryMessages(+line: String) -> IO(Unit):
  reportContextOf(SessionJson.parseSessionEntryLine(~Unit, ~Tools.ToolDetails, ~V.Value, ~Session.readUnit, ~Session.readDetails, ~Session.readRaw, line))

# The in-memory cases of lax-message-content with the native value for
# "no content" (an empty list): a tool result without content, a message_end
# replacement without content and a custom message without content.
def withoutContent(message: Session.Message()) -> Maybe<&2, Session.Message()>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}: Some{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Nil{}, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}}
    case _: None{}

def emptyEnd(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: IO.pure(Handled(Ext.MessageEndEventResult), Done{Some{Ext.MessageEndEventResult{withoutContent(message)}}})

def emptyEndFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~emptyEnd, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def laxContent(+dir: String, agentDir: String, +kind: String) -> IO(Unit):
  match kind:
    case "tool":
      do IO<Unit>:
        +harness : Harness <- createHarness(dir, agentDir, [ToolSpec{"web_search", NoContent{}}], setup([Reg.Call{"call_search", "web_search", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]))
        prompted(sessionOf(harness), "search something")
        H.reportMessages(sessionOf(harness))
        Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
        cleanup(harness)
    case "message_end":
      do IO<Unit>:
        +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
        +harness : Harness <- createHarnessWith(dir, agentDir, Nil{}, setup([Reg.Text{"hello"}]), ref, [inline("empty-end", emptyEndFactory)])
        prompted(sessionOf(harness), "hi")
        H.reportMessages(sessionOf(harness))
        cleanup(harness)
    case _:
      do IO<Unit>:
        +harness : Harness <- createHarness(dir, agentDir, Nil{}, setup(Nil{}))
        sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Ext.CustomMessageInput{"test", Ai.UserBlocks{Nil{}}, False{}, None{}}, Session.sendDefaults())
        H.reportMessages(sessionOf(harness))
        cleanup(harness)

# #2023: a follow-up an extension queues with sendUserMessage is raw user
# text, not an extension command.
def recordCommand(env: Unit, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{args, _}:
      do IO<Result<&2, &2, String, Unit>>:
        print("command_run", Json.field("args", Json.text(args), Nil{}))
        return Done{Unit{}}

def testCommandFactory(apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    R.write(Maybe<&2, Ext.ExtensionAPI>, apiRef, Some{api})
    handler : Ext.CommandHandler() <- C.create(~Unit, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~recordCommand, Unit{})
    Loader.registerCommand(api, "testcmd", Ext.CommandOptions{Some{"Test command"}, None{}, handler})

def sendFollowUp(found: Maybe<&2, Ext.ExtensionAPI>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{api}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{"/testcmd queued"}, Some{Ext.UserFollowUp{}})
        H.reportOutcome("sent", result)

def queuedSlashFollowUp(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +apiRef : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +toolStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +harness : Harness <- createHarnessWith(dir, agentDir, [ToolSpec{"wait", Gated{toolStarted, release}}], setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"first turn complete"}, Reg.Text{"queued follow-up handled by model"}]), ref, [inline("testcmd", api => testCommandFactory(apiRef, api))])
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, toolStarted)
    found : Maybe<&2, Ext.ExtensionAPI> <- R.read(Maybe<&2, Ext.ExtensionAPI>, apiRef)
    sendFollowUp(found)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    finished : Maybe<&1, Unit> <- Chan.recv(Unit, done)
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "custom_order" <> dir <> agentDir <> Nil{}: customOrder(dir, agentDir)
    case "bash_recorded" <> dir <> agentDir <> Nil{}: bashRecorded(dir, agentDir)
    case "bash_abort" <> dir <> agentDir <> Nil{}: bashAbort(dir, agentDir)
    case "bash_abort_all" <> dir <> agentDir <> Nil{}: bashAbortAll(dir, agentDir)
    case "aborted_assistant" <> dir <> agentDir <> Nil{}: abortedAssistant(dir, agentDir)
    case "custom_during_tool" <> dir <> agentDir <> second <> Nil{}: customDuringTool(dir, agentDir, second)
    case "message_end_cost" <> dir <> agentDir <> Nil{}: messageEndCost(dir, agentDir)
    case "settled_order" <> dir <> agentDir <> Nil{}: settledOrder(dir, agentDir)
    case "tool_call_settled" <> dir <> agentDir <> Nil{}: toolCallSettled(dir, agentDir)
    case "blocked_terminate" <> dir <> agentDir <> Nil{}: blockedTerminate(dir, agentDir)
    case "preflight_abort" <> dir <> agentDir <> Nil{}: preflightAbort(dir, agentDir)
    case "settled_retry" <> dir <> agentDir <> Nil{}: settledAfterRetry(dir, agentDir)
    case "settled_follow_up" <> dir <> agentDir <> Nil{}: settledAfterFollowUp(dir, agentDir)
    case "command_waits_for_idle" <> dir <> agentDir <> Nil{}: commandWaitsForIdle(dir, agentDir)
    case "tree_cancel_compacting" <> dir <> agentDir <> Nil{}: treeCancelCompacting(dir, agentDir)
    case "tree_waiting" <> dir <> agentDir <> Nil{}: treeWaiting(dir, agentDir)
    case "entry_messages" <> line <> Nil{}: entryMessages(line)
    case "lax_content" <> dir <> agentDir <> kind <> Nil{}: laxContent(dir, agentDir, kind)
    case "queued_slash_follow_up" <> dir <> agentDir <> Nil{}: queuedSlashFollowUp(dir, agentDir)
    case "compaction_override" <> dir <> agentDir <> path <> Nil{}: compactionOverride(dir, agentDir, path)
    case "compaction_budget" <> dir <> agentDir <> path <> Nil{}: compactionBudget(dir, agentDir, path)
    case "compaction_model_switch" <> dir <> agentDir <> Nil{}: compactionModelSwitch(dir, agentDir)
    case _: IO.die(Unit, 1, "usage: suite-harness <scenario> <dir> <agentDir> [arguments]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
