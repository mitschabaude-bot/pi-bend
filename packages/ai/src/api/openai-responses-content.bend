import Base
import ../types.bend as T
import ../utils/sanitize-unicode.bend as Unicode
import ./transform-messages.bend as Transform
import ../../../runtime/src/record.bend as R

# Provider wire content remains typed until the explicit JSON boundary. The
# discriminator and fixed image detail are supplied by the constructors.
type ResponseInputContent is Data:
  ResponseInputText{text: String}
  ResponseInputImage{imageUrl: String}

type ToolResultOutput is Data:
  TextOutput{text: String}
  ContentOutput{content: List<&2, ResponseInputContent>}

type UserInput is Data:
  UserInput{content: List<&2, ResponseInputContent>}

def image(image: T.ImageContent) -> ResponseInputContent:
  match image:
    case T.ImageContent{data, mimeType}: ResponseInputImage{"data:" ++ mimeType ++ ";base64," ++ data}

def textParts(content: List<&2, T.TextImageContent>) -> List<&2, String>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> textParts(rest)
    case _ <> rest: textParts(rest)

def images(content: List<&2, T.TextImageContent>) -> List<&2, ResponseInputContent>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageImage{value} <> rest: image(value) <> images(rest)
    case _ <> rest: images(rest)

def toolOutput(vision: Bool, +text: String, images: List<&2, ResponseInputContent>) -> ToolResultOutput:
  match vision images:
    case _ Nil{}: TextOutput{Unicode.sanitizeSurrogates(Bool.pick(String, String.is_empty(text), "(no tool output)", text))}
    case False{} _ <> _: TextOutput{Unicode.sanitizeSurrogates(Bool.pick(String, String.is_empty(text), "(see attached image)", text))}
    case True{} +head <> +rest:
      ContentOutput{Bool.pick(List<&2, ResponseInputContent>, String.is_empty(text), head <> rest, ResponseInputText{Unicode.sanitizeSurrogates(text)} <> head <> rest)}

def convertToolResultOutput(-J: Data, model: T.Model<J>, +content: List<&2, T.TextImageContent>) -> ToolResultOutput:
  toolOutput(Transform.imageCapability(J, model), String.join(textParts(content), "\n"), images(content))

def userBlocks(content: List<&2, T.TextImageContent>) -> List<&2, ResponseInputContent>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: ResponseInputText{Unicode.sanitizeSurrogates(text)} <> userBlocks(rest)
    case T.TextImageImage{value} <> rest: image(value) <> userBlocks(rest)

# A plain empty string still becomes one text block. An empty block list omits
# the user message entirely, matching the provider conversion's continue path.
def convertUserContent(content: T.UserContent) -> Maybe<&2, UserInput>:
  match content:
    case T.UserText{text}: Some{UserInput{ResponseInputText{Unicode.sanitizeSurrogates(text)} <> Nil{}}}
    case T.UserBlocks{Nil{}}: None{}
    case T.UserBlocks{head <> rest}: Some{UserInput{userBlocks(head <> rest)}}

def contentToJson(content: ResponseInputContent) -> T.JsonValue:
  match content:
    case ResponseInputText{text}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"input_text"}} <> R.Property{"text", T.JsonString{text}} <> Nil{}}}
    case ResponseInputImage{url}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"input_image"}} <> R.Property{"detail", T.JsonString{"auto"}} <> R.Property{"image_url", T.JsonString{url}} <> Nil{}}}

def contentsToJson(content: List<&2, ResponseInputContent>) -> List<&2, T.JsonValue>:
  match content:
    case Nil{}: Nil{}
    case head <> rest: contentToJson(head) <> contentsToJson(rest)

def outputToJson(output: ToolResultOutput) -> T.JsonValue:
  match output:
    case TextOutput{text}: T.JsonString{text}
    case ContentOutput{content}: T.JsonArray{contentsToJson(content)}

def userToJson(user: UserInput) -> T.JsonValue:
  match user:
    case UserInput{content}: T.JsonObject{R.Record{R.Property{"role", T.JsonString{"user"}} <> R.Property{"content", T.JsonArray{contentsToJson(content)}} <> Nil{}}}
