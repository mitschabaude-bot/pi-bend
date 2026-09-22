import Base
import ./u64.bend as W
import ./big-nat.bend as B
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

# Number.isInteger semantics: signed zeros are integers, infinities/NaNs are
# not. A finite number is integral exactly when shifting away its fractional
# significand bits and restoring them leaves the significand unchanged.
def integralFinite(+exponent: U32, +significand: W.U64) -> Bool:
  +shift = U32.to_nat(U32.min((1075 - U32.min(exponent, 1075) : U32), 64))
  W.equal(significand, W.shiftLeft(W.shiftRight(significand, shift), shift))

def integerDecoded(value: Decoded) -> Bool:
  match value:
    case Finite{_, exponent, significand}: integralFinite(exponent, significand)
    case _: False{}

def isInteger(value: F64) -> Bool: integerDecoded(decode(value))

# Truncate toward zero by clearing fractional significand bits. In particular,
# negative sub-unit values become negative zero and special values retain bits.
def truncateSmall(small: Bool, negative: Bool, +exponent: U32, significand: W.U64) -> F64:
  match small:
    case True{}: pack(negative, 0, W.zero())
    case False{}:
      +shift = U32.to_nat((1075 - exponent : U32))
      pack(negative, exponent, W.shiftLeft(W.shiftRight(significand, shift), shift))

def truncateLarge(large: Bool, original: F64, negative: Bool, +exponent: U32, significand: W.U64) -> F64:
  match large:
    case True{}: original
    case False{}: truncateSmall(U32.is_lt(exponent, 1023), negative, exponent, significand)

def truncated(original: F64, decoded: Decoded) -> F64:
  match decoded:
    case Finite{negative, +exponent, significand}: truncateLarge(U32.is_ge(exponent, 1075), original, negative, exponent, significand)
    case _: original

def truncate(+value: F64) -> F64: truncated(value, decode(value))


# Reference-quality shortest decimal conversion using exact rounding intervals.
# All comparisons and divisions are integer operations. No floating estimates,
# host formatting or precision truncation participate in digit selection.
# Exponents/decimal positions are stored with bias 400, covering binary64's range.
type Interval is Data:
  Interval{lower: B.BigNat, center: B.BigNat, upper: B.BigNat, denominator: B.BigNat, inclusive: Bool, exponent: Nat}

type Decimal is Data:
  Decimal{digits: String, position: Nat}

def fromWord(word: W.U64) -> B.BigNat:
  match word:
    case W.U64{high, low}: B.add(B.shiftLeft(B.fromU32(high), 32n), B.fromU32(low))

def scaleBinary(positive: Bool, exponent: U32, lower: B.BigNat, center: B.BigNat, upper: B.BigNat, inclusive: Bool) -> Interval:
  match positive:
    case True{}:
      +shift = U32.to_nat((exponent - 1077 : U32))
      Interval{B.shiftLeft(lower, shift), B.shiftLeft(center, shift), B.shiftLeft(upper, shift), B.one(), inclusive, 400n}
    case False{}: Interval{lower, center, upper, B.shiftLeft(B.one(), U32.to_nat((1077 - exponent : U32))), inclusive, 400n}

# 4*m times 2^(e-2) is the original value. At a normal power-of-two boundary
# the lower neighbour is half as far away; at the subnormal boundary it is not.
def interval(+exponent: U32, +significand: W.U64) -> Interval:
  +center = W.shiftLeft(significand, 2n)
  lowerGap = Bool.pick(U32, U32.is_gt(exponent, 1) && W.equal(significand, W.U64{1048576, 0}), 1, 2)
  inclusive = W.equal(W.bitAnd(significand, W.one()), W.zero())
  scaleBinary(U32.is_ge(exponent, 1077), exponent, fromWord(W.subtract(center, W.fromU32(lowerGap))), fromWord(center), fromWord(W.add(center, W.fromU32(2))), inclusive)

