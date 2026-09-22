import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ordered-map.bend as M
import ../packages/runtime/src/f64.bend as F

# Context normalization: the legacy prompt and tool fields become one leading
# system message exactly when they carry something.

law normalization_without_prompt_or_tools_adds_nothing:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for messages: List<&2, T.Message<P, A, G, H>>
  {Transcript.normalizeContext(P, A, G, H, T.Context{None{}, messages, None{}}) == T.TranscriptContext{messages} : T.TranscriptContext<P, A, G, H>}

law blank_prompt_and_empty_tools_add_nothing:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for messages: List<&2, T.Message<P, A, G, H>>
  {Transcript.normalizeContext(P, A, G, H, T.Context{Some{""}, messages, Some{Nil{}}}) == T.TranscriptContext{messages} : T.TranscriptContext<P, A, G, H>}

law a_prompt_becomes_the_leading_system_message:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for head: Char
  for rest: String
  for messages: List<&2, T.Message<P, A, G, H>>
  for tools: Maybe<&2, List<&2, T.Tool<P>>>
  {Transcript.normalizeContext(P, A, G, H, T.Context{Some{SCon{head, rest}}, messages, tools}) == T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{SCon{head, rest}}, None{}, Transcript.nonEmptyTools(P, tools), None{}, F.fromU32(0)}} <> messages} : T.TranscriptContext<P, A, G, H>}

law tools_alone_create_the_leading_system_message:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for messages: List<&2, T.Message<P, A, G, H>>
  for tool: T.Tool<P>
  for tools: List<&2, T.Tool<P>>
  {Transcript.normalizeContext(P, A, G, H, T.Context{None{}, messages, Some{tool <> tools}}) == T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{""}, None{}, Some{tool <> tools}, None{}, F.fromU32(0)}} <> messages} : T.TranscriptContext<P, A, G, H>}

# System message replay and collapse.

type NonSystem<-A: Data, -G: Data, -H: Data> is Data:
  UserTurn{value: T.UserMessage}
  AssistantTurn{value: T.AssistantMessage<A, G>}
  ToolResultTurn{value: T.ToolResultMessage<H>}

