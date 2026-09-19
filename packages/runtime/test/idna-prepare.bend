import Base
import ../src/idna-prepare.bend as Prepare
import ../src/idna-mapping.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as MappingData
import ../src/unicode-17-normalization.bend as NormalizationData
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(result: Result<&2, &2, Mapping.MappingError, String>) -> String:
  match result:
    case Fail{Mapping.Disallowed{code}}: "invalid;" ++ U32.show(code)
    case Done{value}: "+" ++ Text.showText(value)

def cases(args: List<String>, +context: Prepare.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(Prepare.prepare(context, Mapping.Nontransitional{}, text(Split.split(head, ','), ""))))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Prepare.Context{MappingData.table(), NormalizationData.tables()})
