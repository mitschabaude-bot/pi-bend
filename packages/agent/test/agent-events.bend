import Base
import ../src/event-emission.bend as Emission
import ../src/agent-events.bend as Events
import ../src/agent-listeners.bend as Listeners
import ../src/agent-runtime.bend as Runtime
import ../src/agent-lifecycle.bend as Life
import ../src/agent-state.bend as State
import ../src/types.bend as T
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/ref.bend as R
import ./agent-runtime.bend as Fixture
import ./agent-queues.bend as QueueTest
import ./message-events.bend as Test

def EmittedEvent() -> Data: T.AgentEvent<Unit, Unit, Unit, Unit, String, Unit, Unit>
def Input() -> Data: Listeners.Input<EmittedEvent(), Abort.AbortSignal<Unit>>
def Registry() -> Data: Listeners.Listeners<EmittedEvent(), Abort.AbortSignal<Unit>, String>
def Outcome() -> Data: Result<&2, &2, Events.DeliveryError<String>, Unit>
type Environment is Data:
  Environment{first: Bool, fail: Bool, runtime: Fixture.Runtime(), entered: Chan(Unit), release: Chan(Unit), log: R.Ref<String>}
def gate(first: Bool, entered: Chan(Unit), release: Chan(Unit)) -> IO(Unit):
  match first:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        R.requireSent(sent)
        IO.join(Unit, release)
def isEnd(event: EmittedEvent()) -> Bool:
  match event:
    case T.AgentEnd{_}: True{}
    case _: False{}
