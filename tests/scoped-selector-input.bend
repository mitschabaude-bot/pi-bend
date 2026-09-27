import Base
import ../packages/coding-agent/src/modes/interactive/components/scoped-models-selector.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/components/input.bend as Input
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def model(provider: String,+id: String) -> Models.Model():
  Ai.Model{id,"Display " ++ id,Ai.OpenAIResponsesApi{},provider,"https://example.invalid",False{},None{},[Ai.InputText{}],None{},Ai.ModelCost{U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),None{}},None{},U32.to_f64(10000),U32.to_f64(1000),None{},None{},None{}}
def models() -> List<&2,Models.Model()>:
  [model("zeta","last"),model("alpha","a-long-model-name-with-dashes"),model("alpha","other"),model("éclair","accent"),model("alpha_beta","under"),model("alpha-beta","dash"),model("中","模型"),model("alpha","mini"),model("alpha","max"),model("alpha","extra"),model("alpha","eleven"),model("alpha","twelve")]
def catalog(flag: String) -> List<&2,Models.Model()>:
  match flag: case "1": Nil{} case "3": List.take(&2,Models.Model(),models(),3n) case _: models()
def scope(value: String) -> P.Scope:
  match value: case "all": P.All{} case "": P.Selected{Nil{}} case value: P.Selected{String.split(value,',')}
def actionText(action: P.Action) -> String:
  match action: case P.Continue{}: "continue" case P.Cancel{}: "cancel" case P.Changed{_}: "changed" case P.Save{_}: "save"
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def optionalBool(value: Maybe<&2,Bool>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Boolean{value}
def response(value: Maybe<&2,T.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{T.TuiMouseEventResult{handled,capture,focus,render}}:
      object([R.Property{"handled",V.Boolean{handled}},R.Property{"capture",V.Boolean{capture}},R.Property{"focus",V.Boolean{focus}},R.Property{"render",optionalBool(render)}])
def selectedValue(value: Maybe<&2,P.Item>) -> V.Value:
  match value: case None{}: V.Null{} case Some{P.Item{id,_,_}}: V.Text{id}
def texts(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines: case Nil{}: Nil{} case line <> rest: V.Text{line} <> texts(rest)
def scopeValue(value: P.Scope) -> V.Value:
  match value: case P.All{}: V.Null{} case P.Selected{ids}: V.ArrayValue{texts(ids)}
def cursor(state: P.State) -> Nat: Input.getCursor(P.searchOf(state))
def emitted(pair: P.State & List<&2,String>,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>) -> IO(P.State):
  match pair:
    case (+state,lines):
      do IO<P.State>:
        value : V.Value = object([R.Property{"selected",selectedValue(P.selectedItem(state))},R.Property{"query",V.Text{Input.getValue(P.searchOf(state))}},R.Property{"cursor",V.Number{U32.to_f64(U32.from_nat(cursor(state)))}},R.Property{"scope",scopeValue(P.scopeOf(state))},R.Property{"action",V.Text{actionText(action)}},R.Property{"response",response(result)},R.Property{"lines",V.ArrayValue{texts(lines)}}])
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
        return state
def show(+state: P.State,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(P.State):
  do IO<P.State>:
    pair : P.State & List<&2,String> <- P.render(state,theme,bindings,width)
    emitted(pair,action,result)
def mouseResponse(value: Maybe<&2,C.MouseResponse>) -> Maybe<&2,T.TuiMouseEventResult>:
  match value: case Some{C.LocalResult{result}}: Some{result} case _: None{}
def mousePair(pair: P.State & Maybe<&2,C.MouseResponse>) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match pair: case (state,response): (state,P.Continue{},mouseResponse(response))
def mouse(+state: P.State,+width: Nat,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,parts: List<&2,String>) -> IO(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>):
  match parts:
    case zone <> x <> _:
      do IO<P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>>:
        header : List<&2,String> <- P.heading(theme,bindings,width)
        +column : T.Offset = T.Forward{Maybe.default(&2,Nat,Nat.read(x),0n)}
        +row : Nat = List.length(&2,String,header)
        +line : T.Offset = T.Forward{Bool.pick(Nat,String.eq(zone,"search"),row,row + 2n)}
        return mousePair(P.mouseSearch(state,row,T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},column,line,column,line,width,1000n,False{},False{},False{},None{},None{}}))
    case _: IO.pure(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,(state,P.Continue{},None{}))
def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "right": "\u{1b}[C" case "home": "\u{1}" case "end": "\u{5}" case "backspace": "\u{7f}" case "delete": "\u{1b}[3~" case "wordLeft": "\u{1b}b" case "wordRight": "\u{1b}f" case "killWord": "\u{17}" case "yank": "\u{19}" case "undo": "\u{1f}" case "ctrlC": "\u{3}" case "enableAll": "\u{1}" case "clearAll": "\u{18}" case "provider": "\u{10}" case "reorderUp": "\u{1b}[1;3A" case "reorderDown": "\u{1b}[1;3B" case "tab": "\t" case "save": "\u{13}" case value: value
def inputPair(pair: P.State & P.Action) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match pair: case (state,action): (state,action,None{})
def focusPair(pair: P.Modal & Unit) -> IO(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>):
  match pair:
    case (P.Open{state},_): IO.pure(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,(state,P.Continue{},None{}))
    case _: IO.die(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,1,"focus unexpectedly closed the selector")
def step(+state: P.State,width: Nat,source: W.Source,bindings: Bindings.KeybindingsManager,theme: Theme.Theme,parts: List<&2,String>) -> IO(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>):
  match parts:
    case "focus" <> flag <> _: focusPair(P.focusedModal(P.Open{state},String.eq(flag,"1")))
    case "mouse" <> rest: mouse(state,width,theme,bindings,rest)
    case "key" <> "refresh" <> _: IO.pure(P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>,(P.updateModels(state,List.reverse(&2,Models.Model(),P.modelsOf(state)),"Refreshing model catalogs…"),P.Continue{},None{}))
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
        pair : P.State & P.Action & Maybe<&2,T.TuiMouseEventResult> <- step(state,width,source,bindings,theme,String.split(action,'|'))
        updated : P.State <- next(pair,theme,width,bindings)
        steps(rest,updated,theme,width,source,bindings)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,root: String,+width: Nat,enabled: String,+empty: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load scoped selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        +source : W.Source <- W.readyFor(W.Pending{root ++ "/packages/runtime/data"},"English word commands")
        state : P.State <- show(P.create(catalog(empty),scope(enabled),Bool.pick(String,String.eq(empty,"3"),"","Refreshing model catalogs…")),P.Continue{},None{},theme,width,bindings)
        steps(actions,state,theme,width,source,bindings)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> enabled <> empty <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),enabled,empty,actions)
    case _: IO.die(Unit,1,"expected root width enabled empty actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
