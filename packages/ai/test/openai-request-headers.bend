import Base
import ../src/types.bend as T
import ../src/api/openai-client.bend as Client
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-message.bend as H
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as Text

def optionField(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def optionalText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def textOrEmpty(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def headerValue(value: V.Value) -> T.Nullable<String>:
  match value:
    case V.Text{text}: T.PresentValue{text}
    case _: T.NullValue{}

def headerProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, headerValue(value)} <> headerProperties(rest)

def headerLayer(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{fields}}}: Some{R.Record{headerProperties(fields)}}
    case _: None{}

def platformProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{text}} <> rest: R.Property{name, text} <> platformProperties(rest)
    case _ <> rest: platformProperties(rest)

def platformFields(value: Maybe<&2, V.Value>) -> R.Record<String>:
  match value:
    case Some{V.ObjectValue{R.Record{fields}}}: R.Record{platformProperties(fields)}
    case _: R.new(String)

def milliseconds(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

def requestDefaults(+value: V.Value) -> Client.Defaults:
  Client.Defaults{textOrEmpty(optionField(value, "userAgent")), platformFields(optionField(value, "platform")), optionalText(optionField(value, "organization")), optionalText(optionField(value, "project"))}

def wireFields(values: List<&2, H.Header>) -> List<&2, R.Property<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: R.Property{name, V.Text{value}} <> wireFields(rest)

def errorKind(value: Client.HeaderError) -> String:
  match value:
    case Client.TimeoutNotInteger{_}: "timeout-integer"
    case Client.TimeoutNegative{_}: "timeout-negative"
    case Client.TimeoutEncodingFailure{_}: "encoding"
    case Client.HeaderFailure{_}: "header"
    case Client.MissingAuthentication{}: "authentication"

def shown(value: Result<&2, &2, Client.HeaderError, Headers.Headers>) -> V.Value:
  match value:
    case Fail{cause}: V.ObjectValue{R.Record{R.Property{"error", V.Text{errorKind(cause)}} <> Nil{}}}
    case Done{fields}: V.ObjectValue{R.Record{R.Property{"headers", V.ObjectValue{R.Record{wireFields(Headers.entries(fields))}}} <> Nil{}}}

def checked(retries: Nat, input: Result<&2, &2, Parse.ParseError, V.Value>, expected: Result<&2, &2, Parse.ParseError, V.Value>) -> IO(Unit):
  match input expected:
    case Done{+value} Done{reference}:
      actual = shown(Client.buildHeaders(requestDefaults(value), textOrEmpty(optionField(value, "apiKey")), retries, milliseconds(optionField(value, "timeout")), headerLayer(optionField(value, "client")), headerLayer(optionField(value, "body")), headerLayer(optionField(value, "request"))))
      Bool.pick(IO(Unit), V.equal(actual, reference), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "OpenAI request headers mismatch"))
    case _ _: IO.die(Unit, 1, "invalid header fixture JSON")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS OpenAI request headers")
    case retry <> input <> expected <> rest:
      do IO<Unit>:
        checked(U32.to_nat(Text.decimal(retry, 0)), Parse.parse(Text.fromScalars(Text.parseNumbers(input))), Parse.parse(Text.fromScalars(Text.parseNumbers(expected))))
        all(rest)
    case _: IO.die(Unit, 1, "invalid header fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
