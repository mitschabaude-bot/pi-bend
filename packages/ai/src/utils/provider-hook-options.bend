import Base
import ../types.bend as T
import ./provider-hook-map.bend as Map

# Change only the hook error domain. Signals, fetch handles, environment,
# headers and retry/timeout settings retain their original values.
def hooks(-Value: Data, -Model: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -E: Data, options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, E>) -> Map.Hooks<Value, Model, E>:
  match options:
    case T.ProviderRequestOptions{_, _, _, _, _, payload, response, _, _, _, _}: Map.Hooks{payload, response}

def replace(-Value: Data, -Model: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Source: Data, -Target: Data, options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Source>, adapted: Map.Hooks<Value, Model, Target>) -> T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Target>:
  match options adapted:
    case T.ProviderRequestOptions{signal, telemetry, key, fetch, env, _, _, headers, timeout, count, delay} Map.Hooks{payload, response}:
      T.ProviderRequestOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, count, delay}

def borrowed(-Value: Data, -Model: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Source: Data, -Target: Data, options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Source>, pair: Map.Owner<Value, Model, Target> & Map.Hooks<Value, Model, Target>) -> Map.Owner<Value, Model, Target> & T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Target>:
  match pair:
    case Tuple{owner, adapted}: (owner, replace(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, adapted))

# The returned owner must outlive every use of the adapted options. Disposing
# it retires the adapters, leaving caller-owned hooks and other handles intact.
def create(~Value: Data, ~Model: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Source: Data, ~Target: Data, ~embed: Source -> Target, +options: T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Source>) -> IO(Map.Owner<Value, Model, Target> & T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Target>):
  do IO<Map.Owner<Value, Model, Target> & T.ProviderRequestOptions<Model, Signal, Telemetry, Fetch, Value, Target>>:
    owner : Map.Owner<Value, Model, Target> <- Map.create(~Value, ~Model, ~Source, ~Target, ~embed, hooks(Value, Model, Signal, Telemetry, Fetch, Source, options))
    return borrowed(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, Map.borrow(Value, Model, Target, owner))
