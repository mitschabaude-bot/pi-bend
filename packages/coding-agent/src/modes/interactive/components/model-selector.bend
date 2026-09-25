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
import ../model-search.bend as Search
import ./keybinding-hints.bend as Hints

# A searchable, mounted catalog selector. The catalog is already limited to
# authenticated providers by ModelRuntime; selection carries the real model.
type State is Data:
  State{all: List<&2,Models.Model()>,scoped: List<&2,Models.Model()>,visible: List<&2,Models.Model()>,selected: Nat,query: String,current: Maybe<&2,Models.Model()>,defaultRef: Maybe<&2,String>,scopedMode: Bool,status: String}
type Action is Data: Continue{} Cancel{} Chosen{model: Models.Model(),persist: Bool}
type Choice is Data: Choice{model: Models.Model(),persist: Bool}

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
def filtered(+items: List<&2,Models.Model()>,+query: String) -> List<&2,Models.Model()>:
  Bool.pick(List<&2,Models.Model()>,String.is_empty(query),items,Fuzzy.fuzzyFilter(~Models.Model(),~Search.modelSelectorText,items,query))
def currentIndex(items: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+index: Nat) -> Nat:
  match items:
    case Nil{}: 0n
    case model <> rest:
      Bool.pick(Unit -> Nat,isCurrent(model,current),_ => index,_ => currentIndex(rest,current,index + 1n))(Unit{})
def hasScope(items: List<&2,Models.Model()>) -> Bool: Bool.not(List.is_empty(&2,Models.Model(),items))
def hasScopeOf(state: State) -> Bool:
  match state: case State{_,scoped,_,_,_,_,_,_,_}: hasScope(scoped)
def initial(items: List<&2,Models.Model()>,+scoped: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+query: String,defaultRef: Maybe<&2,String>,status: String) -> State:
  +ordered = currentFirst(items,current,Nil{})
  +scope = hasScope(scoped)
  +active = Bool.pick(List<&2,Models.Model()>,scope,scoped,ordered)
  +visible = filtered(active,query)
  +selected = Bool.pick(Nat,String.is_empty(query),currentIndex(visible,current,0n),0n)
  State{ordered,scoped,visible,selected,query,current,defaultRef,scope,status}
def create(items: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: String,_height: Nat) -> State:
  initial(items,Nil{},current,query,None{},"")
def createScoped(items: List<&2,Models.Model()>,scoped: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: String,defaultRef: Maybe<&2,String>) -> State:
  initial(items,scoped,current,query,defaultRef,"Refreshing model catalogs…")
def withQuery(state: State,+query: String) -> State:
  match state:
    case State{+all,+scoped,_,_,_,current,defaultRef,+mode,status}:
      +active = Bool.pick(List<&2,Models.Model()>,mode,scoped,all)
      State{all,scoped,filtered(active,query),0n,query,current,defaultRef,mode,status}
def toggled(state: State) -> State:
  match state:
    case State{+all,+scoped,_,_,+query,+current,defaultRef,+mode,status}:
      +next = Bool.not(mode)
      +active = Bool.pick(List<&2,Models.Model()>,next,scoped,all)
      +visible = filtered(active,query)
      +selected = Bool.pick(Nat,String.is_empty(query),currentIndex(visible,current,0n),0n)
      State{all,scoped,visible,selected,query,current,defaultRef,next,status}
def toggleIfScoped(+state: State) -> State:
  Bool.pick(Unit -> State,hasScopeOf(state),_ => toggled(state),_ => state)(Unit{})
def refreshedState(state: State,models: List<&2,Models.Model()>,status: String) -> State:
  match state:
    case State{_,+scoped,_,_,+query,+current,defaultRef,+mode,_}:
      +ordered = currentFirst(models,current,Nil{})
      +active = Bool.pick(List<&2,Models.Model()>,mode,scoped,ordered)
      +visible = filtered(active,query)
      +index = Bool.pick(Nat,String.is_empty(query),currentIndex(visible,current,0n),0n)
      State{ordered,scoped,visible,index,query,current,defaultRef,mode,status}
def selected(state: State) -> Maybe<&2,Models.Model()>:
  match state: case State{_,_,visible,index,_,_,_,_,_}: List.get(&2,Models.Model(),visible,index)
def count(state: State) -> Nat:
  match state: case State{_,_,visible,_,_,_,_,_,_}: List.length(&2,Models.Model(),visible)
def queryOf(state: State) -> String:
  match state: case State{_,_,_,_,query,_,_,_,_}: query
def move(state: State,up: Bool) -> State:
  match state:
    case State{all,scoped,+visible,+index,query,current,defaultRef,mode,status}:
      +count = List.length(&2,Models.Model(),visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{all,scoped,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),query,current,defaultRef,mode,status}
def withoutFirst(text: String) -> String:
  match text: case SNil{}: "" case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: withoutFirst(String.reverse(text))
def printable(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159))
def selectFound(state: State,model: Maybe<&2,Models.Model()>,persist: Bool) -> State & Action:
  match model:
    case None{}: (state,Continue{})
    case Some{value}: (state,Chosen{value,persist})
def otherInput(+state: State,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),_ => (withQuery(state,withoutLast(queryOf(state))),Continue{}),
    _ => Bool.pick(Unit -> State & Action,printable(data),_ => (withQuery(state,queryOf(state) ++ data),Continue{}),_ => (state,Continue{}))(Unit{}))(Unit{})
