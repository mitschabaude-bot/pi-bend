import Base
import ../src/http-body-source.bend as Source
import ../src/http-response.bend as Response
import ../src/sse-reader.bend as SSE
import ../src/sse-decoder.bend as Event
import ../src/callback.bend as Cb
import ../src/http-response-stream.bend as Stream
import ./http-response.bend as Input
import ./utf8-runner.bend as Text

def slowRead(state: Input.State) -> IO(Input.State & Result<&2, &2, String, Maybe<&2, Stream.Event>>):
  do IO<Input.State & Result<&2, &2, String, Maybe<&2, Stream.Event>>>:
    IO.sleep(1)
    Input.read(state)

def raw(value: Result<&2, &2, String, Maybe<&2, SSE.Chunk>>) -> String:
  match value:
    case Done{Some{SSE.Bytes{bytes}}}: "parallel:" ++ String.join(Text.showNumbers(bytes), ",")
    case _: "parallel:unexpected"

def result(value: Result<&2, &2, String, Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{error}: "error:" ++ error

def parallel(owner: Source.Owner<Input.State, String>, source: SSE.Source<String>) -> IO(Unit):
  match source:
    case SSE.Source{+next, _}:
      do IO<Unit>:
        first : Chan(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>) <- IO.fork(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, Cb.call(Unit, Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, next, Unit{}))
        second : Chan(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>) <- IO.fork(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, Cb.call(Unit, Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, next, Unit{}))
        a : Result<&2, &2, String, Maybe<&2, SSE.Chunk>> <- IO.join(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, first)
        b : Result<&2, &2, String, Maybe<&2, SSE.Chunk>> <- IO.join(Result<&2, &2, String, Maybe<&2, SSE.Chunk>>, second)
        IO.print(raw(a))
        IO.print(raw(b))
        disposed : Result<&2, &2, String, Unit> <- Source.dispose(Input.State, String, owner)
        IO.print("dispose:" ++ result(disposed))

def event(value: Result<&2, &2, String, Maybe<&2, Event.ServerSentEvent>>) -> String:
  match value:
    case Done{None{}}: "end"
    case Fail{error}: "error:" ++ error
    case Done{Some{Event.ServerSentEvent{_, data, _}}}: "data:" ++ Text.showText(data)

def finished(owner: Source.Owner<Input.State, String>, value: SSE.CloseResult<String>) -> IO(Unit):
  match value:
    case SSE.CloseResult{_, value}:
      do IO<Unit>:
        IO.print("reader-close:" ++ result(value))
        disposed : Result<&2, &2, String, Unit> <- Source.dispose(Input.State, String, owner)
        IO.print("dispose:" ++ result(disposed))

def advanced(value: SSE.CloseResult<String>) -> SSE.Next<String>:
  match value:
    case SSE.CloseResult{cursor, Done{_}}: SSE.Next{cursor, Done{None{}}}
    case SSE.CloseResult{cursor, Fail{error}}: SSE.Next{cursor, Fail{error}}

def advance(action: Char, cursor: SSE.Cursor<String>) -> IO(SSE.Next<String>):
  match action:
    case 'c':
      do IO<SSE.Next<String>>:
        value : SSE.CloseResult<String> <- SSE.close(String, cursor)
        return advanced(value)
    case _: SSE.next(String, cursor)

def actions(todo: String, owner: Source.Owner<Input.State, String>, value: SSE.Next<String>) -> IO(Unit):
  match todo value:
    case SNil{} SSE.Next{cursor, value}:
      do IO<Unit>:
        IO.print(event(value))
        closed : SSE.CloseResult<String> <- SSE.close(String, cursor)
        finished(owner, closed)
    case SCon{action, rest} SSE.Next{cursor, value}:
      do IO<Unit>:
        IO.print(event(value))
        next : SSE.Next<String> <- advance(action, cursor)
        actions(rest, owner, next)

def acquired(todo: String, pair: Source.Owner<Input.State, String> & SSE.Source<String>) -> IO(Unit):
  match todo pair:
    case SCon{'p', _} Tuple{owner, source}: parallel(owner, source)
    case SNil{} Tuple{owner, source}:
      do IO<Unit>:
        closed : SSE.CloseResult<String> <- SSE.close(String, SSE.create(String, source))
        finished(owner, closed)
    case SCon{action, rest} Tuple{owner, source}:
      do IO<Unit>:
        next : SSE.Next<String> <- advance(action, SSE.create(String, source))
        actions(rest, owner, next)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case fails <> todo <> values:
      do IO<Unit>:
        owner : Source.Owner<Input.State, String> <- Source.create(~String, ~Input.State, ~String, ~Input.error, ~slowRead, ~Input.close, Response.Open{Input.State{values, String.eq(fails, "1")}, True{}})
        acquired(todo, Source.borrow(Input.State, String, owner))
    case _: IO.die(Unit, 1, "expected cleanup/actions/events")

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
