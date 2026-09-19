import Base
import ../src/u32-table.bend as Table
import ../src/idna-properties.bend as Data
import ../src/unicode-17-idna-properties.bend as Unicode
import ../src/unicode-bidi-class.bend as Bidi
import ../src/unicode-joining-type.bend as Joining
import ../src/idna-label-context.bend as Context
import ../src/idna-bidi.bend as Rule
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def bidiCode(value: Bidi.Class) -> U32:
  match value:
    case Bidi.L{}: 0
    case Bidi.R{}: 1
    case Bidi.AL{}: 2
    case Bidi.EN{}: 3
    case Bidi.AN{}: 4
    case Bidi.ES{}: 5
    case Bidi.CS{}: 6
    case Bidi.ET{}: 7
    case Bidi.ON{}: 8
    case Bidi.BN{}: 9
    case Bidi.NSM{}: 10
    case Bidi.B{}: 11
    case Bidi.S{}: 12
    case Bidi.WS{}: 13
    case Bidi.LRE{}: 14
    case Bidi.LRO{}: 15
    case Bidi.RLE{}: 16
    case Bidi.RLO{}: 17
    case Bidi.PDF{}: 18
    case Bidi.LRI{}: 19
    case Bidi.RLI{}: 20
    case Bidi.FSI{}: 21
    case Bidi.PDI{}: 22

def joiningCode(value: Joining.JoiningType) -> U32:
  match value:
    case Joining.NonJoining{}: 0
    case Joining.LeftJoining{}: 1
    case Joining.RightJoining{}: 2
    case Joining.DualJoining{}: 3
    case Joining.JoinCausing{}: 4
    case Joining.Transparent{}: 5

def bit(value: Bool) -> U32:
  match value:
    case True{}: 1
    case False{}: 0

def show(value: Maybe<&2, Data.Properties>) -> String:
  match value:
    case None{}: "none"
    case Some{Data.Properties{bidi, joining, ccc, mark}}:
      U32.show(bidiCode(bidi)) ++ ";" ++ U32.show(joiningCode(joining)) ++ ";" ++ U32.show(ccc) ++ ";" ++ U32.show(bit(mark))

def mix(hash: U32, code: U32) -> U32: U32.xor((hash * 16777619 : U32), code)

def hashed(value: Maybe<&2, Data.Properties>, hash: U32) -> U32:
  match value:
    case None{}: mix(hash, 4294967295)
    case Some{Data.Properties{bidi, joining, ccc, mark}}:
      mix(mix(mix(mix(hash, bidiCode(bidi)), joiningCode(joining)), ccc), bit(mark))

def range(fuel: Nat, +code: U32, +table: Table.Table<Data.Entry>, hash: U32) -> U32:
  match fuel:
    case Zero{}: hash
    case Succ{rest}: range(rest, (code + 1 : U32), table, hashed(Data.lookup(table, code), hash))

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def showContext(value: Result<&2, &2, U32, Context.Analysis>) -> String:
  match value:
    case Fail{code}: "invalid;" ++ U32.show(code)
    case Done{Context.Analysis{mark, Rule.Analysis{rtl, valid}, joiners}}:
      U32.show(bit(mark)) ++ U32.show(bit(rtl)) ++ U32.show(bit(valid)) ++ U32.show(bit(joiners))

def run(parts: List<&2, String>, table: Table.Table<Data.Entry>) -> String:
  match parts:
    case "p" <> code <> Nil{}: show(Data.lookup(table, Text.decimal(code, 0)))
    case "r" <> start <> count <> Nil{}: U32.show(range(U32.to_nat(Text.decimal(count, 0)), Text.decimal(start, 0), table, 2166136261))
    case "s" <> input <> Nil{}: showContext(Context.analyze(table, text(Split.split(input, ','), "")))
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
