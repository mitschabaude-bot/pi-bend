import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def result(value: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match value:
    case Fail{(code, _)}: IO.print(U32.show(code))
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "address probe unexpectedly connected")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case a <> b <> c <> d <> port <> scope <> Nil{}:
      do IO<Unit>:
        value : Result<&1, &1, U32 & String, Socket> <- TCP.connect_ipv6(Scalar.decimal(a, 0), Scalar.decimal(b, 0), Scalar.decimal(c, 0), Scalar.decimal(d, 0), Scalar.decimal(port, 0), Scalar.decimal(scope, 0))
        result(value)
    case _: IO.die(Unit, 1, "expected four address words, port and scope")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
