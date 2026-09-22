import Base
import ../src/agent-loop.bend as Emission
import ../src/agent.bend as Failure
import ../src/agent.bend as Events
import ../src/agent.bend as Listeners
import ../src/agent.bend as Runtime
import ../src/agent.bend as Life
import ../src/agent.bend as State
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date
import ./agent-runtime.bend as Fixture
import ./agent-events.bend as EventTest
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema

def isEqual(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}
def equal(a: F64, b: F64) -> Bool: isEqual(F.compare(a, b))
def ordered(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{LT{}}: True{}
    case Some{EQ{}}: True{}
    case _: False{}
def atMost(a: F64, b: F64) -> Bool: ordered(F.compare(a, b))
def zero(value: F64) -> Bool: equal(value, F.fromU32(0))
def usageZero(usage: Ai.Usage) -> Bool:
  match usage:
    case Ai.Usage{a, b, c, d, None{}, None{}, e, Ai.UsageCost{f, g, h, i, j}}: zero(a) && zero(b) && zero(c) && zero(d) && zero(e) && zero(f) && zero(g) && zero(h) && zero(i) && zero(j)
    case _: False{}
def reason(stop: Ai.StopReason, aborted: Bool) -> Bool:
  match stop:
    case Ai.Error{}: Bool.not(aborted)
    case Ai.Aborted{}: aborted
    case _: False{}
def valid(message: Ai.AssistantMessage<Schema.Value, Unit>, aborted: Bool, expected: String, lower: F64, upper: F64) -> Bool:
  match message:
    case Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"", None{}}} <> Nil{}, "failure-api", "failure-provider", "failure-model", None{}, None{}, None{}, None{}, usage, stop, None{}, Some{error}, None{}, None{}, +timestamp}:
      usageZero(usage) && reason(stop, aborted) && String.eq(error, expected) && atMost(lower, timestamp) && atMost(timestamp, upper)
    case _: False{}
def timestamp(message: Ai.AssistantMessage<Schema.Value, Unit>) -> F64:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, _, _, value}: value
def stampState(previous: Maybe<&2, F64>, +value: F64) -> Maybe<&2, F64> & Bool:
  match previous:
    case None{}: (Some{value}, True{})
    case Some{+old}: (Some{old}, equal(old, value))
def stage(event: EventTest.EmittedEvent()) -> U32:
  match event:
    case T.MessageStart{_}: 0
    case T.MessageEnd{_}: 1
    case T.TurnEnd{_, _}: 2
    case T.AgentEnd{_}: 3
    case _: 4
def stageName(index: U32) -> String:
  match index:
    case 0: "start"
    case 1: "end"
    case 2: "turn"
    case _: "agent"
def assistant(message: Fixture.Message()) -> IO(Ai.AssistantMessage<Schema.Value, Unit>):
  match message:
    case T.LlmMessage{Ai.Assistant{value}}: IO.pure(Ai.AssistantMessage<Schema.Value, Unit>, value)
    case _: IO.die(Ai.AssistantMessage<Schema.Value, Unit>, 1, "failure event lacks an assistant message")
def eventMessage(event: EventTest.EmittedEvent()) -> IO(Ai.AssistantMessage<Schema.Value, Unit>):
  match event:
    case T.MessageStart{message}: assistant(message)
    case T.MessageEnd{message}: assistant(message)
    case T.TurnEnd{message, Nil{}}: assistant(message)
    case T.AgentEnd{message <> Nil{}}: assistant(message)
    case _: IO.die(Ai.AssistantMessage<Schema.Value, Unit>, 1, "failure event has wrong batch shape")
def stateError(value: Fixture.Value()) -> String:
  match value:
    case T.AgentState{_, _, _, _, _, _, _, error}: Maybe.default(&2, String, error, "none")
def key(+owned: Fixture.Owned()) -> String:
  Fixture.key(owned) ++ "~" ++ stateError(Runtime.stateValue(Unit, Unit, String, String, owned))
type Environment is Data:
  Environment{runtime: Fixture.Runtime(), log: R.Ref<String>, stamp: R.Ref<Maybe<&2, F64>>, lower: F64, aborted: Bool, error: String, failStage: U32, failListener: U32, listener: U32}
def body(environment: Environment, input: EventTest.Input()) -> IO(Emission.Emission<String>):
  match environment input:
    case Environment{runtime, log, stamp, lower, +aborted, error, failStage, failListener, +listener} Listeners.Input{+event, signal}:
      do IO<Emission.Emission<String>>:
        +message : Ai.AssistantMessage<Schema.Value, Unit> <- eventMessage(event)
        upper : F64 <- Date.now()
        Test.assertion(valid(message, aborted, error, lower, upper), "failure content, metadata, usage, reason, error or wall-clock timestamp differs")
        stable : Bool <- R.modify(Maybe<&2, F64>, Bool, stamp, previous => stampState(previous, timestamp(message)))
        Test.assertion(stable, "all failure events share one timestamp")
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(Bool.not(Bool.xor(cancelled, aborted)), "failure listener gets the active cancellation signal")
        owned : Fixture.Owned() <- Runtime.snapshotRuntime(Unit, Unit, String, String, runtime)
        +index : U32 = stage(event)
        entry : String = stageName(index) ++ "." ++ Bool.pick(String, U32.is_eq(listener, 0), "0", "1") ++ "@" ++ key(owned) ++ ";"
        R.modify(String, Unit, log, previous => (previous ++ entry, Unit{}))
        return Emission.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(index, failStage) && U32.is_eq(listener, failListener), Fail{"listener failed"}, Done{Unit{}})}

