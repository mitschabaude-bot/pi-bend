import Base
import ../packages/coding-agent/src/modes/interactive/components/settings-submenu.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/runtime/src/callback.bend as C
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/tui/src/components/input.bend as Input
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def texts(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines: case Nil{}: Nil{} case line <> rest: V.Text{line} <> texts(rest)

def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "right": "\u{1b}[C" case "home": "\u{1}" case "end": "\u{5}" case "backspace": "\u{7f}" case "delete": "\u{1b}[3~" case "wordLeft": "\u{1b}b" case "wordRight": "\u{1b}f" case "killWord": "\u{17}" case "yank": "\u{19}" case "undo": "\u{1f}" case "tab": "\t" case "save": "\u{13}" case value: value

type Trace is Data: Trace{events: List<&2,String>,completed: Nat}
def logged(trace: Trace,event: String,done: Bool) -> Trace & Unit:
  match trace: case Trace{events,count}: (Trace{List.append(&2,String,events,[event]),count + Bool.pick(Nat,done,1n,0n)},Unit{})
def propertyText(pair: R.Property<String>) -> String: match pair: case R.Property{key,value}: key ++ "=" ++ value
def propertyTexts(fields: List<&2,R.Property<String>>) -> List<&2,String>:
  match fields: case Nil{}: Nil{} case field <> rest: propertyText(field) <> propertyTexts(rest)
def joined(fields: List<&2,String>) -> String:
  match fields: case Nil{}: "" case field <> +rest: field ++ Bool.pick(String,List.is_empty(&2,String,rest),"",";") ++ joined(rest)
def contextText(context: P.Context()) -> String:
  joined(propertyTexts(R.entries(String,context)))
def completed(trace: Ref.Ref<Trace>,context: P.Context()) -> IO(Unit): Ref.modify(Trace,Unit,trace,state => logged(state,"complete:" ++ contextText(context),True{}))
def cancelled(trace: Ref.Ref<Trace>,_: Unit) -> IO(Unit): Ref.modify(Trace,Unit,trace,state => logged(state,"cancel",False{}))
def modelItems(trace: Trace) -> List<&2,Select.SelectItem>:
  match trace: case Trace{_,count}: [Select.SelectItem{"a","Alpha",Some{"saved " ++ Nat.show(count)}},Select.SelectItem{"b","Beta",None{}},Select.SelectItem{"c","Charlie",None{}}]
def modelOptions(trace: Ref.Ref<Trace>,_: P.Context()) -> IO(List<&2,Select.SelectItem>):
  do IO<List<&2,Select.SelectItem>>:
    state : Trace <- Ref.read(Trace,trace)
    return modelItems(state)
def levelTitle(_: Unit,context: P.Context()) -> IO(String): IO.pure(String,"Level for " ++ Maybe.default(&2,String,R.get(String,context,"model"),"?"))
def levelOptions(_: Unit,context: P.Context()) -> IO(List<&2,Select.SelectItem>):
  IO.pure(List<&2,Select.SelectItem>,Bool.pick(List<&2,Select.SelectItem>,String.eq(Maybe.default(&2,String,R.get(String,context,"model"),""),"c"),Nil{},[Select.SelectItem{"low","Low",Some{"Quick"}},Select.SelectItem{"high","High",Some{"Careful"}}]))
def modelPreselect(_: Unit,_: P.Context()) -> IO(Maybe<&2,String>): IO.pure(Maybe<&2,String>,Some{"b"})
def levelPreselect(_: Unit,_: P.Context()) -> IO(Maybe<&2,String>): IO.pure(Maybe<&2,String>,Some{"high"})
def stateContext(state: P.SteppedSubmenu) -> P.Context(): match state: case P.SteppedSubmenu{_,_,context,_,_,_,_,_}: context
def stateIndex(state: P.SteppedSubmenu) -> Nat: match state: case P.SteppedSubmenu{_,index,_,_,_,_,_,_}: index
def optionalText(value: Maybe<&2,String>) -> V.Value: match value: case None{}: V.Null{} case Some{value}: V.Text{value}
def snapshot(pair: P.SteppedSubmenu & List<&2,String>,events: Trace) -> IO(P.SteppedSubmenu):
  match pair events:
    case (+state,lines) Trace{events,_}:
      do IO<P.SteppedSubmenu>:
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(object([R.Property{"context",V.Text{contextText(stateContext(state))}},R.Property{"index",V.Number{U32.to_f64(U32.from_nat(stateIndex(state)))}},R.Property{"selected",optionalText(P.selectedValue(P.active(state)))},R.Property{"query",V.Text{P.query(P.active(state))}},R.Property{"events",V.ArrayValue{texts(events)}},R.Property{"lines",V.ArrayValue{texts(lines)}}]))),"null"))
        return state
