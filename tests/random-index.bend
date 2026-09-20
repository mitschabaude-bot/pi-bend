import Base
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/test/utf8-runner.bend as Scalar

def printed(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "reject"
    case Some{n}: Nat.show(n)

def result(value: Result<&2, &2, Index.Error, Index.Range>, word: U32) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{range}: printed(Index.select(range, word))

def bound(+text: String) -> Nat:
  Bool.pick(Nat, String.eq(text, "full"), Index.width(), Bool.pick(Nat, String.eq(text, "large"), 1n+Index.width(), U32.to_nat(Scalar.decimal(text, 0))))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case boundText <> word <> rest:
      do IO<Unit>:
        IO.print(result(Index.prepare(bound(boundText)), Scalar.decimal(word, 0)))
        args(rest)
    case _: IO.die(Unit, 1, "expected bound and word")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
