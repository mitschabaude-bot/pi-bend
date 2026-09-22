import Base
import ../src/api/openai-responses-shared.bend as C
import ../src/types.bend as T
import ./api/responses-named.bend as Fixture
import ../../runtime/test/schema.bend as Assert

def ids(items: List<&2,C.ResponseInputItem>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case C.AssistantInput{C.OutputMessage{id,_,_}} <> rest: id <> ids(rest)
    case _ <> rest: ids(rest)

def exact(values: List<&2,String>) -> Bool:
  match values:
    case "msg_pi_1" <> "msg_pi_1_1" <> Nil{}: True{}
    case _: False{}

def contains(values: List<&2,String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: String.eq(head,value) || contains(rest,value)

def unique(values: List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> +rest: Bool.not(contains(rest,head)) && unique(rest)

def run() -> IO(Unit):
  message = Fixture.assistant(T.AssistantThinking{T.ThinkingContent{"private reasoning",None{},None{}}} <> T.AssistantText{T.TextContent{"visible answer",None{}}} <> Nil{},"anthropic-messages","anthropic","claude-opus-4-8",T.Stop{})
  do IO<Unit>:
    items : List<&2,C.ResponseInputItem> <- Fixture.convert(Fixture.model(T.OpenAICodexResponsesApi{},"openai-codex","gpt-5.5"),Some{"You are concise."},Fixture.user("hello") <> message <> Nil{},"openai" <> "openai-codex" <> "opencode" <> Nil{},None{})
    +messageIds : List<&2,String> = ids(items)
    Assert.assertion(exact(messageIds),"exact fallback IDs after foreign thinking conversion")
    Assert.assertion(unique(messageIds),"fallback message IDs are unique")
    IO.print("PASS generates unique fallback message IDs for multiple text blocks in one assistant turn")
