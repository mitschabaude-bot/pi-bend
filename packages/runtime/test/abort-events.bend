import Base
import ../src/abort.bend as A
import ../src/event-target.bend as T
import ../src/event.bend as E
import ../src/clock.bend as Clock
import ../src/listener-registry.bend as L
import ../src/callback.bend as C
import ../src/ref.bend as R

def Signal() -> Data: A.AbortSignal<U32, String>
def EventValue() -> Data: E.WebEvent<Signal()>
def Input() -> Type: T.HostInput(Signal())
def ListenerValue() -> Data: T.HostListener(Signal(), String)

type Handler is Data:
  Handler{controller: A.AbortController<U32, String>, label: String, mode: U32, log: R.Ref<List<&2, String>>, retained: R.Ref<Maybe<&2, EventValue()>>, second: Maybe<&2, ListenerValue()>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def booleanText(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def append(log: R.Ref<List<&2, String>>, text: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, log, current => (text <> current, Unit{}))

def equalTarget(value: Maybe<&2, Signal()>, target: Signal()) -> Bool:
  match value:
    case None{}: False{}
    case Some{actual}: A.same(U32, String, actual, target)

def render(view: E.Properties<Signal()>, +target: Signal(), label: String) -> String:
  match view:
    case E.Properties{eventType, bubbles, cancelable, composed, prevented, _, received, current, _, phase, _, _, trusted, _}:
      label ++ ":" ++ eventType ++ ":" ++ booleanText(trusted) ++ ":" ++ booleanText(bubbles) ++ ":" ++ booleanText(cancelable) ++ ":" ++ booleanText(composed) ++ ":" ++ booleanText(prevented) ++ ":" ++ U32.show(phase) ++ ":" ++ booleanText(equalTarget(current, target)) ++ ":" ++ booleanText(equalTarget(received, target))

def record(event: EventValue(), target: Signal(), log: R.Ref<List<&2, String>>, label: String) -> IO(Unit):
  do IO<Unit>:
    view : E.Properties<Signal()> <- E.snapshot(Signal(), event)
    append(log, render(view, target, label))

def showReason(value: Maybe<&2, A.AbortReason<U32>>) -> String:
  match value:
    case None{}: "none"
    case Some{A.Supplied{number}}: U32.show(number)
    case Some{A.DefaultAbort{_}}: "unexpected default"

def state(+target: Signal(), log: R.Ref<List<&2, String>>, label: String) -> IO(Unit):
  do IO<Unit>:
    isAborted : Bool <- A.aborted(U32, String, target)
    why : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, String, target)
    append(log, label ++ ":" ++ booleanText(isAborted) ++ ":" ++ showReason(why))

def retain(event: EventValue(), retained: R.Ref<Maybe<&2, EventValue()>>, trusted: Bool) -> IO(Unit):
  match trusted:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: R.write(Maybe<&2, EventValue()>, retained, Some{event})

def action(mode: U32, controller: A.AbortController<U32, String>, +target: Signal(), event: EventValue(), log: R.Ref<List<&2, String>>, second: Maybe<&2, ListenerValue()>) -> IO(T.Output(String)):
  match mode:
    case 1: IO.pure(T.Output(String), Fail{"a failure"})
    case 2:
      do IO<T.Output(String)>:
        E.stopImmediatePropagation(Signal(), event)
        return Done{Unit{}}
    case 3:
      do IO<T.Output(String)>:
        A.abort(U32, String, controller, Some{99})
        state(target, log, "reentrant")
        return Done{Unit{}}
    case 5:
      do IO<T.Output(String)>:
        A.removeEventListener(U32, String, target, "abort", second, False{})
        return Done{Unit{}}
    case _: IO.pure(T.Output(String), Done{Unit{}})

def first(isFirst: Bool, mode: U32, controller: A.AbortController<U32, String>, target: Signal(), +event: EventValue(), log: R.Ref<List<&2, String>>, second: Maybe<&2, ListenerValue()>) -> IO(T.Output(String)):
  match isFirst:
    case False{}: IO.pure(T.Output(String), Done{Unit{}})
    case True{}:
      do IO<T.Output(String)>:
        E.preventDefault(Signal(), event)
        action(mode, controller, target, event, log, second)

def body(handler: Handler, input: Input()) -> IO(T.Output(String)):
  match handler input:
    case Handler{+controller, +label, mode, +log, retained, second} Tuple{+target, +event}:
      do IO<T.Output(String)>:
        assertion(A.same(U32, String, target, A.signal(U32, String, controller)), "abort listener this lost full signal identity")
        actual : Maybe<&2, Signal()> <- E.target(Signal(), event)
        assertion(equalTarget(actual, target), "abort event target lost signal identity")
        trusted : Bool <- E.isTrusted(Signal(), event)
        retain(event, retained, trusted && String.eq(label, "a"))
        record(event, target, log, label)
        state(target, log, label ++ " state")
        first(String.eq(label, "a"), mode, controller, target, event, log, second)

def manualResult(log: R.Ref<List<&2, String>>, result: Result<&2, &2, E.DispatchError, Bool>) -> IO(Unit):
  match result:
    case Done{value}: append(log, "manual:" ++ booleanText(value))
    case Fail{_}: IO.die(Unit, 1, "manual signal dispatch failed")

def manual(mode: U32, +target: Signal(), clock: Clock.Clock, +log: R.Ref<List<&2, String>>) -> IO(Unit):
  match mode:
    case 4:
      do IO<Unit>:
        +event : EventValue() <- E.new(Signal(), clock, "abort", E.defaultInit())
        result : Result<&2, &2, E.DispatchError, Bool> <- A.dispatchEvent(U32, String, target, event)
        manualResult(log, result)
        state(target, log, "after manual")
        E.dispose(Signal(), event)
    case _: IO.pure(Unit, Unit{})

def recordRetained(value: Maybe<&2, EventValue()>, target: Signal(), log: R.Ref<List<&2, String>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{event}: record(event, target, log, "retained")

def expectedError(actual: Maybe<&2, String>, expected: String) -> IO(Unit):
  match actual:
    case None{}: IO.die(Unit, 1, "abort listener error lost")
    case Some{error}: assertion(String.eq(error, expected), "abort listener error changed")

def checkErrors(+queue: T.ReportQueue<String>, expected: List<&2, String>) -> IO(Unit):
  match expected:
    case Nil{}:
      do IO<Unit>:
        actual : Maybe<&2, String> <- T.takeReportedError(String, queue)
        assertion(Maybe.is_none(&2, String, actual), "unexpected abort listener error")
    case error <> rest:
      do IO<Unit>:
        actual : Maybe<&2, String> <- T.takeReportedError(String, queue)
        expectedError(actual, error)
        checkErrors(queue, rest)

def run(+mode: U32, once: Bool, passive: Bool, +expected: String, errors: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +clock : Clock.Clock <- Clock.new()
    +queue : T.ReportQueue<String> <- T.newReportQueue(String)
    +controller : A.AbortController<U32, String> <- A.new(U32, String, clock, queue)
    +target : Signal() = A.signal(U32, String, controller)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +retained : R.Ref<Maybe<&2, EventValue()>> <- R.new(Maybe<&2, EventValue()>, None{})
    +b : ListenerValue() <- C.create(~Handler, ~Input(), ~T.Output(String), ~body, Handler{controller, "b", 0, log, retained, None{}})
    +a : ListenerValue() <- C.create(~Handler, ~Input(), ~T.Output(String), ~body, Handler{controller, "a", mode, log, retained, Some{b}})
    +late : ListenerValue() <- C.create(~Handler, ~Input(), ~T.Output(String), ~body, Handler{controller, "late", 0, log, retained, None{}})
    A.addEventListener(U32, String, target, "abort", Some{a}, L.Options{False{}, once, passive})
    A.addEventListener(U32, String, target, "abort", Some{b}, L.Options{False{}, False{}, False{}})
    state(target, log, "before")
    manual(mode, target, clock, log)
    A.abort(U32, String, controller, Some{0})
    state(target, log, "after")
    A.abort(U32, String, controller, Some{99})
    A.abort(U32, String, controller, None{})
    state(target, log, "repeat")
    A.addEventListener(U32, String, target, "abort", Some{late}, L.Options{False{}, False{}, False{}})
    A.abort(U32, String, controller, Some{100})
    state(target, log, "late registration")
    saved : Maybe<&2, EventValue()> <- R.read(Maybe<&2, EventValue()>, retained)
    recordRetained(saved, target, log)
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    +actualTrace : String = String.join(List.reverse(&2, String, recorded), "|")
    assertion(String.eq(actualTrace, expected), "AbortSignal trace differs. Expected: " ++ expected ++ " Actual: " ++ actualTrace)
    checkErrors(queue, errors)
    C.dispose(Input(), T.Output(String), a)
    C.dispose(Input(), T.Output(String), b)
    C.dispose(Input(), T.Output(String), late)
    oldEvent : Maybe<&2, EventValue()> <- R.dispose(Maybe<&2, EventValue()>, retained)
    A.dispose(U32, String, controller)
    T.disposeReportQueue(String, queue)
    previous : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}

# Concurrent native abort attempts must settle and dispatch exactly once, even
# with a callback reentering abort. This supplements the single-threaded oracle.
def countCallback(counter: R.Ref<U32>, input: Input()) -> IO(T.Output(String)):
  match input:
    case Tuple{+target, +event}:
      do IO<T.Output(String)>:
        settled : Bool <- A.aborted(U32, String, target)
        assertion(settled, "abort listener ran before state settlement")
        actual : Maybe<&2, Signal()> <- E.target(Signal(), event)
        assertion(equalTarget(actual, target), "concurrent dispatch lost signal identity")
        trusted : Bool <- E.isTrusted(Signal(), event)
        assertion(trusted, "controller abort event must be trusted")
        A.abort(U32, String, A.AbortController{target}, Some{1000})
        R.modify(U32, Unit, counter, value => (U32.add(value, 1), Unit{}))
        return Done{Unit{}}

def abortMany(count: Nat, +controller: A.AbortController<U32, String>) -> IO(List<&2, Chan(Unit)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(Unit)>, Nil{})
    case 1n+ +n:
      do IO<List<&2, Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit, A.abort(U32, String, controller, Some{U32.from_nat(n)}))
        tail : List<&2, Chan(Unit)> <- abortMany(n, controller)
        return task <> tail

def joinAll(tasks: List<&2, Chan(Unit)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        result : Unit <- IO.join(Unit, head)
        joinAll(tail)

def concurrent() -> IO(Unit):
  do IO<Unit>:
    +clock : Clock.Clock <- Clock.new()
    +queue : T.ReportQueue<String> <- T.newReportQueue(String)
    +controller : A.AbortController<U32, String> <- A.new(U32, String, clock, queue)
    +other : A.AbortController<U32, String> <- A.new(U32, String, clock, queue)
    +target : Signal() = A.signal(U32, String, controller)
    assertion(Bool.not(A.same(U32, String, target, A.signal(U32, String, other))), "distinct signals must have distinct identities")
    +counter : R.Ref<U32> <- R.new(U32, 0)
    +callback : ListenerValue() <- C.create(~R.Ref<U32>, ~Input(), ~T.Output(String), ~countCallback, counter)
    A.addEventListener(U32, String, target, "abort", Some{callback}, L.Options{False{}, False{}, False{}})
    tasks : List<&2, Chan(Unit)> <- abortMany(100n, controller)
    joinAll(tasks)
    called : U32 <- R.read(U32, counter)
    assertion(U32.is_eq(called, 1), "competing abort calls must dispatch exactly once")
    checkErrors(queue, Nil{})
    C.dispose(Input(), T.Output(String), callback)
    A.dispose(U32, String, controller)
    A.dispose(U32, String, other)
    T.disposeReportQueue(String, queue)
    previous : U32 <- R.dispose(U32, counter)
    IO.print("PASS 100 competing aborts dispatch once with reentrant listener")
