import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-hook-options.bend as Options
import ../packages/ai/src/utils/provider-hook-map.bend as Map

# An independent projection forgets both hooks and their error type, so the
# invariant compares all other fields across different error domains.
def configuration(-Value: Data, -Model: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -E: Data, options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, E>) -> T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Unit>:
  match options:
    case T.ProviderRequestOptions{signal, telemetry, key, fetch, env, _, _, headers, timeout, count, delay}:
      T.ProviderRequestOptions{signal, telemetry, key, fetch, env, None{}, None{}, headers, timeout, count, delay}

law replacement_preserves_all_other_options:
  for -Value: Data
  for -Model: Data
  for -Signal: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Source: Data
  for -Target: Data
  for options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Source>
  for adapted: Map.Hooks<Value, Model, Target>
  {configuration(Value, Model, Signal, Telemetry, Fetch, Target, Options.replace(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, adapted)) == configuration(Value, Model, Signal, Telemetry, Fetch, Source, options) : T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Unit>}

law replacement_installs_exact_hooks:
  for -Value: Data
  for -Model: Data
  for -Signal: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Source: Data
  for -Target: Data
  for options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Source>
  for adapted: Map.Hooks<Value, Model, Target>
  {Options.hooks(Value, Model, Signal, Telemetry, Fetch, Target, Options.replace(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, adapted)) == adapted : Map.Hooks<Value, Model, Target>}
