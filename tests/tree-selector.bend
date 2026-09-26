import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/f64.bend as F
import ../packages/coding-agent/src/core/session-manager.bend as Tree
import ../packages/coding-agent/src/modes/interactive/components/tree-selector.bend as Picker
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def sharedTexts(texts: List<String>) -> List<&2,String>:
  match texts: case Nil{}: Nil{} case text <> rest: text <> sharedTexts(rest)
def entry(index: Nat,parent: Maybe<&2,String>,text: String) -> Picker.Entry():
  Tree.SessionMessageEntry{Tree.SessionEntryBase{Nat.show(index),parent,"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F.fromU32(1)}}}}
def metadata(+index: Nat,children: List<&2,Picker.Node()>) -> Picker.Node():
  Tree.SessionTreeNode{Tree.ModelChangeEntry{Tree.SessionEntryBase{"m" ++ Nat.show(index),Some{Nat.show(index)},"2025-01-01T00:00:00Z"},"test","test-model"},children,None{},None{}}
def nodes(texts: List<&2,String>,+index: Nat,+parent: Maybe<&2,String>,+shape: String) -> List<&2,Picker.Node()>:
  match texts:
    case Nil{}: Nil{}
    case text <> +rest:
      +id = Nat.show(index)
      +value = entry(index,parent,text)
      +hidden = String.eq(shape,"hidden") || String.eq(shape,"hidden-star")
      +parentId = Bool.pick(String,hidden,"m" ++ id,id)
      +children = Bool.pick(Unit -> List<&2,Picker.Node()>,String.eq(shape,"roots"),_ => Nil{},_ => nodes(rest,index + 1n,Some{parentId},Bool.pick(String,String.eq(shape,"star") || String.eq(shape,"hidden-star"),"roots",shape)))(Unit{})
      +siblings = Bool.pick(Unit -> List<&2,Picker.Node()>,String.eq(shape,"roots"),_ => nodes(rest,index + 1n,parent,shape),_ => Nil{})(Unit{})
      Tree.SessionTreeNode{value,Bool.pick(List<&2,Picker.Node()>,hidden,metadata(index,children) <> Nil{},children),None{},None{}} <> siblings
def actionText(action: Picker.Action) -> String:
  match action:
    case Picker.Continue{}: "continue"
    case Picker.Cancel{}: "cancel"
    case Picker.Copied{text}: "copied:" ++ Maybe.default(&2,String,text,"<none>")
    case Picker.Chosen{id}: "chosen:" ++ id
def textValues(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case text <> rest: V.Text{text} <> textValues(rest)
def emit(component: Picker.TreeSelectorComponent,action: Picker.Action,+theme: Theme.Theme,width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  do IO<Unit>:
    +copy : Picker.TreeSelectorComponent = component
    lines : List<&2,String> <- Picker.render(copy,theme,width,bindings)
    selected : V.Value = Maybe.default(&2,V.Value,Maybe.map(&2,String,V.Value,text => V.Text{text},Picker.selectedId(Picker.getTreeList(copy))),V.Null{})
    value : V.Value = V.ObjectValue{R.Record{[R.Property{"selected",selected},R.Property{"action",V.Text{actionText(action)}},R.Property{"lines",V.ArrayValue{textValues(lines)}}]}}
    IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
def key(name: String) -> String:
  match name:
    case "up": "\u{1b}[A"
    case "down": "\u{1b}[B"
    case "enter": "\r"
    case "escape": "\u{1b}"
    case "left": "\u{1b}[D"
    case "right": "\u{1b}[C"
    case "fold": "\u{1b}[1;5D"
    case "unfold": "\u{1b}[1;5C"
    case "all": "\u{1}"
    case "default": "\u{4}"
    case "no-tools": "\u{14}"
    case "user": "\u{15}"
    case "labeled": "\u{c}"
    case "cycle": "\u{f}"
    case "copy": "\u{18}"
    case "backspace": "\u{7f}"
    case _: name
def emitted(pair: Picker.TreeList & Picker.Action,+theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(Picker.TreeList):
  match pair:
    case Tuple{+list,action}:
      do IO<Picker.TreeList>:
        emit(Picker.TreeSelectorComponent{list},action,theme,width,bindings)
        return list
def steps(actions: List<&2,String>,+list: Picker.TreeList,+theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        updated : Picker.TreeList <- emitted(Picker.input(list,bindings,Keys.defaults(),key(action)),theme,width,bindings)
        steps(rest,updated,theme,width,bindings)
def runTheme(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,+width: Nat,+initial: String,+actions: String,shape: String,texts: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +component : Picker.TreeSelectorComponent = Picker.TreeSelectorComponent{Picker.create(nodes(sharedTexts(texts),0n,None{},shape),Bool.pick(Maybe<&2,String>,String.is_empty(initial),None{},Some{initial}),24n)}
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        emit(component,Picker.Continue{},theme,width,bindings)
        steps(Bool.pick(List<&2,String>,String.is_empty(actions),Nil{},String.split(actions,',')),Picker.getTreeList(component),theme,width,bindings)
def run(args: List<String>) -> IO(Unit):
  match args:
    case root <> width <> initial <> actions <> shape <> texts:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        runTheme(theme,Maybe.default(&2,Nat,Nat.read(width),80n),initial,actions,shape,texts)
    case _: IO.die(Unit,1,"expected root width initial actions texts...")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
