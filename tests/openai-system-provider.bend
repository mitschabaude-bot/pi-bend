import Base
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/error-body.bend as ErrorBody
import ../packages/ai/src/api/openai-http-error.bend as HTTPError
import ../packages/ai/src/api/openai-responses-attempt.bend as Generic
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as ConfiguredAcquire
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-sleep.bend as Sleep
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as ResolverOptions
import ../packages/runtime/src/dns-udp-plan.bend as UDP
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/ai/test/provider-retry.bend as Effects
import ./http-resolved-exchange.bend as Setup

import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-acquire.bend as Acquire
import ../packages/ai/src/api/openai-request-headers.bend as HeaderDefaults
import ../packages/ai/src/utils/provider-request.bend as Driver
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/url-absolute.bend as Absolute
import ../packages/runtime/src/idna-domain.bend as Domain
import ../packages/runtime/src/idna-label.bend as Label
import ../packages/runtime/src/idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../packages/runtime/src/unicode-17-normalization.bend as NormalizationData
import ../packages/runtime/src/unicode-17-idna-properties.bend as PropertiesData

import ../packages/ai/src/api/openai-responses-default-session.bend as Default
import ../packages/ai/src/api/openai-responses-system-provider.bend as Provider
import ../packages/ai/src/api/openai-responses-owned-acquire.bend as OwnedAcquire
import ../packages/ai/src/api/openai-responses-system-error.bend as SystemError
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/utils/provider-owned-acquire.bend as Owned
import ../packages/ai/src/api/openai-responses-options.bend as Options
import ../packages/ai/src/api/openai-responses-auth.bend as Auth
import ../packages/ai/test/openai-responses-request.bend as Transcript
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Error
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-responses-stream.bend as Content
import ../packages/ai/src/api/openai-responses-terminal.bend as Terminal
import ../packages/ai/src/api/openai-responses-scoped-reader.bend as Scoped
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-sse-json.bend as Json
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/runtime/src/schema-value.bend as V
import ./openai-scoped-session.bend as Model
import ./openai-scoped-responses-reader.bend as BodySource
import ./openai-provider-driver.bend as Display

def encoded(value: Result<&2, &2, Envelope.Error, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "invalid"

def shown(value: T.JsonValue) -> String: encoded(Envelope.serialize(value))


def client(+mode: U32, port: U32) -> Acquire.Client:
  Acquire.Client{Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.Options{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, HeaderDefaults.Defaults{"pi-bend-test", Record.new(String), None{}, None{}}, "fixture-key", Record.new(T.Nullable<String>), Bool.pick(String, U32.is_eq(mode, 10), "not a URL", "http://127.0.0.1:" ++ U32.show(port) ++ "/v1"), Some{Bool.pick(F.F64, U32.is_eq(mode, 11), F.nan(), F.fromU32(1000))}}


def E() -> Data: SystemError.Error<String, String>
def formatted(value: Result<&2, &2, ErrorBody.NormalizationError, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "format failure"

def renderNative(value: Error.Error<String, System.SourceError(), String>) -> String:
  match value:
    case Error.PreparationFailure{Preparation.CredentialFailure{cause}}: Auth.errorMessage(cause)
    case Error.HookFailure{text}: text
    case Error.AcquisitionFailure{ConfiguredAcquire.InvalidOptions{_}}: "invalid retry options"
    case Error.AcquisitionFailure{ConfiguredAcquire.AcquisitionFailed{Driver.PayloadFailure{Error.HookFailure{text}}}}: text
    case Error.AcquisitionFailure{ConfiguredAcquire.AcquisitionFailed{Driver.ResponseFailure{Error.HookFailure{text}, _}}}: text
    case Error.AcquisitionFailure{ConfiguredAcquire.AcquisitionFailed{Driver.RequestFailure{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{Error.AttemptFailure{Generic.HTTPFailure{value}}, _, _, _, _, _}}}}}}: formatted(HTTPError.format(value, "openai"))
    case Error.AcquisitionFailure{ConfiguredAcquire.AcquisitionFailed{Driver.RequestFailure{Retry.RequestAborted{}}}}: "Request aborted"
    case Error.ProcessingFailure{Content.ReadFailure{Error.ReaderFailure{cause}}}: BodySource.mapError(cause)
    case Error.ProcessingFailure{Content.TerminalFailure{cause}}: Terminal.errorMessage(cause)
    case _: "native failure"

def render(value: E()) -> String:
  match value:
    case SystemError.AcquisitionFailure{Owned.InitializationFailure{_}}: "system configuration"
    case SystemError.AcquisitionFailure{Owned.AcquisitionFailure{cause}}: renderNative(cause)
    case SystemError.ProcessingFailure{Content.ReadFailure{SystemError.ReaderFailure{cause}}}: BodySource.mapError(cause)
    case SystemError.ProcessingFailure{Content.TerminalFailure{cause}}: Terminal.errorMessage(cause)
    case _: "system provider failure"

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
    case T.ResponseInput{T.ProviderResponse{status, _}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("response:model:" ++ Effects.scalar(F.toBits(status)) ++ ":ok")
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 3), Fail{"response"}, Done{Unit{}})

