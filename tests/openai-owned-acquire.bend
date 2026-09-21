import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-owned-acquire.bend as P
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/api/openai-responses-auth.bend as Auth
import ../packages/ai/src/api/openai-responses-native-session-error.bend as E
import ../packages/ai/src/api/openai-responses-native-session.bend as Native
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-responses-prepared-acquire.bend as Ready
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-request-headers.bend as Headers
import ../packages/ai/src/utils/provider-owned-acquire.bend as Owned
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/url-absolute.bend as URL
import ../packages/runtime/src/idna-domain.bend as Domain
import ../packages/runtime/src/idna-label.bend as Label
import ../packages/runtime/src/idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../packages/runtime/src/unicode-17-normalization.bend as NormalizationData
import ../packages/runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/runtime/src/http-resolved-exchange.bend as HTTP
import ../packages/runtime/src/dns-pair-result.bend as Pair
import ../packages/runtime/src/connection-order.bend as Order
import ../packages/runtime/src/http-response-stream.bend as Response
import ../packages/runtime/src/http-chunked-body.bend as Chunked

def Error() -> Data: P.Inner(String, String)

def model() -> T.Model<T.JsonValue>:
  T.Model{"test", "Test", T.OpenAIResponsesApi{}, "openai", "http://localhost", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{F.fromU32(1), F.fromU32(2), F.fromU32(3), F.fromU32(4), None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def original(+mode: U32, port: U32) -> Preparation.Prepared:
  Preparation.Prepared{"fixture-key", Bool.pick(String, U32.is_eq(mode, 7) || U32.is_eq(mode, 8), "not a URL", "http://" ++ Bool.pick(String, U32.is_eq(mode, 14), "fixture.invalid", "127.0.0.1") ++ ":" ++ U32.show(port) ++ "/v1"), R.Record{R.Property{"x-fixture", T.PresentValue{"yes"}} <> Nil{}}, T.JsonString{"original"}, Policy.getCompat("openai", "http://localhost", None{}), R.Record{R.Property{"tool", "program"} <> Nil{}}, T.CacheLong{}}

def prepared(+mode: U32, port: U32) -> IO(Result<&2, &2, Preparation.Error, Preparation.Prepared>):
  do IO<Result<&2, &2, Preparation.Error, Preparation.Prepared>>:
    IO.print("prepare")
    return Bool.pick(Result<&2, &2, Preparation.Error, Preparation.Prepared>, U32.is_eq(mode, 4), Fail{Preparation.CredentialFailure{Auth.MissingApiKey{"fixture"}}}, Done{original(mode, port)})

def selected(mode: U32) -> Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>:
  match mode:
    case 1: Done{Some{T.JsonNull{}}}
    case 2: Done{Some{T.JsonNumber{F.fromU32(9)}}}
    case 6: Fail{E.HookFailure{"payload"}}
    case 13: Done{Some{T.JsonNumber{F.nan()}}}
    case _: Done{None{}}

def payload(mode: U32, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>):
  do IO<Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>>:
    IO.print("payload")
    return selected(mode)

def status200(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{EQ{}}: True{}
    case _: False{}

def response(mode: U32, input: T.ResponseInput<T.Model<T.JsonValue>>) -> IO(Result<&2, &2, Error(), Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{status, _}, _}:
      do IO<Result<&2, &2, Error(), Unit>>:
        IO.print("response:" ++ Bool.pick(String, status200(F.compare(status, F.fromU32(200))), "200", "other"))
        return Bool.pick(Result<&2, &2, Error(), Unit>, U32.is_eq(mode, 3), Fail{E.HookFailure{"response"}}, Done{Unit{}})

def options(+mode: U32, payloadHook: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, Error()), responseHook: T.ResponseCallback(T.Model<T.JsonValue>, Error())) -> Native.Options(String, System.SourceError(), String, Unit, Unit):
  T.ProviderRequestOptions{None{}, None{}, None{}, None{}, None{}, Some{payloadHook}, Some{responseHook}, None{}, Some{Bool.pick(F.F64, U32.is_eq(mode, 12), F.nan(), F.fromU32(3000))}, Some{Bool.pick(F.F64, U32.is_eq(mode, 5), F.nan(), F.fromU32(1))}, None{}}

def context(resolver: String, hosts: String) -> P.Context:
  P.Context{URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.Options{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, Headers.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, System.Files{resolver, hosts, 7, 65536n, 1000, 4096}, HTTP.Options{Pair.IPv4First{}, Order.IPv4First{}, 1000, 7, Response.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}}, 4096n}

def render(value: P.Error(String, String)) -> String:
  match value:
    case Owned.InitializationFailure{System.ConfigurationFailure{_}}: "configuration"
    case Owned.AcquisitionFailure{E.PreparationFailure{Preparation.CredentialFailure{Auth.MissingApiKey{provider}}}}: "credential:" ++ provider
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.InvalidOptions{_}}}: "retry-options"
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.PayloadFailure{E.HookFailure{cause}}}}}: cause
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.ResponseFailure{E.HookFailure{cause}, Done{_}}}}}: cause ++ ":closed"
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}}}: "aborted"
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{E.EnvelopeFailure{Envelope.URLFailure{_}}}}}}}}: "url"
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{E.EnvelopeFailure{Envelope.HeaderFailure{_}}}}}}}}: "header"
    case Owned.AcquisitionFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{E.EnvelopeFailure{Envelope.NonFinitePayload{}}}}}}}}: "nonfinite"
    case _: "unexpected"

