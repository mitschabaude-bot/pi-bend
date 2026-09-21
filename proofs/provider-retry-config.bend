import Base
import ../laws/provider-retry-config.bend as Laws

def Laws.request_uses_only_retry_settings(Model, Reason, Telemetry, Fetch, Payload, E, signal, telemetry, apiKey, fetch, env, onPayload, onResponse, headers, timeout, retries, limit): {==}
