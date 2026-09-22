import Base
import ../laws/provider-retry.bend as Laws
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/f64.bend as F

def Laws.success_bypasses_retry_effects(v, Reason, E, Value, effects, options, index, exhausted, value):
  match options:
    case Retry.ProviderRetryOptions{_, _, _}: {==}

def Laws.finished_bypasses_continuation(v, E, Value, result, next): {==}
def Laws.retry_invokes_continuation(v, E, Value, next): {==}
def Laws.abort_stops_failed_request(v, Reason, E, Value, effects, options, index, error, exhausted): {==}
def Laws.exhaustion_preserves_failure(v, Reason, E, Value, effects, options, index, error): {==}
def Laws.application_failure_is_not_retried(v, Reason, E, Value, effects, options, index, error): {==}

def Laws.invalid_sleep_retains_cause(v, E, Value, error): {==}
def Laws.sleep_cancellation_is_abort(v, E, Value): {==}
def Laws.completed_sleep_allows_retry(v, E, Value): {==}

def Laws.accepted_options_preserve_all_fields(Reason, retries, signal, limit): {==}
def Laws.retry_count_error_precedes_delay_validation(Reason, limit, signal, cause): {==}
def Laws.invalid_count_retains_conversion_cause(cause): {==}
def Laws.valid_count_retains_presence(count): {==}
def Laws.invalid_delay_retains_original_value(value): {==}
def Laws.valid_delay_retains_original_value(value): {==}
def Laws.absent_options_preserve_default_selection(Reason, signal): {==}


law completed_signal:
  for -Reason: Data
  for retries: Maybe<&2, Nat>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for value: Result<&2, &2, Retry.OptionsError, Maybe<&2, F64>>
  {Retry.completed(Reason, retries, signal, value) == Laws.withSignal(Reason, signal, Retry.completed(Reason, retries, None{}, value)) : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

def completed_signal(Reason, retries, signal, value):
  match value:
    case Fail{cause}: {==}
    case Done{limit}: {==}

law counted_signal:
  for -Reason: Data
  for limit: Maybe<&2, F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for value: Result<&2, &2, Retry.OptionsError, Maybe<&2, Nat>>
  {Retry.counted(Reason, limit, signal, value) == Laws.withSignal(Reason, signal, Retry.counted(Reason, limit, None{}, value)) : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

def counted_signal(Reason, limit, signal, value):
  match value:
    case Fail{cause}: {==}
    case Done{retries}: completed_signal(Reason, retries, signal, Retry.delayLimit(limit))

def Laws.signal_selection_is_independent_of_numeric_validation(Reason, retries, limit, signal):
  counted_signal(Reason, limit, signal, Retry.countOption(retries))

def Laws.invalid_duration_has_no_timer_effect(Reason, error, signal): {==}
