import Base
import ../types.bend as T
import ./text.bend as Text
import ./json.bend as Json
import ./schema-json.bend as SchemaJson
import ./tool-declaration.bend as Declaration
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Token estimation is a provider heuristic, measured in UTF-16 code units as
# upstream. Message/schema types remain intact; callers supply pure encoders
# when their tool parameters or arguments use application-specific records.
type ContextUsageEstimate is Data:
  ContextUsageEstimate{tokens: F.F64, usageTokens: F.F64, trailingTokens: F.F64, lastUsageIndex: Maybe<&2, Nat>}

def equalOrder(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def positive(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case _: False{}

def atLeast(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case Some{EQ{}}: True{}
    case _: False{}

def calculateContextTokens(usage: T.Usage) -> F.F64:
  match usage:
    case T.Usage{input, output, read, write, _, _, +total, _}:
      Bool.pick(F.F64, equalOrder(F.compare(total, F.fromU32(0))) || F.isNaN(total), F.add(F.add(F.add(input, output), read), write), total)

def textCharsFrom(text: String, chars: F.F64) -> F.F64:
  match text:
    case SNil{}: chars
    case SCon{Chr{code}, rest}: textCharsFrom(rest, F.add(chars, F.fromU32(Bool.pick(U32, U32.is_gt(code, 65535), 2, 1))))

def textChars(text: String) -> F.F64: textCharsFrom(text, F.fromU32(0))

def tokensForChars(chars: F.F64) -> F.F64:
  +quotient = F.divide(chars, F.fromU32(4))
  +whole = F.truncate(quotient)
  Bool.pick(F.F64, equalOrder(F.compare(quotient, whole)), whole, F.add(whole, F.fromU32(1)))

def estimateTextTokens(text: String) -> F.F64: tokensForChars(textChars(text))

def blockChars(blocks: List<&2, T.TextImageContent>, chars: F.F64) -> F.F64:
  match blocks:
    case Nil{}: chars
    case T.TextImageText{T.TextContent{text, _}} <> rest: blockChars(rest, F.add(chars, textChars(text)))
    case T.TextImageImage{_} <> rest: blockChars(rest, F.add(chars, F.fromU32(4800)))

def estimateTextAndImageContentTokens(content: T.UserContent) -> F.F64:
  match content:
    case T.UserText{text}: estimateTextTokens(text)
    case T.UserBlocks{blocks}: tokensForChars(blockChars(blocks, F.fromU32(0)))

def serializedText(result: Maybe<&2, String>) -> String:
  match result:
    case Some{text}: text
    case None{}: "[unserializable]"

def safeJsonStringify(value: T.JsonValue) -> String: serializedText(Json.stringify(value))

def toolValues(~P: Data, ~encode: P -> T.JsonValue, tools: List<&2, T.Tool<P>>) -> List<&2, T.JsonValue>:
  match tools:
    case Nil{}: Nil{}
    case T.Tool{name, description, parameters, sampling} <> rest:
      fields = {R.Record{R.Property{"name", T.JsonString{name}} <> R.Property{"description", T.JsonString{description}} <> R.Property{"parameters", encode(parameters)} <> Nil{}} : R.Record<T.JsonValue>}
      T.JsonObject{Declaration.addSampling(fields, sampling)} <> toolValues(~P, ~encode, rest)

def referenceValues(tools: List<&2, T.ToolReference>) -> List<&2, T.JsonValue>:
  match tools:
    case Nil{}: Nil{}
    case T.ToolReference{name} <> rest: T.JsonObject{R.Record{R.Property{"name", T.JsonString{name}} <> Nil{}}} <> referenceValues(rest)

def estimateToolsTokens(values: List<&2, T.JsonValue>) -> F.F64:
  match values:
    case Nil{}: F.fromU32(0)
    case head <> tail: estimateTextTokens(safeJsonStringify(T.JsonArray{head <> tail}))

def addedTokens(~P: Data, ~encode: P -> T.JsonValue, tools: Maybe<&2, List<&2, T.Tool<P>>>) -> F.F64:
  match tools:
    case None{}: F.fromU32(0)
    case Some{values}: estimateToolsTokens(toolValues(~P, ~encode, values))

def removedTokens(tools: Maybe<&2, List<&2, T.ToolReference>>) -> F.F64:
  match tools:
    case None{}: F.fromU32(0)
    case Some{values}: estimateToolsTokens(referenceValues(values))

def systemParts(~P: Data, ~encode: P -> T.JsonValue, message: T.SystemMessage<P>, text: F.F64) -> F.F64:
  match message:
    case T.SystemMessage{_, _, added, removed, _}: F.add(F.add(text, addedTokens(~P, ~encode, added)), removedTokens(removed))

def systemTokens(~P: Data, ~encode: P -> T.JsonValue, +message: T.SystemMessage<P>) -> F.F64:
  text = estimateTextTokens(Text.renderComplete(P, message))
  systemParts(~P, ~encode, message, text)

def assistantChars(~A: Data, ~encode: A -> T.JsonValue, blocks: List<&2, T.AssistantContent<A>>, chars: F.F64) -> F.F64:
  match blocks:
    case Nil{}: chars
    case T.AssistantText{T.TextContent{text, _}} <> rest: assistantChars(~A, ~encode, rest, F.add(chars, textChars(text)))
    case T.AssistantThinking{T.ThinkingContent{text, _, _}} <> rest: assistantChars(~A, ~encode, rest, F.add(chars, textChars(text)))
    case T.AssistantToolCall{T.ToolCall{_, name, arguments, _, _}} <> rest: assistantChars(~A, ~encode, rest, F.add(chars, F.add(textChars(name), textChars(safeJsonStringify(encode(arguments))))))

def estimateMessageTokensWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, message: T.Message<P, A, G, D>) -> F.F64:
  match message:
    case T.System{value}: systemTokens(~P, ~encodeParameters, value)
    case T.User{T.UserMessage{content, _}}: estimateTextAndImageContentTokens(content)
    case T.ToolResult{T.ToolResultMessage{_, _, content, _, _, _, _}}: estimateTextAndImageContentTokens(T.UserBlocks{content})
    case T.Assistant{T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: tokensForChars(assistantChars(~A, ~encodeArguments, content, F.fromU32(0)))

# Wire-schema convenience entry point; diagnostic and tool-result details do
# not contribute tokens and retain their caller-selected types.
def estimateMessageTokens(~G: Data, ~D: Data, message: T.Message<S.Value, S.Value, G, D>) -> F.F64:
  estimateMessageTokensWith(~S.Value, ~S.Value, ~G, ~D, ~SchemaJson.toJson, ~SchemaJson.toJson, message)

type Observation is Data:
  Observation{timestamp: F.F64, usage: Maybe<&2, F.F64>}

def successful(reason: T.StopReason) -> Bool:
  match reason:
    case T.Error{}: False{}
    case T.Aborted{}: False{}
    case _: True{}

def assistantObservation(~A: Data, ~G: Data, message: T.AssistantMessage<A, G>) -> Observation:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, usage, reason, _, _, _, _, timestamp}:
      +tokens = calculateContextTokens(usage)
      Observation{timestamp, Bool.pick(Maybe<&2, F.F64>, successful(reason) && positive(F.compare(tokens, F.fromU32(0))), Some{tokens}, None{})}

def observe(~P: Data, ~A: Data, ~G: Data, ~D: Data, message: T.Message<P, A, G, D>) -> Observation:
  match message:
    case T.System{T.SystemMessage{_, _, _, _, timestamp}}: Observation{timestamp, None{}}
    case T.User{T.UserMessage{_, timestamp}}: Observation{timestamp, None{}}
    case T.ToolResult{T.ToolResultMessage{_, _, _, _, _, _, timestamp}}: Observation{timestamp, None{}}
    case T.Assistant{value}: assistantObservation(~A, ~G, value)

def laterTimestamp(order: Maybe<&2, Cmp>, left: F.F64, right: F.F64) -> F.F64:
  match order:
    case None{}: F.nan()
    case Some{LT{}}: right
    case _: left

type EstimateState is Data:
  EstimateState{nextIndex: Nat, latestPrefixTimestamp: F.F64, usageTokens: F.F64, trailingTokens: F.F64, lastUsageIndex: Maybe<&2, Nat>}

def recordEstimate(applies: Bool, usage: Maybe<&2, F.F64>, +index: Nat, latest: F.F64, previousUsage: F.F64, trailing: F.F64, previousIndex: Maybe<&2, Nat>, estimated: F.F64) -> EstimateState:
  match applies usage:
    case True{} Some{tokens}: EstimateState{1n+index, latest, tokens, F.fromU32(0), Some{index}}
    case _ _: EstimateState{1n+index, latest, previousUsage, F.add(trailing, estimated), previousIndex}

def advance(state: EstimateState, observation: Observation, estimated: F.F64) -> EstimateState:
  match state observation:
    case EstimateState{index, +prefix, usage, trailing, last} Observation{+timestamp, reported}:
      recordEstimate(atLeast(F.compare(timestamp, prefix)), reported, index, laterTimestamp(F.compare(prefix, timestamp), prefix, timestamp), usage, trailing, last, estimated)

def finish(state: EstimateState) -> ContextUsageEstimate:
  match state:
    case EstimateState{_, _, +usage, +trailing, last}: ContextUsageEstimate{F.add(usage, trailing), usage, trailing, last}

# A single immutable fold selects the latest applicable usage and accumulates
# subsequent estimates. Later stale/error replies do not discard earlier usage.
def estimateFrom(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, messages: List<&2, T.Message<P, A, G, D>>, state: EstimateState) -> ContextUsageEstimate:
  match messages:
    case Nil{}: finish(state)
    case +head <> rest:
      estimateFrom(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, rest, advance(state, observe(~P, ~A, ~G, ~D, head), estimateMessageTokensWith(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, head)))

def estimateMessagesWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, messages: List<&2, T.Message<P, A, G, D>>) -> ContextUsageEstimate:
  estimateFrom(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, messages, EstimateState{0n, F.infinity(True{}), F.fromU32(0), F.fromU32(0), None{}})

def estimateContextTokensWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~encodeParameters: P -> T.JsonValue, ~encodeArguments: A -> T.JsonValue, context: T.TranscriptContext<P, A, G, D>) -> ContextUsageEstimate:
  match context:
    case T.TranscriptContext{messages}: estimateMessagesWith(~P, ~A, ~G, ~D, ~encodeParameters, ~encodeArguments, messages)

def estimateMessages(~G: Data, ~D: Data, messages: List<&2, T.Message<S.Value, S.Value, G, D>>) -> ContextUsageEstimate:
  estimateMessagesWith(~S.Value, ~S.Value, ~G, ~D, ~SchemaJson.toJson, ~SchemaJson.toJson, messages)

def estimateContextTokens(~G: Data, ~D: Data, context: T.TranscriptContext<S.Value, S.Value, G, D>) -> ContextUsageEstimate:
  estimateContextTokensWith(~S.Value, ~S.Value, ~G, ~D, ~SchemaJson.toJson, ~SchemaJson.toJson, context)
