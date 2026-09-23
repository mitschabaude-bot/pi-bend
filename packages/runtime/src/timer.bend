import Base
import ./abort.bend as A
import ./deferred.bend as D
import ./f64.bend as F
import ./u64.bend as W


# Native timers use literal U32 milliseconds. Reject unrepresentable durations
# instead of rounding, wrapping or turning overflow into a one-millisecond wait.
type MillisecondsError is Data:
  Unrepresentable{value: F64}

def low(value: W.U64) -> U32:
  match value:
    case W.U64{_, word}: word

def candidate(value: F.Decoded) -> U32:
  match value:
    case F.Finite{_, exponent, significand}:
      low(W.shiftRight(significand, U32.to_nat(U32.min((1075 - exponent : U32), 64))))
    case _: 0

def checkedMilliseconds(value: F64, exactMilliseconds: U32, comparison: Maybe<&2, Cmp>) -> Result<&2, &2, MillisecondsError, U32>:
  match comparison:
    case Some{EQ{}}: Done{exactMilliseconds}
    case _: Fail{Unrepresentable{value}}

# Re-encoding the candidate establishes exactness, including signed-zero
# equality. This also rejects negative, fractional and non-finite inputs.
def exactMilliseconds(+value: F64) -> Result<&2, &2, MillisecondsError, U32>:
  +word = candidate(F.decode(value))
  checkedMilliseconds(value, word, F.compare(value, F.fromU32(word)))


# Backoff may be fractional. Quantize downward only when the input is finite,
# nonnegative and below 2^32; invalid values retain their original bits.
type Error is Data:
  InvalidDuration{value: F64}

def checked(value: F64, word: U32, lower: Maybe<&2, Cmp>, upper: Maybe<&2, Cmp>) -> Result<&2, &2, Error, U32>:
  match lower upper:
    case Some{EQ{}} Some{LT{}}: Done{word}
    case Some{GT{}} Some{LT{}}: Done{word}
    case _ _: Fail{InvalidDuration{value}}

def milliseconds(+value: F64) -> Result<&2, &2, Error, U32>:
  checked(value, candidate(F.decode(value)), F.compare(value, F.fromU32(0)), F.compare(value, F.multiply(F.fromU32(65536), F.fromU32(65536))))

# Abortable sleeps over the owned Timer primitive. The signal remains caller-owned.
# Each call retires its timer, observation and watcher before returning.
def cancelForReasonSleep(-Reason: Data, handle: TimerCancel, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Maybe<&2, A.AbortReason<Reason>>):
  match reason:
    case None{}: IO.pure(Maybe<&2, A.AbortReason<Reason>>, None{})
    case Some{value}:
      do IO<Maybe<&2, A.AbortReason<Reason>>>:
        won : Bool <- Timer.cancel(handle)
        return Bool.pick(Maybe<&2, A.AbortReason<Reason>>, won, Some{value}, None{})

def watchSleep(-Reason: Data, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>, handle: TimerCancel) -> IO(Maybe<&2, A.AbortReason<Reason>>):
  do IO<Maybe<&2, A.AbortReason<Reason>>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelForReasonSleep(Reason, handle, reason)

def settledSleep(-Reason: Data, elapsed: Bool, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match elapsed:
    case True{}: IO.pure(Result<&2, &2, A.AbortReason<Reason>, Unit>, Done{Unit{}})
    case False{}:
      match reason:
        case Some{why}: IO.pure(Result<&2, &2, A.AbortReason<Reason>, Unit>, Fail{why})
        case None{}: IO.die(Result<&2, &2, A.AbortReason<Reason>, Unit>, 1, "cancelled sleep lost its abort reason")

def finishSleep(-Reason: Data, result: Timer & Bool, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Maybe<&2, A.AbortReason<Reason>>)) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match result:
    case Tuple{owner, elapsed}:
      do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        reason : Maybe<&2, A.AbortReason<Reason>> <- IO.join(Maybe<&2, A.AbortReason<Reason>>, watcher)
        Timer.close(owner)
        settledSleep(Reason, elapsed, reason)

def waitObserved(-Reason: Data, pair: Timer & TimerCancel, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match pair:
    case Tuple{owner, handle}:
      match observation:
        case D.Observation{ticket, cancellation}:
          do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
            watcher : Chan(Maybe<&2, A.AbortReason<Reason>>) <- IO.fork(Maybe<&2, A.AbortReason<Reason>>, watchSleep(Reason, ticket, handle))
            result : Timer & Bool <- Timer.wait(owner)
            finishSleep(Reason, result, cancellation, watcher)

def start(-Reason: Data, milliseconds: U32, signal: A.AbortSignal<Reason>, precheck: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match precheck:
    case Fail{why}: IO.pure(Result<&2, &2, A.AbortReason<Reason>, Unit>, Fail{why})
    case Done{_}:
      do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        pair : Timer & TimerCancel <- Timer.new(milliseconds)
        waitObserved(Reason, pair, observation)

# A pre-aborted signal fails immediately. Otherwise timer commitment competes
# with the registered abort watcher. Milliseconds are literal, including zero;
# event-loop delay normalization belongs in the provider's backoff adapter.
def sleep(-Reason: Data, milliseconds: U32, +signal: A.AbortSignal<Reason>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
    precheck : Result<&2, &2, A.AbortReason<Reason>, Unit> <- A.throwIfAborted(Reason, signal)
    start(Reason, milliseconds, signal, precheck)
