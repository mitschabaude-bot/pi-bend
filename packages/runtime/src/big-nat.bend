import Base

# Exact unsigned integers, little-endian base-2^32 limbs. Canonical zero is an
# empty list; the final limb of a nonzero value is nonzero. Limb products use
# the native high-word multiply; carries and borrows come from wrapped
# comparisons. Factories/operations maintain these invariants.
type BigNat is Data:
  BigNat{limbs: List<&2, U32>}

type Division is Data:
  Division{quotient: BigNat, remainder: BigNat}

def trimHead(+head: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match tail:
    case Nil{}: Bool.pick(List<&2, U32>, U32.is_eq(head, 0), Nil{}, head <> Nil{})
    case _ <> _: head <> tail

def trim(limbs: List<&2, U32>) -> List<&2, U32>:
  match limbs:
    case Nil{}: Nil{}
    case head <> rest: trimHead(head, trim(rest))

def zero() -> BigNat: BigNat{Nil{}}
def one() -> BigNat: BigNat{1 <> Nil{}}
def fromU32(+value: U32) -> BigNat:
  BigNat{trim(value <> Nil{})}

def isZero(value: BigNat) -> Bool:
  match value:
    case BigNat{Nil{}}: True{}
    case _: False{}

def compareLow(high: Cmp, low: Cmp) -> Cmp:
  match high:
    case EQ{}: low
    case other: other

def compareLimbs(left: List<&2, U32>, right: List<&2, U32>) -> Cmp:
  match left right:
    case Nil{} Nil{}: EQ{}
    case Nil{} _ <> _: LT{}
    case _ <> _ Nil{}: GT{}
    case a <> xs b <> ys: compareLow(compareLimbs(xs, ys), U32.cmp(a, b))

def compare(left: BigNat, right: BigNat) -> Cmp:
  match left right:
    case BigNat{a} BigNat{b}: compareLimbs(a, b)

def equalOrder(order: Cmp) -> Bool:
  match order:
    case EQ{}: True{}
    case _: False{}

def equal(left: BigNat, right: BigNat) -> Bool: equalOrder(compare(left, right))

# A wrapped sum is smaller than an addend exactly when it carried.
def carried(+sum: U32, addend: U32) -> U32:
  Bool.pick(U32, U32.is_lt(sum, addend), 1, 0)

def addLimbs(left: List<&2, U32>, right: List<&2, U32>, +carry: U32) -> List<&2, U32>:
  match left right:
    case Nil{} Nil{}: trimHead(carry, Nil{})
    case +a <> xs Nil{}:
      +sum = (a + carry : U32)
      sum <> addLimbs(xs, Nil{}, carried(sum, a))
    case Nil{} +b <> ys:
      +sum = (b + carry : U32)
      sum <> addLimbs(Nil{}, ys, carried(sum, b))
    case +a <> xs +b <> ys:
      +partial = (a + b : U32)
      +sum = (partial + carry : U32)
      sum <> addLimbs(xs, ys, (carried(partial, a) + carried(sum, partial) : U32))

def add(left: BigNat, right: BigNat) -> BigNat:
  match left right:
    case BigNat{a} BigNat{b}: BigNat{addLimbs(a, b, 0)}

# Called only after checking left >= right. A wrapped difference borrows
# exactly when the subtrahend exceeds the minuend, checked before wrapping.
def subtractLimbs(left: List<&2, U32>, right: List<&2, U32>, +borrow: U32) -> List<&2, U32>:
  match left right:
    case Nil{} _: Nil{}
    case +a <> xs Nil{}:
      (a - borrow : U32) <> subtractLimbs(xs, Nil{}, carried(a, borrow))
    case +a <> xs +b <> ys:
      +partial = (a - b : U32)
      (partial - borrow : U32) <> subtractLimbs(xs, ys, (carried(a, b) + carried(partial, borrow) : U32))

def subtractOrdered(order: Cmp, left: BigNat, right: BigNat) -> Maybe<&2, BigNat>:
  match order left right:
    case LT{} _ _: None{}
    case _ BigNat{a} BigNat{b}: Some{BigNat{trim(subtractLimbs(a, b, 0))}}

def subtract(+left: BigNat, +right: BigNat) -> Maybe<&2, BigNat>:
  subtractOrdered(compare(left, right), left, right)

# A limb times a factor plus a carry is below 2^64: the high word plus at
# most one carried bit is the next carry.
def multiplyLimb(limbs: List<&2, U32>, +factor: U32, +carry: U32) -> List<&2, U32>:
  match limbs:
    case Nil{}: trimHead(carry, Nil{})
    case +head <> rest:
      +low = (U32.mul(head, factor) + carry : U32)
      low <> multiplyLimb(rest, factor, (U32.mul_hi(head, factor) + carried(low, carry) : U32))

def multiplyLimbs(left: List<&2, U32>, +right: List<&2, U32>) -> List<&2, U32>:
  match left:
    case Nil{}: Nil{}
    case head <> rest: addLimbs(multiplyLimb(right, head, 0), 0 <> multiplyLimbs(rest, right), 0)

def multiply(left: BigNat, right: BigNat) -> BigNat:
  match left right:
    case BigNat{a} BigNat{b}: BigNat{trim(multiplyLimbs(a, b))}

def multiplyU32(value: BigNat, factor: U32) -> BigNat:
  multiply(value, fromU32(factor))

def prefixZeros(count: Nat, limbs: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: limbs
    case 1n+n: 0 <> prefixZeros(n, limbs)

def shiftLeft(value: BigNat, +count: Nat) -> BigNat:
  match value:
    case BigNat{Nil{}}: zero()
    case BigNat{head <> rest}:
      BigNat{prefixZeros(count / 32n, multiplyLimb(head <> rest, U32.shln(1, count % 32n), 0))}

def powerLoop(exponent: Nat, +base: BigNat, accumulator: BigNat) -> BigNat:
  match exponent:
    case 0n: accumulator
    case 1n+n: powerLoop(n, base, multiply(accumulator, base))

def power(base: BigNat, exponent: Nat) -> BigNat: powerLoop(exponent, base, one())

def divideBitResult(order: Cmp, quotient: BigNat, remainder: BigNat, divisor: BigNat) -> Division:
  match order remainder divisor:
    case LT{} remainder _: Division{quotient, remainder}
    case _ BigNat{a} BigNat{b}: Division{add(quotient, one()), BigNat{trim(subtractLimbs(a, b, 0))}}

def divideBit(bit: U32, divisor: BigNat, state: Division) -> Division:
  match state:
    case Division{quotient, remainder}:
      +denominator = divisor
      +nextRemainder = add(shiftLeft(remainder, 1n), fromU32(bit))
      divideBitResult(compare(nextRemainder, denominator), shiftLeft(quotient, 1n), nextRemainder, denominator)

def divideWord(count: Nat, +word: U32, +divisor: BigNat, state: Division) -> Division:
  match count:
    case 0n: state
    case 1n+n:
      divideWord(n, U32.shl(word), divisor, divideBit(U32.shrn(word, 31n), divisor, state))

def divideLimbs(limbs: List<&2, U32>, +divisor: BigNat, state: Division) -> Division:
  match limbs:
    case Nil{}: state
    case head <> rest: divideLimbs(rest, divisor, divideWord(32n, head, divisor, state))

# Binary long division has one step per input bit, with no artificial size cap.
def divide(dividend: BigNat, divisor: BigNat) -> Maybe<&2, Division>:
  match dividend divisor:
    case _ BigNat{Nil{}}: None{}
    case BigNat{limbs} divisor: Some{divideLimbs(List.reverse(&2, U32, limbs), divisor, Division{zero(), zero()})}

type SmallDivision is Data:
  SmallDivision{quotient: BigNat, remainder: U32}

# divisor is in [1, 65535]. A limb is divided as two 16-bit halves so that
# remainder*65536+half stays representable; the remainder is below the
# divisor, so each half quotient fits 16 bits. Processing most-significant
# first builds little-endian quotient limbs.
def divideSmallLimbs(limbs: List<&2, U32>, +divisor: U32, quotient: List<&2, U32>, remainder: U32) -> SmallDivision:
  match limbs:
    case Nil{}: SmallDivision{BigNat{trim(quotient)}, remainder}
    case +head <> rest:
      +high = (remainder * 65536 + U32.shrn(head, 16n) : U32)
      +low = ((high % divisor : U32) * 65536 + U32.and(head, 65535) : U32)
      divideSmallLimbs(rest, divisor, U32.or(U32.shln((high / divisor : U32), 16n), (low / divisor : U32)) <> quotient, (low % divisor : U32))

def divideSmallRaw(dividend: BigNat, divisor: U32) -> SmallDivision:
  match dividend:
    case BigNat{limbs}: divideSmallLimbs(List.reverse(&2, U32, limbs), divisor, Nil{}, 0)

def divideSmallChecked(valid: Bool, dividend: BigNat, divisor: U32) -> Maybe<&2, SmallDivision>:
  match valid:
    case False{}: None{}
    case True{}: Some{divideSmallRaw(dividend, divisor)}

def divideSmall(dividend: BigNat, +divisor: U32) -> Maybe<&2, SmallDivision>:
  divideSmallChecked(U32.is_gt(divisor, 0) && U32.is_le(divisor, 65535), dividend, divisor)

def decimalDigits(chars: String, state: Maybe<&2, BigNat>) -> Maybe<&2, BigNat>:
  match chars state:
    case _ None{}: None{}
    case SNil{} Some{value}: Some{value}
    case SCon{Chr{+code}, rest} Some{value}:
      decimalDigits(rest, Bool.pick(Maybe<&2, BigNat>, U32.is_ge(code, 48) && U32.is_le(code, 57), Some{add(multiplyU32(value, 10), fromU32((code - 48 : U32)))}, None{}))

# Exact unsigned decimal integers only. Floating-point syntax is a separate API.
def fromDecimal(text: String) -> Maybe<&2, BigNat>:
  match text:
    case SNil{}: None{}
    case text: decimalDigits(text, Some{zero()})

def showDigits(fuel: Nat, step: SmallDivision, accumulator: String) -> String:
  match fuel step:
    case 0n _: accumulator
    case 1n+n SmallDivision{BigNat{Nil{}}, remainder}: SCon{Char.from_u32((48 + remainder : U32)), accumulator}
    case 1n+n SmallDivision{quotient, remainder}:
      showDigits(n, divideSmallRaw(quotient, 10), SCon{Char.from_u32((48 + remainder : U32)), accumulator})

def toDecimal(value: BigNat) -> String:
  match value:
    case BigNat{Nil{}}: "0"
    case BigNat{+limbs}:
      # Each 32-bit limb contributes at most ten decimal digits. This is a
      # proven input-size bound for termination, not a fixed precision limit.
      showDigits(List.length(&2, U32, limbs) * 10n, divideSmallRaw(BigNat{limbs}, 10), "")

# Big-endian octet conversion; callers validate byte ranges. Fixed-width
# output requires that the number fits in the requested width.
def readBigEndian(bytes: List<&2, U32>, value: BigNat) -> BigNat:
  match bytes:
    case Nil{}: value
    case byte <> rest: readBigEndian(rest, add(multiplyU32(value, 256), fromU32(byte)))

def fromBigEndian(bytes: List<&2, U32>) -> BigNat:
  readBigEndian(bytes, zero())

# Public modular arithmetic. The modulus must be nonzero.
def remainder(division: Division) -> BigNat:
  match division:
    case Division{_, value}: value

def reduce(value: BigNat, modulus: BigNat) -> BigNat:
  match value:
    case BigNat{limbs}: remainder(divideLimbs(List.reverse(&2, U32, limbs), modulus, Division{zero(), zero()}))

def multiplyBit(set: Bool, squared: BigNat, base: BigNat, modulus: BigNat) -> BigNat:
  match set:
    case False{}: squared
    case True{}: reduce(multiply(squared, base), modulus)

def powerByte(fuel: Nat, +byte: U32, +base: BigNat, +modulus: BigNat, +value: BigNat) -> BigNat:
  match fuel:
    case 0n: value
    case 1n+fuel:
      powerByte(fuel, U32.and(U32.shl(byte), 255), base, modulus, multiplyBit(U32.is_eq(U32.and(byte, 128), 128), reduce(multiply(value, value), modulus), base, modulus))

def modularPower(exponent: List<&2, U32>, +base: BigNat, +modulus: BigNat, value: BigNat) -> BigNat:
  match exponent:
    case Nil{}: value
    case byte <> rest: modularPower(rest, base, modulus, powerByte(8n, byte, base, modulus, value))

def writeBigEndian(count: Nat, step: SmallDivision, bytes: List<&2, U32>) -> List<&2, U32>:
  match count step:
    case 0n _: bytes
    case 1n+count SmallDivision{quotient, byte}: writeBigEndian(count, divideSmallRaw(quotient, 256), byte <> bytes)

# Montgomery arithmetic for an odd modulus of k limbs, R = 2^(32k). A value
# is kept as a*R mod m; a product of two such values is reduced word by word:
# k times, add u*m for the u that clears the low limb, then drop that limb.
# Every step is linear in k, so a modular product is quadratic, where the
# bit-serial division behind `reduce` is quadratic per bit.
type Montgomery is Data:
  Montgomery{modulus: List<&2, U32>, width: Nat, negInverse: U32}

# -m^-1 mod 2^32 by Newton's iteration from the low limb (odd): each step
# doubles the correct bits, and m0*m0 = 1 mod 8 seeds three of them.
def newtonInverse(fuel: Nat, +m0: U32, +inverse: U32) -> U32:
  match fuel:
    case 0n: inverse
    case 1n+n: newtonInverse(n, m0, (inverse * U32.sub(2, (m0 * inverse : U32)) : U32))

def montgomery(limbs: List<&2, U32>) -> Montgomery:
  match limbs:
    case Nil{}: Montgomery{Nil{}, 0n, 0}
    case +m0 <> +rest:
      Montgomery{m0 <> rest, List.length(&2, U32, m0 <> rest), U32.sub(0, newtonInverse(5n, m0, m0))}

def dropLow(limbs: List<&2, U32>) -> List<&2, U32>:
  match limbs:
    case Nil{}: Nil{}
    case _ <> rest: rest

def lowLimb(limbs: List<&2, U32>) -> U32:
  match limbs:
    case Nil{}: 0
    case head <> _: head

def reduceSteps(steps: Nat, space: Montgomery, +value: List<&2, U32>) -> List<&2, U32>:
  match steps space:
    case 0n _: value
    case 1n+n Montgomery{+modulus, width, +negInverse}:
      +factor = (lowLimb(value) * negInverse : U32)
      reduceSteps(n, Montgomery{modulus, width, negInverse}, dropLow(addLimbs(value, multiplyLimb(modulus, factor, 0), 0)))

def montgomeryFinish(order: Cmp, value: List<&2, U32>, modulus: List<&2, U32>) -> BigNat:
  match order:
    case LT{}: BigNat{trim(value)}
    case _: BigNat{trim(subtractLimbs(value, modulus, 0))}

# REDC: value < m*R in, value*R^-1 mod m out.
def montgomeryReduce(space: Montgomery, value: List<&2, U32>) -> BigNat:
  match space:
    case Montgomery{+modulus, +width, +negInverse}:
      +reduced = reduceSteps(width, Montgomery{modulus, width, negInverse}, value)
      montgomeryFinish(compareLimbs(trim(reduced), modulus), reduced, modulus)

def montgomeryMultiply(space: Montgomery, left: BigNat, right: BigNat) -> BigNat:
  match left right:
    case BigNat{a} BigNat{b}: montgomeryReduce(space, multiplyLimbs(a, b))

def montgomeryBit(set: Bool, space: Montgomery, squared: BigNat, base: BigNat) -> BigNat:
  match set:
    case False{}: squared
    case True{}: montgomeryMultiply(space, squared, base)

def montgomeryByte(fuel: Nat, +byte: U32, +space: Montgomery, +base: BigNat, +value: BigNat) -> BigNat:
  match fuel:
    case 0n: value
    case 1n+fuel:
      montgomeryByte(fuel, U32.and(U32.shl(byte), 255), space, base, montgomeryBit(U32.is_eq(U32.and(byte, 128), 128), space, montgomeryMultiply(space, value, value), base))

def montgomeryPower(exponent: List<&2, U32>, +space: Montgomery, +base: BigNat, value: BigNat) -> BigNat:
  match exponent:
    case Nil{}: value
    case byte <> rest: montgomeryPower(rest, space, base, montgomeryByte(8n, byte, space, base, value))

# Enters Montgomery form: a*R mod m through the general reduction, once.
def montgomeryEnter(space: Montgomery, value: BigNat, modulus: BigNat) -> BigNat:
  match space:
    case Montgomery{_, width, _}: reduce(shiftLeft(value, Nat.mul(width, 32n)), modulus)

def limbsOf(value: BigNat) -> List<&2, U32>:
  match value:
    case BigNat{limbs}: limbs

def isOdd(value: BigNat) -> Bool:
  match value:
    case BigNat{Nil{}}: False{}
    case BigNat{head <> _}: U32.is_eq(U32.and(head, 1), 1)

def montgomeryPowerMod(exponent: List<&2, U32>, base: BigNat, modulus: BigNat) -> BigNat:
  match modulus:
    case BigNat{+limbs}:
      +space = montgomery(limbs)
      +m = {BigNat{limbs} : BigNat}
      montgomeryReduce(space, limbsOf(montgomeryPower(exponent, space, montgomeryEnter(space, base, m), montgomeryEnter(space, one(), m))))

def powerModBy(odd: Bool, exponent: List<&2, U32>, base: BigNat, +modulus: BigNat) -> BigNat:
  match odd:
    case True{}: montgomeryPowerMod(exponent, base, modulus)
    case False{}: modularPower(exponent, base, modulus, reduce(one(), modulus))

# The modulus must be nonzero; an odd one (every RSA modulus and prime
# field) takes the Montgomery ladder, an even one the bit-serial reduction.
def powerMod(exponent: List<&2, U32>, base: BigNat, +modulus: BigNat) -> BigNat:
  powerModBy(isOdd(modulus), exponent, base, modulus)

def toBigEndian(width: Nat, value: BigNat) -> List<&2, U32>:
  writeBigEndian(width, divideSmallRaw(value, 256), Nil{})
