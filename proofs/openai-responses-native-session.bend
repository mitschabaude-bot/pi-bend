import Base
import ../laws/openai-responses-native-session.bend as Laws
import ../packages/ai/src/types.bend as T

def Laws.supplied_signal_selection_has_no_effects(Reason, signal): {==}
def Laws.supplied_signal_retirement_has_no_effects(Reason, signal): {==}
def Laws.borrowing_preserves_supplied_signal(Reason, signal): {==}
def Laws.borrowing_preserves_local_controller(Reason, controller): {==}
def Laws.acquisition_preserves_owned_response(Reason, SourceError, HookError, response): {==}
def Laws.acquisition_preserves_typed_failure(Reason, SourceError, HookError, cause): {==}
def Laws.chosen_signal_reaches_retry_options(Reason, SourceError, HookError, Telemetry, CustomFetch, signal, options):
  match options:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.binding_preserves_other_options(Reason, SourceError, HookError, Telemetry, CustomFetch, signal, options):
  match options:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _}: {==}
