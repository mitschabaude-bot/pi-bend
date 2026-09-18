import Base
import ./ref.bend as R

# Repeatable asynchronous observation of a value that settles exactly once.
type State<-A: Data> is Data:
  Pending{waiters: List<&2, Chan(A)>}
  Resolved{value: A}

type Deferred<-A: Data> is Data:
  Deferred{state: R.Ref<State<A>>}

# A registration owns one receive. The Deferred itself can be observed again.
type Ticket<-A: Data> is Type:
  Ticket{reply: Chan(A)}

def new(-A: Data) -> IO(Deferred<A>):
  do IO<Deferred<A>>:
    state : R.Ref<State<A>> <- R.new(State<A>, Pending{Nil{}})
    return Deferred{state}

def registerState(-A: Data, state: State<A>, reply: Chan(A)) -> State<A> & Maybe<&2, A>:
  match state:
    case Pending{waiters}: (Pending{reply <> waiters}, None{})
    case Resolved{+value}: (Resolved{value}, Some{value})

def notifyReady(-A: Data, reply: Chan(A), ready: Maybe<&2, A>) -> IO(Unit):
  match ready:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        sent : Bool <- Chan.send(A, reply, value)
        R.requireSent(sent)

# Registration completes before returning, even when the value is unresolved.
# This supports deterministic waiter ordering without sleeps or actor polling.
def subscribe(-A: Data, deferred: Deferred<A>) -> IO(Ticket<A>):
  match deferred:
    case Deferred{state}:
      do IO<Ticket<A>>:
        +reply : Chan(A) <- Chan.new(A, 1)
        ready : Maybe<&2, A> <- R.modify(State<A>, Maybe<&2, A>, state, current => registerState(A, current, reply))
        notifyReady(A, reply, ready)
        return Ticket{reply}

def wait(-A: Data, ticket: Ticket<A>) -> IO(A):
  match ticket:
    case Ticket{reply}: IO.join(A, reply)

def result(-A: Data, deferred: Deferred<A>) -> IO(A):
  do IO<A>:
    ticket : Ticket<A> <- subscribe(A, deferred)
    wait(A, ticket)

def settleState(-A: Data, state: State<A>, value: A) -> State<A> & Maybe<&2, List<&2, Chan(A)>>:
  match state:
    case Pending{waiters}: (Resolved{value}, Some{List.reverse(&2, Chan(A), waiters)})
    case Resolved{original}: (Resolved{original}, None{})

def wake(-A: Data, waiters: List<&2, Chan(A)>, +value: A) -> IO(Unit):
  match waiters:
    case Nil{}: IO.pure(Unit, Unit{})
    case reply <> rest:
      do IO<Unit>:
        sent : Bool <- Chan.send(A, reply, value)
        R.requireSent(sent)
        wake(A, rest, value)

def notifySettlement(-A: Data, waiters: Maybe<&2, List<&2, Chan(A)>>, value: A) -> IO(Bool):
  match waiters:
    case None{}: IO.pure(Bool, False{})
    case Some{replies}:
      do IO<Bool>:
        wake(A, replies, value)
        return True{}

# True identifies the winning settlement. Later settlements are ignored.
def resolve(-A: Data, deferred: Deferred<A>, +value: A) -> IO(Bool):
  match deferred:
    case Deferred{state}:
      do IO<Bool>:
        waiters : Maybe<&2, List<&2, Chan(A)>> <- R.modify(State<A>, Maybe<&2, List<&2, Chan(A)>>, state, current => settleState(A, current, value))
        notifySettlement(A, waiters, value)

# Low-level lifetime boundary: finish all observations and retire aliases first.
# Pending values may be retired only with no observers. This is not cancellation.
def dispose(-A: Data, deferred: Deferred<A>) -> IO(Unit):
  match deferred:
    case Deferred{state}:
      do IO<Unit>:
        previous : State<A> <- R.dispose(State<A>, state)
        return Unit{}

# Non-blocking observation; a pending value stays distinct from a resolved value.
def peekState(-A: Data, state: State<A>) -> Maybe<&2, A>:
  match state:
    case Pending{_}: None{}
    case Resolved{value}: Some{value}

def peek(-A: Data, deferred: Deferred<A>) -> IO(Maybe<&2, A>):
  match deferred:
    case Deferred{state}:
      do IO<Maybe<&2, A>>:
        value : State<A> <- R.read(State<A>, state)
        return peekState(A, value)
