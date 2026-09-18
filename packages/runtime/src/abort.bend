import Base
import ./deferred.bend as D
import ./ref.bend as R

# Core abort state only. EventTarget dispatch, dependent signals, timeouts and
# listener cleanup are still required before this is the full AbortSignal API.
type AbortError is Data:
  AbortError{name: String, message: String, code: U32}

type AbortReason<-Reason: Data> is Data:
  Supplied{value: Reason}
  DefaultAbort{error: R.Ref<AbortError>}

type AbortSignal<-Reason: Data> is Data:
  AbortSignal{settlement: D.Deferred<AbortReason<Reason>>}

type AbortController<-Reason: Data> is Data:
  AbortController{signal: AbortSignal<Reason>}

def new(-Reason: Data) -> IO(AbortController<Reason>):
  do IO<AbortController<Reason>>:
    settlement : D.Deferred<AbortReason<Reason>> <- D.new(AbortReason<Reason>)
    return AbortController{AbortSignal{settlement}}

def signal(-Reason: Data, controller: AbortController<Reason>) -> AbortSignal<Reason>:
  match controller:
    case AbortController{value}: value

def reason(-Reason: Data, value: AbortSignal<Reason>) -> IO(Maybe<&2, AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement}: D.peek(AbortReason<Reason>, settlement)

def isAborted(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def aborted(-Reason: Data, value: AbortSignal<Reason>) -> IO(Bool):
  do IO<Bool>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, value)
    return isAborted(Reason, current)

def checked(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> Result<&2, &2, AbortReason<Reason>, Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{why}: Fail{why}

def throwIfAborted(-Reason: Data, value: AbortSignal<Reason>) -> IO(Result<&2, &2, AbortReason<Reason>, Unit>):
  do IO<Result<&2, &2, AbortReason<Reason>, Unit>>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, value)
    return checked(Reason, current)

def retainDefault(error: R.Ref<AbortError>, won: Bool) -> IO(Unit):
  match won:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        previous : AbortError <- R.dispose(AbortError, error)
        return Unit{}

def settle(-Reason: Data, +settlement: D.Deferred<AbortReason<Reason>>, why: Maybe<&2, Reason>) -> IO(Unit):
  match why:
    case Some{value}:
      do IO<Unit>:
        won : Bool <- D.resolve(AbortReason<Reason>, settlement, Supplied{value})
        return Unit{}
    case None{}:
      do IO<Unit>:
        +error : R.Ref<AbortError> <- R.new(AbortError, AbortError{"AbortError", "This operation was aborted", 20})
        won : Bool <- D.resolve(AbortReason<Reason>, settlement, DefaultAbort{error})
        retainDefault(error, won)

def abortPending(-Reason: Data, settlement: D.Deferred<AbortReason<Reason>>, why: Maybe<&2, Reason>, current: Maybe<&2, AbortReason<Reason>>) -> IO(Unit):
  match current:
    case Some{_}: IO.pure(Unit, Unit{})
    case None{}: settle(Reason, settlement, why)

# None represents omitted/undefined. Null, false and zero can be supplied values
# of Reason and are not tested for truthiness. First settlement wins atomically.
def abort(-Reason: Data, controller: AbortController<Reason>, why: Maybe<&2, Reason>) -> IO(Unit):
  match controller:
    case AbortController{AbortSignal{+settlement}}:
      do IO<Unit>:
        current : Maybe<&2, AbortReason<Reason>> <- D.peek(AbortReason<Reason>, settlement)
        abortPending(Reason, settlement, why, current)

# Native removable observation, not an EventTarget listener. Registration is
# acknowledged before return; late observers receive the existing reason.
# Consume the ticket even when cancelled. Cancelling does not abort the signal.
def observe(-Reason: Data, value: AbortSignal<Reason>) -> IO(D.Observation<AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement}: D.observe(AbortReason<Reason>, settlement)

def releaseReason(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> IO(Unit):
  match value:
    case Some{DefaultAbort{error}}:
      do IO<Unit>:
        previous : AbortError <- R.dispose(AbortError, error)
        return Unit{}
    case _: IO.pure(Unit, Unit{})

# Owner-only disposal after all aliases/tickets retire. Supplied reason objects
# remain caller-owned. A never-aborted signal may be retired with no observers.
def dispose(-Reason: Data, controller: AbortController<Reason>) -> IO(Unit):
  match controller:
    case AbortController{AbortSignal{+settlement}}:
      do IO<Unit>:
        current : Maybe<&2, AbortReason<Reason>> <- D.peek(AbortReason<Reason>, settlement)
        releaseReason(Reason, current)
        D.dispose(AbortReason<Reason>, settlement)
