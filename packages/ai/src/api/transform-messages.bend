import Base
import ../types.bend as Ai
import ../utils/model-api.bend as Api
import ../../../runtime/src/text-space.bend as Space

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

# Replay identity uses all three identifiers; shared providers or API families
# alone do not make encrypted reasoning or signatures portable.
type Target is Data:
  Target{api: String, provider: String, id: String}

def target(-J: Data, model: Ai.Model<J>) -> Target:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}: Target{Api.name(api), provider, id}

def sameModel(-A: Data, -G: Data, target: Target, source: Ai.AssistantMessage<A, G>) -> Bool:
  match target source:
    case Target{api, provider, id} Ai.AssistantMessage{_, sourceApi, sourceProvider, sourceId, _, _, _, _, _, _, _, _, _, _, _}:
      String.eq(api, sourceApi) && String.eq(provider, sourceProvider) && String.eq(id, sourceId)

def nonempty(signature: Maybe<&2, String>) -> Bool:
  match signature:
    case Some{text}: Bool.not(String.eq(text, ""))
    case None{}: False{}

def replayThinking(-A: Data, +same: Bool, +content: Ai.ThinkingContent) -> Maybe<&2, Ai.AssistantContent<A>>:
  match content:
    case Ai.ThinkingContent{+thinking, signature, redacted}:
      Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, Maybe.default(&2, Bool, redacted, False{}),
        Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, same, Some{Ai.AssistantThinking{content}}, None{}),
        Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, same && nonempty(signature), Some{Ai.AssistantThinking{content}},
          Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, Space.blank(thinking), None{},
            Some{Bool.pick(Ai.AssistantContent<A>, same, Ai.AssistantThinking{content}, Ai.AssistantText{Ai.TextContent{thinking, None{}}})})))

def replayBlock(-A: Data, +same: Bool, block: Ai.AssistantContent<A>) -> Maybe<&2, Ai.AssistantContent<A>>:
  match block:
    case Ai.AssistantThinking{thinking}: replayThinking(A, same, thinking)
    case Ai.AssistantText{Ai.TextContent{text, signature}}:
      Some{Ai.AssistantText{Ai.TextContent{text, Bool.pick(Maybe<&2, String>, same, signature, None{})}}}
    case Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, +signature, namespace}}:
      Some{Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, Bool.pick(Maybe<&2, String>, Bool.not(same) && nonempty(signature), None{}, signature), namespace}}}

def prependBlock(-A: Data, block: Maybe<&2, Ai.AssistantContent<A>>, rest: List<&2, Ai.AssistantContent<A>>) -> List<&2, Ai.AssistantContent<A>>:
  match block:
    case None{}: rest
    case Some{block}: block <> rest

def replayContent(-A: Data, content: List<&2, Ai.AssistantContent<A>>, +same: Bool) -> List<&2, Ai.AssistantContent<A>>:
  match content:
    case Nil{}: Nil{}
    case block <> rest: prependBlock(A, replayBlock(A, same, block), replayContent(A, rest, same))

def replaySelected(-A: Data, -G: Data, same: Bool, source: Ai.AssistantMessage<A, G>) -> Ai.AssistantMessage<A, G>:
  match source:
    case Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, thinkingLevel, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}:
      Ai.AssistantMessage{replayContent(A, content, same), api, provider, model, responseModel, responseId, thinkingLevel, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}

def replayAssistant(-A: Data, -G: Data, -J: Data, +source: Ai.AssistantMessage<A, G>, model: Ai.Model<J>) -> Ai.AssistantMessage<A, G>:
  replaySelected(A, G, sameModel(A, G, target(J, model), source), source)
