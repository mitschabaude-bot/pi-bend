import Base
import ../types.bend as T
import ../utils/schema-json.bend as Schema
import ./constrained-sampling.bend as Constrained
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/sanitize-unicode.bend as Unicode
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Google Generative AI request values. Transport details live in the client;
# these are the JSON members accepted by streamGenerateContent.
def J() -> Data: T.JsonValue
def Fields() -> Data: R.Record<J()>
def str(value: String) -> J(): T.JsonString{value}
def obj(fields: Fields()) -> J(): T.JsonObject{fields}
def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}
def add(fields: Fields(), name: String, value: J()) -> Fields(): R.set(J(), fields, name, value)
def maybe(fields: Fields(), name: String, value: Maybe<&2, J()>) -> Fields():
  match value:
    case None{}: fields
    case Some{item}: add(fields, name, item)

# The public onPayload callback sees Google SDK GenerateContentParameters,
# before the SDK separates config fields into HTTP wire members.
def configFields(+fields: Fields(), generation: J()) -> Fields():
  match generation:
    case T.JsonObject{base}:
      +a = maybe(base, "systemInstruction", R.get(J(), fields, "systemInstruction"))
      +b = maybe(a, "tools", R.get(J(), fields, "tools"))
      maybe(b, "toolConfig", R.get(J(), fields, "toolConfig"))
    case _: R.new(J())

def sdkParams(id: String, wire: J()) -> J():
  match wire:
    case T.JsonObject{+fields}:
      +contents = Maybe.default(&2, J(), R.get(J(), fields, "contents"), T.JsonArray{Nil{}})
      +generation = Maybe.default(&2, J(), R.get(J(), fields, "generationConfig"), obj(R.new(J())))
      obj(R.Record{field("model", str(id)) <> field("contents", contents) <> field("config", obj(configFields(fields, generation))) <> Nil{}})
    case _: wire

def wireConfig(fields: Fields()) -> Fields():
  R.remove(J(), R.remove(J(), R.remove(J(), fields, "systemInstruction"), "tools"), "toolConfig")

def sdkWireFields(fields: Fields(), config: J()) -> Fields():
  match config:
    case T.JsonObject{+settings}:
      +base = {R.Record{field("contents", Maybe.default(&2, J(), R.get(J(), fields, "contents"), T.JsonArray{Nil{}})) <> field("generationConfig", obj(wireConfig(settings))) <> Nil{}} : Fields()}
      +a = maybe(base, "systemInstruction", R.get(J(), settings, "systemInstruction"))
      +b = maybe(a, "tools", R.get(J(), settings, "tools"))
      maybe(b, "toolConfig", R.get(J(), settings, "toolConfig"))
    case _: R.Record{field("contents", Maybe.default(&2, J(), R.get(J(), fields, "contents"), T.JsonArray{Nil{}})) <> field("generationConfig", obj(R.new(J()))) <> Nil{}}

