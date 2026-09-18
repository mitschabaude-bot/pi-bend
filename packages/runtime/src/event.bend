import Base
import ./ref.bend as R
import ./f64.bend as F
import ./utf16.bend as U

# Node Event state. Construction with a supplied monotonic timestamp is internal;
# the public clock-backed constructor and complete EventTarget are still pending.
type EventInit is Data:
  EventInit{bubbles: Bool, cancelable: Bool, composed: Bool}

type Description is Data:
  Description{eventType: String, init: EventInit, timeStamp: F.F64, isTrusted: Bool}

type Location<-Target: Data> is Data:
  Location{target: Maybe<&2, Target>, dispatching: Bool, passive: Bool}

type Flags is Data:
  Flags{cancelled: Bool, propagationStopped: Bool, immediateStopped: Bool}

type State<-Target: Data> is Data:
  State{description: Description, location: Location<Target>, flags: Flags}

type WebEvent<-Target: Data> is Data:
  WebEvent{state: R.Ref<State<Target>>}

type Properties<-Target: Data> is Data:
  Properties{eventType: String, bubbles: Bool, cancelable: Bool, composed: Bool, defaultPrevented: Bool, timeStamp: F.F64, target: Maybe<&2, Target>, currentTarget: Maybe<&2, Target>, srcElement: Maybe<&2, Target>, eventPhase: U32, cancelBubble: Bool, returnValue: Bool, isTrusted: Bool, composedPath: List<&2, Target>}

type DispatchError is Data:
  EventRecursion{eventType: String}

def NONE() -> U32: 0
def CAPTURING_PHASE() -> U32: 1
def AT_TARGET() -> U32: 2
def BUBBLING_PHASE() -> U32: 3

def defaultInit() -> EventInit: EventInit{False{}, False{}, False{}}

def createAt(-Target: Data, eventType: String, init: EventInit, timeStamp: F.F64, trusted: Bool) -> IO(WebEvent<Target>):
  do IO<WebEvent<Target>>:
    state : R.Ref<State<Target>> <- R.new(State<Target>, State{Description{U.normalize(eventType), init, timeStamp, trusted}, Location{None{}, False{}, False{}}, Flags{False{}, False{}, False{}}})
    return WebEvent{state}

def same(-Target: Data, left: WebEvent<Target>, right: WebEvent<Target>) -> Bool:
  match left right:
    case WebEvent{a} WebEvent{b}: R.same(State<Target>, a, b)

def path(-Target: Data, target: Maybe<&2, Target>, dispatching: Bool) -> List<&2, Target>:
  match target dispatching:
    case Some{value} True{}: value <> Nil{}
    case _ _: Nil{}

def properties(-Target: Data, state: State<Target>) -> Properties<Target>:
  match state:
    case State{Description{eventType, EventInit{bubbles, +cancelable, composed}, timeStamp, trusted}, Location{+target, +dispatching, _}, Flags{+cancelled, stopped, _}}:
      Properties{eventType, bubbles, cancelable, composed, cancelable && cancelled, timeStamp, target, Bool.pick(Maybe<&2, Target>, dispatching, target, None{}), target, Bool.pick(U32, dispatching, AT_TARGET(), NONE()), stopped, Bool.not(cancelable && cancelled), trusted, path(Target, target, dispatching)}

def snapshot(-Target: Data, event: WebEvent<Target>) -> IO(Properties<Target>):
  match event:
    case WebEvent{state}:
      do IO<Properties<Target>>:
        current : State<Target> <- R.read(State<Target>, state)
        return properties(Target, current)

# Legacy initEvent changes only type/bubbles/cancelable when not dispatching.
# In Node it preserves cancellation, stop flags, composed, timestamp and target.
def initialize(-Target: Data, state: State<Target>, eventType: String, bubbles: Bool, cancelable: Bool) -> State<Target>:
  match state:
    case State{description, Location{target, True{}, passive}, flags}: State{description, Location{target, True{}, passive}, flags}
    case State{Description{_, EventInit{_, _, composed}, stamp, trusted}, location, flags}: State{Description{eventType, EventInit{bubbles, cancelable, composed}, stamp, trusted}, location, flags}

