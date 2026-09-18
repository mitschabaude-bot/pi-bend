import Base
import ./ref.bend as R
import ./callback.bend as C
import ./big-nat.bend as N
import ./utf16.bend as U

# Internal EventTarget listener-list operations. Dispatch, event flags, signal
# options and exception reporting belong to EventTarget, not this collection.
type Options is Data:
  Options{capture: Bool, once: Bool, passive: Bool}

type Registration<-Input: Type, -Output: Type> is Data:
  Registration{key: N.BigNat, eventType: String, callback: C.Callback<Input, Output>, options: Options}

# Links are registration keys rather than separately allocated channels. A
# removed node keeps its original next link until all active walks finish.
type Node<-Input: Type, -Output: Type> is Data:
  Node{registration: Registration<Input, Output>, next: Maybe<&2, N.BigNat>}

type State<-Input: Type, -Output: Type> is Data:
  State{nextKey: N.BigNat, walks: Nat, live: List<&2, Node<Input, Output>>, retired: List<&2, Node<Input, Output>>}

type Registry<-Input: Type, -Output: Type> is Data:
  Registry{state: R.Ref<State<Input, Output>>}

# A walk owns one active-traversal count. Consume it to End or call close.
type Cursor<-Input: Type, -Output: Type> is Type:
  Cursor{registry: Registry<Input, Output>, next: Maybe<&2, N.BigNat>}

type Step<-Input: Type, -Output: Type> is Type:
  End{}
  More{cursor: Cursor<Input, Output>, listener: Maybe<&2, Registration<Input, Output>>}

def new(-Input: Type, -Output: Type) -> IO(Registry<Input, Output>):
  do IO<Registry<Input, Output>>:
    state : R.Ref<State<Input, Output>> <- R.new(State<Input, Output>, State{N.zero(), 0n, Nil{}, Nil{}})
    return Registry{state}

