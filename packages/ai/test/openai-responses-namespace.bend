import Base
import ../src/api/openai-responses-shared.bend as C
import ../src/types.bend as T
import ./api/responses-named.bend as Fixture
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as Assert

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
    dropsNamespaces()
    ordinary()