def initEvent(-Target: Data, event: WebEvent<Target>, eventType: String, bubbles: Bool, cancelable: Bool) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (initialize(Target, current, U.normalize(eventType), bubbles, cancelable), Unit{}))

def preventState(-Target: Data, state: State<Target>) -> State<Target>:
  match state:
    case State{Description{eventType, EventInit{bubbles, +cancelable, composed}, stamp, trusted}, Location{target, dispatching, +passive}, Flags{cancelled, stopped, immediate}}:
      State{Description{eventType, EventInit{bubbles, cancelable, composed}, stamp, trusted}, Location{target, dispatching, passive}, Flags{cancelled || (cancelable && Bool.not(passive)), stopped, immediate}}

def preventDefault(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (preventState(Target, current), Unit{}))

def setReturnValue(-Target: Data, event: WebEvent<Target>, value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: preventDefault(Target, event)

def stopState(-Target: Data, state: State<Target>, immediately: Bool) -> State<Target>:
  match state:
    case State{description, location, Flags{cancelled, _, immediate}}: State{description, location, Flags{cancelled, True{}, immediate || immediately}}

def stopPropagation(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (stopState(Target, current, False{}), Unit{}))

def stopImmediatePropagation(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (stopState(Target, current, True{}), Unit{}))

def setCancelBubble(-Target: Data, event: WebEvent<Target>, value: Bool) -> IO(Unit):
  match value:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: stopPropagation(Target, event)

def recursionMessage(error: DispatchError) -> String:
  match error:
    case EventRecursion{eventType}: "The event \"" ++ eventType ++ "\" is already being dispatched"

# Failed recursive dispatch leaves the original target and flags untouched.
def beginState(-Target: Data, state: State<Target>, target: Target) -> State<Target> & Result<&2, &2, DispatchError, Unit>:
  match state:
    case State{Description{+eventType, init, stamp, trusted}, Location{previous, True{}, passive}, flags}:
      (State{Description{eventType, init, stamp, trusted}, Location{previous, True{}, passive}, flags}, Fail{EventRecursion{eventType}})
    case State{description, Location{_, False{}, passive}, flags}:
      (State{description, Location{Some{target}, True{}, passive}, flags}, Done{Unit{}})

def beginDispatch(-Target: Data, event: WebEvent<Target>, target: Target) -> IO(Result<&2, &2, DispatchError, Unit>):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Result<&2, &2, DispatchError, Unit>, state, current => beginState(Target, current, target))

def dispatchFinished(-Target: Data, state: State<Target>) -> State<Target>:
  match state:
    case State{description, Location{target, _, passive}, flags}: State{description, Location{target, False{}, passive}, flags}

def finishDispatch(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (dispatchFinished(Target, current), Unit{}))

# Node clears this flag after a successful callback return, but not on a throw.
# Entering a subsequent listener does not restore it. Final dispatch exit clears
# it regardless. Error reporting belongs to EventTarget, outside these hooks.
def listenerReturned(-Target: Data, event: WebEvent<Target>) -> IO(Unit): finishDispatch(Target, event)

def passiveState(-Target: Data, state: State<Target>, value: Bool) -> State<Target>:
  match state:
    case State{description, Location{target, dispatching, _}, flags}: State{description, Location{target, dispatching, value}, flags}

def enterListener(-Target: Data, event: WebEvent<Target>, passive: Bool) -> IO(Unit):
  match event passive:
    case _ False{}: IO.pure(Unit, Unit{})
    case WebEvent{state} True{}: R.modify(State<Target>, Unit, state, current => (passiveState(Target, current, True{}), Unit{}))

def leaveListener(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}: R.modify(State<Target>, Unit, state, current => (passiveState(Target, current, False{}), Unit{}))

def immediateFlag(-Target: Data, state: State<Target>) -> Bool:
  match state:
    case State{_, _, Flags{_, _, immediate}}: immediate

