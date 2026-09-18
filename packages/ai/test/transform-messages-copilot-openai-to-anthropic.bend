import Base
import ../src/api/transform-messages.bend as Transform
import ../src/api/transform-tool-results.bend as Repair
import ../src/types.bend as Ai
import ../src/utils/model-api.bend as Api
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/test/schema.bend as T

def Messages() -> Data: Repair.Messages(V.Value, V.Value, Unit, Unit)
def Input() -> Data: Transform.NormalizeToolCallIdInput<V.Value, Unit, Unit>
def Output() -> Data: Result<&2, &2, String, String>
def model() -> Ai.Model<Unit>:
  +zero = F.fromU32(0)
  Ai.Model{"claude-sonnet-4.6", "Claude Sonnet 4.6", Ai.AnthropicMessagesApi{}, "github-copilot", "https://api.individual.githubcopilot.com", True{}, None{}, Ai.InputText{} <> Ai.InputImage{} <> Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(16000), None{}, None{}, None{}}
def assistant(content: List<&2, Ai.AssistantContent<V.Value>>, api: String, id: String, reason: Ai.StopReason) -> Ai.AssistantMessage<V.Value, Unit>:
  +zero = F.fromU32(0)
  Ai.AssistantMessage{content, api, "github-copilot", id, None{}, None{}, None{}, None{}, Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, Ai.UsageCost{zero, zero, zero, zero, zero}}, reason, None{}, None{}, None{}, None{}, zero}
def field(key: String, text: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{key, V.Text{text}} <> Nil{}}}
def user(text: String) -> Ai.Message<V.Value, V.Value, Unit, Unit>:
  Ai.User{Ai.UserMessage{Ai.UserText{text}, F.fromU32(0)}}
def tool(id: String, name: String, args: V.Value, signature: Maybe<&2, String>) -> Ai.AssistantContent<V.Value>:
  Ai.AssistantToolCall{Ai.ToolCall{id, name, args, signature, None{}}}
def safeChar(+code: U32) -> U32:
  Bool.pick(U32, (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 95) || U32.is_eq(code, 45), code, 95)
def normalize(limit: Nat, text: String) -> String:
  match limit text:
    case Zero{} _: ""
    case _ SNil{}: ""
    case Succ{rest} SCon{Chr{code}, tail}: SCon{Chr{safeChar(code)}, normalize(rest, tail)}
def normalizeBody(unused: Unit, input: Input()) -> IO(Output()):
  match input:
    case Transform.NormalizeToolCallIdInput{id, target, source}:
      do IO<Output()>:
        T.assertion(String.eq(Api.name(Api.modelApi(Unit, target)), "anthropic-messages"), "normalizer receives target model")
        return Done{normalize(64n, id)}
def success(result: Result<&2, &2, String, Messages()>) -> IO(Messages()):
  match result:
    case Done{messages}: IO.pure(Messages(), messages)
    case Fail{error}: IO.die(Messages(), 1, error)
def transform(messages: Messages()) -> IO(Messages()):
  do IO<Messages()>:
    +normalizer : Transform.Normalizer(V.Value, Unit, Unit, String) <- C.create(~Unit, ~Input(), ~Output(), ~normalizeBody, Unit{})
    result : Result<&2, &2, String, Messages()> <- Transform.transformMessages(~V.Value, ~V.Value, ~Unit, ~Unit, ~Unit, ~String, messages, model(), Some{normalizer})
    C.dispose(Input(), Output(), normalizer)
    success(result)
def assistantBlocks(messages: Messages()) -> List<&2, Ai.AssistantContent<V.Value>>:
  match messages:
    case Nil{}: Nil{}
    case Ai.Assistant{Ai.AssistantMessage{blocks, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> _: blocks
    case _ <> rest: assistantBlocks(rest)
def thinkingConverted(content: List<&2, Ai.AssistantContent<V.Value>>) -> Bool:
  match content:
    case Ai.AssistantText{Ai.TextContent{a, None{}}} <> Ai.AssistantText{Ai.TextContent{b, None{}}} <> Nil{}: String.eq(a, "Let me think about this...") && String.eq(b, "Hi there!")
    case _: False{}
def signatureRemoved(content: List<&2, Ai.AssistantContent<V.Value>>) -> Bool:
  match content:
    case Ai.AssistantToolCall{Ai.ToolCall{id, name, args, None{}, None{}}} <> Nil{}: String.eq(id, "call_123") && String.eq(name, "bash") && V.equal(args, field("command", "ls"))
    case _: False{}
def isError(result: Ai.ToolResultMessage<Unit>) -> Bool:
  match result:
    case Ai.ToolResultMessage{_, _, _, _, _, error, _}: error
def synthetic(messages: Messages()) -> List<&2, Ai.ToolResultMessage<Unit>>:
  match messages:
    case Nil{}: Nil{}
    case Ai.ToolResult{+result} <> rest:
      +tail = synthetic(rest)
      Bool.pick(List<&2, Ai.ToolResultMessage<Unit>>, isError(result), result <> tail, tail)
    case _ <> rest: synthetic(rest)
def syntheticResult(results: List<&2, Ai.ToolResultMessage<Unit>>, expectedId: String, expectedName: String) -> Bool:
  match results:
    case Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, None{}, None{}, True{}, _} <> Nil{}:
      String.eq(id, expectedId) && String.eq(name, expectedName) && String.eq(text, "No result provided")
    case _: False{}
def realResult(messages: Messages()) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, None{}, None{}, False{}, _}} <> _: String.eq(id, "call_1_fc_1") && String.eq(name, "read") && String.eq(text, "done")
    case _ <> rest: realResult(rest)
