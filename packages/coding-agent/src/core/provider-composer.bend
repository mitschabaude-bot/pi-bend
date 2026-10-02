import Base
import ../../../ai/src/api/openai-responses.bend as Responses
import ../../../ai/src/api/openai-codex-responses.bend as Codex
import ../../../ai/src/api/azure-openai-responses.bend as Azure
import ../../../ai/src/api/anthropic-messages.bend as Anthropic
import ../../../ai/src/api/anthropic-messages-client.bend as AnthropicClient
import ../../../ai/src/api/google-generative-ai.bend as Google
import ../../../ai/src/api/google-vertex.bend as Vertex
import ../../../ai/src/api/openai-completions.bend as Completions
import ../../../ai/src/api/mistral-conversations.bend as Mistral
import ../../../ai/src/api/bedrock-converse-stream.bend as Bedrock
import ../../../ai/src/api/pi-messages.bend as Pi
import ./model-config.bend as Config
import ./resolve-config-value.bend as ConfigValue
import ../../../ai/src/types.bend as T
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/model-api.bend as Api
import ../../../ai/src/utils/model-json.bend as ModelJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/fetch.bend as Fetch
import ../../../agent/src/types.bend as Agent
import ./tools/index.bend as Tools

# Composition of a built-in provider with its models.json layer and an
# extension's registerProvider(name, config) layer (upstream
# provider-composer.ts). Stream dispatch: an extension's
# streamSimple serves its api; other requests stream through the api-keyed
# native providers, as upstream's composed stream falls back to the api
# registry (model-runtime.bend).

def Model() -> Data: T.Model<T.JsonValue>

type ProviderModelConfig is Data:
  ProviderModelConfig{id: String, name: String, api: Maybe<&2, T.ModelApi>, baseUrl: Maybe<&2, String>, reasoning: Bool, thinkingLevelMap: Maybe<&2, T.ThinkingLevelMap>, input: List<&2, T.ModelInput>, inputLimits: Maybe<&2, T.ModelInputLimits>, cost: T.ModelCost, promptCache: Maybe<&2, T.ModelPromptCache>, contextWindow: F64, maxTokens: F64, samplingParams: Maybe<&2, R.Record<T.JsonValue>>, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, V.Value>}

# One coherent catalog state: source models, the extension's latest model
# definitions, and the OAuth projection used for the last publication.
# The epoch prevents a superseded asynchronous publication replacing it.
type ModelLayerState is Data:
  ModelLayerState{epoch: Nat, base: List<&2, Model()>, extension: Maybe<&2, List<&2, ProviderModelConfig>>, credential: Maybe<&2, Auth.Credential>, error: Maybe<&2, String>}

# Merge records, replacing existing values and appending new keys.
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
    case Some{Auth.ApiKeyAuth{_, _, resolve, _}}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, input)
def loginDefaultResult(value: Result<&2,&2,String,String>) -> Auth.LoginOutcome():
  match value:
    case Fail{reason}: Fail{reason}
    case Done{SNil{}}: Fail{"API key cannot be empty"}
    case Done{key}: Done{Auth.ApiKeyCredential{Some{key},None{}}}
def loginDefault(interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{_,prompt,_}:
      do IO<Auth.LoginOutcome()>:
        value : Result<&2,&2,String,String> <- C.call(Auth.AuthPrompt,Result<&2,&2,String,String>,prompt,Auth.SecretPrompt{"Enter API key",None{},None{}})
        return loginDefaultResult(value)
def loginInherited(inherited: Maybe<&2,Auth.ApiKeyAuth>,interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match inherited:
    case Some{Auth.ApiKeyAuth{_,Some{callback},_,_}}: C.call(Auth.ProviderAuthInteraction,Auth.LoginOutcome(),callback,interaction)
    case _: loginDefault(interaction)
def loginConfigured(config: KeyConfig,interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
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

# upstream's composed check: a stored key counts without resolving it, a
# configured key without running its command (a template needs each
# variable it references), and otherwise the inherited check or resolution
# decides.
def resolvedCheck(outcome: Auth.AuthOutcome()) -> Auth.CheckOutcome():
  match outcome:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{None{}}
    case Done{Some{Auth.AuthResult{_, _, source}}}: Done{Some{Auth.AuthCheck{source, Auth.ApiKeyType{}}}}

def inheritedCheck(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, input: Auth.ResolveInput) -> IO(Auth.CheckOutcome()):
  match inheritedAuth:
    case Some{Auth.ApiKeyAuth{_, _, _, Some{check}}}: C.call(Auth.ResolveInput, Auth.CheckOutcome(), check, input)
    case other:
      do IO<Auth.CheckOutcome()>:
        outcome : Auth.AuthOutcome() <- inheritedResolve(other, input)
        return resolvedCheck(outcome)

def storedCheck(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, input: Auth.ResolveInput, credential: Auth.Credential) -> IO(Auth.CheckOutcome()):
  match inheritedAuth credential:
    case Some{Auth.ApiKeyAuth{name, login, resolve, Some{check}}} _: inheritedCheck(Some{Auth.ApiKeyAuth{name, login, resolve, Some{check}}}, input)
    case _ Auth.ApiKeyCredential{Some{SCon{_, _}}, _}: IO.pure(Auth.CheckOutcome(), Done{Some{Auth.AuthCheck{Some{"stored credential"}, Auth.ApiKeyType{}}}})
    case inheritedAuth _: inheritedCheck(inheritedAuth, input)

def configuredCheck(+rawKey: String, context: Auth.AuthContext) -> IO(Auth.CheckOutcome()):
  do IO<Auth.CheckOutcome()>:
    ready : Bool <- checkConfiguredApiKey(rawKey, context)
    return Done{Bool.pick(Maybe<&2, Auth.AuthCheck>, ready, Some{Auth.AuthCheck{Some{"configured API key"}, Auth.ApiKeyType{}}}, None{})}

def checkWith(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, rawKey: Maybe<&2, String>, +context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>) -> IO(Auth.CheckOutcome()):
  match credential rawKey:
    case Some{+stored} _: storedCheck(inheritedAuth, Auth.ResolveInput{context, Some{stored}, signal}, stored)
    case None{} Some{raw}: configuredCheck(raw, context)
    case None{} None{}: inheritedCheck(inheritedAuth, Auth.ResolveInput{context, None{}, signal})

def checkConfigured(config: KeyConfig, input: Auth.ResolveInput) -> IO(Auth.CheckOutcome()):
  match config input:
    case KeyConfig{_, inherited, rawKey, _, _} Auth.ResolveInput{context, credential, signal}: checkWith(inherited, rawKey, context, credential, signal)

# Parts of the base provider's auth that a composed wrapper owns.
type Retained is Data:
  RetainedApiKey{auth: Auth.ApiKeyAuth}
  RetainedToAuth{toAuth: C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>>}
  RetainedRefresh{refresh: AiModels.RefreshModels()}
  RetainedModelsState{state: Ref.Ref<ModelLayerState>}

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
    case RetainedRefresh{refresh} <> rest:
      do IO<Unit>:
        C.dispose(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, refresh)
        disposeRetained(rest)
    case RetainedModelsState{state} <> rest:
      do IO<Unit>:
        previous : ModelLayerState <- Ref.dispose(ModelLayerState, state)
        disposeRetained(rest)

type Composition<-A: Data> is Data:
  Composition{auth: Maybe<&2, A>, retained: List<&2, Retained>}

def retainedKey(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>) -> List<&2, Retained>:
  match inheritedAuth:
    case None{}: Nil{}
    case Some{wrapped}: RetainedApiKey{wrapped} <> Nil{}

def inheritedName(inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>) -> String:
  match inheritedAuth:
    case Some{Auth.ApiKeyAuth{name, _, _, _}}: name
    case None{}: "API key"

def wrappedKey(+config: KeyConfig) -> IO(Composition<Auth.ApiKeyAuth>):
  match config:
    case KeyConfig{_, +inherited, _, _, _}:
      do IO<Composition<Auth.ApiKeyAuth>>:
        resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~KeyConfig, ~Auth.ResolveInput, ~(Auth.AuthOutcome()), ~resolveConfigured, config)
        login : C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()> <- C.create(~KeyConfig,~Auth.ProviderAuthInteraction,~(Auth.LoginOutcome()),~loginConfigured,config)
        check : C.Callback<Auth.ResolveInput, Auth.CheckOutcome()> <- C.create(~KeyConfig, ~Auth.ResolveInput, ~(Auth.CheckOutcome()), ~checkConfigured, config)
        return Composition{Some{Auth.ApiKeyAuth{inheritedName(inherited), Some{login}, resolve, Some{check}}}, retainedKey(inherited)}

def configuredHeaders(config: Config.ModelsJsonProvider) -> Maybe<&2, R.Record<String>>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, headers, _, _, _, _}: headers

def configuredApiKey(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{_, _, apiKey, _, _, _, _, _, _, _}: apiKey

def configuredAuthHeader(config: Config.ModelsJsonProvider) -> Bool:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, _, authHeader, _, _}: Maybe.default(&2, Bool, authHeader, False{})

# OAuth-only providers get no fabricated API-key method.
def composedKey(+providerId: String, inheritedAuth: Maybe<&2, Auth.ApiKeyAuth>, oauth: Bool, keyValue: Maybe<&2, String>, +headerConfig: Maybe<&2, R.Record<String>>, +bearerHeader: Bool) -> IO(Composition<Auth.ApiKeyAuth>):
  match inheritedAuth keyValue:
    case None{} None{}:
      Bool.pick(Unit -> IO(Composition<Auth.ApiKeyAuth>), oauth, _ => IO.pure(Composition<Auth.ApiKeyAuth>, Composition{None{}, Nil{}}), _ => wrappedKey(KeyConfig{providerId, None{}, None{}, headerConfig, bearerHeader}))(Unit{})
    case inheritedAuth keyValue: wrappedKey(KeyConfig{providerId, inheritedAuth, keyValue, headerConfig, bearerHeader})



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
    case Auth.OAuthAuth{name, subscription, label, login, refresh, +toAuth}:
      do IO<Composition<Auth.OAuthAuth>>:
        wrapped : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~OAuthConfig, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuthConfigured, OAuthConfig{providerId, toAuth, rawHeaders, authHeader})
        return Composition{Some{Auth.OAuthAuth{name, subscription, label, login, refresh, wrapped}}, RetainedToAuth{toAuth} <> Nil{}}

