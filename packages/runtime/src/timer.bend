import Base
import ./f64.bend as F
import ./u64.bend as W


# Native timers use literal U32 milliseconds. Reject unrepresentable durations
# instead of rounding, wrapping or turning overflow into a one-millisecond wait.
type MillisecondsError is Data:
  Unrepresentable{value: F.F64}

def low(value: W.U64) -> U32:
  match value:
    case W.U64{_, word}: word

def candidate(value: F.Decoded) -> U32:
  match value:
    case F.Finite{_, exponent, significand}:
      low(W.shiftRight(significand, U32.to_nat(U32.min((1075 - exponent : U32), 64))))
    case _: 0

def checkedMilliseconds(value: F.F64, millisecondsMilliseconds: U32, comparison: Maybe<&2, Cmp>) -> Result<&2, &2, MillisecondsError, U32>:
  match comparison:
    case Some{EQ{}}: Done{millisecondsMilliseconds}
    case _: Fail{Unrepresentable{value}}

# Re-encoding the candidate establishes exactness, including signed-zero
# equality. This also rejects negative, fractional and non-finite inputs.
def millisecondsMilliseconds(+value: F.F64) -> Result<&2, &2, MillisecondsError, U32>:
  +word = candidate(F.decode(value))
  checkedMilliseconds(value, word, F.compare(value, F.fromU32(word)))


# Backoff may be fractional. Quantize downward only when the input is finite,
# nonnegative and below 2^32; invalid values retain their original bits.
type Error is Data:
  InvalidDuration{value: F.F64}

def checked(value: F.F64, word: U32, lower: Maybe<&2, Cmp>, upper: Maybe<&2, Cmp>) -> Result<&2, &2, Error, U32>:
  match lower upper:
    case Some{EQ{}} Some{LT{}}: Done{word}
    case Some{GT{}} Some{LT{}}: Done{word}
    case _ _: Fail{InvalidDuration{value}}

def milliseconds(+value: F.F64) -> Result<&2, &2, Error, U32>:
  checked(value, candidate(F.decode(value)), F.compare(value, F.fromU32(0)), F.compare(value, F.multiply(F.fromU32(65536), F.fromU32(65536))))
