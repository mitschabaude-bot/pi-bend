import Base
import ../types.bend as T
import ../utils/hash.bend as Hash
import ../utils/json.bend as Json
import ../utils/schema-json.bend as SchemaJson
import ../utils/sanitize-unicode.bend as Unicode
import ./openai-text-signature.bend as Signature
import ./openai-responses-ids.bend as Ids
import ./transform-messages.bend as Transform
import ./constrained-sampling.bend as Sampling
import ../../../runtime/src/json-parse.bend as Parse
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

# Reasoning signatures are opaque provider-owned JSON. Ordinary output items
# retain typed fields rather than acquiring a dynamic property representation.
type Call is Data:
  Call{id: Maybe<&2, String>, callId: String, name: String, namespace: Maybe<&2, String>}

type AssistantItem is Data:
  ReasoningReplay{value: V.Value}
  OutputMessage{id: String, text: String, phase: Maybe<&2, T.TextSignaturePhase>}
  FunctionCall{call: Call, arguments: String}
  CustomToolCall{call: Call, input: String}

type Error is Data:
  InvalidReasoningSignature{error: Parse.Error}
  InvalidGrammarInput{error: Sampling.Error}
  InvalidArguments{}

type ReplayContext is Data:
  ReplayContext{sameModel: Bool, differentModel: Bool, messageIndex: Nat, grammarInputProperties: R.Record<String>}

# Count wire UTF-16 units without expanding the string into a second buffer.
def units(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{code}, rest}: Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n) + units(rest)

def fallbackId(messageIndex: Nat, textIndex: Nat) -> String:
  match textIndex:
    case 0n: "msg_pi_" ++ Nat.show(messageIndex)
    case value: "msg_pi_" ++ Nat.show(messageIndex) ++ "_" ++ Nat.show(value)

def messageId(+id: String, fallback: String) -> String:
  Bool.pick(String, String.is_empty(id), fallback, Bool.pick(String, Nat.is_gt(units(id), 64n), "msg_" ++ Hash.shortHash(id), id))

def textItem(signature: Maybe<&2, T.TextSignatureV1>, text: String, fallback: String) -> AssistantItem:
  match signature:
    case None{}: OutputMessage{fallback, Unicode.sanitizeSurrogates(text), None{}}
    case Some{T.TextSignatureV1{id, phase}}: OutputMessage{messageId(id, fallback), Unicode.sanitizeSurrogates(text), phase}

def reasoning(result: Result<&2, &2, Parse.Error, V.Value>) -> Result<&2, &2, Error, Maybe<&2, AssistantItem>>:
  match result:
    case Fail{error}: Fail{InvalidReasoningSignature{error}}
    case Done{value}: Done{Some{ReasoningReplay{value}}}

def thinking(signature: Maybe<&2, String>) -> Result<&2, &2, Error, Maybe<&2, AssistantItem>>:
  match signature:
    case None{}: Done{None{}}
    case Some{SNil{}}: Done{None{}}
    case Some{text}: reasoning(Parse.parse(text))

def itemId(+raw: String, differentModel: Bool, custom: Bool) -> Maybe<&2, String>:
  +fc = Ids.fcPrefix(raw)
  Bool.pick(Maybe<&2, String>, (differentModel && fc) || (Bool.not(custom) && Bool.not(fc)), None{}, Some{raw})

def callParts(parts: Maybe<&2, Ids.IdParts>, original: String, name: String, namespace: Maybe<&2, String>, differentModel: Bool, custom: Bool) -> Call:
  match parts:
    case None{}: Call{None{}, original, name, namespace}
    case Some{Ids.IdParts{call, raw}}: Call{itemId(raw, differentModel, custom), call, name, namespace}

def customCall(call: Call, input: Result<&2, &2, Sampling.Error, String>) -> Result<&2, &2, Error, AssistantItem>:
  match input:
    case Fail{error}: Fail{InvalidGrammarInput{error}}
    case Done{text}: Done{CustomToolCall{call, Unicode.sanitizeSurrogates(text)}}

def functionCall(call: Call, arguments: Maybe<&2, String>) -> Result<&2, &2, Error, AssistantItem>:
  match arguments:
    case None{}: Fail{InvalidArguments{}}
    case Some{text}: Done{FunctionCall{call, text}}

# Provider JSON may be a scalar or array even for a declared object schema.
# Keep it intact for ordinary function calls; grammar tools require a field.
def grammarInput(name: String, arguments: V.Value, property: String) -> Result<&2, &2, Sampling.Error, String>:
  match arguments:
    case V.ObjectValue{fields}: Sampling.getGrammarToolInput(name, fields, property)
    case _: Fail{Sampling.GrammarArgumentNotString{name, property}}

def convertCall(property: Maybe<&2, String>, +id: String, +name: String, arguments: V.Value, namespace: Maybe<&2, String>, differentModel: Bool) -> Result<&2, &2, Error, AssistantItem>:
  match property:
    case None{}: functionCall(callParts(Ids.splitId(id, ""), id, name, namespace, differentModel, False{}), Json.stringify(SchemaJson.toJson(arguments)))
    case Some{inputProperty}: customCall(callParts(Ids.splitId(id, ""), id, name, namespace, differentModel, True{}), grammarInput(name, arguments, inputProperty))

def optionalItem(result: Result<&2, &2, Error, AssistantItem>) -> Result<&2, &2, Error, Maybe<&2, AssistantItem>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{item}: Done{Some{item}}

