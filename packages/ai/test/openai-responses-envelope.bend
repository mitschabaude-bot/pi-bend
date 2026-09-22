import Base
import ../src/types.bend as T
import ../src/api/openai-client.bend as Client
import ../src/utils/schema-json.bend as Convert
import ./openai-request-headers.bend as H
import ./openai-responses-url.bend as U
import ../../runtime/src/url.bend as Absolute
import ../../runtime/src/url.bend as URL
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/string.bend as Split
import ../../runtime/test/utf8-runner.bend as Text
import ../../runtime/src/idna.bend as Domain
import ../../runtime/src/idna.bend as Label
import ../../runtime/src/idna.bend as Mapping
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData

def json(value: Maybe<&2, V.Value>) -> T.JsonValue:
  match value:
    case None{}: T.JsonNull{}
    case Some{value}: Convert.toJson(value)

def payload(mode: String, value: Maybe<&2, V.Value>) -> T.JsonValue:
  match mode:
    case "nan": T.JsonNumber{F.nan()}
    case "infinity": T.JsonNumber{F.infinity(False{})}
    case "negative-infinity": T.JsonNumber{F.infinity(True{})}
    case "nested-nan": T.JsonObject{R.Record{R.Property{"data", T.JsonArray{T.JsonNull{} <> T.JsonNumber{F.nan()} <> Nil{}}} <> Nil{}}}
    case _: json(value)

def client(value: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  match value:
    case None{}: R.new(T.Nullable<String>)
    case Some{fields}: fields

def error(value: Client.RequestError) -> String:
  match value:
    case Client.URLFailure{Client.InvalidURL{_}}: "url"
    case Client.URLFailure{Client.InvalidQuery{cause}}: "query-" ++ U.failure(cause)
    case Client.HeaderRejected{cause}: H.errorKind(cause)
    case Client.NonFinitePayload{}: "nonfinite-payload"
    case Client.PayloadEncodingFailure{}: "payload-encoding"

def shown(result: Result<&2, &2, Client.RequestError, Client.Request>) -> V.Value:
  match result:
    case Fail{cause}: V.ObjectValue{R.Record{R.Property{"error", V.Text{error(cause)}} <> Nil{}}}
    case Done{Client.Request{url, method, headers, body, timeout}}:
      V.ObjectValue{R.Record{R.Property{"url", V.Text{URL.serialize(url, False{})}} <> R.Property{"method", V.Text{method}} <> R.Property{"headers", V.ObjectValue{R.Record{H.wireFields(Headers.entries(headers))}}} <> R.Property{"body", V.Text{body}} <> R.Property{"timeout", V.Number{timeout}} <> Nil{}}}

def checked(context: Absolute.Context, input: Result<&2, &2, Parse.ParseError, V.Value>, expected: Result<&2, &2, Parse.ParseError, V.Value>) -> IO(Unit):
  match input expected:
    case Done{+value} Done{reference}:
      actual = shown(Client.prepareRequest(context, H.requestDefaults(value), H.textOrEmpty(H.optionField(value, "apiKey")), client(H.headerLayer(H.optionField(value, "client"))), H.textOrEmpty(H.optionField(value, "baseUrl")), H.milliseconds(H.optionField(value, "timeout")), payload(H.textOrEmpty(H.optionField(value, "payloadMode")), H.optionField(value, "payload"))))
      Bool.pick(IO(Unit), V.equal(actual, reference), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Responses envelope mismatch"))
    case _ _: IO.die(Unit, 1, "invalid envelope fixture JSON")

def text(input: String) -> String:
  Text.fromScalars(Text.numbers(Split.split(input, ',')))

def cases(args: List<String>, +context: Absolute.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.print("PASS Responses request envelopes")
    case input <> expected <> rest:
      do IO<Unit>:
        checked(context, Parse.parse(text(input)), Parse.parse(text(expected)))
        cases(rest, context)
    case _: IO.die(Unit, 1, "incomplete envelope fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}})