def abortIf(runtime: Fixture.Runtime(), aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}: Runtime.abortRuntime(Unit, Unit, String, String, runtime)
    case False{}: IO.pure(Unit, Unit{})
def execute(+runtime: Fixture.Runtime(), aborted: Bool, error: String, claimed: Life.Claimed<Fixture.Plan()>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    ignored : Result<&2, &2, String, Life.ActiveRun> <- Runtime.recordEvent(Unit, Unit, String, String, Unit, Unit, runtime, T.ToolExecutionStart{"pending", "tool", Schema.Null{}})
    abortIf(runtime, aborted)
    return Fail{error}
def requireClaim(result: Fixture.Claim()) -> IO(Life.Claimed<Fixture.Plan()>):
  match result:
    case Done{value}: IO.pure(Life.Claimed<Fixture.Plan()>, value)
    case _: IO.die(Life.Claimed<Fixture.Plan()>, 1, "fixture failed to claim run")
def resultKey(result: EventTest.Outcome()) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{Events.ListenerFailed{message}}: message
    case Fail{Events.OutsideRun{message}}: "outside:" ++ message
def model() -> Ai.Model<Ai.JsonValue>:
  +zero = F.fromU32(0)
  Ai.Model{"failure-model", "Failure", Ai.CustomModelApi{"failure-api"}, "failure-provider", "", False{}, None{}, Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, zero, zero, None{}, None{}, None{}}
def scenario(+aborted: Bool, +error: String, +failStage: U32, +failListener: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    Test.assertion(valid(Failure.failureMessage(Unit, model(), aborted, error, F.fromU32(42)), aborted, error, F.fromU32(42), F.fromU32(42)), "explicit failure constructor preserves timestamp and complete message shape")
    initial : State.AgentInitialState<Unit, Unit, String, String> = State.AgentInitialState{Some{"base"}, Some{model()}, None{}, None{}, None{}}
    +runtime : Fixture.Runtime() <- Runtime.newRuntime(Unit, Unit, String, String, initial, T.OneAtATime{}, T.OneAtATime{})
    +registry : EventTest.Registry() <- Listeners.newListeners(EventTest.EmittedEvent(), String)
    +log : R.Ref<String> <- R.new(String, "")
    +stamp : R.Ref<Maybe<&2, F64>> <- R.new(Maybe<&2, F64>, None{})
    +lower : F64 <- Date.now()
    +first : Listeners.Handler(EventTest.EmittedEvent(), String) <- C.create(~Environment, ~EventTest.Input(), ~Emission.Emission<String>, ~body, Environment{runtime, log, stamp, lower, aborted, error, failStage, failListener, 0})
    +second : Listeners.Handler(EventTest.EmittedEvent(), String) <- C.create(~Environment, ~EventTest.Input(), ~Emission.Emission<String>, ~body, Environment{runtime, log, stamp, lower, aborted, error, failStage, failListener, 1})
    ignored : Listeners.Subscription<EventTest.EmittedEvent(), String> <- Listeners.subscribeListeners(EventTest.EmittedEvent(), String, registry, first)
    ignored : Listeners.Subscription<EventTest.EmittedEvent(), String> <- Listeners.subscribeListeners(EventTest.EmittedEvent(), String, registry, second)
    initialClaim : Fixture.Claim() <- Runtime.beginPrompt(Unit, Unit, String, String, runtime, Nil{})
    claimed : Life.Claimed<Fixture.Plan()> <- requireClaim(initialClaim)
    result : EventTest.Outcome() <- Failure.runClaimedFailure(Unit, Unit, String, String, Unit, Unit, String, Fixture.Plan(), runtime, registry, claimed, claim => execute(runtime, aborted, error, claim), value => value)
    Runtime.waitForIdleRuntime(Unit, Unit, String, String, runtime)
    final : Fixture.Owned() <- Runtime.snapshotRuntime(Unit, Unit, String, String, runtime)
    trace : String <- R.read(String, log)
    +actual : String = trace ++ "#" ++ resultKey(result) ++ "#" ++ key(final)
    Test.assertion(String.eq(actual, expected), "failure recovery differs from source: " ++ actual)
    retired : Fixture.Owned() <- Runtime.disposeRuntime(Unit, Unit, String, String, runtime)
    Listeners.disposeListeners(EventTest.EmittedEvent(), String, registry)
    C.dispose(EventTest.Input(), Emission.Emission<String>, first)
    C.dispose(EventTest.Input(), Emission.Emission<String>, second)
    oldLog : String <- R.dispose(String, log)
    oldStamp : Maybe<&2, F64> <- R.dispose(Maybe<&2, F64>, stamp)
    return Unit{}
