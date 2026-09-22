import Base
import ../../../runtime/src/image.bend as Image

# Metadata parsing is bounded to its owning APP1/EXIF chunk. Image decoding and
# pixel permutations belong to codecs and the shared RGBA raster respectively.
type Error is Data:
  InvalidByte{}
  TruncatedContainer{}
  InvalidContainer{}
  InvalidTiff{}
  InvalidOrientation{}
  DuplicateOrientation{}
  Raster{cause: Image.Error}

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>

def length(bytes: List<&2,U32>, count: Nat) -> Parsed(Nat):
  match bytes:
    case Nil{}: Done{count}
    case byte <> +rest:
      Bool.pick(Unit -> Parsed(Nat),U32.is_le(byte,255),_ => length(rest,1n+count),_ => Fail{InvalidByte{}})(Unit{})

def word16(little: Bool, +a: U32, +b: U32) -> Nat:
  Bool.pick(Nat,little,U32.to_nat(a) + U32.to_nat(b) * 256n,U32.to_nat(a) * 256n + U32.to_nat(b))

def word32(little: Bool, +a: U32, +b: U32, +c: U32, +d: U32) -> Nat:
  Bool.pick(Nat,little,word16(True{},a,b) + word16(True{},c,d) * 65536n,word16(False{},a,b) * 65536n + word16(False{},c,d))

def drop(count: Nat, bytes: List<&2,U32>) -> Parsed(List<&2,U32>):
  match count bytes:
    case 0n rest: Done{rest}
    case 1n+n _ <> rest: drop(n,rest)
    case _ Nil{}: Fail{TruncatedContainer{}}

type Slice is Data:
  Slice{bytes: List<&2,U32>, rest: List<&2,U32>}

