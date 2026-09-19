import Base
import ../src/sse-reader.bend as D
import ../src/ref.bend as Ref
import ../src/callback.bend as Cb
import ./sse-decoder-runner.bend as Events
import ../src/sse-decoder.bend as SSE

type Input is Data:
  ChunkStep{chunk: D.Chunk}
  ReadError{}

type Action is Data:
  Pull{}
  Return{}

type Capture is Data:
  Capture{remaining: List<&2, Input>, reversed: List<&2, String>}

type Environment is Data:
  Environment{capture: Ref.Ref<Capture>, closeFails: Bool}

def takeInput(inputs: List<&2, Input>, trace: List<&2, String>) -> Capture & Result<&2, &2, String, Maybe<&2, D.Chunk>>:
  match inputs:
    case Nil{}: (Capture{Nil{}, "read" <> trace}, Done{None{}})
    case ReadError{} <> rest: (Capture{rest, "read" <> trace}, Fail{"read failed"})
    case ChunkStep{chunk} <> rest: (Capture{rest, "read" <> trace}, Done{Some{chunk}})

def readStep(capture: Capture) -> Capture & Result<&2, &2, String, Maybe<&2, D.Chunk>>:
  match capture:
    case Capture{inputs, trace}: takeInput(inputs, trace)

def readCallback(environment: Environment, unused: Unit) -> IO(Result<&2, &2, String, Maybe<&2, D.Chunk>>):
  match environment:
    case Environment{capture, _}: Ref.modify(Capture, Result<&2, &2, String, Maybe<&2, D.Chunk>>, capture, readStep)

def logged(text: String, capture: Capture) -> Capture & Unit:
  match capture:
    case Capture{remaining, trace}: (Capture{remaining, text <> trace}, Unit{})

def log(capture: Ref.Ref<Capture>, text: String) -> IO(Unit):
  Ref.modify(Capture, Unit, capture, state => logged(text, state))

def closeCallback(environment: Environment, unused: Unit) -> IO(Result<&2, &2, String, Unit>):
  match environment:
    case Environment{capture, fails}:
      do IO<Result<&2, &2, String, Unit>>:
        log(capture, "close")
        return Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"close failed"}, Done{Unit{}})

def showNext(result: Result<&2, &2, String, Maybe<&2, SSE.ServerSentEvent>>) -> String:
  match result:
    case Fail{error}: "next:error:" ++ error
    case Done{event}: "next:" ++ Events.showEvent(event)

def recordNext(capture: Ref.Ref<Capture>, next: D.Next<String>) -> IO(D.Cursor<String>):
  match next:
    case D.Next{cursor, result}:
      do IO<D.Cursor<String>>:
        log(capture, showNext(result))
        return cursor

def showClose(result: Result<&2, &2, String, Unit>) -> String:
  match result:
    case Fail{error}: "return:error:" ++ error
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
        next : D.Next<String> <- D.next(String, cursor)
        cursor : D.Cursor<String> <- recordNext(capture, next)
        execute(rest, capture, cursor)
    case Return{} <> rest:
      do IO<D.Cursor<String>>:
        closed : D.CloseResult<String> <- D.close(String, cursor)
        cursor : D.Cursor<String> <- recordClose(capture, closed)
        execute(rest, capture, cursor)

def showCapture(capture: Capture) -> String:
  match capture:
    case Capture{_, trace}: String.join(List.reverse(&2, String, trace), "|")

def run(inputs: List<&2, Input>, actions: List<&2, Action>, +closeFails: Bool) -> IO(Unit):
  do IO<Unit>:
    +capture : Ref.Ref<Capture> <- Ref.new(Capture, Capture{inputs, Nil{}})
    +reader : Cb.Callback<Unit, Result<&2, &2, String, Maybe<&2, D.Chunk>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, String, Maybe<&2, D.Chunk>>, ~readCallback, Environment{capture, closeFails})
    +closer : Cb.Callback<Unit, Result<&2, &2, String, Unit>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, String, Unit>, ~closeCallback, Environment{capture, closeFails})
    finished : D.Cursor<String> <- execute(actions, capture, D.create(String, D.Source{reader, closer}))
    Cb.dispose(Unit, Result<&2, &2, String, Maybe<&2, D.Chunk>>, reader)
    Cb.dispose(Unit, Result<&2, &2, String, Unit>, closer)
    trace : Capture <- Ref.dispose(Capture, capture)
    IO.print(showCapture(trace))
