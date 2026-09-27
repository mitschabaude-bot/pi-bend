import Base
import ../packages/coding-agent/src/modes/interactive/components/login-dialog.bend as P
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/components/input.bend as Input
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/tui.bend as T
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def optionalBool(value: Maybe<&2,Bool>) -> V.Value:
  match value: case None{}: V.Null{} case Some{value}: V.Boolean{value}
def response(value: Maybe<&2,T.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{T.TuiMouseEventResult{handled,capture,focus,render}}:
      object([R.Property{"handled",V.Boolean{handled}},R.Property{"capture",V.Boolean{capture}},R.Property{"focus",V.Boolean{focus}},R.Property{"render",optionalBool(render)}])
def texts(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines: case Nil{}: Nil{} case line <> rest: V.Text{line} <> texts(rest)

def choice(+id: String,+name: String,+kind: Auth.CredentialType,+method: String,status: String) -> P.Choice:
  +label = Auth.typeName(kind)
  P.Choice{P.AuthChoice{P.ProviderSelection{id,kind}},name,status,name ++ " " ++ id ++ " " ++ label ++ " " ++ method}
def choices() -> List<&2,P.Choice>:
  [choice("anthropic","Anthropic",Auth.OAuthType{},"Claude account"," ✓ configured"),
   choice("anthropic","Anthropic",Auth.ApiKeyType{},"Anthropic API key"," • subscription configured"),
   choice("openai","OpenAI",Auth.ApiKeyType{},"OpenAI API key"," ✓ env: OPENAI_API_KEY"),
   choice("local-proxy","local-proxy",Auth.ApiKeyType{},"Proxy token"," ✓ key in models.json"),
   choice("command-proxy","command-proxy",Auth.ApiKeyType{},"Shell credential"," ✓ command in models.json"),
   choice("google","Google",Auth.ApiKeyType{},"Google Cloud credentials"," • unconfigured"),
   choice("long","A very long provider name that should be truncated",Auth.OAuthType{},"Long account"," • unconfigured"),
   choice("中","日本語",Auth.OAuthType{},"Account"," • API key configured"),
   choice("nine","Nine",Auth.ApiKeyType{},"Token"," ✓ configured"),
   choice("ten","Ten",Auth.OAuthType{},"Account"," • unconfigured")]
def selected(value: Maybe<&2,P.Choice>) -> V.Value:
  match value:
    case Some{P.Choice{P.AuthChoice{P.ProviderSelection{id,kind}},_,_,_}}: V.Text{id ++ "/" ++ Auth.typeName(kind)}
    case _: V.Null{}
def emitted(current: P.State,lines: List<&2,String>,result: Maybe<&2,T.TuiMouseEventResult>) -> IO(Unit):
  match current:
    case P.Choosing{_,_,_,visible,index,+query}:
      IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(object([R.Property{"selected",selected(List.get(&2,P.Choice,visible,index))},R.Property{"query",V.Text{Input.getValue(query)}},R.Property{"cursor",V.Number{U32.to_f64(U32.from_nat(Input.getCursor(query)))}},R.Property{"response",response(result)},R.Property{"lines",V.ArrayValue{texts(lines)}}]))),"null"))
    case _: IO.die(Unit,1,"selector unexpectedly closed")
def shown(+state: Ref.Ref<P.State>,theme: Theme.Theme,width: Nat,result: Maybe<&2,T.TuiMouseEventResult>) -> IO(Unit):
  do IO<Unit>:
    current : P.State <- Ref.read(P.State,state)
    pair : P.State & List<&2,String> <- P.renderProvider(current,theme,width)
    +lines : List<&2,String> <- P.providerStored(state,pair)
    updated : P.State <- Ref.read(P.State,state)
    emitted(updated,lines,result)
def key(value: String) -> String:
  match value: case "up": "\u{1b}[A" case "down": "\u{1b}[B" case "enter": "\r" case "escape": "\u{1b}" case "left": "\u{1b}[D" case "right": "\u{1b}[C" case "home": "\u{1}" case "end": "\u{5}" case "backspace": "\u{7f}" case "delete": "\u{1b}[3~" case "wordLeft": "\u{1b}b" case "wordRight": "\u{1b}f" case "killWord": "\u{17}" case "yank": "\u{19}" case "undo": "\u{1f}" case "tab": "\t" case "save": "\u{13}" case value: value

