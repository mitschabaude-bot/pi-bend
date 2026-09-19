import Base
import ../src/url-resolve.bend as Resolve
import ../src/url-absolute.bend as Absolute
import ../src/url-record.bend as Record
import ../src/url-serialize.bend as Serialize
import ../src/idna-domain.bend as Domain
import ../src/idna-label.bend as Label
import ../src/idna-mapping.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as MappingData
import ../src/unicode-17-normalization.bend as NormalizationData
import ../src/unicode-17-idna-properties.bend as PropertiesData
import ../src/string-split.bend as Split
import ./url-absolute.bend as Text
import ./utf8-runner.bend as Scalar

def show(value: Result<&2, &2, Resolve.Error, Record.URL>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{result}: "+" ++ Scalar.showText(Serialize.serialize(result, False{}))

def withBase(context: Absolute.Context, result: Result<&2, &2, Absolute.Error, Record.URL>, input: String) -> String:
  match result:
    case Fail{_}: "invalid"
    case Done{base}: show(Resolve.parse(context, base, input))

def cases(args: List<String>, +context: Absolute.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case input <> base <> rest:
      do IO<Unit>:
        IO.print(withBase(context, Absolute.parse(context, Text.text(Split.split(base, ','), "")), Text.text(Split.split(input, ','), "")))
        cases(rest, context)
    case _: IO.die(Unit, 1, "expected input/base argument pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Absolute.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.Options{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}})
