import Base
import ../laws/transcript.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ordered-map.bend as M
import ./string-equality.bend as StringEquality
import ../packages/ai/src/utils/text.bend as Text

def Laws.normalization_without_prompt_or_tools_adds_nothing(P, A, G, H, messages): {==}

def Laws.blank_prompt_and_empty_tools_add_nothing(P, A, G, H, messages): {==}

def Laws.a_prompt_becomes_the_leading_system_message(P, A, G, H, head, rest, messages, tools): {==}

def Laws.tools_alone_create_the_leading_system_message(P, A, G, H, messages, tool, tools): {==}

def Laws.supported_mid_conversation_system_messages_keep_the_transcript(P, A, G, H, context): {==}

def Laws.collapse_leaves_no_system_message_after_the_head(P, A, G, H, messages):
  match messages:
    case Nil{}: {==}
    case T.System{system} <> rest: Laws.collapse_leaves_no_system_message_after_the_head(P, A, G, H, rest)
    case T.User{user} <> rest: Laws.collapse_leaves_no_system_message_after_the_head(P, A, G, H, rest)
    case T.Assistant{assistant} <> rest: Laws.collapse_leaves_no_system_message_after_the_head(P, A, G, H, rest)
    case T.ToolResult{result} <> rest: Laws.collapse_leaves_no_system_message_after_the_head(P, A, G, H, rest)

def replay_plain(-P: Data, -A: Data, -G: Data, -H: Data, turns: List<&2, Laws.NonSystem<A, G, H>>, state: Transcript.ReplayState) -> {Transcript.replayMessages(P, A, G, H, Laws.plainOf(P, A, G, H, turns), state) == state : Transcript.ReplayState}:
  match turns:
    case Nil{}: {==}
    case Laws.UserTurn{user} <> rest: replay_plain(P, A, G, H, rest, state)
    case Laws.AssistantTurn{assistant} <> rest: replay_plain(P, A, G, H, rest, state)
    case Laws.ToolResultTurn{result} <> rest: replay_plain(P, A, G, H, rest, state)

def tools_plain(-P: Data, -A: Data, -G: Data, -H: Data, turns: List<&2, Laws.NonSystem<A, G, H>>, tools: M.OrderedMap<T.Tool<P>>, includeRemoved: Bool) -> {Transcript.collectTools(P, A, G, H, Laws.plainOf(P, A, G, H, turns), tools, includeRemoved) == M.values(T.Tool<P>, tools) : List<&2, T.Tool<P>>}:
  match turns:
    case Nil{}: {==}
    case Laws.UserTurn{user} <> rest: tools_plain(P, A, G, H, rest, tools, includeRemoved)
    case Laws.AssistantTurn{assistant} <> rest: tools_plain(P, A, G, H, rest, tools, includeRemoved)
    case Laws.ToolResultTurn{result} <> rest: tools_plain(P, A, G, H, rest, tools, includeRemoved)

def without_plain(-P: Data, -A: Data, -G: Data, -H: Data, turns: List<&2, Laws.NonSystem<A, G, H>>) -> {Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, turns)) == Laws.plainOf(P, A, G, H, turns) : List<&2, T.Message<P, A, G, H>>}:
  match turns:
    case Nil{}: {==}
    case Laws.UserTurn{user} <> rest:
      Equal.cong(List<&2, T.Message<P, A, G, H>>, List<&2, T.Message<P, A, G, H>>, tail => T.User{user} <> tail, Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, rest)), Laws.plainOf(P, A, G, H, rest), without_plain(P, A, G, H, rest))
    case Laws.AssistantTurn{assistant} <> rest:
      Equal.cong(List<&2, T.Message<P, A, G, H>>, List<&2, T.Message<P, A, G, H>>, tail => T.Assistant{assistant} <> tail, Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, rest)), Laws.plainOf(P, A, G, H, rest), without_plain(P, A, G, H, rest))
    case Laws.ToolResultTurn{result} <> rest:
      Equal.cong(List<&2, T.Message<P, A, G, H>>, List<&2, T.Message<P, A, G, H>>, tail => T.ToolResult{result} <> tail, Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, rest)), Laws.plainOf(P, A, G, H, rest), without_plain(P, A, G, H, rest))

