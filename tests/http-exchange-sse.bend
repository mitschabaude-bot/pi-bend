import Base
import ../packages/runtime/src/http-exchange-response.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-body-source.bend as Source
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/sse-reader.bend as SSE
import ../packages/runtime/src/sse-decoder.bend as Event
import ../packages/runtime/test/utf8-runner.bend as Text

def mapped(value: Progress.Error<Exchange.ReadError<String>>) -> String: "transport"

def result(value: Result<&2, &2, String, Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{error}: "error:" ++ error

def finished(owner: Source.Owner<Exchange.Exchange<String>, String>, value: SSE.CloseResult<String>) -> IO(Unit):
  match value:
    case SSE.CloseResult{_, value}:
      do IO<Unit>:
        IO.print("reader-close:" ++ result(value))
        disposed : Result<&2, &2, String, Unit> <- Source.dispose(Exchange.Exchange<String>, String, owner)
        IO.print("dispose:" ++ result(disposed))

def loop(fuel: Nat, +early: Bool, owner: Source.Owner<Exchange.Exchange<String>, String>, value: SSE.Next<String>) -> IO(Unit):
  match fuel early value:
    case Succ{rest} False{} SSE.Next{cursor, Done{Some{Event.ServerSentEvent{_, data, _}}}}:
      do IO<Unit>:
        IO.print("data:" ++ Text.showText(data))
        next : SSE.Next<String> <- SSE.next(String, cursor)
        loop(rest, early, owner, next)
    case _ _ SSE.Next{cursor, Done{Some{Event.ServerSentEvent{_, data, _}}}}:
      do IO<Unit>:
        IO.print("data:" ++ Text.showText(data))
        closed : SSE.CloseResult<String> <- SSE.close(String, cursor)
        finished(owner, closed)
    case _ _ SSE.Next{cursor, Done{None{}}}:
      do IO<Unit>:
        IO.print("end")
        closed : SSE.CloseResult<String> <- SSE.close(String, cursor)
        finished(owner, closed)
    case _ _ SSE.Next{cursor, Fail{error}}:
      do IO<Unit>:
        IO.print("error:" ++ error)
        closed : SSE.CloseResult<String> <- SSE.close(String, cursor)
        finished(owner, closed)

def acquired(mode: U32, pair: Source.Owner<Exchange.Exchange<String>, String> & SSE.Source<String>) -> IO(Unit):
  match mode pair:
    case 2 Tuple{owner, source}:
      do IO<Unit>:
        closed : SSE.CloseResult<String> <- SSE.close(String, SSE.create(String, source))
        finished(owner, closed)
    case other Tuple{owner, source}:
      do IO<Unit>:
        next : SSE.Next<String> <- SSE.next(String, SSE.create(String, source))
        loop(128n, U32.is_eq(other, 1), owner, next)

def response(mode: U32, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "response failed")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        owner : Source.Owner<Exchange.Exchange<String>, String> <- HTTP.source(~String, ~String, ~mapped, body)
        acquired(mode, Source.borrow(Exchange.Exchange<String>, String, owner))

def exchange(mode: U32, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "exchange failed")
    case Done{owner}:
      do IO<Unit>:
        value : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.start(String, owner)
        response(mode, value)

def prepared(mode: U32, socket: Socket, signal: Abort.AbortSignal<String>, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match value:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "prepare failed")
    case Done{request}:
      do IO<Unit>:
        value : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, signal, request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        exchange(mode, value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case port <> mode <> _:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Text.decimal(port, 0)))
        prepared(Text.decimal(mode, 0), socket, Abort.signal(String, controller), Request.prepare("GET", "/sse", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
        Abort.dispose(String, controller)
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
