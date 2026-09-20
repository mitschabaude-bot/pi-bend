import Base
import ../packages/ai/src/api/openai-http-errors.bend as Errors
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-response-reader.bend as Reader
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/abortable-socket.bend as Socket
import ../packages/runtime/src/socket-upload.bend as Upload
import ../packages/runtime/src/socket-interrupt.bend as Interrupt
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Text

def source(code: U32) -> Source.Error<String>:
  match code:
    case 0: Source.SocketFailure{Socket.Aborted{Abort.DefaultAbort{}}}
    case 1: Source.SocketFailure{Socket.Aborted{Abort.Supplied{"stop"}}}
    case 2: Source.SocketFailure{Socket.SocketError{17, "AbortError"}}
    case 3: Source.UploadFailure{Upload.WriteFailure{Socket.Aborted{Abort.Supplied{"stop"}}, None{}}}
    case 4: Source.UploadFailure{Upload.WriteFailure{Socket.Aborted{Abort.DefaultAbort{}}, Some{Interrupt.Error{17, "cleanup"}}}}
    case 5: Source.UploadWithCleanup{Upload.WriteFailure{Socket.Aborted{Abort.DefaultAbort{}}, None{}}, Interrupt.Error{17, "cleanup"}}
    case 6: Source.Released{}
    case 7: Source.InvalidReadSize{}
    case 8: Source.CleanupFailure{Interrupt.Error{17, "cleanup"}}
    case 9: Source.UploadFailure{Upload.InterruptFailure{Interrupt.Error{17, "interrupt"}}}
    case 10: Source.UploadFailure{Upload.WriteFailure{Socket.SocketError{17, "AbortError"}, None{}}}
    case _: Source.SocketFailure{Socket.SocketError{0, "Request was aborted"}}

def reader(mode: U32, +error: Source.Error<String>) -> Reader.ReadError<Source.Error<String>>:
  match mode:
    case 0: Reader.PrimaryFailure{Reader.SourceError{error}}
    case 1: Reader.ReleaseFailure{error}
    case _: Reader.FailureWithRelease{Reader.SourceError{error}, error}

def exchange(mode: U32, error: Reader.ReadError<Source.Error<String>>, cause: Source.Error<String>) -> Exchange.ReadError<String>:
  match mode:
    case 0: Exchange.ResponseFailure{error}
    case 1: Exchange.DisposalFailure{cause}
    case _: Exchange.ResponseWithDisposal{error, cause}

def progress(mode: U32, +error: Exchange.ReadError<String>) -> Errors.TransportError(String):
  match mode:
    case 0: Progress.PrimaryFailure{Progress.TransportFailure{error}}
    case 1: Progress.CleanupFailure{error}
    case 2: Progress.FailureWithCleanup{Progress.TransportFailure{error}, error}
    case 3: Progress.PrimaryFailure{Progress.MissingHead{}}
    case _: Progress.PrimaryFailure{Progress.MissingCompletion{}}

def shown(value: SSE.ReadError<Errors.TransportError(String)>) -> String:
  match value:
    case SSE.Aborted{}: "abort"
    case SSE.Failure{_}: "failure"

def run(parts: List<&2, U32>) -> IO(Unit):
  match parts:
    case leaf <> r <> e <> p <> Nil{}:
      +cause = source(leaf)
      IO.print(shown(Errors.classify(String, progress(p, exchange(e, reader(r, cause), cause)))))
    case _: IO.die(Unit, 1, "expected four error codes")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        run(Text.parseNumbers(first))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
