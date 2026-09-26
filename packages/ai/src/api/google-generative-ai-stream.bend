import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/schema-json.bend as Schema
import ../utils/json.bend as Wire
import ./google-shared.bend as Shared
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf8.bend as UTF8

# The response side of upstream `stream` (google-generative-ai.ts) as pure
# transitions: @google/genai's stream framing (processStreamResponse), the
# chunk loop over candidate parts, finish reasons and usage, and the checks
# after the loop. The IO driver feeds body chunks and publishes events.
# Stream framing
# --------------
# The SDK splits the decoded text at the first "\n\n", "\r\r" or "\r\n\r\n"
# and keeps `data:` events; a whole network chunk that parses as a JSON error
# object fails the stream.
type Framer is Data:
  Framer{utf8: UTF8.Decoder, buffer: String}

def createFramer() -> Framer: Framer{UTF8.create(), ""}

type Split is Data:
  Split{event: String, rest: String}

def splitAt(text: String, reversed: String) -> Maybe<&2, Split>:
  match text:
    case SNil{}: None{}
    case SCon{'\n', SCon{'\n', rest}}: Some{Split{String.reverse(reversed), rest}}
    case SCon{'\r', SCon{'\n', SCon{'\r', SCon{'\n', rest}}}}: Some{Split{String.reverse(reversed), rest}}
    case SCon{'\r', SCon{'\r', rest}}: Some{Split{String.reverse(reversed), rest}}
    case SCon{char, rest}: splitAt(rest, SCon{char, reversed})

def dataEvent(+event: String) -> Maybe<&2, String>:
  +trimmed = Space.trim(event)
  Bool.pick(Maybe<&2, String>, String.starts_with(trimmed, "data:"), Some{Space.trim(String.drop(trimmed, 5n))}, None{})

def prependData(value: Maybe<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match value:
    case None{}: reversed
    case Some{data}: data <> reversed

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def errorCode(value: V.Value) -> Maybe<&2, F64>:
  match value:
    case V.ObjectValue{fields}: numberOf(R.get(V.Value, fields, "code"))
    case _: None{}

def inRange(code: Maybe<&2, F64>) -> Bool:
  match code:
    case Some{+value}: F.isAtLeast(F.compare(value, F.fromU32(400))) && F.isGreater(F.compare(F.fromU32(600), value))
    case None{}: False{}

def jsonText(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Schema.toJson(value)), "")

def utf8Of(framer: Framer) -> UTF8.Decoder:
  match framer:
    case Framer{utf8, _}: utf8

# The end of the body: leftover non-blank text is an incomplete segment.
def finishFramer(framer: Framer) -> Maybe<&2, String>:
  match framer:
    case Framer{_, buffer}: Bool.pick(Maybe<&2, String>, Space.blank(buffer), None{}, Some{"Incomplete JSON segment at the end"})

# The chunk loop
# --------------
type BlockKind is Data:
  TextKind{}
  ThinkingKind{}

type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, current: Maybe<&2, BlockKind>, model: T.Model<T.JsonValue>, toolCalls: Nat}

def zero() -> F64: F.fromU32(0)

def emptyUsage() -> T.Usage:
  T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def numberText(+value: F64) -> String: Maybe.default(&2, String, F.toJsonNumber(value), "NaN")

