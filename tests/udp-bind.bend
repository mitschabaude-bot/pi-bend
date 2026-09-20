import Base
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as Test

def result(value: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match value:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{socket}:
      do IO<Unit>:
        local : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
        socket : Socket <- Test.observed(local)
        Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> port <> Nil{}:
      do IO<Unit>:
        value : Result<&1, &1, U32 & String, Socket> <- UDP.bind_family(Scalar.decimal(family, 0), Scalar.decimal(port, 0))
        result(value)
    case _: IO.die(Unit, 1, "expected family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
