import Base
import ../packages/runtime/src/dns-transport.bend as Rotation
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/runtime/src/string.bend as Split

def csv(values: List<&2, U32>, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case value <> rest: csv(rest, String.reverse(U32.show(value) ++ ",") ++ reversed)

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case text <> rest: numbers(rest, Scalar.decimal(text, 0) <> reversed)

def order(choice: Rotation.Chosen<U32>) -> String:
  match choice:
    case Rotation.Chosen{servers, _}: csv(servers, "")

def stateOf(choice: Rotation.Chosen<U32>) -> Rotation.ServerRotationState<U32>:
  match choice:
    case Rotation.Chosen{_, value}: value

# Print each selected order, then advance from the returned immutable state.
def run(flags: String, state: Rotation.ServerRotationState<U32>) -> IO(Unit):
  match flags:
    case SNil{}: IO.pure(Unit, Unit{})
    case SCon{flag, rest}:
      +choice = Rotation.choose(U32, Char.is_eq(flag, '1'), state)
      do IO<Unit>:
        IO.print(order(choice))
        run(rest, stateOf(choice))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case servers <> flags <> rest:
      do IO<Unit>:
        run(flags, Rotation.start(U32, numbers(Split.split(servers, ','), Nil{})))
        args(rest)
    case _: IO.die(Unit, 1, "expected comma-separated servers and rotation flags")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
