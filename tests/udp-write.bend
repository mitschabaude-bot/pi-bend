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

def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "write cancellation contract failed")

def before(mode: String, +handle: UDPWriteCancel) -> IO(Unit):
  match mode:
    case "cancel":
      do IO<Unit>:
        won : Bool <- UDPWrite.cancel(handle)
        require(won)
        again : Bool <- UDPWrite.cancel(handle)
        require(Bool.not(again))
    case _: IO.pure(Unit, Unit{})

def delayed(handle: UDPWriteCancel) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(20)
    UDPWrite.cancel(handle)

def wait(mode: String, write: UDPWrite, handle: UDPWriteCancel) -> IO(Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>):
  match mode:
    case "park":
      do IO<Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>>:
        task : Chan(Bool) <- IO.fork(Bool, delayed(handle))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>> <- UDPWrite.wait(write)
        won : Bool <- IO.join(Bool, task)
        require(won)
        return result
    case "release":
      do IO<Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>>:
        socket : Socket <- UDPWrite.release(write)
        return (socket, None{})
    case _: UDPWrite.wait(write)

def reported(pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>) -> IO(Socket):
  match pair:
    case (socket, None{}):
      do IO<Socket>:
        IO.print("cancelled")
        return socket
    case (socket, Some{value}): sent((socket, value))

def marker(old: UDPWriteCancel, pair: UDPWrite & UDPWriteCancel) -> IO(Unit):
  match pair:
    case (write, +handle):
      do IO<Unit>:
        stale : Bool <- UDPWrite.cancel(old)
        require(Bool.not(stale))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>> <- UDPWrite.wait(write)
        socket : Socket <- reported(result)
        stale : Bool <- UDPWrite.cancel(handle)
        require(Bool.not(stale))
        Socket.close(socket)

def operation(+family: U32, port: U32, +mode: String, pair: UDPWrite & UDPWriteCancel) -> IO(Unit):
  match pair:
    case (write, +handle):
      do IO<Unit>:
        before(mode, handle)
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>> <- wait(mode, write, handle)
        socket : Socket <- reported(result)
        next : UDPWrite & UDPWriteCancel <- UDPWrite.new(socket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), port, 0, 17 <> 0 <> 255 <> Nil{})
        marker(handle, next)

def opened(+family: U32, +port: U32, mode: String, bytes: List<&2, U32>, result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "bind failed")
    case Done{socket}:
      do IO<Unit>:
        pair : UDPWrite & UDPWriteCancel <- UDPWrite.new(socket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), port, 0, bytes)
        operation(family, port, mode, pair)

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
