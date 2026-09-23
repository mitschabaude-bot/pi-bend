import Base
import ../types.bend as T
import ../utils/hash.bend as Hash
import ../utils/json.bend as Json
import ../utils/schema-json.bend as SchemaJson
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/transcript.bend as Transcript
import ../utils/text.bend as Text
import ./transform-messages.bend as Transform
import ./constrained-sampling.bend as C
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/json.bend as StringJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/callback.bend as Callback

# Request-side conversion shared by the OpenAI Responses providers: text
# signatures, tool-call identifiers, transcript messages, tool declarations and
# their JSON wire encoding. Response processing is in openai-responses-stream.

# Text signatures
# ---------------

def phaseName(phase: T.TextSignaturePhase) -> String:
  match phase:
    case T.Commentary{}: "commentary"
    case T.FinalAnswer{}: "final_answer"

def phaseField(phase: Maybe<&2,T.TextSignaturePhase>) -> String:
  match phase:
    case None{}: ""
    case Some{value}: ",\"phase\":" ++ StringJson.quote(phaseName(value))

def encodeTextSignatureV1(id: String, phase: Maybe<&2,T.TextSignaturePhase>) -> String:
  "{\"v\":1,\"id\":" ++ StringJson.quote(id) ++ phaseField(phase) ++ "}"

def decodedPhase(value: Maybe<&2,V.Value>) -> Maybe<&2,T.TextSignaturePhase>:
  match value:
    case Some{V.Text{"commentary"}}: Some{T.Commentary{}}
    case Some{V.Text{"final_answer"}}: Some{T.FinalAnswer{}}
    case _: None{}

def version(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Number{number}}: F.isEqual(F.compare(number,F.fromU32(1)))
    case _: False{}

def parsedFields(validVersion: Bool, id: Maybe<&2,V.Value>, phase: Maybe<&2,V.Value>) -> Maybe<&2,T.TextSignatureV1>:
  match validVersion id:
    case True{} Some{V.Text{text}}: Some{T.TextSignatureV1{text,decodedPhase(phase)}}
    case _ _: None{}

def parsedSignature(result: Result<&2,&2,Parse.ParseError,V.Value>) -> Maybe<&2,T.TextSignatureV1>:
  match result:
    case Done{V.ObjectValue{+fields}}: parsedFields(version(R.get(V.Value,fields,"v")),R.get(V.Value,fields,"id"),R.get(V.Value,fields,"phase"))
    case _: None{}

def legacyFallback(parsed: Maybe<&2,T.TextSignatureV1>, text: String) -> Maybe<&2,T.TextSignatureV1>:
  match parsed:
    case None{}: Some{T.TextSignatureV1{text,None{}}}
    case value: value

def parseTextSignature(signature: Maybe<&2,String>) -> Maybe<&2,T.TextSignatureV1>:
  match signature:
    case None{}: None{}
    case Some{SNil{}}: None{}
    case Some{SCon{'{',+rest}}: legacyFallback(parsedSignature(Parse.parse(SCon{'{',rest})),SCon{'{',rest})
    case Some{text}: Some{T.TextSignatureV1{text,None{}}}

# Tool result and user content
# ----------------------------

# Provider wire content remains typed until the explicit JSON boundary. The
# discriminator and fixed image detail are supplied by the constructors.
type ResponseInputContent is Data:
  ResponseInputText{text: String}
  ResponseInputImage{imageUrl: String}

type ToolResultOutput is Data:
  TextOutput{text: String}
  ContentOutput{content: List<&2, ResponseInputContent>}

def image(image: T.ImageContent) -> ResponseInputContent:
  match image:
    case T.ImageContent{data, mimeType}: ResponseInputImage{"data:" ++ mimeType ++ ";base64," ++ data}

def textParts(content: List<&2, T.TextImageContent>) -> List<&2, String>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> textParts(rest)
    case _ <> rest: textParts(rest)

def images(content: List<&2, T.TextImageContent>) -> List<&2, ResponseInputContent>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageImage{value} <> rest: image(value) <> images(rest)
    case _ <> rest: images(rest)

def toolOutput(vision: Bool, +text: String, images: List<&2, ResponseInputContent>) -> ToolResultOutput:
  match vision images:
    case _ Nil{}: TextOutput{Unicode.sanitizeSurrogates(Bool.pick(String, String.is_empty(text), "(no tool output)", text))}
    case False{} _ <> _: TextOutput{Unicode.sanitizeSurrogates(Bool.pick(String, String.is_empty(text), "(see attached image)", text))}
    case True{} +head <> +rest:
      ContentOutput{Bool.pick(List<&2, ResponseInputContent>, String.is_empty(text), head <> rest, ResponseInputText{Unicode.sanitizeSurrogates(text)} <> head <> rest)}

def convertToolResultOutput(-J: Data, model: T.Model<J>, +content: List<&2, T.TextImageContent>) -> ToolResultOutput:
  toolOutput(Transform.imageCapability(J, model), String.join(textParts(content), "\n"), images(content))

def userBlocks(content: List<&2, T.TextImageContent>) -> List<&2, ResponseInputContent>:
  match content:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: ResponseInputText{Unicode.sanitizeSurrogates(text)} <> userBlocks(rest)
    case T.TextImageImage{value} <> rest: image(value) <> userBlocks(rest)

