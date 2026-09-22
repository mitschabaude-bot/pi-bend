import Base
import ../src/types.bend as T
import ../src/api/github-copilot-headers.bend as Copilot
import ../src/api/openai-responses.bend as Responses
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ./request-headers.bend as Output

def Message() -> Data: T.Message<Unit, Unit, Unit, Unit>

def blocks(image: Bool) -> List<&2, T.TextImageContent>:
  match image:
    case True{}: T.TextImageText{T.TextContent{"before", None{}}} <> T.TextImageImage{T.ImageContent{"", "image/png"}} <> T.TextImageText{T.TextContent{"after", None{}}} <> Nil{}
    case False{}: T.TextImageText{T.TextContent{"text", None{}}} <> Nil{}

def tool(content: List<&2, T.TextImageContent>) -> Message():
  T.ToolResult{T.ToolResultMessage{"id", "tool", content, None{}, None{}, False{}, F.fromU32(0)}}

def assistant() -> Message():
  +zero = F.fromU32(0)
  T.Assistant{T.AssistantMessage{Nil{}, "openai-responses", "github-copilot", "test", None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}}, T.Stop{}, None{}, None{}, None{}, None{}, zero}}

# s system, u string user, b text-block user, i image user, e empty user,
# t text tool, j image tool, k empty tool, a assistant.
def message(code: U32) -> Message():
  match code:
    case 115: T.System{T.SystemMessage{T.SystemText{"system"}, None{}, None{}, None{}, F.fromU32(0)}}
    case 117: T.User{T.UserMessage{T.UserText{"text"}, F.fromU32(0)}}
    case 98: T.User{T.UserMessage{T.UserBlocks{blocks(False{})}, F.fromU32(0)}}
    case 105: T.User{T.UserMessage{T.UserBlocks{blocks(True{})}, F.fromU32(0)}}
    case 101: T.User{T.UserMessage{T.UserBlocks{Nil{}}, F.fromU32(0)}}
    case 116: tool(blocks(False{}))
    case 106: tool(blocks(True{}))
    case 107: tool(Nil{})
    case _: assistant()

def messages(text: String) -> List<&2, Message()>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{code}, rest}: message(code) <> messages(rest)

def showBool(flag: Bool) -> String:
  match flag:
    case True{}: "true"
    case False{}: "false"

def record(properties: List<&2, R.Property<String>>) -> String:
  match properties:
    case Nil{}: ""
    case R.Property{name, value} <> rest: name ++ "=" ++ value ++ ";" ++ record(rest)

def modelHeaders() -> Maybe<&2, R.Record<String>>:
  Some{R.Record{R.Property{"X-Initiator", "model"} <> Nil{}}}

def callerHeaders(override: Bool) -> Maybe<&2, T.ProviderHeaders()>:
  match override:
    case False{}: None{}
    case True{}: Some{R.Record{R.Property{"X-Initiator", T.PresentValue{"caller"}} <> R.Property{"Copilot-Vision-Request", T.NullValue{}} <> Nil{}}}

def assembled(provider: String, input: List<&2, Message()>, override: Bool) -> String:
  String.join(Output.showProperties(R.entries(T.Nullable<String>, Responses.clientHeaders(Unit, Unit, Unit, Unit, "pi/test", provider, modelHeaders(), T.TranscriptContext{input}, T.OpenAISession{}, Some{"session"}, callerHeaders(override)))), "|")

def run(+input: List<&2, Message()>) -> String:
  Copilot.inferCopilotInitiator(Unit, Unit, Unit, Unit, input) ++ "#" ++ showBool(Copilot.hasCopilotVisionInput(Unit, Unit, Unit, Unit, input)) ++ "#" ++ record(R.entries(String, Copilot.buildCopilotDynamicHeaders(Unit, Unit, Unit, Unit, input, False{}))) ++ "#" ++ record(R.entries(String, Copilot.buildCopilotDynamicHeaders(Unit, Unit, Unit, Unit, input, True{}))) ++ "#" ++ assembled("github-copilot", input, False{}) ++ "#" ++ assembled("github-copilot", input, True{}) ++ "#" ++ assembled("openai", input, False{})

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(messages(head)))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
