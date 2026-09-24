import Base
import ../src/agent-loop.bend as Completion
import ../src/agent-loop.bend as Execution
import ../src/agent-loop.bend as Call
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/agent-loop.bend as E
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./validated-tool-execution.bend as H
import ./message-events.bend as Test
import ./tool-call-sequential.bend as S
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

def Turn() -> Data: T.AgentTurnContext<Unit, String, String, String>
def Next() -> Data: Completion.NextTurn<Unit, String, String, String>
def Outcome() -> Data: Result<&2, &2, String, Next()>
def Log() -> Data: R.Ref<List<&2, String>>
def Finished() -> Data: Result<&2, &2, String, Maybe<&2, T.AgentTurnDecision>>
def QueueOutput() -> Data: Result<&2, &2, String, H.Messages()>

type Hook is Data:
  Hook{log: Log(), mode: U32, tools: Bool}
type Queue is Data:
  Queue{log: Log(), name: String, mode: U32}
type Recording is Data:
  Recording{log: Log(), failAt: String, tools: Bool}

def log(reference: Log(), entry: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, reference, values => (entry <> values, Unit{}))

def messageNames(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.CustomMessage{text} <> rest: text ++ "|" ++ messageNames(rest)
    case T.LlmMessage{Ai.Assistant{_}} <> rest: "assistant|" ++ messageNames(rest)
    case T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, Some{details}, _, False{}, _}}} <> rest: Bool.pick(String, String.eq(details, "tool"), id, "unexpected") ++ "|" ++ messageNames(rest)
    case _ <> rest: "unexpected|" ++ messageNames(rest)

def resultsMatch(values: List<&2, Ai.ToolResultMessage<String>>, tools: Bool) -> Bool:
  match values tools:
    case Nil{} False{}: True{}
    case Ai.ToolResultMessage{id, name, _, Some{details}, _, False{}, _} <> Nil{} True{}: String.eq(id, "call") && String.eq(name, "echo") && String.eq(details, "tool")
    case _ _: False{}

def snapshot(turn: Turn(), +tools: Bool) -> Bool:
  match turn:
    case T.AgentTurnContext{_, results, T.AgentContext{messages, _}, history}:
      resultsMatch(results, tools) && String.eq(messageNames(messages), Bool.pick(String, tools, "old|assistant|call|", "old|assistant|")) && String.eq(messageNames(history), Bool.pick(String, tools, "prompt|assistant|call|", "prompt|assistant|"))

def decided(mode: U32) -> Finished():
  match mode:
    case 0: Done{None{}}
    case 1: Done{Some{T.EndTurn{}}}
    case _: Fail{"finish failed"}

def finish(environment: Hook, input: T.ToolHookInput<Turn()>) -> IO(Finished()):
  match environment input:
    case Hook{recording, mode, tools} T.ToolHookInput{turn, _}:
      do IO<Finished()>:
        Test.assertion(snapshot(turn, tools), "finishTurn sees both committed histories and ordered tool results")
        log(recording, "finish")
        return decided(mode)

def queued(name: String, mode: U32) -> QueueOutput():
  match mode:
    case 0: Done{Nil{}}
    case 1: Done{T.CustomMessage{name} <> Nil{}}
    case _: Fail{name ++ " failed"}

def queue(environment: Queue, unused: Unit) -> IO(QueueOutput()):
  match environment:
    case Queue{recording, +name, mode}:
      do IO<QueueOutput()>:
        log(recording, name)
        return queued(name, mode)

def eventName(event: H.EventValue(), tools: Bool) -> IO(String):
  match event:
    case T.TurnEnd{_, results}:
      do IO<String>:
        Test.assertion(resultsMatch(results, tools), "turn_end receives ordered tool results")
        return "turn_end"
    case T.AgentEnd{messages}:
      do IO<String>:
        Test.assertion(String.eq(messageNames(messages), Bool.pick(String, tools, "prompt|assistant|call|", "prompt|assistant|")), "agent_end includes exactly the generated history")
        return "agent_end"
    case other: IO.pure(String, S.key(other))

