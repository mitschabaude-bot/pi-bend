import Base
import ../src/f64.bend as F
import ../src/f64-natural.bend as D
import ./utf8-runner.bend as H
import ../src/u64.bend as W

def rejected(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: "invalid:" ++ U32.show(high) ++ ":" ++ U32.show(low)

def show(value: Result<&2, &2, D.Error, Nat>) -> String:
  match value:
    case Done{word}: Nat.show(word)
    case Fail{D.Unrepresentable{value}}: rejected(F.toBits(value))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case hi <> lo <> Nil{}: IO.print(show(D.convert(F.fromBits(H.decimal(hi, 0), H.decimal(lo, 0)))))
    case _: IO.die(Unit, 1, "expected binary64 words")

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        run(String.split(value, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
