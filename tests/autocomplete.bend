import Base
import ../packages/tui/src/autocomplete.bend as A
import ../packages/runtime/src/base64.bend as B
import ../packages/runtime/src/utf8.bend as U
import ../packages/runtime/src/string.bend as S
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/collation.bend as Collation

def encoded(value: String) -> String: B.encoded(U.encode(value),"")
def natural(text: String) -> Nat: Maybe.default(&2,Nat,Nat.read(text),0n)
def optional(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some" ++ encoded(text)
def reportError(value: A.Error) -> IO(Unit):
  match value:
    case A.InvalidCursor{}: IO.print("error:cursor")
    case A.InvalidPrefix{}: IO.print("error:prefix")
    case A.InvalidBasePath{}: IO.print("error:base")
    case A.Operation{message}: IO.print("error:" ++ message)
    case _: IO.print("error:other")
def reportItems(items: List<&2,A.AutocompleteItem>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit,Unit{})
    case A.AutocompleteItem{value,label,description} <> rest:
      do IO<Unit>:
        IO.print("item:" ++ encoded(value) ++ ":" ++ encoded(label) ++ ":" ++ optional(description))
        reportItems(rest)
def reportSuggestions(value: A.ResultOf(Maybe<&2,A.AutocompleteSuggestions>)) -> IO(Unit):
  match value:
    case Fail{error}: reportError(error)
    case Done{None{}}: IO.print("none")
    case Done{Some{A.AutocompleteSuggestions{items,prefix}}}:
      do IO<Unit>:
        IO.print("prefix:" ++ encoded(prefix))
        reportItems(items)
def reportApply(value: A.ResultOf(A.Completion)) -> IO(Unit):
  match value:
    case Fail{error}: reportError(error)
    case Done{A.Completion{lines,line,column}}: IO.print("apply:" ++ encoded(String.join(lines,"\n")) ++ ":" ++ Nat.show(line) ++ ":" ++ Nat.show(column))
def reportTrigger(value: A.ResultOf(Bool)) -> IO(Unit):
  match value:
    case Fail{error}: reportError(error)
    case Done{value}: IO.print("trigger:" ++ Bool.show(value))
def argumentCompletions(unused: Unit,+prefix: String) -> IO(A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>)):
  Bool.pick(Unit -> IO(A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>)),S.equal(prefix,"error"),_ => IO.pure(A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>),Fail{A.Operation{"callback"}}),
    _ => IO.pure(A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>),Done{Some{A.AutocompleteItem{prefix ++ "one","argument",Some{"callback result"}} <> Nil{}}}))(Unit{})
# The commands of upstream autocomplete-skill-slash.test.ts.
def skillCommand(name: String,description: String) -> A.Command: A.Slash{A.SlashCommand{name,Some{description},None{},None{}}}
def skillCommands() -> List<&2,A.Command>:
  [skillCommand("skill:deep-research","Multi-agent deep research"),skillCommand("skill:research-idea","Refine a raw idea into a falsifiable seed"),skillCommand("skill:to-sidecar","Route work to a sidecar"),skillCommand("model","Select the active model")]
def commands(+mode: String,callback: C.Callback<String,A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>)> ) -> List<&2,A.Command>:
  Bool.pick(List<&2,A.Command>,S.equal(mode,"commands"),
    A.Slash{A.SlashCommand{"model",Some{"Choose model"},Some{"[name]"},Some{callback}}} <>
    A.Slash{A.SlashCommand{"compact",Some{"Compact context"},None{},None{}}} <>
    A.Item{A.AutocompleteItem{"clear","ignored label",Some{"Clear"}}} <> Nil{},
    Bool.pick(List<&2,A.Command>,S.equal(mode,"skills"),skillCommands(),Nil{}))
# "locale" is the production order: the root collation, as localeCompare.
def collated(loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(A.SortPolicy):
  match loaded:
    case Done{collator}: IO.pure(A.SortPolicy,A.LocaleOrder{collator})
    case Fail{_}: IO.die(A.SortPolicy,1,"collation data unavailable")
def sortPolicy(+policy: String) -> IO(A.SortPolicy):
  Bool.pick(Unit -> IO(A.SortPolicy),S.equal(policy,"locale"),
    _ => do IO<A.SortPolicy>:
      loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load("packages/runtime/data")
      collated(loaded),
    _ => IO.pure(A.SortPolicy,Bool.pick(A.SortPolicy,S.equal(policy,"folded"),A.FoldedScalarOrder{},A.ScalarOrder{})))(Unit{})
def query(+mode: String,root: String,home: String,lines: String,line: Nat,column: Nat,force: String,recursive: String,policy: String) -> IO(Unit):
  do IO<Unit>:
    order : A.SortPolicy <- sortPolicy(policy)
    +callback : C.Callback<String,A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>)> <- C.create(~Unit,~String,~A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>),~(unused => prefix => argumentCompletions(unused,prefix)),Unit{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    ignored : Bool <- Bool.pick(Unit -> IO(Bool),S.equal(mode,"aborted"),_ => Abort.abort(Unit,controller,None{}),_ => IO.pure(Bool,False{}))(Unit{})
    result : A.ResultOf(Maybe<&2,A.AutocompleteSuggestions>) <- A.getSuggestions(A.CombinedAutocompleteProvider{commands(mode,callback),root,home,order,S.equal(recursive,"yes")},S.split(lines,'\n'),line,column,A.Options{Some{Abort.signal(Unit,controller)},S.equal(force,"yes")})
    reportSuggestions(result)
    Abort.dispose(Unit,controller)
    C.dispose(String,A.ResultOf(Maybe<&2,List<&2,A.AutocompleteItem>>),callback)
def reportPrefixes(texts: List<String>) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit,Unit{})
    case +text <> rest:
      do IO<Unit>:
        IO.print(optional(A.extractAtPrefix(text)) ++ ":" ++ optional(A.extractPathPrefix(text,False{})) ++ ":" ++ optional(A.extractPathPrefix(text,True{})))
        reportPrefixes(rest)
def run(args: List<String>) -> IO(Unit):
  match args:
    case "prefixes" <> rest: reportPrefixes(rest)
    case "apply" <> lines <> line <> column <> value <> label <> prefix <> Nil{}: reportApply(A.applyCompletion(S.split(lines,'\n'),natural(line),natural(column),A.AutocompleteItem{value,label,None{}},prefix))
    case "trigger" <> lines <> line <> column <> Nil{}: reportTrigger(A.shouldTriggerFileCompletion(S.split(lines,'\n'),natural(line),natural(column)))
    case mode <> root <> home <> lines <> line <> column <> force <> recursive <> policy <> Nil{}: query(mode,root,home,lines,natural(line),natural(column),force,recursive,policy)
    case _: IO.die(Unit,1,"invalid fixture arguments")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
