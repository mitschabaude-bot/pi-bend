import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses.bend as P
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/api/openai-sse.bend as Sse
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/url.bend as Absolute
import ../packages/runtime/src/idna.bend as Domain
import ../packages/runtime/src/idna.bend as Label
import ../packages/runtime/src/idna.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../packages/runtime/src/unicode-17-normalization.bend as NormalizationData
import ../packages/runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../packages/runtime/test/utf8-runner.bend as Text
import ./http-resolved-exchange.bend as Setup

# The OpenAI Responses provider end to end over a loopback HTTP server:
# preparation, hooks, native transport, pi's retry policy, SSE processing,
# service-tier pricing, cancellation and resource retirement. The Python
# harness scripts the server and compares every line with the pinned
# upstream wrapper driven by the same events.

def Message() -> Data: T.AssistantMessage<V.Value, Unit>
def AssistantEvent() -> Data: T.AssistantMessageEvent<V.Value, Unit>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)
def Run() -> Type: P.Run<String, Unit, String>
def Outcome() -> Data: P.RunResult<String, Unit, String>
def Hooks() -> Data: Sse.Hooks<Sse.TransportError(String)>

def identity(value: String) -> String: value

def bits(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ "," ++ U32.show(low)

def status(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def encoded(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "invalid"

def shown(value: T.JsonValue) -> String: encoded(Json.stringify(value))

# Hooks
# -----

def replacement(mode: U32) -> Maybe<&2, T.JsonValue>:
  match mode:
    case 14: Some{T.JsonNumber{F.fromU32(9)}}
    case 15: Some{T.JsonNull{}}
    case _: None{}

def payload(+mode: U32, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Maybe<&2, T.JsonValue>>):
  match input:
    case T.PayloadInput{value, _}:
      do IO<Result<&2, &2, String, Maybe<&2, T.JsonValue>>>:
        IO.print("payload:" ++ shown(value) ++ ":model")
        return Bool.pick(Result<&2, &2, String, Maybe<&2, T.JsonValue>>, U32.is_eq(mode, 2), Fail{"payload"}, Done{replacement(mode)})

def response(mode: U32, input: T.ResponseInput<T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{code, headers}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("response:model:" ++ status(F.toBits(code)) ++ ":" ++ Maybe.default(&2, String, R.get(String, headers, "x-response"), "missing"))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 3), Fail{"response"}, Done{Unit{}})

# The SSE hooks observe early iterator closure and JSON diagnostics.
def abortHook(environment: Unit, unused: Unit) -> IO(Unit): IO.print("abort-hook")

def diagnosticHook(environment: Unit, cause: Sse.DispatchError) -> IO(Result<&2, &2, Sse.ReadError<Sse.TransportError(String)>, Unit>):
  do IO<Result<&2, &2, Sse.ReadError<Sse.TransportError(String)>, Unit>>:
    IO.print("diagnostic")
    return Done{Unit{}}

def hooks() -> IO(Hooks()):
  do IO<Hooks()>:
    abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~abortHook, Unit{})
    diagnostic : C.Callback<Sse.DispatchError, Result<&2, &2, Sse.ReadError<Sse.TransportError(String)>, Unit>> <- C.create(~Unit, ~Sse.DispatchError, ~Result<&2, &2, Sse.ReadError<Sse.TransportError(String)>, Unit>, ~diagnosticHook, Unit{})
    return Sse.Hooks{abort, diagnostic}

def retireHooks(value: Hooks()) -> IO(Unit):
  do IO<Unit>:
    Sse.disposeHooks(Sse.TransportError(String), value)
    IO.print("dependencies:closed")

# Display
# -------

def detail(value: Message()) -> String:
  match value:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, None{}, _, _, _}: "none"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, Some{text}, _, _, _}: Text.showText(text)

def stop(value: T.StopReason) -> String:
  match value:
    case T.Pending{}: "pending"
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Deferred{}: "deferred"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"

def contents(values: List<&2, T.AssistantContent<V.Value>>) -> String:
  match values:
    case Nil{}: ""
    case T.AssistantText{T.TextContent{text, _}} <> rest: Text.showText(text) ++ ";" ++ contents(rest)
    case _ <> rest: "other;" ++ contents(rest)

def usage(value: T.Usage) -> String:
  match value:
    case T.Usage{input, output, read, write, _, _, total, T.UsageCost{_, _, _, _, cost}}:
      bits(F.toBits(input)) ++ ":" ++ bits(F.toBits(output)) ++ ":" ++ bits(F.toBits(read)) ++ ":" ++ bits(F.toBits(write)) ++ ":" ++ bits(F.toBits(total)) ++ ":" ++ bits(F.toBits(cost))

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def snapshot(+value: Message()) -> String:
  match value:
    case T.AssistantMessage{blocks, _, _, _, _, id, _, _, tokens, reason, _, _, _, _, _}:
      "output:" ++ contents(blocks) ++ ":" ++ optional(id) ++ ":" ++ stop(reason) ++ ":" ++ usage(tokens) ++ ":error:" ++ detail(value)

