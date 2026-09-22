import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/transform-messages.bend as Transform
import ../packages/ai/src/utils/diagnostics.bend as Diagnostics
import ../packages/runtime/src/text.bend as Space
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F

# Image downgrade for models without image input.

def hasImage(content: List<&2, Ai.TextImageContent>) -> Bool:
  match content:
    case Nil{}: False{}
    case Ai.TextImageImage{_} <> _: True{}
    case _ <> rest: hasImage(rest)

def textsOf(texts: List<&2, Ai.TextContent>) -> List<&2, Ai.TextImageContent>:
  match texts:
    case Nil{}: Nil{}
    case text <> rest: Ai.TextImageText{text} <> textsOf(rest)

type Role is Data:
  SystemRole{}
  UserRole{}
  AssistantRole{}
  ToolResultRole{}

def roles(-P: Data, -A: Data, -G: Data, -D: Data, messages: List<&2, Ai.Message<P, A, G, D>>) -> List<&2, Role>:
  match messages:
    case Nil{}: Nil{}
    case Ai.System{_} <> rest: SystemRole{} <> roles(P, A, G, D, rest)
    case Ai.User{_} <> rest: UserRole{} <> roles(P, A, G, D, rest)
    case Ai.Assistant{_} <> rest: AssistantRole{} <> roles(P, A, G, D, rest)
    case Ai.ToolResult{_} <> rest: ToolResultRole{} <> roles(P, A, G, D, rest)

law images_never_survive:
  for content: List<&2, Ai.TextImageContent>
  for previous: Bool
  for +placeholder: String
  {hasImage(Transform.replaceImages(content, previous, placeholder)) == False{} : Bool}

law text_only_content_is_unchanged:
  for texts: List<&2, Ai.TextContent>
  for previous: Bool
  for +placeholder: String
  {Transform.replaceImages(textsOf(texts), previous, placeholder) == textsOf(texts) : List<&2, Ai.TextImageContent>}

law adjacent_images_share_one_placeholder:
  for first: Ai.ImageContent
  for second: Ai.ImageContent
  for rest: List<&2, Ai.TextImageContent>
  for previous: Bool
  for +placeholder: String
  {Transform.replaceImages(Ai.TextImageImage{first} <> Ai.TextImageImage{second} <> rest, previous, placeholder) == Transform.replaceImages(Ai.TextImageImage{first} <> rest, previous, placeholder) : List<&2, Ai.TextImageContent>}

law downgrade_keeps_message_roles:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for messages: List<&2, Ai.Message<P, A, G, D>>
  {roles(P, A, G, D, Transform.downgradeMessages(P, A, G, D, messages)) == roles(P, A, G, D, messages) : List<&2, Role>}

law system_messages_are_not_downgraded:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for system: Ai.SystemMessage<P>
  {Transform.downgradeMessage(P, A, G, D, Ai.System{system}) == Ai.System{system} : Ai.Message<P, A, G, D>}

law assistant_messages_are_not_downgraded:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for assistant: Ai.AssistantMessage<A, G>
  {Transform.downgradeMessage(P, A, G, D, Ai.Assistant{assistant}) == Ai.Assistant{assistant} : Ai.Message<P, A, G, D>}

# Replay of assistant content on the same or a different model.

type Plain<-A: Data> is Data:
  PlainText{value: Ai.TextContent}
  PlainCall{value: Ai.ToolCall<A>}

def plainOf(-A: Data, blocks: List<&2, Plain<A>>) -> List<&2, Ai.AssistantContent<A>>:
  match blocks:
    case Nil{}: Nil{}
    case PlainText{text} <> rest: Ai.AssistantText{text} <> plainOf(A, rest)
    case PlainCall{call} <> rest: Ai.AssistantToolCall{call} <> plainOf(A, rest)

def hasThinking(-A: Data, content: List<&2, Ai.AssistantContent<A>>) -> Bool:
  match content:
    case Nil{}: False{}
    case Ai.AssistantThinking{_} <> _: True{}
    case _ <> rest: hasThinking(A, rest)

law same_model_replays_text_and_tool_calls_verbatim:
  for -A: Data
  for blocks: List<&2, Plain<A>>
  {Transform.replayContent(A, plainOf(A, blocks), True{}) == plainOf(A, blocks) : List<&2, Ai.AssistantContent<A>>}

