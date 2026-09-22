import Base
import ../src/types.bend as T
import ../src/api/openai-responses.bend as Prepare
import ../src/api/constrained-sampling.bend as Sampling
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Parse
import ../../runtime/test/utf8-runner.bend as H
import ./openai-responses-request.bend as Fixture
import ./openai-responses-policy-runner.bend as P
import ./json-value-data.bend as Data

def prepareModel(provider: String, compat: Maybe<&2, T.OpenAIResponsesCompat>) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"target", "Target", T.OpenAIResponsesApi{}, provider, "https://example.test", True{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, Some{R.Record{R.Property{"User-Agent", "model-agent"} <> R.Property{"authorization", "model-only"} <> Nil{}}}, compat}

def callerHeaders(scenario: U32) -> Maybe<&2, T.ProviderHeaders()>:
  match scenario:
    case 2: Some{R.Record{R.Property{"Authorization", T.PresentValue{"Bearer custom"}} <> Nil{}}}
    case 3: Some{R.Record{R.Property{"CF-AIG-AUTHORIZATION", T.PresentValue{"gateway"}} <> Nil{}}}
    case 5: Some{R.Record{R.Property{"Authorization", T.PresentValue{" \t"}} <> Nil{}}}
    case 6: Some{R.Record{R.Property{"User-Agent", T.PresentValue{"caller-agent"}} <> R.Property{"session_id", T.NullValue{}} <> R.Property{"x-client-request-id", T.PresentValue{"override"}} <> Nil{}}}
    case _: None{}

def callerKey(scenario: U32) -> Maybe<&2, String>:
  match scenario:
    case 1: None{}
    case 2: None{}
    case 3: Some{""}
    case 4: None{}
    case 5: None{}
    case _: Some{"fixture-key"}

def callerRetention(scenario: U32) -> Maybe<&2, T.CacheRetention>:
  match scenario:
    case 7: Some{T.CacheNone{}}
    case 8: None{}
    case 9: Some{T.CacheShort{}}
    case 10: None{}
    case _: Some{T.CacheLong{}}

def callerEnvironment(scenario: U32) -> Maybe<&2, T.ProviderEnv()>:
  match scenario:
    case 10: None{}
    case _: Some{R.Record{R.Property{"PI_CACHE_RETENTION", "long"} <> Nil{}}}

def preparedTier(scenario: U32) -> Maybe<&2, T.Nullable<Prepare.ServiceTier>>:
  match scenario:
    case 11: Some{T.NullValue{}}
    case 12: Some{T.PresentValue{Prepare.TierAuto{}}}
    case 13: Some{T.PresentValue{Prepare.TierDefault{}}}
    case 14: Some{T.PresentValue{Prepare.TierFlex{}}}
    case 15: Some{T.PresentValue{Prepare.TierScale{}}}
    case _: Some{T.PresentValue{Prepare.TierPriority{}}}

def prepareOptions(+scenario: U32) -> Prepare.OpenAIResponsesOptions<Unit, Unit, Unit>:
  Prepare.fromStreamOptions(Unit, Unit, Unit, T.StreamOptions{None{}, None{}, callerKey(scenario), None{}, callerEnvironment(scenario), None{}, None{}, callerHeaders(scenario), None{}, None{}, None{}, Some{F.fromU32(0)}, None{}, Some{F.fromU32(1)}, None{}, callerRetention(scenario), Some{"session"}, None{}, None{}}, Prepare.ResponsesSettings{Some{T.High{}}, Some{T.PresentValue{Prepare.SummaryConcise{}}}, preparedTier(scenario), Some{T.JsonString{"required"}}})

def nullableHeader(value: T.Nullable<String>) -> V.Value:
  match value:
    case T.NullValue{}: V.Null{}
    case T.PresentValue{text}: V.Text{text}

def headerProperties(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, nullableHeader(value)} <> headerProperties(rest)

def headersValue(values: T.ProviderHeaders()) -> V.Value:
  match values:
    case R.Record{entries}: V.ObjectValue{R.Record{headerProperties(entries)}}

def stringProperties(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, V.Text{value}} <> stringProperties(rest)

def stringsValue(values: R.Record<String>) -> V.Value:
  match values:
    case R.Record{entries}: V.ObjectValue{R.Record{stringProperties(entries)}}

def preparationError(cause: Prepare.PreparationError) -> String:
  match cause:
    case Prepare.MissingApiKey{provider}: "No API key for provider: " ++ provider
    case Prepare.MissingAccountId{}: "Failed to extract accountId from token"
    case Prepare.GrammarFailure{error}: Sampling.errorMessage(error)
    case Prepare.PayloadFailure{_}: "payload conversion failed"
    case Prepare.UnsupportedApi{_}: "unsupported API"

def preparationValue(result: Result<&2, &2, Prepare.PreparationError, Prepare.Prepared>) -> V.Value:
  match result:
    case Fail{cause}: V.ObjectValue{R.Record{R.Property{"error", V.Text{preparationError(cause)}} <> Nil{}}}
    case Done{Prepare.Prepared{apiKey, baseUrl, headers, payload, compat, declarations, retention, _, _, _}}:
      V.ObjectValue{R.Record{R.Property{"apiKey", V.Text{apiKey}} <> R.Property{"baseUrl", V.Text{baseUrl}} <> R.Property{"headers", headersValue(headers)} <> R.Property{"payload", Data.project(payload)} <> R.Property{"compat", V.Text{P.showCompat(compat)}} <> R.Property{"grammar", stringsValue(declarations)} <> R.Property{"retention", V.Text{P.showRetention(retention)}} <> Nil{}}}

def prepareCase(mode: String, flags: String, scenario: String, provider: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    actual : Result<&2, &2, Prepare.PreparationError, Prepare.Prepared> <- Prepare.prepare(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, prepareModel(provider, P.compat(String.split(flags, '.'))), Fixture.context(H.decimal(mode, 0)), prepareOptions(H.decimal(scenario, 0)), "test-agent")
    Fixture.check(preparationValue(actual), Parse.parse(H.fromScalars(H.parseNumbers(expected))))

def prepareAll(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS Responses preparation")
    case mode <> flags <> scenario <> provider <> expected <> rest:
      do IO<Unit>:
        prepareCase(mode, flags, scenario, provider, expected)
        prepareAll(rest)
    case _: IO.die(Unit, 1, "invalid preparation fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    prepareAll(arguments)
