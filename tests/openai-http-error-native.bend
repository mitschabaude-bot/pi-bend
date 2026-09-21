import Base
import ../packages/ai/src/api/openai-http-error.bend as Error
import ../packages/ai/src/utils/provider-http-response.bend as Provider
import ../packages/ai/test/openai-http-error.bend as View
import ../packages/runtime/src/http-exchange-response.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/test/utf8-runner.bend as Text
import ./http-body-consume-native.bend as Show

def constructed(provider: String, value: Result<&2, &2, Error.ConstructionError<Exchange.ReadError<String>>, Error.APIError>) -> IO(Unit):
  match value:
    case Done{value}: View.shown(provider, value)
    case Fail{Error.DiagnosticReadFailure{metadata, cause}}: IO.print("read-error:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Show.textFailure(cause))
    case Fail{Error.DiagnosticEncodingFailure{metadata, _}}: IO.print("encoding-error:" ++ U32.show(Metadata.status(metadata)))

def accepted(provider: String, value: Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{cause}: constructed(provider, Error.fromResponse(Exchange.ReadError<String>, cause))
    case Done{Response.Response{metadata, body}}:
      do IO<Unit>:
        IO.print("accepted:" ++ U32.show(Metadata.status(metadata)))
        result : Result<&2, &2, Consume.TextError<Exchange.ReadError<String>>, String> <- HTTP.text(~String, 1000n, body)
        IO.print(Show.shownText(result))

def headed(provider: String, limit: Nat, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "head failed")
    case Done{response}:
      do IO<Unit>:
        result : Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- Provider.acceptWith(~(Exchange.ReadError<String>), ~(Exchange.Exchange<String>), ~(HTTP.read(String)), ~(Exchange.close(String)), limit, response)
        accepted(provider, result)

def started(provider: String, limit: Nat, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "start failed")
    case Done{owner}:
      do IO<Unit>:
        result : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.start(~String, owner)
        headed(provider, limit, result)

def prepared(port: U32, provider: String, limit: Nat, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "prepare failed")
    case Done{request}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, A.signal(String, controller), request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        started(provider, limit, result)
        A.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> provider <> limit <> Nil{}: prepared(Text.decimal(port, 0), provider, U32.to_nat(Text.decimal(limit, 0)), Request.prepare("GET", "/error", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
    case _: IO.die(Unit, 1, "expected port provider diagnostic-limit")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
