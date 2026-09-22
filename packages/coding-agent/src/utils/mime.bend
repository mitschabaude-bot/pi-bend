import Base
import ../../../runtime/src/filesystem.bend as FS

# File byte primitives use U32 lists. Reject out-of-range values rather than
# silently wrapping them as a JavaScript Uint8Array constructor would.
def validBytes(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> +rest:
      Bool.pick(Unit -> Bool,U32.is_le(byte,255),unused => validBytes(rest),unused => False{})(Unit{})

def be32(a: U32, b: U32, c: U32, d: U32) -> Nat:
  U32.to_nat(a) * 16777216n + U32.to_nat(b) * 65536n + U32.to_nat(c) * 256n + U32.to_nat(d)

def le16(a: U32, b: U32) -> Nat:
  U32.to_nat(a) + U32.to_nat(b) * 256n

# Scan only forward: each chunk header consumes eight bytes, then skip its
# payload and CRC. acTL before IDAT marks animation, even with a partial body.
# Like Pi, truncated later chunks do not invalidate an otherwise recognized PNG.
def animated(bytes: List<&2,U32>, skip: Nat) -> Bool:
  match bytes skip:
    case _ <> rest 1n+remaining: animated(rest,remaining)
    case a <> b <> c <> d <> +t0 <> +t1 <> +t2 <> +t3 <> +rest 0n:
      +control = U32.is_eq(t0,97) && U32.is_eq(t1,99) && U32.is_eq(t2,84) && U32.is_eq(t3,76)
      +image = U32.is_eq(t0,73) && U32.is_eq(t1,68) && U32.is_eq(t2,65) && U32.is_eq(t3,84)
      Bool.pick(Unit -> Bool,control,unused => True{},
        unused => Bool.pick(Unit -> Bool,image,unused => False{},unused => animated(rest,be32(a,b,c,d) + 4n))(Unit{}))(Unit{})
    case _ _: False{}

def png(bytes: List<&2,U32>) -> Maybe<&2,String>:
  match bytes:
    case 0 <> 0 <> 0 <> 13 <> 73 <> 72 <> 68 <> 82 <> +rest:
      Bool.pick(Maybe<&2,String>,animated(0 <> 0 <> 0 <> 13 <> 73 <> 72 <> 68 <> 82 <> rest,0n),None{},Some{"image/png"})
    case _: None{}

def depth(bits: Nat) -> Bool:
  match bits:
    case 1n: True{}
    case 4n: True{}
    case 8n: True{}
    case 16n: True{}
    case 24n: True{}
    case 32n: True{}
    case _: False{}

def planes(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case 1 <> 0 <> a <> b <> _: depth(le16(a,b))
    case _: False{}

# bytes begins at offset 18, immediately after the DIB size word.
def dib(+size: Nat, bytes: List<&2,U32>) -> Bool:
  match bytes:
    case _ <> _ <> _ <> _ <> +rest:
      Bool.pick(Unit -> Bool,Nat.is_eq(size,12n),unused => planes(rest),
        unused => Nat.is_ge(size,40n) && Nat.is_le(size,124n) && planes(List.drop(&2,U32,rest,4n)))(Unit{})
    case _: False{}

# bytes begins after BM. The reserved fields are intentionally ignored, as in
# Pi; recognition is a header sniff, not full image validation or decoding.
def bmp(bytes: List<&2,U32>) -> Maybe<&2,String>:
  match bytes:
    case f0 <> f1 <> f2 <> f3 <> _ <> _ <> _ <> _ <> p0 <> p1 <> p2 <> p3 <> h0 <> h1 <> h2 <> h3 <> +rest:
      +fileSize = be32(f3,f2,f1,f0)
      +pixels = be32(p3,p2,p1,p0)
      +header = be32(h3,h2,h1,h0)
      valid = (Nat.is_eq(fileSize,0n) || Nat.is_ge(fileSize,26n)) && Nat.is_ge(pixels,14n + header) &&
        (Nat.is_eq(fileSize,0n) || Nat.is_lt(pixels,fileSize)) && dib(header,rest)
      Bool.pick(Maybe<&2,String>,valid,Some{"image/bmp"},None{})
    case _: None{}

def jpeg(bytes: List<&2,U32>) -> Maybe<&2,String>:
  match bytes:
    case 247 <> _: None{}
    case _: Some{"image/jpeg"}

def recognized(bytes: List<&2,U32>) -> Maybe<&2,String>:
  match bytes:
    case 255 <> 216 <> 255 <> rest: jpeg(rest)
    case 137 <> 80 <> 78 <> 71 <> 13 <> 10 <> 26 <> 10 <> rest: png(rest)
    case 71 <> 73 <> 70 <> _: Some{"image/gif"}
    case 82 <> 73 <> 70 <> 70 <> _ <> _ <> _ <> _ <> 87 <> 69 <> 66 <> 80 <> _: Some{"image/webp"}
    case 66 <> 77 <> rest: bmp(rest)
    case _: None{}

def detectSupportedImageMimeType(+buffer: List<&2,U32>) -> Maybe<&2,String>:
  Bool.pick(Unit -> Maybe<&2,String>,validBytes(buffer),unused => recognized(buffer),unused => None{})(Unit{})

def detectSupportedImageMimeTypeFromFile(path: String) -> IO(Result<&2, &2, FS.Error, Maybe<&2, String>>):
  do IO<Result<&2, &2, FS.Error, Maybe<&2, String>>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readPrefix(path, 4100)
    return Result.map(&2, &2, FS.Error, List<&2, U32>, Maybe<&2, String>, value => detectSupportedImageMimeType(value), bytes)
