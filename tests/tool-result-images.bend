import Base
import ../packages/coding-agent/src/utils/tool-result-images.bend as Images
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

# tool-result-images.test.ts: arguments are an auto-resize mode ("default"
# or "false") and one JSON array of content blocks; the output is
# {"unchanged":true} or the normalized blocks. tests/tool_result_images_check.py
# builds the images and asserts upstream's expectations.

def text(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{found}}: found
    case _: ""

def block(value: V.Value) -> Ai.TextImageContent:
  match value:
    case V.ObjectValue{+fields}:
      Bool.pick(Ai.TextImageContent, String.eq(text(R.get(V.Value, fields, "type")), "image"), Ai.TextImageImage{Ai.ImageContent{text(R.get(V.Value, fields, "data")), text(R.get(V.Value, fields, "mimeType"))}}, Ai.TextImageText{Ai.TextContent{text(R.get(V.Value, fields, "text")), None{}}})
    case _: Ai.TextImageText{Ai.TextContent{"", None{}}}

def blockList(items: List<&2, V.Value>) -> List<&2, Ai.TextImageContent>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: block(item) <> blockList(rest)

def blocks(value: Result<&2, &2, Json.ParseError, V.Value>) -> List<&2, Ai.TextImageContent>:
  match value:
    case Done{V.ArrayValue{items}}: blockList(items)
    case _: Nil{}

def rendered(value: Ai.TextImageContent) -> String:
  match value:
    case Ai.TextImageText{Ai.TextContent{found, _}}: "{\"type\":\"text\",\"text\":" ++ Json.quote(found) ++ "}"
    case Ai.TextImageImage{Ai.ImageContent{data, mime}}: "{\"type\":\"image\",\"data\":" ++ Json.quote(data) ++ ",\"mimeType\":" ++ Json.quote(mime) ++ "}"

def renderedAll(values: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: rendered(value) <> renderedAll(rest)

def report(result: Maybe<&2, List<&2, Ai.TextImageContent>>) -> String:
  match result:
    case None{}: "{\"unchanged\":true}"
    case Some{values}: "{\"content\":[" ++ String.join(renderedAll(values), ",") ++ "]}"

def options(mode: String) -> Images.NormalizeToolResultImagesOptions:
  Bool.pick(Images.NormalizeToolResultImagesOptions, String.eq(mode, "false"), Images.NormalizeToolResultImagesOptions{Some{False{}}, None{}}, Images.defaults())

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> content <> Nil{}: IO.print(report(Images.normalizeToolResultImages(blocks(Json.parse(content)), options(mode))))
    case _: IO.die(Unit, 1, "expected mode and JSON content")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
