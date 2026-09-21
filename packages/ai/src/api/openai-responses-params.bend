import Base
import ../types.bend as T
import ../utils/thinking-levels.bend as Thinking
import ./openai-responses-policy.bend as Policy
import ./simple-options.bend as Simple
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as Word

# Request-body projection of StreamOptions plus Responses-specific settings.
# Transport, callbacks and retry options stay in the provider wrapper. A native
# SDK tool-choice type is supplied by the caller, with its wire encoder.
type RequestOptions<-Choice: Data> is Data:
  RequestOptions{maxTokens: Maybe<&2, F.F64>, temperature: Maybe<&2, F.F64>, serviceTier: Maybe<&2, T.Nullable<String>>, toolChoice: Maybe<&2, Choice>, reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<String>>, sessionId: Maybe<&2, String>, samplingParams: Maybe<&2, R.Record<T.JsonValue>>}

type RequestModel is Data:
  RequestModel{id: String, provider: String, reasoning: Bool, thinkingLevelMap: Maybe<&2, T.ThinkingLevelMap>}

def requestModel(-J: Data, model: T.Model<J>) -> RequestModel:
  match model:
    case T.Model{id, _, _, provider, _, reasoning, mapping, _, _, _, _, _, _, _}: RequestModel{id, provider, reasoning, mapping}

def OPENAI_RESPONSES_MIN_OUTPUT_TOKENS() -> F.F64: F.fromU32(16)

def optionalString(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{text}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def optionalNullableString(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{T.NullValue{}}: R.set(T.JsonValue, fields, key, T.JsonNull{})
    case Some{T.PresentValue{text}}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def optionalNumber(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, F.F64>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{scalar}: R.set(T.JsonValue, fields, key, T.JsonNumber{scalar})

def activeNumber(value: F.Decoded) -> Bool:
  match value:
    case F.NotANumber{}: False{}
    case F.Infinity{_}: True{}
    case F.Finite{_, _, magnitude}: Bool.not(Word.equal(magnitude, Word.zero()))

def outputTokens(enabled: Bool, value: Maybe<&2, F.F64>) -> Maybe<&2, F.F64>:
  match enabled value:
    case True{} Some{+scalar}: Bool.pick(Maybe<&2, F.F64>, activeNumber(F.decode(scalar)), Some{Simple.maximum(scalar, OPENAI_RESPONSES_MIN_OUTPUT_TOKENS())}, None{})
    case _ _: None{}

def mappedEffort(value: Maybe<&2, T.Nullable<String>>, fallback: String) -> String:
  match value:
    case Some{T.PresentValue{text}}: text
    case _: fallback

def requestedEffort(value: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>) -> String:
  match value:
    case None{}: "medium"
    case Some{+level}: mappedEffort(Thinking.mapped(mapping, T.Thinking{level}), Thinking.name(T.Thinking{level}))

def summaryText(value: Maybe<&2, T.Nullable<String>>) -> Maybe<&2, String>:
  match value:
    case Some{T.PresentValue{SNil{}}}: None{}
    case Some{T.PresentValue{text}}: Some{text}
    case _: None{}

def reasoningRequested(effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> Bool:
  match effort summary:
    case None{} None{}: False{}
    case _ _: True{}

def summaryOrAuto(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "auto"
    case Some{text}: text

def encryptedContent(fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  R.set(T.JsonValue, fields, "include", T.JsonArray{T.JsonString{"reasoning.encrypted_content"} <> Nil{}})

def offReasoning(fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match provider mapping:
    case "github-copilot" _: fields
    case _ Some{T.NullValue{}}: fields
    case _ value: R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{mappedEffort(value, "none")}} <> Nil{}}})

def configuredReasoning(requested: Bool, fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match requested:
    case False{}: offReasoning(fields, provider, Thinking.mapped(mapping, T.Off{}))
    case True{}: encryptedContent(R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{requestedEffort(effort, mapping)}} <> R.Property{"summary", T.JsonString{summaryOrAuto(summary)}} <> Nil{}}}))

