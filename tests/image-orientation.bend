import Base
import ../packages/runtime/src/image.bend as Image
import ../packages/runtime/src/string.bend as Strings

def makePixels(count: Nat, +index: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n: makePixels(n,(index + 1 : U32),(index * 2654435761 : U32) <> reversed)

def error(cause: Image.Error) -> String:
  match cause:
    case Image.InvalidDimensions{}: "dimensions"
    case Image.InvalidPixelCount{}: "pixels"
    case Image.InvalidOrientation{}: "orientation"

def shown(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ shown(rest)

def result(value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ shown(Image.toPixels(Image.Raster{width,height,pixels}))

def oriented(orientation: U32, value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{image}: result(Image.orient(orientation,image))

def number(text: String) -> U32: U32.from_nat(Maybe.default(&2,Nat,Nat.read(text),0n))

def sized(+width: U32, +height: U32, orientation: U32) -> String:
  oriented(orientation,Image.fromPixels(width,height,makePixels(U32.to_nat(width) * U32.to_nat(height),0,Nil{})))

def digest(values: List<U32>, hash: U32) -> U32:
  match values:
    case Nil{}: hash
    case value <> rest: digest(rest,U32.xor((hash * 16777619 : U32),value))

def summary(value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{Image.Raster{+width,+height,pixels}}:
      U32.show(width) ++ ":" ++ U32.show(height) ++ ":hash:" ++ U32.show(digest(Image.toPixels(Image.Raster{width,height,pixels}),2166136261))

def large(value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{cause}: "error:" ++ error(cause)
    case Done{image}: summary(Image.orient(6,image))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "large" <> Nil{}: large(Image.fromPixels(300,257,makePixels(77100n,0,Nil{})))
    case "short" <> Nil{}: result(Image.fromPixels(2,2,0 <> Nil{}))
    case "overflow" <> Nil{}: result(Image.fromPixels(4294967295,4294967295,Nil{}))
    case "capacity" <> Nil{}: result(Image.orient(6,Image.Raster{3,3,Array.new(U32,0n,0)}))
    case width <> height <> orientation <> Nil{}: sized(number(width),number(height),number(orientation))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(value,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
