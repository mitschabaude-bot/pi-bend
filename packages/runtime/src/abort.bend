import Base
import ./deferred.bend as D
import ./ref.bend as R
import ./event-target.bend as T
import ./event.bend as E
import ./listener-registry.bend as L
import ./clock.bend as Clock
import ./f64.bend as F

# Abort state and typed function-listener dispatch. Dependent signals, timeout,
# onabort, full DOMException and managed ownership remain pending.
type AbortError is Data:
  AbortError{name: String, message: String, code: U32}

type AbortReason<-Reason: Data> is Data:
  Supplied{value: Reason}
  DefaultAbort{error: R.Ref<AbortError>}

type AbortSignal<-Reason: Data, -Error: Data> is Data:
  AbortSignal{settlement: D.Deferred<AbortReason<Reason>>, dispatcher: T.Dispatcher<AbortSignal<Reason, Error>, Error>, clock: Clock.Clock, fired: R.Ref<Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>>}

type AbortController<-Reason: Data, -Error: Data> is Data:
  AbortController{signal: AbortSignal<Reason, Error>}

def new(-Reason: Data, -Error: Data, clock: Clock.Clock, reports: T.ReportQueue<Error>) -> IO(AbortController<Reason, Error>):
  do IO<AbortController<Reason, Error>>:
    settlement : D.Deferred<AbortReason<Reason>> <- D.new(AbortReason<Reason>)
    dispatcher : T.Dispatcher<AbortSignal<Reason, Error>, Error> <- T.newDispatcher(AbortSignal<Reason, Error>, Error, reports)
    fired : R.Ref<Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>> <- R.new(Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>, None{})
    return AbortController{AbortSignal{settlement, dispatcher, clock, fired}}

def signal(-Reason: Data, -Error: Data, controller: AbortController<Reason, Error>) -> AbortSignal<Reason, Error>:
  match controller:
    case AbortController{value}: value

def reason(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>) -> IO(Maybe<&2, AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement, _, _, _}: D.peek(AbortReason<Reason>, settlement)

def isAborted(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def aborted(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>) -> IO(Bool):
  do IO<Bool>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, Error, value)
    return isAborted(Reason, current)

def checked(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> Result<&2, &2, AbortReason<Reason>, Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{why}: Fail{why}

def throwIfAborted(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>) -> IO(Result<&2, &2, AbortReason<Reason>, Unit>):
  do IO<Result<&2, &2, AbortReason<Reason>, Unit>>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, Error, value)
    return checked(Reason, current)

def retainDefault(error: R.Ref<AbortError>, won: Bool) -> IO(Unit):
  match won:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        previous : AbortError <- R.dispose(AbortError, error)
        return Unit{}

# The controller owns its one abort event until disposal, allowing listeners to
# retain it after dispatch. State is settled before any listener runs. Only the
# atomic winner creates and dispatches the trusted event.
def runAbort(-Reason: Data, -Error: Data, +value: AbortSignal<Reason, Error>, won: Bool) -> IO(Unit):
  match value won:
    case _ False{}: IO.pure(Unit, Unit{})
    case AbortSignal{+settlement, +dispatcher, +clock, +fired} True{}:
      do IO<Unit>:
        stamp : F.F64 <- Clock.now(clock)
        +event : E.WebEvent<AbortSignal<Reason, Error>> <- E.createAt(AbortSignal<Reason, Error>, "abort", E.defaultInit(), stamp, True{})
        R.write(Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>, fired, Some{event})
        result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEventDispatcher(AbortSignal<Reason, Error>, Error, dispatcher, AbortSignal{settlement, dispatcher, clock, fired}, event)
        return Unit{}

def settle(-Reason: Data, -Error: Data, +value: AbortSignal<Reason, Error>, why: Maybe<&2, Reason>) -> IO(Unit):
  match value why:
    case AbortSignal{+settlement, dispatcher, clock, fired} Some{supplied}:
      do IO<Unit>:
        won : Bool <- D.resolve(AbortReason<Reason>, settlement, Supplied{supplied})
        runAbort(Reason, Error, AbortSignal{settlement, dispatcher, clock, fired}, won)
    case AbortSignal{+settlement, dispatcher, clock, fired} None{}:
      do IO<Unit>:
        +error : R.Ref<AbortError> <- R.new(AbortError, AbortError{"AbortError", "This operation was aborted", 20})
        +won : Bool <- D.resolve(AbortReason<Reason>, settlement, DefaultAbort{error})
        retainDefault(error, won)
        runAbort(Reason, Error, AbortSignal{settlement, dispatcher, clock, fired}, won)

