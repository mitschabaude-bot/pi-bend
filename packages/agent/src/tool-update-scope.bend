import Base
import ../../runtime/src/ref.bend as R
import ../../runtime/src/deferred.bend as D

# Invocation-owned effect state. Message/tool payloads remain immutable values.
def Outcome(-Error: Data) -> Data: Result<&2, &2, Error, Unit>
type Failure<-Error: Data> is Data:
  Failure{index: Nat, error: Error}
type State<-Error: Data> is Data:
  State{accepting: Bool, active: Nat, nextIndex: Nat, firstFailure: Maybe<&2, Failure<Error>>, outcome: Maybe<&2, Outcome(Error)>}
type Scope<-Error: Data> is Data:
  Scope{state: R.Ref<State<Error>>, completion: D.Deferred<Outcome(Error)>, drained: D.Deferred<Unit>}
# Affine tickets prevent settling an accepted update more than once.
# Owners must complete every accepted ticket before disposing the scope.
type Ticket<-Error: Data> is Type:
  Ticket{scope: Scope<Error>, index: Nat}
type Notification<-Error: Data> is Data:
  Notification{outcome: Maybe<&2, Outcome(Error)>, drained: Bool}

def new(-Error: Data) -> IO(Scope<Error>):
  do IO<Scope<Error>>:
    state : R.Ref<State<Error>> <- R.new(State<Error>, State{True{}, 0n, 0n, None{}, None{}})
    completion : D.Deferred<Outcome(Error)> <- D.new(Outcome(Error))
    drained : D.Deferred<Unit> <- D.new(Unit)
    return Scope{state, completion, drained}

def reserve(-Error: Data, state: State<Error>) -> State<Error> & Maybe<&2, Nat>:
  match state:
    case State{True{}, active, +next, failure, outcome}: {(State{True{}, 1n+active, 1n+next, failure, outcome}, Some{next}) : State<Error> & Maybe<&2, Nat>}
    case other: {(other, None{}) : State<Error> & Maybe<&2, Nat>}

def ticket(-Error: Data, scope: Scope<Error>, index: Maybe<&2, Nat>) -> Maybe<&1, Ticket<Error>>:
  match index:
    case None{}: None{}
    case Some{value}: Some{Ticket{scope, value}}

def begin(-Error: Data, +scope: Scope<Error>) -> IO(Maybe<&1, Ticket<Error>>):
  match scope:
    case Scope{state, _, _}:
      do IO<Maybe<&1, Ticket<Error>>>:
        index : Maybe<&2, Nat> <- R.modify(State<Error>, Maybe<&2, Nat>, state, current => reserve(Error, current))
        return ticket(Error, scope, index)

# Before closing, already-failed updates are selected in registration order.
# After closing, the first arriving failure wins the pending completion.
def earlier(-Error: Data, +index: Nat, error: Error, previous: Maybe<&2, Failure<Error>>) -> Maybe<&2, Failure<Error>>:
  match previous:
    case None{}: Some{Failure{index, error}}
    case Some{Failure{+oldIndex, oldError}}: Some{Bool.pick(Failure<Error>, Nat.is_lt(index, oldIndex), Failure{index, error}, Failure{oldIndex, oldError})}

def preserveOutcome(-Error: Data, error: Error, outcome: Maybe<&2, Outcome(Error)>) -> Maybe<&2, Outcome(Error)>:
  match outcome:
    case None{}: Some{Fail{error}}
    case other: other

def failedState(-Error: Data, state: State<Error>, index: Nat, error: Error) -> State<Error>:
  match state:
    case State{True{}, active, next, failure, outcome}: State{True{}, active, next, earlier(Error, index, error, failure), outcome}
    case State{False{}, active, next, failure, outcome}: State{False{}, active, next, failure, preserveOutcome(Error, error, outcome)}

def completedState(-Error: Data, state: State<Error>, index: Nat, completion: Outcome(Error)) -> State<Error>:
  match completion:
    case Done{_}: state
    case Fail{error}: failedState(Error, state, index, error)

def recordedOutcome(-Error: Data, state: State<Error>) -> Maybe<&2, Outcome(Error)>:
  match state:
    case State{_, _, _, _, outcome}: outcome

def recordFailure(-Error: Data, state: State<Error>, index: Nat, completion: Outcome(Error)) -> State<Error> & Maybe<&2, Outcome(Error)>:
  +updated = completedState(Error, state, index, completion)
  (updated, recordedOutcome(Error, updated))

