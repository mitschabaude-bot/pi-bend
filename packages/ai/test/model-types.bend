import Base
import ../src/types.bend as T
import ../src/utils/model-api.bend as Api
import ../../runtime/src/f64.bend as F

# The dependent API argument binds the type of compat at construction time.
def model(api: T.ModelApi, compat: Maybe<&2, T.ModelCompatibility(api)>) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"test", "Test", api, "test-provider", "https://example.test", True{}, None{}, T.InputText{} <> T.InputImage{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, compat}

def category(api: T.ModelApi) -> U32:
  match api:
    case T.OpenAICompletionsApi{}: 1
    case T.OpenAIResponsesApi{}: 2
    case T.AzureOpenAIResponsesApi{}: 3
    case T.OpenAICodexResponsesApi{}: 4
    case T.AnthropicMessagesApi{}: 5
    case T.BedrockConverseStreamApi{}: 6
    case T.MistralConversationsApi{}: 7
    case T.GoogleGenerativeAiApi{}: 8
    case T.GoogleVertexApi{}: 9
    case T.PiMessagesApi{}: 10
    case T.CustomModelApi{_}: 0

def check(+model: T.Model<T.JsonValue>, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_eq(category(Api.modelApi(T.JsonValue, model)), category(Api.fromString(expected))) && String.eq(Api.name(Api.modelApi(T.JsonValue, model)), expected) && String.eq(Api.name(Api.fromString(expected)), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "model API did not round trip"))

def main() -> IO(Unit):
  do IO<Unit>:
    check(model(T.OpenAICompletionsApi{}, Some{T.OpenAICompletionsCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}), "openai-completions")
    +responses : T.OpenAIResponsesCompat = T.OpenAIResponsesCompat{Some{False{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{True{}}}
    check(model(T.OpenAIResponsesApi{}, Some{responses}), "openai-responses")
    check(model(T.AzureOpenAIResponsesApi{}, Some{responses}), "azure-openai-responses")
    check(model(T.OpenAICodexResponsesApi{}, Some{responses}), "openai-codex-responses")
    check(model(T.AnthropicMessagesApi{}, Some{T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}), "anthropic-messages")
    check(model(T.BedrockConverseStreamApi{}, Some{T.BedrockCompat{Some{True{}}}}), "bedrock-converse-stream")
    check(model(T.MistralConversationsApi{}, Some{T.MistralConversationsCompat{Some{False{}}}}), "mistral-conversations")
    check(model(T.GoogleGenerativeAiApi{}, None{}), "google-generative-ai")
    check(model(T.GoogleVertexApi{}, None{}), "google-vertex")
    check(model(T.PiMessagesApi{}, None{}), "pi-messages")
    check(model(T.CustomModelApi{"custom-example"}, None{}), "custom-example")
    IO.print("PASS API-dependent model construction and identifier round trips")