def Laws.a_transcript_without_system_messages_replays_nothing(P, A, G, H, turns):
  %Equal.sym(Transcript.ReplayState, Transcript.replayMessages(P, A, G, H, Laws.plainOf(P, A, G, H, turns), Transcript.ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}}), Transcript.ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}}, replay_plain(P, A, G, H, turns, Transcript.ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}})) : {Transcript.finishReplay(P, _, Transcript.collectTools(P, A, G, H, Laws.plainOf(P, A, G, H, turns), M.new(T.Tool<P>), True{})) == None{} : Maybe<&2, T.SystemMessage<P>>}
  %Equal.sym(List<&2, T.Tool<P>>, Transcript.collectTools(P, A, G, H, Laws.plainOf(P, A, G, H, turns), M.new(T.Tool<P>), True{}), M.values(T.Tool<P>, M.new(T.Tool<P>)), tools_plain(P, A, G, H, turns, M.new(T.Tool<P>), True{})) : {Transcript.finishReplay(P, Transcript.ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}}, _) == None{} : Maybe<&2, T.SystemMessage<P>>}
  {==}

def Laws.collapse_without_system_messages_is_identity(P, A, G, H, turns):
  %Equal.sym(Maybe<&2, T.SystemMessage<P>>, Transcript.getCurrentSystemMessage(P, A, G, H, Laws.plainOf(P, A, G, H, turns)), None{}, Laws.a_transcript_without_system_messages_replays_nothing(P, A, G, H, turns)) : {T.TranscriptContext{Transcript.collapsedMessages(P, A, G, H, _, Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, turns)))} == T.TranscriptContext{Laws.plainOf(P, A, G, H, turns)} : T.TranscriptContext<P, A, G, H>}
  %Equal.sym(List<&2, T.Message<P, A, G, H>>, Transcript.withoutSystemMessages(P, A, G, H, Laws.plainOf(P, A, G, H, turns)), Laws.plainOf(P, A, G, H, turns), without_plain(P, A, G, H, turns)) : {T.TranscriptContext{_} == T.TranscriptContext{Laws.plainOf(P, A, G, H, turns)} : T.TranscriptContext<P, A, G, H>}
  {==}

def Laws.replay_keeps_the_first_timestamp(P, A, G, H, messages, content, sections, timestamp):
  match messages:
    case Nil{}: {==}
    case T.System{T.SystemMessage{text, patch, added, removed, stamp}} <> rest:
      Laws.replay_keeps_the_first_timestamp(P, A, G, H, rest, Transcript.appendContent(Text.systemContentText(text), content), Transcript.applySections(Text.sectionEntries(patch), sections), timestamp)
    case T.User{user} <> rest: Laws.replay_keeps_the_first_timestamp(P, A, G, H, rest, content, sections, timestamp)
    case T.Assistant{assistant} <> rest: Laws.replay_keeps_the_first_timestamp(P, A, G, H, rest, content, sections, timestamp)
    case T.ToolResult{result} <> rest: Laws.replay_keeps_the_first_timestamp(P, A, G, H, rest, content, sections, timestamp)

def Laws.declared_tools_ignore_removals(P, content, sections, added, removed, timestamp, tools): {==}

def Laws.an_added_tool_is_current(P, A, G, H, content, sections, name, description, parameters, sampling, timestamp): {==}

def Laws.a_removed_tool_is_no_longer_current(P, A, G, H, content, sections, name, description, parameters, sampling, timestamp, later, laterSections, laterTimestamp):
  %StringEquality.eq_reflexive(name) : {M.propertyValues(T.Tool<P>, Bool.pick(List<&2, R.Property<T.Tool<P>>>, _, Nil{}, R.Property{name, T.Tool{name, description, parameters, sampling}} <> Nil{})) == Nil{} : List<&2, T.Tool<P>>}
  {==}

def Laws.declared_tools_survive_removal(P, A, G, H, content, sections, name, description, parameters, sampling, timestamp, later, laterSections, laterTimestamp): {==}

def Laws.tool_removals_are_non_additive(P, A, G, H, content, sections, added, reference, references, timestamp, rest):
  match rest:
    case Nil{}: {==}
    case T.System{system} <> more: {==}
    case T.User{user} <> more: {==}
    case T.Assistant{assistant} <> more: {==}
    case T.ToolResult{result} <> more: {==}
