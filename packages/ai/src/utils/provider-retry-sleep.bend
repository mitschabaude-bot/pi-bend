import Base
import ./provider-retry.bend as R
import ../../../runtime/src/abortable-sleep.bend as S
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/timer-delay.bend as Delay

def completed(-Reason: Data, result: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> Result<&2, &2, Unit, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{_}: Fail{Unit{}}

def closeBare(result: Timer & Bool) -> IO(Result<&2, &2, Unit, Unit>):
  match result:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, Unit, Unit>>:
        Timer.close(owner)
        return Done{Unit{}}

def waitBare(pair: Timer & TimerCancel) -> IO(Result<&2, &2, Unit, Unit>):
  match pair:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, Unit, Unit>>:
        result : Timer & Bool <- Timer.wait(owner)
        closeBare(result)

def sleep(-Reason: Data, input: R.SleepInput<Reason>) -> IO(Result<&2, &2, Unit, Unit>):
  match input:
    case R.SleepInput{milliseconds, None{}}:
      do IO<Result<&2, &2, Unit, Unit>>:
        timer : Timer & TimerCancel <- Timer.new(Delay.milliseconds(milliseconds))
        waitBare(timer)
    case R.SleepInput{milliseconds, Some{signal}}:
      do IO<Result<&2, &2, Unit, Unit>>:
        result : Result<&2, &2, A.AbortReason<Reason>, Unit> <- S.sleep(Reason, Delay.milliseconds(milliseconds), signal)
        return completed(Reason, result)
