import Base
import ../src/api/openai-responses.bend as Request
import ../src/api/constrained-sampling.bend as Sampling
import ../src/types.bend as T
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/test/utf8-runner.bend as H
import ./json-value-data.bend as Data
import ./openai-responses-policy-runner.bend as P

def model(compat: Maybe<&2, T.OpenAIResponsesCompat>) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"target", "Target", T.OpenAIResponsesApi{}, "openai", "https://example.test", True{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, compat}

def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"input", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"input"} <> Nil{}}} <> Nil{}}}

def tool(name: String, grammar: Bool) -> T.Tool<V.Value>:
  T.Tool{name, "A tool", schema(), Bool.pick(Maybe<&2, T.ToolConstrainedSampling>, grammar, Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{Some{"start: /[a-z]+/"}, None{}}}}}, None{})}

def Messages() -> Data: List<&2, T.Message<V.Value, R.Record<V.Value>, Unit, Unit>>

def later(mode: U32) -> Messages():
  match mode:
    case 2: T.System{T.SystemMessage{T.SystemText{"updated"}, None{}, Some{tool("later", False{}) <> Nil{}}, None{}, F.fromU32(2)}} <> T.User{T.UserMessage{T.UserText{"again"}, F.fromU32(3)}} <> Nil{}
    case 3: T.System{T.SystemMessage{T.SystemText{"updated"}, None{}, None{}, Some{T.ToolReference{"tool"} <> Nil{}}, F.fromU32(2)}} <> Nil{}
    case 4: T.System{T.SystemMessage{T.SystemText{"updated"}, None{}, Some{T.Tool{"tool", "Redefined", schema(), None{}} <> Nil{}}, None{}, F.fromU32(2)}} <> Nil{}
    case _: Nil{}

def context(+mode: U32) -> T.TranscriptContext<V.Value, R.Record<V.Value>, Unit, Unit>:
  tools = Bool.pick(Maybe<&2, List<&2, T.Tool<V.Value>>>, U32.is_eq(mode, 0), None{}, Some{tool("tool", U32.is_eq(mode, 5)) <> Nil{}})
  T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{"initial"}, None{}, tools, None{}, F.fromU32(1)}} <> T.User{T.UserMessage{T.UserText{"hello"}, F.fromU32(1)}} <> later(mode)}

def settings() -> Request.OpenAIResponsesOptions<Unit, Unit, Unit>:
  Request.fromStreamOptions(Unit, Unit, Unit, T.StreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(0)}, None{}, Some{F.fromU32(1)}, None{}, None{}, Some{"session"}, None{}, None{}}, Request.ResponsesSettings{Some{T.High{}}, Some{T.PresentValue{Request.SummaryConcise{}}}, Some{T.PresentValue{Request.TierPriority{}}}, Some{T.JsonString{"required"}}})

def identity(value: T.JsonValue) -> T.JsonValue: value

def output(value: Result<&2, &2, Request.BuildError, T.JsonValue>) -> V.Value:
  match value:
    case Done{value}: V.ObjectValue{R.Record{R.Property{"output", Data.project(value)} <> Nil{}}}
    case Fail{Request.ToolConversion{error}}: V.ObjectValue{R.Record{R.Property{"error", V.Text{Sampling.errorMessage(error)}} <> Nil{}}}
    case Fail{Request.MessageConversion{_}}: V.Text{"message conversion failed"}

def check(actual: V.Value, expected: Result<&2, &2, Parse.Error, V.Value>) -> IO(Unit):
  match expected:
    case Done{value}: Bool.pick(IO(Unit), V.equal(actual, value), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Responses request mismatch"))
    case _: IO.die(Unit, 1, "invalid expected JSON")

def run(mode: String, +flags: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, Request.BuildError, T.JsonValue> <- Request.buildParams(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, model(P.compat(String.split(flags, '.'))), context(H.decimal(mode, 0)), settings(), Request.getCompat("openai", "https://example.test", P.compat(String.split(flags, '.'))), R.new(String), T.CacheLong{})
    check(output(result), Parse.parse(H.fromScalars(H.parseNumbers(expected))))

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS Responses request")
    case mode <> flags <> expected <> rest:
      do IO<Unit>:
        run(mode, flags, expected)
        all(rest)
    case _: IO.die(Unit, 1, "invalid request fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
