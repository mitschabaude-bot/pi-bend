import Base
import ../src/agent.bend as R
import ../src/agent.bend as L
import ../src/agent.bend as State
import ../src/agent.bend as Continue
import ../src/agent.bend as Q
import ../src/agent.bend as Pending
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/string-set.bend as Set
import ../../runtime/src/f64.bend as F
import ./agent-queues.bend as Fixture
import ./message-events.bend as Test

def Runtime() -> Data: R.OwnedRuntime<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit>
def Owned() -> Data: R.OwnedState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit>
def Value() -> Data: T.AgentState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit>
def Message() -> Data: Fixture.Message()
def Plan() -> Data: Continue.Plan<Message()>
def Claim() -> Data: Result<&2, &2, L.ClaimError<String>, L.Claimed<Plan()>>
type Step is Data:
  Step{run: Maybe<&2, L.ActiveRun>, decision: String}
def role(message: Message()) -> String:
  match message:
    case T.LlmMessage{Ai.System{_}}: "s"
    case T.LlmMessage{Ai.User{_}}: "u"
    case T.LlmMessage{Ai.Assistant{_}}: "a"
    case T.LlmMessage{Ai.ToolResult{_}}: "t"
    case T.CustomMessage{_}: "c"
def roles(messages: List<&2, Message()>) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: role(message) ++ roles(rest)
def partial(message: Maybe<&2, Message()>) -> String:
  match message:
    case None{}: "-"
    case Some{value}: role(value)
def queueKey(+queue: Pending.PendingMessageQueue<Message()>) -> String:
  Fixture.modeName(Pending.getModePending(Message(), queue)) ++ ":" ++ String.join(Fixture.names(Pending.values(Message(), queue)), ",")
def stateKey(prompt: String, state: Value()) -> String:
  match state:
    case T.AgentState{_, _, _, messages, streaming, message, pending, _}:
      prompt ++ "|" ++ roles(messages) ++ "|" ++ Bool.pick(String, streaming, "1", "0") ++ "|" ++ partial(message) ++ "|" ++ String.join(Set.toList(pending), ",")
def key(owned: Owned()) -> String:
  match owned:
    case R.OwnedState{+state, Q.Queues{steering, followUp}}:
      stateKey(State.systemPromptState(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, state), state) ++ "|" ++ queueKey(steering) ++ "|" ++ queueKey(followUp)
def planKey(plan: Plan()) -> String:
  match plan:
    case Continue.Continue{}: "continue"
    case Continue.Prompt{messages, skip}: "prompt:" ++ String.join(Fixture.names(messages), ",") ++ ":" ++ Bool.pick(String, skip, "1", "0")
def claimKey(previous: Maybe<&2, L.ActiveRun>, prompt: Bool, result: Claim()) -> Step:
  match result:
    case Done{L.Claimed{run, plan}}: Step{Some{run}, planKey(plan)}
    case Fail{L.Rejected{error}}: Step{previous, "error:" ++ error}
    case Fail{L.LifeBusy{}}: Step{previous, Bool.pick(String, prompt, "error:Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.", "error:Agent is already processing. Wait for completion before continuing.")}
def resetKey(result: Result<&2, &2, String, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{error}: "error:" ++ error
def eventKey(result: Result<&2, &2, String, L.ActiveRun>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{error}: "error:" ++ error
def finish(+runtime: Runtime(), active: Maybe<&2, L.ActiveRun>) -> IO(Step):
  match active:
    case None{}: IO.pure(Step, Step{None{}, "idle"})
    case Some{run}:
      do IO<Step>:
        won : Bool <- R.finishRunRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, run)
        Test.assertion(won, "fixture must finish its current run")
        R.waitForIdleRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        return Step{None{}, "finished"}
def event(operation: U32) -> T.AgentEvent<Unit, Unit, Unit, Unit, String, Unit, Unit>:
  match operation:
    case 6: T.MessageEnd{Fixture.user("user")}
    case 7: T.MessageEnd{Fixture.assistant()}
    case 8: T.MessageStart{Fixture.assistant()}
    case 9: T.ToolExecutionStart{"call", "tool", Unit{}}
    case 10: T.AgentEnd{Nil{}}
    case _: T.MessageEnd{T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"updated"}, None{}, None{}, None{}, F.fromU32(0)}}}}
