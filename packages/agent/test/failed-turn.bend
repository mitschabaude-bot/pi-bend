import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as Schema

def EventValue() -> Data: T.AgentEvent<Unit, String, String, Unit, Unit>
def Outcome() -> Data: Result<&2, &2, String, Loop.AssistantCompletion<H.Message()>>
def Emitted() -> Data: Result<&2, &2, String, Unit>
type Environment is Data:
  Environment{count: R.Ref<U32>, trace: R.Ref<String>, failAt: U32}

def checkMessages(values: H.Messages()) -> IO(Unit):
  match values:
    case T.CustomMessage{first} <> T.LlmMessage{Ai.Assistant{_}} <> Nil{}:
      Test.assertion(String.eq(first, "extra"), "completion changed existing messages")
    case _: IO.die(Unit, 1, "completion must append assistant after existing messages")

def inspect(event: EventValue()) -> IO(Unit):
  match event:
    case T.TurnEnd{T.LlmMessage{Ai.Assistant{message}}, Nil{}}:
      Test.assertion(Loop.assistantFailed(Unit, message), "failed turn carried successful assistant")
    case T.AgentEnd{messages}: checkMessages(messages)
    case _: IO.die(Unit, 1, "unexpected failure-branch event or nonempty tool results")

def emit(environment: Environment, event: EventValue()) -> IO(Emitted()):
  match environment:
    case Environment{count, trace, failAt}:
      do IO<Emitted()>:
        +current : EventValue() = event
        inspect(current)
        kind : String = T.eventType(Unit, String, String, Unit, Unit, current)
        R.modify(String, Unit, trace, old => (old ++ kind ++ "|", Unit{}))
        index : U32 <- R.modify(U32, U32, count, +n => (U32.add(n, 1), n))
        return Bool.pick(Emitted(), U32.is_eq(index, failAt), Fail{"listener failure"}, Done{Unit{}})

def check(result: Outcome(), expected: String) -> IO(Unit):
  match result:
    case Fail{error}: Test.assertion(String.eq(error, expected), "wrong listener error")
    case Done{Loop.AssistantCompletion{messages, failed}}:
      do IO<Unit>:
        checkMessages(messages)
        Test.assertion(String.eq(Bool.pick(String, failed, "ended", "continue"), expected), "completion result differs")

def run(reason: Ai.StopReason, failAt: U32, expected: String, expectedTrace: String, expectedCalls: U32) -> IO(Unit):
  do IO<Unit>:
    +zero : F64 = F.fromU32(0)
    message : Ai.AssistantMessage<Schema.Value, Unit> = Test.assistant(Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), reason)
    +messages : H.Messages() = T.CustomMessage{"extra"} <> Nil{}
    +trace : R.Ref<String> <- R.new(String, "")
    +count : R.Ref<U32> <- R.new(U32, 0)
    +sink : Loop.AgentEventSink(Unit, String, String, Unit, Unit, String) <- C.create(~Environment, ~EventValue(), ~Emitted(), ~emit, Environment{count, trace, failAt})
    result : Outcome() <- Loop.recordAssistantCompletion(Unit, String, String, Unit, Unit, String, message, messages, sink)
    check(result, expected)
    Test.assertion(Nat.is_eq(List.length(&2, H.Message(), messages), 1n), "completion mutated input history")
    observed : String <- R.dispose(String, trace)
    Test.assertion(String.eq(observed, expectedTrace), "completion event order differs")
    calls : U32 <- R.dispose(U32, count)
    Test.assertion(U32.is_eq(calls, expectedCalls), "completion event count differs")
    C.dispose(EventValue(), Emitted(), sink)
