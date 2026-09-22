import Base
import ../src/agent.bend as Pending
import ../src/agent.bend as Q
import ../src/agent.bend as Continue
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema

def mode(index: U32) -> T.QueueMode: Bool.pick(T.QueueMode, U32.is_eq(index, 1), T.All{}, T.OneAtATime{})
def modeName(value: T.QueueMode) -> String:
  match value:
    case T.All{}: "all"
    case T.OneAtATime{}: "one"
def queueKey(+queue: Pending.PendingMessageQueue<String>, output: List<&2, String>) -> String:
  modeName(Pending.getModePending(String, queue)) ++ ";" ++ Bool.pick(String, Pending.hasItems(String, queue), "1", "0") ++ ";" ++ String.join(Pending.values(String, queue), ",") ++ ";" ++ String.join(output, ",")
def queueStep(queue: Pending.PendingMessageQueue<String>, operation: U32) -> Pending.PendingMessageQueue<String> & List<&2, String>:
  match operation:
    case 0: (Pending.enqueuePending(String, queue, "a"), Nil{})
    case 1: (Pending.enqueuePending(String, queue, "b"), Nil{})
    case 2: Pending.drainPending(String, queue)
    case 3: (Pending.clearPending(String, queue), Nil{})
    case 4: (Pending.setModePending(String, queue, T.All{}), Nil{})
    case _: (Pending.setModePending(String, queue, T.OneAtATime{}), Nil{})

type QueueSnapshot is Data:
  QueueSnapshot{queue: Pending.PendingMessageQueue<String>, output: List<&2, String>}
def snapshot(value: Pending.PendingMessageQueue<String> & List<&2, String>) -> QueueSnapshot:
  match value:
    case Tuple{queue, output}: QueueSnapshot{queue, output}

@unsafe def queueSteps(queue: Pending.PendingMessageQueue<String>, operations: List<&2, U32>, expected: List<&2, String>, result: Maybe<&2, QueueSnapshot>) -> IO(Unit):
  match operations expected result:
    case operations wanted <> rest Some{QueueSnapshot{+next, output}}:
      do IO<Unit>:
        Test.assertion(String.eq(queueKey(next, output), wanted), "pending queue state/drained batch differs from source")
        queueSteps(next, operations, rest, None{})
    case operation <> rest expected None{}: queueSteps(Pending.newPending(String, T.All{}), rest, expected, Some{snapshot(queueStep(queue, operation))})
    case Nil{} Nil{} None{}: IO.pure(Unit, Unit{})
    case _ _ _: Test.assertion(False{}, "queue fixture length mismatch")
def queueScenario(initialMode: U32, operations: List<&2, U32>, expected: List<&2, String>) -> IO(Unit):
  queueSteps(Pending.newPending(String, T.All{}), operations, expected, Some{QueueSnapshot{Pending.newPending(String, mode(initialMode)), Nil{}}})

def pairKey(queues: Q.Queues<String>) -> String:
  match queues:
    case Q.Queues{steering, followUp}: queueKey(steering, Nil{}) ++ "|" ++ queueKey(followUp, Nil{})
def pairScenario() -> IO(Unit):
  do IO<Unit>:
    +queues : Q.Queues<String> = Q.enqueueQueues(String, Q.enqueueQueues(String, Q.defaultQueues(String), Q.QueuesSteering{}, "s"), Q.FollowUp{}, "f")
    Test.assertion(String.eq(pairKey(Q.setModeQueues(String, queues, Q.QueuesSteering{}, T.All{})), "all;1;s;|one;1;f;"), "steering mode keeps follow-up state")
    Test.assertion(String.eq(pairKey(Q.setModeQueues(String, queues, Q.FollowUp{}, T.All{})), "one;1;s;|all;1;f;"), "follow-up mode keeps steering state")
    Test.assertion(String.eq(pairKey(Q.clearQueues(String, queues, Q.QueuesSteering{})), "one;0;;|one;1;f;"), "clearing steering keeps follow-up")
    Test.assertion(String.eq(pairKey(Q.clearQueues(String, queues, Q.FollowUp{})), "one;1;s;|one;0;;"), "clearing follow-up keeps steering")
    Test.assertion(String.eq(pairKey(Q.clearAll(String, Q.setModeQueues(String, queues, Q.QueuesSteering{}, T.All{}))), "all;0;;|one;0;;"), "clearing both queues preserves modes")
    Test.assertion(String.eq(pairKey(queues), "one;1;s;|one;1;f;"), "queue operations preserve retained snapshots")

