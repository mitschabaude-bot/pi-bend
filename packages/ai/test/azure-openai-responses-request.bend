import Base
import ../src/types.bend as T
import ../src/api/azure-openai-responses.bend as Azure
import ../src/api/openai-client.bend as Client
import ../src/api/openai-responses.bend as Responses
import ../src/providers/azure-openai-responses.models.bend as Catalog
import ../src/utils/schema-json.bend as Convert
import ./openai-request-headers.bend as H
import ./openai-responses-request.bend as Fixture
import ./openai-responses-policy-runner.bend as P
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as Domain
import ../../runtime/src/idna.bend as Label
import ../../runtime/src/idna.bend as Mapping
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/string.bend as Split
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/url.bend as URL
import ../../runtime/test/utf8-runner.bend as Text

# Azure request preparation and the SDK envelope versus upstream `stream`
# with a capturing fetch (tests/azure_openai_responses_check.py). Each case
# names a catalog model, its overrides, a Responses fixture context and the
# stream options; the result is the request or the preparation error.

def Options() -> Data: Azure.AzureOpenAIResponsesOptions<Unit, Unit, Unit>

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>: H.optionField(value, name)

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>: H.optionalText(value)

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>: H.milliseconds(value)

def json(value: Maybe<&2, V.Value>) -> Maybe<&2, T.JsonValue>:
  Maybe.map(&2, V.Value, T.JsonValue, Convert.toJson, value)

def properties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> properties(rest)
    case _ <> rest: properties(rest)

def strings(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{properties(values)}}
    case _: None{}

def jsonProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.JsonValue>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Convert.toJson(value)} <> jsonProperties(rest)

def jsonRecord(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{jsonProperties(values)}}
    case _: None{}

def level(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{T.Minimal{}}
    case Some{"low"}: Some{T.Low{}}
    case Some{"medium"}: Some{T.Medium{}}
    case Some{"high"}: Some{T.High{}}
    case Some{"xhigh"}: Some{T.XHigh{}}
    case Some{"max"}: Some{T.Max{}}
    case _: None{}

def summary(value: Maybe<&2, V.Value>) -> Maybe<&2, T.Nullable<Responses.ReasoningSummary>>:
  match value:
    case Some{V.Null{}}: Some{T.NullValue{}}
    case Some{V.Text{"auto"}}: Some{T.PresentValue{Responses.SummaryAuto{}}}
    case Some{V.Text{"detailed"}}: Some{T.PresentValue{Responses.SummaryDetailed{}}}
    case Some{V.Text{"concise"}}: Some{T.PresentValue{Responses.SummaryConcise{}}}
    case _: None{}

def options(+value: V.Value) -> Options():
  base = {T.StreamOptions{None{}, None{}, text(field(value, "apiKey")), None{}, strings(field(value, "env")), None{}, None{}, H.headerLayer(field(value, "headers")), number(field(value, "timeoutMs")), None{}, None{}, number(field(value, "temperature")), jsonRecord(field(value, "samplingParams")), number(field(value, "maxTokens")), None{}, None{}, text(field(value, "sessionId")), None{}, None{}} : Responses.StreamOptions(Unit, Unit, Unit)}
  Azure.AzureOpenAIResponsesOptions{base, level(text(field(value, "reasoningEffort"))), json(field(value, "toolChoice")), summary(field(value, "reasoningSummary")), text(field(value, "azureApiVersion")), text(field(value, "azureResourceName")), text(field(value, "azureBaseUrl")), text(field(value, "azureDeploymentName"))}

def find(models: List<&2, T.Model<T.JsonValue>>, +id: String) -> Maybe<&2, T.Model<T.JsonValue>>:
  match models:
    case Nil{}: None{}
    case T.Model{+name, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o} <> rest: Bool.pick(Maybe<&2, T.Model<T.JsonValue>>, String.eq(name, id), Some{T.Model{name, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o}}, find(rest, id))

def compat(value: Maybe<&2, String>, original: Maybe<&2, T.OpenAIResponsesCompat>) -> Maybe<&2, T.OpenAIResponsesCompat>:
  match value:
    case None{}: original
    case Some{flags}: P.compat(String.split(flags, '.'))

# Azure catalog models carry OpenAI Responses compatibility.
def withOverrides(model: T.Model<T.JsonValue>, +value: V.Value) -> T.Model<T.JsonValue>:
  match model:
    case T.Model{id, name, T.AzureOpenAIResponsesApi{}, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, original}:
      T.Model{id, name, T.AzureOpenAIResponsesApi{}, provider, Maybe.default(&2, String, text(field(value, "baseUrl")), baseUrl), reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, Maybe.or(&2, R.Record<String>, strings(field(value, "modelHeaders")), headers), compat(text(field(value, "compat")), original)}
    case other: other

def modeOf(value: Result<&2, &2, F.Error, Nat>) -> U32:
  match value:
    case Done{index}: U32.from_nat(index)
    case Fail{_}: 0

def mode(value: Maybe<&2, F64>) -> U32:
  match value:
    case Some{scalar}: modeOf(F.convert(scalar))
    case None{}: 0

def config(+value: V.Value, urls: URL.Context) -> Responses.Config:
  Responses.Config{urls, H.requestDefaults(value), Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def errorValue(message: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"error", V.Text{message}} <> Nil{}}}

