import Base
import ../types.bend as T
import ./model-api.bend as Api
import ./message-json.bend as MessageJson
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Public JSON shape of pi-ai Model. Optional members are absent when their
# typed Maybe is None; nullable thinking mappings remain explicit JSON null.
def fields() -> R.Record<V.Value>: R.new(V.Value)
def object(fields: R.Record<V.Value>) -> V.Value: V.ObjectValue{fields}
def text(value: String) -> V.Value: V.Text{value}
def number(value: F64) -> V.Value: V.Number{value}
def boolean(value: Bool) -> V.Value: V.Boolean{value}

def put(fields: R.Record<V.Value>, key: String, value: V.Value) -> R.Record<V.Value>:
  R.set(V.Value, fields, key, value)

def optional(fields: R.Record<V.Value>, key: String, value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case None{}: fields
    case Some{value}: put(fields, key, value)

def optionalText(fields: R.Record<V.Value>, key: String, value: Maybe<&2, String>) -> R.Record<V.Value>:
  optional(fields, key, Maybe.map(&2, String, V.Value, text, value))

def optionalNumber(fields: R.Record<V.Value>, key: String, value: Maybe<&2, F64>) -> R.Record<V.Value>:
  optional(fields, key, Maybe.map(&2, F64, V.Value, number, value))

def optionalBoolean(fields: R.Record<V.Value>, key: String, value: Maybe<&2, Bool>) -> R.Record<V.Value>:
  optional(fields, key, Maybe.map(&2, Bool, V.Value, boolean, value))

def stringValues(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: text(value) <> stringValues(rest)

def strings(values: List<&2, String>) -> V.Value:
  V.ArrayValue{stringValues(values)}

def optionalStrings(fields: R.Record<V.Value>, key: String, value: Maybe<&2, List<&2, String>>) -> R.Record<V.Value>:
  optional(fields, key, Maybe.map(&2, List<&2, String>, V.Value, strings, value))

def jsonProperties(properties: List<&2, R.Property<T.JsonValue>>) -> List<&2, R.Property<V.Value>>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, MessageJson.jsonValue(value)} <> jsonProperties(rest)

def stringProperties(properties: List<&2, R.Property<String>>) -> List<&2, R.Property<V.Value>>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, text(value)} <> stringProperties(rest)

def nullable(value: T.Nullable<String>) -> V.Value:
  match value:
    case T.NullValue{}: V.Null{}
    case T.PresentValue{value}: text(value)

def thinkingLevel(value: T.ModelThinkingLevel) -> String:
  match value:
    case T.Off{}: "off"
    case T.Thinking{T.Minimal{}}: "minimal"
    case T.Thinking{T.Low{}}: "low"
    case T.Thinking{T.Medium{}}: "medium"
    case T.Thinking{T.High{}}: "high"
    case T.Thinking{T.XHigh{}}: "xhigh"
    case T.Thinking{T.Max{}}: "max"

def thinkingProperties(values: List<&2, T.ThinkingLevelMapping>, result: R.Record<V.Value>) -> R.Record<V.Value>:
  match values:
    case Nil{}: result
    case T.ThinkingLevelMapping{level, None{}} <> rest: thinkingProperties(rest, result)
    case T.ThinkingLevelMapping{level, Some{value}} <> rest: thinkingProperties(rest, put(result, thinkingLevel(level), nullable(value)))

def thinkingLevelMap(value: T.ThinkingLevelMap) -> V.Value:
  match value:
    case T.ThinkingLevelMap{properties}: object(thinkingProperties(properties, fields()))

def input(value: T.ModelInput) -> V.Value:
  match value:
    case T.InputText{}: text("text")
    case T.InputImage{}: text("image")

