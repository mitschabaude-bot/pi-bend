import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses.bend as P
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-sse.bend as Sse
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/diagnostics.bend as Diagnostics

def identity(value: String) -> String: value

# Lifecycle: what settles the assistant message.

law cancellation_precedes_stop_validation:
  for -Reason: Data
  for -E: Data
  for reason: T.StopReason
  for api: String
  for detail: Maybe<&2, String>
  {P.check(Reason, E, True{}, reason, api, detail) == Fail{P.RequestAborted{}} : Result<&2, &2, P.Error<Reason, E>, T.DoneReason>}

law pending_stop_is_missing:
  for -Reason: Data
  for -E: Data
  for api: String
  for detail: Maybe<&2, String>
  {P.check(Reason, E, False{}, T.Pending{}, api, detail) == Fail{P.MissingStopReason{api}} : Result<&2, &2, P.Error<Reason, E>, T.DoneReason>}

# An existing failure keeps its cause even when the signal was also aborted.
law failure_keeps_cause_under_cancellation:
  for -G: Data
  for provider: String
  for output: T.AssistantMessage<V.Value, G>
  for aborted: Bool
  for cause: P.Error<String, String>
  {P.complete(~String, ~String, ~identity, G, provider, output, aborted, Some{cause}) == P.Failed{Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{}), P.withFailure(G, output, aborted, P.describe(~String, ~String, ~identity, provider, cause)), cause} : P.Terminal<String, G, String>}

# Failure changes only the stop reason and error message: partial content,
# usage, provider metadata and the original timestamp survive.
law failure_preserves_message_fields:
  for -G: Data
  for content: List<&2, T.AssistantContent<V.Value>>
  for api: T.Api()
  for provider: T.ProviderId()
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for thinking: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: T.Usage
  for stop: T.StopReason
  for deferred: Maybe<&2, T.DeferredHandle>
  for error: Maybe<&2, String>
  for raw: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F64
  for aborted: Bool
  for detail: String
  {P.withFailure(G, T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, aborted, detail) == T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, Bool.pick(T.StopReason, aborted, T.Aborted{}, T.Error{}), deferred, Some{detail}, raw, endTurn, timestamp} : T.AssistantMessage<V.Value, G>}

# A cleanup failure after processing never replaces the processing outcome.
law disposal_failure_never_replaces_processing_outcome:
  for -Reason: Data
  for -G: Data
  for -E: Data
  for output: T.AssistantMessage<V.Value, G>
  for error: Maybe<&2, Stream.Error<P.ReaderError(Reason)>>
  for cause: Sse.CloseError<Reason>
  {P.processed(Reason, G, E, Stream.RunResult{output, error}, Fail{cause}) == P.Outcome{output, Maybe.map(&2, Stream.Error<P.ReaderError(Reason)>, P.Error<Reason, E>, why => P.ProcessingFailure{why}, error), Some{P.DisposalFailure{cause}}} : P.Outcome<Reason, G, E>}

# Ownership: the caller's signal is borrowed, never disposed.
law supplied_signal_is_never_disposed:
  for -Reason: Data
  for signal: Abort.AbortSignal<Reason>
  {P.retireSignal(Reason, P.Supplied{signal}) == IO.pure(Unit, Unit{}) : IO(Unit)}

# Transport: cancellation and request rejection are observed before any
# transport is initialized, and an acquisition failure never reaches the hooks.
law cancelled_request_never_opens_transport:
  for config: P.Config
  for hooks: Sse.Hooks<Sse.TransportError(String)>
  for model: T.Model<T.JsonValue>
  for options: Stream.OpenAIResponsesStreamOptions
  for custom: Maybe<&2, Fetch.Fetch(String)>
  for hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, String)>
  for output: T.AssistantMessage<V.Value, Unit>
  for events: Events.AssistantMessageEventStream(V.Value, Unit)
  for parent: P.Signal(String)
  for retry: Retry.ProviderRetryOptions<String>
  for request: Result<&2, &2, Client.RequestError, Client.Request>
  {P.requested(~String, ~Unit, ~String, config, hooks, model, options, custom, hook, output, events, parent, retry, True{}, request) == IO.pure(P.Outcome<String, Unit, String>, P.Outcome{output, Some{P.RequestFailure{Retry.RequestAborted{}}}, None{}}) : IO(P.Outcome<String, Unit, String>)}