def step(runtime: Runtime(), active: Maybe<&2, L.ActiveRun>, operation: U32) -> IO(Step):
  match operation:
    case 0:
      do IO<Step>:
        result : Result<&2, &2, String, Unit> <- R.resetRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        return Step{active, resetKey(result)}
    case 1:
      do IO<Step>:
        R.steerRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Fixture.user("s"))
        return Step{active, "ok"}
    case 2:
      do IO<Step>:
        R.followUpRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Fixture.user("f"))
        return Step{active, "ok"}
    case 3:
      do IO<Step>:
        result : Claim() <- R.beginPrompt(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Fixture.user("prompt") <> Nil{})
        return claimKey(active, True{}, result)
    case 4:
      do IO<Step>:
        result : Claim() <- R.beginContinue(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        return claimKey(active, False{}, result)
    case 5: finish(runtime, active)
    case 12:
      do IO<Step>:
        R.setQueueMode(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.QueuesSteering{}, T.All{})
        return Step{active, "ok"}
    case 13:
      do IO<Step>:
        R.setQueueMode(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.FollowUp{}, T.All{})
        return Step{active, "ok"}
    case 14:
      do IO<Step>:
        R.clearQueue(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.QueuesSteering{})
        return Step{active, "ok"}
    case 15:
      do IO<Step>:
        R.clearQueue(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.FollowUp{})
        return Step{active, "ok"}
    case 16:
      do IO<Step>:
        R.clearAllRuntimeQueues(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        return Step{active, "ok"}
    case 17:
      do IO<Step>:
        messages : List<&2, Message()> <- R.drainRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.QueuesSteering{})
        return Step{active, "drained:" ++ String.join(Fixture.names(messages), ",")}
    case 18:
      do IO<Step>:
        messages : List<&2, Message()> <- R.drainRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, Q.FollowUp{})
        return Step{active, "drained:" ++ String.join(Fixture.names(messages), ",")}
    case other:
      do IO<Step>:
        result : Result<&2, &2, String, L.ActiveRun> <- R.recordEvent(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, Unit, Unit, runtime, event(other))
        return Step{active, eventKey(result)}
def verify(value: Step, state: String, +expected: String) -> IO(Unit):
  match value:
    case Step{_, decision}:
      do IO<Unit>:
        +actual : String = decision ++ "#" ++ state
        Test.assertion(String.eq(actual, expected), "runtime source mismatch: " ++ actual ++ " != " ++ expected)
@unsafe def steps(+runtime: Runtime(), operations: List<&2, U32>, expected: List<&2, String>, current: Step) -> IO(Unit):
  match operations expected current:
    case Nil{} Nil{} Step{active, _}:
      do IO<Unit>:
        ignored : Step <- finish(runtime, active)
        final : Owned() <- R.disposeRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        return Unit{}
    case operation <> rest wanted <> expectedRest Step{active, _}:
      do IO<Unit>:
        +next : Step <- step(runtime, active, operation)
        owned : Owned() <- R.snapshotRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
        verify(next, key(owned), wanted)
        steps(runtime, rest, expectedRest, next)
    case _ _ _: IO.die(Unit, 1, "runtime fixture length mismatch")
def initialHistory(index: U32) -> List<&2, Message()>:
  match index:
    case 0: Nil{}
    case 1: Fixture.user("user") <> Nil{}
    case _: Fixture.assistant() <> Nil{}
def scenario(historyIndex: U32, steering: U32, follow: U32, operations: List<&2, U32>, expected: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    initial : State.AgentInitialState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit> = State.AgentInitialState{Some{"base"}, None{}, None{}, None{}, Some{initialHistory(historyIndex)}}
    runtime : Runtime() <- R.newRuntime(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, initial, Fixture.mode(steering), Fixture.mode(follow))
    steps(runtime, operations, expected, Step{None{}, ""})
