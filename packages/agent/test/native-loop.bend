import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ./context.bend as H
import ./turn-update.bend as ConfigTest
import ../../runtime/src/schema-value.bend as Schema

def Config() -> Data: ConfigTest.Config()
def Message() -> Data: Ai.AssistantMessage<Schema.Value, Unit>
def EventValue() -> Data: T.AgentEvent<Unit, String, String, Unit, Unit>
def Log() -> Data: R.Ref<List<&2, String>>
def Input() -> Data: T.StreamInput<Unit, String, Config()>
def StreamValue() -> Data: Stream.AssistantMessageEventStream(Schema.Value, Unit)
def ConvertResult() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, String>>>
def TransformInput() -> Data: T.TransformContextInput<H.Messages()>
def TransformResult() -> Data: Result<&2, &2, String, H.Messages()>

type ProviderState is Data:
  ProviderState{log: Log(), stream: StreamValue()}
type SinkState is Data:
  SinkState{log: Log(), events: R.Ref<List<&2, EventValue()>>, failUpdate: Bool}
type TransformState is Data:
  TransformState{log: Log(), fail: Bool}

def log(value: Log(), item: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, value, entries => (item <> entries, Unit{}))

def message(text: String, reason: Ai.StopReason) -> Message():
  +zero = F.fromU32(0)
  Test.assistant(Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), reason)

def messageText(value: Message()) -> String:
  match value:
    case Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: text
    case _: "invalid"

def convertBody(state: TransformState, values: H.Messages()) -> IO(ConvertResult()):
  match state:
    case TransformState{logValue, fail}:
      do IO<ConvertResult()>:
        log(logValue, "convert")
        Test.assertion(Nat.is_eq(List.length(&2, H.Message(), values), 2n), "converter must receive transformed messages")
        return Bool.pick(ConvertResult(), fail, Fail{"convert failed"}, Done{Ai.User{Ai.UserMessage{Ai.UserText{"converted"}, F.fromU32(0)}} <> Nil{}})

def transformBody(state: TransformState, input: TransformInput()) -> IO(TransformResult()):
  match state input:
    case TransformState{logValue, fail} T.TransformContextInput{messages, _}:
      do IO<TransformResult()>:
        log(logValue, "transform")
        return Bool.pick(TransformResult(), fail, Fail{"transform failed"}, Done{List.append(&2, H.Message(), messages, T.CustomMessage{"transformed"} <> Nil{})})

def keyBody(state: TransformState, provider: String) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match state:
    case TransformState{logValue, fail}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        log(logValue, "key")
        return Bool.pick(Result<&2, &2, String, Maybe<&2, String>>, fail, Fail{"key failed"}, Done{Some{"resolved"}})

def checkKey(value: Result<&2, &2, String, Maybe<&2, String>>) -> IO(Unit):
  match value:
    case Done{Some{key}}: Test.assertion(String.eq(key, "resolved"), "provider must receive resolved credentials")
    case _: Test.assertion(False{}, "missing resolved key")

def checkOptions(options: Maybe<&2, Config()>) -> IO(Unit):
  match options:
    case None{}: Test.assertion(False{}, "missing request configuration")
    case Some{value}: checkKey(Loop.fallbackApiKey(Unit, String, String, String, Unit, value))

def checkTranscript(context: Ai.TranscriptContext<Schema.Value, Schema.Value, Unit, String>) -> IO(Unit):
  match context:
    case Ai.TranscriptContext{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> Nil{}}:
      Test.assertion(String.eq(text, "converted"), "provider must receive converted transcript")
    case _: Test.assertion(False{}, "provider transcript shape")

def ProviderOutput() -> Type: Result<&2, &1, String, T.StreamLease<Unit, String>>
def providerBody(state: ProviderState, input: Input()) -> IO(ProviderOutput()):
  match state input:
    case ProviderState{logValue, +stream} T.StreamInput{_, context, options}:
      do IO<ProviderOutput()>:
        log(logValue, "provider")
        checkOptions(options)
        checkTranscript(context)
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Message(), stream, Ai.Start{message("first", Ai.Pending{})})
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Message(), stream, Ai.TextDelta{F.fromU32(0), "second", message("second", Ai.Pending{})})
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Message(), stream, Ai.StreamDone{Ai.DoneStop{}, message("second", Ai.Stop{})})
        return Done{T.borrowedStream(Unit, String, stream)}

def updateEvent(event: EventValue()) -> Bool:
  match event:
    case T.MessageUpdate{_, _}: True{}
    case _: False{}

def sinkBody(state: SinkState, event: EventValue()) -> IO(Result<&2, &2, String, Unit>):
  match state:
    case SinkState{logValue, events, failUpdate}:
      do IO<Result<&2, &2, String, Unit>>:
        +current : EventValue() = event
        log(logValue, T.eventType(Unit, String, String, Unit, Unit, current))
        R.modify(List<&2, EventValue()>, Unit, events, values => (current <> values, Unit{}))
        return Bool.pick(Result<&2, &2, String, Unit>, failUpdate && updateEvent(current), Fail{"listener failed"}, Done{Unit{}})

