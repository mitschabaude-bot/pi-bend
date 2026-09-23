import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/webp.bend as WebP
import ../packages/runtime/src/image.bend as Image

def nibble(+char: Char) -> U32:
  +code = Char.to_u32(char)
  Bool.pick(U32,U32.is_le(code,57),(code - 48 : U32),(code - 87 : U32))

def decode(text: String, reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SCon{a,SCon{b,rest}}: decode(rest,(nibble(a) * 16 + nibble(b) : U32) <> reversed)
    case _: List.reverse(&2,U32,reversed)

def error(value: WebP.Error) -> String:
  match value:
    case WebP.Signature{}: "signature"
    case WebP.InvalidByte{}: "byte"
    case WebP.Truncated{}: "truncated"
    case WebP.PixelLimit{}: "limit"
    case WebP.Dimensions{}: "dimensions"
    case WebP.Header{}: "header"
    case WebP.Chunk{}: "chunk"
    case WebP.Alpha{}: "alpha"
    case WebP.LosslessError{_}: "lossless"
    case WebP.LossyError{_}: "lossy"

def shown(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ shown(rest)

def rendered(value: Result<&2,&1,WebP.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ shown(Image.toPixels(Image.Raster{width,height,pixels}))

def digest(values: List<U32>, hash: U32) -> U32:
  match values:
    case Nil{}: hash
    case value <> rest: digest(rest,U32.xor((hash * 16777619 : U32),value))

def summary(value: Result<&2,&1,WebP.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":hash:" ++ U32.show(digest(Image.toPixels(Image.Raster{width,height,pixels}),2166136261))

def run(text: String) -> String:
  match text:
    case SCon{'a',rest}: rendered(WebP.withAlpha(Some{decode(rest,Nil{})},1000000n,Image.Raster{3,2,Array.new(U32,3n,305420031)}))
    case "invalid": rendered(WebP.decode(66 <> 77 <> 256 <> Nil{},1000000n))
    case SCon{'#',rest}: summary(WebP.decode(decode(rest,Nil{}),1000000n))
    case SCon{'@',rest}: rendered(WebP.decode(decode(rest,Nil{}),1n))
    case value: rendered(WebP.decode(decode(value,Nil{}),1000000n))

def fileResult(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> String:
  match result:
    case Fail{_}: "file-error"
    case Done{bytes}: summary(WebP.decode(bytes,1000000n))

def argument(text: String) -> IO(Unit):
  match text:
    case SCon{'!',path}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        IO.print(fileResult(bytes))
    case value: IO.print(run(value))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        argument(value)
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