# LT means below one; GT means at least ten; EQ is normalized to [1,10).
def directionOrders(atOne: Cmp, atTen: Cmp) -> Cmp:
  match atOne atTen:
    case LT{} _: LT{}
    case _ LT{}: EQ{}
    case _ _: GT{}

def directionOf(state: Interval) -> Cmp:
  match state:
    case Interval{_, +center, _, +denominator, _, _}:
      directionOrders(B.compare(center, denominator), B.compare(center, B.multiplyU32(denominator, 10)))

# The normalization bound is derived from binary64's maximum denominator bit
# count (1076), which exceeds the required decimal rescalings (at most 324).
def normalizeDecimal(fuel: Nat, direction: Cmp, state: Interval) -> Maybe<&2, Interval>:
  match fuel direction state:
    case _ EQ{} state: Some{state}
    case 0n _ _: None{}
    case 1n+n LT{} Interval{lower, center, upper, denominator, inclusive, exponent}:
      +next = {Interval{B.multiplyU32(lower, 10), B.multiplyU32(center, 10), B.multiplyU32(upper, 10), denominator, inclusive, (exponent - 1n : Nat)} : Interval}
      normalizeDecimal(n, directionOf(next), next)
    case 1n+n GT{} Interval{lower, center, upper, denominator, inclusive, exponent}:
      +next = {Interval{lower, center, upper, B.multiplyU32(denominator, 10), inclusive, (exponent + 1n : Nat)} : Interval}
      normalizeDecimal(n, directionOf(next), next)

def withinBounds(lower: Cmp, upper: Cmp, inclusive: Bool) -> Bool:
  match lower upper:
    case LT{} _: False{}
    case _ GT{}: False{}
    case GT{} LT{}: True{}
    case _ _: inclusive

def admissible(candidate: B.BigNat, state: Interval) -> Bool:
  match state:
    case Interval{lower, _, upper, denominator, inclusive, _}:
      +scaled = B.multiply(candidate, denominator)
      withinBounds(B.compare(scaled, lower), B.compare(scaled, upper), inclusive)

def even(value: B.BigNat) -> Bool:
  match value:
    case B.BigNat{Nil{}}: True{}
    case B.BigNat{head <> _}: U32.is_eq(U32.and(head, 1), 0)

def nearest(order: Cmp, +down: B.BigNat, up: B.BigNat) -> B.BigNat:
  match order:
    case LT{}: down
    case GT{}: up
    case EQ{}: Bool.pick(B.BigNat, even(down), down, up)

def chooseCandidates(downValid: Bool, upValid: Bool, down: B.BigNat, up: B.BigNat, remainder: B.BigNat, denominator: B.BigNat) -> Maybe<&2, B.BigNat>:
  match downValid upValid:
    case False{} False{}: None{}
    case True{} False{}: Some{down}
    case False{} True{}: Some{up}
    case True{} True{}: Some{nearest(B.compare(B.shiftLeft(remainder, 1n), denominator), down, up)}

def candidates(+state: Interval, denominator: B.BigNat, divided: Maybe<&2, B.Division>) -> Maybe<&2, B.BigNat>:
  match divided:
    case None{}: None{}
    case Some{B.Division{+down, remainder}}:
      +up = B.add(down, B.one())
      chooseCandidates(admissible(down, state), admissible(up, state), down, up, remainder, denominator)

def select(+state: Interval) -> Maybe<&2, B.BigNat>:
  match state:
    case Interval{_, center, _, +denominator, _, _}: candidates(state, denominator, B.divide(center, denominator))

def stripHead(head: Char, tail: String) -> String:
  match head tail:
    case Chr{48} SNil{}: ""
    case head tail: SCon{head, tail}

def stripTrailingZeros(digits: String) -> String:
  match digits:
    case SNil{}: ""
    case SCon{head, tail}: stripHead(head, stripTrailingZeros(tail))

def decimalResult(coefficient: B.BigNat, places: Nat, exponent: Nat) -> Decimal:
  +digits = B.toDecimal(coefficient)
  Decimal{stripTrailingZeros(digits), exponent + 1n + String.length(digits) - places}

