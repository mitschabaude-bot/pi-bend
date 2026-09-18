import Base
import ./f64.bend as F
import ./u64.bend as W
import ./big-nat.bend as B

# Exact rational-to-binary64 rounding, shared by numeric text parsers. Neither
# numerator nor denominator is first rounded to a floating-point value.
type Bounds is Data:
  Bounds{lower: W.U64, upper: W.U64}

def integerWord(word: W.U64) -> B.BigNat:
  match word:
    case W.U64{high, low}: B.add(B.shiftLeft(B.fromU32(high), 32n), B.fromU32(low))

# Positive finite values expressed in units of the least positive subnormal.
# The upper endpoint is a virtual 2^1024 value, whose encoding is infinity.
# Its midpoint with the largest finite number is the overflow threshold.
def decodedUnits(value: F.Decoded) -> B.BigNat:
  match value:
    case F.Finite{_, exponent, significand}: B.shiftLeft(integerWord(significand), U32.to_nat((exponent - 1 : U32)))
    case F.Infinity{_}: B.shiftLeft(B.one(), 2098n)
    case F.NotANumber{}: B.zero()

def units(bits: W.U64) -> B.BigNat: decodedUnits(F.decode(F.F64{bits}))

def narrow(order: Cmp, lower: W.U64, +middle: W.U64, upper: W.U64) -> Bounds:
  match order:
    case LT{}: Bounds{lower, middle}
    case _: Bounds{middle, upper}

# Monotone positive encodings span fewer than 2^63 steps. Sixty-three exact
# bisections therefore leave adjacent endpoints, including for zero/overflow.
def bracket(steps: Nat, +target: B.BigNat, +denominator: B.BigNat, bounds: Bounds) -> Bounds:
  match steps bounds:
    case 0n bounds: bounds
    case 1n+n Bounds{+lower, +upper}:
      +middle = W.shiftRightOne(W.add(lower, upper))
      order = B.compare(target, B.multiply(units(middle), denominator))
      bracket(n, target, denominator, narrow(order, lower, middle, upper))

def roundChoice(order: Cmp, +lower: W.U64, upper: W.U64) -> W.U64:
  match order:
    case LT{}: lower
    case GT{}: upper
    case EQ{}: Bool.pick(W.U64, W.equal(W.bitAnd(lower, W.one()), W.zero()), lower, upper)

def rounded(target: B.BigNat, denominator: B.BigNat, bounds: Bounds) -> F.F64:
  match bounds:
    case Bounds{+lower, +upper}:
      midpointTwice = B.multiply(B.add(units(lower), units(upper)), denominator)
      F.F64{roundChoice(B.compare(B.shiftLeft(target, 1n), midpointTwice), lower, upper)}

def signed(negative: Bool, value: F.F64) -> F.F64:
  match negative:
    case False{}: value
    case True{}: F.negate(value)

def fromRatio(negative: Bool, numerator: B.BigNat, denominator: B.BigNat) -> Maybe<&2, F.F64>:
  match denominator:
    case B.BigNat{Nil{}}: None{}
    case B.BigNat{head <> tail}:
      +divisor = {B.BigNat{head <> tail} : B.BigNat}
      +target = B.shiftLeft(numerator, 1074n)
      bounds = bracket(63n, target, divisor, Bounds{W.zero(), W.U64{2146435072, 0}})
      Some{signed(negative, rounded(target, divisor, bounds))}