def finishBody(+first: Bool, fail: Bool, entered: Chan(Unit), release: Chan(Unit), signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    gate(first, entered, release)
    aborted : Bool <- Abort.aborted(Unit, signal)
    Test.assertion(aborted, "subscribers receive the active signal, including cancellation during await")
    return Bool.pick(Result<&2, &2, String, Unit>, fail, Fail{Bool.pick(String, first, "first failed", "second failed")}, Done{Unit{}})
def body(environment: Environment, input: Input()) -> IO(Emission.Emission<String>):
  match environment input:
    case Environment{+first, fail, runtime, entered, release, +log} Listeners.Input{event, signal}:
      do IO<Emission.Emission<String>>:
        Test.assertion(isEnd(event), "subscriber receives the original event")
        state : Fixture.Owned() <- Runtime.snapshot(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        Test.assertion(String.eq(Fixture.key(state), "base|s|1|-||one:|one:"), "agent_end state commits before listeners without becoming idle")
        name : String = Bool.pick(String, first, "first;", "second;")
        R.modify(String, Unit, log, old => (old ++ name, Unit{}))
        Emission.start(String, finishBody(first, fail, entered, release, signal))

def requireRun(result: Fixture.Claim()) -> IO(Life.ActiveRun):
  match result:
    case Done{Life.Claimed{run, _}}: IO.pure(Life.ActiveRun, run)
    case _: IO.die(Life.ActiveRun, 1, "fixture run failed to start")
def deliver(+runtime: Fixture.Runtime(), run: Life.ActiveRun, delivery: Emission.Emission<Events.DeliveryError<String>>, reply: Chan(Outcome())) -> IO(Unit):
  do IO<Unit>:
    result : Outcome() <- Emission.wait(Events.DeliveryError<String>, delivery)
    finished : Bool <- Runtime.finishRun(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, run)
    Test.assertion(finished, "run finalizes after awaited delivery, including failure")
    sent : Bool <- Chan.send(Outcome(), reply, result)
    R.requireSent(sent)
def observe(run: Life.ActiveRun) -> IO(D.Ticket<Unit>):
  match run:
    case Life.ActiveRun{completion, _}: D.subscribe(Unit, completion)
def pending(run: Life.ActiveRun) -> IO(Bool):
  match run:
    case Life.ActiveRun{completion, _}:
      do IO<Bool>:
        value : Maybe<&2, Unit> <- D.peek(Unit, completion)
        return Maybe.is_none(&2, Unit, value)
def expectedOutcome(result: Outcome(), mode: U32) -> Bool:
  match result mode:
    case Done{_} 0: True{}
    case Fail{Events.ListenerFailed{message}} 1: String.eq(message, "first failed")
    case Fail{Events.ListenerFailed{message}} 2: String.eq(message, "second failed")
    case _ _: False{}
def outside(result: Outcome()) -> Bool:
  match result:
    case Fail{Events.OutsideRun{message}}: String.eq(message, "Agent listener invoked outside active run")
    case _: False{}
def resetBusy(result: Result<&2, &2, String, Unit>) -> Bool:
  match result:
    case Fail{message}: String.eq(message, "Agent is already processing. Wait for completion before resetting.")
    case _: False{}
def idleWorker(runtime: Fixture.Runtime(), reply: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Runtime.waitForIdle(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    sent : Bool <- Chan.send(Unit, reply, Unit{})
    R.requireSent(sent)
def scenario(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    initial : State.AgentInitialState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit> = State.AgentInitialState{Some{"base"}, None{}, None{}, None{}, None{}}
    +runtime : Fixture.Runtime() <- Runtime.new(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, initial, T.OneAtATime{}, T.OneAtATime{})
    +registry : Registry() <- Listeners.new(EmittedEvent(), Abort.AbortSignal<Unit>, String)
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +log : R.Ref<String> <- R.new(String, "")
    +first : Listeners.Handler(EmittedEvent(), Abort.AbortSignal<Unit>, String) <- C.create(~Environment, ~Input(), ~Emission.Emission<String>, ~body, Environment{True{}, U32.is_eq(mode, 1), runtime, entered, release, log})
    +second : Listeners.Handler(EmittedEvent(), Abort.AbortSignal<Unit>, String) <- C.create(~Environment, ~Input(), ~Emission.Emission<String>, ~body, Environment{False{}, U32.is_eq(mode, 2), runtime, entered, release, log})
    ignored : Listeners.Subscription<EmittedEvent(), Abort.AbortSignal<Unit>, String> <- Listeners.subscribe(EmittedEvent(), Abort.AbortSignal<Unit>, String, registry, first)
    ignored : Listeners.Subscription<EmittedEvent(), Abort.AbortSignal<Unit>, String> <- Listeners.subscribe(EmittedEvent(), Abort.AbortSignal<Unit>, String, registry, second)
    claimed : Fixture.Claim() <- Runtime.beginPrompt(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("prompt") <> Nil{})
    +run : Life.ActiveRun <- requireRun(claimed)
    active : Result<&2, &2, String, Life.ActiveRun> <- Runtime.recordEvent(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, T.MessageStart{QueueTest.assistant()})
    +reply : Chan(Outcome()) <- Chan.new(Outcome(), 1)
    delivery : Emission.Emission<Events.DeliveryError<String>> <- Events.startEvents(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, String, runtime, registry, T.AgentEnd{Nil{}})
    immediate : String <- R.read(String, log)
    Test.assertion(String.eq(immediate, "first;"), "first listener starts before event initiation returns")
    IO.spawn(Unit, deliver(runtime, run, delivery, reply))
    IO.join(Unit, entered)
    trace : String <- R.read(String, log)
    Test.assertion(String.eq(trace, "first;"), "second subscriber cannot overlap the first")
    state : Fixture.Owned() <- Runtime.snapshot(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    Test.assertion(String.eq(Fixture.key(state), "base|s|1|-||one:|one:"), "agent stays streaming during an awaited agent_end listener")
    wait : D.Ticket<Unit> <- observe(run)
    unsettled : Bool <- pending(run)
    Test.assertion(unsettled, "idle completion remains pending while listener is suspended")
    +idle : Chan(Unit) <- Chan.new(Unit, 1)
    IO.spawn(Unit, idleWorker(runtime, idle))
    reset : Result<&2, &2, String, Unit> <- Runtime.reset(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    Test.assertion(resetBusy(reset), "awaited listener keeps reset guarded without holding the owner lock")
    Runtime.abort(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    result : Outcome() <- IO.join(Outcome(), reply)
    Test.assertion(expectedOutcome(result, mode), "delivery returns the first listener error")
    D.wait(Unit, wait)
    IO.join(Unit, idle)
    +trace : String <- R.read(String, log)
    Test.assertion(String.eq(trace, Bool.pick(String, U32.is_eq(mode, 1), "first;", "first;second;")), "listener failure stops later delivery")
    invalid : Outcome() <- Events.processEvents(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, String, runtime, registry, T.MessageEnd{QueueTest.user("late")})
    Test.assertion(outside(invalid), "outside-run event returns the source error")
    unchanged : String <- R.read(String, log)
    Test.assertion(String.eq(trace, unchanged), "outside-run events never reach subscribers")
    final : Fixture.Owned() <- Runtime.dispose(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    Test.assertion(String.eq(Fixture.key(final), "base|su|0|-||one:|one:"), "finish clears streaming and idle event reduction precedes its error")
    Listeners.dispose(EmittedEvent(), Abort.AbortSignal<Unit>, String, registry)
    C.dispose(Input(), Emission.Emission<String>, first)
    C.dispose(Input(), Emission.Emission<String>, second)
    old : String <- R.dispose(String, log)
    return Unit{}
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0)
    scenario(1)
    scenario(2)
    IO.print("PASS awaited Agent event delivery, cancellation, idle and listener failures")
