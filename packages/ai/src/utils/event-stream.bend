import Base
import ../types.bend as Types
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/deferred.bend as D
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/fifo.bend as Q

# Port of the generic EventStream in pi-ai at 46c9de402. Yield and End encode
# IteratorResult's discriminated done flag; Yield can itself contain None.
type Iteration<-T: Data> is Data:
  Yield{value: T}
  End{}

type State<-T: Data> is Data:
  State{queue: Q.Queue<T>, waiting: Q.Queue<Chan(Iteration<T>)>, done: Bool, resultClaimed: Bool}

type EventStream<-T: Data, -R: Data> is Data:
  EventStream{state: Ref.Ref<State<T>>, finalResult: D.Deferred<R>, isComplete: C.Callback<T, Bool>, extractResult: C.Callback<T, R>}

def create(-T: Data, -R: Data, isComplete: C.Callback<T, Bool>, extractResult: C.Callback<T, R>) -> IO(EventStream<T, R>):
  do IO<EventStream<T, R>>:
    state : Ref.Ref<State<T>> <- Ref.new(State<T>, State{Q.new(T), Q.new(Chan(Iteration<T>)), False{}, False{}})
    finalResult : D.Deferred<R> <- D.new(R)
    return EventStream{state, finalResult, isComplete, extractResult}

def doneState(-T: Data, state: State<T>) -> State<T> & Bool:
  match state:
    case State{queue, waiting, +done, claimed}: (State{queue, waiting, done, claimed}, done)

type Commit<-T: Data> is Data:
  Ignored{}
  Delivered{reply: Maybe<&2, Chan(Iteration<T>)>}

def enqueueDelivery(-T: Data, queue: Q.Queue<T>, done: Bool, claimed: Bool, event: T, popped: Q.Queue<Chan(Iteration<T>)> & Maybe<&2, Chan(Iteration<T>)>) -> State<T> & Commit<T>:
  match popped:
    case Tuple{waiting, None{}}: (State{Q.enqueue(T, queue, event), waiting, done, claimed}, Delivered{None{}})
    case Tuple{waiting, Some{+reply}}: (State{queue, waiting, done, claimed}, Delivered{Some{reply}})

# Commit the event and its terminal flag together. IO callbacks may suspend,
# so recheck closure here and reserve the first final result in the same state.
def commitPush(-T: Data, state: State<T>, event: T, +complete: Bool) -> State<T> & Commit<T>:
  match state:
    case State{queue, waiting, True{}, claimed}: (State{queue, waiting, True{}, claimed}, Ignored{})
    case State{queue, waiting, False{}, claimed}: enqueueDelivery(T, queue, complete, claimed || complete, event, Q.dequeue(Chan(Iteration<T>), waiting))

def notify(-T: Data, reply: Maybe<&2, Chan(Iteration<T>)>, item: Iteration<T>) -> IO(Unit):
  match reply:
    case None{}: IO.pure(Unit, Unit{})
    case Some{channel}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Iteration<T>, channel, item)
        Ref.requireSent(sent)

