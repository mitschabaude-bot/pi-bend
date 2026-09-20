import Base
import ../packages/ai/src/utils/provider-retry.bend as Retry

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
