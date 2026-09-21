import Base
import ../packages/ai/src/utils/provider-retry-options.bend as O
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/f64-natural.bend as N
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/abort.bend as A

law accepted_options_preserve_all_fields:
  for -Reason: Data
  for retries: Maybe<&2, Nat>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for limit: Maybe<&2, F.F64>
  {O.completed(Reason, retries, signal, Done{limit}) == Done{Retry.ProviderRetryOptions{retries, limit, signal}} : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}

law retry_count_error_precedes_delay_validation:
  for -Reason: Data
  for limit: Maybe<&2, F.F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for cause: O.Error
  {O.counted(Reason, limit, signal, Fail{cause}) == Fail{cause} : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}

law invalid_count_retains_conversion_cause:
  for cause: N.Error
  {O.countValue(Fail{cause}) == Fail{O.InvalidRetryCount{cause}} : Result<&2, &2, O.Error, Maybe<&2, Nat>>}

law valid_count_retains_presence:
  for count: Nat
  {O.countValue(Done{count}) == Done{Some{count}} : Result<&2, &2, O.Error, Maybe<&2, Nat>>}

law invalid_delay_retains_original_value:
  for value: F.F64
  {O.delayChecked(value, False{}) == Fail{O.InvalidDelayLimit{value}} : Result<&2, &2, O.Error, Maybe<&2, F.F64>>}

law valid_delay_retains_original_value:
  for value: F.F64
  {O.delayChecked(value, True{}) == Done{Some{value}} : Result<&2, &2, O.Error, Maybe<&2, F.F64>>}

law absent_options_preserve_default_selection:
  for -Reason: Data
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  {O.resolve(Reason, None{}, None{}, signal) == Done{Retry.ProviderRetryOptions{None{}, None{}, signal}} : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}

def withSignal(-Reason: Data, signal: Maybe<&2, A.AbortSignal<Reason>>, value: Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>) -> Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Retry.ProviderRetryOptions{retries, limit, _}}: Done{Retry.ProviderRetryOptions{retries, limit, signal}}

# Validation and numeric policy never depend on which signal was selected.
# This constrains the complete resolve pipeline, including all error paths.
law signal_selection_is_independent_of_numeric_validation:
  for -Reason: Data
  for retries: Maybe<&2, F.F64>
  for limit: Maybe<&2, F.F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  {O.resolve(Reason, retries, limit, signal) == withSignal(Reason, signal, O.resolve(Reason, retries, limit, None{})) : Result<&2, &2, O.Error, Retry.ProviderRetryOptions<Reason>>}
