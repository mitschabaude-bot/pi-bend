import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./message-events.bend as Test
import ./assistant-response.bend as Response
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as F

def Message() -> Data: Ai.AssistantMessage<String, Unit>
def Event() -> Data: T.AgentEvent<Unit, String, Unit, String, String, Unit, Unit>
def Outcome() -> Data: Result<&2, &2, String, Bool>
def Emitted() -> Data: Result<&2, &2, String, Unit>
def Sink() -> Data: Loop.AgentEventSink(Unit, String, Unit, String, String, Unit, Unit, String)
def Results() -> Data: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<String>>>>
def Owners() -> Data: R.Ref<List<&2, Results()>>
type Environment is Data:
  Environment{message: R.Ref<Message()>, content: R.Ref<List<&2, Ai.AssistantContent<String>>>, usage: R.Ref<Ai.Usage>, messages: H.Messages(), extra: R.Ref<String>, count: R.Ref<U32>, trace: R.Ref<String>, failAt: U32, ready: Chan(Unit), release: Chan(Unit)}

def emptyResults(values: List<&2, R.Ref<Ai.ToolResultMessage<String>>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "failed turn must have empty tool results")

def checkMessages(values: List<&2, H.Message()>, message: R.Ref<Message()>, +extra: R.Ref<String>, appended: Bool) -> IO(Unit):
  match values appended:
    case T.CustomMessage{+first} <> T.LlmMessage{Ai.Assistant{actual}} <> Nil{} False{}: Test.assertion(R.same(String, first, extra) && R.same(Message(), actual, message), "completion appended message out of order")
    case T.CustomMessage{first} <> T.LlmMessage{Ai.Assistant{actual}} <> T.CustomMessage{last} <> Nil{} True{}: Test.assertion(R.same(String, first, extra) && R.same(String, last, extra) && R.same(Message(), actual, message), "listener mutation not retained")
    case _ _: IO.die(Unit, 1, "completion message array shape differs")

def inspect(environment: Environment, event: Event()) -> IO(Unit):
  match environment event:
    case Environment{+message, content, usage, +messages, +extra, _, _, _, _, _} T.TurnEnd{T.LlmMessage{Ai.Assistant{actual}}, results}:
      do IO<Unit>:
        Test.assertion(R.same(Message(), actual, message), "failed turn copied assistant message")
        values : List<&2, R.Ref<Ai.ToolResultMessage<String>>> <- R.read(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, results)
        emptyResults(values)
        before : List<&2, H.Message()> <- R.read(List<&2, H.Message()>, messages)
        checkMessages(before, message, extra, False{})
        R.modify(List<&2, H.Message()>, Unit, messages, previous => (List.append(&2, H.Message(), previous, T.CustomMessage{extra} <> Nil{}), Unit{}))
        R.write(Message(), message, Test.assistant(content, usage, Ai.Stop{}))
    case Environment{message, _, _, messages, extra, _, _, _, _, _} T.AgentEnd{+actual}:
      do IO<Unit>:
        Test.assertion(R.same(List<&2, H.Message()>, actual, messages), "agent end copied newMessages")
        values : List<&2, H.Message()> <- R.read(List<&2, H.Message()>, actual)
        checkMessages(values, message, extra, True{})
    case _ _: IO.die(Unit, 1, "unexpected failure-branch event")

def emitShared(+environment: Environment, +event: Event()) -> IO(Emitted()):
  match environment:
    case Environment{_, _, _, _, _, count, trace, failAt, ready, release}:
      do IO<Emitted()>:
        inspect(environment, event)
        kind : String = T.eventType(Unit, String, Unit, String, String, Unit, Unit, event)
        R.modify(String, Unit, trace, old => (old ++ kind ++ "|", Unit{}))
        index : U32 <- R.modify(U32, U32, count, +n => (U32.add(n, 1), n))
        sent : Bool <- Chan.send(Unit, ready, Unit{})
        token : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Bool.pick(Emitted(), U32.is_eq(index, failAt), Fail{"listener failure"}, Done{Unit{}})

def emit(environment: Environment, event: Event()) -> IO(Emitted()):
  emitShared(environment, event)

def task(message: R.Ref<Message()>, messages: H.Messages(), sink: Sink(), arrays: Owners(), done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    result : Outcome() <- Loop.recordAssistantCompletion(Unit, String, Unit, String, String, Unit, Unit, String, message, messages, sink, arrays)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def shown(result: Outcome()) -> String:
  match result:
    case Fail{error}: error
    case Done{True{}}: "ended"
    case Done{False{}}: "continue"

def disposeArrays(values: List<&2, Results()>, failed: Bool) -> IO(Unit):
  match values failed:
    case Nil{} False{}: IO.pure(Unit, Unit{})
    case reference <> Nil{} True{}:
      do IO<Unit>:
        old : List<&2, R.Ref<Ai.ToolResultMessage<String>>> <- R.dispose(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, reference)
        emptyResults(old)
    case _ _: IO.die(Unit, 1, "failed-turn result-array allocation differs")

def run(reason: Ai.StopReason, failAt: U32, expected: String, expectedTrace: String, +expectedCalls: U32) -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +usage : R.Ref<Ai.Usage> <- R.new(Ai.Usage, Test.usage(cost))
    +content : R.Ref<List<&2, Ai.AssistantContent<String>>> <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +message : R.Ref<Message()> <- R.new(Message(), Test.assistant(content, usage, reason))
    +extra : R.Ref<String> <- R.new(String, "extra")
    +messages : H.Messages() <- R.new(List<&2, H.Message()>, T.CustomMessage{extra} <> Nil{})
    +arrays : Owners() <- R.new(List<&2, Results()>, Nil{})
    +trace : R.Ref<String> <- R.new(String, "")
    +count : R.Ref<U32> <- R.new(U32, 0)
    +ready : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +sink : Sink() <- C.create(~Environment, ~Event(), ~Emitted(), ~emit, Environment{message, content, usage, messages, extra, count, trace, failAt, ready, release})
    running : Chan(Outcome()) <- IO.fork(Outcome(), task(message, messages, sink, arrays, done))
    Response.drive(expectedCalls, ready, release, done)
    result : Outcome() <- IO.join(Outcome(), running)
    Test.assertion(String.eq(shown(result), expected), "completion result differs from upstream")
    observedTrace : String <- R.dispose(String, trace)
    Test.assertion(String.eq(observedTrace, expectedTrace), "completion event order differs")
    calls : U32 <- R.dispose(U32, count)
    Test.assertion(U32.is_eq(calls, expectedCalls), "completion event count differs")
    values : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, messages)
    checkMessages(values, message, extra, Bool.not(U32.is_eq(expectedCalls, 0)))
    owned : List<&2, Results()> <- R.dispose(List<&2, Results()>, arrays)
    disposeArrays(owned, Bool.not(U32.is_eq(expectedCalls, 0)))
    C.dispose(Event(), Emitted(), sink)
    Chan.close(Unit, ready)
    Chan.close(Unit, release)
    D.dispose(Unit, done)
    oldMessage : Message() <- R.dispose(Message(), message)
    oldContent : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, content)
    oldUsage : Ai.Usage <- R.dispose(Ai.Usage, usage)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    oldExtra : String <- R.dispose(String, extra)
    return Unit{}
