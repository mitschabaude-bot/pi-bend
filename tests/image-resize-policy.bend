import Base
import ../packages/coding-agent/src/utils/image-resize.bend as Resize
import ../packages/runtime/src/base64.bend as Base64
import ../packages/runtime/src/string.bend as Strings

def show(value: Maybe<&2,Resize.ResizedImage>) -> String:
  match value:
    case None{}: "none"
    case Some{Resize.ResizedImage{data,mime,ow,oh,w,h,changed}}:
      mime ++ ":" ++ U32.show(ow) ++ ":" ++ U32.show(oh) ++ ":" ++ U32.show(w) ++ ":" ++ U32.show(h) ++ ":" ++ Bool.pick(String,changed,"true","false") ++ ":" ++ data

def decoded(mime: String, options: Resize.ImageResizeOptions, value: Result<&2,&2,Base64.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{_}: "none"
    case Done{bytes}: show(Resize.resizeImageInProcess(bytes,mime,options))

def run(parts: List<&2,String>) -> String:
  match parts:
    case width <> height <> bytes <> quality <> mime <> data <> Nil{}:
      decoded(mime,Resize.ImageResizeOptions{U32.read(width),U32.read(height),Nat.read(bytes),U32.read(quality)},Base64.decode(data))
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
