import Base
import ../packages/runtime/src/jpeg.bend as Jpeg
import ../packages/runtime/src/image.bend as Raster
import ../packages/runtime/src/string.bend as S
import ./aes128-gcm.bend as Bytes

def error(value: Jpeg.Error) -> String:
  match value:
    case Jpeg.Signature{}: "signature"
    case Jpeg.InvalidByte{}: "byte"
    case Jpeg.Truncated{}: "truncated"
    case Jpeg.FrameHeader{}: "frame"
    case Jpeg.ScanHeader{}: "scan"
    case Jpeg.Quantization{}: "quantization"
    case Jpeg.InvalidHuffman{}: "huffman"
    case Jpeg.Entropy{}: "entropy"
    case Jpeg.Restart{}: "restart"
    case Jpeg.PixelLimit{}: "limit"
    case Jpeg.Unsupported{marker}: "unsupported " ++ U32.show(marker)

def numbers(values: List<U32>, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case value <> rest: numbers(rest,String.reverse(U32.show(value)) ++ "," ++ reversed)

def result(value: Result<&2,&1,Jpeg.Error,Raster.Raster>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{Raster.Raster{+width,+height,pixels}}:
      "ok " ++ U32.show(width) ++ "," ++ U32.show(height) ++ numbers(Raster.toPixels(Raster.Raster{width,height,pixels}),"")

def checksum(values: List<U32>, sum: U32) -> U32:
  match values:
    case Nil{}: sum
    case value <> rest: checksum(rest,(sum + value : U32))

def summary(value: Result<&2,&1,Jpeg.Error,Raster.Raster>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{Raster.Raster{+width,+height,pixels}}:
      "sum " ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(checksum(Raster.toPixels(Raster.Raster{width,height,pixels}),0))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "summary" <> limit <> bytes <> Nil{}: summary(Jpeg.decode(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case limit <> bytes <> Nil{}: result(Jpeg.decode(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
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
