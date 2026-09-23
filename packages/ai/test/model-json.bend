import Base
import ../src/types.bend as T
import ../src/utils/model-json.bend as Codec
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Json
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

def checkParsed(value: V.Value, parsed: Result<&2, &2, Json.ParseError, V.Value>, +label: String) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.die(Unit, 1, "bad expected JSON: " ++ label)
    case Done{expectedValue}:
      Bool.pick(IO(Unit), V.equal(value, expectedValue), IO.print("PASS " ++ label), IO.die(Unit, 1, "model JSON mismatch: " ++ label))

def checkJson(value: V.Value, expected: String, label: String) -> IO(Unit):
  checkParsed(value, Json.parse(expected), label)

def sparse() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"id", "name", T.CustomModelApi{"custom"}, "provider", "https://test", False{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(1024), F.fromU32(64), None{}, None{}, None{}}

def richResponses() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  +one = F.fromU32(1)
  +sampling = R.set(T.JsonValue, R.new(T.JsonValue), "nested", T.JsonObject{R.set(T.JsonValue, R.new(T.JsonValue), "list", T.JsonArray{T.JsonNull{} <> T.JsonBoolean{False{}} <> Nil{}})})
  +headers = R.set(String, R.new(String), "X-Test", "yes")
  +compat = {T.OpenAIResponsesCompat{Some{False{}}, Some{True{}}, Some{T.OpenAINoSession{}}, None{}, Some{True{}}, None{}, Some{False{}}, Some{True{}}, None{}, Some{False{}}} : T.OpenAIResponsesCompat}
  T.Model{"responses", "Responses", T.OpenAIResponsesApi{}, "openai", "https://test/v1", True{}, Some{T.ThinkingLevelMap{T.ThinkingLevelMapping{T.Off{}, Some{T.NullValue{}}} <> T.ThinkingLevelMapping{T.Thinking{T.High{}}, Some{T.PresentValue{"high"}}} <> T.ThinkingLevelMapping{T.Thinking{T.Low{}}, None{}} <> Nil{}}}, T.InputText{} <> T.InputImage{} <> Nil{}, Some{T.ModelInputLimits{Some{F.fromU32(4096)}, Some{T.ModelImageInputLimits{Some{T.ModelImageResizeOptions{Some{F.fromU32(512)}, None{}, Some{F.fromU32(2048)}, Some{F.fromU32(80)}}}, Some{F.fromU32(3)}, None{}}}}}, T.ModelCost{one, F.fromU32(2), zero, zero, Some{T.ModelCostTier{F.fromU32(4), F.fromU32(5), zero, zero, F.fromU32(1000)} <> Nil{}}}, Some{T.ModelPromptCache{Some{F.fromU32(300)}, None{}}}, F.fromU32(128000), F.fromU32(8192), Some{sampling}, Some{headers}, Some{compat}}

