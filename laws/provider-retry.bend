import Base
import ../packages/runtime/src/timer.bend as Delay
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/f64.bend as N
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/abort.bend as A

# These IO-program equalities quantify over affine as well as copyable values.
# They establish which branches can invoke effects, not universal termination.
law success_bypasses_retry_effects:
  for -v: Quant
  for -Reason: Data
  for -E: Data
  for -Value: Kind(v)
  for effects: Retry.Effects<Reason>
  for options: Retry.ProviderRetryOptions<Reason>
  for index: Nat
  for exhausted: Bool
  for value: Value
  {Retry.received(v, Reason, E, Value, effects, options, index, exhausted, Done{value}) == IO.pure(Retry.Decision<v, E, Value>, Retry.Finished{Done{value}}) : IO(Retry.Decision<v, E, Value>)}

law finished_bypasses_continuation:
  for -v: Quant
  for -E: Data
  for -Value: Kind(v)
  for result: Result<&2, v, Retry.RetryFailure<E>, Value>
  for next: Unit -> IO(Result<&2, v, Retry.RetryFailure<E>, Value>)
  {Retry.resume(v, E, Value, Retry.Finished{result}, next) == IO.pure(Result<&2, v, Retry.RetryFailure<E>, Value>, result) : IO(Result<&2, v, Retry.RetryFailure<E>, Value>)}

law retry_invokes_continuation:
  for -v: Quant
  for -E: Data
  for -Value: Kind(v)
  for next: Unit -> IO(Result<&2, v, Retry.RetryFailure<E>, Value>)
  {Retry.resume(v, E, Value, Retry.Retry{}, next) == next(Unit{}) : IO(Result<&2, v, Retry.RetryFailure<E>, Value>)}

law abort_stops_failed_request:
  for -v: Quant
  for -Reason: Data
  for -E: Data
  for -Value: Kind(v)
  for effects: Retry.Effects<Reason>
  for options: Retry.ProviderRetryOptions<Reason>
  for index: Nat
  for error: Retry.RequestFailure<E>
  for exhausted: Bool
  {Retry.failed(v, Reason, E, Value, effects, options, index, error, True{}, exhausted) == IO.pure(Retry.Decision<v, E, Value>, Retry.Finished{Fail{Retry.RequestAborted{}}}) : IO(Retry.Decision<v, E, Value>)}

law exhaustion_preserves_failure:
  for -v: Quant
  for -Reason: Data
  for -E: Data
  for -Value: Kind(v)
  for effects: Retry.Effects<Reason>
  for options: Retry.ProviderRetryOptions<Reason>
  for index: Nat
  for error: Retry.RequestFailure<E>
  {Retry.failed(v, Reason, E, Value, effects, options, index, error, False{}, True{}) == IO.pure(Retry.Decision<v, E, Value>, Retry.Finished{Fail{Retry.RequestFailed{error}}}) : IO(Retry.Decision<v, E, Value>)}

law application_failure_is_not_retried:
  for -v: Quant
  for -Reason: Data
  for -E: Data
  for -Value: Kind(v)
  for effects: Retry.Effects<Reason>
  for options: Retry.ProviderRetryOptions<Reason>
  for index: Nat
  for error: E
  {Retry.classify(v, Reason, E, Value, effects, options, index, Retry.Other{error}) == IO.pure(Retry.Decision<v, E, Value>, Retry.Finished{Fail{Retry.RequestFailed{Retry.Other{error}}}}) : IO(Retry.Decision<v, E, Value>)}

law invalid_sleep_retains_cause:
  for -v: Quant
  for -E: Data
  for -Value: Kind(v)
  for error: Delay.Error
  {Retry.afterSleep(v, E, Value, Fail{Retry.InvalidSleepDuration{error}}) == Retry.Finished{Fail{Retry.SleepRejected{error}}} : Retry.Decision<v, E, Value>}

law sleep_cancellation_is_abort:
  for -v: Quant
  for -E: Data
  for -Value: Kind(v)
  {Retry.afterSleep(v, E, Value, Fail{Retry.SleepAborted{}}) == Retry.Finished{Fail{Retry.RequestAborted{}}} : Retry.Decision<v, E, Value>}

law completed_sleep_allows_retry:
  for -v: Quant
  for -E: Data
  for -Value: Kind(v)
  {Retry.afterSleep(v, E, Value, Done{Unit{}}) == Retry.Retry{} : Retry.Decision<v, E, Value>}

# Option validation at the provider boundary.
law accepted_options_preserve_all_fields:
  for -Reason: Data
  for retries: Maybe<&2, Nat>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for limit: Maybe<&2, F64>
  {Retry.completed(Reason, retries, signal, Done{limit}) == Done{Retry.ProviderRetryOptions{retries, limit, signal}} : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

law retry_count_error_precedes_delay_validation:
  for -Reason: Data
  for limit: Maybe<&2, F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  for cause: Retry.OptionsError
  {Retry.counted(Reason, limit, signal, Fail{cause}) == Fail{cause} : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

law invalid_count_retains_conversion_cause:
  for cause: N.Error
  {Retry.countValue(Fail{cause}) == Fail{Retry.InvalidRetryCount{cause}} : Result<&2, &2, Retry.OptionsError, Maybe<&2, Nat>>}

law valid_count_retains_presence:
  for count: Nat
  {Retry.countValue(Done{count}) == Done{Some{count}} : Result<&2, &2, Retry.OptionsError, Maybe<&2, Nat>>}

law invalid_delay_retains_original_value:
  for value: F64
  {Retry.delayChecked(value, False{}) == Fail{Retry.InvalidDelayLimit{value}} : Result<&2, &2, Retry.OptionsError, Maybe<&2, F64>>}

law valid_delay_retains_original_value:
  for value: F64
  {Retry.delayChecked(value, True{}) == Done{Some{value}} : Result<&2, &2, Retry.OptionsError, Maybe<&2, F64>>}

law absent_options_preserve_default_selection:
  for -Reason: Data
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  {Retry.resolve(Reason, None{}, None{}, signal) == Done{Retry.ProviderRetryOptions{None{}, None{}, signal}} : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

def withSignal(-Reason: Data, signal: Maybe<&2, A.AbortSignal<Reason>>, value: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>) -> Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Retry.ProviderRetryOptions{retries, limit, _}}: Done{Retry.ProviderRetryOptions{retries, limit, signal}}

# Validation and numeric policy never depend on which signal was selected.
# This constrains the complete resolve pipeline, including all error paths.
law signal_selection_is_independent_of_numeric_validation:
  for -Reason: Data
  for retries: Maybe<&2, F64>
  for limit: Maybe<&2, F64>
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  {Retry.resolve(Reason, retries, limit, signal) == withSignal(Reason, signal, Retry.resolve(Reason, retries, limit, None{})) : Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>}

# Native sleeps.
law invalid_duration_has_no_timer_effect:
  for -Reason: Data
  for error: Delay.Error
  for signal: Maybe<&2, A.AbortSignal<Reason>>
  {Retry.converted(Reason, Fail{error}, signal) == IO.pure(Result<&2, &2, Retry.SleepError, Unit>, Fail{Retry.InvalidSleepDuration{error}}) : IO(Result<&2, &2, Retry.SleepError, Unit>)}