def emit(environment: Recording, event: H.EventValue()) -> IO(E.Emission<String>):
  match environment:
    case Recording{recording, failAt, tools}:
      do IO<E.Emission<String>>:
        +name : String <- eventName(event, tools)
        log(recording, name)
        return E.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{"delivery failed"}, Done{Unit{}})}

def execute(terminate: Bool, input: H.ExecuteInput()) -> IO(H.ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{id, arguments, _, _}:
      do IO<H.ExecuteOutput()>:
        Test.assertion(String.eq(id, "call") && V.equal(arguments, H.field(V.Number{F.fromU32(42)})), "turn tool uses native validated arguments")
        return Done{T.AgentToolResult{Nil{}, Some{"tool"}, None{}, Some{terminate}}}
    case _: IO.die(H.ExecuteOutput(), 1, "unexpected tool input")

def notAborted(unused: Unit, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Bool): IO.pure(Bool, False{})

def content(tools: Bool) -> List<&2, Ai.AssistantContent<V.Value>>:
  match tools:
    case True{}: Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", H.field(V.Text{"42"}), None{}, None{}}} <> Nil{}
    case False{}: Ai.AssistantText{Ai.TextContent{"done", None{}}} <> Nil{}

def check(actual: Outcome(), category: U32, tools: Bool, expectedPending: String, expectedError: String) -> IO(Unit):
  match actual category:
    case Done{Completion.Finished{turn}} 0: Test.assertion(snapshot(turn, tools), "finished turn snapshot")
    case Done{Completion.CompletionContinue{turn, pending}} 1: Test.assertion(snapshot(turn, tools) && String.eq(messageNames(pending), expectedPending), "next-turn snapshot and pending messages stay separate")
    case Fail{error} 2: Test.assertion(String.eq(error, expectedError), "turn failure propagates unchanged")
    case _ _: Test.assertion(False{}, "unexpected turn transition")

def configuration(converter: C.Callback<H.Messages(), H.Converted()>, finishHook: C.Callback<T.ToolHookInput<Turn()>, Finished()>, steering: C.Callback<Unit, QueueOutput()>, followUp: C.Callback<Unit, QueueOutput()>) -> H.Config():
  T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, Some{finishHook}, None{}, None{}, Some{steering}, Some{followUp}, None{}, None{}, None{}}

