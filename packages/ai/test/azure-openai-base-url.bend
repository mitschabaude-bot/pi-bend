import Base
import ../src/types.bend as T
import ../src/api/azure-openai-responses.bend as Azure
import ../src/api/openai-client.bend as Client
import ../src/api/openai-responses.bend as Responses
import ../src/providers/azure-openai-responses.models.bend as Catalog
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as Domain
import ../../runtime/src/idna.bend as Label
import ../../runtime/src/idna.bend as Mapping
import ../../runtime/src/pi-user-agent.bend as UserAgent
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/url.bend as URL

# upstream azure-openai-base-url.test.ts. Upstream mocks the AzureOpenAI
# constructor and records its baseURL, defaultHeaders and the request params;
# here the prepared request carries exactly those values (baseUrl, client
# headers, payload). Upstream sets process.env; these cases pass the same
# variables as the stream's provider environment, which takes precedence.

def Options() -> Data: Azure.AzureOpenAIResponsesOptions<Unit, Unit, Unit>
def Prepared() -> Data: Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>

def urls() -> URL.Context:
  URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}

def config(agent: String) -> Responses.Config:
  Responses.Config{urls(), Client.Defaults{agent, R.new(String), None{}, None{}}, Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def find(models: List<&2, T.Model<T.JsonValue>>) -> T.Model<T.JsonValue>:
  match models:
    case Nil{}: T.Model{"missing", "", T.AzureOpenAIResponsesApi{}, "", "", False{}, None{}, Nil{}, None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(0), F.fromU32(0), None{}, None{}, None{}}
    case T.Model{+id, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o} <> rest: Bool.pick(T.Model<T.JsonValue>, String.eq(id, "gpt-4o-mini"), T.Model{id, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o}, find(rest))

# getModel("azure-openai-responses", "gpt-4o-mini")
def gpt4oMini() -> T.Model<T.JsonValue>: find(Catalog.AZURE_OPENAI_RESPONSES_MODELS())

def withoutStrictMode(model: T.Model<T.JsonValue>) -> T.Model<T.JsonValue>:
  match model:
    case T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, _}:
      T.Model{id, name, T.AzureOpenAIResponsesApi{}, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, Some{T.OpenAIResponsesCompat{None{}, None{}, None{}, None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}}}}

def preferredTool() -> T.Tool<V.Value>:
  T.Tool{"preferred", "Preferred constrained tool", V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}, Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Prefer{}}}}}

def context(tools: Maybe<&2, List<&2, T.Tool<V.Value>>>) -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, T.User{T.UserMessage{T.UserText{"hello"}, F.fromU32(1)}} <> Nil{}, tools})

def env(name: String, value: String) -> Maybe<&2, T.ProviderEnv()>:
  Some{R.Record{R.Property{name, value} <> Nil{}}}

def options(environment: Maybe<&2, T.ProviderEnv()>, baseUrl: Maybe<&2, String>, sessionId: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>) -> Options():
  Azure.AzureOpenAIResponsesOptions{T.StreamOptions{None{}, None{}, Some{"test-api-key"}, None{}, environment, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, sessionId, None{}, None{}}, None{}, None{}, None{}, None{}, None{}, baseUrl, None{}}

def azureBase() -> Maybe<&2, String>: Some{"https://my-resource.openai.azure.com"}

def prepare(agent: String, model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, Unit, Unit>, selected: Options()) -> IO(Prepared()):
  Azure.prepare(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, urls(), agent, model, context, selected)

def report(+name: String, passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), passed, IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name))

def baseUrlOf(prepared: Prepared()) -> String:
  match prepared:
    case Done{Responses.ProviderRequest{_, baseUrl, _, _, _, _}}: baseUrl
    case Fail{cause}: "error: " ++ Responses.describePreparation(cause)

def payloadField(name: String, prepared: Prepared()) -> Maybe<&2, T.JsonValue>:
  match prepared:
    case Done{Responses.ProviderRequest{_, _, _, T.JsonObject{fields}, _, _}}: R.get(T.JsonValue, fields, name)
    case _: None{}

def userAgentOf(prepared: Prepared()) -> Maybe<&2, T.Nullable<String>>:
  match prepared:
    case Done{Responses.ProviderRequest{_, _, headers, _, _, _}}: R.get(T.Nullable<String>, headers, "User-Agent")
    case _: None{}

def strictAbsent(tools: Maybe<&2, T.JsonValue>) -> Bool:
  match tools:
    case Some{T.JsonArray{T.JsonObject{fields} <> _}}: Bool.not(Maybe.is_some(&2, T.JsonValue, R.get(T.JsonValue, fields, "strict")))
    case _: False{}

def isString(expected: String, value: Maybe<&2, T.JsonValue>) -> Bool:
  match value:
    case Some{T.JsonString{text}}: String.eq(text, expected)
    case _: False{}

def isFalse(value: Maybe<&2, T.JsonValue>) -> Bool:
  match value:
    case Some{T.JsonBoolean{False{}}}: True{}
    case _: False{}

def isPresent(expected: String, value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.PresentValue{text}}: String.eq(text, expected)
    case _: False{}