law rejected_request_never_opens_transport:
  for config: P.Config
  for hooks: Sse.Hooks<Sse.TransportError(String)>
  for model: T.Model<T.JsonValue>
  for options: Stream.OpenAIResponsesStreamOptions
  for custom: Maybe<&2, Fetch.Fetch(String)>
  for hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, String)>
  for output: T.AssistantMessage<V.Value, Unit>
  for events: Events.AssistantMessageEventStream(V.Value, Unit)
  for parent: P.Signal(String)
  for retry: Retry.ProviderRetryOptions<String>
  for cause: Client.RequestError
  {P.requested(~String, ~Unit, ~String, config, hooks, model, options, custom, hook, output, events, parent, retry, False{}, Fail{cause}) == IO.pure(P.Outcome<String, Unit, String>, P.Outcome{output, Some{P.RequestRejected{cause}}, None{}}) : IO(P.Outcome<String, Unit, String>)}

law acquisition_failure_skips_hooks:
  for config: P.Config
  for hooks: Sse.Hooks<Sse.TransportError(String)>
  for model: T.Model<T.JsonValue>
  for options: Stream.OpenAIResponsesStreamOptions
  for hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, String)>
  for output: T.AssistantMessage<V.Value, Unit>
  for events: Events.AssistantMessageEventStream(V.Value, Unit)
  for cause: P.Error<String, String>
  {P.acquired(~String, ~Unit, ~String, config, hooks, model, options, hook, output, events, Fail{cause}) == IO.pure(P.Outcome<String, Unit, String>, P.Outcome{output, Some{cause}, None{}}) : IO(P.Outcome<String, Unit, String>)}

# Options: the Responses options are a lossless extension of StreamOptions.
law responses_options_extend_stream_options:
  for -Reason: Data
  for -Telemetry: Data
  for -E: Data
  for base: P.StreamOptions(Reason, Telemetry, E)
  for settings: P.ResponsesSettings
  {P.toStreamOptions(Reason, Telemetry, E, P.fromStreamOptions(Reason, Telemetry, E, base, settings)) == base : P.StreamOptions(Reason, Telemetry, E)}

law responses_options_retain_settings:
  for -Reason: Data
  for -Telemetry: Data
  for -E: Data
  for base: P.StreamOptions(Reason, Telemetry, E)
  for settings: P.ResponsesSettings
  {P.settings(Reason, Telemetry, E, P.fromStreamOptions(Reason, Telemetry, E, base, settings)) == settings : P.ResponsesSettings}

law responses_options_split_and_rejoin:
  for -Reason: Data
  for -Telemetry: Data
  for -E: Data
  for options: P.OpenAIResponsesOptions<Reason, Telemetry, E>
  {P.fromStreamOptions(Reason, Telemetry, E, P.toStreamOptions(Reason, Telemetry, E, options), P.settings(Reason, Telemetry, E, options)) == options : P.OpenAIResponsesOptions<Reason, Telemetry, E>}

# Caching policy.
law disabled_caching_drops_session_affinity:
  for sessionId: Maybe<&2, String>
  {P.cacheSessionId(T.CacheNone{}, sessionId) == None{} : Maybe<&2, String>}

law explicit_retention_overrides_environment:
  for value: T.CacheRetention
  for env: Maybe<&2, String>
  {P.resolveCacheRetentionValue(Some{value}, env) == value : T.CacheRetention}

law long_retention_header_requires_compat:
  for developer: Bool
  for midConvo: Bool
  for affinity: T.SessionAffinityFormat
  for strict: Bool
  for grammar: Bool
  for additional: Bool
  for search: Bool
  for explicit: Bool
  for maxOutput: Bool
  for retention: T.CacheRetention
  {P.getPromptCacheRetention(P.ResolvedCompat{developer, midConvo, affinity, False{}, strict, grammar, additional, search, explicit, maxOutput}, retention) == None{} : Maybe<&2, String>}

law explicit_cache_mode_supersedes_retention_header:
  for developer: Bool
  for midConvo: Bool
  for affinity: T.SessionAffinityFormat
  for longCache: Bool
  for strict: Bool
  for grammar: Bool
  for additional: Bool
  for search: Bool
  for maxOutput: Bool
  for retention: T.CacheRetention
  {P.getPromptCacheRetention(P.ResolvedCompat{developer, midConvo, affinity, longCache, strict, grammar, additional, search, True{}, maxOutput}, retention) == None{} : Maybe<&2, String>}

# Service-tier pricing: only flex and priority reprice usage.
law absent_service_tier_keeps_usage:
  for model: T.Model<T.JsonValue>
  for usage: T.Usage
  {P.applyServiceTierPricing(model, None{}, usage) == usage : T.Usage}

law default_service_tier_keeps_usage:
  for model: T.Model<T.JsonValue>
  for usage: T.Usage
  {P.applyServiceTierPricing(model, Some{"default"}, usage) == usage : T.Usage}

law auto_service_tier_keeps_usage:
  for model: T.Model<T.JsonValue>
  for usage: T.Usage
  {P.applyServiceTierPricing(model, Some{"auto"}, usage) == usage : T.Usage}
