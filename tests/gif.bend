import Base
import ../packages/runtime/src/gif.bend as Gif
import ../packages/runtime/src/image.bend as Image

def nibble(+char: Char) -> U32:
  +code = Char.to_u32(char)
  Bool.pick(U32,U32.is_le(code,57),(code - 48 : U32),(code - 87 : U32))

def decode(text: String, reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SCon{a,SCon{b,rest}}: decode(rest,(nibble(a) * 16 + nibble(b) : U32) <> reversed)
    case _: List.reverse(&2,U32,reversed)

def error(value: Gif.Error) -> String:
  match value:
    case Gif.Signature{}: "signature"
    case Gif.InvalidByte{}: "byte"
    case Gif.Truncated{}: "truncated"
    case Gif.Dimensions{}: "dimensions"
    case Gif.PixelLimit{}: "limit"
    case Gif.FrameBounds{}: "bounds"
    case Gif.Block{}: "block"
    case Gif.PaletteIndex{}: "palette"
    case Gif.CodeSize{}: "size"
    case Gif.InvalidCode{}: "code"
    case Gif.OutputLength{}: "length"
    case Gif.MissingEnd{}: "end"

def shown(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ shown(rest)

def rendered(value: Result<&2,&1,Gif.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ shown(Image.toPixels(Image.Raster{width,height,pixels}))

def digest(values: List<U32>, hash: U32) -> U32:
  match values:
    case Nil{}: hash
    case value <> rest: digest(rest,U32.xor((hash * 16777619 : U32),value))

def summary(value: Result<&2,&1,Gif.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":hash:" ++ U32.show(digest(Image.toPixels(Image.Raster{width,height,pixels}),2166136261))

def run(text: String) -> String:
  match text:
    case "invalid": rendered(Gif.decode(66 <> 77 <> 256 <> Nil{},1000000n))
    case SCon{'#',rest}: summary(Gif.decode(decode(rest,Nil{}),1000000n))
    case SCon{'@',rest}: rendered(Gif.decode(decode(rest,Nil{}),1n))
    case value: rendered(Gif.decode(decode(value,Nil{}),1000000n))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(value))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
