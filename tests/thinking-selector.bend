import Base
import ../packages/coding-agent/src/modes/interactive/components/thinking-selector.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/thinking-levels.bend as Levels
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def level(text: String) -> Ai.ModelThinkingLevel:
  match text:
    case "off": Ai.Off{}
    case "minimal": Ai.Thinking{Ai.Minimal{}}
    case "low": Ai.Thinking{Ai.Low{}}
    case "medium": Ai.Thinking{Ai.Medium{}}
    case "high": Ai.Thinking{Ai.High{}}
    case "xhigh": Ai.Thinking{Ai.XHigh{}}
    case _: Ai.Thinking{Ai.Max{}}
def levels(items: List<&2,String>) -> List<&2,Ai.ModelThinkingLevel>:
  match items: case Nil{}: Nil{} case text <> rest: level(text) <> levels(rest)
def actionText(action: P.Action) -> String:
  match action:
    case P.Continue{}: "continue"
    case P.Cancel{}: "cancel"
    case P.Chosen{value,persist}: Bool.pick(String,persist,"default:","chosen:") ++ Levels.name(value)
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def optionalBool(value: Maybe<&2,Bool>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Boolean{value}
def response(value: Maybe<&2,T.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{T.TuiMouseEventResult{handled,capture,focus,render}}:
      object([R.Property{"handled",V.Boolean{handled}},R.Property{"capture",V.Boolean{capture}},R.Property{"focus",V.Boolean{focus}},R.Property{"render",optionalBool(render)}])
def selectedValue(value: Maybe<&2,Ai.ModelThinkingLevel>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Text{Levels.name(value)}
def texts(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines: case Nil{}: Nil{} case line <> rest: V.Text{line} <> texts(rest)
def emitted(pair: P.State & List<&2,String>,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>) -> IO(P.State):
  match pair:
    case (+state,lines):
      do IO<P.State>:
        value : V.Value = object([R.Property{"selected",selectedValue(P.currentSelection(state))},R.Property{"action",V.Text{actionText(action)}},R.Property{"response",response(result)},R.Property{"lines",V.ArrayValue{texts(lines)}}])
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
        return state
def show(+state: P.State,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(P.State):
  do IO<P.State>:
    pair : P.State & List<&2,String> <- P.rendered(state,theme,bindings,width)
    emitted(pair,action,result)
def offset(parts: List<&2,String>) -> T.Offset:
  match parts:
    case "n" <> value <> _: T.Backward{Maybe.default(&2,Nat,Nat.read(value),0n)}
    case _ <> value <> _: T.Forward{Maybe.default(&2,Nat,Nat.read(value),0n)}
    case _: T.Forward{0n}
def relative(+base: Nat,value: T.Offset) -> T.Offset:
  match value:
    case T.Forward{value}: T.Forward{base + value}
    case T.Backward{+value}: Bool.pick(T.Offset,Nat.is_lt(base,value),T.Backward{value - base},T.Forward{base - value})
def row(state: P.State,zone: String,value: T.Offset) -> T.Offset:
  match state zone:
    case P.State{_,_,_,_,_,_,Some{P.Layout{_,search,_,_}}} "search": relative(search,value)
    case P.State{_,_,_,_,_,_,Some{P.Layout{_,_,list,_}}} "list": relative(list,value)
    case _ _: value
def kind(value: String) -> T.TuiMouseEventType:
  match value: case "press": T.MousePress{} case "click": T.MouseClick{} case "wheel": T.MouseWheel{} case "move": T.MouseMove{} case _: T.MouseRelease{}
def button(value: String) -> T.TuiMouseButton:
  match value: case "right": T.MouseRight{} case "none": T.NoButton{} case _: T.MouseLeft{}
def mouse(+state: P.State,width: Nat,parts: List<&2,String>) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match parts:
    case tag <> zone <> y <> x <> +delta <> btn <> _:
      +column = offset(String.split(x,':'))
      +line = row(state,zone,offset(String.split(y,':')))
      P.handleMouse(state,T.TuiMouseEvent{kind(tag),button(btn),column,line,column,line,width,1000n,False{},False{},False{},Bool.pick(Maybe<&2,T.Offset>,String.is_empty(delta),None{},Some{offset(String.split(delta,':'))}),Some{1n}})
    case _: (state,P.Continue{},None{})
def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "save": "\u{13}" case value: value
def inputPair(pair: P.State & P.Action) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match pair: case (state,action): (state,action,None{})
def step(+state: P.State,width: Nat,source: W.Source,bindings: Bindings.KeybindingsManager,parts: List<&2,String>) -> IO(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>):
  match parts:
    case "mouse" <> rest: IO.pure(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,mouse(state,width,rest))
    case "key" <> value <> _:
      do IO<P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>>:
        pair : P.State & P.Action <- P.input(state,source,bindings,Keys.defaults(),key(value))
        return inputPair(pair)
    case _: IO.pure(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,(state,P.Continue{},None{}))
def next(pair: P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(P.State):
  match pair: case (state,action,result): show(state,action,result,theme,width,bindings)
def steps(actions: List<String>,state: P.State,+theme: Theme.Theme,+width: Nat,+source: W.Source,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        pair : P.State & P.Action & Maybe<&2,T.TuiMouseEventResult> <- step(state,width,source,bindings,String.split(action,'|'))
        updated : P.State <- next(pair,theme,width,bindings)
        steps(rest,updated,theme,width,source,bindings)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,root: String,+width: Nat,current: String,+defaultLevel: String,+names: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load thinking selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        state : P.State <- show(P.createWithDefault(Bool.pick(List<&2,Ai.ModelThinkingLevel>,String.is_empty(names),Nil{},levels(String.split(names,','))),level(current),Bool.pick(Maybe<&2,Ai.ModelThinkingLevel>,String.eq(defaultLevel,"-"),None{},Some{level(defaultLevel)})),P.Continue{},None{},theme,width,bindings)
        steps(actions,state,theme,width,W.Pending{root ++ "/packages/runtime/data"},bindings)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> current <> defaultLevel <> names <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),current,defaultLevel,names,actions)
    case _: IO.die(Unit,1,"expected root width current default levels actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
