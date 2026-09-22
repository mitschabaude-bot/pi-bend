import Base
import ../../runtime/src/sse-reader.bend as D
import ../src/api/openai-sse.bend as Sse
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/callback.bend as Cb

type Input is Data:
  ChunkStep{chunk: D.Chunk}
  ReadError{}
  ReadAbort{}

type Action is Data:
  Pull{}
  Return{}

type Capture is Data:
  Capture{remaining: List<&2, Input>, reversed: List<&2, String>}

type Environment is Data:
  Environment{capture: Ref.Ref<Capture>, closeMode: String, diagnosticMode: String}

def takeInput(inputs: List<&2, Input>, trace: List<&2, String>) -> Capture & Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>:
  match inputs:
    case Nil{}: (Capture{Nil{}, "read" <> trace}, Done{None{}})
    case ReadError{} <> rest: (Capture{rest, "read" <> trace}, Fail{Sse.Failure{"read failed"}})
    case ReadAbort{} <> rest: (Capture{rest, "read" <> trace}, Fail{Sse.Aborted{}})
    case ChunkStep{chunk} <> rest: (Capture{rest, "read" <> trace}, Done{Some{chunk}})

def readStep(capture: Capture) -> Capture & Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>:
  match capture:
    case Capture{inputs, trace}: takeInput(inputs, trace)

def readCallback(environment: Environment, unused: Unit) -> IO(Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>):
  match environment:
    case Environment{capture, _, _}: Ref.modify(Capture, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>, capture, readStep)

def logged(text: String, capture: Capture) -> Capture & Unit:
  match capture:
    case Capture{remaining, trace}: (Capture{remaining, text <> trace}, Unit{})

def log(capture: Ref.Ref<Capture>, text: String) -> IO(Unit):
  Ref.modify(Capture, Unit, capture, state => logged(text, state))

def effectResult(mode: String, error: String) -> Result<&2, &2, Sse.ReadError<String>, Unit>:
  match mode:
    case "1": Fail{Sse.Failure{error}}
    case "2": Fail{Sse.Aborted{}}
    case _: Done{Unit{}}

def abortCallback(environment: Environment, unused: Unit) -> IO(Unit):
  match environment:
    case Environment{capture, _, _}: log(capture, "abort")

def diagnosticName(target: Sse.DiagnosticTarget) -> String:
  match target:
    case Sse.ClientLogger{}: "diagnostic:client"
    case Sse.ConsoleLogger{}: "diagnostic:console"

def diagnosticCallback(environment: Environment, error: Sse.DispatchError) -> IO(Result<&2, &2, Sse.ReadError<String>, Unit>):
  match environment error:
    case Environment{capture, _, mode} Sse.InvalidJson{_, _, _, target}:
      do IO<Result<&2, &2, Sse.ReadError<String>, Unit>>:
        log(capture, diagnosticName(target))
        return effectResult(mode, "diagnostic failed")
    case _ _: IO.die(Result<&2, &2, Sse.ReadError<String>, Unit>, 1, "unexpected diagnostic")

def closeCallback(environment: Environment, unused: Unit) -> IO(Result<&2, &2, Sse.ReadError<String>, Unit>):
  match environment:
    case Environment{capture, mode, _}:
      do IO<Result<&2, &2, Sse.ReadError<String>, Unit>>:
        log(capture, "close")
        return effectResult(mode, "close failed")

def showError(error: Sse.Error<String>) -> String:
  match error:
    case Sse.TransportFailure{cause}: cause
    case Sse.DiagnosticFailure{cause}: cause
    case Sse.DispatchFailure{Sse.InvalidJson{_, _, _, _}}: "json"
    case Sse.DispatchFailure{Sse.ApiErrorPayload{_}}: "api"

