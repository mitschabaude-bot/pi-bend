import Base
import ./f64.bend as F
import ./u64.bend as W

# Native timers use literal U32 milliseconds. Reject unrepresentable durations
# instead of rounding, wrapping or turning overflow into a one-millisecond wait.
type Error is Data:
  Unrepresentable{value: F.F64}

def low(value: W.U64) -> U32:
  match value:
    case W.U64{_, word}: word

def candidate(value: F.Decoded) -> U32:
  match value:
    case F.Finite{_, exponent, significand}:
      low(W.shiftRight(significand, U32.to_nat(U32.min((1075 - exponent : U32), 64))))
    case _: 0

def checked(value: F.F64, milliseconds: U32, comparison: Maybe<&2, Cmp>) -> Result<&2, &2, Error, U32>:
  match comparison:
    case Some{EQ{}}: Done{milliseconds}
    case _: Fail{Unrepresentable{value}}

# Re-encoding the candidate establishes exactness, including signed-zero
# equality. This also rejects negative, fractional and non-finite inputs.
def milliseconds(+value: F.F64) -> Result<&2, &2, Error, U32>:
  +word = candidate(F.decode(value))
  checked(value, word, F.compare(value, F.fromU32(word)))
