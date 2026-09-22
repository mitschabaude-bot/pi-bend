import Base
import ./u64.bend as W
import ./f64.bend as F

# One shared origin per runtime, initialized before application callbacks start.
# Copies retain the same origin. No wall clock, host float or F32 is involved.
type Clock is Data:
  Clock{origin: W.U64}

def words(value: U32 & U32) -> W.U64:
  match value:
    case Tuple{high, low}: W.U64{high, low}

def ticks() -> IO(W.U64):
  do IO<W.U64>:
    value : U32 & U32 <- IO.monotonicNanoseconds()
    return words(value)

def new() -> IO(Clock):
  do IO<Clock>:
    origin : W.U64 <- ticks()
    return Clock{origin}

# Subtract exact ticks before binary64 conversion, preserving small intervals
# even when the absolute monotonic counter exceeds binary64 integer precision.
def elapsed(clock: Clock, current: W.U64) -> F64:
  match clock:
    case Clock{origin}: F.divide(F.fromU64(W.subtract(current, origin)), F.fromU32(1000000))

def now(clock: Clock) -> IO(F64):
  do IO<F64>:
    current : W.U64 <- ticks()
    return elapsed(clock, current)
