import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/diagnostics.bend as Diagnostics
import ../utils/json-parse.bend as Json
import ./anthropic-messages.bend as Messages
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf8.bend as UTF8

def truthy(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def withoutSpace(value: String) -> String:
  match value:
    case SCon{' ', rest}: rest
    case other: other

type Field is Data:
  Field{name: String, value: String}

def splitField(line: String, reversed: String) -> Field:
  match line:
    case SNil{}: Field{String.reverse(reversed), ""}
    case SCon{':', rest}: Field{String.reverse(reversed), withoutSpace(rest)}
    case SCon{char, rest}: splitField(rest, SCon{char, reversed})

type Line is Data:
  Line{line: String, rest: String}

# Assistant message fold
# ----------------------
type Block is Data:
  TextBlock{value: T.TextContent}
  ThinkingBlock{value: T.ThinkingContent}
  ToolBlock{value: T.ToolCall<V.Value>, partialJson: String}

# `index` is the wire index; a stopped block leaves the index table.
type Slot is Data:
  Slot{index: Maybe<&2, F64>, contentIndex: Nat, block: Block}

type InputTransformation is Data:
  InputTransformation{transformationType: Maybe<&2, String>, path: Maybe<&2, String>, reason: Maybe<&2, String>}

# `usageModel` prices usage: a returned fallback model's cost when configured.
# OAuth requests map returned tool names back through the current tools.
type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, slots: List<&2, Slot>, model: T.Model<T.JsonValue>, usageModel: T.Model<T.JsonValue>, transformations: Maybe<&2, List<&2, InputTransformation>>, sawMessageStart: Bool, sawMessageEnd: Bool, oauth: Bool, tools: List<&2, T.Tool<V.Value>>}

def zero() -> F64: F.fromU32(0)