def lastResult(messages: Messages()) -> List<&2, Ai.ToolResultMessage<Unit>>:
  match messages:
    case Ai.ToolResult{result} <> Nil{}: result <> Nil{}
    case _ <> rest: lastResult(rest)
    case Nil{}: Nil{}
def caseThinking() -> IO(Unit):
  do IO<Unit>:
    content : List<&2, Ai.AssistantContent<V.Value>> = Ai.AssistantThinking{Ai.ThinkingContent{"Let me think about this...", Some{"reasoning_content"}, None{}}} <> Ai.AssistantText{Ai.TextContent{"Hi there!", None{}}} <> Nil{}
    result : Messages() <- transform(user("hello") <> Ai.Assistant{assistant(content, "openai-completions", "gpt-4o", Ai.Stop{})} <> Nil{})
    T.assertion(thinkingConverted(assistantBlocks(result)), "converts thinking blocks to plain text when source model differs")
    IO.print("PASS converts thinking blocks to plain text when source model differs")
def caseSignature() -> IO(Unit):
  do IO<Unit>:
    content : List<&2, Ai.AssistantContent<V.Value>> = tool("call_123", "bash", field("command", "ls"), Some{"{\"type\":\"reasoning.encrypted\",\"id\":\"call_123\",\"data\":\"encrypted\"}"}) <> Nil{}
    reply : Ai.Message<V.Value, V.Value, Unit, Unit> = Ai.ToolResult{Ai.ToolResultMessage{"call_123", "bash", Ai.TextImageText{Ai.TextContent{"output", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(0)}}
    result : Messages() <- transform(user("run a command") <> Ai.Assistant{assistant(content, "openai-responses", "gpt-5", Ai.ToolUse{})} <> reply <> Nil{})
    T.assertion(signatureRemoved(assistantBlocks(result)), "removes thoughtSignature from tool calls when migrating between models")
    IO.print("PASS removes thoughtSignature from tool calls when migrating between models")
def caseTrailing() -> IO(Unit):
  do IO<Unit>:
    content : List<&2, Ai.AssistantContent<V.Value>> = tool("call_123|fc_123", "read", field("path", "README.md"), None{}) <> Nil{}
    result : Messages() <- transform(user("read the file") <> Ai.Assistant{assistant(content, "openai-responses", "gpt-5", Ai.ToolUse{})} <> Nil{})
    T.assertion(syntheticResult(lastResult(result), "call_123_fc_123", "read"), "adds synthetic tool results for trailing orphaned tool calls")
    IO.print("PASS adds synthetic tool results for trailing orphaned tool calls")
def casePartial() -> IO(Unit):
  do IO<Unit>:
    content : List<&2, Ai.AssistantContent<V.Value>> = tool("call_1|fc_1", "read", field("path", "README.md"), None{}) <> tool("call_2|fc_2", "bash", field("command", "pwd"), None{}) <> Nil{}
    reply : Ai.Message<V.Value, V.Value, Unit, Unit> = Ai.ToolResult{Ai.ToolResultMessage{"call_1|fc_1", "read", Ai.TextImageText{Ai.TextContent{"done", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(0)}}
    +result : Messages() <- transform(user("run commands") <> Ai.Assistant{assistant(content, "openai-responses", "gpt-5", Ai.ToolUse{})} <> reply <> Nil{})
    T.assertion(syntheticResult(synthetic(result), "call_2_fc_2", "bash") && realResult(result), "adds synthetic results only for trailing tool calls that are still missing results")
    IO.print("PASS adds synthetic results only for trailing tool calls that are still missing results")
def main() -> IO(Unit):
  do IO<Unit>:
    caseThinking()
    caseSignature()
    caseTrailing()
    casePartial()
