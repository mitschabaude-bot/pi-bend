import Base
import ../types.bend as T
import ./json.bend as Wire
import ./json-parse.bend as JsonParse
import ./schema-json.bend as Convert
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/u64.bend as W

# pi-mono utils/assistant-message-frame.ts: compact, replayable
# assistant-message progress. AssistantMessageFrameEncoder turns stream
# events into frames; terminal settlement is excluded and persisted
# separately. reduceAssistantMessageFrames replays frames into the message.
#
# Upstream's events share one live partial that may run ahead of a queued
# event; the encoder records per-block offsets (in UTF-16 code units, as
# JavaScript string lengths) so a delta already visible in a start snapshot
# is not replayed. Here each event carries the partial as it was when the
# event was encoded, and the encoder is an explicit state value: `encode`
# returns the next encoder with the frame, or upstream's error message.
# Blocks are typed, so upstream's clones that whitelist public fields and
# its structuredClone snapshots hold by construction.

def Message(-G: Data) -> Data: T.AssistantMessage<V.Value, G>

def Event(-G: Data) -> Data: T.AssistantMessageEvent<V.Value, G>

type AssistantMessageFrame<-G: Data> is Data:
  StartFrame{partial: T.AssistantMessage<V.Value, G>}
  TextStartFrame{contentIndex: F64, content: T.TextContent}
  TextDeltaFrame{contentIndex: F64, delta: String}
  TextEndFrame{contentIndex: F64, content: String, textSignature: Maybe<&2, String>}
  ThinkingStartFrame{contentIndex: F64, content: T.ThinkingContent}
  ThinkingDeltaFrame{contentIndex: F64, delta: String}
  ThinkingEndFrame{contentIndex: F64, content: String, thinkingSignature: Maybe<&2, String>, redacted: Maybe<&2, Bool>}
  ToolcallStartFrame{contentIndex: F64, toolCall: T.ToolCall<V.Value>}
  ToolcallCheckpointFrame{contentIndex: F64, json: String}
  ToolcallDeltaFrame{contentIndex: F64, delta: String}
  ToolcallEndFrame{contentIndex: F64, id: String, name: String, arguments: V.Value, thoughtSignature: Maybe<&2, String>, namespace: Maybe<&2, String>}

def frameType(-G: Data, frame: AssistantMessageFrame<G>) -> String:
  match frame:
    case StartFrame{_}: "start"
    case TextStartFrame{_, _}: "text_start"
    case TextDeltaFrame{_, _}: "text_delta"
    case TextEndFrame{_, _, _}: "text_end"
    case ThinkingStartFrame{_, _}: "thinking_start"
    case ThinkingDeltaFrame{_, _}: "thinking_delta"
    case ThinkingEndFrame{_, _, _, _}: "thinking_end"
    case ToolcallStartFrame{_, _}: "toolcall_start"
    case ToolcallCheckpointFrame{_, _}: "toolcall_checkpoint"
    case ToolcallDeltaFrame{_, _}: "toolcall_delta"
    case ToolcallEndFrame{_, _, _, _, _, _}: "toolcall_end"

def eventType(-G: Data, event: Event(G)) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case T.ThinkingStart{_, _}: "thinking_start"
    case T.ThinkingDelta{_, _, _}: "thinking_delta"
    case T.ThinkingEnd{_, _, _}: "thinking_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"

def contentType(content: T.AssistantContent<V.Value>) -> String:
  match content:
    case T.AssistantText{_}: "text"
    case T.AssistantThinking{_}: "thinking"
    case T.AssistantToolCall{_}: "toolCall"

# Content indexes
# ---------------
# Number.MAX_SAFE_INTEGER
def maxSafeInteger() -> F64: F.subtract(F.multiply(F.fromU32(2097152), F.multiply(F.fromU32(2147483648), F.fromU32(2))), F.fromU32(1))

def indexText(+index: F64) -> String: Maybe.default(&2, String, F.toDecimal(index), F64.show(index))

def naturalIndex(result: Result<&2, &2, F.Error, Nat>) -> Maybe<&2, Nat>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

# assertContentIndex: a safe non-negative integer.
def checkedIndex(+index: F64, valid: Maybe<&2, Nat>) -> Result<&2, &2, String, Nat>:
  match valid:
    case Some{value}: Done{value}
    case None{}: Fail{"Invalid assistant message frame contentIndex: " ++ indexText(index)}

def contentIndex(+index: F64) -> Result<&2, &2, String, Nat>:
  checkedIndex(index, Bool.pick(Maybe<&2, Nat>, F.isInteger(index) && F.isAtLeast(F.compare(index, F.fromU32(0))) && F.isAtMost(F.compare(index, maxSafeInteger())), naturalIndex(F.convert(index)), None{}))

# UTF-16 lengths and slices
# -------------------------
def units(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{+code}, rest}: Nat.add(Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n), units(rest))

def lowSurrogate(+code: U32) -> U32: (56320 + ((code - 65536 : U32) % 1024) : U32)

