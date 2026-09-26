import Base
import ../types.bend as T
import ../models.bend as Models
import ../utils/schema-json.bend as Schema
import ../utils/transcript.bend as Transcript
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/thinking-levels.bend as Levels
import ./constrained-sampling.bend as Sampling
import ./transform-messages.bend as Transform
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/case-map.bend as Case
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space

# Shared utilities for the Google Generative AI and Google Vertex providers
# (pi `google-shared.ts`): thinking levels, thought signatures, Gemini version
# rules, message and tool conversion, tool calling modes and finish reasons.
# Values are the SDK's Content/Part objects as typed JSON values.
def J() -> Data: T.JsonValue

def str(value: String) -> J(): T.JsonString{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def optionalField(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: field(name, item) <> rest

# Thinking levels
# ---------------
# Google's ThinkingLevel enum (GoogleApiThinkingLevel).
type GoogleApiThinkingLevel is Data:
  ThinkingLevelUnspecified{}
  MinimalLevel{}
  LowLevel{}
  MediumLevel{}
  HighLevel{}

def googleLevelName(level: GoogleApiThinkingLevel) -> String:
  match level:
    case ThinkingLevelUnspecified{}: "THINKING_LEVEL_UNSPECIFIED"
    case MinimalLevel{}: "MINIMAL"
    case LowLevel{}: "LOW"
    case MediumLevel{}: "MEDIUM"
    case HighLevel{}: "HIGH"

def modelLevelName(level: T.ThinkingLevel) -> String: Levels.name(T.Thinking{level})

def standardLevel(+name: String) -> Maybe<&2, T.ThinkingLevel>:
  match name:
    case "minimal": Some{T.Minimal{}}
    case "low": Some{T.Low{}}
    case "medium": Some{T.Medium{}}
    case "high": Some{T.High{}}
    case _: None{}

def mappingText(value: Maybe<&2, T.Nullable<String>>) -> String:
  match value:
    case Some{T.PresentValue{text}}: text
    case Some{T.NullValue{}}: "null"
    case None{}: "undefined"

def resolvedName(value: Maybe<&2, T.Nullable<String>>, level: T.ThinkingLevel) -> String:
  match value:
    case Some{T.PresentValue{text}}: Case.lower(text)
    case _: modelLevelName(level)

def unsupportedMapping(+model: T.Model<J()>, level: T.ThinkingLevel, value: Maybe<&2, T.Nullable<String>>) -> String:
  "Unsupported Google thinking level mapping for " ++ T.modelProvider(model) ++ "/" ++ T.modelId(model) ++ ": " ++ modelLevelName(level) ++ " -> " ++ mappingText(value)

def resolvedLevel(selected: Maybe<&2, T.ThinkingLevel>, +model: T.Model<J()>, level: T.ThinkingLevel, +value: Maybe<&2, T.Nullable<String>>) -> Result<&2, &2, String, T.ThinkingLevel>:
  match selected:
    case Some{resolved}: Done{resolved}
    case None{}: Fail{unsupportedMapping(model, level, value)}

def thinkingMap(model: T.Model<J()>) -> Maybe<&2, T.ThinkingLevelMap>:
  match model:
    case T.Model{_, _, _, _, _, _, levels, _, _, _, _, _, _, _, _, _}: levels

# upstream resolveGoogleThinkingLevel: a mapped string (case-insensitively) or
# the level itself must be one of the four standard Google levels.
def resolveGoogleThinkingLevel(+model: T.Model<J()>, +level: T.ThinkingLevel) -> Result<&2, &2, String, T.ThinkingLevel>:
  +value = Levels.mapped(thinkingMap(model), T.Thinking{level})
  resolvedLevel(standardLevel(resolvedName(value, level)), model, level, value)

def startsAt(text: String, prefix: String) -> Bool: String.starts_with(text, prefix)

def proOrFlash(+rest: String) -> Bool: startsAt(rest, "-pro") || startsAt(rest, "-flash")

def minorThen(rest: Maybe<&2, String>) -> Bool:
  match rest:
    case Some{after}: proOrFlash(after)
    case None{}: False{}

def toGoogleThinkingLevel(level: T.ThinkingLevel) -> GoogleApiThinkingLevel:
  match level:
    case T.Minimal{}: MinimalLevel{}
    case T.Low{}: LowLevel{}
    case T.Medium{}: MediumLevel{}
    case _: HighLevel{}

def levelConfig(level: GoogleApiThinkingLevel) -> J(): obj(field("thinkingLevel", str(googleLevelName(level))) <> Nil{})

def budgetZero() -> J(): obj(field("thinkingBudget", T.JsonNumber{F.fromU32(0)}) <> Nil{})

def disabledLevel(result: Result<&2, &2, String, T.ThinkingLevel>) -> Result<&2, &2, String, J()>:
  match result:
    case Fail{message}: Fail{message}
    case Done{level}: Done{levelConfig(toGoogleThinkingLevel(level))}

def disabledFallback(+model: T.Model<J()>, fallback: T.ModelThinkingLevel) -> Result<&2, &2, String, J()>:
  match fallback:
    case T.Off{}: Done{budgetZero()}
    case T.Thinking{level}: disabledLevel(resolveGoogleThinkingLevel(model, level))

def disabledFor(levels: Bool, +model: T.Model<J()>) -> Result<&2, &2, String, J()>:
  match levels:
    case False{}: Done{budgetZero()}
    case True{}: disabledFallback(model, Models.clampThinkingLevel(J(), model, T.Off{}))

# Thought signatures
# ------------------
# `thought: true` is the only thinking marker; a signature can ride on any part.
def isThinkingPart(thought: Maybe<&2, Bool>) -> Bool:
  match thought:
    case Some{True{}}: True{}
    case _: False{}

# Keep the last non-empty signature within one streamed block.
def retainThoughtSignature(existing: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: existing

def base64Char(+char: Char) -> Bool:
  +code = Char.to_u32(char)
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 43) || U32.is_eq(code, 47)

def padding(text: String, count: Nat) -> Bool:
  match text count:
    case SNil{} _: True{}
    case SCon{'=', rest} 1n+left: padding(rest, left)
    case _ _: False{}

def base64Body(text: String, seen: Bool) -> Bool:
  match text:
    case SNil{}: seen
    case SCon{+char, +rest}: Bool.pick(Bool, Char.is_eq(char, '='), seen && padding(SCon{char, rest}, 2n), base64Char(char) && base64Body(rest, True{}))

# Google requires base64 (TYPE_BYTES): /^[A-Za-z0-9+/]+={0,2}$/ with a length
# divisible by four.
def isValidThoughtSignature(signature: Maybe<&2, String>) -> Bool:
  match signature:
    case Some{SCon{+c, +cs}}: Nat.is_eq(Nat.mod(String.length(SCon{c, cs}), 4n), 0n) && base64Body(SCon{c, cs}, False{})
    case _: False{}

def resolveThoughtSignature(same: Bool, +signature: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, same && isValidThoughtSignature(signature), signature, None{})

def parseDigits(text: String, value: Nat) -> Nat:
  match text:
    case SNil{}: value
    case SCon{char, rest}: parseDigits(rest, value * 10n + U32.to_nat(U32.sub(Char.to_u32(char), 48)))

# Gemini versions
# ---------------
def majorDigits(digits: String) -> Maybe<&2, Nat>:
  match digits:
    case SNil{}: None{}
    case text: Some{parseDigits(text, 0n)}

def leadingDigits(text: String) -> String:
  match text:
    case SCon{+char, rest}: Bool.pick(String, Char.is_digit(char), SCon{char, leadingDigits(rest)}, "")
    case SNil{}: ""

def afterDigits(+text: String) -> Maybe<&2, String>:
  +digits = leadingDigits(text)
  Bool.pick(Maybe<&2, String>, String.is_empty(digits), None{}, Some{String.drop(text, String.length(digits))})

def versionSuffix(+rest: String) -> Bool:
  match rest:
    case SCon{'.', digits}: minorThen(afterDigits(digits)) || proOrFlash(rest)
    case _: proOrFlash(rest)

# /gemini-3(?:\.\d+)?-(?:pro|flash)/ anywhere in the text.
def gemini3Family(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char, +rest}: (startsAt(SCon{char, rest}, "gemini-3") && versionSuffix(String.drop(SCon{char, rest}, 8n))) || gemini3Family(rest)

# upstream usesGoogleThinkingLevel: Gemini 3 Pro/Flash, the flash aliases and
# Gemma 4 use the discrete thinkingLevel control.
def usesGoogleThinkingLevel(model: T.Model<J()>) -> Bool:
  +id = Case.lower(T.modelId(model))
  gemini3Family(id) || String.eq(id, "gemini-flash-latest") || String.eq(id, "gemini-flash-lite-latest") || String.contains(id, "gemma-4") || String.contains(id, "gemma4")

# upstream getDisabledGoogleThinkingConfig: level models keep their lowest
# supported level when "off" is unavailable.
def getDisabledGoogleThinkingConfig(+model: T.Model<J()>) -> Result<&2, &2, String, J()>:
  disabledFor(usesGoogleThinkingLevel(model), model)

def afterPrefix(+text: String, +prefix: String) -> Maybe<&2, Nat>:
  Bool.pick(Maybe<&2, Nat>, startsAt(text, prefix), majorDigits(leadingDigits(String.drop(text, String.length(prefix)))), None{})

def firstMajor(live: Maybe<&2, Nat>, +text: String) -> Maybe<&2, Nat>:
  match live:
    case Some{major}: Some{major}
    case None{}: afterPrefix(text, "gemini-")

# /^gemini(?:-live)?-(\d+)/ on the lowercased id.
def getGeminiMajorVersion(modelId: String) -> Maybe<&2, Nat>:
  +text = Case.lower(modelId)
  firstMajor(afterPrefix(text, "gemini-live-"), text)

def atLeast3(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{major}: Nat.is_ge(major, 3n)
    case None{}: False{}

# Models behind Google APIs that need explicit tool call ids.
def requiresToolCallId(+modelId: String) -> Bool:
  String.starts_with(modelId, "claude-") || String.starts_with(modelId, "gpt-oss-") || atLeast3(getGeminiMajorVersion(modelId))

def multimodalMajor(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{major}: Nat.is_ge(major, 3n)
    case None{}: True{}

def supportsMultimodalFunctionResponse(modelId: String) -> Bool: multimodalMajor(getGeminiMajorVersion(modelId))

# Gemini 3+ enforces required function parameters in validated modes.
def supportsGoogleStrictToolSampling(modelId: String) -> Bool: atLeast3(getGeminiMajorVersion(modelId))

# convertMessages
# ---------------
def textPart(text: String) -> J(): obj(field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{})

def inlineData(image: T.ImageContent) -> J():
  match image:
    case T.ImageContent{data, mime}: obj(field("inlineData", obj(field("mimeType", str(mime)) <> field("data", str(data)) <> Nil{})) <> Nil{})

def userPart(item: T.TextImageContent) -> J():
  match item:
    case T.TextImageText{T.TextContent{text, _}}: textPart(text)
    case T.TextImageImage{image}: inlineData(image)

def userParts(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: userPart(item) <> userParts(rest)

def content(role: String, parts: List<&2, J()>) -> J(): obj(field("role", str(role)) <> field("parts", T.JsonArray{parts}) <> Nil{})

def userContent(value: T.UserContent) -> Maybe<&2, J()>:
  match value:
    case T.UserText{text}: Some{content("user", textPart(text) <> Nil{})}
    case T.UserBlocks{Nil{}}: None{}
    case T.UserBlocks{items}: Some{content("user", userParts(items))}

def signatureField(signature: Maybe<&2, String>) -> List<&2, R.Property<J()>>:
  match signature:
    case Some{value}: field("thoughtSignature", str(value)) <> Nil{}
    case None{}: Nil{}

def unsigned(+text: String, signature: Maybe<&2, String>) -> Bool: Space.blank(text) && Maybe.is_none(&2, String, signature)

def textBlock(+text: String, +signature: Maybe<&2, String>) -> Maybe<&2, J()>:
  Bool.pick(Maybe<&2, J()>, unsigned(text, signature), None{}, Some{obj(field("text", str(Unicode.sanitizeSurrogates(text))) <> signatureField(signature))})

def thinkingBlock(+text: String, +signature: Maybe<&2, String>, same: Bool) -> Maybe<&2, J()>:
  match same:
    case True{}: Bool.pick(Maybe<&2, J()>, unsigned(text, signature), None{}, Some{obj(field("thought", T.JsonBoolean{True{}}) <> field("text", str(Unicode.sanitizeSurrogates(text))) <> signatureField(signature))})
    case False{}: Bool.pick(Maybe<&2, J()>, Space.blank(text), None{}, Some{textPart(text)})

def callFields(id: String, name: String, arguments: V.Value, includeId: Bool) -> List<&2, R.Property<J()>>:
  field("name", str(name)) <> field("args", Schema.toJson(arguments)) <> Bool.pick(List<&2, R.Property<J()>>, includeId, field("id", str(id)) <> Nil{}, Nil{})

def assistantPart(block: T.AssistantContent<V.Value>, +same: Bool, +includeId: Bool) -> Maybe<&2, J()>:
  match block:
    case T.AssistantText{T.TextContent{text, signature}}: textBlock(text, resolveThoughtSignature(same, signature))
    case T.AssistantThinking{T.ThinkingContent{text, signature, _}}: thinkingBlock(text, resolveThoughtSignature(same, signature), same)
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, signature, _}}: Some{obj(field("functionCall", obj(callFields(id, name, arguments, includeId))) <> signatureField(resolveThoughtSignature(same, signature)))}

def prependOptional(value: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def assistantParts(blocks: List<&2, T.AssistantContent<V.Value>>, +same: Bool, +includeId: Bool) -> List<&2, J()>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: prependOptional(assistantPart(block, same, includeId), assistantParts(rest, same, includeId))

def modelTurn(parts: List<&2, J()>) -> Maybe<&2, J()>:
  match parts:
    case Nil{}: None{}
    case values: Some{content("model", values)}

def resultTexts(items: List<&2, T.TextImageContent>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> resultTexts(rest)
    case _ <> rest: resultTexts(rest)

def resultImages(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageImage{image} <> rest: inlineData(image) <> resultImages(rest)
    case _ <> rest: resultImages(rest)

def hasImageInput(inputs: List<&2, T.ModelInput>) -> Bool:
  match inputs:
    case Nil{}: False{}
    case T.InputImage{} <> _: True{}
    case _ <> rest: hasImageInput(rest)

def modelImages(model: T.Model<J()>) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, _, _, inputs, _, _, _, _, _, _, _, _}: hasImageInput(inputs)

def responseValue(+text: String, images: Bool) -> String:
  Bool.pick(String, Bool.not(String.is_empty(text)), Unicode.sanitizeSurrogates(text), Bool.pick(String, images, "(see attached image)", ""))

def functionResponse(name: String, id: String, +error: Bool, +value: String, +images: List<&2, J()>, multimodal: Bool, includeId: Bool) -> J():
  +hasImages = Bool.not(List.is_empty(&2, J(), images))
  obj(field("functionResponse", obj(field("name", str(name)) <> field("response", obj(field(Bool.pick(String, error, "error", "output"), str(value)) <> Nil{})) <> List.append(&2, R.Property<J()>, Bool.pick(List<&2, R.Property<J()>>, hasImages && multimodal, field("parts", T.JsonArray{images}) <> Nil{}, Nil{}), Bool.pick(List<&2, R.Property<J()>>, includeId, field("id", str(id)) <> Nil{}, Nil{})))) <> Nil{})

def hasFunctionResponse(parts: List<&2, J()>) -> Bool:
  match parts:
    case Nil{}: False{}
    case T.JsonObject{fields} <> rest: Maybe.is_some(&2, J(), R.get(J(), fields, "functionResponse")) || hasFunctionResponse(rest)
    case _ <> rest: hasFunctionResponse(rest)

def userResponses(role: Maybe<&2, J()>, parts: Maybe<&2, J()>) -> Maybe<&2, List<&2, J()>>:
  match role parts:
    case Some{T.JsonString{"user"}} Some{T.JsonArray{+values}}: Bool.pick(Maybe<&2, List<&2, J()>>, hasFunctionResponse(values), Some{values}, None{})
    case _ _: None{}

def responseTurn(value: J()) -> Maybe<&2, List<&2, J()>>:
  match value:
    case T.JsonObject{+fields}: userResponses(R.get(J(), fields, "role"), R.get(J(), fields, "parts"))
    case _: None{}

def mergedResponse(parts: Maybe<&2, List<&2, J()>>, last: J(), rest: List<&2, J()>, part: J()) -> List<&2, J()>:
  match parts:
    case Some{values}: content("user", List.append(&2, J(), values, part <> Nil{})) <> rest
    case None{}: content("user", part <> Nil{}) <> last <> rest

# Cloud Code Assist requires all function responses in one user turn: a
# response joins the previous turn when it already carries responses.
def appendResponse(reversed: List<&2, J()>, part: J()) -> List<&2, J()>:
  match reversed:
    case Nil{}: content("user", part <> Nil{}) <> Nil{}
    case +last <> rest: mergedResponse(responseTurn(last), last, rest, part)

def toolResult(-D: Data, result: T.ToolResultMessage<D>, +model: T.Model<J()>, reversed: List<&2, J()>) -> List<&2, J()>:
  match result:
    case T.ToolResultMessage{id, name, +items, _, _, error, _}:
      +images = Bool.pick(List<&2, J()>, modelImages(model), resultImages(items), Nil{})
      +hasImages = Bool.not(List.is_empty(&2, J(), images))
      +multimodal = supportsMultimodalFunctionResponse(T.modelId(model))
      +merged = appendResponse(reversed, functionResponse(name, id, error, responseValue(String.join(resultTexts(items), "\n"), hasImages), images, multimodal, requiresToolCallId(T.modelId(model))))
      Bool.pick(List<&2, J()>, hasImages && Bool.not(multimodal), content("user", textPart("Tool result image:") <> images) <> merged, merged)

def sameModel(-G: Data, +message: T.AssistantMessage<V.Value, G>, +model: T.Model<J()>) -> Bool:
  String.eq(T.assistantProvider(V.Value, G, message), T.modelProvider(model)) && String.eq(T.assistantModel(V.Value, G, message), T.modelId(model))

def convertStep(-G: Data, -D: Data, message: T.Message<V.Value, V.Value, G, D>, +model: T.Model<J()>, reversed: List<&2, J()>) -> List<&2, J()>:
  match message:
    case T.User{T.UserMessage{value, _}}: prependOptional(userContent(value), reversed)
    case T.Assistant{+source}: prependOptional(modelTurn(assistantParts(T.assistantContent(V.Value, G, source), sameModel(G, source, model), requiresToolCallId(T.modelId(model)))), reversed)
    case T.ToolResult{result}: toolResult(D, result, model, reversed)
    case T.System{_}: reversed

def convertLoop(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +model: T.Model<J()>, reversed: List<&2, J()>) -> List<&2, J()>:
  match messages:
    case Nil{}: List.reverse(&2, J(), reversed)
    case message <> rest: convertLoop(G, D, rest, model, convertStep(G, D, message, model, reversed))

def within(+code: U32, low: U32, high: U32) -> Bool: U32.is_ge(code, low) && U32.is_le(code, high)

def normalizeChar(+char: Char) -> Char:
  +code = Char.to_u32(char)
  Bool.pick(Char, within(code, 97, 122) || within(code, 65, 90) || within(code, 48, 57) || U32.is_eq(code, 95) || U32.is_eq(code, 45), char, '_')

# `id.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64)` over UTF-16 code units.
def normalizeUnits(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+char, rest}:
      +tail = normalizeUnits(rest)
      Bool.pick(String, U32.is_ge(Char.to_u32(char), 65536), SCon{'_', SCon{'_', tail}}, SCon{normalizeChar(char), tail})

def normalizeId(id: String) -> String:
  String.take(normalizeUnits(id), 64n)

def normalizeInput(-A: Data, -G: Data, -M: Data, unused: Unit, input: Transform.NormalizeToolCallIdInput<A, G, M>) -> IO(Result<&2, &2, Sampling.Error, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, _, _}: IO.pure(Result<&2, &2, Sampling.Error, String>, Done{normalizeId(id)})

def converted(-G: Data, -D: Data, +model: T.Model<J()>, result: Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>>) -> List<&2, J()>:
  match result:
    case Done{messages}: convertLoop(G, D, messages, model, Nil{})
    case Fail{_}: Nil{}

def transformed(~G: Data, ~D: Data, +model: T.Model<J()>, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, normalize: Bool) -> IO(List<&2, J()>):
  match normalize:
    case False{}:
      do IO<List<&2, J()>>:
        result : Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, messages, model, None{})
        return converted(G, D, model, result)
    case True{}:
      do IO<List<&2, J()>>:
        +normalizer : Transform.Normalizer(V.Value, G, J(), Sampling.Error) <- C.create(~Unit, ~Transform.NormalizeToolCallIdInput<V.Value, G, J()>, ~Result<&2, &2, Sampling.Error, String>, ~(normalizeInput(V.Value, G, J())), Unit{})
        result : Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, messages, model, Some{normalizer})
        C.dispose(Transform.NormalizeToolCallIdInput<V.Value, G, J()>, Result<&2, &2, Sampling.Error, String>, normalizer)
        return converted(G, D, model, result)

def contextMessages(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match context:
    case T.TranscriptContext{messages}: messages

# upstream convertMessages: Gemini has no mid-conversation system messages,
# so the transcript is collapsed and its leading prompt removed first.
def convertMessages(~G: Data, ~D: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> IO(List<&2, J()>):
  transformed(~G, ~D, model, Transcript.withoutInitialSystemMessage(V.Value, V.Value, G, D, contextMessages(G, D, Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context))), requiresToolCallId(T.modelId(model)))

# Tools
# -----
def metaDeclaration(+key: String) -> Bool:
  String.eq(key, "$schema") || String.eq(key, "$id") || String.eq(key, "$anchor") || String.eq(key, "$dynamicAnchor") || String.eq(key, "$vocabulary") || String.eq(key, "$comment") || String.eq(key, "$defs") || String.eq(key, "definitions")

def consDeclaration(head: Result<&2, &2, Sampling.Error, J()>, tail: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match head tail:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{item} Done{items}: Done{item <> items}

def wrapped(result: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{items}: Done{Some{T.JsonArray{obj(field("functionDeclarations", T.JsonArray{items}) <> Nil{}) <> Nil{}}}}

# FunctionCallingConfigMode.
def mapToolChoice(choice: String) -> String:
  match choice:
    case "auto": "AUTO"
    case "none": "NONE"
    case "any": "ANY"
    case _: "AUTO"

def strictStep(result: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> Result<&2, &2, Sampling.Error, Bool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Some{True{}}}: Done{True{}}
    case Done{_}: Done{False{}}

# `tools.some(...)`: stops at the first strict tool or error.
def anyStrict(tools: List<&2, T.Tool<V.Value>>, +supportsStrict: Bool, found: Result<&2, &2, Sampling.Error, Bool>) -> Result<&2, &2, Sampling.Error, Bool>:
  match tools found:
    case _ Fail{error}: Fail{error}
    case _ Done{True{}}: Done{True{}}
    case Nil{} Done{False{}}: Done{False{}}
    case tool <> rest Done{False{}}: anyStrict(rest, supportsStrict, strictStep(Sampling.resolveJsonSchemaStrictSampling(tool, supportsStrict)))

def modeFor(choice: Maybe<&2, String>, strict: Result<&2, &2, Sampling.Error, Bool>) -> Result<&2, &2, Sampling.Error, Maybe<&2, String>>:
  match choice strict:
    case Some{"none"} _: Done{Some{"NONE"}}
    case Some{"any"} _: Done{Some{"ANY"}}
    case _ Fail{error}: Fail{error}
    case _ Done{True{}}: Done{Some{"VALIDATED"}}
    case Some{name} Done{False{}}: Done{Some{mapToolChoice(name)}}
    case None{} Done{False{}}: Done{None{}}

# Finish reasons
# --------------
# upstream mapStopReason over the SDK's FinishReason values; an unknown value
# throws.
def mapStopReason(reason: String) -> Result<&2, &2, String, T.StopReason>:
  match reason:
    case "STOP": Done{T.Stop{}}
    case "MAX_TOKENS": Done{T.Length{}}
    case "BLOCKLIST": Done{T.Error{}}
    case "PROHIBITED_CONTENT": Done{T.Error{}}
    case "SPII": Done{T.Error{}}
    case "SAFETY": Done{T.Error{}}
    case "IMAGE_SAFETY": Done{T.Error{}}
    case "IMAGE_PROHIBITED_CONTENT": Done{T.Error{}}
    case "IMAGE_RECITATION": Done{T.Error{}}
    case "IMAGE_OTHER": Done{T.Error{}}
    case "RECITATION": Done{T.Error{}}
    case "FINISH_REASON_UNSPECIFIED": Done{T.Error{}}
    case "OTHER": Done{T.Error{}}
    case "LANGUAGE": Done{T.Error{}}
    case "MALFORMED_FUNCTION_CALL": Done{T.Error{}}
    case "UNEXPECTED_TOOL_CALL": Done{T.Error{}}
    case "TOO_MANY_TOOL_CALLS": Done{T.Error{}}
    case "NO_IMAGE": Done{T.Error{}}
    case other: Fail{"Unhandled stop reason: " ++ other}

# upstream mapStopReasonString, for raw API responses.
def mapStopReasonString(reason: String) -> T.StopReason:
  match reason:
    case "STOP": T.Stop{}
    case "MAX_TOKENS": T.Length{}
    case _: T.Error{}

type Sanitizing is Data:
  Visit{value: V.Value}
  Fields{remaining: List<&2, R.Property<V.Value>>, built: List<&2, R.Property<V.Value>>}
  FieldResult{key: String, remaining: List<&2, R.Property<V.Value>>, built: List<&2, R.Property<V.Value>>}

def withoutMeta(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutMeta(rest)
      Bool.pick(List<&2, R.Property<V.Value>>, metaDeclaration(key), tail, R.Property{key, value} <> tail)

# A finite work stack visits each object once; arrays are kept as they are.
@unsafe

def sanitize(tasks: List<&2, Sanitizing>, completed: V.Value) -> V.Value:
  match tasks:
    case Nil{}: completed
    case Visit{V.ObjectValue{R.Record{fields}}} <> rest: sanitize(Fields{withoutMeta(fields), Nil{}} <> rest, completed)
    case Visit{other} <> rest: sanitize(rest, other)
    case Fields{Nil{}, built} <> rest: sanitize(rest, V.ObjectValue{R.Record{List.reverse(&2, R.Property<V.Value>, built)}})
    case Fields{R.Property{key, value} <> tail, built} <> rest: sanitize(Visit{value} <> FieldResult{key, tail, built} <> rest, completed)
    case FieldResult{key, remaining, built} <> rest: sanitize(Fields{remaining, R.Property{key, completed} <> built} <> rest, V.Null{})

# upstream sanitizeForOpenApi: strip JSON-schema meta declarations from
# objects, recursively through object values.
def sanitizeForOpenApi(schema: V.Value) -> V.Value: sanitize(Visit{schema} <> Nil{}, V.Null{})

def parametersField(useParameters: Bool, parameters: V.Value) -> R.Property<J()>:
  match useParameters:
    case True{}: field("parameters", Schema.toJson(sanitizeForOpenApi(parameters)))
    case False{}: field("parametersJsonSchema", Schema.toJson(parameters))

def declaration(name: String, description: String, parameters: V.Value, useParameters: Bool) -> J():
  obj(field("name", str(name)) <> field("description", str(description)) <> parametersField(useParameters, parameters) <> Nil{})

def declared(tool: T.Tool<V.Value>, useParameters: Bool, parameters: Result<&2, &2, Sampling.Error, V.Value>) -> Result<&2, &2, Sampling.Error, J()>:
  match parameters tool:
    case Fail{error} _: Fail{error}
    case Done{schema} T.Tool{name, description, _, _}: Done{declaration(name, description, schema, useParameters)}

def strictParameters(+tool: T.Tool<V.Value>, useParameters: Bool, strict: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> Result<&2, &2, Sampling.Error, J()>:
  match strict:
    case Fail{error}: Fail{error}
    case Done{selected}: declared(tool, useParameters, Sampling.getJsonSchemaToolParameters(tool, selected))

def declarations(tools: List<&2, T.Tool<V.Value>>, +useParameters: Bool, +supportsStrict: Bool) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match tools:
    case Nil{}: Done{Nil{}}
    case +tool <> rest: consDeclaration(strictParameters(tool, useParameters, Sampling.resolveJsonSchemaStrictSampling(tool, supportsStrict)), declarations(rest, useParameters, supportsStrict))

# upstream convertTools: `parametersJsonSchema` (full JSON Schema) by default,
# or the sanitized OpenAPI `parameters`; no tools means no declarations.
def convertTools(tools: List<&2, T.Tool<V.Value>>, useParameters: Bool, supportsStrict: Bool) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  match tools:
    case Nil{}: Done{None{}}
    case values: wrapped(declarations(values, useParameters, supportsStrict))

# upstream resolveGoogleFunctionCallingMode: explicit none/any win, strict
# JSON-schema tools select VALIDATED, else the mapped choice.
def resolveGoogleFunctionCallingMode(tools: List<&2, T.Tool<V.Value>>, choice: Maybe<&2, String>, supportsStrict: Bool) -> Result<&2, &2, Sampling.Error, Maybe<&2, String>>:
  modeFor(choice, anyStrict(tools, supportsStrict, Done{False{}}))