def sameCapture(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

# Duplicate/removal identity ignores once and passive. Types are canonicalized
# on the boundary so equivalent UTF-16 representations remain the same key.
def matches(-Input: Type, -Output: Type, registration: Registration<Input, Output>, eventType: String, callback: C.Callback<Input, Output>, capture: Bool) -> Bool:
  match registration:
    case Registration{_, name, listener, Options{capturing, _, _}}:
      String.eq(name, eventType) && C.same(Input, Output, listener, callback) && sameCapture(capturing, capture)

def keyOf(-Input: Type, -Output: Type, registration: Registration<Input, Output>) -> N.BigNat:
  match registration:
    case Registration{key, _, _, _}: key

def nodeKey(-Input: Type, -Output: Type, node: Node<Input, Output>) -> N.BigNat:
  match node:
    case Node{registration, _}: keyOf(Input, Output, registration)

def isType(-Input: Type, -Output: Type, registration: Registration<Input, Output>, eventType: String) -> Bool:
  match registration:
    case Registration{_, name, _, _}: String.eq(name, eventType)

def onceOnly(-Input: Type, -Output: Type, registration: Registration<Input, Output>) -> Bool:
  match registration:
    case Registration{_, _, _, Options{_, once, _}}: once

def findMatching(-Input: Type, -Output: Type, nodes: List<&2, Node<Input, Output>>, +eventType: String, +callback: C.Callback<Input, Output>, +capture: Bool) -> Maybe<&2, Node<Input, Output>>:
  match nodes:
    case Nil{}: None{}
    case Node{+registration, +next} <> rest:
      Bool.pick(Maybe<&2, Node<Input, Output>>, matches(Input, Output, registration, eventType, callback, capture), Some{Node{registration, next}}, findMatching(Input, Output, rest, eventType, callback, capture))

def findKey(-Input: Type, -Output: Type, nodes: List<&2, Node<Input, Output>>, +key: N.BigNat) -> Maybe<&2, Node<Input, Output>>:
  match nodes:
    case Nil{}: None{}
    case +node <> rest:
      Bool.pick(Maybe<&2, Node<Input, Output>>, N.equal(nodeKey(Input, Output, node), key), Some{node}, findKey(Input, Output, rest, key))

def linkTail(-Input: Type, -Output: Type, node: Node<Input, Output>, eventType: String, key: N.BigNat) -> Node<Input, Output>:
  match node:
    case Node{+registration, None{}}:
      Node{registration, Bool.pick(Maybe<&2, N.BigNat>, isType(Input, Output, registration, eventType), Some{key}, None{})}
    case Node{registration, next}: Node{registration, next}

def appendNode(-Input: Type, -Output: Type, nodes: List<&2, Node<Input, Output>>, +registration: Registration<Input, Output>, +eventType: String, +key: N.BigNat) -> List<&2, Node<Input, Output>>:
  match nodes:
    case Nil{}: Node{registration, None{}} <> Nil{}
    case node <> rest: linkTail(Input, Output, node, eventType, key) <> appendNode(Input, Output, rest, registration, eventType, key)

def addUnlessDuplicate(-Input: Type, -Output: Type, duplicate: Maybe<&2, Node<Input, Output>>, state: State<Input, Output>, +eventType: String, callback: C.Callback<Input, Output>, options: Options) -> State<Input, Output> & Bool:
  match duplicate state:
    case Some{_} unchanged: (unchanged, False{})
    case None{} State{+key, walks, live, retired}:
      (State{N.add(key, N.one()), walks, appendNode(Input, Output, live, Registration{key, eventType, callback, options}, eventType, key), retired}, True{})

def addState(-Input: Type, -Output: Type, state: State<Input, Output>, +eventType: String, +callback: C.Callback<Input, Output>, options: Options) -> State<Input, Output> & Bool:
  match state options:
    case State{key, walks, +live, retired} Options{+capture, once, passive}:
      addUnlessDuplicate(Input, Output, findMatching(Input, Output, live, eventType, callback, capture), State{key, walks, live, retired}, eventType, callback, Options{capture, once, passive})

# True identifies an appended registration. Duplicates retain original flags.
def add(-Input: Type, -Output: Type, registry: Registry<Input, Output>, eventType: String, callback: C.Callback<Input, Output>, options: Options) -> IO(Bool):
  match registry:
    case Registry{state}:
      R.modify(State<Input, Output>, Bool, state, current => addState(Input, Output, current, U.normalize(eventType), callback, options))

def redirect(next: Maybe<&2, N.BigNat>, key: N.BigNat, replacement: Maybe<&2, N.BigNat>) -> Maybe<&2, N.BigNat>:
  match next:
    case None{}: None{}
    case Some{+candidate}: Bool.pick(Maybe<&2, N.BigNat>, N.equal(candidate, key), replacement, Some{candidate})

def unlink(-Input: Type, -Output: Type, nodes: List<&2, Node<Input, Output>>, +key: N.BigNat, +replacement: Maybe<&2, N.BigNat>) -> List<&2, Node<Input, Output>>:
  match nodes:
    case Nil{}: Nil{}
    case Node{+registration, next} <> rest:
      +tail = unlink(Input, Output, rest, key, replacement)
      Bool.pick(List<&2, Node<Input, Output>>, N.equal(keyOf(Input, Output, registration), key), tail, Node{registration, redirect(next, key, replacement)} <> tail)

def retainRemoved(-Input: Type, -Output: Type, walks: Nat, removed: Node<Input, Output>, retired: List<&2, Node<Input, Output>>) -> List<&2, Node<Input, Output>>:
  match walks:
    case 0n: Nil{}
    case 1n+ _: removed <> retired

def removeNode(-Input: Type, -Output: Type, state: State<Input, Output>, node: Node<Input, Output>) -> State<Input, Output>:
  match state node:
    case State{key, +walks, live, retired} Node{+registration, +next}:
      State{key, walks, unlink(Input, Output, live, keyOf(Input, Output, registration), next), retainRemoved(Input, Output, walks, Node{registration, next}, retired)}

def removeFound(-Input: Type, -Output: Type, state: State<Input, Output>, found: Maybe<&2, Node<Input, Output>>) -> State<Input, Output> & Bool:
  match found:
    case None{}: (state, False{})
    case Some{node}: (removeNode(Input, Output, state, node), True{})

def removeState(-Input: Type, -Output: Type, state: State<Input, Output>, eventType: String, callback: C.Callback<Input, Output>, capture: Bool) -> State<Input, Output> & Bool:
  match state:
    case State{key, walks, +live, retired}:
      removeFound(Input, Output, State{key, walks, live, retired}, findMatching(Input, Output, live, eventType, callback, capture))

def remove(-Input: Type, -Output: Type, registry: Registry<Input, Output>, eventType: String, callback: C.Callback<Input, Output>, capture: Bool) -> IO(Bool):
  match registry:
    case Registry{state}:
      R.modify(State<Input, Output>, Bool, state, current => removeState(Input, Output, current, U.normalize(eventType), callback, capture))

def head(-Input: Type, -Output: Type, nodes: List<&2, Node<Input, Output>>, +eventType: String) -> Maybe<&2, N.BigNat>:
  match nodes:
    case Nil{}: None{}
    case Node{+registration, _} <> rest:
      Bool.pick(Maybe<&2, N.BigNat>, isType(Input, Output, registration, eventType), Some{keyOf(Input, Output, registration)}, head(Input, Output, rest, eventType))

def beginState(-Input: Type, -Output: Type, state: State<Input, Output>, eventType: String) -> State<Input, Output> & Maybe<&2, N.BigNat>:
  match state:
    case State{key, walks, +live, retired}: (State{key, 1n+walks, live, retired}, head(Input, Output, live, eventType))

def begin(-Input: Type, -Output: Type, registry: Registry<Input, Output>, eventType: String) -> IO(Cursor<Input, Output>):
  match registry:
    case Registry{+state}:
      do IO<Cursor<Input, Output>>:
        next : Maybe<&2, N.BigNat> <- R.modify(State<Input, Output>, Maybe<&2, N.BigNat>, state, current => beginState(Input, Output, current, U.normalize(eventType)))
        return Cursor{Registry{state}, next}

def retainWhileWalking(-Input: Type, -Output: Type, walks: Nat, retired: List<&2, Node<Input, Output>>) -> List<&2, Node<Input, Output>>:
  match walks:
    case 0n: Nil{}
    case 1n+ _: retired

def closeState(-Input: Type, -Output: Type, state: State<Input, Output>) -> State<Input, Output> & Bool:
  match state:
    case State{key, 0n, live, retired}: (State{key, 0n, live, retired}, False{})
    case State{key, 1n+ +walks, live, retired}: (State{key, walks, live, retainWhileWalking(Input, Output, walks, retired)}, True{})

def requireWalk(closed: Bool) -> IO(Unit):
  match closed:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "listener registry: walk already closed")

