import Base
import ../src/api/openai-responses-shared.bend as Shared
import ../src/api/openai-responses-stream.bend as Stream
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ./api/responses-stream.bend as Harness
import ./api/responses-messages.bend as Fixture
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# upstream azure-openai-responses-reasoning-replay.test.ts: an Azure model's
# streamed reasoning replays with the encrypted content of output_item.done,
# or of response.completed when output_item.done omitted it.

def model() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"gpt-5-mini", "GPT-5 Mini", T.AzureOpenAIResponsesApi{}, "azure-openai-responses", "https://example.invalid", True{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(400000), F.fromU32(128000), None{}, None{}, None{}}

def withEncrypted(fields: R.Record<V.Value>, encrypted: Maybe<&2, String>) -> R.Record<V.Value>:
  match encrypted:
    case None{}: fields
    case Some{value}: R.set(V.Value, fields, "encrypted_content", V.Text{value})

def reasoning(id: String, encrypted: Maybe<&2, String>) -> Stream.OutputItem:
  Stream.ReasoningItem{withEncrypted(R.Record{R.Property{"type", V.Text{"reasoning"}} <> R.Property{"id", V.Text{id}} <> R.Property{"summary", V.ArrayValue{Nil{}}} <> Nil{}}, encrypted)}

def events(+id: String, done: Maybe<&2, String>, completed: String) -> List<&2, Stream.ResponseStreamEvent>:
  Stream.ContentEvent{Stream.Added{F.fromU32(0), reasoning(id, None{})}} <>
  Stream.ContentEvent{Stream.Changed{F.fromU32(0), Stream.ItemDone{reasoning(id, done)}}} <>
  Stream.ResponseCompleted{Stream.Response{Some{"resp_test"}, Some{"completed"}, None{}, reasoning(id, Some{completed}) <> Nil{}, None{}, None{}}} <> Nil{}

def successful(execution: Harness.Execution) -> IO(T.AssistantMessage<V.Value, Unit>):
  match execution:
    case Harness.Execution{Stream.RunResult{output, None{}}, _}: IO.pure(T.AssistantMessage<V.Value, Unit>, output)
    case _: IO.die(T.AssistantMessage<V.Value, Unit>, 1, "unexpected Responses stream failure")

def identity(value: V.Value) -> V.Value: value

def user(text: String, timestamp: U32) -> T.Message<V.Value, V.Value, Unit, Unit>:
  T.User{T.UserMessage{T.UserText{text}, F.fromU32(timestamp)}}

def getReplayedReasoning(output: T.AssistantMessage<V.Value, Unit>) -> IO(Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>):
  context = Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, user("first", 1) <> T.Assistant{output} <> user("follow-up", 2) <> Nil{}, None{}})
  Shared.convertResponsesMessagesWith(~V.Value, ~V.Value, ~Unit, ~Unit, ~Unit, ~identity, ~identity, ~Shared.conversionClock, model(), context, "azure-openai-responses" <> Nil{}, None{})

def text(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{content}}: content
    case _: "(missing)"

def matches(+fields: R.Record<V.Value>, id: String, encrypted: String) -> Bool:
  String.eq(text(R.get(V.Value, fields, "type")), "reasoning") && String.eq(text(R.get(V.Value, fields, "id")), id) && String.eq(text(R.get(V.Value, fields, "encrypted_content")), encrypted)

def replayed(items: List<&2, Shared.ResponseInputItem>, id: String, encrypted: String) -> Bool:
  match items:
    case Nil{}: False{}
    case Shared.AssistantInput{Shared.ReasoningReplay{V.ObjectValue{fields}}} <> _: matches(fields, id, encrypted)
    case _ <> rest: replayed(rest, id, encrypted)

def verdict(+name: String, id: String, encrypted: String, result: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "FAIL " ++ name ++ ": replay conversion failed")
    case Done{items}: Bool.pick(IO(Unit), replayed(items, id, encrypted), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name))

def run(name: String, +id: String, done: Maybe<&2, String>, +encrypted: String) -> IO(Unit):
  do IO<Unit>:
    execution : Harness.Execution <- Harness.executeWithGrammar(events(id, done, "from-response-completed"), Harness.NoHooks{}, None{}, None{}, Fixture.assistantJson(Nil{}, "azure-openai-responses", "azure-openai-responses", "gpt-5-mini", T.Pending{}), model())
    output : T.AssistantMessage<V.Value, Unit> <- successful(execution)
    result : Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>> <- getReplayedReasoning(output)
    verdict(name, id, encrypted, result)

def main() -> IO(Unit):
  do IO<Unit>:
    run("preserves existing encrypted_content from output_item.done", "rs_done", Some{"from-output-item-done"}, "from-output-item-done")
    run("fills encrypted_content when output_item.done omitted it", "rs_missing", None{}, "from-response-completed")
