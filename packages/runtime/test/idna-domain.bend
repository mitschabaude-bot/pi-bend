import Base
import ../src/idna-domain.bend as Domain
import ../src/idna-label.bend as Label
import ../src/idna-mapping.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as MappingData
import ../src/unicode-17-normalization.bend as NormalizationData
import ../src/unicode-17-idna-properties.bend as PropertiesData
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def mode(value: String) -> Mapping.Mode:
  match value:
    case "t": Mapping.Transitional{}
    case _: Mapping.Nontransitional{}

def show(value: Result<&2, &2, Domain.Error, String>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{result}: "+" ++ Text.showText(result)

def run(parts: List<&2, String>, context: Label.Context) -> String:
  match parts:
    case processing <> hyphens <> std3 <> joiners <> bidi <> dns <> input <> Nil{}:
      show(Domain.toASCII(context, Domain.Options{Label.Options{String.eq(hyphens, "1"), String.eq(std3, "1"), String.eq(joiners, "1"), mode(processing)}, String.eq(bidi, "1"), String.eq(dns, "1")}, text(Split.split(input, ','), "")))
    case _: "invalid-case"

def cases(args: List<String>, +context: Label.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';'), context))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()})
