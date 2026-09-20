import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def payload(size: Nat, +position: U32, bad: Bool, +reversed: List<&2, U32>) -> List<&2, U32>:
  match size:
    case Zero{}: List.reverse(&2, U32, Bool.pick(List<&2, U32>, bad, 256 <> reversed, reversed))
    case Succ{rest}: payload(rest, (position + 1 : U32), bad, (position % 256 : U32) <> reversed)

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  match pair:
    case (socket, Done{_}):
      do IO<Socket>:
        IO.print("ok")
        return socket
    case (socket, Fail{(code, _)}):
      do IO<Socket>:
        IO.print("error:" ++ U32.show(code))
        return socket

def send(socket: Socket, +family: U32, port: U32, +mode: String, bytes: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, Unit>):
  UDP.send_bytes(socket, Bool.pick(U32, String.eq(mode, "family"), 7, family), Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), Bool.pick(U32, String.eq(mode, "word"), 1, 0), 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), Bool.pick(U32, String.eq(mode, "zero-port"), 0, Bool.pick(U32, String.eq(mode, "large-port"), 65536, port)), Bool.pick(U32, String.eq(mode, "scope"), 1, 0), bytes)

def opened(+family: U32, +port: U32, mode: String, bytes: List<&2, U32>, result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "bind failed")
    case Done{socket}:
      do IO<Unit>:
        first : Socket & Result<&1, &1, U32 & String, Unit> <- send(socket, family, port, mode, bytes)
        socket : Socket <- sent(first)
        next : Socket & Result<&1, &1, U32 & String, Unit> <- send(socket, family, port, "ok", 17 <> 0 <> 255 <> Nil{})
        socket : Socket <- sent(next)
        Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> port <> size <> +mode <> Nil{}:
      +number = Scalar.decimal(family, 0)
      do IO<Unit>:
        socket : Result<&1, &1, U32 & String, Socket> <- UDP.bind_family(number, 0)
        opened(number, Scalar.decimal(port, 0), mode, payload(U32.to_nat(Scalar.decimal(size, 0)), 0, String.eq(mode, "byte"), Nil{}), socket)
    case _: IO.die(Unit, 1, "expected family port size mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
