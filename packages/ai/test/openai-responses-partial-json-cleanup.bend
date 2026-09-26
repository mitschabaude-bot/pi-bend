import Base
import ../src/api/openai-responses-stream.bend as Stream
import ../src/types.bend as T
import ./api/responses-stream.bend as Harness
import ./api/responses-messages.bend as Fixture
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/openai-responses-partial-json-cleanup.test.ts
# through the public processResponsesStream. The streaming scratch JSON lives
# in the stream state's Function block, not in T.ToolCall, so the persisted
# block and the toolcall_end event carry no partialJson key by construction;
# the checks below read the observable JSON of both. Upstream's reference
# identity `toolCallEnd.toolCall toBe persistedToolCall` is adapted to value
# equality of the two snapshots.
def model() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"gpt-5-mini", "GPT-5 Mini", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", True{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(400000), F.fromU32(128000), None{}, None{}, None{}}

def argumentsJson() -> String: "{\"path\":\"README.md\",\"content\":\"updated\"}"

def functionItem(arguments: String) -> Stream.OutputItem: Stream.FunctionItem{"fc_test", "call_test", "edit", arguments, None{}}

def events() -> List<&2, Stream.ResponseStreamEvent>:
  Stream.ContentEvent{Stream.Added{F.fromU32(0), functionItem("")}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.FunctionDelta{"{\"path\":\"README.md\""}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.FunctionDelta{",\"content\":\"updated\"}"}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.FunctionDone{argumentsJson()}}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.ItemDone{functionItem(argumentsJson())}}} <>
  Stream.ResponseCompleted{Stream.Response{Some{"resp_test"}, Some{"completed"}, None{}, Nil{}, None{}, None{}}} <> Nil{}

def field(value: Maybe<&2, V.Value>, name: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: R.get(V.Value, fields, name)
    case _: None{}

def items(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def isText(value: Maybe<&2, V.Value>, want: String) -> Bool:
  match value:
    case Some{V.Text{text}}: String.eq(text, want)
    case _: False{}

def isToolcallEnd(value: V.Value) -> Bool: isText(field(field(Some{value}, "emit"), "type"), "toolcall_end")

# The first emitted toolcall_end event.
def toolcallEnd(trace: List<&2, V.Value>) -> Maybe<&2, V.Value>:
  match trace:
    case Nil{}: None{}
    case +entry <> rest: Maybe.or(&2, V.Value, Bool.pick(Maybe<&2, V.Value>, isToolcallEnd(entry), field(Some{entry}, "emit"), None{}), toolcallEnd(rest))

def same(left: Maybe<&2, V.Value>, right: Maybe<&2, V.Value>) -> Bool:
  match left right:
    case Some{a} Some{b}: V.equal(a, b)
    case _ _: False{}

def parsedResult(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def parsed(text: String) -> Maybe<&2, V.Value>: parsedResult(Parse.parse(text))

def check(ok: Bool, +name: String, message: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ message))

def verify(+name: String, +report: V.Value) -> IO(Unit):
  +content = items(field(field(Some{report}, "output"), "content"))
  +persisted = List.head(&2, V.Value, content)
  +ended = toolcallEnd(items(field(Some{report}, "trace")))
  do IO<Unit>:
    check(Maybe.is_none(&2, V.Value, field(Some{report}, "error")), name, "the stream failed")
    check(Nat.is_eq(List.length(&2, V.Value, content), 1n), name, "expected one content block")
    check(isText(field(persisted, "type"), "toolCall"), name, "expected a toolCall block")
    check(same(field(persisted, "arguments"), parsed(argumentsJson())), name, "arguments differ")
    check(Maybe.is_none(&2, V.Value, field(persisted, "partialJson")), name, "persisted block keeps partialJson")
    check(Maybe.is_some(&2, V.Value, ended), name, "no toolcall_end event")
    check(same(field(ended, "toolCall"), persisted), name, "toolcall_end carries a different tool call")
    check(Maybe.is_none(&2, V.Value, field(field(ended, "toolCall"), "partialJson")), name, "toolcall_end keeps partialJson")
    IO.print("PASS " ++ name)

def reportOf(execution: Harness.Execution) -> V.Value:
  match execution:
    case Harness.Execution{result, capture}: Harness.resultValue(result, capture)

def run() -> IO(Unit):
  do IO<Unit>:
    execution : Harness.Execution <- Harness.execute(events(), Harness.NoHooks{}, None{}, Fixture.assistantJson(Nil{}, "openai-responses", "openai", "gpt-5-mini", T.Pending{}), model())
    verify("removes partialJson from persisted tool-call blocks at output_item.done", reportOf(execution))

def main() -> IO(Unit): run()