# The base OAuth method with configured headers applied to its request auth;
# unchanged when nothing is configured.
def composedOAuth(providerId: String, base: Maybe<&2, Auth.OAuthAuth>, headerConfig: Maybe<&2, R.Record<String>>, bearerHeader: Bool) -> IO(Composition<Auth.OAuthAuth>):
  match base headerConfig bearerHeader:
    case None{} _ _: IO.pure(Composition<Auth.OAuthAuth>, Composition{None{}, Nil{}})
    case Some{oauth} None{} False{}: IO.pure(Composition<Auth.OAuthAuth>, Composition{Some{oauth}, Nil{}})
    case Some{oauth} headers bearerHeader: wrappedOAuth(providerId, oauth, headers, bearerHeader)



# Extension providers (upstream ProviderConfigInput)
# --------------------------------------------------

# Requests retain their raw API options or their simple reasoning configuration.
# Auth preparation changes only the common fields. Extension callbacks handle
# both variants; upstream also invokes config.streamSimple for raw requests.
def StreamOptions() -> Data: T.SimpleStreamOptions<T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError>
def BaseOptions() -> Data: T.StreamOptions<T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError>

type ApiStreamOptions is Data:
  CommonOptions{base: BaseOptions()}
  ResponsesOptions{options: Responses.OpenAIResponsesOptions<Unit, Unit, Tools.ToolError>}
  CodexOptions{options: Codex.OpenAICodexResponsesOptions<Unit, Unit, Tools.ToolError>}
  AzureOptions{options: Azure.AzureOpenAIResponsesOptions<Unit, Unit, Tools.ToolError>}
  AnthropicOptions{options: AnthropicClient.Options(Unit, Unit, Tools.ToolError)}
  GoogleOptions{options: Google.GoogleOptions<Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError>}
  VertexOptions{options: Vertex.Options(Unit, Unit, Tools.ToolError)}
  CompletionsOptions{options: Completions.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError)}
  MistralOptions{options: Mistral.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError)}
  BedrockOptions{options: Bedrock.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError)}
  PiOptions{options: Pi.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError)}

type RequestOptions is Data:
  SimpleOptions{options: StreamOptions()}
  RawOptions{options: ApiStreamOptions}

def SimpleStreamRequest() -> Data: Agent.StreamInput<V.Value, Tools.ToolDetails, StreamOptions()>
def RawStreamRequest() -> Data: Agent.StreamInput<V.Value, Tools.ToolDetails, ApiStreamOptions>
def StreamRequest() -> Data: Agent.StreamInput<V.Value, Tools.ToolDetails, RequestOptions>
def StreamOutput() -> Type: Result<&2, &1, Tools.ToolError, Agent.StreamLease<V.Value, Tools.ToolError>>
def ProviderStream() -> Data: C.Callback<StreamRequest(), StreamOutput()>

def emptyBase() -> BaseOptions(): T.toStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError, T.emptySimpleStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError))

def rawBase(options: ApiStreamOptions) -> BaseOptions():
  match options:
    case CommonOptions{base}: base
    case ResponsesOptions{value}: Responses.toStreamOptions(Unit, Unit, Tools.ToolError, value)
    case CodexOptions{Codex.OpenAICodexResponsesOptions{base, _, _, _, _, _}}: base
    case AzureOptions{Azure.AzureOpenAIResponsesOptions{base, _, _, _, _, _, _, _}}: base
    case AnthropicOptions{Anthropic.AnthropicOptions{base, _, _, _, _, _, _, _}}: base
    case GoogleOptions{Google.GoogleOptions{base, _, _}}: base
    case VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, _, _}, _, _}}: base
    case CompletionsOptions{Completions.OpenAICompletionsOptions{base, _, _, _}}: base
    case MistralOptions{Mistral.MistralOptions{base, _, _, _}}: base
    case BedrockOptions{Bedrock.BedrockOptions{base, _, _, _, _, _, _, _, _, _}}: base
    case PiOptions{Pi.PiMessagesOptions{base, _, _, _}}: base

