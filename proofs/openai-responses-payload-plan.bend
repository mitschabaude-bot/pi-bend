import Base
import ../laws/openai-responses-payload-plan.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-retry.bend as Retry

def Laws.validated_wire_retains_original_preparation_and_callbacks(Reason, Source, Hook, original, wire, response, retry): {==}
def Laws.payload_failure_preserves_typed_cause(Reason, Source, Hook, Telemetry, Fetch, original, options, retry, cause): {==}
def Laws.selected_payload_cannot_invoke_payload_hook_again(Reason, Source, Hook, Telemetry, Fetch, options):
  match options:
    case T.ProviderRequestOptions{_, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.envelope_failure_retains_cause_without_cancellation(Reason, Source, Hook, cause): {==}
def Laws.observed_cancellation_takes_precedence_over_envelope_failure(Reason, Source, Hook, cause): {==}

def Laws.observed_cancellation_prevents_runtime_initialization(Reason, Source, Hook, original, response, retry, result): {==}
