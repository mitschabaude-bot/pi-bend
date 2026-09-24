import Base
import ../../../core/trust-manager.bend as Trust
import ../theme/theme.bend as Theme
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref

type State is Data:
  State{cwd: String,options: List<&2,Trust.ProjectTrustOption>,saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,trusted: Bool,selected: Nat}
type Modal is Data: Closed{} Open{state: State}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Trust.ProjectTrustOption,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def isSaved(option: Trust.ProjectTrustOption,saved: Maybe<&2,Trust.ProjectTrustStoreEntry>) -> Bool:
  match option saved:
    case Trust.ProjectTrustOption{_,True{},_,Some{path}} Some{Trust.ProjectTrustStoreEntry{savedPath,True{}}}: String.eq(path,savedPath)
    case Trust.ProjectTrustOption{_,False{},_,Some{path}} Some{Trust.ProjectTrustStoreEntry{savedPath,False{}}}: String.eq(path,savedPath)
    case _ _: False{}
def selected(options: List<&2,Trust.ProjectTrustOption>,+saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,+index: Nat) -> Nat:
  match options:
    case Nil{}: 0n
    case option <> rest: Bool.pick(Nat,isSaved(option,saved),index,selected(rest,saved,index + 1n))
def new(cwd: String,+options: List<&2,Trust.ProjectTrustOption>,+saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,trusted: Bool) -> State:
  State{cwd,options,saved,trusted,selected(options,saved,0n)}
def decision(saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,cwd: String) -> String:
  match saved:
    case None{}: "none"
    case Some{Trust.ProjectTrustStoreEntry{+path,True{}}}: "trusted (" ++ Bool.pick(String,String.eq(path,cwd),path,"inherited from " ++ path) ++ ")"
    case Some{Trust.ProjectTrustStoreEntry{+path,False{}}}: "untrusted (" ++ Bool.pick(String,String.eq(path,cwd),path,"inherited from " ++ path) ++ ")"
def color(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def border(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ border(rest)
def paddedParts(parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: (" " ++ part) <> paddedParts(rest)
def padded(text: String,width: Nat) -> List<&2,String>:
  paddedParts(Utils.wrapTextWithAnsi(text,width - 2n))
def optionLabel(option: Trust.ProjectTrustOption) -> String:
  match option: case Trust.ProjectTrustOption{label,_,_,_}: label
def choiceRows(options: List<&2,Trust.ProjectTrustOption>,+saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,+index: Nat,+selectedIndex: Nat,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case +option <> rest:
      +active = Nat.is_eq(index,selectedIndex)
      +prefix = Bool.pick(String,active,"→ ","  ") ++ Bool.pick(String,isSaved(option,saved),"✓ ","  ")
      List.append(&2,String,padded(color(theme,Bool.pick(String,active,"accent","text"),prefix ++ optionLabel(option)),width),choiceRows(rest,saved,index + 1n,selectedIndex,theme,width))
def namedKeys(keys: List<&2,Keys.KeyId>,fallback: String) -> String:
  match keys:
    case Nil{}: fallback
    case key <> Nil{}: Keys.formatKeyId(key)
    case key <> rest: Keys.formatKeyId(key) ++ "/" ++ namedKeys(rest,fallback)
def hint(bindings: Bindings.KeybindingsManager,+action: String) -> String:
  namedKeys(Bindings.getKeys(bindings,action),action)
def render(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> List<&2,String>:
  match state:
    case State{+cwd,options,+saved,trusted,index}:
      +rule = color(theme,"border",border(width))
      +title = padded(color(theme,"accent","Project trust"),width)
      +location = padded(color(theme,"muted",cwd),width)
      +savedLine = padded(color(theme,"muted","Saved decision: " ++ decision(saved,cwd)),width)
      +current = padded(color(theme,"muted","Current session: " ++ Bool.pick(String,trusted,"trusted","untrusted")),width)
      +help = padded(color(theme,"muted","↑↓ navigate  " ++ hint(bindings,"tui.select.confirm") ++ " save  " ++ hint(bindings,"tui.select.cancel") ++ " cancel"),width)
      rule <> "" <> List.append(&2,String,title,List.append(&2,String,location,
        "" <> List.append(&2,String,savedLine,List.append(&2,String,current,
          "" <> List.append(&2,String,choiceRows(options,saved,0n,index,theme,width),
            "" <> List.append(&2,String,help,"" <> rule <> Nil{}))))))
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
type Action is Data: Up{} Down{} Confirm{} Cancel{} Ignore{}
def action(+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> Action:
  Bool.pick(Unit -> Action,Bindings.matches(bindings,keyboard,data,"tui.select.up") || String.eq(data,"k"),_ => Up{},
    _ => Bool.pick(Unit -> Action,Bindings.matches(bindings,keyboard,data,"tui.select.down") || String.eq(data,"j"),_ => Down{},
      _ => Bool.pick(Unit -> Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm") || String.eq(data,"\n"),_ => Confirm{},
        _ => Bool.pick(Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),Cancel{},Ignore{}))(Unit{}))(Unit{}))(Unit{})
def changed(state: State,action: Action) -> State:
  match state action:
    case State{cwd,options,saved,trusted,index} Up{}: State{cwd,options,saved,trusted,index - 1n}
    case State{cwd,+options,saved,trusted,index} Down{}: State{cwd,options,saved,trusted,Nat.min(index + 1n,List.length(&2,Trust.ProjectTrustOption,options) - 1n)}
    case state _: state
def selectedOption(state: State) -> Maybe<&2,Trust.ProjectTrustOption>:
  match state: case State{_,options,_,_,index}: List.get(&2,Trust.ProjectTrustOption,options,index)
def chooseOption(chosen: Callback.Callback<Trust.ProjectTrustOption,Unit>,option: Maybe<&2,Trust.ProjectTrustOption>) -> IO(Unit):
  match option:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(Trust.ProjectTrustOption,Unit,chosen,value)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Trust.ProjectTrustOption,Unit>,state: State,action: Action) -> IO(Unit):
  match action:
    case Cancel{}: Ref.write(Modal,modal,Closed{})
    case Confirm{}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        chooseOption(chosen,selectedOption(state))
    case other: Ref.write(Modal,modal,Open{changed(state,other)})
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Trust.ProjectTrustOption,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receiveOpen(modal,chosen,state,action(bindings,keyboard,data))
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
    case Open{_}: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
    case Closed{}: editorMouse(editor,event)
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
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Trust.ProjectTrustOption,Unit>) -> IO(Owner):
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
