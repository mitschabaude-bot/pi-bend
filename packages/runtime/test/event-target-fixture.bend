import Base
import ../src/event-target.bend as T
import ../src/event.bend as E
import ../src/clock.bend as Clock
import ../src/listener-registry.bend as L
import ../src/callback.bend as C
import ../src/ref.bend as R

# Same Node action fixtures, now exercising the production EventTarget dispatcher.
type Action is Data:
  Add{eventType: String, callback: Nat, options: L.Options}
  Remove{eventType: String, callback: Nat, capture: Bool}
  Dispatch{eventType: String}

type CallbackSpec is Data:
  CallbackSpec{label: String, actions: List<&2, Action>}

type Context is Data:
  Context{target: T.EventTarget<String>, clock: Clock.Clock, log: R.Ref<List<&2, String>>, callbacks: R.Ref<List<&2, T.EventListener(String)>>}

type Environment is Data:
  Environment{context: Context, label: String, actions: List<&2, Action>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def callbackFound(found: Maybe<&2, T.EventListener(String)>) -> IO(T.EventListener(String)):
  match found:
    case Some{callback}: IO.pure(T.EventListener(String), callback)
    case None{}: IO.die(T.EventListener(String), 1, "fixture callback missing")

def callbackAt(context: Context, index: Nat) -> IO(T.EventListener(String)):
  match context:
    case Context{_, _, _, callbacks}:
      do IO<T.EventListener(String)>:
        values : List<&2, T.EventListener(String)> <- R.read(List<&2, T.EventListener(String)>, callbacks)
        callbackFound(List.get(&2, T.EventListener(String), values, index))

def requireSuccess(result: Result<&2, &2, E.DispatchError, Bool>) -> IO(Unit):
  match result:
    case Done{True{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "non-cancelling dispatch must succeed")

def dispatch(target: T.EventTarget<String>, clock: Clock.Clock, eventType: String) -> IO(Unit):
  do IO<Unit>:
    +event : T.EventValue(String) <- E.new(T.EventTarget<String>, clock, eventType, E.defaultInit())
    result : Result<&2, &2, E.DispatchError, Bool> <- T.dispatchEvent(String, target, event)
    requireSuccess(result)
    E.dispose(T.EventTarget<String>, event)

def runAction(context: Context, action: Action) -> IO(Unit):
  match context action:
    case Context{+target, clock, log, callbacks} Add{eventType, index, options}:
      do IO<Unit>:
        callback : T.EventListener(String) <- callbackAt(Context{target, clock, log, callbacks}, index)
        T.addEventListener(String, target, eventType, Some{callback}, options)
    case Context{+target, clock, log, callbacks} Remove{eventType, index, capture}:
      do IO<Unit>:
        callback : T.EventListener(String) <- callbackAt(Context{target, clock, log, callbacks}, index)
        T.removeEventListener(String, target, eventType, Some{callback}, capture)
    case Context{target, clock, _, _} Dispatch{eventType}: dispatch(target, clock, eventType)

def runActions(+context: Context, actions: List<&2, Action>) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit, Unit{})
    case action <> rest:
      do IO<Unit>:
        runAction(context, action)
        runActions(context, rest)

def body(environment: Environment, input: T.Input(String)) -> IO(T.Output(String)):
  match environment input:
    case Environment{Context{+target, clock, +log, callbacks}, label, actions} Tuple{this, _}:
      do IO<T.Output(String)>:
        assertion(T.same(String, target, this), "callback this must be the dispatch target")
        R.modify(List<&2, String>, Unit, log, current => (label <> current, Unit{}))
        runActions(Context{target, clock, log, callbacks}, actions)
        return Done{Unit{}}

def makeCallbacks(+context: Context, specs: List<&2, CallbackSpec>) -> IO(List<&2, T.EventListener(String)>):
  match specs:
    case Nil{}: IO.pure(List<&2, T.EventListener(String)>, Nil{})
    case CallbackSpec{label, actions} <> rest:
      do IO<List<&2, T.EventListener(String)>>:
        callback : T.EventListener(String) <- C.create(~Environment, ~T.Input(String), ~T.Output(String), ~body, Environment{context, label, actions})
        tail : List<&2, T.EventListener(String)> <- makeCallbacks(context, rest)
        return callback <> tail

def disposeCallbacks(callbacks: List<&2, T.EventListener(String)>) -> IO(Unit):
  match callbacks:
    case Nil{}: IO.pure(Unit, Unit{})
    case callback <> rest:
      do IO<Unit>:
        C.dispose(T.Input(String), T.Output(String), callback)
        disposeCallbacks(rest)

def run(name: String, specs: List<&2, CallbackSpec>, actions: List<&2, Action>, expected: String) -> IO(Unit):
  do IO<Unit>:
    clock : Clock.Clock <- Clock.new()
    +reports : T.ReportQueue<String> <- T.newReportQueue(String)
    +target : T.EventTarget<String> <- T.new(String, reports)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +callbacks : R.Ref<List<&2, T.EventListener(String)>> <- R.new(List<&2, T.EventListener(String)>, Nil{})
    +context : Context = Context{target, clock, log, callbacks}
    values : List<&2, T.EventListener(String)> <- makeCallbacks(context, specs)
    R.write(List<&2, T.EventListener(String)>, callbacks, values)
    runActions(context, actions)
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    assertion(String.eq(String.join(List.reverse(&2, String, recorded), ","), expected), name)
    error : Maybe<&2, String> <- T.takeReportedError(String, reports)
    assertion(Maybe.is_none(&2, String, error), "unexpected listener failure")
    T.dispose(String, target)
    owned : List<&2, T.EventListener(String)> <- R.dispose(List<&2, T.EventListener(String)>, callbacks)
    disposeCallbacks(owned)
    T.disposeReportQueue(String, reports)
    previous : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}
