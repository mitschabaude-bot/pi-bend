import Base
import ../src/api/openai-responses-shared.bend as C
import ../src/types.bend as T
import ./api/responses-named.bend as Fixture
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as Assert
import ../../runtime/src/schema-value.bend as V
import ./api/responses-stream-contracts.bend as Stream

def absentTerminalError() -> IO(Unit):
  do IO<Unit>:
    output : T.AssistantMessage<V.Value, Unit> <- Stream.execute(Stream.functionEvents(), None{})
    Assert.assertion(Stream.absentError(output), "terminal error message is absent")
    IO.print("PASS omits an absent error message")

def functionNamespace() -> IO(Unit):
  do IO<Unit>:
    +output : T.AssistantMessage<V.Value, Unit> <- Stream.execute(Stream.functionEvents(), None{})
    Assert.assertion(Stream.messageTool(output, "call_test|fc_test", "lookup", Stream.payload("value", "hello"), Some{"dynamic_tools"}), "streamed function namespace and arguments")
    replayed : Result<&2, &2, C.MessageError, List<&2, C.ResponseInputItem>> <- Stream.replay(output, None{})
    Assert.assertion(Stream.replayMatches(replayed, False{}), "function namespace survives public transcript replay")
    IO.print("PASS round-trips a function namespace received only on output_item.done")

def customNamespace() -> IO(Unit):
  +properties = {R.Record{R.Property{"query", "input"} <> Nil{}} : R.Record<String>}
  do IO<Unit>:
    +output : T.AssistantMessage<V.Value, Unit> <- Stream.execute(Stream.customEvents(), Some{properties})
    Assert.assertion(Stream.messageTool(output, "call_test|ctc_test", "query", Stream.payload("input", "hello"), Some{"dynamic_tools"}), "streamed custom namespace and arguments")
    replayed : Result<&2, &2, C.MessageError, List<&2, C.ResponseInputItem>> <- Stream.replay(output, Some{properties})
    Assert.assertion(Stream.replayMatches(replayed, True{}), "custom namespace survives public transcript replay")
    IO.print("PASS round-trips a custom-tool namespace received only on output_item.done")

def targetDropsNamespace(model: T.Model<Unit>) -> IO(Unit):
  message = Fixture.assistant(Fixture.toolCall("call_function|fc_test","lookup","value","hello",Some{"dynamic_tools"}) <> Fixture.toolCall("call_custom|ctc_test","query","input","hello",Some{"dynamic_tools"}) <> Nil{},"openai-responses","openai","gpt-5.4",T.Pending{})
  options = {C.ConvertResponsesMessagesOptions{None{},Some{R.Record{R.Property{"query","input"} <> Nil{}}},None{},None{},None{},None{}} : C.ConvertResponsesMessagesOptions}
  do IO<Unit>:
    +items : List<&2,C.ResponseInputItem> <- Fixture.convert(model,None{},message <> Nil{},"openai" <> Nil{},Some{options})
    Assert.assertion(Fixture.withoutNamespace(Fixture.findCall(items,False{})),"migrated function call exists without a namespace")
    Assert.assertion(Fixture.withoutNamespace(Fixture.findCall(items,True{})),"migrated custom call exists without a namespace")

def dropsNamespaces() -> IO(Unit):
  do IO<Unit>:
    targetDropsNamespace(Fixture.model(T.OpenAIResponsesApi{},"openai","gpt-5.2"))
    targetDropsNamespace(Fixture.model(T.OpenAIResponsesApi{},"azure-openai-responses","gpt-5.4"))
    targetDropsNamespace(Fixture.model(T.OpenAICodexResponsesApi{},"openai-codex","gpt-5.3-codex-spark"))
    IO.print("PASS drops namespaces when the target cannot replay their load items")

def ordinary() -> IO(Unit):
  message = Fixture.assistant(Fixture.toolCall("call_test|fc_test","lookup","value","hello",None{}) <> Nil{},"openai-responses","openai","gpt-5.4",T.Pending{})
  do IO<Unit>:
    items : List<&2,C.ResponseInputItem> <- Fixture.convert(Fixture.model(T.OpenAIResponsesApi{},"openai","gpt-5.4"),None{},message <> Nil{},"openai" <> Nil{},None{})
    Assert.assertion(Fixture.withoutNamespace(Fixture.findCall(items,False{})),"ordinary function call exists without a namespace")
    IO.print("PASS does not add a namespace to ordinary function calls")

def run() -> IO(Unit):
  do IO<Unit>:
    absentTerminalError()
    functionNamespace()
    customNamespace()
    dropsNamespaces()
    ordinary()
