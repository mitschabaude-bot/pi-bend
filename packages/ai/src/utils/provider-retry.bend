import Base
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/socket.bend as S
import ../../../runtime/src/calendar.bend as Calendar
import ../../../runtime/src/calendar.bend as Inverse
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64.bend as Decimal
import ../../../runtime/src/f64.bend as Natural
import ../../../runtime/src/f64.bend as Round
import ../../../runtime/src/http-message.bend as HTTP
import ../../../runtime/src/parse-float.bend as Number
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/timer.bend as Delay
import ../../../runtime/src/u64.bend as W

# pi `provider-retry.ts`: the retry policy shared by the provider SDK
# adapters, the request loop around it, and the native effects (entropy,
# clock, HTTP-date parsing and timer sleeps) the loop consumes. Provider
# adapters classify failures at their typed boundary and keep the original
# error; nothing here reflects on error objects.

# Policy
# ------

# Normalized header values and an optional status; plain application
# failures never enter this policy.
type DelaySource is Data:
  Backoff{}
  ServerMilliseconds{value: F.F64}
  ServerDate{text: String}

type DelayError is Data:
  ServerDelayTooLong{delayMs: F.F64, maxDelayMs: F.F64}

def DEFAULT_MAX_RETRY_DELAY_MS() -> F.F64: F.fromU32(60000)

