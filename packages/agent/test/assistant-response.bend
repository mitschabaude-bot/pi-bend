import Base
import ./turn-update.bend as U
import ../../ai/test/model-types.bend as Model
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as E
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as F

def Message() -> Data: Ai.AssistantMessage<String, Unit>
def SourceEvent() -> Data: Ai.AssistantMessageEvent<String, Unit>
def AgentEvent() -> Data: T.AgentEvent<Unit, String, Unit, String, String, Unit, Unit>
def Output() -> Data: Result<&2, &2, String, R.Ref<Message()>>
def Emitted() -> Data: Result<&2, &2, String, Unit>
def Sink() -> Data: Loop.AgentEventSink(Unit, String, Unit, String, String, Unit, Unit, String)
def Stream() -> Data: E.AssistantMessageEventStream(String, Unit)
def Consumer() -> Data: Loop.AssistantResponseConsumer<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit>
def Request() -> Data: Loop.AssistantRequest<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, Unit, Unit>
def ProviderInput() -> Data: T.StreamInput<Unit, String, Unit, String, Unit, U.Config()>
def Provider() -> Data: T.StreamFn(Unit, String, Unit, String, Unit, U.Config())
def Normalized() -> Data: Ai.TranscriptContext<Unit, String, Unit, String>
def LlmMessages() -> Data: R.Ref<List<&2, Ai.Message<Unit, String, Unit, String>>>
type ConverterEnvironment is Data:
  ConverterEnvironment{expected: H.Messages(), output: LlmMessages(), count: R.Ref<U32>, fail: Bool}
type ProviderEnvironment is Data:
  ProviderEnvironment{stream: Stream(), model: R.Ref<Ai.Model<Unit>>, config: R.Ref<U.Config()>, converter: U.Converter(), llm: LlmMessages(), ready: Chan(Unit), release: Chan(Unit), count: R.Ref<U32>}

type Environment is Data:
  Environment{mode: U32, failAt: U32, partial: R.Ref<Message()>, update: R.Ref<Message()>, final: R.Ref<Message()>, messages: H.Messages(), extra: R.Ref<String>, trace: R.Ref<String>, count: R.Ref<U32>, ready: Chan(Unit), release: Chan(Unit)}

def named(value: Message(), name: String) -> Message():
  match value:
    case Ai.AssistantMessage{content, api, provider, _, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}: Ai.AssistantMessage{content, api, provider, name, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}

def name(value: Message()) -> String:
  match value:
    case Ai.AssistantMessage{_, _, _, model, _, _, _, _, _, _, _, _, _, _, _}: model

def eventMessage(event: AgentEvent()) -> IO(R.Ref<Message()>):
  match event:
    case T.MessageStart{T.LlmMessage{Ai.Assistant{message}}}: IO.pure(R.Ref<Message()>, message)
    case T.MessageUpdate{T.LlmMessage{Ai.Assistant{message}}, _}: IO.pure(R.Ref<Message()>, message)
    case T.MessageEnd{T.LlmMessage{Ai.Assistant{message}}}: IO.pure(R.Ref<Message()>, message)
    case _: IO.die(R.Ref<Message()>, 1, "unexpected assistant event")

def sourceFor(+id: String, partial: R.Ref<Message()>, update: R.Ref<Message()>, final: R.Ref<Message()>) -> R.Ref<Message()>:
  Bool.pick(R.Ref<Message()>, String.eq(id, "p"), partial, Bool.pick(R.Ref<Message()>, String.eq(id, "u"), update, final))

def inject(enabled: Bool, messages: H.Messages(), extra: R.Ref<String>) -> IO(Unit):
  match enabled:
    case True{}: R.modify(List<&2, H.Message()>, Unit, messages, values => (List.append(&2, H.Message(), values, T.CustomMessage{extra} <> Nil{}), Unit{}))
    case False{}: IO.pure(Unit, Unit{})

def emitShared(environment: Environment, +event: AgentEvent()) -> IO(Emitted()):
  match environment:
    case Environment{mode, failAt, partial, update, final, messages, extra, trace, count, ready, release}:
      do IO<Emitted()>:
        +message : R.Ref<Message()> <- eventMessage(event)
        value : Message() <- R.read(Message(), message)
        +id : String = name(value)
        +kind : String = T.eventType(Unit, String, Unit, String, String, Unit, Unit, event)
        original : R.Ref<Message()> = sourceFor(id, partial, update, final)
        +same : Bool = R.same(Message(), message, original)
        Test.assertion(Bool.pick(Bool, String.eq(kind, "message_end"), same, Bool.not(same)), "stream event snapshot/live identity differs")
        R.modify(String, Unit, trace, old => (old ++ kind ++ ":" ++ id ++ "|", Unit{}))
        +index : U32 <- R.modify(U32, U32, count, +n => (U32.add(n, 1), n))
        inject(U32.is_eq(mode, 8) && U32.is_eq(index, 0), messages, extra)
        sent : Bool <- Chan.send(Unit, ready, Unit{})
        token : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Bool.pick(Emitted(), U32.is_eq(index, failAt), Fail{"listener failure"}, Done{Unit{}})

