import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/json.bend as Json
import ../utils/json-parse.bend as Parse
import ../utils/schema-json.bend as SchemaJson
import ./constrained-sampling.bend as Sampling
import ./openai-responses-shared.bend as Shared
import ./transform-messages.bend as Transform
import ./openai-sse.bend as Sse
import ../../../runtime/src/json.bend as D
import ../../../runtime/src/json.bend as JsonParse
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/utf16.bend as Utf16

# Response-side processing shared by the OpenAI Responses providers: decoding
# wire events, folding them into an immutable assistant message with ordered
# events, finalizing usage/stop reasons, and driving an event source to
# completion (`processResponsesStream`).

# Output items and content blocks
# -------------------------------

# Reasoning items are opaque provider replay tokens: keep their complete JSON,
# including unknown metadata. Other output items have ordinary native fields.
type OutputItem is Data:
  ReasoningItem{fields: R.Record<V.Value>}
  MessageItem{id: String, phase: Maybe<&2, T.TextSignaturePhase>, content: List<&2, String>}
  FunctionItem{id: String, callId: String, name: String, arguments: String, namespace: Maybe<&2, String>}
  CustomItem{id: String, callId: String, name: String, input: Maybe<&2, String>, namespace: Maybe<&2, String>}
  OtherItem{}

# Scratch state is private to streaming, never attached to a public ToolCall.
type Block is Data:
  Thinking{value: T.ThinkingContent}
  Text{value: T.TextContent}
  Function{value: T.ToolCall<V.Value>, partialJson: String}
  Custom{value: T.ToolCall<V.Value>, property: String, input: String, buffer: Sampling.GrammarToolInputJsonBuffer}
  Completed{value: T.AssistantContent<V.Value>}

type Input is Data:
  ThinkingDelta{delta: String}
  SummaryPartDone{}
  TextDelta{delta: String}
  FunctionDelta{delta: String}
  FunctionDone{arguments: String}
  CustomDelta{delta: String}
  CustomDone{input: String}
  ItemDone{item: OutputItem}

# Each signal owns the content at emission time; in particular the last custom
# input delta precedes a namespace supplied by output_item.done.
type Signal is Data:
  Started{content: T.AssistantContent<V.Value>}
  Delta{content: T.AssistantContent<V.Value>, delta: String}
  Ended{content: T.AssistantContent<V.Value>}

type BlockUpdate is Data:
  BlockUpdate{block: Block, signals: List<&2, Signal>, finished: Bool}

def blockContent(block: Block) -> T.AssistantContent<V.Value>:
  match block:
    case Thinking{value}: T.AssistantThinking{value}
    case Text{value}: T.AssistantText{value}
    case Function{value, _}: T.AssistantToolCall{value}
    case Custom{value, _, _, _}: T.AssistantToolCall{value}
    case Completed{value}: value

def unchangedBlock(block: Block) -> BlockUpdate: BlockUpdate{block, Nil{}, False{}}

def startedBlock(+block: Block) -> Maybe<&2, BlockUpdate>:
  Some{BlockUpdate{block, Started{blockContent(block)} <> Nil{}, False{}}}

def optionalText(text: Maybe<&2, String>, fallback: String) -> String:
  match text:
    case Some{value}: value
    case None{}: fallback

def inputArguments(property: String, input: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{property, V.Text{input}} <> Nil{}}}

def startBlock(item: OutputItem, properties: R.Record<String>) -> Maybe<&2, BlockUpdate>:
  match item:
    case ReasoningItem{_}: startedBlock(Thinking{T.ThinkingContent{"", None{}, None{}}})
    case MessageItem{_, _, _}: startedBlock(Text{T.TextContent{"", None{}}})
    case FunctionItem{id, callId, name, arguments, namespace}: startedBlock(Function{T.ToolCall{callId ++ "|" ++ id, name, V.ObjectValue{R.new(V.Value)}, None{}, namespace}, arguments})
    case CustomItem{id, callId, +name, input, namespace}:
      +property = optionalText(R.get(String, properties, name), "input")
      +text = optionalText(input, "")
      startedBlock(Custom{T.ToolCall{callId ++ "|" ++ id, name, inputArguments(property, text), None{}, namespace}, property, text, Sampling.GrammarToolInputJsonBuffer{"", False{}, False{}}})
    case OtherItem{}: None{}

def deltaBlock(+block: Block, text: String) -> BlockUpdate:
  BlockUpdate{block, Delta{blockContent(block), text} <> Nil{}, False{}}

def optionalDelta(+block: Block, text: Maybe<&2, String>) -> BlockUpdate:
  match text:
    case None{}: unchangedBlock(block)
    case Some{value}: deltaBlock(block, value)

def nonemptySuffix(suffix: Maybe<&2, String>) -> Maybe<&2, String>:
  match suffix:
    case Some{""}: None{}
    case Some{text}: Some{Utf16.normalize(text)}
    case None{}: None{}

def withArguments(tool: T.ToolCall<V.Value>, value: V.Value) -> T.ToolCall<V.Value>:
  match tool:
    case T.ToolCall{id, name, _, signature, namespace}: T.ToolCall{id, name, value, signature, namespace}

def withNamespace(tool: T.ToolCall<V.Value>, replacement: Maybe<&2, String>) -> T.ToolCall<V.Value>:
  match tool replacement:
    case value None{}: value
    case T.ToolCall{id, name, args, signature, _} Some{text}: T.ToolCall{id, name, args, signature, Some{text}}

def customUpdated(tool: T.ToolCall<V.Value>, +property: String, +input: String, result: Result<&2, &2, Sampling.Error, Sampling.GrammarToolInputJsonUpdate>) -> Result<&2, &2, Sampling.Error, BlockUpdate>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Sampling.GrammarToolInputJsonUpdate{buffer, emitted}}: Done{optionalDelta(Custom{withArguments(tool, inputArguments(property, input)), property, input, buffer}, emitted)}

def customInput(tool: T.ToolCall<V.Value>, +property: String, +input: String, buffer: Sampling.GrammarToolInputJsonBuffer, close: Bool) -> Result<&2, &2, Sampling.Error, BlockUpdate>:
  customUpdated(tool, property, input, Sampling.appendGrammarToolInputJsonDelta(buffer, property, input, close))

def joinTexts(parts: List<&2, String>, +separator: String) -> String:
  match parts:
    case Nil{}: ""
    case text <> Nil{}: text
    case text <> rest: text ++ separator ++ joinTexts(rest, separator)

