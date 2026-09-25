import Base
import ./model-config.bend as Config
import ./resolve-config-value.bend as ConfigValue
import ../../../ai/src/types.bend as T
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/utils/model-api.bend as Api
import ../../../ai/src/utils/model-json.bend as ModelJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/abort.bend as Abort

# Composition of a built-in provider with its models.json layer
# (upstream provider-composer.ts). Extension providers (registerProvider,
# streamSimple, extension OAuth, refreshModels/modifyModels) and radius OAuth
# providers are not ported; stream dispatch stays with the api-keyed native
# providers, as upstream's composed stream falls back to the api registry.

def Model() -> Data: T.Model<T.JsonValue>

# JavaScript object spread over records: existing keys keep their position.
def assign(-A: Data, entries: List<&2, R.Property<A>>, base: R.Record<A>) -> R.Record<A>:
  match entries:
    case Nil{}: base
    case R.Property{key, value} <> rest: assign(A, rest, R.set(A, base, key, value))

def spread(-A: Data, base: R.Record<A>, entries: List<&2, R.Property<A>>) -> R.Record<A>: assign(A, entries, base)

def recordOr(-A: Data, value: Maybe<&2, R.Record<A>>) -> R.Record<A>:
  Maybe.default(&2, R.Record<A>, value, R.new(A))

def nonemptyRecord(-A: Data, +record: R.Record<A>) -> Maybe<&2, R.Record<A>>:
  Bool.pick(Maybe<&2, R.Record<A>>, List.is_empty(&2, R.Property<A>, R.entries(A, record)), None{}, Some{record})

# Compatibility
# -------------

