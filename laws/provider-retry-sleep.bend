import Base
import ../packages/ai/src/utils/provider-retry-sleep.bend as Sleep
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/timer-delay.bend as Delay
import ../packages/runtime/src/abort.bend as Abort

law invalid_duration_has_no_timer_effect:
  for -Reason: Data
  for error: Delay.Error
  for signal: Maybe<&2, Abort.AbortSignal<Reason>>
  {Sleep.converted(Reason, Fail{error}, signal) == IO.pure(Result<&2, &2, Retry.SleepError, Unit>, Fail{Retry.InvalidSleepDuration{error}}) : IO(Result<&2, &2, Retry.SleepError, Unit>)}
