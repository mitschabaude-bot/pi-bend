import Base
import ../packages/runtime/src/http-exchange.bend as Source
import ../packages/runtime/src/http-response.bend as Reader
import ../packages/runtime/src/http-response.bend as Stream
import ../packages/runtime/src/http-message.bend as Chunked
import ../packages/runtime/src/socket.bend as Socket
import ../packages/runtime/src/abort.bend as A
import ./tcp-bytes-probe.bend as Probe
import ../packages/runtime/test/utf8-runner.bend as Text

type Capture is Data:
  Capture{heads: U32, body: List<&2, U32>, completed: Bool}

def event(capture: Capture, value: Stream.StreamEvent) -> Capture:
  match capture value:
    case Capture{heads, body, completed} Stream.FinalHead{_, _}: Capture{(heads + 1 : U32), body, completed}
    case Capture{heads, body, completed} Stream.BodyData{bytes}: Capture{heads, List.append(&2, U32, body, bytes), completed}
    case Capture{heads, body, _} Stream.Completed{_}: Capture{heads, body, True{}}
    case capture _: capture

def error(value: Source.SocketSourceError<String>) -> String:
  match value:
    case Source.SocketSourceSocketFailure{Socket.Aborted{A.Supplied{reason}}}: "abort:" ++ reason
    case Source.SocketSourceInvalidReadSize{}: "invalid-size"
    case _: "source-error"

def primary(value: Reader.ResponseReaderPrimaryError<Source.SocketSourceError<String>>) -> String:
  match value:
    case Reader.SourceError{why}: error(why)
    case Reader.DecodeError{_}: "decode"

def failure(value: Reader.ReadError<Source.SocketSourceError<String>>) -> String:
  match value:
    case Reader.ResponseReaderPrimaryFailure{why}: primary(why)
    case Reader.ReleaseFailure{why}: "release:" ++ error(why)
    case Reader.FailureWithRelease{why, _}: "both:" ++ primary(why)

def summary(capture: Capture, terminal: String) -> String:
  match capture:
    case Capture{heads, body, completed}: U32.show(heads) ++ ";" ++ String.join(Text.showNumbers(body), ",") ++ ";" ++ Bool.pick(String, completed, "done", "unfinished") ++ ";" ++ terminal

def closeChecked(value: Reader.CloseResult<Source.SocketSourceError<String>>) -> IO(Unit):
  match value:
    case Reader.CloseResult{_, Done{_}}: IO.pure(Unit, Unit{})
    case Reader.CloseResult{_, Fail{_}}: IO.die(Unit, 1, "reader close failed")

def stop(cursor: Reader.Cursor<Source.SocketSourceError<String>>, capture: Capture, terminal: String) -> IO(String):
  do IO<String>:
    closed : Reader.CloseResult<Source.SocketSourceError<String>> <- Reader.closeReader(Source.SocketSourceError<String>, cursor)
    closeChecked(closed)
    return summary(capture, terminal)

def loop(fuel: Nat, next: Reader.ResponseReaderNext<Source.SocketSourceError<String>>, capture: Capture, +early: Bool) -> IO(String):
  match fuel next:
    case _ Reader.ResponseReaderNext{cursor, Fail{why}}: stop(cursor, capture, failure(why))
    case _ Reader.ResponseReaderNext{cursor, Done{None{}}}: stop(cursor, capture, "eof")
    case Zero{} Reader.ResponseReaderNext{cursor, _}: stop(cursor, capture, "out-of-fuel")
    case Succ{rest} Reader.ResponseReaderNext{cursor, Done{Some{value}}}:
      match early:
        case True{}: stop(cursor, event(capture, value), "early")
        case False{}:
          do IO<String>:
            next : Reader.ResponseReaderNext<Source.SocketSourceError<String>> <- Reader.readerNext(Source.SocketSourceError<String>, cursor)
            loop(rest, next, event(capture, value), False{})

def sourceClosed(result: Result<&2, &2, Source.SocketSourceError<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "source disposal failed")

def stream(pair: Source.Owner<String> & Reader.Source<Source.SocketSourceError<String>>, early: Bool) -> IO(String):
  match pair:
    case (owner, source):
      do IO<String>:
        next : Reader.ResponseReaderNext<Source.SocketSourceError<String>> <- Reader.readerNext(Source.SocketSourceError<String>, Reader.createReader(Source.SocketSourceError<String>, source, "GET", Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}))
        text : String <- loop(256n, next, Capture{0, Nil{}, False{}}, early)
        result : Result<&2, &2, Source.SocketSourceError<String>, Unit> <- Source.dispose(String, owner)
        sourceClosed(result)
        return text

def earlyMode(mode: U32) -> Bool:
  match mode:
    case 4: True{}
    case _: False{}

def adopted(mode: U32, result: Result<&2, &1, Source.SocketSourceError<String>, Source.Owner<String>>) -> IO(String):
  match result:
    case Fail{why}: IO.pure(String, error(why))
    case Done{owner}: stream(Source.borrow(String, owner), earlyMode(mode))

def abortLater(controller: A.AbortController<String>) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(100)
    A.abort(String, controller, Some{"stop"})

def active(socket: Socket, +controller: A.AbortController<String>, +mode: U32) -> IO(String):
  match mode:
    case 3:
      do IO<String>:
        task : Chan(Bool) <- IO.fork(Bool, abortLater(controller))
        result : Result<&2, &1, Source.SocketSourceError<String>, Source.Owner<String>> <- Source.create(~String, socket, A.signal(String, controller), 7)
        text : String <- adopted(3, result)
        won : Bool <- IO.join(Bool, task)
        return text
    case 6:
      do IO<String>:
        result : Result<&2, &1, Source.SocketSourceError<String>, Source.Owner<String>> <- Source.create(~String, socket, A.signal(String, controller), 0)
        adopted(6, result)
    case other:
      do IO<String>:
        result : Result<&2, &1, Source.SocketSourceError<String>, Source.Owner<String>> <- Source.create(~String, socket, A.signal(String, controller), 7)
        adopted(other, result)

def cases(count: Nat, +port: U32, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        text : String <- active(socket, controller, (index % 7 : U32))
        A.dispose(String, controller)
        IO.print(text)
        cases(rest, port, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(21n, Probe.port(args), 0)
