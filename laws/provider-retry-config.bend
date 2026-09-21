import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-retry-config.bend as Config
import ../packages/ai/src/utils/provider-retry-options.bend as Options
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/f64.bend as F

# Quantify over all unrelated settings and callbacks: none can affect retry
# resolution, and constructing this pure result cannot invoke a hook.
law request_uses_only_retry_settings:
  for -Model: Data
  for -Reason: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Payload: Data
  for -E: Data
  for signal: Maybe<&2, Abort.AbortSignal<Reason>>
  for telemetry: Maybe<&2, Telemetry>
  for apiKey: Maybe<&2, String>
  for fetch: Maybe<&2, Fetch>
  for env: Maybe<&2, T.ProviderEnv()>
  for onPayload: Maybe<&2, T.PayloadCallback(Payload, Model, E)>
  for onResponse: Maybe<&2, T.ResponseCallback(Model, E)>
  for headers: Maybe<&2, T.ProviderHeaders()>
  for timeout: Maybe<&2, F.F64>
  for retries: Maybe<&2, F.F64>
  for limit: Maybe<&2, F.F64>
  {Config.request(Model, Reason, Telemetry, Fetch, Payload, E, T.ProviderRequestOptions{signal, telemetry, apiKey, fetch, env, onPayload, onResponse, headers, timeout, retries, limit}) == Options.resolve(Reason, retries, limit, signal) : Result<&2, &2, Options.Error, Retry.ProviderRetryOptions<Reason>>}