def metadata(value: Preparation.Prepared) -> String:
  match value:
    case Preparation.Prepared{"fixture-key", _, _, T.JsonString{"original"}, _, R.Record{R.Property{"tool", "program"} <> Nil{}}, T.CacheLong{}}: "original"
    case _: "changed"

def released(result: Result<&2, &2, Error(), Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("closed")
    case Fail{_}: IO.die(Unit, 1, "close failed")

def received(result: Result<&2, &1, P.Error(String, String), P.Owner(String)>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.print("error:" ++ render(cause))
    case Done{Owned.Owner{runtime, Ready.Owner{+preparation, body}}}:
      do IO<Unit>:
        IO.print("metadata:" ++ metadata(preparation))
        closed : Result<&2, &2, Error(), Unit> <- P.release(String, String, Owned.Owner{runtime, Ready.Owner{preparation, body}})
        released(closed)

def preabort(enabled: Bool, parent: Abort.AbortController<String>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        ignored : Bool <- Abort.abort(String, parent, Some{"stop"})
        return Unit{}

def run(+mode: U32, port: U32, resolver: String, hosts: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    preabort(U32.is_eq(mode, 8) || U32.is_eq(mode, 10), parent)
    +payloadHook : T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, Error()) <- C.create(~U32, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>, ~payload, mode)
    +responseHook : T.ResponseCallback(T.Model<T.JsonValue>, Error()) <- C.create(~U32, ~T.ResponseInput<T.Model<T.JsonValue>>, ~Result<&2, &2, Error(), Unit>, ~response, mode)
    result : Result<&2, &1, P.Error(String, String), P.Owner(String)> <- P.run(~String, ~String, ~Unit, ~Unit, context(resolver, hosts), Abort.signal(String, parent), model(), options(mode, payloadHook, responseHook), prepared(mode, port))
    received(result)
    IO.print("borrowed-hooks")
    ignoredPayload : Result<&2, &2, Error(), Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>, payloadHook, T.PayloadInput{T.JsonNull{}, model()})
    ignoredResponse : Result<&2, &2, Error(), Unit> <- C.call(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, Error(), Unit>, responseHook, T.ResponseInput{T.ProviderResponse{F.fromU32(200), R.new(String)}, model()})
    live : Bool <- Abort.aborted(String, Abort.signal(String, parent))
    IO.print(Bool.pick(String, live, "parent:aborted", "parent:live"))
    C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, Error(), Maybe<&2, T.JsonValue>>, payloadHook)
    C.dispose(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, Error(), Unit>, responseHook)
    Abort.dispose(String, parent)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> port <> resolver <> hosts <> Nil{}: run(Scalar.decimal(mode, 0), Scalar.decimal(port, 0), resolver, hosts)
    case _: IO.die(Unit, 1, "expected mode port resolver hosts")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