def emit(environment: Environment, event: AgentEvent()) -> IO(Emitted()):
  emitShared(environment, event)

def pushStart(stream: Stream(), message: R.Ref<Message()>, include: Bool) -> IO(Unit):
  match include:
    case True{}: E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.Start{message})
    case False{}: IO.pure(Unit, Unit{})

def updates(+stream: Stream(), +message: R.Ref<Message()>, call: R.Ref<Ai.ToolCall<String>>) -> IO(Unit):
  do IO<Unit>:
    +index : F.F64 = F.fromU32(0)
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.TextStart{index, message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.TextDelta{index, "x", message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.TextEnd{index, "x", message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ThinkingStart{index, message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ThinkingDelta{index, "x", message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ThinkingEnd{index, "x", message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ToolcallStart{index, message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ToolcallDelta{index, "x", message})
    E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.ToolcallEnd{index, call, message})

def pushMiddle(mode: U32, stream: Stream(), message: R.Ref<Message()>, call: R.Ref<Ai.ToolCall<String>>) -> IO(Unit):
  match mode:
    case 2: E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.TextStart{F.fromU32(0), message})
    case 3: updates(stream, message, call)
    case 6: pushStart(stream, message, True{})
    case 8: E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.TextStart{F.fromU32(0), message})
    case _: IO.pure(Unit, Unit{})

def terminal(mode: U32, stream: Stream(), final: R.Ref<Message()>) -> IO(Unit):
  match mode:
    case 4: E.end(SourceEvent(), R.Ref<Message()>, stream, Some{final})
    case 5: E.end(SourceEvent(), R.Ref<Message()>, stream, Some{final})
    case 7: E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.StreamError{Ai.ErrorError{}, final})
    case _: E.push(SourceEvent(), R.Ref<Message()>, stream, Ai.StreamDone{Ai.DoneStop{}, final})

def convert(environment: ConverterEnvironment, messages: H.Messages()) -> IO(U.Output()):
  match environment:
    case ConverterEnvironment{expected, output, count, fail}:
      do IO<U.Output()>:
        Test.assertion(R.same(List<&2, H.Message()>, messages, expected), "full request conversion input changed")
        R.modify(U32, Unit, count, n => (U32.add(n, 1), Unit{}))
        return Bool.pick(U.Output(), fail, Fail{"conversion failure"}, Done{output})

def checkNormalized(value: Normalized(), expected: LlmMessages()) -> IO(Unit):
  match value:
    case Ai.TranscriptContext{messages}: Test.assertion(R.same(List<&2, Ai.Message<Unit, String, Unit, String>>, messages, expected), "full request normalized array changed")

def provide(environment: ProviderEnvironment, input: ProviderInput()) -> IO(Stream()):
  match environment input:
    case ProviderEnvironment{stream, +model, config, converter, llm, ready, release, count} T.StreamInput{actualModel, normalized, Some{+options}}:
      do IO<Stream()>:
        Test.assertion(R.same(Ai.Model<Unit>, actualModel, model), "provider model identity changed")
        Test.assertion(Bool.not(R.same(U.Config(), options, config)), "provider received original config instead of snapshot")
        normalizedValue : Normalized() <- R.read(Normalized(), normalized)
        checkNormalized(normalizedValue, llm)
        value : U.Config() <- R.read(U.Config(), options)
        retained : String <- U.view(value, model, converter)
        Test.assertion(String.eq(retained, "none|true"), "full request dropped agent-only converter or session fields")
        R.modify(U32, Unit, count, n => (U32.add(n, 1), Unit{}))
        sent : Bool <- Chan.send(Unit, ready, Unit{})
        token : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return stream
    case _ _: IO.die(Stream(), 1, "full request omitted provider options")

def task(consumer: Consumer(), request: Request(), full: Bool, done: D.Deferred<Unit>) -> IO(Output()):
  do IO<Output()>:
    result : Output() <- Bool.pick(IO(Output()), full, Loop.streamAssistantResponse(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, Unit, Unit, request), Loop.consumeAssistantResponse(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, consumer))
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

@unsafe
def drive(count: U32, +ready: Chan(Unit), +release: Chan(Unit), +done: D.Deferred<Unit>) -> IO(Unit):
  match count:
    case 0: IO.pure(Unit, Unit{})
    case _:
      do IO<Unit>:
        token : Maybe<&1, Unit> <- Chan.recv(Unit, ready)
        status : Maybe<&2, Unit> <- D.peek(Unit, done)
        Test.assertion(Maybe.is_none(&2, Unit, status), "stream listener was not awaited")
        sent : Bool <- Chan.send(Unit, release, Unit{})
        drive(U32.sub(count, 1), ready, release, done)

def checkResult(result: Output(), final: R.Ref<Message()>, expected: String) -> IO(Unit):
  match result:
    case Fail{error}: Test.assertion(String.eq(error, expected), "stream listener failure changed")
    case Done{message}: Test.assertion(String.eq(expected, "final") && R.same(Message(), message, final), "consumer did not return exact stream result")

def messageNames(values: List<&2, H.Message()>) -> IO(String):
  match values:
    case Nil{}: IO.pure(String, "")
    case T.LlmMessage{Ai.Assistant{message}} <> rest:
      do IO<String>:
        value : Message() <- R.read(Message(), message)
        tail : String <- messageNames(rest)
        return name(value) ++ "|" ++ tail
    case T.CustomMessage{extra} <> rest:
      do IO<String>:
        value : String <- R.read(String, extra)
        tail : String <- messageNames(rest)
        return value ++ "|" ++ tail
    case _ <> _: IO.die(String, 1, "unexpected transcript message")

def disposeSnapshots(values: List<&2, R.Ref<Message()>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        old : Message() <- R.dispose(Message(), reference)
        disposeSnapshots(rest)

def checkOwnerCount(-Value: Data, values: List<&2, Value>, expectedOne: Bool) -> IO(Unit):
  match values expectedOne:
    case Nil{} False{}: IO.pure(Unit, Unit{})
    case _ <> Nil{} True{}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "request allocation count differs")

def disposeContexts(values: List<&2, R.Ref<Normalized()>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        old : Normalized() <- R.dispose(Normalized(), reference)
        disposeContexts(rest)

def disposeConfigurations(values: List<&2, R.Ref<U.Config()>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        old : U.Config() <- R.dispose(U.Config(), reference)
        disposeConfigurations(rest)

def runCase(+full: Bool, +mode: U32, failAt: U32, expected: String, expectedTrace: String, expectedMessages: String, +expectedCount: U32) -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +usage : R.Ref<Ai.Usage> <- R.new(Ai.Usage, Test.usage(cost))
    +content : R.Ref<List<&2, Ai.AssistantContent<String>>> <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +partial : R.Ref<Message()> <- R.new(Message(), named(Test.assistant(content, usage, Ai.Pending{}), "p"))
    +update : R.Ref<Message()> <- R.new(Message(), named(Test.assistant(content, usage, Ai.Pending{}), "u"))
    +final : R.Ref<Message()> <- R.new(Message(), named(Test.assistant(content, usage, Ai.Stop{}), "f"))
    +call : R.Ref<Ai.ToolCall<String>> <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"call", "tool", "args", None{}, None{}})
    +messages : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{messages, None{}})
    +snapshots : R.Ref<List<&2, R.Ref<Message()>>> <- R.new(List<&2, R.Ref<Message()>>, Nil{})
    +extra : R.Ref<String> <- R.new(String, "extra")
    +trace : R.Ref<String> <- R.new(String, "")
    +count : R.Ref<U32> <- R.new(U32, 0)
    +ready : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +sink : Sink() <- C.create(~Environment, ~AgentEvent(), ~Emitted(), ~emit, Environment{mode, failAt, partial, update, final, messages, extra, trace, count, ready, release})
    +stream : Stream() <- E.createAssistantMessageEventStream(~String, ~Unit)
    pushStart(stream, partial, Bool.not(U32.is_eq(mode, 0) || U32.is_eq(mode, 2) || U32.is_eq(mode, 4)))
    pushMiddle(mode, stream, update, call)
    terminal(mode, stream, final)
    +preparedContexts : R.Ref<List<&2, R.Ref<Normalized()>>> <- R.new(List<&2, R.Ref<Normalized()>>, Nil{})
    +preparedConfigurations : R.Ref<List<&2, R.Ref<U.Config()>>> <- R.new(List<&2, R.Ref<U.Config()>>, Nil{})
    +llm : LlmMessages() <- R.new(List<&2, Ai.Message<Unit, String, Unit, String>>, Nil{})
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +preparationCount : R.Ref<U32> <- R.new(U32, 0)
    +converter : U.Converter() <- C.create(~ConverterEnvironment, ~H.Messages(), ~U.Output(), ~convert, ConverterEnvironment{messages, llm, preparationCount, U32.is_eq(mode, 9)})
    +config : R.Ref<U.Config()> <- R.new(U.Config(), U.config(model, None{}, converter))
    +provider : Provider() <- C.create(~ProviderEnvironment, ~ProviderInput(), ~Stream(), ~provide, ProviderEnvironment{stream, model, config, converter, llm, ready, release, preparationCount})
    running : Chan(Output()) <- IO.fork(Output(), task(Loop.AssistantResponseConsumer{context, sink, snapshots, stream}, Loop.AssistantRequest{context, config, None{}, sink, provider, preparedContexts, preparedConfigurations, snapshots}, full, done))
    drive(U32.add(expectedCount, Bool.pick(U32, full && Bool.not(U32.is_eq(mode, 9)), 1, 0)), ready, release, done)
    result : Output() <- IO.join(Output(), running)
    checkResult(result, final, expected)
    observedTrace : String <- R.dispose(String, trace)
    Test.assertion(String.eq(observedTrace, expectedTrace), "assistant event trace differs from upstream")
    observedCount : U32 <- R.dispose(U32, count)
    Test.assertion(U32.is_eq(observedCount, expectedCount), "assistant event count differs")
    values : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, messages)
    observedMessages : String <- messageNames(values)
    Test.assertion(String.eq(observedMessages, expectedMessages), "assistant transcript updates differ from upstream")
    retained : List<&2, R.Ref<Message()>> <- R.dispose(List<&2, R.Ref<Message()>>, snapshots)
    disposeSnapshots(retained)
    preparationCalls : U32 <- R.dispose(U32, preparationCount)
    Test.assertion(U32.is_eq(preparationCalls, Bool.pick(U32, full, Bool.pick(U32, U32.is_eq(mode, 9), 1, 2), 0)), "conversion/provider invocation count differs")
    +oldPreparedContexts : List<&2, R.Ref<Normalized()>> <- R.dispose(List<&2, R.Ref<Normalized()>>, preparedContexts)
    checkOwnerCount(R.Ref<Normalized()>, oldPreparedContexts, full && Bool.not(U32.is_eq(mode, 9)))
    disposeContexts(oldPreparedContexts)
    +oldPreparedConfigurations : List<&2, R.Ref<U.Config()>> <- R.dispose(List<&2, R.Ref<U.Config()>>, preparedConfigurations)
    checkOwnerCount(R.Ref<U.Config()>, oldPreparedConfigurations, full && Bool.not(U32.is_eq(mode, 9)))
    disposeConfigurations(oldPreparedConfigurations)
    C.dispose(ProviderInput(), Stream(), provider)
    C.dispose(H.Messages(), U.Output(), converter)
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    oldLlm : List<&2, Ai.Message<Unit, String, Unit, String>> <- R.dispose(List<&2, Ai.Message<Unit, String, Unit, String>>, llm)
    C.dispose(AgentEvent(), Emitted(), sink)
    E.disposeAssistantMessageEventStream(String, Unit, stream)
    Chan.close(Unit, ready)
    Chan.close(Unit, release)
    D.dispose(Unit, done)
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    oldExtra : String <- R.dispose(String, extra)
    oldCall : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, call)
    oldPartial : Message() <- R.dispose(Message(), partial)
    oldUpdate : Message() <- R.dispose(Message(), update)
    oldFinal : Message() <- R.dispose(Message(), final)
    oldContent : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, content)
    oldUsage : Ai.Usage <- R.dispose(Ai.Usage, usage)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    return Unit{}

def run(+mode: U32, +failAt: U32, +expected: String, +expectedTrace: String, +expectedMessages: String, +expectedCount: U32) -> IO(Unit):
  do IO<Unit>:
    runCase(False{}, mode, failAt, expected, expectedTrace, expectedMessages, expectedCount)
    runCase(True{}, mode, failAt, expected, expectedTrace, expectedMessages, expectedCount)

def runConversionFailure(expected: String) -> IO(Unit):
  runCase(True{}, 9, 4294967295, expected, "", "", 0)
