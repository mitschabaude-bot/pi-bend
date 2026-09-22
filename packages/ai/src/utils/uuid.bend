import Base
import ../../../runtime/src/u64.bend as W
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date

# Time-ordered UUIDv7 from a 48-bit millisecond timestamp and 74 random bits.
# The process-wide monotonic sequence of the upstream generator is not kept:
# every id draws fresh OS entropy, which the spec permits.

def hexDigit(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hexByte(+byte: U32) -> String:
  SCon{hexDigit(U32.shrn(byte, 4n)), SCon{hexDigit(U32.and(byte, 15)), SNil{}}}

def hex(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case byte <> rest: hexByte(byte) ++ hex(rest)

def timestampBytes(+high: U32, +low: U32) -> List<&2, U32>:
  [U32.and(U32.shrn(high, 8n), 255), U32.and(high, 255), U32.and(U32.shrn(low, 24n), 255), U32.and(U32.shrn(low, 16n), 255), U32.and(U32.shrn(low, 8n), 255), U32.and(low, 255)]

# bytes 6..15: version nibble 7 then 12 random bits, variant 10 then 62 random bits.
def layout(timestamp: List<&2, U32>, random: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match random:
    case r6 <> r7 <> r8 <> r9 <> r10 <> r11 <> r12 <> r13 <> r14 <> r15 <> Nil{}: Some{List.append(&2, U32, timestamp, [U32.or(112, U32.and(r6, 15)), r7, U32.or(128, U32.and(r8, 63)), r9, r10, r11, r12, r13, r14, r15])}
    case _: None{}

def formattedBytes(+bytes: List<&2, U32>) -> String:
  hex(List.take(&2, U32, bytes, 4n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 4n), 2n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 6n), 2n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 8n), 2n)) ++ "-" ++ hex(List.drop(&2, U32, bytes, 10n))

def formatted(bytes: List<&2, U32>) -> String: formattedBytes(bytes)

def uuidv7(timestamp: W.U64, random: List<&2, U32>) -> Maybe<&2, String>:
  match timestamp:
    case W.U64{high, low}: Maybe.map(&2, List<&2, U32>, String, formatted, layout(timestampBytes(U32.and(high, 65535), low), random))

def generated(timestamp: U32 & U32, random: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, String, String>:
  match timestamp random:
    case _ Fail{(_, message)}: Fail{"Could not obtain entropy for a UUID: " ++ message}
    case Tuple{high, low} Done{bytes}: Maybe.default(&2, Result<&2, &2, String, String>, Maybe.map(&2, String, Result<&2, &2, String, String>, value => Done{value}, uuidv7(W.U64{high, low}, bytes)), Fail{"Entropy source returned too few bytes for a UUID"})

def generate() -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    timestamp : U32 & U32 <- IO.unixMilliseconds()
    random : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(10)
    return generated(timestamp, random)
