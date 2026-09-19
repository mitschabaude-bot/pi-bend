import Base
import ../src/api/openai-responses-shared.bend as C
import ../src/api/openai-responses-content.bend as Content
import ../src/types.bend as T
import ./api/responses-named.bend as Fixture
import ../../runtime/test/schema.bend as Assert

def placeholder(items: List<&2,C.ResponseInputItem>) -> Bool:
  match items:
    case Nil{}: False{}
    case C.FunctionToolOutput{_,Content.TextOutput{"(no tool output)"}} <> _: True{}
    case C.FunctionToolOutput{_,_} <> _: False{}
    case _ <> rest: placeholder(rest)

def run() -> IO(Unit):
  message = Fixture.assistant(Fixture.toolCall("tool-1","bash","command","true",None{}) <> Nil{},"openai-completions","openai","gpt-4o-mini",T.ToolUse{})
  do IO<Unit>:
    items : List<&2,C.ResponseInputItem> <- Fixture.convert(Fixture.model(T.OpenAICompletionsApi{},"openai","gpt-4o-mini"),None{},Fixture.user("Run the command") <> message <> Fixture.result("tool-1","bash","") <> Nil{},"openai" <> "openai-codex" <> "opencode" <> Nil{},None{})
    # Exact equality also excludes the unrelated attached-image placeholder.
    Assert.assertion(placeholder(items),"empty result has text-only no-output placeholder")
    IO.print("PASS uses '(no tool output)' placeholder for empty tool results without images")