def emptyUsage() -> T.Usage:
  T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def create(-G: Data, +model: T.Model<T.JsonValue>, timestamp: F64, providerThinkingLevel: Maybe<&2, String>, oauth: Bool, tools: List<&2, T.Tool<V.Value>>) -> State<G>:
  match model:
    case T.Model{+id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      State{T.AssistantMessage{Nil{}, "anthropic-messages", provider, id, None{}, None{}, providerThinkingLevel, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, Nil{}, model, model, None{}, False{}, False{}, oauth, tools}

def stateMessage(-G: Data, state: State<G>) -> T.AssistantMessage<V.Value, G>:
  match state:
    case State{message, _, _, _, _, _, _, _, _}: message

def field(value: V.Value, name: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2, V.Value, R.get(V.Value, fields, name), V.Null{})
    case _: V.Null{}

def textValue(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{item}: Some{item}
    case _: None{}

def afterCarriage(text: String) -> String:
  match text:
    case SCon{'\n', rest}: rest
    case other: other

# upstream consumeLine: the text before the first CR or LF, and the rest after
# its line break (CRLF counts once when both are present).
def consumeLine(text: String, reversed: String) -> Maybe<&2, Line>:
  match text:
    case SNil{}: None{}
    case SCon{'\r', rest}: Some{Line{String.reverse(reversed), afterCarriage(rest)}}
    case SCon{'\n', rest}: Some{Line{String.reverse(reversed), rest}}
    case SCon{char, rest}: consumeLine(rest, SCon{char, reversed})

def numberValue(value: V.Value) -> Maybe<&2, F64>:
  match value:
    case V.Number{item}: Some{item}
    case _: None{}

def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)

def blockContent(block: Block) -> T.AssistantContent<V.Value>:
  match block:
    case TextBlock{value}: T.AssistantText{value}
    case ThinkingBlock{value}: T.AssistantThinking{value}
    case ToolBlock{value, _}: T.AssistantToolCall{value}

def withMessage(-G: Data, state: State<G>, message: T.AssistantMessage<V.Value, G>) -> State<G>:
  match state:
    case State{_, slots, model, usageModel, transformations, start, end, oauth, tools}: State{message, slots, model, usageModel, transformations, start, end, oauth, tools}

def withSlots(-G: Data, state: State<G>, slots: List<&2, Slot>) -> State<G>:
  match state:
    case State{message, _, model, usageModel, transformations, start, end, oauth, tools}: State{message, slots, model, usageModel, transformations, start, end, oauth, tools}

def sameIndex(left: Maybe<&2, F64>, right: Maybe<&2, F64>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: F.isEqual(F.compare(a, b))
    case _ _: False{}

def contentCount(-G: Data, message: T.AssistantMessage<V.Value, G>) -> Nat: count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))

def contentPosition(value: Nat) -> F64: F.fromNat(value)

def replaceAt(values: List<&2, T.AssistantContent<V.Value>>, position: Nat, next: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values position:
    case Nil{} _: next <> Nil{}
    case _ <> tail 0n: next <> tail
    case head <> tail 1n+rest: head <> replaceAt(tail, rest, next)

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, position: Nat, block: Block) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{replaceAt(content, position, blockContent(block)), api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

# upstream `blocks.findIndex((b) => b.index === event.index)`.
def findSlot(slots: List<&2, Slot>, +key: Maybe<&2, F64>) -> Maybe<&2, Slot>:
  match slots:
    case Nil{}: None{}
    case Slot{+index, position, block} <> rest: Bool.pick(Maybe<&2, Slot>, sameIndex(index, key), Some{Slot{index, position, block}}, findSlot(rest, key))

def withoutSlot(slots: List<&2, Slot>, +position: Nat) -> List<&2, Slot>:
  match slots:
    case Nil{}: Nil{}
    case Slot{index, +at, block} <> rest:
      +tail = withoutSlot(rest, position)
      Bool.pick(List<&2, Slot>, Nat.is_eq(at, position), tail, Slot{index, at, block} <> tail)

def replaceSlot(slots: List<&2, Slot>, slot: Slot) -> List<&2, Slot>:
  match slot:
    case Slot{index, +position, block}: Slot{index, position, block} <> withoutSlot(slots, position)

# message_start
# -------------
def firstNumber(value: V.Value) -> F64:
  match value:
    case V.Number{+item}: Bool.pick(F64, F.isNaN(item), zero(), item)
    case _: zero()

def optionalNumber(value: V.Value) -> Maybe<&2, F64>:
  match value:
    case V.Number{item}: Some{item}
    case _: None{}

def withCost(usage: T.Usage, cost: T.UsageCost) -> T.Usage:
  match usage:
    case T.Usage{input, output, read, write, long, reasoning, total, _}: T.Usage{input, output, read, write, long, reasoning, total, cost}

def withTotals(usage: T.Usage, model: T.Model<T.JsonValue>) -> T.Usage:
  match usage:
    case T.Usage{+input, +output, +read, +write, long, reasoning, _, _}:
      +draft = {T.Usage{input, output, read, write, long, reasoning, F.add(F.add(F.add(input, output), read), write), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
      withCost(draft, Cost.calculate(T.JsonValue, model, draft))

# message_start replaces the counts (`|| 0`) and the 1h cache write portion.
def startUsage(usage: T.Usage, +incoming: V.Value) -> T.Usage:
  match usage:
    case T.Usage{_, _, _, _, _, reasoning, total, cost}:
      T.Usage{firstNumber(field(incoming, "input_tokens")), firstNumber(field(incoming, "output_tokens")), firstNumber(field(incoming, "cache_read_input_tokens")), firstNumber(field(incoming, "cache_creation_input_tokens")), Some{firstNumber(field(field(incoming, "cache_creation"), "ephemeral_1h_input_tokens"))}, reasoning, total, cost}

def transformation(+value: V.Value) -> InputTransformation:
  InputTransformation{textValue(field(value, "type")), textValue(field(value, "path")), textValue(field(value, "reason"))}

def transformationList(values: List<&2, V.Value>) -> List<&2, InputTransformation>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: transformation(value) <> transformationList(rest)

def arrayTransformations(value: V.Value, previous: Maybe<&2, List<&2, InputTransformation>>) -> Maybe<&2, List<&2, InputTransformation>>:
  match value:
    case V.ArrayValue{values}: Some{transformationList(values)}
    case _: previous

def matchingFallback(values: List<&2, T.AnthropicAllowedFallbackModel>, +provider: String, +model: String) -> Maybe<&2, T.ModelCost>:
  match values:
    case Nil{}: None{}
    case T.AnthropicAllowedFallbackModel{+owner, +name, cost} <> rest: Bool.pick(Maybe<&2, T.ModelCost>, String.eq(owner, provider) && String.eq(name, model), Some{cost}, matchingFallback(rest, provider, model))

def pricedWith(model: T.Model<T.JsonValue>, cost: Maybe<&2, T.ModelCost>) -> T.Model<T.JsonValue>:
  match model cost:
    case current None{}: current
    case T.Model{id, name, api, provider, base, reasoning, levels, input, limits, _, cache, window, maximum, sampling, headers, compat} Some{price}: T.Model{id, name, api, provider, base, reasoning, levels, input, limits, price, cache, window, maximum, sampling, headers, compat}

# The model that prices usage after message_start: a different returned model
# uses a configured fallback's cost.
def usageModelFor(+model: T.Model<T.JsonValue>, responseModel: Maybe<&2, String>) -> T.Model<T.JsonValue>:
  match responseModel:
    case Some{+name}: Bool.pick(T.Model<T.JsonValue>, String.eq(name, T.modelId(model)), model, pricedWith(model, matchingFallback(Messages.allowedFallbackModels(model), T.modelProvider(model), name)))
    case None{}: pricedWith(model, matchingFallback(Messages.allowedFallbackModels(model), T.modelProvider(model), ""))

# `if (responseModel !== model.id) output.responseModel = responseModel`.
def responseModelFor(+id: String, returned: Maybe<&2, String>, previous: Maybe<&2, String>) -> Maybe<&2, String>:
  match returned:
    case Some{+name}: Bool.pick(Maybe<&2, String>, String.eq(name, id), previous, Some{name})
    case None{}: None{}

# content_block_start
# -------------------
def toolArguments(value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.ObjectValue{R.new(V.Value)}
    case other: other

def toolName(+name: String, oauth: Bool, tools: List<&2, T.Tool<V.Value>>) -> String:
  match oauth:
    case True{}: Messages.fromClaudeCodeName(name, tools)
    case False{}: name

def startEvent(-G: Data, index: F64, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{_}: T.TextStart{index, message}
    case ThinkingBlock{_}: T.ThinkingStart{index, message}
    case ToolBlock{_, _}: T.ToolcallStart{index, message}

def oauthOf(-G: Data, state: State<G>) -> Bool:
  match state:
    case State{_, _, _, _, _, _, _, oauth, _}: oauth

def toolsOf(-G: Data, state: State<G>) -> List<&2, T.Tool<V.Value>>:
  match state:
    case State{_, _, _, _, _, _, _, _, tools}: tools

# content_block_delta
# -------------------
def appended(value: Maybe<&2, String>, delta: String) -> String:
  match value:
    case Some{text}: text ++ delta
    case None{}: delta

type Delta is Data:
  Delta{block: Block, visible: Maybe<&2, String>}

def deltaEvent(-G: Data, index: F64, part: String, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{_}: T.TextDelta{index, part, message}
    case ThinkingBlock{_}: T.ThinkingDelta{index, part, message}
    case ToolBlock{_, _}: T.ToolcallDelta{index, part, message}

def slotsOf(-G: Data, state: State<G>) -> List<&2, Slot>:
  match state:
    case State{_, slots, _, _, _, _, _, _, _}: slots

# content_block_stop
# ------------------
def stopped(block: Block) -> Block:
  match block:
    case ToolBlock{T.ToolCall{id, name, _, thought, namespace}, json}: ToolBlock{T.ToolCall{id, name, Json.parseStreamingJson(Some{json}), thought, namespace}, ""}
    case other: other

def endEvent(-G: Data, index: F64, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{T.TextContent{value, _}}: T.TextEnd{index, value, message}
    case ThinkingBlock{T.ThinkingContent{value, _, _}}: T.ThinkingEnd{index, value, message}
    case ToolBlock{value, _}: T.ToolcallEnd{index, value, message}

# message_delta
# -------------
def presentOr(value: Maybe<&2, F64>, previous: F64) -> F64: Maybe.default(&2, F64, value, previous)

def presentOrMaybe(value: Maybe<&2, F64>, previous: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match value:
    case Some{item}: Some{item}
    case None{}: previous

# Only present (non-null) counts replace earlier ones; thinking tokens are
# reasoning, a subset of output.
def deltaUsage(usage: T.Usage, +incoming: V.Value) -> T.Usage:
  match usage:
    case T.Usage{input, output, read, write, long, reasoning, total, cost}:
      T.Usage{presentOr(optionalNumber(field(incoming, "input_tokens")), input), presentOr(optionalNumber(field(incoming, "output_tokens")), output), presentOr(optionalNumber(field(incoming, "cache_read_input_tokens")), read), presentOr(optionalNumber(field(incoming, "cache_creation_input_tokens")), write), long, presentOrMaybe(optionalNumber(field(field(incoming, "output_tokens_details"), "thinking_tokens")), reasoning), total, cost}

def stopErrorMessage(mapping: Messages.StopMapping, previous: Maybe<&2, String>) -> Maybe<&2, String>:
  match mapping:
    case Messages.StopMapping{_, Some{message}}: Some{message}
    case Messages.StopMapping{_, None{}}: previous

def stopReasonOf(mapping: Messages.StopMapping) -> T.StopReason:
  match mapping:
    case Messages.StopMapping{reason, _}: reason

# Events
# ------
def markStop(-G: Data, state: State<G>) -> State<G>:
  match state:
    case State{message, slots, model, usageModel, transformations, start, _, oauth, tools}: State{message, slots, model, usageModel, transformations, start, True{}, oauth, tools}

def knownEvent(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{"message_start"}: True{}
    case Some{"message_delta"}: True{}
    case Some{"message_stop"}: True{}
    case Some{"content_block_start"}: True{}
    case Some{"content_block_delta"}: True{}
    case Some{"content_block_stop"}: True{}
    case _: False{}

# After the loop
# --------------
def withError(-G: Data, message: T.AssistantMessage<V.Value, G>, reason: T.StopReason, text: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, Some{text}, raw, endTurn, timestamp}

def errorReason(aborted: Bool) -> T.ErrorReason:
  match aborted:
    case True{}: T.ErrorAborted{}
    case False{}: T.ErrorError{}

def stopFor(aborted: Bool) -> T.StopReason:
  match aborted:
    case True{}: T.Aborted{}
    case False{}: T.Error{}

def diagnostic(-G: Data, message: T.AssistantMessage<V.Value, G>, value: Diagnostics.AssistantMessageDiagnostic<G>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, Some{List.append(&2, Diagnostics.AssistantMessageDiagnostic<G>, Maybe.default(&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>, diagnostics, Nil{}), value <> Nil{})}, usage, stop, deferred, error, raw, endTurn, timestamp}

def withTransformations(-G: Data, message: T.AssistantMessage<V.Value, G>, transformations: Maybe<&2, List<&2, InputTransformation>>, timestamp: F64, details: List<&2, InputTransformation> -> G) -> T.AssistantMessage<V.Value, G>:
  match transformations:
    case Some{Nil{}}: message
    case Some{values}: diagnostic(G, message, Diagnostics.AssistantMessageDiagnostic{"anthropic_input_transformations", timestamp, None{}, Some{details(values)}})
    case None{}: message

def errorOr(value: Maybe<&2, String>) -> String:
  match value:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "An unknown error occurred"

# The response side of upstream `stream` (anthropic-messages.ts) as pure
# transitions: iterateSseMessages' line decoder, iterateAnthropicEvents'
# filtering and parsing, the event loop over the assistant message and the
# checks after the loop. The IO driver (anthropic-messages-client.bend) only
# feeds body chunks and publishes the returned events.
# Server-sent events
# ------------------
type ServerSentEvent is Data:
  ServerSentEvent{event: Maybe<&2, String>, data: String, raw: List<&2, String>}

# Field lines accumulate in reverse; `buffer` holds the undecoded line tail.
type SseDecoder is Data:
  SseDecoder{utf8: UTF8.Decoder, buffer: String, event: Maybe<&2, String>, data: List<&2, String>, raw: List<&2, String>}

type Decoded is Data:
  Decoded{decoder: SseDecoder, events: List<&2, ServerSentEvent>}

def createDecoder() -> SseDecoder: SseDecoder{UTF8.create(), "", None{}, Nil{}, Nil{}}

def bufferOf(decoder: SseDecoder) -> String:
  match decoder:
    case SseDecoder{_, buffer, _, _, _}: buffer

def utf8Of(decoder: SseDecoder) -> UTF8.Decoder:
  match decoder:
    case SseDecoder{utf8, _, _, _, _}: utf8

def flushedEvent(event: Maybe<&2, String>, data: List<&2, String>, raw: List<&2, String>, empty: Bool) -> Maybe<&2, ServerSentEvent>:
  match empty:
    case True{}: None{}
    case False{}: Some{ServerSentEvent{event, String.join(List.reverse(&2, String, data), "\n"), List.reverse(&2, String, raw)}}

type Flushed is Data:
  Flushed{decoder: SseDecoder, event: Maybe<&2, ServerSentEvent>}

# upstream flushSseEvent: nothing without an event name or data.
def flushSseEvent(decoder: SseDecoder) -> Flushed:
  match decoder:
    case SseDecoder{utf8, buffer, +event, +data, raw}: Flushed{SseDecoder{utf8, buffer, None{}, Nil{}, Nil{}}, flushedEvent(event, data, raw, Bool.not(truthy(event)) && List.is_empty(&2, String, data))}

def fieldLine(decoder: SseDecoder, field: Field) -> SseDecoder:
  match decoder field:
    case SseDecoder{utf8, buffer, _, data, raw} Field{"event", value}: SseDecoder{utf8, buffer, Some{value}, data, raw}
    case SseDecoder{utf8, buffer, event, data, raw} Field{"data", value}: SseDecoder{utf8, buffer, event, value <> data, raw}
    case current _: current

def recordRaw(decoder: SseDecoder, line: String) -> SseDecoder:
  match decoder:
    case SseDecoder{utf8, buffer, event, data, raw}: SseDecoder{utf8, buffer, event, data, line <> raw}

def nonemptyLine(decoder: SseDecoder, +line: String) -> SseDecoder:
  match line:
    case SCon{':', _}: recordRaw(decoder, line)
    case _: fieldLine(recordRaw(decoder, line), splitField(line, ""))

# upstream decodeSseLine: a blank line dispatches the pending event.
def decodeSseLine(+line: String, decoder: SseDecoder) -> Flushed:
  match line:
    case SNil{}: flushSseEvent(decoder)
    case _: Flushed{nonemptyLine(decoder, line), None{}}

def withBuffer(decoder: SseDecoder, buffer: String) -> SseDecoder:
  match decoder:
    case SseDecoder{utf8, _, event, data, raw}: SseDecoder{utf8, buffer, event, data, raw}

def prependEvent(event: Maybe<&2, ServerSentEvent>, reversed: List<&2, ServerSentEvent>) -> List<&2, ServerSentEvent>:
  match event:
    case None{}: reversed
    case Some{item}: item <> reversed

def appendText(decoder: SseDecoder, text: String) -> SseDecoder:
  match decoder:
    case SseDecoder{utf8, buffer, event, data, raw}: SseDecoder{utf8, buffer ++ text, event, data, raw}

def withUtf8(decoder: SseDecoder, utf8: UTF8.Decoder) -> SseDecoder:
  match decoder:
    case SseDecoder{_, buffer, event, data, raw}: SseDecoder{utf8, buffer, event, data, raw}

def trailing(flushed: Flushed) -> List<&2, ServerSentEvent>:
  match flushed:
    case Flushed{_, event}: prependEvent(event, Nil{})

def parseErrorText(cause: Parse.ParseError) -> String:
  match cause:
    case Parse.ParseInvalidValue{}: "invalid value"
    case Parse.InvalidEscape{}: "invalid escape"
    case Parse.UnescapedControl{}: "unescaped control character"
    case Parse.UnterminatedString{}: "unterminated string"
    case Parse.UnexpectedToken{}: "unexpected token"
    case Parse.UnexpectedEnd{}: "unexpected end"
    case Parse.TrailingInput{}: "trailing input"
    case Parse.InputLimit{}: "input limit exceeded"

def lastLine(flushed: Flushed) -> List<&2, ServerSentEvent>:
  match flushed:
    case Flushed{decoder, event}: List.append(&2, ServerSentEvent, prependEvent(event, Nil{}), trailing(flushSseEvent(decoder)))

def finalLine(decoder: SseDecoder, events: List<&2, ServerSentEvent>) -> List<&2, ServerSentEvent>:
  match decoder:
    case SseDecoder{utf8, SNil{}, event, data, raw}: List.append(&2, ServerSentEvent, events, trailing(flushSseEvent(SseDecoder{utf8, "", event, data, raw})))
    case SseDecoder{utf8, SCon{c, cs}, event, data, raw}: List.append(&2, ServerSentEvent, events, lastLine(decodeSseLine(SCon{c, cs}, SseDecoder{utf8, "", event, data, raw})))

def finishedText(decoded: Decoded) -> List<&2, ServerSentEvent>:
  match decoded:
    case Decoded{decoder, events}: finalLine(decoder, events)

# A thrown error ends the loop; the driver then runs the catch block.
type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, thrown: Maybe<&2, String>}

def unchanged(-G: Data, state: State<G>) -> Step<G>: Step{state, Nil{}, None{}}

def throwStep(-G: Data, state: State<G>, message: String) -> Step<G>: Step{state, Nil{}, Some{message}}

def fallback(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{+message, slots, model, usageModel, transformations, start, end, oauth, tools}:
      +current = {State{message, slots, model, usageModel, transformations, start, end, oauth, tools} : State<G>}
      Bool.pick(Step<G>, Nat.is_eq(contentCount(G, message), 0n), unchanged(G, current), throwStep(G, current, "Anthropic performed an unsupported mid-output model fallback"))

def textOr(value: V.Value, fallback: String) -> String: Maybe.default(&2, String, textValue(value), fallback)

def eventType(value: V.Value) -> String: textOr(field(value, "type"), "")

def startedBlock(+value: V.Value, kind: String, oauth: Bool, tools: List<&2, T.Tool<V.Value>>) -> Maybe<&2, Block>:
  match kind:
    case "text": Some{TextBlock{T.TextContent{textOr(field(value, "text"), ""), None{}}}}
    case "thinking": Some{ThinkingBlock{T.ThinkingContent{textOr(field(value, "thinking"), ""), Some{textOr(field(value, "signature"), "")}, None{}}}}
    case "redacted_thinking": Some{ThinkingBlock{T.ThinkingContent{"[Reasoning redacted]", textValue(field(value, "data")), Some{True{}}}}}
    case "tool_use": Some{ToolBlock{T.ToolCall{textOr(field(value, "id"), ""), toolName(textOr(field(value, "name"), ""), oauth, tools), toolArguments(field(value, "input")), None{}, None{}}, ""}}
    case _: None{}

def appliedDelta(block: Block, kind: String, +delta: V.Value) -> Maybe<&2, Delta>:
  match block kind:
    case TextBlock{T.TextContent{value, signature}} "text_delta":
      +part = textOr(field(delta, "text"), "")
      Some{Delta{TextBlock{T.TextContent{value ++ part, signature}}, Some{part}}}
    case ThinkingBlock{T.ThinkingContent{value, signature, redacted}} "thinking_delta":
      +part = textOr(field(delta, "thinking"), "")
      Some{Delta{ThinkingBlock{T.ThinkingContent{value ++ part, signature, redacted}}, Some{part}}}
    case ToolBlock{T.ToolCall{id, name, _, thought, namespace}, json} "input_json_delta":
      +part = textOr(field(delta, "partial_json"), "")
      +next = json ++ part
      Some{Delta{ToolBlock{T.ToolCall{id, name, Json.parseStreamingJson(Some{next}), thought, namespace}, next}, Some{part}}}
    case ThinkingBlock{T.ThinkingContent{value, signature, redacted}} "signature_delta": Some{Delta{ThinkingBlock{T.ThinkingContent{value, Some{appended(signature, textOr(field(delta, "signature"), ""))}, redacted}}, None{}}}
    case _ _: None{}

def mappedDelta(-G: Data, state: State<G>, +raw: String, mapping: Result<&2, &2, String, Messages.StopMapping>) -> Step<G>:
  match mapping state:
    case Fail{message} State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, _, endTurn, timestamp}, slots, model, usageModel, transformations, start, end, oauth, tools}:
      throwStep(G, State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, Some{raw}, endTurn, timestamp}, slots, model, usageModel, transformations, start, end, oauth, tools}, message)
    case Done{+selected} State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp}, slots, model, usageModel, transformations, start, end, oauth, tools}:
      unchanged(G, State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stopReasonOf(selected), deferred, stopErrorMessage(selected, error), Some{raw}, endTurn, timestamp}, slots, model, usageModel, transformations, start, end, oauth, tools})

def stopReasonDelta(-G: Data, state: State<G>, +delta: V.Value, reason: Maybe<&2, String>) -> Step<G>:
  match reason:
    case Some{SCon{+c, +cs}}: mappedDelta(G, state, SCon{c, cs}, Messages.mapStopReason(SCon{c, cs}, textValue(field(field(delta, "stop_details"), "explanation"))))
    case _: unchanged(G, state)

def appendSteps(-G: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Step<G>) -> Step<G>:
  match step:
    case Step{state, later, thrownMessage}: Step{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, later), thrownMessage}

# upstream's catch block: the stop reason follows the abort signal and the
# thrown error's message becomes the error message.
def failed(-G: Data, state: State<G>, message: String, +aborted: Bool) -> Step<G>:
  match state:
    case State{current, slots, model, usageModel, transformations, start, end, oauth, tools}:
      +output = withError(G, current, stopFor(aborted), message)
      Step{State{output, slots, model, usageModel, transformations, start, end, oauth, tools}, T.StreamError{errorReason(aborted), output} <> Nil{}, None{}}

def emitted(-G: Data, state: State<G>, event: T.AssistantMessageEvent<V.Value, G>) -> Step<G>: Step{state, event <> Nil{}, None{}}

def added(-G: Data, state: State<G>, key: Maybe<&2, F64>, block: Maybe<&2, Block>) -> Step<G>:
  match block state:
    case None{} current: unchanged(G, current)
    case Some{+next} State{+message, slots, model, usageModel, transformations, start, end, oauth, tools}:
      +at = contentCount(G, message)
      +updated = withContent(G, message, at, next)
      emitted(G, State{updated, Slot{key, at, next} <> slots, model, usageModel, transformations, start, end, oauth, tools}, startEvent(G, contentPosition(at), updated, next))

def deltaApplied(-G: Data, state: State<G>, key: Maybe<&2, F64>, +at: Nat, delta: Maybe<&2, Delta>) -> Step<G>:
  match delta state:
    case None{} current: unchanged(G, current)
    case Some{Delta{+block, None{}}} State{message, slots, model, usageModel, transformations, start, end, oauth, tools}:
      unchanged(G, State{withContent(G, message, at, block), replaceSlot(slots, Slot{key, at, block}), model, usageModel, transformations, start, end, oauth, tools})
    case Some{Delta{+block, Some{part}}} State{message, slots, model, usageModel, transformations, start, end, oauth, tools}:
      +updated = withContent(G, message, at, block)
      emitted(G, State{updated, replaceSlot(slots, Slot{key, at, block}), model, usageModel, transformations, start, end, oauth, tools}, deltaEvent(G, contentPosition(at), part, updated, block))

def deltaFound(-G: Data, state: State<G>, found: Maybe<&2, Slot>, +delta: V.Value) -> Step<G>:
  match found:
    case None{}: unchanged(G, state)
    case Some{Slot{key, +at, block}}: deltaApplied(G, state, key, at, appliedDelta(block, eventType(delta), delta))

def stopFound(-G: Data, state: State<G>, found: Maybe<&2, Slot>) -> Step<G>:
  match found state:
    case None{} current: unchanged(G, current)
    case Some{Slot{_, +at, block}} State{message, slots, model, usageModel, transformations, start, end, oauth, tools}:
      +finished = stopped(block)
      +updated = withContent(G, message, at, finished)
      emitted(G, State{updated, withoutSlot(slots, at), model, usageModel, transformations, start, end, oauth, tools}, endEvent(G, contentPosition(at), updated, finished))

def doneWith(-G: Data, current: State<G>, +output: T.AssistantMessage<V.Value, G>, reason: T.StopReason) -> Step<G>:
  match reason:
    case T.Stop{}: emitted(G, current, T.StreamDone{T.DoneStop{}, output})
    case T.Length{}: emitted(G, current, T.StreamDone{T.DoneLength{}, output})
    case T.ToolUse{}: emitted(G, current, T.StreamDone{T.DoneToolUse{}, output})
    case T.Pending{}: throwStep(G, current, "Anthropic stream ended without a stop reason")
    case _: throwStep(G, current, errorOr(T.assistantErrorMessage(V.Value, G, output)))

def done(-G: Data, state: State<G>, timestamp: F64, details: List<&2, InputTransformation> -> G) -> Step<G>:
  match state:
    case State{message, slots, model, usageModel, +transformations, start, end, oauth, tools}:
      +output = withTransformations(G, message, transformations, timestamp, details)
      doneWith(G, State{output, slots, model, usageModel, transformations, start, end, oauth, tools}, output, T.assistantStopReason(V.Value, G, output))

# The end of the body: an unfinished message stream, an aborted request, a
# missing or failing stop reason, then input transformation diagnostics and
# `done`. A thrown step still needs the catch block (`failed`).
def finish(-G: Data, state: State<G>, aborted: Bool, timestamp: F64, details: List<&2, InputTransformation> -> G) -> Step<G>:
  match state aborted:
    case State{message, slots, model, usageModel, transformations, True{}, False{}, oauth, tools} _: throwStep(G, State{message, slots, model, usageModel, transformations, True{}, False{}, oauth, tools}, "Anthropic stream ended before message_stop")
    case current True{}: throwStep(G, current, "Request was aborted")
    case current False{}: done(G, current, timestamp, details)

def messageStart(-G: Data, state: State<G>, +event: V.Value) -> Step<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, +id, previous, _, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, slots, +model, _, transformations, _, end, oauth, tools}:
      +reply = field(event, "message")
      +returned = textValue(field(reply, "model"))
      +usageModel = usageModelFor(model, returned)
      +nextUsage = withTotals(startUsage(usage, field(reply, "usage")), usageModel)
      unchanged(G, State{T.AssistantMessage{content, api, provider, id, responseModelFor(id, returned, previous), textValue(field(reply, "id")), level, diagnostics, nextUsage, stop, deferred, error, raw, endTurn, timestamp}, slots, model, usageModel, arrayTransformations(field(reply, "input_transformations"), transformations), True{}, end, oauth, tools})