def showValue(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: "unexpected value"

def showEvent(event: Maybe<&2, String>) -> String:
  match event:
    case None{}: "absent"
    case Some{event}: event

def showNext(result: Result<&2, &2, Sse.Error<String>, Maybe<&2, Sse.Message>>) -> String:
  match result:
    case Fail{error}: "next:error:" ++ showError(error)
    case Done{None{}}: "next:-"
    case Done{Some{Sse.JsonMessage{data}}}: "next:" ++ showValue(data)
    case Done{Some{Sse.EventMessage{event, data}}}: "next:event:" ++ showEvent(event) ++ ":" ++ showValue(data)

def recordNext(capture: Ref.Ref<Capture>, next: Sse.Next<String>) -> IO(Sse.Cursor<String>):
  match next:
    case Sse.Next{cursor, result}:
      do IO<Sse.Cursor<String>>:
        log(capture, showNext(result))
        return cursor

def showClose(result: Result<&2, &2, Sse.Error<String>, Unit>) -> String:
  match result:
    case Fail{error}: "return:error:" ++ showError(error)
    case Done{_}: "return:ok"

def recordClose(capture: Ref.Ref<Capture>, closed: Sse.CloseResult<String>) -> IO(Sse.Cursor<String>):
  match closed:
    case Sse.CloseResult{cursor, result}:
      do IO<Sse.Cursor<String>>:
        log(capture, showClose(result))
        return cursor

def execute(actions: List<&2, Action>, +capture: Ref.Ref<Capture>, cursor: Sse.Cursor<String>) -> IO(Sse.Cursor<String>):
  match actions:
    case Nil{}: IO.pure(Sse.Cursor<String>, cursor)
    case Pull{} <> rest:
      do IO<Sse.Cursor<String>>:
        next : Sse.Next<String> <- Sse.next(String, cursor)
        cursor : Sse.Cursor<String> <- recordNext(capture, next)
        execute(rest, capture, cursor)
    case Return{} <> rest:
      do IO<Sse.Cursor<String>>:
        closed : Sse.CloseResult<String> <- Sse.close(String, cursor)
        cursor : Sse.Cursor<String> <- recordClose(capture, closed)
        execute(rest, capture, cursor)

def showCapture(capture: Capture) -> String:
  match capture:
    case Capture{_, trace}: String.join(List.reverse(&2, String, trace), "|")

def run(inputs: List<&2, Input>, actions: List<&2, Action>, +closeMode: String, +diagnosticMode: String, synthesize: Bool) -> IO(Unit):
  do IO<Unit>:
    +capture : Ref.Ref<Capture> <- Ref.new(Capture, Capture{inputs, Nil{}})
    +reader : Cb.Callback<Unit, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>, ~readCallback, Environment{capture, closeMode, diagnosticMode})
    +closer : Cb.Callback<Unit, Result<&2, &2, Sse.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, Sse.ReadError<String>, Unit>, ~closeCallback, Environment{capture, closeMode, diagnosticMode})
    +aborter : Cb.Callback<Unit, Unit> <- Cb.create(~Environment, ~Unit, ~Unit, ~abortCallback, Environment{capture, closeMode, diagnosticMode})
    +diagnostic : Cb.Callback<Sse.DispatchError, Result<&2, &2, Sse.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Sse.DispatchError, ~Result<&2, &2, Sse.ReadError<String>, Unit>, ~diagnosticCallback, Environment{capture, closeMode, diagnosticMode})
    finished : Sse.Cursor<String> <- execute(actions, capture, Sse.create(String, D.Source{reader, closer}, Sse.Hooks{aborter, diagnostic}, synthesize))
    Cb.dispose(Unit, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, D.Chunk>>, reader)
    Cb.dispose(Unit, Result<&2, &2, Sse.ReadError<String>, Unit>, closer)
    Cb.dispose(Unit, Unit, aborter)
    Cb.dispose(Sse.DispatchError, Result<&2, &2, Sse.ReadError<String>, Unit>, diagnostic)
    trace : Capture <- Ref.dispose(Capture, capture)
    IO.print(showCapture(trace))
