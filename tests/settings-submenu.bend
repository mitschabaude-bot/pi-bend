import Base
import ../packages/coding-agent/src/modes/interactive/components/settings-submenu.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
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

def items() -> List<&2,Select.SelectItem>:
  [Select.SelectItem{"a","A long model name [provider]",Some{"high"}},Select.SelectItem{"b","Beta",None{}},Select.SelectItem{"c","Charlie",Some{"a long description that will be clipped"}},Select.SelectItem{"d","Delta",None{}},Select.SelectItem{"e","Echo",None{}},Select.SelectItem{"f","Foxtrot",None{}},Select.SelectItem{"g","Golf",None{}},Select.SelectItem{"h","Hotel",None{}},Select.SelectItem{"i","India",None{}},Select.SelectItem{"j","Juliet",None{}},Select.SelectItem{"k","Kilo",None{}},Select.SelectItem{"l","Lima",None{}}]
def selectedValue(value: Maybe<&2,String>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Text{value}
def cursor(state: P.SelectSubmenu) -> Nat:
  match state: case P.SelectSubmenu{_,_,_,_,Some{search},_}: Input.getCursor(search) case _: 0n
def actionText(action: P.Action) -> String:
  match action: case P.Continue{}: "continue" case P.Selected{value}: "selected:" ++ value case P.Cancel{}: "cancel" case P.SelectionChanged{value}: "selection:" ++ value
def emitted(pair: P.SelectSubmenu & List<&2,String>,action: P.Action) -> IO(P.SelectSubmenu):
  match pair:
    case (+state,lines):
      do IO<P.SelectSubmenu>:
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(object([R.Property{"selected",selectedValue(P.selectedValue(state))},R.Property{"query",V.Text{P.query(state)}},R.Property{"cursor",V.Number{U32.to_f64(U32.from_nat(cursor(state)))}},R.Property{"action",V.Text{actionText(action)}},R.Property{"lines",V.ArrayValue{texts(lines)}}]))),"null"))
        return state
def show(state: P.SelectSubmenu,action: P.Action,theme: Theme.Theme,width: Nat) -> IO(P.SelectSubmenu):
  do IO<P.SelectSubmenu>:
    pair : P.SelectSubmenu & List<&2,String> <- P.render(state,theme,width)
    emitted(pair,action)
def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "right": "\u{1b}[C" case "home": "\u{1}" case "end": "\u{5}" case "backspace": "\u{7f}" case "delete": "\u{1b}[3~" case "wordLeft": "\u{1b}b" case "wordRight": "\u{1b}f" case "killWord": "\u{17}" case "yank": "\u{19}" case "undo": "\u{1f}" case "tab": "\t" case "save": "\u{13}" case value: value

def shown(pair: P.SelectSubmenu & P.Action,theme: Theme.Theme,width: Nat) -> IO(P.SelectSubmenu):
  match pair: case (state,action): show(state,action,theme,width)
def steps(actions: List<String>,state: P.SelectSubmenu,+theme: Theme.Theme,+width: Nat,+words: W.Source,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        pair : P.SelectSubmenu & P.Action <- P.handleInput(state,words,bindings,Keys.defaults(),key(action))
        updated : P.SelectSubmenu <- shown(pair,theme,width)
        steps(rest,updated,theme,width,words,bindings)
def prepared(pair: P.ThemeOwner & Select.SelectListTheme,+colors: Ref.Ref<Theme.Theme>,+theme: Theme.Theme,+width: Nat,+root: String,empty: String,searchable: String,current: String,description: String,actions: List<String>) -> IO(Unit):
  match pair:
    case (owner,listTheme):
      do IO<Unit>:
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        +words : W.Source <- W.readyFor(W.Pending{root ++ "/packages/runtime/data"},"English word commands")
        state : P.SelectSubmenu <- show(P.new("Select a setting",description,Bool.pick(List<&2,Select.SelectItem>,String.eq(empty,"1"),Nil{},items()),current,listTheme,P.noCallbacks(),P.SelectSubmenuOptions{String.eq(searchable,"1"),None{}}),P.Continue{},theme,width)
        steps(actions,state,theme,width,words,bindings)
        P.disposeTheme(owner)
        unused : Theme.Theme <- Ref.dispose(Theme.Theme,colors)
        return Unit{}
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,root: String,width: Nat,empty: String,searchable: String,current: String,description: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load submenu theme")
    case Done{+theme}:
      do IO<Unit>:
        +colors : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
        owner : P.ThemeOwner <- P.createTheme(colors)
        prepared(P.theme(owner),colors,theme,width,root,empty,searchable,current,description,actions)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> empty <> searchable <> current <> description <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),empty,searchable,current,description,actions)
    case _: IO.die(Unit,1,"expected root width empty searchable current description actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
