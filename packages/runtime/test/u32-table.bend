import Base
import ../src/u32-table.bend as Table
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def table(kind: String) -> Table.Table<U32>:
  match kind:
    case "e": Table.Table{0n, Table.Empty{}}
    case "z": Table.Table{1n, Table.Branch{0, 17, Table.Empty{}, Table.Empty{}}}
    case "m": Table.Table{1n, Table.Branch{4294967295, 19, Table.Empty{}, Table.Empty{}}}
    case _: Table.Table{3n, Table.Branch{5, 50, Table.Branch{2, 20, Table.Empty{}, Table.Empty{}}, Table.Branch{4294967295, 99, Table.Branch{100, 1000, Table.Empty{}, Table.Empty{}}, Table.Empty{}}}}

def show(result: Maybe<&2, U32>) -> String:
  match result:
    case None{}: "-"
    case Some{value}: U32.show(value)

def query(+values: Table.Table<U32>, +key: U32) -> String:
  show(Table.get(U32, values, key)) ++ ";" ++ show(Table.floor(U32, values, key))

def run(parts: List<&2, String>) -> String:
  match parts:
    case kind <> key <> Nil{}: query(table(kind), Text.decimal(key, 0))
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
