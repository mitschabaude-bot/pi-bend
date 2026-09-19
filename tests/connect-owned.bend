import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def assertion(value: Bool, message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def begin(ipv6: Bool, port: U32) -> IO(Connect & ConnectCancel):
  match ipv6:
    case False{}: IO.try(Connect & ConnectCancel, Connect.ipv4(2130706433, port))
    case True{}: IO.try(Connect & ConnectCancel, Connect.ipv6(0, 0, 0, 1, port, 0))

def failed(result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{(code, _)}: IO.print("cancelled:" ++ U32.show(code))
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "cancelled connect returned a socket")

def stale(handle: ConnectCancel) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- Connect.cancel(handle)
    assertion(Bool.not(won), "stale cancellation won")

def cancelBefore(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        won : Bool <- Connect.cancel(handle)
        assertion(won, "initial cancellation lost")
        stale(handle)
        result : Result<&1, &1, U32 & String, Socket> <- Connect.wait(owner)
        failed(result)
        stale(handle)

def cancelParked(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        task : Chan(Result<&1, &1, U32 & String, Socket>) <- IO.fork(Result<&1, &1, U32 & String, Socket>, Connect.wait(owner))
        IO.sleep(5)
        won : Bool <- Connect.cancel(handle)
        assertion(won, "parked cancellation lost")
        result : Result<&1, &1, U32 & String, Socket> <- IO.join(Result<&1, &1, U32 & String, Socket>, task)
        failed(result)
        stale(handle)

def retired(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        Connect.close(owner)
        stale(handle)
        IO.print("closed")

def received(pair: Socket & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match pair:
    case (socket, Done{value}):
      do IO<Unit>:
        Socket.close(socket)
        assertion(String.eq(value, "y"), "wrong received byte")
        IO.print("connected")
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "read failed")

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (socket, Done{_}):
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(socket, 1)
        received(result)
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "write failed")

def completed(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, handle):
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, Connect.wait(owner))
        stale(handle)
        result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, "x")
        sent(result)

def operation(mode: String, pair: Connect & ConnectCancel) -> IO(Unit):
  match mode:
    case "before": cancelBefore(pair)
    case "parked": cancelParked(pair)
    case "close": retired(pair)
    case _: completed(pair)

def repeat(count: Nat, +mode: String, +ipv6: Bool, +port: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        pair : Connect & ConnectCancel <- begin(ipv6, port)
        operation(mode, pair)
        repeat(rest, mode, ipv6, port)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> Nil{}: repeat(32n, mode, String.eq(family, "6"), Scalar.decimal(port, 0))
    case _: IO.die(Unit, 1, "expected mode, family and port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
