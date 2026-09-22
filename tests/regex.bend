import Base
import ../packages/runtime/src/regex.bend as R
import ../packages/runtime/src/base64.bend as B64
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/u32-table.bend as Table

def matched(mode: String,regex: R.Regex,+text: String) -> Bool:
  match mode:
    case SCon{'s',+rest}: R.finish(R.feed(String.drop(text,String.length(rest)),R.feed("",R.feed(String.take(text,String.length(rest)),R.create(regex)))))
    case SCon{'L',+rest}: R.finish(R.feed(String.drop(text,String.length(rest)),R.feed("",R.feed(String.take(text,String.length(rest)),R.create(regex)))))
    case _: R.isMatch(regex,text)

def compile(+mode: String,pattern: String) -> Result<&2,&2,R.Error,R.Regex>:
  match mode:
    case SCon{'L',_}: R.compileLiteral(pattern,False{})
    case "li": R.compileLiteral(pattern,True{})
    case "l": R.compileLiteral(pattern,False{})
    case _: R.compile(pattern,String.eq(mode,"i"))

def report(mode: String,result: Result<&2,&2,R.Error,R.Regex>,text: String) -> IO(Unit):
  match result:
    case Fail{R.Syntax{message}}: IO.print(String.append("error:",message))
    case Fail{R.RequiresByteInput{}}: IO.print("byte-input-required")
    case Fail{R.SizeLimit{}}: IO.print("error:Pattern size limit")
    case Done{regex}: IO.print(Bool.pick(String,matched(mode,regex,text),"true","false"))

def textDecoded(result: Result<&2,&2,Utf8.Error,String>) -> Maybe<&2,String>:
  match result:
    case Fail{_}: None{}
    case Done{text}: Some{text}

def decoded(bytes: Result<&2,&2,B64.Error,List<&2,U32>>) -> Maybe<&2,String>:
  match bytes:
    case Fail{_}: None{}
    case Done{bytes}: textDecoded(Utf8.decodeWith(Utf8.Preserve{},bytes))

def runCase(+mode: String,pattern: Maybe<&2,String>,text: Maybe<&2,String>) -> IO(Unit):
  match pattern text:
    case Some{pattern} Some{text}: report(mode,compile(mode,pattern),text)
    case _ _: IO.die(Unit,1,"invalid fixture Base64/UTF-8")

def rows(count: Nat,+index: U32,reversed: List<&2,Table.Entry<U32>>) -> List<&2,Table.Entry<U32>>:
  match count:
    case Zero{}: List.reverse(&2,Table.Entry<U32>,reversed)
    case Succ{count}: rows(count,(index + 1 : U32),Table.Entry{(index * 2 : U32),(index * index : U32)} <> reversed)

def replacements(count: Nat,+index: U32,+table: Table.Table<U32>) -> Table.Table<U32>:
  match count:
    case Zero{}: table
    case Succ{count}: replacements(count,(index + 1 : U32),Bool.pick(Unit -> Table.Table<U32>,U32.is_eq((index % 3 : U32),0),_ => Table.replace(U32,table,(index * 2 : U32),(index + 7 : U32)),_ => table)(Unit{}))

def expected(+point: U32,+count: U32,+floor: Bool,changed: Bool) -> Maybe<&2,U32>:
  +index = Bool.pick(U32,floor,U32.min(U32.shrn(point,1n),(count - 1 : U32)),U32.shrn(point,1n))
  +value = Bool.pick(U32,changed && U32.is_eq((index % 3 : U32),0),(index + 7 : U32),(index * index : U32))
  Bool.pick(Maybe<&2,U32>,U32.is_lt(index,count) && (floor || U32.is_eq(U32.and(point,1),0)),Some{value},None{})

def same(a: Maybe<&2,U32>,b: Maybe<&2,U32>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{a} Some{b}: U32.is_eq(a,b)
    case _ _: False{}

def tableChecks(fuel: Nat,+point: U32,+count: U32,+original: Table.Table<U32>,+changed: Table.Table<U32>,+okay: Bool) -> Bool:
  match fuel:
    case Zero{}: okay
    case Succ{fuel}: tableChecks(fuel,(point + 1 : U32),count,original,changed,okay && same(Table.get(U32,original,point),expected(point,count,False{},False{})) && same(Table.get(U32,changed,point),expected(point,count,False{},True{})) && same(Table.floor(U32,original,point),expected(point,count,True{},False{})) && same(Table.floor(U32,changed,point),expected(point,count,True{},True{})))

def checkTables() -> IO(Unit):
  +original = Table.fromSortedEntries(U32,rows(16385n,0,Nil{}))
  +changed = Table.replace(U32,replacements(16385n,0,original),65535,7)
  IO.print(Bool.pick(String,tableChecks(32775n,0,16385,original,changed,True{}) && same(Table.get(U32,changed,65535),None{}),"true","false"))

def run(args: List<String>) -> IO(Unit):
  match args:
    case "tables" <> Nil{}: checkTables()
    case mode <> pattern <> text <> rest:
      do IO<Unit>:
        runCase(mode,decoded(B64.decode(pattern)),decoded(B64.decode(text)))
        run(rest)
    case Nil{}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"expected mode/Base64-pattern/Base64-text triples")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