def publish(-Error: Data, target: D.Deferred<Outcome(Error)>, outcome: Maybe<&2, Outcome(Error)>) -> IO(Unit):
  match outcome:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        won : Bool <- D.resolve(Outcome(Error), target, value)
        return Unit{}

def signalDrained(-Error: Data, drained: D.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- D.resolve(Unit, drained, Unit{})
    return Unit{}

def notify(-Error: Data, completion: D.Deferred<Outcome(Error)>, drained: D.Deferred<Unit>, action: Notification<Error>) -> IO(Unit):
  match action:
    case Notification{outcome, ready}:
      do IO<Unit>:
        publish(Error, completion, outcome)
        Bool.pick(IO(Unit), ready, signalDrained(Error, drained), IO.pure(Unit, Unit{}))

def retire(-Error: Data, state: State<Error>) -> State<Error> & Notification<Error>:
  match state:
    case State{False{}, 1n+0n, next, failure, None{}}: {(State{False{}, 0n, next, failure, Some{Done{Unit{}}}}, Notification{Some{Done{Unit{}}}, True{}}) : State<Error> & Notification<Error>}
    case State{False{}, 1n+0n, next, failure, Some{+outcome}}: {(State{False{}, 0n, next, failure, Some{outcome}}, Notification{Some{outcome}, True{}}) : State<Error> & Notification<Error>}
    case State{accepting, 1n+active, next, failure, outcome}: {(State{accepting, active, next, failure, outcome}, Notification{None{}, False{}}) : State<Error> & Notification<Error>}
    case other: {(other, Notification{None{}, False{}}) : State<Error> & Notification<Error>}

# Publish failure before retiring the worker. Drain means no worker can still
# access scope resources, including the completion Deferred's notification phase.
def complete(-Error: Data, update: Ticket<Error>, outcome: Outcome(Error)) -> IO(Unit):
  match update:
    case Ticket{Scope{+state, +completion, drained}, index}:
      do IO<Unit>:
        ready : Maybe<&2, Outcome(Error)> <- R.modify(State<Error>, Maybe<&2, Outcome(Error)>, state, current => recordFailure(Error, current, index, outcome))
        publish(Error, completion, ready)
        action : Notification<Error> <- R.modify(State<Error>, Notification<Error>, state, current => retire(Error, current))
        notify(Error, completion, drained, action)

def closingOutcome(-Error: Data, active: Nat, failure: Maybe<&2, Failure<Error>>) -> Maybe<&2, Outcome(Error)>:
  match failure:
    case Some{Failure{_, error}}: Some{Fail{error}}
    case None{}: Bool.pick(Maybe<&2, Outcome(Error)>, Nat.is_eq(active, 0n), Some{Done{Unit{}}}, None{})

def closeState(-Error: Data, state: State<Error>) -> State<Error> & Notification<Error>:
  match state:
    case State{True{}, +active, next, +failure, _}:
      +outcome = closingOutcome(Error, active, failure)
      {(State{False{}, active, next, failure, outcome}, Notification{outcome, Nat.is_eq(active, 0n)}) : State<Error> & Notification<Error>}
    case other: {(other, Notification{None{}, False{}}) : State<Error> & Notification<Error>}

# Close synchronously when tool execution settles, before awaiting listeners.
def close(-Error: Data, scope: Scope<Error>) -> IO(Unit):
  match scope:
    case Scope{state, completion, drained}:
      do IO<Unit>:
        action : Notification<Error> <- R.modify(State<Error>, Notification<Error>, state, current => closeState(Error, current))
        notify(Error, completion, drained, action)

def result(-Error: Data, scope: Scope<Error>) -> IO(Outcome(Error)):
  match scope:
    case Scope{_, completion, _}: D.result(Outcome(Error), completion)

# Retire all retained callback aliases before disposal. Result may fail before
# every accepted update settles; disposal additionally waits for their drain.
def dispose(-Error: Data, scope: Scope<Error>) -> IO(Unit):
  match scope:
    case Scope{state, completion, +drained}:
      do IO<Unit>:
        finished : Unit <- D.result(Unit, drained)
        previous : State<Error> <- R.dispose(State<Error>, state)
        D.dispose(Outcome(Error), completion)
        D.dispose(Unit, drained)
