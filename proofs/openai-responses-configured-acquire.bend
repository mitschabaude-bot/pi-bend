import Base
import ../laws/openai-responses-configured-acquire.bend as Laws
import ../packages/ai/src/types.bend as T

def Laws.invalid_configuration_has_no_effects(url, defaults, model, prepared, settings, request, effects, release, cause):
  match settings:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _}: {==}
def Laws.successful_body_transfers_unchanged(E, State, body): {==}
def Laws.acquisition_error_retains_cause(E, State, cause): {==}
