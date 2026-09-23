import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/json-parse.bend as Repair
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Pure Chat Completions chunk fold. Tool slots are keyed by the wire index,
# because providers may interleave argument fragments for several calls.
type Block is Data:
  TextBlock{position: Nat, value: String}
  ThinkingBlock{position: Nat, value: String, signature: String}

type ToolSlot is Data:
  ToolSlot{wireIndex: F64, position: Nat, id: String, name: String, arguments: String}

type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, text: Maybe<&2, Block>, thinking: Maybe<&2, Block>, tools: List<&2, ToolSlot>, finished: Bool}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, String>}

def zero() -> F64: F.fromU32(0)
def emptyUsage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}
def create(-G: Data, model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>:
  match model:
    case T.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      State{T.AssistantMessage{Nil{}, "openai-completions", provider, id, None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, None{}, None{}, Nil{}, False{}}

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}
def at(value: V.Value, name: String) -> V.Value: Maybe.default(&2, V.Value, field(value, name), V.Null{})
def string(value: V.Value) -> String:
  match value:
    case V.Text{text}: text
    case _: ""
def optionalString(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{text}: Some{text}
    case _: None{}
def number(value: V.Value) -> F64:
  match value:
    case V.Number{value}: value
    case _: zero()
def isNull(value: V.Value) -> Bool:
  match value:
    case V.Null{}: True{}
    case _: False{}
def items(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}
def firstItem(values: List<&2, V.Value>) -> V.Value:
  match values:
    case head <> _: head
    case Nil{}: V.Null{}
def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)
def index(value: Nat) -> F64: F.fromU32(U32.from_nat(value))
def replace(values: List<&2, T.AssistantContent<V.Value>>, position: Nat, next: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values position:
    case Nil{} _: next <> Nil{}
    case _ <> rest 0n: next <> rest
    case head <> rest 1n+tail: head <> replace(rest, tail, next)
def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, content: List<&2, T.AssistantContent<V.Value>>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}
def withResponse(-G: Data, message: T.AssistantMessage<V.Value, G>, incomingId: Maybe<&2, String>, incomingModel: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, previousModel, previousId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, Maybe.or(&2, String, previousModel, incomingModel), Maybe.or(&2, String, previousId, incomingId), level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}
def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, usage: T.Usage) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}
def withStop(-G: Data, message: T.AssistantMessage<V.Value, G>, stop: T.StopReason, raw: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, Some{raw}, endTurn, timestamp}
def withError(-G: Data, message: T.AssistantMessage<V.Value, G>, text: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, T.Error{}, deferred, Some{text}, raw, endTurn, timestamp}

def applied(-G: Data, state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> Step<G>: Step{state, events, None{}}
def unchanged(-G: Data, state: State<G>) -> Step<G>: applied(G, state, Nil{})
def failed(-G: Data, state: State<G>, +message: String) -> Step<G>:
  match state:
    case State{prior, text, thinking, tools, finished}:
      +error = withError(G, prior, message)
      Step{State{error, text, thinking, tools, finished}, T.StreamError{T.ErrorError{}, error} <> Nil{}, Some{message}}
def prefix(-G: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Step<G>) -> Step<G>:
  match step:
    case Step{state, later, error}: Step{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, later), error}

def textDelta(-G: Data, state: State<G>, +delta: String) -> Step<G>:
  match state:
    case State{+message, Some{TextBlock{+position, previous}}, thinking, tools, finished}:
      +value = previous ++ delta
      +next = withContent(G, message, replace(T.assistantContent(V.Value, G, message), position, T.AssistantText{T.TextContent{value, None{}}}))
      applied(G, State{next, Some{TextBlock{position, value}}, thinking, tools, finished}, T.TextDelta{index(position), delta, next} <> Nil{})
    case State{+message, _, thinking, tools, finished}:
      +position = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +next = withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), T.AssistantText{T.TextContent{delta, None{}}} <> Nil{}))
      applied(G, State{next, Some{TextBlock{position, delta}}, thinking, tools, finished}, T.TextStart{index(position), next} <> T.TextDelta{index(position), delta, next} <> Nil{})

def reasoningField(+delta: V.Value) -> String:
  +a = string(at(delta, "reasoning_content"))
  +b = string(at(delta, "reasoning"))
  Bool.pick(String, String.is_empty(a), Bool.pick(String, String.is_empty(b), string(at(delta, "reasoning_text")), b), a)

def thinkingDelta(-G: Data, state: State<G>, +delta: String) -> Step<G>:
  match state:
    case State{+message, text, Some{ThinkingBlock{+position, previous, +signature}}, tools, finished}:
      +value = previous ++ delta
      +next = withContent(G, message, replace(T.assistantContent(V.Value, G, message), position, T.AssistantThinking{T.ThinkingContent{value, Some{signature}, None{}}}))
      applied(G, State{next, text, Some{ThinkingBlock{position, value, signature}}, tools, finished}, T.ThinkingDelta{index(position), delta, next} <> Nil{})
    case State{+message, text, _, tools, finished}:
      +position = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +signature = {"reasoning_content" : String}
      +next = withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), T.AssistantThinking{T.ThinkingContent{delta, Some{signature}, None{}}} <> Nil{}))
      applied(G, State{next, text, Some{ThinkingBlock{position, delta, signature}}, tools, finished}, T.ThinkingStart{index(position), next} <> T.ThinkingDelta{index(position), delta, next} <> Nil{})