def input(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.models.save"),_ => selectFound(state,selected(state),True{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.input.tab"),_ => (toggleIfScoped(state),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => (move(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => (move(state,False{}),Continue{}),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => selectFound(state,selected(state),False{}),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => (state,Cancel{}),_ => otherInput(state,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def shade(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.background(theme,key,text),text)
def isDefault(model: Models.Model(),defaultRef: Maybe<&2,String>) -> Bool:
  match defaultRef:
    case None{}: False{}
    case Some{reference}: String.eq(Models.reference(model),reference)
def line(+model: Models.Model(),current: Maybe<&2,Models.Model()>,defaultRef: Maybe<&2,String>,+selected: Bool,+theme: Theme.Theme,width: Nat) -> String:
  +cursor = Bool.pick(String,selected,paint(theme,"accent","→ "),"  ")
  +marker = Bool.pick(String,isCurrent(model,current),paint(theme,"accent","✓ "),"  ")
  +id = Models.modelId(model)
  +name = Bool.pick(String,selected,paint(theme,"accent",id),id)
  +provider = " " ++ paint(theme,"muted","[" ++ Models.modelProvider(model) ++ "]")
  +defaultBadge = Bool.pick(String,isDefault(model,defaultRef),paint(theme,"muted"," · default"),"")
  Utils.truncateToWidth(cursor ++ marker ++ name ++ provider ++ defaultBadge,width,"",False{})
def rows(items: List<&2,Models.Model()>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+current: Maybe<&2,Models.Model()>,+defaultRef: Maybe<&2,String>,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match items skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: rows(rest,skip,remaining,index + 1n,selected,current,defaultRef,theme,width)
    case model <> rest Zero{} Succ{remaining}:
      line(model,current,defaultRef,Nat.is_eq(index,selected),theme,width) <> rows(rest,0n,remaining,index + 1n,selected,current,defaultRef,theme,width)
def scopeText(+mode: Bool,+theme: Theme.Theme) -> String:
  paint(theme,"muted","Scope: ") ++ Bool.pick(String,mode,paint(theme,"muted","all"),paint(theme,"accent","all")) ++ paint(theme,"muted"," | ") ++ Bool.pick(String,mode,paint(theme,"accent","scoped"),paint(theme,"muted","scoped"))
def scopeLines(scoped: List<&2,Models.Model()>,mode: Bool,+theme: Theme.Theme,bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  match scoped:
    case Nil{}: paint(theme,"warning","Only showing models from configured providers. Use /login to add providers.") <> Nil{}
    case _: scopeText(mode,theme) <> (Hints.keyHint(theme,bindings,"tui.input.tab","scope") ++ paint(theme,"muted"," (all/scoped)")) <> Nil{}
def detail(found: Maybe<&2,Models.Model()>,theme: Theme.Theme) -> List<&2,String>:
  match found:
    case None{}: Nil{}
    case Some{model}: "" <> paint(theme,"muted","  Model Name: " ++ Models.modelName(model)) <> Nil{}
def statusLines(+status: String,theme: Theme.Theme) -> List<&2,String>:
  +color = Bool.pick(String,String.eq(status,"Model catalogs refreshed."),"success",Bool.pick(String,String.eq(status,"Refreshing model catalogs…"),"muted","error"))
  Bool.pick(List<&2,String>,String.is_empty(status),Nil{},"" <> paint(theme,color,"  " ++ status) <> Nil{})
def border(width: Nat) -> String: String.repeat("─",width)
def render(+state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> List<&2,String>:
  match state:
    case State{_,+scoped,+visible,+index,query,current,defaultRef,mode,status}:
      +count = List.length(&2,Models.Model(),visible)
      +start = Nat.min(index - 5n,count - Nat.min(count,10n))
      +body = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching models") <> Nil{},rows(visible,start,10n,0n,index,current,defaultRef,theme,width))
      +counter = Bool.pick(List<&2,String>,Nat.is_gt(count,10n),paint(theme,"muted","  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")") <> Nil{},Nil{})
      +hint = "  " ++ Hints.keyDisplayText(bindings,"tui.select.confirm") ++ " to select · " ++ Hints.keyDisplayText(bindings,"app.models.save") ++ " to set as default · " ++ Hints.keyDisplayText(bindings,"tui.select.cancel") ++ " to cancel"
      List.concat(&2,String,[
        [paint(theme,"border",border(width)),""],
        scopeLines(scoped,mode,theme,bindings),
        ["","> " ++ query ++ "\u{1b}[7m \u{1b}[0m",""],
        body,counter,detail(selected(state),theme),statusLines(status,theme),
        ["",paint(theme,"dim",hint),paint(theme,"border",border(width))]
      ])

type Modal is Data: Closed{} Open{state: State}
def refreshedModal(current: Modal,models: List<&2,Models.Model()>,status: String) -> Modal & Bool:
  match current:
    case Closed{}: (Closed{},False{})
    case Open{state}: (Open{refreshedState(state,models,status)},True{})
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}
def drawCurrent(current: Modal,editor: Component.Component,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}: IO.pure(List<&2,String>,render(state,theme,bindings,width))
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,bindings,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        chosenTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,editor,chosenTheme,bindings,width)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,Continue{}): Ref.write(Modal,modal,Open{state})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,Chosen{model,persist}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{model,persist})
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,data: String) -> IO(Unit):
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
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>) -> IO(Owner):
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
def refreshed(host: Host,models: List<&2,Models.Model()>,status: String) -> IO(Bool):
  match host:
    case Host{modal,_,_,_,_,_}:
      do IO<Bool>:
        published : Maybe<&1,Bool> <- Ref.tryModify(Modal,Bool,modal,current => refreshedModal(current,models,status))
        return Maybe.default(&1,Bool,published,False{})
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
