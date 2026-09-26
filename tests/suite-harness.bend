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

type ToolSpec is Data:
  ToolSpec{name: String, kind: ToolKind}

type ToolEnv is Data:
  ToolEnv{session: R.Ref<Maybe<&2, Session.AgentSession>>, kind: ToolKind}

def textOf(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
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
        sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(session, Session.CustomMessageInput{"subagent-reply", Ai.UserText{"subagent replied"}, True{}, None{}}, Session.SendMessageOptions{Some{False{}}, None{}})
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

def textSchema() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Json.field("text", Json.object(Json.field("type", Json.text("string"), Nil{})), Nil{})), Nil{})))

def emptySchema() -> V.Value: Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Nil{}), Nil{})))

def schemaOf(kind: ToolKind) -> V.Value:
  match kind:
    case Echo{_}: textSchema()
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

def harnessLoadout(+tools: List<&2, Tools.Tool()>) -> Runtime.Loadout:
  Runtime.Loadout{promptSections(), tools, Nil{}, Nil{}, None{}, Nil{}, None{}, tools}

def builtTools(built: Built) -> List<&2, Tools.Tool()>:
  match built:
    case Built{tools, _}: tools

def builtExecutes(built: Built) -> List<&2, Tools.Execute()>:
  match built:
    case Built{_, executes}: executes

def createHarness(+dir: String, agentDir: String, specs: List<&2, ToolSpec>, setup: Reg.Setup) -> IO(Harness):
  do IO<Harness>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +built : Built <- buildTools(ref, specs)
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    stored : Session.Session() <- H.requireSession(created)
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(dir, agentDir, Settings.options())
    +value : Reg.Fixture <- Reg.fixtureWithLoadout(stored, dir, H.settingsOf(loaded), setup, harnessLoadout(builtTools(built)))
    R.write(Maybe<&2, Session.AgentSession>, ref, Some{Reg.sessionOf(value)})
    return Harness{value, ref, builtExecutes(built)}

def sessionOf(harness: Harness) -> Session.AgentSession:
  match harness:
    case Harness{fixture, _, _}: Reg.sessionOf(fixture)

def cleanup(harness: Harness) -> IO(Unit):
  match harness:
    case Harness{fixture, ref, executes}:
      do IO<Unit>:
        found : Maybe<&2, Session.AgentSession> <- R.dispose(Maybe<&2, Session.AgentSession>, ref)
        Reg.teardown(fixture)
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
    sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Session.CustomMessageInput{"note", Ai.UserText{"hello"}, True{}, Some{Json.object(Json.field("a", V.Number{U32.to_f64(1)}, Nil{}))}}, Session.sendDefaults())
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

def run(args: List<String>) -> IO(Unit):
  match args:
    case "custom_order" <> dir <> agentDir <> Nil{}: customOrder(dir, agentDir)
    case "bash_recorded" <> dir <> agentDir <> Nil{}: bashRecorded(dir, agentDir)
    case "bash_abort" <> dir <> agentDir <> Nil{}: bashAbort(dir, agentDir)
    case "bash_abort_all" <> dir <> agentDir <> Nil{}: bashAbortAll(dir, agentDir)
    case "aborted_assistant" <> dir <> agentDir <> Nil{}: abortedAssistant(dir, agentDir)
    case "custom_during_tool" <> dir <> agentDir <> second <> Nil{}: customDuringTool(dir, agentDir, second)
    case _: IO.die(Unit, 1, "usage: suite-harness <scenario> <dir> <agentDir> [arguments]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
