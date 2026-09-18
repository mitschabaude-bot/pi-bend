import Base
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/big-nat.bend as N

# Ordered subscriptions with explicit registration positions. User callbacks
# run outside the lock. Each dispatch observes removals/additions before it
# selects the next listener, preserving the source's awaited live dispatch.
type Input<-Event: Data, -Signal: Data> is Data:
  Input{event: Event, signal: Signal}
def Handler(-Event: Data, -Signal: Data, -Error: Data) -> Data:
  C.Callback<Input<Event, Signal>, Result<&2, &2, Error, Unit>>
type Entry<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Entry{position: N.BigNat, callback: Handler(Event, Signal, Error)}
type State<-Event: Data, -Signal: Data, -Error: Data> is Data:
  State{next: N.BigNat, entries: List<&2, Entry<Event, Signal, Error>>}
type Listeners<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Listeners{state: R.Ref<State<Event, Signal, Error>>}
type Subscription<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Subscription{listeners: Listeners<Event, Signal, Error>, callback: Handler(Event, Signal, Error)}

def new(-Event: Data, -Signal: Data, -Error: Data) -> IO(Listeners<Event, Signal, Error>):
  do IO<Listeners<Event, Signal, Error>>:
    state : R.Ref<State<Event, Signal, Error>> <- R.new(State<Event, Signal, Error>, State{N.zero(), Nil{}})
    return Listeners{state}
def contains(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +callback: Handler(Event, Signal, Error)) -> Bool:
  match entries:
    case Nil{}: False{}
    case Entry{_, other} <> rest: C.same(Input<Event, Signal>, Result<&2, &2, Error, Unit>, callback, other) || contains(Event, Signal, Error, rest, callback)
def added(-Event: Data, -Signal: Data, -Error: Data, +next: N.BigNat, entries: List<&2, Entry<Event, Signal, Error>>, callback: Handler(Event, Signal, Error), exists: Bool) -> State<Event, Signal, Error>:
  match exists:
    case True{}: State{next, entries}
    case False{}: State{N.add(next, N.one()), List.append(&2, Entry<Event, Signal, Error>, entries, Entry{next, callback} <> Nil{})}
def addState(-Event: Data, -Signal: Data, -Error: Data, state: State<Event, Signal, Error>, +callback: Handler(Event, Signal, Error)) -> State<Event, Signal, Error> & Unit:
  match state:
    case State{next, +entries}: (added(Event, Signal, Error, next, entries, callback, contains(Event, Signal, Error, entries, callback)), Unit{})
def subscribe(-Event: Data, -Signal: Data, -Error: Data, +listeners: Listeners<Event, Signal, Error>, +callback: Handler(Event, Signal, Error)) -> IO(Subscription<Event, Signal, Error>):
  match listeners:
    case Listeners{+state}:
      do IO<Subscription<Event, Signal, Error>>:
        R.modify(State<Event, Signal, Error>, Unit, state, current => addState(Event, Signal, Error, current, callback))
        return Subscription{Listeners{state}, callback}
def remove(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +callback: Handler(Event, Signal, Error)) -> List<&2, Entry<Event, Signal, Error>>:
  match entries:
    case Nil{}: Nil{}
    case Entry{position, +other} <> +rest:
      Bool.pick(List<&2, Entry<Event, Signal, Error>>, C.same(Input<Event, Signal>, Result<&2, &2, Error, Unit>, callback, other), rest, Entry{position, other} <> remove(Event, Signal, Error, rest, callback))
def removeState(-Event: Data, -Signal: Data, -Error: Data, state: State<Event, Signal, Error>, callback: Handler(Event, Signal, Error)) -> State<Event, Signal, Error> & Unit:
  match state:
    case State{next, entries}: (State{next, remove(Event, Signal, Error, entries, callback)}, Unit{})
def unsubscribe(-Event: Data, -Signal: Data, -Error: Data, subscription: Subscription<Event, Signal, Error>) -> IO(Unit):
  match subscription:
    case Subscription{Listeners{state}, callback}: R.modify(State<Event, Signal, Error>, Unit, state, current => removeState(Event, Signal, Error, current, callback))
def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}
def eligible(position: N.BigNat, cursor: Maybe<&2, N.BigNat>) -> Bool:
  match cursor:
    case None{}: True{}
    case Some{previous}: less(N.compare(previous, position))
def nextEntry(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Signal, Error>>:
  match entries:
    case Nil{}: None{}
    case Entry{+position, callback} <> rest:
      Bool.pick(Maybe<&2, Entry<Event, Signal, Error>>, eligible(position, cursor), Some{Entry{position, callback}}, nextEntry(Event, Signal, Error, rest, cursor))
def selected(-Event: Data, -Signal: Data, -Error: Data, state: State<Event, Signal, Error>, cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Signal, Error>>:
  match state:
    case State{_, entries}: nextEntry(Event, Signal, Error, entries, cursor)
# Phase/result arguments avoid mutual recursion: each callback settles before
# the next selection. Failure immediately stops this event's delivery.
@unsafe def dispatch(-Event: Data, -Signal: Data, -Error: Data, +listeners: Listeners<Event, Signal, Error>, +input: Input<Event, Signal>, cursor: Maybe<&2, N.BigNat>, result: Result<&2, &2, Error, Unit>, next: Maybe<&2, Entry<Event, Signal, Error>>, select: Bool) -> IO(Result<&2, &2, Error, Unit>):
  match listeners result next select:
    case Listeners{_} Fail{error} _ _: IO.pure(Result<&2, &2, Error, Unit>, Fail{error})
    case Listeners{+state} Done{_} _ True{}:
      do IO<Result<&2, &2, Error, Unit>>:
        current : State<Event, Signal, Error> <- R.read(State<Event, Signal, Error>, state)
        dispatch(Event, Signal, Error, Listeners{state}, input, None{}, Done{Unit{}}, selected(Event, Signal, Error, current, cursor), False{})
    case Listeners{state} Done{_} Some{Entry{position, callback}} False{}:
      do IO<Result<&2, &2, Error, Unit>>:
        outcome : Result<&2, &2, Error, Unit> <- C.call(Input<Event, Signal>, Result<&2, &2, Error, Unit>, callback, input)
        dispatch(Event, Signal, Error, Listeners{state}, input, Some{position}, outcome, None{}, True{})
    case Listeners{_} Done{_} None{} False{}: IO.pure(Result<&2, &2, Error, Unit>, Done{Unit{}})
def emit(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>, event: Event, signal: Signal) -> IO(Result<&2, &2, Error, Unit>):
  dispatch(Event, Signal, Error, listeners, Input{event, signal}, None{}, Done{Unit{}}, None{}, True{})
# Callbacks are borrowed. Drain in-flight dispatches before disposing the
# registry, then retire callback handles according to their own ownership.
def dispose(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>) -> IO(Unit):
  match listeners:
    case Listeners{state}:
      do IO<Unit>:
        previous : State<Event, Signal, Error> <- R.dispose(State<Event, Signal, Error>, state)
        return Unit{}
