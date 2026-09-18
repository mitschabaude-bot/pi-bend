import Base
import ../src/listener-registry.bend as L
import ../src/callback.bend as C
import ../src/ref.bend as R

# Actions and expected traces come from the actual Node EventTarget oracle.
type Action is Data:
  Add{eventType: String, callback: Nat, options: L.Options}
  Remove{eventType: String, callback: Nat, capture: Bool}
  Dispatch{eventType: String}

type CallbackSpec is Data:
  CallbackSpec{label: String, actions: List<&2, Action>}

type Context is Data:
  Context{registry: L.Registry<String, Unit>, log: R.Ref<List<&2, String>>, callbacks: R.Ref<List<&2, C.Callback<String, Unit>>>}

type Environment is Data:
  Environment{context: Context, label: String, actions: List<&2, Action>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def callbackFound(found: Maybe<&2, C.Callback<String, Unit>>) -> IO(C.Callback<String, Unit>):
  match found:
    case Some{callback}: IO.pure(C.Callback<String, Unit>, callback)
    case None{}: IO.die(C.Callback<String, Unit>, 1, "fixture callback missing")

def callbackAt(context: Context, index: Nat) -> IO(C.Callback<String, Unit>):
  match context:
    case Context{_, _, callbacks}:
      do IO<C.Callback<String, Unit>>:
        values : List<&2, C.Callback<String, Unit>> <- R.read(List<&2, C.Callback<String, Unit>>, callbacks)
        callbackFound(List.get(&2, C.Callback<String, Unit>, values, index))

def invoke(listener: Maybe<&2, L.Registration<String, Unit>>, eventType: String) -> IO(Unit):
  match listener:
    case None{}: IO.pure(Unit, Unit{})
    case Some{L.Registration{_, _, callback, _}}: C.call(String, Unit, callback, eventType)

# A callback can append more listeners, so a traversal has no structural bound.
# Every iteration performs an IO step. No artificial fuel truncates dispatch.
@unsafe def drain(step: L.Step<String, Unit>, +eventType: String) -> IO(Unit):
  match step:
    case L.End{}: IO.pure(Unit, Unit{})
    case L.More{cursor, listener}:
      do IO<Unit>:
        invoke(listener, eventType)
        next : L.Step<String, Unit> <- L.next(String, Unit, cursor)
        drain(next, eventType)

def dispatch(registry: L.Registry<String, Unit>, +eventType: String) -> IO(Unit):
  do IO<Unit>:
    cursor : L.Cursor<String, Unit> <- L.begin(String, Unit, registry, eventType)
    step : L.Step<String, Unit> <- L.next(String, Unit, cursor)
    drain(step, eventType)

def runAction(+context: Context, action: Action) -> IO(Unit):
  match context action:
    case Context{registry, log, callbacks} Add{eventType, index, options}:
      do IO<Unit>:
        callback : C.Callback<String, Unit> <- callbackAt(Context{registry, log, callbacks}, index)
        added : Bool <- L.add(String, Unit, registry, eventType, callback, options)
        return Unit{}
    case Context{registry, log, callbacks} Remove{eventType, index, capture}:
      do IO<Unit>:
        callback : C.Callback<String, Unit> <- callbackAt(Context{registry, log, callbacks}, index)
        removed : Bool <- L.remove(String, Unit, registry, eventType, callback, capture)
        return Unit{}
    case Context{registry, _, _} Dispatch{eventType}: dispatch(registry, eventType)

def runActions(+context: Context, actions: List<&2, Action>) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit, Unit{})
    case action <> rest:
      do IO<Unit>:
        runAction(context, action)
        runActions(context, rest)

def body(environment: Environment, unused: String) -> IO(Unit):
  match environment:
    case Environment{Context{registry, +log, callbacks}, label, actions}:
      do IO<Unit>:
        R.modify(List<&2, String>, Unit, log, current => (label <> current, Unit{}))
        runActions(Context{registry, log, callbacks}, actions)

def makeCallbacks(+context: Context, specs: List<&2, CallbackSpec>) -> IO(List<&2, C.Callback<String, Unit>>):
  match specs:
    case Nil{}: IO.pure(List<&2, C.Callback<String, Unit>>, Nil{})
    case CallbackSpec{label, actions} <> rest:
      do IO<List<&2, C.Callback<String, Unit>>>:
        callback : C.Callback<String, Unit> <- C.create(~Environment, ~String, ~Unit, ~body, Environment{context, label, actions})
        tail : List<&2, C.Callback<String, Unit>> <- makeCallbacks(context, rest)
        return callback <> tail

def disposeCallbacks(callbacks: List<&2, C.Callback<String, Unit>>) -> IO(Unit):
  match callbacks:
    case Nil{}: IO.pure(Unit, Unit{})
    case callback <> rest:
      do IO<Unit>:
        C.dispose(String, Unit, callback)
        disposeCallbacks(rest)

def checkRetired(state: L.State<String, Unit>) -> IO(Unit):
  match state:
    case L.State{_, 0n, _, Nil{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "finished dispatch must release retired nodes and traversal count")

def checkCleanup(registry: L.Registry<String, Unit>) -> IO(Unit):
  match registry:
    case L.Registry{state}:
      do IO<Unit>:
        current : L.State<String, Unit> <- R.read(L.State<String, Unit>, state)
        checkRetired(current)

def run(name: String, specs: List<&2, CallbackSpec>, actions: List<&2, Action>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +registry : L.Registry<String, Unit> <- L.new(String, Unit)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +callbacks : R.Ref<List<&2, C.Callback<String, Unit>>> <- R.new(List<&2, C.Callback<String, Unit>>, Nil{})
    +context : Context = Context{registry, log, callbacks}
    values : List<&2, C.Callback<String, Unit>> <- makeCallbacks(context, specs)
    R.write(List<&2, C.Callback<String, Unit>>, callbacks, values)
    runActions(context, actions)
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    assertion(String.eq(String.join(List.reverse(&2, String, recorded), ","), expected), name)
    checkCleanup(registry)
    L.dispose(String, Unit, registry)
    owned : List<&2, C.Callback<String, Unit>> <- R.dispose(List<&2, C.Callback<String, Unit>>, callbacks)
    disposeCallbacks(owned)
    previous : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}
