import Base
import ./http-response.bend as Input
import ../src/http-response.bend as Response
import ../src/http-response.bend as Progress
import ../src/http-response.bend as Metadata
import ../src/http-response.bend as Stream
import ../src/http-response.bend as Ops
import ../src/callback.bend as C
import ../src/ref.bend as R

# Both operations capture a distinct live counter, so this cannot collapse
# into the captureless functions that masked the old affine-closure defect.
def counted(+count: U32) -> U32 & Unit: ((count + 1 : U32), Unit{})

def readCaptured(counter: R.Ref<U32>, state: Input.State) -> IO(Input.State & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>):
  do IO<Input.State & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>>:
    unused : Unit <- R.modify(U32, Unit, counter, value => counted(value))
    Input.read(state)

def closeCaptured(counter: R.Ref<U32>, state: Input.State) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    unused : Unit <- R.modify(U32, Unit, counter, value => counted(value))
    Input.close(state)

def advance(reader: Ops.Read(String, Input.State), closer: Ops.Close(String, Input.State), action: Char, body: Response.Body<Input.State>) -> IO(Response.Next<String, Input.State>):
  match action:
    case 'c': Response.closeWith(String, Input.State, state => Ops.closeTransportCallbacks(String, Input.State, closer, state), body)
    case _: Response.nextResponse(String, Input.State, reader, closer, body)

def actions(+reader: Ops.Read(String, Input.State), +closer: Ops.Close(String, Input.State), todo: String, next: Response.Next<String, Input.State>) -> IO(Unit):
  match todo next:
    case SNil{} Response.Next{body, value}:
      do IO<Unit>:
        IO.print(Input.result(value))
        final : Response.Next<String, Input.State> <- Response.closeWith(String, Input.State, state => Ops.closeTransportCallbacks(String, Input.State, closer, state), body)
        Input.ended(final)
    case SCon{action, rest} Response.Next{body, value}:
      do IO<Unit>:
        IO.print(Input.result(value))
        next : Response.Next<String, Input.State> <- advance(reader, closer, action, body)
        actions(reader, closer, rest, next)

def started(+reader: Ops.Read(String, Input.State), +closer: Ops.Close(String, Input.State), todo: String, value: Result<&2, &1, Progress.ResponseProgressError<String>, Response.Response<Input.State>>) -> IO(Unit):
  match todo value:
    case _ Fail{value}: IO.print("start-error:" ++ Input.error(value))
    case SNil{} Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("head")
        final : Response.Next<String, Input.State> <- Response.closeWith(String, Input.State, state => Ops.closeTransportCallbacks(String, Input.State, closer, state), body)
        Input.ended(final)
    case SCon{action, rest} Done{Response.Response{+metadata, body}}:
      do IO<Unit>:
        IO.print("head:" ++ U32.show(Metadata.metadataStatus(metadata)) ++ ":" ++ Bool.pick(String, Metadata.bodyPresent(metadata), "body", "null"))
        next : Response.Next<String, Input.State> <- advance(reader, closer, action, body)
        actions(reader, closer, rest, next)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case fails <> todo <> values:
      do IO<Unit>:
        +reads : R.Ref<U32> <- R.new(U32, 0)
        +closes : R.Ref<U32> <- R.new(U32, 0)
        +reader : Ops.Read(String, Input.State) <- C.create(~(R.Ref<U32>), ~Input.State, ~(Input.State & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>), ~readCaptured, reads)
        +closer : Ops.Close(String, Input.State) <- C.create(~(R.Ref<U32>), ~Input.State, ~Result<&2, &2, String, Unit>, ~closeCaptured, closes)
        value : Result<&2, &1, Progress.ResponseProgressError<String>, Response.Response<Input.State>> <- Response.start(String, Input.State, reader, closer, Input.State{values, String.eq(fails, "1")})
        started(reader, closer, todo, value)
        C.dispose(Input.State, Input.State & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>, reader)
        C.dispose(Input.State, Result<&2, &2, String, Unit>, closer)
        readCount : U32 <- R.dispose(U32, reads)
        closeCount : U32 <- R.dispose(U32, closes)
        IO.print("callbacks:" ++ U32.show(readCount) ++ ":" ++ U32.show(closeCount))
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
