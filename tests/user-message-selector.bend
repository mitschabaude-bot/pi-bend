import Base
import ../packages/coding-agent/src/modes/interactive/components/user-message-selector.bend as Picker
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def items(texts: List<String>,+index: Nat) -> List<&2,Picker.UserMessageItem>:
  match texts:
    case Nil{}: Nil{}
    case text <> rest: Picker.UserMessageItem{Nat.show(index),text,None{}} <> items(rest,index + 1n)
def actionText(action: Picker.Action) -> String:
  match action:
    case Picker.Continue{}: "continue"
    case Picker.Cancel{}: "cancel"
    case Picker.Chosen{id}: "chosen:" ++ id
def textValues(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case text <> rest: V.Text{text} <> textValues(rest)
def emit(component: Picker.UserMessageSelectorComponent,action: Picker.Action,+theme: Theme.Theme,width: Nat) -> IO(Unit):
  do IO<Unit>:
    +copy : Picker.UserMessageSelectorComponent = component
    lines : List<&2,String> <- Picker.render(copy,theme,width)
    selected : V.Value = Maybe.default(&2,V.Value,Maybe.map(&2,String,V.Value,text => V.Text{text},Picker.selectedId(Picker.getMessageList(copy))),V.Null{})
    value : V.Value = V.ObjectValue{R.Record{[R.Property{"selected",selected},R.Property{"action",V.Text{actionText(action)}},R.Property{"lines",V.ArrayValue{textValues(lines)}}]}}
    IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
def key(name: String) -> String:
  match name:
    case "up": "\u{1b}[A"
    case "down": "\u{1b}[B"
    case "enter": "\r"
    case "escape": "\u{1b}"
    case "left": "\u{1b}[D"
    case _: name
def emitted(pair: Picker.UserMessageList & Picker.Action,+theme: Theme.Theme,width: Nat) -> IO(Picker.UserMessageList):
  match pair:
    case Tuple{+list,action}:
      do IO<Picker.UserMessageList>:
        emit(Picker.UserMessageSelectorComponent{list},action,theme,width)
        return list
def steps(actions: List<&2,String>,+list: Picker.UserMessageList,+theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        updated : Picker.UserMessageList <- emitted(Picker.handleInput(list,bindings,Keys.defaults(),key(action)),theme,width)
        steps(rest,updated,theme,width,bindings)
def runTheme(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,+width: Nat,+initial: String,+actions: String,texts: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +component : Picker.UserMessageSelectorComponent = Picker.new(items(texts,0n),Bool.pick(Maybe<&2,String>,String.is_empty(initial),None{},Some{initial}))
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        emit(component,Picker.Continue{},theme,width)
        steps(Bool.pick(List<&2,String>,String.is_empty(actions),Nil{},String.split(actions,',')),Picker.getMessageList(component),theme,width,bindings)
def run(args: List<String>) -> IO(Unit):
  match args:
    case root <> width <> initial <> actions <> texts:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        runTheme(theme,Maybe.default(&2,Nat,Nat.read(width),80n),initial,actions,texts)
    case _: IO.die(Unit,1,"expected root width initial actions texts...")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