def withText(-G: Data, state: State<G>, delta: String) -> Step<G>:
  match delta:
    case SNil{}: unchanged(G, state)
    case _: textDelta(G, state, delta)
def withThinking(-G: Data, state: State<G>, delta: String) -> Step<G>:
  match delta:
    case SNil{}: unchanged(G, state)
    case _: thinkingDelta(G, state, delta)

def afterText(-G: Data, step: Step<G>, delta: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: prefix(G, events, withThinking(G, state, reasoningField(delta)))
    case other: other

def parsedArgs(value: Result<&2, &2, Json.ParseError, V.Value>) -> V.Value:
  match value:
    case Done{V.ObjectValue{fields}}: V.ObjectValue{fields}
    case _: V.ObjectValue{R.new(V.Value)}

def parseArgs(value: String) -> V.Value: parsedArgs(Repair.parseJsonWithRepair(value))

def toolCall(slot: ToolSlot) -> T.ToolCall<V.Value>:
  match slot:
    case ToolSlot{_, _, id, name, arguments}: T.ToolCall{id, name, parseArgs(arguments), None{}, None{}}
def slotIndex(slot: ToolSlot) -> F64:
  match slot:
    case ToolSlot{wire, _, _, _, _}: wire
def slotAt(slots: List<&2, ToolSlot>, +value: F64) -> Maybe<&2, ToolSlot>:
  match slots:
    case Nil{}: None{}
    case ToolSlot{+wire, position, id, name, arguments} <> rest:
      Bool.pick(Maybe<&2, ToolSlot>, F.isEqual(F.compare(wire, value)), Some{ToolSlot{wire, position, id, name, arguments}}, slotAt(rest, value))
def replaceSlot(slots: List<&2, ToolSlot>, +value: ToolSlot) -> List<&2, ToolSlot>:
  match slots:
    case Nil{}: value <> Nil{}
    case ToolSlot{+wire, position, id, name, arguments} <> +rest:
      Bool.pick(List<&2, ToolSlot>, F.isEqual(F.compare(wire, slotIndex(value))), value <> rest, ToolSlot{wire, position, id, name, arguments} <> replaceSlot(rest, value))

def toolDeltaAt(-G: Data, +message: T.AssistantMessage<V.Value, G>, text: Maybe<&2, Block>, thinking: Maybe<&2, Block>, +tools: List<&2, ToolSlot>, finished: Bool, +wire: F64, id: String, name: String, +args: String, found: Maybe<&2, ToolSlot>) -> Step<G>:
  match found:
    case None{}:
      +position = count(T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message))
      +slot = {ToolSlot{wire, position, id, name, args} : ToolSlot}
      +call = toolCall(slot)
      +next = withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, G, message), T.AssistantToolCall{call} <> Nil{}))
      applied(G, State{next, text, thinking, List.append(&2, ToolSlot, tools, slot <> Nil{}), finished}, T.ToolcallStart{index(position), next} <> T.ToolcallDelta{index(position), args, next} <> Nil{})
    case Some{ToolSlot{_, +position, +oldId, +oldName, oldArgs}}:
      +slot = {ToolSlot{wire, position, Bool.pick(String, String.is_empty(oldId), id, oldId), Bool.pick(String, String.is_empty(oldName), name, oldName), oldArgs ++ args} : ToolSlot}
      +call = toolCall(slot)
      +next = withContent(G, message, replace(T.assistantContent(V.Value, G, message), position, T.AssistantToolCall{call}))
      applied(G, State{next, text, thinking, replaceSlot(tools, slot), finished}, T.ToolcallDelta{index(position), args, next} <> Nil{})

def toolDelta(-G: Data, state: State<G>, +fragment: V.Value) -> Step<G>:
  match state:
    case State{message, text, thinking, +tools, finished}:
      +wire = number(at(fragment, "index"))
      +function = at(fragment, "function")
      toolDeltaAt(G, message, text, thinking, tools, finished, wire, string(at(fragment, "id")), string(at(function, "name")), string(at(function, "arguments")), slotAt(tools, wire))

def toolDeltas(-G: Data, values: List<&2, V.Value>, step: Step<G>) -> Step<G>:
  match values step:
    case Nil{} _: step
    case item <> rest Step{state, events, None{}}: toolDeltas(G, rest, prefix(G, events, toolDelta(G, state, item)))
    case _ other: other

def afterThinking(-G: Data, step: Step<G>, delta: V.Value) -> Step<G>:
  match step:
    case Step{state, events, None{}}: prefix(G, events, toolDeltas(G, items(at(delta, "tool_calls")), unchanged(G, state)))
    case other: other

def delta(-G: Data, state: State<G>, +value: V.Value) -> Step<G>:
  afterThinking(G, afterText(G, withText(G, state, string(at(value, "content"))), value), value)

