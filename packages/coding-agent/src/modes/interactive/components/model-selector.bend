import Base
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../../../core/model-runtime.bend as Models
import ../theme/theme.bend as Theme

# A searchable, mounted catalog selector. The catalog is already limited to
# authenticated providers by ModelRuntime; selection carries the real model.
type State is Data:
  State{all: List<&2,Models.Model()>,visible: List<&2,Models.Model()>,selected: Nat,query: String,current: Maybe<&2,Models.Model()>,height: Nat}
type Action is Data: Continue{} Cancel{} Chosen{model: Models.Model()}

def sameModel(+left: Models.Model(),+right: Models.Model()) -> Bool:
  String.eq(Models.modelProvider(left),Models.modelProvider(right)) && String.eq(Models.modelId(left),Models.modelId(right))
def isCurrent(model: Models.Model(),current: Maybe<&2,Models.Model()>) -> Bool:
  match current:
    case None{}: False{}
    case Some{value}: sameModel(model,value)
def currentFirst(items: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+other: List<&2,Models.Model()>) -> List<&2,Models.Model()>:
  match items:
    case Nil{}: List.reverse(&2,Models.Model(),other)
    case +model <> +rest:
      Bool.pick(Unit -> List<&2,Models.Model()>,isCurrent(model,current),_ => model <> List.append(&2,Models.Model(),List.reverse(&2,Models.Model(),other),rest),_ => currentFirst(rest,current,model <> other))(Unit{})
def searchText(model: Models.Model()) -> String:
  match model:
    case Ai.Model{+id,name,_,+provider,_,_,_,_,_,_,_,_,_,_,_,_}: provider ++ " " ++ provider ++ "/" ++ id ++ " " ++ provider ++ " " ++ id ++ " " ++ name
def filtered(+items: List<&2,Models.Model()>,+query: String) -> List<&2,Models.Model()>:
  Bool.pick(List<&2,Models.Model()>,String.is_empty(query),items,Fuzzy.fuzzyFilter(~Models.Model(),~searchText,items,query))
def create(items: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+query: String,height: Nat) -> State:
  +ordered = currentFirst(items,current,Nil{})
  State{ordered,filtered(ordered,query),0n,query,current,Nat.max(5n,height / 2n)}
def withQuery(state: State,+query: String) -> State:
  match state:
    case State{+all,_,_,_,current,height}: State{all,filtered(all,query),0n,query,current,height}
def selected(state: State) -> Maybe<&2,Models.Model()>:
  match state: case State{_,visible,index,_,_,_}: List.get(&2,Models.Model(),visible,index)
def count(state: State) -> Nat:
  match state: case State{_,visible,_,_,_,_}: List.length(&2,Models.Model(),visible)
def queryOf(state: State) -> String:
  match state: case State{_,_,_,query,_,_}: query
def move(state: State,up: Bool) -> State:
  match state:
    case State{all,+visible,+index,query,current,height}:
      +count = List.length(&2,Models.Model(),visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),query,current,height}
def withoutFirst(text: String) -> String:
  match text: case SNil{}: "" case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: withoutFirst(String.reverse(text))
def printable(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159))
def selectFound(state: State,model: Maybe<&2,Models.Model()>) -> State & Action:
  match model:
    case None{}: (state,Continue{})
    case Some{value}: (state,Chosen{value})
def otherInput(+state: State,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),_ => (withQuery(state,withoutLast(queryOf(state))),Continue{}),
    _ => Bool.pick(Unit -> State & Action,printable(data),_ => (withQuery(state,queryOf(state) ++ data),Continue{}),_ => (state,Continue{}))(Unit{}))(Unit{})
def input(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => (move(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => (move(state,False{}),Continue{}),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => selectFound(state,selected(state)),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => (state,Cancel{}),_ => otherInput(state,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def shade(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.background(theme,key,text),text)
def line(+model: Models.Model(),current: Maybe<&2,Models.Model()>,+selected: Bool,+theme: Theme.Theme,width: Nat) -> String:
  +marker = Bool.pick(String,isCurrent(model,current)," •","")
  +name = Models.modelName(model)
  +text = Bool.pick(String,selected,"› ","  ") ++ Models.reference(model) ++ marker ++ Bool.pick(String,String.is_empty(name),"","  " ++ name)
  Utils.truncateToWidth(Bool.pick(String,selected,shade(theme,"selectedBg",paint(theme,"accent",text)),paint(theme,"muted",text)),width,"",False{})
def rows(items: List<&2,Models.Model()>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+current: Maybe<&2,Models.Model()>,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match items skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: rows(rest,skip,remaining,index + 1n,selected,current,theme,width)
    case model <> rest Zero{} Succ{remaining}:
      line(model,current,Nat.is_eq(index,selected),theme,width) <> rows(rest,0n,remaining,index + 1n,selected,current,theme,width)
def render(state: State,+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match state:
    case State{_,+visible,+index,query,current,+height}:
      +count = List.length(&2,Models.Model(),visible)
      +start = Nat.min(index - height / 2n,count - Nat.min(count,height))
      +body = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching models") <> Nil{},rows(visible,start,height,0n,index,current,theme,width))
      "" <> paint(theme,"accent","  Select Model") <> paint(theme,"warning","  Only showing models from configured providers. Use /login to add providers.") <> (paint(theme,"muted","  Search: ") ++ paint(theme,"accent",query)) <> List.append(&2,String,body,paint(theme,"muted","  (" ++ Nat.show(Bool.pick(Nat,Nat.is_eq(count,0n),0n,index + 1n)) ++ "/" ++ Nat.show(count) ++ ") · ↑/↓ select · Enter confirm · Esc cancel") <> Nil{})

type Modal is Data: Closed{} Open{state: State}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Models.Model(),Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}
def drawCurrent(current: Modal,editor: Component.Component,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}: IO.pure(List<&2,String>,render(state,theme,width))
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        chosenTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,editor,chosenTheme,width)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Models.Model(),Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,Continue{}): Ref.write(Modal,modal,Open{state})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,Chosen{model}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Models.Model(),Unit,chosen,model)
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Models.Model(),Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receiveOpen(modal,chosen,input(state,bindings,keyboard,data))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,bindings,keyboard,chosen}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,modal,editor,bindings,keyboard,chosen,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(current: Modal,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{_}: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{modal,editor,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,editor,event)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Models.Model(),Unit>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,bindings,keyboard,chosen})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host,state: State) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_}: Ref.write(Modal,modal,Open{state})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