# `text.slice(count)` in UTF-16 code units; a pair split by `count` keeps its
# low surrogate, as JavaScript does.
def sliceUnits(text: String, +count: Nat) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, +rest}:
      +width = Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n)
      Bool.pick(Unit -> String, Nat.is_eq(count, 0n), _ => SCon{Chr{code}, rest}, _ => Bool.pick(Unit -> String, Nat.is_lt(count, width), _ => SCon{Chr{lowSurrogate(code)}, rest}, _ => sliceUnits(rest, Nat.sub(count, width)))(Unit{}))(Unit{})

# Tool-call arguments
# -------------------
def serializedText(text: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match text:
    case Some{value}: Done{value}
    case None{}: Fail{"Tool-call arguments are not JSON-serializable"}

def serializedArguments(value: V.Value) -> Result<&2, &2, String, String>: serializedText(Wire.stringify(Convert.toJson(value)))

def parsedArguments(json: String) -> V.Value: JsonParse.parseStreamingJson(Some{json})

def resultText(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: "{}"

def emptyParsedToolArguments() -> String: resultText(serializedArguments(parsedArguments("")))

def sameNumber(+left: F64, +right: F64) -> Bool: W.equal(F.toBits(left), F.toBits(right)) || (F.isNaN(left) && F.isNaN(right))

type Prefix is Data:
  Prefix{snapshot: V.Value, current: V.Value}

def pairs(snapshots: List<&2, V.Value>, currents: List<&2, V.Value>, rest: List<&2, Prefix>) -> Maybe<&2, List<&2, Prefix>>:
  match snapshots currents:
    case Nil{} _: Some{rest}
    case _ Nil{}: None{}
    case snapshot <> more current <> others: Maybe.map(&2, List<&2, Prefix>, List<&2, Prefix>, tail => Prefix{snapshot, current} <> tail, pairs(more, others, rest))

def fieldPair(value: V.Value, found: Maybe<&2, V.Value>, tail: Maybe<&2, List<&2, Prefix>>) -> Maybe<&2, List<&2, Prefix>>:
  match found:
    case None{}: None{}
    case Some{current}: Maybe.map(&2, List<&2, Prefix>, List<&2, Prefix>, pending => Prefix{value, current} <> pending, tail)

def fieldPairs(snapshot: List<&2, R.Property<V.Value>>, +current: R.Record<V.Value>, rest: List<&2, Prefix>) -> Maybe<&2, List<&2, Prefix>>:
  match snapshot:
    case Nil{}: Some{rest}
    case R.Property{name, value} <> more: fieldPair(value, R.get(V.Value, current, name), fieldPairs(more, current, rest))

def expanded(pair: Prefix, rest: List<&2, Prefix>) -> Maybe<&2, List<&2, Prefix>>:
  match pair:
    case Prefix{V.Text{snapshot}, V.Text{current}}: Bool.pick(Maybe<&2, List<&2, Prefix>>, String.starts_with(current, snapshot), Some{rest}, None{})
    case Prefix{V.Text{_}, _}: None{}
    case Prefix{V.ArrayValue{snapshots}, V.ArrayValue{currents}}: pairs(snapshots, currents, rest)
    case Prefix{V.ArrayValue{_}, _}: None{}
    case Prefix{V.ObjectValue{R.Record{fields}}, V.ObjectValue{current}}: fieldPairs(fields, current, rest)
    case Prefix{V.ObjectValue{_}, _}: None{}
    case Prefix{V.Null{}, V.Null{}}: Some{rest}
    case Prefix{V.Boolean{left}, V.Boolean{right}}: Bool.pick(Maybe<&2, List<&2, Prefix>>, Bool.not(Bool.xor(left, right)), Some{rest}, None{})
    case Prefix{V.Number{left}, V.Number{right}}: Bool.pick(Maybe<&2, List<&2, Prefix>>, sameNumber(left, right), Some{rest}, None{})
    case Prefix{_, _}: None{}

# isJsonPrefix over a work list: strings extend, arrays and objects extend
# element- and key-wise, other values are identical (Object.is).
@unsafe def prefixes(pending: Maybe<&2, List<&2, Prefix>>) -> Bool:
  match pending:
    case None{}: False{}
    case Some{Nil{}}: True{}
    case Some{pair <> rest}: prefixes(expanded(pair, rest))

def isJsonPrefix(snapshot: V.Value, current: V.Value) -> Bool: prefixes(Some{[Prefix{snapshot, current}]})

# Encoder
# -------
type BlockKind is Data:
  TextKind{}
  ThinkingKind{}
  ToolCallKind{}

def kindName(kind: BlockKind) -> String:
  match kind:
    case TextKind{}: "text"
    case ThinkingKind{}: "thinking"
    case ToolCallKind{}: "toolCall"

type EncoderBlockState is Data:
  TextState{kind: BlockKind, coveredChars: Nat, deltaChars: Nat}
  ToolCallState{caughtUp: Bool, catchupJson: String, snapshotArguments: String}

def stateKind(state: EncoderBlockState) -> BlockKind:
  match state:
    case TextState{kind, _, _}: kind
    case ToolCallState{_, _, _}: ToolCallKind{}

type Slot is Data:
  Slot{index: Nat, state: EncoderBlockState}

type AssistantMessageFrameEncoder is Data:
  AssistantMessageFrameEncoder{started: Bool, terminal: Bool, blocks: List<&2, Slot>}

def newEncoder() -> AssistantMessageFrameEncoder: AssistantMessageFrameEncoder{False{}, False{}, Nil{}}

type Encoding<-G: Data> is Data:
  Encoding{encoder: AssistantMessageFrameEncoder, frame: Maybe<&2, AssistantMessageFrame<G>>}

type Found is Data:
  Found{at: Nat, state: EncoderBlockState}

def Encoded(-G: Data) -> Data: Result<&2, &2, String, Encoding<G>>

def slotState(slots: List<&2, Slot>, +index: Nat) -> Maybe<&2, EncoderBlockState>:
  match slots:
    case Nil{}: None{}
    case Slot{at, state} <> rest: Bool.pick(Maybe<&2, EncoderBlockState>, Nat.is_eq(at, index), Some{state}, slotState(rest, index))

def withoutSlot(slots: List<&2, Slot>, +index: Nat) -> List<&2, Slot>:
  match slots:
    case Nil{}: Nil{}
    case Slot{+at, state} <> +rest: Bool.pick(List<&2, Slot>, Nat.is_eq(at, index), rest, Slot{at, state} <> withoutSlot(rest, index))

def withSlot(slots: List<&2, Slot>, +index: Nat, state: EncoderBlockState) -> List<&2, Slot>: Slot{index, state} <> withoutSlot(slots, index)

def emitted(-G: Data, encoder: AssistantMessageFrameEncoder, frame: Maybe<&2, AssistantMessageFrame<G>>) -> Encoded(G): Done{Encoding{encoder, frame}}

# The event's content block: eventBlock.
def foundBlock(+kindLabel: String, +index: F64, block: Maybe<&2, T.AssistantContent<V.Value>>) -> Result<&2, &2, String, T.AssistantContent<V.Value>>:
  match block:
    case Some{found}: Done{found}
    case None{}: Fail{kindLabel ++ " event has no content block at index " ++ indexText(index)}

def eventBlockAt(-G: Data, +kindLabel: String, +index: F64, partial: Message(G), at: Result<&2, &2, String, Nat>) -> Result<&2, &2, String, T.AssistantContent<V.Value>>:
  match at:
    case Fail{message}: Fail{message}
    case Done{position}: foundBlock(kindLabel, index, List.get(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, partial), position))

def eventBlock(-G: Data, +kindLabel: String, +index: F64, partial: Message(G)) -> Result<&2, &2, String, T.AssistantContent<V.Value>>: eventBlockAt(G, kindLabel, index, partial, contentIndex(index))

def kindMismatch(+kindLabel: String, +index: F64, content: T.AssistantContent<V.Value>) -> String:
  kindLabel ++ " event points to " ++ contentType(content) ++ " block at index " ++ indexText(index)

# block(contentIndex, kind): the started block's state.
def stateFound(+index: F64, +at: Nat, +kind: BlockKind, found: Maybe<&2, EncoderBlockState>) -> Result<&2, &2, String, Found>:
  match found:
    case None{}: Fail{"Assistant message " ++ kindName(kind) ++ " block " ++ indexText(index) ++ " has not started"}
    case Some{+state}: Bool.pick(Result<&2, &2, String, Found>, String.eq(kindName(stateKind(state)), kindName(kind)), Done{Found{at, state}}, Fail{"Assistant message block " ++ indexText(index) ++ " is " ++ kindName(stateKind(state)) ++ ", not " ++ kindName(kind)})

def blocksOf(encoder: AssistantMessageFrameEncoder) -> List<&2, Slot>:
  match encoder:
    case AssistantMessageFrameEncoder{_, _, blocks}: blocks

def blockStateAt(encoder: AssistantMessageFrameEncoder, +index: F64, kind: BlockKind, at: Result<&2, &2, String, Nat>) -> Result<&2, &2, String, Found>:
  match at:
    case Fail{message}: Fail{message}
    case Done{+position}: stateFound(index, position, kind, slotState(blocksOf(encoder), position))

def blockState(encoder: AssistantMessageFrameEncoder, +index: F64, kind: BlockKind) -> Result<&2, &2, String, Found>: blockStateAt(encoder, index, kind, contentIndex(index))

def replaced(encoder: AssistantMessageFrameEncoder, +at: Nat, state: EncoderBlockState) -> AssistantMessageFrameEncoder:
  match encoder:
    case AssistantMessageFrameEncoder{started, terminal, blocks}: AssistantMessageFrameEncoder{started, terminal, withSlot(blocks, at, state)}

def removed(encoder: AssistantMessageFrameEncoder, +at: Nat) -> AssistantMessageFrameEncoder:
  match encoder:
    case AssistantMessageFrameEncoder{started, terminal, blocks}: AssistantMessageFrameEncoder{started, terminal, withoutSlot(blocks, at)}

def startFree(encoder: AssistantMessageFrameEncoder, +index: F64, +at: Nat, state: EncoderBlockState, existing: Maybe<&2, EncoderBlockState>) -> Result<&2, &2, String, AssistantMessageFrameEncoder>:
  match existing:
    case Some{_}: Fail{"Assistant message block " ++ indexText(index) ++ " starts more than once"}
    case None{}: Done{replaced(encoder, at, state)}

def startBlockAt(+encoder: AssistantMessageFrameEncoder, +index: F64, state: EncoderBlockState, at: Result<&2, &2, String, Nat>) -> Result<&2, &2, String, AssistantMessageFrameEncoder>:
  match at:
    case Fail{message}: Fail{message}
    case Done{+position}: startFree(encoder, index, position, state, slotState(blocksOf(encoder), position))

def startBlock(encoder: AssistantMessageFrameEncoder, +index: F64, state: EncoderBlockState) -> Result<&2, &2, String, AssistantMessageFrameEncoder>: startBlockAt(encoder, index, state, contentIndex(index))

def endFound(encoder: AssistantMessageFrameEncoder, found: Result<&2, &2, String, Found>) -> Result<&2, &2, String, AssistantMessageFrameEncoder>:
  match found:
    case Fail{message}: Fail{message}
    case Done{Found{at, _}}: Done{removed(encoder, at)}

def endBlock(+encoder: AssistantMessageFrameEncoder, +index: F64, kind: BlockKind) -> Result<&2, &2, String, AssistantMessageFrameEncoder>: endFound(encoder, blockState(encoder, index, kind))

def startedWith(-G: Data, started: Result<&2, &2, String, AssistantMessageFrameEncoder>, frame: AssistantMessageFrame<G>) -> Encoded(G):
  match started:
    case Fail{message}: Fail{message}
    case Done{encoder}: Done{Encoding{encoder, Some{frame}}}

def textDeltaFrame(-G: Data, kind: BlockKind, +index: F64, delta: String) -> AssistantMessageFrame<G>:
  match kind:
    case ThinkingKind{}: ThinkingDeltaFrame{index, delta}
    case _: TextDeltaFrame{index, delta}

def uncoveredDelta(-G: Data, encoder: AssistantMessageFrameEncoder, +at: Nat, +kind: BlockKind, +covered: Nat, +deltaStart: Nat, +index: F64, +delta: String) -> Encoded(G):
  +length = units(delta)
  +next = replaced(encoder, at, TextState{kind, covered, Nat.add(deltaStart, length)})
  +visible = Nat.sub(covered, Nat.min(covered, deltaStart))
  Bool.pick(Encoded(G), Nat.is_ge(visible, length), emitted(G, next, None{}), emitted(G, next, Some{textDeltaFrame(G, kind, index, sliceUnits(delta, visible))}))

def textDeltaFound(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, delta: String, found: Result<&2, &2, String, Found>) -> Encoded(G):
  match found:
    case Fail{message}: Fail{message}
    case Done{Found{at, TextState{stateKind, covered, deltaStart}}}: uncoveredDelta(G, encoder, at, stateKind, covered, deltaStart, index, delta)
    case Done{_}: Fail{"Unreachable text encoder state"}

def encodeTextDelta(-G: Data, +encoder: AssistantMessageFrameEncoder, +index: F64, delta: String, kind: BlockKind) -> Encoded(G): textDeltaFound(G, encoder, index, delta, blockState(encoder, index, kind))

def caughtUpDelta(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, +delta: String) -> Encoded(G):
  match delta:
    case SNil{}: emitted(G, encoder, None{})
    case text: emitted(G, encoder, Some{ToolcallDeltaFrame{index, text}})

def checkpointFrame(-G: Data, next: AssistantMessageFrameEncoder, +index: F64, json: String) -> Encoded(G):
  match json:
    case SNil{}: emitted(G, next, None{})
    case text: emitted(G, next, Some{ToolcallCheckpointFrame{index, text}})

def checkpoint(-G: Data, encoder: AssistantMessageFrameEncoder, +at: Nat, +index: F64, +json: String) -> Encoded(G):
  checkpointFrame(G, replaced(encoder, at, ToolCallState{True{}, "", ""}), index, json)

# A catch-up JSON whose parsed arguments reproduce the start snapshot, or
# (legacy grammar calls) extend it, catches the block up.
def catchUp(-G: Data, +encoder: AssistantMessageFrameEncoder, +at: Nat, +index: F64, +catchup: String, +snapshot: String, serialized: Result<&2, &2, String, String>) -> Encoded(G):
  match serialized:
    case Fail{message}: Fail{message}
    case Done{current}:
      Bool.pick(Encoded(G), String.eq(current, snapshot) || isJsonPrefix(parsedArguments(snapshot), parsedArguments(catchup)), checkpoint(G, encoder, at, index, catchup), emitted(G, replaced(encoder, at, ToolCallState{False{}, catchup, snapshot}), None{}))

def toolDeltaFound(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, delta: String, found: Result<&2, &2, String, Found>) -> Encoded(G):
  match found:
    case Fail{message}: Fail{message}
    case Done{Found{_, ToolCallState{True{}, _, _}}}: caughtUpDelta(G, encoder, index, delta)
    case Done{Found{at, ToolCallState{False{}, catchupJson, snapshot}}}:
      +catchup = catchupJson ++ delta
      catchUp(G, encoder, at, index, catchup, snapshot, serializedArguments(parsedArguments(catchup)))
    case Done{_}: Fail{"Unreachable tool-call encoder state"}

def encodeToolDelta(-G: Data, +encoder: AssistantMessageFrameEncoder, +index: F64, delta: String) -> Encoded(G): toolDeltaFound(G, encoder, index, delta, blockState(encoder, index, ToolCallKind{}))

def textStarted(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block:
    case Fail{message}: Fail{message}
    case Done{T.AssistantText{T.TextContent{+text, signature}}}: startedWith(G, startBlock(encoder, index, TextState{TextKind{}, units(text), 0n}), TextStartFrame{index, T.TextContent{text, signature}})
    case Done{other}: Fail{kindMismatch("text_start", index, other)}

def thinkingStarted(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block:
    case Fail{message}: Fail{message}
    case Done{T.AssistantThinking{T.ThinkingContent{+thinking, signature, redacted}}}: startedWith(G, startBlock(encoder, index, TextState{ThinkingKind{}, units(thinking), 0n}), ThinkingStartFrame{index, T.ThinkingContent{thinking, signature, redacted}})
    case Done{other}: Fail{kindMismatch("thinking_start", index, other)}

def toolStartedWith(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, toolCall: T.ToolCall<V.Value>, serialized: Result<&2, &2, String, String>) -> Encoded(G):
  match serialized:
    case Fail{message}: Fail{message}
    case Done{+snapshot}:
      +caughtUp = String.eq(snapshot, emptyParsedToolArguments())
      startedWith(G, startBlock(encoder, index, ToolCallState{caughtUp, "", Bool.pick(String, caughtUp, "", snapshot)}), ToolcallStartFrame{index, toolCall})

def toolStarted(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block:
    case Fail{message}: Fail{message}
    case Done{T.AssistantToolCall{T.ToolCall{id, name, +arguments, signature, namespace}}}: toolStartedWith(G, encoder, index, T.ToolCall{id, name, arguments, signature, namespace}, serializedArguments(arguments))
    case Done{other}: Fail{kindMismatch("toolcall_start", index, other)}

def ended(-G: Data, finished: Result<&2, &2, String, AssistantMessageFrameEncoder>, frame: AssistantMessageFrame<G>) -> Encoded(G): startedWith(G, finished, frame)

def textEnded(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, content: String, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block:
    case Fail{message}: Fail{message}
    case Done{T.AssistantText{T.TextContent{_, signature}}}: ended(G, endBlock(encoder, index, TextKind{}), TextEndFrame{index, content, signature})
    case Done{other}: Fail{kindMismatch("text_end", index, other)}

def thinkingEnded(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, content: String, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block:
    case Fail{message}: Fail{message}
    case Done{T.AssistantThinking{T.ThinkingContent{_, signature, redacted}}}: ended(G, endBlock(encoder, index, ThinkingKind{}), ThinkingEndFrame{index, content, signature, redacted})
    case Done{other}: Fail{kindMismatch("thinking_end", index, other)}

def toolEnded(-G: Data, encoder: AssistantMessageFrameEncoder, +index: F64, toolCall: T.ToolCall<V.Value>, block: Result<&2, &2, String, T.AssistantContent<V.Value>>) -> Encoded(G):
  match block toolCall:
    case Fail{message} _: Fail{message}
    case Done{T.AssistantToolCall{_}} T.ToolCall{id, name, arguments, signature, namespace}: ended(G, endBlock(encoder, index, ToolCallKind{}), ToolcallEndFrame{index, id, name, arguments, signature, namespace})
    case Done{other} _: Fail{kindMismatch("toolcall_end", index, other)}

# The start frame's message: public fields only, no content, pending.
def startMessage(-G: Data, message: Message(G)) -> Message(G):
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, _, _, _, _, timestamp}:
      T.AssistantMessage{Nil{}, api, provider, model, responseModel, responseId, level, diagnostics, usage, T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def withStarted(encoder: AssistantMessageFrameEncoder) -> AssistantMessageFrameEncoder:
  match encoder:
    case AssistantMessageFrameEncoder{_, terminal, blocks}: AssistantMessageFrameEncoder{True{}, terminal, blocks}

def withTerminal(encoder: AssistantMessageFrameEncoder) -> AssistantMessageFrameEncoder:
  match encoder:
    case AssistantMessageFrameEncoder{started, _, blocks}: AssistantMessageFrameEncoder{started, True{}, blocks}

def encodeStarted(-G: Data, encoder: AssistantMessageFrameEncoder, event: Event(G)) -> Encoded(G):
  match event:
    case T.TextStart{+index, partial}: textStarted(G, encoder, index, eventBlock(G, "text_start", index, partial))
    case T.TextDelta{index, delta, _}: encodeTextDelta(G, encoder, index, delta, TextKind{})
    case T.TextEnd{+index, content, partial}: textEnded(G, encoder, index, content, eventBlock(G, "text_end", index, partial))
    case T.ThinkingStart{+index, partial}: thinkingStarted(G, encoder, index, eventBlock(G, "thinking_start", index, partial))
    case T.ThinkingDelta{index, delta, _}: encodeTextDelta(G, encoder, index, delta, ThinkingKind{})
    case T.ThinkingEnd{+index, content, partial}: thinkingEnded(G, encoder, index, content, eventBlock(G, "thinking_end", index, partial))
    case T.ToolcallStart{+index, partial}: toolStarted(G, encoder, index, eventBlock(G, "toolcall_start", index, partial))
    case T.ToolcallDelta{index, delta, _}: encodeToolDelta(G, encoder, index, delta)
    case T.ToolcallEnd{+index, toolCall, partial}: toolEnded(G, encoder, index, toolCall, eventBlock(G, "toolcall_end", index, partial))
    case _: Fail{"Unreachable assistant message event"}

def encodeOpen(-G: Data, encoder: AssistantMessageFrameEncoder, event: Event(G)) -> Encoded(G):
  match encoder event:
    case AssistantMessageFrameEncoder{True{}, _, _} T.Start{_}: Fail{"Assistant message stream contains more than one start event"}
    case AssistantMessageFrameEncoder{False{}, _, _} T.Start{partial}: emitted(G, withStarted(encoder), Some{StartFrame{startMessage(G, partial)}})
    case AssistantMessageFrameEncoder{False{}, _, _} T.StreamDone{_, _}: Fail{"Assistant message done event appears before start"}
    case AssistantMessageFrameEncoder{True{}, _, _} T.StreamDone{_, _}: emitted(G, withTerminal(encoder), None{})
    case _ T.StreamError{_, _}: emitted(G, withTerminal(encoder), None{})
    case AssistantMessageFrameEncoder{False{}, _, _} other: Fail{"Assistant message " ++ eventType(G, other) ++ " event appears before start"}
    case AssistantMessageFrameEncoder{True{}, _, _} other: encodeStarted(G, encoder, other)

# AssistantMessageFrameEncoder.encode: the next encoder and the event's frame
# (None when the event adds nothing to replay), or upstream's error message.
def encode(-G: Data, encoder: AssistantMessageFrameEncoder, event: Event(G)) -> Encoded(G):
  match encoder:
    case AssistantMessageFrameEncoder{_, True{}, _}: Fail{"Assistant message event " ++ eventType(G, event) ++ " follows a terminal event"}
    case AssistantMessageFrameEncoder{_, False{}, _}: encodeOpen(G, encoder, event)

# Reducer
# -------
type ReducerBlockState is Data:
  Reducing{kind: BlockKind, ended: Bool, json: String}

type ReducerSlot is Data:
  ReducerSlot{index: Nat, state: ReducerBlockState}

type Reduction<-G: Data> is Data:
  Reduction{message: Maybe<&2, Message(G)>, frameBeforeStart: Maybe<&2, String>, states: List<&2, ReducerSlot>}

def reducerState(slots: List<&2, ReducerSlot>, +index: Nat) -> Maybe<&2, ReducerBlockState>:
  match slots:
    case Nil{}: None{}
    case ReducerSlot{at, state} <> rest: Bool.pick(Maybe<&2, ReducerBlockState>, Nat.is_eq(at, index), Some{state}, reducerState(rest, index))

def withReducerState(slots: List<&2, ReducerSlot>, +index: Nat, +state: ReducerBlockState) -> List<&2, ReducerSlot>:
  match slots:
    case Nil{}: [ReducerSlot{index, state}]
    case ReducerSlot{+at, current} <> +rest: Bool.pick(List<&2, ReducerSlot>, Nat.is_eq(at, index), ReducerSlot{at, state} <> rest, ReducerSlot{at, current} <> withReducerState(rest, index, state))

def withContent(-G: Data, message: Message(G), content: List<&2, T.AssistantContent<V.Value>>) -> Message(G):
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, rawStop, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, rawStop, endTurn, timestamp}

def Reduced(-G: Data) -> Data: Result<&2, &2, String, Reduction<G>>

def appendAt(-G: Data, +message: Message(G), states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, +index: F64, block: T.AssistantContent<V.Value>, kind: BlockKind, position: Result<&2, &2, String, Nat>) -> Reduced(G):
  match position:
    case Fail{text}: Fail{text}
    case Done{+at}:
      +content = T.assistantContent(V.Value, G, message)
      +length = List.length(&2, T.AssistantContent<V.Value>, content)
      Bool.pick(Reduced(G), Nat.is_eq(at, length), Done{Reduction{Some{withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, content, [block]))}, frameBefore, withReducerState(states, at, Reducing{kind, False{}, ""})}}, Fail{"Cannot start assistant message block at index " ++ indexText(index) ++ ": " ++ Bool.pick(String, Nat.is_lt(at, length), "already exists", "would leave a gap")})

def appendBlock(-G: Data, message: Message(G), states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, +index: F64, block: T.AssistantContent<V.Value>, kind: BlockKind) -> Reduced(G):
  appendAt(G, message, states, frameBefore, index, block, kind, contentIndex(index))

type Change is Data:
  Change{block: T.AssistantContent<V.Value>, state: ReducerBlockState}

type Active is Data:
  Active{at: Nat, block: T.AssistantContent<V.Value>, state: ReducerBlockState}

def activeChecked(+frameType: String, +index: F64, +at: Nat, expected: BlockKind, found: T.AssistantContent<V.Value>, state: ReducerBlockState, matches: Bool) -> Result<&2, &2, String, Active>:
  match matches state:
    case False{} _: Fail{frameType ++ " frame expected " ++ kindName(expected) ++ " block at index " ++ indexText(index) ++ ", found " ++ contentType(found)}
    case True{} Reducing{_, True{}, _}: Fail{frameType ++ " frame follows the end of block at index " ++ indexText(index)}
    case True{} active: Done{Active{at, found, active}}

def activeFound(+frameType: String, +index: F64, +at: Nat, +expected: BlockKind, block: Maybe<&2, T.AssistantContent<V.Value>>, state: Maybe<&2, ReducerBlockState>) -> Result<&2, &2, String, Active>:
  match block state:
    case Some{+found} Some{Reducing{+kind, ended, json}}: activeChecked(frameType, index, at, expected, found, Reducing{kind, ended, json}, String.eq(kindName(kind), kindName(expected)) && String.eq(contentType(found), kindName(expected)))
    case _ _: Fail{frameType ++ " frame has no started block at index " ++ indexText(index)}

def activeAt(-G: Data, message: Message(G), states: List<&2, ReducerSlot>, +index: F64, expected: BlockKind, +frameType: String, position: Result<&2, &2, String, Nat>) -> Result<&2, &2, String, Active>:
  match position:
    case Fail{text}: Fail{text}
    case Done{+at}: activeFound(frameType, index, at, expected, List.get(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), at), reducerState(states, at))

def activeBlock(-G: Data, message: Message(G), states: List<&2, ReducerSlot>, +index: F64, expected: BlockKind, +frameType: String) -> Result<&2, &2, String, Active>:
  activeAt(G, message, states, index, expected, frameType, contentIndex(index))

def updated(-G: Data, +message: Message(G), states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, +at: Nat, block: T.AssistantContent<V.Value>, state: ReducerBlockState) -> Reduction<G>:
  Reduction{Some{withContent(G, message, List.set(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), at, block))}, frameBefore, withReducerState(states, at, state)}

def withText(block: T.AssistantContent<V.Value>, +delta: String) -> T.AssistantContent<V.Value>:
  match block:
    case T.AssistantText{T.TextContent{text, signature}}: T.AssistantText{T.TextContent{text ++ delta, signature}}
    case T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}}: T.AssistantThinking{T.ThinkingContent{thinking ++ delta, signature, redacted}}
    case other: other