def plainOf(-P: Data, -A: Data, -G: Data, -H: Data, turns: List<&2, NonSystem<A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match turns:
    case Nil{}: Nil{}
    case UserTurn{user} <> rest: T.User{user} <> plainOf(P, A, G, H, rest)
    case AssistantTurn{assistant} <> rest: T.Assistant{assistant} <> plainOf(P, A, G, H, rest)
    case ToolResultTurn{result} <> rest: T.ToolResult{result} <> plainOf(P, A, G, H, rest)

def hasSystem(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case T.System{_} <> _: True{}
    case _ <> rest: hasSystem(P, A, G, H, rest)

def timestampOf(state: Transcript.ReplayState) -> Maybe<&2, F.F64>:
  match state:
    case Transcript.ReplayState{_, _, timestamp}: timestamp

law supported_mid_conversation_system_messages_keep_the_transcript:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for context: T.TranscriptContext<P, A, G, H>
  {Transcript.resolveTranscript(P, A, G, H, context, Some{True{}}) == context : T.TranscriptContext<P, A, G, H>}

law collapse_leaves_no_system_message_after_the_head:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for messages: List<&2, T.Message<P, A, G, H>>
  {hasSystem(P, A, G, H, Transcript.withoutSystemMessages(P, A, G, H, messages)) == False{} : Bool}

law a_transcript_without_system_messages_replays_nothing:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for +turns: List<&2, NonSystem<A, G, H>>
  {Transcript.getCurrentSystemMessage(P, A, G, H, plainOf(P, A, G, H, turns)) == None{} : Maybe<&2, T.SystemMessage<P>>}

law collapse_without_system_messages_is_identity:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for +turns: List<&2, NonSystem<A, G, H>>
  {Transcript.collapseSystemMessages(P, A, G, H, T.TranscriptContext{plainOf(P, A, G, H, turns)}) == T.TranscriptContext{plainOf(P, A, G, H, turns)} : T.TranscriptContext<P, A, G, H>}

law replay_keeps_the_first_timestamp:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for messages: List<&2, T.Message<P, A, G, H>>
  for content: List<&2, String>
  for sections: R.Record<Maybe<&2, String>>
  for timestamp: F.F64
  {timestampOf(Transcript.replayMessages(P, A, G, H, messages, Transcript.ReplayState{content, sections, Some{timestamp}})) == Some{timestamp} : Maybe<&2, F.F64>}

# Tool replay: removals only count for the current tool set, never for the
# declared one; a first declaration is never a redefinition.

law declared_tools_ignore_removals:
  for -P: Data
  for content: T.SystemContent
  for sections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for added: Maybe<&2, List<&2, T.Tool<P>>>
  for removed: Maybe<&2, List<&2, T.ToolReference>>
  for timestamp: F.F64
  for tools: M.OrderedMap<T.Tool<P>>
  {Transcript.replayTools(P, T.SystemMessage{content, sections, added, removed, timestamp}, tools, False{}) == Transcript.addTools(P, Transcript.listValue(T.Tool<P>, added), tools) : M.OrderedMap<T.Tool<P>>}

law an_added_tool_is_current:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for content: T.SystemContent
  for sections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for +name: String
  for description: String
  for parameters: P
  for sampling: Maybe<&2, T.ToolConstrainedSampling>
  for timestamp: F.F64
  {Transcript.getCurrentTools(P, A, G, H, T.System{T.SystemMessage{content, sections, Some{T.Tool{name, description, parameters, sampling} <> Nil{}}, None{}, timestamp}} <> Nil{}) == T.Tool{name, description, parameters, sampling} <> Nil{} : List<&2, T.Tool<P>>}

law a_removed_tool_is_no_longer_current:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for content: T.SystemContent
  for sections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for +name: String
  for description: String
  for parameters: P
  for sampling: Maybe<&2, T.ToolConstrainedSampling>
  for timestamp: F.F64
  for later: T.SystemContent
  for laterSections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for laterTimestamp: F.F64
  {Transcript.getCurrentTools(P, A, G, H, T.System{T.SystemMessage{content, sections, Some{T.Tool{name, description, parameters, sampling} <> Nil{}}, None{}, timestamp}} <> T.System{T.SystemMessage{later, laterSections, None{}, Some{T.ToolReference{name} <> Nil{}}, laterTimestamp}} <> Nil{}) == Nil{} : List<&2, T.Tool<P>>}

law declared_tools_survive_removal:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for content: T.SystemContent
  for sections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for +name: String
  for description: String
  for parameters: P
  for sampling: Maybe<&2, T.ToolConstrainedSampling>
  for timestamp: F.F64
  for later: T.SystemContent
  for laterSections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for laterTimestamp: F.F64
  {Transcript.getDeclaredTools(P, A, G, H, T.System{T.SystemMessage{content, sections, Some{T.Tool{name, description, parameters, sampling} <> Nil{}}, None{}, timestamp}} <> T.System{T.SystemMessage{later, laterSections, None{}, Some{T.ToolReference{name} <> Nil{}}, laterTimestamp}} <> Nil{}) == T.Tool{name, description, parameters, sampling} <> Nil{} : List<&2, T.Tool<P>>}

law tool_removals_are_non_additive:
  for -P: Data
  for -A: Data
  for -G: Data
  for -H: Data
  for content: T.SystemContent
  for sections: Maybe<&2, R.Record<Maybe<&2, String>>>
  for added: Maybe<&2, List<&2, T.Tool<P>>>
  for reference: T.ToolReference
  for references: List<&2, T.ToolReference>
  for timestamp: F.F64
  for rest: List<&2, T.Message<P, A, G, H>>
  {Transcript.hasNonAdditiveToolChanges(P, A, G, H, T.System{T.SystemMessage{content, sections, added, Some{reference <> references}, timestamp}} <> rest) == True{} : Bool}
