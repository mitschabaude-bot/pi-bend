import Base
import ../src/main-loop.bend as Main
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../src/tool-call.bend as Call
import ../src/event-emission.bend as E
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/src/utils/model-api.bend as Api
import ../../ai/src/utils/tool-declaration.bend as D
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./validated-tool-execution.bend as H
import ./message-events.bend as Test

def Assistant() -> Data: Ai.AssistantMessage<V.Value, Unit>
def StreamValue() -> Data: Stream.AssistantMessageEventStream(V.Value, Unit)
def ProviderInput() -> Data: T.StreamInput<V.Value, V.Value, Unit, String, Unit, H.Config()>
def Turn() -> Data: T.ShouldStopAfterTurnContext<V.Value, V.Value, Unit, String, String, V.Value, Unit, String>
def Update() -> Data: T.AgentLoopTurnUpdate<V.Value, V.Value, Unit, String, String, V.Value, Unit, String, Unit>
def PrepareOutput() -> Data: Result<&2, &2, String, Maybe<&2, Update()>>
def QueueOutput() -> Data: Result<&2, &2, String, H.Messages()>
def Outcome() -> Data: Result<&2, &2, String, H.Messages()>
def Log() -> Data: R.Ref<List<&2, String>>

type Provider is Data:
  Provider{kind: U32, count: R.Ref<U32>, log: Log(), requests: Log(), streams: R.Ref<List<&2, StreamValue()>>}
type Execution is Data:
  Execution{terminate: Bool, count: R.Ref<U32>}
type Queue is Data:
  Queue{name: String, enabled: Bool, count: R.Ref<U32>, log: Log()}
type Stopping is Data:
  Stopping{stop: Bool, log: Log()}
type Recording is Data:
  Recording{failAt: String, log: Log()}

def log(reference: Log(), entry: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, reference, values => (entry <> values, Unit{}))

def bump(reference: R.Ref<U32>) -> IO(U32):
  R.modify(U32, U32, reference, +value => ((value + 1 : U32), value))

def assistant(content: List<&2, Ai.AssistantContent<V.Value>>, reason: Ai.StopReason) -> Assistant():
  +zero = F.fromU32(0)
  Ai.AssistantMessage{content, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), reason, None{}, None{}, None{}, None{}, zero}

def text(value: String) -> List<&2, Ai.AssistantContent<V.Value>>: Ai.AssistantText{Ai.TextContent{value, None{}}} <> Nil{}
def toolContent() -> List<&2, Ai.AssistantContent<V.Value>>: Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", H.field(V.Text{"42"}), None{}, None{}}} <> Nil{}

def response(kind: U32, count: U32) -> Assistant():
  match kind count:
    case 0 0: assistant(toolContent(), Ai.ToolUse{})
    case 1 0: assistant(toolContent(), Ai.Length{})
    case 2 0: assistant(text("error"), Ai.Error{})
    case 3 0: assistant(toolContent(), Ai.Aborted{})
    case _ _: assistant(text("done"), Ai.Stop{})

def finalEvent(+message: Assistant()) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, _, _, _, _}: Ai.StreamError{Ai.ErrorError{}, message}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, _, _, _, _}: Ai.StreamError{Ai.ErrorAborted{}, message}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}: Ai.StreamDone{Ai.DoneLength{}, message}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.ToolUse{}, _, _, _, _, _}: Ai.StreamDone{Ai.DoneToolUse{}, message}
    case _: Ai.StreamDone{Ai.DoneStop{}, message}

def assistantName(message: Assistant()) -> String:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, _, _, _, _}: "assistant:error"
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, _, _, _, _}: "assistant:aborted"
    case Ai.AssistantMessage{Ai.AssistantToolCall{_} <> _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: "assistant:tool"
    case Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{value, _}} <> _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: "assistant:" ++ value
    case _: "unexpected"

def llmName(message: Ai.Message<V.Value, V.Value, Unit, String>) -> String:
  match message:
    case Ai.System{_}: "system"
    case Ai.User{Ai.UserMessage{Ai.UserText{value}, _}}: value
    case Ai.Assistant{value}: assistantName(value)
    case Ai.ToolResult{Ai.ToolResultMessage{_, _, _, _, _, isError, _}}: Bool.pick(String, isError, "tool:error", "tool:ok")
    case _: "unexpected"

def names(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.CustomMessage{value} <> rest: value ++ "|" ++ names(rest)
    case T.LlmMessage{message} <> rest: llmName(message) ++ "|" ++ names(rest)

def llmNames(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: llmName(message) ++ "|" ++ llmNames(rest)

def converted(messages: H.Messages()) -> List<&2, Ai.Message<V.Value, V.Value, Unit, String>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{message} <> rest: message <> converted(rest)
    case T.CustomMessage{value} <> rest: Ai.User{Ai.UserMessage{Ai.UserText{value}, F.fromU32(0)}} <> converted(rest)

def convert(recording: Log(), messages: H.Messages()) -> IO(H.Converted()):
  do IO<H.Converted()>:
    log(recording, "convert")
    return Done{converted(messages)}

def provider(environment: Provider, input: ProviderInput()) -> IO(StreamValue()):
  match environment input:
    case Provider{kind, count, recording, requests, streams} T.StreamInput{model, Ai.TranscriptContext{messages}, _}:
      do IO<StreamValue()>:
        +index : U32 <- bump(count)
        Test.assertion(U32.is_lt(index, 4), "loop must settle rather than spin")
        Test.assertion(String.eq(Api.name(Api.modelApi(Unit, model)), Bool.pick(String, U32.is_eq(index, 0), "original", "changed")), "next-turn model reaches the provider")
        log(requests, llmNames(messages))
        log(recording, "provider")
        +stream : StreamValue() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Assistant(), stream, Ai.Start{assistant(text("partial"), Ai.Pending{})})
        Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Assistant(), stream, finalEvent(response(kind, index)))
        return stream