def kind(value: AssistantEvent()) -> String:
  match value:
    case T.Start{_}: "start"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case _: "other"

def partial(value: AssistantEvent()) -> Message():
  match value:
    case T.Start{message}: message
    case T.TextStart{_, message}: message
    case T.TextDelta{_, _, message}: message
    case T.TextEnd{_, _, message}: message
    case T.ThinkingStart{_, message}: message
    case T.ThinkingDelta{_, _, message}: message
    case T.ThinkingEnd{_, _, message}: message
    case T.ToolcallStart{_, message}: message
    case T.ToolcallDelta{_, _, message}: message
    case T.ToolcallEnd{_, _, message}: message
    case T.StreamDone{_, message}: message
    case T.StreamError{_, message}: message

def retained(values: List<&2, AssistantEvent()>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case +head <> rest:
      do IO<Unit>:
        IO.print("retained:" ++ kind(head) ++ ":" ++ snapshot(partial(head)))
        retained(rest)

def toolArguments(value: Message()) -> IO(Unit):
  match value:
    case T.AssistantMessage{T.AssistantToolCall{T.ToolCall{_, name, args, _, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: IO.print("tool:" ++ name ++ ":" ++ shown(SchemaJson.toJson(args)))
    case _: IO.print("tool:none")

def timestamp(value: Message()) -> IO(Unit):
  match value:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, _, _, stamp}: IO.print("timestamp:" ++ bits(F.toBits(stamp)))

def cause(value: P.Terminal<String, Unit, String>) -> String:
  match value:
    case P.Successful{_, _}: "ok"
    case P.Failed{_, _, error}: P.describe(~String, ~String, ~identity, "openai", error)

def cleanup(value: Maybe<&2, P.Error<String, String>>) -> String:
  match value:
    case None{}: "none"
    case Some{error}: P.describe(~String, ~String, ~identity, "openai", error)

def finished(value: Outcome()) -> IO(Unit):
  match value:
    case P.RunResult{terminal, retired}: IO.print("run:" ++ cause(terminal) ++ ":cleanup:" ++ cleanup(retired))

# Consumption
# -----------

@unsafe def drainStep(+cursor: Events.Iterator<AssistantEvent(), Message()>, value: Events.Iteration<AssistantEvent()>) -> IO(List<&2, AssistantEvent()>):
  match value:
    case Events.End{}: IO.pure(List<&2, AssistantEvent()>, Nil{})
    case Events.Yield{event}:
      do IO<List<&2, AssistantEvent()>>:
        following : Events.Iteration<AssistantEvent()> <- Events.nextValue(AssistantEvent(), Message(), cursor)
        tail : List<&2, AssistantEvent()> <- drainStep(cursor, following)
        return event <> tail

def drain(+cursor: Events.Iterator<AssistantEvent(), Message()>) -> IO(List<&2, AssistantEvent()>):
  do IO<List<&2, AssistantEvent()>>:
    first : Events.Iteration<AssistantEvent()> <- Events.nextValue(AssistantEvent(), Message(), cursor)
    drainStep(cursor, first)

def observed(cursor: Events.Iterator<AssistantEvent(), Message()>, consumed: Chan(List<&2, AssistantEvent()>), final: Chan(Message()), pair: Run() & Outcome()) -> IO(Unit):
  match pair:
    case Tuple{owner, result}:
      do IO<Unit>:
        finished(result)
        events : List<&2, AssistantEvent()> <- IO.join(List<&2, AssistantEvent()>, consumed)
        retained(events)
        +output : Message() <- IO.join(Message(), final)
        IO.print("final:" ++ snapshot(output))
        toolArguments(output)
        timestamp(output)
        Events.disposeIterator(AssistantEvent(), Message(), cursor)
        ignored : Outcome() <- P.dispose(String, Unit, String, owner)
        return Unit{}

def observe(pair: Run() & Stream()) -> IO(Unit):
  match pair:
    case Tuple{owner, +events}:
      do IO<Unit>:
        +cursor : Events.Iterator<AssistantEvent(), Message()> <- Events.iterator(AssistantEvent(), Message(), events)
        consumed : Chan(List<&2, AssistantEvent()>) <- IO.fork(List<&2, AssistantEvent()>, drain(cursor))
        final : Chan(Message()) <- IO.fork(Message(), Events.resultValue(AssistantEvent(), Message(), events))
        joined : Run() & Outcome() <- P.wait(String, Unit, String, owner)
        observed(cursor, consumed, final, joined)

# Inputs
# ------

def tier(mode: U32) -> Maybe<&2, T.Nullable<P.ServiceTier>>:
  match mode:
    case 24: Some{T.PresentValue{P.TierFlex{}}}
    case 27: Some{T.PresentValue{P.TierFlex{}}}
    case 25: Some{T.PresentValue{P.TierPriority{}}}
    case 26: Some{T.PresentValue{P.TierPriority{}}}
    case 28: Some{T.PresentValue{P.TierPriority{}}}
    case _: None{}

def model(mode: U32, port: U32) -> T.Model<T.JsonValue>:
  T.Model{Bool.pick(String, U32.is_eq(mode, 26), "gpt-5.5", "test"), "Test", T.OpenAIResponsesApi{}, "openai", "http://127.0.0.1:" ++ U32.show(port) ++ "/v1", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{F.fromU32(1000000), F.fromU32(2000000), F.fromU32(3000000), F.fromU32(4000000), None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, Some{T.OpenAIResponsesCompat{None{}, None{}, None{}, None{}, None{}, Some{True{}}, None{}, None{}, None{}, None{}}}}

def grammarSchema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"program", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"program"} <> Nil{}}} <> Nil{}}}