def show(state: P.SteppedSubmenu,+trace: Ref.Ref<Trace>,theme: Theme.Theme,width: Nat) -> IO(P.SteppedSubmenu):
  do IO<P.SteppedSubmenu>:
    pair : P.SteppedSubmenu & List<&2,String> <- P.renderStepped(state,theme,width)
    events : Trace <- Ref.read(Trace,trace)
    snapshot(pair,events)
def steps(actions: List<String>,state: P.SteppedSubmenu,+trace: Ref.Ref<Trace>,+theme: Theme.Theme,+width: Nat,+words: W.Source,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        next : P.SteppedSubmenu <- P.handleSteppedInput(state,words,bindings,Keys.defaults(),key(action))
        updated : P.SteppedSubmenu <- show(next,trace,theme,width)
        steps(rest,updated,trace,theme,width,words,bindings)
def checked(result: Result<&2,&2,P.BuildError,P.SteppedSubmenu>,trace: Ref.Ref<Trace>,theme: Theme.Theme,width: Nat,words: W.Source,bindings: Bindings.KeybindingsManager,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"invalid stepped fixture")
    case Done{state}:
      do IO<Unit>:
        +trace : Ref.Ref<Trace> = trace
        +theme : Theme.Theme = theme
        +width : Nat = width
        initial : P.SteppedSubmenu <- show(state,trace,theme,width)
        steps(actions,initial,trace,theme,width,words,bindings)
def prepared(pair: P.ThemeOwner & Select.SelectListTheme,+colors: Ref.Ref<Theme.Theme>,theme: Theme.Theme,+root: String,width: Nat,loop: String,start: String,actions: List<String>) -> IO(Unit):
  match pair:
    case (owner,listTheme):
      do IO<Unit>:
        +trace : Ref.Ref<Trace> <- Ref.new(Trace,Trace{Nil{},0n})
        +complete : C.Callback<P.Context(),Unit> <- C.create(~Ref.Ref<Trace>,~P.Context(),~Unit,~completed,trace)
        +cancel : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<Trace>,~Unit,~Unit,~cancelled,trace)
        +models : C.Callback<P.Context(),List<&2,Select.SelectItem>> <- C.create(~Ref.Ref<Trace>,~P.Context(),~List<&2,Select.SelectItem>,~modelOptions,trace)
        +levels : C.Callback<P.Context(),List<&2,Select.SelectItem>> <- C.create(~Unit,~P.Context(),~List<&2,Select.SelectItem>,~levelOptions,Unit{})
        +title : C.Callback<P.Context(),String> <- C.create(~Unit,~P.Context(),~String,~levelTitle,Unit{})
        +first : C.Callback<P.Context(),Maybe<&2,String>> <- C.create(~Unit,~P.Context(),~Maybe<&2,String>,~modelPreselect,Unit{})
        +second : C.Callback<P.Context(),Maybe<&2,String>> <- C.create(~Unit,~P.Context(),~Maybe<&2,String>,~levelPreselect,Unit{})
        definitions : List<&2,P.SteppedSubmenuStep> = [P.SteppedSubmenuStep{"model",P.Literal{"Choose model"},P.Literal{"Select model"},models,Some{first},True{},None{}},P.SteppedSubmenuStep{"level",P.Dynamic{title},P.Literal{"Select level"},levels,Some{second},False{},None{}}]
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        words : W.Source <- W.readyFor(W.Pending{root ++ "/packages/runtime/data"},"English word commands")
        +index : Nat = Maybe.default(&2,Nat,Nat.read(start),0n)
        created : Result<&2,&2,P.BuildError,P.SteppedSubmenu> <- P.stepped(definitions,listTheme,complete,cancel,P.SteppedSubmenuOptions{index,Bool.pick(P.Context(),Nat.is_eq(index,0n),R.new(String),R.set(String,R.new(String),"model","a")),String.eq(loop,"1")})
        checked(created,trace,theme,width,words,bindings,actions)
        C.dispose(P.Context(),Unit,complete)
        C.dispose(Unit,Unit,cancel)
        C.dispose(P.Context(),List<&2,Select.SelectItem>,models)
        C.dispose(P.Context(),List<&2,Select.SelectItem>,levels)
        C.dispose(P.Context(),String,title)
        C.dispose(P.Context(),Maybe<&2,String>,first)
        C.dispose(P.Context(),Maybe<&2,String>,second)
        discarded : Trace <- Ref.dispose(Trace,trace)
        P.disposeTheme(owner)
        unused : Theme.Theme <- Ref.dispose(Theme.Theme,colors)
        return Unit{}
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,root: String,width: Nat,loop: String,start: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load theme")
    case Done{+theme}:
      do IO<Unit>:
        +colors : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
        owner : P.ThemeOwner <- P.createTheme(colors)
        prepared(P.theme(owner),colors,theme,root,width,loop,start,actions)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> loop <> start <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),loop,start,actions)
    case _: IO.die(Unit,1,"expected root width loop start actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