def completions() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  +kwargs = R.set(T.ChatTemplateKwargValue, R.new(T.ChatTemplateKwargValue), "enable", T.TemplateVariable{T.ThinkingEnabled{}, Some{True{}}})
  +routing = {T.OpenRouterRouting{Some{False{}}, None{}, Some{T.DenyCollection{}}, None{}, None{}, Some{"one" <> "two" <> Nil{}}, None{}, None{}, None{}, Some{T.SortByOptions{Some{"price"}, Some{T.NullValue{}}}}, Some{T.RoutingMaxPrice{Some{T.StringPrice{"0.2"}}, None{}, None{}, None{}, None{}}}, Some{T.PercentilePreference{T.RoutingPercentiles{Some{F.fromU32(50)}, None{}, None{}, None{}}}}, Some{T.OverallPreference{F.fromU32(2)}}} : T.OpenRouterRouting}
  +compat = {T.OpenAICompletionsCompat{Some{False{}}, None{}, None{}, None{}, None{}, Some{T.MaxCompletionTokens{}}, None{}, None{}, None{}, None{}, Some{T.ChatTemplateThinking{}}, Some{kwargs}, None{}, Some{routing}, Some{T.VercelGatewayRouting{Some{"bedrock" <> Nil{}}, None{}}}, None{}, Some{T.ThinkingBudgetTokens{}}, None{}, None{}, None{}, None{}, None{}, Some{T.AnthropicCacheControl{}}, None{}, Some{T.OpenRouterSession{}}, None{}, Some{F.fromU32(7)}} : T.OpenAICompletionsCompat}
  T.Model{"chat", "Chat", T.OpenAICompletionsApi{}, "router", "https://router", True{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(100), F.fromU32(10), None{}, None{}, Some{compat}}

def anthropic() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  +fallback = {T.AnthropicAllowedFallbackModel{"anthropic", "secondary", T.ModelCost{F.fromU32(3), zero, zero, zero, None{}}} : T.AnthropicAllowedFallbackModel}
  +compat = {T.AnthropicMessagesCompat{None{}, None{}, None{}, Some{T.AnthropicOpenRouterSession{}}, None{}, Some{False{}}, None{}, None{}, Some{True{}}, None{}, None{}, None{}, Some{fallback <> Nil{}}} : T.AnthropicMessagesCompat}
  T.Model{"claude", "Claude", T.AnthropicMessagesApi{}, "anthropic", "https://api", True{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(200), F.fromU32(20), None{}, None{}, Some{compat}}

def main() -> IO(Unit):
  do IO<Unit>:
    checkJson(Codec.model(sparse()), "{\"id\":\"id\",\"name\":\"name\",\"api\":\"custom\",\"provider\":\"provider\",\"baseUrl\":\"https://test\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":1024,\"maxTokens\":64}", "sparse optional omission")
    checkJson(Codec.model(richResponses()), "{\"id\":\"responses\",\"name\":\"Responses\",\"api\":\"openai-responses\",\"provider\":\"openai\",\"baseUrl\":\"https://test/v1\",\"reasoning\":true,\"thinkingLevelMap\":{\"off\":null,\"high\":\"high\"},\"input\":[\"text\",\"image\"],\"inputLimits\":{\"maxRequestBytes\":4096,\"images\":{\"resize\":{\"maxWidth\":512,\"maxBytes\":2048,\"jpegQuality\":80},\"maxPerMessage\":3}},\"cost\":{\"input\":1,\"output\":2,\"cacheRead\":0,\"cacheWrite\":0,\"tiers\":[{\"input\":4,\"output\":5,\"cacheRead\":0,\"cacheWrite\":0,\"inputTokensAbove\":1000}]},\"promptCache\":{\"short\":300},\"contextWindow\":128000,\"maxTokens\":8192,\"samplingParams\":{\"nested\":{\"list\":[null,false]}},\"headers\":{\"X-Test\":\"yes\"},\"compat\":{\"supportsDeveloperRole\":false,\"supportsMidConvoSystemMessages\":true,\"sessionAffinityFormat\":\"openai-nosession\",\"supportsStrictMode\":true,\"supportsAdditionalTools\":false,\"supportsToolSearch\":true,\"supportsMaxOutputTokens\":false}}", "responses metadata")
    checkJson(Codec.model(completions()), "{\"id\":\"chat\",\"name\":\"Chat\",\"api\":\"openai-completions\",\"provider\":\"router\",\"baseUrl\":\"https://router\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":100,\"maxTokens\":10,\"compat\":{\"supportsStore\":false,\"maxTokensField\":\"max_completion_tokens\",\"thinkingFormat\":\"chat-template\",\"chatTemplateKwargs\":{\"enable\":{\"$var\":\"thinking.enabled\",\"omitWhenOff\":true}},\"openRouterRouting\":{\"allow_fallbacks\":false,\"data_collection\":\"deny\",\"order\":[\"one\",\"two\"],\"sort\":{\"by\":\"price\",\"partition\":null},\"max_price\":{\"prompt\":\"0.2\"},\"preferred_min_throughput\":{\"p50\":50},\"preferred_max_latency\":2},\"vercelGatewayRouting\":{\"only\":[\"bedrock\"]},\"thinkingTokenBudgetField\":\"thinking_budget_tokens\",\"cacheControlFormat\":\"anthropic\",\"sessionAffinityFormat\":\"openrouter\",\"vllmPriority\":7}}", "completions routing")
    checkJson(Codec.model(anthropic()), "{\"id\":\"claude\",\"name\":\"Claude\",\"api\":\"anthropic-messages\",\"provider\":\"anthropic\",\"baseUrl\":\"https://api\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":200,\"maxTokens\":20,\"compat\":{\"sessionAffinityFormat\":\"openrouter\",\"supportsTemperature\":false,\"supportsStrictTools\":true,\"allowedFallbackModels\":[{\"provider\":\"anthropic\",\"model\":\"secondary\",\"cost\":{\"input\":3,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}}]}}", "anthropic fallback")
