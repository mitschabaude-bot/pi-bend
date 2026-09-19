import Base
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/http-response-reader.bend as Reader
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/abortable-socket.bend as Transport
import ../packages/runtime/src/abort.bend as A
import ./tcp-bytes-probe.bend as Probe
import ../packages/runtime/test/utf8-runner.bend as Text

type Capture is Data:
  Capture{heads: U32, body: List<&2, U32>, completed: Bool}

def event(capture: Capture, value: Stream.Event) -> Capture:
  match capture value:
    case Capture{heads, body, completed} Stream.FinalHead{_, _}: Capture{(heads + 1 : U32), body, completed}
    case Capture{heads, body, completed} Stream.BodyData{bytes}: Capture{heads, List.append(&2, U32, body, bytes), completed}
    case Capture{heads, body, _} Stream.Completed{_}: Capture{heads, body, True{}}
    case capture _: capture

def error(value: Source.Error<String>) -> String:
  match value:
    case Source.SocketFailure{Transport.Aborted{A.Supplied{reason}}}: "abort:" ++ reason
    case Source.InvalidReadSize{}: "invalid-size"
    case _: "source-error"

def primary(value: Reader.PrimaryError<Source.Error<String>>) -> String:
  match value:
    case Reader.SourceError{why}: error(why)
    case Reader.DecodeError{_}: "decode"

def failure(value: Reader.ReadError<Source.Error<String>>) -> String:
  match value:
    case Reader.PrimaryFailure{why}: primary(why)
    case Reader.ReleaseFailure{why}: "release:" ++ error(why)
    case Reader.FailureWithRelease{why, _}: "both:" ++ primary(why)

def summary(capture: Capture, terminal: String) -> String:
  match capture:
    case Capture{heads, body, completed}: U32.show(heads) ++ ";" ++ String.join(Text.showNumbers(body), ",") ++ ";" ++ Bool.pick(String, completed, "done", "unfinished") ++ ";" ++ terminal

def closeChecked(value: Result<&2, &2, Exchange.ReadError<String>, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "exchange close failed")

def stop(exchange: Exchange.Exchange<String>, capture: Capture, terminal: String) -> IO(String):
  do IO<String>:
    result : Result<&2, &2, Exchange.ReadError<String>, Unit> <- Exchange.close(String, exchange)
    closeChecked(result)
    return summary(capture, terminal)

def exchangeError(value: Exchange.ReadError<String>) -> String:
  match value:
    case Exchange.ResponseFailure{error}: failure(error)
    case _: "cleanup-error"

def retired(next: Exchange.Next<String>) -> IO(Unit):
  match next:
    case Exchange.Next{Exchange.Closed{}, Done{None{}}}: IO.pure(Unit, Unit{})
    case Exchange.Next{exchange, _}:
      do IO<Unit>:
        result : Result<&2, &2, Exchange.ReadError<String>, Unit> <- Exchange.close(String, exchange)
        IO.die(Unit, 1, "terminal exchange retained resources")

def ended(exchange: Exchange.Exchange<String>, capture: Capture, text: String) -> IO(String):
  match exchange:
    case Exchange.Closed{}:
      do IO<String>:
        next : Exchange.Next<String> <- Exchange.next(String, Exchange.Closed{})
        retired(next)
        return summary(capture, text)
    case value:
      do IO<String>:
        result : String <- stop(value, capture, text)
        IO.die(String, 1, "terminal state was not retired")

def loop(fuel: Nat, next: Exchange.Next<String>, capture: Capture, early: Bool) -> IO(String):
  match fuel next:
    case _ Exchange.Next{exchange, Fail{why}}: ended(exchange, capture, exchangeError(why))
    case _ Exchange.Next{exchange, Done{None{}}}: ended(exchange, capture, "eof")
    case Zero{} Exchange.Next{exchange, _}: stop(exchange, capture, "out-of-fuel")
    case Succ{rest} Exchange.Next{exchange, Done{Some{value}}}:
      match early:
        case True{}: stop(exchange, event(capture, value), "early")
        case False{}:
          do IO<String>:
            next : Exchange.Next<String> <- Exchange.next(String, exchange)
            loop(rest, next, event(capture, value), False{})

def earlyMode(mode: U32) -> Bool:
  match mode:
    case 4: True{}
    case _: False{}

def adopted(mode: U32, result: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(String):
  match result:
    case Fail{Exchange.InvalidReadSize{}}: IO.pure(String, "invalid-size")
    case Fail{Exchange.SocketFailure{Transport.Aborted{A.Supplied{why}}}}: IO.pure(String, "start-abort:" ++ why)
    case Fail{_}: IO.die(String, 1, "unexpected exchange start failure")
    case Done{exchange}:
      do IO<String>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        loop(256n, next, Capture{0, Nil{}, False{}}, earlyMode(mode))

def requested(socket: Socket, signal: A.AbortSignal<String>, maximum: U32, request: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>):
  match request:
    case Fail{_}:
      do IO<Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>>:
        Socket.close(socket)
        IO.die(Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>, 1, "invalid fixture request")
    case Done{value}: Exchange.start(~String, socket, signal, value, maximum, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})

def start(socket: Socket, signal: A.AbortSignal<String>, maximum: U32) -> IO(Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>):
  requested(socket, signal, maximum, Request.prepare("GET", "/", Headers.appendField(Headers.new(), H.Header{"host", "example.test"}), Body.Absent{}))

def abortLater(controller: A.AbortController<String>) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(100)
    A.abort(String, controller, Some{"stop"})

def active(socket: Socket, +controller: A.AbortController<String>, +mode: U32) -> IO(String):
  match mode:
    case 3:
      do IO<String>:
        task : Chan(Bool) <- IO.fork(Bool, abortLater(controller))
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- start(socket, A.signal(String, controller), 7)
        text : String <- adopted(3, result)
        won : Bool <- IO.join(Bool, task)
        return text
    case 6:
      do IO<String>:
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- start(socket, A.signal(String, controller), 0)
        adopted(6, result)
    case 7:
      do IO<String>:
        won : Bool <- A.abort(String, controller, Some{"stop"})
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- start(socket, A.signal(String, controller), 7)
        adopted(7, result)
    case other:
      do IO<String>:
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- start(socket, A.signal(String, controller), 7)
        adopted(other, result)

def cases(count: Nat, +port: U32, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        text : String <- active(socket, controller, (index % 8 : U32))
        A.dispose(String, controller)
        IO.print(text)
        cases(rest, port, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(24n, Probe.port(args), 0)
