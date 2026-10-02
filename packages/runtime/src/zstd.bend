import Base

# A standards-compliant Zstandard frame writer for HTTP request bodies. It
# emits independent raw blocks: this keeps framing small and deterministic,
# while leaving entropy compression as a separate optimization.
type Error is Data:
  InvalidByte{}
  InputLimit{}

def inputSize(bytes: List<&2, U32>, +count: U32) -> Result<&2, &2, Error, U32>:
  match bytes:
    case Nil{}: Done{count}
    case byte <> rest:
      Bool.pick(Unit -> Result<&2, &2, Error, U32>, U32.is_gt(byte, 255), _ => Fail{InvalidByte{}}, _ =>
        Bool.pick(Unit -> Result<&2, &2, Error, U32>, U32.is_eq(count, 4294967295), _ => Fail{InputLimit{}}, _ => inputSize(rest, (count + 1 : U32)))(Unit{}))(Unit{})

def little16(+value: U32) -> List<&2, U32>:
  U32.and(value, 255) <> U32.and(U32.shrn(value, 8n), 255) <> Nil{}

def little32(+value: U32) -> List<&2, U32>:
  U32.and(value, 255) <> U32.and(U32.shrn(value, 8n), 255) <> U32.and(U32.shrn(value, 16n), 255) <> U32.shrn(value, 24n) <> Nil{}

# Single-segment frames carry their exact content size and need no window
# descriptor. Two-byte sizes use Zstandard's required 256-byte bias.
def frameHeader(+size: U32) -> List<&2, U32>:
  +magic = {40 <> 181 <> 47 <> 253 <> Nil{} : List<&2, U32>}
  Bool.pick(List<&2, U32>, U32.is_lt(size, 256), List.append(&2, U32, magic, 32 <> size <> Nil{}),
    Bool.pick(List<&2, U32>, U32.is_le(size, 65791), List.append(&2, U32, magic, 96 <> little16((size - 256 : U32))), List.append(&2, U32, magic, 160 <> little32(size))))

def blockHeader(+size: U32, last: Bool) -> List<&2, U32>:
  +value = {U32.or(U32.shln(size, 3n), Bool.pick(U32, last, 1, 0)) : U32}
  U32.and(value, 255) <> U32.and(U32.shrn(value, 8n), 255) <> U32.and(U32.shrn(value, 16n), 255) <> Nil{}

# Each recursive step removes exactly 131071 bytes; the checker cannot see the
# decrease through List.drop plus U32 subtraction.
@unsafe
def blocks(+bytes: List<&2, U32>, +size: U32) -> List<&2, U32>:
  Bool.pick(Unit -> List<&2, U32>, U32.is_le(size, 131071), _ => List.append(&2, U32, blockHeader(size, True{}), bytes), _ =>
    List.append(&2, U32, blockHeader(131071, False{}), List.append(&2, U32, List.take(&2, U32, bytes, 131071n), blocks(List.drop(&2, U32, bytes, 131071n), (size - 131071 : U32)))))(Unit{})

def framed(+bytes: List<&2, U32>, result: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{+size}: Done{List.append(&2, U32, frameHeader(size), blocks(bytes, size))}

def encode(+bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  framed(bytes, inputSize(bytes, 0))
