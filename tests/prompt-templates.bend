import Base
import ../packages/coding-agent/src/core/prompt-templates.bend as P
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as W

import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/core/diagnostics.bend as Diagnostics
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties

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

def scope(value: Skills.SourceScope) -> String:
  match value:
    case Skills.User{}: "user"
    case Skills.Project{}: "project"
    case Skills.Temporary{}: "temporary"

def optional(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: W.showText(value)

def source(info: Skills.SourceInfo) -> String:
  match info:
    case Skills.SourceInfo{path,origin,kind,_,base}: W.showText(path) ++ "|" ++ origin ++ "|" ++ scope(kind) ++ "|top-level|" ++ optional(base)

def showTemplates(values: List<&2,P.PromptTemplate>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case P.PromptTemplate{name,description,hint,content,info,path} <> rest:
      do IO<Unit>:
        IO.print("template|" ++ W.showText(name) ++ "|" ++ W.showText(description) ++ "|" ++ optional(hint) ++ "|" ++ W.showText(content) ++ "|" ++ W.showText(path) ++ "|" ++ source(info))
        showTemplates(rest)

def showDiagnostics(values: List<&2,Diagnostics.ResourceDiagnostic>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case Diagnostics.ResourceDiagnostic{kind,message,path,_} <> rest:
      do IO<Unit>:
        IO.print("diagnostic|" ++ Diagnostics.typeName(kind) ++ "|" ++ optional(path) ++ "|" ++ W.showText(message))
        showDiagnostics(rest)

def loaded(value: Result<&2,&2,Paths.Error,P.LoadResult>) -> IO(Unit):
  match value:
    case Fail{_}: IO.print("path-error")
    case Done{P.LoadResult{templates,diagnostics}}:
      do IO<Unit>:
        showTemplates(templates)
        showDiagnostics(diagnostics)
        IO.print("end")

def loadTemplates(+cwd: String, agent: String, home: String, defaults: Bool, config: String, paths: List<&2,String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Paths.Error,P.LoadResult> <- P.loadPromptTemplates(Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}},config,P.LoadPromptTemplatesOptions{cwd,agent,paths,defaults})
    loaded(result)

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "l" <> cwd <> agent <> home <> enabled <> config <> paths: loadTemplates(text(cwd),text(agent),text(home),Strings.equal(enabled,"1"),text(config),texts(paths,Nil{}))
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