def withArguments(block: T.AssistantContent<V.Value>, arguments: V.Value) -> T.AssistantContent<V.Value>:
  match block:
    case T.AssistantToolCall{T.ToolCall{id, name, _, signature, namespace}}: T.AssistantToolCall{T.ToolCall{id, name, arguments, signature, namespace}}
    case other: other

def withJson(state: ReducerBlockState, json: String) -> ReducerBlockState:
  match state:
    case Reducing{kind, ended, _}: Reducing{kind, ended, json}

def jsonOf(state: ReducerBlockState) -> String:
  match state:
    case Reducing{_, _, json}: json

def endedState(state: ReducerBlockState) -> ReducerBlockState:
  match state:
    case Reducing{kind, _, json}: Reducing{kind, True{}, json}

def applied(-G: Data, message: Message(G), states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, +at: Nat, change: Change) -> Reduced(G):
  match change:
    case Change{next, nextState}: Done{updated(G, message, states, frameBefore, at, next, nextState)}

def onActive(-G: Data, message: Message(G), states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, active: Result<&2, &2, String, Active>, change: Active -> Change) -> Reduced(G):
  match active:
    case Fail{text}: Fail{text}
    case Done{Active{+at, block, state}}: applied(G, message, states, frameBefore, at, change(Active{at, block, state}))

