import Base
import ../src/event-target.bend as T
import ../src/event.bend as E
import ../src/clock.bend as Clock
import ../src/listener-registry.bend as L
import ../src/callback.bend as C
import ../src/ref.bend as R

type Mode is Data:
  Noop{}
  Cancel{}
  Stop{}
  ResetStop{}
  Immediate{}
  Throw{}
  Recursive{}

type Handler is Data:
  Handler{label: String, mode: Mode, log: R.Ref<List<&2, String>>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def append(log: R.Ref<List<&2, String>>, text: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, log, current => (text <> current, Unit{}))

def equalTarget(value: Maybe<&2, T.EventTarget<String>>, target: T.EventTarget<String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{actual}: T.same(String, actual, target)

def booleanText(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def render(properties: E.Properties<T.EventTarget<String>>, target: T.EventTarget<String>, label: String) -> String:
  match properties:
    case E.Properties{_, _, _, _, cancelled, _, _, current, _, phase, stopped, _, _, _}:
      label ++ ":" ++ U32.show(phase) ++ ":" ++ booleanText(cancelled) ++ ":" ++ booleanText(stopped) ++ ":" ++ booleanText(equalTarget(current, target))

def record(event: T.EventValue(String), target: T.EventTarget<String>, log: R.Ref<List<&2, String>>, label: String) -> IO(Unit):
  do IO<Unit>:
    view : E.Properties<T.EventTarget<String>> <- E.snapshot(T.EventTarget<String>, event)
    append(log, render(view, target, label))

def recursion(log: R.Ref<List<&2, String>>, result: Result<&2, &2, E.DispatchError, Bool>) -> IO(Unit):
  match result:
    case Done{_}: append(log, "recursive:succeeded")
    case Fail{error}: append(log, "recursive:" ++ E.errorCode(error))

def act(mode: Mode, label: String, target: T.EventTarget<String>, +event: T.EventValue(String), log: R.Ref<List<&2, String>>) -> IO(T.Output(String)):
  match mode:
    case Throw{}: IO.pure(T.Output(String), Fail{label})
    case Recursive{}:
      do IO<T.Output(String)>:
        result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEvent(String, target, event)
        recursion(log, result)
        return Done{Unit{}}
    case Cancel{}:
      do IO<T.Output(String)>:
        E.preventDefault(T.EventTarget<String>, event)
        return Done{Unit{}}
    case Stop{}:
      do IO<T.Output(String)>:
        E.stopPropagation(T.EventTarget<String>, event)
        return Done{Unit{}}
    case ResetStop{}:
      do IO<T.Output(String)>:
        E.setCancelBubble(T.EventTarget<String>, event, False{})
        return Done{Unit{}}
    case Immediate{}:
      do IO<T.Output(String)>:
        E.stopImmediatePropagation(T.EventTarget<String>, event)
        return Done{Unit{}}
    case Noop{}: IO.pure(T.Output(String), Done{Unit{}})

def after(result: T.Output(String), label: String, target: T.EventTarget<String>, event: T.EventValue(String), log: R.Ref<List<&2, String>>) -> IO(T.Output(String)):
  match result:
    case Fail{error}: IO.pure(T.Output(String), Fail{error})
    case Done{Unit{}}:
      do IO<T.Output(String)>:
        record(event, target, log, label ++ " after")
        return Done{Unit{}}

def body(handler: Handler, input: T.Input(String)) -> IO(T.Output(String)):
  match handler input:
    case Handler{+label, mode, +log} Tuple{+target, +event}:
      do IO<T.Output(String)>:
        actual : Maybe<&2, T.EventTarget<String>> <- E.target(T.EventTarget<String>, event)
        assertion(equalTarget(actual, target), "listener this must equal the live event target")
        record(event, target, log, label ++ " before")
        result : T.Output(String) <- act(mode, label, target, event, log)
        after(result, label, target, event, log)

def recordResult(log: R.Ref<List<&2, String>>, result: Result<&2, &2, E.DispatchError, Bool>) -> IO(Unit):
  match result:
    case Done{value}: append(log, "result:" ++ booleanText(value))
    case Fail{_}: IO.die(Unit, 1, "outer dispatch unexpectedly rejected")

def dispatchMany(count: Nat, +target: T.EventTarget<String>, +event: T.EventValue(String), +log: R.Ref<List<&2, String>>) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+ n:
      do IO<Unit>:
        result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEvent(String, target, event)
        recordResult(log, result)
        record(event, target, log, "end")
        dispatchMany(n, target, event, log)

def expectedError(actual: Maybe<&2, String>, expected: String) -> IO(Unit):
  match actual:
    case None{}: IO.die(Unit, 1, "listener error was lost")
    case Some{error}: assertion(String.eq(error, expected), "listener errors must retain FIFO order")

def checkErrors(+queue: T.ReportQueue<String>, expected: List<&2, String>) -> IO(Unit):
  match expected:
    case Nil{}:
      do IO<Unit>:
        actual : Maybe<&2, String> <- T.takeReportedError(String, queue)
        assertion(Maybe.is_none(&2, String, actual), "unexpected listener error")
    case error <> rest:
      do IO<Unit>:
        actual : Maybe<&2, String> <- T.takeReportedError(String, queue)
        expectedError(actual, error)
        checkErrors(queue, rest)

def run(first: Mode, second: Mode, passive: Bool, once: Bool, cancelable: Bool, repeat: Nat, expected: String, errors: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    clock : Clock.Clock <- Clock.new()
    +queue : T.ReportQueue<String> <- T.newReportQueue(String)
    +target : T.EventTarget<String> <- T.new(String, queue)
    +event : T.EventValue(String) <- E.new(T.EventTarget<String>, clock, "x", E.EventInit{False{}, cancelable, False{}})
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +a : T.EventListener(String) <- C.create(~Handler, ~T.Input(String), ~T.Output(String), ~body, Handler{"a", first, log})
    +b : T.EventListener(String) <- C.create(~Handler, ~T.Input(String), ~T.Output(String), ~body, Handler{"b", second, log})
    T.addEventListener(String, target, "x", None{}, L.Options{False{}, False{}, False{}})
    T.removeEventListener(String, target, "x", None{}, False{})
    T.addEventListener(String, target, "x", Some{a}, L.Options{False{}, once, passive})
    T.addEventListener(String, target, "x", Some{b}, L.Options{False{}, False{}, False{}})
    dispatchMany(repeat, target, event, log)
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    assertion(String.eq(String.join(List.reverse(&2, String, recorded), "|"), expected), "EventTarget trace differs from Node")
    checkErrors(queue, errors)
    E.dispose(T.EventTarget<String>, event)
    T.dispose(String, target)
    C.dispose(T.Input(String), T.Output(String), a)
    C.dispose(T.Input(String), T.Output(String), b)
    T.disposeReportQueue(String, queue)
    previous : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}

# Errors from different targets share runtime reporting order. Disposing one
# target must not close the queue or erase an error awaiting deferred delivery.
def sharedReports() -> IO(Unit):
  do IO<Unit>:
    +clock : Clock.Clock <- Clock.new()
    +queue : T.ReportQueue<String> <- T.newReportQueue(String)
    +first : T.EventTarget<String> <- T.new(String, queue)
    +second : T.EventTarget<String> <- T.new(String, queue)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +a : T.EventListener(String) <- C.create(~Handler, ~T.Input(String), ~T.Output(String), ~body, Handler{"a", Throw{}, log})
    +b : T.EventListener(String) <- C.create(~Handler, ~T.Input(String), ~T.Output(String), ~body, Handler{"b", Throw{}, log})
    T.addEventListener(String, first, "x", Some{a}, L.Options{False{}, False{}, False{}})
    T.addEventListener(String, second, "x", Some{b}, L.Options{False{}, False{}, False{}})
    +event : T.EventValue(String) <- E.new(T.EventTarget<String>, clock, "x", E.defaultInit())
    result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEvent(String, first, event)
    recordResult(log, result)
    E.dispose(T.EventTarget<String>, event)
    T.dispose(String, first)
    C.dispose(T.Input(String), T.Output(String), a)
    +event : T.EventValue(String) <- E.new(T.EventTarget<String>, clock, "x", E.defaultInit())
    result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEvent(String, second, event)
    recordResult(log, result)
    E.dispose(T.EventTarget<String>, event)
    T.dispose(String, second)
    C.dispose(T.Input(String), T.Output(String), b)
    checkErrors(queue, "a" <> "b" <> Nil{})
    T.disposeReportQueue(String, queue)
    previous : List<&2, String> <- R.dispose(List<&2, String>, log)
    IO.print("PASS shared reporting queue survives target disposal and preserves cross-target order")
