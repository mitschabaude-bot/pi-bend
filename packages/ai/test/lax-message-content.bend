import Base
import ../src/types.bend as T
import ../src/utils/message-json.bend as MessageJson
import ../../runtime/src/json.bend as J
import ../../runtime/src/schema-value.bend as V

# upstream lax-message-content.test.ts: the Message types require `content`,
# but untyped callers (custom tools, hand-built histories, old session files)
# can violate that contract. Upstream normalizes null/missing content to an
# empty array in transformMessages; natively a message can only come from
# such callers through JSON decoding, so the decoder normalizes it, and the
# typed transform never sees null.

def Message() -> Data: T.Message<V.Value, V.Value, V.Value, V.Value>
def raw(value: V.Value) -> MessageJson.Decoded(V.Value): Done{value}
def decodedValue(value: Result<&2, &2, J.ParseError, V.Value>) -> MessageJson.Decoded(Message()):
  match value:
    case Fail{_}: Fail{J.MissingField{Nil{}}}
    case Done{+json}: MessageJson.decodeMessage(~V.Value, ~V.Value, ~raw, ~raw, json)
def decoded(+text: String) -> MessageJson.Decoded(Message()): decodedValue(J.parse(text))
def empty(value: MessageJson.Decoded(Message())) -> Bool:
  match value:
    case Done{T.User{T.UserMessage{T.UserBlocks{Nil{}}, _}}}: True{}
    case Done{T.Assistant{T.AssistantMessage{Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: True{}
    case Done{T.ToolResult{T.ToolResultMessage{_, _, Nil{}, _, _, _, _}}}: True{}
    case _: False{}
def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def main() -> IO(Unit):
  do IO<Unit>:
    check(empty(decoded("{\"role\":\"user\",\"content\":null,\"timestamp\":1}")), "user content null")
    check(empty(decoded("{\"role\":\"assistant\",\"content\":null,\"api\":\"openai-completions\",\"provider\":\"openai\",\"model\":\"test-model\",\"usage\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}},\"stopReason\":\"stop\",\"timestamp\":1}")), "assistant content null")
    check(empty(decoded("{\"role\":\"toolResult\",\"toolCallId\":\"call_1\",\"toolName\":\"web_search\",\"isError\":false,\"timestamp\":1}")), "tool result content missing")
    IO.print("PASS lax message content handling: normalizes null/missing content to an empty array instead of crashing")
