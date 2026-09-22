import Base
import ./u64.bend as W
import ./f64.bend as F

# Date.now's wall-clock source, separate from monotonic elapsed-time clocks.
# Negative epochs use signed two's-complement words; conversion never passes
# through F32 or a host floating-point adapter. This is not the full Date API.
def fromMilliseconds(+value: W.U64) -> F64:
  match value:
    case W.U64{+high, +low}:
      Bool.pick(F64, U32.is_ge(high, 2147483648), F.negate(F.fromU64(W.subtract(W.zero(), W.U64{high, low}))), F.fromU64(W.U64{high, low}))

def words(value: U32 & U32) -> W.U64:
  match value:
    case Tuple{high, low}: W.U64{high, low}

def now() -> IO(F64):
  do IO<F64>:
    value : U32 & U32 <- IO.unixMilliseconds()
    return fromMilliseconds(words(value))
