import Base
import ./abort-events.bend as Test
import ../src/abort.bend as A
import ../src/event-target.bend as T
import ../src/event.bend as E
import ../src/callback.bend as C
import ../src/ref.bend as R
import ../src/clock.bend as Clock
import ../src/listener-registry.bend as L

type Action is Data:
  Add{index: U32}
  Remove{index: U32}
  SetHandler{index: Maybe<&2, U32>}
  Fire{}
  Abort{}

type Environment is Data:
  Environment{target: Test.Signal(), log: R.Ref<List<&2, String>>, callbacks: R.Ref<List<&2, Test.ListenerValue()>>, mode: U32, index: U32}

def lookup(callbacks: List<&2, Test.ListenerValue()>, index: U32) -> IO(Test.ListenerValue()):
  match callbacks index:
    case Nil{} _: IO.die(Test.ListenerValue(), 1, "missing test callback")
    case head <> _ 0: IO.pure(Test.ListenerValue(), head)
    case _ <> tail n: lookup(tail, U32.sub(n, 1))

def applyMutation(target: Test.Signal(), mode: U32, index: U32, replacement: Test.ListenerValue()) -> IO(Unit):
  match mode index:
    case 1 0: A.setOnabort(U32, String, target, Some{replacement})
    case 2 0: A.setOnabort(U32, String, target, None{})
    case _ _: IO.pure(Unit, Unit{})

def outcome(mode: U32, index: U32) -> T.Output(String):
  match mode index:
    case 3 1: Fail{"handler failure"}
    case _ _: Done{Unit{}}

def body(environment: Environment, input: Test.Input()) -> IO(T.Output(String)):
  match environment input:
    case Environment{expected, +log, callbacks, +mode, +index} Tuple{+target, +event}:
      do IO<T.Output(String)>:
        Test.assertion(A.same(U32, String, target, expected), "onabort this lost signal identity")
        received : Maybe<&2, Test.Signal()> <- E.target(Test.Signal(), event)
        Test.assertion(Test.equalTarget(received, target), "onabort event target lost signal identity")
        phase : U32 <- E.eventPhase(Test.Signal(), event)
        current : Maybe<&2, Test.Signal()> <- E.currentTarget(Test.Signal(), event)
        Test.append(log, U32.show(index) ++ ":" ++ U32.show(phase) ++ ":" ++ Test.booleanText(Test.equalTarget(current, target)))
        values : List<&2, Test.ListenerValue()> <- R.read(List<&2, Test.ListenerValue()>, callbacks)
        replacement : Test.ListenerValue() <- lookup(values, 3)
        applyMutation(target, mode, index, replacement)
        return outcome(mode, index)

def identify(+callback: Test.ListenerValue(), callbacks: List<&2, Test.ListenerValue()>, +index: U32) -> String:
  match callbacks:
    case Nil{}: "unknown"
    case head <> tail: Bool.pick(String, C.same(Test.Input(), T.Output(String), callback, head), U32.show(index), identify(callback, tail, U32.add(index, 1)))

def getterText(value: Maybe<&2, Test.ListenerValue()>, callbacks: List<&2, Test.ListenerValue()>) -> String:
  match value:
    case None{}: "null"
    case Some{callback}: identify(callback, callbacks, 0)

