import Base
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as EndpointTest

def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "read race contract failed")

def delayed(handle: UDPReadCancel) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(20)
    UDPRead.cancel(handle)

def packet(expected: U32, pair: Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>) -> IO(Socket):
  match pair:
    case (socket, Done{(_, False{}, byte <> Nil{})}):
      do IO<Socket>:
        require(U32.is_eq(byte, expected))
        return socket
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "packet missing or changed")

def finished(won: Bool, expected: U32, pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> IO(Socket):
  match pair:
    case (socket, None{}):
      do IO<Socket>:
        require(won)
        next : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 10)
        socket : Socket <- packet(expected, next)
        IO.print("cancelled")
        return socket
    case (socket, Some{value}):
      do IO<Socket>:
        require(Bool.not(won))
        socket : Socket <- packet(expected, (socket, value))
        IO.print("packet")
        return socket

def race(expected: U32, pair: UDPRead & UDPReadCancel) -> IO(Socket):
  match pair:
    case (read, +handle):
      do IO<Socket>:
        task : Chan(Bool) <- IO.fork(Bool, delayed(handle))
        IO.print("armed")
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        won : Bool <- IO.join(Bool, task)
        socket : Socket <- finished(won, expected, result)
        stale : Bool <- UDPRead.cancel(handle)
        require(Bool.not(stale))
        return socket

def loop(count: Nat, +position: U32, socket: Socket) -> IO(Unit):
  match count:
    case Zero{}:
      do IO<Unit>:
        Socket.close(socket)
        IO.print("done")
    case Succ{rest}:
      do IO<Unit>:
        read : UDPRead & UDPReadCancel <- UDPRead.new(socket, 10)
        socket : Socket <- race(position, read)
        loop(rest, (position + 1 : U32), socket)

def run(family: U32, count: Nat) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    local : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- EndpointTest.observed(local)
    loop(count, 0, socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> count <> Nil{}: run(Scalar.decimal(family, 0), U32.to_nat(Scalar.decimal(count, 0)))
    case _: IO.die(Unit, 1, "expected family count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
