import Base
import ../types.bend as T
import ./provider-retry.bend as Retry
import ./provider-retry-options.bend as Options
import ../../../runtime/src/abort.bend as Abort

# Resolve the canonical public options at the provider boundary. Other request
# settings and borrowed hooks stay with the caller; this projection has no IO.
def request(-Model: Data, -Reason: Data, -Telemetry: Data, -Fetch: Data, -Payload: Data, -E: Data, options: T.ProviderRequestOptions<Model, Abort.AbortSignal<Reason>, Telemetry, Fetch, Payload, E>) -> Result<&2, &2, Options.Error, Retry.ProviderRetryOptions<Reason>>:
  match options:
    case T.ProviderRequestOptions{signal, _, _, _, _, _, _, _, _, retries, limit}: Options.resolve(Reason, retries, limit, signal)

def stream(-Value: Data, -Reason: Data, -Telemetry: Data, -Fetch: Data, -E: Data, options: T.StreamOptions<Value, Abort.AbortSignal<Reason>, Telemetry, Fetch, E>) -> Result<&2, &2, Options.Error, Retry.ProviderRetryOptions<Reason>>:
  request(T.Model<Value>, Reason, Telemetry, Fetch, Value, E, T.toProviderRequestOptions(Value, Abort.AbortSignal<Reason>, Telemetry, Fetch, E, options))
