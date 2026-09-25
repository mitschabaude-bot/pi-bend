import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/json.bend as Wire
import ../utils/json-parse.bend as Partial
import ../utils/schema-json.bend as Schema
import ./constrained-sampling.bend as Sampling
import ./openai-completions.bend as Request
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# The Chat Completions chunk fold of upstream `stream` (openai-completions.ts):
# one text block, one thinking block and tool-call blocks found by their wire
# index or id, streamed reasoning_details kept as replay metadata, then the
# block endings and the finish_reason checks. Each step returns the events it
# publishes; a thrown error ends the fold with the message upstream reports.

# Settings the fold reads from the model, its resolved compat and the request.
type Settings is Data:
  Settings{model: T.Model<T.JsonValue>, supportsFinishReason: Bool, grammarToolInputProperties: R.Record<String>}

def settingsModel(settings: Settings) -> T.Model<T.JsonValue>:
  match settings:
    case Settings{model, _, _}: model

# A reasoning detail as an ordered object whose members can hold `undefined`
# (None): upstream merges details with `??=` and `||=`, which can create a
# member holding undefined that JSON.stringify then omits.
def Detail() -> Data: R.Record<Maybe<&2, V.Value>>

# The custom (grammar) input of a tool call: the argument property and the
# JSON buffer its streamed input is re-encoded through.
type CustomInput is Data:
  CustomInput{property: String, buffer: Sampling.GrammarToolInputJsonBuffer}

# A tool-call block: the call written to the content plus upstream's scratch
# members (streamIndex, partialArgs, customInput), dropped when it ends.
type ToolBlock is Data:
  ToolBlock{position: Nat, streamIndex: Maybe<&2, F64>, id: String, name: String, arguments: V.Value, partialArgs: Maybe<&2, String>, customInput: Maybe<&2, CustomInput>}

type Mapped<-K: Data> is Data:
  Mapped{key: K, position: Nat}

type State<-G: Data> is Data:
  State{message: T.AssistantMessage<V.Value, G>, text: Maybe<&2, Nat>, thinking: Maybe<&2, Nat>, tools: List<&2, ToolBlock>, byIndex: List<&2, Mapped<F64>>, byId: List<&2, Mapped<String>>, details: Maybe<&2, List<&2, Detail()>>, hasFinishReason: Bool}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, String>}

def zero() -> F64: F.fromU32(0)
def emptyUsage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def create(-G: Data, model: T.Model<T.JsonValue>, timestamp: F64) -> State<G>:
  match model:
    case T.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      State{T.AssistantMessage{Nil{}, "openai-completions", provider, id, None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}, None{}, None{}, Nil{}, Nil{}, Nil{}, None{}, False{}}

def stateMessage(-G: Data, state: State<G>) -> T.AssistantMessage<V.Value, G>:
  match state:
    case State{message, _, _, _, _, _, _, _}: message

# JSON access
# -----------

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def jsonText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{content}}: Some{content}
    case _: None{}

def nonemptyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

