import Base
import ./editor.bend as Editor
import ../component.bend as Component
import ../keybindings.bend as Keybindings
import ../keys.bend as Keys
import ../tui.bend as Tui
import ../word-navigation.bend as Word
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/word-segmenter.bend as Segmenter

# The terminal owns one editor. Component callbacks borrow its serialized
# state; a submission callback must schedule application work without trying
# to re-enter this editor during the same input event.
type State is Data:
  State{editor: Editor.Editor,words: Segmenter.Context,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,error: Maybe<&2,Editor.Error>}
type Handle is Data: Handle{resource: Serial.Handle<State>}
type Owner is Type:
  Owner{resource: Serial.Owner<State>,component: Component.Component,handle: Handle}

def renderedPair(pair: Editor.Editor & List<&2,String>,words: Segmenter.Context,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,error: Maybe<&2,Editor.Error>) -> State & List<&2,String>:
  match pair:
    case (next,lines): (State{next,words,bindings,keyboard,rows,error},lines)
def rendered(state: State,width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{editor,words,bindings,keyboard,+rows,error}:
      do IO<State & List<&2,String>>:
        height : Nat <- Ref.read(Nat,rows)
        pair : Editor.Editor & List<&2,String> <- Editor.render(editor,width,height)
        return renderedPair(pair,words,bindings,keyboard,rows,error)
def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{resource}: Serial.run(State,List<&2,String>,resource,state => rendered(state,width))

def accepted(previous: State,result: Editor.ResultOf(Editor.Editor)) -> State:
  match previous result:
    case State{_,words,bindings,keyboard,rows,_} Done{editor}: State{editor,words,bindings,keyboard,rows,None{}}
    case State{editor,words,bindings,keyboard,rows,_} Fail{error}: State{editor,words,bindings,keyboard,rows,Some{error}}
def inputState(state: State,data: String) -> IO(State & Unit):
  match state:
    case State{+editor,+words,+bindings,+keyboard,+rows,error}:
      do IO<State & Unit>:
        height : Nat <- Ref.read(Nat,rows)
        result : Editor.ResultOf(Editor.Editor) <- Editor.handleInput(~Segmenter.Context,~Word.nativeSegments,words,editor,bindings,keyboard,data,height)
        return (accepted(State{editor,words,bindings,keyboard,rows,error},result),Unit{})
def inputLive(handle: Handle,data: String) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => inputState(state,data))

def focusedState(state: State,focused: Bool) -> IO(State & Unit):
  match state:
    case State{+editor,words,bindings,keyboard,rows,error}:
      IO.pure(State & Unit,(State{Editor.setFocused(editor,focused),words,bindings,keyboard,rows,error},Unit{}))
def focusLive(handle: Handle,focused: Bool) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => focusedState(state,focused))
def invalidated(state: State) -> IO(State & Unit):
  match state:
    case State{editor,words,bindings,keyboard,rows,error}:
      IO.pure(State & Unit,(State{Editor.invalidate(editor),words,bindings,keyboard,rows,error},Unit{}))
def invalidateLive(handle: Handle,value: Unit) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,invalidated)

def mouseAccepted(previous: State,result: Editor.ResultOf(Editor.MouseResult)) -> State & Maybe<&2,Component.MouseResponse>:
  match previous result:
    case State{_,words,bindings,keyboard,rows,_} Done{Editor.MouseResult{editor,response}}:
      (State{editor,words,bindings,keyboard,rows,None{}},Maybe.map(&2,Tui.TuiMouseEventResult,Component.MouseResponse,answer => Component.LocalResult{answer},response))
    case State{editor,words,bindings,keyboard,rows,_} Fail{error}:
      (State{editor,words,bindings,keyboard,rows,Some{error}},None{})
def mouseState(state: State,event: Tui.TuiMouseEvent) -> IO(State & Maybe<&2,Component.MouseResponse>):
  match state:
    case State{+editor,words,bindings,keyboard,rows,error}:
      do IO<State & Maybe<&2,Component.MouseResponse>>:
        result : Editor.ResultOf(Editor.MouseResult) <- Editor.handleMouse(editor,event)
        return mouseAccepted(State{editor,words,bindings,keyboard,rows,error},result)
def mouseLive(handle: Handle,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match handle:
    case Handle{resource}: Serial.run(State,Maybe<&2,Component.MouseResponse>,resource,state => mouseState(state,event))

def errorState(state: State) -> IO(State & Maybe<&2,Editor.Error>):
  match state:
    case State{editor,words,bindings,keyboard,rows,+error}:
      IO.pure(State & Maybe<&2,Editor.Error>,(State{editor,words,bindings,keyboard,rows,error},error))
def lastError(handle: Handle) -> IO(Maybe<&2,Editor.Error>):
  match handle:
    case Handle{resource}: Serial.run(State,Maybe<&2,Editor.Error>,resource,errorState)
def textState(state: State) -> IO(State & String):
  match state:
    case State{+editor,words,bindings,keyboard,rows,error}:
      IO.pure(State & String,(State{editor,words,bindings,keyboard,rows,error},Editor.getText(editor)))
def text(handle: Handle) -> IO(String):
  match handle:
    case Handle{resource}: Serial.run(State,String,resource,textState)

def created(id: Component.ComponentId,pair: Serial.Owner<State> & Serial.Handle<State>) -> IO(Owner):
  match pair:
    case (resource,+handle):
      do IO<Owner>:
        render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Handle,~Nat,~List<&2,String>,~renderLive,Handle{handle})
        input : Callback.Callback<String,Unit> <- Callback.create(~Handle,~String,~Unit,~inputLive,Handle{handle})
        mouse : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Handle,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouseLive,Handle{handle})
        invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Handle,~Unit,~Unit,~invalidateLive,Handle{handle})
        focus : Callback.Callback<Bool,Unit> <- Callback.create(~Handle,~Bool,~Unit,~focusLive,Handle{handle})
        return Owner{resource,Component.Component{id,render,Some{input},Some{mouse},invalidate,Some{focus},False{}},Handle{handle}}
def create(id: Component.ComponentId,editor: Editor.Editor,words: Segmenter.Context,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{editor,words,bindings,keyboard,rows,None{}})
    created(id,Serial.borrow(State,resource))
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{resource,+component,+handle}: (Owner{resource,component,handle},component,handle)
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{editor,_,_,_,_,_}: Editor.dispose(editor)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,Component.Component{_,render,Some{input},Some{mouse},invalidate,Some{focus},_},_}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
    case _: IO.die(Unit,1,"invalid editor component")
