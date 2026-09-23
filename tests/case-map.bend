import Base
import ../packages/runtime/src/case-map.bend as C
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def cases(values: List<&2,V.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case V.Text{text} <> rest:
      do IO<Unit>:
        IO.print(J.quote(C.lower(text)))
        cases(rest)
    case _: IO.die(Unit,1,"expected strings")
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: cases(values)
    case _: IO.die(Unit,1,"expected array")
def hash(text: String,value: U32) -> U32:
  match text:
    case SNil{}: value
    case SCon{Chr{code},rest}: hash(rest,U32.xor((value * 16777619: U32),code))
def domain(fuel: Nat,+code: U32,+digest: U32) -> U32:
  match fuel:
    case Zero{}: digest
    case Succ{left}:
      domain(left,(code + 1: U32),Bool.pick(Unit -> U32,U32.is_ge(code,55296) && U32.is_lt(code,57344),_ => digest,
        _ => hash(C.lower(SCon{Chr{code},""}),digest))(Unit{}))
def repeat(count: Nat,+text: String,acc: String) -> String:
  match count:
    case Zero{}: acc
    case Succ{rest}: repeat(rest,text,text ++ acc)
def summary(text: String) -> IO(Unit):
  +result = C.lower(text)
  IO.print(Nat.show(String.length(result)) ++ ":" ++ U32.show(hash(result,2166136261)))
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case "domain" <> Nil{}: IO.print(U32.show(domain(1114112n,0,2166136261)))
    case "long" <> Nil{}:
      do IO<Unit>:
        summary("AΣ" ++ repeat(100000n,"\u{301}",""))
        summary("AΣ" ++ repeat(100000n,"\u{301}","") ++ "A")
        summary(repeat(50000n,"Σ\u{301}",""))
        summary(repeat(50000n,"İ", ""))
    case text <> Nil{}: parsed(J.parse(text))
    case _: IO.die(Unit,1,"expected JSON array/domain/long")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