def xaiInclude(provider: String, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match provider:
    case "xai": encryptedContent(fields)
    case _: fields

def addReasoning(fields: R.Record<T.JsonValue>, model: RequestModel, +effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match model:
    case RequestModel{_, _, False{}, _}: fields
    case RequestModel{_, +provider, True{}, mapping}:
      +selected = summaryText(summary)
      xaiInclude(provider, configuredReasoning(reasoningRequested(effort, selected), fields, provider, mapping, effort, selected))

def cacheOptions(fields: R.Record<T.JsonValue>, value: Maybe<&2, Policy.PromptCacheOptions>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{Policy.ExplicitMode{}}: R.set(T.JsonValue, fields, "prompt_cache_options", T.JsonObject{R.Record{R.Property{"mode", T.JsonString{"explicit"}} <> Nil{}}})
    case Some{Policy.ThirtyMinuteTtl{}}: R.set(T.JsonValue, fields, "prompt_cache_options", T.JsonObject{R.Record{R.Property{"ttl", T.JsonString{"30m"}} <> Nil{}}})

def baseFields(id: String, input: List<&2, T.JsonValue>, +compat: Policy.ResolvedCompat, +retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  fields = {R.Record{R.Property{"model", T.JsonString{id}} <> R.Property{"input", T.JsonArray{input}} <> R.Property{"stream", T.JsonBoolean{True{}}} <> R.Property{"store", T.JsonBoolean{False{}}} <> Nil{}} : R.Record<T.JsonValue>}
  cacheOptions(optionalString(optionalString(fields, "prompt_cache_key", Policy.promptCacheKey(retention, sessionId)), "prompt_cache_retention", Policy.getPromptCacheRetention(compat, retention)), Policy.getPromptCacheOptions(compat, retention))

def addTools(fields: R.Record<T.JsonValue>, tools: List<&2, T.JsonValue>) -> R.Record<T.JsonValue>:
  match tools:
    case Nil{}: fields
    case values: R.set(T.JsonValue, fields, "tools", T.JsonArray{values})

def addChoice(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, fields: R.Record<T.JsonValue>, choice: Maybe<&2, Choice>) -> R.Record<T.JsonValue>:
  match choice:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "tool_choice", encodeChoice(value))

# Explicit custom sampling fields override named fields last, including null.
def overrideFields(entries: List<&2, R.Property<T.JsonValue>>, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match entries:
    case Nil{}: fields
    case R.Property{key, value} <> rest: overrideFields(rest, R.set(T.JsonValue, fields, key, value))

def samplingFields(fields: R.Record<T.JsonValue>, sampling: Maybe<&2, R.Record<T.JsonValue>>) -> R.Record<T.JsonValue>:
  match sampling:
    case None{}: fields
    case Some{values}: overrideFields(R.entries(T.JsonValue, values), fields)

def maxOutputSupport(value: Policy.ResolvedCompat) -> Bool:
  match value:
    case Policy.ResolvedCompat{_, _, _, _, _, _, _, _, _, enabled}: enabled

def modelId(value: RequestModel) -> String:
  match value:
    case RequestModel{id, _, _, _}: id

# Converted messages/tools stay typed in the shared converter until its JSON
# boundary. This function assembles the final wire object without mutating them.
def buildConvertedParams(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, +model: RequestModel, input: List<&2, T.JsonValue>, tools: List<&2, T.JsonValue>, options: RequestOptions<Choice>, +compat: Policy.ResolvedCompat, retention: T.CacheRetention) -> T.JsonValue:
  match options:
    case RequestOptions{maxTokens, temperature, tier, choice, effort, summary, session, sampling}:
      fields = baseFields(modelId(model), input, compat, retention, session)
      budgeted = optionalNumber(fields, "max_output_tokens", outputTokens(maxOutputSupport(compat), maxTokens))
      configured = optionalNullableString(optionalNumber(budgeted, "temperature", temperature), "service_tier", tier)
      toolFields = addChoice(~Choice, ~encodeChoice, addTools(configured, tools), choice)
      T.JsonObject{samplingFields(addReasoning(toolFields, model, effort, summary), sampling)}
