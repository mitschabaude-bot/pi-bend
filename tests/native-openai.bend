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
import ../packages/ai/src/api/openai-responses-stream.bend as ResponsesStream
import ../packages/ai/src/api/openai-sse.bend as SSE
import ../packages/runtime/src/socket.bend as Socket
import ../packages/runtime/src/deadline.bend as Deadline

# Live integration runner, not a second CLI implementation. Credentials come
# only from the environment; output is model text or a fixed failure category.
# Model cost metadata is deliberately zero in this smoke fixture.
def identity(value: String) -> String: value

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def config(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> P.Config:
  P.Config{
    urlContext(),
    Client.Defaults{"pi-bend-native-integration", R.new(String), None{}, None{}},
    Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535},
    HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}},
    HTTP.WithTLS{authorizer, TLS.defaults()}, 65536n, False{}}

def model(name: String, base: String) -> T.Model<T.JsonValue>:
  T.Model{name, "Live integration", T.OpenAIResponsesApi{}, "openai", base, False{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

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
    case Client.HTTPFailure{Client.APIError{metadata, _, _}}: "HTTP " ++ U32.show(Response.metadataStatus(metadata))
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

# Opt-in test diagnostics use constructor categories and numeric OS codes only.
# Never render provider messages, JSON paths, payloads, headers or credentials.
def diagnosticSocket(cause: Socket.Error<Deadline.Cause<Unit>>) -> String:
  match cause:
    case Socket.SocketError{code,_}: "socket.os." ++ U32.show(code)
    case Socket.Aborted{_}: "socket.aborted"

def diagnosticTLS(cause: TLS.Error<Deadline.Cause<Unit>>) -> String:
  match cause:
    case TLS.Network{cause}: diagnosticSocket(cause)
    case TLS.Protocol{cause}: "tls." ++ TLSTest.renderError(cause)
    case TLS.WriteQueueFull{_}: "tls.write-queue-full"
    case TLS.Closed{}: "tls.closed"
    case TLS.ShutdownFailure{_}: "tls.shutdown"
    case TLS.InvalidOptions{}: "tls.options"

def diagnosticSource(cause: HTTP.SocketSourceError<Deadline.Cause<Unit>>) -> String:
  match cause:
    case HTTP.TLSSourceFailure{cause}: diagnosticTLS(cause)
    case HTTP.TLSWithCleanup{cause,_}: "cleanup+" ++ diagnosticTLS(cause)
    case HTTP.SocketSourceSocketFailure{_}: "socket.source"
    case HTTP.CleanupFailure{_}: "socket.cleanup"
    case HTTP.UploadFailure{_}: "socket.upload"
    case HTTP.UploadWithCleanup{_,_}: "socket.upload+cleanup"
    case HTTP.Released{}: "socket.released"
    case HTTP.SocketSourceInvalidReadSize{}: "socket.read-size"

def diagnosticReadPrimary(cause: Response.ResponseReaderPrimaryError<HTTP.SocketSourceError<Deadline.Cause<Unit>>>) -> String:
  match cause:
    case Response.SourceError{cause}: diagnosticSource(cause)
    case Response.DecodeError{Response.HeadError{_}}: "http.head"
    case Response.DecodeError{Response.BodyError{_}}: "http.body"
    case Response.DecodeError{Response.ResponseStreamPolicyError{_}}: "http.policy"
    case Response.DecodeError{Response.TooManyInformational{}}: "http.informational-limit"
    case Response.DecodeError{Response.IncompleteResponse{}}: "http.truncated"

def diagnosticRead(cause: Response.ReadError<HTTP.SocketSourceError<Deadline.Cause<Unit>>>) -> String:
  match cause:
    case Response.ResponseReaderPrimaryFailure{cause}: diagnosticReadPrimary(cause)
    case Response.ReleaseFailure{cause}: "release." ++ diagnosticSource(cause)
    case Response.FailureWithRelease{cause,_}: "release+" ++ diagnosticReadPrimary(cause)

def diagnosticExchange(cause: Client.ReadError(Unit)) -> String:
  match cause:
    case HTTP.ResponseFailure{cause}: diagnosticRead(cause)
    case HTTP.DisposalFailure{cause}: "dispose." ++ diagnosticSource(cause)
    case HTTP.ResponseWithDisposal{cause,_}: "dispose+" ++ diagnosticRead(cause)

def diagnosticProgressPrimary(cause: Response.ResponseProgressPrimaryError<Client.ReadError(Unit)>) -> String:
  match cause:
    case Response.TransportFailure{cause}: diagnosticExchange(cause)
    case Response.MissingHead{}: "http.missing-head"
    case Response.MissingCompletion{}: "http.missing-completion"
    case Response.UnexpectedEvent{_}: "http.unexpected-event"

def diagnosticProgress(cause: Response.ResponseProgressError<Client.ReadError(Unit)>) -> String:
  match cause:
    case Response.ResponseProgressPrimaryFailure{cause}: diagnosticProgressPrimary(cause)
    case Response.ResponseProgressCleanupFailure{cause}: "cleanup." ++ diagnosticExchange(cause)
    case Response.ResponseProgressFailureWithCleanup{cause,_}: "cleanup+" ++ diagnosticProgressPrimary(cause)

def diagnosticSSE(cause: SSE.Error<SSE.TransportError(Unit)>) -> String:
  match cause:
    case SSE.TransportFailure{cause}: diagnosticProgress(cause)
    case SSE.DiagnosticFailure{cause}: "sse.diagnostic." ++ diagnosticProgress(cause)
    case SSE.DispatchFailure{SSE.InvalidJson{_,_,_,_}}: "sse.invalid-json"
    case SSE.DispatchFailure{SSE.ApiErrorPayload{_}}: "sse.api-error"

def diagnosticReader(cause: P.ReaderError(Unit)) -> String:
  match cause:
    case ResponsesStream.StreamingFailure{cause}: diagnosticSSE(cause)
    case ResponsesStream.ProtocolFailure{_}: "responses.event-schema"

def diagnosticProcessing(cause: ResponsesStream.Error<P.ReaderError(Unit)>) -> String:
  match cause:
    case ResponsesStream.ReadFailure{cause}: "read." ++ diagnosticReader(cause)
    case ResponsesStream.EmitFailure{cause}: "emit." ++ diagnosticReader(cause)
    case ResponsesStream.ContentFailure{_}: "responses.content"
    case ResponsesStream.TerminalFailure{ResponsesStream.MissingTerminalResponse{}}: "responses.missing-terminal"
    case ResponsesStream.TerminalFailure{ResponsesStream.ProviderFailure{_}}: "responses.provider-error"
    case ResponsesStream.TerminalFailure{ResponsesStream.UnhandledStopReason{_}}: "responses.stop-reason"
    case ResponsesStream.TerminalFailure{ResponsesStream.InvalidReasoningSignature{}}: "responses.reasoning-signature"

def diagnosticAttempt(cause: Client.AttemptError<Unit>) -> String:
  match cause:
    case Client.TransportFailure{Client.FetchFailure{Response.DispatchFailure{Fetch.HeaderFailure{_,_,cause},_}}}: "headers." ++ diagnosticProgress(cause)
    case Client.TransportFailure{Client.FetchFailure{Response.DispatchFailure{Fetch.ExchangeFailure{_,_,HTTP.ResolvedExchangeFailure{HTTP.TLSStartFailure{cause}}},_}}}: "connect." ++ diagnosticTLS(cause)
    case cause: attemptError(cause)

def diagnosticRequest(cause: Retry.RetryFailure<Client.AttemptError<Unit>>) -> String:
  match cause:
    case Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause,_,_,_,_,_}}}: diagnosticAttempt(cause)
    case Retry.RequestFailed{Retry.Other{cause}}: diagnosticAttempt(cause)
    case _: "retry.failed"

def diagnosticError(cause: P.Error<Unit,String>) -> String:
  match cause:
    case P.RequestFailure{cause}: "request." ++ diagnosticRequest(cause)
    case P.ProcessingFailure{cause}: "processing." ++ diagnosticProcessing(cause)
    case P.ReleaseFailure{cause}: "release." ++ diagnosticProgress(cause)
    case P.DisposalFailure{SSE.CursorFailure{cause}}: "dispose.cursor." ++ diagnosticSSE(cause)
    case P.DisposalFailure{_}: "dispose.body"
    case P.HookFailure{_}: "hook"
    case P.OutputFailure{_}: "output"
    case P.MissingStopReason{_}: "missing-stop-reason"
    case P.InvalidRetryOptions{_}: "retry-options"
    case P.EntropyFailure{_}: "entropy"
    case cause: error(cause)

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