def requestError(error: Client.RequestError) -> String:
  match error:
    case Client.URLFailure{_}: "url"
    case Client.HeaderRejected{cause}: H.errorKind(cause)
    case Client.NonFinitePayload{}: "nonfinite-payload"
    case Client.PayloadEncodingFailure{}: "payload-encoding"

def shown(result: Result<&2, &2, Client.RequestError, Client.Request>) -> V.Value:
  match result:
    case Fail{cause}: errorValue(requestError(cause))
    case Done{Client.Request{url, _, headers, body, _}}:
      V.ObjectValue{R.Record{R.Property{"url", V.Text{URL.serialize(url, False{})}} <> R.Property{"headers", V.ObjectValue{R.Record{H.wireFields(Headers.entries(headers))}}} <> R.Property{"body", V.Text{body}} <> Nil{}}}

def envelope(configuration: Responses.Config, timeout: Maybe<&2, F64>, result: Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>) -> V.Value:
  match result:
    case Fail{cause}: errorValue(Responses.describePreparation(cause))
    case Done{Responses.ProviderRequest{apiKey, baseUrl, headers, +payload, target, processing}}:
      shown(Responses.envelope(configuration, Responses.ProviderRequest{apiKey, baseUrl, headers, payload, target, processing}, timeout, payload))

def run(+value: V.Value, +urls: URL.Context, model: T.Model<T.JsonValue>, expected: V.Value) -> IO(Unit):
  do IO<Unit>:
    +configuration : Responses.Config = config(value, urls)
    result : Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest> <- Azure.prepare(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, urls, H.textOrEmpty(field(value, "userAgent")), withOverrides(model, value), Fixture.context(mode(number(field(value, "mode")))), options(value))
    actual : V.Value = envelope(configuration, number(field(value, "timeoutMs")), result)
    Bool.pick(IO(Unit), V.equal(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Azure request mismatch"))

def found(value: V.Value, urls: URL.Context, reference: V.Value, model: Maybe<&2, T.Model<T.JsonValue>>) -> IO(Unit):
  match model:
    case None{}: IO.die(Unit, 1, "unknown catalog model")
    case Some{selected}: run(value, urls, selected, reference)

def checked(urls: URL.Context, input: Result<&2, &2, Parse.ParseError, V.Value>, expected: Result<&2, &2, Parse.ParseError, V.Value>) -> IO(Unit):
  match input expected:
    case Done{+value} Done{reference}: found(value, urls, reference, find(Catalog.AZURE_OPENAI_RESPONSES_MODELS(), Maybe.default(&2, String, text(field(value, "modelId")), "")))
    case _ _: IO.die(Unit, 1, "invalid Azure fixture JSON")

def decoded(input: String) -> String:
  Text.fromScalars(Text.numbers(Split.split(input, ',')))

def cases(args: List<String>, +urls: URL.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.print("PASS Azure OpenAI Responses requests")
    case input <> expected <> rest:
      do IO<Unit>:
        checked(urls, Parse.parse(decoded(input)), Parse.parse(decoded(expected)))
        cases(rest, urls)
    case _: IO.die(Unit, 1, "incomplete Azure fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}})