def block(~A: Data, ~encode: A -> V.Value, content: T.AssistantContent<A>, context: ReplayContext, textIndex: Nat) -> Result<&2, &2, Error, Maybe<&2, AssistantItem>>:
  match content context:
    case T.AssistantThinking{T.ThinkingContent{_, signature, _}} _: thinking(signature)
    case T.AssistantText{T.TextContent{text, signature}} ReplayContext{_, _, index, _}: Done{Some{textItem(Signature.parseTextSignature(signature), text, fallbackId(index, textIndex))}}
    case T.AssistantToolCall{T.ToolCall{id, +name, arguments, _, namespace}} ReplayContext{same, different, _, properties}: optionalItem(convertCall(R.get(String, properties, name), id, name, encode(arguments), Bool.pick(Maybe<&2, String>, same, namespace, None{}), different))

def advance(-A: Data, content: T.AssistantContent<A>, index: Nat) -> Nat:
  match content:
    case T.AssistantText{_}: index + 1n
    case _: index

def append(item: Result<&2, &2, Error, Maybe<&2, AssistantItem>>, reversed: List<&2, AssistantItem>) -> Result<&2, &2, Error, List<&2, AssistantItem>>:
  match item:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{reversed}
    case Done{Some{value}}: Done{value <> reversed}

# This stage receives already-transformed content. It returns the first error
# without exposing a partially converted message; only text blocks advance IDs.
def collect(~A: Data, ~encode: A -> V.Value, content: List<&2, T.AssistantContent<A>>, +context: ReplayContext, +textIndex: Nat, result: Result<&2, &2, Error, List<&2, AssistantItem>>) -> Result<&2, &2, Error, List<&2, AssistantItem>>:
  match content result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, AssistantItem, reversed)}
    case +head <> rest Done{reversed}: collect(~A, ~encode, rest, context, advance(A, head, textIndex), append(block(~A, ~encode, head, context, textIndex), reversed))

def convertAssistantContent(~A: Data, ~encode: A -> V.Value, content: List<&2, T.AssistantContent<A>>, context: ReplayContext) -> Result<&2, &2, Error, List<&2, AssistantItem>>:
  collect(~A, ~encode, content, context, 0n, Done{Nil{}})

# The complete-message entry point derives identity from canonical source and
# target records, so callers cannot accidentally preserve a foreign namespace.
def convertAssistantMessage(~A: Data, ~G: Data, ~encode: A -> V.Value, target: Transform.Target, source: T.AssistantMessage<A, G>, messageIndex: Nat, grammarInputProperties: R.Record<String>) -> Result<&2, &2, Error, List<&2, AssistantItem>>:
  match target source:
    case Transform.Target{api, provider, id} T.AssistantMessage{content, sourceApi, sourceProvider, sourceModel, _, _, _, _, _, _, _, _, _, _, _}:
      +sameProviderAndApi = String.eq(api, sourceApi) && String.eq(provider, sourceProvider)
      +sameId = String.eq(id, sourceModel)
      convertAssistantContent(~A, ~encode, content, ReplayContext{sameProviderAndApi && sameId, sameProviderAndApi && Bool.not(sameId), messageIndex, grammarInputProperties})

def optionalField(name: String, value: Maybe<&2, String>) -> List<&2, R.Property<T.JsonValue>>:
  match value:
    case None{}: Nil{}
    case Some{text}: R.Property{name, T.JsonString{text}} <> Nil{}

def phaseField(phase: Maybe<&2, T.TextSignaturePhase>) -> List<&2, R.Property<T.JsonValue>>:
  match phase:
    case None{}: Nil{}
    case Some{value}: R.Property{"phase", T.JsonString{Signature.phaseName(value)}} <> Nil{}

def callToJson(call: Call, kind: String, field: String, value: String) -> T.JsonValue:
  match call:
    case Call{id, callId, name, namespace}:
      fields = {R.Property{"call_id", T.JsonString{callId}} <> R.Property{"name", T.JsonString{name}} <> R.Property{field, T.JsonString{value}} <> optionalField("namespace", namespace) : List<&2, R.Property<T.JsonValue>>}
      T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> List.append(&2, R.Property<T.JsonValue>, optionalField("id", id), fields)}}

def outputTextToJson(text: String) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{"output_text"}} <> R.Property{"text", T.JsonString{text}} <> R.Property{"annotations", T.JsonArray{Nil{}}} <> Nil{}}}

def messageToJson(id: String, text: String, phase: Maybe<&2, T.TextSignaturePhase>) -> T.JsonValue:
  fields = {R.Property{"type", T.JsonString{"message"}} <> R.Property{"role", T.JsonString{"assistant"}} <> R.Property{"content", T.JsonArray{outputTextToJson(text) <> Nil{}}} <> R.Property{"status", T.JsonString{"completed"}} <> R.Property{"id", T.JsonString{id}} <> phaseField(phase) : List<&2, R.Property<T.JsonValue>>}
  T.JsonObject{R.Record{fields}}

def itemToJson(item: AssistantItem) -> T.JsonValue:
  match item:
    case ReasoningReplay{value}: SchemaJson.toJson(value)
    case FunctionCall{call, arguments}: callToJson(call, "function_call", "arguments", arguments)
    case CustomToolCall{call, input}: callToJson(call, "custom_tool_call", "input", input)
    case OutputMessage{id, text, phase}: messageToJson(id, text, phase)

def itemList(items: List<&2, AssistantItem>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: itemToJson(head) <> itemList(rest)

def itemsToJson(items: List<&2, AssistantItem>) -> T.JsonValue:
  T.JsonArray{itemList(items)}
