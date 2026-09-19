import Base
import ./abort.bend as A
import ./deferred.bend as D

# This module needs the owned Timer primitive. The signal remains caller-owned.
# Each call retires its timer, observation and watcher before returning.
def cancelForReason(-Reason: Data, handle: TimerCancel, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Maybe<&2, A.AbortReason<Reason>>):
  match reason:
    case None{}: IO.pure(Maybe<&2, A.AbortReason<Reason>>, None{})
    case Some{value}:
      do IO<Maybe<&2, A.AbortReason<Reason>>>:
        won : Bool <- Timer.cancel(handle)
        return Bool.pick(Maybe<&2, A.AbortReason<Reason>>, won, Some{value}, None{})

def watch(-Reason: Data, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>, handle: TimerCancel) -> IO(Maybe<&2, A.AbortReason<Reason>>):
  do IO<Maybe<&2, A.AbortReason<Reason>>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelForReason(Reason, handle, reason)

def settled(-Reason: Data, elapsed: Bool, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match elapsed:
    case True{}: IO.pure(Result<&2, &2, A.AbortReason<Reason>, Unit>, Done{Unit{}})
    case False{}:
      match reason:
        case Some{why}: IO.pure(Result<&2, &2, A.AbortReason<Reason>, Unit>, Fail{why})
        case None{}: IO.die(Result<&2, &2, A.AbortReason<Reason>, Unit>, 1, "cancelled sleep lost its abort reason")

def finish(-Reason: Data, result: Timer & Bool, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Maybe<&2, A.AbortReason<Reason>>)) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match result:
    case Tuple{owner, elapsed}:
      do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        reason : Maybe<&2, A.AbortReason<Reason>> <- IO.join(Maybe<&2, A.AbortReason<Reason>>, watcher)
        Timer.close(owner)
        settled(Reason, elapsed, reason)

def waitObserved(-Reason: Data, pair: Timer & TimerCancel, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match pair:
    case Tuple{owner, handle}:
      match observation:
        case D.Observation{ticket, cancellation}:
          do IO<Result<&2, &2, A.AbortReason<Reason>, Unit>>:
            watcher : Chan(Maybe<&2, A.AbortReason<Reason>>) <- IO.fork(Maybe<&2, A.AbortReason<Reason>>, watch(Reason, ticket, handle))
            result : Timer & Bool <- Timer.wait(owner)
            finish(Reason, result, cancellation, watcher)

def start(-Reason: Data, milliseconds: U32, signal: A.AbortSignal<Reason>, checked: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> IO(Result<&2, &2, A.AbortReason<Reason>, Unit>):
  match checked:
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
    checked : Result<&2, &2, A.AbortReason<Reason>, Unit> <- A.throwIfAborted(Reason, signal)
    start(Reason, milliseconds, signal, checked)
