import Base
import ../packages/runtime/src/http-connect-exchange.bend as Client
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-response-reader.bend as Reader
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/http-response-stream.bend as Response
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ./http-request-exchange.bend as Consume
import ./abortable-connect.bend as Address
import ./connect-owned.bend as Test
import ../packages/runtime/test/utf8-runner.bend as Scalar

def limits() -> Response.Limits:
  Response.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}

def prepared(value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Request.Prepared):
  match value:
    case Done{value}: IO.pure(Request.Prepared, value)
    case Fail{_}: IO.die(Request.Prepared, 1, "request preparation failed")

def request() -> IO(Request.Prepared):
  prepared(Request.prepare("POST", "/connect", Headers.appendField(Headers.new(), Header.Header{"host", "logical.example"}), Body.Text{"hello"}))

def failed(next: Exchange.Next<String>) -> IO(Unit):
  match next:
    case Exchange.Next{exchange, Fail{Exchange.ResponseFailure{Reader.PrimaryFailure{Reader.SourceError{Source.SocketFailure{SocketIO.Aborted{Abort.Supplied{reason}}}}}}}}:
      do IO<Unit>:
        Consume.close(exchange)
        Test.assertion(String.eq(reason, "stop"), "read lost original abort reason")
    case Exchange.Next{exchange, _}:
      do IO<Unit>:
        Consume.close(exchange)
        IO.die(Unit, 1, "expected typed read abort")

# The peer sends only a final head, then withholds body bytes. Abort a read
# already launched after consuming the head, using the same connect signal.
def head(fuel: Nat, +controller: Abort.AbortController<String>, next: Exchange.Next<String>) -> IO(Unit):
  match fuel next:
    case _ Exchange.Next{exchange, Done{Some{Response.FinalHead{_, _}}}}:
      do IO<Unit>:
        task : Chan(Exchange.Next<String>) <- IO.fork(Exchange.Next<String>, Exchange.next(String, exchange))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        result : Exchange.Next<String> <- IO.join(Exchange.Next<String>, task)
        failed(result)
    case Succ{rest} Exchange.Next{exchange, Done{Some{_}}}:
      do IO<Unit>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        head(rest, controller, next)
    case _ Exchange.Next{exchange, _}:
      do IO<Unit>:
        Consume.close(exchange)
        IO.die(Unit, 1, "expected final head")

def success(mode: String, controller: Abort.AbortController<String>, exchange: Exchange.Exchange<String>) -> IO(Unit):
  match mode:
    case "success":
      do IO<Unit>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        Consume.loop(128n, next, Nil{})
    case "read":
      do IO<Unit>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        head(128n, controller, next)
    case _:
      do IO<Unit>:
        Consume.close(exchange)
        IO.die(Unit, 1, "unexpected exchange")

def result(+mode: String, code: U32, controller: Abort.AbortController<String>, value: Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Done{exchange}: success(mode, controller, exchange)
    case Fail{Client.ConnectionFailure{Connect.Aborted{Abort.Supplied{reason}}}}:
      Test.assertion((String.eq(mode, "pre") || String.eq(mode, "pending")) && String.eq(reason, "stop"), "wrong connect abort")
    case Fail{Client.ConnectionFailure{Connect.SocketError{actual, _}}}: Test.assertion(String.eq(mode, "error") && U32.is_eq(actual, code), "wrong connect errno")
    case Fail{Client.ExchangeFailure{Exchange.InvalidReadSize{}}}: Test.assertion(String.eq(mode, "zero"), "unexpected size error")
    case _: IO.die(Unit, 1, "unexpected start failure")

def run(+mode: String, +request: Request.Prepared, endpoint: Connect.Address, port: U32, code: U32, +controller: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "pending":
      do IO<Unit>:
        task : Chan(Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>>) <- IO.fork(Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>>, Client.start(~String, endpoint, port, Abort.signal(String, controller), request, 7, limits()))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        value : Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>> <- IO.join(Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>>, task)
        result(mode, code, controller, value)
    case "pre":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        value : Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>> <- Client.start(~String, endpoint, port, Abort.signal(String, controller), request, 7, limits())
        result(mode, code, controller, value)
    case _:
      do IO<Unit>:
        value : Result<&2, &1, Client.Error<String>, Exchange.Exchange<String>> <- Client.start(~String, endpoint, port, Abort.signal(String, controller), request, Bool.pick(U32, String.eq(mode, "zero"), 0, 7), limits())
        result(mode, code, controller, value)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> code <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        request : Request.Prepared <- request()
        run(mode, request, Address.address(String.eq(family, "6")), Scalar.decimal(port, 0), Scalar.decimal(code, 0), controller)
        Abort.dispose(String, controller)
        IO.print("PASS HTTP connect exchange")
    case _: IO.die(Unit, 1, "expected mode family port errno")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
