import Base
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as ConfiguredAcquire
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/utils/provider-retry-options.bend as RetryOptions
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-attempt.bend as Generic
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-http-error.bend as HTTPError
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-sleep.bend as Sleep
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-exchange-response.bend as Reader
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-fetch-scope.bend as Scope
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/dns-udp-plan.bend as UDP
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-scheme.bend as Scheme
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/ai/test/provider-retry.bend as Effects
import ./http-resolved-exchange.bend as Setup

import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-cleartext-request.bend as NativeRequest
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

def State() -> Type: Attempt.State(String)
def Owner() -> Type: Response.Response<State()>
def Outcome() -> Type: Acquire.Outcome(String, State())

def original(error: Attempt.Error(String, File.Failure)) -> String:
  match error:
    case Generic.HTTPFailure{HTTPError.APIError{_, _, message}}: "http:" ++ message
    case Generic.DiagnosticFailure{_}: "diagnostic"
    case Generic.FetchFailure{_}: "fetch"

def increment(+count: U32) -> U32 & Unit: ((count + 1 : U32), Unit{})

def read(state: State()) -> IO(State() & Result<&2, &2, Attempt.ReadError(String), Maybe<&2, Stream.Event>>):
  Scope.read(String, Attempt.ReadError(String), Attempt.Transport(String), Reader.read(Deadline.Cause<String>), state)

def close(state: State()) -> IO(Result<&2, &2, Attempt.ReadError(String), Unit>):
  Scope.close(String, Attempt.ReadError(String), Attempt.Transport(String), Exchange.close(Deadline.Cause<String>), state)

def consumed(value: Result<&2, &2, Consume.TextError<Attempt.ReadError(String)>, String>) -> IO(Unit):
  match value:
    case Done{text}: IO.print("body:" ++ text)
    case Fail{_}: IO.print("body-error")

def sleep(environment: Unit, input: Retry.SleepInput<String>) -> IO(Result<&2, &2, Retry.SleepError, Unit>):
  do IO<Result<&2, &2, Retry.SleepError, Unit>>:
    IO.print("sleep")
    Sleep.sleep(String, input)

def model() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"target", "Target", T.OpenAIResponsesApi{}, "openai", "unused", True{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def modelId(value: T.Model<T.JsonValue>) -> String:
  match value:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def encoded(value: Result<&2, &2, Envelope.Error, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "invalid"

def shown(value: T.JsonValue) -> String: encoded(Envelope.serialize(value))

def payloadChoice(mode: U32) -> Result<&2, &2, String, Maybe<&2, T.JsonValue>>:
  match mode:
    case 2: Done{Some{T.JsonString{"replacement"}}}
    case 3: Done{Some{T.JsonNumber{F.fromU32(0)}}}
    case 4: Fail{"payload"}
    case 8: Done{Some{T.JsonNumber{F.nan()}}}
    case 9: Done{Some{T.JsonNull{}}}
    case _: Done{None{}}

def payloadHook(+mode: U32, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Maybe<&2, T.JsonValue>>):
  match input:
    case T.PayloadInput{value, model}:
      do IO<Result<&2, &2, String, Maybe<&2, T.JsonValue>>>:
        IO.print("payload:" ++ shown(value) ++ ":" ++ modelId(model))
        return payloadChoice(mode)

def responseHook(+mode: U32, input: T.ResponseInput<T.Model<T.JsonValue>>) -> IO(Result<&2, &2, String, Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{status, _}, model}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("response:" ++ Effects.scalar(F.toBits(status)) ++ ":" ++ modelId(model))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 5) || U32.is_eq(mode, 6), Fail{"response"}, Done{Unit{}})

type Environment is Data:
  Environment{native: C.Callback<Envelope.Request, Outcome()>, counter: R.Ref<U32>}

def request(environment: Environment, wire: Envelope.Request) -> IO(Outcome()):
  match environment:
    case Environment{native, counter}:
      do IO<Outcome()>:
        ignored : Unit <- R.modify(U32, Unit, counter, value => increment(value))
        IO.print("request")
        C.call(Envelope.Request, Outcome(), native, wire)

def released(fails: Bool, value: Response.Next<Attempt.ReadError(String), State()>) -> Result<&2, &2, String, Unit>:
  match value:
    case Response.Next{Response.Closed{_}, Done{_}}: Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"cleanup"}, Done{Unit{}})
    case _: Fail{"close"}

def release(fails: Bool, owner: Owner()) -> IO(Result<&2, &2, String, Unit>):
  match owner:
    case Response.Response{_, body}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("release")
        result : Response.Next<Attempt.ReadError(String), State()> <- Response.closeWith(Attempt.ReadError(String), State(), close, body)
        return released(fails, result)

