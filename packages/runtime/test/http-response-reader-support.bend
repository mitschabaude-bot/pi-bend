import Base
import ../src/http-response.bend as D
import ../src/ref.bend as Ref
import ../src/callback.bend as Cb
import ./http-response-stream.bend as Events
import ../src/http-response.bend as Stream
import ../src/http-message.bend as Chunked
import ./utf8-runner.bend as Text

type Input is Data:
  ChunkStep{chunk: List<&2, U32>}
  ReadError{}
  ResetError{}

type Action is Data:
  Pull{}
  Return{}

type Capture is Data:
  Capture{remaining: List<&2, Input>, reversed: List<&2, String>}

type Environment is Data:
  Environment{capture: Ref.Ref<Capture>, closeFails: Bool}

def takeInput(inputs: List<&2, Input>, trace: List<&2, String>) -> Capture & Result<&2, &2, String, Maybe<&2, List<&2, U32>>>:
  match inputs:
    case Nil{}: (Capture{Nil{}, "read" <> trace}, Done{None{}})
    case ResetError{} <> rest: (Capture{rest, "read" <> trace}, Fail{"reset"})
    case ReadError{} <> rest: (Capture{rest, "read" <> trace}, Fail{"read failed"})
    case ChunkStep{chunk} <> rest: (Capture{rest, "read" <> trace}, Done{Some{chunk}})

def readStep(capture: Capture) -> Capture & Result<&2, &2, String, Maybe<&2, List<&2, U32>>>:
  match capture:
    case Capture{inputs, trace}: takeInput(inputs, trace)

def readCallback(environment: Environment, unused: Unit) -> IO(Result<&2, &2, String, Maybe<&2, List<&2, U32>>>):
  match environment:
    case Environment{capture, _}: Ref.modify(Capture, Result<&2, &2, String, Maybe<&2, List<&2, U32>>>, capture, readStep)

def logged(text: String, capture: Capture) -> Capture & Unit:
  match capture:
    case Capture{remaining, trace}: (Capture{remaining, text <> trace}, Unit{})

def log(capture: Ref.Ref<Capture>, text: String) -> IO(Unit):
  Ref.modify(Capture, Unit, capture, state => logged(text, state))

def releaseReason(reason: D.ReleaseReason) -> String:
  match reason:
    case D.MessageComplete{rest}: "complete:" ++ String.join(Text.showNumbers(rest), ",")
    case D.CleanEOF{}: "eof"
    case D.ResetEOF{}: "reset"
    case D.DecodeFailure{}: "decode"
    case D.ResponseReaderReadFailure{}: "read-error"
    case D.EarlyClose{}: "early"

def releaseText(request: D.Release) -> String:
  match request:
    case D.Release{reason, None{}}: "release:" ++ releaseReason(reason) ++ ":no-head"
    case D.Release{reason, Some{head}}: "release:" ++ releaseReason(reason) ++ ":" ++ Events.code(head)

def closeCallback(environment: Environment, request: D.Release) -> IO(Result<&2, &2, String, Unit>):
  match environment:
    case Environment{capture, fails}:
      do IO<Result<&2, &2, String, Unit>>:
        log(capture, releaseText(request))
        return Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"close failed"}, Done{Unit{}})

def primary(error: D.ResponseReaderPrimaryError<String>) -> String:
  match error:
    case D.SourceError{error}: "source:" ++ error
    case D.DecodeError{_}: "decode"

def failure(error: D.ReadError<String>) -> String:
  match error:
    case D.ResponseReaderPrimaryFailure{error}: primary(error)
    case D.ReleaseFailure{error}: "release:" ++ error
    case D.FailureWithRelease{error, release}: primary(error) ++ "+release:" ++ release

def showNext(result: Result<&2, &2, D.ReadError<String>, Maybe<&2, Stream.StreamEvent>>) -> String:
  match result:
    case Fail{error}: "next:error:" ++ failure(error)
    case Done{None{}}: "next:none"
    case Done{Some{event}}: "next:" ++ Events.event(event)

def recordNext(capture: Ref.Ref<Capture>, next: D.ResponseReaderNext<String>) -> IO(D.Cursor<String>):
  match next:
    case D.ResponseReaderNext{cursor, result}:
      do IO<D.Cursor<String>>:
        log(capture, showNext(result))
        return cursor

