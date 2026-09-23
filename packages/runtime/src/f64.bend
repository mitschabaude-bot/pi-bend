import Base
import ./u64.bend as W
import ./big-nat.bend as B

# IEEE 754 binary64 over Bend's native F64 (the bits, high word first):
# arithmetic, comparison and decimal spelling are primitives. Decoding,
# integrality, natural-number conversion and exact ratio rounding are pure
# word operations. The software implementation these primitives are checked
# against is packages/runtime/test/f64-software.bend.

type Decoded is Data:
  Finite{negative: Bool, exponent: U32, significand: W.U64}
  Infinity{negative: Bool}
  NotANumber{}

def fromBits(high: U32, low: U32) -> F64: F64{high, low}
def toBits(value: F64) -> W.U64:
  match value:
    case F64{high, low}: W.U64{high, low}
def ofWord(word: W.U64) -> F64:
  match word:
    case W.U64{high, low}: F64{high, low}

def nan() -> F64: F64{2146959360, 0}
def infinity(negative: Bool) -> F64:
  F64{Bool.pick(U32, negative, 4293918720, 2146435072), 0}

def decodeFields(special: Bool, negative: Bool, +exponent: U32, +fraction: W.U64) -> Decoded:
  match special:
    case True{}: Bool.pick(Decoded, W.equal(fraction, W.zero()), Infinity{negative}, NotANumber{})
    case False{}:
      hidden = Bool.pick(W.U64, U32.is_eq(exponent, 0), W.zero(), W.U64{1048576, 0})
      Finite{negative, U32.max(exponent, 1), W.bitOr(fraction, hidden)}

def decode(value: F64) -> Decoded:
  match value:
    case F64{+high, low}:
      +exponent = U32.and(U32.shrn(high, 20n), 2047)
      decodeFields(U32.is_eq(exponent, 2047), U32.is_ge(high, 2147483648), exponent, W.U64{U32.and(high, 1048575), low})

def isNaN(value: F64) -> Bool:
  match value:
    case F64{+high, +low}:
      U32.is_eq(U32.and(high, 2146435072), 2146435072) && Bool.not(U32.is_eq(U32.and(high, 1048575), 0) && U32.is_eq(low, 0))

def negate(value: F64) -> F64: F64.neg(value)
def add(a: F64, b: F64) -> F64: F64.add(a, b)
def subtract(a: F64, b: F64) -> F64: F64.sub(a, b)
def multiply(a: F64, b: F64) -> F64: F64.mul(a, b)
def divide(a: F64, b: F64) -> F64: F64.div(a, b)

# An unordered operand (NaN) compares as None; ordered values compare by
# value, so -0 equals 0.
def ordering(less: Bool, equal: Bool) -> Cmp:
  match less equal:
    case True{} _: LT{}
    case _ True{}: EQ{}
    case _ _: GT{}

def compareOrdered(unordered: Bool, +a: F64, +b: F64) -> Maybe<&2, Cmp>:
  match unordered:
    case True{}: None{}
    case False{}: Some{ordering(F64.is_lt(a, b), F64.is_eq(a, b))}

def compare(+a: F64, +b: F64) -> Maybe<&2, Cmp>:
  compareOrdered(isNaN(a) || isNaN(b), a, b)

