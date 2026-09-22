import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses.bend as P
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as TLSClient
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ./tls13-client.bend as TLSTest
import ../packages/runtime/src/deadline.bend as Deadline

# Live integration runner, not a second CLI implementation. Credentials come
# only from the environment; output is model text or a fixed failure category.
# Model cost metadata is deliberately zero in this smoke fixture.
def identity(value: String) -> String: value

def config(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> P.Config:
  P.Config{
    URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}},
    Client.Defaults{"pi-bend-native-integration", R.new(String), None{}, None{}},
    Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535},
    HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}},
    HTTP.WithTLS{authorizer, TLS.defaults()}, 65536n, False{}}

def model(name: String, base: String) -> T.Model<T.JsonValue>:
  T.Model{name, "Live integration", T.OpenAIResponsesApi{}, "openai", base, False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, F.fromU32(128000), F.fromU32(128), None{}, None{}, None{}}

def options(key: String) -> P.OpenAIResponsesOptions<Unit, Unit, String>:
  P.fromStreamOptions(Unit, Unit, String,
    T.StreamOptions{None{}, None{}, Some{key}, None{}, Some{R.new(String)}, None{}, None{}, None{}, Some{F.fromU32(120000)}, Some{F.fromU32(0)}, None{}, None{}, None{}, Some{F.fromU32(128)}, None{}, None{}, None{}, None{}, None{}},
    P.ResponsesSettings{None{}, None{}, None{}, None{}})

def text(parts: List<&2, T.AssistantContent<V.Value>>) -> String:
  match parts:
    case Nil{}: ""
    case T.AssistantText{T.TextContent{value, _}} <> rest: value ++ text(rest)
    case _ <> rest: text(rest)

def message(value: T.AssistantMessage<V.Value, Unit>) -> String:
  match value:
    case T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: text(content)

def headerPrimary(cause: Response.ResponseProgressPrimaryError<HTTP.ReadError<Deadline.Cause<Unit>>>) -> String:
  match cause:
    case Response.TransportFailure{HTTP.ResponseFailure{Response.ResponseReaderPrimaryFailure{Response.SourceError{HTTP.TLSSourceFailure{TLS.Protocol{detail}}}}}}: "TLS read " ++ TLSTest.renderError(detail)
    case Response.TransportFailure{HTTP.ResponseFailure{Response.ResponseReaderPrimaryFailure{Response.SourceError{HTTP.TLSSourceFailure{TLS.Network{_}}}}}}: "TLS read network failure"
    case Response.TransportFailure{HTTP.ResponseFailure{Response.ResponseReaderPrimaryFailure{Response.DecodeError{Response.HeadError{_}}}}}: "HTTP head syntax failure"
    case Response.TransportFailure{HTTP.ResponseFailure{Response.ResponseReaderPrimaryFailure{Response.DecodeError{Response.ResponseStreamPolicyError{_}}}}}: "HTTP response policy failure"
    case Response.TransportFailure{HTTP.ResponseFailure{Response.ResponseReaderPrimaryFailure{Response.DecodeError{Response.IncompleteResponse{}}}}}: "HTTP response truncated"
    case _: "HTTP header primary failure"

def headerError(cause: Response.ResponseProgressError<HTTP.ReadError<Deadline.Cause<Unit>>>) -> String:
  match cause:
    case Response.ResponseProgressPrimaryFailure{primary}: headerPrimary(primary)
    case Response.ResponseProgressFailureWithCleanup{primary, _}: headerPrimary(primary)
    case _: "HTTP header cleanup failure"

def transportError(cause: Client.FetchError<Unit>) -> String:
  match cause:
    case Client.FetchFailure{Response.DispatchFailure{Fetch.ExchangeFailure{_, _, HTTP.ResolvedExchangeFailure{HTTP.TLSStartFailure{TLS.Protocol{detail}}}}, _}}: "TLS " ++ TLSTest.renderError(detail)
    case Client.FetchFailure{Response.DispatchFailure{Fetch.ExchangeFailure{_, _, HTTP.ResolvedExchangeFailure{HTTP.TLSStartFailure{_}}}, _}}: "TLS transport failed"
    case Client.FetchFailure{Response.DispatchFailure{Fetch.HeaderFailure{_, _, detail}, _}}: headerError(detail)
    case Client.FetchFailure{Response.DispatchFailure{Fetch.Unresolved{_}, _}}: "DNS resolution failed"
    case Client.FetchFailure{Response.DispatchFailure{Fetch.ExchangeFailure{_, _, _}, _}}: "connection setup failed"
    case other: P.describeTransport(Unit, other)

def attemptError(cause: Client.AttemptError<Unit>) -> String:
  match cause:
    case Client.TransportFailure{detail}: transportError(detail)
    case Client.HTTPFailure{Client.APIError{metadata, _, _}}: "HTTP " ++ U32.show(Response.statusResponseMetadata(metadata))
    case _: "error-response decoding failed"

def requestError(cause: Retry.RetryFailure<Client.AttemptError<Unit>>) -> String:
  match cause:
    case Retry.RequestFailed{Retry.Provider{Retry.ProviderError{original, _, _, _, _, _}}}: attemptError(original)
    case Retry.RequestFailed{Retry.Other{original}}: attemptError(original)
    case _: "retry failed"

def error(cause: P.Error<Unit, String>) -> String:
  match cause:
    case P.PreparationFailure{_}: "preparation failed"
    case P.RequestRejected{_}: "request rejected"
    case P.InitializationFailure{_}: "transport initialization failed"
    case P.RequestFailure{cause}: requestError(cause)
    case P.ProcessingFailure{_}: "stream processing failed"
    case P.RequestAborted{}: "request aborted"
    case _: "provider failed"

def report(result: P.RunResult<Unit, Unit, String>) -> IO(Unit):
  match result:
    case P.RunResult{P.Successful{_, output}, None{}}: IO.print(message(output))
    case P.RunResult{P.Failed{_, _, cause}, _}: IO.die(Unit, 1, error(cause))
    case _: IO.die(Unit, 1, "provider cleanup failed")

def request(name: String, base: String, prompt: String, certificates: Result<&2, &2, Trust.Error, List<&2, X509.Certificate>>) -> IO(Unit):
  match certificates:
    case Fail{_}: IO.die(Unit, 1, "trust bundle failed")
    case Done{anchors}:
      do IO<Unit>:
        +authorizer : C.Callback<URL.Host, TLSClient.Authorization> <- Trust.newSAN(Trust.SANPolicy{anchors, 256n})
        key : String <- IO.try(String, IO.get_env("OPENAI_API_KEY"))
        run : P.Run<Unit, Unit, String> <- P.stream(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~identity, config(authorizer), model(name, base), T.TranscriptContext{T.User{T.UserMessage{T.UserText{prompt}, F.fromU32(0)}} <> Nil{}}, options(key))
        result : P.RunResult<Unit, Unit, String> <- P.dispose(Unit, Unit, String, run)
        C.dispose(URL.Host, TLSClient.Authorization, authorizer)
        report(result)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case bundle <> name <> base <> prompt <> Nil{}:
      do IO<Unit>:
        certificates : Result<&2, &2, Trust.Error, List<&2, X509.Certificate>> <- Trust.load(bundle, 1048576n)
        request(name, base, prompt, certificates)
    case _: IO.die(Unit, 1, "expected trust-bundle model base-url prompt")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
