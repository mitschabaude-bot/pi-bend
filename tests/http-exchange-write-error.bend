import Base
import ../packages/runtime/src/http-response-reader.bend as Reader
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/abortable-socket.bend as Transport
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ./tcp-bytes-probe.bend as Probe

def observed(next: Exchange.Next<String>) -> IO(Unit):
  match next:
    case Exchange.Next{Exchange.Closed{}, Fail{Exchange.ResponseFailure{Reader.PrimaryFailure{Reader.SourceError{Source.SocketFailure{Transport.SocketError{32, _}}}}}}}: IO.print("PASS exchange write failure")
    case Exchange.Next{exchange, _}:
      do IO<Unit>:
        result : Result<&2, &2, Exchange.ReadError<String>, Unit> <- Exchange.close(String, exchange)
        IO.die(Unit, 1, "injected write failure was not returned or exchange retained resources")

def failed(result: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "unexpected start failure")
    case Done{exchange}:
      do IO<Unit>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        observed(next)

def start(socket: Socket, signal: A.AbortSignal<String>, request: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match request:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "invalid fixture request")
    case Done{value}:
      do IO<Unit>:
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, signal, value, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        failed(result)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +controller : A.AbortController<String> <- A.new(String)
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Probe.port(args)))
    start(socket, A.signal(String, controller), Request.prepare("POST", "/", Headers.appendField(Headers.new(), H.Header{"host", "example.test"}), Body.Text{"abc"}))
    A.dispose(String, controller)
