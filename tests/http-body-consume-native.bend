import Base
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-body-buffer.bend as Buffer
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/test/http-body-consume.bend as Check
import ../packages/runtime/src/http-exchange-response.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-response-reader.bend as Reader
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Text

def bodyFailure(value: Buffer.Error<Exchange.ReadError<String>>) -> String:
  match value:
    case Buffer.PrimaryFailure{Buffer.ByteLimitExceeded{}}: "limit"
    case _: "transport"

def textFailure(value: Consume.TextError<Exchange.ReadError<String>>) -> String:
  match value:
    case Consume.BodyFailure{cause}: bodyFailure(cause)
    case Consume.InvalidUTF8{_}: "utf8"

def shownBytes(value: Result<&2, &2, Buffer.Error<Exchange.ReadError<String>>, List<&2, U32>>) -> String:
  match value:
    case Fail{cause}: "error:" ++ bodyFailure(cause)
    case Done{bytes}: "bytes:" ++ String.join(Text.showNumbers(bytes), ",")

def shownText(value: Result<&2, &2, Consume.TextError<Exchange.ReadError<String>>, String>) -> String:
  match value:
    case Fail{cause}: "error:" ++ textFailure(cause)
    case Done{text}: "text:" ++ Text.showText(text)

def shownJSON(value: Result<&2, &2, Consume.JSONError<Exchange.ReadError<String>>, V.Value>) -> String:
  match value:
    case Fail{Consume.TextFailure{cause}}: "error:" ++ textFailure(cause)
    case Fail{Consume.InvalidJSON{_}}: "error:json"
    case Done{value}: "json:" ++ Check.show(value)

def consume(mode: U32, limit: Nat, body: Response.Body<Exchange.Exchange<String>>) -> IO(Unit):
  match mode:
    case 1:
      do IO<Unit>:
        result : Result<&2, &2, Consume.TextError<Exchange.ReadError<String>>, String> <- HTTP.text(String, limit, body)
        IO.print(shownText(result))
    case 2:
      do IO<Unit>:
        result : Result<&2, &2, Consume.JSONError<Exchange.ReadError<String>>, V.Value> <- HTTP.json(String, limit, body)
        IO.print(shownJSON(result))
    case _:
      do IO<Unit>:
        result : Result<&2, &2, Buffer.Error<Exchange.ReadError<String>>, List<&2, U32>> <- HTTP.bytes(String, limit, body)
        IO.print(shownBytes(result))

def response(mode: U32, limit: Nat, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.print("start-error")
    case Done{Response.Response{_, body}}: consume(mode, limit, body)

def exchange(mode: U32, limit: Nat, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "exchange start failed")
    case Done{owner}:
      do IO<Unit>:
        value : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.start(String, owner)
        response(mode, limit, value)

def prepared(mode: U32, limit: Nat, +controller: Abort.AbortController<String>, socket: Socket, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match value:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "prepare failed")
    case Done{request}:
      do IO<Unit>:
        value : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, Abort.signal(String, controller), request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        exchange(mode, limit, value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case port <> mode <> method <> budget <> _:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Text.decimal(port, 0)))
        prepared(Text.decimal(mode, 0), U32.to_nat(Text.decimal(budget, 0)), controller, socket, Request.prepare(method, "/body", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
        Abort.dispose(String, controller)
    case _: IO.die(Unit, 1, "expected port mode method budget")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
