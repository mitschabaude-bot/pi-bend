import Base
import ./provider-retry-policy.bend as P
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/callback.bend as C

# Provider adapters classify failures at their typed boundary, retaining the
# original error. No reflection or reconstruction of error objects is needed.
type ProviderError<-E: Data> is Data:
  ProviderError{original: E, message: String, status: Maybe<&2, F.F64>, shouldRetry: Maybe<&2, String>, retryAfterMs: Maybe<&2, String>, retryAfter: Maybe<&2, String>}

type RequestFailure<-E: Data> is Data:
  Provider{error: ProviderError<E>}
  Other{original: E}

type RetryFailure<-E: Data> is Data:
  RequestFailed{error: RequestFailure<E>}
  RequestAborted{}
  DelayRejected{error: P.DelayError, providerMessage: String}

type ProviderRetryOptions<-Reason: Data> is Data:
  ProviderRetryOptions{maxRetries: Maybe<&2, Nat>, maxRetryDelayMs: Maybe<&2, F.F64>, signal: Maybe<&2, A.AbortSignal<Reason>>}

type SleepInput<-Reason: Data> is Data:
  SleepInput{milliseconds: F.F64, signal: Maybe<&2, A.AbortSignal<Reason>>}

# Effect handles are borrowed for the duration of the request loop. The caller
# owns their disposal; production and virtual-time tests use the same loop.
type Effects<-Reason: Data> is Data:
  Effects{random: C.Callback<Unit, F.F64>, parseDate: C.Callback<String, F.F64>, now: C.Callback<Unit, F.F64>, sleep: C.Callback<SleepInput<Reason>, Result<&2, &2, Unit, Unit>>}

type Decision<-E: Data, -Value: Data> is Data:
  Finished{result: Result<&2, &2, RetryFailure<E>, Value>}
  Retry{}

