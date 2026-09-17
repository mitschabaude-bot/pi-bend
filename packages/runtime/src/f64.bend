import Base
import ./u64.bend as W

# IEEE-754 binary64 storage and round-to-nearest, ties-to-even addition.
# No conversion through F32, host arithmetic, or foreign effects.
type F64 is Data:
  F64{bits: W.U64}

type Decoded is Data:
  Finite{negative: Bool, exponent: U32, significand: W.U64}
  Infinity{negative: Bool}
  NotANumber{}

def fromBits(high: U32, low: U32) -> F64: F64{W.U64{high, low}}
def toBits(value: F64) -> W.U64:
  match value:
    case F64{bits}: bits

def nan() -> F64: fromBits(2146959360, 0)
def infinity(negative: Bool) -> F64:
  fromBits(Bool.pick(U32, negative, 4293918720, 2146435072), 0)

def decodeFields(special: Bool, negative: Bool, +exponent: U32, +fraction: W.U64) -> Decoded:
  match special:
    case True{}: Bool.pick(Decoded, W.equal(fraction, W.zero()), Infinity{negative}, NotANumber{})
    case False{}:
      hidden = Bool.pick(W.U64, U32.is_eq(exponent, 0), W.zero(), W.U64{1048576, 0})
      Finite{negative, U32.max(exponent, 1), W.bitOr(fraction, hidden)}

def decode(value: F64) -> Decoded:
  match value:
    case F64{W.U64{+high, low}}:
      +exponent = U32.and(U32.shrn(high, 20n), 2047)
      decodeFields(U32.is_eq(exponent, 2047), U32.is_ge(high, 2147483648), exponent, W.U64{U32.and(high, 1048575), low})

def isNaN(value: F64) -> Bool:
  match value:
    case F64{W.U64{+high, +low}}:
      U32.is_eq(U32.and(high, 2146435072), 2146435072) && Bool.not(U32.is_eq(U32.and(high, 1048575), 0) && U32.is_eq(low, 0))

def negate(value: F64) -> F64:
  match value:
    case F64{W.U64{high, low}}: fromBits(U32.xor(high, 2147483648), low)

# Preserve any discarded one-bit as a sticky bit for correct final rounding.
def shiftRightJam(+value: W.U64, count: U32) -> W.U64:
  +n = U32.to_nat(U32.min(count, 64))
  +shifted = W.shiftRight(value, n)
  sticky = Bool.not(W.equal(value, W.shiftLeft(shifted, n)))
  W.bitOr(shifted, W.fromU32(Bool.pick(U32, sticky, 1, 0)))

def pack(negative: Bool, exponent: U32, value: W.U64) -> F64:
  match value:
    case W.U64{high, low}:
      sign = Bool.pick(U32, negative, 2147483648, 0)
      fromBits(U32.or(sign, U32.or(U32.shln(exponent, 20n), U32.and(high, 1048575))), low)

def packRounded(+negative: Bool, +exponent: U32, +value: W.U64) -> F64:
  +carry = W.atLeast(W.compare(value, W.U64{2097152, 0}))
  +adjusted = Bool.pick(W.U64, carry, W.shiftRightOne(value), value)
  +exp = (exponent + Bool.pick(U32, carry, 1, 0) : U32)
  encodedExp = Bool.pick(U32, W.atLeast(W.compare(adjusted, W.U64{1048576, 0})), exp, 0)
  Bool.pick(F64, U32.is_ge(exp, 2047), infinity(negative), pack(negative, encodedExp, adjusted))

def roundFinite(negative: Bool, exponent: U32, value: W.U64) -> F64:
  match value:
    case W.U64{+high, +low}:
      +roundBits = U32.and(low, 7)
      odd = U32.is_ne(U32.and(low, 8), 0)
      increment = U32.is_gt(roundBits, 4) || (U32.is_eq(roundBits, 4) && odd)
      rounded = W.add(W.shiftRight(W.U64{high, low}, 3n), W.fromU32(Bool.pick(U32, increment, 1, 0)))
      packRounded(negative, exponent, rounded)

# Cancellation can remove at most 55 significant bits. Stop at exponent 1
# so subnormal results keep the same scaling as the smallest normal value.
def normalize(fuel: Nat, done: Bool, negative: Bool, +exponent: U32, +value: W.U64) -> F64:
  match fuel done:
    case _ True{}: roundFinite(negative, exponent, value)
    case 0n False{}: roundFinite(negative, exponent, value)
    case 1n+n False{}:
      +next = W.shiftLeftOne(value)
      +exp = (exponent - 1 : U32)
      normalize(n, U32.is_le(exp, 1) || W.atLeast(W.compare(next, W.U64{8388608, 0})), negative, exp, next)

def finishDifference(negative: Bool, +exponent: U32, +value: W.U64) -> F64:
  Bool.pick(F64, W.equal(value, W.zero()), fromBits(0, 0), normalize(56n, U32.is_le(exponent, 1) || W.atLeast(W.compare(value, W.U64{8388608, 0})), negative, exponent, value))

def finiteSum(sameSign: Bool, +negativeA: Bool, negativeB: Bool, +exponent: U32, +a: W.U64, +b: W.U64) -> F64:
  match sameSign:
    case True{}:
      +sum = W.add(a, b)
      +carry = W.atLeast(W.compare(sum, W.U64{16777216, 0}))
      roundFinite(negativeA, (exponent + Bool.pick(U32, carry, 1, 0) : U32), Bool.pick(W.U64, carry, shiftRightJam(sum, 1), sum))
    case False{}:
      +aLarger = W.atLeast(W.compare(a, b))
      finishDifference(Bool.pick(Bool, aLarger, negativeA, negativeB), exponent, Bool.pick(W.U64, aLarger, W.subtract(a, b), W.subtract(b, a)))

def addDecoded(a: Decoded, b: Decoded) -> F64:
  match a b:
    case NotANumber{} _: nan()
    case _ NotANumber{}: nan()
    case Infinity{+sa} Infinity{+sb}: Bool.pick(F64, Bool.pick(Bool, sa, sb, Bool.not(sb)), infinity(sa), nan())
    case Infinity{sa} _: infinity(sa)
    case _ Infinity{sb}: infinity(sb)
    case Finite{+sa, +ea, ma} Finite{+sb, +eb, mb}:
      +exponent = U32.max(ea, eb)
      aAligned = shiftRightJam(W.shiftLeft(ma, 3n), (exponent - ea : U32))
      bAligned = shiftRightJam(W.shiftLeft(mb, 3n), (exponent - eb : U32))
      finiteSum(Bool.pick(Bool, sa, sb, Bool.not(sb)), sa, sb, exponent, aAligned, bAligned)

def add(a: F64, b: F64) -> F64: addDecoded(decode(a), decode(b))
def subtract(a: F64, b: F64) -> F64: add(a, negate(b))