def settleOptional(-R: Data, deferred: D.Deferred<R>, value: Maybe<&2, R>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{resultValue}:
      do IO<Unit>:
        won : Bool <- D.resolve(R, deferred, resultValue)
        return Unit{}

def extractIfComplete(-T: Data, -R: Data, complete: Bool, extract: C.Callback<T, R>, event: T) -> IO(Maybe<&2, R>):
  match complete:
    case False{}: IO.pure(Maybe<&2, R>, None{})
    case True{}:
      do IO<Maybe<&2, R>>:
        value : R <- C.call(T, R, extract, event)
        return Some{value}

def publishCommitted(-T: Data, -R: Data, finalResult: D.Deferred<R>, event: T, value: Maybe<&2, R>, commit: Commit<T>) -> IO(Unit):
  match commit:
    case Ignored{}: IO.pure(Unit, Unit{})
    case Delivered{reply}:
      do IO<Unit>:
        settleOptional(R, finalResult, value)
        notify(T, reply, Yield{event})

def pushOpen(-T: Data, -R: Data, closed: Bool, state: Ref.Ref<State<T>>, finalResult: D.Deferred<R>, predicate: C.Callback<T, Bool>, extract: C.Callback<T, R>, +event: T) -> IO(Unit):
  match closed:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        +complete : Bool <- C.call(T, Bool, predicate, event)
        value : Maybe<&2, R> <- extractIfComplete(T, R, complete, extract, event)
        commit : Commit<T> <- Ref.modify(State<T>, Commit<T>, state, current => commitPush(T, current, event, complete))
        publishCommitted(T, R, finalResult, event, value, commit)

def push(-T: Data, -R: Data, stream: EventStream<T, R>, event: T) -> IO(Unit):
  match stream:
    case EventStream{+state, finalResult, predicate, extract}:
      do IO<Unit>:
        closed : Bool <- Ref.modify(State<T>, Bool, state, current => doneState(T, current))
        pushOpen(T, R, closed, state, finalResult, predicate, extract, event)

def endState(-T: Data, state: State<T>, +provided: Bool) -> State<T> & (List<&2, Chan(Iteration<T>)> & Bool):
  match state:
    case State{queue, waiting, _, +claimed}: (State{queue, Q.new(Chan(Iteration<T>)), True{}, claimed || provided}, (Q.drain(Chan(Iteration<T>), waiting), provided && Bool.not(claimed)))

# The atomic state transition owns result settlement. A later end cannot win
# merely because the terminal push's continuation has not run yet.
def settleClaimed(-R: Data, claimed: Bool, deferred: D.Deferred<R>, value: Maybe<&2, R>) -> IO(Unit):
  match claimed:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: settleOptional(R, deferred, value)

def wakeEnded(-T: Data, waiting: List<&2, Chan(Iteration<T>)>) -> IO(Unit):
  match waiting:
    case Nil{}: IO.pure(Unit, Unit{})
    case reply <> rest:
      do IO<Unit>:
        notify(T, Some{reply}, End{})
        wakeEnded(T, rest)

def publishEnd(-T: Data, -R: Data, finalResult: D.Deferred<R>, value: Maybe<&2, R>, ended: List<&2, Chan(Iteration<T>)> & Bool) -> IO(Unit):
  match ended:
    case Tuple{waiting, claimed}:
      do IO<Unit>:
        settleClaimed(R, claimed, finalResult, value)
        wakeEnded(T, waiting)

def end(-T: Data, -R: Data, stream: EventStream<T, R>, +value: Maybe<&2, R>) -> IO(Unit):
  match stream:
    case EventStream{state, finalResult, _, _}:
      do IO<Unit>:
        ended : List<&2, Chan(Iteration<T>)> & Bool <- Ref.modify(State<T>, List<&2, Chan(Iteration<T>)> & Bool, state, current => endState(T, current, Maybe.is_some(&2, R, value)))
        publishEnd(T, R, finalResult, value, ended)

# Like the upstream method, return the same final-result promise immediately.
def result(-T: Data, -R: Data, stream: EventStream<T, R>) -> D.Deferred<R>:
  match stream:
    case EventStream{_, finalResult, _, _}: finalResult

# Convenience equivalent to await stream.result().
def resultValue(-T: Data, -R: Data, stream: EventStream<T, R>) -> IO(R):
  D.result(R, result(T, R, stream))

def subscribeEmpty(-T: Data, done: Bool, claimed: Bool, queue: Q.Queue<T>, waiting: Q.Queue<Chan(Iteration<T>)>, reply: Chan(Iteration<T>)) -> State<T> & Maybe<&2, Iteration<T>>:
  match done:
    case True{}: (State{queue, waiting, True{}, claimed}, Some{End{}})
    case False{}: (State{queue, Q.enqueue(Chan(Iteration<T>), waiting, reply), False{}, claimed}, None{})

def subscribePopped(-T: Data, waiting: Q.Queue<Chan(Iteration<T>)>, done: Bool, claimed: Bool, reply: Chan(Iteration<T>), popped: Q.Queue<T> & Maybe<&2, T>) -> State<T> & Maybe<&2, Iteration<T>>:
  match popped:
    case Tuple{queue, None{}}: subscribeEmpty(T, done, claimed, queue, waiting, reply)
    case Tuple{queue, Some{value}}: (State{queue, waiting, done, claimed}, Some{Yield{value}})

def subscribeState(-T: Data, state: State<T>, reply: Chan(Iteration<T>)) -> State<T> & Maybe<&2, Iteration<T>>:
  match state:
    case State{queue, waiting, done, claimed}: subscribePopped(T, waiting, done, claimed, reply, Q.dequeue(T, queue))

def subscribeReady(-T: Data, reply: Chan(Iteration<T>), ready: Maybe<&2, Iteration<T>>) -> IO(Unit):
  match ready:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: notify(T, Some{reply}, value)

# Internal primitive used by each iterator's serialized request driver.
def subscribe(-T: Data, -R: Data, stream: EventStream<T, R>) -> IO(D.Ticket<Iteration<T>>):
  match stream:
    case EventStream{state, _, _, _}:
      do IO<D.Ticket<Iteration<T>>>:
        +reply : Chan(Iteration<T>) <- Chan.new(Iteration<T>, 1)
        ready : Maybe<&2, Iteration<T>> <- Ref.modify(State<T>, Maybe<&2, Iteration<T>>, state, current => subscribeState(T, current, reply))
        subscribeReady(T, reply, ready)
        return D.Ticket{reply}

# Each async generator serializes its own next calls. Separate iterators share
# the stream queue but have independent request queues and terminal states.
type Request<-T: Data> is Data:
  Request{answer: D.Deferred<Iteration<T>>, registered: Maybe<&2, Chan(Unit)>}

type IteratorState<-T: Data> is Data:
  IteratorState{requests: Q.Queue<Request<T>>, running: Bool, ended: Bool, idleWaiters: List<&2, Chan(Unit)>}

type Iterator<-T: Data, -R: Data> is Data:
  Iterator{stream: EventStream<T, R>, state: Ref.Ref<IteratorState<T>>}

def iterator(-T: Data, -R: Data, stream: EventStream<T, R>) -> IO(Iterator<T, R>):
  do IO<Iterator<T, R>>:
    state : Ref.Ref<IteratorState<T>> <- Ref.new(IteratorState<T>, IteratorState{Q.new(Request<T>), False{}, False{}, Nil{}})
    return Iterator{stream, state}

def acknowledge(reply: Maybe<&2, Chan(Unit)>) -> IO(Unit):
  match reply:
    case None{}: IO.pure(Unit, Unit{})
    case Some{channel}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, channel, Unit{})
        Ref.requireSent(sent)