def withRawBase(options: ApiStreamOptions, base: BaseOptions()) -> ApiStreamOptions:
  match options:
    case CommonOptions{_}: CommonOptions{base}
    case ResponsesOptions{value}: ResponsesOptions{Responses.fromStreamOptions(Unit, Unit, Tools.ToolError, base, Responses.settings(Unit, Unit, Tools.ToolError, value))}
    case CodexOptions{Codex.OpenAICodexResponsesOptions{_, effort, summary, tier, verbosity, choice}}: CodexOptions{Codex.OpenAICodexResponsesOptions{base, effort, summary, tier, verbosity, choice}}
    case AzureOptions{Azure.AzureOpenAIResponsesOptions{_, effort, choice, summary, version, resource, url, deployment}}: AzureOptions{Azure.AzureOpenAIResponsesOptions{base, effort, choice, summary, version, resource, url, deployment}}
    case AnthropicOptions{Anthropic.AnthropicOptions{_, thinking, budget, effort, display, interleaved, choice, client}}: AnthropicOptions{Anthropic.AnthropicOptions{base, thinking, budget, effort, display, interleaved, choice, client}}
    case GoogleOptions{Google.GoogleOptions{_, choice, thinking}}: GoogleOptions{Google.GoogleOptions{base, choice, thinking}}
    case VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{_, choice, thinking}, project, location}}: VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, choice, thinking}, project, location}}
    case CompletionsOptions{Completions.OpenAICompletionsOptions{_, choice, effort, budgets}}: CompletionsOptions{Completions.OpenAICompletionsOptions{base, choice, effort, budgets}}
    case MistralOptions{Mistral.MistralOptions{_, choice, mode, effort}}: MistralOptions{Mistral.MistralOptions{base, choice, mode, effort}}
    case BedrockOptions{Bedrock.BedrockOptions{_, region, profile, choice, effort, budgets, interleaved, display, metadata, bearer}}: BedrockOptions{Bedrock.BedrockOptions{base, region, profile, choice, effort, budgets, interleaved, display, metadata, bearer}}
    case PiOptions{Pi.PiMessagesOptions{_, effort, choice, debug}}: PiOptions{Pi.PiMessagesOptions{base, effort, choice, debug}}

# Built-in raw options have API-specific defaults, independent of simple
# reasoning conversion. A typed option record for another API is rejected.
def optionsForApi(api: T.ModelApi, options: ApiStreamOptions) -> Result<&2, &2, String, ApiStreamOptions>:
  match api options:
    case T.OpenAIResponsesApi{} CommonOptions{base}: Done{ResponsesOptions{Responses.fromStreamOptions(Unit, Unit, Tools.ToolError, base, Responses.ResponsesSettings{None{}, None{}, None{}, None{}})}}
    case T.OpenAICodexResponsesApi{} CommonOptions{base}: Done{CodexOptions{Codex.OpenAICodexResponsesOptions{base, None{}, None{}, None{}, None{}, None{}}}}
    case T.AzureOpenAIResponsesApi{} CommonOptions{base}: Done{AzureOptions{Azure.AzureOpenAIResponsesOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.AnthropicMessagesApi{} CommonOptions{base}: Done{AnthropicOptions{Anthropic.AnthropicOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.GoogleGenerativeAiApi{} CommonOptions{base}: Done{GoogleOptions{Google.GoogleOptions{base, None{}, None{}}}}
    case T.GoogleVertexApi{} CommonOptions{base}: Done{VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, None{}, None{}}, None{}, None{}}}}
    case T.OpenAICompletionsApi{} CommonOptions{base}: Done{CompletionsOptions{Completions.OpenAICompletionsOptions{base, None{}, None{}, None{}}}}
    case T.MistralConversationsApi{} CommonOptions{base}: Done{MistralOptions{Mistral.MistralOptions{base, None{}, None{}, None{}}}}
    case T.BedrockConverseStreamApi{} CommonOptions{base}: Done{BedrockOptions{Bedrock.BedrockOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.PiMessagesApi{} CommonOptions{base}: Done{PiOptions{Pi.PiMessagesOptions{base, None{}, None{}, None{}}}}
    case T.OpenAIResponsesApi{} ResponsesOptions{value}: Done{ResponsesOptions{value}}
    case T.OpenAICodexResponsesApi{} CodexOptions{value}: Done{CodexOptions{value}}
    case T.AzureOpenAIResponsesApi{} AzureOptions{value}: Done{AzureOptions{value}}
    case T.AnthropicMessagesApi{} AnthropicOptions{value}: Done{AnthropicOptions{value}}
    case T.GoogleGenerativeAiApi{} GoogleOptions{value}: Done{GoogleOptions{value}}
    case T.GoogleVertexApi{} VertexOptions{value}: Done{VertexOptions{value}}
    case T.OpenAICompletionsApi{} CompletionsOptions{value}: Done{CompletionsOptions{value}}
    case T.MistralConversationsApi{} MistralOptions{value}: Done{MistralOptions{value}}
    case T.BedrockConverseStreamApi{} BedrockOptions{value}: Done{BedrockOptions{value}}
    case T.PiMessagesApi{} PiOptions{value}: Done{PiOptions{value}}
    case T.CustomModelApi{_} CommonOptions{base}: Done{CommonOptions{base}}
    case _ _: Fail{"Raw stream options do not match the model API"}

def requestBase(options: RequestOptions) -> BaseOptions():
  match options:
    case SimpleOptions{value}: T.toStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError, value)
    case RawOptions{value}: rawBase(value)

def withRequestBase(options: RequestOptions, base: BaseOptions()) -> RequestOptions:
  match options base:
    case RawOptions{value} base: RawOptions{withRawBase(value, base)}
    case SimpleOptions{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, deferred, budgets}} T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, tokens, transport, retention, session, connect, metadata}:
      SimpleOptions{T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, tokens, transport, retention, session, connect, metadata, choice, reasoning, deferred, budgets}}

# Simple-only consumers explicitly select the simple variant; no raw options
# are projected through the simple reasoning conversion.
def simpleOptions(options: Maybe<&2, RequestOptions>) -> Maybe<&2, StreamOptions()>:
  match options:
    case Some{SimpleOptions{value}}: Some{value}
    case _: None{}

# One of ProviderConfigInput.models; `api` and `baseUrl` fall back to the
# provider config, then to the defaults model.


# Native auth methods carry their model projection beside them. The caller
# owns both callbacks; composition retains only wrappers it creates.
type OAuthModelsInput is Data:
  OAuthModelsInput{models: List<&2, Model()>, credential: Auth.Credential}

type OAuthProvider is Data:
  OAuthProvider{auth: Auth.OAuthAuth, modifyModels: Maybe<&2, C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>>}

def ModelRefresh() -> Data: C.Callback<AiModels.RefreshModelsContext, Result<&2, &2, String, List<&2, ProviderModelConfig>>>

# Native OAuth methods and stream callbacks remain borrowed from their
# extension owner; composition owns only the callbacks it creates.
type ProviderConfigInput is Data:
  ProviderConfigInput{name: Maybe<&2, String>, baseUrl: Maybe<&2, String>, apiKey: Maybe<&2, String>, api: Maybe<&2, T.ModelApi>, streamSimple: Maybe<&2, ProviderStream()>, headers: Maybe<&2, R.Record<String>>, authHeader: Maybe<&2, Bool>, models: Maybe<&2, List<&2, ProviderModelConfig>>, oauth: Maybe<&2, OAuthProvider>, refreshModels: Maybe<&2, ModelRefresh()>}