def recordGetter(target: Test.Signal(), log: R.Ref<List<&2, String>>, callbacks: List<&2, Test.ListenerValue()>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2, Test.ListenerValue()> <- A.onabort(U32, String, target)
    Test.append(log, "get:" ++ getterText(value, callbacks))

def set(target: Test.Signal(), index: Maybe<&2, U32>, callbacks: List<&2, Test.ListenerValue()>) -> IO(Unit):
  match index:
    case None{}: A.setOnabort(U32, String, target, None{})
    case Some{number}:
      do IO<Unit>:
        callback : Test.ListenerValue() <- lookup(callbacks, number)
        A.setOnabort(U32, String, target, Some{callback})

def recordResult(log: R.Ref<List<&2, String>>, result: Result<&2, &2, E.DispatchError, Bool>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "onabort test dispatch failed")
    case Done{value}: Test.append(log, "result:" ++ Test.booleanText(value))

def act(action: Action, +target: Test.Signal(), clock: Clock.Clock, log: R.Ref<List<&2, String>>, callbacks: List<&2, Test.ListenerValue()>) -> IO(Unit):
  match action:
    case Add{index}:
      do IO<Unit>:
        callback : Test.ListenerValue() <- lookup(callbacks, index)
        A.addEventListener(U32, String, target, "abort", Some{callback}, L.Options{False{}, False{}, False{}})
    case Remove{index}:
      do IO<Unit>:
        callback : Test.ListenerValue() <- lookup(callbacks, index)
        A.removeEventListener(U32, String, target, "abort", Some{callback}, False{})
    case SetHandler{index}: set(target, index, callbacks)
    case Abort{}: A.abort(U32, String, A.AbortController{target}, Some{0})
    case Fire{}:
      do IO<Unit>:
        +event : Test.EventValue() <- E.new(Test.Signal(), clock, "abort", E.defaultInit())
        result : Result<&2, &2, E.DispatchError, Bool> <- A.dispatchEvent(U32, String, target, event)
        recordResult(log, result)
        E.dispose(Test.Signal(), event)

def execute(actions: List<&2, Action>, +target: Test.Signal(), +clock: Clock.Clock, +log: R.Ref<List<&2, String>>, +callbacks: List<&2, Test.ListenerValue()>) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit, Unit{})
    case action <> rest:
      do IO<Unit>:
        act(action, target, clock, log, callbacks)
        recordGetter(target, log, callbacks)
        execute(rest, target, clock, log, callbacks)

def disposeCallbacks(callbacks: List<&2, Test.ListenerValue()>) -> IO(Unit):
  match callbacks:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        C.dispose(Test.Input(), T.Output(String), head)
        disposeCallbacks(tail)

def run(+mode: U32, actions: List<&2, Action>, +expected: String, errors: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +clock : Clock.Clock <- Clock.new()
    +queue : T.ReportQueue<String> <- T.newReportQueue(String)
    +controller : A.AbortController<U32, String> <- A.new(~U32, ~String, clock, queue)
    +target : Test.Signal() = A.signal(U32, String, controller)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +pool : R.Ref<List<&2, Test.ListenerValue()>> <- R.new(List<&2, Test.ListenerValue()>, Nil{})
    a : Test.ListenerValue() <- C.create(~Environment, ~Test.Input(), ~T.Output(String), ~body, Environment{target, log, pool, mode, 0})
    b : Test.ListenerValue() <- C.create(~Environment, ~Test.Input(), ~T.Output(String), ~body, Environment{target, log, pool, mode, 1})
    c : Test.ListenerValue() <- C.create(~Environment, ~Test.Input(), ~T.Output(String), ~body, Environment{target, log, pool, mode, 2})
    d : Test.ListenerValue() <- C.create(~Environment, ~Test.Input(), ~T.Output(String), ~body, Environment{target, log, pool, mode, 3})
    +callbacks : List<&2, Test.ListenerValue()> = a <> b <> c <> d <> Nil{}
    R.write(List<&2, Test.ListenerValue()>, pool, callbacks)
    recordGetter(target, log, callbacks)
    execute(actions, target, clock, log, callbacks)
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    +actual : String = String.join(List.reverse(&2, String, recorded), "|")
    Test.assertion(String.eq(actual, expected), "onabort trace mismatch. Expected: " ++ expected ++ " Actual: " ++ actual)
    Test.checkErrors(queue, errors)
    A.dispose(U32, String, controller)
    disposeCallbacks(callbacks)
    oldPool : List<&2, Test.ListenerValue()> <- R.dispose(List<&2, Test.ListenerValue()>, pool)
    oldLog : List<&2, String> <- R.dispose(List<&2, String>, log)
    T.disposeReportQueue(String, queue)
