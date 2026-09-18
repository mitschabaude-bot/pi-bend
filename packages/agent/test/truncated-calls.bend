import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./message-events.bend as Test
import ./assistant-response.bend as Response
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/record.bend as Record
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D

def Details() -> Data: R.Ref<Record.Record<Bool>>
def ResultValue() -> Data: T.AgentToolResult<Details()>
def Message() -> Data: Ai.ToolResultMessage<Details()>
def Event() -> Data: T.AgentEvent<Unit, String, Unit, Details(), String, Unit, R.Ref<ResultValue()>>
def Emitted() -> Data: Result<&2, &2, String, Unit>
def Output() -> Data: Result<&2, &2, String, Loop.ExecutedToolCallBatch<Details()>>
def Sink() -> Data: Loop.AgentEventSink(Unit, String, Unit, Details(), String, Unit, R.Ref<ResultValue()>, String)
def Calls() -> Data: R.Ref<List<&2, T.AgentToolCall(String)>>
def Scope() -> Data: Loop.TruncatedToolCallScope<Bool>
type Environment is Data:
  Environment{mode: U32, failAt: U32, calls: Calls(), first: T.AgentToolCall(String), appended: T.AgentToolCall(String), texts: R.Ref<List<&2, String>>, lastDetails: R.Ref<Maybe<&2, Details()>>, lastMessage: R.Ref<Maybe<&2, R.Ref<Message()>>>, count: R.Ref<U32>, trace: R.Ref<String>, ready: Chan(Unit), release: Chan(Unit)}

def rename(value: Ai.ToolCall<String>) -> Ai.ToolCall<String>:
  match value:
    case Ai.ToolCall{id, _, args, signature, namespace}: Ai.ToolCall{id, "changed", args, signature, namespace}

def change(mode: U32, calls: Calls(), first: T.AgentToolCall(String), appended: T.AgentToolCall(String)) -> IO(Unit):
  match mode:
    case 1: R.modify(Ai.ToolCall<String>, Unit, first, value => (rename(value), Unit{}))
    case 2: R.modify(List<&2, T.AgentToolCall(String)>, Unit, calls, values => (List.append(&2, T.AgentToolCall(String), values, appended <> Nil{}), Unit{}))
    case _: IO.pure(Unit, Unit{})

def changeFirst(index: U32, mode: U32, calls: Calls(), first: T.AgentToolCall(String), appended: T.AgentToolCall(String)) -> IO(Unit):
  match index:
    case 0: change(mode, calls, first, appended)
    case _: IO.pure(Unit, Unit{})

def popText(values: List<&2, String>) -> List<&2, String> & Maybe<&2, String>:
  match values:
    case head <> tail: (tail, Some{head})
    case Nil{}: (Nil{}, None{})

def checkText(values: List<&2, Ai.TextImageContent>, expected: Maybe<&2, String>) -> IO(Unit):
  match values expected:
    case Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{} Some{wanted}: Test.assertion(String.eq(text, wanted), "truncated-call error text differs from upstream")
    case _ _: IO.die(Unit, 1, "truncated-call error content shape differs")

def fresh(previous: Maybe<&2, Details()>, current: Details()) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit, Unit{})
    case Some{old}: Test.assertion(Bool.not(R.same(Record.Record<Bool>, old, current)), "truncated calls reused an empty details object")