def Message() -> Data: T.AgentMessage<Unit, Unit, String>
def Messages() -> Data: List<&2, Message()>
def user(text: String) -> Message(): T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, F.fromU32(0)}}}
def system() -> Message(): T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"system"}, None{}, None{}, None{}, F.fromU32(0)}}}
def assistant() -> Message():
  +zero = F.fromU32(0)
  T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Nil{}, "custom", "provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.Stop{}, None{}, None{}, None{}, None{}, zero}}}
def history(index: U32) -> Messages():
  match index:
    case 0: Nil{}
    case 1: system() <> Nil{}
    case 2: user("user") <> Nil{}
    case 3: assistant() <> Nil{}
    case 4: T.CustomMessage{"custom"} <> Nil{}
    case 5: T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"id", "tool", Nil{}, None{}, None{}, False{}, F.fromU32(0)}}} <> Nil{}
    case 6: user("user") <> system() <> Nil{}
    case _: system() <> assistant() <> Nil{}
def names(messages: Messages()) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}} <> rest: text <> names(rest)
    case _ <> rest: "unexpected" <> names(rest)
def queued(count: U32, +prefix: String) -> Messages():
  match count:
    case 0: Nil{}
    case 1: user(prefix ++ "0") <> Nil{}
    case 2: user(prefix ++ "0") <> user(prefix ++ "1") <> Nil{}
    case _: user(prefix ++ "0") <> user(prefix ++ "1") <> user(prefix ++ "2") <> Nil{}
def fill(messages: Messages(), queues: Q.Queues<Message()>, +kind: Q.QueueKind) -> Q.Queues<Message()>:
  match messages:
    case Nil{}: queues
    case head <> rest: fill(rest, Q.enqueueQueues(Message(), queues, kind, head), kind)
def decision(result: Result<&2, &2, Continue.ContinueError, Continue.Plan<Message()>>) -> String:
  match result:
    case Fail{error}: "error:" ++ Continue.errorMessage(error)
    case Done{Continue.Continue{}}: "continue"
    case Done{Continue.Prompt{messages, skip}}: "prompt:" ++ String.join(names(messages), ",") ++ ":" ++ Bool.pick(String, skip, "1", "0")
def planKey(result: Q.Queues<Message()> & Result<&2, &2, Continue.ContinueError, Continue.Plan<Message()>>) -> String:
  match result:
    case Tuple{Q.Queues{+steering, +followUp}, planned}:
      decision(planned) ++ ";" ++ String.join(names(Pending.values(Message(), steering)), ",") ++ ";" ++ String.join(names(Pending.values(Message(), followUp)), ",") ++ ";" ++ Bool.pick(String, Q.queuesHaveMessages(Message(), Q.Queues{steering, followUp}), "1", "0")
def continuationScenario(active: Bool, historyIndex: U32, steeringMode: U32, followMode: U32, steeringCount: U32, followCount: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    +queues : Q.Queues<Message()> = fill(queued(steeringCount, "s"), fill(queued(followCount, "f"), Q.newQueues(Message(), mode(steeringMode), mode(followMode)), Q.FollowUp{}), Q.QueuesSteering{})
    before : String = planKey((queues, Done{Continue.Continue{}}))
    result : Q.Queues<Message()> & Result<&2, &2, Continue.ContinueError, Continue.Plan<Message()>> = Continue.planContinue(Unit, Unit, String, active, history(historyIndex), queues)
    Test.assertion(String.eq(planKey(result), expected), "Agent continuation decision/remaining queues differ from source")
    Test.assertion(String.eq(planKey((queues, Done{Continue.Continue{}})), before), "earlier queue snapshot stays unchanged")