def cleanup(value: Result<&2, &2, String, Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{cause}: cause

def finished(value: Result<&2, &1, Driver.Error<String>, Owner()>) -> IO(Unit):
  match value:
    case Fail{Driver.PayloadFailure{cause}}: IO.print("failed:payload:" ++ cause)
    case Fail{Driver.ResponseFailure{cause, result}}: IO.print("failed:response:" ++ cause ++ ":" ++ cleanup(result))
    case Fail{Driver.RequestFailure{Retry.RequestFailed{Retry.Other{cause}}}}: IO.print("failed:request:" ++ cause)
    case Fail{Driver.RequestFailure{_}}: IO.print("failed:retry")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("accepted")
        result : Result<&2, &2, Consume.TextError<Attempt.ReadError(String)>, String> <- Consume.textWith(~Attempt.ReadError(String), ~State(), ~read, ~close, 65536n, body)
        consumed(result)

def envelopeError(error: Envelope.Error) -> String:
  match error:
    case Envelope.NonFinitePayload{}: "nonfinite"
    case Envelope.URLFailure{_}: "url"
    case Envelope.HeaderFailure{_}: "headers"
    case Envelope.PayloadEncodingFailure{}: "encoding"

def finishedConfigured(value: ConfiguredAcquire.Outcome(String, State())) -> IO(Unit):
  match value:
    case Fail{ConfiguredAcquire.InvalidOptions{RetryOptions.InvalidRetryCount{_}}}: IO.print("failed:options:count")
    case Fail{ConfiguredAcquire.InvalidOptions{RetryOptions.InvalidDelayLimit{_}}}: IO.print("failed:options:limit")
    case Fail{ConfiguredAcquire.AcquisitionFailed{cause}}: finished(Fail{cause})
    case Done{body}: finished(Done{body})

def acquire(+mode: U32, settings: Acquire.Client, signal: Abort.AbortSignal<String>, payload: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String), response: T.ResponseCallback(T.Model<T.JsonValue>, String), attempt: C.Callback<Envelope.Request, Outcome()>, effects: Retry.Effects<String>) -> IO(ConfiguredAcquire.Outcome(String, State())):
  match settings:
    case Acquire.Client{url, defaults, apiKey, headers, +baseUrl, timeout}:
      ConfiguredAcquire.run(~String, ~Unit, ~Unit, ~String, ~State(), ~envelopeError, url, defaults, model(), Preparation.Prepared{apiKey, baseUrl, headers, T.JsonString{"original"}, Policy.getCompat("openai", baseUrl, None{}), Record.new(String), T.CacheShort{}}, T.ProviderRequestOptions{Some{signal}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String)>, U32.is_eq(mode, 0), None{}, Some{payload}), Bool.pick(Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, String)>, U32.is_eq(mode, 0), None{}, Some{response}), None{}, timeout, Some{Bool.pick(F.F64, U32.is_eq(mode, 12), F.nan(), F.fromU32(1))}, Bool.pick(Maybe<&2, F.F64>, U32.is_eq(mode, 13), Some{F.nan()}, None{})}, attempt, effects, release(U32.is_eq(mode, 6)))

def client(+mode: U32, port: U32) -> Acquire.Client:
  Acquire.Client{Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.Options{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, HeaderDefaults.Defaults{"pi-bend-test", Record.new(String), None{}, None{}}, "fixture-key", Record.new(T.Nullable<String>), Bool.pick(String, U32.is_eq(mode, 10), "not a URL", "http://127.0.0.1:" ++ U32.show(port) ++ "/v1"), Some{Bool.pick(F.F64, U32.is_eq(mode, 11), F.nan(), F.fromU32(1000))}}

def run(+mode: U32, port: U32, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (resolverOwner, resolver):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +counter : R.Ref<U32> <- R.new(U32, 0)
        +fetch : C.Callback<Fetch.Input<String>, Attempt.FetchResult(String, File.Failure)> <- Native.create(~String, ~File.Failure, Native.Context{resolver, Setup.database(0, False{}), Setup.options(0, False{})})
        +nativeRequest : C.Callback<Envelope.Request, Outcome()> <- NativeRequest.create(~String, ~File.Failure, ~String, ~original, Abort.signal(String, parent), fetch, 65536n)
        +attempt : C.Callback<Envelope.Request, Outcome()> <- C.create(~Environment, ~Envelope.Request, ~Outcome(), ~request, Environment{nativeRequest, counter})
        +payload : T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, String) <- C.create(~U32, ~(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>), ~(Result<&2, &2, String, Maybe<&2, T.JsonValue>>), ~(selectedMode => input => payloadHook(selectedMode, input)), mode)
        +response : T.ResponseCallback(T.Model<T.JsonValue>, String) <- C.create(~U32, ~(T.ResponseInput<T.Model<T.JsonValue>>), ~(Result<&2, &2, String, Unit>), ~(selectedMode => input => responseHook(selectedMode, input)), mode)
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Effects.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.nowBody, Unit{})
        +delay : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>> <- C.create(~Unit, ~Retry.SleepInput<String>, ~Result<&2, &2, Retry.SleepError, Unit>, ~sleep, Unit{})
        result : ConfiguredAcquire.Outcome(String, State()) <- acquire(mode, client(mode, port), Abort.signal(String, parent), payload, response, attempt, Retry.Effects{random, date, now, delay})
        C.dispose(Envelope.Request, Outcome(), attempt)
        C.dispose(Envelope.Request, Outcome(), nativeRequest)
        finishedConfigured(result)
        C.dispose(Fetch.Input<String>, Attempt.FetchResult(String, File.Failure), fetch)
        C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, payload)
        C.dispose(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, String, Unit>, response)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, delay)
        count : U32 <- R.dispose(U32, counter)
        IO.print("count:" ++ U32.show(count))
        Resolver.close(resolverOwner)
        Abort.dispose(String, parent)

def created(mode: U32, port: U32, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(mode, port, Resolver.borrow(owner))

def configured(mode: U32, port: U32, result: Result<&2, &2, UDP.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver settings")
    case Done{config}:
      do IO<Unit>:
        result : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~Setup.seed, 0, config)
        created(mode, port, result)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> port <> Nil{}: configured(Scalar.decimal(mode, 0), Scalar.decimal(port, 0), Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, 9} <> Nil{}, 100, 512, Search.prepare(Options.Options{1, 1, 1, Nil{}}, Nil{})))
    case _: IO.die(Unit, 1, "expected mode port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
