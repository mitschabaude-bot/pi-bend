import Base
import ./ref.bend as R
import ./big-nat.bend as N

type Waiter<-A: Data> is Data:
  Required{reply: Chan(A)}
  Removable{key: N.BigNat, reply: Chan(Maybe<&2, A>)}

# Repeatable asynchronous observation of a value that settles exactly once.
type State<-A: Data> is Data:
  Pending{nextKey: N.BigNat, waiters: List<&2, Waiter<A>>}
  Resolved{value: A}

type Deferred<-A: Data> is Data:
  Deferred{state: R.Ref<State<A>>}

# A registration owns one receive. The Deferred itself can be observed again.
type Ticket<-A: Data> is Type:
  Ticket{reply: Chan(A)}

# Cancellation may be requested independently of the single receiving owner.
type Cancellation<-A: Data> is Data:
  Cancellation{deferred: Deferred<A>, key: N.BigNat}

type Observation<-A: Data> is Type:
  Observation{ticket: Ticket<Maybe<&2, A>>, cancellation: Cancellation<A>}

def new(-A: Data) -> IO(Deferred<A>):
  do IO<Deferred<A>>:
    state : R.Ref<State<A>> <- R.new(State<A>, Pending{N.zero(), Nil{}})
    return Deferred{state}

def registerState(-A: Data, state: State<A>, reply: Chan(A)) -> State<A> & Maybe<&2, A>:
  match state:
    case Pending{nextKey, waiters}: (Pending{nextKey, Required{reply} <> waiters}, None{})
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

def settleState(-A: Data, state: State<A>, value: A) -> State<A> & Maybe<&2, List<&2, Waiter<A>>>:
  match state:
    case Pending{_, waiters}: (Resolved{value}, Some{List.reverse(&2, Waiter<A>, waiters)})
    case Resolved{original}: (Resolved{original}, None{})

def deliver(-A: Data, waiter: Waiter<A>, value: A) -> IO(Unit):
  match waiter:
    case Required{reply}: notifyReady(A, reply, Some{value})
    case Removable{_, reply}: notifyReady(Maybe<&2, A>, reply, Some{Some{value}})

def wake(-A: Data, waiters: List<&2, Waiter<A>>, +value: A) -> IO(Unit):
  match waiters:
    case Nil{}: IO.pure(Unit, Unit{})
    case waiter <> rest:
      do IO<Unit>:
        deliver(A, waiter, value)
        wake(A, rest, value)

def notifySettlement(-A: Data, waiters: Maybe<&2, List<&2, Waiter<A>>>, value: A) -> IO(Bool):
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
        waiters : Maybe<&2, List<&2, Waiter<A>>> <- R.modify(State<A>, Maybe<&2, List<&2, Waiter<A>>>, state, current => settleState(A, current, value))
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
    case Pending{_, _}: None{}
    case Resolved{value}: Some{value}

def peek(-A: Data, deferred: Deferred<A>) -> IO(Maybe<&2, A>):
  match deferred:
    case Deferred{state}:
      do IO<Maybe<&2, A>>:
        value : State<A> <- R.read(State<A>, state)
        return peekState(A, value)

def registerObservation(-A: Data, state: State<A>, reply: Chan(Maybe<&2, A>)) -> State<A> & (N.BigNat & Maybe<&2, A>):
  match state:
    case Pending{+nextKey, waiters}:
      (Pending{N.add(nextKey, N.one()), Removable{nextKey, reply} <> waiters}, (nextKey, None{}))
    case Resolved{+value}: (Resolved{value}, (N.zero(), Some{value}))

def observationReady(-A: Data, deferred: Deferred<A>, +reply: Chan(Maybe<&2, A>), registration: N.BigNat & Maybe<&2, A>) -> IO(Observation<A>):
  match registration:
    case Tuple{key, ready}:
      do IO<Observation<A>>:
        notifyReady(Maybe<&2, A>, reply, Maybe.map(&2, A, Maybe<&2, A>, value => Some{value}, ready))
        return Observation{Ticket{reply}, Cancellation{deferred, key}}

# The ticket must be consumed even after cancellation, releasing its channel.
# None means this observation was cancelled; Some retains the settled value.
def observe(-A: Data, +deferred: Deferred<A>) -> IO(Observation<A>):
  match deferred:
    case Deferred{+state}:
      do IO<Observation<A>>:
        +reply : Chan(Maybe<&2, A>) <- Chan.new(Maybe<&2, A>, 1)
        registration : N.BigNat & Maybe<&2, A> <- R.modify(State<A>, N.BigNat & Maybe<&2, A>, state, current => registerObservation(A, current, reply))
        observationReady(A, Deferred{state}, reply, registration)

def restoreWaiter(-A: Data, waiter: Waiter<A>, removed: List<&2, Waiter<A>> & Maybe<&2, Chan(Maybe<&2, A>)>) -> List<&2, Waiter<A>> & Maybe<&2, Chan(Maybe<&2, A>)>:
  match removed:
    case Tuple{rest, reply}: (waiter <> rest, reply)

def removeWaiter(-A: Data, waiters: List<&2, Waiter<A>>, +key: N.BigNat) -> List<&2, Waiter<A>> & Maybe<&2, Chan(Maybe<&2, A>)>:
  match waiters:
    case Nil{}: (Nil{}, None{})
    case Required{reply} <> rest: restoreWaiter(A, Required{reply}, removeWaiter(A, rest, key))
    case Removable{+candidate, +reply} <> +rest:
      Bool.pick(List<&2, Waiter<A>> & Maybe<&2, Chan(Maybe<&2, A>)>, N.equal(candidate, key), (rest, Some{reply}), restoreWaiter(A, Removable{candidate, reply}, removeWaiter(A, rest, key)))

def removedState(-A: Data, nextKey: N.BigNat, removed: List<&2, Waiter<A>> & Maybe<&2, Chan(Maybe<&2, A>)>) -> State<A> & Maybe<&2, Chan(Maybe<&2, A>)>:
  match removed:
    case Tuple{rest, reply}: (Pending{nextKey, rest}, reply)

def cancelState(-A: Data, state: State<A>, key: N.BigNat) -> State<A> & Maybe<&2, Chan(Maybe<&2, A>)>:
  match state:
    case Pending{nextKey, waiters}: removedState(A, nextKey, removeWaiter(A, waiters, key))
    case Resolved{value}: (Resolved{value}, None{})

def notifyCancellation(-A: Data, removed: Maybe<&2, Chan(Maybe<&2, A>)>) -> IO(Bool):
  match removed:
    case None{}: IO.pure(Bool, False{})
    case Some{reply}:
      do IO<Bool>:
        notifyReady(Maybe<&2, A>, reply, Some{None{}})
        return True{}

# Atomic removal competes with settlement. Exactly one side owns delivery.
# True means cancellation won; repeated or post-settlement calls return false.
def cancel(-A: Data, cancellation: Cancellation<A>) -> IO(Bool):
  match cancellation:
    case Cancellation{Deferred{state}, key}:
      do IO<Bool>:
        removed : Maybe<&2, Chan(Maybe<&2, A>)> <- R.modify(State<A>, Maybe<&2, Chan(Maybe<&2, A>)>, state, current => cancelState(A, current, key))
        notifyCancellation(A, removed)
