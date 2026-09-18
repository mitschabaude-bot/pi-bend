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

# Shared EventTarget machinery is parameterized by the actual receiver. Derived
# targets retain their own type and identity in callbacks and event.target.
type Dispatcher<-Host: Data, -Error: Data> is Data:
  Dispatcher{listeners: L.Registry<(Host & E.WebEvent<Host>), Result<&2, &2, Error, Unit>>, reports: ReportQueue<Error>}

type EventTarget<-Error: Data> is Data:
  EventTarget{dispatcher: Dispatcher<EventTarget<Error>, Error>}

def HostInput(-Host: Data) -> Type: Host & E.WebEvent<Host>
def HostListener(-Host: Data, -Error: Data) -> Data:
  C.Callback<HostInput(Host), Result<&2, &2, Error, Unit>>
def EventListener(-Error: Data) -> Data: HostListener(EventTarget<Error>, Error)
def Input(-Error: Data) -> Type: HostInput(EventTarget<Error>)
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

def newDispatcher(-Host: Data, -Error: Data, reports: ReportQueue<Error>) -> IO(Dispatcher<Host, Error>):
  do IO<Dispatcher<Host, Error>>:
    listeners : L.Registry<HostInput(Host), Output(Error)> <- L.new(HostInput(Host), Output(Error))
    return Dispatcher{listeners, reports}

def sameDispatcher(-Host: Data, -Error: Data, left: Dispatcher<Host, Error>, right: Dispatcher<Host, Error>) -> Bool:
  match left right:
    case Dispatcher{L.Registry{a}, _} Dispatcher{L.Registry{b}, _}: R.same(L.State<HostInput(Host), Output(Error)>, a, b)

# Options are already resolved capture/once/passive flags. Signal options,
# object listeners and returned-promise rejection observation remain pending.
# None omits registration; Node's add-listener warning and listener-count
# diagnostics still require the runtime warning-reporting path.
def addEventListenerDispatcher(-Host: Data, -Error: Data, target: Dispatcher<Host, Error>, eventType: String, listener: Maybe<&2, HostListener(Host, Error)>, options: L.Options) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case Dispatcher{listeners, _} Some{callback}:
      do IO<Unit>:
        added : Bool <- L.add(HostInput(Host), Output(Error), listeners, eventType, callback, options)
        return Unit{}

def removeEventListenerDispatcher(-Host: Data, -Error: Data, target: Dispatcher<Host, Error>, eventType: String, listener: Maybe<&2, HostListener(Host, Error)>, capture: Bool) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case Dispatcher{listeners, _} Some{callback}:
      do IO<Unit>:
        removed : Bool <- L.remove(HostInput(Host), Output(Error), listeners, eventType, callback, capture)
        return Unit{}

def returned(-Host: Data, -Error: Data, event: E.WebEvent<Host>, reports: ReportQueue<Error>, result: Output(Error)) -> IO(Unit):
  match result:
    case Done{Unit{}}: E.listenerReturned(Host, event)
    case Fail{error}: enqueueError(Error, reports, error)

def invoke(-Host: Data, -Error: Data, +target: Dispatcher<Host, Error>, +host: Host, +event: E.WebEvent<Host>, listener: Maybe<&2, L.Registration<HostInput(Host), Output(Error)>>) -> IO(Unit):
  match target listener:
    case _ None{}: IO.pure(Unit, Unit{})
    case Dispatcher{+listeners, +reports} Some{L.Registration{_, _, callback, L.Options{_, _, passive}}}:
      do IO<Unit>:
        E.enterListener(Host, event, passive)
        result : Output(Error) <- C.call(HostInput(Host), Output(Error), callback, (host, event))
        returned(Host, Error, event, reports, result)
        E.leaveListener(Host, event)

def decision(-Host: Data, -Error: Data, stopped: Bool, registration: L.Registration<HostInput(Host), Output(Error)>) -> L.DispatchDecision:
  match stopped registration:
    case False{} _: L.CallListener{}
    case True{} L.Registration{_, _, _, L.Options{_, _, True{}}}: L.SkipListener{}
    case True{} _: L.StopDispatch{}

def step(-Host: Data, -Error: Data, +event: E.WebEvent<Host>, cursor: L.Cursor<HostInput(Host), Output(Error)>) -> IO(L.Step<HostInput(Host), Output(Error)>):
  do IO<L.Step<HostInput(Host), Output(Error)>>:
    stopped : Bool <- E.immediatePropagationStopped(Host, event)
    L.nextWith(HostInput(Host), Output(Error), cursor, registration => decision(Host, Error, stopped, registration))