def providerConfig() -> ProviderConfigInput: ProviderConfigInput{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def configApi(config: ProviderConfigInput) -> Maybe<&2, T.ModelApi>:
  match config:
    case ProviderConfigInput{_, _, _, api, _, _, _, _, _, _}: api

def configStream(config: ProviderConfigInput) -> Maybe<&2, ProviderStream()>:
  match config:
    case ProviderConfigInput{_, _, _, _, stream, _, _, _, _, _}: stream

# upstream registerProvider's merge: the new registration's defined values
# over the previous registration's.
def mergeProviderConfig(previous: ProviderConfigInput, config: ProviderConfigInput) -> ProviderConfigInput:
  match previous config:
    case ProviderConfigInput{n0, b0, k0, a0, s0, h0, x0, m0, o0, r0} ProviderConfigInput{n1, b1, k1, a1, s1, h1, x1, m1, o1, r1}:
      ProviderConfigInput{Maybe.or(&2, String, n1, n0), Maybe.or(&2, String, b1, b0), Maybe.or(&2, String, k1, k0), Maybe.or(&2, T.ModelApi, a1, a0), Maybe.or(&2, ProviderStream(), s1, s0), Maybe.or(&2, R.Record<String>, h1, h0), Maybe.or(&2, Bool, x1, x0), Maybe.or(&2, List<&2, ProviderModelConfig>, m1, m0), Maybe.or(&2, OAuthProvider, o1, o0), Maybe.or(&2, ModelRefresh(), r1, r0)}

def withModelBaseUrl(model: Model(), +url: String) -> Model():
  match model:
    case T.Model{id, name, api, provider, _, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, headers, compat}:
      T.Model{id, name, api, provider, url, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, headers, compat}

def withBaseUrls(models: List<&2, Model()>, +url: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: withModelBaseUrl(model, url) <> withBaseUrls(rest, url)

def extensionModel(+providerId: String, definition: ProviderModelConfig, +api: T.ModelApi, baseUrl: String) -> Model():
  match definition:
    case ProviderModelConfig{id, name, _, _, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, _, compat}:
      T.Model{id, name, api, providerId, baseUrl, reasoning, levels, inputs, limits, cost, cache, window, maximum, sampling, None{}, compatFor(api, compat)}

def locatedExtensionModel(+providerId: String, definition: ProviderModelConfig, +api: T.ModelApi, baseUrl: Maybe<&2, String>) -> Result<&2, &2, String, Model()>:
  match baseUrl:
    case None{}: Fail{"Provider " ++ providerId ++ ": \"baseUrl\" is required when defining custom models."}
    case Some{url}: Done{extensionModel(providerId, definition, api, url)}

def definitionModelApi(definition: ProviderModelConfig) -> Maybe<&2, T.ModelApi>:
  match definition:
    case ProviderModelConfig{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _}: api

def definitionModelBaseUrl(definition: ProviderModelConfig) -> Maybe<&2, String>:
  match definition:
    case ProviderModelConfig{_, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: baseUrl

def definitionModelId(definition: ProviderModelConfig) -> String:
  match definition:
    case ProviderModelConfig{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def configBaseUrl(config: ProviderConfigInput) -> Maybe<&2, String>:
  match config:
    case ProviderConfigInput{_, baseUrl, _, _, _, _, _, _, _, _}: baseUrl

def configModels(config: ProviderConfigInput) -> Maybe<&2, List<&2, ProviderModelConfig>>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, _, _, models, _, _}: models

def apiOfModel(model: Model()) -> T.ModelApi: Api.modelApi(T.JsonValue, model)

def extensionModelFor(+providerId: String, definition: ProviderModelConfig, +baseUrl: Maybe<&2, String>, api: Maybe<&2, T.ModelApi>) -> Result<&2, &2, String, Model()>:
  match api:
    case None{}: Fail{"Provider " ++ providerId ++ ", model " ++ definitionModelId(definition) ++ ": no \"api\" specified. Set at provider or model level."}
    case Some{found}: locatedExtensionModel(providerId, definition, found, baseUrl)

# upstream applyExtension's model: api and baseUrl from the definition, the
# provider config, then the defaults model; request headers are not model
# fields.
def extensionModelWith(+providerId: String, +definition: ProviderModelConfig, +config: ProviderConfigInput, +defaults: Maybe<&2, Model()>) -> Result<&2, &2, String, Model()>:
  extensionModelFor(providerId, definition, Maybe.or(&2, String, definitionModelBaseUrl(definition), Maybe.or(&2, String, configBaseUrl(config), Maybe.map(&2, Model(), String, modelBaseUrl, defaults))), Maybe.or(&2, T.ModelApi, definitionModelApi(definition), Maybe.or(&2, T.ModelApi, configApi(config), Maybe.map(&2, Model(), T.ModelApi, apiOfModel, defaults))))

def requestedApiName(+definition: ProviderModelConfig, +config: ProviderConfigInput) -> Maybe<&2, String>:
  Maybe.map(&2, T.ModelApi, String, Api.name, Maybe.or(&2, T.ModelApi, definitionModelApi(definition), configApi(config)))

def extensionModels(+providerId: String, definitions: List<&2, ProviderModelConfig>, +config: ProviderConfigInput, +base: List<&2, Model()>) -> Result<&2, &2, String, List<&2, Model()>>:
  match definitions:
    case Nil{}: Done{Nil{}}
    case +definition <> rest:
      Result.bind(&2, &2, String, Model(), List<&2, Model()>, extensionModelWith(providerId, definition, config, findModelDefaults(base, definitionModelId(definition), requestedApiName(definition, config))), model => Result.map(&2, &2, String, List<&2, Model()>, List<&2, Model()>, others => model <> others, extensionModels(providerId, rest, config, base)))

def baseUrlOverride(+models: List<&2, Model()>, baseUrl: Maybe<&2, String>) -> List<&2, Model()>:
  match baseUrl:
    case None{}: models
    case Some{url}: withBaseUrls(models, url)

def extendedModels(+providerId: String, +models: List<&2, Model()>, +config: ProviderConfigInput, definitions: Maybe<&2, List<&2, ProviderModelConfig>>) -> Result<&2, &2, String, List<&2, Model()>>:
  match definitions:
    case None{}: Done{baseUrlOverride(models, configBaseUrl(config))}
    case Some{list}: extensionModels(providerId, list, config, models)

# upstream applyExtension: without models, a baseUrl moves every model;
# with models, they replace the provider's.
def applyExtension(+providerId: String, +models: List<&2, Model()>, extension: Maybe<&2, ProviderConfigInput>) -> Result<&2, &2, String, List<&2, Model()>>:
  match extension:
    case None{}: Done{models}
    case Some{+config}: extendedModels(providerId, models, config, configModels(config))

# upstream validateExtensionProvider: a streamSimple needs its api, and the
# layers must compose.
def validateStream(+providerId: String, config: ProviderConfigInput) -> Result<&2, &2, String, Unit>:
  match config:
    case ProviderConfigInput{_, _, _, None{}, Some{_}, _, _, _, _, _}: Fail{"Provider " ++ providerId ++ ": \"api\" is required when registering streamSimple."}
    case _: Done{Unit{}}

def providerName(config: Config.ModelsJsonProvider) -> Maybe<&2, String>:
  match config:
    case Config.ModelsJsonProvider{name, _, _, _, _, _, _, _, _, _}: name

# The configured values of the models.json entry and the extension config
# (upstream configuredApiKey, configuredHeaders and authHeader).
type Layers is Data:
  Layers{config: Maybe<&2, Config.ModelsJsonProvider>, extension: Maybe<&2, ProviderConfigInput>}

def extensionField(-A: Data, extension: Maybe<&2, ProviderConfigInput>, get: ProviderConfigInput -> Maybe<&2, A>) -> Maybe<&2, A>:
  match extension:
    case None{}: None{}
    case Some{config}: get(config)

def configField(-A: Data, config: Maybe<&2, Config.ModelsJsonProvider>, get: Config.ModelsJsonProvider -> Maybe<&2, A>) -> Maybe<&2, A>:
  match config:
    case None{}: None{}
    case Some{entry}: get(entry)

def extensionKey(config: ProviderConfigInput) -> Maybe<&2, String>:
  match config:
    case ProviderConfigInput{_, _, key, _, _, _, _, _, _, _}: key

def extensionHeaders(config: ProviderConfigInput) -> Maybe<&2, R.Record<String>>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, headers, _, _, _, _}: headers

def extensionAuthHeader(config: ProviderConfigInput) -> Maybe<&2, Bool>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, _, authHeader, _, _, _}: authHeader

def extensionName(config: ProviderConfigInput) -> Maybe<&2, String>:
  match config:
    case ProviderConfigInput{name, _, _, _, _, _, _, _, _, _}: name

def entryAuthHeader(config: Config.ModelsJsonProvider) -> Maybe<&2, Bool>:
  match config:
    case Config.ModelsJsonProvider{_, _, _, _, _, _, _, authHeader, _, _}: authHeader

def layeredApiKey(layers: Layers) -> Maybe<&2, String>:
  match layers:
    case Layers{config, extension}: Maybe.or(&2, String, extensionField(String, extension, extensionKey), configField(String, config, configuredApiKey))

def mergedRecords(base: Maybe<&2, R.Record<String>>, over: Maybe<&2, R.Record<String>>) -> Maybe<&2, R.Record<String>>:
  match base over:
    case None{} None{}: None{}
    case base over: Some{spread(String, recordOr(String, base), R.entries(String, recordOr(String, over)))}

def layeredHeaders(layers: Layers) -> Maybe<&2, R.Record<String>>:
  match layers:
    case Layers{config, extension}: mergedRecords(configField(R.Record<String>, config, configuredHeaders), extensionField(R.Record<String>, extension, extensionHeaders))

def layeredAuthHeader(layers: Layers) -> Bool:
  match layers:
    case Layers{config, extension}: Maybe.default(&2, Bool, Maybe.or(&2, Bool, extensionField(Bool, extension, extensionAuthHeader), configField(Bool, config, entryAuthHeader)), False{})

def layeredName(layers: Layers) -> Maybe<&2, String>:
  match layers:
    case Layers{config, extension}: Maybe.or(&2, String, extensionField(String, extension, extensionName), configField(String, config, providerName))

def layeredBaseUrl(layers: Layers) -> Maybe<&2, String>:
  match layers:
    case Layers{config, extension}: Maybe.or(&2, String, extensionField(String, extension, configBaseUrl), configField(String, config, providerBaseUrl))

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

def nativeOAuth(provider: OAuthProvider) -> Auth.OAuthAuth:
  match provider:
    case OAuthProvider{auth, _}: auth

def extensionOAuth(config: ProviderConfigInput) -> Maybe<&2, Auth.OAuthAuth>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, _, _, _, oauth, _}: Maybe.map(&2, OAuthProvider, Auth.OAuthAuth, value => nativeOAuth(value), oauth)

