import Base
import ../laws/transform-messages.bend as Laws
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/transform-messages.bend as Transform
import ../packages/runtime/src/text.bend as Space
import ../packages/runtime/src/record.bend as R
import ./string-equality.bend as StringEquality

def Laws.images_never_survive(content, previous, placeholder):
  match content:
    case Nil{}: {==}
    case Ai.TextImageImage{image} <> rest:
      match previous:
        case True{}: Laws.images_never_survive(rest, True{}, placeholder)
        case False{}: Laws.images_never_survive(rest, True{}, placeholder)
    case Ai.TextImageText{Ai.TextContent{+text, signature}} <> rest:
      Laws.images_never_survive(rest, String.eq(text, placeholder), placeholder)

def Laws.text_only_content_is_unchanged(texts, previous, placeholder):
  match texts:
    case Nil{}: {==}
    case Ai.TextContent{+text, signature} <> rest:
      Equal.cong(List<&2, Ai.TextImageContent>, List<&2, Ai.TextImageContent>, tail => Ai.TextImageText{Ai.TextContent{text, signature}} <> tail, Transform.replaceImages(Laws.textsOf(rest), String.eq(text, placeholder), placeholder), Laws.textsOf(rest), Laws.text_only_content_is_unchanged(rest, String.eq(text, placeholder), placeholder))

def Laws.adjacent_images_share_one_placeholder(first, second, rest, previous, placeholder):
  match previous:
    case True{}: {==}
    case False{}: {==}

def Laws.downgrade_keeps_message_roles(P, A, G, D, messages):
  match messages:
    case Nil{}: {==}
    case Ai.System{system} <> rest:
      Equal.cong(List<&2, Laws.Role>, List<&2, Laws.Role>, tail => Laws.SystemRole{} <> tail, Laws.roles(P, A, G, D, Transform.downgradeMessages(P, A, G, D, rest)), Laws.roles(P, A, G, D, rest), Laws.downgrade_keeps_message_roles(P, A, G, D, rest))
    case Ai.User{Ai.UserMessage{content, timestamp}} <> rest:
      Equal.cong(List<&2, Laws.Role>, List<&2, Laws.Role>, tail => Laws.UserRole{} <> tail, Laws.roles(P, A, G, D, Transform.downgradeMessages(P, A, G, D, rest)), Laws.roles(P, A, G, D, rest), Laws.downgrade_keeps_message_roles(P, A, G, D, rest))
    case Ai.Assistant{assistant} <> rest:
      Equal.cong(List<&2, Laws.Role>, List<&2, Laws.Role>, tail => Laws.AssistantRole{} <> tail, Laws.roles(P, A, G, D, Transform.downgradeMessages(P, A, G, D, rest)), Laws.roles(P, A, G, D, rest), Laws.downgrade_keeps_message_roles(P, A, G, D, rest))
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, content, details, usage, isError, timestamp}} <> rest:
      Equal.cong(List<&2, Laws.Role>, List<&2, Laws.Role>, tail => Laws.ToolResultRole{} <> tail, Laws.roles(P, A, G, D, Transform.downgradeMessages(P, A, G, D, rest)), Laws.roles(P, A, G, D, rest), Laws.downgrade_keeps_message_roles(P, A, G, D, rest))

def Laws.system_messages_are_not_downgraded(P, A, G, D, system): {==}

def Laws.assistant_messages_are_not_downgraded(P, A, G, D, assistant): {==}

def Laws.same_model_replays_text_and_tool_calls_verbatim(A, blocks):
  match blocks:
    case Nil{}: {==}
    case Laws.PlainText{Ai.TextContent{text, signature}} <> rest:
      Equal.cong(List<&2, Ai.AssistantContent<A>>, List<&2, Ai.AssistantContent<A>>, tail => Ai.AssistantText{Ai.TextContent{text, signature}} <> tail, Transform.replayContent(A, Laws.plainOf(A, rest), True{}), Laws.plainOf(A, rest), Laws.same_model_replays_text_and_tool_calls_verbatim(A, rest))
    case Laws.PlainCall{Ai.ToolCall{id, name, arguments, signature, namespace}} <> rest:
      Equal.cong(List<&2, Ai.AssistantContent<A>>, List<&2, Ai.AssistantContent<A>>, tail => Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, signature, namespace}} <> tail, Transform.replayContent(A, Laws.plainOf(A, rest), True{}), Laws.plainOf(A, rest), Laws.same_model_replays_text_and_tool_calls_verbatim(A, rest))

