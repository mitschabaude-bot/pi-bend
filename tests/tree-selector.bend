import Base
import ../packages/runtime/src/json.bend as Parse
import ../packages/runtime/src/word-segmenter.bend as Segmenter
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
def toolNodes(+name: String,arguments: V.Value,result: String,+missing: Bool) -> List<&2,Picker.Node()>:
  +usage = {Ai.Usage{F.fromU32(1),F.fromU32(1),F.fromU32(0),F.fromU32(0),None{},None{},F.fromU32(2),Ai.UsageCost{F.fromU32(0),F.fromU32(0),F.fromU32(0),F.fromU32(0),F.fromU32(0)}}: Ai.Usage}
  +call = {Ai.ToolCall{Bool.pick(String,missing,"other","call"),name,arguments,None{},None{}}: Ai.ToolCall<V.Value>}
  +assistant = {Tree.SessionMessageEntry{Tree.SessionEntryBase{"1",Some{"0"},"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{[Ai.AssistantToolCall{call}],"openai-responses","openai","test-model",None{},None{},None{},None{},usage,Ai.ToolUse{},None{},None{},None{},None{},F.fromU32(1)}}}}: Picker.Entry()}
  +output = {Tree.SessionMessageEntry{Tree.SessionEntryBase{"2",Some{"1"},"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"call",name,[Ai.TextImageText{Ai.TextContent{result,None{}}}],None{},None{},False{},F.fromU32(1)}}}}: Picker.Entry()}
  [Tree.SessionTreeNode{entry(0n,None{},"tool request"),[Tree.SessionTreeNode{assistant,[Tree.SessionTreeNode{output,Nil{},None{},None{}}],None{},None{}}],None{},None{}}]
def parsedNodes(result: Result<&2,&2,Parse.ParseError,V.Value>,name: String,text: String,missing: Bool) -> IO(List<&2,Picker.Node()>):
  match result:
    case Fail{_}: IO.die(List<&2,Picker.Node()>,1,"invalid tool arguments")
    case Done{arguments}: IO.pure(List<&2,Picker.Node()>,toolNodes(name,arguments,text,missing))
def fixtureNodes(shape: String,texts: List<String>) -> IO(List<&2,Picker.Node()>):
  match shape texts:
    case "tool" name <> arguments <> result <> Nil{}: parsedNodes(Parse.parse(arguments),name,result,False{})
    case "missing-tool" name <> arguments <> result <> Nil{}: parsedNodes(Parse.parse(arguments),name,result,True{})
    case _ _: IO.pure(List<&2,Picker.Node()>,nodes(sharedTexts(texts),0n,None{},shape))
def actionText(action: Picker.Action) -> String:
  match action:
    case Picker.Continue{}: "continue"
    case Picker.Cancel{}: "cancel"
    case Picker.Copied{text}: "copied:" ++ Maybe.default(&2,String,text,"<none>")
    case Picker.Chosen{id}: "chosen:" ++ id
    case Picker.LabelChanged{id,label}: "labeled:" ++ id ++ ":" ++ Maybe.default(&2,String,label,"<none>")
    case Picker.EditLabel{_,_}: "unexpected-edit-action"
    case Picker.InputError{_}: "input-error"
def textValues(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case text <> rest: V.Text{text} <> textValues(rest)
def selectedLabel(node: Maybe<&2,Picker.Node()>) -> V.Value:
  match node:
    case Some{Tree.SessionTreeNode{_,_,Some{text},_}}: V.Text{text}
    case _: V.Null{}
def emitRendered(pair: Picker.TreeSelectorComponent & List<&2,String>,action: Picker.Action) -> IO(Picker.TreeSelectorComponent):
  match pair:
    case (+component,lines):
      do IO<Picker.TreeSelectorComponent>:
        selected : V.Value = Maybe.default(&2,V.Value,Maybe.map(&2,String,V.Value,text => V.Text{text},Picker.selectedId(Picker.getTreeList(component))),V.Null{})
        value : V.Value = V.ObjectValue{R.Record{[R.Property{"selected",selected},R.Property{"label",selectedLabel(Picker.getSelectedNode(Picker.getTreeList(component)))},R.Property{"action",V.Text{actionText(action)}},R.Property{"lines",V.ArrayValue{textValues(lines)}}]}}
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
        return component
def emit(component: Picker.TreeSelectorComponent,action: Picker.Action,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(Picker.TreeSelectorComponent):
  do IO<Picker.TreeSelectorComponent>:
    pair : Picker.TreeSelectorComponent & List<&2,String> <- Picker.render(component,theme,width,bindings)
    emitRendered(pair,action)
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
    case "label": "L"
    case "word-left": "\u{1b}[1;5D"
    case "word-right": "\u{1b}[1;5C"
    case "kill-word": "\u{17}"
    case "home": "\u{1}"
    case "end": "\u{5}"
    case "kill-start": "\u{15}"
    case "kill-end": "\u{b}"
    case "yank": "\u{19}"
    case "paste-start": "\u{1b}[200~"
    case "paste-end": "\u{1b}[201~"
    case _: name
def emitted(pair: Picker.TreeSelectorComponent & Picker.Action,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(Picker.TreeSelectorComponent):
  match pair: case (component,action): emit(component,action,theme,width,bindings)
def prepared(source: Segmenter.Source,text: Maybe<&2,String>) -> IO(Segmenter.Source):
  match text: case None{}: IO.pure(Segmenter.Source,source) case Some{value}: Segmenter.readyFor(source,value)
def steps(actions: List<&2,String>,+component: Picker.TreeSelectorComponent,+source: Segmenter.Source,+theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        +data : String = key(action)
        +ready : Segmenter.Source <- prepared(source,Picker.wordText(component,bindings,Keys.defaults(),data))
        pair : Picker.TreeSelectorComponent & Picker.Action <- Picker.handleInput(component,ready,bindings,Keys.defaults(),data)
        updated : Picker.TreeSelectorComponent <- emitted(pair,theme,width,bindings)
        steps(rest,updated,ready,theme,width,bindings)
def runTheme(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,+width: Nat,+initial: String,+actions: String,shape: String,texts: List<String>,root: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +tree : List<&2,Picker.Node()> <- fixtureNodes(shape,texts)
        +component : Picker.TreeSelectorComponent = Picker.setFocused(Picker.fromList(Picker.create(tree,Bool.pick(Maybe<&2,String>,String.is_empty(initial),None{},Some{initial}),24n)),True{})
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        shown : Picker.TreeSelectorComponent <- emit(component,Picker.Continue{},theme,width,bindings)
        steps(Bool.pick(List<&2,String>,String.is_empty(actions),Nil{},String.split(actions,',')),shown,Segmenter.Pending{root ++ "/packages/runtime/data"},theme,width,bindings)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> initial <> actions <> shape <> texts:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        runTheme(theme,Maybe.default(&2,Nat,Nat.read(width),80n),initial,actions,shape,texts,root)
    case _: IO.die(Unit,1,"expected root width initial actions texts...")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
