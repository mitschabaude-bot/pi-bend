import Base
import ./provider-retry.bend as R
import ../../../runtime/src/abortable-sleep.bend as S
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/timer-delay.bend as Delay

def completed(-Reason: Data, result: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> Result<&2, &2, R.SleepError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{_}: Fail{R.SleepAborted{}}

def closeBare(result: Timer & Bool) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match result:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        Timer.close(owner)
        return Done{Unit{}}

def waitBare(pair: Timer & TimerCancel) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match pair:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        result : Timer & Bool <- Timer.wait(owner)
        closeBare(result)

def valid(-Reason: Data, milliseconds: U32, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match signal:
    case None{}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        timer : Timer & TimerCancel <- Timer.new(milliseconds)
        waitBare(timer)
    case Some{signal}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        result : Result<&2, &2, A.AbortReason<Reason>, Unit> <- S.sleep(Reason, milliseconds, signal)
        return completed(Reason, result)

def converted(-Reason: Data, result: Result<&2, &2, Delay.Error, U32>, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, R.SleepError, Unit>, Fail{R.InvalidSleepDuration{error}})
    case Done{milliseconds}: valid(Reason, milliseconds, signal)

def sleep(-Reason: Data, input: R.SleepInput<Reason>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match input:
    case R.SleepInput{milliseconds, signal}: converted(Reason, Delay.milliseconds(milliseconds), signal)
