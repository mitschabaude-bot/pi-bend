import Base
import ../packages/runtime/src/png.bend as Png
import ../packages/runtime/src/image.bend as Raster
import ../packages/runtime/src/string.bend as S
import ./aes128-gcm.bend as Bytes

def error(value: Png.Error) -> String:
  match value:
    case Png.Signature{}: "signature"
    case Png.Truncated{}: "truncated"
    case Png.InvalidByte{}: "byte"
    case Png.ChunkLength{}: "length"
    case Png.ChunkType{}: "type"
    case Png.Crc{_}: "crc"
    case Png.InvalidHeader{}: "header"
    case Png.ChunkOrder{}: "order"
    case Png.Palette{}: "palette"
    case Png.Transparency{}: "transparency"
    case Png.CriticalChunk{_}: "critical"
    case Png.Compressed{_}: "compressed"
    case Png.Scanline{}: "scanline"
    case Png.Filter{}: "filter"
    case Png.PaletteIndex{}: "index"
    case Png.PixelLimit{}: "limit"
    case Png.InvalidRaster{}: "raster"
    case Png.OutputLimit{}: "output"
    case Png.Encoding{_}: "encoding"

def numbers(values: List<U32>, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case value <> rest: numbers(rest,String.reverse(U32.show(value)) ++ "," ++ reversed)

def result(value: Result<&2,&1,Png.Error,Raster.Raster>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{Raster.Raster{+width,+height,pixels}}:
      "ok " ++ U32.show(width) ++ "," ++ U32.show(height) ++ numbers(Raster.toPixels(Raster.Raster{width,height,pixels}),"")

def checksum(values: List<U32>, sum: U32) -> U32:
  match values:
    case Nil{}: sum
    case value <> rest: checksum(rest,(sum + value : U32))

def summary(value: Result<&2,&1,Png.Error,Raster.Raster>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{Raster.Raster{+width,+height,pixels}}:
      "sum " ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(checksum(Raster.toPixels(Raster.Raster{width,height,pixels}),0))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "summary" <> limit <> bytes <> Nil{}: summary(Png.decode(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case limit <> bytes <> Nil{}: result(Png.decode(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
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