def textField(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def reasoningTexts(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.ObjectValue{fields} <> rest: textField(R.get(V.Value, fields, "text")) <> reasoningTexts(rest)
    case _ <> rest: "" <> reasoningTexts(rest)

def reasoningText(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.ArrayValue{values}}: joinTexts(reasoningTexts(values), "\n\n")
    case _: ""

def orText(text: String, fallback: String) -> String:
  match text:
    case "": fallback
    case other: other

def endedBlock(+value: T.AssistantContent<V.Value>) -> BlockUpdate:
  BlockUpdate{Completed{value}, Ended{value} <> Nil{}, True{}}

def customEnded(result: Result<&2, &2, Sampling.Error, BlockUpdate>, replacement: Maybe<&2, String>) -> Result<&2, &2, Sampling.Error, BlockUpdate>:
  match result:
    case Fail{error}: Fail{error}
    case Done{BlockUpdate{Custom{tool, _, _, _}, signals, _}}:
      +value = {T.AssistantToolCall{withNamespace(tool, replacement)} : T.AssistantContent<V.Value>}
      Done{BlockUpdate{Completed{value}, List.append(&2, Signal, signals, Ended{value} <> Nil{}), True{}}}
    case Done{update}: Done{update}

def finishBlock(block: Block, item: OutputItem) -> Result<&2, &2, Sampling.Error, BlockUpdate>:
  match block item:
    case Thinking{T.ThinkingContent{text, _, redacted}} ReasoningItem{+fields}:
      selected = orText(reasoningText(R.get(V.Value, fields, "summary")), orText(reasoningText(R.get(V.Value, fields, "content")), text))
      Done{endedBlock(T.AssistantThinking{T.ThinkingContent{selected, Json.stringify(SchemaJson.toJson(V.ObjectValue{fields})), redacted}})}
    case Text{_} MessageItem{id, phase, texts}: Done{endedBlock(T.AssistantText{T.TextContent{joinTexts(texts, ""), Some{Shared.encodeTextSignatureV1(id, phase)}}})}
    case Function{tool, partial} FunctionItem{_, _, _, final, replacement}:
      Done{endedBlock(T.AssistantToolCall{withNamespace(withArguments(tool, Parse.parseStreamingJson(Some{orText(final, orText(partial, "{}"))})), replacement)})}
    case Custom{tool, property, input, buffer} CustomItem{_, _, _, final, replacement}:
      customEnded(customInput(tool, property, optionalText(final, input), buffer, True{}), replacement)
    case other _: Done{unchangedBlock(other)}

def blockStep(block: Block, input: Input) -> Result<&2, &2, Sampling.Error, BlockUpdate>:
  match block input:
    case value ItemDone{item}: finishBlock(value, item)
    case Thinking{T.ThinkingContent{text, signature, redacted}} ThinkingDelta{+chunk}: Done{deltaBlock(Thinking{T.ThinkingContent{text ++ chunk, signature, redacted}}, chunk)}
    case Thinking{T.ThinkingContent{text, signature, redacted}} SummaryPartDone{}: Done{deltaBlock(Thinking{T.ThinkingContent{text ++ "\n\n", signature, redacted}}, "\n\n")}
    case Text{T.TextContent{text, signature}} TextDelta{+chunk}: Done{deltaBlock(Text{T.TextContent{text ++ chunk, signature}}, chunk)}
    case Function{tool, partial} FunctionDelta{+chunk}:
      +next = partial ++ chunk
      Done{deltaBlock(Function{withArguments(tool, Parse.parseStreamingJson(Some{next})), next}, chunk)}
    case Function{tool, previous} FunctionDone{+next}:
      optional = nonemptySuffix(Sampling.prefixSuffix(Sampling.codeUnits(previous), Sampling.codeUnits(next)))
      Done{optionalDelta(Function{withArguments(tool, Parse.parseStreamingJson(Some{next})), next}, optional)}
    case Custom{tool, property, text, buffer} CustomDelta{chunk}: customInput(tool, property, text ++ chunk, buffer, False{})
    case Custom{tool, property, _, buffer} CustomDone{text}: customInput(tool, property, text, buffer, True{})
    case other _: Done{unchangedBlock(other)}

# Output slots
# ------------

# Provider output indices and assistant content indices are distinct: items
# may arrive out of order, and replacing an output slot appends a new content
# block. Wire indices retain fixed-size binary64 values; sparse/large numeric
# keys never allocate unary naturals in proportion to their magnitude.
type Slot is Data:
  Slot{outputIndex: F64, contentIndex: Nat, block: Block}

type State<-G: Data> is Data:
  State{output: T.AssistantMessage<V.Value, G>, slots: List<&2, Slot>, reasoningBlocks: R.Record<Nat>, grammarProperties: R.Record<String>}

type ContentEvent is Data:
  Added{outputIndex: F64, item: OutputItem}
  Changed{outputIndex: F64, input: Input}

type Update<-G: Data> is Data:
  Update{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, Sampling.Error>}

def create(-G: Data, output: T.AssistantMessage<V.Value, G>, grammarProperties: R.Record<String>) -> State<G>:
  State{output, Nil{}, R.new(Nat), grammarProperties}

def stateOutput(-G: Data, state: State<G>) -> T.AssistantMessage<V.Value, G>:
  match state:
    case State{value, _, _, _}: value

def withOutput(-G: Data, state: State<G>, output: T.AssistantMessage<V.Value, G>) -> State<G>:
  match state:
    case State{_, slots, refs, properties}: State{output, slots, refs, properties}

def messageBlocks(-G: Data, message: T.AssistantMessage<V.Value, G>) -> List<&2, T.AssistantContent<V.Value>>:
  match message:
    case T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def count(values: List<&2, T.AssistantContent<V.Value>>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(rest)

def numericIndex(index: Nat) -> F64:
  match index:
    case 0n: F.fromU32(0)
    case 1n+rest: F.add(F.fromU32(1), numericIndex(rest))

def findSlot(slots: List<&2, Slot>, +index: F64) -> Maybe<&2, Slot>:
  match slots:
    case Nil{}: None{}
    case Slot{+key, position, block} <> rest: Bool.pick(Maybe<&2, Slot>, V.equal(V.Number{key}, V.Number{index}), Some{Slot{key, position, block}}, findSlot(rest, index))

def removeSlot(slots: List<&2, Slot>, +index: F64) -> List<&2, Slot>:
  match slots:
    case Nil{}: Nil{}
    case Slot{+key, position, block} <> rest:
      +tail = removeSlot(rest, index)
      Bool.pick(List<&2, Slot>, V.equal(V.Number{key}, V.Number{index}), tail, Slot{key, position, block} <> tail)

# Only the internal append position may reach Nil; all other positions came
# from an existing slot. Replacing a block never mutates retained snapshots.
def replaceBlock(values: List<&2, T.AssistantContent<V.Value>>, index: Nat, value: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values index:
    case Nil{} _: value <> Nil{}
    case _ <> rest 0n: value <> rest
    case head <> rest 1n+tail: head <> replaceBlock(rest, tail, value)

def withBlock(-G: Data, +message: T.AssistantMessage<V.Value, G>, index: Nat, value: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  Transform.withContent(V.Value, G, message, replaceBlock(messageBlocks(G, message), index, value))

def withStopReason(-G: Data, message: T.AssistantMessage<V.Value, G>, reason: T.StopReason) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, endTurn, time}

def applyMessagePhaseStopReason(-G: Data, state: State<G>, item: OutputItem) -> State<G>:
  match state item:
    case State{message, slots, reasoning, properties} MessageItem{_, Some{T.FinalAnswer{}}, _}: State{withStopReason(G, message, T.Stop{}), slots, reasoning, properties}
    case other _: other

def startedEvent(-G: Data, index: F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{_}: T.TextStart{index, message}
    case T.AssistantThinking{_}: T.ThinkingStart{index, message}
    case T.AssistantToolCall{_}: T.ToolcallStart{index, message}

def deltaEvent(-G: Data, index: F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>, delta: String) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{_}: T.TextDelta{index, delta, message}
    case T.AssistantThinking{_}: T.ThinkingDelta{index, delta, message}
    case T.AssistantToolCall{_}: T.ToolcallDelta{index, delta, message}

def endedEvent(-G: Data, index: F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{T.TextContent{text, _}}: T.TextEnd{index, text, message}
    case T.AssistantThinking{T.ThinkingContent{text, _, _}}: T.ThinkingEnd{index, text, message}
    case T.AssistantToolCall{value}: T.ToolcallEnd{index, value, message}

def signalContent(signal: Signal) -> T.AssistantContent<V.Value>:
  match signal:
    case Started{value}: value
    case Delta{value, _}: value
    case Ended{value}: value

def signalEvent(-G: Data, index: Nat, message: T.AssistantMessage<V.Value, G>, signal: Signal) -> T.AssistantMessageEvent<V.Value, G>:
  match signal:
    case Started{value}: startedEvent(G, numericIndex(index), message, value)
    case Delta{value, delta}: deltaEvent(G, numericIndex(index), message, value, delta)
    case Ended{value}: endedEvent(G, numericIndex(index), message, value)

type Emission<-G: Data> is Data:
  Emission{output: T.AssistantMessage<V.Value, G>, reversed: List<&2, T.AssistantMessageEvent<V.Value, G>>}

def emitOne(-G: Data, +index: Nat, current: Emission<G>, +signal: Signal) -> Emission<G>:
  match current:
    case Emission{message, reversed}:
      +next = withBlock(G, message, index, signalContent(signal))
      Emission{next, signalEvent(G, index, next, signal) <> reversed}

def emitAll(-G: Data, signals: List<&2, Signal>, +index: Nat, current: Emission<G>) -> Emission<G>:
  match signals:
    case Nil{}: current
    case head <> tail: emitAll(G, tail, index, emitOne(G, index, current, head))

def slotsAfter(slots: List<&2, Slot>, +key: F64, position: Nat, block: Block, finished: Bool) -> List<&2, Slot>:
  match finished:
    case True{}: removeSlot(slots, key)
    case False{}: Slot{key, position, block} <> removeSlot(slots, key)

def reasoningAfter(refs: R.Record<Nat>, position: Nat, finished: Bool, item: Maybe<&2, OutputItem>) -> R.Record<Nat>:
  match finished item:
    case True{} Some{ReasoningItem{fields}}: R.set(Nat, refs, textField(R.get(V.Value, fields, "id")), position)
    case _ _: refs

def committed(-G: Data, slots: List<&2, Slot>, refs: R.Record<Nat>, properties: R.Record<String>, +position: Nat, block: Block, emission: Emission<G>) -> Update<G>:
  match emission:
    case Emission{message, reversed}: Update{State{withBlock(G, message, position, blockContent(block)), slots, refs, properties}, List.reverse(&2, T.AssistantMessageEvent<V.Value, G>, reversed), None{}}

def applyUpdate(-G: Data, state: State<G>, key: F64, +position: Nat, item: Maybe<&2, OutputItem>, update: BlockUpdate) -> Update<G>:
  match state update:
    case State{message, slots, refs, properties} BlockUpdate{+block, signals, +finished}:
      committed(G, slotsAfter(slots, key, position, block, finished), reasoningAfter(refs, position, finished, item), properties, position, block, emitAll(G, signals, position, Emission{message, Nil{}}))

def unchangedState(-G: Data, state: State<G>) -> Update<G>: Update{state, Nil{}, None{}}

def createdSlot(-G: Data, +state: State<G>, key: F64, value: Maybe<&2, BlockUpdate>) -> Update<G>:
  match value:
    case None{}: unchangedState(G, state)
    case Some{update}: applyUpdate(G, state, key, count(messageBlocks(G, stateOutput(G, state))), None{}, update)

def addSlot(-G: Data, state: State<G>, key: F64, item: OutputItem) -> Update<G>:
  match state:
    case State{message, slots, refs, +properties}: createdSlot(G, State{message, slots, refs, properties}, key, startBlock(item, properties))

def appliedStep(-G: Data, state: State<G>, key: F64, position: Nat, item: Maybe<&2, OutputItem>, result: Result<&2, &2, Sampling.Error, BlockUpdate>) -> Update<G>:
  match result:
    case Fail{error}: Update{state, Nil{}, Some{error}}
    case Done{update}: applyUpdate(G, state, key, position, item, update)

def doneItem(input: Input) -> Maybe<&2, OutputItem>:
  match input:
    case ItemDone{item}: Some{item}
    case _: None{}

def changeExisting(-G: Data, state: State<G>, slot: Maybe<&2, Slot>, +input: Input) -> Update<G>:
  match slot:
    case None{}: unchangedState(G, state)
    case Some{Slot{key, position, block}}: appliedStep(G, state, key, position, doneItem(input), blockStep(block, input))

def changeSlot(-G: Data, state: State<G>, key: F64, input: Input) -> Update<G>:
  match state:
    case State{message, +slots, refs, properties}: changeExisting(G, State{message, slots, refs, properties}, findSlot(slots, key), input)

def prependEvents(-G: Data, earlier: List<&2, T.AssistantMessageEvent<V.Value, G>>, update: Update<G>) -> Update<G>:
  match update:
    case Update{state, events, error}: Update{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, earlier, events), error}

def finishCreated(-G: Data, key: F64, item: OutputItem, update: Update<G>) -> Update<G>:
  match update:
    case Update{state, events, _}: prependEvents(G, events, changeSlot(G, state, key, ItemDone{item}))

# output_item.done for an unknown slot creates it first (getOrCreateSlot).
def finishSlot(-G: Data, state: State<G>, +key: F64, +item: OutputItem, slot: Maybe<&2, Slot>) -> Update<G>:
  match slot:
    case None{}: finishCreated(G, key, item, addSlot(G, state, key, item))
    case some: changeExisting(G, state, some, ItemDone{item})

def contentStep(-G: Data, state: State<G>, input: ContentEvent) -> Update<G>:
  match state input:
    case value Added{key, +item}: addSlot(G, applyMessagePhaseStopReason(G, value, item), key, item)
    case State{message, +slots, refs, properties} Changed{+key, ItemDone{+item}}: finishSlot(G, applyMessagePhaseStopReason(G, State{message, slots, refs, properties}, item), key, item, findSlot(slots, key))
    case value Changed{key, input}: changeSlot(G, value, key, input)

# Terminal responses
# ------------------

# Missing usage fields are distinct from an absent usage record: the latter
# retains previous accounting, but both paths recalculate cost.
type ResponseUsage is Data:
  ResponseUsage{input: Maybe<&2, F64>, output: Maybe<&2, F64>, cached: Maybe<&2, F64>, cacheWrite: Maybe<&2, F64>, reasoning: Maybe<&2, F64>, total: Maybe<&2, F64>}

type Response is Data:
  Response{id: Maybe<&2, String>, status: Maybe<&2, String>, incompleteReason: Maybe<&2, String>, output: List<&2, OutputItem>, usage: Maybe<&2, ResponseUsage>, serviceTier: Maybe<&2, String>}

type ProviderError is Data:
  ProviderError{code: Maybe<&2, String>, message: Maybe<&2, String>}

type TerminalError is Data:
  InvalidReasoningSignature{}
  UnhandledStopReason{status: String}
  ProviderFailure{message: String}
  MissingTerminalResponse{}

def terminalMessage(error: TerminalError) -> String:
  match error:
    case InvalidReasoningSignature{}: "Invalid stored Responses reasoning signature"
    case UnhandledStopReason{status}: "Unhandled stop reason: " ++ status
    case ProviderFailure{message}: message
    case MissingTerminalResponse{}: "OpenAI Responses stream ended before a terminal response event"

type Terminal<-G: Data> is Data:
  Terminal{state: State<G>, error: Maybe<&2, TerminalError>}

def withResponseId(-G: Data, message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, _, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

def withOptionalResponseId(-G: Data, message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match id:
    case None{}: message
    case Some{""}: message
    case other: withResponseId(G, message, other)

def getUsage(-G: Data, message: T.AssistantMessage<V.Value, G>) -> T.Usage:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, value, _, _, _, _, _, _}: value

def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, usage: T.Usage) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, _, stop, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

def normalizedNumber(+number: F64, compared: Maybe<&2, Cmp>) -> F64:
  match compared:
    case None{}: F.fromU32(0)
    case Some{EQ{}}: F.fromU32(0)
    case _: number

def usageNumber(value: Maybe<&2, F64>) -> F64:
  match value:
    case None{}: F.fromU32(0)
    case Some{+amount}: normalizedNumber(amount, F.compare(amount, F.fromU32(0)))

def nonnegative(value: F64, compared: Maybe<&2, Cmp>) -> F64:
  match compared:
    case Some{LT{}}: F.fromU32(0)
    case Some{EQ{}}: F.fromU32(0)
    case _: value

# OpenAI includes cached and cache-write tokens in input_tokens: subtract both.
def inputTokens(input: F64, cached: F64, written: F64) -> F64:
  +remaining = F.subtract(F.subtract(input, cached), written)
  nonnegative(remaining, F.compare(remaining, F.fromU32(0)))

def responseUsage(previous: T.Usage, value: Maybe<&2, ResponseUsage>) -> T.Usage:
  match value:
    case None{}: previous
    case Some{ResponseUsage{input, output, cached, written, reasoning, total}}:
      +read = usageNumber(cached)
      +write = usageNumber(written)
      +zero = F.fromU32(0)
      T.Usage{inputTokens(usageNumber(input), read, write), usageNumber(output), read, write, None{}, Some{usageNumber(reasoning)}, usageNumber(total), T.UsageCost{zero, zero, zero, zero, zero}}

def withCost(usage: T.Usage, cost: T.UsageCost) -> T.Usage:
  match usage:
    case T.Usage{input, output, read, write, longWrite, reasoning, total, _}: T.Usage{input, output, read, write, longWrite, reasoning, total, cost}

def accounting(-G: Data, +message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>, incoming: Maybe<&2, ResponseUsage>, cost: T.ModelCost) -> T.AssistantMessage<V.Value, G>:
  +next = responseUsage(getUsage(G, message), incoming)
  withUsage(G, withOptionalResponseId(G, message, id), withCost(next, Cost.compute(cost, next)))

# Azure can omit reasoning.encrypted_content from output_item.done and provide
# it only in response.completed.response.output. Backfill the persisted
# signature so store:false multi-turn replay stays stateless (pi#6409).
def encodeSignature(fields: R.Record<V.Value>, encrypted: String) -> Maybe<&2, String>:
  Json.stringify(SchemaJson.toJson(V.ObjectValue{R.set(V.Value, fields, "encrypted_content", V.Text{encrypted})}))

def encodedSignature(value: Maybe<&2, String>) -> Result<&2, &2, TerminalError, String>:
  match value:
    case None{}: Fail{InvalidReasoningSignature{}}
    case Some{text}: Done{text}

def selectedSignature(text: String, encrypted: String, fields: R.Record<V.Value>, existing: String) -> Result<&2, &2, TerminalError, String>:
  match existing:
    case "": encodedSignature(encodeSignature(fields, encrypted))
    case _: Done{text}

def decodedSignature(text: String, encrypted: String, parsed: Result<&2, &2, JsonParse.ParseError, V.Value>) -> Result<&2, &2, TerminalError, String>:
  match parsed:
    case Done{V.ObjectValue{+fields}}: selectedSignature(text, encrypted, fields, textField(R.get(V.Value, fields, "encrypted_content")))
    case _: Fail{InvalidReasoningSignature{}}

def thinkingSignature(text: String, redacted: Maybe<&2, Bool>, result: Result<&2, &2, TerminalError, String>) -> Result<&2, &2, TerminalError, T.AssistantContent<V.Value>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{signature}: Done{T.AssistantThinking{T.ThinkingContent{text, Some{signature}, redacted}}}

def repairStored(text: String, redacted: Maybe<&2, Bool>, +stored: String, encrypted: String) -> Result<&2, &2, TerminalError, T.AssistantContent<V.Value>>:
  match stored:
    case "": Done{T.AssistantThinking{T.ThinkingContent{text, Some{""}, redacted}}}
    case +signature: thinkingSignature(text, redacted, decodedSignature(signature, encrypted, JsonParse.parse(signature)))

def repairBlock(block: T.AssistantContent<V.Value>, +encrypted: String) -> Result<&2, &2, TerminalError, T.AssistantContent<V.Value>>:
  match block:
    case T.AssistantThinking{T.ThinkingContent{text, Some{+stored}, redacted}}: repairStored(text, redacted, stored, encrypted)
    case other: Done{other}

def prependRepaired(block: T.AssistantContent<V.Value>, result: Result<&2, &2, TerminalError, List<&2, T.AssistantContent<V.Value>>>) -> Result<&2, &2, TerminalError, List<&2, T.AssistantContent<V.Value>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{block <> rest}

def repairedHead(result: Result<&2, &2, TerminalError, T.AssistantContent<V.Value>>, rest: List<&2, T.AssistantContent<V.Value>>) -> Result<&2, &2, TerminalError, List<&2, T.AssistantContent<V.Value>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{block}: Done{block <> rest}

def repairAt(blocks: List<&2, T.AssistantContent<V.Value>>, index: Nat, encrypted: String) -> Result<&2, &2, TerminalError, List<&2, T.AssistantContent<V.Value>>>:
  match blocks index:
    case Nil{} _: Done{Nil{}}
    case head <> rest 0n: repairedHead(repairBlock(head, encrypted), rest)
    case head <> rest 1n+tail: prependRepaired(head, repairAt(rest, tail, encrypted))

def backfilled(-G: Data, +state: State<G>, result: Result<&2, &2, TerminalError, List<&2, T.AssistantContent<V.Value>>>) -> Terminal<G>:
  match result:
    case Fail{error}: Terminal{state, Some{error}}
    case Done{blocks}: Terminal{withOutput(G, state, Transform.withContent(V.Value, G, stateOutput(G, state), blocks)), None{}}

def repairReference(-G: Data, +state: State<G>, encrypted: String, reference: Maybe<&2, Nat>) -> Terminal<G>:
  match encrypted reference:
    case "" _: Terminal{state, None{}}
    case _ None{}: Terminal{state, None{}}
    case text Some{position}: backfilled(G, state, repairAt(messageBlocks(G, stateOutput(G, state)), position, text))

def backfillItem(-G: Data, state: State<G>, item: OutputItem) -> Terminal<G>:
  match state item:
    case State{message, slots, +refs, properties} ReasoningItem{+fields}:
      repairReference(G, State{message, slots, refs, properties}, textField(R.get(V.Value, fields, "encrypted_content")), R.get(Nat, refs, textField(R.get(V.Value, fields, "id"))))
    case other _: Terminal{other, None{}}

def backfill(-G: Data, items: List<&2, OutputItem>, current: Terminal<G>) -> Terminal<G>:
  match items current:
    case _ Terminal{state, Some{error}}: Terminal{state, Some{error}}
    case Nil{} other: other
    case head <> rest Terminal{state, None{}}: backfill(G, rest, backfillItem(G, state, head))

def accounted(-G: Data, id: Maybe<&2, String>, incoming: Maybe<&2, ResponseUsage>, cost: T.ModelCost, current: Terminal<G>) -> Terminal<G>:
  match current:
    case Terminal{state, Some{error}}: Terminal{state, Some{error}}
    case Terminal{+state, None{}}: Terminal{withOutput(G, state, accounting(G, stateOutput(G, state), id, incoming, cost)), None{}}

def resolveServiceTier(response: Maybe<&2, String>, requested: Maybe<&2, String>) -> Maybe<&2, String>:
  match response:
    case None{}: requested
    case some: some

def withRawStopReason(-G: Data, message: T.AssistantMessage<V.Value, G>, raw: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, _, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

type MappedStop is Data:
  MappedStop{reason: T.StopReason, errorMessage: Maybe<&2, String>}

# Incomplete responses retain the provider's reason so max-output truncation
# and content filtering stay distinct.
def incomplete(reason: Maybe<&2, String>) -> MappedStop:
  match reason:
    case Some{"max_output_tokens"}: MappedStop{T.Length{}, None{}}
    case None{}: MappedStop{T.Error{}, Some{"Response incomplete without a provider reason"}}
    case Some{""}: MappedStop{T.Error{}, Some{"Response incomplete without a provider reason"}}
    case Some{text}: MappedStop{T.Error{}, Some{"Response incomplete: " ++ text}}

def mapStopReason(status: Maybe<&2, String>, reason: Maybe<&2, String>) -> Result<&2, &2, TerminalError, MappedStop>:
  match status:
    case None{}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{""}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"completed"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"incomplete"}: Done{incomplete(reason)}
    case Some{"failed"}: Done{MappedStop{T.Error{}, None{}}}
    case Some{"cancelled"}: Done{MappedStop{T.Error{}, None{}}}
    case Some{"in_progress"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"queued"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{text}: Fail{UnhandledStopReason{text}}

def hasToolCall(blocks: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

def toolStop(stop: T.StopReason, tool: Bool) -> T.StopReason:
  match stop tool:
    case T.Stop{} True{}: T.ToolUse{}
    case reason _: reason

def withStop(-G: Data, message: T.AssistantMessage<V.Value, G>, mapped: MappedStop) -> T.AssistantMessage<V.Value, G>:
  match message mapped:
    case T.AssistantMessage{+content, api, provider, model, responseModel, id, thinking, diagnostics, usage, _, deferred, _, raw, endTurn, time} MappedStop{reason, error}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, toolStop(reason, hasToolCall(content)), deferred, error, raw, endTurn, time}

def rawReason(status: Maybe<&2, String>, reason: Maybe<&2, String>) -> Maybe<&2, String>:
  match reason:
    case None{}: status
    case Some{""}: status
    case Some{text}: Some{optionalText(status, "undefined") ++ "." ++ text}

def mappedStop(-G: Data, +state: State<G>, result: Result<&2, &2, TerminalError, MappedStop>) -> Terminal<G>:
  match result:
    case Fail{error}: Terminal{state, Some{error}}
    case Done{stop}: Terminal{withOutput(G, state, withStop(G, stateOutput(G, state), stop)), None{}}

def finishResponse(-G: Data, +state: State<G>, +status: Maybe<&2, String>, +reason: Maybe<&2, String>) -> Terminal<G>:
  mappedStop(G, withOutput(G, state, withRawStopReason(G, stateOutput(G, state), rawReason(status, reason))), mapStopReason(status, reason))

# Usage is accounted and priced before the stop reason is mapped. The pricing
# hooks are pure, so an unchanged usage means no tier pricing applies.
def priced(~J: Data, ~G: Data, ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, model: T.Model<J>, requested: Maybe<&2, String>, response: Maybe<&2, String>, status: Maybe<&2, String>, reason: Maybe<&2, String>, current: Terminal<G>) -> Terminal<G>:
  match current:
    case Terminal{state, Some{error}}: Terminal{state, Some{error}}
    case Terminal{+state, None{}}:
      finishResponse(G, withOutput(G, state, withUsage(G, stateOutput(G, state), applyPricing(model, resolveTier(response, requested), getUsage(G, stateOutput(G, state))))), status, reason)

def finalizeResponse(~J: Data, ~G: Data, ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, +model: T.Model<J>, requested: Maybe<&2, String>, state: State<G>, response: Response) -> Terminal<G>:
  match response:
    case Response{id, +status, +reason, items, usage, tier}:
      priced(~J, ~G, ~resolveTier, ~applyPricing, model, requested, tier, status, reason, accounted(G, id, usage, Cost.modelCost(J, model), backfill(G, items, Terminal{state, None{}})))

def failureReason(reason: Maybe<&2, String>) -> String:
  match reason:
    case None{}: ""
    case Some{""}: ""
    case Some{text}: "incomplete: " ++ text

def failureMessage(error: Maybe<&2, ProviderError>, reason: Maybe<&2, String>) -> String:
  match error:
    case Some{ProviderError{code, message}}: orText(optionalText(code, ""), "unknown") ++ ": " ++ orText(optionalText(message, ""), "no message")
    case None{}: orText(failureReason(reason), "Unknown error (no error details in response)")

def failedResponse(-G: Data, +state: State<G>, status: Maybe<&2, String>, error: Maybe<&2, ProviderError>, reason: Maybe<&2, String>) -> Terminal<G>:
  Terminal{withOutput(G, state, withRawStopReason(G, stateOutput(G, state), status)), Some{ProviderFailure{failureMessage(error, reason)}}}

def streamError(code: Maybe<&2, String>, message: String) -> TerminalError:
  ProviderFailure{"Error Code " ++ optionalText(code, "null") ++ ": " ++ message}

# Wire decoding
# -------------

type ResponseStreamEvent is Data:
  ContentEvent{value: ContentEvent}
  ResponseCreated{id: String}
  ResponseCompleted{response: Response}
  ResponseIncomplete{response: Response}
  ResponseFailed{status: Maybe<&2, String>, error: Maybe<&2, ProviderError>, reason: Maybe<&2, String>}
  ResponseError{code: Maybe<&2, String>, message: String}
  IgnoredEvent{}

# Decode only fields consumed by pi. Opaque reasoning replay retains all fields.
def decodePhase(value: V.Value) -> Result<&2, &2, D.Error, T.TextSignaturePhase>:
  match value:
    case V.Text{"commentary"}: Done{T.Commentary{}}
    case V.Text{"final_answer"}: Done{T.FinalAnswer{}}
    case _: Fail{D.InvalidValue{Nil{}, "commentary or final_answer"}}

# Upstream joins text for output_text and refusal for other variants.
def decodePart(value: V.Value) -> Result<&2, &2, D.Error, String>:
  do Result<&2, &2, D.Error, String>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : String <- D.required(String, fields, "type", D.string)
    text : Maybe<&2, String> <- D.optional(String, fields, Bool.pick(String, String.eq(kind, "output_text"), "text", "refusal"), D.string)
    return Maybe.default(&2, String, text, "")

def decodeParts(value: V.Value) -> Result<&2, &2, D.Error, List<&2, String>>:
  D.list(~String, ~decodePart, value)

def decodeMessageItem(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, OutputItem>:
  do Result<&2, &2, D.Error, OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    phase : Maybe<&2, T.TextSignaturePhase> <- D.optional(T.TextSignaturePhase, fields, "phase", decodePhase)
    content : Maybe<&2, List<&2, String>> <- D.optional(List<&2, String>, fields, "content", decodeParts)
    return MessageItem{id, phase, Maybe.default(&2, List<&2, String>, content, Nil{})}

def decodeFunctionItem(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, OutputItem>:
  do Result<&2, &2, D.Error, OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    callId : String <- D.required(String, fields, "call_id", D.string)
    name : String <- D.required(String, fields, "name", D.string)
    arguments : Maybe<&2, String> <- D.optional(String, fields, "arguments", D.string)
    namespace : Maybe<&2, String> <- D.optional(String, fields, "namespace", D.string)
    return FunctionItem{id, callId, name, Maybe.default(&2, String, arguments, ""), namespace}

def decodeCustomItem(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, OutputItem>:
  do Result<&2, &2, D.Error, OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    callId : String <- D.required(String, fields, "call_id", D.string)
    name : String <- D.required(String, fields, "name", D.string)
    input : Maybe<&2, String> <- D.optional(String, fields, "input", D.string)
    namespace : Maybe<&2, String> <- D.optional(String, fields, "namespace", D.string)
    return CustomItem{id, callId, name, input, namespace}

def taggedItem(kind: Maybe<&2, String>, fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, OutputItem>:
  match kind:
    case Some{"reasoning"}: Done{ReasoningItem{fields}}
    case Some{"message"}: decodeMessageItem(fields)
    case Some{"function_call"}: decodeFunctionItem(fields)
    case Some{"custom_tool_call"}: decodeCustomItem(fields)
    case _: Done{OtherItem{}}

def decodeItem(value: V.Value) -> Result<&2, &2, D.Error, OutputItem>:
  do Result<&2, &2, D.Error, OutputItem>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : Maybe<&2, String> <- D.optional(String, fields, "type", D.string)
    taggedItem(kind, fields)

# Optional nested fields preserve absence instead of inventing zero accounting.
def details(fields: Maybe<&2, R.Record<V.Value>>) -> R.Record<V.Value>:
  Maybe.default(&2, R.Record<V.Value>, fields, R.new(V.Value))

def decodeUsage(value: V.Value) -> Result<&2, &2, D.Error, ResponseUsage>:
  do Result<&2, &2, D.Error, ResponseUsage>:
    +fields : R.Record<V.Value> <- D.object(value)
    input : Maybe<&2, F64> <- D.optional(F64, fields, "input_tokens", D.number)
    output : Maybe<&2, F64> <- D.optional(F64, fields, "output_tokens", D.number)
    total : Maybe<&2, F64> <- D.optional(F64, fields, "total_tokens", D.number)
    inputDetails : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "input_tokens_details", D.object)
    outputDetails : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "output_tokens_details", D.object)
    +inputFields : R.Record<V.Value> = details(inputDetails)
    cached : Maybe<&2, F64> <- D.located(Maybe<&2, F64>, D.optional(F64, inputFields, "cached_tokens", D.number), D.Field{"input_tokens_details"})
    written : Maybe<&2, F64> <- D.located(Maybe<&2, F64>, D.optional(F64, inputFields, "cache_write_tokens", D.number), D.Field{"input_tokens_details"})
    reasoning : Maybe<&2, F64> <- D.located(Maybe<&2, F64>, D.optional(F64, details(outputDetails), "reasoning_tokens", D.number), D.Field{"output_tokens_details"})
    return ResponseUsage{input, output, cached, written, reasoning, total}

def decodeReason(value: V.Value) -> Result<&2, &2, D.Error, Maybe<&2, String>>:
  do Result<&2, &2, D.Error, Maybe<&2, String>>:
    fields : R.Record<V.Value> <- D.object(value)
    D.optional(String, fields, "reason", D.string)

def flatten(-A: Data, value: Maybe<&2, Maybe<&2, A>>) -> Maybe<&2, A>:
  match value:
    case None{}: None{}
    case Some{inner}: inner

def incompleteReason(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Maybe<&2, String>>:
  do Result<&2, &2, D.Error, Maybe<&2, String>>:
    value : Maybe<&2, Maybe<&2, String>> <- D.optional(Maybe<&2, String>, fields, "incomplete_details", decodeReason)
    return flatten(String, value)

def decodeOutput(value: V.Value) -> Result<&2, &2, D.Error, List<&2, OutputItem>>:
  D.list(~OutputItem, ~decodeItem, value)

def decodeResponse(value: V.Value) -> Result<&2, &2, D.Error, Response>:
  do Result<&2, &2, D.Error, Response>:
    +fields : R.Record<V.Value> <- D.object(value)
    id : Maybe<&2, String> <- D.optional(String, fields, "id", D.string)
    status : Maybe<&2, String> <- D.optional(String, fields, "status", D.string)
    reason : Maybe<&2, String> <- incompleteReason(fields)
    output : Maybe<&2, List<&2, OutputItem>> <- D.optional(List<&2, OutputItem>, fields, "output", decodeOutput)
    usage : Maybe<&2, ResponseUsage> <- D.optional(ResponseUsage, fields, "usage", decodeUsage)
    tier : Maybe<&2, String> <- D.optional(String, fields, "service_tier", D.string)
    return Response{id, status, reason, Maybe.default(&2, List<&2, OutputItem>, output, Nil{}), usage, tier}

def decodeProviderError(value: V.Value) -> Result<&2, &2, D.Error, ProviderError>:
  do Result<&2, &2, D.Error, ProviderError>:
    +fields : R.Record<V.Value> <- D.object(value)
    code : Maybe<&2, String> <- D.optional(String, fields, "code", D.string)
    message : Maybe<&2, String> <- D.optional(String, fields, "message", D.string)
    return ProviderError{code, message}

# Wire spelling is data: classify once, then dispatch on the native sum.
type EventKind is Data:
  CreatedKind{}
  AddedKind{}
  SummaryTextKind{}
  ReasoningTextKind{}
  SummaryPartKind{}
  OutputTextKind{}
  RefusalKind{}
  FunctionDeltaKind{}
  FunctionDoneKind{}
  CustomDeltaKind{}
  CustomDoneKind{}
  ItemDoneKind{}
  CompletedKind{}
  IncompleteKind{}
  FailedKind{}
  ErrorKind{}
  UnknownKind{}

def eventNames() -> R.Record<EventKind>:
  R.Record{
    R.Property{"response.created", CreatedKind{}} <>
    R.Property{"response.output_item.added", AddedKind{}} <>
    R.Property{"response.reasoning_summary_text.delta", SummaryTextKind{}} <>
    R.Property{"response.reasoning_text.delta", ReasoningTextKind{}} <>
    R.Property{"response.reasoning_summary_part.done", SummaryPartKind{}} <>
    R.Property{"response.output_text.delta", OutputTextKind{}} <>
    R.Property{"response.refusal.delta", RefusalKind{}} <>
    R.Property{"response.function_call_arguments.delta", FunctionDeltaKind{}} <>
    R.Property{"response.function_call_arguments.done", FunctionDoneKind{}} <>
    R.Property{"response.custom_tool_call_input.delta", CustomDeltaKind{}} <>
    R.Property{"response.custom_tool_call_input.done", CustomDoneKind{}} <>
    R.Property{"response.output_item.done", ItemDoneKind{}} <>
    R.Property{"response.completed", CompletedKind{}} <>
    R.Property{"response.incomplete", IncompleteKind{}} <>
    R.Property{"response.failed", FailedKind{}} <>
    R.Property{"error", ErrorKind{}} <>
    Nil{}
  }

def classifyEvent(value: Maybe<&2, String>) -> EventKind:
  match value:
    case None{}: UnknownKind{}
    case Some{name}: Maybe.default(&2, EventKind, R.get(EventKind, eventNames(), name), UnknownKind{})

def decodeAdded(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    index : F64 <- D.required(F64, fields, "output_index", D.number)
    item : OutputItem <- D.required(OutputItem, fields, "item", decodeItem)
    return ContentEvent{Added{index, item}}

def decodeChanged(+fields: R.Record<V.Value>, input: R.Record<V.Value> -> Result<&2, &2, D.Error, Input>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    index : F64 <- D.required(F64, fields, "output_index", D.number)
    value : Input <- input(fields)
    return ContentEvent{Changed{index, value}}

def textInput(fields: R.Record<V.Value>, key: String, make: String -> Input) -> Result<&2, &2, D.Error, Input>:
  Result.map(&2, &2, D.Error, String, Input, make, D.required(String, fields, key, D.string))

def itemDone(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Input>:
  Result.map(&2, &2, D.Error, OutputItem, Input, item => ItemDone{item}, D.required(OutputItem, fields, "item", decodeItem))

def decodeResponseId(value: V.Value) -> Result<&2, &2, D.Error, String>:
  do Result<&2, &2, D.Error, String>:
    fields : R.Record<V.Value> <- D.object(value)
    D.required(String, fields, "id", D.string)

def decodeCreated(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  Result.map(&2, &2, D.Error, String, ResponseStreamEvent, id => ResponseCreated{id}, D.required(String, fields, "response", decodeResponseId))

def decodeFinalized(fields: R.Record<V.Value>, complete: Bool) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    +response : Response <- D.required(Response, fields, "response", decodeResponse)
    return Bool.pick(ResponseStreamEvent, complete, ResponseCompleted{response}, ResponseIncomplete{response})

def decodeFailedResponse(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    status : Maybe<&2, String> <- D.optional(String, fields, "status", D.string)
    error : Maybe<&2, ProviderError> <- D.optional(ProviderError, fields, "error", decodeProviderError)
    reason : Maybe<&2, String> <- incompleteReason(fields)
    return ResponseFailed{status, error, reason}

def decodeFailed(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    response : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "response", D.object)
    D.located(ResponseStreamEvent, decodeFailedResponse(details(response)), D.Field{"response"})

def decodeError(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    code : Maybe<&2, String> <- D.optional(String, fields, "code", D.string)
    message : String <- D.required(String, fields, "message", D.string)
    return ResponseError{code, message}

def taggedEvent(kind: EventKind, fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  match kind:
    case CreatedKind{}: decodeCreated(fields)
    case AddedKind{}: decodeAdded(fields)
    case SummaryTextKind{}: decodeChanged(fields, record => textInput(record, "delta", text => ThinkingDelta{text}))
    case ReasoningTextKind{}: decodeChanged(fields, record => textInput(record, "delta", text => ThinkingDelta{text}))
    case SummaryPartKind{}: decodeChanged(fields, record => Done{SummaryPartDone{}})
    case OutputTextKind{}: decodeChanged(fields, record => textInput(record, "delta", text => TextDelta{text}))
    case RefusalKind{}: decodeChanged(fields, record => textInput(record, "delta", text => TextDelta{text}))
    case FunctionDeltaKind{}: decodeChanged(fields, record => textInput(record, "delta", text => FunctionDelta{text}))
    case FunctionDoneKind{}: decodeChanged(fields, record => textInput(record, "arguments", text => FunctionDone{text}))
    case CustomDeltaKind{}: decodeChanged(fields, record => textInput(record, "delta", text => CustomDelta{text}))
    case CustomDoneKind{}: decodeChanged(fields, record => textInput(record, "input", text => CustomDone{text}))
    case ItemDoneKind{}: decodeChanged(fields, itemDone)
    case CompletedKind{}: decodeFinalized(fields, True{})
    case IncompleteKind{}: decodeFinalized(fields, False{})
    case FailedKind{}: decodeFailed(fields)
    case ErrorKind{}: decodeError(fields)
    case _: Done{IgnoredEvent{}}

# Decode the event's JSON type discriminator, not the SSE event name. Fields
# unused by pi remain uninspected, including unknown future event variants.
def decodeEvent(value: V.Value) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  do Result<&2, &2, D.Error, ResponseStreamEvent>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : Maybe<&2, String> <- D.optional(String, fields, "type", D.string)
    taggedEvent(classifyEvent(kind), fields)

# SDK-synthesized envelopes have no top-level type, so pi ignores them.
def fromMessage(message: Sse.Message) -> Result<&2, &2, D.Error, ResponseStreamEvent>:
  match message:
    case Sse.JsonMessage{value}: decodeEvent(value)
    case Sse.EventMessage{_, _}: Done{IgnoredEvent{}}

# Event source over an SSE cursor
# -------------------------------

type ReaderError<-T: Data> is Data:
  StreamingFailure{cause: Sse.Error<T>}
  ProtocolFailure{cause: D.Error}

def EventStep(-T: Data) -> Type: Sse.Cursor<T> & Result<&2, &2, ReaderError<T>, Maybe<&2, ResponseStreamEvent>>

def closedAfterFailure(-T: Data, error: D.Error, closed: Sse.CloseResult<T>) -> EventStep(T):
  match closed:
    case Sse.CloseResult{cursor, _}: (cursor, Fail{ProtocolFailure{error}})

# Decode failures occur inside the iterator, so they close the lower stream
# before returning failure. A failing close never replaces that error.
def decoded(-T: Data, cursor: Sse.Cursor<T>, result: Result<&2, &2, D.Error, ResponseStreamEvent>) -> IO(EventStep(T)):
  match result:
    case Done{event}: IO.pure(EventStep(T), (cursor, Done{Some{event}}))
    case Fail{error}:
      do IO<EventStep(T)>:
        closed : Sse.CloseResult<T> <- Sse.close(T, cursor)
        return closedAfterFailure(T, error, closed)

def receivedMessage(-T: Data, next: Sse.Next<T>) -> IO(EventStep(T)):
  match next:
    case Sse.Next{cursor, Fail{error}}: IO.pure(EventStep(T), (cursor, Fail{StreamingFailure{error}}))
    case Sse.Next{cursor, Done{None{}}}: IO.pure(EventStep(T), (cursor, Done{None{}}))
    case Sse.Next{cursor, Done{Some{message}}}: decoded(T, cursor, fromMessage(message))

def nextEvent(-T: Data, cursor: Sse.Cursor<T>) -> IO(EventStep(T)):
  do IO<EventStep(T)>:
    pulled : Sse.Next<T> <- Sse.next(T, cursor)
    receivedMessage(T, pulled)

def closedEvents(-T: Data, result: Sse.CloseResult<T>) -> Sse.Cursor<T> & Result<&2, &2, ReaderError<T>, Unit>:
  match result:
    case Sse.CloseResult{cursor, Done{value}}: (cursor, Done{value})
    case Sse.CloseResult{cursor, Fail{error}}: (cursor, Fail{StreamingFailure{error}})

def closeEvents(-T: Data, cursor: Sse.Cursor<T>) -> IO(Sse.Cursor<T> & Result<&2, &2, ReaderError<T>, Unit>):
  do IO<Sse.Cursor<T> & Result<&2, &2, ReaderError<T>, Unit>>:
    result : Sse.CloseResult<T> <- Sse.close(T, cursor)
    return closedEvents(T, result)

# Processing
# ----------

type OpenAIResponsesStreamOptions is Data:
  OpenAIResponsesStreamOptions{serviceTier: Maybe<&2, String>, grammarToolInputProperties: R.Record<String>}

def defaultOptions() -> OpenAIResponsesStreamOptions:
  OpenAIResponsesStreamOptions{None{}, R.new(String)}

# Default hooks for processResponsesStream: the response's tier wins over the
# request's, and no tier pricing is applied.
def defaultResolveServiceTier(response: Maybe<&2, String>, requested: Maybe<&2, String>) -> Maybe<&2, String>:
  resolveServiceTier(response, requested)

def noServiceTierPricing(-J: Data, model: T.Model<J>, serviceTier: Maybe<&2, String>, usage: T.Usage) -> T.Usage: usage

type Error<-E: Data> is Data:
  ReadFailure{error: E}
  EmitFailure{error: E}
  ContentFailure{error: Sampling.Error}
  TerminalFailure{error: TerminalError}

type RunResult<-G: Data, -E: Data> is Data:
  RunResult{output: T.AssistantMessage<V.Value, G>, error: Maybe<&2, Error<E>>}

type RunState<-G: Data> is Data:
  RunState{content: State<G>, sawTerminalResponse: Bool}

type Step<-G: Data, -E: Data> is Data:
  Step{state: RunState<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, Error<E>>}

def finishRun(-G: Data, -E: Data, state: RunState<G>, error: Maybe<&2, Error<E>>) -> RunResult<G, E>:
  match state:
    case RunState{content, _}: RunResult{stateOutput(G, content), error}

def contentUpdate(-G: Data, -E: Data, terminal: Bool, update: Update<G>) -> Step<G, E>:
  match update:
    case Update{state, events, None{}}: Step{RunState{state, terminal}, events, None{}}
    case Update{state, events, Some{error}}: Step{RunState{state, terminal}, events, Some{ContentFailure{error}}}

def terminalUpdate(-G: Data, -E: Data, update: Terminal<G>) -> Step<G, E>:
  match update:
    case Terminal{state, None{}}: Step{RunState{state, True{}}, Nil{}, None{}}
    case Terminal{state, Some{error}}: Step{RunState{state, True{}}, Nil{}, Some{TerminalFailure{error}}}

def step(~J: Data, ~G: Data, ~E: Data, ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, model: T.Model<J>, requested: Maybe<&2, String>, state: RunState<G>, event: ResponseStreamEvent) -> Step<G, E>:
  match state event:
    case RunState{content, terminal} ContentEvent{value}: contentUpdate(G, E, terminal, contentStep(G, content, value))
    case RunState{+content, terminal} ResponseCreated{id}: Step{RunState{withOutput(G, content, withResponseId(G, stateOutput(G, content), Some{id})), terminal}, Nil{}, None{}}
    case RunState{content, _} ResponseCompleted{response}: terminalUpdate(G, E, finalizeResponse(~J, ~G, ~resolveTier, ~applyPricing, model, requested, content, response))
    case RunState{content, _} ResponseIncomplete{response}: terminalUpdate(G, E, finalizeResponse(~J, ~G, ~resolveTier, ~applyPricing, model, requested, content, response))
    case RunState{content, _} ResponseFailed{status, error, reason}: terminalUpdate(G, E, failedResponse(G, content, status, error, reason))
    case value ResponseError{code, message}: Step{value, Nil{}, Some{TerminalFailure{streamError(code, message)}}}
    case value IgnoredEvent{}: Step{value, Nil{}, None{}}

# The message carried by an event: the immutable snapshot at emission time.
def eventSnapshot(-G: Data, event: T.AssistantMessageEvent<V.Value, G>) -> T.AssistantMessage<V.Value, G>:
  match event:
    case T.Start{message}: message
    case T.TextStart{_, message}: message
    case T.TextDelta{_, _, message}: message
    case T.TextEnd{_, _, message}: message
    case T.ThinkingStart{_, message}: message
    case T.ThinkingDelta{_, _, message}: message
    case T.ThinkingEnd{_, _, message}: message
    case T.ToolcallStart{_, message}: message
    case T.ToolcallDelta{_, _, message}: message
    case T.ToolcallEnd{_, _, message}: message
    case T.StreamDone{_, message}: message
    case T.StreamError{_, message}: message

type Decision<-G: Data, -E: Data> is Data:
  Continue{state: RunState<G>}
  Finished{result: RunResult<G, E>, close: Bool}

# A failed sink can interrupt a two-event item completion: the result carries
# the snapshot at that emission, not the reducer's later content.
def emitted(-G: Data, -E: Data, event: T.AssistantMessageEvent<V.Value, G>, result: Result<&2, &2, E, Unit>) -> Result<&2, &2, RunResult<G, E>, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{RunResult{eventSnapshot(G, event), Some{EmitFailure{error}}}}

def published(-S: Type, -G: Data, -E: Data, event: T.AssistantMessageEvent<V.Value, G>, sent: S & Result<&2, &2, E, Unit>) -> S & Result<&2, &2, RunResult<G, E>, Unit>:
  match sent:
    case (source, result): (source, emitted(G, E, event, result))

def publish(~S: Type, ~E: Data, ~G: Data, ~emit: S -> T.AssistantMessageEvent<V.Value, G> -> IO(S & Result<&2, &2, E, Unit>), events: List<&2, T.AssistantMessageEvent<V.Value, G>>, pair: S & Result<&2, &2, RunResult<G, E>, Unit>) -> IO(S & Result<&2, &2, RunResult<G, E>, Unit>):
  match events pair:
    case _ Tuple{source, Fail{failure}}: IO.pure(S & Result<&2, &2, RunResult<G, E>, Unit>, (source, Fail{failure}))
    case Nil{} Tuple{source, Done{_}}: IO.pure(S & Result<&2, &2, RunResult<G, E>, Unit>, (source, Done{Unit{}}))
    case +head <> rest Tuple{source, Done{_}}:
      do IO<S & Result<&2, &2, RunResult<G, E>, Unit>>:
        sent : S & Result<&2, &2, E, Unit> <- emit(source, head)
        publish(~S, ~E, ~G, ~emit, rest, published(S, G, E, head, sent))

# A processor failure closes the iterator, like leaving a for-await loop with
# an exception; EOF and a failed read do not.
def delivered(-S: Type, -G: Data, -E: Data, state: RunState<G>, error: Maybe<&2, Error<E>>, pair: S & Result<&2, &2, RunResult<G, E>, Unit>) -> S & Decision<G, E>:
  match error pair:
    case _ Tuple{source, Fail{failure}}: (source, Finished{failure, True{}})
    case Some{failure} Tuple{source, Done{_}}: (source, Finished{finishRun(G, E, state, Some{failure}), True{}})
    case None{} Tuple{source, Done{_}}: (source, Continue{state})

def stepped(~S: Type, ~E: Data, ~G: Data, ~emit: S -> T.AssistantMessageEvent<V.Value, G> -> IO(S & Result<&2, &2, E, Unit>), source: S, next: Step<G, E>) -> IO(S & Decision<G, E>):
  match next:
    case Step{state, events, error}:
      do IO<S & Decision<G, E>>:
        pair : S & Result<&2, &2, RunResult<G, E>, Unit> <- publish(~S, ~E, ~G, ~emit, events, (source, Done{Unit{}}))
        return delivered(S, G, E, state, error, pair)

def endOfStream(sawTerminalResponse: Bool) -> Maybe<&2, TerminalError>:
  match sawTerminalResponse:
    case True{}: None{}
    case False{}: Some{MissingTerminalResponse{}}

def exhausted(-G: Data, -E: Data, state: RunState<G>) -> Decision<G, E>:
  match state:
    case RunState{content, terminal}: Finished{RunResult{stateOutput(G, content), Maybe.map(&2, TerminalError, Error<E>, error => TerminalFailure{error}, endOfStream(terminal))}, False{}}

def received(~J: Data, ~G: Data, ~E: Data, ~S: Type, ~emit: S -> T.AssistantMessageEvent<V.Value, G> -> IO(S & Result<&2, &2, E, Unit>), ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, model: T.Model<J>, requested: Maybe<&2, String>, state: RunState<G>, pulled: S & Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>) -> IO(S & Decision<G, E>):
  match pulled:
    case (source, Fail{error}): IO.pure(S & Decision<G, E>, (source, Finished{finishRun(G, E, state, Some{ReadFailure{error}}), False{}}))
    case (source, Done{None{}}): IO.pure(S & Decision<G, E>, (source, exhausted(G, E, state)))
    case (source, Done{Some{event}}): stepped(~S, ~E, ~G, ~emit, source, step(~J, ~G, ~E, ~resolveTier, ~applyPricing, model, requested, state, event))

def closedIteration(-S: Type, -G: Data, -E: Data, result: RunResult<G, E>, closed: S & Result<&2, &2, E, Unit>) -> S & RunResult<G, E>:
  match closed:
    case (source, _): (source, result)

# AsyncIteratorClose preserves an existing failure if return also fails.
def closeIteration(~S: Type, ~E: Data, ~close: S -> IO(S & Result<&2, &2, E, Unit>), -G: Data, source: S, result: RunResult<G, E>, closing: Bool) -> IO(S & RunResult<G, E>):
  match closing:
    case False{}: IO.pure(S & RunResult<G, E>, (source, result))
    case True{}:
      do IO<S & RunResult<G, E>>:
        closed : S & Result<&2, &2, E, Unit> <- close(source)
        return closedIteration(S, G, E, result, closed)

# The external iterator determines termination. Like the generic event stream,
# this loop has no artificial event/fuel limit.
@unsafe def loop(~S: Type, ~E: Data, ~J: Data, ~G: Data, ~next: S -> IO(S & Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>), ~close: S -> IO(S & Result<&2, &2, E, Unit>), ~emit: S -> T.AssistantMessageEvent<V.Value, G> -> IO(S & Result<&2, &2, E, Unit>), ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, +model: T.Model<J>, +requested: Maybe<&2, String>, pair: S & Decision<G, E>) -> IO(S & RunResult<G, E>):
  match pair:
    case (source, Finished{result, closing}): closeIteration(~S, ~E, ~close, G, source, result, closing)
    case (source, Continue{state}):
      do IO<S & RunResult<G, E>>:
        pulled : S & Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>> <- next(source)
        decided : S & Decision<G, E> <- received(~J, ~G, ~E, ~S, ~emit, ~resolveTier, ~applyPricing, model, requested, state, pulled)
        loop(~S, ~E, ~J, ~G, ~next, ~close, ~emit, ~resolveTier, ~applyPricing, model, requested, decided)

# Fold an event source into the assistant message, publishing each content
# event through the sink. The source is an affine iterator state with
# compile-time `next`/`close`/`emit` steps; the caller receives it back and
# owns its disposal. Pure service-tier hooks replace the upstream callbacks.
def processResponsesStream(~S: Type, ~E: Data, ~J: Data, ~G: Data, ~next: S -> IO(S & Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>), ~close: S -> IO(S & Result<&2, &2, E, Unit>), ~emit: S -> T.AssistantMessageEvent<V.Value, G> -> IO(S & Result<&2, &2, E, Unit>), ~resolveTier: Maybe<&2, String> -> Maybe<&2, String> -> Maybe<&2, String>, ~applyPricing: T.Model<J> -> Maybe<&2, String> -> T.Usage -> T.Usage, source: S, output: T.AssistantMessage<V.Value, G>, model: T.Model<J>, options: OpenAIResponsesStreamOptions) -> IO(S & RunResult<G, E>):
  match options:
    case OpenAIResponsesStreamOptions{requested, properties}:
      loop(~S, ~E, ~J, ~G, ~next, ~close, ~emit, ~resolveTier, ~applyPricing, model, requested, (source, Continue{RunState{create(G, output, properties), False{}}}))
