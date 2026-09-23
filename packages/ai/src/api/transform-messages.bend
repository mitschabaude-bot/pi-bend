import Base
import ../types.bend as Ai
import ../utils/model-api.bend as Api
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ./transform-tool-results.bend as Repair

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

# Normalizers are caller-owned callbacks. Their typed error short-circuits the
# first pass, before repair can synthesize results or read the wall clock.
type NormalizeToolCallIdInput<-A: Data, -G: Data, -J: Data> is Data:
  NormalizeToolCallIdInput{id: String, model: Ai.Model<J>, source: Ai.AssistantMessage<A, G>}

def Normalizer(-A: Data, -G: Data, -J: Data, -E: Data) -> Data:
  C.Callback<NormalizeToolCallIdInput<A, G, J>, Result<&2, &2, E, String>>

type NormalizedContent<-A: Data> is Data:
  NormalizedContent{content: List<&2, Ai.AssistantContent<A>>, ids: R.Record<String>}

def withContent(-A: Data, -G: Data, source: Ai.AssistantMessage<A, G>, content: List<&2, Ai.AssistantContent<A>>) -> Ai.AssistantMessage<A, G>:
  match source:
    case Ai.AssistantMessage{_, api, provider, model, responseModel, responseId, thinkingLevel, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}:
      Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, thinkingLevel, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}

def rememberId(+old: String, +new: String, +ids: R.Record<String>) -> R.Record<String>:
  Bool.pick(R.Record<String>, String.eq(old, new), ids, R.set(String, ids, old, new))

def normalizedCall(-A: Data, -E: Data, call: Ai.ToolCall<A>, ids: R.Record<String>, reversed: List<&2, Ai.AssistantContent<A>>, result: Result<&2, &2, E, String>) -> Result<&2, &2, E, NormalizedContent<A>>:
  match call result:
    case _ Fail{error}: Fail{error}
    case Ai.ToolCall{old, name, arguments, signature, namespace} Done{+id}:
      Done{NormalizedContent{Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, signature, namespace}} <> reversed, rememberId(old, id, ids)}}

def normalizeBlock(-A: Data, -G: Data, -J: Data, -E: Data, block: Ai.AssistantContent<A>, model: Ai.Model<J>, source: Ai.AssistantMessage<A, G>, normalizer: Normalizer(A, G, J, E), ids: R.Record<String>, reversed: List<&2, Ai.AssistantContent<A>>) -> IO(Result<&2, &2, E, NormalizedContent<A>>):
  match block:
    case Ai.AssistantToolCall{+call}:
      do IO<Result<&2, &2, E, NormalizedContent<A>>>:
        result : Result<&2, &2, E, String> <- C.call(NormalizeToolCallIdInput<A, G, J>, Result<&2, &2, E, String>, normalizer, NormalizeToolCallIdInput{Repair.callId(A, call), model, source})
        return normalizedCall(A, E, call, ids, reversed, result)
    case other: IO.pure(Result<&2, &2, E, NormalizedContent<A>>, Done{NormalizedContent{other <> reversed, ids}})

def normalizeContent(-A: Data, -G: Data, -J: Data, -E: Data, remaining: List<&2, Ai.AssistantContent<A>>, +model: Ai.Model<J>, +source: Ai.AssistantMessage<A, G>, +normalizer: Normalizer(A, G, J, E), state: Result<&2, &2, E, NormalizedContent<A>>) -> IO(Result<&2, &2, E, NormalizedContent<A>>):
  match remaining state:
    case _ Fail{error}: IO.pure(Result<&2, &2, E, NormalizedContent<A>>, Fail{error})
    case Nil{} Done{NormalizedContent{content, ids}}:
      IO.pure(Result<&2, &2, E, NormalizedContent<A>>, Done{NormalizedContent{List.reverse(&2, Ai.AssistantContent<A>, content), ids}})
    case block <> rest Done{NormalizedContent{reversed, ids}}:
      do IO<Result<&2, &2, E, NormalizedContent<A>>>:
        next : Result<&2, &2, E, NormalizedContent<A>> <- normalizeBlock(A, G, J, E, block, model, source, normalizer, ids, reversed)
        normalizeContent(A, G, J, E, rest, model, source, normalizer, next)

def normalizeAssistant(-A: Data, -G: Data, -J: Data, -E: Data, same: Bool, content: List<&2, Ai.AssistantContent<A>>, model: Ai.Model<J>, source: Ai.AssistantMessage<A, G>, normalizer: Maybe<&2, Normalizer(A, G, J, E)>, ids: R.Record<String>) -> IO(Result<&2, &2, E, NormalizedContent<A>>):
  match same normalizer:
    case False{} Some{callback}: normalizeContent(A, G, J, E, content, model, source, callback, Done{NormalizedContent{Nil{}, ids}})
    case _ _: IO.pure(Result<&2, &2, E, NormalizedContent<A>>, Done{NormalizedContent{content, ids}})

type FirstPass<-P: Data, -A: Data, -G: Data, -D: Data> is Data:
  FirstPass{reversed: Repair.Messages(P, A, G, D), ids: R.Record<String>}