def atLeast500(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case Some{GT{}}: True{}
    case _: False{}

def equalOrder(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def equal(left: F.F64, right: F.F64) -> Bool: equalOrder(F.compare(left, right))

def retryableStatus(status: Maybe<&2, F.F64>) -> Bool:
  match status:
    case None{}: True{}
    case Some{+value}: equal(value, F.fromU32(408)) || equal(value, F.fromU32(409)) || equal(value, F.fromU32(429)) || atLeast500(F.compare(value, F.fromU32(500)))

# Mirrors the pinned OpenAI/Anthropic SDK retry policy.
def isRetryableProviderError(status: Maybe<&2, F.F64>, shouldRetry: Maybe<&2, String>) -> Bool:
  match shouldRetry:
    case Some{"true"}: True{}
    case Some{"false"}: False{}
    case _: retryableStatus(status)

def secondsOrDate(invalid: Bool, seconds: F.F64, text: String) -> DelaySource:
  match invalid:
    case True{}: ServerDate{text}
    case False{}: ServerMilliseconds{F.multiply(seconds, F.fromU32(1000))}

def retryAfter(value: Maybe<&2, String>) -> DelaySource:
  match value:
    case None{}: Backoff{}
    case Some{SNil{}}: Backoff{}
    case Some{+text}:
      +seconds = Number.parseFloat(text)
      secondsOrDate(F.isNaN(seconds), seconds, text)

def millisecondsOrFallback(invalid: Bool, value: F.F64, fallback: Maybe<&2, String>) -> DelaySource:
  match invalid:
    case True{}: retryAfter(fallback)
    case False{}: ServerMilliseconds{value}

def selectDelaySource(milliseconds: Maybe<&2, String>, seconds: Maybe<&2, String>) -> DelaySource:
  match milliseconds:
    case None{}: retryAfter(seconds)
    case Some{SNil{}}: retryAfter(seconds)
    case Some{text}:
      +value = Number.parseFloat(text)
      millisecondsOrFallback(F.isNaN(value), value, seconds)

def positive(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case _: False{}

def maxDelay(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: DEFAULT_MAX_RETRY_DELAY_MS()
    case Some{scalar}: scalar

def limited(excessive: Bool, delayMs: F.F64, maxDelayMs: F.F64) -> Result<&2, &2, DelayError, F.F64>:
  match excessive:
    case True{}: Fail{ServerDelayTooLong{delayMs, maxDelayMs}}
    case False{}: Done{delayMs}

def validateServerRetryDelayMs(+delayMs: F.F64, maximum: Maybe<&2, F.F64>) -> Result<&2, &2, DelayError, F.F64>:
  +limit = maxDelay(maximum)
  limited(positive(F.compare(limit, F.fromU32(0))) && positive(F.compare(delayMs, limit)), delayMs, limit)

def baseDelay(index: Nat) -> F.F64:
  match index:
    case 0n: F.fromU32(500)
    case 1n: F.fromU32(1000)
    case 2n: F.fromU32(2000)
    case 3n: F.fromU32(4000)
    case _: F.fromU32(8000)

def backoffDelay(retryIndex: Nat, random: F.F64) -> F.F64:
  F.multiply(baseDelay(retryIndex), F.subtract(F.fromU32(1), F.multiply(random, F.divide(F.fromU32(1), F.fromU32(4)))))

# A date instruction is resolved before validating its server delay; backoff
# jitter is not subject to the server-requested-delay cap.
def resolveServerDate(parsedEpochMs: F.F64, nowMs: F.F64, maximum: Maybe<&2, F.F64>) -> Result<&2, &2, DelayError, F.F64>:
  validateServerRetryDelayMs(F.subtract(parsedEpochMs, nowMs), maximum)

# Failures and options
# --------------------

type ProviderError<-E: Data> is Data:
  ProviderError{original: E, message: String, status: Maybe<&2, F.F64>, shouldRetry: Maybe<&2, String>, retryAfterMs: Maybe<&2, String>, retryAfter: Maybe<&2, String>}

type RequestFailure<-E: Data> is Data:
  Provider{error: ProviderError<E>}
  Other{original: E}

type SleepError is Data:
  SleepAborted{}
  InvalidSleepDuration{error: Delay.Error}

type RetryFailure<-E: Data> is Data:
  RequestFailed{error: RequestFailure<E>}
  RequestAborted{}
  SleepRejected{error: Delay.Error}
  DelayRejected{error: DelayError, providerMessage: String}

type ProviderRetryOptions<-Reason: Data> is Data:
  ProviderRetryOptions{maxRetries: Maybe<&2, Nat>, maxRetryDelayMs: Maybe<&2, F.F64>, signal: Maybe<&2, A.AbortSignal<Reason>>}

# The public numeric options are validated once at the provider boundary.
# Absent values keep the defaults (zero retries, a 60-second delay cap; zero
# disables the cap). Invalid configuration is a typed failure, not NaN math.
type OptionsError is Data:
  InvalidRetryCount{cause: Natural.Error}
  InvalidDelayLimit{value: F.F64}

def countValue(value: Result<&2, &2, Natural.Error, Nat>) -> Result<&2, &2, OptionsError, Maybe<&2, Nat>>:
  match value:
    case Fail{cause}: Fail{InvalidRetryCount{cause}}
    case Done{number}: Done{Some{number}}

def countOption(value: Maybe<&2, F.F64>) -> Result<&2, &2, OptionsError, Maybe<&2, Nat>>:
  match value:
    case None{}: Done{None{}}
    case Some{number}: countValue(Natural.convert(number))

def delayChecked(value: F.F64, valid: Bool) -> Result<&2, &2, OptionsError, Maybe<&2, F.F64>>:
  match valid:
    case False{}: Fail{InvalidDelayLimit{value}}
    case True{}: Done{Some{value}}

def nonnegative(comparison: Maybe<&2, Cmp>) -> Bool:
  match comparison:
    case Some{EQ{}}: True{}
    case Some{GT{}}: True{}
    case _: False{}

def finite(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def delayLimit(value: Maybe<&2, F.F64>) -> Result<&2, &2, OptionsError, Maybe<&2, F.F64>>:
  match value:
    case None{}: Done{None{}}
    case Some{+number}: delayChecked(number, finite(F.decode(number)) && nonnegative(F.compare(number, F.fromU32(0))))

def completed(-Reason: Data, retries: Maybe<&2, Nat>, signal: Maybe<&2, A.AbortSignal<Reason>>, value: Result<&2, &2, OptionsError, Maybe<&2, F.F64>>) -> Result<&2, &2, OptionsError, ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{limit}: Done{ProviderRetryOptions{retries, limit, signal}}

def counted(-Reason: Data, limit: Maybe<&2, F.F64>, signal: Maybe<&2, A.AbortSignal<Reason>>, value: Result<&2, &2, OptionsError, Maybe<&2, Nat>>) -> Result<&2, &2, OptionsError, ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{retries}: completed(Reason, retries, signal, delayLimit(limit))

def resolve(-Reason: Data, retries: Maybe<&2, F.F64>, limit: Maybe<&2, F.F64>, signal: Maybe<&2, A.AbortSignal<Reason>>) -> Result<&2, &2, OptionsError, ProviderRetryOptions<Reason>>:
  counted(Reason, limit, signal, countOption(retries))

# The request loop
# ----------------

type SleepInput<-Reason: Data> is Data:
  SleepInput{milliseconds: F.F64, signal: Maybe<&2, A.AbortSignal<Reason>>}

# Effect handles are borrowed for the duration of the request loop. The caller
# owns their disposal; production and virtual-time tests use the same loop.
type Effects<-Reason: Data> is Data:
  Effects{random: C.Callback<Unit, F.F64>, parseDate: C.Callback<String, F.F64>, now: C.Callback<Unit, F.F64>, sleep: C.Callback<SleepInput<Reason>, Result<&2, &2, SleepError, Unit>>}

type Decision<v, -E: Data, -Value: Kind(v)> is Kind(v):
  Finished{result: Result<&2, v, RetryFailure<E>, Value>}
  Retry{}

def signalAborted(-Reason: Data, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: A.aborted(Reason, value)

def delay(-Reason: Data, effects: Effects<Reason>, source: DelaySource, index: Nat, maximum: Maybe<&2, F.F64>) -> IO(Result<&2, &2, DelayError, F.F64>):
  match effects:
    case Effects{random, parseDate, now, _}:
      match source:
        case Backoff{}:
          do IO<Result<&2, &2, DelayError, F.F64>>:
            value : F.F64 <- C.call(Unit, F.F64, random, Unit{})
            return Done{backoffDelay(index, value)}
        case ServerMilliseconds{value}: IO.pure(Result<&2, &2, DelayError, F.F64>, validateServerRetryDelayMs(value, maximum))
        case ServerDate{text}:
          do IO<Result<&2, &2, DelayError, F.F64>>:
            epoch : F.F64 <- C.call(String, F.F64, parseDate, text)
            current : F.F64 <- C.call(Unit, F.F64, now, Unit{})
            return resolveServerDate(epoch, current, maximum)

def afterSleep(v, -E: Data, -Value: Kind(v), result: Result<&2, &2, SleepError, Unit>) -> Decision<v, E, Value>:
  match result:
    case Done{_}: Retry{}
    case Fail{SleepAborted{}}: Finished{Fail{RequestAborted{}}}
    case Fail{InvalidSleepDuration{error}}: Finished{Fail{SleepRejected{error}}}

def sleepDelay(v, -Reason: Data, -E: Data, -Value: Kind(v), effects: Effects<Reason>, signal: Maybe<&2, A.AbortSignal<Reason>>, message: String, result: Result<&2, &2, DelayError, F.F64>) -> IO(Decision<v, E, Value>):
  match effects result:
    case _ Fail{error}: IO.pure(Decision<v, E, Value>, Finished{Fail{DelayRejected{error, message}}})
    case Effects{_, _, _, sleep} Done{milliseconds}:
      do IO<Decision<v, E, Value>>:
        slept : Result<&2, &2, SleepError, Unit> <- C.call(SleepInput<Reason>, Result<&2, &2, SleepError, Unit>, sleep, SleepInput{milliseconds, signal})
        return afterSleep(v, E, Value, slept)

def providerDecision(v, -Reason: Data, -E: Data, -Value: Kind(v), +effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, error: ProviderError<E>, retryable: Bool) -> IO(Decision<v, E, Value>):
  match options error retryable:
    case _ value False{}: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestFailed{Provider{value}}}})
    case ProviderRetryOptions{_, maximum, signal} ProviderError{_, message, _, _, milliseconds, seconds} True{}:
      do IO<Decision<v, E, Value>>:
        result : Result<&2, &2, DelayError, F.F64> <- delay(Reason, effects, selectDelaySource(milliseconds, seconds), index, maximum)
        sleepDelay(v, Reason, E, Value, effects, signal, message, result)

def canRetry(-E: Data, error: ProviderError<E>) -> Bool:
  match error:
    case ProviderError{_, _, status, shouldRetry, _, _}: isRetryableProviderError(status, shouldRetry)

def classify(v, -Reason: Data, -E: Data, -Value: Kind(v), effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, failure: RequestFailure<E>) -> IO(Decision<v, E, Value>):
  match failure:
    case Other{original}: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestFailed{Other{original}}}})
    case Provider{+error}: providerDecision(v, Reason, E, Value, effects, options, index, error, canRetry(E, error))

