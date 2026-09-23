import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/json-parse.bend as Json
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Pure fold of Anthropic's message SSE events. Wire indices identify blocks;
# public content indices count only supported blocks, including redacted thinking.
type Block is Data:
  TextBlock{value: T.TextContent}
  ThinkingBlock{value: T.ThinkingContent}
  ToolBlock{value: T.ToolCall<V.Value>, json: String}

type Slot is Data:
  Slot{wireIndex: F64, contentIndex: Nat, block: Block}

type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, slots: List<&2, Slot>, started: Bool, stopped: Bool}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, String>}

def zero() -> F64: F.fromU32(0)
def emptyUsage() -> T.Usage:
  T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def create(-G: Data, model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>:
  match model:
    case T.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      State{T.AssistantMessage{Nil{}, "anthropic-messages", provider, id, None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, Nil{}, False{}, False{}}

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def orNull(value: Maybe<&2, V.Value>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{item}: item

def at(object: V.Value, name: String) -> V.Value: orNull(field(object, name))

def asText(value: V.Value) -> String:
  match value:
    case V.Text{item}: item
    case _: ""

def optionalText(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{item}: Some{item}
    case _: None{}

def number(value: V.Value) -> F64:
  match value:
    case V.Number{item}: item
    case _: zero()

def optionalNumber(value: V.Value) -> Maybe<&2, F64>:
  match value:
    case V.Number{item}: Some{item}
    case _: None{}

def eventType(event: V.Value) -> String: asText(at(event, "type"))

def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)

def index(value: Nat) -> F64:
  match value:
    case 0n: zero()
    case 1n+rest: F.add(F.fromU32(1), index(rest))

def blockContent(block: Block) -> T.AssistantContent<V.Value>:
  match block:
    case TextBlock{value}: T.AssistantText{value}
    case ThinkingBlock{value}: T.AssistantThinking{value}
    case ToolBlock{value, _}: T.AssistantToolCall{value}

def replace(values: List<&2, T.AssistantContent<V.Value>>, position: Nat, next: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values position:
    case Nil{} _: next <> Nil{}
    case _ <> tail 0n: next <> tail
    case head <> tail 1n+rest: head <> replace(tail, rest, next)

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, values: List<&2, T.AssistantContent<V.Value>>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{values, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withBlock(-G: Data, +message: T.AssistantMessage<V.Value, G>, position: Nat, block: Block) -> T.AssistantMessage<V.Value, G>:
  withContent(G, message, replace(T.assistantContent(V.Value, G, message), position, blockContent(block)))

def slot(slots: List<&2, Slot>, +key: F64) -> Maybe<&2, Slot>:
  match slots:
    case Nil{}: None{}
    case Slot{+wire, position, block} <> rest: Bool.pick(Maybe<&2, Slot>, F.isEqual(F.compare(wire, key)), Some{Slot{wire, position, block}}, slot(rest, key))

def without(slots: List<&2, Slot>, +key: F64) -> List<&2, Slot>:
  match slots:
    case Nil{}: Nil{}
    case Slot{+wire, position, block} <> rest:
      +tail = without(rest, key)
      Bool.pick(List<&2, Slot>, F.isEqual(F.compare(wire, key)), tail, Slot{wire, position, block} <> tail)

def startBlockNamed(+value: V.Value, kind: String) -> Maybe<&2, Block>:
  match kind:
    case "text": Some{TextBlock{T.TextContent{asText(at(value, "text")), None{}}}}
    case "thinking": Some{ThinkingBlock{T.ThinkingContent{asText(at(value, "thinking")), Some{asText(at(value, "signature"))}, None{}}}}
    case "redacted_thinking": Some{ThinkingBlock{T.ThinkingContent{"[Reasoning redacted]", Some{asText(at(value, "data"))}, Some{True{}}}}}
    case "tool_use": Some{ToolBlock{T.ToolCall{asText(at(value, "id")), asText(at(value, "name")), at(value, "input"), None{}, None{}}, ""}}
    case _: None{}

def startBlock(+value: V.Value) -> Maybe<&2, Block>: startBlockNamed(value, eventType(value))

def started(-G: Data, position: F64, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{_}: T.TextStart{position, message}
    case ThinkingBlock{_}: T.ThinkingStart{position, message}
    case ToolBlock{_, _}: T.ToolcallStart{position, message}

def changed(-G: Data, position: F64, delta: String, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{_}: T.TextDelta{position, delta, message}
    case ThinkingBlock{_}: T.ThinkingDelta{position, delta, message}
    case ToolBlock{_, _}: T.ToolcallDelta{position, delta, message}

def ended(-G: Data, position: F64, message: T.AssistantMessage<V.Value, G>, block: Block) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case TextBlock{T.TextContent{text, _}}: T.TextEnd{position, text, message}
    case ThinkingBlock{T.ThinkingContent{text, _, _}}: T.ThinkingEnd{position, text, message}
    case ToolBlock{value, _}: T.ToolcallEnd{position, value, message}

def applied(-G: Data, state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> Step<G>:
  Step{state, events, None{}}

def unchanged(-G: Data, state: State<G>) -> Step<G>: applied(G, state, Nil{})

def failed(-G: Data, state: State<G>, +cause: String) -> Step<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}, slots, began, stopped}:
      +message = {T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, T.Error{}, deferred, Some{cause}, raw, endTurn, timestamp} : T.AssistantMessage<V.Value, G>}
      Step{State{message, slots, began, stopped}, T.StreamError{T.ErrorError{}, message} <> Nil{}, Some{cause}}

def fallbackWith(-G: Data, state: State<G>, empty: Bool) -> Step<G>:
  match empty:
    case True{}: unchanged(G, state)
    case False{}: failed(G, state, "Anthropic performed an unsupported mid-output model fallback")

def fallback(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{+message, slots, began, stopped}:
      fallbackWith(G, State{message, slots, began, stopped}, List.is_empty(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message)))

def added(-G: Data, state: State<G>, key: F64, block: Maybe<&2, Block>) -> Step<G>:
  match state block:
    case State{message, slots, began, stopped} None{}: unchanged(G, State{message, slots, began, stopped})
    case State{+message, slots, began, stopped} Some{+next}:
      +position = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +updated = withBlock(G, message, position, next)
      applied(G, State{updated, Slot{key, position, next} <> slots, began, stopped}, started(G, index(position), updated, next) <> Nil{})

def appendSignature(value: Maybe<&2, String>, delta: String) -> String:
  match value:
    case None{}: delta
    case Some{text}: text ++ delta

def updateBlock(block: Block, kind: String, delta: V.Value) -> Block:
  match block kind:
    case TextBlock{T.TextContent{value, signature}} "text_delta": TextBlock{T.TextContent{value ++ asText(at(delta, "text")), signature}}
    case ThinkingBlock{T.ThinkingContent{value, signature, redacted}} "thinking_delta": ThinkingBlock{T.ThinkingContent{value ++ asText(at(delta, "thinking")), signature, redacted}}
    case ThinkingBlock{T.ThinkingContent{value, signature, redacted}} "signature_delta": ThinkingBlock{T.ThinkingContent{value, Some{appendSignature(signature, asText(at(delta, "signature")))}, redacted}}
    case ToolBlock{T.ToolCall{id, name, _, thought, namespace}, json} "input_json_delta":
      +next = json ++ asText(at(delta, "partial_json"))
      ToolBlock{T.ToolCall{id, name, Json.parseStreamingJson(Some{next}), thought, namespace}, next}
    case other _: other

def deltaText(kind: String, delta: V.Value) -> String:
  match kind:
    case "text_delta": asText(at(delta, "text"))
    case "thinking_delta": asText(at(delta, "thinking"))
    case "input_json_delta": asText(at(delta, "partial_json"))
    case _: ""

def visible(+kind: String) -> Bool:
  String.eq(kind, "text_delta") || String.eq(kind, "thinking_delta") || String.eq(kind, "input_json_delta")

def deltaExisting(-G: Data, state: State<G>, found: Maybe<&2, Slot>, +delta: V.Value) -> Step<G>:
  match state found:
    case current None{}: unchanged(G, current)
    case State{message, slots, began, stopped} Some{Slot{+key, +position, block}}:
      +kind = eventType(delta)
      +next = updateBlock(block, kind, delta)
      +updated = withBlock(G, message, position, next)
      +events = Bool.pick(List<&2, T.AssistantMessageEvent<V.Value, G>>, visible(kind), changed(G, index(position), deltaText(kind, delta), updated, next) <> Nil{}, Nil{})
      applied(G, State{updated, Slot{key, position, next} <> without(slots, key), began, stopped}, events)

def finalized(block: Block) -> Block:
  match block:
    case ToolBlock{T.ToolCall{id, name, _, thought, namespace}, json}: ToolBlock{T.ToolCall{id, name, Json.parseStreamingJson(Some{json}), thought, namespace}, ""}
    case value: value

def stopExisting(-G: Data, state: State<G>, found: Maybe<&2, Slot>) -> Step<G>:
  match state found:
    case current None{}: unchanged(G, current)
    case State{message, slots, began, stopped} Some{Slot{+key, +position, block}}:
      +next = finalized(block)
      +updated = withBlock(G, message, position, next)
      applied(G, State{updated, without(slots, key), began, stopped}, ended(G, index(position), updated, next) <> Nil{})

def reason(value: String) -> T.StopReason:
  match value:
    case "end_turn": T.Stop{}
    case "pause_turn": T.Stop{}
    case "stop_sequence": T.Stop{}
    case "max_tokens": T.Length{}
    case "tool_use": T.ToolUse{}
    case _: T.Error{}

def prefer(-A: Data, value: Maybe<&2, A>, fallback: Maybe<&2, A>) -> Maybe<&2, A>:
  match value:
    case None{}: fallback
    case some: some

def maybeNumber(value: Maybe<&2, F64>, fallback: F64) -> F64:
  match value:
    case None{}: fallback
    case Some{item}: item

def withCost(original: T.Usage, cost: T.UsageCost) -> T.Usage:
  match original:
    case T.Usage{input, output, read, write, write1h, reasoning, total, _}: T.Usage{input, output, read, write, write1h, reasoning, total, cost}

def usage(original: T.Usage, +incoming: V.Value, model: T.Model<T.JsonValue>) -> T.Usage:
  match original:
    case T.Usage{input, output, read, write, write1h, reasoning, _, _}:
      +nextInput = optionalNumber(at(incoming, "input_tokens"))
      +nextOutput = optionalNumber(at(incoming, "output_tokens"))
      +nextRead = optionalNumber(at(incoming, "cache_read_input_tokens"))
      +nextWrite = optionalNumber(at(incoming, "cache_creation_input_tokens"))
      +a = maybeNumber(nextInput, input)
      +b = maybeNumber(nextOutput, output)
      +c = maybeNumber(nextRead, read)
      +d = maybeNumber(nextWrite, write)
      +long = prefer(F64, optionalNumber(at(at(incoming, "cache_creation"), "ephemeral_1h_input_tokens")), write1h)
      +thought = prefer(F64, optionalNumber(at(at(incoming, "output_tokens_details"), "thinking_tokens")), reasoning)
      +draft = {T.Usage{a, b, c, d, long, thought, F.add(F.add(a, b), F.add(c, d)), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
      withCost(draft, Cost.calculate(T.JsonValue, model, draft))

def messageStart(-G: Data, state: State<G>, event: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, +id, _, _, level, diagnostics, prior, stop, deferred, error, raw, endTurn, timestamp}, slots, _, stopped}:
      +reply = at(event, "message")
      +responseModel = asText(at(reply, "model"))
      +responseId = optionalText(at(reply, "id"))
      +different = Bool.pick(Maybe<&2, String>, String.eq(responseModel, id), None{}, Some{responseModel})
      +nextUsage = usage(prior, at(reply, "usage"), model)
      applied(G, State{T.AssistantMessage{content, api, provider, id, different, responseId, level, diagnostics, nextUsage, stop, deferred, error, raw, endTurn, timestamp}, slots, True{}, stopped}, Nil{})

def matchReason(value: Maybe<&2, String>, previous: T.StopReason) -> T.StopReason:
  match value:
    case None{}: previous
    case Some{item}: reason(item)

def refusalExplanation(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{message}: Some{message}
    case None{}: Some{"The model refused to complete the request"}

def stopError(value: Maybe<&2, String>, delta: V.Value) -> Maybe<&2, String>:
  match value:
    case Some{"refusal"}: refusalExplanation(optionalText(at(at(delta, "stop_details"), "explanation")))
    case Some{"sensitive"}: Some{"Provider stopped with: sensitive"}
    case _: None{}

def messageDelta(-G: Data, state: State<G>, +event: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  match state:
    case State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, prior, stop, deferred, error, raw, endTurn, timestamp}, slots, began, stopped}:
      +wireReason = optionalText(at(at(event, "delta"), "stop_reason"))
      +nextReason = matchReason(wireReason, stop)
      +nextUsage = usage(prior, at(event, "usage"), model)
      applied(G, State{T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, nextUsage, nextReason, deferred, prefer(String, stopError(wireReason, at(event, "delta")), error), prefer(String, wireReason, raw), endTurn, timestamp}, slots, began, stopped}, Nil{})

def errorText(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "Anthropic stream ended without a stop reason"

def terminalReason(-G: Data, +next: State<G>, +message: T.AssistantMessage<V.Value, G>, reason: T.StopReason) -> Step<G>:
  match reason:
    case T.Stop{}: applied(G, next, T.StreamDone{T.DoneStop{}, message} <> Nil{})
    case T.Length{}: applied(G, next, T.StreamDone{T.DoneLength{}, message} <> Nil{})
    case T.ToolUse{}: applied(G, next, T.StreamDone{T.DoneToolUse{}, message} <> Nil{})
    case _: failed(G, next, errorText(T.assistantErrorMessage(V.Value, G, message)))

def terminal(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{+message, slots, began, _}: terminalReason(G, State{message, slots, began, True{}}, message, T.assistantStopReason(V.Value, G, message))

def deltaState(-G: Data, +state: State<G>, key: F64, delta: V.Value) -> Step<G>:
  match state:
    case State{_, +slots, _, _}: deltaExisting(G, state, slot(slots, key), delta)

def stopState(-G: Data, +state: State<G>, key: F64) -> Step<G>:
  match state:
    case State{_, +slots, _, _}: stopExisting(G, state, slot(slots, key))

def blockStartedKind(-G: Data, state: State<G>, event: V.Value, block: V.Value, kind: String) -> Step<G>:
  match kind:
    case "fallback": fallback(G, state)
    case _: added(G, state, number(at(event, "index")), startBlock(block))

def blockStarted(-G: Data, state: State<G>, +event: V.Value) -> Step<G>:
  +block = at(event, "content_block")
  blockStartedKind(G, state, event, block, eventType(block))

def eventNamed(-G: Data, state: State<G>, +value: V.Value, model: T.Model<T.JsonValue>, kind: String) -> Step<G>:
  match kind:
    case "message_start": messageStart(G, state, value, model)
    case "content_block_start": blockStarted(G, state, value)
    case "content_block_delta": deltaState(G, state, number(at(value, "index")), at(value, "delta"))
    case "content_block_stop": stopState(G, state, number(at(value, "index")))
    case "message_delta": messageDelta(G, state, value, model)
    case "message_stop": terminal(G, state)
    case _: unchanged(G, state)

def event(-G: Data, state: State<G>, +value: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  eventNamed(G, state, value, model, eventType(value))

def finish(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{_, _, True{}, False{}}: failed(G, state, "Anthropic stream ended before message_stop")
    case _: unchanged(G, state)
