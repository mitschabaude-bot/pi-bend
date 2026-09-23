import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/schema-json.bend as Schema
import ../utils/json.bend as Wire
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Pure fold of Google streamGenerateContent SSE chunks. Each chunk is a
# complete candidate fragment; text parts extend the current public block.
type Active is Data:
  TextBlock{position: Nat, text: String, signature: Maybe<&2, String>}
  ThinkingBlock{position: Nat, text: String, signature: Maybe<&2, String>}

type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, active: Maybe<&2, Active>, started: Bool, finished: Bool, nextTool: Nat}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, String>}

def zero() -> F64: F.fromU32(0)
def emptyUsage() -> T.Usage:
  T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def create(-G: Data, model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>:
  match model:
    case T.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      State{T.AssistantMessage{Nil{}, "google-generative-ai", provider, id, None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, None{}, False{}, False{}, 0n}

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def orNull(value: Maybe<&2, V.Value>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{item}: item

def at(value: V.Value, name: String) -> V.Value: orNull(field(value, name))

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

def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{item}: item
    case _: False{}

def firstItem(value: V.Value) -> V.Value:
  match value:
    case V.ArrayValue{head <> _}: head
    case _: V.Null{}

def parts(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case _: Nil{}

def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)

def position(value: Nat) -> F64:
  match value:
    case 0n: zero()
    case 1n+rest: F.add(F.fromU32(1), position(rest))

def replace(items: List<&2, T.AssistantContent<V.Value>>, position: Nat, value: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match items position:
    case Nil{} _: value <> Nil{}
    case _ <> tail 0n: value <> tail
    case head <> tail 1n+rest: head <> replace(tail, rest, value)

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, content: List<&2, T.AssistantContent<V.Value>>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def prefer(-A: Data, value: Maybe<&2, A>, fallback: Maybe<&2, A>) -> Maybe<&2, A>:
  match value:
    case Some{_}: value
    case None{}: fallback

def withResponse(-G: Data, message: T.AssistantMessage<V.Value, G>, responseId: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, prior, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, prefer(String, prior, responseId), level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, usage: T.Usage) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withStop(-G: Data, message: T.AssistantMessage<V.Value, G>, stop: T.StopReason, reason: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, Some{reason}, endTurn, timestamp}

def withError(-G: Data, message: T.AssistantMessage<V.Value, G>, error: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, id, responseModel, responseId, level, diagnostics, usage, T.Error{}, deferred, Some{error}, raw, endTurn, timestamp}

def applied(-G: Data, state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> Step<G>:
  Step{state, events, None{}}

def unchanged(-G: Data, state: State<G>) -> Step<G>: applied(G, state, Nil{})

def failed(-G: Data, state: State<G>, +cause: String) -> Step<G>:
  match state:
    case State{message, active, started, finished, nextTool}:
      +error = withError(G, message, cause)
      Step{State{error, active, started, finished, nextTool}, T.StreamError{T.ErrorError{}, error} <> Nil{}, Some{cause}}

def activeText(value: Active) -> String:
  match value:
    case TextBlock{_, text, _}: text
    case ThinkingBlock{_, text, _}: text

def activeEnd(-G: Data, value: Active, message: T.AssistantMessage<V.Value, G>) -> T.AssistantMessageEvent<V.Value, G>:
  match value:
    case TextBlock{index, text, _}: T.TextEnd{position(index), text, message}
    case ThinkingBlock{index, text, _}: T.ThinkingEnd{position(index), text, message}

def close(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{message, None{}, started, finished, nextTool}: unchanged(G, State{message, None{}, started, finished, nextTool})
    case State{+message, Some{active}, started, finished, nextTool}:
      applied(G, State{message, None{}, started, finished, nextTool}, activeEnd(G, active, message) <> Nil{})

def extendSignature(previous: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case Some{SCon{first, rest}}: Some{SCon{first, rest}}
    case _: previous

def updated(-G: Data, state: State<G>, +index: Nat, +thought: Bool, +delta: String, previous: String, +signature: Maybe<&2, String>) -> Step<G>:
  match state:
    case State{+message, _, started, finished, nextTool}:
      +text = previous ++ delta
      +block = Bool.pick(T.AssistantContent<V.Value>, thought, T.AssistantThinking{T.ThinkingContent{text, signature, None{}}}, T.AssistantText{T.TextContent{text, signature}})
      +next = withContent(G, message, replace(T.assistantContent(V.Value, G, message), index, block))
      +active = Bool.pick(Active, thought, ThinkingBlock{index, text, signature}, TextBlock{index, text, signature})
      +event = Bool.pick(T.AssistantMessageEvent<V.Value, G>, thought, T.ThinkingDelta{position(index), delta, next}, T.TextDelta{position(index), delta, next})
      applied(G, State{next, Some{active}, started, finished, nextTool}, event <> Nil{})

def prefix(-G: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Step<G>) -> Step<G>:
  match step:
    case Step{state, later, error}: Step{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, later), error}

def begun(-G: Data, state: State<G>, +thought: Bool, delta: String, +signature: Maybe<&2, String>) -> Step<G>:
  match state:
    case State{+message, _, started, finished, nextTool}:
      +index = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +block = Bool.pick(T.AssistantContent<V.Value>, thought, T.AssistantThinking{T.ThinkingContent{"", signature, None{}}}, T.AssistantText{T.TextContent{"", signature}})
      +next = withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), block <> Nil{}))
      +active = Bool.pick(Active, thought, ThinkingBlock{index, "", signature}, TextBlock{index, "", signature})
      +event = Bool.pick(T.AssistantMessageEvent<V.Value, G>, thought, T.ThinkingStart{position(index), next}, T.TextStart{position(index), next})
      +following = updated(G, State{next, Some{active}, started, finished, nextTool}, index, thought, delta, "", signature)
      prefix(G, event <> Nil{}, following)

def afterClose(-G: Data, step: Step<G>, thought: Bool, delta: String, signature: Maybe<&2, String>) -> Step<G>:
  match step:
    case Step{closed, events, _}: prefix(G, events, begun(G, closed, thought, delta, signature))

def textWith(-G: Data, state: State<G>, current: Maybe<&2, Active>, thought: Bool, delta: String, signature: Maybe<&2, String>) -> Step<G>:
  match current thought:
    case Some{TextBlock{index, prior, oldSignature}} False{}: updated(G, state, index, False{}, delta, prior, extendSignature(oldSignature, signature))
    case Some{ThinkingBlock{index, prior, oldSignature}} True{}: updated(G, state, index, True{}, delta, prior, extendSignature(oldSignature, signature))
    case _ _: afterClose(G, close(G, state), thought, delta, signature)

def textPart(-G: Data, +state: State<G>, delta: String, thought: Bool, signature: Maybe<&2, String>) -> Step<G>:
  match state:
    case State{_, current, _, _, _}: textWith(G, state, current, thought, delta, signature)

def toolIdFrom(value: Maybe<&2, String>, name: String, count: Nat) -> String:
  match value:
    case Some{SCon{first, rest}}: SCon{first, rest}
    case _: name ++ "_" ++ Nat.show(count)

def toolId(value: V.Value, name: String, count: Nat) -> String:
  toolIdFrom(optionalText(at(value, "id")), name, count)

def toolClosed(-G: Data, step: Step<G>, part: V.Value, +call: V.Value) -> Step<G>:
  match step:
    case Step{State{+message, _, started, finished, +nextTool}, ended, _}:
      +index = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +name = asText(at(call, "name"))
      +args = at(call, "args")
      +tool = {T.ToolCall{toolId(call, name, nextTool), name, args, optionalText(at(part, "thoughtSignature")), None{}} : T.ToolCall<V.Value>}
      +next = withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), T.AssistantToolCall{tool} <> Nil{}))
      +delta = Maybe.default(&2, String, Wire.stringify(Schema.toJson(args)), "{}")
      +events = {T.ToolcallStart{position(index), next} <> T.ToolcallDelta{position(index), delta, next} <> T.ToolcallEnd{position(index), tool, next} <> Nil{} : List<&2, T.AssistantMessageEvent<V.Value, G>>}
      applied(G, State{next, None{}, started, finished, 1n + nextTool}, List.append(&2, T.AssistantMessageEvent<V.Value, G>, ended, events))

