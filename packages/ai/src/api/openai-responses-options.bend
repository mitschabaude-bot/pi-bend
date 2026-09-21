import Base
import ../types.bend as T
import ./openai-responses-params.bend as Params
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

type ReasoningSummary is Data:
  SummaryAuto{}
  SummaryDetailed{}
  SummaryConcise{}

type ServiceTier is Data:
  TierAuto{}
  TierDefault{}
  TierFlex{}
  TierScale{}
  TierPriority{}

def summaryName(value: ReasoningSummary) -> String:
  match value:
    case SummaryAuto{}: "auto"
    case SummaryDetailed{}: "detailed"
    case SummaryConcise{}: "concise"

def tierName(value: ServiceTier) -> String:
  match value:
    case TierAuto{}: "auto"
    case TierDefault{}: "default"
    case TierFlex{}: "flex"
    case TierScale{}: "scale"
    case TierPriority{}: "priority"

def summaryValue(value: Maybe<&2, T.Nullable<ReasoningSummary>>) -> Maybe<&2, T.Nullable<String>>:
  match value:
    case None{}: None{}
    case Some{T.NullValue{}}: Some{T.NullValue{}}
    case Some{T.PresentValue{selected}}: Some{T.PresentValue{summaryName(selected)}}

def tierValue(value: Maybe<&2, T.Nullable<ServiceTier>>) -> Maybe<&2, T.Nullable<String>>:
  match value:
    case None{}: None{}
    case Some{T.NullValue{}}: Some{T.NullValue{}}
    case Some{T.PresentValue{selected}}: Some{T.PresentValue{tierName(selected)}}

# The upstream interface extends StreamOptions. Keep every inherited field,
# including borrowed callback/fetch/signal handles, in the native typed record.
# Value is the wire payload/sampling type; Choice is the SDK tool-choice type.
type OpenAIResponsesOptions<-Value: Data, -Choice: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  OpenAIResponsesOptions{signal: Maybe<&2, Signal>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch>, env: Maybe<&2, T.ProviderEnv()>, onPayload: Maybe<&2, T.PayloadCallback(Value, T.Model<Value>, Error)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<Value>, Error)>, headers: Maybe<&2, T.ProviderHeaders()>, timeoutMs: Maybe<&2, F.F64>, maxRetries: Maybe<&2, F.F64>, maxRetryDelayMs: Maybe<&2, F.F64>, temperature: Maybe<&2, F.F64>, samplingParams: Maybe<&2, R.Record<Value>>, maxTokens: Maybe<&2, F.F64>, transport: Maybe<&2, T.Transport>, cacheRetention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, F.F64>, metadata: Maybe<&2, R.Record<Value>>, reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<ReasoningSummary>>, serviceTier: Maybe<&2, T.Nullable<ServiceTier>>, toolChoice: Maybe<&2, Choice>}

type ResponsesSettings<-Choice: Data> is Data:
  ResponsesSettings{reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<ReasoningSummary>>, serviceTier: Maybe<&2, T.Nullable<ServiceTier>>, toolChoice: Maybe<&2, Choice>}

def fromStreamOptions(-Value: Data, -Choice: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>, settings: ResponsesSettings<Choice>) -> OpenAIResponsesOptions<Value, Choice, Signal, Telemetry, Fetch, Error>:
  match base settings:
    case T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata} ResponsesSettings{reasoningEffort, reasoningSummary, serviceTier, toolChoice}: OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, reasoningEffort, reasoningSummary, serviceTier, toolChoice}

def toStreamOptions(-Value: Data, -Choice: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: OpenAIResponsesOptions<Value, Choice, Signal, Telemetry, Fetch, Error>) -> T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, _, _, _, _}: T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}

def settings(-Value: Data, -Choice: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: OpenAIResponsesOptions<Value, Choice, Signal, Telemetry, Fetch, Error>) -> ResponsesSettings<Choice>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reasoningEffort, reasoningSummary, serviceTier, toolChoice}: ResponsesSettings{reasoningEffort, reasoningSummary, serviceTier, toolChoice}

# Actual Responses wire bodies use canonical JSON, while transport handles and
# callbacks remain typed. Only body fields enter the parameter builder.
def requestOptions(-Choice: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: OpenAIResponsesOptions<T.JsonValue, Choice, Signal, Telemetry, Fetch, Error>) -> Params.RequestOptions<Choice>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, samplingParams, maxTokens, _, _, sessionId, _, _, reasoningEffort, reasoningSummary, serviceTier, toolChoice}: Params.RequestOptions{maxTokens, temperature, tierValue(serviceTier), toolChoice, reasoningEffort, summaryValue(reasoningSummary), sessionId, samplingParams}
