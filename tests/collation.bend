import Base
import ../packages/runtime/src/collation.bend as C
import ../packages/runtime/src/filesystem.bend as FS

# Fixture runner for tests/collation_check.py. Strings are space-separated hex
# code points (lone surrogates included), so the fixture is plain ASCII.
#   pairs <file>: lines "A\tB\tSIGN", SIGN one of -1, 0, 1; prints the count.
#   sort <file>: lines ".A" (one string each); prints them sorted, same format.
def splitBytes(bytes: List<&2,U32>,+separator: U32,+current: List<&2,U32>,+reversed: List<&2,List<&2,U32>>) -> List<&2,List<&2,U32>>:
  match bytes:
    case Nil{}: List.reverse(&2,List<&2,U32>,List.reverse(&2,U32,current) <> reversed)
    case +byte <> +rest:
      Bool.pick(Unit -> List<&2,List<&2,U32>>,U32.is_eq(byte,separator),_ => splitBytes(rest,separator,Nil{},List.reverse(&2,U32,current) <> reversed),
        _ => splitBytes(rest,separator,byte <> current,reversed))(Unit{})
def digit(+byte: U32) -> U32:
  Bool.pick(U32,U32.is_le(byte,57),(byte - 48 : U32),Bool.pick(U32,U32.is_le(byte,70),(byte - 55 : U32),(byte - 87 : U32)))
def number(bytes: List<&2,U32>,+value: U32) -> U32:
  match bytes:
    case Nil{}: value
    case byte <> rest: number(rest,(value * 16 + digit(byte) : U32))
def codesOf(numbers: List<&2,List<&2,U32>>,reversed: List<&2,U32>) -> List<&2,U32>:
  match numbers:
    case Nil{}: List.reverse(&2,U32,reversed)
    case Nil{} <> rest: codesOf(rest,reversed)
    case digits <> rest: codesOf(rest,number(digits,0) <> reversed)
# Code points or UTF-16 units: lone surrogates are not Bend Chars on the JS lane.
def parsed(field: List<&2,U32>) -> List<&2,U32>: codesOf(splitBytes(field,32,Nil{},Nil{}),Nil{})
def signOf(field: List<&2,U32>) -> Cmp:
  match field:
    case 45 <> _: LT{}
    case 49 <> _: GT{}
    case _: EQ{}
def cmpName(order: Cmp) -> String:
  match order:
    case LT{}: "-1"
    case EQ{}: "0"
    case GT{}: "1"
def sameOrder(left: Cmp,right: Cmp) -> Bool:
  match left right:
    case LT{} LT{}: True{}
    case EQ{} EQ{}: True{}
    case GT{} GT{}: True{}
    case _ _: False{}