def statusText(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case Some{V.Number{number}}: numberText(number)
    case Some{V.Null{}}: "null"
    case _: "undefined"

def statusOf(value: V.Value) -> String:
  match value:
    case V.ObjectValue{fields}: statusText(R.get(V.Value, fields, "status"))
    case _: "undefined"

# The output message names the adapter's api: "google-generative-ai" or
# "google-vertex" (upstream google-vertex.ts shares this loop).
def createFor(-G: Data, api: String, +model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>:
  State{T.AssistantMessage{Nil{}, api, T.modelProvider(model), T.modelId(model), None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, None{}, model, 0n}

def create(-G: Data, +model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>: createFor(G, "google-generative-ai", model, timestamp)

def messageApi(-G: Data, message: T.AssistantMessage<V.Value, G>) -> String:
  match message:
    case T.AssistantMessage{_, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

def endedWithoutReason(-G: Data, message: T.AssistantMessage<V.Value, G>) -> String:
  Bool.pick(String, String.eq(messageApi(G, message), "google-vertex"), "Google Vertex stream ended without a finish reason", "Google stream ended without a finish reason")

def stateMessage(-G: Data, state: State<G>) -> T.AssistantMessage<V.Value, G>:
  match state:
    case State{message, _, _, _}: message

def fieldOf(value: V.Value, name: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2, V.Value, R.get(V.Value, fields, name), V.Null{})
    case _: V.Null{}

def present(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def textOf(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{item}: Some{item}
    case _: None{}

def truthyText(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def flag(value: V.Value) -> Maybe<&2, Bool>:
  match value:
    case V.Boolean{item}: Some{item}
    case _: None{}

def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)

def lastIndex(-G: Data, message: T.AssistantMessage<V.Value, G>) -> F64:
  F.subtract(F.fromNat(count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))), F.fromU32(1))

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, content: List<&2, T.AssistantContent<V.Value>>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def appended(-G: Data, +message: T.AssistantMessage<V.Value, G>, block: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), block <> Nil{}))

def replaceLast(values: List<&2, T.AssistantContent<V.Value>>, block: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values:
    case Nil{}: block <> Nil{}
    case _ <> Nil{}: block <> Nil{}
    case head <> rest: head <> replaceLast(rest, block)

def lastBlock(values: List<&2, T.AssistantContent<V.Value>>) -> Maybe<&2, T.AssistantContent<V.Value>>: List.last(&2, T.AssistantContent<V.Value>, values)

def blockEndOf(-G: Data, kind: BlockKind, +message: T.AssistantMessage<V.Value, G>, block: Maybe<&2, T.AssistantContent<V.Value>>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match kind block:
    case TextKind{} Some{T.AssistantText{T.TextContent{text, _}}}: T.TextEnd{lastIndex(G, message), text, message} <> Nil{}
    case ThinkingKind{} Some{T.AssistantThinking{T.ThinkingContent{text, _, _}}}: T.ThinkingEnd{lastIndex(G, message), text, message} <> Nil{}
    case _ _: Nil{}

def blockEnd(-G: Data, kind: BlockKind, +message: T.AssistantMessage<V.Value, G>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  blockEndOf(G, kind, message, lastBlock(T.assistantContent(V.Value, G, message)))

def sameKind(current: Maybe<&2, BlockKind>, thinking: Bool) -> Bool:
  match current thinking:
    case Some{TextKind{}} False{}: True{}
    case Some{ThinkingKind{}} True{}: True{}
    case _ _: False{}

def extended(block: Maybe<&2, T.AssistantContent<V.Value>>, +delta: String, signature: Maybe<&2, String>) -> T.AssistantContent<V.Value>:
  match block:
    case Some{T.AssistantThinking{T.ThinkingContent{text, previous, redacted}}}: T.AssistantThinking{T.ThinkingContent{text ++ delta, Shared.retainThoughtSignature(previous, signature), redacted}}
    case Some{T.AssistantText{T.TextContent{text, previous}}}: T.AssistantText{T.TextContent{text ++ delta, Shared.retainThoughtSignature(previous, signature)}}
    case _: T.AssistantText{T.TextContent{delta, signature}}

def deltaEvent(-G: Data, kind: Maybe<&2, BlockKind>, index: F64, delta: String, message: T.AssistantMessage<V.Value, G>) -> T.AssistantMessageEvent<V.Value, G>:
  match kind:
    case Some{ThinkingKind{}}: T.ThinkingDelta{index, delta, message}
    case _: T.TextDelta{index, delta, message}

def hasToolId(content: List<&2, T.AssistantContent<V.Value>>, +id: String) -> Bool:
  match content:
    case Nil{}: False{}
    case T.AssistantToolCall{T.ToolCall{existing, _, _, _, _}} <> rest: String.eq(existing, id) || hasToolId(rest, id)
    case _ <> rest: hasToolId(rest, id)

def argumentsOf(value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.ObjectValue{R.new(V.Value)}
    case other: other

def millisecondText(value: F64) -> String: numberText(value)

# A missing or duplicate id becomes `${name}_${Date.now()}_${++toolCallCounter}`.
def toolId(provided: Maybe<&2, String>, +content: List<&2, T.AssistantContent<V.Value>>, +name: String, +now: F64, calls: Nat) -> String:
  match provided:
    case Some{+id}: Bool.pick(String, hasToolId(content, id), name ++ "_" ++ millisecondText(now) ++ "_" ++ Nat.show(1n + calls), id)
    case None{}: name ++ "_" ++ millisecondText(now) ++ "_" ++ Nat.show(1n + calls)

def generated(provided: Maybe<&2, String>, +content: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match provided:
    case Some{+id}: hasToolId(content, id)
    case None{}: True{}

def argumentsText(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Schema.toJson(value)), "")

def listOf(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}

def firstOf(value: V.Value) -> V.Value:
  match value:
    case V.ArrayValue{head <> _}: head
    case _: V.Null{}

def truthyId(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def tokens(value: V.Value) -> F64:
  match value:
    case V.Number{+item}: Bool.pick(F64, F.isNaN(item), zero(), item)
    case _: zero()

def withCost(usage: T.Usage, cost: T.UsageCost) -> T.Usage:
  match usage:
    case T.Usage{input, output, read, write, long, reasoning, total, _}: T.Usage{input, output, read, write, long, reasoning, total, cost}

def chunkUsage(+metadata: V.Value, model: T.Model<T.JsonValue>) -> T.Usage:
  +prompt = tokens(fieldOf(metadata, "promptTokenCount"))
  +cached = tokens(fieldOf(metadata, "cachedContentTokenCount"))
  +candidates = tokens(fieldOf(metadata, "candidatesTokenCount"))
  +thoughts = tokens(fieldOf(metadata, "thoughtsTokenCount"))
  +draft = {T.Usage{F.subtract(prompt, cached), F.add(candidates, thoughts), cached, zero(), None{}, Some{thoughts}, tokens(fieldOf(metadata, "totalTokenCount")), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
  withCost(draft, Cost.calculate(T.JsonValue, model, draft))

def truthyObject(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{V.ObjectValue{fields}}
    case Some{V.ArrayValue{values}}: Some{V.ArrayValue{values}}
    case _: None{}

def withUsage(-G: Data, state: State<G>, metadata: Maybe<&2, V.Value>) -> State<G>:
  match state metadata:
    case current None{}: current
    case State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp}, current, +model, calls} Some{value}:
      State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, chunkUsage(value, model), stop, deferred, error, raw, endTurn, timestamp}, current, model, calls}

def hasToolCall(content: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match content:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

def toolUse(reason: T.StopReason, tools: Bool) -> T.StopReason:
  match reason tools:
    case T.Stop{} True{}: T.ToolUse{}
    case other _: other

# After the loop
# --------------
def withError(-G: Data, message: T.AssistantMessage<V.Value, G>, reason: T.StopReason, text: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, Some{text}, raw, endTurn, timestamp}

def stopFor(aborted: Bool) -> T.StopReason:
  match aborted:
    case True{}: T.Aborted{}
    case False{}: T.Error{}

def errorReason(aborted: Bool) -> T.ErrorReason:
  match aborted:
    case True{}: T.ErrorAborted{}
    case False{}: T.ErrorError{}

def rawOf(-G: Data, message: T.AssistantMessage<V.Value, G>) -> Maybe<&2, String>:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, raw, _, _}: raw

def providerStopped(raw: Maybe<&2, String>) -> String:
  match raw:
    case Some{SCon{c, cs}}: "Provider stopped with: " ++ SCon{c, cs}
    case _: "An unknown error occurred"

type Framed is Data:
  Framed{framer: Framer, events: List<&2, String>, error: Maybe<&2, String>}

type Framing is Data:
  Framing{buffer: String, reversed: List<&2, String>}
  Complete{buffer: String, events: List<&2, String>}

def frameStep(buffer: String, reversed: List<&2, String>, split: Maybe<&2, Split>) -> Framing:
  match split:
    case None{}: Complete{buffer, List.reverse(&2, String, reversed)}
    case Some{Split{event, rest}}: Framing{rest, prependData(dataEvent(event), reversed)}

# Each event consumes at least two buffered characters, so the buffer's
# length bounds the loop.
def frames(fuel: Nat, state: Framing) -> Framing:
  match fuel state:
    case _ Complete{buffer, events}: Complete{buffer, events}
    case 0n Framing{buffer, reversed}: Complete{buffer, List.reverse(&2, String, reversed)}
    case 1n+left Framing{+buffer, reversed}: frames(left, frameStep(buffer, reversed, splitAt(buffer, "")))

def completed(utf8: UTF8.Decoder, state: Framing, error: Maybe<&2, String>) -> Framed:
  match state:
    case Complete{buffer, events}: Framed{Framer{utf8, buffer}, events, error}
    case Framing{buffer, reversed}: Framed{Framer{utf8, buffer}, List.reverse(&2, String, reversed), error}

def chunkErrorWith(+chunk: V.Value, error: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match error:
    case Some{+detail}: Bool.pick(Maybe<&2, String>, inRange(errorCode(detail)), Some{"got status: " ++ statusOf(detail) ++ ". " ++ jsonText(chunk)}, None{})
    case None{}: None{}

def chunkError(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Maybe<&2, String>:
  match result:
    case Done{V.ObjectValue{+fields}}: chunkErrorWith(V.ObjectValue{fields}, R.get(V.Value, fields, "error"))
    case _: None{}

def framedText(framer: Framer, utf8: UTF8.Decoder, +text: String) -> Framed:
  match framer:
    case Framer{_, buffer}:
      +joined = buffer ++ text
      completed(utf8, frames(1n + String.length(joined), Framing{joined, Nil{}}), chunkError(Parse.parse(text)))

def framedDecoded(framer: Framer, decoded: UTF8.Decoded) -> Framed:
  match decoded:
    case UTF8.Decoded{utf8, text}: framedText(framer, utf8, text)

def frameBytes(+framer: Framer, bytes: List<&2, U32>) -> Framed: framedDecoded(framer, UTF8.decode(utf8Of(framer), bytes))

def frameText(+framer: Framer, text: String) -> Framed: framedText(framer, utf8Of(framer), text)

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, thrown: Maybe<&2, String>}

def ended(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{message, None{}, model, calls}: Step{State{message, None{}, model, calls}, Nil{}, None{}}
    case State{+message, Some{kind}, model, calls}: Step{State{message, None{}, model, calls}, blockEnd(G, kind, message), None{}}

def startBlock(-G: Data, state: State<G>, thinking: Bool) -> Step<G>:
  match state thinking:
    case State{message, _, model, calls} True{}:
      +next = appended(G, message, T.AssistantThinking{T.ThinkingContent{"", None{}, None{}}})
      Step{State{next, Some{ThinkingKind{}}, model, calls}, T.ThinkingStart{lastIndex(G, next), next} <> Nil{}, None{}}
    case State{message, _, model, calls} False{}:
      +next = appended(G, message, T.AssistantText{T.TextContent{"", None{}}})
      Step{State{next, Some{TextKind{}}, model, calls}, T.TextStart{lastIndex(G, next), next} <> Nil{}, None{}}

def appendText(-G: Data, state: State<G>, +delta: String, signature: Maybe<&2, String>) -> Step<G>:
  match state:
    case State{+message, +current, model, calls}:
      +content = T.assistantContent(V.Value, G, message)
      +next = withContent(G, message, replaceLast(content, extended(lastBlock(content), delta, signature)))
      Step{State{next, current, model, calls}, deltaEvent(G, current, lastIndex(G, next), delta, next) <> Nil{}, None{}}

def functionCall(-G: Data, state: State<G>, +part: V.Value, +call: V.Value, +now: F64) -> Step<G>:
  match state:
    case State{+message, _, model, +calls}:
      +content = T.assistantContent(V.Value, G, message)
      +provided = truthyText(fieldOf(call, "id"))
      +name = Maybe.default(&2, String, truthyText(fieldOf(call, "name")), "")
      +arguments = argumentsOf(fieldOf(call, "args"))
      +tool = {T.ToolCall{toolId(provided, content, name, now, calls), name, arguments, truthyText(fieldOf(part, "thoughtSignature")), None{}} : T.ToolCall<V.Value>}
      +next = appended(G, message, T.AssistantToolCall{tool})
      +index = lastIndex(G, next)
      Step{State{next, None{}, model, Bool.pick(Nat, generated(provided, content), 1n + calls, calls)}, T.ToolcallStart{index, next} <> T.ToolcallDelta{index, argumentsText(arguments), next} <> T.ToolcallEnd{index, tool, next} <> Nil{}, None{}}

def finished(-G: Data, state: State<G>, +reason: String, mapped: Result<&2, &2, String, T.StopReason>) -> Step<G>:
  match state mapped:
    case State{T.AssistantMessage{+content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, _, endTurn, timestamp}, current, model, calls} Fail{message}:
      Step{State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, Some{reason}, endTurn, timestamp}, current, model, calls}, Nil{}, Some{message}}
    case State{T.AssistantMessage{+content, api, provider, id, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp}, current, model, calls} Done{selected}:
      Step{State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, toolUse(selected, hasToolCall(content)), deferred, error, Some{reason}, endTurn, timestamp}, current, model, calls}, Nil{}, None{}}

def finishReason(-G: Data, state: State<G>, reason: Maybe<&2, String>) -> Step<G>:
  match reason:
    case Some{+value}: finished(G, state, value, Shared.mapStopReason(value))
    case None{}: Step{state, Nil{}, None{}}

# upstream's catch block; the message is formatProviderError(
# normalizeProviderError(error)), which keeps these errors' own messages.
def failed(-G: Data, state: State<G>, message: String, +aborted: Bool) -> Step<G>:
  match state:
    case State{current, active, model, calls}:
      +output = withError(G, current, stopFor(aborted), message)
      Step{State{output, active, model, calls}, T.StreamError{errorReason(aborted), output} <> Nil{}, None{}}

def appendSteps(-G: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Step<G>) -> Step<G>:
  match step:
    case Step{state, later, thrown}: Step{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, later), thrown}

def afterEnd(-G: Data, step: Step<G>, thinking: Bool) -> Step<G>:
  match step:
    case Step{state, events, _}: appendSteps(G, events, startBlock(G, state, thinking))

def openedFor(-G: Data, state: State<G>, same: Bool, thinking: Bool) -> Step<G>:
  match same:
    case True{}: Step{state, Nil{}, None{}}
    case False{}: afterEnd(G, ended(G, state), thinking)

def opened(-G: Data, +state: State<G>, +thinking: Bool) -> Step<G>:
  match state:
    case State{_, current, _, _}: openedFor(G, state, sameKind(current, thinking), thinking)

def withText(-G: Data, step: Step<G>, +delta: String, signature: Maybe<&2, String>) -> Step<G>:
  match step:
    case Step{state, events, _}: appendSteps(G, events, appendText(G, state, delta, signature))

def textPart(-G: Data, +state: State<G>, +part: V.Value, text: Maybe<&2, String>) -> Step<G>:
  match text:
    case None{}: Step{state, Nil{}, None{}}
    case Some{+delta}: withText(G, opened(G, state, Shared.isThinkingPart(flag(fieldOf(part, "thought")))), delta, textOf(fieldOf(part, "thoughtSignature")))

def withCall(-G: Data, step: Step<G>, +part: V.Value, call: V.Value, +now: F64) -> Step<G>:
  match step:
    case Step{state, events, _}: appendSteps(G, events, functionCall(G, state, part, call, now))

def callPart(-G: Data, +state: State<G>, +part: V.Value, call: Maybe<&2, V.Value>, +now: F64) -> Step<G>:
  match call:
    case None{}: Step{state, Nil{}, None{}}
    case Some{V.Null{}}: Step{state, Nil{}, None{}}
    case Some{value}: withCall(G, ended(G, state), part, value, now)

def afterText(-G: Data, step: Step<G>, +part: V.Value, +now: F64) -> Step<G>:
  match step:
    case Step{state, events, _}: appendSteps(G, events, callPart(G, state, part, present(part, "functionCall"), now))

def partStep(-G: Data, +state: State<G>, +part: V.Value, +now: F64) -> Step<G>:
  afterText(G, textPart(G, state, part, textOf(fieldOf(part, "text"))), part, now)

def parts(-G: Data, values: List<&2, V.Value>, +now: F64, step: Step<G>) -> Step<G>:
  match values step:
    case Nil{} done: done
    case part <> rest Step{state, events, _}: parts(G, rest, now, appendSteps(G, events, partStep(G, state, part, now)))

# `output.responseId ||= chunk.responseId`.
def withResponseId(-G: Data, state: State<G>, +chunk: V.Value) -> State<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, id, responseModel, +responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, current, model, calls}:
      State{T.AssistantMessage{content, api, provider, id, responseModel, Bool.pick(Maybe<&2, String>, truthyId(responseId), responseId, textOf(fieldOf(chunk, "responseId"))), level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, current, model, calls}

def appendUsage(-G: Data, step: Step<G>, +chunk: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: Step{withUsage(G, state, truthyObject(present(chunk, "usageMetadata"))), events, None{}}
    case other: other

def afterParts(-G: Data, step: Step<G>, +candidate: V.Value, +chunk: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: appendUsage(G, appendSteps(G, events, finishReason(G, state, truthyText(fieldOf(candidate, "finishReason")))), chunk)
    case other: other

# One parsed stream chunk; `now` is Date.now() for generated tool call ids.
def streamChunk(-G: Data, state: State<G>, +value: V.Value, +now: F64) -> Step<G>:
  +candidate = firstOf(fieldOf(value, "candidates"))
  afterParts(G, parts(G, listOf(fieldOf(fieldOf(candidate, "content"), "parts")), now, Step{withResponseId(G, state, value), Nil{}, None{}}), candidate, value)

def parsedChunk(-G: Data, state: State<G>, +data: String, result: Result<&2, &2, Parse.ParseError, V.Value>, +now: F64) -> Step<G>:
  match result:
    case Done{value}: streamChunk(G, state, value, now)
    case Fail{_}: Step{state, Nil{}, Some{"exception parsing stream chunk " ++ data ++ ". SyntaxError: JSON Parse error"}}

# Consecutive data events stop at the first thrown error.
def dataEvents(-G: Data, values: List<&2, String>, +now: F64, step: Step<G>) -> Step<G>:
  match values step:
    case _ Step{state, emitted, Some{message}}: Step{state, emitted, Some{message}}
    case Nil{} done: done
    case +data <> rest Step{state, emitted, None{}}: dataEvents(G, rest, now, appendSteps(G, emitted, parsedChunk(G, state, data, Parse.parse(data), now)))

def doneWith(-G: Data, state: State<G>, +message: T.AssistantMessage<V.Value, G>, reason: T.StopReason) -> Step<G>:
  match reason:
    case T.Stop{}: Step{state, T.StreamDone{T.DoneStop{}, message} <> Nil{}, None{}}
    case T.Length{}: Step{state, T.StreamDone{T.DoneLength{}, message} <> Nil{}, None{}}
    case T.ToolUse{}: Step{state, T.StreamDone{T.DoneToolUse{}, message} <> Nil{}, None{}}
    case T.Pending{}: Step{state, Nil{}, Some{endedWithoutReason(G, message)}}
    case _: Step{state, Nil{}, Some{providerStopped(rawOf(G, message))}}

def checked(-G: Data, state: State<G>, aborted: Bool) -> Step<G>:
  match aborted state:
    case True{} current: Step{current, Nil{}, Some{"Request was aborted"}}
    case False{} State{+message, current, model, calls}: doneWith(G, State{message, current, model, calls}, message, T.assistantStopReason(V.Value, G, message))

def afterEnded(-G: Data, step: Step<G>, aborted: Bool) -> Step<G>:
  match step:
    case Step{state, events, _}: appendSteps(G, events, checked(G, state, aborted))

# The end of the stream: the open block ends, then the abort, missing finish
# reason and error checks, then `done`. A thrown step still needs `failed`.
def finish(-G: Data, state: State<G>, aborted: Bool) -> Step<G>: afterEnded(G, ended(G, state), aborted)

# The generated tool-call id counter. Upstream's is one module variable for
# the process; the client carries it in a shared Ref and hands its value to
# each chunk step (see google-generative-ai-client.bend).
def toolCallsOf(-G: Data, state: State<G>) -> Nat:
  match state:
    case State{_, _, _, calls}: calls

def withToolCalls(-G: Data, state: State<G>, calls: Nat) -> State<G>:
  match state:
    case State{message, current, model, _}: State{message, current, model, calls}