# This source method stays owned by the extension or baseline provider.
# Header composition may wrap toAuth, but never replaces login or refresh.
def layeredOAuth(layers: Layers, inherited: Maybe<&2, Auth.OAuthAuth>) -> Maybe<&2, Auth.OAuthAuth>:
  match layers:
    case Layers{_, extension}: Maybe.or(&2, Auth.OAuthAuth, extensionField(Auth.OAuthAuth, extension, extensionOAuth), inherited)

def sourceAuth(+layers: Layers, inherited: Auth.ProviderAuth) -> Auth.ProviderAuth:
  match inherited:
    case Auth.ProviderAuth{key, oauth}: Auth.ProviderAuth{key, layeredOAuth(layers, oauth)}

def composeApiKeyAuth(+providerId: String, inherited: Maybe<&2, Auth.ApiKeyAuth>, oauth: Bool, +layers: Layers) -> IO(Composition<Auth.ApiKeyAuth>):
  composedKey(providerId, inherited, oauth, layeredApiKey(layers), layeredHeaders(layers), layeredAuthHeader(layers))

def composeOAuthAuth(providerId: String, base: Maybe<&2, Auth.OAuthAuth>, +layers: Layers) -> IO(Composition<Auth.OAuthAuth>):
  composedOAuth(providerId, layeredOAuth(layers, base), layeredHeaders(layers), layeredAuthHeader(layers))

# upstream: extension name, models.json name, base name, then the id.
def composedName(+providerId: String, +layers: Layers, base: Maybe<&2, Base>) -> String:
  match base:
    case Some{Base{name, _, _, _}}: Maybe.default(&2, String, layeredName(layers), name)
    case None{}: Maybe.default(&2, String, layeredName(layers), providerId)

# Provider.baseUrl is a string; a custom provider without one has "".
def composedBaseUrl(+layers: Layers, base: Maybe<&2, Base>) -> String:
  match base:
    case Some{Base{_, url, _, _}}: Maybe.default(&2, String, layeredBaseUrl(layers), url)
    case None{}: Maybe.default(&2, String, layeredBaseUrl(layers), "")

def composedAuth(+providerId: String, name: String, baseUrl: String, models: List<&2, Model()>, apiKey: Composition<Auth.ApiKeyAuth>, oauth: Composition<Auth.OAuthAuth>) -> Result<&2, &2, String, Composed>:
  match apiKey oauth:
    case Composition{None{}, _} Composition{None{}, _}: Fail{"Provider " ++ providerId ++ ": no authentication method configured."}
    case Composition{key, keyRetained} Composition{method, methodRetained}: Done{Composed{name, baseUrl, Auth.ProviderAuth{key, method}, models, List.append(&2, Retained, keyRetained, methodRetained)}}

def composeAuth(+providerId: String, +base: Maybe<&2, Base>, +layers: Layers, models: List<&2, Model()>, providerAuth: Auth.ProviderAuth) -> IO(Result<&2, &2, String, Composed>):
  match providerAuth:
    case Auth.ProviderAuth{inherited, +oauth}:
      do IO<Result<&2, &2, String, Composed>>:
        apiKey : Composition<Auth.ApiKeyAuth> <- composeApiKeyAuth(providerId, inherited, Maybe.is_some(&2, Auth.OAuthAuth, layeredOAuth(layers, oauth)), layers)
        method : Composition<Auth.OAuthAuth> <- composeOAuthAuth(providerId, oauth, layers)
        return composedAuth(providerId, composedName(providerId, layers, base), composedBaseUrl(layers, base), models, apiKey, method)

def layerOverrides(layers: Layers) -> Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>:
  match layers:
    case Layers{Some{config}, _}: overridesOf(config)
    case Layers{None{}, _}: None{}

def composedModels(+providerId: String, +base: Maybe<&2, Base>, +layers: Layers, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Result<&2, &2, String, Composed>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Composed>, Fail{error})
    case Done{valid}: composeAuth(providerId, base, layers, applyOverrides(valid, layerOverrides(layers)), baseAuth(base))