# Early termination must close its cursor too (for example stopImmediatePropagation).
def close(-Input: Type, -Output: Type, cursor: Cursor<Input, Output>) -> IO(Unit):
  match cursor:
    case Cursor{Registry{state}, _}:
      do IO<Unit>:
        closed : Bool <- R.modify(State<Input, Output>, Bool, state, current => closeState(Input, Output, current))
        requireWalk(closed)

type Advance<-Input: Type, -Output: Type> is Data:
  Advance{next: Maybe<&2, N.BigNat>, listener: Maybe<&2, Registration<Input, Output>>}
  Stopped{}

type DispatchDecision is Data:
  CallListener{}
  SkipListener{}
  StopDispatch{}

def stoppedState(-Input: Type, -Output: Type, closed: State<Input, Output> & Bool) -> State<Input, Output> & Maybe<&2, Advance<Input, Output>>:
  match closed:
    case Tuple{state, True{}}: (state, Some{Stopped{}})
    case Tuple{state, False{}}: (state, None{})

def advanceSelected(-Input: Type, -Output: Type, +state: State<Input, Output>, node: Node<Input, Output>, live: Bool, decision: DispatchDecision) -> State<Input, Output> & Maybe<&2, Advance<Input, Output>>:
  match node live decision:
    case _ _ StopDispatch{}: stoppedState(Input, Output, closeState(Input, Output, state))
    case Node{_, next} _ SkipListener{}: (state, Some{Advance{next, None{}}})
    case Node{_, next} False{} CallListener{}: (state, Some{Advance{next, None{}}})
    case Node{+registration, +next} True{} CallListener{}:
      (Bool.pick(State<Input, Output>, onceOnly(Input, Output, registration), removeNode(Input, Output, state, Node{registration, next}), state), Some{Advance{next, Some{registration}}})

