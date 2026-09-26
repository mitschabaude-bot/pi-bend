import Base
import ../src/api/anthropic-messages.bend as Messages
import ../src/api/anthropic-messages-client.bend as Client
import ../src/api/anthropic-messages-stream.bend as Fold
import ../src/providers/anthropic.models.bend as Anthropic
import ../src/providers/github-copilot.models.bend as Copilot
import ../src/providers/kimi-coding.models.bend as Kimi
import ../src/providers/openrouter.models.bend as OpenRouter
import ../src/providers/fireworks.models.bend as Fireworks
import ../src/providers/vercel-ai-gateway.models.bend as Vercel
import ../src/types.bend as T
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as Convert
import ../src/utils/json.bend as Wire
import ./anthropic-harness.bend as H
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-message.bend as Http
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/url.bend as URL
import ../../runtime/test/utf8-runner.bend as Text

# Differential cases for tests/anthropic_messages_check.py: each argument is
# one JSON case (as comma-separated code points); each result line is
# "R " and the encoded JSON the pinned TypeScript reference also produces:
# the captured params, the wire request, or the streamed message and events.
def J() -> Data: T.JsonValue

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def flag(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{item}}: Some{item}
    case _: None{}

def list(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def properties(value: Maybe<&2, V.Value>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: values
    case _: Nil{}

# Catalog
# -------
def catalog(+provider: String) -> List<&2, T.Model<J()>>:
  match provider:
    case "anthropic": Anthropic.ANTHROPIC_MODELS()
    case "github-copilot": Copilot.GITHUB_COPILOT_MODELS()
    case "kimi-coding": Kimi.KIMI_CODING_MODELS()
    case "openrouter": OpenRouter.OPENROUTER_MODELS()
    case "fireworks": Fireworks.FIREWORKS_MODELS()
    case "vercel-ai-gateway": Vercel.VERCEL_AI_GATEWAY_MODELS()
    case _: Nil{}

def findModel(models: List<&2, T.Model<J()>>, +id: String) -> Maybe<&2, T.Model<J()>>:
  match models:
    case Nil{}: None{}
    case +first <> rest: Bool.pick(Maybe<&2, T.Model<J()>>, String.eq(T.modelId(first), id), Some{first}, findModel(rest, id))

def catalogEntry(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Model<J()>>:
  match value:
    case Some{V.ArrayValue{V.Text{provider} <> V.Text{id} <> Nil{}}}: findModel(catalog(provider), id)
    case _: None{}

def affinity(value: Maybe<&2, V.Value>) -> Maybe<&2, T.AnthropicSessionAffinityFormat>:
  match value:
    case Some{V.Text{"openrouter"}}: Some{T.AnthropicOpenRouterSession{}}
    case _: None{}

def level(+name: String) -> Maybe<&2, T.ModelThinkingLevel>:
  match name:
    case "off": Some{T.Off{}}
    case "minimal": Some{T.Thinking{T.Minimal{}}}
    case "low": Some{T.Thinking{T.Low{}}}
    case "medium": Some{T.Thinking{T.Medium{}}}
    case "high": Some{T.Thinking{T.High{}}}
    case "xhigh": Some{T.Thinking{T.XHigh{}}}
    case "max": Some{T.Thinking{T.Max{}}}
    case _: None{}

def nullable(value: V.Value) -> T.Nullable<String>:
  match value:
    case V.Text{item}: T.PresentValue{item}
    case _: T.NullValue{}

def mapping(name: Maybe<&2, T.ModelThinkingLevel>, value: V.Value, rest: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match name:
    case Some{selected}: T.ThinkingLevelMapping{selected, Some{nullable(value)}} <> rest
    case None{}: rest

def mappings(values: List<&2, R.Property<V.Value>>) -> List<&2, T.ThinkingLevelMapping>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: mapping(level(name), value, mappings(rest))

def levels(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{T.ThinkingLevelMap{mappings(values)}}
    case _: None{}

def input(value: V.Value) -> Maybe<&2, T.ModelInput>:
  match value:
    case V.Text{"text"}: Some{T.InputText{}}
    case V.Text{"image"}: Some{T.InputImage{}}
    case _: None{}

def cost(value: Maybe<&2, V.Value>) -> T.ModelCost:
  match value:
    case Some{+prices}: T.ModelCost{Maybe.default(&2, F64, number(field(prices, "input")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "output")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "cacheRead")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "cacheWrite")), F.fromU32(0)), None{}}
    case None{}: H.zeroCost()

def fallback(+value: V.Value) -> T.AnthropicAllowedFallbackModel:
  T.AnthropicAllowedFallbackModel{Maybe.default(&2, String, text(field(value, "provider")), ""), Maybe.default(&2, String, text(field(value, "model")), ""), cost(field(value, "cost"))}

def fallbacks(values: List<&2, V.Value>) -> List<&2, T.AnthropicAllowedFallbackModel>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: fallback(value) <> fallbacks(rest)

def optionalFallbacks(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.AnthropicAllowedFallbackModel>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{fallbacks(values)}
    case _: None{}

def compat(+value: V.Value) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{flag(field(value, "supportsEagerToolInputStreaming")), flag(field(value, "supportsLongCacheRetention")), flag(field(value, "sendSessionAffinityHeaders")), affinity(field(value, "sessionAffinityFormat")), flag(field(value, "supportsCacheControlOnTools")), flag(field(value, "supportsTemperature")), flag(field(value, "forceAdaptiveThinking")), flag(field(value, "allowEmptySignature")), flag(field(value, "supportsStrictTools")), flag(field(value, "supportsMidConvoEffort")), flag(field(value, "supportsMidConvoSystemMessages")), flag(field(value, "supportsMidConvoToolChanges")), optionalFallbacks(field(value, "allowedFallbackModels"))}

def prependInput(value: Maybe<&2, T.ModelInput>, rest: List<&2, T.ModelInput>) -> List<&2, T.ModelInput>:
  match value:
    case Some{item}: item <> rest
    case None{}: rest

def inputList(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prependInput(input(value), inputList(rest))

def inputs(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: T.InputText{} <> Nil{}
    case _: inputList(values)

def stringProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> stringProperties(rest)
    case _ <> rest: stringProperties(rest)

def strings(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{stringProperties(values)}}
    case _: None{}

def withCompat(model: T.Model<J()>, value: Maybe<&2, V.Value>) -> T.Model<J()>:
  match value:
    case None{}: model
    case Some{selected}: H.withCompat(model, compat(selected))

def decodedMessage(value: MessageJson.Decoded(T.Message<V.Value, V.Value, H.Diagnostics(), Unit>), rest: List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>) -> List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>:
  match value:
    case Done{message}: message <> rest
    case Fail{_}: rest

def decodedTool(value: MessageJson.Decoded(T.Tool<V.Value>), rest: List<&2, T.Tool<V.Value>>) -> List<&2, T.Tool<V.Value>>:
  match value:
    case Done{tool}: tool <> rest
    case Fail{_}: rest

def toolList(values: List<&2, V.Value>) -> List<&2, T.Tool<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: decodedTool(MessageJson.decodeTool(first), toolList(rest))

def tools(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.Tool<V.Value>>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{toolList(values)}
    case _: None{}

# Options
# -------
def thinking(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{T.Minimal{}}
    case Some{"low"}: Some{T.Low{}}
    case Some{"medium"}: Some{T.Medium{}}
    case Some{"high"}: Some{T.High{}}
    case Some{"xhigh"}: Some{T.XHigh{}}
    case Some{"max"}: Some{T.Max{}}
    case _: None{}

def retention(value: Maybe<&2, String>) -> Maybe<&2, T.CacheRetention>:
  match value:
    case Some{"none"}: Some{T.CacheNone{}}
    case Some{"short"}: Some{T.CacheShort{}}
    case Some{"long"}: Some{T.CacheLong{}}
    case _: None{}

def nullableProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, nullable(value)} <> nullableProperties(rest)

def headers(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{nullableProperties(values)}}
    case _: None{}

def optionalCompat(value: Maybe<&2, V.Value>) -> Maybe<&2, T.AnthropicMessagesCompat>:
  match value:
    case Some{selected}: Some{compat(selected)}
    case None{}: None{}

def custom(+value: V.Value) -> T.Model<J()>:
  +id = Maybe.default(&2, String, text(field(value, "id")), "custom")
  T.Model{id, Maybe.default(&2, String, text(field(value, "name")), id), T.AnthropicMessagesApi{}, Maybe.default(&2, String, text(field(value, "provider")), "custom"), Maybe.default(&2, String, text(field(value, "baseUrl")), "http://127.0.0.1:9"), Maybe.default(&2, Bool, flag(field(value, "reasoning")), False{}), levels(field(value, "thinkingLevelMap")), inputs(list(field(value, "input"))), None{}, cost(field(value, "cost")), None{}, Maybe.default(&2, F64, number(field(value, "contextWindow")), F.fromU32(200000)), Maybe.default(&2, F64, number(field(value, "maxTokens")), F.fromU32(32000)), None{}, strings(field(value, "headers")), optionalCompat(field(value, "compat"))}

def modelFrom(entry: Maybe<&2, T.Model<J()>>, +value: V.Value) -> T.Model<J()>:
  match entry:
    case Some{model}: withCompat(model, field(value, "compat"))
    case None{}: custom(Maybe.default(&2, V.Value, field(value, "custom"), V.Null{}))

def modelOf(+value: V.Value) -> T.Model<J()>: modelFrom(catalogEntry(field(value, "catalog")), value)

def jsonProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<J()>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Convert.toJson(value)} <> jsonProperties(rest)

def jsonRecord(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<J()>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{jsonProperties(values)}}
    case _: None{}

def simpleChoice(value: Maybe<&2, String>) -> Maybe<&2, T.ToolChoice>:
  match value:
    case Some{"auto"}: Some{T.AutoTool{}}
    case Some{"none"}: Some{T.NoTool{}}
    case _: None{}

def budgets(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingBudgets>:
  match value:
    case Some{+levels}: Some{T.ThinkingBudgets{number(field(levels, "minimal")), number(field(levels, "low")), number(field(levels, "medium")), number(field(levels, "high"))}}
    case None{}: None{}

def base(+value: V.Value) -> T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>:
  T.StreamOptions{None{}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), None{}, None{}, None{}, number(field(value, "temperature")), None{}, number(field(value, "maxTokens")), None{}, retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), None{}, jsonRecord(field(value, "metadata"))}

def simple(+value: V.Value) -> H.Simple():
  T.SimpleStreamOptions{None{}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), None{}, None{}, None{}, number(field(value, "temperature")), None{}, number(field(value, "maxTokens")), None{}, retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), None{}, jsonRecord(field(value, "metadata")), simpleChoice(text(field(value, "toolChoice"))), thinking(text(field(value, "reasoning"))), None{}, budgets(field(value, "thinkingBudgets"))}

def display(value: Maybe<&2, String>) -> Maybe<&2, Messages.AnthropicThinkingDisplay>:
  match value:
    case Some{"summarized"}: Some{Messages.Summarized{}}
    case Some{"omitted"}: Some{Messages.Omitted{}}
    case _: None{}

def toolNamed(value: Maybe<&2, String>) -> Maybe<&2, Messages.AnthropicToolChoice>:
  match value:
    case Some{name}: Some{Messages.ChoiceTool{name}}
    case None{}: None{}

def namedChoice(value: V.Value) -> Maybe<&2, Messages.AnthropicToolChoice>: toolNamed(text(field(value, "name")))

def choice(value: Maybe<&2, V.Value>) -> Maybe<&2, Messages.AnthropicToolChoice>:
  match value:
    case Some{V.Text{"auto"}}: Some{Messages.ChoiceAuto{}}
    case Some{V.Text{"any"}}: Some{Messages.ChoiceAny{}}
    case Some{V.Text{"none"}}: Some{Messages.ChoiceNone{}}
    case Some{other}: namedChoice(other)
    case None{}: None{}

def direct(+value: V.Value) -> H.Options():
  Messages.AnthropicOptions{base(value), flag(field(value, "thinkingEnabled")), number(field(value, "thinkingBudgetTokens")), text(field(value, "effort")), display(text(field(value, "thinkingDisplay"))), flag(field(value, "interleavedThinking")), choice(field(value, "toolChoice")), None{}}

def entryOptions(entry: Maybe<&2, String>, +model: T.Model<J()>, +context: H.Context(), +selected: V.Value) -> H.Options():
  match entry:
    case Some{"simple"}: H.fromSimple(model, context, simple(selected))
    case _: direct(selected)

def optionsOf(+model: T.Model<J()>, +context: H.Context(), +value: V.Value) -> H.Options():
  entryOptions(text(field(value, "entry")), model, context, Maybe.default(&2, V.Value, field(value, "options"), V.ObjectValue{R.new(V.Value)}))

# Results
# -------
def jsonText(value: J()) -> String: Maybe.default(&2, String, Wire.stringify(value), "null")

def headerProperties(values: List<&2, Http.Header>) -> List<&2, R.Property<J()>>:
  match values:
    case Nil{}: Nil{}
    case Http.Header{name, value} <> rest: R.Property{String.to_lower(name), T.JsonString{value}} <> headerProperties(rest)

def request(value: Maybe<&2, Fetch.Input<Unit>>) -> J():
  match value:
    case Some{Fetch.Input{url, method, headers, Http.Text{body}, _}}: H.obj(H.prop("url", T.JsonString{URL.serialize(url, False{})}) <> H.prop("method", T.JsonString{method}) <> H.prop("headers", T.JsonObject{R.Record{headerProperties(Http.entries(headers))}}) <> H.prop("body", T.JsonString{body}) <> Nil{})
    case _: T.JsonNull{}

def optionalText(name: String, value: Maybe<&2, String>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{item}: R.Property{name, V.Text{item}} <> rest
    case None{}: rest

def transformations(values: List<&2, Fold.InputTransformation>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case Fold.InputTransformation{kind, path, reason} <> rest: V.ObjectValue{R.Record{optionalText("type", kind, optionalText("path", path, optionalText("reason", reason, Nil{})))}} <> transformations(rest)

def details(values: List<&2, Fold.InputTransformation>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"transformations", V.ArrayValue{transformations(values)}} <> Nil{}}}

# Context
# -------
def noDiagnostics(value: V.Value) -> MessageJson.Decoded(H.Diagnostics()):
  Fail{Decode.WrongType{Nil{}, "no diagnostic details"}}

def noDetails(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no tool details"}}

def messages(values: List<&2, V.Value>) -> List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>:
  match values:
    case Nil{}: Nil{}
    case +first <> rest: decodedMessage(MessageJson.decodeMessage(~H.Diagnostics(), ~Unit, ~noDiagnostics, ~noDetails, first), messages(rest))

def contextOf(+value: V.Value) -> H.Context():
  H.contextWith(text(field(value, "systemPrompt")), messages(list(field(value, "messages"))), tools(field(value, "tools")))

def events(values: List<&2, H.Event()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case event <> rest: Convert.toJson(MessageJson.assistantMessageEvent(~H.Diagnostics(), ~details, event)) <> events(rest)

def response(outcome: H.Outcome) -> J():
  match outcome:
    case H.Outcome{message, _, _, _, emitted}: H.obj(H.prop("message", Convert.toJson(MessageJson.assistantMessage(~H.Diagnostics(), ~details, message))) <> H.prop("events", T.JsonArray{events(emitted)}) <> Nil{})

def modeNamed(name: Maybe<&2, String>, body: Maybe<&2, String>) -> H.Mode:
  match name:
    case Some{"request"}: H.Send{}
    case Some{"response"}: H.Respond{Maybe.default(&2, String, body, "") <> Nil{}}
    case _: H.Capture{}

def modeOf(+value: V.Value) -> H.Mode: modeNamed(text(field(value, "mode")), text(field(value, "body")))

def payloadResult(outcome: H.Outcome) -> J():
  match outcome:
    case H.Outcome{message, Some{payload}, _, _, _}: payload
    case H.Outcome{message, None{}, _, _, _}: H.obj(H.prop("error", T.JsonString{Maybe.default(&2, String, H.errorMessage(message), "")}) <> Nil{})

def resultOf(mode: H.Mode, outcome: H.Outcome) -> J():
  match mode:
    case H.Capture{}: payloadResult(outcome)
    case H.Send{}: request(H.requestOf(outcome))
    case _: response(outcome)

def runCase(+value: V.Value) -> IO(Unit):
  +model = modelOf(Maybe.default(&2, V.Value, field(value, "model"), V.Null{}))
  +context = contextOf(value)
  +mode = modeOf(value)
  do IO<Unit>:
    outcome : H.Outcome <- H.run(model, context, optionsOf(model, context, value), mode)
    IO.print("R " ++ Text.showText(jsonText(resultOf(mode, outcome))))

def parsed(value: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{item}: runCase(item)
    case Fail{_}: IO.print("R " ++ Text.showText("{\"error\":\"invalid case\"}"))

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        parsed(Decode.parse(Text.fromScalars(Text.parseNumbers(value))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
