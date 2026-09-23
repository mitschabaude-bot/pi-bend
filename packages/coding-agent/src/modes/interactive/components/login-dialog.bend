import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../theme/theme.bend as Theme

# Replaces the editor while the native device flow waits for authorization.
# Esc calls the flow's abort controller; closing restores the original editor.
type State is Data: Closed{} Waiting{} Device{url: String,code: String}
type Host is Data:
  Host{state: Ref.Ref<State>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def bar(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ bar(rest)
def clipped(text: String,width: Nat) -> String:
  Utils.truncateToWidth(text,width,"",False{})
def frame(+theme: Theme.Theme,+width: Nat,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent"," Login to OpenAI Codex") <> "" <> List.append(&2,String,body,paint(theme,"dim",bar(width)) <> Nil{})
def waiting(+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  frame(theme,width,paint(theme,"dim"," Requesting device code...") <> "" <> " (Esc to cancel)" <> Nil{})
def device(+theme: Theme.Theme,+width: Nat,+url: String,code: String) -> List<&2,String>:
  +link = "\u{1b}]8;;" ++ url ++ "\u{7}" ++ url ++ "\u{1b}]8;;\u{7}"
  frame(theme,width,clipped(paint(theme,"accent"," " ++ link),width) <> paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"warning"," Enter code: " ++ code) <> "" <> paint(theme,"dim"," Waiting for authentication...") <> " (Esc to cancel)" <> Nil{})
def drawCurrent(state: State,editor: Component.Component,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match state:
    case Closed{}: Component.render(editor,width)
    case Waiting{}: IO.pure(List<&2,String>,waiting(theme,width))
    case Device{url,code}: IO.pure(List<&2,String>,device(theme,width,url,code))
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{state,editor,theme,_,_,_}:
      do IO<List<&2,String>>:
        current : State <- Ref.read(State,state)
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,editor,colors,width)
def receiveCurrent(current: State,state: Ref.Ref<State>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case _:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => do IO<Unit>:
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
        Callback.call(Unit,Unit,cancel,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+state,editor,_,bindings,keyboard,cancel}:
      do IO<Unit>:
        current : State <- Ref.read(State,state)
        receiveCurrent(current,state,editor,bindings,keyboard,cancel,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(current: State,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{state,editor,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : State <- Ref.read(State,state)
        mouseCurrent(current,editor,event)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.setFocused(editor,value)
def create(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    state : Ref.Ref<State> <- Ref.new(State,Closed{})
    +host : Host <- IO.pure(Host,Host{state,editor,theme,bindings,keyboard,cancel})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrow(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host) -> IO(Unit):
  match host:
    case Host{state,editor,_,_,_,_}:
      do IO<Unit>:
        Component.setFocused(editor,False{})
        Ref.write(State,state,Waiting{})
def showCode(host: Host,url: String,code: String) -> IO(Unit):
  match host: case Host{state,_,_,_,_,_}: Ref.write(State,state,Device{url,code})
def close(host: Host) -> IO(Unit):
  match host:
    case Host{state,editor,_,_,_,_}:
      do IO<Unit>:
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{state,_,_,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : State <- Ref.dispose(State,state)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
