import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-options.bend as O
import ../laws/openai-responses-options.bend as Laws

def Laws.extension_preserves_base(Value, Choice, Signal, Telemetry, Fetch, Error, base, extra):
  match base extra:
    case T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata} O.ResponsesSettings{_, _, _, _}: {==}

def Laws.extension_preserves_provider_settings(Value, Choice, Signal, Telemetry, Fetch, Error, base, extra):
  match base extra:
    case T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata} O.ResponsesSettings{_, _, _, _}: {==}

def Laws.projections_reconstruct_all_options(Value, Choice, Signal, Telemetry, Fetch, Error, options):
  match options:
    case O.OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, _, _, _, _}: {==}