def mappedStop(reason: String) -> T.StopReason:
  match reason:
    case "stop": T.Stop{}
    case "end": T.Stop{}
    case "length": T.Length{}
    case "tool_calls": T.ToolUse{}
    case "function_call": T.ToolUse{}
    case "": T.Pending{}
    case _: T.Error{}

def stopMessage(-G: Data, message: T.AssistantMessage<V.Value, G>, +reason: String, mapped: T.StopReason) -> T.AssistantMessage<V.Value, G>:
  match mapped:
    case T.Error{}: withError(G, withStop(G, message, T.Error{}, reason), "Provider finish_reason: " ++ reason)
    case other: withStop(G, message, other, reason)

def usage(-G: Data, message: T.AssistantMessage<V.Value, G>, +value: V.Value, model: T.Model<T.JsonValue>) -> T.AssistantMessage<V.Value, G>:
  +prompt = number(at(value, "prompt_tokens"))
  +output = number(at(value, "completion_tokens"))
  +promptDetails = at(value, "prompt_tokens_details")
  +completionDetails = at(value, "completion_tokens_details")
  +cached = number(at(promptDetails, "cached_tokens"))
  +write = number(at(promptDetails, "cache_write_tokens"))
  +read = Bool.pick(F64, F.isEqual(F.compare(cached, zero())), number(at(value, "prompt_cache_hit_tokens")), cached)
  +reasoning = number(at(completionDetails, "reasoning_tokens"))
  +draft = {T.Usage{F.maximum(zero(), F.subtract(F.subtract(prompt, read), write)), output, read, write, None{}, Some{reasoning}, F.add(prompt, output), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
  withUsage(G, message, T.Usage{F.maximum(zero(), F.subtract(F.subtract(prompt, read), write)), output, read, write, None{}, Some{reasoning}, F.add(prompt, output), Cost.calculate(T.JsonValue, model, draft)})

def metadata(-G: Data, state: State<G>, +chunk: V.Value, model: T.Model<T.JsonValue>) -> State<G>:
  match state:
    case State{+message, text, thinking, +tools, finished}:
      +a = withResponse(G, message, optionalString(at(chunk, "id")), optionalString(at(chunk, "model")))
      +rawUsage = at(chunk, "usage")
      +b = Bool.pick(T.AssistantMessage<V.Value, G>, isNull(rawUsage), a, usage(G, a, rawUsage, model))
      State{b, text, thinking, tools, finished}

def finishReason(-G: Data, step: Step<G>, +reason: String) -> Step<G>:
  match step:
    case Step{State{message, text, thinking, tools, _}, events, None{}}:
      +next = stopMessage(G, message, reason, mappedStop(reason))
      Step{State{next, text, thinking, tools, True{}}, events, None{}}
    case other: other

def choice(-G: Data, state: State<G>, +value: V.Value) -> Step<G>:
  +finish = string(at(value, "finish_reason"))
  +processed = delta(G, state, at(value, "delta"))
  Bool.pick(Step<G>, String.is_empty(finish), processed, finishReason(G, processed, finish))

def chunk(-G: Data, state: State<G>, +value: V.Value, model: T.Model<T.JsonValue>) -> Step<G>:
  +updated = metadata(G, state, value, model)
  choice(G, updated, firstItem(items(at(value, "choices"))))

def endBlocks(-G: Data, +message: T.AssistantMessage<V.Value, G>, values: List<&2, T.AssistantContent<V.Value>>, +position: Nat) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match values:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{content, _}} <> rest: T.TextEnd{index(position), content, message} <> endBlocks(G, message, rest, 1n + position)
    case T.AssistantThinking{T.ThinkingContent{content, _, _}} <> rest: T.ThinkingEnd{index(position), content, message} <> endBlocks(G, message, rest, 1n + position)
    case T.AssistantToolCall{call} <> rest: T.ToolcallEnd{index(position), call, message} <> endBlocks(G, message, rest, 1n + position)

def doneReason(reason: T.StopReason) -> Maybe<&2, T.DoneReason>:
  match reason:
    case T.Stop{}: Some{T.DoneStop{}}
    case T.Length{}: Some{T.DoneLength{}}
    case T.ToolUse{}: Some{T.DoneToolUse{}}
    case _: None{}
def finalReason(-G: Data, +message: T.AssistantMessage<V.Value, G>, tools: List<&2, ToolSlot>, finished: Bool, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, reason: Maybe<&2, T.DoneReason>) -> Step<G>:
  match reason:
    case Some{selected}: Step{State{message, None{}, None{}, tools, finished}, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, T.StreamDone{selected, message} <> Nil{}), None{}}
    case None{}: prefix(G, events, failed(G, State{message, None{}, None{}, tools, finished}, Maybe.default(&2, String, T.assistantErrorMessage(V.Value, G, message), "Stream ended without finish_reason")))

def final(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{+message, text, thinking, +tools, finished}:
      +events = endBlocks(G, message, T.assistantContent(V.Value, G, message), 0n)
      finalReason(G, message, tools, finished, events, doneReason(T.assistantStopReason(V.Value, G, message)))

def finish(-G: Data, state: State<G>) -> Step<G>: final(G, state)