def take(count: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(Slice):
  match count bytes:
    case 0n rest: Done{Slice{List.reverse(&2,U32,reversed),rest}}
    case 1n+n byte <> rest: take(n,rest,byte <> reversed)
    case _ Nil{}: Fail{TruncatedContainer{}}

def bind(-A: Data, -B: Data, value: Parsed(A), next: A -> Parsed(B)) -> Parsed(B):
  match value:
    case Fail{error}: Fail{error}
    case Done{value}: next(value)

# Orientation is a single inline SHORT. Do not reinterpret malformed type/count
# fields, or normalize invalid orientation values to a plausible image rotation.
def collectOrientation(previous: Maybe<&2,U32>, valid: Bool, +value: Nat) -> Parsed(Maybe<&2,U32>):
  match previous valid:
    case Some{_} _: Fail{DuplicateOrientation{}}
    case None{} False{}: Fail{InvalidOrientation{}}
    case None{} True{}:
      Bool.pick(Parsed(Maybe<&2,U32>),Nat.is_ge(value,1n) && Nat.is_le(value,8n),Done{Some{U32.from_nat(value)}},Fail{InvalidOrientation{}})

def entry(+little: Bool, a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32, +previous: Maybe<&2,U32>) -> Parsed(Maybe<&2,U32>):
  Bool.pick(Unit -> Parsed(Maybe<&2,U32>),Nat.is_eq(word16(little,a,b),274n),
    _ => collectOrientation(previous,Nat.is_eq(word16(little,c,d),3n) && Nat.is_eq(word32(little,e,f,g,h),1n),word16(little,i,j)),
    _ => Done{previous})(Unit{})

def entries(count: Nat, +little: Bool, bytes: List<&2,U32>, found: Maybe<&2,U32>) -> Parsed(U32):
  match count bytes:
    case 0n _ <> _ <> _ <> _ <> _: Done{Maybe.default(&2,U32,found,1)}
    case 1n+n a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> _ <> _ <> rest:
      bind(Maybe<&2,U32>,U32,entry(little,a,b,c,d,e,f,g,h,i,j,found),value => entries(n,little,rest,value))
    case _ _: Fail{InvalidTiff{}}

def directory(+little: Bool, bytes: List<&2,U32>) -> Parsed(U32):
  match bytes:
    case a <> b <> rest: entries(word16(little,a,b),little,rest,None{})
    case _: Fail{InvalidTiff{}}

def atDirectory(little: Bool, value: Parsed(List<&2,U32>)) -> Parsed(U32):
  match value:
    case Fail{_}: Fail{InvalidTiff{}}
    case Done{bytes}: directory(little,bytes)

def offset(+little: Bool, +position: Nat, bytes: List<&2,U32>) -> Parsed(U32):
  Bool.pick(Unit -> Parsed(U32),Nat.is_eq(position,0n),_ => Done{1},
    _ => Bool.pick(Unit -> Parsed(U32),Nat.is_ge(position,8n),_ => atDirectory(little,drop(position - 8n,bytes)),_ => Fail{InvalidTiff{}})(Unit{}))(Unit{})

def tiff(bytes: List<&2,U32>) -> Parsed(U32):
  match bytes:
    case 73 <> 73 <> 42 <> 0 <> a <> b <> c <> d <> rest: offset(True{},word32(True{},a,b,c,d),rest)
    case 77 <> 77 <> 0 <> 42 <> a <> b <> c <> d <> rest: offset(False{},word32(False{},a,b,c,d),rest)
    case _: Fail{InvalidTiff{}}

type Step is Data:
  Next{bytes: List<&2,U32>}
  Finished{orientation: U32}

def found(value: Parsed(U32)) -> Parsed(Step):
  match value:
    case Fail{error}: Fail{error}
    case Done{orientation}: Done{Finished{orientation}}

def exif(value: Slice) -> Parsed(Step):
  match value:
    case Slice{69 <> 120 <> 105 <> 102 <> 0 <> 0 <> bytes,_}: found(tiff(bytes))
    case Slice{_,rest}: Done{Next{rest}}

def jpegSegment(+marker: U32, bytes: List<&2,U32>) -> Parsed(Step):
  match bytes:
    case a <> b <> +rest:
      +size = word16(False{},a,b)
      Bool.pick(Unit -> Parsed(Step),Nat.is_ge(size,2n),
        _ => Bool.pick(Unit -> Parsed(Step),U32.is_eq(marker,225),
          _ => bind(Slice,Step,take(size - 2n,rest,Nil{}),exif),
          _ => bind(List<&2,U32>,Step,drop(size - 2n,rest),tail => Done{Next{tail}}))(Unit{}),
        _ => Fail{InvalidContainer{}})(Unit{})
    case _: Fail{TruncatedContainer{}}

def jpegMarker(+marker: U32, +bytes: List<&2,U32>) -> Parsed(Step):
  Bool.pick(Unit -> Parsed(Step),U32.is_eq(marker,218) || U32.is_eq(marker,217),_ => Done{Finished{1}},
    _ => Bool.pick(Unit -> Parsed(Step),U32.is_eq(marker,255),_ => Done{Next{255 <> bytes}},
      _ => Bool.pick(Unit -> Parsed(Step),U32.is_eq(marker,1) || U32.is_eq(marker,216) || (U32.is_ge(marker,208) && U32.is_le(marker,215)),_ => Done{Next{bytes}},
        _ => Bool.pick(Unit -> Parsed(Step),U32.is_eq(marker,0),_ => Fail{InvalidContainer{}},_ => jpegSegment(marker,bytes))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def advance(value: Parsed(Step), next: List<&2,U32> -> Parsed(U32)) -> Parsed(U32):
  match value:
    case Fail{error}: Fail{error}
    case Done{Finished{orientation}}: Done{orientation}
    case Done{Next{bytes}}: next(bytes)

def jpeg(fuel: Nat, bytes: List<&2,U32>) -> Parsed(U32):
  match fuel bytes:
    case _ Nil{}: Done{1}
    case 1n+n 255 <> marker <> rest: advance(jpegMarker(marker,rest),tail => jpeg(n,tail))
    case _ _: Fail{InvalidContainer{}}

# WebP permits TIFF directly or the JPEG-style Exif\0\0 prefix.
def webpExif(bytes: List<&2,U32>) -> Parsed(U32):
  match bytes:
    case 69 <> 120 <> 105 <> 102 <> 0 <> 0 <> rest: tiff(rest)
    case values: tiff(values)

def webpFound(padding: Nat, value: Slice) -> Parsed(Step):
  match value:
    case Slice{bytes,rest}: bind(List<&2,U32>,Step,drop(padding,rest),_ => found(webpExif(bytes)))

def webpChunk(isExif: Bool, +size: Nat, bytes: List<&2,U32>) -> Parsed(Step):
  match isExif:
    case True{}: bind(Slice,Step,take(size,bytes,Nil{}),value => webpFound(Nat.mod(size,2n),value))
    case False{}: bind(List<&2,U32>,Step,drop(size + Nat.mod(size,2n),bytes),tail => Done{Next{tail}})

def webp(fuel: Nat, bytes: List<&2,U32>) -> Parsed(U32):
  match fuel bytes:
    case _ Nil{}: Done{1}
    case 1n+n a <> b <> c <> d <> e <> f <> g <> h <> rest:
      advance(webpChunk(U32.is_eq(a,69) && U32.is_eq(b,88) && U32.is_eq(c,73) && U32.is_eq(d,70),word32(True{},e,f,g,h),rest),tail => webp(n,tail))
    case _ _: Fail{TruncatedContainer{}}

def riffChunks(fuel: Nat, value: Slice) -> Parsed(U32):
  match value:
    case Slice{bytes,Nil{}}: webp(fuel,bytes)
    case _: Fail{InvalidContainer{}}

def riff(fuel: Nat, +size: Nat, bytes: List<&2,U32>) -> Parsed(U32):
  Bool.pick(Unit -> Parsed(U32),Nat.is_ge(size,4n),
    _ => bind(Slice,U32,take(size - 4n,bytes,Nil{}),value => riffChunks(fuel,value)),_ => Fail{InvalidContainer{}})(Unit{})

def recognized(fuel: Nat, bytes: List<&2,U32>) -> Parsed(U32):
  match bytes:
    case 255 <> 216 <> rest: jpeg(fuel,rest)
    case 82 <> 73 <> 70 <> 70 <> a <> b <> c <> d <> 87 <> 69 <> 66 <> 80 <> rest: riff(fuel,word32(True{},a,b,c,d),rest)
    case _: Done{1}

def getExifOrientation(+bytes: List<&2,U32>) -> Parsed(U32):
  bind(Nat,U32,length(bytes,0n),size => recognized(size,bytes))

def oriented(value: Result<&2,&1,Image.Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Done{image}: Done{image}
    case Fail{cause}: Fail{Raster{cause}}

def apply(image: Image.Raster, value: Parsed(U32)) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{error}: Fail{error}
    case Done{orientation}: oriented(Image.orient(orientation,image))

def applyExifOrientation(image: Image.Raster, originalBytes: List<&2,U32>) -> Result<&2,&1,Error,Image.Raster>:
  apply(image,getExifOrientation(originalBytes))