# Iterator closure is local to this response. It does not cancel the caller.
def abortHook(environment: Unit, unused: Unit) -> IO(Unit): IO.print("abort-hook")
def optional(value: Maybe<&2, E()>) -> String:
  match value:
    case None{}: "none"
    case Some{cause}: render(cause)

def cause(value: Life.Terminal<V.Value, Unit, E()>) -> String:
  match value:
    case Life.Successful{_, _}: "ok"
    case Life.Failed{_, _, reason}: Life.describe(E(), render, reason)

def finished(value: Life.RunResult<V.Value, Unit, E()>) -> IO(Unit):
  match value:
    case Life.RunResult{terminal, cleanup, delivery}: IO.print("run:" ++ cause(terminal) ++ ":cleanup:" ++ optional(cleanup) ++ ":delivery:" ++ optional(delivery))

def toolArguments(value: Display.Message()) -> IO(Unit):
  match value:
    case T.AssistantMessage{T.AssistantToolCall{T.ToolCall{_, name, args, _, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: IO.print("tool:" ++ name ++ ":" ++ shown(SchemaJson.toJson(args)))
    case T.AssistantMessage{Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: IO.print("tool:none")
    case _: IO.die(Unit, 1, "unexpected content shape")

def eventKind(value: Display.AssistantEvent()) -> String:
  match value:
    case T.Start{_}: "start"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case _: "unexpected"

def eventKinds(values: List<&2, Display.AssistantEvent()>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print("event:" ++ eventKind(first))
        eventKinds(rest)

def observed(cursor: Events.Iterator<Display.AssistantEvent(), Display.Message()>, consumed: Chan(List<&2, Display.AssistantEvent()>), final: Chan(Display.Message()), pair: Session.Run<V.Value, Unit, E()> & Life.RunResult<V.Value, Unit, E()>) -> IO(Unit):
  match pair:
    case Tuple{owner, result}:
      do IO<Unit>:
        finished(result)
        +events : List<&2, Display.AssistantEvent()> <- IO.join(List<&2, Display.AssistantEvent()>, consumed)
        Display.retained(events)
        eventKinds(events)
        +output : Display.Message() <- IO.join(Display.Message(), final)
        IO.print("final:" ++ Display.snapshot(output))
        toolArguments(output)
        Events.disposeIterator(Display.AssistantEvent(), Display.Message(), cursor)
        ignored : Life.RunResult<V.Value, Unit, E()> <- Session.dispose(V.Value, Unit, E(), owner)
        return Unit{}

def observe(pair: Session.Run<V.Value, Unit, E()> & Display.Stream()) -> IO(Unit):
  match pair:
    case Tuple{owner, +stream}:
      do IO<Unit>:
        +cursor : Events.Iterator<Display.AssistantEvent(), Display.Message()> <- Events.iterator(Display.AssistantEvent(), Display.Message(), stream)
        consumed : Chan(List<&2, Display.AssistantEvent()>) <- IO.fork(List<&2, Display.AssistantEvent()>, Display.drain(cursor))
        final : Chan(Display.Message()) <- IO.fork(Display.Message(), Events.resultValue(Display.AssistantEvent(), Display.Message(), stream))
        joined : Session.Run<V.Value, Unit, E()> & Life.RunResult<V.Value, Unit, E()> <- Session.wait(V.Value, Unit, E(), owner)
        observed(cursor, consumed, final, joined)

def tier(mode: U32) -> Maybe<&2, T.Nullable<Options.ServiceTier>>:
  match mode:
    case 24: Some{T.PresentValue{Options.TierFlex{}}}
    case 27: Some{T.PresentValue{Options.TierFlex{}}}
    case 25: Some{T.PresentValue{Options.TierPriority{}}}
    case 26: Some{T.PresentValue{Options.TierPriority{}}}
    case 28: Some{T.PresentValue{Options.TierPriority{}}}
    case _: None{}

def selectedModel(mode: U32, baseUrl: String, value: T.Model<T.JsonValue>) -> T.Model<T.JsonValue>:
  match value:
    case T.Model{id, name, api, provider, _, reasoning, input, cost, context, max, thinking, settings, headers, compat}:
      T.Model{Bool.pick(String, U32.is_eq(mode, 26), "gpt-5.5", id), name, T.OpenAIResponsesApi{}, provider, baseUrl, reasoning, input, cost, context, max, thinking, settings, headers, Some{T.OpenAIResponsesCompat{None{}, None{}, None{}, None{}, None{}, Some{True{}}, None{}, None{}, None{}, None{}}}}

def grammarSchema() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", V.ObjectValue{Record.Record{Record.Property{"program", V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> Record.Property{"required", V.ArrayValue{V.Text{"program"} <> Nil{}}} <> Nil{}}}

def grammarTool() -> T.Tool<V.Value>:
  T.Tool{"tool", "A tool", grammarSchema(), Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{Some{"start: /[a-z]+/"}, None{}}}}}}

def grammarContext() -> T.TranscriptContext<V.Value, Record.Record<V.Value>, Unit, Unit>:
  T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{"initial"}, None{}, Some{grammarTool() <> Nil{}}, None{}, F.fromU32(1)}} <> T.User{T.UserMessage{T.UserText{"hello"}, F.fromU32(1)}} <> Nil{}}

