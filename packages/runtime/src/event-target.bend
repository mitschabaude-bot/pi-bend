import Base
import ./event.bend as E
import ./listener-registry.bend as L
import ./callback.bend as C
import ./ref.bend as R
import ./fifo.bend as Q

# Runtime-owned reporting queue, shared by targets. Dispatch enqueues listener
# failures; the runtime's next-tick/error-reporting integration is still pending.
type ReportQueue<-Error: Data> is Data:
  ReportQueue{pending: R.Ref<Q.Queue<Error>>}

type EventTarget<-Error: Data> is Data:
  EventTarget{listeners: L.Registry<(EventTarget<Error> & E.WebEvent<EventTarget<Error>>), Result<&2, &2, Error, Unit>>, reports: ReportQueue<Error>}

def EventListener(-Error: Data) -> Data:
  C.Callback<(EventTarget<Error> & E.WebEvent<EventTarget<Error>>), Result<&2, &2, Error, Unit>>

def Input(-Error: Data) -> Type: EventTarget<Error> & E.WebEvent<EventTarget<Error>>
def Output(-Error: Data) -> Data: Result<&2, &2, Error, Unit>
def EventValue(-Error: Data) -> Data: E.WebEvent<EventTarget<Error>>

def newReportQueue(-Error: Data) -> IO(ReportQueue<Error>):
  do IO<ReportQueue<Error>>:
    pending : R.Ref<Q.Queue<Error>> <- R.new(Q.Queue<Error>, Q.new(Error))
    return ReportQueue{pending}

def enqueueError(-Error: Data, queue: ReportQueue<Error>, error: Error) -> IO(Unit):
  match queue:
    case ReportQueue{pending}: R.modify(Q.Queue<Error>, Unit, pending, current => (Q.enqueue(Error, current, error), Unit{}))

# Runtime/test observation boundary, not synchronous user error delivery.
def takeReportedError(-Error: Data, queue: ReportQueue<Error>) -> IO(Maybe<&2, Error>):
  match queue:
    case ReportQueue{pending}: R.modify(Q.Queue<Error>, Maybe<&2, Error>, pending, current => Q.dequeue(Error, current))

# Owner boundary: retire all target aliases and consume pending reports first.
def disposeReportQueue(-Error: Data, queue: ReportQueue<Error>) -> IO(Unit):
  match queue:
    case ReportQueue{pending}:
      do IO<Unit>:
        remaining : Q.Queue<Error> <- R.dispose(Q.Queue<Error>, pending)
        return Unit{}

def new(-Error: Data, reports: ReportQueue<Error>) -> IO(EventTarget<Error>):
  do IO<EventTarget<Error>>:
    listeners : L.Registry<Input(Error), Output(Error)> <- L.new(Input(Error), Output(Error))
    return EventTarget{listeners, reports}

def same(-Error: Data, left: EventTarget<Error>, right: EventTarget<Error>) -> Bool:
  match left right:
    case EventTarget{L.Registry{a}, _} EventTarget{L.Registry{b}, _}: R.same(L.State<Input(Error), Output(Error)>, a, b)

# Options are already resolved capture/once/passive flags. Signal options,
# object listeners and returned-promise rejection observation remain pending.
# None omits registration; Node's add-listener warning and listener-count
# diagnostics still require the runtime warning-reporting path.
def addEventListener(-Error: Data, target: EventTarget<Error>, eventType: String, listener: Maybe<&2, EventListener(Error)>, options: L.Options) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case EventTarget{listeners, _} Some{callback}:
      do IO<Unit>:
        added : Bool <- L.add(Input(Error), Output(Error), listeners, eventType, callback, options)
        return Unit{}

def removeEventListener(-Error: Data, target: EventTarget<Error>, eventType: String, listener: Maybe<&2, EventListener(Error)>, capture: Bool) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case EventTarget{listeners, _} Some{callback}:
      do IO<Unit>:
        removed : Bool <- L.remove(Input(Error), Output(Error), listeners, eventType, callback, capture)
        return Unit{}

