import Base
import ../src/types.bend as T
import ../src/models.bend as Models
import ../src/auth/types.bend as Auth
import ../src/utils/model-api.bend as Api
import ../src/providers/cloudflare-ai-gateway.models.bend as Gateway
import ../src/providers/cloudflare-workers-ai.models.bend as Workers
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/string.bend as Text

# upstream cloudflare-stream.test.ts. Upstream wraps an API implementation and
# captures the model its stream and streamSimple receive; Bend dispatches
# both through the one model transform of the provider's streams
# (Models.streamModel), so each case checks that transform once. The native
# cases cover the three gateway APIs, Workers AI, partial environments and
# models.json composition (upstream provider-composer supportsBaseApi).

def testModel(api: T.ModelApi, url: String) -> T.Model<T.JsonValue>:
  T.Model{"model", "model", api, "cloudflare-ai-gateway", url, False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def gatewayOpenAI() -> String: "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/openai"

def gatewayStreams() -> Models.ProviderStreams: Models.CloudflareStreams{[T.AnthropicMessagesApi{}, T.OpenAICompletionsApi{}, T.OpenAIResponsesApi{}]}

def providerEnv(entries: List<&2, R.Property<String>>) -> Maybe<&2, T.ProviderEnv()>: Some{R.Record{entries}}

def accountAndGateway() -> Maybe<&2, T.ProviderEnv()>:
  providerEnv([R.Property{"CLOUDFLARE_ACCOUNT_ID", "account"}, R.Property{"CLOUDFLARE_GATEWAY_ID", "gateway"}])

def baseUrlOf(value: T.Model<T.JsonValue>) -> String:
  match value:
    case T.Model{_, _, _, _, url, _, _, _, _, _, _, _, _, _, _, _}: url

def streamed(streams: Models.ProviderStreams, value: T.Model<T.JsonValue>, environment: Maybe<&2, T.ProviderEnv()>) -> String:
  baseUrlOf(Models.streamModel(T.JsonValue, streams, value, environment))

def report(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " != " ++ expected))

def check(+name: String, passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), passed, IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name))

# Every catalog model materializes both placeholders and keeps the rest of
# its endpoint.
def materializedAll(+streams: Models.ProviderStreams, models: List<&2, T.Model<T.JsonValue>>) -> Bool:
  match models:
    case Nil{}: True{}
    case +value <> rest:
      +url = streamed(streams, value, accountAndGateway())
      Bool.not(String.contains(url, "{")) && String.eq(Text.replaceAll(Text.replaceAll(baseUrlOf(value), "{CLOUDFLARE_ACCOUNT_ID}", "account"), "{CLOUDFLARE_GATEWAY_ID}", "gateway"), url) && materializedAll(streams, rest)

def names(apis: List<&2, T.ModelApi>) -> List<&2, String>:
  match apis:
    case Nil{}: Nil{}
    case api <> rest: Api.name(api) <> names(rest)

def apiNames(streams: Models.ProviderStreams) -> String:
  match streams:
    case Models.ApiStreams{}: "api"
    case Models.CloudflareStreams{apis}: String.join(names(apis), ",")

def baseProvider(models: List<&2, T.Model<T.JsonValue>>, streams: Models.ProviderStreams) -> Maybe<&2, Models.Provider>:
  Some{Models.Provider{"cloudflare-ai-gateway", "Cloudflare AI Gateway", "", Auth.ProviderAuth{None{}, None{}}, models, streams, None{}}}

def main() -> IO(Unit):
  do IO<Unit>:
    report("materializes the model endpoint before dispatch", streamed(gatewayStreams(), testModel(T.OpenAICompletionsApi{}, gatewayOpenAI()), accountAndGateway()), "https://gateway.ai.cloudflare.com/v1/account/gateway/openai")
    report("keeps placeholders when the provider env does not resolve them", streamed(gatewayStreams(), testModel(T.OpenAICompletionsApi{}, gatewayOpenAI()), None{}), gatewayOpenAI())
    report("keeps a placeholder whose variable is unset", streamed(gatewayStreams(), testModel(T.OpenAIResponsesApi{}, gatewayOpenAI()), providerEnv([R.Property{"CLOUDFLARE_ACCOUNT_ID", "account"}])), "https://gateway.ai.cloudflare.com/v1/account/{CLOUDFLARE_GATEWAY_ID}/openai")
    report("materializes an anthropic-messages endpoint", streamed(gatewayStreams(), testModel(T.AnthropicMessagesApi{}, "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/anthropic"), accountAndGateway()), "https://gateway.ai.cloudflare.com/v1/account/gateway/anthropic")
    report("leaves APIs the provider does not wrap unchanged", streamed(Models.CloudflareStreams{[T.OpenAICompletionsApi{}]}, testModel(T.OpenAIResponsesApi{}, gatewayOpenAI()), accountAndGateway()), gatewayOpenAI())
    report("leaves other providers' endpoints unchanged", streamed(Models.ApiStreams{}, testModel(T.OpenAICompletionsApi{}, gatewayOpenAI()), accountAndGateway()), gatewayOpenAI())
    check("materializes every AI Gateway catalog endpoint", materializedAll(gatewayStreams(), Gateway.CLOUDFLARE_AI_GATEWAY_MODELS()))
    check("materializes every Workers AI catalog endpoint", materializedAll(Models.CloudflareStreams{[T.OpenAICompletionsApi{}]}, Workers.CLOUDFLARE_WORKERS_AI_MODELS()))
    report("a models.json overlay streams through the base provider for its models' APIs", apiNames(Models.inheritedStreams(baseProvider([testModel(T.OpenAIResponsesApi{}, gatewayOpenAI()), testModel(T.AnthropicMessagesApi{}, "")], gatewayStreams()))), "anthropic-messages,openai-responses")
    report("a custom provider streams through the API implementations", apiNames(Models.inheritedStreams(None{})), "api")
