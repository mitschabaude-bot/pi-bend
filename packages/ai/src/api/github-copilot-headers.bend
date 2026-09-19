import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R

def initiator(-P: Data, -A: Data, -D: Data, -U: Data, message: T.Message<P, A, D, U>) -> String:
  match message:
    case T.User{_}: "user"
    case _: "agent"

def inferCopilotInitiator(-P: Data, -A: Data, -D: Data, -U: Data, messages: List<&2, T.Message<P, A, D, U>>) -> String:
  match messages:
    case Nil{}: "user"
    case last <> Nil{}: initiator(P, A, D, U, last)
    case _ <> rest: inferCopilotInitiator(P, A, D, U, rest)

def imageBlocks(blocks: List<&2, T.TextImageContent>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case T.TextImageImage{_} <> _: True{}
    case _ <> rest: imageBlocks(rest)

def userImages(content: T.UserContent) -> Bool:
  match content:
    case T.UserText{_}: False{}
    case T.UserBlocks{blocks}: imageBlocks(blocks)

def messageImages(-P: Data, -A: Data, -D: Data, -U: Data, message: T.Message<P, A, D, U>) -> Bool:
  match message:
    case T.User{T.UserMessage{content, _}}: userImages(content)
    case T.ToolResult{T.ToolResultMessage{_, _, content, _, _, _, _}}: imageBlocks(content)
    case _: False{}

def hasCopilotVisionInput(-P: Data, -A: Data, -D: Data, -U: Data, messages: List<&2, T.Message<P, A, D, U>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case head <> rest: messageImages(P, A, D, U, head) || hasCopilotVisionInput(P, A, D, U, rest)

def visionHeader(hasImages: Bool) -> List<&2, R.Property<String>>:
  match hasImages:
    case False{}: Nil{}
    case True{}: R.Property{"Copilot-Vision-Request", "true"} <> Nil{}

def buildCopilotDynamicHeaders(-P: Data, -A: Data, -D: Data, -U: Data, messages: List<&2, T.Message<P, A, D, U>>, hasImages: Bool) -> R.Record<String>:
  R.Record{R.Property{"X-Initiator", inferCopilotInitiator(P, A, D, U, messages)} <> R.Property{"Openai-Intent", "conversation-edits"} <> visionHeader(hasImages)}

def forProvider(-P: Data, -A: Data, -D: Data, -U: Data, provider: String, +messages: List<&2, T.Message<P, A, D, U>>) -> Maybe<&2, R.Record<String>>:
  match provider:
    case "github-copilot": Some{buildCopilotDynamicHeaders(P, A, D, U, messages, hasCopilotVisionInput(P, A, D, U, messages))}
    case _: None{}