def grammarTool() -> T.Tool<V.Value>:
  T.Tool{"tool", "A tool", grammarSchema(), Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{Some{"start: /[a-z]+/"}, None{}}}}}}

def context() -> P.Context(Unit, Unit):
  T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{"initial"}, None{}, Some{grammarTool() <> Nil{}}, None{}, F.fromU32(1)}} <> T.User{T.UserMessage{T.UserText{"hello"}, F.fromU32(1)}} <> Nil{}}

def config(files: Fetch.Files) -> P.Config:
  P.Config{Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, files, Setup.options(0, False{}), HTTP.NoTLS{}, 65536n, False{}}

def options(+mode: U32, supplied: Bool, parent: Abort.AbortSignal<String>, payloadHook: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String), responseHook: T.ResponseCallback(T.Model<T.JsonValue>, String)) -> P.OpenAIResponsesOptions<String, Unit, String>:
  P.fromStreamOptions(String, Unit, String, T.StreamOptions{Bool.pick(Maybe<&2, Abort.AbortSignal<String>>, supplied, Some{parent}, None{}), None{}, Some{Bool.pick(String, U32.is_eq(mode, 30), "", "fixture-key")}, None{}, Some{R.new(String)}, Some{payloadHook}, Some{responseHook}, None{}, Some{F.fromU32(1000)}, Some{Bool.pick(F.F64, U32.is_eq(mode, 22), F.nan(), F.fromU32(2))}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, P.ResponsesSettings{None{}, None{}, tier(mode), None{}})

# Mode 33 takes the default entry point: sampled clock and default SSE hooks.
def start(mode: U32, port: U32, files: Fetch.Files, settings: P.OpenAIResponsesOptions<String, Unit, String>) -> IO(Run()):
  match mode:
    case 33: P.stream(~String, ~Unit, ~Unit, ~Unit, ~String, ~identity, config(files), model(mode, port), context(), settings)
    case _:
      do IO<Run()>:
        +owned : Hooks() <- hooks()
        P.streamAt(~String, ~Unit, ~Unit, ~Unit, ~String, ~identity, config(files), owned, model(mode, port), context(), settings, F.fromU32(123), retireHooks(owned))

def preAbort(enabled: Bool, controller: Abort.AbortController<String>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, None{})
        return Unit{}

def run(+mode: U32, +supplied: Bool, +port: U32, resolver: String, hosts: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    preAbort(U32.is_eq(mode, 23) && supplied, parent)
    +payloadHook : T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, String, Maybe<&2, T.JsonValue>>, ~(selected => value => payload(selected, value)), mode)
    +responseHook : T.ResponseCallback(T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.ResponseInput<T.Model<T.JsonValue>>, ~Result<&2, &2, String, Unit>, ~(selected => value => response(selected, value)), mode)
    owner : Run() <- start(mode, port, Fetch.Files{resolver, hosts, 7, 65536n, 1000, 4096}, options(mode, supplied, Abort.signal(String, parent), payloadHook, responseHook))
    observe(P.borrow(String, Unit, String, owner))
    originalPayload : Result<&2, &2, String, Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payloadHook, T.PayloadInput{T.JsonNumber{F.fromU32(7)}, model(0, port)})
    originalResponse : Result<&2, &2, String, Unit> <- C.call(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, responseHook, T.ResponseInput{T.ProviderResponse{F.fromU32(200), R.set(String, R.new(String), "x-response", "ok")}, model(0, port)})
    IO.print("originals:alive")
    callerAborted : Bool <- Abort.aborted(String, Abort.signal(String, parent))
    IO.print("caller:" ++ Bool.pick(String, callerAborted, "aborted", "live"))
    C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payloadHook)
    C.dispose(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, responseHook)
    Abort.dispose(String, parent)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> port <> supplied <> resolver <> hosts <> Nil{}: run(Text.decimal(mode, 0), String.eq(supplied, "yes"), Text.decimal(port, 0), resolver, hosts)
    case _: IO.die(Unit, 1, "expected mode port supplied resolver hosts")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