# A plain empty string still becomes one text block. An empty block list omits
# the user message entirely, matching the provider conversion's continue path.
def convertUserContent(content: T.UserContent) -> Maybe<&2, List<&2, ResponseInputContent>>:
  match content:
    case T.UserText{text}: Some{ResponseInputText{Unicode.sanitizeSurrogates(text)} <> Nil{}}
    case T.UserBlocks{Nil{}}: None{}
    case T.UserBlocks{head <> rest}: Some{userBlocks(head <> rest)}

def contentToJson(content: ResponseInputContent) -> T.JsonValue:
  match content:
    case ResponseInputText{text}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"input_text"}} <> R.Property{"text", T.JsonString{text}} <> Nil{}}}
    case ResponseInputImage{url}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"input_image"}} <> R.Property{"detail", T.JsonString{"auto"}} <> R.Property{"image_url", T.JsonString{url}} <> Nil{}}}

def contentsToJson(content: List<&2, ResponseInputContent>) -> List<&2, T.JsonValue>:
  match content:
    case Nil{}: Nil{}
    case head <> rest: contentToJson(head) <> contentsToJson(rest)

def outputToJson(output: ToolResultOutput) -> T.JsonValue:
  match output:
    case TextOutput{text}: T.JsonString{text}
    case ContentOutput{content}: T.JsonArray{contentsToJson(content)}

def userToJson(content: List<&2, ResponseInputContent>) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"role", T.JsonString{"user"}} <> R.Property{"content", T.JsonArray{contentsToJson(content)}} <> Nil{}}}

# Tool-call identifiers
# ---------------------

# Provider IDs use an ASCII wire alphabet. A supplementary scalar occupies two
# UTF-16 units, so it replaces two disallowed units before the 64-unit cap.
def allowed(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 95) || U32.is_eq(code, 45)

def replacement(+code: U32) -> String:
  Bool.pick(String, allowed(code), SCon{Chr{code}, SNil{}}, Bool.pick(String, U32.is_gt(code, 65535), "__", "_"))

def sanitize(part: String) -> String:
  match part:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: replacement(code) ++ sanitize(rest)

def dropUnderscores(text: String) -> String:
  match text:
    case SCon{'_', rest}: dropUnderscores(rest)
    case other: other

def normalizeIdPart(part: String) -> String:
  String.reverse(dropUnderscores(String.reverse(String.take(sanitize(part), 64n))))

def buildForeignResponsesItemId(itemId: String) -> String:
  "fc_" ++ Hash.shortHash(itemId)

def firstPart(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'|', _}: String.reverse(reversed)
    case SCon{char, rest}: firstPart(rest, SCon{char, reversed})

type IdParts is Data:
  IdParts{call: String, item: String}

def splitId(text: String, reversed: String) -> Maybe<&2, IdParts>:
  match text:
    case SNil{}: None{}
    case SCon{'|', rest}: Some{IdParts{String.reverse(reversed), firstPart(rest, "")}}
    case SCon{char, rest}: splitId(rest, SCon{char, reversed})

def fcPrefix(text: String) -> Bool:
  match text:
    case SCon{'f', SCon{'c', SCon{'_', _}}}: True{}
    case _: False{}

def normalizedItem(foreign: Bool, item: String) -> String:
  match foreign:
    case True{}: buildForeignResponsesItemId(item)
    case False{}: normalizeIdPart(item)

def withPrefix(+item: String) -> String:
  Bool.pick(String, fcPrefix(item), item, normalizeIdPart("fc_" ++ item))

def normalizeSplit(split: Maybe<&2, IdParts>, original: String, foreign: Bool) -> String:
  match split:
    case None{}: normalizeIdPart(original)
    case Some{IdParts{call, item}}: normalizeIdPart(call) ++ "|" ++ withPrefix(normalizedItem(foreign, item))

def contains(providers: List<&2, String>, +provider: String) -> Bool:
  match providers:
    case Nil{}: False{}
    case head <> rest: String.eq(head, provider) || contains(rest, provider)

def normalizeAllowed(keepComposite: Bool, +id: String, foreign: Bool) -> String:
  match keepComposite:
    case False{}: normalizeIdPart(id)
    case True{}: normalizeSplit(splitId(id, ""), id, foreign)

def normalizeFor(id: String, +targetProvider: String, targetApi: String, sourceProvider: String, sourceApi: String, allowedProviders: List<&2, String>) -> String:
  normalizeAllowed(contains(allowedProviders, targetProvider), id, Bool.not(String.eq(targetProvider, sourceProvider) && String.eq(targetApi, sourceApi)))

def normalizeToolCallId(-A: Data, -G: Data, id: String, target: Transform.Target, source: T.AssistantMessage<A, G>, allowedProviders: List<&2, String>) -> String:
  match target source:
    case Transform.Target{api, provider, _} T.AssistantMessage{_, sourceApi, sourceProvider, _, _, _, _, _, _, _, _, _, _, _, _}: normalizeFor(id, provider, api, sourceProvider, sourceApi, allowedProviders)

# Assistant replay
# ----------------

# Reasoning signatures are opaque provider-owned JSON. Ordinary output items
# retain typed fields rather than acquiring a dynamic property representation.
type Call is Data:
  Call{id: Maybe<&2, String>, callId: String, name: String, namespace: Maybe<&2, String>}

