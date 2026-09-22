import Base
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response.bend as Progress
import ../packages/runtime/src/http-response.bend as Metadata
import ../packages/runtime/src/http-exchange.bend as Exchange
import ../packages/runtime/src/http-response.bend as Reader
import ../packages/runtime/src/http-exchange.bend as Source
import ../packages/runtime/src/socket.bend as SocketIO
import ../packages/runtime/src/http-message.bend as Request
import ../packages/runtime/src/http-message.bend as Body
import ../packages/runtime/src/http-response.bend as Stream
import ../packages/runtime/src/http-message.bend as Chunked
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-message.bend as Header
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Text

def result(value: Result<&2, &2, Progress.ResponseProgressError<Exchange.ReadError<String>>, Maybe<&2, List<&2, U32>>>) -> String:
  match value:
    case Done{None{}}: "end"
    case Done{Some{bytes}}: "bytes:" ++ String.join(Text.showNumbers(bytes), ",")
    case Fail{Progress.ResponseProgressPrimaryFailure{Progress.TransportFailure{Exchange.ResponseFailure{Reader.ResponseReaderPrimaryFailure{Reader.SourceError{Source.SocketSourceSocketFailure{SocketIO.SocketAborted{Abort.Supplied{reason}}}}}}}}}: "abort:" ++ reason
    case Fail{_}: "error"

def closed(value: Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Response.Next{Response.Closed{_}, outcome}: IO.print("closed:" ++ result(outcome))
    case _: IO.die(Unit, 1, "owner not closed")

def loop(fuel: Nat, value: Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match fuel value:
    case Succ{rest} Response.Next{body, Done{Some{bytes}}}:
      do IO<Unit>:
        IO.print("bytes:" ++ String.join(Text.showNumbers(bytes), ","))
        next : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- HTTP.next(~String, body)
        loop(rest, next)
    case _ Response.Next{body, outcome}:
      do IO<Unit>:
        IO.print(result(outcome))
        ended : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- HTTP.close(String, body)
        closed(ended)

def consume(mode: U32, controller: Abort.AbortController<String>, body: Response.Body<Exchange.Exchange<String>>) -> IO(Unit):
  match mode:
    case 1:
      do IO<Unit>:
        ended : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- HTTP.close(String, body)
        closed(ended)
    case 2:
      do IO<Unit>:
        task : Chan(Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>) <- IO.fork(Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>, HTTP.next(~String, body))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        next : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- IO.join(Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>, task)
        loop(128n, next)
    case _:
      do IO<Unit>:
        next : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- HTTP.next(~String, body)
        loop(128n, next)

def response(mode: U32, controller: Abort.AbortController<String>, value: Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.print("start-error")
    case Done{Response.Response{+metadata, body}}:
      do IO<Unit>:
        IO.print("head:" ++ U32.show(Metadata.statusResponseMetadata(metadata)) ++ ":" ++ Bool.pick(String, Metadata.bodyPresent(metadata), "body", "null"))
        consume(mode, controller, body)

def exchange(mode: U32, controller: Abort.AbortController<String>, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "exchange start failed")
    case Done{owner}:
      do IO<Unit>:
        value : Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.startExchangeResponse(~String, owner)
        response(mode, controller, value)

def prepared(mode: U32, +controller: Abort.AbortController<String>, socket: Socket, value: Result<&2, &2, Request.RequestError, Request.BufferedRequestPrepared>) -> IO(Unit):
  match value:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "prepare failed")
    case Done{request}:
      do IO<Unit>:
        value : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.startSocketExchange(~String, socket, Abort.signal(String, controller), request, 4096, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        exchange(mode, controller, value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case port <> mode <> method <> _:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Text.decimal(port, 0)))
        prepared(Text.decimal(mode, 0), controller, socket, Request.prepareBufferedRequest(method, "/body", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
        Abort.dispose(String, controller)
    case _: IO.die(Unit, 1, "expected port mode method")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