# Callbacks can add listeners, so dispatch has no finite structural bound. Each
# iteration performs IO, and every terminating path releases its affine cursor.
@unsafe def drain(-Host: Data, -Error: Data, +target: Dispatcher<Host, Error>, +host: Host, +event: E.WebEvent<Host>, current: L.Step<HostInput(Host), Output(Error)>) -> IO(Bool):
  match current:
    case L.End{}:
      do IO<Bool>:
        E.finishDispatch(Host, event)
        E.returnValue(Host, event)
    case L.More{cursor, listener}:
      do IO<Bool>:
        invoke(Host, Error, target, host, event, listener)
        next : L.Step<HostInput(Host), Output(Error)> <- step(Host, Error, event, cursor)
        drain(Host, Error, target, host, event, next)

def dispatchStarted(-Host: Data, -Error: Data, +target: Dispatcher<Host, Error>, +host: Host, +event: E.WebEvent<Host>, started: Result<&2, &2, E.DispatchError, Unit>) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  match target started:
    case _ Fail{error}: IO.pure(Result<&2, &2, E.DispatchError, Bool>, Fail{error})
    case Dispatcher{+listeners, reports} Done{Unit{}}:
      do IO<Result<&2, &2, E.DispatchError, Bool>>:
        eventType : String <- E.eventType(Host, event)
        cursor : L.Cursor<HostInput(Host), Output(Error)> <- L.begin(HostInput(Host), Output(Error), listeners, eventType)
        first : L.Step<HostInput(Host), Output(Error)> <- step(Host, Error, event, cursor)
        result : Bool <- drain(Host, Error, Dispatcher{listeners, reports}, host, event, first)
        return Done{result}

def dispatchEventDispatcher(-Host: Data, -Error: Data, +target: Dispatcher<Host, Error>, +host: Host, +event: E.WebEvent<Host>) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  do IO<Result<&2, &2, E.DispatchError, Bool>>:
    started : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(Host, event, host)
    dispatchStarted(Host, Error, target, host, event, started)

# Targets do not own their callbacks or shared reporting queue. All dispatches
# and event-held target aliases must retire before the owner disposes a target.
def disposeDispatcher(-Host: Data, -Error: Data, target: Dispatcher<Host, Error>) -> IO(Unit):
  match target:
    case Dispatcher{listeners, _}: L.dispose(HostInput(Host), Output(Error), listeners)

# Ordinary EventTarget public API. Derived targets use the same dispatcher with
# their own Host type; no wrapper is substituted for the callback receiver.
def new(-Error: Data, reports: ReportQueue<Error>) -> IO(EventTarget<Error>):
  do IO<EventTarget<Error>>:
    dispatcher : Dispatcher<EventTarget<Error>, Error> <- newDispatcher(EventTarget<Error>, Error, reports)
    return EventTarget{dispatcher}

def same(-Error: Data, left: EventTarget<Error>, right: EventTarget<Error>) -> Bool:
  match left right:
    case EventTarget{a} EventTarget{b}: sameDispatcher(EventTarget<Error>, Error, a, b)

def addEventListener(-Error: Data, target: EventTarget<Error>, eventType: String, listener: Maybe<&2, EventListener(Error)>, options: L.Options) -> IO(Unit):
  match target:
    case EventTarget{dispatcher}: addEventListenerDispatcher(EventTarget<Error>, Error, dispatcher, eventType, listener, options)

def removeEventListener(-Error: Data, target: EventTarget<Error>, eventType: String, listener: Maybe<&2, EventListener(Error)>, capture: Bool) -> IO(Unit):
  match target:
    case EventTarget{dispatcher}: removeEventListenerDispatcher(EventTarget<Error>, Error, dispatcher, eventType, listener, capture)

def dispatchEvent(-Error: Data, +target: EventTarget<Error>, +event: EventValue(Error)) -> IO(Result<&2, &2, E.DispatchError, Bool>):
  match target:
    case EventTarget{+dispatcher}: dispatchEventDispatcher(EventTarget<Error>, Error, dispatcher, EventTarget{dispatcher}, event)

def dispose(-Error: Data, target: EventTarget<Error>) -> IO(Unit):
  match target:
    case EventTarget{dispatcher}: disposeDispatcher(EventTarget<Error>, Error, dispatcher)