def textAppended(active: Active, +delta: String) -> Change:
  match active:
    case Active{_, block, state}: Change{withText(block, delta), state}

def textFinished(active: Active, content: String, signature: Maybe<&2, String>) -> Change:
  match active:
    case Active{_, _, state}: Change{T.AssistantText{T.TextContent{content, signature}}, endedState(state)}

def thinkingFinished(active: Active, content: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>) -> Change:
  match active:
    case Active{_, _, state}: Change{T.AssistantThinking{T.ThinkingContent{content, signature, redacted}}, endedState(state)}

def checkpointed(active: Active, +json: String) -> Change:
  match active:
    case Active{_, block, state}: Change{withArguments(block, parsedArguments(json)), withJson(state, json)}

def jsonAppended(active: Active, delta: String) -> Change:
  match active:
    case Active{_, block, +state}: Change{block, withJson(state, jsonOf(state) ++ delta)}

def toolFinished(active: Active, toolCall: T.ToolCall<V.Value>) -> Change:
  match active:
    case Active{_, _, state}: Change{T.AssistantToolCall{toolCall}, endedState(state)}

def reduceFrame(-G: Data, +message: Message(G), +states: List<&2, ReducerSlot>, +frameBefore: Maybe<&2, String>, frame: AssistantMessageFrame<G>) -> Reduced(G):
  match frame:
    case StartFrame{_}: Fail{"Assistant message frame sequence contains more than one start frame"}
    case TextStartFrame{index, content}: appendBlock(G, message, states, frameBefore, index, T.AssistantText{content}, TextKind{})
    case ThinkingStartFrame{index, content}: appendBlock(G, message, states, frameBefore, index, T.AssistantThinking{content}, ThinkingKind{})
    case ToolcallStartFrame{index, toolCall}: appendBlock(G, message, states, frameBefore, index, T.AssistantToolCall{toolCall}, ToolCallKind{})
    case TextDeltaFrame{index, delta}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, TextKind{}, "text_delta"), active => textAppended(active, delta))
    case ThinkingDeltaFrame{index, delta}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, ThinkingKind{}, "thinking_delta"), active => textAppended(active, delta))
    case TextEndFrame{index, content, signature}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, TextKind{}, "text_end"), active => textFinished(active, content, signature))
    case ThinkingEndFrame{index, content, signature, redacted}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, ThinkingKind{}, "thinking_end"), active => thinkingFinished(active, content, signature, redacted))
    case ToolcallCheckpointFrame{index, json}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, ToolCallKind{}, "toolcall_checkpoint"), active => checkpointed(active, json))
    case ToolcallDeltaFrame{index, delta}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, ToolCallKind{}, "toolcall_delta"), active => jsonAppended(active, delta))
    case ToolcallEndFrame{index, id, name, arguments, signature, namespace}: onActive(G, message, states, frameBefore, activeBlock(G, message, states, index, ToolCallKind{}, "toolcall_end"), active => toolFinished(active, T.ToolCall{id, name, arguments, signature, namespace}))

