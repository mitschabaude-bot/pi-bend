import Base
import ../src/unicode.bend as Normalization
import ../src/unicode-17-normalization.bend as Unicode
import ../src/unicode.bend as Data
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def numbers(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case part <> rest: numbers(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def grow(count: Nat, text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: grow(rest, SCon{'\u{315}', SCon{'\u{300}', text}})

def checksum(text: String, count: U32, hash: U32) -> String:
  match text:
    case SNil{}: U32.show(count) ++ ";" ++ U32.show(hash)
    case SCon{Chr{code}, rest}: checksum(rest, (count + 1 : U32), U32.xor((hash * 16777619 : U32), code))

def run(parts: List<&2, String>, tables: Data.Tables) -> String:
  match parts:
    case "c" <> input <> Nil{}: Text.showText(Normalization.nfc(tables, numbers(Split.split(input, ','), "")))
    case "d" <> input <> Nil{}: Text.showText(Normalization.nfd(tables, numbers(Split.split(input, ','), "")))
    case "gc" <> count <> Nil{}: checksum(Normalization.nfc(tables, SCon{'a', grow(U32.to_nat(Text.decimal(count, 0)), "")}), 0, 2166136261)
    case "gd" <> count <> Nil{}: checksum(Normalization.nfd(tables, SCon{'a', grow(U32.to_nat(Text.decimal(count, 0)), "")}), 0, 2166136261)
    case _: "invalid-case"

def cases(args: List<String>, +tables: Data.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';'), tables))
        cases(rest, tables)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Unicode.tables())
