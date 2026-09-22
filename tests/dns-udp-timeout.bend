import Base
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/test/utf8-runner.bend as Scalar

def position(code: String) -> Timeout.Position:
  match code:
    case "0": Timeout.First{}
    case "1": Timeout.SecondOfTwo{}
    case "2": Timeout.SecondOfThree{}
    case _: Timeout.ThirdOfThree{}

def converted(seconds: Nat, result: Result<&2, &2, Timeout.MillisecondsError, U32>) -> String:
  match result:
    case Fail{_}: "conversion-failed"
    case Done{milliseconds}: U32.show(U32.from_nat(seconds)) ++ ":" ++ U32.show(milliseconds)

def show(result: Result<&2, &2, Timeout.UdpTimeoutError, Timeout.Duration>) -> String:
  match result:
    case Fail{Timeout.UdpTimeoutInvalidTimeout{value}}: "invalid:" ++ U32.show(value)
    case Done{+duration}: converted(Timeout.seconds(duration), Timeout.milliseconds(duration))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case timeout <> code <> rest:
      do IO<Unit>:
        IO.print(show(Timeout.budget(Scalar.decimal(timeout, 0), position(code))))
        run(rest)
    case _: IO.die(Unit, 1, "expected timeout/position pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
