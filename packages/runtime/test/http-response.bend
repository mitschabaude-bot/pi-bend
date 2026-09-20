import Base
import ../src/http-response.bend as Response
import ../src/http-response-progress.bend as Progress
import ../src/http-response-metadata.bend as Metadata
import ../src/http-response-stream.bend as Stream
import ../src/http-head.bend as Head
import ../src/http-status.bend as Status
import ../src/http-header.bend as Header
import ./utf8-runner.bend as Text

type State is Type:
  State{events: List<&2, String>, cleanup: Bool}

def head() -> Head.ResponseHead:
  Head.ResponseHead{Status.StatusLine{1, 1, 200, 79 <> 75 <> Nil{}}, Nil{}}

def event(value: String) -> Result<&2, &2, String, Maybe<&2, Stream.Event>>:
  match value:
    case SCon{'h', _}: Done{Some{Stream.FinalHead{head(), True{}}}}
    case SCon{'z', _}: Done{Some{Stream.FinalHead{head(), False{}}}}
    case SCon{'i', _}: Done{Some{Stream.InformationalHead{head()}}}
    case SCon{'b', bytes}: Done{Some{Stream.BodyData{Text.parseNumbers(bytes)}}}
    case SCon{'c', text}: Done{Some{Stream.Completed{Header.Header{"x-end", text} <> Nil{}}}}
    case SCon{'e', text}: Fail{text}
    case _: Done{None{}}

def read(state: State) -> IO(State & Result<&2, &2, String, Maybe<&2, Stream.Event>>):
  match state:
    case State{Nil{}, cleanup}:
      do IO<State & Result<&2, &2, String, Maybe<&2, Stream.Event>>>:
        IO.print("read:eof")
        return (State{Nil{}, cleanup}, Done{None{}})
    case State{+value <> rest, cleanup}:
      do IO<State & Result<&2, &2, String, Maybe<&2, Stream.Event>>>:
        IO.print("read:" ++ value)
        return (State{rest, cleanup}, event(value))

def close(state: State) -> IO(Result<&2, &2, String, Unit>):
  match state:
    case State{_, fails}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("close")
        return Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"cleanup"}, Done{Unit{}})

def primary(value: Progress.PrimaryError<String>) -> String:
  match value:
    case Progress.TransportFailure{text}: "transport:" ++ text
    case Progress.MissingHead{}: "missing-head"
    case Progress.MissingCompletion{}: "missing-completion"
    case Progress.UnexpectedEvent{_}: "unexpected"

def error(value: Progress.Error<String>) -> String:
  match value:
    case Progress.PrimaryFailure{value}: primary(value)
    case Progress.CleanupFailure{text}: text
    case Progress.FailureWithCleanup{value, text}: primary(value) ++ "+" ++ text

def result(value: Result<&2, &2, Progress.Error<String>, Maybe<&2, List<&2, U32>>>) -> String:
  match value:
    case Fail{value}: "error:" ++ error(value)
    case Done{None{}}: "end"
    case Done{Some{bytes}}: "bytes:" ++ String.join(Text.showNumbers(bytes), ",")

def fields(value: Maybe<&2, List<&2, Header.Header>>) -> String:
  match value:
    case None{}: "none"
    case Some{Header.Header{_, text} <> Nil{}}: text
    case Some{_}: "empty"

def ended(next: Response.Next<String, State>) -> IO(Unit):
  match next:
    case Response.Next{Response.Closed{trailers}, value}: IO.print("final:" ++ result(value) ++ ":" ++ fields(trailers))
    case _: IO.die(Unit, 1, "close returned open body")

def advance(action: Char, body: Response.Body<State>) -> IO(Response.Next<String, State>):
  match action:
    case 'c': Response.closeWith(String, State, close, body)
    case _: Response.nextWith(String, State, read, close, body)

def actions(todo: String, next: Response.Next<String, State>) -> IO(Unit):
  match todo next:
    case SNil{} Response.Next{body, value}:
      do IO<Unit>:
        IO.print(result(value))
        final : Response.Next<String, State> <- Response.closeWith(String, State, close, body)
        ended(final)
    case SCon{action, rest} Response.Next{body, value}:
      do IO<Unit>:
        IO.print(result(value))
        next : Response.Next<String, State> <- advance(action, body)
        actions(rest, next)

def started(todo: String, value: Result<&2, &1, Progress.Error<String>, Response.Response<State>>) -> IO(Unit):
  match todo value:
    case _ Fail{value}: IO.print("start-error:" ++ error(value))
    case SNil{} Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("head")
        final : Response.Next<String, State> <- Response.closeWith(String, State, close, body)
        ended(final)
    case SCon{action, rest} Done{Response.Response{+metadata, body}}:
      do IO<Unit>:
        IO.print("head:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Bool.pick(String, Metadata.bodyPresent(metadata), "body", "null"))
        next : Response.Next<String, State> <- advance(action, body)
        actions(rest, next)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case fails <> todo <> values:
      do IO<Unit>:
        value : Result<&2, &1, Progress.Error<String>, Response.Response<State>> <- Response.startWith(String, State, read, close, State{values, String.eq(fails, "1")})
        started(todo, value)
    case _: IO.die(Unit, 1, "bad response fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print("case")
        run(String.split(first, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
