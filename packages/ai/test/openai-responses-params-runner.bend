import Base
import ../src/api/openai-responses-params.bend as Params
import ../src/api/openai-responses-policy.bend as Policy
import ../src/types.bend as T
import ../src/utils/schema-json.bend as Convert
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as H
import ./json-value-data.bend as Data
import ./openai-responses-policy-runner.bend as P

def field(value: V.Value, key: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case _: None{}

def scalar(value: Maybe<&2, V.Value>) -> Maybe<&2, F.F64>:
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

def options(+value: V.Value) -> Params.RequestOptions<T.JsonValue>:
  Params.RequestOptions{scalar(field(value, "maxTokens")), scalar(field(value, "temperature")), nullableString(field(value, "serviceTier")), choice(field(value, "toolChoice")), effort(field(value, "reasoningEffort")), nullableString(field(value, "reasoningSummary")), stringValue(field(value, "sessionId")), sampling(field(value, "samplingParams"))}

def jsonItems(values: List<&2, V.Value>) -> List<&2, T.JsonValue>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: Convert.toJson(head) <> jsonItems(rest)

def identity(value: T.JsonValue) -> T.JsonValue: value

def check(value: V.Value) -> IO(Unit):
  match value:
    case V.ArrayValue{V.Text{id} <> V.Text{+provider} <> V.Boolean{reasoning} <> mappingValue <> settings <> V.Text{flags} <> V.Text{retention} <> V.ArrayValue{input} <> V.ArrayValue{tools} <> expected <> Nil{}}:
      model = {Params.RequestModel{id, provider, reasoning, mapping(Some{mappingValue})} : Params.RequestModel}
      compat = Policy.getCompat(provider, "", P.compat(String.split(flags, '.')))
      actual = Params.buildConvertedParams(~T.JsonValue, ~identity, model, jsonItems(input), jsonItems(tools), options(settings), compat, Policy.resolveCacheRetentionValue(P.retention(retention), None{}))
      Bool.pick(IO(Unit), V.equal(Data.project(actual), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Responses params mismatch"))
    case _: IO.die(Unit, 1, "invalid params fixture")

def parsed(value: Result<&2, &2, Parse.Error, V.Value>) -> IO(Unit):
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