def toolPart(-G: Data, state: State<G>, part: V.Value, call: V.Value) -> Step<G>:
  toolClosed(G, close(G, state), part, call)

def partCall(-G: Data, state: State<G>, value: V.Value, call: Maybe<&2, V.Value>) -> Step<G>:
  match call:
    case Some{selected}: toolPart(G, state, value, selected)
    case None{}: unchanged(G, state)

def partText(-G: Data, state: State<G>, +value: V.Value, selected: Maybe<&2, V.Value>) -> Step<G>:
  match selected:
    case Some{V.Text{delta}}: textPart(G, state, delta, boolean(at(value, "thought")), optionalText(at(value, "thoughtSignature")))
    case _: unchanged(G, state)

def partAfterText(-G: Data, step: Step<G>, +value: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: prefix(G, events, partCall(G, state, value, field(value, "functionCall")))
    case other: other

def part(-G: Data, state: State<G>, +value: V.Value) -> Step<G>:
  partAfterText(G, partText(G, state, value, field(value, "text")), value)

def applyPart(-G: Data, prior: Step<G>, value: V.Value) -> Step<G>:
  match prior:
    case Step{state, events, None{}}: prefix(G, events, part(G, state, value))
    case other: other

def allParts(-G: Data, values: List<&2, V.Value>, step: Step<G>) -> Step<G>:
  match values:
    case Nil{}: step
    case item <> rest: allParts(G, rest, applyPart(G, step, item))

def usageCost(-G: Data, message: T.AssistantMessage<V.Value, G>, draft: T.Usage, cost: T.UsageCost) -> T.AssistantMessage<V.Value, G>:
  match draft:
    case T.Usage{a, b, c, d, e, f, total, _}: withUsage(G, message, T.Usage{a, b, c, d, e, f, total, cost})

def usage(-G: Data, message: T.AssistantMessage<V.Value, G>, +value: V.Value, model: T.Model<T.JsonValue>) -> T.AssistantMessage<V.Value, G>:
  +input = number(at(value, "promptTokenCount"))
  +read = number(at(value, "cachedContentTokenCount"))
  +output = number(at(value, "candidatesTokenCount"))
  +reasoning = number(at(value, "thoughtsTokenCount"))
  +draft = {T.Usage{F.subtract(input, read), F.add(output, reasoning), read, zero(), None{}, Some{reasoning}, number(at(value, "totalTokenCount")), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
  usageCost(G, message, draft, Cost.calculate(T.JsonValue, model, draft))

def maybeUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, value: V.Value, model: T.Model<T.JsonValue>) -> T.AssistantMessage<V.Value, G>:
  match value:
    case V.Null{}: message
    case other: usage(G, message, other, model)

def reason(value: String) -> T.StopReason:
  match value:
    case "STOP": T.Stop{}
    case "MAX_TOKENS": T.Length{}
    case "": T.Pending{}
    case _: T.Error{}

def hasTool(content: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match content:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasTool(rest)

def stop(-G: Data, +message: T.AssistantMessage<V.Value, G>, +wire: String) -> T.AssistantMessage<V.Value, G>:
  +mapped = reason(wire)
  +chosen = Bool.pick(T.StopReason, hasTool(T.assistantContent(V.Value, G, message)) && String.eq(wire, "STOP"), T.ToolUse{}, mapped)
  withStop(G, message, chosen, wire)

def metadata(-G: Data, state: State<G>, +chunk: V.Value, model: T.Model<T.JsonValue>) -> State<G>:
  match state:
    case State{message, active, started, finished, nextTool}:
      +candidate = firstItem(at(chunk, "candidates"))
      +wire = asText(at(candidate, "finishReason"))
      +a = withResponse(G, message, optionalText(at(chunk, "responseId")))
      +b = maybeUsage(G, a, at(chunk, "usageMetadata"), model)
      +c = Bool.pick(T.AssistantMessage<V.Value, G>, String.is_empty(wire), b, stop(G, b, wire))
      State{c, active, started, finished, nextTool}

def withMetadata(-G: Data, step: Step<G>, value: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  match step:
    case Step{state, events, None{}}: Step{metadata(G, state, value, model), events, None{}}
    case other: other

def chunk(-G: Data, state: State<G>, +value: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  +candidate = firstItem(at(value, "candidates"))
  withMetadata(G, allParts(G, parts(at(at(candidate, "content"), "parts")), unchanged(G, state)), value, model)

def errorReason(-G: Data, message: T.AssistantMessage<V.Value, G>) -> String:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, Some{wire}, _, _}: "Provider stopped with: " ++ wire
    case _: "An unknown error occurred"

def finalReason(-G: Data, state: State<G>, message: T.AssistantMessage<V.Value, G>, reason: T.StopReason) -> Step<G>:
  match reason:
    case T.Stop{}: applied(G, state, T.StreamDone{T.DoneStop{}, message} <> Nil{})
    case T.Length{}: applied(G, state, T.StreamDone{T.DoneLength{}, message} <> Nil{})
    case T.ToolUse{}: applied(G, state, T.StreamDone{T.DoneToolUse{}, message} <> Nil{})
    case T.Pending{}: failed(G, state, "Google stream ended without a finish reason")
    case _: failed(G, state, errorReason(G, message))

def finishClosed(-G: Data, step: Step<G>) -> Step<G>:
  match step:
    case Step{State{+message, active, started, _, nextTool}, events, _}:
      prefix(G, events, finalReason(G, State{message, active, started, True{}, nextTool}, message, T.assistantStopReason(V.Value, G, message)))

def finish(-G: Data, state: State<G>) -> Step<G>:
  finishClosed(G, close(G, state))
