import Base
import ../laws/provider-retry.bend as Laws
import ../packages/ai/src/utils/provider-retry.bend as Retry

def Laws.success_bypasses_retry_effects(v, Reason, E, Value, effects, options, index, exhausted, value):
  match options:
    case Retry.ProviderRetryOptions{_, _, _}: {==}

def Laws.finished_bypasses_continuation(v, E, Value, result, next): {==}
def Laws.retry_invokes_continuation(v, E, Value, next): {==}
def Laws.abort_stops_failed_request(v, Reason, E, Value, effects, options, index, error, exhausted): {==}
def Laws.exhaustion_preserves_failure(v, Reason, E, Value, effects, options, index, error): {==}
def Laws.application_failure_is_not_retried(v, Reason, E, Value, effects, options, index, error): {==}
