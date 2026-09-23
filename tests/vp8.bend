import Base
import ../packages/runtime/src/vp8.bend as Vp8
import ../packages/runtime/src/image.bend as Image
import ../packages/runtime/src/string.bend as S
import ../packages/runtime/test/utf8-runner.bend as Wire

def values(pixels: List<U32>) -> String:
  match pixels:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ values(rest)

def result(value: Result<&2,&1,Vp8.Error,Image.Raster>) -> String:
  match value:
    case Done{raster}:
      "ok:" ++ values(Image.toPixels(raster))
    case Fail{Vp8.InvalidByte{}}: "error:byte"
    case Fail{Vp8.Truncated{}}: "error:truncated"
    case Fail{Vp8.Signature{}}: "error:signature"
    case Fail{Vp8.Interframe{}}: "error:interframe"
    case Fail{Vp8.Dimensions{}}: "error:dimensions"
    case Fail{Vp8.PixelLimit{}}: "error:limit"
    case Fail{Vp8.ColorSpace{}}: "error:color"
    case Fail{Vp8.Partition{}}: "error:partition"
    case Fail{Vp8.UnsupportedVersion{}}: "error:version"
    case Fail{Vp8.HiddenFrame{}}: "error:hidden"

def describe(header: Vp8.Parsed(Vp8.Header)) -> String:
  match header:
    case Done{Vp8.Header{_,_,Vp8.Parameters{Vp8.Features{enabled,_,_,_,_,_},simple,_,_,_,count,_,_,_},_,_}}:
      U32.show(count) ++ ":" ++ U32.show(Bool.pick(U32,simple,1,0)) ++ ":" ++ U32.show(Bool.pick(U32,enabled,1,0))
    case Fail{_}: "error:header"

def run(parts: List<&2,String>) -> String:
  match parts:
    case "header" <> bytes <> Nil{}: describe(Vp8.frameHeader(Wire.numbers(S.split(bytes,',')),100000000n))
    case limit <> bytes <> Nil{}: result(Vp8.decode(Wire.numbers(S.split(bytes,',')),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case _: "invalid fixture"

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
