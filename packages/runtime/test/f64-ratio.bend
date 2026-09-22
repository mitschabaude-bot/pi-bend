import Base
import ../src/f64.bend as Ratio
import ../src/f64.bend as F
import ../src/u64.bend as W
import ../src/big-nat.bend as B

def matches(actual: Maybe<&2, F64>, expected: Maybe<&2, F64>) -> Bool:
  match actual expected:
    case None{} None{}: True{}
    case Some{a} Some{b}: W.equal(F.toBits(a), F.toBits(b))
    case _ _: False{}

def check(negative: Bool, numerator: B.BigNat, denominator: B.BigNat, expected: Maybe<&2, F64>, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), matches(Ratio.fromRatio(negative, numerator, denominator), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))