def keyboard(current: P.State,state: Ref.Ref<P.State>,reply: Ref.Ref<Maybe<&2,P.Pending>>,words: Ref.Ref<W.Source>,bindings: Bindings.KeybindingsManager,data: String) -> IO(Unit):
  match current:
    case P.Choosing{menu,title,all,visible,index,query}: P.menuInput(state,reply,bindings,Keys.defaults(),menu,title,all,visible,index,query,data,words)
    case _: IO.die(Unit,1,"selector unexpectedly closed")
def mouseResponse(value: Maybe<&2,C.MouseResponse>) -> Maybe<&2,T.TuiMouseEventResult>:
  match value: case Some{C.LocalResult{result}}: Some{result} case _: None{}
def mouseResult(pair: P.State & Maybe<&2,C.MouseResponse>,state: Ref.Ref<P.State>) -> IO(Maybe<&2,T.TuiMouseEventResult>):
  match pair:
    case (current,response):
      do IO<Maybe<&2,T.TuiMouseEventResult>>:
        Ref.write(P.State,state,current)
        return mouseResponse(response)
def step(+state: Ref.Ref<P.State>,reply: Ref.Ref<Maybe<&2,P.Pending>>,words: Ref.Ref<W.Source>,bindings: Bindings.KeybindingsManager,+width: Nat,parts: List<&2,String>) -> IO(Maybe<&2,T.TuiMouseEventResult>):
  match parts:
    case "mouse" <> zone <> x <> _:
      do IO<Maybe<&2,T.TuiMouseEventResult>>:
        current : P.State <- Ref.read(P.State,state)
        +column : T.Offset = T.Forward{Maybe.default(&2,Nat,Nat.read(x),0n)}
        +row : T.Offset = T.Forward{Bool.pick(Nat,String.eq(zone,"search"),4n,6n)}
        mouseResult(P.providerMouse(current,T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},column,row,column,row,width,1000n,False{},False{},False{},None{},None{}}),state)
    case "focus" <> flag <> _:
      do IO<Maybe<&2,T.TuiMouseEventResult>>:
        Ref.modify(P.State,Unit,state,current => P.focusedState(current,String.eq(flag,"1")))
        return None{}
    case "key" <> data <> _:
      do IO<Maybe<&2,T.TuiMouseEventResult>>:
        current : P.State <- Ref.read(P.State,state)
        keyboard(current,state,reply,words,bindings,key(data))
        return None{}
    case _: IO.pure(Maybe<&2,T.TuiMouseEventResult>,None{})
def steps(actions: List<String>,+state: Ref.Ref<P.State>,+reply: Ref.Ref<Maybe<&2,P.Pending>>,+words: Ref.Ref<W.Source>,+bindings: Bindings.KeybindingsManager,+theme: Theme.Theme,+width: Nat) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        result : Maybe<&2,T.TuiMouseEventResult> <- step(state,reply,words,bindings,width,String.split(action,'|'))
        shown(state,theme,width,result)
        steps(rest,state,reply,words,bindings,theme,width)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,root: String,+width: Nat,mode: String,empty: String,+query: String,actions: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load provider selector theme")
    case Done{+theme}:
      do IO<Unit>:
        +all : List<&2,P.Choice> = Bool.pick(List<&2,P.Choice>,String.eq(empty,"1"),Nil{},choices())
        +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
        +state : Ref.Ref<P.State> <- Ref.new(P.State,P.Choosing{P.Provider{},Bool.pick(String,String.eq(mode,"logout"),"Select provider to logout:","Select provider to configure:"),all,P.filtered(all,query),0n,Input.setFocused(Input.setValue(Input.new(None{}),query),True{})})
        +reply : Ref.Ref<Maybe<&2,P.Pending>> <- Ref.new(Maybe<&2,P.Pending>,None{})
        +words : Ref.Ref<W.Source> <- Ref.new(W.Source,W.Pending{root ++ "/packages/runtime/data"})
        shown(state,theme,width,None{})
        steps(actions,state,reply,words,bindings,theme,width)
        discarded : P.State <- Ref.dispose(P.State,state)
        pending : Maybe<&2,P.Pending> <- Ref.dispose(Maybe<&2,P.Pending>,reply)
        unused : W.Source <- Ref.dispose(W.Source,words)
        return Unit{}
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> width <> mode <> empty <> query <> actions:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,root,Maybe.default(&2,Nat,Nat.read(width),80n),mode,empty,query,actions)
    case _: IO.die(Unit,1,"expected root width mode empty query actions")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
