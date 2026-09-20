import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def payload(count: Nat, +position: U32, +reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: List.reverse(&2, U32, reversed)
    case Succ{rest}: payload(rest, (position + 1 : U32), (position % 256 : U32) <> reversed)

def equal(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> rest b <> tail: Bool.and(U32.is_eq(a, b), equal(rest, tail))
    case _ _: False{}

def require(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "datagram benchmark contract failed")

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  match pair:
    case (socket, Done{_}): IO.pure(Socket, socket)
    case (socket, Fail{_}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "send failed")

def received(expected: List<&2, U32>, port: U32, pair: Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>) -> IO(Socket):
  match pair:
    case (socket, Done{((_, _, _, _, _, peerPort, _), truncated, bytes)}):
      do IO<Socket>:
        require(Bool.and(U32.is_eq(port, peerPort), Bool.and(Bool.not(truncated), equal(expected, bytes))))
        return socket
    case (socket, Fail{_}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "receive failed")

def loop(count: Nat, +family: U32, +port: U32, +bytes: List<&2, U32>, socket: Socket) -> IO(Unit):
  match count:
    case Zero{}: Socket.close(socket)
    case Succ{rest}:
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.send_bytes(socket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), port, 0, bytes)
        socket : Socket <- sent(result)
        result : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 65535)
        socket : Socket <- received(bytes, port, result)
        loop(rest, family, port, bytes, socket)

def bound(count: Nat, family: U32, bytes: List<&2, U32>, pair: Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> IO(Unit):
  match pair:
    case (socket, Done{(_, _, _, _, _, port, _)}): loop(count, family, port, bytes, socket)
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "endpoint failed")

def run(+family: U32, count: Nat, bytes: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    endpoint : Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32> <- Socket.endpoint(socket, 0)
    bound(count, family, bytes, endpoint)
    IO.print("ok")

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> count <> size <> Nil{}: run(Scalar.decimal(family, 0), U32.to_nat(Scalar.decimal(count, 0)), payload(U32.to_nat(Scalar.decimal(size, 0)), 0, Nil{}))
    case _: IO.die(Unit, 1, "expected family count size")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
