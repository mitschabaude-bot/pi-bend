import Base
import ../src/api/openai-responses.bend as P
import ../src/types.bend as T
import ../src/utils/schema-json.bend as Convert
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as H
import ./json-value-data.bend as Data
import ./openai-responses-policy-runner.bend as Policy

def field(value: V.Value, key: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case _: None{}

def scalar(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{scalar}}: Some{scalar}
    case _: None{}

def stringValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def nullableString(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Nullable<String>>:
  match value:
    case Some{V.Null{}}: Some{T.NullValue{}}
    case Some{V.Text{text}}: Some{T.PresentValue{text}}
    case _: None{}

def effort(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevel>:
  match value:
    case Some{V.Text{"minimal"}}: Some{T.Minimal{}}
    case Some{V.Text{"low"}}: Some{T.Low{}}
    case Some{V.Text{"medium"}}: Some{T.Medium{}}
    case Some{V.Text{"high"}}: Some{T.High{}}
    case Some{V.Text{"xhigh"}}: Some{T.XHigh{}}
    case Some{V.Text{"max"}}: Some{T.Max{}}
    case _: None{}

def summary(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Nullable<P.ReasoningSummary>>:
  match value:
    case Some{V.Null{}}: Some{T.NullValue{}}
    case Some{V.Text{"auto"}}: Some{T.PresentValue{P.SummaryAuto{}}}
    case Some{V.Text{"detailed"}}: Some{T.PresentValue{P.SummaryDetailed{}}}
    case Some{V.Text{"concise"}}: Some{T.PresentValue{P.SummaryConcise{}}}
    case _: None{}

def tier(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Nullable<P.ServiceTier>>:
  match value:
    case Some{V.Null{}}: Some{T.NullValue{}}
    case Some{V.Text{"auto"}}: Some{T.PresentValue{P.TierAuto{}}}
    case Some{V.Text{"default"}}: Some{T.PresentValue{P.TierDefault{}}}
    case Some{V.Text{"flex"}}: Some{T.PresentValue{P.TierFlex{}}}
    case Some{V.Text{"scale"}}: Some{T.PresentValue{P.TierScale{}}}
    case Some{V.Text{"priority"}}: Some{T.PresentValue{P.TierPriority{}}}
    case _: None{}

def mapping(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{+fields}: Some{T.ThinkingLevelMap{T.ThinkingLevelMapping{T.Off{}, nullableString(field(fields, "off"))} <> T.ThinkingLevelMapping{T.Thinking{T.Minimal{}}, nullableString(field(fields, "minimal"))} <> T.ThinkingLevelMapping{T.Thinking{T.Low{}}, nullableString(field(fields, "low"))} <> T.ThinkingLevelMapping{T.Thinking{T.Medium{}}, nullableString(field(fields, "medium"))} <> T.ThinkingLevelMapping{T.Thinking{T.High{}}, nullableString(field(fields, "high"))} <> T.ThinkingLevelMapping{T.Thinking{T.XHigh{}}, nullableString(field(fields, "xhigh"))} <> T.ThinkingLevelMapping{T.Thinking{T.Max{}}, nullableString(field(fields, "max"))} <> Nil{}}}
    case _: None{}

def choice(value: Maybe<&2, V.Value>) -> Maybe<&2, T.JsonValue>:
  match value:
    case None{}: None{}
    case Some{value}: Some{Convert.toJson(value)}

def samplingEntries(values: List<&2, R.Property<V.Value>>) -> R.Record<T.JsonValue>:
  match values:
    case Nil{}: R.new(T.JsonValue)
    case R.Property{key, value} <> rest: R.set(T.JsonValue, samplingEntries(rest), key, Convert.toJson(value))

def sampling(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{samplingEntries(R.entries(V.Value, fields))}
    case _: None{}

def Options() -> Data: P.OpenAIResponsesOptions<Unit, Unit, Unit>

def options(+value: V.Value) -> Options():
  P.fromStreamOptions(Unit, Unit, Unit, T.StreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, scalar(field(value, "temperature")), sampling(field(value, "samplingParams")), scalar(field(value, "maxTokens")), None{}, None{}, stringValue(field(value, "sessionId")), None{}, None{}}, P.ResponsesSettings{effort(field(value, "reasoningEffort")), summary(field(value, "reasoningSummary")), tier(field(value, "serviceTier")), choice(field(value, "toolChoice"))})

def model(id: String, provider: String, reasoning: Bool, thinking: Maybe<&2, T.ThinkingLevelMap>) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{id, "Test", T.OpenAIResponsesApi{}, provider, "", reasoning, thinking, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def jsonItems(values: List<&2, V.Value>) -> List<&2, T.JsonValue>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: Convert.toJson(head) <> jsonItems(rest)

def check(value: V.Value) -> IO(Unit):
  match value:
    case V.ArrayValue{V.Text{id} <> V.Text{+provider} <> V.Boolean{reasoning} <> mappingValue <> settings <> V.Text{flags} <> V.Text{retention} <> V.ArrayValue{input} <> V.ArrayValue{tools} <> expected <> Nil{}}:
      compat = P.getCompat(provider, "", Policy.compat(String.split(flags, '.')))
      actual = P.assembledParams(Unit, Unit, Unit, model(id, provider, reasoning, mapping(Some{mappingValue})), jsonItems(input), jsonItems(tools), options(settings), compat, P.resolveCacheRetentionValue(Policy.retention(retention), None{}))
      Bool.pick(IO(Unit), V.equal(Data.project(actual), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Responses params mismatch"))
    case _: IO.die(Unit, 1, "invalid params fixture")

def parsed(value: Result<&2, &2, Parse.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{value}: check(value)
    case _: IO.die(Unit, 1, "invalid params JSON")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS Responses params")
    case head <> rest:
      do IO<Unit>:
        parsed(Parse.parse(H.fromScalars(H.parseNumbers(head))))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
