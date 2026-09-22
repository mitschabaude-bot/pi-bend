import Base
import ../types.bend as T
import ../utils/estimate.bend as Estimate
import ../utils/schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Shared provider response-budget and request-option policy.
type ThinkingTokenAllocation is Data:
  ThinkingTokenAllocation{maxTokens: F64, thinkingBudget: F64}

def MIN_ANSWER_TOKENS() -> F64: F.fromU32(1024)

def DEFAULT_THINKING_BUDGETS() -> T.ThinkingBudgets:
  T.ThinkingBudgets{Some{F.fromU32(1024)}, Some{F.fromU32(2048)}, Some{F.fromU32(8192)}, Some{F.fromU32(16384)}}

def clampLevel(effort: T.ThinkingLevel) -> T.ThinkingLevel:
  match effort:
    case T.XHigh{}: T.High{}
    case T.Max{}: T.High{}
    case other: other

def clampReasoning(effort: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.ThinkingLevel>:
  match effort:
    case None{}: None{}
    case Some{level}: Some{clampLevel(level)}

def orDefault(value: Maybe<&2, F64>, fallback: U32) -> F64:
  match value:
    case None{}: F.fromU32(fallback)
    case Some{number}: number

def selectBudget(level: T.ThinkingLevel, budgets: T.ThinkingBudgets) -> F64:
  match level budgets:
    case T.Minimal{} T.ThinkingBudgets{value, _, _, _}: orDefault(value, 1024)
    case T.Low{} T.ThinkingBudgets{_, value, _, _}: orDefault(value, 2048)
    case T.Medium{} T.ThinkingBudgets{_, _, value, _}: orDefault(value, 8192)
    case _ T.ThinkingBudgets{_, _, _, value}: orDefault(value, 16384)

def thinkingBudgetForLevel(reasoningLevel: T.ThinkingLevel, customBudgets: Maybe<&2, T.ThinkingBudgets>) -> F64:
  match customBudgets:
    case None{}: selectBudget(reasoningLevel, DEFAULT_THINKING_BUDGETS())
    case Some{budgets}: selectBudget(reasoningLevel, budgets)

def clampThinkingBudgetToAnswerRoom(thinkingBudget: F64, ceiling: F64) -> F64:
  F.minimum(thinkingBudget, F.maximum(F.fromU32(0), F.subtract(ceiling, MIN_ANSWER_TOKENS())))

def responseCeiling(baseMaxTokens: Maybe<&2, F64>, modelMaxTokens: F64, thinkingBudget: F64) -> F64:
  match baseMaxTokens:
    case None{}: modelMaxTokens
    case Some{base}: F.minimum(F.add(base, thinkingBudget), modelMaxTokens)

def fitBudget(order: Maybe<&2, Cmp>, +maxTokens: F64, thinkingBudget: F64) -> ThinkingTokenAllocation:
  match order:
    case Some{LT{}}: ThinkingTokenAllocation{maxTokens, clampThinkingBudgetToAnswerRoom(thinkingBudget, maxTokens)}
    case Some{EQ{}}: ThinkingTokenAllocation{maxTokens, clampThinkingBudgetToAnswerRoom(thinkingBudget, maxTokens)}
    case _: ThinkingTokenAllocation{maxTokens, thinkingBudget}

def adjustMaxTokensForThinking(baseMaxTokens: Maybe<&2, F64>, modelMaxTokens: F64, reasoningLevel: T.ThinkingLevel, customBudgets: Maybe<&2, T.ThinkingBudgets>) -> ThinkingTokenAllocation:
  +thinkingBudget = thinkingBudgetForLevel(reasoningLevel, customBudgets)
  +maxTokens = responseCeiling(baseMaxTokens, modelMaxTokens, thinkingBudget)
  fitBudget(F.compare(maxTokens, thinkingBudget), maxTokens, thinkingBudget)

def contextCeiling(+window: F64, estimated: F64, +maxTokens: F64) -> F64:
  available = F.subtract(F.subtract(window, estimated), F.fromU32(4096))
  Bool.pick(F64, F.isAtMost(F.compare(window, F.fromU32(0))), F.maximum(F.fromU32(1), maxTokens), F.minimum(maxTokens, F.maximum(F.fromU32(1), available)))

def estimatedTokens(value: Estimate.ContextUsageEstimate) -> F64:
  match value:
    case Estimate.ContextUsageEstimate{tokens, _, _, _}: tokens

def contextWindow(-V: Data, model: T.Model<V>) -> F64:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, window, _, _, _, _}: window

def clampMaxTokensToContextWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~V: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, model: T.Model<V>, context: T.TranscriptContext<P, A, G, D>, maxTokens: F64) -> F64:
  contextCeiling(contextWindow(V, model), estimatedTokens(Estimate.estimateContextTokensWith(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, context)), maxTokens)

def clampMaxTokensToContext(~G: Data, ~D: Data, ~V: Data, model: T.Model<V>, context: T.TranscriptContext<S.Value, S.Value, G, D>, maxTokens: F64) -> F64:
  clampMaxTokensToContextWith(~S.Value, ~S.Value, ~G, ~D, ~V, ~SchemaJson.toJson, ~SchemaJson.toJson, model, context, maxTokens)

def mergeFields(-V: Data, fields: List<&2, R.Property<V>>, defaults: R.Record<V>) -> R.Record<V>:
  match fields:
    case Nil{}: defaults
    case R.Property{key, value} <> rest: mergeFields(V, rest, R.set(V, defaults, key, value))

def mergeSampling(-V: Data, defaults: Maybe<&2, R.Record<V>>, overrides: Maybe<&2, R.Record<V>>) -> Maybe<&2, R.Record<V>>:
  match defaults overrides:
    case None{} other: other
    case other None{}: other
    case Some{left} Some{right}: Some{mergeFields(V, R.entries(V, right), left)}

def keyOverride(explicit: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match explicit:
    case None{}: fallback
    case Some{+key}: Bool.pick(Maybe<&2, String>, String.is_empty(key), fallback, Some{key})

def selectedMax(value: Maybe<&2, F64>, fallback: F64) -> F64:
  match value:
    case None{}: fallback
    case Some{number}: number

def baseFields(-V: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, window: F64, estimated: F64, modelMax: F64, sampling: Maybe<&2, R.Record<V>>, key: Maybe<&2, String>, options: T.StreamOptions<V, Signal, Telemetry, Fetch, Error>) -> T.StreamOptions<V, Signal, Telemetry, Fetch, Error>:
  match options:
    case T.StreamOptions{signal, telemetry, apiKey, fetch, env, payload, response, headers, timeout, retries, delay, temperature, customSampling, maxTokens, transport, cache, session, wsTimeout, metadata}:
      T.StreamOptions{signal, telemetry, keyOverride(key, apiKey), fetch, env, payload, response, headers, timeout, retries, delay, temperature, mergeSampling(V, sampling, customSampling), Some{contextCeiling(window, estimated, selectedMax(maxTokens, modelMax))}, transport, cache, session, wsTimeout, metadata}

def projectedOptions(-V: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<V, Signal, Telemetry, Fetch, Error>>) -> T.StreamOptions<V, Signal, Telemetry, Fetch, Error>:
  match options:
    case Some{value}: T.toStreamOptions(V, Signal, Telemetry, Fetch, Error, value)
    case None{}: T.StreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def baseModel(-V: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, model: T.Model<V>, estimated: F64, options: Maybe<&2, T.SimpleStreamOptions<V, Signal, Telemetry, Fetch, Error>>, apiKey: Maybe<&2, String>) -> T.StreamOptions<V, Signal, Telemetry, Fetch, Error>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, window, modelMax, sampling, _, _}:
      baseFields(V, Signal, Telemetry, Fetch, Error, window, estimated, modelMax, sampling, apiKey, projectedOptions(V, Signal, Telemetry, Fetch, Error, options))

def buildBaseOptionsWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~V: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, model: T.Model<V>, context: T.TranscriptContext<P, A, G, D>, options: Maybe<&2, T.SimpleStreamOptions<V, Signal, Telemetry, Fetch, Error>>, apiKey: Maybe<&2, String>) -> T.StreamOptions<V, Signal, Telemetry, Fetch, Error>:
  baseModel(V, Signal, Telemetry, Fetch, Error, model, estimatedTokens(Estimate.estimateContextTokensWith(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, context)), options, apiKey)

def buildBaseOptions(~G: Data, ~D: Data, ~V: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, model: T.Model<V>, context: T.TranscriptContext<S.Value, S.Value, G, D>, options: Maybe<&2, T.SimpleStreamOptions<V, Signal, Telemetry, Fetch, Error>>, apiKey: Maybe<&2, String>) -> T.StreamOptions<V, Signal, Telemetry, Fetch, Error>:
  buildBaseOptionsWith(~S.Value, ~S.Value, ~G, ~D, ~V, ~Signal, ~Telemetry, ~Fetch, ~Error, ~SchemaJson.toJson, ~SchemaJson.toJson, model, context, options, apiKey)