def abortPending(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>, why: Maybe<&2, Reason>, current: Maybe<&2, AbortReason<Reason>>) -> IO(Unit):
  match current:
    case Some{_}: IO.pure(Unit, Unit{})
    case None{}: settle(Reason, Error, value, why)

# None represents omitted/undefined. Null, false and zero can be supplied values
# of Reason and are not tested for truthiness. First settlement wins atomically.
def abort(-Reason: Data, -Error: Data, controller: AbortController<Reason, Error>, why: Maybe<&2, Reason>) -> IO(Unit):
  match controller:
    case AbortController{+value}:
      do IO<Unit>:
        current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, Error, value)
        abortPending(Reason, Error, value, why, current)

def same(-Reason: Data, -Error: Data, left: AbortSignal<Reason, Error>, right: AbortSignal<Reason, Error>) -> Bool:
  match left right:
    case AbortSignal{_, a, _, _} AbortSignal{_, b, _, _}: T.sameDispatcher(AbortSignal<Reason, Error>, Error, a, b)

def addEventListener(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>, eventType: String, listener: Maybe<&2, T.HostListener(AbortSignal<Reason, Error>, Error)>, options: L.Options) -> IO(Unit):
  match value:
    case AbortSignal{_, dispatcher, _, _}: T.addEventListenerDispatcher(AbortSignal<Reason, Error>, Error, dispatcher, eventType, listener, options)

def removeEventListener(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>, eventType: String, listener: Maybe<&2, T.HostListener(AbortSignal<Reason, Error>, Error)>, capture: Bool) -> IO(Unit):
  match value:
    case AbortSignal{_, dispatcher, _, _}: T.removeEventListenerDispatcher(AbortSignal<Reason, Error>, Error, dispatcher, eventType, listener, capture)

# Explicit dispatch is inherited behavior: dispatching an event named abort does
# not itself abort the signal or change its reason.
def dispatchEvent(-Reason: Data, -Error: Data, +value: AbortSignal<Reason, Error>, event: E.WebEvent<AbortSignal<Reason, Error>>) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  match value:
    case AbortSignal{+settlement, +dispatcher, +clock, +fired}: T.dispatchEventDispatcher(AbortSignal<Reason, Error>, Error, dispatcher, AbortSignal{settlement, dispatcher, clock, fired}, event)

# Native removable observation, not an EventTarget listener. Registration is
# acknowledged before return; late observers receive the existing reason.
# Consume the ticket even when cancelled. Cancelling does not abort the signal.
def observe(-Reason: Data, -Error: Data, value: AbortSignal<Reason, Error>) -> IO(D.Observation<AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement, _, _, _}: D.observe(AbortReason<Reason>, settlement)

def releaseReason(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> IO(Unit):
  match value:
    case Some{DefaultAbort{error}}:
      do IO<Unit>:
        previous : AbortError <- R.dispose(AbortError, error)
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def releaseEvent(-Reason: Data, -Error: Data, value: Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{event}: E.dispose(AbortSignal<Reason, Error>, event)

# Owner-only disposal after all aliases, callbacks, retained event references,
# dispatches and observation tickets retire. Supplied reasons are caller-owned.
def dispose(-Reason: Data, -Error: Data, controller: AbortController<Reason, Error>) -> IO(Unit):
  match controller:
    case AbortController{AbortSignal{+settlement, dispatcher, _, fired}}:
      do IO<Unit>:
        current : Maybe<&2, AbortReason<Reason>> <- D.peek(AbortReason<Reason>, settlement)
        event : Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>> <- R.dispose(Maybe<&2, E.WebEvent<AbortSignal<Reason, Error>>>, fired)
        releaseEvent(Reason, Error, event)
        T.disposeDispatcher(AbortSignal<Reason, Error>, Error, dispatcher)
        releaseReason(Reason, current)
        D.dispose(AbortReason<Reason>, settlement)