def showClose(result: Result<&2, &2, D.ReadError<String>, Unit>) -> String:
  match result:
    case Fail{error}: "return:error:" ++ failure(error)
    case Done{_}: "return:ok"

def recordClose(capture: Ref.Ref<Capture>, closed: D.CloseResult<String>) -> IO(D.Cursor<String>):
  match closed:
    case D.CloseResult{cursor, result}:
      do IO<D.Cursor<String>>:
        log(capture, showClose(result))
        return cursor

def execute(actions: List<&2, Action>, +capture: Ref.Ref<Capture>, cursor: D.Cursor<String>) -> IO(D.Cursor<String>):
  match actions:
    case Nil{}: IO.pure(D.Cursor<String>, cursor)
    case Pull{} <> rest:
      do IO<D.Cursor<String>>:
        next : D.ResponseReaderNext<String> <- D.nextResponseReader(String, cursor)
        cursor : D.Cursor<String> <- recordNext(capture, next)
        execute(rest, capture, cursor)
    case Return{} <> rest:
      do IO<D.Cursor<String>>:
        closed : D.CloseResult<String> <- D.closeResponseReader(String, cursor)
        cursor : D.Cursor<String> <- recordClose(capture, closed)
        execute(rest, capture, cursor)

def showCapture(capture: Capture) -> String:
  match capture:
    case Capture{_, trace}: String.join(List.reverse(&2, String, trace), "|")

def run(inputs: List<&2, Input>, actions: List<&2, Action>, +closeFails: Bool) -> IO(Unit):
  do IO<Unit>:
    +capture : Ref.Ref<Capture> <- Ref.new(Capture, Capture{inputs, Nil{}})
    +reader : Cb.Callback<Unit, Result<&2, &2, String, Maybe<&2, List<&2, U32>>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, String, Maybe<&2, List<&2, U32>>>, ~readCallback, Environment{capture, closeFails})
    +closer : Cb.Callback<D.Release, Result<&2, &2, String, Unit>> <- Cb.create(~Environment, ~D.Release, ~Result<&2, &2, String, Unit>, ~closeCallback, Environment{capture, closeFails})
    finished : D.Cursor<String> <- execute(actions, capture, D.createResponseReader(String, D.Source{reader, closer}, "GET", Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}))
    cleanup : D.CloseResult<String> <- D.closeResponseReader(String, finished)
    Cb.dispose(Unit, Result<&2, &2, String, Maybe<&2, List<&2, U32>>>, reader)
    Cb.dispose(D.Release, Result<&2, &2, String, Unit>, closer)
    trace : Capture <- Ref.dispose(Capture, capture)
    IO.print(showCapture(trace))


def transportResult(result: Result<&2, &2, String, Maybe<&2, List<&2, U32>>>) -> D.ReadResult<String>:
  match result:
    case Fail{"reset"}: D.Reset{"reset"}
    case value: D.fromResult(String, value)

def transportCallback(environment: Environment, unused: Unit) -> IO(D.ReadResult<String>):
  do IO<D.ReadResult<String>>:
    result : Result<&2, &2, String, Maybe<&2, List<&2, U32>>> <- readCallback(environment, unused)
    return transportResult(result)

def runTransport(inputs: List<&2, Input>, actions: List<&2, Action>, +closeFails: Bool) -> IO(Unit):
  do IO<Unit>:
    +capture : Ref.Ref<Capture> <- Ref.new(Capture, Capture{inputs, Nil{}})
    +reader : Cb.Callback<Unit, D.ReadResult<String>> <- Cb.create(~Environment, ~Unit, ~D.ReadResult<String>, ~transportCallback, Environment{capture, closeFails})
    +closer : Cb.Callback<D.Release, Result<&2, &2, String, Unit>> <- Cb.create(~Environment, ~D.Release, ~Result<&2, &2, String, Unit>, ~closeCallback, Environment{capture, closeFails})
    finished : D.Cursor<String> <- execute(actions, capture, D.createResponseReader(String, D.TransportSource{reader, closer}, "GET", Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}))
    cleanup : D.CloseResult<String> <- D.closeResponseReader(String, finished)
    Cb.dispose(Unit, D.ReadResult<String>, reader)
    Cb.dispose(D.Release, Result<&2, &2, String, Unit>, closer)
    trace : Capture <- Ref.dispose(Capture, capture)
    IO.print(showCapture(trace))
