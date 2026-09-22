import Base
import ../packages/runtime/src/jpeg-encode.bend as Jpeg
import ../packages/runtime/src/image.bend as Image
import ../packages/runtime/src/string.bend as S
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./aes128-gcm.bend as Hex

def samePixels(left: List<U32>, right: List<&2,U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> rest b <> more: Bool.pick(Unit -> Bool,U32.is_eq(a,b),_ => samePixels(rest,more),_ => False{})(Unit{})
    case _ _: False{}

def result(value: Result<&2,&2,Jpeg.Error,List<&2,U32>>) -> String:
  match value:
    case Done{bytes}: "ok:" ++ Hex.show(bytes)
    case Fail{Jpeg.InvalidDimensions{}}: "error:dimensions"
    case Fail{Jpeg.InvalidPixelCount{}}: "error:pixels"
    case Fail{Jpeg.InvalidQuality{}}: "error:quality"
    case Fail{Jpeg.OutputLimit{}}: "error:limit"

def encoded(expected: List<&2,U32>, pair: Image.Raster & Result<&2,&2,Jpeg.Error,List<&2,U32>>) -> String:
  match pair:
    case (image,value): Bool.pick(Result<&2,&2,Jpeg.Error,List<&2,U32>> -> String,samePixels(Image.toPixels(image),expected),result,_ => "corrupted raster")(value)

def image(+pixels: List<&2,U32>, width: U32, height: U32, quality: U32, limit: Nat, value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{_}: "invalid fixture"
    case Done{raster}: encoded(pixels,Jpeg.encode(raster,quality,limit))

def randomPixels(count: Nat, +state: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n:
      +a = U32.xor(state,U32.shln(state,13n))
      +b = U32.xor(a,U32.shrn(a,17n))
      +c = U32.xor(b,U32.shln(b,5n))
      randomPixels(n,c,c <> reversed)

def pixels(+values: List<&2,U32>, +width: U32, +height: U32, quality: U32, limit: Nat) -> String:
  image(values,width,height,quality,limit,Image.fromPixels(width,height,values))

def invalidRetained(width: U32, height: U32, value: Result<&2,&2,Jpeg.Error,List<&2,U32>>, fetched: Array<U32> & U32) -> String:
  match fetched:
    case (_,pixel): result(value) ++ ":" ++ U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ U32.show(pixel)

def invalid(pair: Image.Raster & Result<&2,&2,Jpeg.Error,List<&2,U32>>) -> String:
  match pair:
    case (Image.Raster{width,height,buffer},value): invalidRetained(width,height,value,Array.get(U32,buffer,0))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "pixels" <> width <> height <> quality <> limit <> values <> Nil{}:
      pixels(Wire.numbers(S.split(values,',')),Wire.decimal(width,0),Wire.decimal(height,0),Wire.decimal(quality,0),Maybe.default(&2,Nat,Nat.read(limit),0n))
    case "random" <> width <> height <> quality <> limit <> seed <> Nil{}:
      +w = Wire.decimal(width,0)
      +h = Wire.decimal(height,0)
      pixels(randomPixels(U32.to_nat(w) * U32.to_nat(h),Wire.decimal(seed,0),Nil{}),w,h,Wire.decimal(quality,0),Maybe.default(&2,Nat,Nat.read(limit),0n))
    case "invalid" <> width <> height <> quality <> limit <> Nil{}:
      invalid(Jpeg.encode(Image.Raster{Wire.decimal(width,0),Wire.decimal(height,0),Array.new(U32,0n,16909060)},Wire.decimal(quality,0),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case _: "invalid fixture arguments"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(S.split(value,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
