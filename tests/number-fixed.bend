import Base
import ../packages/runtime/src/f64.bend as Number
import ../packages/runtime/src/number-string.bend as Numbers
import ../packages/runtime/src/string.bend as Strings

def render(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def run(parts: List<&2,String>) -> String:
  match parts:
    case high <> low <> digits <> Nil{}: render(Numbers.formatFixed(Number.fromBits(Maybe.default(&2,U32,U32.read(high),0),Maybe.default(&2,U32,U32.read(low),0)),Maybe.default(&2,Nat,Nat.read(digits),0n)))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(value,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
