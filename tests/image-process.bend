import Base
import ../packages/coding-agent/src/utils/image-process.bend as Images
import ../packages/coding-agent/src/utils/image-resize.bend as Resize
import ../packages/runtime/src/base64.bend as Base64
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/src/json.bend as Json

def quoted(hints: List<&2,String>) -> List<&2,String>:
  match hints:
    case Nil{}: Nil{}
    case hint <> rest: Json.quote(hint) <> quoted(rest)

def report(value: Images.ProcessImageResult) -> String:
  match value:
    case Images.Unsupported{message}: "{\"ok\":false,\"message\":" ++ Json.quote(message) ++ "}"
    case Images.Processed{data,mime,hints}: "{\"ok\":true,\"data\":" ++ Json.quote(data) ++ ",\"mimeType\":" ++ Json.quote(mime) ++ ",\"hints\":[" ++ String.join(quoted(hints),",") ++ "]}"

def processed(mime: String, options: Images.ProcessImageOptions, value: Result<&2,&2,Base64.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{bytes}: report(Images.processImage(bytes,mime,options))

def run(parts: List<&2,String>) -> String:
  match parts:
    case resize <> width <> height <> limit <> quality <> mime <> data <> Nil{}:
      processed(mime,Images.ProcessImageOptions{Some{Bool.not(String.eq(resize,"false"))},Some{Resize.ImageResizeOptions{U32.read(width),U32.read(height),Nat.read(limit),U32.read(quality)}}},Base64.decode(data))
    case "note" <> ow <> oh <> width <> height <> Nil{}:
      Json.quote(Maybe.default(&2,String,Resize.formatDimensionNote(Resize.ResizedImage{"","image/png",Maybe.default(&2,U32,U32.read(ow),0),Maybe.default(&2,U32,U32.read(oh),0),Maybe.default(&2,U32,U32.read(width),0),Maybe.default(&2,U32,U32.read(height),0),True{}}),"none"))
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
