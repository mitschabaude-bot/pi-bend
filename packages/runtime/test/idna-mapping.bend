import Base
import ../src/u32-table.bend as Table
import ../src/unicode.bend as Data
import ../src/idna.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as Unicode
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def mode(text: String) -> Mapping.Mode:
  match text:
    case "t": Mapping.Transitional{}
    case _: Mapping.Nontransitional{}

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(result: Result<&2, &2, Mapping.MappingError, String>) -> String:
  match result:
    case Fail{Mapping.Disallowed{code}}: "invalid;" ++ U32.show(code)
    case Done{value}: "+" ++ Text.showText(value)

def mix(hash: U32, code: U32) -> U32: U32.xor((hash * 16777619 : U32), code)

def hashed(text: String, hash: U32) -> U32:
  match text:
    case SNil{}: mix(hash, 4294967295)
    case SCon{Chr{code}, rest}: hashed(rest, mix(hash, code))

def resultHash(result: Result<&2, &2, Mapping.MappingError, String>, hash: U32) -> U32:
  match result:
    case Fail{Mapping.Disallowed{code}}: mix(mix(hash, 0), code)
    case Done{text}: hashed(text, mix(hash, 1))

def range(fuel: Nat, +code: U32, +table: Table.Table<Data.Entry>, +processing: Mapping.Mode, hash: U32) -> U32:
  match fuel:
    case Zero{}: hash
    case Succ{rest}: range(rest, (code + 1 : U32), table, processing, resultHash(Mapping.codePoint(table, processing, code), hash))

def run(parts: List<&2, String>, table: Table.Table<Data.Entry>) -> String:
  match parts:
    case "m" <> processing <> input <> Nil{}: show(Mapping.map(table, mode(processing), text(Split.split(input, ','), "")))
    case "p" <> processing <> code <> Nil{}: show(Mapping.codePoint(table, mode(processing), Text.decimal(code, 0)))
    case "r" <> processing <> start <> count <> Nil{}: U32.show(range(U32.to_nat(Text.decimal(count, 0)), Text.decimal(start, 0), table, mode(processing), 2166136261))
    case _: "invalid-case"

def cases(args: List<String>, +table: Table.Table<Data.Entry>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';'), table))
        cases(rest, table)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Unicode.table())