def blockStartKind(-G: Data, +state: State<G>, +event: V.Value, +block: V.Value, kind: String) -> Step<G>:
  match kind:
    case "fallback": fallback(G, state)
    case other: added(G, state, numberValue(field(event, "index")), startedBlock(block, other, oauthOf(G, state), toolsOf(G, state)))

def blockStart(-G: Data, state: State<G>, +event: V.Value) -> Step<G>:
  +block = field(event, "content_block")
  blockStartKind(G, state, event, block, eventType(block))

def blockDelta(-G: Data, +state: State<G>, +event: V.Value) -> Step<G>:
  deltaFound(G, state, findSlot(slotsOf(G, state), numberValue(field(event, "index"))), field(event, "delta"))

def blockStop(-G: Data, +state: State<G>, +event: V.Value) -> Step<G>:
  stopFound(G, state, findSlot(slotsOf(G, state), numberValue(field(event, "index"))))

def usageDelta(-G: Data, state: State<G>, +event: V.Value) -> State<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, slots, model, +usageModel, transformations, start, end, oauth, tools}:
      +nextUsage = withTotals(deltaUsage(usage, field(event, "usage")), usageModel)
      State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, nextUsage, stop, deferred, error, raw, endTurn, timestamp}, slots, model, usageModel, arrayTransformations(field(event, "input_transformations"), transformations), start, end, oauth, tools}

