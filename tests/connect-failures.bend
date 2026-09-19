import Base
import ./connect-owned.bend as Test
import ../packages/runtime/test/utf8-runner.bend as Scalar

def failed(result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "unexpected connection success")

def started(result: Result<&1, &1, U32 & String, Connect & ConnectCancel>) -> IO(Unit):
  match result:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{(owner, handle)}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Socket> <- Connect.wait(owner)
        failed(result)
        Test.stale(handle)

def attempt(ipv6: Bool, port: U32) -> IO(Unit):
  match ipv6:
    case False{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Connect & ConnectCancel> <- Connect.ipv4(2130706433, port)
        started(result)
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Connect & ConnectCancel> <- Connect.ipv6(0, 0, 0, 1, port, 0)
        started(result)

def repeat(count: Nat, +ipv6: Bool, +port: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        attempt(ipv6, port)
        repeat(rest, ipv6, port)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case family <> port <> Nil{}: repeat(32n, String.eq(family, "6"), Scalar.decimal(port, 0))
    case _: IO.die(Unit, 1, "expected family and port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
