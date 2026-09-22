import Base
import ./provider-retry.bend as T
import ../src/utils/provider-retry.bend as R
import ../src/utils/provider-retry.bend as Sleep
import ../src/utils/provider-retry.bend as E
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/abort.bend as A
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as H

def check(valid: Bool, label: String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def counts(counter: Ref.Ref<U32>, calls: U32, timers: U32) -> IO(Unit):
  do IO<Unit>:
    actual : U32 <- Ref.read(U32, counter)
    pending : U32 <- TestClock.pending()
    check(U32.is_eq(actual, calls), "request count")
    check(U32.is_eq(pending, timers), "pending timer count")

def sleepBody(environment: Unit, input: R.SleepInput<String>) -> IO(Result<&2, &2, R.SleepError, Unit>):
  Sleep.sleep(String, input)

def limit(result: Result<&2, &2, E.FormattingError, E.RenderedError>) -> IO(Unit):
  match result:
    case Done{E.RenderedError{name, message}}:
      check(String.eq(name, "Error") && String.eq(message, "Server requested 277403s retry delay (max: 1s). provider message"), "delay error text")
    case _: IO.die(Unit, 1, "delay error rendering")

def assertion(mode: U32, result: Result<&2, &2, R.RetryFailure<String>, String>) -> IO(Unit):
  match mode result:
    case 0 Done{value}: check(String.eq(value, "ok"), "retry result")
    case 3 Done{value}: check(String.eq(value, "ok"), "disabled cap result")
    case 1 Fail{R.RequestFailed{R.Provider{R.ProviderError{original, _, _, _, _, _}}}}: check(String.eq(original, "original"), "original failure retained")
    case 2 Fail{R.DelayRejected{error, message}}: limit(E.delayError(error, message))
    case 4 Fail{R.RequestAborted{}}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "unexpected retry outcome")

def name(mode: U32) -> String:
  match mode:
    case 0: "retries retryable provider errors"
    case 1: "does not retry errors the provider marks as non-retryable"
    case 2: "rejects a provider-requested retry delay above the limit"
    case 3: "allows disabling the provider-requested retry delay cap"
    case _: "aborts a provider-requested retry delay"

def timed(before: U32, +counter: Ref.Ref<U32>, task: Chan(Result<&2, &2, R.RetryFailure<String>, String>)) -> IO(Result<&2, &2, R.RetryFailure<String>, String>):
  do IO<Result<&2, &2, R.RetryFailure<String>, String>>:
    counts(counter, 1, 1)
    TestClock.advance(before)
    TestClock.barrier()
    counts(counter, 1, 1)
    TestClock.advance(1)
    result : Result<&2, &2, R.RetryFailure<String>, String> <- IO.join(Result<&2, &2, R.RetryFailure<String>, String>, task)
    counts(counter, 2, 0)
    return result

def observe(mode: U32, +counter: Ref.Ref<U32>, controller: A.AbortController<String>, task: Chan(Result<&2, &2, R.RetryFailure<String>, String>)) -> IO(Result<&2, &2, R.RetryFailure<String>, String>):
  match mode:
    case 0: timed(999, counter, task)
    case 3: timed(1999, counter, task)
    case 4:
      do IO<Result<&2, &2, R.RetryFailure<String>, String>>:
        TestClock.advance(0)
        counts(counter, 1, 1)
        won : Bool <- A.abort(String, controller, None{})
        check(won, "first abort")
        result : Result<&2, &2, R.RetryFailure<String>, String> <- IO.join(Result<&2, &2, R.RetryFailure<String>, String>, task)
        counts(counter, 1, 0)
        return result
    case _:
      do IO<Result<&2, &2, R.RetryFailure<String>, String>>:
        result : Result<&2, &2, R.RetryFailure<String>, String> <- IO.join(Result<&2, &2, R.RetryFailure<String>, String>, task)
        counts(counter, 1, 0)
        return result

def signal(mode: U32, controller: A.AbortController<String>) -> Maybe<&2, A.AbortSignal<String>>:
  match mode:
    case 4: Some{A.signal(String, controller)}
    case _: None{}

def run(+mode: U32, +configuration: T.Config) -> IO(Unit):
  match configuration:
    case T.Config{_, retries, _, cap, _, _}:
      do IO<Unit>:
        +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
        +controller : A.AbortController<String> <- A.new(String)
        +request : C.Callback<Unit, Result<&2, &2, R.RequestFailure<String>, String>> <- C.create(~T.RequestEnvironment, ~Unit, ~Result<&2, &2, R.RequestFailure<String>, String>, ~T.requestBody, T.RequestEnvironment{counter, configuration})
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~T.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~T.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~T.nowBody, Unit{})
        +sleep : C.Callback<R.SleepInput<String>, Result<&2, &2, R.SleepError, Unit>> <- C.create(~Unit, ~R.SleepInput<String>, ~Result<&2, &2, R.SleepError, Unit>, ~sleepBody, Unit{})
        task : Chan(Result<&2, &2, R.RetryFailure<String>, String>) <- IO.fork(Result<&2, &2, R.RetryFailure<String>, String>, R.retryProviderRequest(String, String, String, request, R.Effects{random, date, now, sleep}, R.ProviderRetryOptions{retries, cap, signal(mode, controller)}))
        TestClock.barrier()
        result : Result<&2, &2, R.RetryFailure<String>, String> <- observe(mode, counter, controller, task)
        assertion(mode, result)
        C.dispose(Unit, Result<&2, &2, R.RequestFailure<String>, String>, request)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(R.SleepInput<String>, Result<&2, &2, R.SleepError, Unit>, sleep)
        previous : U32 <- Ref.dispose(U32, counter)
        A.dispose(String, controller)
        IO.print("PASS " ++ name(mode))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case text <> Nil{}:
      +mode = H.decimal(text, 0)
      run(mode, T.config(mode))
    case _: IO.die(Unit, 1, "expected case")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
