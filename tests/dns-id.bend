import Base
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar

def bytes(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: bytes(rest, reversed)
    case part <> rest: bytes(rest, Scalar.decimal(part, 0) <> reversed)

def shown(value: Result<&2, &2, Id.IdError, U32>) -> String:
  match value:
    case Done{id}: U32.show(id)
    case Fail{Id.SourceFailure{code, message}}: "source:" ++ U32.show(code) ++ ":" ++ message
    case Fail{Id.InvalidBytes{}}: "invalid"

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(shown(Id.decoded(Done{bytes(Split.split(arg, ','), Nil{})})))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(shown(Id.decoded(Fail{Tuple{11, "not ready"}})))
    args : List<String> <- IO.args()
    run(args)
