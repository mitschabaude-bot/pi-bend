import Base
import ../src/types.bend as T
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as Convert
import ../src/utils/json.bend as Wire
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ../src/api/google-generative-ai.bend as Google
import ../src/api/google-shared.bend as Shared
import ../src/providers/google.models.bend as Catalog
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-message.bend as Http
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/url.bend as URL
import ../../runtime/test/utf8-runner.bend as Text

# Differential cases for tests/google_generative_ai_check.py: each argument is
# one JSON case (as comma-separated code points); each result line is "R "
# and the encoded JSON the pinned TypeScript reference also produces: the
# captured SDK parameters, the wire request, or the streamed message and
# events.
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

def findModel(models: List<&2, T.Model<J()>>, +id: String) -> Maybe<&2, T.Model<J()>>:
  match models:
    case Nil{}: None{}
    case +first <> rest: Bool.pick(Maybe<&2, T.Model<J()>>, String.eq(T.modelId(first), id), Some{first}, findModel(rest, id))

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
    case None{}: A.zeroCost()

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

def decodedMessage(value: MessageJson.Decoded(T.Message<V.Value, V.Value, Unit, Unit>), rest: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>) -> List<&2, T.Message<V.Value, V.Value, Unit, Unit>>:
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

def nullableProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, nullable(value)} <> nullableProperties(rest)

def headers(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{nullableProperties(values)}}
    case _: None{}

