import Base
import ../src/agent.bend as L
import ../src/agent-loop.bend as Emission
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort

type Environment is Data:
  Environment{first: Bool, fail: Bool, release: Chan(Unit), started: R.Ref<U32>, completed: R.Ref<Bool>, later: R.Ref<U32>}
def settle(release: Chan(Unit), completed: R.Ref<Bool>, fail: Bool) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    IO.join(Unit, release)
    R.write(Bool, completed, True{})
    return Bool.pick(Result<&2, &2, String, Unit>, fail, Fail{"first failed"}, Done{Unit{}})
def select(event: String, fail: Bool, release: Chan(Unit), completed: R.Ref<Bool>) -> IO(Emission.Emission<String>):
  match event:
    case "first": Emission.startEmission(String, settle(release, completed, fail))
    case _:
      do IO<Emission.Emission<String>>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)
        return Emission.EmissionReady{Done{Unit{}}}
def firstEvent(environment: Environment, event: String) -> IO(Emission.Emission<String>):
  match environment:
    case Environment{_, fail, release, started, completed, _}:
      do IO<Emission.Emission<String>>:
        R.modify(U32, Unit, started, old => (U32.add(old, 1), Unit{}))
        select(event, fail, release, completed)
def body(environment: Environment, input: L.Input<String>) -> IO(Emission.Emission<String>):
  match environment input:
    case Environment{True{}, fail, release, started, completed, later} L.Input{event, _}:
      firstEvent(Environment{True{}, fail, release, started, completed, later}, event)
    case Environment{False{}, _, _, _, completed, later} L.Input{event, _}:
      do IO<Emission.Emission<String>>:
        settled : Bool <- R.read(Bool, completed)
        Test.assertion(Bool.not(String.eq(event, "first")) || settled, "later subscriber waits for the first subscriber's pending work")
        R.modify(U32, Unit, later, old => (U32.add(old, 1), Unit{}))
        return Emission.EmissionReady{Done{Unit{}}}
def valid(result: Result<&2, &2, String, Unit>, fail: Bool) -> Bool:
  match result fail:
    case Done{_} False{}: True{}
    case Fail{error} True{}: String.eq(error, "first failed")
    case _ _: False{}
def scenario(+fail: Bool) -> IO(Unit):
  do IO<Unit>:
    +registry : L.Listeners<String, String> <- L.newListeners(String, String)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +started : R.Ref<U32> <- R.new(U32, 0)
    +completed : R.Ref<Bool> <- R.new(Bool, False{})
    +later : R.Ref<U32> <- R.new(U32, 0)
    +first : L.Handler(String, String) <- C.create(~Environment, ~L.Input<String>, ~Emission.Emission<String>, ~body, Environment{True{}, fail, release, started, completed, later})
    +second : L.Handler(String, String) <- C.create(~Environment, ~L.Input<String>, ~Emission.Emission<String>, ~body, Environment{False{}, fail, release, started, completed, later})
    ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, first)
    ignored : L.Subscription<String, String> <- L.subscribeListeners(String, String, registry, second)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    one : Emission.Emission<String> <- L.start(String, String, registry, "first", Abort.signal(Unit, controller))
    starts : U32 <- R.read(U32, started)
    settled : Bool <- R.read(Bool, completed)
    calls : U32 <- R.read(U32, later)
    Test.assertion(U32.is_eq(starts, 1) && Bool.not(settled) && U32.is_eq(calls, 0), "start performs immediate effects and returns before pending completion")
    two : Emission.Emission<String> <- L.start(String, String, registry, "second", Abort.signal(Unit, controller))
    starts : U32 <- R.read(U32, started)
    Test.assertion(U32.is_eq(starts, 2), "another event starts while the previous delivery is pending")
    secondResult : Result<&2, &2, String, Unit> <- Emission.wait(String, two)
    firstResult : Result<&2, &2, String, Unit> <- Emission.wait(String, one)
    Test.assertion(valid(secondResult, False{}) && valid(firstResult, fail), "each delivery keeps its own completion or first error")
    calls : U32 <- R.read(U32, later)
    Test.assertion(U32.is_eq(calls, Bool.pick(U32, fail, 1, 2)), "pending failure skips remaining subscribers for only its event")
    L.disposeListeners(String, String, registry)
    C.dispose(L.Input<String>, Emission.Emission<String>, first)
    C.dispose(L.Input<String>, Emission.Emission<String>, second)
    old : U32 <- R.dispose(U32, started)
    old : Bool <- R.dispose(Bool, completed)
    old : U32 <- R.dispose(U32, later)
    return Unit{}
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{})
    scenario(True{})
    IO.print("PASS ordered listener initiation, overlapping delivery, awaiting and pending errors")
