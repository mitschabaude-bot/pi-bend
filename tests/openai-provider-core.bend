import Base
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
import ../packages/ai/src/api/openai-responses-provider-core.bend as Provider
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

def sleep(environment: Unit, +input: Retry.SleepInput<String>) -> IO(Result<&2, &2, Retry.SleepError, Unit>):
  match input:
    case Retry.SleepInput{milliseconds, _}:
      do IO<Result<&2, &2, Retry.SleepError, Unit>>:
        IO.print("sleep " ++ Effects.scalar(F.toBits(milliseconds)))
        Sleep.sleep(String, input)


def encoded(value: Result<&2, &2, Envelope.Error, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "invalid"

def shown(value: T.JsonValue) -> String: encoded(Envelope.serialize(value))


def client(+mode: U32, port: U32) -> Acquire.Client:
  Acquire.Client{Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.Options{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, HeaderDefaults.Defaults{"pi-bend-test", Record.new(String), None{}, None{}}, "fixture-key", Record.new(T.Nullable<String>), Bool.pick(String, U32.is_eq(mode, 10), "not a URL", "http://127.0.0.1:" ++ U32.show(port) ++ "/v1"), Some{Bool.pick(F.F64, U32.is_eq(mode, 11), F.nan(), F.fromU32(1000))}}


def E() -> Data: Error.Error<String, File.Failure, String>
def formatted(value: Result<&2, &2, ErrorBody.NormalizationError, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "format failure"

def render(value: E()) -> String:
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

def payload(+mode: U32, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Maybe<&2, T.JsonValue>>):
  match input:
    case T.PayloadInput{value, _}:
      do IO<Result<&2, &2, String, Maybe<&2, T.JsonValue>>>:
        IO.print("payload:" ++ shown(value) ++ ":model")
        return Bool.pick(Result<&2, &2, String, Maybe<&2, T.JsonValue>>, U32.is_eq(mode, 2), Fail{"payload"}, Done{None{}})

def response(mode: U32, input: T.ResponseInput<T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{status, _}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("response:model:" ++ Effects.scalar(F.toBits(status)) ++ ":ok")
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 3), Fail{"response"}, Done{Unit{}})

def fetch(native: C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)>, +input: Fetch.Input<String>) -> IO(Attempt.FetchResult(String, File.Failure)):
  match input:
    case Fetch.Input{_, _, _, body, _}:
      do IO<Attempt.FetchResult(String, File.Failure)>:
        IO.print("request:" ++ body)
        C.call(Fetch.Input<String>, Attempt.FetchResult(String, File.Failure), native, input)

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

def observed(cursor: Events.Iterator<Display.AssistantEvent(), Display.Message()>, consumed: Chan(List<&2, Display.AssistantEvent()>), final: Chan(Display.Message()), pair: Session.Run<V.Value, Unit, E()> & Life.RunResult<V.Value, Unit, E()>) -> IO(Unit):
  match pair:
    case Tuple{owner, result}:
      do IO<Unit>:
        finished(result)
        events : List<&2, Display.AssistantEvent()> <- IO.join(List<&2, Display.AssistantEvent()>, consumed)
        Display.retained(events)
        output : Display.Message() <- IO.join(Display.Message(), final)
        IO.print("final:" ++ Display.snapshot(output))
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
      T.Model{Bool.pick(String, U32.is_eq(mode, 26), "gpt-5.5", id), name, api, provider, baseUrl, reasoning, input, cost, context, max, thinking, settings, headers, compat}

def start(+mode: U32, supplied: Bool, settings: Acquire.Client, parent: Abort.AbortSignal<String>, fetch: C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)>, retry: Retry.Effects<String>, hooks: SSE.Hooks<Scoped.TransportError(String)>, payloadHook: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String), responseHook: T.ResponseCallback(T.Model<T.JsonValue>, String)) -> IO(Session.Run<V.Value, Unit, E()>):
  match settings:
    case Acquire.Client{url, defaults, key, headers, baseUrl, timeout}:
      Provider.streamAt(~T.JsonValue, ~Transcript.identity, ~String, ~File.Failure, ~String, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~(unused => render), Default.Dependencies{url, defaults, fetch, retry, hooks, 65536n, False{}}, selectedModel(mode, baseUrl, Model.model()), Transcript.context(0), Options.fromStreamOptions(T.JsonValue, T.JsonValue, Abort.AbortSignal<String>, Unit, Unit, String, T.StreamOptions{Bool.pick(Maybe<&2, Abort.AbortSignal<String>>, supplied, Some{parent}, None{}), None{}, Some{Bool.pick(String, U32.is_eq(mode, 30), "", key)}, None{}, Some{Record.new(String)}, Some{payloadHook}, Some{responseHook}, Some{headers}, timeout, Some{Bool.pick(F.F64, U32.is_eq(mode, 22), F.nan(), F.fromU32(2))}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, Options.ResponsesSettings{None{}, None{}, tier(mode), None{}}), F.fromU32(123), Unit{}, IO.pure(Unit, Unit{}))

def run(+mode: U32, supplied: Bool, port: U32, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case Tuple{resolverOwner, resolver}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        Effects.preAbort(U32.is_eq(mode, 23), parent)
        +native : C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)> <- Native.create(~String, ~File.Failure, Native.Context{resolver, Setup.database(0, False{}), Setup.options(0, False{})})
        +request : C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)> <- C.create(~C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)>, ~Fetch.Input<String>, ~Attempt.FetchResult(String, File.Failure), ~(transport => input => fetch(transport, input)), native)
        +payloadHook : T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, String, Maybe<&2, T.JsonValue>>, ~(selected => value => payload(selected, value)), mode)
        +responseHook : T.ResponseCallback(T.Model<T.JsonValue>, String) <- C.create(~U32, ~T.ResponseInput<T.Model<T.JsonValue>>, ~Result<&2, &2, String, Unit>, ~(selected => value => response(selected, value)), mode)
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Effects.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.nowBody, Unit{})
        +delay : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>> <- C.create(~Unit, ~Retry.SleepInput<String>, ~Result<&2, &2, Retry.SleepError, Unit>, ~(environment => input => sleep(environment, input)), Unit{})
        +abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~abortHook, Unit{})
        +diagnostic : C.Callback<Json.Error, Result<&2, &2, SSE.ReadError<Scoped.TransportError(String)>, Unit>> <- C.create(~Unit, ~Json.Error, ~Result<&2, &2, SSE.ReadError<Scoped.TransportError(String)>, Unit>, ~BodySource.diagnosticHook, Unit{})
        owner : Session.Run<V.Value, Unit, E()> <- start(mode, supplied, client(0, port), Abort.signal(String, parent), request, Retry.Effects{random, date, now, delay}, SSE.Hooks{abort, diagnostic}, payloadHook, responseHook)
        observe(Session.borrow(V.Value, Unit, E(), owner))
        callerAborted : Bool <- Abort.aborted(String, Abort.signal(String, parent))
        IO.print("caller:" ++ Bool.pick(String, callerAborted, "aborted", "live"))
        C.dispose(Fetch.Input<String>, Attempt.FetchResult(String, File.Failure), request)
        C.dispose(Fetch.Input<String>, Attempt.FetchResult(String, File.Failure), native)
        C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payloadHook)
        C.dispose(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, responseHook)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, delay)
        C.dispose(Unit, Unit, abort)
        C.dispose(Json.Error, Result<&2, &2, SSE.ReadError<Scoped.TransportError(String)>, Unit>, diagnostic)
        Resolver.close(resolverOwner)
        Abort.dispose(String, parent)

def created(mode: U32, supplied: Bool, port: U32, value: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(mode, supplied, port, Resolver.borrow(owner))

def configured(mode: U32, supplied: Bool, port: U32, value: Result<&2, &2, UDP.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "resolver settings")
    case Done{config}:
      do IO<Unit>:
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~Setup.seed, 0, config)
        created(mode, supplied, port, owner)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> port <> supplied <> Nil{}: configured(Scalar.decimal(mode, 0), String.eq(supplied, "yes"), Scalar.decimal(port, 0), Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, 9} <> Nil{}, 100, 512, Search.prepare(ResolverOptions.Options{1, 1, 1, Nil{}}, Nil{})))
    case _: IO.die(Unit, 1, "expected mode port supplied")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
