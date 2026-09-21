import Base
import ./provider-retry.bend as T
import ../src/utils/provider-retry.bend as R
import ../src/utils/provider-retry-sleep.bend as S
import ../../runtime/src/abort.bend as A
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C
import ../../runtime/test/utf8-runner.bend as H

def abortSoon(signal: A.AbortSignal<String>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(5)
    changed : Bool <- A.abort(String, A.AbortController{signal}, Some{"stop"})
    return Unit{}

def perform(abort: Bool, input: R.SleepInput<String>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match abort input:
    case True{} R.SleepInput{milliseconds, Some{+signal}}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        task : Chan(Unit) <- IO.fork(Unit, abortSoon(signal))
        result : Result<&2, &2, R.SleepError, Unit> <- S.sleep(String, R.SleepInput{milliseconds, Some{signal}})
        joined : Unit <- IO.join(Unit, task)
        return result
    case _ value: S.sleep(String, value)

def sleepBody(abort: Bool, +input: R.SleepInput<String>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  match input:
    case R.SleepInput{milliseconds, _}:
      do IO<Result<&2, &2, R.SleepError, Unit>>:
        IO.print("sleep " ++ T.scalar(F.toBits(milliseconds)))
        perform(abort, input)

def callbackBody(abort: Bool, input: R.SleepInput<String>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  sleepBody(abort, input)

def run(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    +sleep : C.Callback<R.SleepInput<String>, Result<&2, &2, R.SleepError, Unit>> <- C.create(~Bool, ~R.SleepInput<String>, ~Result<&2, &2, R.SleepError, Unit>, ~callbackBody, U32.is_eq(mode, 4))
    T.runWithSleep(T.config(mode), sleep)
    C.dispose(R.SleepInput<String>, Result<&2, &2, R.SleepError, Unit>, sleep)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> Nil{}: run(H.decimal(mode, 0))
    case _: IO.die(Unit, 1, "expected mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