def objectFields(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{properties}
    case _: None{}

def nestedCompatKeys() -> List<&2, String>:
  ["openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs"]

def nestedMerge(base: Maybe<&2, R.Record<V.Value>>, override: Maybe<&2, R.Record<V.Value>>, +key: String, merged: R.Record<V.Value>) -> R.Record<V.Value>:
  match base override:
    case None{} None{}: merged
    case base override: R.set(V.Value, merged, key, V.ObjectValue{spread(V.Value, recordOr(V.Value, base), R.entries(V.Value, recordOr(V.Value, override)))})

def mergeNested(keys: List<&2, String>, +base: R.Record<V.Value>, +override: R.Record<V.Value>, merged: R.Record<V.Value>) -> R.Record<V.Value>:
  match keys:
    case Nil{}: merged
    case +key <> rest: mergeNested(rest, base, override, nestedMerge(objectFields(R.get(V.Value, base, key)), objectFields(R.get(V.Value, override, key)), key, merged))

# `{...base, ...override}` with the four routing/template objects merged one
# level deeper, on the JSON form of compat.
def mergeCompat(base: Maybe<&2, V.Value>, override: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match override:
    case None{}: base
    case Some{+value}:
      +baseFields = recordOr(V.Value, objectFields(base))
      +overrideFields = recordOr(V.Value, objectFields(Some{value}))
      Some{V.ObjectValue{mergeNested(nestedCompatKeys(), baseFields, overrideFields, spread(V.Value, baseFields, R.entries(V.Value, overrideFields)))}}

def sessionAffinity(value: Maybe<&2, String>) -> Maybe<&2, T.SessionAffinityFormat>:
  match value:
    case Some{"openai"}: Some{T.OpenAISession{}}
    case Some{"openai-nosession"}: Some{T.OpenAINoSession{}}
    case Some{"openrouter"}: Some{T.OpenRouterSession{}}
    case _: None{}

def anthropicSessionAffinity(value: Maybe<&2, String>) -> Maybe<&2, T.AnthropicSessionAffinityFormat>:
  match value:
    case Some{"openrouter"}: Some{T.AnthropicOpenRouterSession{}}
    case _: None{}

def maxTokensField(value: Maybe<&2, String>) -> Maybe<&2, T.MaxTokensField>:
  match value:
    case Some{"max_completion_tokens"}: Some{T.MaxCompletionTokens{}}
    case Some{"max_tokens"}: Some{T.MaxTokens{}}
    case _: None{}

def thinkingFormat(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingFormat>:
  match value:
    case Some{"openai"}: Some{T.OpenAIThinking{}}
    case Some{"openrouter"}: Some{T.OpenRouterThinking{}}
    case Some{"deepseek"}: Some{T.DeepSeekThinking{}}
    case Some{"together"}: Some{T.TogetherThinking{}}
    case Some{"baseten"}: Some{T.BasetenThinking{}}
    case Some{"zai"}: Some{T.ZaiThinking{}}
    case Some{"qwen"}: Some{T.QwenThinking{}}
    case Some{"chat-template"}: Some{T.ChatTemplateThinking{}}
    case Some{"qwen-chat-template"}: Some{T.QwenChatTemplateThinking{}}
    case Some{"string-thinking"}: Some{T.StringThinking{}}
    case Some{"ant-ling"}: Some{T.AntLingThinking{}}
    case _: None{}

def thinkingTokenBudgetField(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingTokenBudgetField>:
  match value:
    case Some{"thinking_token_budget"}: Some{T.ThinkingTokenBudget{}}
    case Some{"thinking_budget"}: Some{T.ThinkingBudgetField{}}
    case Some{"thinking_budget_tokens"}: Some{T.ThinkingBudgetTokens{}}
    case _: None{}

def cacheControlFormat(value: Maybe<&2, String>) -> Maybe<&2, T.CacheControlFormat>:
  match value:
    case Some{"anthropic"}: Some{T.AnthropicCacheControl{}}
    case _: None{}

def dataCollection(value: Maybe<&2, String>) -> Maybe<&2, T.DataCollection>:
  match value:
    case Some{"deny"}: Some{T.DenyCollection{}}
    case Some{"allow"}: Some{T.AllowCollection{}}
    case _: None{}

def textItems(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{value} <> rest: value <> textItems(rest)
    case _ <> rest: textItems(rest)

def stringItems(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, String>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{textItems(values)}
    case _: None{}

def stringsAt(fields: R.Record<V.Value>, key: String) -> Maybe<&2, List<&2, String>>: stringItems(R.get(V.Value, fields, key))

def nullableText(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Nullable<String>>:
  match value:
    case Some{V.Text{value}}: Some{T.PresentValue{value}}
    case Some{V.Null{}}: Some{T.NullValue{}}
    case _: None{}

def routingSort(value: Maybe<&2, V.Value>) -> Maybe<&2, T.RoutingSort>:
  match value:
    case Some{V.Text{name}}: Some{T.SortByName{name}}
    case Some{V.ObjectValue{+fields}}: Some{T.SortByOptions{Config.textAt(fields, "by"), nullableText(R.get(V.Value, fields, "partition"))}}
    case _: None{}

def price(value: Maybe<&2, V.Value>) -> Maybe<&2, T.PriceValue>:
  match value:
    case Some{V.Number{amount}}: Some{T.NumericPrice{amount}}
    case Some{V.Text{amount}}: Some{T.StringPrice{amount}}
    case _: None{}

def maxPrice(value: Maybe<&2, V.Value>) -> Maybe<&2, T.RoutingMaxPrice>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.RoutingMaxPrice{price(R.get(V.Value, fields, "prompt")), price(R.get(V.Value, fields, "completion")), price(R.get(V.Value, fields, "image")), price(R.get(V.Value, fields, "audio")), price(R.get(V.Value, fields, "request"))}}
    case _: None{}

def preference(value: Maybe<&2, V.Value>) -> Maybe<&2, T.RoutingPreference>:
  match value:
    case Some{V.Number{amount}}: Some{T.OverallPreference{amount}}
    case Some{V.ObjectValue{+fields}}: Some{T.PercentilePreference{T.RoutingPercentiles{Config.numberAt(fields, "p50"), Config.numberAt(fields, "p75"), Config.numberAt(fields, "p90"), Config.numberAt(fields, "p99")}}}
    case _: None{}

def openRouterRouting(value: Maybe<&2, V.Value>) -> Maybe<&2, T.OpenRouterRouting>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.OpenRouterRouting{Config.flagAt(fields, "allow_fallbacks"), Config.flagAt(fields, "require_parameters"), dataCollection(Config.textAt(fields, "data_collection")), Config.flagAt(fields, "zdr"), Config.flagAt(fields, "enforce_distillable_text"), stringsAt(fields, "order"), stringsAt(fields, "only"), stringsAt(fields, "ignore"), stringsAt(fields, "quantizations"), routingSort(R.get(V.Value, fields, "sort")), maxPrice(R.get(V.Value, fields, "max_price")), preference(R.get(V.Value, fields, "preferred_min_throughput")), preference(R.get(V.Value, fields, "preferred_max_latency"))}}
    case _: None{}

def vercelGatewayRouting(value: Maybe<&2, V.Value>) -> Maybe<&2, T.VercelGatewayRouting>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.VercelGatewayRouting{stringsAt(fields, "only"), stringsAt(fields, "order")}}
    case _: None{}

def thinkingVariable(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingVariable>:
  match value:
    case Some{"thinking.enabled"}: Some{T.ThinkingEnabled{}}
    case Some{"thinking.effort"}: Some{T.ThinkingEffort{}}
    case Some{"thinking.budget"}: Some{T.ThinkingBudget{}}
    case _: None{}

def templateVariable(variable: Maybe<&2, T.ThinkingVariable>, omitWhenOff: Maybe<&2, Bool>) -> Maybe<&2, T.ChatTemplateKwargValue>:
  match variable:
    case None{}: None{}
    case Some{variable}: Some{T.TemplateVariable{variable, omitWhenOff}}

def templateValue(value: V.Value) -> Maybe<&2, T.ChatTemplateKwargValue>:
  match value:
    case V.Text{text}: Some{T.TemplateString{text}}
    case V.Number{amount}: Some{T.TemplateNumber{amount}}
    case V.Boolean{flag}: Some{T.TemplateBoolean{flag}}
    case V.Null{}: Some{T.TemplateNull{}}
    case V.ObjectValue{+fields}: templateVariable(thinkingVariable(Config.textAt(fields, "$var")), Config.flagAt(fields, "omitWhenOff"))
    case _: None{}

def templateEntry(key: String, value: Maybe<&2, T.ChatTemplateKwargValue>, rest: List<&2, R.Property<T.ChatTemplateKwargValue>>) -> List<&2, R.Property<T.ChatTemplateKwargValue>>:
  match value:
    case None{}: rest
    case Some{value}: R.Property{key, value} <> rest

def templateEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.ChatTemplateKwargValue>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: templateEntry(key, templateValue(value), templateEntries(rest))

def templateArgs(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<T.ChatTemplateKwargValue>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{templateEntries(R.entries(V.Value, properties))}}
    case _: None{}

def openAICompletionsCompat(+fields: R.Record<V.Value>) -> T.OpenAICompletionsCompat:
  T.OpenAICompletionsCompat{Config.flagAt(fields, "supportsStore"), Config.flagAt(fields, "supportsDeveloperRole"), Config.flagAt(fields, "supportsReasoningEffort"), Config.flagAt(fields, "supportsUsageInStreaming"), Config.flagAt(fields, "supportsFinishReason"), maxTokensField(Config.textAt(fields, "maxTokensField")), Config.flagAt(fields, "requiresToolResultName"), Config.flagAt(fields, "requiresAssistantAfterToolResult"), Config.flagAt(fields, "requiresThinkingAsText"), Config.flagAt(fields, "requiresReasoningContentOnAssistantMessages"), thinkingFormat(Config.textAt(fields, "thinkingFormat")), templateArgs(R.get(V.Value, fields, "chatTemplateKwargs")), templateArgs(R.get(V.Value, fields, "chatTemplateArgs")), openRouterRouting(R.get(V.Value, fields, "openRouterRouting")), vercelGatewayRouting(R.get(V.Value, fields, "vercelGatewayRouting")), Config.flagAt(fields, "zaiToolStream"), thinkingTokenBudgetField(Config.textAt(fields, "thinkingTokenBudgetField")), Config.flagAt(fields, "supportsThinkingTokenBudget"), Config.flagAt(fields, "supportsOpenAIGrammarTools"), Config.flagAt(fields, "supportsMidConvoSystemMessages"), Config.flagAt(fields, "supportsMidConvoToolAdditions"), Config.flagAt(fields, "supportsStrictMode"), cacheControlFormat(Config.textAt(fields, "cacheControlFormat")), Config.flagAt(fields, "sendSessionAffinityHeaders"), sessionAffinity(Config.textAt(fields, "sessionAffinityFormat")), Config.flagAt(fields, "supportsLongCacheRetention"), Config.numberAt(fields, "vllmPriority")}

def openAIResponsesCompat(+fields: R.Record<V.Value>) -> T.OpenAIResponsesCompat:
  T.OpenAIResponsesCompat{Config.flagAt(fields, "supportsDeveloperRole"), Config.flagAt(fields, "supportsMidConvoSystemMessages"), sessionAffinity(Config.textAt(fields, "sessionAffinityFormat")), Config.flagAt(fields, "supportsLongCacheRetention"), Config.flagAt(fields, "supportsStrictMode"), Config.flagAt(fields, "supportsOpenAIGrammarTools"), Config.flagAt(fields, "supportsAdditionalTools"), Config.flagAt(fields, "supportsToolSearch"), Config.flagAt(fields, "supportsExplicitPromptCacheMode"), Config.flagAt(fields, "supportsMaxOutputTokens")}

def fallbackModel(value: V.Value) -> T.AnthropicAllowedFallbackModel:
  +fields = Config.fieldsOf(Some{value})
  T.AnthropicAllowedFallbackModel{Maybe.default(&2, String, Config.textAt(fields, "provider"), ""), Maybe.default(&2, String, Config.textAt(fields, "model"), ""), Maybe.default(&2, T.ModelCost, Config.costOf(R.get(V.Value, fields, "cost")), T.ModelCost{Config.zero(), Config.zero(), Config.zero(), Config.zero(), None{}})}

def fallbackModels(values: List<&2, V.Value>) -> List<&2, T.AnthropicAllowedFallbackModel>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: fallbackModel(value) <> fallbackModels(rest)

def allowedFallbacks(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.AnthropicAllowedFallbackModel>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{fallbackModels(values)}
    case _: None{}

def anthropicMessagesCompat(+fields: R.Record<V.Value>) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{Config.flagAt(fields, "supportsEagerToolInputStreaming"), Config.flagAt(fields, "supportsLongCacheRetention"), Config.flagAt(fields, "sendSessionAffinityHeaders"), anthropicSessionAffinity(Config.textAt(fields, "sessionAffinityFormat")), Config.flagAt(fields, "supportsCacheControlOnTools"), Config.flagAt(fields, "supportsTemperature"), Config.flagAt(fields, "forceAdaptiveThinking"), Config.flagAt(fields, "allowEmptySignature"), Config.flagAt(fields, "supportsStrictTools"), Config.flagAt(fields, "supportsMidConvoEffort"), Config.flagAt(fields, "supportsMidConvoSystemMessages"), Config.flagAt(fields, "supportsMidConvoToolChanges"), allowedFallbacks(R.get(V.Value, fields, "allowedFallbackModels"))}

# The typed compat of a model's api. Keys that belong to another api's compat
# have no field in this type and are dropped; upstream carries them along in
# the untyped object, where no provider reads them.
def compatFor(api: T.ModelApi, value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelCompatibility(api)>:
  match api value:
    case T.OpenAICompletionsApi{} Some{V.ObjectValue{fields}}: Some{openAICompletionsCompat(fields)}
    case T.OpenAIResponsesApi{} Some{V.ObjectValue{fields}}: Some{openAIResponsesCompat(fields)}
    case T.AzureOpenAIResponsesApi{} Some{V.ObjectValue{fields}}: Some{openAIResponsesCompat(fields)}
    case T.OpenAICodexResponsesApi{} Some{V.ObjectValue{fields}}: Some{openAIResponsesCompat(fields)}
    case T.AnthropicMessagesApi{} Some{V.ObjectValue{+fields}}: Some{anthropicMessagesCompat(fields)}
    case T.BedrockConverseStreamApi{} Some{V.ObjectValue{fields}}: Some{T.BedrockCompat{Config.flagAt(fields, "supportsStrictMode")}}
    case T.MistralConversationsApi{} Some{V.ObjectValue{fields}}: Some{T.MistralConversationsCompat{Config.flagAt(fields, "supportsMidConvoSystemMessages")}}
    case _ _: None{}

def mergedCompat(+api: T.ModelApi, base: Maybe<&2, T.ModelCompatibility(api)>, override: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelCompatibility(api)>:
  match override:
    case None{}: base
    case Some{value}: compatFor(api, mergeCompat(ModelJson.compatibility(api, base), Some{value}))

# Model overrides
# ---------------

def levelCode(level: T.ModelThinkingLevel) -> U32:
  match level:
    case T.Off{}: 0
    case T.Thinking{T.Minimal{}}: 1
    case T.Thinking{T.Low{}}: 2
    case T.Thinking{T.Medium{}}: 3
    case T.Thinking{T.High{}}: 4
    case T.Thinking{T.XHigh{}}: 5
    case T.Thinking{T.Max{}}: 6

def setMapping(mappings: List<&2, T.ThinkingLevelMapping>, +mapping: T.ThinkingLevelMapping) -> List<&2, T.ThinkingLevelMapping>:
  match mappings mapping:
    case Nil{} _: mapping <> Nil{}
    case T.ThinkingLevelMapping{+level, +value} <> +rest T.ThinkingLevelMapping{+wanted, _}:
      Bool.pick(List<&2, T.ThinkingLevelMapping>, U32.is_eq(levelCode(level), levelCode(wanted)), mapping <> rest, T.ThinkingLevelMapping{level, value} <> setMapping(rest, mapping))

def setMappings(overrides: List<&2, T.ThinkingLevelMapping>, mappings: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match overrides:
    case Nil{}: mappings
    case mapping <> rest: setMappings(rest, setMapping(mappings, mapping))

def mappingsOf(value: Maybe<&2, T.ThinkingLevelMap>) -> List<&2, T.ThinkingLevelMapping>:
  match value:
    case Some{T.ThinkingLevelMap{properties}}: properties
    case None{}: Nil{}

def mergeThinkingLevelMap(base: Maybe<&2, T.ThinkingLevelMap>, override: Maybe<&2, T.ThinkingLevelMap>) -> Maybe<&2, T.ThinkingLevelMap>:
  match override:
    case None{}: base
    case Some{T.ThinkingLevelMap{overrides}}: Some{T.ThinkingLevelMap{setMappings(overrides, mappingsOf(base))}}

def mergeResize(base: Maybe<&2, T.ModelImageResizeOptions>, override: Maybe<&2, T.ModelImageResizeOptions>) -> Maybe<&2, T.ModelImageResizeOptions>:
  match base override:
    case base None{}: base
    case None{} override: override
    case Some{T.ModelImageResizeOptions{w, h, b, q}} Some{T.ModelImageResizeOptions{ow, oh, ob, oq}}:
      Some{T.ModelImageResizeOptions{Maybe.or(&2, F64, ow, w), Maybe.or(&2, F64, oh, h), Maybe.or(&2, F64, ob, b), Maybe.or(&2, F64, oq, q)}}

def mergeImages(base: Maybe<&2, T.ModelImageInputLimits>, override: Maybe<&2, T.ModelImageInputLimits>) -> Maybe<&2, T.ModelImageInputLimits>:
  match base override:
    case base None{}: base
    case None{} override: override
    case Some{T.ModelImageInputLimits{resize, perMessage, perRequest}} Some{T.ModelImageInputLimits{overrideResize, overrideMessage, overrideRequest}}:
      Some{T.ModelImageInputLimits{mergeResize(resize, overrideResize), Maybe.or(&2, F64, overrideMessage, perMessage), Maybe.or(&2, F64, overrideRequest, perRequest)}}

def mergeInputLimits(base: Maybe<&2, T.ModelInputLimits>, override: Maybe<&2, T.ModelInputLimits>) -> Maybe<&2, T.ModelInputLimits>:
  match base override:
    case base None{}: base
    case None{} override: override
    case Some{T.ModelInputLimits{bytes, images}} Some{T.ModelInputLimits{overrideBytes, overrideImages}}:
      Some{T.ModelInputLimits{Maybe.or(&2, F64, overrideBytes, bytes), mergeImages(images, overrideImages)}}

def overrideCost(cost: T.ModelCost, override: Maybe<&2, Config.ModelCostOverride>) -> T.ModelCost:
  match cost override:
    case cost None{}: cost
    case T.ModelCost{i, o, r, w, tiers} Some{Config.ModelCostOverride{oi, oo, orr, ow, otiers}}:
      T.ModelCost{Maybe.default(&2, F64, oi, i), Maybe.default(&2, F64, oo, o), Maybe.default(&2, F64, orr, r), Maybe.default(&2, F64, ow, w), Maybe.or(&2, List<&2, T.ModelCostTier>, otiers, tiers)}

def mergePromptCache(base: Maybe<&2, T.ModelPromptCache>, override: Maybe<&2, T.ModelPromptCache>) -> Maybe<&2, T.ModelPromptCache>:
  match base override:
    case base None{}: base
    case None{} override: override
    case Some{T.ModelPromptCache{short, long}} Some{T.ModelPromptCache{overrideShort, overrideLong}}:
      Some{T.ModelPromptCache{Maybe.or(&2, F64, overrideShort, short), Maybe.or(&2, F64, overrideLong, long)}}

def mergeSampling(base: Maybe<&2, R.Record<T.JsonValue>>, override: Maybe<&2, R.Record<T.JsonValue>>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match override:
    case None{}: base
    case Some{values}: Some{spread(T.JsonValue, recordOr(T.JsonValue, base), R.entries(T.JsonValue, values))}

# Headers from an override apply at request time, not to the model.
def applyModelOverride(model: Model(), override: Config.ModelsJsonModelOverride) -> Model():
  match model override:
    case T.Model{id, name, +api, provider, baseUrl, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, headers, compat} Config.ModelsJsonModelOverride{overrideName, overrideReasoning, overrideLevels, overrideInputs, overrideLimits, overrideCostValue, overrideCache, overrideWindow, overrideMaximum, overrideSampling, _, overrideCompat}:
      T.Model{id, Maybe.default(&2, String, overrideName, name), api, provider, baseUrl, Maybe.default(&2, Bool, overrideReasoning, reasoning), mergeThinkingLevelMap(levels, overrideLevels), Maybe.default(&2, List<&2, T.ModelInput>, overrideInputs, inputs), mergeInputLimits(limits, overrideLimits), overrideCost(cost, overrideCostValue), mergePromptCache(cache, overrideCache), Maybe.default(&2, F64, overrideWindow, window), Maybe.default(&2, F64, overrideMaximum, maximum), mergeSampling(sampling, overrideSampling), headers, mergedCompat(api, compat, overrideCompat)}

def modelId(model: Model()) -> String: T.modelId(model)

def modelApiName(model: Model()) -> String:
  match model:
    case T.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: Api.name(api)

def modelBaseUrl(model: Model()) -> String:
  match model:
    case T.Model{_, _, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: baseUrl

def overrideFor(overrides: Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>, +model: Model()) -> Model():
  match overrides:
    case None{}: model
    case Some{+entries}: Maybe.default(&2, Model(), Maybe.map(&2, Config.ModelsJsonModelOverride, Model(), override => applyModelOverride(model, override), R.get(Config.ModelsJsonModelOverride, entries, modelId(model))), model)

def applyOverrides(models: List<&2, Model()>, +overrides: Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: overrideFor(overrides, model) <> applyOverrides(rest, overrides)

# models.json models
# ------------------

def overridesOf(config: Config.ModelsJsonProvider) -> Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, _, _, _, overrides}: overrides


def withId(models: List<&2, Model()>, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, Model()>, String.eq(modelId(model), id), Some{model}, withId(rest, id))

def withApi(models: List<&2, Model()>, +api: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, Model()>, String.eq(modelApiName(model), api), Some{model}, withApi(rest, api))

def withRequestedApi(+models: List<&2, Model()>, api: Maybe<&2, String>) -> Maybe<&2, Model()>:
  match api:
    case None{}: None{}
    case Some{api}: withApi(models, api)

def findModelDefaults(+models: List<&2, Model()>, id: String, api: Maybe<&2, String>) -> Maybe<&2, Model()>:
  Maybe.or(&2, Model(), withId(models, id), Maybe.or(&2, Model(), withRequestedApi(models, api), Maybe.or(&2, Model(), withApi(models, "openai-completions"), List.head(&2, Model(), models))))

def greater(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case _: False{}

def positive(value: F64) -> Bool: greater(F.compare(value, Config.zero()))

def invalidSize(value: Maybe<&2, F64>) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: Bool.not(positive(value))

def defaultCost() -> T.ModelCost: T.ModelCost{Config.zero(), Config.zero(), Config.zero(), Config.zero(), None{}}

def builtModel(providerId: String, definition: Config.ModelsJsonModel, providerCompat: Maybe<&2, V.Value>, +api: T.ModelApi, baseUrl: String) -> Model():
  match definition:
    case Config.ModelsJsonModel{+id, name, _, _, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, _, compat}:
      T.Model{id, Maybe.default(&2, String, name, id), api, providerId, baseUrl, Maybe.default(&2, Bool, reasoning, False{}), levels, Maybe.default(&2, List<&2, T.ModelInput>, inputs, T.InputText{} <> Nil{}), limits, Maybe.default(&2, T.ModelCost, cost, defaultCost()), cache, Maybe.default(&2, F64, window, F.fromU32(128000)), Maybe.default(&2, F64, maximum, F.fromU32(16384)), sampling, None{}, compatFor(api, mergeCompat(providerCompat, compat))}

def definitionId(definition: Config.ModelsJsonModel) -> String:
  match definition:
    case Config.ModelsJsonModel{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def definitionApi(definition: Config.ModelsJsonModel) -> Maybe<&2, String>:
  match definition:
    case Config.ModelsJsonModel{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _}: api

def definitionBaseUrl(definition: Config.ModelsJsonModel) -> Maybe<&2, String>:
  match definition:
    case Config.ModelsJsonModel{_, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: baseUrl

def definitionSizes(definition: Config.ModelsJsonModel) -> Maybe<&2, F64> & Maybe<&2, F64>:
  match definition:
    case Config.ModelsJsonModel{_, _, _, _, _, _, _, _, _, _, window, maximum, _, _, _}: (window, maximum)

def providerApi(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, api, _, _, _, _, _, _}: api

def providerBaseUrl(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{_, baseUrl, _, _, _, _, _, _, _, _}: baseUrl

def providerCompat(config: Config.ModelsJsonProvider) -> Maybe<&2, V.Value>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, compat, _, _, _}: compat

def sizedModel(+providerId: String, +definition: Config.ModelsJsonModel, providerCompat: Maybe<&2, V.Value>, api: String, baseUrl: String, sizes: Maybe<&2, F64> & Maybe<&2, F64>) -> Result<&2, &2, String, Model()>:
  match sizes:
    case (window, maximum):
      Bool.pick(Unit -> Result<&2, &2, String, Model()>, invalidSize(window),
        _ => Fail{"Provider " ++ providerId ++ ", model " ++ definitionId(definition) ++ ": invalid contextWindow"},
        _ => Bool.pick(Unit -> Result<&2, &2, String, Model()>, invalidSize(maximum),
          _ => Fail{"Provider " ++ providerId ++ ", model " ++ definitionId(definition) ++ ": invalid maxTokens"},
          _ => Done{builtModel(providerId, definition, providerCompat, Api.fromString(api), baseUrl)})(Unit{}))(Unit{})

def locatedModel(+providerId: String, +definition: Config.ModelsJsonModel, providerCompat: Maybe<&2, V.Value>, api: String, baseUrl: Maybe<&2, String>) -> Result<&2, &2, String, Model()>:
  match baseUrl:
    case None{}: Fail{"Provider " ++ providerId ++ ": \"baseUrl\" is required when defining custom models."}
    case Some{url}: sizedModel(providerId, definition, providerCompat, api, url, definitionSizes(definition))

def apiModel(+providerId: String, +definition: Config.ModelsJsonModel, +config: Config.ModelsJsonProvider, +defaults: Maybe<&2, Model()>, api: Maybe<&2, String>) -> Result<&2, &2, String, Model()>:
  match api:
    case None{}: Fail{"Provider " ++ providerId ++ ", model " ++ definitionId(definition) ++ ": no \"api\" specified. Set at provider or model level."}
    case Some{api}: locatedModel(providerId, definition, providerCompat(config), api, Maybe.or(&2, String, definitionBaseUrl(definition), Maybe.or(&2, String, providerBaseUrl(config), Maybe.map(&2, Model(), String, modelBaseUrl, defaults))))

# A models.json definition; api and baseUrl fall back to the provider entry,
# then to the built-in defaults model. Other fields never inherit.
def modelFromJson(+providerId: String, +definition: Config.ModelsJsonModel, +config: Config.ModelsJsonProvider, +defaults: Maybe<&2, Model()>) -> Result<&2, &2, String, Model()>:
  apiModel(providerId, definition, config, defaults, Maybe.or(&2, String, definitionApi(definition), Maybe.or(&2, String, providerApi(config), Maybe.map(&2, Model(), String, modelApiName, defaults))))

def replaced(models: List<&2, Model()>, +model: Model()) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +existing <> +rest: Bool.pick(List<&2, Model()>, String.eq(modelId(existing), modelId(model)), model <> rest, existing <> replaced(rest, model))

def upsert(+models: List<&2, Model()>, +model: Model()) -> List<&2, Model()>:
  Bool.pick(List<&2, Model()>, Maybe.is_some(&2, Model(), withId(models, modelId(model))), replaced(models, model), List.append(&2, Model(), models, model <> Nil{}))

def applyDefinitions(+providerId: String, definitions: List<&2, Config.ModelsJsonModel>, +config: Config.ModelsJsonProvider, +models: List<&2, Model()>) -> Result<&2, &2, String, List<&2, Model()>>:
  match definitions:
    case Nil{}: Done{models}
    case +definition <> rest:
      Result.bind(&2, &2, String, Model(), List<&2, Model()>, modelFromJson(providerId, definition, config, findModelDefaults(models, definitionId(definition), Maybe.or(&2, String, definitionApi(definition), providerApi(config)))), model => applyDefinitions(providerId, rest, config, upsert(models, model)))

def withProviderConfig(model: Model(), baseUrl: Maybe<&2, String>, compat: Maybe<&2, V.Value>) -> Model():
  match model:
    case T.Model{id, name, +api, provider, url, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, headers, compatValue}:
      T.Model{id, name, api, provider, Maybe.default(&2, String, baseUrl, url), reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, headers, mergedCompat(api, compatValue, compat)}

def configuredBase(models: List<&2, Model()>, +baseUrl: Maybe<&2, String>, +compat: Maybe<&2, V.Value>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: withProviderConfig(model, baseUrl, compat) <> configuredBase(rest, baseUrl, compat)

# A radius provider keeps its own model base URLs.
def modelBaseUrlOverride(oauth: Maybe<&2, Config.ProviderOAuth>, baseUrl: Maybe<&2, String>) -> Maybe<&2, String>:
  match oauth:
    case Some{Config.RadiusOAuth{}}: None{}
    case None{}: baseUrl

def hasItems(-A: Data, value: Maybe<&2, List<&2, A>>) -> Bool:
  match value:
    case Some{_ <> _}: True{}
    case _: False{}

def hasEntries(-A: Data, value: Maybe<&2, R.Record<A>>) -> Bool:
  match value:
    case Some{R.Record{_ <> _}}: True{}
    case _: False{}

def specified(config: Config.ModelsJsonProvider) -> Bool:
  match config:
    case Config.ModelsJsonProvider{_, baseUrl, apiKey, _, oauth, headers, compat, authHeader, models, overrides}:
      hasItems(Config.ModelsJsonModel, models) || Maybe.is_some(&2, String, baseUrl) || Maybe.is_some(&2, R.Record<String>, headers) || Maybe.is_some(&2, V.Value, compat) || hasEntries(Config.ModelsJsonModelOverride, overrides) || Maybe.is_some(&2, String, apiKey) || Maybe.is_some(&2, Config.ProviderOAuth, oauth) || Maybe.is_some(&2, Bool, authHeader)

def oauthWithoutBaseUrl(config: Config.ModelsJsonProvider) -> Bool:
  match config:
    case Config.ModelsJsonProvider{_, None{}, _, _, Some{_}, _, _, _, _, _}: True{}
    case _: False{}

def definitionsOf(config: Config.ModelsJsonProvider) -> List<&2, Config.ModelsJsonModel>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, _, _, models, _}: Maybe.default(&2, List<&2, Config.ModelsJsonModel>, models, Nil{})

def configuredModels(+providerId: String, baseModels: List<&2, Model()>, +config: Config.ModelsJsonProvider) -> Result<&2, &2, String, List<&2, Model()>>:
  match config:
    case Config.ModelsJsonProvider{_, baseUrl, _, _, oauth, _, compat, _, _, _}:
      applyDefinitions(providerId, definitionsOf(config), config, configuredBase(baseModels, modelBaseUrlOverride(oauth, baseUrl), compat))

# Built-in models with the provider's baseUrl and compat, then models.json
# definitions upserted by id.
def applyModelsJson(+providerId: String, baseModels: List<&2, Model()>, +config: Config.ModelsJsonProvider) -> Result<&2, &2, String, List<&2, Model()>>:
  Bool.pick(Unit -> Result<&2, &2, String, List<&2, Model()>>, oauthWithoutBaseUrl(config),
    _ => Fail{"Provider " ++ providerId ++ ": \"baseUrl\" is required when \"oauth\" is set."},
    _ => Bool.pick(Unit -> Result<&2, &2, String, List<&2, Model()>>, specified(config),
      _ => configuredModels(providerId, baseModels, config),
      _ => Fail{"Provider " ++ providerId ++ ": must specify \"baseUrl\", \"headers\", \"compat\", \"modelOverrides\", or \"models\"."})(Unit{}))(Unit{})

# Configured values
# -----------------

def resolutionFailure(+description: String, +config: String, missing: List<&2, String>) -> String:
  match missing:
    case name <> Nil{}: "Failed to resolve " ++ description ++ " from environment variable: " ++ name
    case name <> rest: "Failed to resolve " ++ description ++ " from environment variables: " ++ String.join(name <> rest, ", ")
    case Nil{}: Bool.pick(String, ConfigValue.isCommandConfigValue(config), "Failed to resolve " ++ description ++ " from shell command: " ++ String.drop(config, 1n), "Failed to resolve " ++ description)

def resolvedOrFailure(value: Maybe<&2, String>, +description: String, +config: String, missing: List<&2, String>) -> Result<&2, &2, String, String>:
  match value:
    case Some{value}: Done{value}
    case None{}: Fail{resolutionFailure(description, config, missing)}

# Uncached, so commands run on every resolution.
def resolveConfigValueOrThrow(+config: String, description: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    value : Maybe<&2, String> <- ConfigValue.resolveConfigValueUncached(config, env)
    missing : List<&2, String> <- ConfigValue.getMissingConfigValueEnvVarNames(config, env)
    return resolvedOrFailure(value, description, config, missing)

def resolveEntries(entries: List<&2, R.Property<String>>, +description: String, +env: Maybe<&2, T.ProviderEnv()>, resolved: Result<&2, &2, String, List<&2, R.Property<String>>>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  match entries resolved:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Fail{error})
    case Nil{} Done{reversed}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Done{List.reverse(&2, R.Property<String>, reversed)})
    case R.Property{+key, value} <> rest Done{reversed}:
      do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
        result : Result<&2, &2, String, String> <- resolveConfigValueOrThrow(value, description ++ " header \"" ++ key ++ "\"", env)
        resolveEntries(rest, description, env, Result.map(&2, &2, String, String, List<&2, R.Property<String>>, header => R.Property{key, header} <> reversed, result))

def nonemptyHeaders(result: Result<&2, &2, String, List<&2, R.Property<String>>>) -> Result<&2, &2, String, Maybe<&2, R.Record<String>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Nil{}}: Done{None{}}
    case Done{entries}: Done{Some{R.Record{entries}}}

def resolveHeadersOrThrow(headers: Maybe<&2, R.Record<String>>, +description: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, Maybe<&2, R.Record<String>>>):
  match headers:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, R.Record<String>>>, Done{None{}})
    case Some{values}:
      do IO<Result<&2, &2, String, Maybe<&2, R.Record<String>>>>:
        result : Result<&2, &2, String, List<&2, R.Property<String>>> <- resolveEntries(R.entries(String, values), description, env, Done{Nil{}})
        return nonemptyHeaders(result)

def containsText(values: List<&2, String>, +wanted: String) -> Bool:
  match values:
    case Nil{}: False{}
    case +value <> rest: String.eq(value, wanted) || containsText(rest, wanted)

def uniqueNames(names: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: List.reverse(&2, String, seen)
    case +name <> rest: uniqueNames(rest, Bool.pick(List<&2, String>, containsText(seen, name), seen, name <> seen))

def referencedNames(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: List.append(&2, String, ConfigValue.getConfigValueEnvVarNames(value), referencedNames(rest))

def setFound(env: R.Record<String>, name: String, value: Maybe<&2, String>) -> R.Record<String>:
  match value:
    case None{}: env
    case Some{value}: R.set(String, env, name, value)

def lookupMissing(existing: Maybe<&2, String>, context: Auth.AuthContext, name: String) -> IO(Maybe<&2, String>):
  match existing:
    case Some{value}: IO.pure(Maybe<&2, String>, Some{value})
    case None{}: Auth.envValue(context, name)

def fillEnv(names: List<&2, String>, +context: Auth.AuthContext, +env: R.Record<String>) -> IO(R.Record<String>):
  match names:
    case Nil{}: IO.pure(R.Record<String>, env)
    case +name <> rest:
      do IO<R.Record<String>>:
        value : Maybe<&2, String> <- lookupMissing(R.get(String, env, name), context, name)
        fillEnv(rest, context, setFound(env, name, value))

# The explicit values plus the context's values of every variable the given
# config values reference.
def configContextEnv(values: List<&2, String>, context: Auth.AuthContext, explicit: R.Record<String>) -> IO(Maybe<&2, T.ProviderEnv()>):
  do IO<Maybe<&2, T.ProviderEnv()>>:
    +env : R.Record<String> <- fillEnv(uniqueNames(referencedNames(values), Nil{}), context, explicit)
    return nonemptyRecord(String, env)

def headerValues(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{_, value} <> rest: value <> headerValues(rest)

def present(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, T.PresentValue{value}} <> present(rest)

def mergedHeaders(existing: Maybe<&2, T.ProviderHeaders()>, headers: Maybe<&2, R.Record<String>>) -> Maybe<&2, T.ProviderHeaders()>:
  match existing headers:
    case None{} None{}: None{}
    case existing headers: Some{spread(T.Nullable<String>, recordOr(T.Nullable<String>, existing), present(R.entries(String, recordOr(String, headers))))}

def bearer(apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, baseUrl: Maybe<&2, String>) -> Result<&2, &2, String, Auth.ModelAuth>:
  match apiKey:
    case Some{SCon{+c, +cs}}: Done{Auth.ModelAuth{Some{SCon{c, cs}}, Some{R.set(T.Nullable<String>, recordOr(T.Nullable<String>, headers), "Authorization", T.PresentValue{"Bearer " ++ SCon{c, cs}})}, baseUrl}}
    case _: Fail{"authHeader requires a resolved API key"}

def withConfiguredAuth(modelAuth: Auth.ModelAuth, headers: Maybe<&2, R.Record<String>>, bearerHeader: Bool) -> Result<&2, &2, String, Auth.ModelAuth>:
  match modelAuth bearerHeader:
    case Auth.ModelAuth{apiKey, existing, baseUrl} False{}: Done{Auth.ModelAuth{apiKey, mergedHeaders(existing, headers), baseUrl}}
    case Auth.ModelAuth{apiKey, existing, baseUrl} True{}: bearer(apiKey, mergedHeaders(existing, headers), baseUrl)

def textEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, V.Text{value}} <> rest: R.Property{key, value} <> textEntries(rest)
    case _ <> rest: textEntries(rest)

# A credential's own environment; OAuth credentials keep it among their
# flow-specific members.
def credentialEnv(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, T.ProviderEnv()>:
  match credential:
    case Some{Auth.ApiKeyCredential{_, env}}: env
    case Some{Auth.OAuthCredential{_, _, _, extra}}: Maybe.map(&2, R.Record<V.Value>, R.Record<String>, fields => R.Record{textEntries(R.entries(V.Value, fields))}, objectFields(R.get(V.Value, extra, "env")))
    case None{}: None{}

# Composed API-key auth
# ---------------------

type KeyConfig is Data:
  KeyConfig{providerId: String, inherited: Maybe<&2, Auth.ApiKeyAuth>, rawKey: Maybe<&2, String>, rawHeaders: Maybe<&2, R.Record<String>>, authHeader: Bool}

def inheritedResolve(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match inheritedAuth:
    case None{}: IO.pure(Auth.AuthOutcome(), Done{None{}})
    case Some{Auth.ApiKeyAuth{_, _, resolve}}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, input)
def loginDefaultResult(value: Result<&2,&2,String,String>) -> Auth.LoginOutcome():
  match value:
    case Fail{reason}: Fail{reason}
    case Done{SNil{}}: Fail{"API key cannot be empty"}
    case Done{key}: Done{Auth.ApiKeyCredential{Some{key},None{}}}
def loginDefault(interaction: Auth.LoginInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.LoginInteraction{_,prompt}:
      do IO<Auth.LoginOutcome()>:
        value : Result<&2,&2,String,String> <- C.call(Auth.LoginPrompt,Result<&2,&2,String,String>,prompt,Auth.LoginPrompt{"Enter API key",True{}})
        return loginDefaultResult(value)
def loginInherited(inherited: Maybe<&2,Auth.ApiKeyAuth>,interaction: Auth.LoginInteraction) -> IO(Auth.LoginOutcome()):
  match inherited:
    case Some{Auth.ApiKeyAuth{_,Some{callback},_}}: C.call(Auth.LoginInteraction,Auth.LoginOutcome(),callback,interaction)
    case _: loginDefault(interaction)
def loginConfigured(config: KeyConfig,interaction: Auth.LoginInteraction) -> IO(Auth.LoginOutcome()):
  match config:
    case KeyConfig{_,inherited,_,_,_}: loginInherited(inherited,interaction)

def keyResult(key: String, env: Maybe<&2, T.ProviderEnv()>, source: String) -> Auth.AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, None{}}, env, Some{source}}}}

def storedKey(credential: Auth.Credential) -> Auth.AuthOutcome():
  match credential:
    case Auth.ApiKeyCredential{Some{SCon{c, cs}}, env}: keyResult(SCon{c, cs}, env, "stored credential")
    case _: Done{None{}}

def storedResult(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, input: Auth.ResolveInput, credential: Auth.Credential) -> IO(Auth.AuthOutcome()):
  match inheritedAuth:
    case None{}: IO.pure(Auth.AuthOutcome(), storedKey(credential))
    case inheritedAuth: inheritedResolve(inheritedAuth, input)

# A configured key reaches an inherited resolver as if it were stored.
def configuredKey(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, context: Auth.AuthContext, signal: Abort.AbortSignal<Unit>, key: Result<&2, &2, String, String>) -> IO(Auth.AuthOutcome()):
  match inheritedAuth key:
    case _ Fail{error}: IO.pure(Auth.AuthOutcome(), Fail{error})
    case None{} Done{key}: IO.pure(Auth.AuthOutcome(), keyResult(key, None{}, "configured API key"))
    case inheritedAuth Done{key}: inheritedResolve(inheritedAuth, Auth.ResolveInput{context, Some{Auth.ApiKeyCredential{Some{key}, None{}}}, signal})

def baseOutcome(+providerId: String, inherited: Maybe<&2, Auth.ApiKeyAuth>, rawValue: Maybe<&2, String>, +context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  match rawValue credential:
    case _ Some{+stored}: storedResult(inherited, Auth.ResolveInput{context, Some{stored}, signal}, stored)
    case Some{+raw} None{}:
      do IO<Auth.AuthOutcome()>:
        env : Maybe<&2, T.ProviderEnv()> <- configContextEnv(raw <> Nil{}, context, R.new(String))
        key : Result<&2, &2, String, String> <- resolveConfigValueOrThrow(raw, "API key for provider \"" ++ providerId ++ "\"", env)
        configuredKey(inherited, context, signal, key)
    case None{} None{}: inheritedResolve(inherited, Auth.ResolveInput{context, None{}, signal})

def configuredResult(headers: Result<&2, &2, String, Maybe<&2, R.Record<String>>>, auth: Auth.ModelAuth, env: Maybe<&2, T.ProviderEnv()>, source: Maybe<&2, String>, authHeader: Bool) -> Auth.AuthOutcome():
  match headers:
    case Fail{error}: Fail{error}
    case Done{headers}: Result.map(&2, &2, String, Auth.ModelAuth, Maybe<&2, Auth.AuthResult>, configured => Some{Auth.AuthResult{configured, env, source}}, withConfiguredAuth(auth, headers, authHeader))

def withHeaders(outcome: Auth.AuthOutcome(), providerId: String, +rawHeaders: Maybe<&2, R.Record<String>>, authHeader: Bool, context: Auth.AuthContext, explicit: Maybe<&2, T.ProviderEnv()>) -> IO(Auth.AuthOutcome()):
  match outcome:
    case Fail{error}: IO.pure(Auth.AuthOutcome(), Fail{error})
    case Done{None{}}: IO.pure(Auth.AuthOutcome(), Done{None{}})
    case Done{Some{Auth.AuthResult{auth, +env, source}}}:
      do IO<Auth.AuthOutcome()>:
        +headerEnv : Maybe<&2, T.ProviderEnv()> <- configContextEnv(headerValues(R.entries(String, recordOr(String, rawHeaders))), context, spread(String, recordOr(String, explicit), R.entries(String, recordOr(String, env))))
        headers : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- resolveHeadersOrThrow(rawHeaders, "provider \"" ++ providerId ++ "\"", headerEnv)
        return configuredResult(headers, auth, env, source, authHeader)

def resolveConfigured(config: KeyConfig, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match config input:
    case KeyConfig{+providerId, inherited, rawKey, rawHeaders, authHeader} Auth.ResolveInput{+context, +credential, signal}:
      do IO<Auth.AuthOutcome()>:
        outcome : Auth.AuthOutcome() <- baseOutcome(providerId, inherited, rawKey, context, credential, signal)
        withHeaders(outcome, providerId, rawHeaders, authHeader, context, credentialEnv(credential))

# Parts of the base provider's auth that a composed wrapper owns.
type Retained is Data:
  RetainedApiKey{auth: Auth.ApiKeyAuth}
  RetainedToAuth{toAuth: C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>>}

def disposeRetained(items: List<&2, Retained>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit, Unit{})
    case RetainedApiKey{auth} <> rest:
      do IO<Unit>:
        Auth.disposeApiKeyAuth(auth)
        disposeRetained(rest)
    case RetainedToAuth{toAuth} <> rest:
      do IO<Unit>:
        C.dispose(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth)
        disposeRetained(rest)

type Composition<-A: Data> is Data:
  Composition{auth: Maybe<&2, A>, retained: List<&2, Retained>}

def retainedKey(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>) -> List<&2, Retained>:
  match inheritedAuth:
    case None{}: Nil{}
    case Some{wrapped}: RetainedApiKey{wrapped} <> Nil{}

def inheritedName(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>) -> String:
  match inheritedAuth:
    case Some{Auth.ApiKeyAuth{name, _, _}}: name
    case None{}: "API key"

def wrappedKey(+config: KeyConfig) -> IO(Composition<Auth.ApiKeyAuth>):
  match config:
    case KeyConfig{_, +inherited, _, _, _}:
      do IO<Composition<Auth.ApiKeyAuth>>:
        resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~KeyConfig, ~Auth.ResolveInput, ~(Auth.AuthOutcome()), ~resolveConfigured, config)
        login : C.Callback<Auth.LoginInteraction,Auth.LoginOutcome()> <- C.create(~KeyConfig,~Auth.LoginInteraction,~(Auth.LoginOutcome()),~loginConfigured,config)
        return Composition{Some{Auth.ApiKeyAuth{inheritedName(inherited), Some{login}, resolve}}, retainedKey(inherited)}

def configuredHeaders(config: Config.ModelsJsonProvider) -> Maybe<&2, R.Record<String>>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, headers, _, _, _, _}: headers

def configuredApiKey(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{_, _, apiKey, _, _, _, _, _, _, _}: apiKey

def configuredAuthHeader(config: Config.ModelsJsonProvider) -> Bool:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, _, authHeader, _, _}: Maybe.default(&2, Bool, authHeader, False{})

# OAuth-only providers get no fabricated API-key method. Without configured
# key, headers or authHeader the inherited method is used unchanged, which
# resolves identically to upstream's wrapper.
def composedKey(+providerId: String, inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, oauth: Bool, keyValue: Maybe<&2, String>, +headerConfig: Maybe<&2, R.Record<String>>, +bearerHeader: Bool) -> IO(Composition<Auth.ApiKeyAuth>):
  match inheritedAuth keyValue headerConfig bearerHeader:
    case None{} None{} _ _:
      Bool.pick(Unit -> IO(Composition<Auth.ApiKeyAuth>), oauth, _ => IO.pure(Composition<Auth.ApiKeyAuth>, Composition{None{}, Nil{}}), _ => wrappedKey(KeyConfig{providerId, None{}, None{}, headerConfig, bearerHeader}))(Unit{})
    case Some{auth} None{} None{} False{}: IO.pure(Composition<Auth.ApiKeyAuth>, Composition{Some{auth}, Nil{}})
    case inheritedAuth keyValue headerConfig bearerHeader: wrappedKey(KeyConfig{providerId, inheritedAuth, keyValue, headerConfig, bearerHeader})

def composeApiKeyAuth(+providerId: String, inherited: Maybe<&2, Auth.ApiKeyAuth>, oauth: Bool, +config: Config.ModelsJsonProvider) -> IO(Composition<Auth.ApiKeyAuth>):
  composedKey(providerId, inherited, oauth, configuredApiKey(config), configuredHeaders(config), configuredAuthHeader(config))

# Composed OAuth auth
# -------------------

type OAuthConfig is Data:
  OAuthConfig{providerId: String, toAuth: C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>>, rawHeaders: Maybe<&2, R.Record<String>>, authHeader: Bool}

def oauthHeaders(derived: Result<&2, &2, String, Auth.ModelAuth>, +providerId: String, headerConfig: Maybe<&2, R.Record<String>>, bearerHeader: Bool, env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match derived:
    case Fail{error}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{error})
    case Done{derived}:
      do IO<Result<&2, &2, String, Auth.ModelAuth>>:
        headers : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- resolveHeadersOrThrow(headerConfig, "provider \"" ++ providerId ++ "\"", env)
        return Result.bind(&2, &2, String, Maybe<&2, R.Record<String>>, Auth.ModelAuth, headers, resolved => withConfiguredAuth(derived, resolved, bearerHeader))

def toAuthWith(config: OAuthConfig, +credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match config:
    case OAuthConfig{providerId, toAuth, rawHeaders, authHeader}:
      do IO<Result<&2, &2, String, Auth.ModelAuth>>:
        auth : Result<&2, &2, String, Auth.ModelAuth> <- C.call(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth, credential)
        oauthHeaders(auth, providerId, rawHeaders, authHeader, credentialEnv(Some{credential}))

def toAuthConfigured(config: OAuthConfig, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  toAuthWith(config, credential)

def wrappedOAuth(providerId: String, oauth: Auth.OAuthAuth, rawHeaders: Maybe<&2, R.Record<String>>, authHeader: Bool) -> IO(Composition<Auth.OAuthAuth>):
  match oauth:
    case Auth.OAuthAuth{name, subscription, label, refresh, +toAuth}:
      do IO<Composition<Auth.OAuthAuth>>:
        wrapped : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~OAuthConfig, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuthConfigured, OAuthConfig{providerId, toAuth, rawHeaders, authHeader})
        return Composition{Some{Auth.OAuthAuth{name, subscription, label, refresh, wrapped}}, RetainedToAuth{toAuth} <> Nil{}}

# The base OAuth method with configured headers applied to its request auth;
# unchanged when nothing is configured.
def composedOAuth(providerId: String, base: Maybe<&2, Auth.OAuthAuth>, headerConfig: Maybe<&2, R.Record<String>>, bearerHeader: Bool) -> IO(Composition<Auth.OAuthAuth>):
  match base headerConfig bearerHeader:
    case None{} _ _: IO.pure(Composition<Auth.OAuthAuth>, Composition{None{}, Nil{}})
    case Some{oauth} None{} False{}: IO.pure(Composition<Auth.OAuthAuth>, Composition{Some{oauth}, Nil{}})
    case Some{oauth} headers bearerHeader: wrappedOAuth(providerId, oauth, headers, bearerHeader)

def composeOAuthAuth(providerId: String, base: Maybe<&2, Auth.OAuthAuth>, +config: Config.ModelsJsonProvider) -> IO(Composition<Auth.OAuthAuth>):
  composedOAuth(providerId, base, configuredHeaders(config), configuredAuthHeader(config))

# Provider composition
# --------------------

type Base is Data:
  Base{name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, Model()>}

type Composed is Data:
  Composed{name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, Model()>, retained: List<&2, Retained>}

def baseModels(base: Maybe<&2, Base>) -> List<&2, Model()>:
  match base:
    case Some{Base{_, _, _, models}}: models
    case None{}: Nil{}

def baseAuth(base: Maybe<&2, Base>) -> Auth.ProviderAuth:
  match base:
    case Some{Base{_, _, auth, _}}: auth
    case None{}: Auth.ProviderAuth{None{}, None{}}

def providerName(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{name, _, _, _, _, _, _, _, _, _}: name

def composedName(+providerId: String, config: Config.ModelsJsonProvider, base: Maybe<&2, Base>) -> String:
  match base:
    case Some{Base{name, _, _, _}}: Maybe.default(&2, String, providerName(config), name)
    case None{}: Maybe.default(&2, String, providerName(config), providerId)

# Provider.baseUrl is a string; a custom provider without one has "".
def composedBaseUrl(config: Config.ModelsJsonProvider, base: Maybe<&2, Base>) -> String:
  match base:
    case Some{Base{_, url, _, _}}: Maybe.default(&2, String, providerBaseUrl(config), url)
    case None{}: Maybe.default(&2, String, providerBaseUrl(config), "")

def composedAuth(+providerId: String, name: String, baseUrl: String, models: List<&2, Model()>, apiKey: Composition<Auth.ApiKeyAuth>, oauth: Composition<Auth.OAuthAuth>) -> Result<&2, &2, String, Composed>:
  match apiKey oauth:
    case Composition{None{}, _} Composition{None{}, _}: Fail{"Provider " ++ providerId ++ ": no authentication method configured."}
    case Composition{key, keyRetained} Composition{method, methodRetained}: Done{Composed{name, baseUrl, Auth.ProviderAuth{key, method}, models, List.append(&2, Retained, keyRetained, methodRetained)}}

def composeAuth(+providerId: String, +base: Maybe<&2, Base>, +config: Config.ModelsJsonProvider, models: List<&2, Model()>, providerAuth: Auth.ProviderAuth) -> IO(Result<&2, &2, String, Composed>):
  match providerAuth:
    case Auth.ProviderAuth{inherited, +oauth}:
      do IO<Result<&2, &2, String, Composed>>:
        apiKey : Composition<Auth.ApiKeyAuth> <- composeApiKeyAuth(providerId, inherited, Maybe.is_some(&2, Auth.OAuthAuth, oauth), config)
        method : Composition<Auth.OAuthAuth> <- composeOAuthAuth(providerId, oauth, config)
        return composedAuth(providerId, composedName(providerId, config, base), composedBaseUrl(config, base), models, apiKey, method)

def composedModels(+providerId: String, +base: Maybe<&2, Base>, +config: Config.ModelsJsonProvider, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Result<&2, &2, String, Composed>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Composed>, Fail{error})
    case Done{valid}: composeAuth(providerId, base, config, applyOverrides(valid, overridesOf(config)), baseAuth(base))

# Compose a built-in provider (if any) with its models.json entry. Models are
# validated before any auth callback exists, so a failed composition owns
# nothing. modelOverrides apply last, after custom-model upserts.
def composeModelProvider(+providerId: String, +base: Maybe<&2, Base>, +config: Config.ModelsJsonProvider) -> IO(Result<&2, &2, String, Composed>):
  composedModels(providerId, base, config, applyModelsJson(providerId, baseModels(base), config))

# Availability without resolution: a command-backed key counts as configured
# without running it; a template needs each referenced variable.
def allSet(names: List<&2, String>, +context: Auth.AuthContext) -> IO(Bool):
  match names:
    case Nil{}: IO.pure(Bool, True{})
    case name <> rest:
      do IO<Bool>:
        value : Maybe<&2, String> <- Auth.envValue(context, name)
        others : Bool <- allSet(rest, context)
        return Maybe.is_some(&2, String, value) && others

def checkConfiguredApiKey(+rawKey: String, context: Auth.AuthContext) -> IO(Bool):
  Bool.pick(Unit -> IO(Bool), ConfigValue.isCommandConfigValue(rawKey), _ => IO.pure(Bool, True{}), _ => allSet(ConfigValue.getConfigValueEnvVarNames(rawKey), context))(Unit{})

# Per-model request headers
# -------------------------

def definitionHeaders(definitions: List<&2, Config.ModelsJsonModel>, +id: String) -> Maybe<&2, R.Record<String>>:
  match definitions:
    case Nil{}: None{}
    case Config.ModelsJsonModel{+entryId, _, _, _, _, _, _, _, _, _, _, _, _, headers, _} <> rest: Bool.pick(Maybe<&2, R.Record<String>>, String.eq(entryId, id), headers, definitionHeaders(rest, id))

def entryHeaders(entry: Maybe<&2, Config.ModelsJsonModelOverride>) -> Maybe<&2, R.Record<String>>:
  match entry:
    case Some{Config.ModelsJsonModelOverride{_, _, _, _, _, _, _, _, _, _, headers, _}}: headers
    case None{}: None{}

def overrideHeaders(overrides: Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>, id: String) -> Maybe<&2, R.Record<String>>:
  match overrides:
    case None{}: None{}
    case Some{entries}: entryHeaders(R.get(Config.ModelsJsonModelOverride, entries, id))

def rawModelHeaders(+id: String, config: Maybe<&2, Config.ModelsJsonProvider>) -> Maybe<&2, R.Record<String>>:
  match config:
    case None{}: None{}
    case Some{+config}:
      nonemptyRecord(String, spread(String, recordOr(String, overrideHeaders(overridesOf(config), id)), R.entries(String, recordOr(String, definitionHeaders(definitionsOf(config), id)))))

# The model's own configured headers (modelOverrides, then its models.json
# definition), resolved with the given environment.
def resolveConfiguredModelHeaders(+model: Model(), config: Maybe<&2, Config.ModelsJsonProvider>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, Maybe<&2, R.Record<String>>>):
  resolveHeadersOrThrow(rawModelHeaders(modelId(model), config), "model \"" ++ T.modelProvider(model) ++ "/" ++ modelId(model) ++ "\"", env)
