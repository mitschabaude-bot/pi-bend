import Base
import ../src/url.bend as URL
import ../src/url.bend as Record
import ../src/url.bend as Serialize
import ../src/idna.bend as Domain
import ../src/idna.bend as Label
import ../src/idna.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as MappingData
import ../src/unicode-17-normalization.bend as NormalizationData
import ../src/unicode-17-idna-properties.bend as PropertiesData
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(value: Result<&2, &2, URL.Error, Record.URL>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{result}: "+" ++ Text.showText(Serialize.serializeSerialize(result, False{}))

def cases(args: List<String>, +context: URL.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(URL.parse(context, text(Split.split(head, ','), ""))))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}})
