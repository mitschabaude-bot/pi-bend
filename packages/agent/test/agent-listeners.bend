import Base
import ../src/agent-loop.bend as Emission
import ../src/agent.bend as L
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort

def Handler() -> Data: L.Handler(String, String)
def Registry() -> Data: L.Listeners<String, String>
type Handles is Data:
  Handles{first: Handler(), middle: Handler(), last: Handler()}
type Environment is Data:
  Environment{id: U32, mode: U32, registry: Registry(), handles: R.Ref<Maybe<&2, Handles>>, log: R.Ref<String>}
def label(id: U32) -> String:
  match id:
    case 0: "0"
    case 1: "1"
    case _: "2"
def edit(+registry: Registry(), handles: Handles, mode: U32) -> IO(Unit):
  match handles mode:
    case Handles{_, middle, _} 2: L.unsubscribe(String, String, L.Subscription{registry, middle})
    case Handles{_, _, last} 3:
      do IO<Unit>:
        ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, last)
        return Unit{}
    case Handles{_, +middle, _} 4:
      do IO<Unit>:
        L.unsubscribe(String, String, L.Subscription{registry, middle})
        ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, middle)
        return Unit{}
    case Handles{first, _, _} 5: L.unsubscribe(String, String, L.Subscription{registry, first})
    case _ _: IO.pure(Unit, Unit{})
def editReady(registry: Registry(), handles: Maybe<&2, Handles>, mode: U32) -> IO(Unit):
  match handles:
    case Some{value}: edit(registry, value, mode)
    case None{}: IO.die(Unit, 1, "fixture handles not initialized")
def editIfFirst(id: U32, registry: Registry(), handles: R.Ref<Maybe<&2, Handles>>, mode: U32) -> IO(Unit):
  match id:
    case 0:
      do IO<Unit>:
        value : Maybe<&2, Handles> <- R.read(Maybe<&2, Handles>, handles)
        editReady(registry, value, mode)
    case _: IO.pure(Unit, Unit{})
def body(environment: Environment, input: L.Input<String>) -> IO(Emission.Emission<String>):
  match environment input:
    case Environment{+id, +mode, registry, handles, log} L.Input{event, signal}:
      do IO<Emission.Emission<String>>:
        aborted : Bool <- Abort.aborted(Unit, signal)
        entry : String = label(id) ++ ":" ++ event ++ ":" ++ Bool.pick(String, aborted, "1", "0") ++ ";"
        R.modify(String, Unit, log, old => (old ++ entry, Unit{}))
        editIfFirst(id, registry, handles, mode)
        return Emission.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, (U32.is_eq(mode, 6) && U32.is_eq(id, 0)) || (U32.is_eq(mode, 7) && U32.is_eq(id, 1)), Fail{"error" ++ label(id)}, Done{Unit{}})}

def resultKey(result: Result<&2, &2, String, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{error}: error
def optional(registry: Registry(), callback: Handler(), add: Bool) -> IO(Unit):
  match add:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, callback)
        return Unit{}
def scenario(+mode: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    +registry : Registry() <- L.newListeners(String, String)
    +handles : R.Ref<Maybe<&2, Handles>> <- R.new(Maybe<&2, Handles>, None{})
    +log : R.Ref<String> <- R.new(String, "")
    +first : Handler() <- C.create(~Environment, ~L.Input<String>, ~Emission.Emission<String>, ~body, Environment{0, mode, registry, handles, log})
    +middle : Handler() <- C.create(~Environment, ~L.Input<String>, ~Emission.Emission<String>, ~body, Environment{1, mode, registry, handles, log})
    +last : Handler() <- C.create(~Environment, ~L.Input<String>, ~Emission.Emission<String>, ~body, Environment{2, mode, registry, handles, log})
    R.write(Maybe<&2, Handles>, handles, Some{Handles{first, middle, last}})
    +subscription : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, first)
    optional(registry, first, U32.is_eq(mode, 1))
    ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, middle)
    optional(registry, last, Bool.not(U32.is_eq(mode, 3)))
    empty : String <- R.read(String, log)
    Test.assertion(String.is_empty(empty), "subscribing must not emit an event")
    +live : Abort.AbortController<Unit> <- Abort.new(Unit)
    +stopped : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Abort.abort(Unit, stopped, None{})
    firstResult : Result<&2, &2, String, Unit> <- L.emitListeners(String, String, registry, "first", Abort.signal(Unit, live))
    secondResult : Result<&2, &2, String, Unit> <- L.emitListeners(String, String, registry, "second", Abort.signal(Unit, stopped))
    L.unsubscribe(String, String, subscription)
    ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, first)
    L.unsubscribe(String, String, subscription)
    L.unsubscribe(String, String, subscription)
    thirdResult : Result<&2, &2, String, Unit> <- L.emitListeners(String, String, registry, "third", Abort.signal(Unit, live))
    trace : String <- R.read(String, log)
    Test.assertion(String.eq(trace ++ "|" ++ resultKey(firstResult) ++ "," ++ resultKey(secondResult) ++ "," ++ resultKey(thirdResult), expected), "ordered listener dispatch differs from upstream")
    L.disposeListeners(String, String, registry)
    old : Maybe<&2, Handles> <- R.dispose(Maybe<&2, Handles>, handles)
    C.dispose(L.Input<String>, Emission.Emission<String>, first)
    C.dispose(L.Input<String>, Emission.Emission<String>, middle)
    C.dispose(L.Input<String>, Emission.Emission<String>, last)
    oldLog : String <- R.dispose(String, log)
    return Unit{}