def transformedAssistant(-P: Data, -A: Data, -G: Data, -D: Data, -E: Data, source: Ai.AssistantMessage<A, G>, reversed: Repair.Messages(P, A, G, D), result: Result<&2, &2, E, NormalizedContent<A>>) -> Result<&2, &2, E, FirstPass<P, A, G, D>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{NormalizedContent{content, ids}}: Done{FirstPass{Ai.Assistant{withContent(A, G, source, content)} <> reversed, ids}}

def mappedId(original: String, mapped: Maybe<&2, String>) -> String:
  match mapped:
    case None{}: original
    case Some{+id}: Bool.pick(String, String.eq(id, ""), original, id)

def mappedResult(-D: Data, result: Ai.ToolResultMessage<D>, ids: R.Record<String>) -> Ai.ToolResultMessage<D>:
  match result:
    case Ai.ToolResultMessage{+id, name, content, details, usage, error, timestamp}:
      Ai.ToolResultMessage{mappedId(id, R.get(String, ids, id)), name, content, details, usage, error, timestamp}

def transformOne(-P: Data, -A: Data, -G: Data, -D: Data, -J: Data, -E: Data, message: Ai.Message<P, A, G, D>, +model: Ai.Model<J>, normalizer: Maybe<&2, Normalizer(A, G, J, E)>, state: FirstPass<P, A, G, D>) -> IO(Result<&2, &2, E, FirstPass<P, A, G, D>>):
  match message state:
    case Ai.Assistant{+source} FirstPass{reversed, ids}:
      do IO<Result<&2, &2, E, FirstPass<P, A, G, D>>>:
        +same : Bool = sameModel(A, G, target(J, model), source)
        result : Result<&2, &2, E, NormalizedContent<A>> <- normalizeAssistant(A, G, J, E, same, replayContent(A, Ai.assistantContent(A, G, source), same), model, source, normalizer, ids)
        return transformedAssistant(P, A, G, D, E, source, reversed, result)
    case Ai.ToolResult{result} FirstPass{reversed, +ids}:
      IO.pure(Result<&2, &2, E, FirstPass<P, A, G, D>>, Done{FirstPass{Ai.ToolResult{mappedResult(D, result, ids)} <> reversed, ids}})
    case other FirstPass{reversed, ids}: IO.pure(Result<&2, &2, E, FirstPass<P, A, G, D>>, Done{FirstPass{other <> reversed, ids}})

def firstPass(-P: Data, -A: Data, -G: Data, -D: Data, -J: Data, -E: Data, messages: Repair.Messages(P, A, G, D), +model: Ai.Model<J>, +normalizer: Maybe<&2, Normalizer(A, G, J, E)>, state: Result<&2, &2, E, FirstPass<P, A, G, D>>) -> IO(Result<&2, &2, E, Repair.Messages(P, A, G, D)>):
  match messages state:
    case _ Fail{error}: IO.pure(Result<&2, &2, E, Repair.Messages(P, A, G, D)>, Fail{error})
    case Nil{} Done{FirstPass{reversed, _}}: IO.pure(Result<&2, &2, E, Repair.Messages(P, A, G, D)>, Done{List.reverse(&2, Ai.Message<P, A, G, D>, reversed)})
    case message <> rest Done{current}:
      do IO<Result<&2, &2, E, Repair.Messages(P, A, G, D)>>:
        next : Result<&2, &2, E, FirstPass<P, A, G, D>> <- transformOne(P, A, G, D, J, E, message, model, normalizer, current)
        firstPass(P, A, G, D, J, E, rest, model, normalizer, next)

def finishTransform(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~E: Data, ~now: Unit -> IO(F64), result: Result<&2, &2, E, Repair.Messages(P, A, G, D)>) -> IO(Result<&2, &2, E, Repair.Messages(P, A, G, D)>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, E, Repair.Messages(P, A, G, D)>, Fail{error})
    case Done{messages}:
      do IO<Result<&2, &2, E, Repair.Messages(P, A, G, D)>>:
        repaired : Repair.Messages(P, A, G, D) <- Repair.repairWith(~P, ~A, ~G, ~D, ~now, messages)
        return Done{repaired}

def transformMessagesWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~E: Data, ~now: Unit -> IO(F64), messages: Repair.Messages(P, A, G, D), +model: Ai.Model<J>, normalizer: Maybe<&2, Normalizer(A, G, J, E)>) -> IO(Result<&2, &2, E, Repair.Messages(P, A, G, D)>):
  do IO<Result<&2, &2, E, Repair.Messages(P, A, G, D)>>:
    transformed : Result<&2, &2, E, Repair.Messages(P, A, G, D)> <- firstPass(P, A, G, D, J, E, downgradeUnsupportedImages(P, A, G, D, J, messages, model), model, normalizer, Done{FirstPass{Nil{}, R.new(String)}})
    finishTransform(~P, ~A, ~G, ~D, ~E, ~now, transformed)

def transformMessages(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~E: Data, messages: Repair.Messages(P, A, G, D), model: Ai.Model<J>, normalizer: Maybe<&2, Normalizer(A, G, J, E)>) -> IO(Result<&2, &2, E, Repair.Messages(P, A, G, D)>):
  transformMessagesWith(~P, ~A, ~G, ~D, ~J, ~E, ~Repair.wallClock, messages, model, normalizer)