def wakeIdle(waiters: List<&2, Chan(Unit)>) -> IO(Unit):
  match waiters:
    case Nil{}: IO.pure(Unit, Unit{})
    case channel <> rest:
      do IO<Unit>:
        acknowledge(Some{channel})
        wakeIdle(rest)

type Work<-T: Data> is Data:
  Idle{waiters: List<&2, Chan(Unit)>}
  Work{request: Request<T>, ended: Bool}

def takeRequest(-T: Data, +ended: Bool, waiters: List<&2, Chan(Unit)>, popped: Q.Queue<Request<T>> & Maybe<&2, Request<T>>) -> IteratorState<T> & Work<T>:
  match popped:
    case Tuple{requests, None{}}: (IteratorState{requests, False{}, ended, Nil{}}, Idle{waiters})
    case Tuple{requests, Some{request}}: (IteratorState{requests, True{}, ended, waiters}, Work{request, ended})

def workState(-T: Data, state: IteratorState<T>) -> IteratorState<T> & Work<T>:
  match state:
    case IteratorState{requests, _, ended, waiters}: takeRequest(T, ended, waiters, Q.dequeue(Request<T>, requests))

def rememberEnd(-T: Data, state: IteratorState<T>, value: Iteration<T>) -> IteratorState<T> & Unit:
  match state value:
    case IteratorState{requests, running, _, waiters} End{}: (IteratorState{requests, running, True{}, waiters}, Unit{})
    case state Yield{_}: (state, Unit{})

