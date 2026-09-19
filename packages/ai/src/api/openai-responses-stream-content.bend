import Base
import ../types.bend as T
import ./constrained-sampling.bend as Sampling
import ./openai-text-signature.bend as Signature
import ../utils/json-parse.bend as Parse
import ../utils/json.bend as Json
import ../utils/schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/utf16.bend as Utf16

# Reasoning items are opaque provider replay tokens. Keep their complete JSON,
# including unknown metadata, rather than reconstructing a lossy signature.
# Other output items have ordinary native fields.
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

# Each signal owns the content at emission time. In particular, the last custom
# input delta precedes a namespace supplied by output_item.done.
type Signal is Data:
  Started{content: T.AssistantContent<V.Value>}
  Delta{content: T.AssistantContent<V.Value>, delta: String}
  Ended{content: T.AssistantContent<V.Value>}

type Update is Data:
  Update{block: Block, signals: List<&2, Signal>, finished: Bool}

def content(block: Block) -> T.AssistantContent<V.Value>:
  match block:
    case Thinking{value}: T.AssistantThinking{value}
    case Text{value}: T.AssistantText{value}
    case Function{value, _}: T.AssistantToolCall{value}
    case Custom{value, _, _, _}: T.AssistantToolCall{value}
    case Completed{value}: value

def unchanged(block: Block) -> Update: Update{block, Nil{}, False{}}

def started(+block: Block) -> Maybe<&2, Update>:
  Some{Update{block, Started{content(block)} <> Nil{}, False{}}}

def optionalText(text: Maybe<&2, String>, fallback: String) -> String:
  match text:
    case Some{value}: value
    case None{}: fallback

def inputArguments(property: String, input: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{property, V.Text{input}} <> Nil{}}}

def start(item: OutputItem, properties: R.Record<String>) -> Maybe<&2, Update>:
  match item:
    case ReasoningItem{_}: started(Thinking{T.ThinkingContent{"", None{}, None{}}})
    case MessageItem{_, _, _}: started(Text{T.TextContent{"", None{}}})
    case FunctionItem{id, callId, name, arguments, namespace}: started(Function{T.ToolCall{callId ++ "|" ++ id, name, V.ObjectValue{R.new(V.Value)}, None{}, namespace}, arguments})
    case CustomItem{id, callId, +name, input, namespace}:
      +property = optionalText(R.get(String, properties, name), "input")
      +text = optionalText(input, "")
      started(Custom{T.ToolCall{callId ++ "|" ++ id, name, inputArguments(property, text), None{}, namespace}, property, text, Sampling.GrammarToolInputJsonBuffer{"", False{}, False{}}})
    case OtherItem{}: None{}

def delta(+block: Block, text: String) -> Update:
  Update{block, Delta{content(block), text} <> Nil{}, False{}}

def optionalDelta(+block: Block, text: Maybe<&2, String>) -> Update:
  match text:
    case None{}: unchanged(block)
    case Some{value}: delta(block, value)

def nonemptySuffix(suffix: Maybe<&2, String>) -> Maybe<&2, String>:
  match suffix:
    case Some{""}: None{}
    case Some{text}: Some{Utf16.normalize(text)}
    case None{}: None{}

def arguments(tool: T.ToolCall<V.Value>, value: V.Value) -> T.ToolCall<V.Value>:
  match tool:
    case T.ToolCall{id, name, _, signature, namespace}: T.ToolCall{id, name, value, signature, namespace}

def namespace(tool: T.ToolCall<V.Value>, replacement: Maybe<&2, String>) -> T.ToolCall<V.Value>:
  match tool replacement:
    case value None{}: value
    case T.ToolCall{id, name, args, signature, _} Some{text}: T.ToolCall{id, name, args, signature, Some{text}}

def customUpdated(tool: T.ToolCall<V.Value>, +property: String, +input: String, result: Result<&2, &2, Sampling.Error, Sampling.GrammarToolInputJsonUpdate>) -> Result<&2, &2, Sampling.Error, Update>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Sampling.GrammarToolInputJsonUpdate{buffer, emitted}}:
      Done{optionalDelta(Custom{arguments(tool, inputArguments(property, input)), property, input, buffer}, emitted)}

