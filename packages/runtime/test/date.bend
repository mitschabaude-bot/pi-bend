import Base
import ../src/date.bend as Date
import ../src/f64.bend as F
import ../src/f64.bend as Decimal

def requireText(value: Maybe<&2, String>) -> IO(Unit):
  match value:
    case Some{text}: IO.print(text)
    case None{}: IO.die(Unit, 1, "wall-clock integer formatting failed")

def main() -> IO(Unit):
  do IO<Unit>:
    value : F.F64 <- Date.now()
    requireText(Decimal.toDecimal(value))
