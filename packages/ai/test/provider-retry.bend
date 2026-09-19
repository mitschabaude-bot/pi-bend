import Base
import ../src/utils/provider-retry.bend as P
import ../src/utils/provider-retry-error.bend as Error
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/abort.bend as A
import ../../runtime/test/utf8-runner.bend as H

type Config is Data:
  Config{failures: U32, retries: Maybe<&2, Nat>, error: P.RequestFailure<String>, cap: Maybe<&2, F.F64>, preAbort: Bool, abortSleep: Bool}

def failure(status: U32, retry: Maybe<&2, String>, ms: Maybe<&2, String>, seconds: Maybe<&2, String>) -> P.RequestFailure<String>:
  P.Provider{P.ProviderError{"original", "provider message", Some{F.fromU32(status)}, retry, ms, seconds}}

def config(mode: U32) -> Config:
  match mode:
    case 0: Config{1, Some{1n}, failure(429, None{}, Some{"1000"}, None{}), None{}, False{}, False{}}
    case 1: Config{9, Some{2n}, failure(429, Some{"false"}, None{}, None{}), None{}, False{}, False{}}
    case 2: Config{9, Some{1n}, failure(429, None{}, None{}, Some{"277403"}), Some{F.fromU32(1000)}, False{}, False{}}
    case 3: Config{1, Some{1n}, failure(429, None{}, None{}, Some{"2"}), Some{F.fromU32(0)}, False{}, False{}}
    case 4: Config{9, Some{2n}, failure(429, None{}, None{}, Some{"277403"}), Some{F.fromU32(0)}, False{}, True{}}
    case 5: Config{9, None{}, failure(429, None{}, None{}, None{}), None{}, False{}, False{}}
    case 6: Config{9, Some{2n}, P.Other{"original"}, None{}, False{}, False{}}
    case 7: Config{9, Some{2n}, failure(500, None{}, None{}, None{}), None{}, False{}, False{}}
    case 8: Config{0, Some{2n}, failure(429, None{}, None{}, None{}), None{}, True{}, False{}}
    case 9: Config{9, Some{0n}, failure(429, None{}, None{}, None{}), None{}, True{}, False{}}
    case 10: Config{1, Some{1n}, failure(400, Some{"true"}, Some{"1"}, None{}), None{}, False{}, False{}}
    case _: Config{1, Some{1n}, failure(429, None{}, None{}, Some{"invalid-date"}), None{}, False{}, False{}}

def requestResult(fail: Bool, error: P.RequestFailure<String>) -> Result<&2, &2, P.RequestFailure<String>, String>:
  match fail:
    case True{}: Fail{error}
    case False{}: Done{"ok"}

def next(+count: U32) -> U32 & U32: ((count + 1 : U32), count)

type RequestEnvironment is Data:
  RequestEnvironment{counter: R.Ref<U32>, configuration: Config}

def requestBody(environment: RequestEnvironment, unused: Unit) -> IO(Result<&2, &2, P.RequestFailure<String>, String>):
  match environment:
    case RequestEnvironment{counter, Config{failures, _, error, _, _, _}}:
      do IO<Result<&2, &2, P.RequestFailure<String>, String>>:
        count : U32 <- R.modify(U32, U32, counter, value => next(value))
        IO.print("request")
        return requestResult(U32.is_lt(count, failures), error)

def randomBody(environment: Unit, unused: Unit) -> IO(F.F64):
  do IO<F.F64>:
    IO.print("random")
    return F.fromU32(0)

def dateBody(environment: Unit, text: String) -> IO(F.F64):
  do IO<F.F64>:
    IO.print("date " ++ text)
    return F.nan()

def nowBody(environment: Unit, unused: Unit) -> IO(F.F64):
  do IO<F.F64>:
    IO.print("now")
    return F.fromU32(1000)

def scalar(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def sleepResult(abort: Bool) -> Result<&2, &2, Unit, Unit>:
  match abort:
    case True{}: Fail{Unit{}}
    case False{}: Done{Unit{}}

def sleepBody(abort: Bool, input: P.SleepInput<String>) -> IO(Result<&2, &2, Unit, Unit>):
  match input:
    case P.SleepInput{ms, _}:
      do IO<Result<&2, &2, Unit, Unit>>:
        IO.print("sleep " ++ scalar(F.toBits(ms)))
        return sleepResult(abort)

def preAbort(abort: Bool, controller: A.AbortController<String>) -> IO(Unit):
  match abort:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        changed : Bool <- A.abort(String, controller, Some{"stop"})
        return Unit{}

def showLimit(result: Result<&2, &2, Error.FormattingError, Error.RenderedError>) -> IO(Unit):
  match result:
    case Done{Error.RenderedError{name, message}}: IO.print(name ++ ":" ++ message)
    case Fail{_}: IO.die(Unit, 1, "retry error formatting failed")

def show(result: Result<&2, &2, P.RetryFailure<String>, String>) -> IO(Unit):
  match result:
    case Done{value}: IO.print("done " ++ value)
    case Fail{P.RequestAborted{}}: IO.print("abort")
    case Fail{P.DelayRejected{error, message}}: showLimit(Error.delayError(error, message))
    case Fail{P.RequestFailed{P.Other{original}}}: IO.print("other " ++ original)
    case Fail{P.RequestFailed{P.Provider{P.ProviderError{original, _, _, _, _, _}}}}: IO.print("provider " ++ original)

def runWithSleep(+configuration: Config, sleep: C.Callback<P.SleepInput<String>, Result<&2, &2, Unit, Unit>>) -> IO(Unit):
  match configuration:
    case Config{_, retries, _, cap, aborted, abortSleep}:
      do IO<Unit>:
        +counter : R.Ref<U32> <- R.new(U32, 0)
        +controller : A.AbortController<String> <- A.new(String)
        preAbort(aborted, controller)
        +request : C.Callback<Unit, Result<&2, &2, P.RequestFailure<String>, String>> <- C.create(~RequestEnvironment, ~Unit, ~Result<&2, &2, P.RequestFailure<String>, String>, ~requestBody, RequestEnvironment{counter, configuration})
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~nowBody, Unit{})
        result : Result<&2, &2, P.RetryFailure<String>, String> <- P.retryProviderRequest(String, String, String, request, P.Effects{random, date, now, sleep}, P.ProviderRetryOptions{retries, cap, Some{A.signal(String, controller)}})
        show(result)
        C.dispose(Unit, Result<&2, &2, P.RequestFailure<String>, String>, request)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        count : U32 <- R.dispose(U32, counter)
        A.dispose(String, controller)
        return Unit{}

def run(+configuration: Config) -> IO(Unit):
  match configuration:
    case Config{_, _, _, _, _, abortSleep}:
      do IO<Unit>:
        +sleep : C.Callback<P.SleepInput<String>, Result<&2, &2, Unit, Unit>> <- C.create(~Bool, ~P.SleepInput<String>, ~Result<&2, &2, Unit, Unit>, ~sleepBody, abortSleep)
        runWithSleep(configuration, sleep)
        C.dispose(P.SleepInput<String>, Result<&2, &2, Unit, Unit>, sleep)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> Nil{}: run(config(H.decimal(mode, 0)))
    case _: IO.die(Unit, 1, "expected mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