type AssistantItem is Data:
  ReasoningReplay{value: V.Value}
  OutputMessage{id: String, text: String, phase: Maybe<&2, T.TextSignaturePhase>}
  FunctionCall{call: Call, arguments: String}
  CustomToolCall{call: Call, input: String}

type AssistantError is Data:
  InvalidReasoningSignature{error: Parse.ParseError}
  InvalidGrammarInput{error: C.Error}
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

def reasoningReplay(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Result<&2, &2, AssistantError, Maybe<&2, AssistantItem>>:
  match result:
    case Fail{error}: Fail{InvalidReasoningSignature{error}}
    case Done{value}: Done{Some{ReasoningReplay{value}}}

def thinking(signature: Maybe<&2, String>) -> Result<&2, &2, AssistantError, Maybe<&2, AssistantItem>>:
  match signature:
    case None{}: Done{None{}}
    case Some{SNil{}}: Done{None{}}
    case Some{text}: reasoningReplay(Parse.parse(text))

def itemId(+raw: String, differentModel: Bool, custom: Bool) -> Maybe<&2, String>:
  +fc = fcPrefix(raw)
  Bool.pick(Maybe<&2, String>, (differentModel && fc) || (Bool.not(custom) && Bool.not(fc)), None{}, Some{raw})

def callParts(parts: Maybe<&2, IdParts>, original: String, name: String, namespace: Maybe<&2, String>, differentModel: Bool, custom: Bool) -> Call:
  match parts:
    case None{}: Call{None{}, original, name, namespace}
    case Some{IdParts{call, raw}}: Call{itemId(raw, differentModel, custom), call, name, namespace}

def customCall(call: Call, input: Result<&2, &2, C.Error, String>) -> Result<&2, &2, AssistantError, AssistantItem>:
  match input:
    case Fail{error}: Fail{InvalidGrammarInput{error}}
    case Done{text}: Done{CustomToolCall{call, Unicode.sanitizeSurrogates(text)}}

def functionCall(call: Call, arguments: Maybe<&2, String>) -> Result<&2, &2, AssistantError, AssistantItem>:
  match arguments:
    case None{}: Fail{InvalidArguments{}}
    case Some{text}: Done{FunctionCall{call, text}}

# Provider JSON may be a scalar or array even for a declared object schema.
# Keep it intact for ordinary function calls; grammar tools require a field.
def grammarInput(name: String, arguments: V.Value, property: String) -> Result<&2, &2, C.Error, String>:
  match arguments:
    case V.ObjectValue{fields}: C.getGrammarToolInput(name, fields, property)
    case _: Fail{C.GrammarArgumentNotString{name, property}}

def convertCall(property: Maybe<&2, String>, +id: String, +name: String, arguments: V.Value, namespace: Maybe<&2, String>, differentModel: Bool) -> Result<&2, &2, AssistantError, AssistantItem>:
  match property:
    case None{}: functionCall(callParts(splitId(id, ""), id, name, namespace, differentModel, False{}), Json.stringify(SchemaJson.toJson(arguments)))
    case Some{inputProperty}: customCall(callParts(splitId(id, ""), id, name, namespace, differentModel, True{}), grammarInput(name, arguments, inputProperty))

def optionalItem(result: Result<&2, &2, AssistantError, AssistantItem>) -> Result<&2, &2, AssistantError, Maybe<&2, AssistantItem>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{item}: Done{Some{item}}

def block(~A: Data, ~encode: A -> V.Value, content: T.AssistantContent<A>, context: ReplayContext, textIndex: Nat) -> Result<&2, &2, AssistantError, Maybe<&2, AssistantItem>>:
  match content context:
    case T.AssistantThinking{T.ThinkingContent{_, signature, _}} _: thinking(signature)
    case T.AssistantText{T.TextContent{text, signature}} ReplayContext{_, _, index, _}: Done{Some{textItem(parseTextSignature(signature), text, fallbackId(index, textIndex))}}
    case T.AssistantToolCall{T.ToolCall{id, +name, arguments, _, namespace}} ReplayContext{same, different, _, properties}: optionalItem(convertCall(R.get(String, properties, name), id, name, encode(arguments), Bool.pick(Maybe<&2, String>, same, namespace, None{}), different))

def advance(-A: Data, content: T.AssistantContent<A>, index: Nat) -> Nat:
  match content:
    case T.AssistantText{_}: index + 1n
    case _: index

def append(item: Result<&2, &2, AssistantError, Maybe<&2, AssistantItem>>, reversed: List<&2, AssistantItem>) -> Result<&2, &2, AssistantError, List<&2, AssistantItem>>:
  match item:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{reversed}
    case Done{Some{value}}: Done{value <> reversed}

# This stage receives already-transformed content. It returns the first error
# without exposing a partially converted message; only text blocks advance IDs.
def collect(~A: Data, ~encode: A -> V.Value, content: List<&2, T.AssistantContent<A>>, +context: ReplayContext, +textIndex: Nat, result: Result<&2, &2, AssistantError, List<&2, AssistantItem>>) -> Result<&2, &2, AssistantError, List<&2, AssistantItem>>:
  match content result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, AssistantItem, reversed)}
    case +head <> rest Done{reversed}: collect(~A, ~encode, rest, context, advance(A, head, textIndex), append(block(~A, ~encode, head, context, textIndex), reversed))