def modelsJsonModels(+providerId: String, +models: List<&2, Model()>, config: Maybe<&2, Config.ModelsJsonProvider>) -> Result<&2, &2, String, List<&2, Model()>>:
  match config:
    case None{}: Done{models}
    case Some{entry}: applyModelsJson(providerId, models, entry)

def extensionOf(layers: Layers) -> Maybe<&2, ProviderConfigInput>:
  match layers:
    case Layers{_, extension}: extension

def entryOf(layers: Layers) -> Maybe<&2, Config.ModelsJsonProvider>:
  match layers:
    case Layers{config, _}: config

# The provider's models: the base catalog with the models.json entry, then
# the extension layer; modelOverrides apply last.
def layeredModels(+providerId: String, +base: Maybe<&2, Base>, +layers: Layers) -> Result<&2, &2, String, List<&2, Model()>>:
  Result.bind(&2, &2, String, List<&2, Model()>, List<&2, Model()>, modelsJsonModels(providerId, baseModels(base), entryOf(layers)), models => applyExtension(providerId, models, extensionOf(layers)))

# Compose a provider (the base, if any) with its models.json entry and an
# extension's registration (upstream composeModelProvider). Models are
# validated before any auth callback exists, so a failed composition owns
# nothing.
def composeLayeredProvider(+providerId: String, +base: Maybe<&2, Base>, +layers: Layers) -> IO(Result<&2, &2, String, Composed>):
  composedModels(providerId, base, layers, layeredModels(providerId, base, layers))

def composeModelProvider(+providerId: String, +base: Maybe<&2, Base>, config: Config.ModelsJsonProvider) -> IO(Result<&2, &2, String, Composed>):
  composeLayeredProvider(providerId, base, Layers{Some{config}, None{}})

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

def entryModelHeaders(+id: String, config: Maybe<&2, Config.ModelsJsonProvider>) -> R.Record<String>:
  match config:
    case None{}: R.new(String)
    case Some{+config}: spread(String, recordOr(String, overrideHeaders(overridesOf(config), id)), R.entries(String, recordOr(String, definitionHeaders(definitionsOf(config), id))))

def extensionDefinitionHeaders(definitions: List<&2, ProviderModelConfig>, +id: String) -> Maybe<&2, R.Record<String>>:
  match definitions:
    case Nil{}: None{}
    case ProviderModelConfig{+entryId, _, _, _, _, _, _, _, _, _, _, _, _, headers, _} <> rest: Bool.pick(Maybe<&2, R.Record<String>>, String.eq(entryId, id), headers, extensionDefinitionHeaders(rest, id))

def extensionModelHeaders(+id: String, extension: Maybe<&2, ProviderConfigInput>) -> Maybe<&2, R.Record<String>>:
  match extension:
    case None{}: None{}
    case Some{config}: extensionDefinitionHeaders(Maybe.default(&2, List<&2, ProviderModelConfig>, configModels(config), Nil{}), id)

# upstream rawModelHeaders: modelOverrides, the models.json definition, then
# the extension's model definition.
def rawModelHeaders(+id: String, config: Maybe<&2, Config.ModelsJsonProvider>, extension: Maybe<&2, ProviderConfigInput>) -> Maybe<&2, R.Record<String>>:
  nonemptyRecord(String, spread(String, entryModelHeaders(id, config), R.entries(String, recordOr(String, extensionModelHeaders(id, extension)))))

# The model's own configured headers, resolved with the given environment.
def resolveConfiguredModelHeaders(+model: Model(), config: Maybe<&2, Config.ModelsJsonProvider>, extension: Maybe<&2, ProviderConfigInput>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, Maybe<&2, R.Record<String>>>):
  resolveHeadersOrThrow(rawModelHeaders(modelId(model), config, extension), "model \"" ++ T.modelProvider(model) ++ "/" ++ modelId(model) ++ "\"", env)
# Published catalogs of a composed provider
# -----------------------------------------

# upstream composeModelProvider's getModels: a built-in provider composed with
# its models.json entry shows the entry applied over the base's current
# catalog, so a catalog the base publishes gets the same overlay (and
# modelOverrides) as the static one. The composition was validated on the
# static catalog; an overlay that fails on a published one keeps the
# provider's composed models (`fallback`).
def overlaidModels(+providerId: String, +config: Config.ModelsJsonProvider, +fallback: List<&2, Model()>, published: List<&2, Model()>) -> List<&2, Model()>:
  Result.default(&2, &2, String, List<&2, Model()>, Result.map(&2, &2, String, List<&2, Model()>, List<&2, Model()>, models => applyOverrides(models, overridesOf(config)), applyModelsJson(providerId, published, config)), fallback)

type OverlaidPublish is Data:
  OverlaidPublish{providerId: String, config: Config.ModelsJsonProvider, fallback: List<&2, Model()>, publish: C.Callback<AiModels.ModelsPublication, Bool>}

type OverlaidRefresh is Data:
  OverlaidRefresh{providerId: String, config: Config.ModelsJsonProvider, fallback: List<&2, Model()>, base: AiModels.RefreshModels()}

def publishOverlaid(target: OverlaidPublish, publication: AiModels.ModelsPublication) -> IO(Bool):
  match target publication:
    case OverlaidPublish{+providerId, +config, +fallback, publish} AiModels.ModelsPublication{persist, models}:
      C.call(AiModels.ModelsPublication, Bool, publish, AiModels.ModelsPublication{persist, Maybe.map(&2, List<&2, Model()>, List<&2, Model()>, list => overlaidModels(providerId, config, fallback, list), models)})

def refreshOverlaid(source: OverlaidRefresh, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match source context:
    case OverlaidRefresh{providerId, config, fallback, base} AiModels.RefreshModelsContext{credential, stored, publish, allowNetwork, force, signal}:
      do IO<Result<&2, &2, String, Unit>>:
        +wrapped : C.Callback<AiModels.ModelsPublication, Bool> <- C.create(~OverlaidPublish, ~AiModels.ModelsPublication, ~Bool, ~publishOverlaid, OverlaidPublish{providerId, config, fallback, publish})
        result : Result<&2, &2, String, Unit> <- C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, base, AiModels.RefreshModelsContext{credential, stored, wrapped, allowNetwork, force, signal})
        C.dispose(AiModels.ModelsPublication, Bool, wrapped)
        return result

# upstream composeProvider forwards refreshModels to the base provider; its
# publications reach the collection through the models.json overlay. The
# wrapper is retained by the composition (RetainedRefresh).
def overlaidRefresh(providerId: String, config: Config.ModelsJsonProvider, fallback: List<&2, Model()>, base: AiModels.RefreshModels()) -> IO(AiModels.RefreshModels()):
  C.create(~OverlaidRefresh, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshOverlaid, OverlaidRefresh{providerId, config, fallback, base})

# Dynamic extension catalogs use the same layers as registration. A refresh
# borrows source callbacks and owns only its publication wrapper/state.
type LayeredRefresh is Data:
  LayeredRefresh{providerId: String, base: Maybe<&2, AiModels.RefreshModels()>, layers: Layers, state: Ref.Ref<ModelLayerState>}

type LayeredPublish is Data:
  LayeredPublish{source: LayeredRefresh, epoch: Nat, publish: C.Callback<AiModels.ModelsPublication, Bool>}