def inputValues(values: List<&2, T.ModelInput>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: input(value) <> inputValues(rest)

def inputs(values: List<&2, T.ModelInput>) -> V.Value:
  V.ArrayValue{inputValues(values)}

def costTier(value: T.ModelCostTier) -> V.Value:
  match value:
    case T.ModelCostTier{inputRate, outputRate, cacheRead, cacheWrite, threshold}:
      object(put(put(put(put(put(fields(), "input", number(inputRate)), "output", number(outputRate)), "cacheRead", number(cacheRead)), "cacheWrite", number(cacheWrite)), "inputTokensAbove", number(threshold)))

def costTierValues(values: List<&2, T.ModelCostTier>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: costTier(value) <> costTierValues(rest)

def costTiers(values: List<&2, T.ModelCostTier>) -> V.Value:
  V.ArrayValue{costTierValues(values)}

def cost(value: T.ModelCost) -> V.Value:
  match value:
    case T.ModelCost{inputRate, outputRate, cacheRead, cacheWrite, tiers}:
      object(optional(put(put(put(put(fields(), "input", number(inputRate)), "output", number(outputRate)), "cacheRead", number(cacheRead)), "cacheWrite", number(cacheWrite)), "tiers", Maybe.map(&2, List<&2, T.ModelCostTier>, V.Value, costTiers, tiers)))

def resize(value: T.ModelImageResizeOptions) -> V.Value:
  match value:
    case T.ModelImageResizeOptions{width, height, bytes, quality}:
      object(optionalNumber(optionalNumber(optionalNumber(optionalNumber(fields(), "maxWidth", width), "maxHeight", height), "maxBytes", bytes), "jpegQuality", quality))

def imageLimits(value: T.ModelImageInputLimits) -> V.Value:
  match value:
    case T.ModelImageInputLimits{resizeOptions, perMessage, perRequest}:
      object(optionalNumber(optionalNumber(optional(fields(), "resize", Maybe.map(&2, T.ModelImageResizeOptions, V.Value, resize, resizeOptions)), "maxPerMessage", perMessage), "maxPerRequest", perRequest))

def inputLimits(value: T.ModelInputLimits) -> V.Value:
  match value:
    case T.ModelInputLimits{bytes, images}:
      object(optional(optionalNumber(fields(), "maxRequestBytes", bytes), "images", Maybe.map(&2, T.ModelImageInputLimits, V.Value, imageLimits, images)))

def promptCache(value: T.ModelPromptCache) -> V.Value:
  match value:
    case T.ModelPromptCache{short, long}:
      object(optionalNumber(optionalNumber(fields(), "short", short), "long", long))

def sampling(value: R.Record<T.JsonValue>) -> V.Value:
  object(R.Record{jsonProperties(R.entries(T.JsonValue, value))})

def headers(value: R.Record<String>) -> V.Value:
  object(R.Record{stringProperties(R.entries(String, value))})

def sessionAffinityFormat(value: T.SessionAffinityFormat) -> V.Value:
  match value:
    case T.OpenAISession{}: text("openai")
    case T.OpenAINoSession{}: text("openai-nosession")
    case T.OpenRouterSession{}: text("openrouter")

def anthropicSessionAffinityFormat(value: T.AnthropicSessionAffinityFormat) -> V.Value:
  match value:
    case T.AnthropicOpenRouterSession{}: text("openrouter")

def maxTokensField(value: T.MaxTokensField) -> V.Value:
  match value:
    case T.MaxCompletionTokens{}: text("max_completion_tokens")
    case T.MaxTokens{}: text("max_tokens")

def thinkingFormat(value: T.ThinkingFormat) -> V.Value:
  match value:
    case T.OpenAIThinking{}: text("openai")
    case T.OpenRouterThinking{}: text("openrouter")
    case T.DeepSeekThinking{}: text("deepseek")
    case T.TogetherThinking{}: text("together")
    case T.BasetenThinking{}: text("baseten")
    case T.ZaiThinking{}: text("zai")
    case T.QwenThinking{}: text("qwen")
    case T.ChatTemplateThinking{}: text("chat-template")
    case T.QwenChatTemplateThinking{}: text("qwen-chat-template")
    case T.StringThinking{}: text("string-thinking")
    case T.AntLingThinking{}: text("ant-ling")

def thinkingTokenBudgetField(value: T.ThinkingTokenBudgetField) -> V.Value:
  match value:
    case T.ThinkingTokenBudget{}: text("thinking_token_budget")
    case T.ThinkingBudgetField{}: text("thinking_budget")
    case T.ThinkingBudgetTokens{}: text("thinking_budget_tokens")

def cacheControlFormat(value: T.CacheControlFormat) -> V.Value:
  match value:
    case T.AnthropicCacheControl{}: text("anthropic")

def dataCollection(value: T.DataCollection) -> V.Value:
  match value:
    case T.DenyCollection{}: text("deny")
    case T.AllowCollection{}: text("allow")

def chatTemplateVariable(value: T.ThinkingVariable) -> V.Value:
  match value:
    case T.ThinkingEnabled{}: text("thinking.enabled")
    case T.ThinkingEffort{}: text("thinking.effort")
    case T.ThinkingBudget{}: text("thinking.budget")

def chatTemplateKwarg(value: T.ChatTemplateKwargValue) -> V.Value:
  match value:
    case T.TemplateString{value}: text(value)
    case T.TemplateNumber{value}: number(value)
    case T.TemplateBoolean{value}: boolean(value)
    case T.TemplateNull{}: V.Null{}
    case T.TemplateVariable{variable, omitWhenOff}: object(optionalBoolean(put(fields(), "$var", chatTemplateVariable(variable)), "omitWhenOff", omitWhenOff))

def templateProperties(properties: List<&2, R.Property<T.ChatTemplateKwargValue>>) -> List<&2, R.Property<V.Value>>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, chatTemplateKwarg(value)} <> templateProperties(rest)

def templateArgs(value: R.Record<T.ChatTemplateKwargValue>) -> V.Value:
  object(R.Record{templateProperties(R.entries(T.ChatTemplateKwargValue, value))})

def routingSort(value: T.RoutingSort) -> V.Value:
  match value:
    case T.SortByName{value}: text(value)
    case T.SortByOptions{by, partition}: object(optional(optionalText(fields(), "by", by), "partition", Maybe.map(&2, T.Nullable<String>, V.Value, nullable, partition)))

def price(value: T.PriceValue) -> V.Value:
  match value:
    case T.NumericPrice{value}: number(value)
    case T.StringPrice{value}: text(value)

def routingMaxPrice(value: T.RoutingMaxPrice) -> V.Value:
  match value:
    case T.RoutingMaxPrice{promptValue, completionValue, imageValue, audioValue, requestValue}:
      f0 = fields()
      f1 = optional(f0, "prompt", Maybe.map(&2, T.PriceValue, V.Value, price, promptValue))
      f2 = optional(f1, "completion", Maybe.map(&2, T.PriceValue, V.Value, price, completionValue))
      f3 = optional(f2, "image", Maybe.map(&2, T.PriceValue, V.Value, price, imageValue))
      f4 = optional(f3, "audio", Maybe.map(&2, T.PriceValue, V.Value, price, audioValue))
      f5 = optional(f4, "request", Maybe.map(&2, T.PriceValue, V.Value, price, requestValue))
      object(f5)

def routingPercentiles(value: T.RoutingPercentiles) -> V.Value:
  match value:
    case T.RoutingPercentiles{p50Value, p75Value, p90Value, p99Value}:
      f0 = fields()
      f1 = optionalNumber(f0, "p50", p50Value)
      f2 = optionalNumber(f1, "p75", p75Value)
      f3 = optionalNumber(f2, "p90", p90Value)
      f4 = optionalNumber(f3, "p99", p99Value)
      object(f4)

def routingPreference(value: T.RoutingPreference) -> V.Value:
  match value:
    case T.OverallPreference{value}: number(value)
    case T.PercentilePreference{values}: routingPercentiles(values)

def openRouterRouting(value: T.OpenRouterRouting) -> V.Value:
  match value:
    case T.OpenRouterRouting{allow_fallbacksValue, require_parametersValue, data_collectionValue, zdrValue, enforce_distillable_textValue, orderValue, onlyValue, ignoreValue, quantizationsValue, sortValue, max_priceValue, preferred_min_throughputValue, preferred_max_latencyValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "allow_fallbacks", allow_fallbacksValue)
      f2 = optionalBoolean(f1, "require_parameters", require_parametersValue)
      f3 = optional(f2, "data_collection", Maybe.map(&2, T.DataCollection, V.Value, dataCollection, data_collectionValue))
      f4 = optionalBoolean(f3, "zdr", zdrValue)
      f5 = optionalBoolean(f4, "enforce_distillable_text", enforce_distillable_textValue)
      f6 = optionalStrings(f5, "order", orderValue)
      f7 = optionalStrings(f6, "only", onlyValue)
      f8 = optionalStrings(f7, "ignore", ignoreValue)
      f9 = optionalStrings(f8, "quantizations", quantizationsValue)
      f10 = optional(f9, "sort", Maybe.map(&2, T.RoutingSort, V.Value, routingSort, sortValue))
      f11 = optional(f10, "max_price", Maybe.map(&2, T.RoutingMaxPrice, V.Value, routingMaxPrice, max_priceValue))
      f12 = optional(f11, "preferred_min_throughput", Maybe.map(&2, T.RoutingPreference, V.Value, routingPreference, preferred_min_throughputValue))
      f13 = optional(f12, "preferred_max_latency", Maybe.map(&2, T.RoutingPreference, V.Value, routingPreference, preferred_max_latencyValue))
      object(f13)

def vercelGatewayRouting(value: T.VercelGatewayRouting) -> V.Value:
  match value:
    case T.VercelGatewayRouting{onlyValue, orderValue}:
      f0 = fields()
      f1 = optionalStrings(f0, "only", onlyValue)
      f2 = optionalStrings(f1, "order", orderValue)
      object(f2)

def allowedFallback(value: T.AnthropicAllowedFallbackModel) -> V.Value:
  match value:
    case T.AnthropicAllowedFallbackModel{provider, model, rates}: object(put(put(put(fields(), "provider", text(provider)), "model", text(model)), "cost", cost(rates)))

def allowedFallbackValues(values: List<&2, T.AnthropicAllowedFallbackModel>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: allowedFallback(value) <> allowedFallbackValues(rest)

def allowedFallbacks(values: List<&2, T.AnthropicAllowedFallbackModel>) -> V.Value:
  V.ArrayValue{allowedFallbackValues(values)}

def openAICompletionsCompat(value: T.OpenAICompletionsCompat) -> V.Value:
  match value:
    case T.OpenAICompletionsCompat{supportsStoreValue, supportsDeveloperRoleValue, supportsReasoningEffortValue, supportsUsageInStreamingValue, supportsFinishReasonValue, maxTokensFieldValue, requiresToolResultNameValue, requiresAssistantAfterToolResultValue, requiresThinkingAsTextValue, requiresReasoningContentOnAssistantMessagesValue, thinkingFormatValue, chatTemplateKwargsValue, chatTemplateArgsValue, openRouterRoutingValue, vercelGatewayRoutingValue, zaiToolStreamValue, thinkingTokenBudgetFieldValue, supportsThinkingTokenBudgetValue, supportsOpenAIGrammarToolsValue, supportsMidConvoSystemMessagesValue, supportsMidConvoToolAdditionsValue, supportsStrictModeValue, cacheControlFormatValue, sendSessionAffinityHeadersValue, sessionAffinityFormatValue, supportsLongCacheRetentionValue, vllmPriorityValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "supportsStore", supportsStoreValue)
      f2 = optionalBoolean(f1, "supportsDeveloperRole", supportsDeveloperRoleValue)
      f3 = optionalBoolean(f2, "supportsReasoningEffort", supportsReasoningEffortValue)
      f4 = optionalBoolean(f3, "supportsUsageInStreaming", supportsUsageInStreamingValue)
      f5 = optionalBoolean(f4, "supportsFinishReason", supportsFinishReasonValue)
      f6 = optional(f5, "maxTokensField", Maybe.map(&2, T.MaxTokensField, V.Value, maxTokensField, maxTokensFieldValue))
      f7 = optionalBoolean(f6, "requiresToolResultName", requiresToolResultNameValue)
      f8 = optionalBoolean(f7, "requiresAssistantAfterToolResult", requiresAssistantAfterToolResultValue)
      f9 = optionalBoolean(f8, "requiresThinkingAsText", requiresThinkingAsTextValue)
      f10 = optionalBoolean(f9, "requiresReasoningContentOnAssistantMessages", requiresReasoningContentOnAssistantMessagesValue)
      f11 = optional(f10, "thinkingFormat", Maybe.map(&2, T.ThinkingFormat, V.Value, thinkingFormat, thinkingFormatValue))
      f12 = optional(f11, "chatTemplateKwargs", Maybe.map(&2, R.Record<T.ChatTemplateKwargValue>, V.Value, templateArgs, chatTemplateKwargsValue))
      f13 = optional(f12, "chatTemplateArgs", Maybe.map(&2, R.Record<T.ChatTemplateKwargValue>, V.Value, templateArgs, chatTemplateArgsValue))
      f14 = optional(f13, "openRouterRouting", Maybe.map(&2, T.OpenRouterRouting, V.Value, openRouterRouting, openRouterRoutingValue))
      f15 = optional(f14, "vercelGatewayRouting", Maybe.map(&2, T.VercelGatewayRouting, V.Value, vercelGatewayRouting, vercelGatewayRoutingValue))
      f16 = optionalBoolean(f15, "zaiToolStream", zaiToolStreamValue)
      f17 = optional(f16, "thinkingTokenBudgetField", Maybe.map(&2, T.ThinkingTokenBudgetField, V.Value, thinkingTokenBudgetField, thinkingTokenBudgetFieldValue))
      f18 = optionalBoolean(f17, "supportsThinkingTokenBudget", supportsThinkingTokenBudgetValue)
      f19 = optionalBoolean(f18, "supportsOpenAIGrammarTools", supportsOpenAIGrammarToolsValue)
      f20 = optionalBoolean(f19, "supportsMidConvoSystemMessages", supportsMidConvoSystemMessagesValue)
      f21 = optionalBoolean(f20, "supportsMidConvoToolAdditions", supportsMidConvoToolAdditionsValue)
      f22 = optionalBoolean(f21, "supportsStrictMode", supportsStrictModeValue)
      f23 = optional(f22, "cacheControlFormat", Maybe.map(&2, T.CacheControlFormat, V.Value, cacheControlFormat, cacheControlFormatValue))
      f24 = optionalBoolean(f23, "sendSessionAffinityHeaders", sendSessionAffinityHeadersValue)
      f25 = optional(f24, "sessionAffinityFormat", Maybe.map(&2, T.SessionAffinityFormat, V.Value, sessionAffinityFormat, sessionAffinityFormatValue))
      f26 = optionalBoolean(f25, "supportsLongCacheRetention", supportsLongCacheRetentionValue)
      f27 = optionalNumber(f26, "vllmPriority", vllmPriorityValue)
      object(f27)

def openAIResponsesCompat(value: T.OpenAIResponsesCompat) -> V.Value:
  match value:
    case T.OpenAIResponsesCompat{supportsDeveloperRoleValue, supportsMidConvoSystemMessagesValue, sessionAffinityFormatValue, supportsLongCacheRetentionValue, supportsStrictModeValue, supportsOpenAIGrammarToolsValue, supportsAdditionalToolsValue, supportsToolSearchValue, supportsExplicitPromptCacheModeValue, supportsMaxOutputTokensValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "supportsDeveloperRole", supportsDeveloperRoleValue)
      f2 = optionalBoolean(f1, "supportsMidConvoSystemMessages", supportsMidConvoSystemMessagesValue)
      f3 = optional(f2, "sessionAffinityFormat", Maybe.map(&2, T.SessionAffinityFormat, V.Value, sessionAffinityFormat, sessionAffinityFormatValue))
      f4 = optionalBoolean(f3, "supportsLongCacheRetention", supportsLongCacheRetentionValue)
      f5 = optionalBoolean(f4, "supportsStrictMode", supportsStrictModeValue)
      f6 = optionalBoolean(f5, "supportsOpenAIGrammarTools", supportsOpenAIGrammarToolsValue)
      f7 = optionalBoolean(f6, "supportsAdditionalTools", supportsAdditionalToolsValue)
      f8 = optionalBoolean(f7, "supportsToolSearch", supportsToolSearchValue)
      f9 = optionalBoolean(f8, "supportsExplicitPromptCacheMode", supportsExplicitPromptCacheModeValue)
      f10 = optionalBoolean(f9, "supportsMaxOutputTokens", supportsMaxOutputTokensValue)
      object(f10)

def anthropicMessagesCompat(value: T.AnthropicMessagesCompat) -> V.Value:
  match value:
    case T.AnthropicMessagesCompat{supportsEagerToolInputStreamingValue, supportsLongCacheRetentionValue, sendSessionAffinityHeadersValue, sessionAffinityFormatValue, supportsCacheControlOnToolsValue, supportsTemperatureValue, forceAdaptiveThinkingValue, allowEmptySignatureValue, supportsStrictToolsValue, supportsMidConvoEffortValue, supportsMidConvoSystemMessagesValue, supportsMidConvoToolChangesValue, allowedFallbackModelsValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "supportsEagerToolInputStreaming", supportsEagerToolInputStreamingValue)
      f2 = optionalBoolean(f1, "supportsLongCacheRetention", supportsLongCacheRetentionValue)
      f3 = optionalBoolean(f2, "sendSessionAffinityHeaders", sendSessionAffinityHeadersValue)
      f4 = optional(f3, "sessionAffinityFormat", Maybe.map(&2, T.AnthropicSessionAffinityFormat, V.Value, anthropicSessionAffinityFormat, sessionAffinityFormatValue))
      f5 = optionalBoolean(f4, "supportsCacheControlOnTools", supportsCacheControlOnToolsValue)
      f6 = optionalBoolean(f5, "supportsTemperature", supportsTemperatureValue)
      f7 = optionalBoolean(f6, "forceAdaptiveThinking", forceAdaptiveThinkingValue)
      f8 = optionalBoolean(f7, "allowEmptySignature", allowEmptySignatureValue)
      f9 = optionalBoolean(f8, "supportsStrictTools", supportsStrictToolsValue)
      f10 = optionalBoolean(f9, "supportsMidConvoEffort", supportsMidConvoEffortValue)
      f11 = optionalBoolean(f10, "supportsMidConvoSystemMessages", supportsMidConvoSystemMessagesValue)
      f12 = optionalBoolean(f11, "supportsMidConvoToolChanges", supportsMidConvoToolChangesValue)
      f13 = optional(f12, "allowedFallbackModels", Maybe.map(&2, List<&2, T.AnthropicAllowedFallbackModel>, V.Value, allowedFallbacks, allowedFallbackModelsValue))
      object(f13)

def bedrockCompat(value: T.BedrockCompat) -> V.Value:
  match value:
    case T.BedrockCompat{supportsStrictModeValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "supportsStrictMode", supportsStrictModeValue)
      object(f1)

def mistralConversationsCompat(value: T.MistralConversationsCompat) -> V.Value:
  match value:
    case T.MistralConversationsCompat{supportsMidConvoSystemMessagesValue}:
      f0 = fields()
      f1 = optionalBoolean(f0, "supportsMidConvoSystemMessages", supportsMidConvoSystemMessagesValue)
      object(f1)

def compatibility(api: T.ModelApi, value: Maybe<&2, T.ModelCompatibility(api)>) -> Maybe<&2, V.Value>:
  match api value:
    case T.OpenAICompletionsApi{} Some{value}: Some{openAICompletionsCompat(value)}
    case T.OpenAIResponsesApi{} Some{value}: Some{openAIResponsesCompat(value)}
    case T.AzureOpenAIResponsesApi{} Some{value}: Some{openAIResponsesCompat(value)}
    case T.OpenAICodexResponsesApi{} Some{value}: Some{openAIResponsesCompat(value)}
    case T.AnthropicMessagesApi{} Some{value}: Some{anthropicMessagesCompat(value)}
    case T.BedrockConverseStreamApi{} Some{value}: Some{bedrockCompat(value)}
    case T.MistralConversationsApi{} Some{value}: Some{mistralConversationsCompat(value)}
    case _ _: None{}

def model(value: T.Model<T.JsonValue>) -> V.Value:
  match value:
    case T.Model{id, name, +api, provider, baseUrl, reasoning, thinkingMapValue, modelInput, limitsValue, costValue, cacheValue, contextWindow, maxTokens, samplingParams, headersValue, compat}:
      f0 = fields()
      f1 = put(f0, "id", text(id))
      f2 = put(f1, "name", text(name))
      f3 = put(f2, "api", text(Api.name(api)))
      f4 = put(f3, "provider", text(provider))
      f5 = put(f4, "baseUrl", text(baseUrl))
      f6 = put(f5, "reasoning", boolean(reasoning))
      f7 = optional(f6, "thinkingLevelMap", Maybe.map(&2, T.ThinkingLevelMap, V.Value, thinkingLevelMap, thinkingMapValue))
      f8 = put(f7, "input", inputs(modelInput))
      f9 = optional(f8, "inputLimits", Maybe.map(&2, T.ModelInputLimits, V.Value, inputLimits, limitsValue))
      f10 = put(f9, "cost", cost(costValue))
      f11 = optional(f10, "promptCache", Maybe.map(&2, T.ModelPromptCache, V.Value, promptCache, cacheValue))
      f12 = put(f11, "contextWindow", number(contextWindow))
      f13 = put(f12, "maxTokens", number(maxTokens))
      f14 = optional(f13, "samplingParams", Maybe.map(&2, R.Record<T.JsonValue>, V.Value, sampling, samplingParams))
      f15 = optional(f14, "headers", Maybe.map(&2, R.Record<String>, V.Value, headers, headersValue))
      object(optional(f15, "compat", compatibility(api, compat)))
