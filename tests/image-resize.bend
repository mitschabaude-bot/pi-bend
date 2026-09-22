import Base
import ../packages/runtime/src/image.bend as Image
import ../packages/runtime/src/image-resize.bend as Resize
import ../packages/runtime/src/string.bend as Strings
import ./image-orientation.bend as Pixels

def resized(value: Result<&2,&1,Resize.Error,Image.Raster>) -> String:
  match value:
    case Fail{Resize.InvalidImage{_}}: "image"
    case Fail{Resize.InvalidDimensions{}}: "dimensions"
    case Fail{Resize.PixelLimit{}}: "limit"
    case Done{image}: Pixels.result(Done{image})

def created(width: U32, height: U32, limit: Nat, value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{_}: "image"
    case Done{image}: resized(Resize.resize(image,width,height,limit))

def run(+width: U32, +height: U32, targetWidth: U32, targetHeight: U32, limit: Nat) -> String:
  created(targetWidth,targetHeight,limit,Image.fromPixels(width,height,Pixels.makePixels(U32.to_nat(width) * U32.to_nat(height),0,Nil{})))

def summary(result: Result<&2,&1,Resize.Error,Image.Raster>) -> String:
  match result:
    case Fail{_}: "failed"
    case Done{raster}: Pixels.summary(Done{raster})

def summarized(width: U32, height: U32, value: Result<&2,&1,Image.Error,Image.Raster>) -> String:
  match value:
    case Fail{_}: "image"
    case Done{image}:
      summary(Resize.resize(image,width,height,10000000n))

def request(parts: List<&2,String>) -> String:
  match parts:
    case "bench" <> Nil{}: summarized(512,512,Image.fromPixels(1024,1024,Pixels.makePixels(1048576n,0,Nil{})))
    case width <> height <> targetWidth <> targetHeight <> limit <> Nil{}:
      run(Pixels.number(width),Pixels.number(height),Pixels.number(targetWidth),Pixels.number(targetHeight),Maybe.default(&2,Nat,Nat.read(limit),0n))
    case "invalid" <> Nil{}: resized(Resize.resize(Image.Raster{3,3,Array.new(U32,0n,0)},2,2,100n))
    case _: "invalid request"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(request(Strings.split(value,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
