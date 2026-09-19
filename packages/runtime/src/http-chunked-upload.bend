import Base
import ./big-nat.bend as N
import ./http-buffered-body.bend as Body

# Buffered bodies can use a single chunk. Chunk size counts payload bytes;
# framing delimiters are separate, and an empty body is only the terminator.
def digit(+value: U32) -> U32:
  Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32))

def limb(+value: U32, tail: List<&2, U32>) -> List<&2, U32>:
  digit(U32.and(U32.shrn(value, 12n), 15)) <> digit(U32.and(U32.shrn(value, 8n), 15)) <> digit(U32.and(U32.shrn(value, 4n), 15)) <> digit(U32.and(value, 15)) <> tail

def hexLimbs(values: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: tail
    case value <> rest: hexLimbs(rest, limb(value, tail))

def trim(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: 48 <> Nil{}
    case 48 <> rest: trim(rest)
    case byte <> rest: byte <> rest

def hexadecimal(length: N.BigNat) -> List<&2, U32>:
  match length:
    case N.BigNat{limbs}: trim(hexLimbs(limbs, Nil{}))

def end() -> List<&2, U32>: 48 <> 13 <> 10 <> 13 <> 10 <> Nil{}

def payload(empty: Bool, bytes: List<&2, U32>, length: N.BigNat) -> List<&2, U32>:
  match empty:
    case True{}: end()
    case False{}: List.append(&2, U32, hexadecimal(length), 13 <> 10 <> List.append(&2, U32, bytes, 13 <> 10 <> end()))

# Content comes from buffered-body preparation, which validates each byte and
# computes its immutable length. The result materializes the framed wire bytes;
# the request plan retains the entity content separately for retries.
def encode(content: Body.Content) -> List<&2, U32>:
  match content:
    case Body.Content{bytes, +length}: payload(N.isZero(length), bytes, length)