# Binary64 always has a round-tripping decimal with at most seventeen digits.
# An explicit None exposes any violated internal invariant instead of returning
# a guessed or truncated number. Both adjacent decimal candidates are checked.
def search(fuel: Nat, places: Nat, state: Interval, candidate: Maybe<&2, B.BigNat>) -> Maybe<&2, Decimal>:
  match fuel state candidate:
    case _ Interval{_, _, _, _, _, exponent} Some{coefficient}: Some{decimalResult(coefficient, places, exponent)}
    case 0n _ None{}: None{}
    case 1n+n Interval{lower, center, upper, denominator, inclusive, exponent} None{}:
      +next = {Interval{B.multiplyU32(lower, 10), B.multiplyU32(center, 10), B.multiplyU32(upper, 10), denominator, inclusive, exponent} : Interval}
      search(n, places + 1n, next, select(next))

def shortest(normalized: Maybe<&2, Interval>) -> Maybe<&2, Decimal>:
  match normalized:
    case None{}: None{}
    case Some{+state}: search(16n, 1n, state, select(state))

def zeros(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+n: SCon{Chr{48}, zeros(n)}

def scientificMantissa(digits: String) -> String:
  match digits:
    case SNil{}: ""
    case SCon{head, SNil{}}: SCon{head, SNil{}}
    case SCon{head, tail}: SCon{head, SCon{Chr{46}, tail}}

def scientific(negative: Bool, digits: String, position: Nat) -> String:
  match negative:
    case True{}: scientificMantissa(digits) ++ "e-" ++ Nat.show(401n - position)
    case False{}: scientificMantissa(digits) ++ "e+" ++ Nat.show(position - 401n)

def positiveFixed(enoughPlaces: Bool, +digits: String, +position: Nat) -> String:
  match enoughPlaces:
    case True{}: digits ++ zeros(position - String.length(digits))
    case False{}: String.take(digits, position) ++ "." ++ String.drop(digits, position)

def renderForm(form: U32, +digits: String, +position: Nat) -> String:
  match form:
    case 0: "0." ++ zeros(400n - position) ++ digits
    case 1: positiveFixed(Nat.is_ge(position - 400n, String.length(digits)), digits, position - 400n)
    case 2: scientific(True{}, digits, position)
    case _: scientific(False{}, digits, position)

def render(decimal: Decimal) -> String:
  match decimal:
    case Decimal{digits, +position}:
      form = Bool.pick(U32, Nat.is_le(position, 394n), 2,
        Bool.pick(U32, Nat.is_le(position, 400n), 0,
          Bool.pick(U32, Nat.is_le(position, 421n), 1, 3)))
      renderForm(form, digits, position)

def renderSigned(negative: Bool, result: Maybe<&2, Decimal>) -> Maybe<&2, String>:
  match result:
    case None{}: None{}
    case Some{decimal}: Some{Bool.pick(String, negative, "-", "") ++ render(decimal)}

def finite(zero: Bool, negative: Bool, exponent: U32, significand: W.U64) -> Maybe<&2, String>:
  match zero:
    case True{}: Some{"0"}
    case False{}:
      +state = interval(exponent, significand)
      renderSigned(negative, shortest(normalizeDecimal(U32.to_nat(1077), directionOf(state), state)))

def decoded(value: Decoded) -> Maybe<&2, String>:
  match value:
    case NotANumber{}: Some{"NaN"}
    case Infinity{negative}: Some{Bool.pick(String, negative, "-Infinity", "Infinity")}
    case Finite{negative, exponent, +significand}: finite(W.equal(significand, W.zero()), negative, exponent, significand)

# Base-10 ECMAScript-style number spelling. This is not a locale formatter.
def toDecimal(value: F64) -> Maybe<&2, String>: decoded(decode(value))

# JSON serializes non-finite numeric values as null. Finite values use the same
# decimal spelling; negative zero therefore becomes 0 in both public helpers.
def jsonDecoded(value: Decoded) -> Maybe<&2, String>:
  match value:
    case NotANumber{}: Some{"null"}
    case Infinity{_}: Some{"null"}
    case value: decoded(value)

def toJsonNumber(value: F64) -> Maybe<&2, String>: jsonDecoded(decode(value))


# Bend's native Nat representation is bounded to 48 bits. Decode only a
# bounded candidate, then require exact numeric equality before returning it.
# Negative zero becomes zero; negative/fractional/nonfinite/out-of-range values
# return their original bits in the typed error instead of rounding or wrapping.
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
def decodedUnits(value: Decoded) -> B.BigNat:
  match value:
    case Finite{_, exponent, significand}: B.shiftLeft(integerWord(significand), U32.to_nat((exponent - 1 : U32)))
    case Infinity{_}: B.shiftLeft(B.one(), 2098n)
    case NotANumber{}: B.zero()

def units(bits: W.U64) -> B.BigNat: decodedUnits(decode(F64{bits}))

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
      F64{roundChoice(B.compare(B.shiftLeft(target, 1n), midpointTwice), lower, upper)}

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


# Binary64 fmod: remainder after truncating the quotient toward zero.
# Shift/subtract avoids overflow and quotient rounding, even across the full
# normal/subnormal exponent range. The dividend determines the result sign.
def subtractOnce(+value: W.U64, +divisor: W.U64) -> W.U64:
  Bool.pick(W.U64, W.atLeast(W.compare(value, divisor)), W.subtract(value, divisor), value)

def bitsRemainder(steps: Nat, value: W.U64, +divisor: W.U64) -> W.U64:
  match steps:
    case Zero{}: subtractOnce(value, divisor)
    case Succ{rest}: bitsRemainder(rest, W.shiftLeftOne(subtractOnce(value, divisor)), divisor)

def packed(negative: Bool, normalizedRemainder: Normalized) -> F64:
  match normalizedRemainder:
    case Normalized{+exponent, value}:
      roundExtended(U32.is_le(exponent, 2048), negative, exponent, W.shiftLeft(value, 3n))

def resultRemainder(negative: Bool, exponent: U32, +value: W.U64) -> F64:
  packed(negative, normalizeOperand(52n, W.atLeast(W.compare(value, W.U64{1048576, 0})) || W.equal(value, W.zero()), exponent, value))

def ordered(smaller: Bool, original: F64, negative: Bool, ea: U32, ma: W.U64, +eb: U32, mb: W.U64) -> F64:
  match smaller:
    case True{}: original
    case False{}: resultRemainder(negative, eb, bitsRemainder(U32.to_nat(U32.sub(ea, eb)), ma, mb))

def normalizedRemainder(original: F64, negative: Bool, left: Normalized, right: Normalized) -> F64:
  match left right:
    case Normalized{+ea, ma} Normalized{+eb, mb}:
      ordered(U32.is_lt(ea, eb), original, negative, ea, ma, eb, mb)

def finiteRemainder(zeroDivisor: Bool, original: F64, negative: Bool, ea: U32, ma: W.U64, eb: U32, mb: W.U64) -> F64:
  match zeroDivisor:
    case True{}: nan()
    case False{}: normalizedRemainder(original, negative, normalized(ea, ma), normalized(eb, mb))

def decodedRemainder(original: F64, left: Decoded, right: Decoded) -> F64:
  match left right:
    case Finite{negative, ea, ma} Finite{_, eb, +mb}: finiteRemainder(W.equal(mb, W.zero()), original, negative, ea, ma, eb, mb)
    case Finite{_, _, _} Infinity{_}: original
    case _ _: nan()

def remainder(+left: F64, right: F64) -> F64:
  decodedRemainder(left, decode(left), decode(right))


# Rounding toward positive infinity preserves negative zero and non-finite
# values. Only a positive fractional remainder requires an increment.
def ceilingOf(order: Maybe<&2, Cmp>, integral: F64) -> F64:
  match order:
    case Some{GT{}}: add(integral, fromU32(1))
    case _: integral

def ceil(+value: F64) -> F64:
  +integral = truncate(value)
  ceilingOf(compare(value, integral), integral)