def failed(v, -Reason: Data, -E: Data, -Value: Kind(v), effects: Effects<Reason>, options: ProviderRetryOptions<Reason>, index: Nat, failure: RequestFailure<E>, aborted: Bool, exhausted: Bool) -> IO(Decision<v, E, Value>):
  match aborted exhausted:
    case True{} _: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestAborted{}}})
    case False{} True{}: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestFailed{failure}}})
    case False{} False{}: classify(v, Reason, E, Value, effects, options, index, failure)

def received(v, -Reason: Data, -E: Data, -Value: Kind(v), effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>, index: Nat, exhausted: Bool, result: Result<&2, v, RequestFailure<E>, Value>) -> IO(Decision<v, E, Value>):
  match options result:
    case _ Done{value}: IO.pure(Decision<v, E, Value>, Finished{Done{value}})
    case ProviderRetryOptions{_, _, signal} Fail{failure}:
      do IO<Decision<v, E, Value>>:
        aborted : Bool <- signalAborted(Reason, signal)
        failed(v, Reason, E, Value, effects, options, index, failure, aborted, exhausted)

def resume(v, -E: Data, -Value: Kind(v), decision: Decision<v, E, Value>, next: Unit -> IO(Result<&2, v, RetryFailure<E>, Value>)) -> IO(Result<&2, v, RetryFailure<E>, Value>):
  match decision:
    case Finished{result}: IO.pure(Result<&2, v, RetryFailure<E>, Value>, result)
    case Retry{}: next(Unit{})

