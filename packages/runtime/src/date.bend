import Base
import ./u64.bend as W
import ./f64.bend as F
import ./calendar.bend as Calendar

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

# Date.prototype.toISOString for finite non-negative integral epochs within
# Calendar's civil range: YYYY-MM-DDTHH:MM:SS.mmmZ. Other values yield None.
def zeros(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+n: "0" ++ zeros(n)

def padded(+text: String, width: Nat) -> String:
  zeros(Nat.sub(width, String.length(text))) ++ text

def pad(value: U32, width: Nat) -> String:
  padded(U32.show(value), width)

def civilIso(value: Calendar.CivilTime) -> String:
  match value:
    case Calendar.CivilTime{year, month, day, hour, minute, second, millisecond}:
      pad(year, 4n) ++ "-" ++ pad(month, 2n) ++ "-" ++ pad(day, 2n) ++ "T" ++ pad(hour, 2n) ++ ":" ++ pad(minute, 2n) ++ ":" ++ pad(second, 2n) ++ "." ++ pad(millisecond, 3n) ++ "Z"

def formattedCivil(result: Result<&2, &2, Calendar.Error, Calendar.CivilTime>) -> Maybe<&2, String>:
  match result:
    case Fail{_}: None{}
    case Done{value}: Some{civilIso(value)}

def exactWord(value: F64, word: W.U64, order: Maybe<&2, Cmp>) -> Maybe<&2, String>:
  match order:
    case Some{EQ{}}: formattedCivil(Calendar.fromEpochMilliseconds(word))
    case _: None{}

def formatIso(+value: F64) -> Maybe<&2, String>:
  +word = F.candidate(F.decode(value))
  exactWord(value, word, F.compare(value, F.fromU64(word)))
