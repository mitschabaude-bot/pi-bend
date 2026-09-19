import Base
import ../src/utils/error-body.bend as E
import ../src/utils/schema-json.bend as Convert
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as H

def optionalText(value: V.Value) -> Maybe<&2, String>:
  match value:
    case V.Text{text}: Some{text}
    case _: None{}

def optionalStatus(value: V.Value) -> Maybe<&2, F.F64>:
  match value:
    case V.Number{scalar}: Some{scalar}
    case _: None{}

def bodyData(kind: String, value: V.Value) -> E.Body:
  match value:
    case V.Text{+text}: Bool.pick(E.Body, String.eq(kind, "text"), E.TextBody{text}, E.ParsedBody{Convert.toJson(V.Text{text})})
    case other: E.ParsedBody{Convert.toJson(other)}

def bodies(values: List<&2, V.Value>) -> List<&2, E.Body>:
  match values:
    case Nil{}: Nil{}
    case V.ArrayValue{V.Text{kind} <> payload <> Nil{}} <> rest: bodyData(kind, payload) <> bodies(rest)
    case _ <> rest: E.UnavailableBody{} <> bodies(rest)

def textValue(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}

def statusValue(value: Maybe<&2, F.F64>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{scalar}: V.Number{scalar}

def result(norm: E.NormalizedProviderError, formatted: Result<&2, &2, E.NormalizationError, String>) -> V.Value:
  match norm formatted:
    case E.NormalizedProviderError{status, body, message, carries} Done{text}: V.ArrayValue{statusValue(status) <> textValue(body) <> V.Text{message} <> V.Boolean{carries} <> V.Text{text} <> Nil{}}
    case _ _: V.Text{"formatting failed"}

def normalized(value: Result<&2, &2, E.NormalizationError, E.NormalizedProviderError>, prefix: Maybe<&2, String>) -> V.Value:
  match value:
    case Done{+norm}: result(norm, E.formatProviderError(norm, prefix))
    case Fail{_}: V.Text{"normalization failed"}

def run(value: V.Value) -> V.Value:
  match value:
    case V.ArrayValue{V.Text{mode} <> payload <> prefix <> Nil{}}: normalized(E.normalizeValue(Convert.toJson(payload)), optionalText(prefix))
    case V.ArrayValue{status <> V.Text{message} <> V.ArrayValue{sources} <> prefix <> Nil{}}: normalized(E.normalizeProviderError(E.ProviderFailure{optionalStatus(status), message, bodies(sources)}), optionalText(prefix))
    case _: V.Text{"invalid fixture"}

def check(actual: V.Value, expected: V.Value) -> IO(Unit):
  Bool.pick(IO(Unit), V.equal(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "provider error mismatch"))

def parsed(value: Result<&2, &2, Parse.Error, V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{input <> expected <> Nil{}}}: check(run(input), expected)
    case _: IO.die(Unit, 1, "invalid fixture JSON")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS provider errors")
    case head <> rest:
      do IO<Unit>:
        parsed(Parse.parse(H.fromScalars(H.parseNumbers(head))))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