def captureClientBaseUrl(name: String, agent: String, baseUrl: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    prepared : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(env("AZURE_OPENAI_BASE_URL", baseUrl), None{}, None{}, None{}))
    report(name, String.eq(baseUrlOf(prepared), expected))

def failureMessage(message: T.AssistantMessage<V.Value, Unit>) -> String:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Error{}, _, Some{text}, _, _, _}: text
    case _: "(not an error)"

def failedWith(result: Responses.RunResult<Unit, Unit, Unit>) -> String:
  match result:
    case Responses.RunResult{Responses.Failed{T.ErrorError{}, message, _}, _}: failureMessage(message)
    case _: "(no error)"

def unit(value: Unit) -> String: "unit"

def invalidUrl(+agent: String) -> IO(Unit):
  do IO<Unit>:
    owner : Responses.Run<Unit, Unit, Unit> <- Azure.stream(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~unit, config(agent), gpt4oMini(), context(None{}), options(env("AZURE_OPENAI_BASE_URL", "not-a-url"), None{}, None{}, None{}))
    result : Responses.RunResult<Unit, Unit, Unit> <- Responses.dispose(Unit, Unit, Unit, owner)
    report("throws on invalid URLs", String.contains(failedWith(result), "Invalid Azure OpenAI base URL"))

def normalization(+agent: String) -> IO(Unit):
  do IO<Unit>:
    captureClientBaseUrl("normalizes Cognitive Services root endpoints to /openai/v1", agent, "https://marc-quicktests-resource.cognitiveservices.azure.com", "https://marc-quicktests-resource.cognitiveservices.azure.com/openai/v1")
    captureClientBaseUrl("normalizes Microsoft Foundry root endpoints to /openai/v1", agent, "https://marc-quicktests-resource.ai.azure.com", "https://marc-quicktests-resource.ai.azure.com/openai/v1")
    captureClientBaseUrl("normalizes Azure OpenAI root endpoints to /openai/v1", agent, "https://my-resource.openai.azure.com", "https://my-resource.openai.azure.com/openai/v1")
    captureClientBaseUrl("normalizes /openai to /openai/v1", agent, "https://my-resource.cognitiveservices.azure.com/openai", "https://my-resource.cognitiveservices.azure.com/openai/v1")
    captureClientBaseUrl("preserves /openai/v1 endpoints", agent, "https://my-resource.cognitiveservices.azure.com/openai/v1", "https://my-resource.cognitiveservices.azure.com/openai/v1")
    captureClientBaseUrl("normalizes /openai/v1/responses to /openai/v1", agent, "https://my-resource.services.ai.azure.com/openai/v1/responses", "https://my-resource.services.ai.azure.com/openai/v1")
    captureClientBaseUrl("preserves explicit non-Azure proxy paths", agent, "https://my-proxy.example.com/v1", "https://my-proxy.example.com/v1")
    captureClientBaseUrl("strips query params when normalizing Azure host URLs", agent, "https://my-resource.openai.azure.com/openai?api-version=2024-12-01", "https://my-resource.openai.azure.com/openai/v1")
    captureClientBaseUrl("preserves query params on non-Azure proxy URLs", agent, "https://my-proxy.example.com/v1?custom=true", "https://my-proxy.example.com/v1?custom=true")
    invalidUrl(agent)

def params(+agent: String) -> IO(Unit):
  do IO<Unit>:
    clamped : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(None{}, azureBase(), Some{String.repeat("x", 67n)}, None{}))
    report("clamps prompt_cache_key to OpenAI's 64-character limit", isString(String.repeat("x", 64n), payloadField("prompt_cache_key", clamped)))
    stored : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(None{}, azureBase(), None{}, None{}))
    report("disables server-side response storage", isFalse(payloadField("store", stored)))
    strict : Prepared() <- prepare(agent, withoutStrictMode(gpt4oMini()), context(Some{preferredTool() <> Nil{}}), options(None{}, azureBase(), None{}, None{}))
    report("honors supportsStrictMode: false", strictAbsent(payloadField("tools", strict)))
    resource : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(env("AZURE_OPENAI_RESOURCE_NAME", "my-resource"), None{}, None{}, None{}))
    report("builds correct default URL from AZURE_OPENAI_RESOURCE_NAME", String.eq(baseUrlOf(resource), "https://my-resource.openai.azure.com/openai/v1"))

def userAgent(+agent: String) -> IO(Unit):
  do IO<Unit>:
    default : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(None{}, azureBase(), None{}, None{}))
    report("uses pi's User-Agent by default", isPresent(agent, userAgentOf(default)))
    custom : Prepared() <- prepare(agent, gpt4oMini(), context(None{}), options(None{}, azureBase(), None{}, Some{R.Record{R.Property{"User-Agent", T.PresentValue{"custom-agent"}} <> Nil{}}}))
    report("lets explicit headers override the default User-Agent", isPresent("custom-agent", userAgentOf(custom)))

def main() -> IO(Unit):
  do IO<Unit>:
    +agent : String <- IO.try(String, UserAgent.get())
    normalization(agent)
    params(agent)
    userAgent(agent)
