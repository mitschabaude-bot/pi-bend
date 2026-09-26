import Base

# Fixed-width unsigned arithmetic, modulo 2^64. No foreign effects.
# Limbs are deliberately ordered high, low for readable bit-pattern literals.
type U64 is Data:
  U64{high: U32, low: U32}

type Division is Data:
  Division{quotient: U64, remainder: U64}

def zero() -> U64: U64{0, 0}
def one() -> U64: U64{0, 1}
def fromU32(value: U32) -> U64: U64{0, value}

def equal(a: U64, b: U64) -> Bool:
  match a b:
    case U64{ah, al} U64{bh, bl}: U32.is_eq(ah, bh) && U32.is_eq(al, bl)

def compareLow(order: Cmp, fallback: Cmp) -> Cmp:
  match order:
    case EQ{}: fallback
    case LT{}: LT{}
    case GT{}: GT{}

def compare(a: U64, b: U64) -> Cmp:
  match a b:
    case U64{ah, al} U64{bh, bl}: compareLow(U32.cmp(ah, bh), U32.cmp(al, bl))

def atLeast(order: Cmp) -> Bool:
  match order:
    case LT{}: False{}
    case _: True{}

def add(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, +al} U64{bh, bl}:
      +sum = (al + bl : U32)
      carry = Bool.pick(U32, U32.is_lt(sum, al), 1, 0)
      U64{(ah + bh + carry : U32), sum}

def subtract(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, +al} U64{bh, +bl}:
      borrow = Bool.pick(U32, U32.is_lt(al, bl), 1, 0)
      U64{(ah - bh - borrow : U32), (al - bl : U32)}

def bitAnd(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, al} U64{bh, bl}: U64{U32.and(ah, bh), U32.and(al, bl)}

def bitOr(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, al} U64{bh, bl}: U64{U32.or(ah, bh), U32.or(al, bl)}

def bitXor(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, al} U64{bh, bl}: U64{U32.xor(ah, bh), U32.xor(al, bl)}

def bitNot(a: U64) -> U64:
  match a:
    case U64{ah, al}: U64{U32.not(ah), U32.not(al)}

def topBit(a: U64) -> Bool:
  match a:
    case U64{ah, _}: U32.is_ge(ah, 2147483648)

def shiftLeftOne(a: U64) -> U64:
  match a:
    case U64{ah, +al}: U64{U32.or(U32.shl(ah), U32.shrn(al, 31n)), U32.shl(al)}

def shiftRightOne(a: U64) -> U64:
  match a:
    case U64{+ah, al}: U64{U32.shr(ah), U32.or(U32.shr(al), U32.shln(ah, 31n))}

# Shifts by 64 or more produce zero. Rotations reduce the count modulo 64.
# A shift moves whole words: a count below 32 (never 0 here) splits across
# the limbs, 32 to 63 moves one limb, and C leaves shifts by 32 undefined.
def shiftLeftSplit(+ah: U32, +al: U32, +count: Nat) -> U64:
  U64{U32.or(U32.shln(ah, count), U32.shrn(al, Nat.sub(32n, count))), U32.shln(al, count)}
def shiftRightSplit(+ah: U32, +al: U32, +count: Nat) -> U64:
  U64{U32.shrn(ah, count), U32.or(U32.shrn(al, count), U32.shln(ah, Nat.sub(32n, count)))}
def shiftLeftWide(+al: U32, +count: Nat, +inRange: Bool) -> U64:
  match inRange:
    case True{}: U64{U32.shln(al, Nat.sub(count, 32n)), 0}
    case False{}: zero()
def shiftRightWide(+ah: U32, +count: Nat, +inRange: Bool) -> U64:
  match inRange:
    case True{}: U64{0, U32.shrn(ah, Nat.sub(count, 32n))}
    case False{}: zero()
def shiftLeftBy(+ah: U32, +al: U32, +count: Nat, +small: Bool) -> U64:
  match small:
    case True{}: shiftLeftSplit(ah, al, count)
    case False{}: shiftLeftWide(al, count, Nat.is_lt(count, 64n))
def shiftRightBy(+ah: U32, +al: U32, +count: Nat, +small: Bool) -> U64:
  match small:
    case True{}: shiftRightSplit(ah, al, count)
    case False{}: shiftRightWide(ah, count, Nat.is_lt(count, 64n))

def shiftLeft(a: U64, +count: Nat) -> U64:
  match a count:
    case U64{ah, al} 0n: U64{ah, al}
    case U64{ah, al} 1n+n: shiftLeftBy(ah, al, 1n + n, Nat.is_lt(n, 31n))

def shiftRight(a: U64, +count: Nat) -> U64:
  match a count:
    case U64{ah, al} 0n: U64{ah, al}
    case U64{ah, al} 1n+n: shiftRightBy(ah, al, 1n + n, Nat.is_lt(n, 31n))

def rotateRight(+a: U64, count: Nat) -> U64:
  +n = Nat.mod(count, 64n)
  bitOr(shiftRight(a, n), shiftLeft(a, Nat.sub(64n, n)))

def rotateLeft(+a: U64, count: Nat) -> U64:
  +n = Nat.mod(count, 64n)
  bitOr(shiftLeft(a, n), shiftRight(a, Nat.sub(64n, n)))

# Exact 32 x 32 -> 64 product: the high word is the U32.mul_hi primitive.
def multiplyWords(+a: U32, +b: U32) -> U64: U64{U32.mul_hi(a, b), (a * b : U32)}

def multiply(a: U64, b: U64) -> U64:
  match a b:
    case U64{ah, +al} U64{bh, +bl}:
      add(multiplyWords(al, bl), U64{(ah * bl + al * bh : U32), 0})

# Restoring division. The extra carry bit matters for divisors >= 2^63.
def divideBits(fuel: Nat, +input: U64, +divisor: U64, quotient: U64, +remainder: U64) -> Division:
  match fuel:
    case 0n: Division{quotient, remainder}
    case 1n+n:
      +extended = bitOr(shiftLeftOne(remainder), fromU32(Bool.pick(U32, topBit(input), 1, 0)))
      +fits = topBit(remainder) || atLeast(compare(extended, divisor))
      next = Bool.pick(U64, fits, subtract(extended, divisor), extended)
      q = bitOr(shiftLeftOne(quotient), fromU32(Bool.pick(U32, fits, 1, 0)))
      divideBits(n, shiftLeftOne(input), divisor, q, next)

def divideChecked(isZero: Bool, a: U64, b: U64) -> Maybe<&2, Division>:
  match isZero:
    case True{}: None{}
    case False{}: Some{divideBits(64n, a, b, zero(), zero())}

def divide(a: U64, +b: U64) -> Maybe<&2, Division>:
  divideChecked(equal(b, zero()), a, b)