def refreshField(config: ProviderConfigInput) -> Maybe<&2, ModelRefresh()>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, _, _, _, _, refresh}: refresh

def modifyModelsField(config: ProviderConfigInput) -> Maybe<&2, C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>>:
  match config:
    case ProviderConfigInput{_, _, _, _, _, _, _, _, Some{OAuthProvider{_, modify}}, _}: modify
    case _: None{}

def withConfigModels(config: ProviderConfigInput, models: Maybe<&2, List<&2, ProviderModelConfig>>) -> ProviderConfigInput:
  match config:
    case ProviderConfigInput{name, url, key, api, stream, headers, bearer, _, oauth, refresh}:
      ProviderConfigInput{name, url, key, api, stream, headers, bearer, models, oauth, refresh}

def currentLayers(layers: Layers, models: Maybe<&2, List<&2, ProviderModelConfig>>) -> Layers:
  match layers:
    case Layers{entry, extension}: Layers{entry, Maybe.map(&2, ProviderConfigInput, ProviderConfigInput, config => withConfigModels(config, models), extension)}

def oauthCredential(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, Auth.Credential>:
  match credential:
    case Some{Auth.OAuthCredential{refresh, access, expiry, data}}: Some{Auth.OAuthCredential{refresh, access, expiry, data}}
    case _: None{}

def beginModelRefresh(state: ModelLayerState) -> ModelLayerState & Nat:
  match state:
    case ModelLayerState{epoch, base, extension, credential, _}:
      +next = epoch + 1n
      (ModelLayerState{next, base, extension, credential, None{}}, next)

def layerEpoch(state: ModelLayerState) -> Nat:
  match state:
    case ModelLayerState{epoch, _, _, _, _}: epoch

def commitLayerState(+epoch: Nat, proposed: ModelLayerState, +current: ModelLayerState) -> ModelLayerState & Bool:
  +valid = Nat.is_eq(epoch, layerEpoch(current))
  (Bool.pick(ModelLayerState, valid, proposed, current), valid)

def layerError(epoch: Nat, error: String, state: ModelLayerState) -> ModelLayerState & Unit:
  match state:
    case ModelLayerState{+current, base, extension, credential, previous}:
      (ModelLayerState{current, base, extension, credential, Bool.pick(Maybe<&2, String>, Nat.is_eq(epoch, current), Some{error}, previous)}, Unit{})

def projectWith(callback: Maybe<&2, C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>>, models: List<&2, Model()>, credential: Auth.Credential) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, String, List<&2, Model()>>, Done{models})
    case Some{method}: C.call(OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>, method, OAuthModelsInput{models, credential})

def projectedModels(layers: Layers, models: List<&2, Model()>, credential: Maybe<&2, Auth.Credential>) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match credential:
    case None{}: IO.pure(Result<&2, &2, String, List<&2, Model()>>, Done{models})
    case Some{value}: projectWith(extensionField(C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>, extensionOf(layers), modifyModelsField), models, value)

def transformedModels(+layers: Layers, credential: Maybe<&2, Auth.Credential>, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match result:
    case Fail{reason}: IO.pure(Result<&2, &2, String, List<&2, Model()>>, Fail{reason})
    case Done{models}:
      do IO<Result<&2, &2, String, List<&2, Model()>>>:
        projected : Result<&2, &2, String, List<&2, Model()>> <- projectedModels(layers, models, credential)
        return Result.map(&2, &2, String, List<&2, Model()>, List<&2, Model()>, values => applyOverrides(values, layerOverrides(layers)), projected)

def modelsFromLayers(id: String, +layers: Layers, state: ModelLayerState) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match state:
    case ModelLayerState{_, base, extension, credential, _}:
      +active = currentLayers(layers, extension)
      transformedModels(active, credential, layeredModels(id, Some{Base{"", "", Auth.ProviderAuth{None{}, None{}}, base}}, active))

def committedLayer(accepted: Bool, state: Ref.Ref<ModelLayerState>, epoch: Nat, proposed: ModelLayerState) -> IO(Bool):
  match accepted:
    case False{}: IO.pure(Bool, False{})
    case True{}: Ref.modify(ModelLayerState, Bool, state, current => commitLayerState(epoch, proposed, current))

def publishLayerResult(target: LayeredPublish, proposed: ModelLayerState, persist: AiModels.Persist, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Bool):
  match target result:
    case LayeredPublish{LayeredRefresh{_, _, _, state}, epoch, _} Fail{reason}:
      do IO<Bool>:
        Ref.modify(ModelLayerState, Unit, state, current => layerError(epoch, reason, current))
        return False{}
    case LayeredPublish{LayeredRefresh{_, _, _, state}, epoch, publish} Done{models}:
      do IO<Bool>:
        accepted : Bool <- C.call(AiModels.ModelsPublication, Bool, publish, AiModels.ModelsPublication{persist, Some{models}})
        committedLayer(accepted, state, epoch, proposed)

def withBaseModels(state: ModelLayerState, models: List<&2, Model()>) -> ModelLayerState:
  match state:
    case ModelLayerState{epoch, _, extension, credential, error}: ModelLayerState{epoch, models, extension, credential, error}

def publishLayered(target: LayeredPublish, publication: AiModels.ModelsPublication) -> IO(Bool):
  match target publication:
    case LayeredPublish{_, _, publish} AiModels.ModelsPublication{persist, None{}}:
      C.call(AiModels.ModelsPublication, Bool, publish, AiModels.ModelsPublication{persist, None{}})
    case LayeredPublish{LayeredRefresh{+id, base, +layers, +state}, epoch, publish} AiModels.ModelsPublication{persist, Some{models}}:
      do IO<Bool>:
        current : ModelLayerState <- Ref.read(ModelLayerState, state)
        +next : ModelLayerState = withBaseModels(current, models)
        projected : Result<&2, &2, String, List<&2, Model()>> <- modelsFromLayers(id, layers, next)
        publishLayerResult(LayeredPublish{LayeredRefresh{id, base, layers, state}, epoch, publish}, next, persist, projected)

def callBaseRefresh(callback: Maybe<&2, AiModels.RefreshModels()>, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{method}: C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, method, context)

def refreshedDefinitions(result: Result<&2, &2, String, List<&2, ProviderModelConfig>>) -> Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>>:
  Result.map(&2, &2, String, List<&2, ProviderModelConfig>, Maybe<&2, List<&2, ProviderModelConfig>>, models => Some{models}, result)

def callExtensionRefresh(callback: Maybe<&2, ModelRefresh()>, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>>, Done{None{}})
    case Some{method}:
      do IO<Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>>>:
        models : Result<&2, &2, String, List<&2, ProviderModelConfig>> <- C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, List<&2, ProviderModelConfig>>, method, context)
        return refreshedDefinitions(models)

def afterExtension(state: ModelLayerState, definitions: Maybe<&2, List<&2, ProviderModelConfig>>, credential: Maybe<&2, Auth.Credential>) -> ModelLayerState:
  match state:
    case ModelLayerState{epoch, base, previous, _, error}: ModelLayerState{epoch, base, Maybe.or(&2, List<&2, ProviderModelConfig>, definitions, previous), oauthCredential(credential), error}