def convertAssistantContent(~A: Data, ~encode: A -> V.Value, content: List<&2, T.AssistantContent<A>>, context: ReplayContext) -> Result<&2, &2, AssistantError, List<&2, AssistantItem>>:
  collect(~A, ~encode, content, context, 0n, Done{Nil{}})

# The complete-message entry point derives identity from canonical source and
# target records, so callers cannot accidentally preserve a foreign namespace.
def convertAssistantMessage(~A: Data, ~G: Data, ~encode: A -> V.Value, target: Transform.Target, source: T.AssistantMessage<A, G>, messageIndex: Nat, grammarInputProperties: R.Record<String>) -> Result<&2, &2, AssistantError, List<&2, AssistantItem>>:
  match target source:
    case Transform.Target{api, provider, id} T.AssistantMessage{content, sourceApi, sourceProvider, sourceModel, _, _, _, _, _, _, _, _, _, _, _}:
      +sameProviderAndApi = String.eq(api, sourceApi) && String.eq(provider, sourceProvider)
      +sameId = String.eq(id, sourceModel)
      convertAssistantContent(~A, ~encode, content, ReplayContext{sameProviderAndApi && sameId, sameProviderAndApi && Bool.not(sameId), messageIndex, grammarInputProperties})

def optionalField(name: String, value: Maybe<&2, String>) -> List<&2, R.Property<T.JsonValue>>:
  match value:
    case None{}: Nil{}
    case Some{text}: R.Property{name, T.JsonString{text}} <> Nil{}

def phaseProperty(phase: Maybe<&2, T.TextSignaturePhase>) -> List<&2, R.Property<T.JsonValue>>:
  match phase:
    case None{}: Nil{}
    case Some{value}: R.Property{"phase", T.JsonString{phaseName(value)}} <> Nil{}

def callToJson(call: Call, kind: String, field: String, value: String) -> T.JsonValue:
  match call:
    case Call{id, callId, name, namespace}:
      fields = {R.Property{"call_id", T.JsonString{callId}} <> R.Property{"name", T.JsonString{name}} <> R.Property{field, T.JsonString{value}} <> optionalField("namespace", namespace) : List<&2, R.Property<T.JsonValue>>}
      T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> List.append(&2, R.Property<T.JsonValue>, optionalField("id", id), fields)}}

def outputTextToJson(text: String) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{"output_text"}} <> R.Property{"text", T.JsonString{text}} <> R.Property{"annotations", T.JsonArray{Nil{}}} <> Nil{}}}

def messageToJson(id: String, text: String, phase: Maybe<&2, T.TextSignaturePhase>) -> T.JsonValue:
  fields = {R.Property{"type", T.JsonString{"message"}} <> R.Property{"role", T.JsonString{"assistant"}} <> R.Property{"content", T.JsonArray{outputTextToJson(text) <> Nil{}}} <> R.Property{"status", T.JsonString{"completed"}} <> R.Property{"id", T.JsonString{id}} <> phaseProperty(phase) : List<&2, R.Property<T.JsonValue>>}
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

# Messages and tools
# ------------------

# Native wire declarations and transcript input. Streamed response events
# remain a separate provider layer.
type GrammarToolFormat is Data:
  GrammarToolFormat{syntax: T.GrammarFormat, definition: String}

type OpenAITool is Data:
  FunctionTool{name: String, description: String, parameters: V.Value, strict: Maybe<&2, T.Nullable<Bool>>, deferLoading: Maybe<&2, Bool>}
  CustomTool{name: String, description: String, format: GrammarToolFormat, deferLoading: Maybe<&2, Bool>}

type ConvertResponsesToolsOptions is Data:
  ConvertResponsesToolsOptions{strict: Maybe<&2, T.Nullable<Bool>>, supportsStrictMode: Maybe<&2, Bool>, supportsOpenAIGrammarTools: Maybe<&2, Bool>, toolSearchResult: Maybe<&2, Bool>}

def option(value: Maybe<&2, Bool>, fallback: Bool) -> Bool:
  match value:
    case None{}: fallback
    case Some{boolean}: boolean

def strictDefault(value: Maybe<&2, T.Nullable<Bool>>) -> T.Nullable<Bool>:
  match value:
    case None{}: T.PresentValue{False{}}
    case Some{setting}: setting

def strictEnabled(value: T.Nullable<Bool>) -> Bool:
  match value:
    case T.NullValue{}: False{}
    case T.PresentValue{boolean}: boolean

def deferred(enabled: Bool) -> Maybe<&2, Bool>:
  match enabled:
    case True{}: Some{True{}}
    case False{}: None{}

