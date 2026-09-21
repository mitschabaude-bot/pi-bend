import Base
import ./f64.bend as F
import ./u64.bend as W

# Bend's native Nat representation is bounded to 48 bits. Decode only a
# bounded candidate, then require exact numeric equality before returning it.
# Negative zero becomes zero; negative/fractional/nonfinite/out-of-range values
# return their original bits in the typed error instead of rounding or wrapping.
type Error is Data:
  Unrepresentable{value: F.F64}

def bounded(value: W.U64) -> W.U64:
  match value:
    case W.U64{high, low}: W.U64{U32.and(high, 65535), low}

def candidate(value: F.Decoded) -> W.U64:
  match value:
    case F.Finite{_, exponent, significand}:
      bounded(W.shiftRight(significand, U32.to_nat(U32.min((1075 - exponent : U32), 64))))
    case _: W.zero()

def natural(value: W.U64) -> Nat:
  match value:
    case W.U64{high, low}: Nat.add(Nat.mul(U32.to_nat(U32.and(high, 65535)), Nat.mul(65536n, 65536n)), U32.to_nat(low))

def checked(value: F.F64, word: W.U64, comparison: Maybe<&2, Cmp>) -> Result<&2, &2, Error, Nat>:
  match comparison:
    case Some{EQ{}}: Done{natural(word)}
    case _: Fail{Unrepresentable{value}}

def convert(+value: F.F64) -> Result<&2, &2, Error, Nat>:
  +word = candidate(F.decode(value))
  checked(value, word, F.compare(value, F.fromU64(word)))