def asciiText(bytes: List<&2,U32>,reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case byte <> rest: asciiText(rest,SCon{Chr{byte},reversed})
type Tally is Data: Tally{count: Nat,failures: Nat,report: List<&2,String>}
def checkedRow(+got: Cmp,+want: Cmp,line: List<&2,U32>,tally: Tally) -> Tally:
  match tally:
    case Tally{+count,+failures,+report}:
      Bool.pick(Unit -> Tally,sameOrder(got,want),_ => Tally{Succ{count},failures,report},
        _ => Tally{Succ{count},Succ{failures},Bool.pick(List<&2,String>,Nat.is_lt(failures,20n),(asciiText(line,"") ++ " got " ++ cmpName(got)) <> report,report)})(Unit{})
def surrogateFree(codes: List<&2,U32>) -> Bool:
  match codes:
    case Nil{}: True{}
    case +code <> rest: Bool.pick(Unit -> Bool,U32.is_ge(code,55296) && U32.is_lt(code,57344),_ => False{},_ => surrogateFree(rest))(Unit{})
def stringOf(codes: List<&2,U32>,reversed: String) -> String:
  match codes:
    case Nil{}: String.reverse(reversed)
    case code <> rest: stringOf(rest,SCon{Chr{code},reversed})
# Surrogate-free rows go through the String API, the rest through code units.
def comparedBy(strings: Bool,+collator: C.Collator,left: List<&2,U32>,right: List<&2,U32>) -> Cmp:
  match strings:
    case True{}: C.compare(collator,stringOf(left,""),stringOf(right,""))
    case False{}: C.compareKeys(C.keyCodes(collator,left),C.keyCodes(collator,right))
def compared(+collator: C.Collator,+left: List<&2,U32>,+right: List<&2,U32>) -> Cmp: comparedBy(surrogateFree(left) && surrogateFree(right),collator,left,right)
def rowFields(+collator: C.Collator,fields: List<&2,List<&2,U32>>,line: List<&2,U32>,tally: Tally) -> Tally:
  match fields:
    case a <> b <> sign <> Nil{}: checkedRow(compared(collator,parsed(a),parsed(b)),signOf(sign),line,tally)
    case _: tally
def row(+collator: C.Collator,+line: List<&2,U32>,tally: Tally) -> Tally: rowFields(collator,splitBytes(line,9,Nil{},Nil{}),line,tally)
def rows(+collator: C.Collator,lines: List<&2,List<&2,U32>>,tally: Tally) -> Tally:
  match lines:
    case Nil{}: tally
    case line <> rest: rows(collator,rest,row(collator,line,tally))
def pairsReport(tally: Tally) -> IO(Unit):
  match tally:
    case Tally{count,Zero{},_}: IO.print(Nat.show(count))
    case Tally{count,failures,report}: IO.die(Unit,1,String.join(List.reverse(&2,String,report),"\n") ++ "\ncollation mismatches: " ++ Nat.show(failures) ++ " of " ++ Nat.show(count))

def hexChar(+digit: U32) -> Char: Chr{Bool.pick(U32,U32.is_lt(digit,10),(digit + 48 : U32),(digit + 55 : U32))}
def hexDigits(fuel: Nat,+code: U32,+text: String) -> String:
  match fuel:
    case Zero{}: text
    case Succ{left}:
      +char = hexChar((code % 16 : U32))
      Bool.pick(Unit -> String,U32.is_lt(code,16),_ => SCon{char,text},_ => hexDigits(left,(code / 16 : U32),SCon{char,text}))(Unit{})
def hexOf(text: String,reversed: List<&2,String>) -> String:
  match text:
    case SNil{}: String.join(List.reverse(&2,String,reversed)," ")
    case SCon{Chr{code},rest}: hexOf(rest,hexDigits(8n,code,"") <> reversed)
def strings(lines: List<&2,List<&2,U32>>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case (46 <> field) <> rest: strings(rest,stringOf(parsed(field),"") <> reversed)
    case _ <> rest: strings(rest,reversed)
def hexLines(values: List<&2,String>,reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2,String,reversed),"\n")
    case text <> rest: hexLines(rest,("." ++ hexOf(text,Nil{})) <> reversed)
def run(+collator: C.Collator,+mode: String,bytes: List<&2,U32>) -> IO(Unit):
  +lines = splitBytes(bytes,10,Nil{},Nil{})
  Bool.pick(Unit -> IO(Unit),String.eq(mode,"sort"),_ => IO.print(hexLines(C.sort(collator,strings(lines,Nil{})),Nil{})),
    _ => pairsReport(rows(collator,lines,Tally{0n,0n,Nil{}})))(Unit{})
def fixture(loaded: Result<&2,&2,C.LoadError,C.Collator>,mode: String,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match loaded read:
    case Done{collator} Done{bytes}: run(collator,mode,bytes)
    case Fail{_} _: IO.die(Unit,1,"collation data unavailable")
    case _ Fail{_}: IO.die(Unit,1,"fixture read failed")
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> path <> Nil{}:
      do IO<Unit>:
        loaded : Result<&2,&2,C.LoadError,C.Collator> <- C.load("packages/runtime/data")
        read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        fixture(loaded,mode,read)
    case _: IO.die(Unit,1,"usage: collation pairs|sort FILE")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