def retireHooks(hooks: SSE.Hooks<Scoped.TransportError(String)>) -> IO(Unit):
  do IO<Unit>:
    BodySource.retireHooks(hooks)
    IO.print("dependencies:closed")

def start(+mode: U32, supplied: Bool, settings: Acquire.Client, files: System.Files, parent: Abort.AbortSignal<String>, +hooksOwned: SSE.Hooks<Scoped.TransportError(String)>, payloadHook: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String), responseHook: T.ResponseCallback(T.Model<T.JsonValue>, String)) -> IO(Session.Run<V.Value, Unit, E()>):
  match settings:
    case Acquire.Client{url, defaults, key, headers, baseUrl, timeout}:
      Provider.streamAt(~T.JsonValue, ~Transcript.identity, ~String, ~String, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~(unused => render), Provider.Dependencies{OwnedAcquire.Context{url, defaults, files, Setup.options(0, False{}), 65536n}, hooksOwned, False{}}, selectedModel(mode, baseUrl, Model.model()), grammarContext(), Options.fromStreamOptions(T.JsonValue, T.JsonValue, Abort.AbortSignal<String>, Unit, Unit, String, T.StreamOptions{Bool.pick(Maybe<&2, Abort.AbortSignal<String>>, supplied, Some{parent}, None{}), None{}, Some{Bool.pick(String, U32.is_eq(mode, 30), "", key)}, None{}, Some{Record.new(String)}, Some{payloadHook}, Some{responseHook}, Some{headers}, timeout, Some{Bool.pick(F.F64, U32.is_eq(mode, 22), F.nan(), F.fromU32(2))}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, Options.ResponsesSettings{None{}, None{}, tier(mode), None{}}), F.fromU32(123), Unit{}, retireHooks(hooksOwned))

def run(+mode: U32, supplied: Bool, port: U32, resolver: String, hosts: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    +payloadHook : T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, String, Maybe<&2, T.JsonValue>>, ~(selected => value => payload(selected, value)), mode)
    +responseHook : T.ResponseCallback(T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.ResponseInput<T.Model<T.JsonValue>>, ~Result<&2, &2, String, Unit>, ~(selected => value => response(selected, value)), mode)
    abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~abortHook, Unit{})
    diagnostic : C.Callback<Json.Error, Result<&2, &2, SSE.ReadError<Scoped.TransportError(String)>, Unit>> <- C.create(~Unit, ~Json.Error, ~Result<&2, &2, SSE.ReadError<Scoped.TransportError(String)>, Unit>, ~BodySource.diagnosticHook, Unit{})
    owner : Session.Run<V.Value, Unit, E()> <- start(mode, supplied, client(0, port), System.Files{resolver, hosts, 7, 65536n, 1000, 4096}, Abort.signal(String, parent), SSE.Hooks{abort, diagnostic}, payloadHook, responseHook)
    observe(Session.borrow(V.Value, Unit, E(), owner))
    originalPayload : Result<&2, &2, String, Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payloadHook, T.PayloadInput{T.JsonNumber{F.fromU32(7)}, Model.model()})
    originalResponse : Result<&2, &2, String, Unit> <- C.call(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, responseHook, T.ResponseInput{T.ProviderResponse{F.fromU32(200), Record.new(String)}, Model.model()})
    IO.print("originals:alive")
    callerAborted : Bool <- Abort.aborted(String, Abort.signal(String, parent))
    IO.print("caller:" ++ Bool.pick(String, callerAborted, "aborted", "live"))
    C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payloadHook)
    C.dispose(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, responseHook)
    Abort.dispose(String, parent)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> port <> supplied <> resolver <> hosts <> Nil{}: run(Scalar.decimal(mode, 0), String.eq(supplied, "yes"), Scalar.decimal(port, 0), resolver, hosts)
    case _: IO.die(Unit, 1, "expected mode port supplied resolver hosts")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