def receiveNext(-T: Data, -R: Data, ended: Bool, stream: EventStream<T, R>, registered: Maybe<&2, Chan(Unit)>) -> IO(Iteration<T>):
  match ended:
    case True{}:
      do IO<Iteration<T>>:
        acknowledge(registered)
        return End{}
    case False{}:
      do IO<Iteration<T>>:
        ticket : D.Ticket<Iteration<T>> <- subscribe(T, R, stream)
        acknowledge(registered)
        D.wait(Iteration<T>, ticket)

# Guarded IO recursion: one step consumes one explicitly queued next request.
# The driver exits when idle; there is no permanent actor or polling loop.
@unsafe
def drive(-T: Data, -R: Data, +stream: EventStream<T, R>, +state: Ref.Ref<IteratorState<T>>, work: Work<T>) -> IO(Unit):
  match work:
    case Idle{waiters}: wakeIdle(waiters)
    case Work{Request{answer, registered}, ended}:
      do IO<Unit>:
        +value : Iteration<T> <- receiveNext(T, R, ended, stream, registered)
        Ref.modify(IteratorState<T>, Unit, state, current => rememberEnd(T, current, value))
        following : Work<T> <- Ref.modify(IteratorState<T>, Work<T>, state, current => workState(T, current))
        won : Bool <- D.resolve(Iteration<T>, answer, value)
        drive(T, R, stream, state, following)

def enqueueRequest(-T: Data, state: IteratorState<T>, answer: D.Deferred<Iteration<T>>, registered: Chan(Unit)) -> IteratorState<T> & Bool:
  match state:
    case IteratorState{requests, False{}, ended, waiters}: (IteratorState{Q.enqueue(Request<T>, requests, Request{answer, Some{registered}}), True{}, ended, waiters}, True{})
    case IteratorState{requests, True{}, ended, waiters}: (IteratorState{Q.enqueue(Request<T>, requests, Request{answer, None{}}), True{}, ended, waiters}, False{})

def startDriver(-T: Data, -R: Data, start: Bool, stream: EventStream<T, R>, +state: Ref.Ref<IteratorState<T>>, +registered: Chan(Unit)) -> IO(Unit):
  match start:
    case False{}: Chan.close(Unit, registered)
    case True{}:
      do IO<Unit>:
        work : Work<T> <- Ref.modify(IteratorState<T>, Work<T>, state, current => workState(T, current))
        IO.spawn(Unit, drive(T, R, stream, state, work))
        ready : Unit <- IO.join(Unit, registered)
        return Unit{}

# Returns a Promise-equivalent without waiting for an event. The first pending
# request registers before this call returns, preserving cross-iterator FIFO.
def next(-T: Data, -R: Data, cursor: Iterator<T, R>) -> IO(D.Deferred<Iteration<T>>):
  match cursor:
    case Iterator{stream, +state}:
      do IO<D.Deferred<Iteration<T>>>:
        +answer : D.Deferred<Iteration<T>> <- D.new(Iteration<T>)
        +registered : Chan(Unit) <- Chan.new(Unit, 1)
        start : Bool <- Ref.modify(IteratorState<T>, Bool, state, current => enqueueRequest(T, current, answer, registered))
        startDriver(T, R, start, stream, state, registered)
        return answer

def nextValue(-T: Data, -R: Data, cursor: Iterator<T, R>) -> IO(Iteration<T>):
  do IO<Iteration<T>>:
    +answer : D.Deferred<Iteration<T>> <- next(T, R, cursor)
    value : Iteration<T> <- D.result(Iteration<T>, answer)
    D.dispose(Iteration<T>, answer)
    return value

def idleState(-T: Data, state: IteratorState<T>, reply: Chan(Unit)) -> IteratorState<T> & Bool:
  match state:
    case IteratorState{requests, True{}, ended, waiters}: (IteratorState{requests, True{}, ended, reply <> waiters}, False{})
    case IteratorState{requests, False{}, ended, waiters}: (IteratorState{requests, False{}, ended, waiters}, True{})

def idleReady(ready: Bool, reply: Chan(Unit)) -> IO(Unit):
  match ready:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: acknowledge(Some{reply})

