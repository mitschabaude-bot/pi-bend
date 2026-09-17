import Base
import ./u64.bend as W

# Wide intermediates for binary64 and integer algorithms. Arithmetic wraps.
type U128 is Data:
  U128{high: W.U64, low: W.U64}

def add(a: U128, b: U128) -> U128:
  match a b:
    case U128{ah, +al} U128{bh, bl}:
      +sum = W.add(al, bl)
      carry = Bool.not(W.atLeast(W.compare(sum, al)))
      U128{W.add(W.add(ah, bh), W.fromU32(Bool.pick(U32, carry, 1, 0))), sum}

def shiftedWord(+value: W.U64) -> U128:
  U128{W.shiftRight(value, 32n), W.shiftLeft(value, 32n)}

# Exact 64 x 64 -> 128 product from four full-width limb products.
def multiply(a: W.U64, b: W.U64) -> U128:
  match a b:
    case W.U64{+ah, +al} W.U64{+bh, +bl}:
      outer = {U128{W.multiplyWords(ah, bh), W.multiplyWords(al, bl)} : U128}
      add(add(outer, shiftedWord(W.multiplyWords(ah, bl))), shiftedWord(W.multiplyWords(al, bh)))

def shiftRightOne(value: U128) -> U128:
  match value:
    case U128{+hi, lo}:
      U128{W.shiftRightOne(hi), W.bitOr(W.shiftRightOne(lo), W.shiftLeft(hi, 63n))}

def odd(value: U128) -> Bool:
  match value:
    case U128{_, W.U64{_, lo}}: U32.is_ne(U32.and(lo, 1), 0)

def jam(value: U128, sticky: Bool) -> U128:
  match value:
    case U128{hi, lo}: U128{hi, W.bitOr(lo, W.fromU32(Bool.pick(U32, sticky, 1, 0)))}

def shiftRightJamBits(fuel: Nat, +value: U128) -> U128:
  match fuel:
    case 0n: value
    case 1n+n: shiftRightJamBits(n, jam(shiftRightOne(value), odd(value)))

def shiftRightJam(value: U128, count: Nat) -> U128:
  shiftRightJamBits(Nat.min(count, 128n), value)
