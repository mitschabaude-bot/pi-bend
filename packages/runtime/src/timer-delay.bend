import Base
import ./f64.bend as F
import ./timer-milliseconds.bend as Exact

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
  checked(value, Exact.candidate(F.decode(value)), F.compare(value, F.fromU32(0)), F.compare(value, F.multiply(F.fromU32(65536), F.fromU32(65536))))
