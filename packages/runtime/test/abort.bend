import Base
import ../src/abort.bend as A
import ../src/deferred.bend as D

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def zero(value: Maybe<&2, A.AbortReason<U32>>) -> Bool:
  match value:
    case Some{A.Supplied{n}}: U32.is_eq(n, 0)
    case _: False{}

def observeZero(observation: D.Observation<A.AbortReason<U32>>, +controller: A.AbortController<U32>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, _}:
      do IO<Unit>:
        won : Bool <- A.abort(U32, controller, Some{0})
        assertion(won, "first cancellation must settle")
        lost : Bool <- A.abort(U32, controller, Some{7})
        assertion(Bool.not(lost), "repeated cancellation must not replace the reason")
        value : Maybe<&2, A.AbortReason<U32>> <- D.wait(Maybe<&2, A.AbortReason<U32>>, ticket)
        assertion(zero(value), "pending observer must receive even a zero reason")

def lateZero(observation: D.Observation<A.AbortReason<U32>>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, _}:
      do IO<Unit>:
        value : Maybe<&2, A.AbortReason<U32>> <- D.wait(Maybe<&2, A.AbortReason<U32>>, ticket)
        assertion(zero(value), "late observer must receive retained reason")

def cancelObservation(observation: D.Observation<A.AbortReason<U32>>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, cancel}:
      do IO<Unit>:
        removed : Bool <- D.cancel(A.AbortReason<U32>, cancel)
        assertion(removed, "unsubscribe must unlink pending observation")
        value : Maybe<&2, A.AbortReason<U32>> <- D.wait(Maybe<&2, A.AbortReason<U32>>, ticket)
        assertion(Maybe.is_none(&2, A.AbortReason<U32>, value), "unsubscribed observation must finish without a reason")

def main() -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<U32> <- A.new(U32)
    +signal : A.AbortSignal<U32> = A.signal(U32, controller)
    initial : Bool <- A.aborted(U32, signal)
    assertion(Bool.not(initial), "new signal must be pending")
    cancelled : D.Observation<A.AbortReason<U32>> <- A.observe(U32, signal)
    cancelObservation(cancelled)
    pending : Bool <- A.aborted(U32, signal)
    assertion(Bool.not(pending), "unsubscribing must not cancel the signal")
    observer : D.Observation<A.AbortReason<U32>> <- A.observe(U32, signal)
    observeZero(observer, controller)
    late : D.Observation<A.AbortReason<U32>> <- A.observe(U32, signal)
    lateZero(late)
    final : Bool <- A.aborted(U32, signal)
    assertion(final, "settled signal must report cancellation")
    A.dispose(U32, controller)
    IO.print("PASS native cancellation first settlement, reason retention and removable observations")
