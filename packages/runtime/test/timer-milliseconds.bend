import Base
import ../src/f64.bend as F
import ../src/timer-milliseconds.bend as D
import ./utf8-runner.bend as H

def show(value: Result<&2, &2, D.Error, U32>) -> String:
  match value:
    case Done{word}: U32.show(word)
    case Fail{_}: "invalid"

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case hi <> lo <> Nil{}: IO.print(show(D.milliseconds(F.fromBits(H.decimal(hi, 0), H.decimal(lo, 0)))))
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