def immediatePropagationStopped(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  match event:
    case WebEvent{state}:
      do IO<Bool>:
        current : State<Target> <- R.read(State<Target>, state)
        return immediateFlag(Target, current)

def dispose(-Target: Data, event: WebEvent<Target>) -> IO(Unit):
  match event:
    case WebEvent{state}:
      do IO<Unit>:
        previous : State<Target> <- R.dispose(State<Target>, state)
        return Unit{}

# Read-only property accessors. Bend reserves type and already defines Event
# for window input, so the corresponding names are eventType and WebEvent.

def propertyEventType(-Target: Data, properties: Properties<Target>) -> String:
  match properties:
    case Properties{value, _, _, _, _, _, _, _, _, _, _, _, _, _}: value

def eventType(-Target: Data, event: WebEvent<Target>) -> IO(String):
  do IO<String>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyEventType(Target, view)

def propertyBubbles(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, value, _, _, _, _, _, _, _, _, _, _, _, _}: value

def bubbles(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyBubbles(Target, view)

def propertyCancelable(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, value, _, _, _, _, _, _, _, _, _, _, _}: value

def cancelable(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyCancelable(Target, view)

def propertyComposed(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, _, value, _, _, _, _, _, _, _, _, _, _}: value

def composed(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyComposed(Target, view)

def propertyDefaultPrevented(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, _, _, value, _, _, _, _, _, _, _, _, _}: value

def defaultPrevented(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyDefaultPrevented(Target, view)

def propertyTimeStamp(-Target: Data, properties: Properties<Target>) -> F.F64:
  match properties:
    case Properties{_, _, _, _, _, value, _, _, _, _, _, _, _, _}: value

def timeStamp(-Target: Data, event: WebEvent<Target>) -> IO(F.F64):
  do IO<F.F64>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyTimeStamp(Target, view)

def propertyTarget(-Target: Data, properties: Properties<Target>) -> Maybe<&2, Target>:
  match properties:
    case Properties{_, _, _, _, _, _, value, _, _, _, _, _, _, _}: value

def target(-Target: Data, event: WebEvent<Target>) -> IO(Maybe<&2, Target>):
  do IO<Maybe<&2, Target>>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyTarget(Target, view)

def propertyCurrentTarget(-Target: Data, properties: Properties<Target>) -> Maybe<&2, Target>:
  match properties:
    case Properties{_, _, _, _, _, _, _, value, _, _, _, _, _, _}: value

def currentTarget(-Target: Data, event: WebEvent<Target>) -> IO(Maybe<&2, Target>):
  do IO<Maybe<&2, Target>>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyCurrentTarget(Target, view)

def propertySrcElement(-Target: Data, properties: Properties<Target>) -> Maybe<&2, Target>:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, value, _, _, _, _, _}: value

def srcElement(-Target: Data, event: WebEvent<Target>) -> IO(Maybe<&2, Target>):
  do IO<Maybe<&2, Target>>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertySrcElement(Target, view)

def propertyEventPhase(-Target: Data, properties: Properties<Target>) -> U32:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, _, value, _, _, _, _}: value

def eventPhase(-Target: Data, event: WebEvent<Target>) -> IO(U32):
  do IO<U32>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyEventPhase(Target, view)

def propertyCancelBubble(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, _, _, value, _, _, _}: value

def cancelBubble(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyCancelBubble(Target, view)

def propertyReturnValue(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, _, _, _, value, _, _}: value

def returnValue(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyReturnValue(Target, view)

def propertyIsTrusted(-Target: Data, properties: Properties<Target>) -> Bool:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, _, _, _, _, value, _}: value

def isTrusted(-Target: Data, event: WebEvent<Target>) -> IO(Bool):
  do IO<Bool>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyIsTrusted(Target, view)

def propertyComposedPath(-Target: Data, properties: Properties<Target>) -> List<&2, Target>:
  match properties:
    case Properties{_, _, _, _, _, _, _, _, _, _, _, _, _, value}: value

def composedPath(-Target: Data, event: WebEvent<Target>) -> IO(List<&2, Target>):
  do IO<List<&2, Target>>:
    view : Properties<Target> <- snapshot(Target, event)
    return propertyComposedPath(Target, view)

def errorName(error: DispatchError) -> String: "Error"
def errorCode(error: DispatchError) -> String: "ERR_EVENT_RECURSION"
