import Base
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as EndpointTest

def reversedCsv(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case byte <> rest: reversedCsv(rest, "," ++ String.reverse(U32.show(byte)) ++ reversed)

def csv(bytes: List<&2, U32>) -> String:
  reversedCsv(bytes, "")

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def received(pair: Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>) -> IO(Socket):
  match pair:
    case (socket, Fail{(code, _)}):
      do IO<Socket>:
        IO.print("error:" ++ U32.show(code))
        return socket
    case (socket, Done{((family, a, b, c, d, port, scope), truncated, bytes)}):
      do IO<Socket>:
        IO.print(U32.show(family) ++ ":" ++ U32.show(a) ++ ":" ++ U32.show(b) ++ ":" ++ U32.show(c) ++ ":" ++ U32.show(d) ++ ":" ++ U32.show(port) ++ ":" ++ U32.show(scope) ++ ":" ++ bit(truncated) ++ ":" ++ csv(bytes))
        return socket

def loop(limits: List<String>, socket: Socket) -> IO(Unit):
  match limits:
    case Nil{}: Socket.close(socket)
    case value <> rest:
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, Scalar.decimal(value, 0))
        socket : Socket <- received(result)
        loop(rest, socket)

def opened(limits: List<String>, result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "bind failed")
    case Done{socket}:
      do IO<Unit>:
        local : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
        socket : Socket <- EndpointTest.observed(local)
        loop(limits, socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> limits:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Socket> <- UDP.bind_family(Scalar.decimal(family, 0), 0)
        opened(limits, result)
    case _: IO.die(Unit, 1, "expected family and limits")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