def execute(environment: Execution, input: H.ExecuteInput()) -> IO(H.ExecuteOutput()):
  match environment input:
    case Execution{terminate, count} T.ToolExecutionInput{id, arguments, _, _}:
      do IO<H.ExecuteOutput()>:
        Test.assertion(String.eq(id, "call") && V.equal(arguments, H.field(V.Number{F.fromU32(42)})), "full loop executes validated arguments")
        ignored : U32 <- bump(count)
        return Done{T.AgentToolResult{Nil{}, "tool", None{}, Some{terminate}}}

def validate(count: R.Ref<U32>, input: H.Input()) -> IO(H.Checked()):
  do IO<H.Checked()>:
    ignored : U32 <- bump(count)
    H.validate(Unit{}, input)

def queueValue(enabled: Bool, name: String, shouldDeliver: Bool) -> QueueOutput():
  Done{Bool.pick(H.Messages(), enabled && shouldDeliver, T.CustomMessage{name} <> Nil{}, Nil{})}

def queue(environment: Queue, unused: Unit) -> IO(QueueOutput()):
  match environment:
    case Queue{+name, enabled, count, recording}:
      do IO<QueueOutput()>:
        +index : U32 <- bump(count)
        log(recording, name)
        return queueValue(enabled, name, Bool.pick(Bool, String.eq(name, "steering"), U32.is_eq(index, 1), U32.is_eq(index, 0)))

def stop(environment: Stopping, input: Turn()) -> IO(Result<&2, &2, String, Bool>):
  match environment input:
    case Stopping{shouldStop, recording} T.ShouldStopAfterTurnContext{_, _, T.AgentContext{context, _}, history}:
      do IO<Result<&2, &2, String, Bool>>:
        Test.assertion(String.eq(names(context), "old|" ++ names(history)), "stop hook sees committed context and generated history")
        log(recording, "stop")
        return Done{shouldStop}

def prepare(recording: Log(), input: Turn()) -> IO(PrepareOutput()):
  match input:
    case T.ShouldStopAfterTurnContext{_, _, T.AgentContext{context, _}, history}:
      do IO<PrepareOutput()>:
        Test.assertion(String.eq(names(context), "old|" ++ names(history)), "next-turn hook receives the completed snapshot")
        log(recording, "prepare")
        return Done{Some{T.AgentLoopTurnUpdate{None{}, Some{T.CustomMessage{"prepared"} <> Nil{}}, Some{Model.model(Ai.CustomModelApi{"changed"}, None{})}, Some{Ai.Off{}}}}}

def key(event: H.EventValue()) -> String:
  match event:
    case T.MessageStart{T.CustomMessage{value}}: "message_start:" ++ value
    case T.MessageEnd{T.CustomMessage{value}}: "message_end:" ++ value
    case T.MessageStart{T.LlmMessage{message}}: "message_start:" ++ llmName(message)
    case T.MessageEnd{T.LlmMessage{message}}: "message_end:" ++ llmName(message)
    case T.ToolExecutionStart{id, _, _}: "tool_execution_start:" ++ id
    case T.ToolExecutionEnd{id, _, _, _}: "tool_execution_end:" ++ id
    case other: T.eventType(V.Value, V.Value, Unit, String, String, T.AgentToolResult<String>, T.AgentToolResult<String>, other)

def emit(environment: Recording, event: H.EventValue()) -> IO(E.Emission<String>):
  match environment:
    case Recording{failAt, recording}:
      do IO<E.Emission<String>>:
        +name : String = key(event)
        log(recording, name)
        return E.Ready{Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{"delivery failed"}, Done{Unit{}})}

def abort(unused: Unit, signal: Maybe<&2, Unit>) -> IO(Bool): IO.pure(Bool, False{})
def render(error: String) -> String: error
def declarationError(error: D.DeclarationError) -> String: "declaration failed"

def disposeStreams(streams: List<&2, StreamValue()>) -> IO(Unit):
  match streams:
    case Nil{}: IO.pure(Unit, Unit{})
    case stream <> rest:
      do IO<Unit>:
        Stream.disposeAssistantMessageEventStream(V.Value, Unit, stream)
        disposeStreams(rest)

def checked(outcome: Outcome(), history: String, error: String) -> IO(Unit):
  match outcome:
    case Done{messages}: Test.assertion(String.is_empty(error) && String.eq(names(messages), history), "full loop returns ordered generated history")
    case Fail{value}: Test.assertion(String.eq(value, error), "full loop propagates the first error")