# A thinking block replayed across models is either dropped or becomes text;
# neither outcome adds a thinking block ahead of the rest.
def thinking_case(-A: Data, dropped: Bool, blank: Bool, thinking: String, rest: List<&2, Ai.AssistantContent<A>>, tail: {Laws.hasThinking(A, rest) == False{} : Bool}) -> {Laws.hasThinking(A, Transform.prependBlock(A, Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, dropped, None{}, Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, blank, None{}, Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}})), rest)) == False{} : Bool}:
  match dropped:
    case True{}: tail
    case False{}:
      match blank:
        case True{}: tail
        case False{}: tail

def Laws.cross_model_replay_carries_no_thinking(A, content):
  match content:
    case Nil{}: {==}
    case Ai.AssistantText{Ai.TextContent{text, signature}} <> rest: Laws.cross_model_replay_carries_no_thinking(A, rest)
    case Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, signature, namespace}} <> rest: Laws.cross_model_replay_carries_no_thinking(A, rest)
    case Ai.AssistantThinking{Ai.ThinkingContent{+thinking, signature, redacted}} <> +rest:
      thinking_case(A, Maybe.default(&2, Bool, redacted, False{}), Space.blank(thinking), thinking, Transform.replayContent(A, rest, False{}), Laws.cross_model_replay_carries_no_thinking(A, rest))

def Laws.redacted_thinking_is_dropped_across_models(A, thinking, signature): {==}

def Laws.redacted_thinking_replays_on_the_same_model(A, thinking, signature): {==}

def Laws.signed_thinking_replays_on_the_same_model(A, thinking, head, tail, redacted, unredacted):
  Equal.cong(Bool, Maybe<&2, Ai.AssistantContent<A>>, flag => Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, flag, Some{Ai.AssistantThinking{Ai.ThinkingContent{thinking, Some{SCon{head, tail}}, redacted}}}, Some{Ai.AssistantThinking{Ai.ThinkingContent{thinking, Some{SCon{head, tail}}, redacted}}}), Maybe.default(&2, Bool, redacted, False{}), False{}, unredacted)

def Laws.blank_unsigned_thinking_is_dropped(A, same, thinking, blank):
  match same:
    case True{}:
      Equal.cong(Bool, Maybe<&2, Ai.AssistantContent<A>>, empty => Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, empty, None{}, Some{Ai.AssistantThinking{Ai.ThinkingContent{thinking, None{}, None{}}}}), Space.blank(thinking), True{}, blank)
    case False{}:
      Equal.cong(Bool, Maybe<&2, Ai.AssistantContent<A>>, empty => Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, empty, None{}, Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}}), Space.blank(thinking), True{}, blank)

def Laws.cross_model_thinking_becomes_text(A, thinking, signature, redacted, unredacted, visible):
  Equal.trans(Maybe<&2, Ai.AssistantContent<A>>, Transform.replayThinking(A, False{}, Ai.ThinkingContent{thinking, signature, redacted}), Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, Space.blank(thinking), None{}, Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}}), Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}},
    Equal.cong(Bool, Maybe<&2, Ai.AssistantContent<A>>, flag => Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, flag, None{}, Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, Space.blank(thinking), None{}, Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}})), Maybe.default(&2, Bool, redacted, False{}), False{}, unredacted),
    Equal.cong(Bool, Maybe<&2, Ai.AssistantContent<A>>, empty => Bool.pick(Maybe<&2, Ai.AssistantContent<A>>, empty, None{}, Some{Ai.AssistantText{Ai.TextContent{thinking, None{}}}}), Space.blank(thinking), False{}, visible))

def Laws.cross_model_text_loses_its_signature(A, text, signature): {==}

def Laws.cross_model_tool_call_loses_its_thought_signature(A, id, name, arguments, head, tail, namespace): {==}

def Laws.replay_identity_needs_all_three_identifiers(A, G, api, provider, id, content, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp):
  %StringEquality.eq_reflexive(api) : {Bool.and(Bool.and(_, String.eq(provider, provider)), String.eq(id, id)) == True{} : Bool}
  %StringEquality.eq_reflexive(provider) : {Bool.and(_, String.eq(id, id)) == True{} : Bool}
  %StringEquality.eq_reflexive(id) : {_ == True{} : Bool}
  {==}

def Laws.unmapped_result_keeps_its_id(id): {==}

def Laws.empty_mapping_is_ignored(id): {==}

def Laws.nonempty_mapping_applies(id, head, tail): {==}

def Laws.identity_normalization_is_not_remembered(id, ids):
  %StringEquality.eq_reflexive(id) : {Bool.pick(R.Record<String>, _, ids, R.set(String, ids, id, id)) == ids : R.Record<String>}
  {==}
