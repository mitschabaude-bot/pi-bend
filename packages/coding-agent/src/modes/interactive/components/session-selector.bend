import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme
import ./tree-selector.bend as TreePicker
import ./user-message-selector.bend as UserPicker

type Mode is Data: TreeMode{} ForkMode{}
# A selector temporarily occupies the editor's stable component ID. The live
# editor remains mounted and resumes its own input and focus on dismissal.

type Modal is Data: Closed{} Open{state: TreePicker.TreeList} ForkOpen{component: UserPicker.UserMessageSelectorComponent}
type Choice is Data: Choice{mode: Mode,id: String}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,onCopy: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def drawCurrent(current: Modal,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        TreePicker.render(TreePicker.TreeSelectorComponent{state},chosen,width,bindings)
    case ForkOpen{component}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        UserPicker.render(component,chosen,width)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,bindings,_,_,onCopy}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,editor,theme,width,bindings)
def callCopy(callback: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>,text: Maybe<&2,String>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(Maybe<&2,String>,Unit,value,text)
def disposeCopy(callback: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.dispose(Maybe<&2,String>,Unit,value)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,onCopy: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>,pair: TreePicker.TreeList & TreePicker.Action) -> IO(Unit):
  match pair:
    case (next,TreePicker.Continue{}): Ref.write(Modal,modal,Open{next})
    case (next,TreePicker.Copied{text}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{next})
        callCopy(onCopy,text)
    case (_,TreePicker.Cancel{}): Ref.write(Modal,modal,Closed{})
    case (next,TreePicker.Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{TreeMode{},id})
def receiveFork(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: UserPicker.UserMessageList & UserPicker.Action) -> IO(Unit):
  match pair:
    case (next,UserPicker.Continue{}): Ref.write(Modal,modal,ForkOpen{UserPicker.UserMessageSelectorComponent{next}})
    case (_,UserPicker.Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,UserPicker.Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{ForkMode{},id})
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,onCopy: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receiveOpen(modal,chosen,onCopy,TreePicker.input(state,bindings,keyboard,data))
    case ForkOpen{component}: receiveFork(modal,chosen,UserPicker.handleInput(UserPicker.getMessageList(component),bindings,keyboard,data))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,bindings,keyboard,chosen,onCopy}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,modal,editor,bindings,keyboard,chosen,onCopy,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(current: Modal,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def hostMouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{modal,editor,_,_,_,_,onCopy}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,editor,event)
def hostInvalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,onCopy}: Component.invalidate(editor)
def hostFocus(host: Host,focused: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,onCopy}: Component.setFocused(editor,focused)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,onCopy: Maybe<&2,Callback.Callback<Maybe<&2,String>,Unit>>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +componentId : Component.ComponentId <- IO.pure(Component.ComponentId,Component.id(editor))
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,bindings,keyboard,chosen,onCopy})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~hostMouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~hostInvalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~hostFocus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{componentId,renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host,state: TreePicker.TreeList) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,onCopy}: Ref.write(Modal,modal,Open{state})
def openFork(host: Host,component: UserPicker.UserMessageSelectorComponent) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,onCopy}: Ref.write(Modal,modal,ForkOpen{component})
def close(host: Host) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,onCopy}: Ref.write(Modal,modal,Closed{})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_,onCopy},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
        disposeCopy(onCopy)