def customInput(tool: T.ToolCall<V.Value>, +property: String, +input: String, buffer: Sampling.GrammarToolInputJsonBuffer, close: Bool) -> Result<&2, &2, Sampling.Error, Update>:
  customUpdated(tool, property, input, Sampling.appendGrammarToolInputJsonDelta(buffer, property, input, close))

def join(parts: List<&2, String>, +separator: String) -> String:
  match parts:
    case Nil{}: ""
    case text <> Nil{}: text
    case text <> rest: text ++ separator ++ join(rest, separator)

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
    case Some{V.ArrayValue{values}}: join(reasoningTexts(values), "\n\n")
    case _: ""

def orText(text: String, fallback: String) -> String:
  match text:
    case "": fallback
    case other: other

def ended(+value: T.AssistantContent<V.Value>) -> Update:
  Update{Completed{value}, Ended{value} <> Nil{}, True{}}

def customEnded(result: Result<&2, &2, Sampling.Error, Update>, replacement: Maybe<&2, String>) -> Result<&2, &2, Sampling.Error, Update>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Update{Custom{tool, _, _, _}, signals, _}}:
      +value = {T.AssistantToolCall{namespace(tool, replacement)} : T.AssistantContent<V.Value>}
      Done{Update{Completed{value}, List.append(&2, Signal, signals, Ended{value} <> Nil{}), True{}}}
    case Done{update}: Done{update}

def finish(block: Block, item: OutputItem) -> Result<&2, &2, Sampling.Error, Update>:
  match block item:
    case Thinking{T.ThinkingContent{text, _, redacted}} ReasoningItem{+fields}:
      selected = orText(reasoningText(R.get(V.Value, fields, "summary")), orText(reasoningText(R.get(V.Value, fields, "content")), text))
      Done{ended(T.AssistantThinking{T.ThinkingContent{selected, Json.stringify(SchemaJson.toJson(V.ObjectValue{fields})), redacted}})}
    case Text{_} MessageItem{id, phase, texts}: Done{ended(T.AssistantText{T.TextContent{join(texts, ""), Some{Signature.encodeTextSignatureV1(id, phase)}}})}
    case Function{tool, partial} FunctionItem{_, _, _, final, replacement}:
      Done{ended(T.AssistantToolCall{namespace(arguments(tool, Parse.parseStreamingJson(Some{orText(final, orText(partial, "{}"))})), replacement)})}
    case Custom{tool, property, input, buffer} CustomItem{_, _, _, final, replacement}:
      customEnded(customInput(tool, property, optionalText(final, input), buffer, True{}), replacement)
    case other _: Done{unchanged(other)}

def step(block: Block, input: Input) -> Result<&2, &2, Sampling.Error, Update>:
  match block input:
    case value ItemDone{item}: finish(value, item)
    case Thinking{T.ThinkingContent{text, signature, redacted}} ThinkingDelta{+chunk}: Done{delta(Thinking{T.ThinkingContent{text ++ chunk, signature, redacted}}, chunk)}
    case Thinking{T.ThinkingContent{text, signature, redacted}} SummaryPartDone{}: Done{delta(Thinking{T.ThinkingContent{text ++ "\n\n", signature, redacted}}, "\n\n")}
    case Text{T.TextContent{text, signature}} TextDelta{+chunk}: Done{delta(Text{T.TextContent{text ++ chunk, signature}}, chunk)}
    case Function{tool, partial} FunctionDelta{+chunk}:
      +next = partial ++ chunk
      Done{delta(Function{arguments(tool, Parse.parseStreamingJson(Some{next})), next}, chunk)}
    case Function{tool, previous} FunctionDone{+next}:
      optional = nonemptySuffix(Sampling.prefixSuffix(Sampling.codeUnits(previous), Sampling.codeUnits(next)))
      Done{optionalDelta(Function{arguments(tool, Parse.parseStreamingJson(Some{next})), next}, optional)}
    case Custom{tool, property, text, buffer} CustomDelta{chunk}: customInput(tool, property, text ++ chunk, buffer, False{})
    case Custom{tool, property, _, buffer} CustomDone{text}: customInput(tool, property, text, buffer, True{})
    case other _: Done{unchanged(other)}