def budgets(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingBudgets>:
  match value:
    case Some{+levels}: Some{T.ThinkingBudgets{number(field(levels, "minimal")), number(field(levels, "low")), number(field(levels, "medium")), number(field(levels, "high"))}}
    case None{}: None{}

# Results
# -------
def jsonText(value: J()) -> String: Maybe.default(&2, String, Wire.stringify(value), "null")

def headerProperties(values: List<&2, Http.Header>) -> List<&2, R.Property<J()>>:
  match values:
    case Nil{}: Nil{}
    case Http.Header{name, value} <> rest: R.Property{String.to_lower(name), T.JsonString{value}} <> headerProperties(rest)

def request(value: Maybe<&2, Fetch.Input<Unit>>) -> J():
  match value:
    case Some{Fetch.Input{url, method, headers, Http.Text{body}, _}}: A.obj(A.prop("url", T.JsonString{URL.serialize(url, False{})}) <> A.prop("method", T.JsonString{method}) <> A.prop("headers", T.JsonObject{R.Record{headerProperties(Http.entries(headers))}}) <> A.prop("body", T.JsonString{body}) <> Nil{})
    case _: T.JsonNull{}

# Context
# -------
def noDiagnostics(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no diagnostic details"}}

def noDetails(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no tool details"}}

def messages(values: List<&2, V.Value>) -> List<&2, T.Message<V.Value, V.Value, Unit, Unit>>:
  match values:
    case Nil{}: Nil{}
    case +first <> rest: decodedMessage(MessageJson.decodeMessage(~Unit, ~Unit, ~noDiagnostics, ~noDetails, first), messages(rest))

def contextOf(+value: V.Value) -> H.Context():
  H.contextWith(text(field(value, "systemPrompt")), messages(list(field(value, "messages"))), tools(field(value, "tools")))

# Models
# ------
def findIn(models: List<&2, T.Model<J()>>, value: Maybe<&2, V.Value>) -> Maybe<&2, T.Model<J()>>:
  match value:
    case Some{V.Text{id}}: findModel(models, id)
    case _: None{}

def custom(+value: V.Value) -> T.Model<J()>:
  +id = Maybe.default(&2, String, text(field(value, "id")), "custom")
  T.Model{id, Maybe.default(&2, String, text(field(value, "name")), id), T.GoogleGenerativeAiApi{}, Maybe.default(&2, String, text(field(value, "provider")), "custom"), Maybe.default(&2, String, text(field(value, "baseUrl")), "https://example.invalid/v1beta"), Maybe.default(&2, Bool, flag(field(value, "reasoning")), True{}), levels(field(value, "thinkingLevelMap")), inputs(list(field(value, "input"))), None{}, cost(field(value, "cost")), None{}, Maybe.default(&2, F64, number(field(value, "contextWindow")), F.fromU32(128000)), Maybe.default(&2, F64, number(field(value, "maxTokens")), F.fromU32(8192)), None{}, strings(field(value, "headers")), None{}}

def modelFrom(entry: Maybe<&2, T.Model<J()>>, +value: V.Value) -> T.Model<J()>:
  match entry:
    case Some{model}: model
    case None{}: custom(Maybe.default(&2, V.Value, field(value, "custom"), V.Null{}))

def modelOf(+value: V.Value) -> T.Model<J()>: modelFrom(findIn(Catalog.GOOGLE_MODELS(), field(value, "catalog")), value)

# Options
# -------
def simpleChoice(value: Maybe<&2, String>) -> Maybe<&2, T.ToolChoice>:
  match value:
    case Some{"auto"}: Some{T.AutoTool{}}
    case Some{"none"}: Some{T.NoTool{}}
    case _: None{}

def simple(+value: V.Value) -> H.Simple():
  T.SimpleStreamOptions{None{}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), None{}, None{}, None{}, number(field(value, "temperature")), None{}, number(field(value, "maxTokens")), None{}, None{}, None{}, None{}, None{}, simpleChoice(text(field(value, "toolChoice"))), thinking(text(field(value, "reasoning"))), None{}, budgets(field(value, "thinkingBudgets"))}

def googleLevel(value: Maybe<&2, String>) -> Maybe<&2, Shared.GoogleApiThinkingLevel>:
  match value:
    case Some{"THINKING_LEVEL_UNSPECIFIED"}: Some{Shared.ThinkingLevelUnspecified{}}
    case Some{"MINIMAL"}: Some{Shared.MinimalLevel{}}
    case Some{"LOW"}: Some{Shared.LowLevel{}}
    case Some{"MEDIUM"}: Some{Shared.MediumLevel{}}
    case Some{"HIGH"}: Some{Shared.HighLevel{}}
    case _: None{}

def googleThinking(value: Maybe<&2, V.Value>) -> Maybe<&2, Google.GoogleThinking>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{Google.GoogleThinking{Maybe.default(&2, Bool, flag(R.get(V.Value, fields, "enabled")), False{}), number(R.get(V.Value, fields, "budgetTokens")), googleLevel(text(R.get(V.Value, fields, "level")))}}
    case _: None{}

def direct(+value: V.Value) -> H.Options():
  Google.GoogleOptions{T.StreamOptions{None{}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), None{}, None{}, None{}, number(field(value, "temperature")), None{}, number(field(value, "maxTokens")), None{}, None{}, None{}, None{}, None{}}, text(field(value, "toolChoice")), googleThinking(field(value, "thinking"))}

def entryOptions(entry: Maybe<&2, String>, +model: T.Model<J()>, +context: H.Context(), +selected: V.Value) -> Result<&2, &2, String, H.Options()>:
  match entry:
    case Some{"simple"}: H.fromSimple(model, context, simple(selected))
    case _: Done{direct(selected)}

def optionsOf(+model: T.Model<J()>, +context: H.Context(), +value: V.Value) -> Result<&2, &2, String, H.Options()>:
  entryOptions(text(field(value, "entry")), model, context, Maybe.default(&2, V.Value, field(value, "options"), V.ObjectValue{R.new(V.Value)}))

# Results
# -------
def unitDetails(value: Unit) -> V.Value: V.Null{}

def events(values: List<&2, H.Event()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case event <> rest: Convert.toJson(MessageJson.assistantMessageEvent(~Unit, ~unitDetails, event)) <> events(rest)

def response(outcome: H.Outcome) -> J():
  match outcome:
    case H.Outcome{message, _, _, emitted}: A.obj(A.prop("message", Convert.toJson(MessageJson.assistantMessage(~Unit, ~unitDetails, message))) <> A.prop("events", T.JsonArray{events(emitted)}) <> Nil{})

def modeNamed(name: Maybe<&2, String>, body: Maybe<&2, String>) -> H.Mode:
  match name:
    case Some{"request"}: H.Send{}
    case Some{"response"}: H.Respond{Maybe.default(&2, String, body, "") <> Nil{}}
    case _: H.Capture{}

def modeOf(+value: V.Value) -> H.Mode: modeNamed(text(field(value, "mode")), text(field(value, "body")))

def payloadResult(outcome: H.Outcome) -> J():
  match outcome:
    case H.Outcome{_, Some{payload}, _, _}: payload
    case H.Outcome{message, None{}, _, _}: A.obj(A.prop("error", T.JsonString{Maybe.default(&2, String, H.errorMessage(message), "")}) <> Nil{})

def requestResult(outcome: H.Outcome) -> J():
  match outcome:
    case H.Outcome{message, _, None{}, _}: A.obj(A.prop("error", T.JsonString{Maybe.default(&2, String, H.errorMessage(message), "")}) <> Nil{})
    case H.Outcome{_, _, recorded, _}: request(recorded)

def resultOf(mode: H.Mode, outcome: H.Outcome) -> J():
  match mode:
    case H.Capture{}: payloadResult(outcome)
    case H.Send{}: requestResult(outcome)
    case _: response(outcome)

# A streamSimple that throws before a stream exists reports `thrown`.
def selectedCase(+model: T.Model<J()>, +context: H.Context(), selected: Result<&2, &2, String, H.Options()>, +mode: H.Mode) -> IO(Unit):
  match selected:
    case Fail{message}: IO.print("R " ++ Text.showText(jsonText(A.obj(A.prop("thrown", T.JsonString{message}) <> Nil{}))))
    case Done{options}:
      do IO<Unit>:
        outcome : H.Outcome <- H.run(model, context, options, mode)
        IO.print("R " ++ Text.showText(jsonText(resultOf(mode, outcome))))

def runCase(+value: V.Value) -> IO(Unit):
  +model = modelOf(Maybe.default(&2, V.Value, field(value, "model"), V.Null{}))
  +context = contextOf(value)
  +mode = modeOf(value)
  selectedCase(model, context, optionsOf(model, context, value), mode)

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