def scenario(kind: U32, terminate: Bool, steeringEnabled: Bool, followEnabled: Bool, shouldStop: Bool, failAt: String, expectedHistory: String, expectedError: String, expectedTrace: String, expectedRequests: String, expectedProviders: U32, expectedExecutions: U32, expectedValidations: U32) -> IO(Unit):
  do IO<Unit>:
    +recording : Log() <- R.new(List<&2, String>, Nil{})
    +requests : Log() <- R.new(List<&2, String>, Nil{})
    +streams : R.Ref<List<&2, StreamValue()>> <- R.new(List<&2, StreamValue()>, Nil{})
    +providerCount : R.Ref<U32> <- R.new(U32, 0)
    +executionCount : R.Ref<U32> <- R.new(U32, 0)
    +validationCount : R.Ref<U32> <- R.new(U32, 0)
    +steeringCount : R.Ref<U32> <- R.new(U32, 0)
    +followCount : R.Ref<U32> <- R.new(U32, 0)
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~Execution, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~execute, Execution{terminate, executionCount})
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~R.Ref<U32>, ~H.Input(), ~H.Checked(), ~validate, validationCount)
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Log(), ~H.Messages(), ~H.Converted(), ~convert, recording)
    +providerCallback : C.Callback<ProviderInput(), StreamValue()> <- C.create(~Provider, ~ProviderInput(), ~StreamValue(), ~provider, Provider{kind, providerCount, recording, requests, streams})
    +stopHook : C.Callback<Turn(), Result<&2, &2, String, Bool>> <- C.create(~Stopping, ~Turn(), ~Result<&2, &2, String, Bool>, ~stop, Stopping{shouldStop, recording})
    +prepareHook : C.Callback<Turn(), PrepareOutput()> <- C.create(~Log(), ~Turn(), ~PrepareOutput(), ~prepare, recording)
    +steering : C.Callback<Unit, QueueOutput()> <- C.create(~Queue, ~Unit, ~QueueOutput(), ~queue, Queue{"steering", steeringEnabled, steeringCount, recording})
    +follow : C.Callback<Unit, QueueOutput()> <- C.create(~Queue, ~Unit, ~QueueOutput(), ~queue, Queue{"follow", followEnabled, followCount, recording})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~abort, Unit{})
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~Recording, ~H.EventValue(), ~E.Emission<String>, ~emit, Recording{failAt, recording})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~V.Value, ~V.Value, ~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +updates : Call.Owners(String, String) <- Call.newOwners(String, String)
    +batches : Main.Batches(V.Value, Unit, String, String, V.Value, Unit, String) <- Main.newBatches(V.Value, Unit, String, String, V.Value, Unit, String)
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{T.CustomMessage{"old"} <> T.CustomMessage{"prompt"} <> Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    config : H.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, Some{stopHook}, Some{prepareHook}, Some{steering}, Some{follow}, None{}, None{}, None{}}
    outcome : Outcome() <- Main.runLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~render, ~declarationError, Main.Capture{Some{Unit{}}, validator, aborted, emitter, sink, updates, batches, "empty", providerCallback}, context, config, T.CustomMessage{"prompt"} <> Nil{})
    checked(outcome, expectedHistory, expectedError)
    Main.disposeBatches(V.Value, Unit, String, String, V.Value, Unit, String, batches)
    Call.disposeOwners(String, String, updates)
    trace : List<&2, String> <- R.read(List<&2, String>, recording)
    requestList : List<&2, String> <- R.read(List<&2, String>, requests)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), expectedTrace), "full loop event/callback order")
    Test.assertion(String.eq(String.join(List.reverse(&2, String, requestList), ";"), expectedRequests), "provider requests include committed tool results and prepared/queued messages")
    providers : U32 <- R.read(U32, providerCount)
    executions : U32 <- R.read(U32, executionCount)
    validations : U32 <- R.read(U32, validationCount)
    Test.assertion(U32.is_eq(providers, expectedProviders) && U32.is_eq(executions, expectedExecutions) && U32.is_eq(validations, expectedValidations), "full loop invocation counts and truncated/failed response isolation")
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(ProviderInput(), StreamValue(), providerCallback)
    C.dispose(Turn(), Result<&2, &2, String, Bool>, stopHook)
    C.dispose(Turn(), PrepareOutput(), prepareHook)
    C.dispose(Unit, QueueOutput(), steering)
    C.dispose(Unit, QueueOutput(), follow)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), E.Emission<String>, emitter)
    ownedStreams : List<&2, StreamValue()> <- R.dispose(List<&2, StreamValue()>, streams)
    disposeStreams(ownedStreams)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, recording)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, requests)
    discarded : U32 <- R.dispose(U32, providerCount)
    discarded : U32 <- R.dispose(U32, executionCount)
    discarded : U32 <- R.dispose(U32, validationCount)
    discarded : U32 <- R.dispose(U32, steeringCount)
    discarded : U32 <- R.dispose(U32, followCount)
    return Unit{}