def signalAborted(-Reason: Data, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: A.aborted(Reason, value)

def delay(-Reason: Data, effects: Effects<Reason>, source: P.DelaySource, index: Nat, maximum: Maybe<&2, F.F64>) -> IO(Result<&2, &2, P.DelayError, F.F64>):
  match effects:
    case Effects{random, parseDate, now, _}:
      match source:
        case P.Backoff{}:
          do IO<Result<&2, &2, P.DelayError, F.F64>>:
            value : F.F64 <- C.call(Unit, F.F64, random, Unit{})
            return Done{P.backoffDelay(index, value)}
        case P.ServerMilliseconds{value}: IO.pure(Result<&2, &2, P.DelayError, F.F64>, P.validateServerRetryDelayMs(value, maximum))
        case P.ServerDate{text}:
          do IO<Result<&2, &2, P.DelayError, F.F64>>:
            epoch : F.F64 <- C.call(String, F.F64, parseDate, text)
            current : F.F64 <- C.call(Unit, F.F64, now, Unit{})
            return P.resolveServerDate(epoch, current, maximum)

def afterSleep(-E: Data, -Value: Data, result: Result<&2, &2, Unit, Unit>) -> Decision<E, Value>:
  match result:
    case Done{_}: Retry{}
    case Fail{_}: Finished{Fail{RequestAborted{}}}

def sleepDelay(-Reason: Data, -E: Data, -Value: Data, effects: Effects<Reason>, signal: Maybe<&2, A.AbortSignal<Reason>>, message: String, result: Result<&2, &2, P.DelayError, F.F64>) -> IO(Decision<E, Value>):
  match effects result:
    case _ Fail{error}: IO.pure(Decision<E, Value>, Finished{Fail{DelayRejected{error, message}}})
    case Effects{_, _, _, sleep} Done{milliseconds}:
      do IO<Decision<E, Value>>:
        slept : Result<&2, &2, Unit, Unit> <- C.call(SleepInput<Reason>, Result<&2, &2, Unit, Unit>, sleep, SleepInput{milliseconds, signal})
        return afterSleep(E, Value, slept)

def providerDecision(-Reason: Data, -E: Data, -Value: Data, +effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, error: ProviderError<E>, retryable: Bool) -> IO(Decision<E, Value>):
  match options error retryable:
    case _ value False{}: IO.pure(Decision<E, Value>, Finished{Fail{RequestFailed{Provider{value}}}})
    case ProviderRetryOptions{_, maximum, signal} ProviderError{_, message, _, _, milliseconds, seconds} True{}:
      do IO<Decision<E, Value>>:
        result : Result<&2, &2, P.DelayError, F.F64> <- delay(Reason, effects, P.selectDelaySource(milliseconds, seconds), index, maximum)
        sleepDelay(Reason, E, Value, effects, signal, message, result)

def canRetry(-E: Data, error: ProviderError<E>) -> Bool:
  match error:
    case ProviderError{_, _, status, shouldRetry, _, _}: P.isRetryableProviderError(status, shouldRetry)

def classify(-Reason: Data, -E: Data, -Value: Data, effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, failure: RequestFailure<E>) -> IO(Decision<E, Value>):
  match failure:
    case Other{original}: IO.pure(Decision<E, Value>, Finished{Fail{RequestFailed{Other{original}}}})
    case Provider{+error}: providerDecision(Reason, E, Value, effects, options, index, error, canRetry(E, error))

def failed(-Reason: Data, -E: Data, -Value: Data, effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, failure: RequestFailure<E>, aborted: Bool, exhausted: Bool) -> IO(Decision<E, Value>):
  match aborted exhausted:
    case True{} _: IO.pure(Decision<E, Value>, Finished{Fail{RequestAborted{}}})
    case False{} True{}: IO.pure(Decision<E, Value>, Finished{Fail{RequestFailed{failure}}})
    case False{} False{}: classify(Reason, E, Value, effects, options, index, failure)

def received(-Reason: Data, -E: Data, -Value: Data, effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>, index: Nat, exhausted: Bool, result: Result<&2, &2, RequestFailure<E>, Value>) -> IO(Decision<E, Value>):
  match options result:
    case _ Done{value}: IO.pure(Decision<E, Value>, Finished{Done{value}})
    case ProviderRetryOptions{_, _, signal} Fail{failure}:
      do IO<Decision<E, Value>>:
        aborted : Bool <- signalAborted(Reason, signal)
        failed(Reason, E, Value, effects, options, index, failure, aborted, exhausted)

def resume(-E: Data, -Value: Data, decision: Decision<E, Value>, next: Unit -> IO(Result<&2, &2, RetryFailure<E>, Value>)) -> IO(Result<&2, &2, RetryFailure<E>, Value>):
  match decision:
    case Finished{result}: IO.pure(Result<&2, &2, RetryFailure<E>, Value>, result)
    case Retry{}: next(Unit{})

def exhaustedResult(-E: Data, -Value: Data, decision: Decision<E, Value>) -> IO(Result<&2, &2, RetryFailure<E>, Value>):
  resume(E, Value, decision, unused => IO.die(Result<&2, &2, RetryFailure<E>, Value>, 1, "exhausted retry loop continued"))

# The decreasing retry count bounds the loop; requests always run at least once,
# even with an already-aborted signal. Successful requests are returned directly.
def loop(-Reason: Data, -E: Data, -Value: Data, +request: C.Callback<Unit, Result<&2, &2, RequestFailure<E>, Value>>, +effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>, remaining: Nat, +index: Nat) -> IO(Result<&2, &2, RetryFailure<E>, Value>):
  match remaining:
    case Zero{}:
      do IO<Result<&2, &2, RetryFailure<E>, Value>>:
        result : Result<&2, &2, RequestFailure<E>, Value> <- C.call(Unit, Result<&2, &2, RequestFailure<E>, Value>, request, Unit{})
        decision : Decision<E, Value> <- received(Reason, E, Value, effects, options, index, True{}, result)
        exhaustedResult(E, Value, decision)
    case Succ{rest}:
      do IO<Result<&2, &2, RetryFailure<E>, Value>>:
        result : Result<&2, &2, RequestFailure<E>, Value> <- C.call(Unit, Result<&2, &2, RequestFailure<E>, Value>, request, Unit{})
        decision : Decision<E, Value> <- received(Reason, E, Value, effects, options, index, False{}, result)
        resume(E, Value, decision, unused => loop(Reason, E, Value, request, effects, options, rest, Succ{index}))

def retryCount(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 0n
    case Some{count}: count

def retryProviderRequest(-Reason: Data, -E: Data, -Value: Data, request: C.Callback<Unit, Result<&2, &2, RequestFailure<E>, Value>>, effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>) -> IO(Result<&2, &2, RetryFailure<E>, Value>):
  match options:
    case ProviderRetryOptions{maximum, _, _}: loop(Reason, E, Value, request, effects, options, retryCount(maximum), 0n)
