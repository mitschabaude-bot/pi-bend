import Base
import ../packages/coding-agent/src/utils/exif-orientation.bend as Exif
import ../packages/runtime/src/image.bend as Image

def nibble(+char: Char) -> U32:
  +code = Char.to_u32(char)
  Bool.pick(U32,U32.is_le(code,57),(code - 48 : U32),(code - 87 : U32))

def decode(text: String, reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SCon{a,SCon{b,rest}}: decode(rest,(nibble(a) * 16 + nibble(b) : U32) <> reversed)
    case _: List.reverse(&2,U32,reversed)

def error(value: Exif.Error) -> String:
  match value:
    case Exif.InvalidByte{}: "byte"
    case Exif.TruncatedContainer{}: "truncated"
    case Exif.InvalidContainer{}: "container"
    case Exif.InvalidTiff{}: "tiff"
    case Exif.InvalidOrientation{}: "orientation"
    case Exif.DuplicateOrientation{}: "duplicate"
    case Exif.Raster{_}: "raster"

def parsed(value: Exif.Parsed(U32)) -> String:
  match value:
    case Done{value}: U32.show(value)
    case Fail{cause}: "error:" ++ error(cause)

def shown(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ shown(rest)

def rendered(value: Result<&2,&1,Exif.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ shown(Image.toPixels(Image.Raster{width,height,pixels}))

def applied(bytes: List<&2,U32>, image: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match image:
    case Fail{_}: "fixture-error"
    case Done{image}: rendered(Exif.applyExifOrientation(image,bytes))

def run(text: String) -> String:
  match text:
    case "invalid": parsed(Exif.getExifOrientation(256 <> Nil{}))
    case "invalid-tail": parsed(Exif.getExifOrientation(255 <> 216 <> 255 <> 217 <> 4294967295 <> Nil{}))
    case SCon{'@',rest}: applied(decode(rest,Nil{}),Image.fromPixels(3,2,16909060 <> 84281096 <> 151653132 <> 219025168 <> 286397204 <> 353769240 <> Nil{}))
    case value: parsed(Exif.getExifOrientation(decode(value,Nil{})))

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
