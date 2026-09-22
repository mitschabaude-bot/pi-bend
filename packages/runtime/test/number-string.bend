import Base
import ../src/number-string.bend as N
import ../src/f64.bend as F
import ../src/u64.bend as W

def check(text: String, +expected: F64, label: String) -> IO(Unit):
  +actual = N.toNumber(text)
  same = W.equal(F.toBits(actual), F.toBits(expected)) || (F.isNaN(actual) && F.isNaN(expected))
  Bool.pick(IO(Unit), same, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))