# Explicit lifetimes are temporary until Bend gains managed shared handles.
# Retire all aliases and finish pending requests before disposing an iterator.
def disposeIterator(-T: Data, -R: Data, cursor: Iterator<T, R>) -> IO(Unit):
  match cursor:
    case Iterator{_, +state}:
      do IO<Unit>:
        +reply : Chan(Unit) <- Chan.new(Unit, 1)
        ready : Bool <- Ref.modify(IteratorState<T>, Bool, state, current => idleState(T, current, reply))
        idleReady(ready, reply)
        finished : Unit <- IO.join(Unit, reply)
        previous : IteratorState<T> <- Ref.dispose(IteratorState<T>, state)
        return Unit{}

# Dispose after ending and retiring all iterators/result observers. Callback
# handles are borrowed: their creator retains responsibility for their lifetime.
def dispose(-T: Data, -R: Data, stream: EventStream<T, R>) -> IO(Unit):
  match stream:
    case EventStream{state, finalResult, _, _}:
      do IO<Unit>:
        previous : State<T> <- Ref.dispose(State<T>, state)
        D.dispose(R, finalResult)


# The upstream subclass adds only its fixed completion/extraction callbacks.
# A type alias preserves all generic EventStream operations without wrappers.
def AssistantMessageEventStream(-Arguments: Data, -DiagnosticDetails: Data) -> Data:
  EventStream<Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Types.AssistantMessage<Arguments, DiagnosticDetails>>

def assistantComplete(-Arguments: Data, -DiagnosticDetails: Data, unused: Unit, event: Types.AssistantMessageEvent<Arguments, DiagnosticDetails>) -> IO(Bool):
  match event:
    case Types.StreamDone{_, _}: IO.pure(Bool, True{})
    case Types.StreamError{_, _}: IO.pure(Bool, True{})
    case _: IO.pure(Bool, False{})

def assistantExtract(-Arguments: Data, -DiagnosticDetails: Data, unused: Unit, event: Types.AssistantMessageEvent<Arguments, DiagnosticDetails>) -> IO(Types.AssistantMessage<Arguments, DiagnosticDetails>):
  match event:
    case Types.StreamDone{_, message}: IO.pure(Types.AssistantMessage<Arguments, DiagnosticDetails>, message)
    case Types.StreamError{_, error}: IO.pure(Types.AssistantMessage<Arguments, DiagnosticDetails>, error)
    case _: IO.die(Types.AssistantMessage<Arguments, DiagnosticDetails>, 1, "Unexpected event type for final result")

def createAssistantMessageEventStream(~Arguments: Data, ~DiagnosticDetails: Data) -> IO(AssistantMessageEventStream(Arguments, DiagnosticDetails)):
  do IO<AssistantMessageEventStream(Arguments, DiagnosticDetails)>:
    check : C.Callback<Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Bool> <- C.create(~Unit, ~Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, ~Bool, ~(assistantComplete(Arguments, DiagnosticDetails)), Unit{})
    extract : C.Callback<Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Types.AssistantMessage<Arguments, DiagnosticDetails>> <- C.create(~Unit, ~Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, ~Types.AssistantMessage<Arguments, DiagnosticDetails>, ~(assistantExtract(Arguments, DiagnosticDetails)), Unit{})
    create(Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Types.AssistantMessage<Arguments, DiagnosticDetails>, check, extract)

# The factory above owns its callbacks; unlike generic dispose, release them.
def disposeAssistantMessageEventStream(-Arguments: Data, -DiagnosticDetails: Data, +stream: AssistantMessageEventStream(Arguments, DiagnosticDetails)) -> IO(Unit):
  match stream:
    case EventStream{state, finalResult, check, extract}:
      do IO<Unit>:
        previous : State<Types.AssistantMessageEvent<Arguments, DiagnosticDetails>> <- Ref.dispose(State<Types.AssistantMessageEvent<Arguments, DiagnosticDetails>>, state)
        D.dispose(Types.AssistantMessage<Arguments, DiagnosticDetails>, finalResult)
        C.dispose(Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Bool, check)
        C.dispose(Types.AssistantMessageEvent<Arguments, DiagnosticDetails>, Types.AssistantMessage<Arguments, DiagnosticDetails>, extract)