def functionParameters(name: String, description: String, strict: Maybe<&2, T.Nullable<Bool>>, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, V.Value>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{parameters}: Done{FunctionTool{name, description, parameters, strict, loading}}

def functionDeclaration(tool: T.Tool<V.Value>, +strict: T.Nullable<Bool>, supported: Bool, loading: Maybe<&2, Bool>) -> Result<&2, &2, C.Error, OpenAITool>:
  match tool:
    case T.Tool{+name, +description, parameters, config}:
      functionParameters(name, description, Bool.pick(Maybe<&2, T.Nullable<Bool>>, supported, Some{strict}, None{}), loading, C.getJsonSchemaToolParameters(T.Tool{name, description, parameters, config}, Some{strictEnabled(strict)}))

def strictSelection(value: Maybe<&2, Bool>, fallback: T.Nullable<Bool>) -> T.Nullable<Bool>:
  match value:
    case None{}: fallback
    case Some{boolean}: T.PresentValue{boolean}

def strictTool(tool: T.Tool<V.Value>, fallback: T.Nullable<Bool>, supported: Bool, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, Maybe<&2, Bool>>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{strict}: functionDeclaration(tool, strictSelection(strict, fallback), supported, loading)

def customTool(tool: T.Tool<V.Value>, syntax: T.GrammarFormat, definition: String, loading: Maybe<&2, Bool>) -> Result<&2, &2, C.Error, OpenAITool>:
  match tool:
    case T.Tool{name, description, _, _}: Done{CustomTool{name, description, GrammarToolFormat{syntax, definition}, loading}}

def grammarTool(+tool: T.Tool<V.Value>, fallback: T.Nullable<Bool>, +supported: Bool, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, Maybe<&2, C.GrammarConstrainedSampling>>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: strictTool(tool, fallback, supported, loading, C.resolveJsonSchemaStrictSampling(tool, supported))
    case Done{Some{C.GrammarConstrainedSampling{syntax, definition, _}}}: customTool(tool, syntax, definition, loading)

def collected(value: Result<&2, &2, C.Error, OpenAITool>, reversed: List<&2, OpenAITool>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{tool}: Done{tool <> reversed}

# Conversion visits tools in declaration order and returns the first error.
# The result accumulator makes error propagation explicit without mutation.
def convertFrom(tools: List<&2, T.Tool<V.Value>>, +fallback: T.Nullable<Bool>, +strictSupport: Bool, +grammarSupport: Bool, +loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, List<&2, OpenAITool>>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match tools result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, OpenAITool, reversed)}
    case +head <> tail Done{reversed}: convertFrom(tail, fallback, strictSupport, grammarSupport, loading, collected(grammarTool(head, fallback, strictSupport, loading, C.resolveGrammarConstrainedSampling(head, grammarSupport)), reversed))

def convertConfigured(tools: List<&2, T.Tool<V.Value>>, options: ConvertResponsesToolsOptions) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match options:
    case ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, search}:
      convertFrom(tools, strictDefault(strict), option(strictSupport, True{}), option(grammarSupport, False{}), deferred(option(search, False{})), Done{Nil{}})

def convertResponsesTools(tools: List<&2, T.Tool<V.Value>>, options: Maybe<&2, ConvertResponsesToolsOptions>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match options:
    case None{}: convertConfigured(tools, ConvertResponsesToolsOptions{None{}, None{}, None{}, None{}})
    case Some{value}: convertConfigured(tools, value)

def addLoading(fields: R.Record<T.JsonValue>, loading: Maybe<&2, Bool>) -> R.Record<T.JsonValue>:
  match loading:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "defer_loading", T.JsonBoolean{value})

def addStrict(fields: R.Record<T.JsonValue>, strict: Maybe<&2, T.Nullable<Bool>>) -> R.Record<T.JsonValue>:
  match strict:
    case None{}: fields
    case Some{T.NullValue{}}: R.set(T.JsonValue, fields, "strict", T.JsonNull{})
    case Some{T.PresentValue{value}}: R.set(T.JsonValue, fields, "strict", T.JsonBoolean{value})

def grammarSyntax(syntax: T.GrammarFormat) -> String:
  match syntax:
    case T.OpenAILark{}: "lark"
    case T.OpenAIRegex{}: "regex"

def toolToJson(tool: OpenAITool) -> T.JsonValue:
  match tool:
    case FunctionTool{name, description, parameters, strict, loading}:
      T.JsonObject{addStrict(addLoading(R.Record{R.Property{"type", T.JsonString{"function"}} <> R.Property{"name", T.JsonString{name}} <> R.Property{"description", T.JsonString{description}} <> R.Property{"parameters", SchemaJson.toJson(parameters)} <> Nil{}}, loading), strict)}
    case CustomTool{name, description, GrammarToolFormat{syntax, definition}, loading}:
      T.JsonObject{addLoading(R.Record{R.Property{"type", T.JsonString{"custom"}} <> R.Property{"name", T.JsonString{name}} <> R.Property{"description", T.JsonString{description}} <> R.Property{"format", T.JsonObject{R.Record{R.Property{"type", T.JsonString{"grammar"}} <> R.Property{"syntax", T.JsonString{grammarSyntax(syntax)}} <> R.Property{"definition", T.JsonString{definition}} <> Nil{}}}} <> Nil{}}, loading)}

type InstructionRole is Data:
  SystemRole{}
  DeveloperRole{}

type ResponseInputItem is Data:
  Instruction{role: InstructionRole, text: String}
  UserInput{content: List<&2, ResponseInputContent>}
  AssistantInput{value: AssistantItem}
  FunctionToolOutput{callId: String, output: ToolResultOutput}
  CustomToolOutput{callId: String, output: ToolResultOutput}
  AdditionalTools{tools: List<&2, OpenAITool>}
  ToolSearchCall{callId: String, names: List<&2, String>}
  ToolSearchOutput{callId: String, tools: List<&2, OpenAITool>}

type ConvertResponsesMessagesOptions is Data:
  ConvertResponsesMessagesOptions{includeSystemPrompt: Maybe<&2, Bool>, grammarToolInputProperties: Maybe<&2, R.Record<String>>, supportsMidConvoSystemMessages: Maybe<&2, Bool>, supportsAdditionalTools: Maybe<&2, Bool>, supportsToolSearch: Maybe<&2, Bool>, toolOptions: Maybe<&2, ConvertResponsesToolsOptions>}

type MessageError is Data:
  AssistantConversion{error: AssistantError}
  ToolConversion{error: C.Error}

type AssemblyConfig is Data:
  AssemblyConfig{includeInitial: Bool, grammar: R.Record<String>, additional: Bool, search: Bool, toolOptions: Maybe<&2, ConvertResponsesToolsOptions>, anchors: Bool, role: InstructionRole}

def messageOptions(options: Maybe<&2, ConvertResponsesMessagesOptions>) -> ConvertResponsesMessagesOptions:
  match options:
    case None{}: ConvertResponsesMessagesOptions{None{}, None{}, None{}, None{}, None{}, None{}}
    case Some{value}: value

def grammarProperties(value: Maybe<&2, R.Record<String>>) -> R.Record<String>:
  match value:
    case None{}: R.new(String)
    case Some{properties}: properties

def supportsDeveloper(api: T.ModelApi, compatibility: Maybe<&2, T.ModelCompatibility(api)>) -> Bool:
  match api compatibility:
    case T.OpenAIResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.AzureOpenAIResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.OpenAICodexResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{_, setting, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case _ _: True{}

def instructionRole(-J: Data, model: T.Model<J>) -> InstructionRole:
  match model:
    case T.Model{_, _, api, _, _, reasoning, _, _, _, _, _, _, _, _, _, compatibility}: Bool.pick(InstructionRole, reasoning && supportsDeveloper(api, compatibility), DeveloperRole{}, SystemRole{})

def anchors(-P: Data, tools: Transcript.TranscriptTools<P>) -> Bool:
  match tools:
    case Transcript.TranscriptTools{_, value}: value

def assemblyConfig(-P: Data, -A: Data, -G: Data, -D: Data, -J: Data, messages: List<&2, T.Message<P, A, G, D>>, model: T.Model<J>, options: ConvertResponsesMessagesOptions) -> AssemblyConfig:
  match options:
    case ConvertResponsesMessagesOptions{includeInitial, grammar, _, +additional, +search, tools}:
      AssemblyConfig{option(includeInitial, True{}), grammarProperties(grammar), option(additional, False{}), option(search, False{}), tools, anchors(P, Transcript.resolveTranscriptTools(P, A, G, D, messages, option(additional, False{}) || option(search, False{}))), instructionRole(J, model)}

def schemaTools(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>) -> List<&2, T.Tool<V.Value>>:
  match tools:
    case Nil{}: Nil{}
    case T.Tool{name, description, parameters, sampling} <> rest: T.Tool{name, description, encode(parameters), sampling} <> schemaTools(~P, ~encode, rest)

def toolNames(-P: Data, tools: List<&2, T.Tool<P>>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case T.Tool{name, _, _, _} <> rest: name <> toolNames(P, rest)

def searchToolOptions(options: Maybe<&2, ConvertResponsesToolsOptions>) -> Maybe<&2, ConvertResponsesToolsOptions>:
  match options:
    case None{}: Some{ConvertResponsesToolsOptions{None{}, None{}, None{}, Some{True{}}}}
    case Some{ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, _}}: Some{ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, Some{True{}}}}

def addedItems(result: Result<&2, &2, C.Error, List<&2, OpenAITool>>, additional: Bool, +names: List<&2, String>, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result additional:
    case Fail{error} _: Fail{ToolConversion{error}}
    case Done{tools} True{}: Done{AdditionalTools{tools} <> Nil{}}
    case Done{tools} False{}:
      +id = "pi_tool_load_" ++ Hash.shortHash("system:" ++ Nat.show(index) ++ ":" ++ String.join(names, ","))
      Done{ToolSearchCall{id, names} <> ToolSearchOutput{id, tools} <> Nil{}}

def selectedAdditions(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>, enabled: Bool, +additional: Bool, +options: Maybe<&2, ConvertResponsesToolsOptions>, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match tools enabled:
    case Nil{} _: Done{Nil{}}
    case _ False{}: Done{Nil{}}
    case +head <> +rest True{}:
      addedItems(convertResponsesTools(schemaTools(~P, ~encode, head <> rest), Bool.pick(Maybe<&2, ConvertResponsesToolsOptions>, additional, options, searchToolOptions(options))), additional, toolNames(P, head <> rest), index)

def systemAdditions(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>, leading: Bool, config: AssemblyConfig, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match config:
    case AssemblyConfig{_, _, +additional, search, options, anchored, _}: selectedAdditions(~P, ~encode, tools, Bool.not(leading) && anchored && (additional || search), additional, options, index)

def systemText(-P: Data, +message: T.SystemMessage<P>, +leading: Bool, config: AssemblyConfig) -> List<&2, ResponseInputItem>:
  match config:
    case AssemblyConfig{includeInitial, _, _, _, _, _, role}:
      +text = Bool.pick(String, leading, Text.renderComplete(P, message), Text.renderUpdate(P, message))
      Bool.pick(List<&2, ResponseInputItem>, (leading && Bool.not(includeInitial)) || String.is_empty(text), Nil{}, Instruction{role, Unicode.sanitizeSurrogates(text)} <> Nil{})

def combinedSystem(additions: Result<&2, &2, MessageError, List<&2, ResponseInputItem>>, text: List<&2, ResponseInputItem>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match additions:
    case Fail{error}: Fail{error}
    case Done{items}: Done{List.append(&2, ResponseInputItem, items, text)}

def convertSystem(~P: Data, ~encode: P -> V.Value, +message: T.SystemMessage<P>, +leading: Bool, +config: AssemblyConfig, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  combinedSystem(systemAdditions(~P, ~encode, Transcript.initialToolsValue(P, message), leading, config, index), systemText(P, message, leading, config))

def userItems(user: Maybe<&2, List<&2, ResponseInputContent>>) -> List<&2, ResponseInputItem>:
  match user:
    case None{}: Nil{}
    case Some{content}: UserInput{content} <> Nil{}

def assistantItems(items: List<&2, AssistantItem>) -> List<&2, ResponseInputItem>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: AssistantInput{head} <> assistantItems(rest)

def assistantResult(result: Result<&2, &2, AssistantError, List<&2, AssistantItem>>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result:
    case Fail{error}: Fail{AssistantConversion{error}}
    case Done{items}: Done{assistantItems(items)}

def resultItem(custom: Maybe<&2, String>, callId: String, output: ToolResultOutput) -> ResponseInputItem:
  match custom:
    case None{}: FunctionToolOutput{callId, output}
    case Some{_}: CustomToolOutput{callId, output}

def convertMessage(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, message: T.Message<P, A, G, D>, model: T.Model<J>, config: AssemblyConfig, first: Bool, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match message config:
    case T.System{message} config: convertSystem(~P, ~encodeParameters, message, first, config, index)
    case T.User{T.UserMessage{content, _}} _: Done{userItems(convertUserContent(content))}
    case T.Assistant{message} AssemblyConfig{_, grammar, _, _, _, _, _}: assistantResult(convertAssistantMessage(~A, ~G, ~encodeArguments, Transform.target(J, model), message, index, grammar))
    case T.ToolResult{T.ToolResultMessage{id, name, content, _, _, _, _}} AssemblyConfig{_, grammar, _, _, _, _, _}: Done{resultItem(R.get(String, grammar, name), firstPart(id, ""), convertToolResultOutput(J, model, content)) <> Nil{}}

# Source position always advances. The output message index skips leading
# systems and omitted user/assistant messages, but counts empty later systems.
def counted(-P: Data, -A: Data, -G: Data, -D: Data, message: T.Message<P, A, G, D>, first: Bool, items: List<&2, ResponseInputItem>) -> Bool:
  match message first items:
    case T.System{_} True{} _: False{}
    case T.System{_} False{} _: True{}
    case _ _ Nil{}: False{}
    case _ _ _: True{}

type AssemblyState is Data:
  AssemblyState{reversed: List<&2, ResponseInputItem>, index: Nat}

def appendMessage(-P: Data, -A: Data, -G: Data, -D: Data, message: T.Message<P, A, G, D>, first: Bool, state: AssemblyState, result: Result<&2, &2, MessageError, List<&2, ResponseInputItem>>) -> Result<&2, &2, MessageError, AssemblyState>:
  match state result:
    case _ Fail{error}: Fail{error}
    case AssemblyState{reversed, index} Done{+items}: Done{AssemblyState{List.append(&2, ResponseInputItem, List.reverse(&2, ResponseInputItem, items), reversed), index + Bool.pick(Nat, counted(P, A, G, D, message, first, items), 1n, 0n)}}

def assemblyIndex(state: AssemblyState) -> Nat:
  match state:
    case AssemblyState{_, index}: index

def assemble(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, messages: List<&2, T.Message<P, A, G, D>>, +model: T.Model<J>, +config: AssemblyConfig, +first: Bool, state: Result<&2, &2, MessageError, AssemblyState>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match messages state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{AssemblyState{reversed, _}}: Done{List.reverse(&2, ResponseInputItem, reversed)}
    case +message <> rest Done{+current}:
      index = assemblyIndex(current)
      assemble(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, rest, model, config, False{}, appendMessage(P, A, G, D, message, first, current, convertMessage(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, message, model, config, first, index)))

def normalizeInput(-A: Data, -G: Data, -J: Data, providers: List<&2, String>, input: Transform.NormalizeToolCallIdInput<A, G, J>) -> IO(Result<&2, &2, MessageError, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, model, source}: IO.pure(Result<&2, &2, MessageError, String>, Done{normalizeToolCallId(A, G, id, Transform.target(J, model), source, providers)})

def normalizeBody(-A: Data, -G: Data, -J: Data, providers: List<&2, String>) -> Transform.NormalizeToolCallIdInput<A, G, J> -> IO(Result<&2, &2, MessageError, String>):
  input => normalizeInput(A, G, J, providers, input)

def assembled(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, model: T.Model<J>, config: AssemblyConfig, result: Result<&2, &2, MessageError, List<&2, T.Message<P, A, G, D>>>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{messages}: assemble(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, messages, model, config, True{}, Done{AssemblyState{Nil{}, 0n}})

def convertResolved(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, ~now: Unit -> IO(F64), +model: T.Model<J>, context: T.TranscriptContext<P, A, G, D>, providers: List<&2, String>, options: ConvertResponsesMessagesOptions) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<Result<&2, &2, MessageError, List<&2, ResponseInputItem>>>:
        +normalizer : Transform.Normalizer(A, G, J, MessageError) <- Callback.create(~List<&2, String>, ~Transform.NormalizeToolCallIdInput<A, G, J>, ~Result<&2, &2, MessageError, String>, ~(normalizeBody(A, G, J)), providers)
        transformed : Result<&2, &2, MessageError, List<&2, T.Message<P, A, G, D>>> <- Transform.transformMessagesWith(~P, ~A, ~G, ~D, ~J, ~MessageError, ~now, messages, model, Some{normalizer})
        Callback.dispose(Transform.NormalizeToolCallIdInput<A, G, J>, Result<&2, &2, MessageError, String>, normalizer)
        return assembled(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, model, assemblyConfig(P, A, G, D, J, messages, model, options), transformed)

def midConversation(options: ConvertResponsesMessagesOptions) -> Maybe<&2, Bool>:
  match options:
    case ConvertResponsesMessagesOptions{_, _, value, _, _, _}: value

# The callback belongs to this invocation and is retired after transformation,
# including typed failures. Application types remain intact until serialization.
def convertResponsesMessagesWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, ~now: Unit -> IO(F64), model: T.Model<J>, context: T.TranscriptContext<P, A, G, D>, allowedToolCallProviders: List<&2, String>, options: Maybe<&2, ConvertResponsesMessagesOptions>) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  +configured = messageOptions(options)
  convertResolved(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, ~now, model, Transcript.resolveTranscript(P, A, G, D, context, midConversation(configured)), allowedToolCallProviders, configured)

def parameterValue(value: V.Value) -> V.Value: value

def argumentRecord(value: R.Record<V.Value>) -> V.Value: V.ObjectValue{value}

def conversionClock(unused: Unit) -> IO(F64): Date.now()

def convertResponsesMessages(~G: Data, ~D: Data, ~J: Data, model: T.Model<J>, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, allowedToolCallProviders: List<&2, String>, options: Maybe<&2, ConvertResponsesMessagesOptions>) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  convertResponsesMessagesWith(~V.Value, ~R.Record<V.Value>, ~G, ~D, ~J, ~parameterValue, ~argumentRecord, ~conversionClock, model, context, allowedToolCallProviders, options)

def roleName(role: InstructionRole) -> String:
  match role:
    case SystemRole{}: "system"
    case DeveloperRole{}: "developer"

def toolJsonList(tools: List<&2, OpenAITool>) -> List<&2, T.JsonValue>:
  match tools:
    case Nil{}: Nil{}
    case head <> rest: toolToJson(head) <> toolJsonList(rest)

def toolsToJson(tools: List<&2, OpenAITool>) -> T.JsonValue:
  match tools:
    case Nil{}: T.JsonArray{Nil{}}
    case head <> rest: T.JsonArray{toolToJson(head) <> toolJsonList(rest)}

def resultToJson(kind: String, callId: String, output: ToolResultOutput) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> R.Property{"call_id", T.JsonString{callId}} <> R.Property{"output", outputToJson(output)} <> Nil{}}}

def nameCount(names: List<&2, String>) -> F64:
  match names:
    case Nil{}: F.fromU32(0)
    case _ <> rest: F.add(F.fromU32(1), nameCount(rest))

def searchArguments(+names: List<&2, String>) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"query", T.JsonString{String.join(names, " ")}} <> R.Property{"limit", T.JsonNumber{nameCount(names)}} <> Nil{}}}

def searchItemToJson(kind: String, callId: String, field: String, value: T.JsonValue) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> R.Property{"call_id", T.JsonString{callId}} <> R.Property{"execution", T.JsonString{"client"}} <> R.Property{"status", T.JsonString{"completed"}} <> R.Property{field, value} <> Nil{}}}

def inputItemToJson(item: ResponseInputItem) -> T.JsonValue:
  match item:
    case Instruction{role, text}: T.JsonObject{R.Record{R.Property{"role", T.JsonString{roleName(role)}} <> R.Property{"content", T.JsonString{text}} <> Nil{}}}
    case UserInput{content}: userToJson(content)
    case AssistantInput{value}: itemToJson(value)
    case FunctionToolOutput{id, output}: resultToJson("function_call_output", id, output)
    case CustomToolOutput{id, output}: resultToJson("custom_tool_call_output", id, output)
    case AdditionalTools{tools}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"additional_tools"}} <> R.Property{"role", T.JsonString{"developer"}} <> R.Property{"tools", toolsToJson(tools)} <> Nil{}}}
    case ToolSearchCall{id, names}: searchItemToJson("tool_search_call", id, "arguments", searchArguments(names))
    case ToolSearchOutput{id, tools}: searchItemToJson("tool_search_output", id, "tools", toolsToJson(tools))

def inputJsonList(items: List<&2, ResponseInputItem>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: inputItemToJson(head) <> inputJsonList(rest)

def inputToJson(items: List<&2, ResponseInputItem>) -> T.JsonValue:
  T.JsonArray{inputJsonList(items)}
