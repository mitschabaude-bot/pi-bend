import Base
import ../types.bend as T
import ../utils/schema-json.bend as Schema
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

def requiresToolId(model: T.Model<T.JsonValue>) -> Bool:
  +id = modelId(model)
  String.contains(id, "gemini-3") || String.contains(id, "gemini-4")

def resultTexts(items: List<&2, T.TextImageContent>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> resultTexts(rest)
    case _ <> rest: resultTexts(rest)

def toolResult(-D: Data, result: T.ToolResultMessage<D>, includeId: Bool) -> J():
  match result:
    case T.ToolResultMessage{id, name, items, _, _, error, _}:
      +value = String.join(resultTexts(items), "\n")
      +response = {obj(R.Record{field(Bool.pick(String, error, "error", "output"), str(Unicode.sanitizeSurrogates(value))) <> Nil{}}) : J()}
      +fields = {R.Record{field("name", str(name)) <> field("response", response) <> Nil{}} : Fields()}
      obj(R.Record{field("functionResponse", obj(Bool.pick(Fields(), includeId, add(fields, "id", str(id)), fields))) <> Nil{}})

def flush(reversed: List<&2, J()>, pending: List<&2, J()>) -> List<&2, J()>:
  match pending:
    case Nil{}: reversed
    case values: content("user", values) <> reversed

def messages(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, values: List<&2, T.Message<V.Value, V.Value, G, D>>, +reversed: List<&2, J()>, +pending: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: List.reverse(&2, J(), flush(reversed, pending))
    case T.System{_} <> rest: messages(G, D, model, rest, flush(reversed, pending), Nil{})
    case T.ToolResult{result} <> rest: messages(G, D, model, rest, reversed, List.append(&2, J(), pending, toolResult(D, result, requiresToolId(model)) <> Nil{}))
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

def tool(tool: T.Tool<V.Value>) -> J():
  match tool:
    case T.Tool{name, description, schema, _}:
      obj(R.Record{field("name", str(name)) <> field("description", str(description)) <> field("parametersJsonSchema", Schema.toJson(schema)) <> Nil{}})

def tools(values: List<&2, T.Tool<V.Value>>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: tool(value) <> tools(rest)

def mode(value: ToolChoice) -> String:
  match value:
    case Auto{}: "AUTO"
    case Any{}: "ANY"
    case NoneChoice{}: "NONE"

def toolConfig(choice: Maybe<&2, ToolChoice>, hasTools: Bool) -> Maybe<&2, J()>:
  match choice hasTools:
    case Some{selected} True{}: Some{obj(R.Record{field("functionCallingConfig", obj(R.Record{field("mode", str(mode(selected))) <> Nil{}})) <> Nil{}})}
    case _ _: None{}

def toolDeclarations(values: List<&2, T.Tool<V.Value>>) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case list: Some{T.JsonArray{obj(R.Record{field("functionDeclarations", T.JsonArray{tools(list)}) <> Nil{}}) <> Nil{}}}

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

def buildNormalized(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options) -> J():
  match context:
    case T.TranscriptContext{+values}:
      +currentTools = Transcript.getCurrentTools(V.Value, V.Value, G, D, values)
      +base = {R.Record{field("contents", T.JsonArray{messages(G, D, model, dropInitial(G, D, values), Nil{}, Nil{})}) <> field("generationConfig", config(G, D, T.TranscriptContext{values}, options, supportsThinking(model))) <> Nil{}} : Fields()}
      +a = maybe(base, "systemInstruction", system(G, D, values))
      +b = maybe(a, "tools", toolDeclarations(currentTools))
      obj(maybe(b, "toolConfig", toolConfig(selectedChoice(options), Bool.not(List.is_empty(&2, T.Tool<V.Value>, currentTools)))))

def buildParams(-G: Data, -D: Data, model: T.Model<T.JsonValue>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options) -> J():
  buildNormalized(G, D, model, Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context), options)