def returned(-Error: Data, event: EventValue(Error), reports: ReportQueue<Error>, result: Output(Error)) -> IO(Unit):
  match result:
    case Done{Unit{}}: E.listenerReturned(EventTarget<Error>, event)
    case Fail{error}: enqueueError(Error, reports, error)

def invoke(-Error: Data, +target: EventTarget<Error>, +event: EventValue(Error), listener: Maybe<&2, L.Registration<Input(Error), Output(Error)>>) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case EventTarget{+listeners, +reports} Some{L.Registration{_, _, callback, L.Options{_, _, passive}}}:
      do IO<Unit>:
        E.enterListener(EventTarget<Error>, event, passive)
        result : Output(Error) <- C.call(Input(Error), Output(Error), callback, (EventTarget{listeners, reports}, event))
        returned(Error, event, reports, result)
        E.leaveListener(EventTarget<Error>, event)

def decision(-Error: Data, stopped: Bool, registration: L.Registration<Input(Error), Output(Error)>) -> L.DispatchDecision:
  match stopped registration:
    case False{} _: L.CallListener{}
    case True{} L.Registration{_, _, _, L.Options{_, _, True{}}}: L.SkipListener{}
    case True{} _: L.StopDispatch{}

def step(-Error: Data, +event: EventValue(Error), cursor: L.Cursor<Input(Error), Output(Error)>) -> IO(L.Step<Input(Error), Output(Error)>):
  do IO<L.Step<Input(Error), Output(Error)>>:
    stopped : Bool <- E.immediatePropagationStopped(EventTarget<Error>, event)
    L.nextWith(Input(Error), Output(Error), cursor, registration => decision(Error, stopped, registration))

# Callbacks can add listeners, so dispatch has no finite structural bound. Each
# iteration performs IO, and every terminating path releases its affine cursor.
@unsafe def drain(-Error: Data, +target: EventTarget<Error>, +event: EventValue(Error), current: L.Step<Input(Error), Output(Error)>) -> IO(Bool):
  match current:
    case L.End{}:
      do IO<Bool>:
        E.finishDispatch(EventTarget<Error>, event)
        E.returnValue(EventTarget<Error>, event)
    case L.More{cursor, listener}:
      do IO<Bool>:
        invoke(Error, target, event, listener)
        next : L.Step<Input(Error), Output(Error)> <- step(Error, event, cursor)
        drain(Error, target, event, next)

def dispatchStarted(-Error: Data, +target: EventTarget<Error>, +event: EventValue(Error), started: Result<&2, &2, E.DispatchError, Unit>) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  match target started:
    case _ Fail{error}: IO.pure(Result<&2, &2, E.DispatchError, Bool>, Fail{error})
    case EventTarget{+listeners, reports} Done{Unit{}}:
      do IO<Result<&2, &2, E.DispatchError, Bool>>:
        eventType : String <- E.eventType(EventTarget<Error>, event)
        cursor : L.Cursor<Input(Error), Output(Error)> <- L.begin(Input(Error), Output(Error), listeners, eventType)
        first : L.Step<Input(Error), Output(Error)> <- step(Error, event, cursor)
        result : Bool <- drain(Error, EventTarget{listeners, reports}, event, first)
        return Done{result}

def dispatchEvent(-Error: Data, +target: EventTarget<Error>, +event: EventValue(Error)) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  do IO<Result<&2, &2, E.DispatchError, Bool>>:
    started : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(EventTarget<Error>, event, target)
    dispatchStarted(Error, target, event, started)

# Targets do not own their callbacks or shared reporting queue. All dispatches
# and event-held target aliases must retire before the owner disposes a target.
def dispose(-Error: Data, target: EventTarget<Error>) -> IO(Unit):
  match target:
    case EventTarget{listeners, _}: L.dispose(Input(Error), Output(Error), listeners)