def advanceCandidate(-Input: Type, -Output: Type, state: State<Input, Output>, node: Maybe<&2, Node<Input, Output>>, live: Bool, decide: Registration<Input, Output> -> DispatchDecision) -> State<Input, Output> & Maybe<&2, Advance<Input, Output>>:
  match node:
    case None{}: (state, None{})
    case Some{Node{+registration, next}}: advanceSelected(Input, Output, state, Node{registration, next}, live, decide(registration))

def advanceFound(-Input: Type, -Output: Type, state: State<Input, Output>, found: Maybe<&2, Node<Input, Output>>, retired: Maybe<&2, Node<Input, Output>>, decide: Registration<Input, Output> -> DispatchDecision) -> State<Input, Output> & Maybe<&2, Advance<Input, Output>>:
  match found:
    case Some{node}: advanceCandidate(Input, Output, state, Some{node}, True{}, decide)
    case None{}: advanceCandidate(Input, Output, state, retired, False{}, decide)

def advanceState(-Input: Type, -Output: Type, state: State<Input, Output>, +position: N.BigNat, decide: Registration<Input, Output> -> DispatchDecision) -> State<Input, Output> & Maybe<&2, Advance<Input, Output>>:
  match state:
    case State{key, walks, +live, +retired}:
      advanceFound(Input, Output, State{key, walks, live, retired}, findKey(Input, Output, live, position), findKey(Input, Output, retired, position), decide)

def advanced(-Input: Type, -Output: Type, registry: Registry<Input, Output>, value: Maybe<&2, Advance<Input, Output>>) -> IO(Step<Input, Output>):
  match value:
    case None{}: IO.die(Step<Input, Output>, 1, "listener registry: missing live traversal node")
    case Some{Stopped{}}: IO.pure(Step<Input, Output>, End{})
    case Some{Advance{next, listener}}: IO.pure(Step<Input, Output>, More{Cursor{registry, next}, listener})

# The EventTarget layer supplies a pure decision from its event flags. Evaluate
# it before once removal, including for retired nodes: skipping must not consume
# once, and stopping must close the walk without invoking or removing anything.
def nextWith(-Input: Type, -Output: Type, cursor: Cursor<Input, Output>, decide: Registration<Input, Output> -> DispatchDecision) -> IO(Step<Input, Output>):
  match cursor:
    case Cursor{registry, None{}}:
      do IO<Step<Input, Output>>:
        close(Input, Output, Cursor{registry, None{}})
        return End{}
    case Cursor{Registry{+state}, Some{position}}:
      do IO<Step<Input, Output>>:
        value : Maybe<&2, Advance<Input, Output>> <- R.modify(State<Input, Output>, Maybe<&2, Advance<Input, Output>>, state, current => advanceState(Input, Output, current, position, decide))
        advanced(Input, Output, Registry{state}, value)

# Normal traversal caches next and removes once before callback invocation.
def next(-Input: Type, -Output: Type, cursor: Cursor<Input, Output>) -> IO(Step<Input, Output>):
  nextWith(Input, Output, cursor, registration => CallListener{})

# Callbacks remain caller-owned. Dispose only after all cursor/registry aliases
# retire; removed nodes have already been reclaimed when the last walk closed.
def dispose(-Input: Type, -Output: Type, registry: Registry<Input, Output>) -> IO(Unit):
  match registry:
    case Registry{state}:
      do IO<Unit>:
        previous : State<Input, Output> <- R.dispose(State<Input, Output>, state)
        return Unit{}