def wireFromConfig(fields: Fields(), config: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match config:
    case None{}: None{}
    case Some{settings}: Some{obj(sdkWireFields(fields, settings))}

def wireParams(params: J()) -> Maybe<&2, J()>:
  match params:
    case T.JsonObject{+fields}: wireFromConfig(fields, R.get(J(), fields, "config"))
    case _: None{}

type Thinking is Data:
  NoThinking{}
  DisabledThinking{level: Maybe<&2, String>}
  BudgetThinking{tokens: F64}
  LevelThinking{level: String}

type ToolChoice is Data:
  Auto{}
  Any{}
  NoneChoice{}

type Options is Data:
  Options{maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, thinking: Thinking, toolChoice: Maybe<&2, ToolChoice>}

def optionalNumber(value: Maybe<&2, F64>) -> Maybe<&2, J()>:
  Maybe.map(&2, F64, J(), number => T.JsonNumber{number}, value)

def userPart(part: T.TextImageContent) -> J():
  match part:
    case T.TextImageText{T.TextContent{text, _}}: obj(R.Record{field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{}})
    case T.TextImageImage{T.ImageContent{data, mime}}: obj(R.Record{field("inlineData", obj(R.Record{field("mimeType", str(mime)) <> field("data", str(data)) <> Nil{}})) <> Nil{}})

def userParts(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: userPart(item) <> userParts(rest)

def userContent(value: T.UserContent) -> List<&2, J()>:
  match value:
    case T.UserText{text}: obj(R.Record{field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{}}) <> Nil{}
    case T.UserBlocks{items}: userParts(items)

def content(role: String, parts: List<&2, J()>) -> J():
  obj(R.Record{field("role", str(role)) <> field("parts", T.JsonArray{parts}) <> Nil{}})

def signed(fields: Fields(), signature: Maybe<&2, String>) -> Fields():
  maybe(fields, "thoughtSignature", Maybe.map(&2, String, J(), str, signature))

def validated(value: String, result: Result<&2, &2, Base64.Error, List<&2, U32>>) -> Maybe<&2, String>:
  match result:
    case Done{_}: Some{value}
    case Fail{_}: None{}

def sameSignature(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{+first, +rest}}: validated(SCon{first, rest}, Base64.decode(SCon{first, rest}))
    case _: None{}

def acceptedSignature(sameModel: Bool, value: Maybe<&2, String>) -> Maybe<&2, String>:
  match sameModel:
    case False{}: None{}
    case True{}: sameSignature(value)

def keep(text: String, signature: Maybe<&2, String>) -> Bool:
  Bool.not(String.is_empty(String.trim(text))) || Maybe.is_some(&2, String, signature)

def assistantPart(part: T.AssistantContent<V.Value>, +sameModel: Bool, +includeId: Bool) -> Maybe<&2, J()>:
  match part:
    case T.AssistantText{T.TextContent{+text, value}}:
      +signature = acceptedSignature(sameModel, value)
      Bool.pick(Maybe<&2, J()>, keep(text, signature), Some{obj(signed(R.Record{field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{}}, signature))}, None{})
    case T.AssistantThinking{T.ThinkingContent{+text, value, _}}:
      +signature = acceptedSignature(sameModel, value)
      +plain = {R.Record{field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{}} : Fields()}
      +fields = Bool.pick(Fields(), sameModel, add(plain, "thought", T.JsonBoolean{True{}}), plain)
      Bool.pick(Maybe<&2, J()>, keep(text, signature), Some{obj(signed(fields, signature))}, None{})
    case T.AssistantToolCall{T.ToolCall{id, name, args, signature, _}}:
      +call = {R.Record{field("name", str(name)) <> field("args", Schema.toJson(args)) <> Nil{}} : Fields()}
      +withId = Bool.pick(Fields(), includeId, add(call, "id", str(id)), call)
      Some{obj(signed(R.Record{field("functionCall", obj(withId)) <> Nil{}}, acceptedSignature(sameModel, signature)))}

def optionalCons(value: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def assistantParts(items: List<&2, T.AssistantContent<V.Value>>, +sameModel: Bool, +includeId: Bool) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: optionalCons(assistantPart(item, sameModel, includeId), assistantParts(rest, sameModel, includeId))

def modelId(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def modelProvider(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def supportsThinking(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, enabled, _, _, _, _, _, _, _, _, _, _}: enabled

def sameAssistant(-G: Data, +message: T.AssistantMessage<V.Value, G>, +model: T.Model<T.JsonValue>) -> Bool:
  String.eq(T.assistantModel(V.Value, G, message), modelId(model)) && String.eq(T.assistantProvider(V.Value, G, message), modelProvider(model))

def supportsStrictId(+id: String) -> Bool:
  String.starts_with(id, "gemini-3") || String.starts_with(id, "gemini-4") || String.starts_with(id, "gemini-live-3") || String.starts_with(id, "gemini-live-4")

def supportsStrictMode(model: T.Model<T.JsonValue>) -> Bool:
  supportsStrictId(modelId(model))

def requiresToolId(model: T.Model<T.JsonValue>) -> Bool:
  +id = modelId(model)
  String.starts_with(id, "claude-") || String.starts_with(id, "gpt-oss-") || supportsStrictId(id)

def resultTexts(items: List<&2, T.TextImageContent>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> resultTexts(rest)
    case _ <> rest: resultTexts(rest)

def imageParts(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageImage{T.ImageContent{data, mime}} <> rest:
      obj(R.Record{field("inlineData", obj(R.Record{field("mimeType", str(mime)) <> field("data", str(data)) <> Nil{}})) <> Nil{}}) <> imageParts(rest)
    case _ <> rest: imageParts(rest)

def hasImageInput(inputs: List<&2, T.ModelInput>) -> Bool:
  match inputs:
    case Nil{}: False{}
    case T.InputImage{} <> _: True{}
    case _ <> rest: hasImageInput(rest)

def supportedImages(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, _, _, inputs, _, _, _, _, _, _, _, _}: hasImageInput(inputs)

def multimodalResponse(model: T.Model<T.JsonValue>) -> Bool:
  +id = modelId(model)
  Bool.not(String.starts_with(id, "gemini-2") || String.starts_with(id, "gemini-live-2"))

def responseText(items: List<&2, T.TextImageContent>, hasImages: Bool) -> String:
  +value = String.join(resultTexts(items), "\n")
  Bool.pick(String, Bool.not(String.is_empty(value)), value, Bool.pick(String, hasImages, "(see attached image)", ""))

def imageResultParts(model: T.Model<T.JsonValue>, items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  Bool.pick(List<&2, J()>, supportedImages(model), imageParts(items), Nil{})

def toolResult(-D: Data, result: T.ToolResultMessage<D>, includeId: Bool, +images: List<&2, J()>, multimodal: Bool) -> J():
  match result:
    case T.ToolResultMessage{id, name, +items, _, _, error, _}:
      +value = responseText(items, Bool.not(List.is_empty(&2, J(), images)))
      +response = {obj(R.Record{field(Bool.pick(String, error, "error", "output"), str(Unicode.sanitizeSurrogates(value))) <> Nil{}}) : J()}
      +fields = {R.Record{field("name", str(name)) <> field("response", response) <> Nil{}} : Fields()}
      +withId = Bool.pick(Fields(), includeId, add(fields, "id", str(id)), fields)
      +withImages = Bool.pick(Fields(), multimodal && Bool.not(List.is_empty(&2, J(), images)), add(withId, "parts", T.JsonArray{images}), withId)
      obj(R.Record{field("functionResponse", obj(withImages)) <> Nil{}})

def syntheticImageTurn(images: List<&2, J()>) -> J():
  content("user", obj(R.Record{field("text", str("Tool result image:")) <> Nil{}}) <> images)

def flush(reversed: List<&2, J()>, pending: List<&2, J()>) -> List<&2, J()>:
  match pending:
    case Nil{}: reversed
    case values: content("user", values) <> reversed

def appendedImageResult(-D: Data, result: T.ToolResultMessage<D>, includeId: Bool, +images: List<&2, J()>, reversed: List<&2, J()>, pending: List<&2, J()>) -> List<&2, J()>:
  syntheticImageTurn(images) <> flush(reversed, List.append(&2, J(), pending, toolResult(D, result, includeId, images, False{}) <> Nil{}))

def ordinaryResult(-D: Data, result: T.ToolResultMessage<D>, includeId: Bool, images: List<&2, J()>, multimodal: Bool, pending: List<&2, J()>) -> List<&2, J()>:
  List.append(&2, J(), pending, toolResult(D, result, includeId, images, multimodal) <> Nil{})

def resultItems(-D: Data, result: T.ToolResultMessage<D>) -> List<&2, T.TextImageContent>:
  match result:
    case T.ToolResultMessage{_, _, items, _, _, _, _}: items

def messages(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, values: List<&2, T.Message<V.Value, V.Value, G, D>>, +reversed: List<&2, J()>, +pending: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: List.reverse(&2, J(), flush(reversed, pending))
    case T.System{_} <> rest: messages(G, D, model, rest, flush(reversed, pending), Nil{})
    case T.ToolResult{+result} <> rest:
      +images = imageResultParts(model, resultItems(D, result))
      +multimodal = multimodalResponse(model)
      +legacyImage = Bool.not(multimodal) && Bool.not(List.is_empty(&2, J(), images))
      +nextReversed = Bool.pick(List<&2, J()>, legacyImage, appendedImageResult(D, result, requiresToolId(model), images, reversed, pending), reversed)
      +nextPending = Bool.pick(List<&2, J()>, legacyImage, Nil{}, ordinaryResult(D, result, requiresToolId(model), images, multimodal, pending))
      messages(G, D, model, rest, nextReversed, nextPending)
    case T.User{T.UserMessage{value, _}} <> rest:
      +parts = userContent(value)
      +next = Bool.pick(List<&2, J()>, List.is_empty(&2, J(), parts), flush(reversed, pending), content("user", parts) <> flush(reversed, pending))
      messages(G, D, model, rest, next, Nil{})
    case T.Assistant{+assistant} <> rest:
      +parts = assistantParts(T.assistantContent(V.Value, G, assistant), sameAssistant(G, assistant, model), requiresToolId(model))
      +next = Bool.pick(List<&2, J()>, List.is_empty(&2, J(), parts), flush(reversed, pending), content("model", parts) <> flush(reversed, pending))
      messages(G, D, model, rest, next, Nil{})

def dropInitial(-G: Data, -D: Data, values: List<&2, T.Message<V.Value, V.Value, G, D>>) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match values:
    case T.System{_} <> rest: rest
    case other: other

type ToolEntry is Data:
  ToolEntry{declaration: J(), strict: Bool}

type ToolList is Data:
  ToolList{declarations: List<&2, J()>, strict: Bool}

def isStrict(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{True{}}: True{}
    case _: False{}

def declared(name: String, description: String, strict: Bool, result: Result<&2, &2, Constrained.Error, V.Value>) -> Result<&2, &2, Constrained.Error, ToolEntry>:
  match result:
    case Fail{error}: Fail{error}
    case Done{schema}:
      Done{ToolEntry{obj(R.Record{field("name", str(name)) <> field("description", str(description)) <> field("parametersJsonSchema", Schema.toJson(schema)) <> Nil{}}), strict}}

def selectedToolWith(+tool: T.Tool<V.Value>, +strict: Maybe<&2, Bool>) -> Result<&2, &2, Constrained.Error, ToolEntry>:
  match tool:
    case T.Tool{name, description, _, _}: declared(name, description, isStrict(strict), Constrained.getJsonSchemaToolParameters(tool, strict))

def selectedTool(tool: T.Tool<V.Value>, result: Result<&2, &2, Constrained.Error, Maybe<&2, Bool>>) -> Result<&2, &2, Constrained.Error, ToolEntry>:
  match result:
    case Fail{error}: Fail{error}
    case Done{strict}: selectedToolWith(tool, strict)

def checkedTool(+tool: T.Tool<V.Value>, supportsStrict: Bool) -> Result<&2, &2, Constrained.Error, ToolEntry>:
  selectedTool(tool, Constrained.resolveJsonSchemaStrictSampling(tool, supportsStrict))

def prependTool(head: Result<&2, &2, Constrained.Error, ToolEntry>, tail: Result<&2, &2, Constrained.Error, ToolList>) -> Result<&2, &2, Constrained.Error, ToolList>:
  match head tail:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{ToolEntry{item, strict}} Done{ToolList{items, later}}: Done{ToolList{item <> items, strict || later}}

def tools(values: List<&2, T.Tool<V.Value>>, +supportsStrict: Bool) -> Result<&2, &2, Constrained.Error, ToolList>:
  match values:
    case Nil{}: Done{ToolList{Nil{}, False{}}}
    case value <> rest: prependTool(checkedTool(value, supportsStrict), tools(rest, supportsStrict))

def callingMode(choice: Maybe<&2, ToolChoice>, strict: Bool) -> Maybe<&2, String>:
  match choice:
    case Some{NoneChoice{}}: Some{"NONE"}
    case Some{Any{}}: Some{"ANY"}
    case Some{Auto{}}: Some{Bool.pick(String, strict, "VALIDATED", "AUTO")}
    case None{}: Bool.pick(Maybe<&2, String>, strict, Some{"VALIDATED"}, None{})

def callingConfig(value: Maybe<&2, String>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{selected}: Some{obj(R.Record{field("functionCallingConfig", obj(R.Record{field("mode", str(selected)) <> Nil{}})) <> Nil{}})}

def toolConfig(choice: Maybe<&2, ToolChoice>, hasTools: Bool, strict: Bool) -> Maybe<&2, J()>:
  match hasTools:
    case False{}: None{}
    case True{}: callingConfig(callingMode(choice, strict))

def toolDeclarations(values: List<&2, J()>) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case list: Some{T.JsonArray{obj(R.Record{field("functionDeclarations", T.JsonArray{list}) <> Nil{}}) <> Nil{}}}

def thinking(value: Thinking) -> Maybe<&2, J()>:
  match value:
    case NoThinking{}: None{}
    case DisabledThinking{None{}}: Some{obj(R.Record{field("thinkingBudget", T.JsonNumber{F.fromU32(0)}) <> Nil{}})}
    case DisabledThinking{Some{level}}: Some{obj(R.Record{field("thinkingLevel", str(level)) <> Nil{}})}
    case BudgetThinking{tokens}: Some{obj(R.Record{field("includeThoughts", T.JsonBoolean{True{}}) <> field("thinkingBudget", T.JsonNumber{tokens}) <> Nil{}})}
    case LevelThinking{level}: Some{obj(R.Record{field("includeThoughts", T.JsonBoolean{True{}}) <> field("thinkingLevel", str(level)) <> Nil{}})}

def systemFrom(value: Maybe<&2, T.SystemMessage<V.Value>>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{message}:
      +value = Text.renderComplete(V.Value, message)
      Bool.pick(Maybe<&2, J()>, String.is_empty(value), None{}, Some{obj(R.Record{field("parts", T.JsonArray{obj(R.Record{field("text", str(Unicode.sanitizeSurrogates(value))) <> Nil{}}) <> Nil{}}) <> field("role", str("user")) <> Nil{}})})

def system(-G: Data, -D: Data, values: List<&2, T.Message<V.Value, V.Value, G, D>>) -> Maybe<&2, J()>:
  systemFrom(Transcript.getInitialSystemMessage(V.Value, V.Value, G, D, values))

def config(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options, canThink: Bool) -> J():
  match context options:
    case T.TranscriptContext{values} Options{maximum, temperature, thought, choice}:
      +currentTools = Transcript.getCurrentTools(V.Value, V.Value, G, D, values)
      +fields = {R.Record{Nil{}} : Fields()}
      +a = maybe(fields, "maxOutputTokens", optionalNumber(maximum))
      +b = maybe(a, "temperature", optionalNumber(temperature))
      obj(maybe(b, "thinkingConfig", Bool.pick(Maybe<&2, J()>, canThink, thinking(thought), None{})))

def selectedChoice(value: Options) -> Maybe<&2, ToolChoice>:
  match value:
    case Options{_, _, _, choice}: choice

def withDeclaredTools(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, +values: List<&2, T.Message<V.Value, V.Value, G, D>>, +options: Options, declaration: Result<&2, &2, Constrained.Error, ToolList>) -> Result<&2, &2, Constrained.Error, J()>:
  match declaration:
    case Fail{error}: Fail{error}
    case Done{ToolList{+items, strict}}:
      +base = {R.Record{field("contents", T.JsonArray{messages(G, D, model, dropInitial(G, D, values), Nil{}, Nil{})}) <> field("generationConfig", config(G, D, T.TranscriptContext{values}, options, supportsThinking(model))) <> Nil{}} : Fields()}
      +a = maybe(base, "systemInstruction", system(G, D, values))
      +b = maybe(a, "tools", toolDeclarations(items))
      Done{obj(maybe(b, "toolConfig", toolConfig(selectedChoice(options), Bool.not(List.is_empty(&2, J(), items)), strict)))}

def buildNormalized(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options) -> Result<&2, &2, Constrained.Error, J()>:
  match context:
    case T.TranscriptContext{+values}:
      +currentTools = Transcript.getCurrentTools(V.Value, V.Value, G, D, values)
      withDeclaredTools(G, D, model, values, options, tools(currentTools, supportsStrictMode(model)))

def buildParams(-G: Data, -D: Data, model: T.Model<T.JsonValue>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options) -> Result<&2, &2, Constrained.Error, J()>:
  buildNormalized(G, D, model, Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context), options)
