import Base
import ../packages/runtime/src/word-break.bend as G
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def encoded(items: List<&2,String>,reversed: List<&2,String>) -> String:
  match items:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case text <> rest: encoded(rest,J.quote(text) <> reversed)
def walked(fuel: Nat,value: Maybe<&1,String & String>,reversed: List<&2,String>) -> List<&2,String>:
  match fuel value:
    case _ None{}: List.reverse(&2,String,reversed)
    case Succ{remaining} Some{(cluster,rest)}: walked(remaining,G.next(rest),cluster <> reversed)
    case Zero{} _: "EXHAUSTED" <> Nil{}
def walking(+text: String) -> List<&2,String>: walked(String.length(text),G.next(text),Nil{})
def cases(values: List<&2,V.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case V.Text{+text} <> rest:
      do IO<Unit>:
        IO.print("[" ++ encoded(G.segments(text),Nil{}) ++ "," ++ encoded(walking(text),Nil{}) ++ "]")
        cases(rest)
    case _: IO.die(Unit,1,"expected strings")
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: cases(values)
    case _: IO.die(Unit,1,"expected JSON string array")
def repeat(count: Nat,+text: String,acc: String) -> String:
  match count:
    case Zero{}: acc
    case Succ{rest}: repeat(rest,text,text ++ acc)
def hash(text: String,value: U32) -> U32:
  match text:
    case SNil{}: value
    case SCon{Chr{code},rest}: hash(rest,U32.xor((value * 16777619 : U32),code))
def summary(values: List<&2,String>,count: Nat,scalars: Nat,digest: U32) -> String:
  match values:
    case Nil{}: Nat.show(count) ++ ":" ++ Nat.show(scalars) ++ ":" ++ U32.show(digest)
    case +cluster <> rest: summary(rest,Succ{count},scalars + String.length(cluster),hash(cluster,digest))
def largeCase(+text: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(summary(G.segments(text),0n,0n,2166136261))
    IO.print(summary(walking(text),0n,0n,2166136261))
def large() -> IO(Unit):
  do IO<Unit>:
    largeCase("a" ++ repeat(100000n,"\u{301}",""))
    largeCase("a:" ++ repeat(100000n,"\u{301}","") ++ "b")
    largeCase("a:" ++ repeat(100000n,"\u{301}","") ++ "!")
    largeCase(repeat(50000n,"🇦", ""))
    largeCase("👩" ++ repeat(20000n,"\u{200d}👩", ""))
    largeCase(repeat(100000n,"a", ""))
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case "long" <> Nil{}: large()
    case text <> Nil{}: parsed(J.parse(text))
    case _: IO.die(Unit,1,"expected JSON string array or long")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
