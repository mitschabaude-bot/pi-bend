import Base
import ./u64.bend as W
import ./u128.bend as Wide

# IEEE-754 binary64 storage and arithmetic, round-to-nearest, ties-to-even.
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

# Extended biased exponents carry an additional 2048 so normalization and
# underflow remain unsigned. Nonzero finite inputs normalize in <= 52 steps.
type Normalized is Data:
  Normalized{exponent: U32, significand: W.U64}

def normalizeOperand(fuel: Nat, ready: Bool, +exponent: U32, +value: W.U64) -> Normalized:
  match fuel ready:
    case _ True{}: Normalized{exponent, value}
    case 0n False{}: Normalized{exponent, value}
    case 1n+n False{}:
      +next = W.shiftLeftOne(value)
      normalizeOperand(n, W.atLeast(W.compare(next, W.U64{1048576, 0})), (exponent - 1 : U32), next)

def normalized(exponent: U32, +value: W.U64) -> Normalized:
  normalizeOperand(52n, W.atLeast(W.compare(value, W.U64{1048576, 0})) || W.equal(value, W.zero()), (exponent + 2048 : U32), value)

def roundExtended(subnormal: Bool, negative: Bool, exponent: U32, value: W.U64) -> F64:
  match subnormal:
    case True{}: roundFinite(negative, 1, shiftRightJam(value, (2049 - exponent : U32)))
    case False{}: roundFinite(negative, (exponent - 2048 : U32), value)

def roundedProduct(product: Wide.U128, negative: Bool, +exponent: U32) -> F64:
  match product:
    case Wide.U128{_, lo}: roundExtended(U32.is_le(exponent, 2048), negative, exponent, lo)

def multiplyProduct(+product: Wide.U128, negative: Bool, exponent: U32) -> F64:
  match product:
    case Wide.U128{hi, _}:
      +carry = W.atLeast(W.compare(hi, W.U64{512, 0}))
      roundedProduct(Wide.shiftRightJam(product, Bool.pick(Nat, carry, 50n, 49n)), negative, (exponent + Bool.pick(U32, carry, 1, 0) : U32))

def multiplyNormalized(a: Normalized, b: Normalized, negative: Bool) -> F64:
  match a b:
    case Normalized{ea, ma} Normalized{eb, mb}:
      # The unshifted product has 105 or 106 bits; preserve 3 rounding bits.
      +product = Wide.multiply(ma, mb)
      # Bit 105 is bit 41 of the high limb, or bit 9 of its high word.
      multiplyProduct(product, negative, (ea + eb - 3071 : U32))

def signXor(a: Bool, +b: Bool) -> Bool: Bool.pick(Bool, a, Bool.not(b), b)

def multiplyDecoded(a: Decoded, b: Decoded) -> F64:
  match a b:
    case NotANumber{} _: nan()
    case _ NotANumber{}: nan()
    case Infinity{sa} Infinity{sb}: infinity(signXor(sa, sb))
    case Infinity{sa} Finite{sb, _, mb}: Bool.pick(F64, W.equal(mb, W.zero()), nan(), infinity(signXor(sa, sb)))
    case Finite{sa, _, ma} Infinity{sb}: Bool.pick(F64, W.equal(ma, W.zero()), nan(), infinity(signXor(sa, sb)))
    case Finite{sa, ea, ma} Finite{sb, eb, mb}: multiplyNormalized(normalized(ea, ma), normalized(eb, mb), signXor(sa, sb))

def multiply(a: F64, b: F64) -> F64: multiplyDecoded(decode(a), decode(b))

# Generate fractional quotient bits without constructing a shifted 109-bit
# dividend. The remainder stays below the 53-bit divisor throughout.
def quotientBits(fuel: Nat, +divisor: W.U64, quotient: W.U64, remainder: W.U64) -> W.Division:
  match fuel:
    case 0n: W.Division{quotient, remainder}
    case 1n+n:
      +doubled = W.shiftLeftOne(remainder)
      +fits = W.atLeast(W.compare(doubled, divisor))
      q = W.bitOr(W.shiftLeftOne(quotient), W.fromU32(Bool.pick(U32, fits, 1, 0)))
      r = Bool.pick(W.U64, fits, W.subtract(doubled, divisor), doubled)
      quotientBits(n, divisor, q, r)

