import Base
import ../types.bend as Ai

# Shared provider transcript preparation. Each stage returns immutable typed
# messages; JSON serialization belongs to the individual provider boundary.
def userImagePlaceholder() -> String: "(image omitted: model does not support images)"
def toolImagePlaceholder() -> String: "(tool image omitted: model does not support images)"

def replaceImages(content: List<&2, Ai.TextImageContent>, previousWasPlaceholder: Bool, +placeholder: String) -> List<&2, Ai.TextImageContent>:
  match content:
    case Nil{}: Nil{}
    case Ai.TextImageImage{_} <> rest:
      +tail = replaceImages(rest, True{}, placeholder)
      Bool.pick(List<&2, Ai.TextImageContent>, previousWasPlaceholder, tail, Ai.TextImageText{Ai.TextContent{placeholder, None{}}} <> tail)
    case Ai.TextImageText{Ai.TextContent{+text, signature}} <> rest:
      Ai.TextImageText{Ai.TextContent{text, signature}} <> replaceImages(rest, String.eq(text, placeholder), placeholder)

def replaceImagesWithPlaceholder(content: List<&2, Ai.TextImageContent>, placeholder: String) -> List<&2, Ai.TextImageContent>:
  replaceImages(content, False{}, placeholder)

def userContent(content: Ai.UserContent) -> Ai.UserContent:
  match content:
    case Ai.UserText{text}: Ai.UserText{text}
    case Ai.UserBlocks{blocks}: Ai.UserBlocks{replaceImagesWithPlaceholder(blocks, userImagePlaceholder())}

def downgradeMessage(-P: Data, -A: Data, -G: Data, -D: Data, message: Ai.Message<P, A, G, D>) -> Ai.Message<P, A, G, D>:
  match message:
    case Ai.User{Ai.UserMessage{content, timestamp}}: Ai.User{Ai.UserMessage{userContent(content), timestamp}}
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, content, details, usage, isError, timestamp}}:
      Ai.ToolResult{Ai.ToolResultMessage{id, name, replaceImagesWithPlaceholder(content, toolImagePlaceholder()), details, usage, isError, timestamp}}
    case other: other

def downgradeMessages(-P: Data, -A: Data, -G: Data, -D: Data, messages: List<&2, Ai.Message<P, A, G, D>>) -> List<&2, Ai.Message<P, A, G, D>>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: downgradeMessage(P, A, G, D, message) <> downgradeMessages(P, A, G, D, rest)

def supportsImages(input: List<&2, Ai.ModelInput>) -> Bool:
  match input:
    case Nil{}: False{}
    case Ai.InputImage{} <> _: True{}
    case _ <> rest: supportsImages(rest)

def imageCapability(-J: Data, model: Ai.Model<J>) -> Bool:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, input, _, _, _, _, _, _}: supportsImages(input)

def downgradeSelected(-P: Data, -A: Data, -G: Data, -D: Data, enabled: Bool, messages: List<&2, Ai.Message<P, A, G, D>>) -> List<&2, Ai.Message<P, A, G, D>>:
  match enabled:
    case True{}: messages
    case False{}: downgradeMessages(P, A, G, D, messages)

def downgradeUnsupportedImages(-P: Data, -A: Data, -G: Data, -D: Data, -J: Data, messages: List<&2, Ai.Message<P, A, G, D>>, model: Ai.Model<J>) -> List<&2, Ai.Message<P, A, G, D>>:
  downgradeSelected(P, A, G, D, imageCapability(J, model), messages)