def exhaustedResult(v, -E: Data, -Value: Kind(v), decision: Decision<v, E, Value>) -> IO(Result<&2, v, RetryFailure<E>, Value>):
  resume(v, E, Value, decision, unused => IO.die(Result<&2, v, RetryFailure<E>, Value>, 1, "exhausted retry loop continued"))

# The decreasing retry count bounds the loop; requests always run at least once,
# even with an already-aborted signal. Successful requests are returned directly.
def loop(v, -Reason: Data, -E: Data, -Value: Kind(v), +request: C.Callback<Unit, Result<&2, v, RequestFailure<E>, Value>>, +effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>, remaining: Nat, +index: Nat) -> IO(Result<&2, v, RetryFailure<E>, Value>):
  match remaining:
    case Zero{}:
      do IO<Result<&2, v, RetryFailure<E>, Value>>:
        result : Result<&2, v, RequestFailure<E>, Value> <- C.call(Unit, Result<&2, v, RequestFailure<E>, Value>, request, Unit{})
        decision : Decision<v, E, Value> <- received(v, Reason, E, Value, effects, options, index, True{}, result)
        exhaustedResult(v, E, Value, decision)
    case Succ{rest}:
      do IO<Result<&2, v, RetryFailure<E>, Value>>:
        result : Result<&2, v, RequestFailure<E>, Value> <- C.call(Unit, Result<&2, v, RequestFailure<E>, Value>, request, Unit{})
        decision : Decision<v, E, Value> <- received(v, Reason, E, Value, effects, options, index, False{}, result)
        resume(v, E, Value, decision, unused => loop(v, Reason, E, Value, request, effects, options, rest, Succ{index}))