def checkOutcome(outcome: Result<&2, &2, String, Message()>, expected: String) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(String.eq(error, expected), "request error propagation")
    case Done{value}: Test.assertion(String.eq(messageText(value), expected), "request final message")

def checkRetained(events: List<&2, EventValue()>) -> IO(Unit):
  match events:
    case T.MessageStart{T.LlmMessage{Ai.Assistant{first}}} <> T.MessageUpdate{T.LlmMessage{Ai.Assistant{second}}, _} <> _:
      Test.assertion(String.eq(messageText(first), "first") && String.eq(messageText(second), "second"), "retained events must preserve their own snapshots")
    case _: Test.assertion(False{}, "missing start/update snapshots")

def checkContext(context: H.Context()) -> IO(Unit):
  match context:
    case T.AgentContext{T.CustomMessage{original} <> T.LlmMessage{Ai.Assistant{final}} <> Nil{}, _}:
      Test.assertion(String.eq(original, "original") && String.eq(messageText(final), "second"), "agent state must preserve prior messages and replace the streaming message")
    case _: Test.assertion(False{}, "request context transition changed transcript shape")

def scenario(+failTransform: Bool, failUpdate: Bool, +failConvert: Bool, +failKey: Bool, expected: String, expectedTrace: String) -> IO(Unit):
  do IO<Unit>:
    +logValue : Log() <- R.new(List<&2, String>, Nil{})
    +events : R.Ref<List<&2, EventValue()>> <- R.new(List<&2, EventValue()>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{T.CustomMessage{"original"} <> Nil{}, None{}})
    +stream : StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
    +converter : C.Callback<H.Messages(), ConvertResult()> <- C.create(~TransformState, ~H.Messages(), ~ConvertResult(), ~convertBody, TransformState{logValue, failConvert})
    +transformer : C.Callback<TransformInput(), TransformResult()> <- C.create(~TransformState, ~TransformInput(), ~TransformResult(), ~transformBody, TransformState{logValue, failTransform})
    +resolver : C.Callback<String, Result<&2, &2, String, Maybe<&2, String>>> <- C.create(~TransformState, ~String, ~Result<&2, &2, String, Maybe<&2, String>>, ~keyBody, TransformState{logValue, failKey})
    +provider : C.Callback<Input(), ProviderOutput()> <- C.create(~ProviderState, ~Input(), ~ProviderOutput(), ~providerBody, ProviderState{logValue, stream})
    +sink : C.Callback<EventValue(), Result<&2, &2, String, Unit>> <- C.create(~SinkState, ~EventValue(), ~Result<&2, &2, String, Unit>, ~sinkBody, SinkState{logValue, events, failUpdate})
    config : Config() = T.AgentLoopConfig{Ai.SimpleStreamOptions{None{}, None{}, Some{"fallback"}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, Some{transformer}, Some{resolver}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
    outcome : Result<&2, &2, String, Message()> <- Loop.streamAssistantResponse(Unit, String, String, String, Unit, Unit, Unit, Loop.AssistantRequest{context, config, None{}, sink, provider})
    checkOutcome(outcome, expected)
    trace : List<&2, String> <- R.read(List<&2, String>, logValue)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), expectedTrace), "awaited callback/event order or failure short-circuit changed")
    +failedBeforeStream : Bool = failTransform || failConvert || failKey
    saved : List<&2, EventValue()> <- R.read(List<&2, EventValue()>, events)
    Bool.pick(IO(Unit), failedBeforeStream, IO.pure(Unit, Unit{}), checkRetained(List.reverse(&2, EventValue(), saved)))
    current : H.Context() <- R.read(H.Context(), context)
    Bool.pick(IO(Unit), failedBeforeStream, IO.pure(Unit, Unit{}), checkContext(current))
    C.dispose(H.Messages(), ConvertResult(), converter)
    C.dispose(TransformInput(), TransformResult(), transformer)
    C.dispose(String, Result<&2, &2, String, Maybe<&2, String>>, resolver)
    C.dispose(Input(), ProviderOutput(), provider)
    C.dispose(EventValue(), Result<&2, &2, String, Unit>, sink)
    Stream.disposeAssistantMessageEventStream(Schema.Value, Unit, stream)
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    oldEvents : List<&2, EventValue()> <- R.dispose(List<&2, EventValue()>, events)
    oldLog : List<&2, String> <- R.dispose(List<&2, String>, logValue)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, False{}, False{}, False{}, "second", "transform|convert|key|provider|message_start|message_update|message_end")
    scenario(True{}, False{}, False{}, False{}, "transform failed", "transform")
    scenario(False{}, True{}, False{}, False{}, "listener failed", "transform|convert|key|provider|message_start|message_update")
    scenario(False{}, False{}, True{}, False{}, "convert failed", "transform|convert")
    scenario(False{}, False{}, False{}, True{}, "key failed", "transform|convert|key")
    IO.print("PASS immutable request pipeline, callback ordering, snapshots and error short-circuiting")