def items(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, V.Value>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{values}
    case _: None{}

def isObject(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{_}: True{}
    case _: False{}

# JavaScript truthiness of a JSON member.
def truthy(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: False{}
    case Some{V.Null{}}: False{}
    case Some{V.Boolean{flag}}: flag
    case Some{V.Text{SNil{}}}: False{}
    case Some{V.Number{+number}}: Bool.not(F.isNaN(number)) && Bool.not(F.isEqual(F.compare(number, zero())))
    case Some{_}: True{}

def count(-A: Data, values: List<&2, A>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(A, rest)

def index(value: Nat) -> F64: F.fromU32(U32.from_nat(value))

# Message updates
# ---------------

def contentOf(-G: Data, message: T.AssistantMessage<V.Value, G>) -> List<&2, T.AssistantContent<V.Value>>: T.assistantContent(V.Value, G, message)

def blockAt(values: List<&2, T.AssistantContent<V.Value>>, position: Nat) -> Maybe<&2, T.AssistantContent<V.Value>>:
  match values position:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+tail: blockAt(rest, tail)

def replace(values: List<&2, T.AssistantContent<V.Value>>, position: Nat, next: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values position:
    case Nil{} _: next <> Nil{}
    case _ <> rest 0n: next <> rest
    case head <> rest 1n+tail: head <> replace(rest, tail, next)

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, content: List<&2, T.AssistantContent<V.Value>>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def replaced(-G: Data, +message: T.AssistantMessage<V.Value, G>, position: Nat, block: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  withContent(G, message, replace(contentOf(G, message), position, block))

def appended(-G: Data, +message: T.AssistantMessage<V.Value, G>, block: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  withContent(G, message, List.append(&2, T.AssistantContent<V.Value>, contentOf(G, message), block <> Nil{}))

def falsyText(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: False{}
    case _: True{}

# `responseId ||= chunk.id`; `responseModel ||= chunk.model` for a routed model
# other than the requested one.
def responseIdOf(+current: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, falsyText(current), incoming, current)

def routed(+name: String, requested: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.eq(name, requested), None{}, Some{name})

def routedModel(+requested: String, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case Some{SCon{c, cs}}: routed(SCon{c, cs}, requested)
    case _: None{}

def withResponse(-G: Data, message: T.AssistantMessage<V.Value, G>, incomingId: Maybe<&2, String>, incomingModel: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, +model, +responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, Bool.pick(Maybe<&2, String>, falsyText(responseModel), Maybe.or(&2, String, routedModel(model, incomingModel), responseModel), responseModel), responseIdOf(responseId, incomingId), level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, usage: T.Usage) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withStop(-G: Data, message: T.AssistantMessage<V.Value, G>, stop: T.StopReason) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def withRawStop(-G: Data, message: T.AssistantMessage<V.Value, G>, stop: T.StopReason, raw: String, error: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, previous, _, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Maybe.or(&2, String, error, previous), Some{raw}, endTurn, timestamp}

def withFailure(-G: Data, message: T.AssistantMessage<V.Value, G>, stop: T.StopReason, text: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Some{text}, raw, endTurn, timestamp}

# Usage and stop reasons
# ----------------------

def numberOr(value: Maybe<&2, V.Value>) -> F64: Maybe.default(&2, F64, numberOf(value), zero())

# `x || 0` over a JSON member.
def truthyNumber(+value: Maybe<&2, V.Value>) -> F64:
  Bool.pick(F64, truthy(value), numberOr(value), zero())

def nestedField(value: Maybe<&2, V.Value>, name: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{inner}: field(inner, name)
    case None{}: None{}

def nullish(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{V.Null{}}: True{}
    case _: False{}

# `a ?? b` over JSON members.
def coalesce(+first: Maybe<&2, V.Value>, second: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  Bool.pick(Maybe<&2, V.Value>, nullish(first), second, first)

# upstream parseChunkUsage: cache reads from prompt_tokens_details.cached_tokens,
# DeepSeek's prompt_cache_hit_tokens or Kimi's top-level cached_tokens; writes
# are separate, and completion_tokens already includes reasoning.
def parseChunkUsage(+raw: V.Value, model: T.Model<T.JsonValue>) -> T.Usage:
  +details = field(raw, "prompt_tokens_details")
  +prompt = truthyNumber(field(raw, "prompt_tokens"))
  +read = numberOr(coalesce(nestedField(details, "cached_tokens"), coalesce(field(raw, "prompt_cache_hit_tokens"), field(raw, "cached_tokens"))))
  +write = truthyNumber(nestedField(details, "cache_write_tokens"))
  +input = F.maximum(zero(), F.subtract(F.subtract(prompt, read), write))
  +output = truthyNumber(field(raw, "completion_tokens"))
  +reasoning = truthyNumber(nestedField(field(raw, "completion_tokens_details"), "reasoning_tokens"))
  +draft = {T.Usage{input, output, read, write, None{}, Some{reasoning}, F.add(F.add(F.add(input, output), read), write), T.UsageCost{zero(), zero(), zero(), zero(), zero()}} : T.Usage}
  T.Usage{input, output, read, write, None{}, Some{reasoning}, F.add(F.add(F.add(input, output), read), write), Cost.calculate(T.JsonValue, model, draft)}

type MappedStop is Data:
  MappedStop{stopReason: T.StopReason, errorMessage: Maybe<&2, String>}

def mapStopReason(+reason: String) -> MappedStop:
  match reason:
    case "stop": MappedStop{T.Stop{}, None{}}
    case "end": MappedStop{T.Stop{}, None{}}
    case "length": MappedStop{T.Length{}, None{}}
    case "function_call": MappedStop{T.ToolUse{}, None{}}
    case "tool_calls": MappedStop{T.ToolUse{}, None{}}
    case _: MappedStop{T.Error{}, Some{"Provider finish_reason: " ++ reason}}

# Steps
# -----

def applied(-G: Data, state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> Step<G>: Step{state, events, None{}}
def unchanged(-G: Data, state: State<G>) -> Step<G>: applied(G, state, Nil{})

def prefix(-G: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Step<G>) -> Step<G>:
  match step:
    case Step{state, later, error}: Step{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, events, later), error}

def thrown(-G: Data, state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, message: String) -> Step<G>:
  Step{state, events, Some{message}}

# Continue with `next` only while no error was thrown.
def andThen(-G: Data, step: Step<G>, next: State<G> -> Step<G>) -> Step<G>:
  match step:
    case Step{state, events, None{}}: prefix(G, events, next(state))
    case other: other

# Text and thinking
# -----------------

def textValue(block: Maybe<&2, T.AssistantContent<V.Value>>) -> String:
  match block:
    case Some{T.AssistantText{T.TextContent{value, _}}}: value
    case _: ""

def textDelta(-G: Data, state: State<G>, +delta: String) -> Step<G>:
  match state:
    case State{+message, Some{+position}, thinking, tools, byIndex, byId, details, finished}:
      +next = replaced(G, message, position, T.AssistantText{T.TextContent{textValue(blockAt(contentOf(G, message), position)) ++ delta, None{}}})
      applied(G, State{next, Some{position}, thinking, tools, byIndex, byId, details, finished}, T.TextDelta{index(position), delta, next} <> Nil{})
    case State{+message, None{}, thinking, tools, byIndex, byId, details, finished}:
      +position = count(T.AssistantContent<V.Value>, contentOf(G, message))
      +started = appended(G, message, T.AssistantText{T.TextContent{"", None{}}})
      +next = replaced(G, started, position, T.AssistantText{T.TextContent{delta, None{}}})
      applied(G, State{next, Some{position}, thinking, tools, byIndex, byId, details, finished}, T.TextStart{index(position), started} <> T.TextDelta{index(position), delta, next} <> Nil{})

def withText(-G: Data, state: State<G>, delta: Maybe<&2, String>) -> Step<G>:
  match delta:
    case Some{SCon{c, cs}}: textDelta(G, state, SCon{c, cs})
    case _: unchanged(G, state)

# The single thinking block, created with the signature of whatever started
# it: the reasoning field's name, or "" for reasoning_details.
def ensureThinking(-G: Data, state: State<G>, +signature: String) -> Step<G>:
  match state:
    case State{+message, text, None{}, tools, byIndex, byId, details, finished}:
      +position = count(T.AssistantContent<V.Value>, contentOf(G, message))
      +next = appended(G, message, T.AssistantThinking{T.ThinkingContent{"", Some{signature}, None{}}})
      applied(G, State{next, text, Some{position}, tools, byIndex, byId, details, finished}, T.ThinkingStart{index(position), next} <> Nil{})
    case other: unchanged(G, other)

def thinkingParts(block: Maybe<&2, T.AssistantContent<V.Value>>) -> T.ThinkingContent:
  match block:
    case Some{T.AssistantThinking{content}}: content
    case _: T.ThinkingContent{"", None{}, None{}}

def appendThinking(content: T.ThinkingContent, delta: String) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{value, signature, redacted}: T.ThinkingContent{value ++ delta, signature, redacted}

def thinkingDelta(-G: Data, state: State<G>, +delta: String) -> Step<G>:
  match state:
    case State{+message, text, Some{+position}, tools, byIndex, byId, details, finished}:
      +next = replaced(G, message, position, T.AssistantThinking{appendThinking(thinkingParts(blockAt(contentOf(G, message), position)), delta)})
      applied(G, State{next, text, Some{position}, tools, byIndex, byId, details, finished}, T.ThinkingDelta{index(position), delta, next} <> Nil{})
    case other: unchanged(G, other)

type ReasoningDelta is Data:
  ReasoningDelta{field: String, delta: String}

# The first non-empty of reasoning_content, reasoning and reasoning_text (some
# endpoints repeat the same text in several of them).
def firstReasoning(content: Maybe<&2, String>, reasoning: Maybe<&2, String>, reasoningText: Maybe<&2, String>) -> Maybe<&2, ReasoningDelta>:
  match content reasoning reasoningText:
    case Some{value} _ _: Some{ReasoningDelta{"reasoning_content", value}}
    case None{} Some{value} _: Some{ReasoningDelta{"reasoning", value}}
    case None{} None{} Some{value}: Some{ReasoningDelta{"reasoning_text", value}}
    case _ _ _: None{}

def reasoningDelta(+delta: V.Value) -> Maybe<&2, ReasoningDelta>:
  firstReasoning(nonemptyText(field(delta, "reasoning_content")), nonemptyText(field(delta, "reasoning")), nonemptyText(field(delta, "reasoning_text")))

# OpenCode Go streams `reasoning` but replays reasoning_content.
def thinkingSignature(+provider: String, +name: String) -> String:
  Bool.pick(String, String.eq(provider, "opencode-go") && String.eq(name, "reasoning"), "reasoning_content", name)

def withReasoning(-G: Data, state: State<G>, +provider: String, value: Maybe<&2, ReasoningDelta>) -> Step<G>:
  match value:
    case None{}: unchanged(G, state)
    case Some{ReasoningDelta{name, +delta}}: andThen(G, ensureThinking(G, state, thinkingSignature(provider, name)), next => thinkingDelta(G, next, delta))

# Tool calls
# ----------

def lookupIndex(entries: List<&2, Mapped<F64>>, +wire: F64) -> Maybe<&2, Nat>:
  match entries:
    case Nil{}: None{}
    case Mapped{+key, position} <> rest: Bool.pick(Unit -> Maybe<&2, Nat>, F.isEqual(F.compare(key, wire)), _ => Some{position}, _ => lookupIndex(rest, wire))(Unit{})

def lookupId(entries: List<&2, Mapped<String>>, +id: String) -> Maybe<&2, Nat>:
  match entries:
    case Nil{}: None{}
    case Mapped{+key, position} <> rest: Bool.pick(Unit -> Maybe<&2, Nat>, String.eq(key, id), _ => Some{position}, _ => lookupId(rest, id))(Unit{})

# Map.set: an existing key moves to the new block in place, a new key appends.
def setIndex(entries: List<&2, Mapped<F64>>, +wire: F64, +position: Nat) -> List<&2, Mapped<F64>>:
  match entries:
    case Nil{}: Mapped{wire, position} <> Nil{}
    case Mapped{+key, old} <> +rest: Bool.pick(Unit -> List<&2, Mapped<F64>>, F.isEqual(F.compare(key, wire)), _ => Mapped{key, position} <> rest, _ => Mapped{key, old} <> setIndex(rest, wire, position))(Unit{})

def setId(entries: List<&2, Mapped<String>>, +id: String, +position: Nat) -> List<&2, Mapped<String>>:
  match entries:
    case Nil{}: Mapped{id, position} <> Nil{}
    case Mapped{+key, old} <> +rest: Bool.pick(Unit -> List<&2, Mapped<String>>, String.eq(key, id), _ => Mapped{key, position} <> rest, _ => Mapped{key, old} <> setId(rest, id, position))(Unit{})

def withIndex(entries: List<&2, Mapped<F64>>, wire: Maybe<&2, F64>, +position: Nat) -> List<&2, Mapped<F64>>:
  match wire:
    case Some{value}: setIndex(entries, value, position)
    case None{}: entries

def withId(entries: List<&2, Mapped<String>>, id: Maybe<&2, String>, +position: Nat) -> List<&2, Mapped<String>>:
  match id:
    case Some{SCon{c, cs}}: setId(entries, SCon{c, cs}, position)
    case _: entries

def indexLookup(entries: List<&2, Mapped<F64>>, wire: Maybe<&2, F64>) -> Maybe<&2, Nat>:
  match wire:
    case Some{value}: lookupIndex(entries, value)
    case None{}: None{}

def idLookup(entries: List<&2, Mapped<String>>, id: Maybe<&2, String>) -> Maybe<&2, Nat>:
  match id:
    case Some{SCon{c, cs}}: lookupId(entries, SCon{c, cs})
    case _: None{}

def toolBlockAt(blocks: List<&2, ToolBlock>, +position: Nat) -> Maybe<&2, ToolBlock>:
  match blocks:
    case Nil{}: None{}
    case ToolBlock{+at, a, b, c, d, e, f} <> rest: Bool.pick(Unit -> Maybe<&2, ToolBlock>, Nat.is_eq(at, position), _ => Some{ToolBlock{at, a, b, c, d, e, f}}, _ => toolBlockAt(rest, position))(Unit{})

def blockPosition(block: ToolBlock) -> Nat:
  match block:
    case ToolBlock{position, _, _, _, _, _, _}: position

def replaceToolBlock(blocks: List<&2, ToolBlock>, +next: ToolBlock) -> List<&2, ToolBlock>:
  match blocks:
    case Nil{}: next <> Nil{}
    case ToolBlock{+at, a, b, c, d, e, f} <> +rest: Bool.pick(Unit -> List<&2, ToolBlock>, Nat.is_eq(at, blockPosition(next)), _ => next <> rest, _ => ToolBlock{at, a, b, c, d, e, f} <> replaceToolBlock(rest, next))(Unit{})

def blockCall(block: ToolBlock) -> T.ToolCall<V.Value>:
  match block:
    case ToolBlock{_, _, id, name, arguments, _, _}: T.ToolCall{id, name, arguments, None{}, None{}}

def inputArguments(property: String, input: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{property, V.Text{input}} <> Nil{}}}

def emptyBuffer() -> Sampling.GrammarToolInputJsonBuffer: Sampling.GrammarToolInputJsonBuffer{"", False{}, False{}}

def customProperty(+grammar: R.Record<String>, name: String) -> String:
  Maybe.default(&2, String, R.get(String, grammar, name), "input")

# One `tool_calls` entry. The name is `function.name ?? custom.name ?? ""`.
type Fragment is Data:
  Fragment{streamIndex: Maybe<&2, F64>, id: Maybe<&2, String>, hasFunction: Bool, hasCustom: Bool, name: String, arguments: Maybe<&2, String>, input: Maybe<&2, String>}

def chosenName(functionName: Maybe<&2, String>, customName: Maybe<&2, String>) -> String:
  match functionName customName:
    case Some{name} _: name
    case None{} Some{name}: name
    case None{} None{}: ""

def nameOf(function: Maybe<&2, V.Value>, custom: Maybe<&2, V.Value>) -> String: chosenName(jsonText(nestedField(function, "name")), jsonText(nestedField(custom, "name")))

def fragment(+value: V.Value) -> Fragment:
  +function = field(value, "function")
  +custom = field(value, "custom")
  Fragment{numberOf(field(value, "index")), jsonText(field(value, "id")), truthy(function), truthy(custom), nameOf(function, custom), nonemptyText(nestedField(function, "arguments")), nonemptyText(nestedField(custom, "input"))}

def fragmentIndex(part: Fragment) -> Maybe<&2, F64>:
  match part:
    case Fragment{wire, _, _, _, _, _, _}: wire

def fragmentId(part: Fragment) -> Maybe<&2, String>:
  match part:
    case Fragment{_, id, _, _, _, _, _}: id

def written(-G: Data, state: State<G>, +block: ToolBlock) -> State<G>:
  match state:
    case State{+message, text, thinking, tools, byIndex, byId, details, finished}:
      State{replaced(G, message, blockPosition(block), T.AssistantToolCall{blockCall(block)}), text, thinking, replaceToolBlock(tools, block), byIndex, byId, details, finished}

type Ensured<-G: Data> is Data:
  Ensured{step: Step<G>, position: Nat}

def created(-G: Data, state: State<G>, +grammar: R.Record<String>, +part: Fragment) -> Ensured<G>:
  match state part:
    case State{+message, text, thinking, tools, byIndex, byId, details, finished} Fragment{+wire, +id, hasFunction, hasCustom, +name, _, _}:
      +position = count(T.AssistantContent<V.Value>, contentOf(G, message))
      +isCustom = hasCustom && Bool.not(hasFunction)
      +property = customProperty(grammar, name)
      +block = {ToolBlock{position, wire, Maybe.default(&2, String, id, ""), name, Bool.pick(V.Value, isCustom, inputArguments(property, ""), V.ObjectValue{R.new(V.Value)}), Bool.pick(Maybe<&2, String>, isCustom, None{}, Some{""}), Bool.pick(Maybe<&2, CustomInput>, isCustom, Some{CustomInput{property, emptyBuffer()}}, None{})} : ToolBlock}
      +next = appended(G, message, T.AssistantToolCall{blockCall(block)})
      Ensured{applied(G, State{next, text, thinking, List.append(&2, ToolBlock, tools, block <> Nil{}), withIndex(byIndex, wire, position), withId(byId, id, position), details, finished}, T.ToolcallStart{index(position), next} <> Nil{}), position}

def switchCustom(block: ToolBlock, +grammar: R.Record<String>, switch: Bool) -> ToolBlock:
  match block switch:
    case ToolBlock{position, wire, id, +name, _, _, None{}} True{}:
      +property = customProperty(grammar, name)
      ToolBlock{position, wire, id, name, inputArguments(property, ""), None{}, Some{CustomInput{property, emptyBuffer()}}}
    case other _: other

# A found block gains the stream index it lacked, the delta's id mapping, a
# missing name, and switches to custom input on a custom-only delta.
def updatedBlock(block: ToolBlock, +grammar: R.Record<String>, +part: Fragment) -> ToolBlock:
  match block part:
    case ToolBlock{position, streamIndex, id, +name, arguments, partial, custom} Fragment{wire, _, hasFunction, hasCustom, +incoming, _, _}:
      +named = Bool.pick(String, String.is_empty(name) && Bool.not(String.is_empty(incoming)), incoming, name)
      +indexed = Maybe.or(&2, F64, streamIndex, wire)
      switchCustom(ToolBlock{position, indexed, id, named, arguments, partial, custom}, grammar, hasCustom && Bool.not(hasFunction))

def lacksIndex(block: Maybe<&2, ToolBlock>) -> Bool:
  match block:
    case Some{ToolBlock{_, None{}, _, _, _, _, _}}: True{}
    case _: False{}

def refreshed(-G: Data, state: State<G>, +grammar: R.Record<String>, +part: Fragment, +position: Nat) -> Ensured<G>:
  match state:
    case State{message, text, thinking, +tools, +byIndex, byId, details, finished}:
      +previous = toolBlockAt(tools, position)
      +indexed = Bool.pick(List<&2, Mapped<F64>>, Maybe.is_some(&2, F64, fragmentIndex(part)) && lacksIndex(previous), withIndex(byIndex, fragmentIndex(part), position), byIndex)
      +mapped = {State{message, text, thinking, tools, indexed, withId(byId, fragmentId(part), position), details, finished} : State<G>}
      Ensured{unchanged(G, written(G, mapped, updatedBlock(Maybe.default(&2, ToolBlock, previous, ToolBlock{position, None{}, "", "", V.ObjectValue{R.new(V.Value)}, Some{""}, None{}}), grammar, part))), position}

def existingBlock(byIndex: List<&2, Mapped<F64>>, byId: List<&2, Mapped<String>>, +part: Fragment) -> Maybe<&2, Nat>:
  Maybe.or(&2, Nat, indexLookup(byIndex, fragmentIndex(part)), idLookup(byId, fragmentId(part)))

def ensuredAt(-G: Data, state: State<G>, +grammar: R.Record<String>, +part: Fragment, existing: Maybe<&2, Nat>) -> Ensured<G>:
  match existing:
    case None{}: created(G, state, grammar, part)
    case Some{position}: refreshed(G, state, grammar, part, position)

def ensureToolCallBlock(-G: Data, state: State<G>, +grammar: R.Record<String>, +part: Fragment) -> Ensured<G>:
  match state:
    case State{message, text, thinking, tools, +byIndex, +byId, details, finished}: ensuredAt(G, State{message, text, thinking, tools, byIndex, byId, details, finished}, grammar, part, existingBlock(byIndex, byId, part))

def customInputOf(block: ToolBlock) -> String:
  match block:
    case ToolBlock{_, _, _, _, arguments, _, Some{CustomInput{property, _}}}: Maybe.default(&2, String, jsonText(field(arguments, property)), "")
    case _: ""

type Appended is Data:
  Appended{block: ToolBlock, delta: Maybe<&2, String>}

def appendedInput(block: ToolBlock, +next: String, result: Result<&2, &2, Sampling.Error, Sampling.GrammarToolInputJsonUpdate>) -> Result<&2, &2, Sampling.Error, Appended>:
  match block result:
    case _ Fail{error}: Fail{error}
    case ToolBlock{position, wire, id, name, _, partial, Some{CustomInput{+property, _}}} Done{Sampling.GrammarToolInputJsonUpdate{buffer, delta}}:
      Done{Appended{ToolBlock{position, wire, id, name, inputArguments(property, next), partial, Some{CustomInput{property, buffer}}}, delta}}
    case other _: Done{Appended{other, None{}}}

# appendCustomToolCallInput: a block without custom input yields no delta.
def appendCustomInput(block: ToolBlock, +next: String, close: Bool) -> Result<&2, &2, Sampling.Error, Appended>:
  match block:
    case ToolBlock{a, b, c, d, e, f, Some{CustomInput{+property, +buffer}}}: appendedInput(ToolBlock{a, b, c, d, e, f, Some{CustomInput{property, buffer}}}, next, Sampling.appendGrammarToolInputJsonDelta(buffer, property, next, close))
    case other: Done{Appended{other, None{}}}

def withFunctionArguments(block: ToolBlock, +arguments: String) -> ToolBlock:
  match block:
    case ToolBlock{position, wire, id, name, _, partial, custom}:
      +joined = Maybe.default(&2, String, partial, "") ++ arguments
      ToolBlock{position, wire, id, name, Partial.parseStreamingJson(Some{joined}), Some{joined}, custom}

def withDeltaId(block: ToolBlock, id: Maybe<&2, String>) -> ToolBlock:
  match block id:
    case ToolBlock{position, wire, SNil{}, name, arguments, partial, custom} Some{SCon{c, cs}}: ToolBlock{position, wire, SCon{c, cs}, name, arguments, partial, custom}
    case other _: other

def deltaEvent(-G: Data, state: State<G>, +position: Nat, delta: String) -> Step<G>:
  match state:
    case State{+message, a, b, c, d, e, f, g}: applied(G, State{message, a, b, c, d, e, f, g}, T.ToolcallDelta{index(position), delta, message} <> Nil{})

def customDelta(-G: Data, state: State<G>, +position: Nat, result: Result<&2, &2, Sampling.Error, Appended>) -> Step<G>:
  match result:
    case Fail{error}: thrown(G, state, Nil{}, Sampling.errorMessage(error))
    case Done{Appended{block, delta}}: deltaEvent(G, written(G, state, block), position, Maybe.default(&2, String, delta, ""))

def toolArguments(-G: Data, state: State<G>, +block: ToolBlock, +position: Nat, arguments: Maybe<&2, String>, input: Maybe<&2, String>) -> Step<G>:
  match arguments input:
    case Some{+delta} _: deltaEvent(G, written(G, state, withFunctionArguments(block, delta)), position, delta)
    case None{} Some{delta}: customDelta(G, written(G, state, block), position, appendCustomInput(block, customInputOf(block) ++ delta, False{}))
    case None{} None{}: deltaEvent(G, written(G, state, block), position, "")

# The loop body after ensureToolCallBlock: id and name, then either function
# arguments (re-parsed as partial JSON) or custom input, then one delta event.
def fragmentDelta(-G: Data, state: State<G>, +part: Fragment, +position: Nat) -> Step<G>:
  match state part:
    case State{message, text, thinking, +tools, byIndex, +byId, details, finished} Fragment{_, +id, _, _, _, arguments, input}:
      +block = withDeltaId(Maybe.default(&2, ToolBlock, toolBlockAt(tools, position), ToolBlock{position, None{}, "", "", V.ObjectValue{R.new(V.Value)}, Some{""}, None{}}), id)
      +current = {State{message, text, thinking, tools, byIndex, withId(byId, id, position), details, finished} : State<G>}
      toolArguments(G, current, block, position, arguments, input)

def ensuredDelta(-G: Data, ensured: Ensured<G>, +part: Fragment) -> Step<G>:
  match ensured:
    case Ensured{step, +position}: andThen(G, step, next => fragmentDelta(G, next, part, position))

def toolDelta(-G: Data, state: State<G>, +grammar: R.Record<String>, +value: V.Value) -> Step<G>:
  +part = fragment(value)
  ensuredDelta(G, ensureToolCallBlock(G, state, grammar, part), part)

def toolDeltas(-G: Data, values: List<&2, V.Value>, +grammar: R.Record<String>, step: Step<G>) -> Step<G>:
  match values:
    case Nil{}: step
    case item <> rest: toolDeltas(G, rest, grammar, andThen(G, step, state => toolDelta(G, state, grammar, item)))

# Reasoning details
# -----------------

def flattened(value: Maybe<&2, Maybe<&2, V.Value>>) -> Maybe<&2, V.Value>:
  match value:
    case Some{inner}: inner
    case None{}: None{}

def memberValue(detail: Detail(), key: String) -> Maybe<&2, V.Value>: flattened(R.get(Maybe<&2, V.Value>, detail, key))

def maybeMembers(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<Maybe<&2, V.Value>>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, Some{value}} <> maybeMembers(rest)

def detailOf(value: V.Value) -> Detail():
  match value:
    case V.ObjectValue{R.Record{fields}}: R.Record{maybeMembers(fields)}
    case _: R.new(Maybe<&2, V.Value>)

def assign(detail: Detail(), key: String, value: Maybe<&2, V.Value>) -> Detail(): R.set(Maybe<&2, V.Value>, detail, key, value)

def falsyMember(value: Maybe<&2, V.Value>) -> Bool: Bool.not(truthy(value))

# `target[key] ||= value` and `target[key] ??= value`; either may create the
# member holding undefined.
def orAssign(+detail: Detail(), +key: String, value: Maybe<&2, V.Value>) -> Detail():
  Bool.pick(Detail(), falsyMember(memberValue(detail, key)), assign(detail, key, value), detail)

def nullishAssign(+detail: Detail(), +key: String, value: Maybe<&2, V.Value>) -> Detail():
  Bool.pick(Detail(), nullish(memberValue(detail, key)), assign(detail, key, value), detail)

def concatenated(+detail: Detail(), +key: String, extra: Detail()) -> Detail():
  assign(detail, key, Some{V.Text{Maybe.default(&2, String, jsonText(memberValue(detail, key)), "") ++ Maybe.default(&2, String, jsonText(memberValue(extra, key)), "")}})

# fillMissingCommonReasoningDetailFields
def filled(target: Detail(), +source: Detail()) -> Detail():
  nullishAssign(orAssign(nullishAssign(target, "id", memberValue(source, "id")), "format", memberValue(source, "format")), "index", memberValue(source, "index"))

def detailType(detail: Detail()) -> String: Maybe.default(&2, String, jsonText(memberValue(detail, "type")), "")

def mergedTypes(lastType: String, detailKind: String, +last: Detail(), +detail: Detail()) -> Maybe<&2, Detail()>:
  match lastType detailKind:
    case "reasoning.text" "reasoning.text": Some{filled(orAssign(concatenated(last, "text", detail), "signature", memberValue(detail, "signature")), detail)}
    case "reasoning.summary" "reasoning.summary": Some{filled(concatenated(last, "summary", detail), detail)}
    case _ _: None{}

def mergedDetail(+last: Detail(), +detail: Detail()) -> Maybe<&2, Detail()>: mergedTypes(detailType(last), detailType(detail), last, detail)

def lastDetail(details: List<&2, Detail()>) -> Maybe<&2, Detail()>:
  match details:
    case Nil{}: None{}
    case head <> Nil{}: Some{head}
    case _ <> rest: lastDetail(rest)

def withoutLast(details: List<&2, Detail()>) -> List<&2, Detail()>:
  match details:
    case Nil{}: Nil{}
    case _ <> Nil{}: Nil{}
    case head <> rest: head <> withoutLast(rest)

def mergedOrPushed(+details: List<&2, Detail()>, +detail: Detail(), merged: Maybe<&2, Detail()>) -> List<&2, Detail()>:
  match merged:
    case Some{value}: List.append(&2, Detail(), withoutLast(details), value <> Nil{})
    case None{}: List.append(&2, Detail(), details, detail <> Nil{})

def lastMerged(last: Maybe<&2, Detail()>, +detail: Detail()) -> Maybe<&2, Detail()>:
  match last:
    case Some{previous}: mergedDetail(previous, detail)
    case None{}: None{}

# appendOpenAIReasoningDetail: consecutive text or summary deltas join one
# logical entry; encrypted entries stay discrete.
def appendOpenAIReasoningDetail(+details: List<&2, Detail()>, +detail: Detail()) -> List<&2, Detail()>:
  mergedOrPushed(details, detail, lastMerged(lastDetail(details), detail))

def presentMembers(fields: List<&2, R.Property<Maybe<&2, V.Value>>>) -> List<&2, R.Property<T.JsonValue>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{_, None{}} <> rest: presentMembers(rest)
    case R.Property{key, Some{value}} <> rest: R.Property{key, Schema.toJson(value)} <> presentMembers(rest)

def detailJson(detail: Detail()) -> T.JsonValue:
  match detail:
    case R.Record{fields}: T.JsonObject{R.Record{presentMembers(fields)}}

def detailsJson(details: List<&2, Detail()>) -> List<&2, T.JsonValue>:
  match details:
    case Nil{}: Nil{}
    case head <> rest: detailJson(head) <> detailsJson(rest)

def detailsSignature(details: List<&2, Detail()>) -> String:
  Maybe.default(&2, String, Wire.stringify(T.JsonArray{detailsJson(details)}), "[]")

def signed(content: T.ThinkingContent, signature: String) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{thinking, _, redacted}: T.ThinkingContent{thinking, Some{signature}, redacted}

# applyStreamedReasoningDetails for the thinking block, if details streamed.
def withDetails(-G: Data, state: State<G>) -> State<G>:
  match state:
    case State{+message, text, Some{+position}, tools, byIndex, byId, Some{+details}, finished}:
      State{replaced(G, message, position, T.AssistantThinking{signed(thinkingParts(blockAt(contentOf(G, message), position)), detailsSignature(details))}), text, Some{position}, tools, byIndex, byId, Some{details}, finished}
    case other: other

def recorded(-G: Data, state: State<G>, detail: Detail()) -> State<G>:
  match state:
    case State{message, text, thinking, tools, byIndex, byId, details, finished}:
      State{message, text, thinking, tools, byIndex, byId, Some{appendOpenAIReasoningDetail(Maybe.default(&2, List<&2, Detail()>, details, Nil{}), detail)}, finished}

def detailStep(-G: Data, +state: State<G>, +value: V.Value) -> Step<G>:
  Bool.pick(Unit -> Step<G>, Request.isOpenAIReasoningDetail(value), _ => andThen(G, ensureThinking(G, state, ""), next => unchanged(G, recorded(G, next, detailOf(value)))), _ => unchanged(G, state))(Unit{})

def detailSteps(-G: Data, values: List<&2, V.Value>, step: Step<G>) -> Step<G>:
  match values:
    case Nil{}: step
    case item <> rest: detailSteps(G, rest, andThen(G, step, state => detailStep(G, state, item)))

# Chunks
# ------

def settingsProvider(settings: Settings) -> String: T.modelProvider(settingsModel(settings))

def settingsGrammar(settings: Settings) -> R.Record<String>:
  match settings:
    case Settings{_, _, grammar}: grammar

# One delta, in upstream order: content, reasoning, tool calls, then
# reasoning_details.
def deltaStep(-G: Data, state: State<G>, +settings: Settings, +delta: V.Value) -> Step<G>:
  +texted = withText(G, state, jsonText(field(delta, "content")))
  +reasoned = andThen(G, texted, next => withReasoning(G, next, settingsProvider(settings), reasoningDelta(delta)))
  +tooled = andThen(G, reasoned, next => toolDeltas(G, Maybe.default(&2, List<&2, V.Value>, items(field(delta, "tool_calls")), Nil{}), settingsGrammar(settings), unchanged(G, next)))
  andThen(G, tooled, next => detailSteps(G, Maybe.default(&2, List<&2, V.Value>, items(field(delta, "reasoning_details")), Nil{}), unchanged(G, next)))

def mapMessage(-G: Data, state: State<G>, update: T.AssistantMessage<V.Value, G> -> T.AssistantMessage<V.Value, G>) -> State<G>:
  match state:
    case State{message, a, b, c, d, e, f, g}: State{update(message), a, b, c, d, e, f, g}

def finishReasonSeen(-G: Data, state: State<G>) -> State<G>:
  match state:
    case State{message, a, b, c, d, e, f, _}: State{message, a, b, c, d, e, f, True{}}

def stoppedWith(-G: Data, message: T.AssistantMessage<V.Value, G>, reason: String, mapped: MappedStop) -> T.AssistantMessage<V.Value, G>:
  match mapped:
    case MappedStop{stop, error}: withRawStop(G, message, stop, reason, error)

def stopped(-G: Data, message: T.AssistantMessage<V.Value, G>, +reason: String) -> T.AssistantMessage<V.Value, G>:
  stoppedWith(G, message, reason, mapStopReason(reason))

def withFinish(-G: Data, state: State<G>, reason: Maybe<&2, String>) -> State<G>:
  match reason:
    case Some{SCon{c, cs}}: finishReasonSeen(G, mapMessage(G, state, message => stopped(G, message, SCon{c, cs})))
    case _: state

def usageFrom(-G: Data, +state: State<G>, +value: Maybe<&2, V.Value>, model: T.Model<T.JsonValue>) -> State<G>:
  match value:
    case Some{+raw}: Bool.pick(State<G>, truthy(Some{raw}), mapMessage(G, state, message => withUsage(G, message, parseChunkUsage(raw, model))), state)
    case None{}: state

def firstChoice(values: Maybe<&2, List<&2, V.Value>>) -> Maybe<&2, V.Value>:
  match values:
    case Some{head <> _}: Some{head}
    case _: None{}

def choiceStep(-G: Data, +state: State<G>, +settings: Settings, +chunkUsage: Bool, +choice: V.Value) -> Step<G>:
  +withChoiceUsage = Bool.pick(State<G>, chunkUsage, state, usageFrom(G, state, field(choice, "usage"), settingsModel(settings)))
  +finished = withFinish(G, withChoiceUsage, jsonText(field(choice, "finish_reason")))
  +delta = field(choice, "delta")
  Bool.pick(Unit -> Step<G>, truthy(delta), _ => deltaStep(G, finished, settings, Maybe.default(&2, V.Value, delta, V.Null{})), _ => unchanged(G, finished))(Unit{})

def choiceOf(-G: Data, +state: State<G>, +settings: Settings, +chunkUsage: Bool, choice: Maybe<&2, V.Value>) -> Step<G>:
  match choice:
    case Some{+value}: Bool.pick(Unit -> Step<G>, truthy(Some{value}), _ => choiceStep(G, state, settings, chunkUsage, value), _ => unchanged(G, state))(Unit{})
    case None{}: unchanged(G, state)

def objectChunk(-G: Data, state: State<G>, +value: V.Value, +settings: Settings) -> Step<G>:
  +identified = mapMessage(G, state, message => withResponse(G, message, jsonText(field(value, "id")), jsonText(field(value, "model"))))
  +usage = field(value, "usage")
  +metered = usageFrom(G, identified, usage, settingsModel(settings))
  choiceOf(G, metered, settings, truthy(usage), firstChoice(items(field(value, "choices"))))

# One chunk of the stream loop. Non-object chunks (e.g. `null`) are skipped.
def chunk(-G: Data, +state: State<G>, +value: V.Value, +settings: Settings) -> Step<G>:
  Bool.pick(Unit -> Step<G>, isObject(value), _ => objectChunk(G, state, value, settings), _ => unchanged(G, state))(Unit{})

# Ending
# ------

def hasToolCall(values: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match values:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

def endFor(-G: Data, message: T.AssistantMessage<V.Value, G>, position: Nat, block: Maybe<&2, T.AssistantContent<V.Value>>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match block:
    case Some{T.AssistantText{T.TextContent{value, _}}}: T.TextEnd{index(position), value, message} <> Nil{}
    case Some{T.AssistantThinking{T.ThinkingContent{value, _, _}}}: T.ThinkingEnd{index(position), value, message} <> Nil{}
    case Some{T.AssistantToolCall{call}}: T.ToolcallEnd{index(position), call, message} <> Nil{}
    case None{}: Nil{}

def endEvent(-G: Data, +message: T.AssistantMessage<V.Value, G>, +position: Nat) -> List<&2, T.AssistantMessageEvent<V.Value, G>>: endFor(G, message, position, blockAt(contentOf(G, message), position))

def closedArguments(block: ToolBlock) -> ToolBlock:
  match block:
    case ToolBlock{position, wire, id, name, _, +partial, None{}}: ToolBlock{position, wire, id, name, Partial.parseStreamingJson(partial), partial, None{}}
    case other: other

def deltaEvents(-G: Data, message: T.AssistantMessage<V.Value, G>, position: Nat, delta: Maybe<&2, String>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match delta:
    case Some{value}: T.ToolcallDelta{index(position), value, message} <> Nil{}
    case None{}: Nil{}

def closedCustom(-G: Data, state: State<G>, +position: Nat, result: Result<&2, &2, Sampling.Error, Appended>) -> Step<G>:
  match result:
    case Fail{error}: thrown(G, state, Nil{}, Sampling.errorMessage(error))
    case Done{Appended{block, delta}}:
      +next = written(G, state, block)
      +message = stateMessage(G, next)
      applied(G, next, List.append(&2, T.AssistantMessageEvent<V.Value, G>, deltaEvents(G, message, position, delta), endEvent(G, message, position)))

def closeCustom(+block: ToolBlock) -> Result<&2, &2, Sampling.Error, Appended>: appendCustomInput(block, customInputOf(block), True{})

def finishTool(-G: Data, state: State<G>, +position: Nat, block: Maybe<&2, ToolBlock>) -> Step<G>:
  match block:
    case Some{ToolBlock{a, b, c, d, e, f, Some{custom}}}: closedCustom(G, state, position, closeCustom(ToolBlock{a, b, c, d, e, f, Some{custom}}))
    case Some{other}:
      +next = written(G, state, closedArguments(other))
      applied(G, next, endEvent(G, stateMessage(G, next), position))
    case None{}: unchanged(G, state)

def isThinkingBlock(block: Maybe<&2, T.AssistantContent<V.Value>>) -> Bool:
  match block:
    case Some{T.AssistantThinking{_}}: True{}
    case _: False{}

def isToolBlock(block: Maybe<&2, T.AssistantContent<V.Value>>) -> Bool:
  match block:
    case Some{T.AssistantToolCall{_}}: True{}
    case _: False{}

def toolsOf(-G: Data, state: State<G>) -> List<&2, ToolBlock>:
  match state:
    case State{_, _, _, tools, _, _, _, _}: tools

def endStep(-G: Data, +state: State<G>, +position: Nat) -> Step<G>:
  applied(G, state, endEvent(G, stateMessage(G, state), position))

# finishBlock: text and thinking end with their content (thinking after the
# streamed details are applied); tool calls finalize their arguments.
def finishBlock(-G: Data, +state: State<G>, +position: Nat) -> Step<G>:
  +block = blockAt(contentOf(G, stateMessage(G, state)), position)
  Bool.pick(Unit -> Step<G>, isToolBlock(block), _ => finishTool(G, state, position, toolBlockAt(toolsOf(G, state), position)), _ => endStep(G, Bool.pick(State<G>, isThinkingBlock(block), withDetails(G, state), state), position))(Unit{})

def finishBlocks(-G: Data, remaining: Nat, +position: Nat, step: Step<G>) -> Step<G>:
  match remaining:
    case 0n: step
    case 1n+rest: finishBlocks(G, rest, 1n + position, andThen(G, step, state => finishBlock(G, state, position)))

def doneReason(reason: T.StopReason) -> Maybe<&2, T.DoneReason>:
  match reason:
    case T.Stop{}: Some{T.DoneStop{}}
    case T.Length{}: Some{T.DoneLength{}}
    case T.ToolUse{}: Some{T.DoneToolUse{}}
    case _: None{}

def fallbackStop(-G: Data, state: State<G>, +supportsFinishReason: Bool) -> State<G>:
  match state:
    case State{+message, a, b, c, d, e, f, +seen}: State{Bool.pick(T.AssistantMessage<V.Value, G>, seen || supportsFinishReason, message, withStop(G, message, Bool.pick(T.StopReason, hasToolCall(contentOf(G, message)), T.ToolUse{}, T.Stop{}))), a, b, c, d, e, f, seen}

def errorDetail(value: Maybe<&2, String>) -> String:
  match value:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "Provider returned an error stop reason"

def isError(reason: T.StopReason) -> Bool:
  match reason:
    case T.Error{}: True{}
    case _: False{}

def isPending(reason: T.StopReason) -> Bool:
  match reason:
    case T.Pending{}: True{}
    case _: False{}

def seenFinish(-G: Data, state: State<G>) -> Bool:
  match state:
    case State{_, _, _, _, _, _, _, seen}: seen

def done(-G: Data, state: State<G>, +message: T.AssistantMessage<V.Value, G>, reason: Maybe<&2, T.DoneReason>) -> Step<G>:
  match reason:
    case Some{selected}: applied(G, state, T.StreamDone{selected, message} <> Nil{})
    case None{}: thrown(G, state, Nil{}, "Stream ended without finish_reason")

# The checks after the blocks end, in upstream order.
def checked(-G: Data, state: State<G>, +supportsFinishReason: Bool, aborted: Bool) -> Step<G>:
  +current = fallbackStop(G, state, supportsFinishReason)
  +message = stateMessage(G, current)
  +reason = T.assistantStopReason(V.Value, G, message)
  Bool.pick(Unit -> Step<G>, aborted, _ => thrown(G, current, Nil{}, "Request was aborted"), _ => Bool.pick(Unit -> Step<G>, isError(reason), _ => thrown(G, current, Nil{}, errorDetail(T.assistantErrorMessage(V.Value, G, message))), _ => Bool.pick(Unit -> Step<G>, (supportsFinishReason && Bool.not(seenFinish(G, current))) || isPending(reason), _ => thrown(G, current, Nil{}, "Stream ended without finish_reason"), _ => done(G, current, message, doneReason(reason)))(Unit{}))(Unit{}))(Unit{})

def settingsFinish(settings: Settings) -> Bool:
  match settings:
    case Settings{_, supports, _}: supports

# The end of the stream: finish every block in content order, then the
# abort, finish_reason and error-stop checks.
def finish(-G: Data, +state: State<G>, +settings: Settings, +aborted: Bool) -> Step<G>:
  +blocks = count(T.AssistantContent<V.Value>, contentOf(G, stateMessage(G, state)))
  andThen(G, finishBlocks(G, blocks, 0n, unchanged(G, state)), next => checked(G, next, settingsFinish(settings), aborted))

def failedState(-G: Data, state: State<G>, +message: String, +aborted: Bool) -> Step<G>:
  match state:
    case State{prior, a, b, c, d, e, f, g}:
      +failure = withFailure(G, prior, Bool.pick(T.StopReason, aborted, T.Aborted{}, T.Error{}), message)
      Step{State{failure, a, b, c, d, e, f, g}, T.StreamError{Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{}), failure} <> Nil{}, Some{message}}

# The catch block: streamed details still reach the thinking block, and the
# message ends as aborted or failed with the reported message.
def failedWith(-G: Data, state: State<G>, +message: String, +aborted: Bool) -> Step<G>: failedState(G, withDetails(G, state), message, aborted)

def failed(-G: Data, state: State<G>, +message: String) -> Step<G>: failedWith(G, state, message, False{})