def retryCount(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 0n
    case Some{count}: count

def retryProviderRequestWith(v, -Reason: Data, -E: Data, -Value: Kind(v), request: C.Callback<Unit, Result<&2, v, RequestFailure<E>, Value>>, effects: Effects<Reason>, +options: ProviderRetryOptions<Reason>) -> IO(Result<&2, v, RetryFailure<E>, Value>):
  match options:
    case ProviderRetryOptions{maximum, _, _}: loop(v, Reason, E, Value, request, effects, options, retryCount(maximum), 0n)

# Both entry points share one loop; the second transfers an affine success
# owner exactly once while failures stay copyable descriptions.
def retryProviderRequest(-Reason: Data, -E: Data, -Value: Data, request: C.Callback<Unit, Result<&2, &2, RequestFailure<E>, Value>>, effects: Effects<Reason>, options: ProviderRetryOptions<Reason>) -> IO(Result<&2, &2, RetryFailure<E>, Value>):
  retryProviderRequestWith(&2, Reason, E, Value, request, effects, options)

def retryProviderRequestOwned(-Reason: Data, -E: Data, -Value: Type, request: C.Callback<Unit, Result<&2, &1, RequestFailure<E>, Value>>, effects: Effects<Reason>, options: ProviderRetryOptions<Reason>) -> IO(Result<&2, &1, RetryFailure<E>, Value>):
  retryProviderRequestWith(&1, Reason, E, Value, request, effects, options)

# Rendering
# ---------

type RenderedError is Data:
  RenderedError{name: String, message: String}

type FormattingError is Data:
  NumberFormattingFailure{}

def createAbortError() -> RenderedError:
  RenderedError{"AbortError", "Request aborted"}

def message(delay: Maybe<&2, String>, maximum: Maybe<&2, String>, providerMessage: String) -> Result<&2, &2, FormattingError, RenderedError>:
  match delay maximum:
    case Some{seconds} Some{limit}: Done{RenderedError{"Error", "Server requested " ++ seconds ++ "s retry delay (max: " ++ limit ++ "s). " ++ providerMessage}}
    case _ _: Fail{NumberFormattingFailure{}}

def delayError(error: DelayError, providerMessage: String) -> Result<&2, &2, FormattingError, RenderedError>:
  match error:
    case ServerDelayTooLong{excess, maximum}:
      message(Decimal.toDecimal(Round.ceil(F.divide(excess, F.fromU32(1000)))), Decimal.toDecimal(Round.ceil(F.divide(maximum, F.fromU32(1000)))), providerMessage)

def original(-E: Data, error: RequestFailure<E>) -> E:
  match error:
    case Other{value}: value
    case Provider{ProviderError{value, _, _, _, _, _}}: value

# Original request errors keep the provider's own rendering; only errors
# introduced by the retry helper acquire the names and messages defined here.
def render(-E: Data, error: RetryFailure<E>, renderOriginal: E -> RenderedError) -> Result<&2, &2, FormattingError, RenderedError>:
  match error:
    case RequestFailed{failure}: Done{renderOriginal(original(E, failure))}
    case SleepRejected{_}: Done{RenderedError{"InvalidRetryDelay", "Retry delay is outside the native timer range"}}
    case RequestAborted{}: Done{createAbortError()}
    case DelayRejected{failure, providerMessage}: delayError(failure, providerMessage)

# Native effects
# --------------

# Sleep through the runtime timer, cancellable by the request signal.
def slept(-Reason: Data, result: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> Result<&2, &2, SleepError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{_}: Fail{SleepAborted{}}

def closeBare(result: Timer & Bool) -> IO(Result<&2, &2, SleepError, Unit>):
  match result:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, SleepError, Unit>>:
        Timer.close(owner)
        return Done{Unit{}}

def waitBare(pair: Timer & TimerCancel) -> IO(Result<&2, &2, SleepError, Unit>):
  match pair:
    case Tuple{owner, _}:
      do IO<Result<&2, &2, SleepError, Unit>>:
        result : Timer & Bool <- Timer.wait(owner)
        closeBare(result)

def valid(-Reason: Data, milliseconds: U32, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Result<&2, &2, SleepError, Unit>):
  match signal:
    case None{}:
      do IO<Result<&2, &2, SleepError, Unit>>:
        timer : Timer & TimerCancel <- Timer.new(milliseconds)
        waitBare(timer)
    case Some{signal}:
      do IO<Result<&2, &2, SleepError, Unit>>:
        result : Result<&2, &2, A.AbortReason<Reason>, Unit> <- S.sleep(Reason, milliseconds, signal)
        return slept(Reason, result)

def converted(-Reason: Data, result: Result<&2, &2, Delay.Error, U32>, signal: Maybe<&2, A.AbortSignal<Reason>>) -> IO(Result<&2, &2, SleepError, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, SleepError, Unit>, Fail{InvalidSleepDuration{error}})
    case Done{milliseconds}: valid(Reason, milliseconds, signal)

def sleep(-Reason: Data, input: SleepInput<Reason>) -> IO(Result<&2, &2, SleepError, Unit>):
  match input:
    case SleepInput{milliseconds, signal}: converted(Reason, Delay.milliseconds(milliseconds), signal)

# Retry-After dates: the provider's numeric API uses NaN for an unusable hint.
def unix(result: Result<&2, &2, HTTP.UnixError, W.U64>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{milliseconds}: Date.fromMilliseconds(milliseconds)

def interpreted(result: Result<&2, &2, HTTP.Error, HTTP.Instant>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{instant}: unix(HTTP.unixMilliseconds(instant))

def reference(text: String, result: Result<&2, &2, Inverse.Error, Calendar.CivilTime>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{current}: interpreted(HTTP.parseAt(current, text))

def parseDateAt(epoch: W.U64, text: String) -> F.F64:
  reference(text, Inverse.fromEpochMilliseconds(epoch))

def dateBody(environment: Unit, text: String) -> IO(F.F64):
  do IO<F.F64>:
    epoch : U32 & U32 <- IO.unixMilliseconds()
    return parseDateAt(Date.words(epoch), text)

# The caller owns this callback and retires it after all retry users.
def dateParser() -> IO(C.Callback<String, F.F64>):
  C.create(~Unit, ~String, ~F.F64, ~dateBody, Unit{})

# The jitter callback borrows its generator; dispose the callback first.
def draw(generator: Random.Generator, unused: Unit) -> IO(F.F64):
  Random.random(generator)

def randomCallback(generator: Random.Generator) -> IO(C.Callback<Unit, F.F64>):
  C.create(~Random.Generator, ~Unit, ~F.F64, ~draw, generator)

def nowBody(environment: Unit, unused: Unit) -> IO(F.F64): Date.now()

def sleepBody(~Reason: Data, environment: Unit, input: SleepInput<Reason>) -> IO(Result<&2, &2, SleepError, Unit>):
  sleep(Reason, input)

# One affine lifetime for the callbacks and their generator. The date parser
# is borrowed from the caller and remains valid after this owner is retired.
type Runtime<-Reason: Data> is Type:
  Runtime{effects: Effects<Reason>, generator: Random.Generator}

# Takes ownership of the supplied generator; deterministic tests use this
# without replacing the production callback assembly.
def fromGenerator(~Reason: Data, parseDate: C.Callback<String, F.F64>, +generator: Random.Generator) -> IO(Runtime<Reason>):
  do IO<Runtime<Reason>>:
    random : C.Callback<Unit, F.F64> <- randomCallback(generator)
    now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~nowBody, Unit{})
    sleeper : C.Callback<SleepInput<Reason>, Result<&2, &2, SleepError, Unit>> <- C.create(~Unit, ~SleepInput<Reason>, ~Result<&2, &2, SleepError, Unit>, ~(sleepBody(~Reason)), Unit{})
    return Runtime{Effects{random, parseDate, now, sleeper}, generator}

def initialized(~Reason: Data, parseDate: C.Callback<String, F.F64>, result: Result<&2, &2, Seed.SeedError, Random.Generator>) -> IO(Result<&2, &1, Seed.SeedError, Runtime<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Seed.SeedError, Runtime<Reason>>, Fail{error})
    case Done{generator}:
      do IO<Result<&2, &1, Seed.SeedError, Runtime<Reason>>>:
        runtime : Runtime<Reason> <- fromGenerator(~Reason, parseDate, generator)
        return Done{runtime}

def new(~Reason: Data, parseDate: C.Callback<String, F.F64>) -> IO(Result<&2, &1, Seed.SeedError, Runtime<Reason>>):
  do IO<Result<&2, &1, Seed.SeedError, Runtime<Reason>>>:
    result : Result<&2, &2, Seed.SeedError, Random.Generator> <- Seed.new()
    initialized(~Reason, parseDate, result)

# Borrowed effects may be shared across requests. Join all requests before
# disposing the owner; borrowed handles are not tracked by the type system.
def borrow(-Reason: Data, runtime: Runtime<Reason>) -> Runtime<Reason> & Effects<Reason>:
  match runtime:
    case Runtime{+effects, generator}: (Runtime{effects, generator}, effects)

def dispose(-Reason: Data, runtime: Runtime<Reason>) -> IO(Unit):
  match runtime:
    case Runtime{Effects{random, _, now, sleeper}, generator}:
      do IO<Unit>:
        C.dispose(Unit, F.F64, random)
        C.dispose(Unit, F.F64, now)
        C.dispose(SleepInput<Reason>, Result<&2, &2, SleepError, Unit>, sleeper)
        Random.dispose(generator)
