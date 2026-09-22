import Base
import ../packages/coding-agent/src/core/prompt-templates.bend as P
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as W

def text(value: String) -> String:
  W.fromScalars(W.parseNumbers(value))

def texts(values: List<&2,String>, reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case value <> rest: texts(rest,text(value) <> reversed)

def shown(values: List<&2,String>, reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: "ok|" ++ String.join(List.reverse(&2,String,reversed),";")
    case value <> rest: shown(rest,W.showText(value) <> reversed)

def parsed(result: Result<&2,&2,P.ArgumentError,List<&2,String>>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{values}: shown(values,Nil{})

def expanded(result: Result<&2,&2,P.ArgumentError,String>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{value}: "ok|" ++ W.showText(value)

def template(+name: String, content: String) -> P.PromptTemplate:
  P.PromptTemplate{name,"",None{},content,Skills.SourceInfo{"/test.md","local",Skills.Temporary{},Skills.TopLevel{},None{}},"/test.md"}

def templates(values: List<&2,String>, reversed: List<&2,P.PromptTemplate>) -> List<&2,P.PromptTemplate>:
  match values:
    case name <> content <> rest: templates(rest,template(text(name),text(content)) <> reversed)
    case _: List.reverse(&2,P.PromptTemplate,reversed)

def repeated(n: Nat, +char: Char, reversed: String) -> String:
  match n:
    case 0n: reversed
    case 1n+rest: repeated(rest,char,SCon{char,reversed})

def repeatedText(n: Nat, +value: String, reversed: String) -> String:
  match n:
    case 0n: String.reverse(reversed)
    case 1n+rest: repeatedText(rest,value,String.reverse.go(value,reversed))

def longCase(+value: String, +malformed: String) -> IO(Unit):
  IO.print(Bool.pick(String,
    Strings.equal(P.substituteArgs("$1",[value]),value) &&
    Strings.equal(P.substituteArgs(malformed,["replacement"]),malformed),"long-ok","long-failed"))

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "p" <> value <> Nil{}: IO.print(parsed(P.parseCommandArgs(text(value))))
    case "s" <> content <> args: IO.print("ok|" ++ W.showText(P.substituteArgs(text(content),texts(args,Nil{}))))
    case "e" <> value <> items: IO.print(expanded(P.expandPromptTemplate(text(value),templates(items,Nil{}))))
    case "long" <> Nil{}: longCase(repeated(200000n,'x',""),repeatedText(40000n,"${1:-",""))
    case _: IO.die(Unit,1,"invalid command")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        run(Strings.split(value,'|'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
