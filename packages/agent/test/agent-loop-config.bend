import Base
import ../src/agent.bend as Binding
import ../src/agent.bend as Runtime
import ../src/agent.bend as State
import ../src/agent.bend as Q
import ../src/types.bend as T
import ../src/agent.bend as Life
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./agent-runtime.bend as Fixture
import ./agent-queues.bend as QueueTest
import ./message-events.bend as Test

def Messages() -> Data: List<&2, Fixture.Message()>
def Converted() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Unit, Unit, Unit, Unit>>>
def Config() -> Data: T.AgentLoopConfig<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit>
def Readers() -> Data: Binding.BindingPollers<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit>
def Snapshot() -> Data: Binding.Snapshot<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit>
def converterBody(unused: Unit, messages: Messages()) -> IO(Converted()):
  IO.pure(Converted(), Done{State.defaultConvertToLlm(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, messages)})
def base(converter: C.Callback<Messages(), Converted()>) -> Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(123)}, None{}, None{}, None{}, Some{Ai.Sse{}}, None{}, Some{"session"}, None{}, None{}, None{}, Some{Ai.Medium{}}, None{}, None{}, State.defaultModel(Unit), converter, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.Sequential{}}, None{}, None{}}
def model() -> Ai.Model<Unit>:
  +zero = F.fromU32(0)
  Ai.Model{"current", "Current", Ai.CustomModelApi{"custom"}, "provider", "", False{}, None{}, Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, zero, zero, None{}, None{}, None{}}
def thinking(index: U32) -> T.ThinkingLevel():
  match index:
    case 0: Ai.Off{}
    case 1: Ai.Thinking{Ai.Low{}}
    case _: Ai.Thinking{Ai.High{}}
def level(value: Maybe<&2, Ai.ThinkingLevel>) -> String:
  match value:
    case None{}: "off"
    case Some{Ai.Low{}}: "low"
    case Some{Ai.High{}}: "high"
    case _: "unexpected"
def contextKey(value: T.AgentContext<Unit, Unit, Unit, Unit, String, Unit, Unit, String>) -> String:
  match value:
    case T.AgentContext{messages, Some{Nil{}}}: Fixture.roles(messages)
    case _: "unexpected tools"
def equal(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}
def header(value: Snapshot()) -> String:
  match value:
    case Binding.Snapshot{context, T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, Some{retry}, _, _, _, Some{Ai.Sse{}}, _, Some{"session"}, _, _, _, reasoning, _, _, Ai.Model{"current", _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, Some{T.Sequential{}}, _, _}}:
      Bool.pick(String, equal(F.compare(retry, F.fromU32(123))), "current;" ++ level(reasoning) ++ ";session;sse;123;sequential;" ++ contextKey(context) ++ ";0", "wrong retry cap")
    case _: "wrong configuration"
def selected(config: Config(), steering: Bool) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, getSteeringMessages, getFollowUpMessages, _, _, _}: Bool.pick(Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>>, steering, getSteeringMessages, getFollowUpMessages)
def batch(result: Result<&2, &2, String, Messages()>) -> String:
  match result:
    case Done{messages}: String.join(QueueTest.names(messages), ",")
    case Fail{error}: "error:" ++ error
def poll(callback: Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>>) -> IO(String):
  match callback:
    case None{}: IO.die(String, 1, "missing owner queue callback")
    case Some{value}:
      do IO<String>:
        result : Result<&2, &2, String, Messages()> <- C.call(Unit, Result<&2, &2, String, Messages()>, value, Unit{})
        return batch(result)
def config(value: Snapshot()) -> Config():
  match value:
    case Binding.Snapshot{_, result}: result
def savedContext(value: Snapshot()) -> T.AgentContext<Unit, Unit, Unit, Unit, String, Unit, Unit, String>:
  match value:
    case Binding.Snapshot{context, _}: context
def snapshotContext(value: Snapshot()) -> String:
  match value:
    case Binding.Snapshot{context, _}: contextKey(context)
def scenario(skip: Bool, steering: U32, follow: U32, thinkingIndex: U32, +expected: String) -> IO(Unit):
  do IO<Unit>:
    +converter : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~converterBody, Unit{})
    initial : State.AgentInitialState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit> = State.AgentInitialState{Some{"base"}, Some{model()}, Some{thinking(thinkingIndex)}, None{}, Some{QueueTest.user("initial") <> Nil{}}}
    +runtime : Fixture.Runtime() <- Runtime.newRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, initial, QueueTest.mode(steering), QueueTest.mode(follow))
    Runtime.steerRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s0"))
    Runtime.steerRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s1"))
    Runtime.followUpRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("f0"))
    Runtime.followUpRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("f1"))
    +readers : Readers() <- Binding.newBinding(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~Unit, ~Unit, ~String, ~Unit, runtime, skip)
    +snap : Snapshot() <- Binding.snapshotBinding(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, base(converter), readers)
    prefix : String = header(snap)
    retainedContext : T.AgentContext<Unit, Unit, Unit, Unit, String, Unit, Unit, String> = savedContext(snap)
    +current : Config() = config(snap)
    +steeringCallback : Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>> = selected(current, True{})
    +followCallback : Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>> = selected(current, False{})
    a : String <- poll(steeringCallback)
    b : String <- poll(followCallback)
    Runtime.steerRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s2"))
    Runtime.followUpRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("f2"))
    Runtime.setQueueMode(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.QueuesSteering{}, T.All{})
    Runtime.setQueueMode(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.FollowUp{}, T.All{})
    c : String <- poll(steeringCallback)
    d : String <- poll(followCallback)
    e : String <- poll(steeringCallback)
    ignored : Result<&2, &2, String, Life.ActiveRun> <- Runtime.recordEvent(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, T.MessageEnd{QueueTest.user("later")})
    +freshSnapshot : Snapshot() <- Binding.snapshotBinding(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, base(converter), readers)
    updatedContext : String = snapshotContext(freshSnapshot)
    Runtime.steerRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s3"))
    +fresh : Readers() <- Binding.newBinding(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~Unit, ~Unit, ~String, ~Unit, runtime, True{})
    freshValue : Snapshot() <- Binding.snapshotBinding(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, base(converter), fresh)
    freshConfig : Config() = config(freshValue)
    +freshSteering : Maybe<&2, C.Callback<Unit, Result<&2, &2, String, Messages()>>> = selected(freshConfig, True{})
    f : String <- poll(freshSteering)
    g : String <- poll(steeringCallback)
    h : String <- poll(freshSteering)
    +actual : String = prefix ++ "|" ++ a ++ "|" ++ b ++ "|" ++ c ++ "|" ++ d ++ "|" ++ e ++ "|" ++ contextKey(retainedContext) ++ "|" ++ updatedContext ++ "|" ++ f ++ "|" ++ g ++ "|" ++ h
    Test.assertion(String.eq(actual, expected), "loop configuration differs: " ++ actual ++ " != " ++ expected)
    Binding.disposeBinding(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, fresh)
    Binding.disposeBinding(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, readers)
    C.dispose(Messages(), Converted(), converter)
    final : Fixture.Owned() <- Runtime.disposeRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    return Unit{}