def layerStatus(epoch: Nat, state: ModelLayerState) -> Result<&2, &2, String, Unit>:
  match state:
    case ModelLayerState{current, _, _, _, error}:
      Bool.pick(Result<&2, &2, String, Unit>, Nat.is_eq(epoch, current), Maybe.default(&2, Result<&2, &2, String, Unit>, Maybe.map(&2, String, Result<&2, &2, String, Unit>, reason => Fail{reason}, error), Done{Unit{}}), Done{Unit{}})

def layerResult(state: Ref.Ref<ModelLayerState>, epoch: Nat) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    current : ModelLayerState <- Ref.read(ModelLayerState, state)
    return layerStatus(epoch, current)

def publishExtension(target: LayeredPublish, +context: AiModels.RefreshModelsContext, definitions: Maybe<&2, List<&2, ProviderModelConfig>>) -> IO(Result<&2, &2, String, Unit>):
  match target context:
    case LayeredPublish{LayeredRefresh{+id, base, +layers, +state}, +epoch, publish} AiModels.RefreshModelsContext{credential, _, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        previous : ModelLayerState <- Ref.read(ModelLayerState, state)
        +next : ModelLayerState = afterExtension(previous, definitions, credential)
        models : Result<&2, &2, String, List<&2, Model()>> <- modelsFromLayers(id, layers, next)
        result : Bool <- publishLayerResult(LayeredPublish{LayeredRefresh{id, base, layers, state}, epoch, publish}, next, AiModels.KeepStored{}, models)
        layerResult(state, epoch)

def extensionFinished(stopped: Bool, target: LayeredPublish, context: AiModels.RefreshModelsContext, result: Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>>) -> IO(Result<&2, &2, String, Unit>):
  match stopped result:
    case _ Fail{reason}: IO.pure(Result<&2, &2, String, Unit>, Fail{reason})
    case True{} Done{_}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{} Done{definitions}: publishExtension(target, context, definitions)

def continueLayerRefresh(source: LayeredRefresh, epoch: Nat, context: AiModels.RefreshModelsContext, status: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match source context status:
    case _ _ Fail{reason}: IO.pure(Result<&2, &2, String, Unit>, Fail{reason})
    case LayeredRefresh{+id, +base, +layers, +state} AiModels.RefreshModelsContext{+credential, +stored, +publish, +network, +force, +signal} Done{_}:
      do IO<Result<&2, &2, String, Unit>>:
        +context : AiModels.RefreshModelsContext = AiModels.RefreshModelsContext{credential, stored, publish, network, force, signal}
        refreshed : Result<&2, &2, String, Maybe<&2, List<&2, ProviderModelConfig>>> <- callExtensionRefresh(extensionField(ModelRefresh(), extensionOf(layers), refreshField), context)
        stopped : Bool <- Abort.aborted(Unit, signal)
        extensionFinished(stopped, LayeredPublish{LayeredRefresh{id, base, layers, state}, epoch, publish}, context, refreshed)

def afterBaseRefresh(source: LayeredRefresh, +epoch: Nat, context: AiModels.RefreshModelsContext, result: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match source result:
    case _ Fail{reason}: IO.pure(Result<&2, &2, String, Unit>, Fail{reason})
    case LayeredRefresh{id, base, layers, +state} Done{_}:
      do IO<Result<&2, &2, String, Unit>>:
        status : Result<&2, &2, String, Unit> <- layerResult(state, epoch)
        continueLayerRefresh(LayeredRefresh{id, base, layers, state}, epoch, context, status)

def refreshLayered(source: LayeredRefresh, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match source context:
    case LayeredRefresh{+id, +base, +layers, +state} AiModels.RefreshModelsContext{+credential, +stored, +publish, +network, +force, +signal}:
      do IO<Result<&2, &2, String, Unit>>:
        +epoch : Nat <- Ref.modify(ModelLayerState, Nat, state, beginModelRefresh)
        +wrapped : C.Callback<AiModels.ModelsPublication, Bool> <- C.create(~LayeredPublish, ~AiModels.ModelsPublication, ~Bool, ~publishLayered, LayeredPublish{LayeredRefresh{id, base, layers, state}, epoch, publish})
        result : Result<&2, &2, String, Unit> <- callBaseRefresh(base, AiModels.RefreshModelsContext{credential, stored, wrapped, network, force, signal})
        C.dispose(AiModels.ModelsPublication, Bool, wrapped)
        afterBaseRefresh(LayeredRefresh{id, base, layers, state}, epoch, AiModels.RefreshModelsContext{credential, stored, publish, network, force, signal}, result)

def createdLayerRefresh(enabled: Bool, +id: String, base: Maybe<&2, Base>, callback: Maybe<&2, AiModels.RefreshModels()>, +layers: Layers) -> IO(Maybe<&2, AiModels.RefreshModels()> & List<&2, Retained>):
  match enabled:
    case False{}: IO.pure(Maybe<&2, AiModels.RefreshModels()> & List<&2, Retained>, (None{}, Nil{}))
    case True{}:
      do IO<Maybe<&2, AiModels.RefreshModels()> & List<&2, Retained>>:
        +state : Ref.Ref<ModelLayerState> <- Ref.new(ModelLayerState, ModelLayerState{0n, baseModels(base), extensionField(List<&2, ProviderModelConfig>, extensionOf(layers), configModels), None{}, None{}})
        +refresh : AiModels.RefreshModels() <- C.create(~LayeredRefresh, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshLayered, LayeredRefresh{id, callback, layers, state})
        return (Some{refresh}, [RetainedRefresh{refresh}, RetainedModelsState{state}])

def layeredRefresh(id: String, base: Maybe<&2, Base>, +callback: Maybe<&2, AiModels.RefreshModels()>, +layers: Layers) -> IO(Maybe<&2, AiModels.RefreshModels()> & List<&2, Retained>):
  createdLayerRefresh(Maybe.is_some(&2, AiModels.RefreshModels(), callback) || Maybe.is_some(&2, ModelRefresh(), extensionField(ModelRefresh(), extensionOf(layers), refreshField)) || Maybe.is_some(&2, C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>, extensionField(C.Callback<OAuthModelsInput, Result<&2, &2, String, List<&2, Model()>>>, extensionOf(layers), modifyModelsField)), id, base, callback, layers)

# Unauthenticated requests still retain explicitly configured headers.
type CompatibilityRequestConfig is Data:
  CompatibilityRequestConfig{headers: Maybe<&2, T.ProviderHeaders()>, authHeader: Bool}

def ownModelHeaders(model: Model()) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

def compatibilityConfig(model: Model(), layers: Layers, result: Result<&2, &2, String, Maybe<&2, R.Record<String>>>) -> Result<&2, &2, String, CompatibilityRequestConfig>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{headers}: Done{CompatibilityRequestConfig{mergedHeaders(mergedHeaders(None{}, ownModelHeaders(model)), headers), layeredAuthHeader(layers)}}

def resolveCompatibilityRequestConfig(+model: Model(), +layers: Layers) -> IO(Result<&2, &2, String, CompatibilityRequestConfig>):
  do IO<Result<&2, &2, String, CompatibilityRequestConfig>>:
    configured : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- resolveHeadersOrThrow(nonemptyRecord(String, spread(String, recordOr(String, layeredHeaders(layers)), R.entries(String, recordOr(String, rawModelHeaders(modelId(model), entryOf(layers), extensionOf(layers)))))), "model \"" ++ T.modelProvider(model) ++ "/" ++ modelId(model) ++ "\"", None{})
    return compatibilityConfig(model, layers, configured)