def roundedQuotient(result: W.Division, negative: Bool, +exponent: U32) -> F64:
  match result:
    case W.Division{quotient, remainder}:
      sticky = Bool.not(W.equal(remainder, W.zero()))
      roundExtended(U32.is_le(exponent, 2048), negative, exponent, W.bitOr(quotient, W.fromU32(Bool.pick(U32, sticky, 1, 0))))

def divideNormalized(a: Normalized, b: Normalized, negative: Bool) -> F64:
  match a b:
    case Normalized{ea, +ma} Normalized{eb, +mb}:
      +smaller = Bool.not(W.atLeast(W.compare(ma, mb)))
      numerator = Bool.pick(W.U64, smaller, W.shiftLeftOne(ma), ma)
      result = quotientBits(55n, mb, W.one(), W.subtract(numerator, mb))
      roundedQuotient(result, negative, (ea + 3071 - eb - Bool.pick(U32, smaller, 1, 0) : U32))

def divideFinite(zeroA: Bool, zeroB: Bool, negative: Bool, ea: U32, ma: W.U64, eb: U32, mb: W.U64) -> F64:
  match zeroA zeroB:
    case True{} True{}: nan()
    case False{} True{}: infinity(negative)
    case True{} False{}: pack(negative, 0, W.zero())
    case False{} False{}: divideNormalized(normalized(ea, ma), normalized(eb, mb), negative)

def divideDecoded(a: Decoded, b: Decoded) -> F64:
  match a b:
    case NotANumber{} _: nan()
    case _ NotANumber{}: nan()
    case Infinity{_} Infinity{_}: nan()
    case Infinity{sa} Finite{sb, _, _}: infinity(signXor(sa, sb))
    case Finite{sa, _, _} Infinity{sb}: pack(signXor(sa, sb), 0, W.zero())
    case Finite{sa, ea, +ma} Finite{sb, eb, +mb}: divideFinite(W.equal(ma, W.zero()), W.equal(mb, W.zero()), signXor(sa, sb), ea, ma, eb, mb)

def divide(a: F64, b: F64) -> F64: divideDecoded(decode(a), decode(b))

def reverseOrder(order: Cmp) -> Cmp:
  match order:
    case LT{}: GT{}
    case EQ{}: EQ{}
    case GT{}: LT{}

def compareSigns(sa: Bool, sb: Bool, +a: W.U64, +b: W.U64) -> Cmp:
  match sa sb:
    case False{} False{}: W.compare(a, b)
    case True{} True{}: reverseOrder(W.compare(a, b))
    case True{} False{}: Bool.pick(Cmp, W.equal(a, W.zero()) && W.equal(b, W.zero()), EQ{}, LT{})
    case False{} True{}: Bool.pick(Cmp, W.equal(a, W.zero()) && W.equal(b, W.zero()), EQ{}, GT{})

def compareFinite(a: F64, b: F64) -> Cmp:
  match a b:
    case F64{W.U64{+ah, al}} F64{W.U64{+bh, bl}}:
      compareSigns(U32.is_ge(ah, 2147483648), U32.is_ge(bh, 2147483648), W.U64{U32.and(ah, 2147483647), al}, W.U64{U32.and(bh, 2147483647), bl})

def compareChecked(unordered: Bool, a: F64, b: F64) -> Maybe<&2, Cmp>:
  match unordered:
    case True{}: None{}
    case False{}: Some{compareFinite(a, b)}

# None is the unordered result for NaN; signed zeros compare equal.
def compare(+a: F64, +b: F64) -> Maybe<&2, Cmp>:
  compareChecked(isNaN(a) || isNaN(b), a, b)

def shrinkInteger(fuel: Nat, large: Bool, +exponent: U32, +value: W.U64) -> F64:
  match fuel large:
    case _ False{}: normalize(56n, W.atLeast(W.compare(value, W.U64{8388608, 0})), False{}, exponent, value)
    case 0n True{}: roundFinite(False{}, exponent, value)
    case 1n+n True{}:
      +next = shiftRightJam(value, 1)
      shrinkInteger(n, W.atLeast(W.compare(next, W.U64{16777216, 0})), (exponent + 1 : U32), next)

def fromU64(+value: W.U64) -> F64:
  shrinkInteger(8n, W.atLeast(W.compare(value, W.U64{16777216, 0})), 1078, value)

def fromU32(value: U32) -> F64: fromU64(W.fromU32(value))