def scenario(+tools: Bool, terminate: Bool, finishMode: U32, steeringMode: U32, followMode: U32, failAt: String, category: U32, expectedPending: String, expectedError: String, expectedEvents: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +recording : Log() <- R.new(List<&2, String>, Nil{})
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~Bool, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~execute, terminate)
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.convert, Unit{})
    +finishHook : C.Callback<T.ToolHookInput<Turn()>, Finished()> <- C.create(~Hook, ~T.ToolHookInput<Turn()>, ~Finished(), ~finish, Hook{recording, finishMode, tools})
    +steering : C.Callback<Unit, QueueOutput()> <- C.create(~Queue, ~Unit, ~QueueOutput(), ~queue, Queue{recording, "steering", steeringMode})
    +followUp : C.Callback<Unit, QueueOutput()> <- C.create(~Queue, ~Unit, ~QueueOutput(), ~queue, Queue{recording, "follow", followMode})
    +abort : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~notAborted, Unit{})
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~Recording, ~H.EventValue(), ~E.Emission<String>, ~emit, Recording{recording, failAt, tools})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +owners : Call.Owners(String, String) <- Call.newOwners(String, String)
    +zero : F64 = F.fromU32(0)
    +assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{content(tools), "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.Stop{}, None{}, None{}, None{}, None{}, zero}
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{T.CustomMessage{"old"} <> T.LlmMessage{Ai.Assistant{assistant}} <> Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +config : H.Config() = configuration(converter, finishHook, steering, followUp)
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    capture : Call.CallCapture<Unit, String, String, String, Unit> = Call.CallCapture{assistant, config, Some{Abort.signal(Unit, controller)}, validator, abort, emitter, sink, owners, "empty"}
    +execution : Execution.Execution<Unit, String, String, String> <- Execution.executeToolCalls(~Unit, ~String, ~String, ~String, ~Unit, ~S.render, capture, context)
    batch : S.Outcome() <- Execution.executionResult(Unit, String, String, String, execution)
    history : H.Messages() = T.CustomMessage{"prompt"} <> T.LlmMessage{Ai.Assistant{assistant}} <> Nil{}
    result : Outcome() <- Completion.completeTurn(Unit, String, String, String, Unit, assistant, history, config, sink, None{}, batch)
    check(result, category, tools, expectedPending, expectedError)
    Execution.disposeExecution(Unit, String, String, String, execution)
    recorded : List<&2, String> <- R.read(List<&2, String>, recording)
    Test.assertion(S.equal(List.reverse(&2, String, recorded), expectedEvents), "turn completion event/hook/queue order")
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    Call.disposeOwners(String, String, owners)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(T.ToolHookInput<Turn()>, Finished(), finishHook)
    C.dispose(Unit, QueueOutput(), steering)
    C.dispose(Unit, QueueOutput(), followUp)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, abort)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), E.Emission<String>, emitter)
    dropped : List<&2, String> <- R.dispose(List<&2, String>, recording)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, False{}, 0, 0, 0, "", 0, "", "", "finish" <> "turn_end" <> "steering" <> "follow" <> "agent_end" <> Nil{})
    scenario(False{}, False{}, 0, 1, 1, "", 1, "steering|", "", "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(False{}, False{}, 0, 0, 1, "", 1, "follow|", "", "finish" <> "turn_end" <> "steering" <> "follow" <> Nil{})
    scenario(False{}, False{}, 1, 2, 2, "", 0, "", "", "finish" <> "turn_end" <> "agent_end" <> Nil{})
    scenario(False{}, False{}, 2, 0, 0, "", 2, "", "finish failed", "finish" <> Nil{})
    scenario(False{}, False{}, 0, 2, 0, "", 2, "", "steering failed", "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(False{}, False{}, 0, 0, 2, "", 2, "", "follow failed", "finish" <> "turn_end" <> "steering" <> "follow" <> Nil{})
    scenario(False{}, False{}, 0, 0, 0, "turn_end", 2, "", "delivery failed", "finish" <> "turn_end" <> Nil{})
    scenario(False{}, False{}, 0, 0, 0, "agent_end", 2, "", "delivery failed", "finish" <> "turn_end" <> "steering" <> "follow" <> "agent_end" <> Nil{})
    scenario(True{}, False{}, 0, 0, 0, "", 1, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, False{}, 0, 1, 1, "", 1, "steering|", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, False{}, 0, 0, 1, "", 1, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, False{}, 1, 2, 2, "", 0, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "agent_end" <> Nil{})
    scenario(True{}, False{}, 2, 0, 0, "", 2, "", "finish failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> Nil{})
    scenario(True{}, False{}, 0, 2, 0, "", 2, "", "steering failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, False{}, 0, 0, 2, "", 1, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, False{}, 0, 0, 0, "turn_end", 2, "", "delivery failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> Nil{})
    scenario(True{}, False{}, 0, 0, 0, "agent_end", 1, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, True{}, 0, 0, 0, "", 0, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> "follow" <> "agent_end" <> Nil{})
    scenario(True{}, True{}, 0, 1, 1, "", 1, "steering|", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, True{}, 0, 0, 1, "", 1, "follow|", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> "follow" <> Nil{})
    scenario(True{}, True{}, 1, 2, 2, "", 0, "", "", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "agent_end" <> Nil{})
    scenario(True{}, True{}, 2, 0, 0, "", 2, "", "finish failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> Nil{})
    scenario(True{}, True{}, 0, 2, 0, "", 2, "", "steering failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> Nil{})
    scenario(True{}, True{}, 0, 0, 2, "", 2, "", "follow failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> "follow" <> Nil{})
    scenario(True{}, True{}, 0, 0, 0, "turn_end", 2, "", "delivery failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> Nil{})
    scenario(True{}, True{}, 0, 0, 0, "agent_end", 2, "", "delivery failed", "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "finish" <> "turn_end" <> "steering" <> "follow" <> "agent_end" <> Nil{})
    scenario(True{}, False{}, 0, 0, 0, "end:call", 2, "", "delivery failed", "start:call" <> "end:call" <> Nil{})
    IO.print("PASS 28 composed turn completions: histories, turn events, finishTurn, steering, follow-ups and failures")
