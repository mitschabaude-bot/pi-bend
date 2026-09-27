import Base
import ../packages/coding-agent/src/modes/interactive/components/model-selector.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/runtime/src/collation.bend as Collation
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
def at(index: String) -> Maybe<&2,Models.Model()>: List.get(&2,Models.Model(),models(),Maybe.default(&2,Nat,Nat.read(index),100n))
def scoped(items: List<&2,String>) -> List<&2,Models.Model()>:
  match items: case Nil{}: Nil{} case index <> rest: List.append(&2,Models.Model(),Maybe.default(&2,List<&2,Models.Model()>,Maybe.map(&2,Models.Model(),List<&2,Models.Model()>,value => [value],at(index)),Nil{}),scoped(rest))
def actionText(action: P.Action) -> String:
  match action:
    case P.Continue{}: "continue"
    case P.Cancel{}: "cancel"
    case P.Chosen{value,persist}: Bool.pick(String,persist,"default:","chosen:") ++ Models.reference(value)
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def optionalBool(value: Maybe<&2,Bool>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Boolean{value}
def response(value: Maybe<&2,T.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{T.TuiMouseEventResult{handled,capture,focus,render}}:
      object([R.Property{"handled",V.Boolean{handled}},R.Property{"capture",V.Boolean{capture}},R.Property{"focus",V.Boolean{focus}},R.Property{"render",optionalBool(render)}])
def selectedValue(value: Maybe<&2,Models.Model()>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Text{Models.reference(value)}
def texts(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines: case Nil{}: Nil{} case line <> rest: V.Text{line} <> texts(rest)
def cursor(state: P.State) -> Nat:
  match state: case P.State{_,_,_,_,search,_,_,_,_,_}: Input.getCursor(search)
def emitted(pair: P.State & List<&2,String>,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>) -> IO(P.State):
  match pair:
    case (+state,lines):
      do IO<P.State>:
        value : V.Value = object([R.Property{"selected",selectedValue(P.selected(state))},R.Property{"query",V.Text{P.queryOf(state)}},R.Property{"cursor",V.Number{U32.to_f64(U32.from_nat(cursor(state)))}},R.Property{"action",V.Text{actionText(action)}},R.Property{"response",response(result)},R.Property{"lines",V.ArrayValue{texts(lines)}}])
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(value)),"null"))
        return state
def show(+state: P.State,action: P.Action,result: Maybe<&2,T.TuiMouseEventResult>,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(P.State):
  do IO<P.State>:
    pair : P.State & List<&2,String> <- P.render(state,theme,bindings,width)
    emitted(pair,action,result)
def row(state: P.State,zone: String) -> Nat:
  match state zone:
    case P.State{_,_,_,_,_,_,_,_,_,Some{row}} "search": row
    case P.State{_,_,_,_,_,_,_,_,_,Some{row}} _: row + 2n
    case _ _: 0n
def mouseResponse(value: Maybe<&2,C.MouseResponse()>) -> Maybe<&2,T.TuiMouseEventResult>:
  match value: case Some{C.LocalResult{result}}: Some{result} case _: None{}
def mousePair(pair: P.State & Maybe<&2,C.MouseResponse()>) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match pair: case (state,response): (state,P.Continue{},mouseResponse(response))
def mouse(+state: P.State,width: Nat,parts: List<&2,String>) -> P.State & P.Action & Maybe<&2,T.TuiMouseEventResult>:
  match parts:
    case zone <> x <> _:
      +column = {T.Forward{Maybe.default(&2,Nat,Nat.read(x),0n)}: T.Offset}
      +line = {T.Forward{row(state,zone)}: T.Offset}
      mousePair(P.mouseSearch(state,T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},column,line,column,line,width,1000n,False{},False{},False{},None{},None{}}))
    case _: (state,P.Continue{},None{})
def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "right": "\u{1b}[C" case "home": "\u{1}" case "end": "\u{5}" case "backspace": "\u{7f}" case "delete": "\u{1b}[3~" case "wordLeft": "\u{1b}b" case "wordRight": "\u{1b}f" case "killWord": "\u{17}" case "yank": "\u{19}" case "undo": "\u{1f}" case "tab": "\t" case "save": "\u{13}" case value: value
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
def prepared(root: String,+width: Nat,current: String,defaultModel: String,+scope: String,query: String,empty: String,actions: List<String>,+theme: Theme.Theme,result: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load model selector collation")
    case Done{collator}:
      do IO<Unit>:
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        +source : W.Source <- W.readyFor(W.Pending{root ++ "/packages/runtime/data"},"English word commands")
        state : P.State <- show(P.sortedState(P.createScoped(Bool.pick(List<&2,Models.Model()>,String.eq(empty,"1"),Nil{},models()),Bool.pick(List<&2,Models.Model()>,String.is_empty(scope),Nil{},scoped(String.split(scope,','))),at(current),query,Maybe.map(&2,Models.Model(),String,value => Models.reference(value),at(defaultModel))),collator),P.Continue{},None{},theme,width,bindings)
        steps(actions,state,theme,width,source,bindings)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,+root: String,width: Nat,current: String,defaultModel: String,+scope: String,query: String,empty: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load model selector theme")
    case Done{theme}:
      do IO<Unit>:
        collator : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(root ++ "/packages/runtime/data")
        prepared(root,width,current,defaultModel,scope,query,empty,actions,theme,collator)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> current <> defaultModel <> scope <> query <> empty <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),current,defaultModel,scope,query,empty,actions)
    case _: IO.die(Unit,1,"expected root width current default scope query empty actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
