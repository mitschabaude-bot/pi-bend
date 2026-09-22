import Base
import ../src/idna.bend as Rules
import ../src/u32-table.bend as Table
import ../src/idna.bend as Mapping
import ../src/unicode.bend as Data
import ../src/string.bend as Split
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

def status(value: String) -> Maybe<&2, Data.Status>:
  match value:
    case "v": Some{Data.Valid{}}
    case "d": Some{Data.Deviation{"ss"}}
    case "m": Some{Data.Mapped{"a"}}
    case "i": Some{Data.Ignored{}}
    case "x": Some{Data.Disallowed{}}
    case _: None{}

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def show(value: Maybe<&2, Rules.LabelRulesError>) -> String:
  match value:
    case None{}: "ok"
    case Some{Rules.HyphenPositions{}}: "hyphen-positions"
    case Some{Rules.HyphenEdge{}}: "hyphen-edge"
    case Some{Rules.ReservedPrefix{}}: "reserved"
    case Some{Rules.Dot{}}: "dot"
    case Some{Rules.InvalidASCII{code}}: "ascii;" ++ U32.show(code)
    case Some{Rules.InvalidStatus{code}}: "status;" ++ U32.show(code)

# Small explicit ranges exercise the composed checker without generated data.
def table() -> Table.Table<Data.Entry>:
  Table.Table{3n, Table.Branch{97, Data.Entry{122, Data.Valid{}},
    Table.Branch{46, Data.Entry{46, Data.Valid{}},
      Table.Branch{45, Data.Entry{45, Data.Valid{}}, Table.Empty{}, Table.Empty{}},
      Table.Branch{65, Data.Entry{65, Data.Mapped{"a"}}, Table.Empty{}, Table.Empty{}}},
    Table.Branch{223, Data.Entry{223, Data.Deviation{"ss"}},
      Table.Branch{173, Data.Entry{173, Data.Ignored{}}, Table.Empty{}, Table.Empty{}},
      Table.Branch{500, Data.Entry{500, Data.Disallowed{}}, Table.Empty{}, Table.Empty{}}}}}

def run(parts: List<&2, String>) -> String:
  match parts:
    case "s" <> hyphens <> std3 <> input <> Nil{}:
      show(Rules.syntax(text(Split.split(input, ','), ""), String.eq(hyphens, "1"), String.eq(std3, "1")))
    case "c" <> processing <> hyphens <> std3 <> input <> Nil{}:
      show(Rules.check(table(), Rules.LabelRulesOptions{String.eq(hyphens, "1"), String.eq(std3, "1"), mode(processing)}, text(Split.split(input, ','), "")))
    case "v" <> processing <> value <> Nil{}: bit(Rules.statusAllowed(mode(processing), status(value)))
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