def step(-G: Data, reduction: Reduced(G), frame: AssistantMessageFrame<G>) -> Reduced(G):
  match reduction frame:
    case Fail{text} _: Fail{text}
    case Done{Reduction{None{}, Some{before}, _}} StartFrame{_}: Fail{before ++ " frame appears before the start frame"}
    case Done{Reduction{None{}, None{}, states}} StartFrame{partial}: Done{Reduction{Some{partial}, None{}, states}}
    case Done{Reduction{None{}, before, states}} other: Done{Reduction{None{}, Some{Maybe.default(&2, String, before, frameType(G, other))}, states}}
    case Done{Reduction{Some{message}, before, states}} other: reduceFrame(G, message, states, before, other)

def reduceAll(-G: Data, frames: List<&2, AssistantMessageFrame<G>>, reduction: Reduced(G)) -> Reduced(G):
  match frames:
    case Nil{}: reduction
    case frame <> rest: reduceAll(G, rest, step(G, reduction, frame))

def settledBlock(block: T.AssistantContent<V.Value>, state: Maybe<&2, ReducerBlockState>) -> T.AssistantContent<V.Value>:
  match state:
    case Some{Reducing{ToolCallKind{}, False{}, SCon{c, cs}}}: withArguments(block, parsedArguments(SCon{c, cs}))
    case _: block

# Unfinished tool calls take the arguments of their JSON so far.
def settledBlocks(content: List<&2, T.AssistantContent<V.Value>>, +states: List<&2, ReducerSlot>, +at: Nat) -> List<&2, T.AssistantContent<V.Value>>:
  match content:
    case Nil{}: Nil{}
    case block <> rest: settledBlock(block, reducerState(states, at)) <> settledBlocks(rest, states, Nat.add(at, 1n))

def settled(-G: Data, reduction: Reduced(G)) -> Result<&2, &2, String, Maybe<&2, Message(G)>>:
  match reduction:
    case Fail{text}: Fail{text}
    case Done{Reduction{None{}, _, _}}: Done{None{}}
    case Done{Reduction{Some{+message}, _, states}}: Done{Some{withContent(G, message, settledBlocks(T.assistantContent(V.Value, G, message), states, 0n))}}

# reduceAssistantMessageFrames: the replayed message, None without a start
# frame, or upstream's error message.
def reduceAssistantMessageFrames(-G: Data, frames: List<&2, AssistantMessageFrame<G>>) -> Result<&2, &2, String, Maybe<&2, Message(G)>>:
  settled(G, reduceAll(G, frames, Done{Reduction{None{}, None{}, Nil{}}}))
