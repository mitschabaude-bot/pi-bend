import Base
import ../packages/runtime/src/png.bend as Png
import ../packages/runtime/src/image.bend as Image
import ../packages/runtime/src/deflate-encode.bend as Deflate
import ../packages/runtime/src/string.bend as S
import ./aes128-gcm.bend as Bytes
import ./deflate-encode.bend as Inputs

def checksum(values: List<U32>, sum: U32) -> U32:
  match values:
    case Nil{}: sum
    case value <> rest: checksum(rest,(sum + value : U32))

def result(sum: U32, value: Result<&2,&2,Png.Error,List<&2,U32>>) -> String:
  match value:
    case Done{bytes}: "ok:" ++ U32.show(sum) ++ ":" ++ Bytes.show(bytes)
    case Fail{Png.OutputLimit{}}: "error:limit:" ++ U32.show(sum)
    case Fail{Png.Encoding{Deflate.OutputLimit{}}}: "error:limit:" ++ U32.show(sum)
    case Fail{Png.InvalidRaster{}}: "error:raster:" ++ U32.show(sum)
    case Fail{_}: "error:encoding:" ++ U32.show(sum)

def encoded(pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> String:
  match pair:
    case (image,value): result(checksum(Image.toPixels(image),0),value)

def samePixels(left: List<U32>, right: List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> rest b <> more: Bool.pick(Unit -> Bool,U32.is_eq(a,b),_ => samePixels(rest,more),_ => False{})(Unit{})
    case _ _: False{}

def roundtripDecoded(source: List<U32>, result: Result<&2,&1,Png.Error,Image.Raster>) -> String:
  match result:
    case Fail{_}: "roundtrip:error"
    case Done{image}: Bool.pick(String,samePixels(source,Image.toPixels(image)),"roundtrip:ok","roundtrip:different")

def roundtripPair(pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> String:
  match pair:
    case (Image.Raster{+width,+height,pixels},Done{bytes}): roundtripDecoded(Image.toPixels(Image.Raster{width,height,pixels}),Png.decode(bytes,U32.to_nat(width) * U32.to_nat(height)))
    case _: "roundtrip:error"

def imageDone(roundtrip: Bool, pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> String:
  match roundtrip:
    case False{}: encoded(pair)
    case True{}: roundtripPair(pair)

def image(roundtrip: Bool, +width: U32, +height: U32, limit: Nat, pixels: List<&2,U32>) -> String:
  match width:
    case 0: "invalid"
    case +width:
      imageDone(roundtrip,Png.encode(Image.Raster{width,height,Image.scatter(pixels,1,width,height,0,Array.new(U32,Image.depth(31n,(width * height : U32),1,0n),0))},limit))

def randomPixels(count: Nat, +state: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n:
      +a = U32.xor(state,U32.shln(state,13n))
      +b = U32.xor(a,U32.shrn(a,17n))
      +c = U32.xor(b,U32.shln(b,5n))
      randomPixels(n,c,c <> reversed)

def generated(roundtrip: Bool, mode: String, +width: U32, +height: U32, limit: Nat, value: U32) -> String:
  match mode:
    case "random": image(roundtrip,width,height,limit,randomPixels(U32.to_nat(width) * U32.to_nat(height),value,Nil{}))
    case _: image(roundtrip,width,height,limit,Inputs.repeat(U32.to_nat(width) * U32.to_nat(height),value <> Nil{},Nil{}))

def invalidPixel(width: U32, height: U32, result: Result<&2,&2,Png.Error,List<&2,U32>>, fetched: Array<U32> & U32) -> String:
  match result fetched:
    case Fail{Png.InvalidRaster{}} Tuple{_,value}: "invalid:" ++ U32.show(width) ++ ":" ++ U32.show(height) ++ ":" ++ U32.show(value)
    case _ _: "unexpected"

def invalidRetained(pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> String:
  match pair:
    case (Image.Raster{width,height,pixels},value): invalidPixel(width,height,value,Array.get(U32,pixels,0))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "roundtrip" <> "pixels" <> width <> height <> limit <> pixels <> Nil{}: image(True{},Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),Maybe.default(&2,Nat,Nat.read(limit),0n),Bytes.bytes(pixels))
    case "roundtrip" <> mode <> width <> height <> limit <> value <> Nil{}: generated(True{},mode,Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),Maybe.default(&2,Nat,Nat.read(limit),0n),Maybe.default(&2,U32,U32.read(value),0))
    case "invalid" <> width <> height <> Nil{}: invalidRetained(Png.encode(Image.Raster{Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),Array.new(U32,0n,16909060)},1000n))
    case "pixels" <> width <> height <> limit <> pixels <> Nil{}: image(False{},Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),Maybe.default(&2,Nat,Nat.read(limit),0n),Bytes.bytes(pixels))
    case mode <> width <> height <> limit <> value <> Nil{}: generated(False{},mode,Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),Maybe.default(&2,Nat,Nat.read(limit),0n),Maybe.default(&2,U32,U32.read(value),0))
    case _: "invalid"

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(S.split(head,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