# Outcomes of an ordered comparison; None (an unordered operand) is never
# equal, greater, at least or at most.
def isEqual(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def isGreater(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case _: False{}

def isAtLeast(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case Some{GT{}}: True{}
    case _: False{}

def isAtMost(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{LT{}}: True{}
    case Some{EQ{}}: True{}
    case _: False{}

def isFinite(value: Decoded) -> Bool:
  match value:
    case Finite{_, _, _}: True{}
    case _: False{}

# Unordered numeric inputs propagate NaN. Equal values need no identity or
# signed-zero distinction for a token count.
def minimumOrdered(order: Maybe<&2, Cmp>, left: F64, right: F64) -> F64:
  match order:
    case None{}: nan()
    case Some{GT{}}: right
    case _: left

def minimum(+left: F64, +right: F64) -> F64:
  minimumOrdered(compare(left, right), left, right)

def maximumOrdered(order: Maybe<&2, Cmp>, left: F64, right: F64) -> F64:
  match order:
    case None{}: nan()
    case Some{LT{}}: right
    case _: left

def maximum(+left: F64, +right: F64) -> F64:
  maximumOrdered(compare(left, right), left, right)

# A 64-bit natural rounds once: the high word scaled by 2^32 is exact.
def fromU64(value: W.U64) -> F64:
  match value:
    case W.U64{high, low}: F64.add(F64.mul(U32.to_f64(high), F64{1106247680, 0}), U32.to_f64(low))

def fromU32(value: U32) -> F64: U32.to_f64(value)

# Nat's checked 48-bit range is exactly representable in binary64.
def fromNat(+value: Nat) -> F64:
  fromU64(W.U64{U32.from_nat(value / (65536n * 65536n)),U32.from_nat(value % (65536n * 65536n))})

def integralFinite(+exponent: U32, +significand: W.U64) -> Bool:
  +shift = U32.to_nat(U32.min((1075 - U32.min(exponent, 1075) : U32), 64))
  W.equal(significand, W.shiftLeft(W.shiftRight(significand, shift), shift))

def integerDecoded(value: Decoded) -> Bool:
  match value:
    case Finite{_, exponent, significand}: integralFinite(exponent, significand)
    case _: False{}

def isInteger(value: F64) -> Bool: integerDecoded(decode(value))

# Truncation and ceiling keep negative zero and non-finite values; the
# remainder is fmod: the sign of the dividend, NaN for a zero divisor.
def truncate(value: F64) -> F64: F64.trunc(value)
def ceil(value: F64) -> F64: F64.ceil(value)
def remainder(left: F64, right: F64) -> F64: F64.mod(left, right)

# ECMAScript number spelling: the shortest digits that read back exactly,
# NaN and the infinities by name, every zero as 0.
def decoded(value: Decoded, shown: String) -> String:
  match value:
    case NotANumber{}: "NaN"
    case Infinity{negative}: Bool.pick(String, negative, "-Infinity", "Infinity")
    case Finite{_, _, +significand}: Bool.pick(String, W.equal(significand, W.zero()), "0", shown)

def toDecimal(+value: F64) -> Maybe<&2, String>: Some{decoded(decode(value), F64.show(value))}

# JSON serializes non-finite numbers as null.
def jsonDecoded(value: Decoded, shown: String) -> String:
  match value:
    case NotANumber{}: "null"
    case Infinity{_}: "null"
    case value: decoded(value, shown)

def toJsonNumber(+value: F64) -> Maybe<&2, String>: Some{jsonDecoded(decode(value), F64.show(value))}

type Error is Data:
  Unrepresentable{value: F64}

def bounded(value: W.U64) -> W.U64:
  match value:
    case W.U64{high, low}: W.U64{U32.and(high, 65535), low}

def candidate(value: Decoded) -> W.U64:
  match value:
    case Finite{_, exponent, significand}:
      bounded(W.shiftRight(significand, U32.to_nat(U32.min((1075 - exponent : U32), 64))))
    case _: W.zero()

def natural(value: W.U64) -> Nat:
  match value:
    case W.U64{high, low}: Nat.add(Nat.mul(U32.to_nat(U32.and(high, 65535)), Nat.mul(65536n, 65536n)), U32.to_nat(low))

def checked(value: F64, word: W.U64, comparison: Maybe<&2, Cmp>) -> Result<&2, &2, Error, Nat>:
  match comparison:
    case Some{EQ{}}: Done{natural(word)}
    case _: Fail{Unrepresentable{value}}

def convert(+value: F64) -> Result<&2, &2, Error, Nat>:
  +word = candidate(decode(value))
  checked(value, word, compare(value, fromU64(word)))


def fromWord(word: W.U64) -> B.BigNat:
  match word:
    case W.U64{high, low}: B.add(B.shiftLeft(B.fromU32(high), 32n), B.fromU32(low))

# Exact rational-to-binary64 rounding, shared by numeric text parsers. Neither
# numerator nor denominator is first rounded to a floating-point value.
type Bounds is Data:
  Bounds{lower: W.U64, upper: W.U64}

# Positive finite values expressed in units of the least positive subnormal.
# The upper endpoint is a virtual 2^1024 value, whose encoding is infinity.
# Its midpoint with the largest finite number is the overflow threshold.
def decodedUnits(value: Decoded) -> B.BigNat:
  match value:
    case Finite{_, exponent, significand}: B.shiftLeft(fromWord(significand), U32.to_nat((exponent - 1 : U32)))
    case Infinity{_}: B.shiftLeft(B.one(), 2098n)
    case NotANumber{}: B.zero()

def units(bits: W.U64) -> B.BigNat: decodedUnits(decode(ofWord(bits)))

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

def roundedRatio(target: B.BigNat, denominator: B.BigNat, bounds: Bounds) -> F64:
  match bounds:
    case Bounds{+lower, +upper}:
      midpointTwice = B.multiply(B.add(units(lower), units(upper)), denominator)
      ofWord(roundChoice(B.compare(B.shiftLeft(target, 1n), midpointTwice), lower, upper))

def signed(negative: Bool, value: F64) -> F64:
  match negative:
    case False{}: value
    case True{}: negate(value)

def fromRatio(negative: Bool, numerator: B.BigNat, denominator: B.BigNat) -> Maybe<&2, F64>:
  match denominator:
    case B.BigNat{Nil{}}: None{}
    case B.BigNat{head <> tail}:
      +divisor = {B.BigNat{head <> tail} : B.BigNat}
      +target = B.shiftLeft(numerator, 1074n)
      bounds = bracket(63n, target, divisor, Bounds{W.zero(), W.U64{2146435072, 0}})
      Some{signed(negative, roundedRatio(target, divisor, bounds))}