def usageAfter(-G: Data, step: Step<G>, +event: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: Step{usageDelta(G, state, event), events, None{}}
    case other: other

def messageDelta(-G: Data, state: State<G>, +event: V.Value) -> Step<G>:
  +delta = field(event, "delta")
  usageAfter(G, stopReasonDelta(G, state, delta, textValue(field(delta, "stop_reason"))), event)

def eventNamed(-G: Data, state: State<G>, +value: V.Value, kind: String) -> Step<G>:
  match kind:
    case "message_start": messageStart(G, state, value)
    case "content_block_start": blockStart(G, state, value)
    case "content_block_delta": blockDelta(G, state, value)
    case "content_block_stop": blockStop(G, state, value)
    case "message_delta": messageDelta(G, state, value)
    case "message_stop": unchanged(G, markStop(G, state))
    case _: unchanged(G, state)

# One parsed Anthropic stream event.
def streamEvent(-G: Data, state: State<G>, +value: V.Value) -> Step<G>: eventNamed(G, state, value, eventType(value))

def parsedEvent(-G: Data, state: State<G>, sse: ServerSentEvent, result: Result<&2, &2, Parse.ParseError, V.Value>) -> Step<G>:
  match result sse:
    case Done{value} _: streamEvent(G, state, value)
    case Fail{cause} ServerSentEvent{name, data, raw}: throwStep(G, state, "Could not parse Anthropic SSE event " ++ Maybe.default(&2, String, name, "null") ++ ": " ++ parseErrorText(cause) ++ "; data=" ++ data ++ "; raw=" ++ String.join(raw, "\\n"))

def filteredEvent(-G: Data, state: State<G>, sse: ServerSentEvent, known: Bool) -> Step<G>:
  match known sse:
    case False{} _: unchanged(G, state)
    case True{} ServerSentEvent{name, +data, raw}: parsedEvent(G, state, ServerSentEvent{name, data, raw}, Json.parseJsonWithRepair(data))

def messageEvent(-G: Data, state: State<G>, +name: Maybe<&2, String>, data: String, raw: List<&2, String>) -> Step<G>:
  filteredEvent(G, state, ServerSentEvent{name, data, raw}, knownEvent(name))

def namedEvent(-G: Data, state: State<G>, name: Maybe<&2, String>, data: String, raw: List<&2, String>) -> Step<G>:
  match name:
    case Some{"error"}: throwStep(G, state, data)
    case other: messageEvent(G, state, other, data, raw)

# upstream iterateAnthropicEvents for one server-sent event: an `error` event
# throws its data; only message events are parsed, with repair.
def serverSentEvent(-G: Data, state: State<G>, sse: ServerSentEvent) -> Step<G>:
  match sse:
    case ServerSentEvent{name, data, raw}: namedEvent(G, state, name, data, raw)

# Consecutive events stop at the first thrown error.
def serverSentEvents(-G: Data, events: List<&2, ServerSentEvent>, step: Step<G>) -> Step<G>:
  match events step:
    case _ Step{state, emittedEvents, Some{message}}: Step{state, emittedEvents, Some{message}}
    case Nil{} Step{state, emittedEvents, None{}}: Step{state, emittedEvents, None{}}
    case sse <> rest Step{state, emittedEvents, None{}}: serverSentEvents(G, rest, appendSteps(G, emittedEvents, serverSentEvent(G, state, sse)))

type Drain is Data:
  Drained{decoded: Decoded}
  Draining{decoder: SseDecoder, reversed: List<&2, ServerSentEvent>}

def lineFlushed(flushed: Flushed, rest: String, reversed: List<&2, ServerSentEvent>) -> Drain:
  match flushed:
    case Flushed{decoder, event}: Draining{withBuffer(decoder, rest), prependEvent(event, reversed)}

def consumedLine(decoder: SseDecoder, reversed: List<&2, ServerSentEvent>, line: Maybe<&2, Line>) -> Drain:
  match line:
    case None{}: Drained{Decoded{decoder, List.reverse(&2, ServerSentEvent, reversed)}}
    case Some{Line{text, rest}}: lineFlushed(decodeSseLine(text, decoder), rest, reversed)

def drainStep(+decoder: SseDecoder, reversed: List<&2, ServerSentEvent>) -> Drain:
  +buffer = bufferOf(decoder)
  consumedLine(decoder, reversed, consumeLine(buffer, ""))

# Each line consumes at least one buffered character, so the buffer's length
# bounds the loop.
def drainLines(fuel: Nat, step: Drain) -> Decoded:
  match fuel step:
    case _ Drained{decoded}: decoded
    case 0n Draining{decoder, reversed}: Decoded{decoder, List.reverse(&2, ServerSentEvent, reversed)}
    case 1n+left Draining{decoder, reversed}: drainLines(left, drainStep(decoder, reversed))

def drain(+decoder: SseDecoder) -> Decoded:
  +buffer = bufferOf(decoder)
  drainLines(1n + String.length(buffer), Draining{decoder, Nil{}})

def decodeText(decoder: SseDecoder, text: String) -> Decoded: drain(appendText(decoder, text))

def decodedBytes(decoder: SseDecoder, result: UTF8.Decoded) -> Decoded:
  match result:
    case UTF8.Decoded{utf8, text}: decodeText(withUtf8(decoder, utf8), text)

# One body chunk through TextDecoder (stream: true) and the line decoder.
def decodeBytes(decoder: SseDecoder, bytes: List<&2, U32>) -> Decoded:
  match decoder:
    case SseDecoder{utf8, buffer, event, data, raw}: decodedBytes(SseDecoder{UTF8.create(), buffer, event, data, raw}, UTF8.decode(utf8, bytes))

def flushedUtf8(decoder: SseDecoder, result: UTF8.Decoded) -> List<&2, ServerSentEvent>:
  match result:
    case UTF8.Decoded{utf8, text}: finishedText(decodeText(withUtf8(decoder, utf8), text))

# End of body: the decoder's final text, the remaining complete lines, an
# unterminated last line, then a trailing event without a blank line.
def finishDecoder(decoder: SseDecoder) -> List<&2, ServerSentEvent>:
  match decoder:
    case SseDecoder{utf8, buffer, event, data, raw}: flushedUtf8(SseDecoder{UTF8.create(), buffer, event, data, raw}, UTF8.finish(utf8))
