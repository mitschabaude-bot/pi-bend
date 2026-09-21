import Base
import ../laws/provider-hook-options.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-hook-map.bend as Map

def Laws.replacement_preserves_all_other_options(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, adapted):
  match options adapted:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _} Map.Hooks{_, _}: {==}
def Laws.replacement_installs_exact_hooks(Value, Model, Signal, Telemetry, Fetch, Source, Target, options, adapted):
  match options adapted:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _} Map.Hooks{_, _}: {==}
