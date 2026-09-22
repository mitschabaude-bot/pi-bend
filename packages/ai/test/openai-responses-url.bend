import Base
import ../src/api/openai-client.bend as Client
import ../../runtime/src/url.bend as Absolute
import ../../runtime/src/url.bend as Strict
import ../../runtime/src/url.bend as Form
import ../../runtime/src/url.bend as URL
import ../../runtime/src/url.bend as Serialize
import ../../runtime/src/url.bend as Encode
import ../../runtime/src/idna.bend as Domain
import ../../runtime/src/idna.bend as Label
import ../../runtime/src/idna.bend as Mapping
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../../runtime/src/string.bend as Split
import ../../runtime/test/utf8-runner.bend as Text

def index(value: Nat) -> U32:
  match value:
    case Zero{}: 0
    case Succ{rest}: (1 + index(rest) : U32)

def failure(cause: Strict.FormStrictError) -> String:
  match cause:
    case Strict.InvalidName{field}: "name:" ++ U32.show(index(field))
    case Strict.InvalidValue{field}: "value:" ++ U32.show(index(field))

def entries(tuples: List<&2, Form.Entry>) -> String:
  match tuples:
    case Nil{}: ""
    case Form.Entry{name, value} <> rest: Text.showText(name) ++ ":" ++ Text.showText(value) ++ "/" ++ entries(rest)

def form(result: Result<&2, &2, Strict.FormStrictError, List<&2, Form.Entry>>) -> String:
  match result:
    case Fail{cause}: failure(cause)
    case Done{tuples}: "+" ++ entries(tuples)

def url(result: Result<&2, &2, Client.URLError, URL.URL>) -> String:
  match result:
    case Fail{Client.InvalidURL{_}}: "invalid-url"
    case Fail{Client.InvalidQuery{cause}}: failure(cause)
    case Done{value}: "+" ++ Text.showText(Serialize.serialize(value, False{}))

def dispatch(context: Absolute.Context, kind: Char, text: String) -> String:
  match kind:
    case 'f': form(Strict.parseFormStrict(text))
    case 'q': form(Strict.queryFormStrict(text))
    case 'e': Text.showText(Encode.encodeQueryEncode(text))
    case _: url(Client.responsesURL(context, text))

def run(context: Absolute.Context, arg: String) -> String:
  match arg:
    case SCon{kind, encoded}: dispatch(context, kind, Text.fromScalars(Text.numbers(Split.split(encoded, ','))))
    case _: "invalid-test"

def cases(args: List<String>, +context: Absolute.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(run(context, arg))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}})
