import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme
import ./tree-selector.bend as TreePicker
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ./user-message-selector.bend as UserPicker

type Mode is Data: TreeMode{} ForkMode{}
# A selector temporarily occupies the editor's stable component ID. The live
# editor remains mounted and resumes its own input and focus on dismissal.

type Modal is Data: Closed{} Open{component: TreePicker.TreeSelectorComponent} ForkOpen{component: UserPicker.UserMessageSelectorComponent}
type Choice is Data: Choice{mode: Mode,id: String}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,words: Ref.Ref<Segmenter.Source>,chosen: Callback.Callback<Choice,Unit>,onAction: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def drawCurrent(current: Modal,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{component}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        pair : TreePicker.TreeSelectorComponent & List<&2,String> <- TreePicker.render(component,chosen,width,bindings)
        return Pair.snd(TreePicker.TreeSelectorComponent,List<&2,String>,pair)
    case ForkOpen{component}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        UserPicker.render(component,chosen,width)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,theme,bindings,_,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,editor,theme,width,bindings)
def callAction(callback: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>,action: TreePicker.Action) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(TreePicker.Action,Unit,value,action)
def disposeAction(callback: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.dispose(TreePicker.Action,Unit,value)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,onAction: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>,pair: TreePicker.TreeSelectorComponent & TreePicker.Action) -> IO(Unit):
  match pair:
    case (next,TreePicker.Copied{text}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{next})
        callAction(onAction,TreePicker.Copied{text})
    case (next,TreePicker.LabelChanged{id,label}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{next})
        callAction(onAction,TreePicker.LabelChanged{id,label})
    case (next,TreePicker.InputError{cause}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{next})
        callAction(onAction,TreePicker.InputError{cause})
    case (_,TreePicker.Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,TreePicker.Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{TreeMode{},id})
    case (next,_): Ref.write(Modal,modal,Open{next})
def receiveFork(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: UserPicker.UserMessageList & UserPicker.Action) -> IO(Unit):
  match pair:
    case (next,UserPicker.Continue{}): Ref.write(Modal,modal,ForkOpen{UserPicker.UserMessageSelectorComponent{next}})
    case (_,UserPicker.Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,UserPicker.Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{ForkMode{},id})
def preparedWords(+words: Ref.Ref<Segmenter.Source>,text: Maybe<&2,String>) -> IO(Segmenter.Source):
  match text:
    case None{}: Ref.read(Segmenter.Source,words)
    case Some{value}:
      do IO<Segmenter.Source>:
        source : Segmenter.Source <- Ref.read(Segmenter.Source,words)
        +next : Segmenter.Source <- Segmenter.readyFor(source,value)
        Ref.write(Segmenter.Source,words,next)
        return next
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,words: Ref.Ref<Segmenter.Source>,chosen: Callback.Callback<Choice,Unit>,onAction: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>,+data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{+component}:
      do IO<Unit>:
        source : Segmenter.Source <- preparedWords(words,TreePicker.wordText(component,bindings,keyboard,data))
        pair : TreePicker.TreeSelectorComponent & TreePicker.Action <- TreePicker.handleInput(component,source,bindings,keyboard,data)
        receiveOpen(modal,chosen,onAction,pair)
    case ForkOpen{component}: receiveFork(modal,chosen,UserPicker.handleInput(UserPicker.getMessageList(component),bindings,keyboard,data))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,bindings,keyboard,words,chosen,onAction}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,modal,editor,bindings,keyboard,words,chosen,onAction,data)
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
    case Host{modal,editor,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,editor,event)
def hostInvalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_}: Component.invalidate(editor)
def focusCurrent(modal: Ref.Ref<Modal>,editor: Component.Component,focused: Bool,current: Modal) -> IO(Unit):
  match current:
    case Open{component}: Ref.write(Modal,modal,Open{TreePicker.setFocused(component,focused)})
    case _: Component.setFocused(editor,focused)
def hostFocus(host: Host,focused: Bool) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,_,_,_,_,_}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        focusCurrent(modal,editor,focused,current)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,words: Segmenter.Source,chosen: Callback.Callback<Choice,Unit>,onAction: Maybe<&2,Callback.Callback<TreePicker.Action,Unit>>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    wordSource : Ref.Ref<Segmenter.Source> <- Ref.new(Segmenter.Source,words)
    +componentId : Component.ComponentId <- IO.pure(Component.ComponentId,Component.id(editor))
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,bindings,keyboard,wordSource,chosen,onAction})
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
  match host: case Host{modal,_,_,_,_,_,_,onAction}: Ref.write(Modal,modal,Open{TreePicker.setFocused(TreePicker.fromList(state),True{})})
def openFork(host: Host,component: UserPicker.UserMessageSelectorComponent) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_,onAction}: Ref.write(Modal,modal,ForkOpen{component})
def close(host: Host) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_,onAction}: Ref.write(Modal,modal,Closed{})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,words,_,onAction},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        oldSource : Segmenter.Source <- Ref.dispose(Segmenter.Source,words)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
        disposeAction(onAction)