law cross_model_replay_carries_no_thinking:
  for -A: Data
  for content: List<&2, Ai.AssistantContent<A>>
  {hasThinking(A, Transform.replayContent(A, content, False{})) == False{} : Bool}

law redacted_thinking_is_dropped_across_models:
  for -A: Data
  for thinking: String
  for signature: Maybe<&2, String>
  {Transform.replayThinking(A, False{}, Ai.ThinkingContent{thinking, signature, Some{True{}}}) == None{} : Maybe<&2, Ai.AssistantContent<A>>}

law redacted_thinking_replays_on_the_same_model:
  for -A: Data
  for thinking: String
  for signature: Maybe<&2, String>
  {Transform.replayThinking(A, True{}, Ai.ThinkingContent{thinking, signature, Some{True{}}}) == Some{Ai.AssistantThinking{Ai.ThinkingContent{thinking, signature, Some{True{}}}}} : Maybe<&2, Ai.AssistantContent<A>>}

law signed_thinking_replays_on_the_same_model:
  for -A: Data
  for thinking: String
  for head: Char
  for tail: String
  for redacted: Maybe<&2, Bool>
  for unredacted: {Maybe.default(&2, Bool, redacted, False{}) == False{} : Bool}
  {Transform.replayThinking(A, True{}, Ai.ThinkingContent{thinking, Some{SCon{head, tail}}, redacted}) == Some{Ai.AssistantThinking{Ai.ThinkingContent{thinking, Some{SCon{head, tail}}, redacted}}} : Maybe<&2, Ai.AssistantContent<A>>}

law blank_unsigned_thinking_is_dropped:
  for -A: Data
  for same: Bool
  for thinking: String
  for blank: {Space.blank(thinking) == True{} : Bool}
  {Transform.replayThinking(A, same, Ai.ThinkingContent{thinking, None{}, None{}}) == None{} : Maybe<&2, Ai.AssistantContent<A>>}

law cross_model_thinking_becomes_text:
  for -A: Data
  for thinking: String
  for signature: Maybe<&2, String>
  for redacted: Maybe<&2, Bool>
  for unredacted: {Maybe.default(&2, Bool, redacted, False{}) == False{} : Bool}
  for visible: {Space.blank(thinking) == False{} : Bool}
  {Transform.replayThinking(A, False{}, Ai.ThinkingContent{thinking, signature, redacted}) == Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}} : Maybe<&2, Ai.AssistantContent<A>>}

law cross_model_text_loses_its_signature:
  for -A: Data
  for text: String
  for signature: Maybe<&2, String>
  {Transform.replayBlock(A, False{}, Ai.AssistantText{Ai.TextContent{text, signature}}) == Some{Ai.AssistantText{Ai.TextContent{text, None{}}}} : Maybe<&2, Ai.AssistantContent<A>>}

law cross_model_tool_call_loses_its_thought_signature:
  for -A: Data
  for id: String
  for name: String
  for arguments: A
  for head: Char
  for tail: String
  for namespace: Maybe<&2, String>
  {Transform.replayBlock(A, False{}, Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, Some{SCon{head, tail}}, namespace}}) == Some{Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, None{}, namespace}}} : Maybe<&2, Ai.AssistantContent<A>>}

law replay_identity_needs_all_three_identifiers:
  for -A: Data
  for -G: Data
  for api: String
  for provider: String
  for id: String
  for content: List<&2, Ai.AssistantContent<A>>
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for level: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: Ai.Usage
  for reason: Ai.StopReason
  for deferred: Maybe<&2, Ai.DeferredHandle>
  for error: Maybe<&2, String>
  for rawReason: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F64
  {Transform.sameModel(A, G, Transform.Target{api, provider, id}, Ai.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}) == True{} : Bool}

# Tool-call identifier mapping between normalized calls and their results.

law unmapped_result_keeps_its_id:
  for id: String
  {Transform.mappedId(id, None{}) == id : String}

law empty_mapping_is_ignored:
  for id: String
  {Transform.mappedId(id, Some{""}) == id : String}

law nonempty_mapping_applies:
  for id: String
  for head: Char
  for tail: String
  {Transform.mappedId(id, Some{SCon{head, tail}}) == SCon{head, tail} : String}

law identity_normalization_is_not_remembered:
  for id: String
  for ids: R.Record<String>
  {Transform.rememberId(id, id, ids) == ids : R.Record<String>}