def emptyDetails(value: Record.Record<Bool>) -> IO(Unit):
  match value:
    case Record.Record{Nil{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "error details were not empty")

def inspectResult(value: ResultValue(), texts: R.Ref<List<&2, String>>, +last: R.Ref<Maybe<&2, Details()>>) -> IO(Unit):
  match value:
    case T.AgentToolResult{content, +details, None{}, None{}}:
      do IO<Unit>:
        expected : Maybe<&2, String> <- R.modify(List<&2, String>, Maybe<&2, String>, texts, popText)
        checkText(content, expected)
        previous : Maybe<&2, Details()> <- R.read(Maybe<&2, Details()>, last)
        fresh(previous, details)
        record : Record.Record<Bool> <- R.read(Record.Record<Bool>, details)
        emptyDetails(record)
        R.write(Record.Record<Bool>, details, Record.set(Bool, Record.new(Bool), "seen", True{}))
        R.write(Maybe<&2, Details()>, last, Some{details})
    case _: IO.die(Unit, 1, "truncated error result fields differ")

def sameDetails(value: Maybe<&2, Details()>, expected: Maybe<&2, Details()>) -> IO(Unit):
  match value expected:
    case Some{actual} Some{wanted}: Test.assertion(R.same(Record.Record<Bool>, actual, wanted), "tool-result message copied error details")
    case _ _: IO.die(Unit, 1, "tool-result message omitted details")

def inspectMessage(value: Message(), details: Maybe<&2, Details()>) -> IO(String):
  match value:
    case Ai.ToolResultMessage{id, _, _, actual, None{}, True{}, _}:
      do IO<String>:
        sameDetails(actual, details)
        return id
    case _: IO.die(String, 1, "truncated tool message error/usage fields differ")

def sameMessage(value: R.Ref<Message()>, expected: Maybe<&2, R.Ref<Message()>>) -> IO(Unit):
  match expected:
    case Some{wanted}: Test.assertion(R.same(Message(), value, wanted), "start/end tool message identity changed")
    case None{}: IO.die(Unit, 1, "message_end before message_start")

def observe(environment: Environment, index: U32, event: Event()) -> IO(String):
  match environment event:
    case Environment{mode, _, calls, first, appended, _, _, _, _, _, _, _} T.ToolExecutionStart{id, _, args}:
      do IO<String>:
        Test.assertion(String.eq(args, "args"), "truncated call arguments changed")
        changeFirst(index, mode, calls, first, appended)
        return "tool_execution_start:" ++ id ++ "|"
    case Environment{_, _, _, _, _, texts, last, _, _, _, _, _} T.ToolExecutionEnd{id, _, result, True{}}:
      do IO<String>:
        value : ResultValue() <- R.read(ResultValue(), result)
        inspectResult(value, texts, last)
        return "tool_execution_end:" ++ id ++ "|"
    case Environment{_, _, _, _, _, _, last, stored, _, _, _, _} T.MessageStart{T.LlmMessage{Ai.ToolResult{+message}}}:
      do IO<String>:
        details : Maybe<&2, Details()> <- R.read(Maybe<&2, Details()>, last)
        value : Message() <- R.read(Message(), message)
        id : String <- inspectMessage(value, details)
        R.write(Maybe<&2, R.Ref<Message()>>, stored, Some{message})
        return "message_start:" ++ id ++ "|"
    case Environment{_, _, _, _, _, _, last, stored, _, _, _, _} T.MessageEnd{T.LlmMessage{Ai.ToolResult{+message}}}:
      do IO<String>:
        previous : Maybe<&2, R.Ref<Message()>> <- R.read(Maybe<&2, R.Ref<Message()>>, stored)
        sameMessage(message, previous)
        details : Maybe<&2, Details()> <- R.read(Maybe<&2, Details()>, last)
        value : Message() <- R.read(Message(), message)
        id : String <- inspectMessage(value, details)
        return "message_end:" ++ id ++ "|"
    case _ _: IO.die(String, 1, "unexpected truncated-call event")

def emitShared(+environment: Environment, event: Event()) -> IO(Emitted()):
  match environment:
    case Environment{_, failAt, _, _, _, _, _, _, count, trace, ready, release}:
      do IO<Emitted()>:
        +index : U32 <- R.modify(U32, U32, count, +n => (U32.add(n, 1), n))
        entry : String <- observe(environment, index, event)
        R.modify(String, Unit, trace, old => (old ++ entry, Unit{}))
        sent : Bool <- Chan.send(Unit, ready, Unit{})
        token : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Bool.pick(Emitted(), U32.is_eq(index, failAt), Fail{"listener failure"}, Done{Unit{}})

def emit(environment: Environment, event: Event()) -> IO(Emitted()):
  emitShared(environment, event)

def task(calls: Calls(), sink: Sink(), scope: Scope(), done: D.Deferred<Unit>) -> IO(Output()):
  do IO<Output()>:
    result : Output() <- Loop.failToolCallsFromTruncatedMessage(Unit, String, Unit, String, Unit, String, Bool, Loop.TruncatedToolCallRun{sink, scope}, calls)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def messageId(value: Message()) -> String:
  match value:
    case Ai.ToolResultMessage{id, _, _, _, _, _, _}: id

def ids(values: List<&2, R.Ref<Message()>>) -> IO(String):
  match values:
    case Nil{}: IO.pure(String, "")
    case reference <> rest:
      do IO<String>:
        value : Message() <- R.read(Message(), reference)
        tail : String <- ids(rest)
        return messageId(value) ++ "|" ++ tail

def check(result: Output(), expected: String, expectedIds: String) -> IO(Unit):
  match result:
    case Fail{error}: Test.assertion(String.eq(error, expected), "truncated batch failure differs")
    case Done{Loop.ExecutedToolCallBatch{messages, False{}}}:
      do IO<Unit>:
        Test.assertion(String.eq(expected, "done"), "unexpected successful truncated batch")
        values : List<&2, R.Ref<Message()>> <- R.read(List<&2, R.Ref<Message()>>, messages)
        observed : String <- ids(values)
        Test.assertion(String.eq(observed, expectedIds), "truncated batch message order differs")
    case _: IO.die(Unit, 1, "truncated batch must never terminate")

def disposeRefs(-Value: Data, values: List<&2, R.Ref<Value>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        old : Value <- R.dispose(Value, reference)
        disposeRefs(Value, rest)

def disposeOwner(-Value: Data, owner: R.Ref<List<&2, R.Ref<Value>>>) -> IO(Unit):
  do IO<Unit>:
    values : List<&2, R.Ref<Value>> <- R.dispose(List<&2, R.Ref<Value>>, owner)
    disposeRefs(Value, values)

def initial(count: U32, first: T.AgentToolCall(String), second: T.AgentToolCall(String)) -> List<&2, T.AgentToolCall(String)>:
  match count:
    case 0: Nil{}
    case 1: first <> Nil{}
    case _: first <> second <> Nil{}

def noTexts(values: List<&2, String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "expected error text was not emitted")

def run(count: U32, mode: U32, failAt: U32, expected: String, expectedTrace: String, expectedTexts: List<&2, String>, expectedIds: String, +expectedEvents: U32) -> IO(Unit):
  do IO<Unit>:
    +first : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"a", "a", "args", None{}, None{}})
    +second : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"b", "b", "args", None{}, None{}})
    +third : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"c", "c", "args", None{}, None{}})
    +calls : Calls() <- R.new(List<&2, T.AgentToolCall(String)>, initial(count, first, second))
    +details : R.Ref<List<&2, Details()>> <- R.new(List<&2, Details()>, Nil{})
    +results : R.Ref<List<&2, R.Ref<ResultValue()>>> <- R.new(List<&2, R.Ref<ResultValue()>>, Nil{})
    +messages : R.Ref<List<&2, R.Ref<Message()>>> <- R.new(List<&2, R.Ref<Message()>>, Nil{})
    +batches : R.Ref<List<&2, R.Ref<List<&2, R.Ref<Message()>>>>> <- R.new(List<&2, R.Ref<List<&2, R.Ref<Message()>>>>, Nil{})
    +texts : R.Ref<List<&2, String>> <- R.new(List<&2, String>, expectedTexts)
    +lastDetails : R.Ref<Maybe<&2, Details()>> <- R.new(Maybe<&2, Details()>, None{})
    +lastMessage : R.Ref<Maybe<&2, R.Ref<Message()>>> <- R.new(Maybe<&2, R.Ref<Message()>>, None{})
    +events : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +ready : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +sink : Sink() <- C.create(~Environment, ~Event(), ~Emitted(), ~emit, Environment{mode, failAt, calls, first, third, texts, lastDetails, lastMessage, events, trace, ready, release})
    running : Chan(Output()) <- IO.fork(Output(), task(calls, sink, Loop.TruncatedToolCallScope{details, results, messages, batches}, done))
    Response.drive(expectedEvents, ready, release, done)
    result : Output() <- IO.join(Output(), running)
    check(result, expected, expectedIds)
    observedTrace : String <- R.dispose(String, trace)
    Test.assertion(String.eq(observedTrace, expectedTrace), "truncated-call event trace differs")
    observedEvents : U32 <- R.dispose(U32, events)
    Test.assertion(U32.is_eq(observedEvents, expectedEvents), "truncated-call event count differs")
    remaining : List<&2, String> <- R.dispose(List<&2, String>, texts)
    noTexts(remaining)
    C.dispose(Event(), Emitted(), sink)
    Chan.close(Unit, ready)
    Chan.close(Unit, release)
    D.dispose(Unit, done)
    oldDetails : Maybe<&2, Details()> <- R.dispose(Maybe<&2, Details()>, lastDetails)
    oldMessage : Maybe<&2, R.Ref<Message()>> <- R.dispose(Maybe<&2, R.Ref<Message()>>, lastMessage)
    disposeOwner(List<&2, R.Ref<Message()>>, batches)
    disposeOwner(Message(), messages)
    disposeOwner(ResultValue(), results)
    disposeOwner(Record.Record<Bool>, details)
    oldCalls : List<&2, T.AgentToolCall(String)> <- R.dispose(List<&2, T.AgentToolCall(String)>, calls)
    oldFirst : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, first)
    oldSecond : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, second)
    oldThird : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, third)
    return Unit{}
