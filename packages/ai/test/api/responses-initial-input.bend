import Base
import ../../src/types.bend as T
import ../../src/api/openai-responses-stream.bend as Stream
import ./responses-stream.bend as Harness
import ./responses-stream-contracts.bend as Fixture
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/json-parse.bend as Json
import ../../../runtime/test/schema.bend as Assert

def makeModel() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"gpt-test", "GPT Test", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", False{}, None{}, T.InputText{} <> T.InputImage{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def inputs() -> List<&2, Stream.ResponseStreamEvent>:
  Stream.ContentEvent{Stream.Added{F.fromU32(0), Stream.CustomItem{"ctc_1", "call_1", "sample_tool", Some{"a"}, None{}}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.CustomDelta{"b"}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.CustomDone{"abc"}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.ItemDone{Stream.CustomItem{"ctc_1", "call_1", "sample_tool", Some{"abc"}, None{}}}}} <>
  Stream.ResponseCompleted{Stream.Response{None{}, Some{"completed"}, None{}, Nil{}, Some{Stream.ResponseUsage{Some{F.fromU32(1)}, Some{F.fromU32(1)}, None{}, None{}, None{}, Some{F.fromU32(2)}}}, None{}}} <> Nil{}

def finalMessage(message: T.AssistantMessage<V.Value, Unit>) -> Bool:
  match message:
    case T.AssistantMessage{T.AssistantToolCall{T.ToolCall{"call_1|ctc_1", "sample_tool", arguments, None{}, None{}}} <> Nil{}, _, _, _, _, _, _, _, _, T.ToolUse{}, _, _, _, _, _}: V.equal(arguments, Fixture.payload("payload", "abc"))
    case _: False{}

def get(value: Maybe<&2, V.Value>, key: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: R.get(V.Value, fields, key)
    case _: None{}

def firstArguments(content: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match content:
    case Some{V.ArrayValue{head <> _}}: get(Some{head}, "arguments")
    case _: None{}

type Observation is Data:
  Observation{starts: List<&2, V.Value>, deltas: List<&2, String>}

def startArgument(value: Maybe<&2, V.Value>, state: Observation) -> Observation:
  match value state:
    case Some{arguments} Observation{starts, deltas}: Observation{arguments <> starts, deltas}
    case None{} state: state

def deltaText(value: Maybe<&2, V.Value>, state: Observation) -> Observation:
  match value state:
    case Some{V.Text{text}} Observation{starts, deltas}: Observation{starts, text <> deltas}
    case _ state: state

def capture(kind: Maybe<&2, V.Value>, +event: Maybe<&2, V.Value>, state: Observation) -> Observation:
  match kind:
    case Some{V.Text{"toolcall_start"}}: startArgument(firstArguments(get(get(event, "partial"), "content")), state)
    case Some{V.Text{"toolcall_delta"}}: deltaText(get(event, "delta"), state)
    case _: state

# Trace entries are immutable emission snapshots. Walking the harness's reverse
# trace and prepending matching entries reconstructs source emission order.
def observations(trace: List<&2, V.Value>, state: Observation) -> Observation:
  match trace:
    case Nil{}: state
    case +head <> tail: observations(tail, capture(get(get(Some{head}, "emit"), "type"), get(Some{head}, "emit"), state))

def parsedDelta(value: Result<&2, &2, Json.Error, V.Value>) -> Bool:
  match value:
    case Done{arguments}: V.equal(arguments, Fixture.payload("payload", "abc"))
    case Fail{_}: False{}

def matchesObservation(state: Observation) -> Bool:
  match state:
    case Observation{start <> Nil{}, deltas}: V.equal(start, Fixture.payload("payload", "a")) && parsedDelta(Json.parse(String.join(deltas, "")))
    case _: False{}

def matches(execution: Harness.Execution) -> Bool:
  match execution:
    case Harness.Execution{Stream.RunResult{output, None{}}, Harness.Capture{_, _, _, _, trace}}: finalMessage(output) && matchesObservation(observations(trace, Observation{Nil{}, Nil{}}))
    case _: False{}

def run() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- Harness.executeWithGrammar(inputs(), Harness.NoHooks{}, None{}, Some{R.Record{R.Property{"sample_tool", "payload"} <> Nil{}}}, Fixture.createOutput("gpt-test"), makeModel())
    Assert.assertion(matches(result), "initial argument snapshot, final tool call, stop reason and concatenated JSON deltas")
