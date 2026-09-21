import Base
import ../laws/provider-retry-options.bend as Laws
import ../packages/ai/src/utils/provider-retry-options.bend as O
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/f64.bend as F

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
  for value: Result<&2, &2, O.Error, Maybe<&2, F.F64>>
  {O.completed(Reason, retries, signal, value) == Laws.withSignal(Reason, signal, O.completed(Reason, retries, None{}, value)) : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}

def completed_signal(Reason, retries, signal, value):
  match value:
    case Fail{cause}: {==}
    case Done{limit}: {==}

law counted_signal:
  for -Reason: Data
  for limit: Maybe<&2, F.F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for value: Result<&2, &2, O.Error, Maybe<&2, Nat>>
  {O.counted(Reason, limit, signal, value) == Laws.withSignal(Reason, signal, O.counted(Reason, limit, None{}, value)) : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}

def counted_signal(Reason, limit, signal, value):
  match value:
    case Fail{cause}: {==}
    case Done{retries}: completed_signal(Reason, retries, signal, O.delay(limit))

def Laws.signal_selection_is_independent_of_numeric_validation(Reason, retries, limit, signal):
  counted_signal(Reason, limit, signal, O.count(retries))
