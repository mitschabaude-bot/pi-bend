import Base
import ../../src/api/openai-responses-shared.bend as Shared
import ../../src/api/openai-responses-stream.bend as Driver
import ../../src/api/openai-responses-stream-state.bend as Slots
import ../../src/api/openai-responses-stream-content.bend as Content
import ../../src/api/openai-responses-terminal.bend as Terminal
import ../../src/api/openai-responses-assistant.bend as Replay
import ../../src/types.bend as T
import ../../src/utils/transcript.bend as Transcript
import ./responses-stream.bend as Harness
import ./responses-messages.bend as Fixture
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

def model() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"gpt-5.4", "GPT-5.4", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", True{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(400000), F.fromU32(128000), None{}, None{}, None{}}

def createOutput(id: String) -> T.AssistantMessage<V.Value, Unit>:
  Fixture.assistantJson(Nil{}, "openai-responses", "openai", id, T.Pending{})

def terminalEvent() -> Driver.ResponseStreamEvent:
  Driver.ResponseCompleted{Terminal.Response{Some{"resp_test"}, Some{"completed"}, None{}, Nil{}, None{}, None{}}}

def functionEvents() -> List<&2, Driver.ResponseStreamEvent>:
  Driver.ContentEvent{Slots.Added{0n, Content.FunctionItem{"fc_test", "call_test", "lookup", "", None{}}}} <>
  Driver.ContentEvent{Slots.Changed{0n, Content.ItemDone{Content.FunctionItem{"fc_test", "call_test", "lookup", "{\"value\":\"hello\"}", Some{"dynamic_tools"}}}}} <>
  terminalEvent() <> Nil{}

def customEvents() -> List<&2, Driver.ResponseStreamEvent>:
  Driver.ContentEvent{Slots.Added{0n, Content.CustomItem{"ctc_test", "call_test", "query", Some{""}, None{}}}} <>
  Driver.ContentEvent{Slots.Changed{0n, Content.ItemDone{Content.CustomItem{"ctc_test", "call_test", "query", Some{"hello"}, Some{"dynamic_tools"}}}}} <>
  terminalEvent() <> Nil{}

def successful(execution: Harness.Execution) -> IO(T.AssistantMessage<V.Value, Unit>):
  match execution:
    case Harness.Execution{Driver.RunResult{output, None{}}, _}: IO.pure(T.AssistantMessage<V.Value, Unit>, output)
    case _: IO.die(T.AssistantMessage<V.Value, Unit>, 1, "unexpected Responses stream failure")

def execute(events: List<&2, Driver.ResponseStreamEvent>, properties: Maybe<&2, R.Record<String>>) -> IO(T.AssistantMessage<V.Value, Unit>):
  do IO<T.AssistantMessage<V.Value, Unit>>:
    result : Harness.Execution <- Harness.executeWithGrammar(events, Harness.NoHooks{}, None{}, properties, createOutput("gpt-5.4"), model())
    successful(result)

def absentError(message: T.AssistantMessage<V.Value, Unit>) -> Bool:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, None{}, _, _, _}: True{}
    case _: False{}

def sameNamespace(actual: Maybe<&2, String>, expected: Maybe<&2, String>) -> Bool:
  match actual expected:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def firstTool(blocks: List<&2, T.AssistantContent<V.Value>>, id: String, name: String, arguments: V.Value, namespace: Maybe<&2, String>) -> Bool:
  match blocks:
    case T.AssistantToolCall{T.ToolCall{a, b, c, _, d}} <> _: String.eq(a, id) && String.eq(b, name) && V.equal(c, arguments) && sameNamespace(d, namespace)
    case _: False{}

def messageTool(message: T.AssistantMessage<V.Value, Unit>, id: String, name: String, arguments: V.Value, namespace: Maybe<&2, String>) -> Bool:
  match message:
    case T.AssistantMessage{blocks, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: firstTool(blocks, id, name, arguments, namespace)

def payload(key: String, value: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{key, V.Text{value}} <> Nil{}}}

def identity(value: V.Value) -> V.Value: value

def replay(output: T.AssistantMessage<V.Value, Unit>, properties: Maybe<&2, R.Record<String>>) -> IO(Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>):
  options = {Shared.ConvertResponsesMessagesOptions{None{}, properties, None{}, None{}, None{}, None{}} : Shared.ConvertResponsesMessagesOptions}
  context = Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, T.Assistant{output} <> Nil{}, None{}})
  Shared.convertResponsesMessagesWith(~V.Value, ~V.Value, ~Unit, ~Unit, ~Unit, ~identity, ~identity, ~Shared.conversionClock, model(), context, "openai" <> Nil{}, Some{options})

def callMatches(call: Replay.Call, id: String, name: String) -> Bool:
  match call:
    case Replay.Call{Some{itemId}, callId, toolName, Some{namespace}}: String.eq(itemId, id) && String.eq(callId, "call_test") && String.eq(toolName, name) && String.eq(namespace, "dynamic_tools")
    case _: False{}

def replayItems(items: List<&2, Shared.ResponseInputItem>, +custom: Bool) -> Bool:
  match items custom:
    case Shared.AssistantInput{Replay.FunctionCall{call, arguments}} <> _ False{}: callMatches(call, "fc_test", "lookup") && String.eq(arguments, "{\"value\":\"hello\"}")
    case Shared.AssistantInput{Replay.CustomToolCall{call, input}} <> _ True{}: callMatches(call, "ctc_test", "query") && String.eq(input, "hello")
    case _ <> rest _: replayItems(rest, custom)
    case Nil{} _: False{}

def replayMatches(result: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>, custom: Bool) -> Bool:
  match result:
    case Done{items}: replayItems(items, custom)
    case Fail{_}: False{}
