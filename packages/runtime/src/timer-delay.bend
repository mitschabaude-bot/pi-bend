import Base
import ./f64.bend as F
import ./u64.bend as W

# Provider setTimeout semantics: values outside [1, 2^31-1], including NaN,
# become one millisecond; valid fractions truncate toward zero. This adapter
# keeps that public scheduling contract separate from Timer.new's U32 deadline.
def low(value: W.U64) -> U32:
  match value:
    case W.U64{_, word}: word

def finite(value: F.Decoded) -> U32:
  match value:
    case F.Finite{_, exponent, significand}: low(W.shiftRight(significand, U32.to_nat((1075 - exponent : U32))))
    case _: 1

def inRange(lower: Maybe<&2, Cmp>, upper: Maybe<&2, Cmp>) -> Bool:
  match lower upper:
    case Some{EQ{}} Some{LT{}}: True{}
    case Some{GT{}} Some{LT{}}: True{}
    case Some{GT{}} Some{EQ{}}: True{}
    case _ _: False{}

def checked(valid: Bool, value: F.F64) -> U32:
  match valid:
    case True{}: finite(F.decode(value))
    case False{}: 1

def milliseconds(+value: F.F64) -> U32:
  checked(inRange(F.compare(value, F.fromU32(1)), F.compare(value, F.fromU32(2147483647))), value)
