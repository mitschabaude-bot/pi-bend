import Base
import ../src/types.bend as T
import ../src/utils/estimate.bend as E
import ../src/utils/transcript.bend as Transcript
import ../src/api/simple-options.bend as Options
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V
import ../../runtime/test/schema.bend as Assert
import ./api/context-estimate.bend as Check
import ./api/thinking-options.bend as NumberTest

def usage(+total: F64) -> T.Usage:
  +zero = F.fromU32(0)
  T.Usage{total, zero, zero, zero, None{}, None{}, total, T.UsageCost{zero, zero, zero, zero, zero}}

def assistant(timestamp: U32, tokens: U32) -> T.Message<V.Value, V.Value, Unit, Unit>:
  T.Assistant{T.AssistantMessage{T.AssistantText{T.TextContent{"kept", None{}}} <> Nil{}, "openai-responses", "openai", "test-model", None{}, None{}, None{}, None{}, usage(F.fromU32(tokens)), T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(timestamp)}}

def user(text: String, timestamp: U32) -> T.Message<V.Value, V.Value, Unit, Unit>:
  T.User{T.UserMessage{T.UserText{text}, F.fromU32(timestamp)}}

def model() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"test-model", "Test Model", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(10000), F.fromU32(8000), None{}, None{}, None{}}

def maxTokens(options: T.StreamOptions<Unit, Unit, Unit, Unit, String>) -> Bool:
  match options:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, Some{value}, _, _, _, _, _}: NumberTest.numberEqual(value, F.fromU32(4899))
    case _: False{}

def stale() -> IO(Unit):
  +context = Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{Some{"system"}, user("summary", 200) <> assistant(100, 9500) <> user(Check.repeat(4000n, Chr{120}), 300) <> Nil{}, None{}})
  do IO<Unit>:
    Assert.assertion(Check.same(E.estimateContextTokens(~Unit, ~Unit, context), E.ContextUsageEstimate{F.fromU32(1005), F.fromU32(0), F.fromU32(1005), None{}}), "stale usage estimate")
    Assert.assertion(maxTokens(Options.buildBaseOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(), context, None{}, None{})), "stale usage response limit")
    IO.print("PASS ignores stale assistant usage after a newer message is inserted before it")

def fresh() -> IO(Unit):
  context = Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, user("summary", 200) <> assistant(100, 9500) <> user("new prompt", 300) <> assistant(400, 2000) <> user("tail", 500) <> Nil{}, None{}})
  do IO<Unit>:
    Assert.assertion(Check.same(E.estimateContextTokens(~Unit, ~Unit, context), E.ContextUsageEstimate{F.fromU32(2001), F.fromU32(2000), F.fromU32(1), Some{3n}}), "fresh usage estimate")
    IO.print("PASS uses assistant usage again after a response to the inserted context")

def main() -> IO(Unit):
  do IO<Unit>:
    stale()
    fresh()
