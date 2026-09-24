import Base
import ./editor.bend as Editor
import ./loader.bend as Loader
import ../component.bend as Component
import ../keybindings.bend as Keybindings
import ../keys.bend as Keys
import ../tui.bend as Tui
import ../word-navigation.bend as Word
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/text.bend as Strings
import ../../../runtime/src/word-segmenter.bend as Segmenter

# The terminal owns one editor. Component callbacks borrow its serialized
# state; a submission callback must schedule application work without trying
# to re-enter this editor during the same input event.
type State is Data:
  State{editor: Editor.Editor,words: Segmenter.Source,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,error: Maybe<&2,Editor.Error>}
type Handle is Data: Handle{resource: Serial.Handle<State>}
type RenderInput is Data: RenderInput{editor: Handle,working: Maybe<&2,Ref.Ref<Maybe<&2,Loader.Handle>>>}
type Owner is Type:
  Owner{resource: Serial.Owner<State>,component: Component.Component,handle: Handle}

def renderedPair(pair: Editor.Editor & List<&2,String>,words: Segmenter.Source,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,error: Maybe<&2,Editor.Error>) -> State & List<&2,String>:
  match pair:
    case (next,lines): (State{next,words,bindings,keyboard,rows,error},lines)
def rendered(state: State,width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{editor,words,bindings,keyboard,+rows,error}:
      do IO<State & List<&2,String>>:
        height : Nat <- Ref.read(Nat,rows)
        pair : Editor.Editor & List<&2,String> <- Editor.render(editor,width,height)
        return renderedPair(pair,words,bindings,keyboard,rows,error)
def statusLine(handle: Maybe<&2,Loader.Handle>,width: Nat) -> IO(Maybe<&2,String>):
  match handle:
    case None{}: IO.pure(Maybe<&2,String>,None{})
    case Some{loader}:
      do IO<Maybe<&2,String>>:
        lines : List<&2,String> <- Loader.renderLive(loader,width + 2n)
        return Some{Strings.trim(Maybe.default(&2,String,List.get(&2,String,lines,1n),""))}
def renderedStatus(state: State,width: Nat,status: Maybe<&2,String>) -> IO(State & List<&2,String>):
  match state:
    case State{editor,words,bindings,keyboard,+rows,error}:
      do IO<State & List<&2,String>>:
        height : Nat <- Ref.read(Nat,rows)
        pair : Editor.Editor & List<&2,String> <- Editor.renderWithStatus(editor,width,height,status)
        return renderedPair(pair,words,bindings,keyboard,rows,error)
def renderLiveCopied(input: RenderInput,+width: Nat) -> IO(List<&2,String>):
  match input:
    case RenderInput{Handle{resource},None{}}: Serial.run(State,List<&2,String>,resource,state => rendered(state,width))
    case RenderInput{Handle{resource},Some{working}}:
      do IO<List<&2,String>>:
        handle : Maybe<&2,Loader.Handle> <- Ref.read(Maybe<&2,Loader.Handle>,working)
        status : Maybe<&2,String> <- statusLine(handle,width)
        Serial.run(State,List<&2,String>,resource,state => renderedStatus(state,width,status))
def renderLive(input: RenderInput,width: Nat) -> IO(List<&2,String>):
  renderLiveCopied(input,width)

def accepted(previous: State,result: Editor.ResultOf(Editor.Editor)) -> State:
  match previous result:
    case State{_,words,bindings,keyboard,rows,_} Done{editor}: State{editor,words,bindings,keyboard,rows,None{}}
    case State{editor,words,bindings,keyboard,rows,_} Fail{error}: State{editor,words,bindings,keyboard,rows,Some{error}}
# The editor's word commands (upstream's Intl.Segmenter users).
def wordCommand(+bindings: Keybindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> Bool:
  Keybindings.matches(bindings,keyboard,data,"tui.editor.cursorWordLeft") || Keybindings.matches(bindings,keyboard,data,"tui.editor.cursorWordRight") || Keybindings.matches(bindings,keyboard,data,"tui.editor.deleteWordBackward") || Keybindings.matches(bindings,keyboard,data,"tui.editor.deleteWordForward")
def wordsFor(needed: Bool,words: Segmenter.Source) -> IO(Segmenter.Source):
  match needed:
    case True{}: Segmenter.ready(words)
    case False{}: IO.pure(Segmenter.Source,words)
def inputState(state: State,+data: String) -> IO(State & Unit):
  match state:
    case State{+editor,words,+bindings,+keyboard,+rows,error}:
      do IO<State & Unit>:
        height : Nat <- Ref.read(Nat,rows)
        +source : Segmenter.Source <- wordsFor(wordCommand(bindings,keyboard,data),words)
        result : Editor.ResultOf(Editor.Editor) <- Editor.handleInput(~Segmenter.Source,~Word.sourceSegments,source,editor,bindings,keyboard,data,height)
        return (accepted(State{editor,source,bindings,keyboard,rows,error},result),Unit{})
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
# A read of the current editor value.
def readState(-A: Data,state: State,read: Editor.Editor -> A) -> IO(State & A):
  match state:
    case State{+editor,words,bindings,keyboard,rows,error}:
      IO.pure(State & A,(State{editor,words,bindings,keyboard,rows,error},read(editor)))
def query(-A: Data,handle: Handle,read: Editor.Editor -> A) -> IO(A):
  match handle:
    case Handle{resource}: Serial.run(State,A,resource,state => readState(A,state,read))
def text(handle: Handle) -> IO(String): query(String,handle,Editor.getText)
def expandedText(handle: Handle) -> IO(String): query(String,handle,Editor.getExpandedText)
def isShowingAutocomplete(handle: Handle) -> IO(Bool): query(Bool,handle,Editor.isShowingAutocomplete)
def setTextState(state: State,value: String) -> IO(State & Unit):
  match state:
    case State{editor,words,bindings,keyboard,rows,error}:
      do IO<State & Unit>:
        next : Editor.Editor <- Editor.setText(editor,value)
        return (State{next,words,bindings,keyboard,rows,error},Unit{})
def setText(handle: Handle,value: String) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => setTextState(state,value))

def created(id: Component.ComponentId,pair: Serial.Owner<State> & Serial.Handle<State>,working: Maybe<&2,Ref.Ref<Maybe<&2,Loader.Handle>>>) -> IO(Owner):
  match pair:
    case (resource,+handle):
      do IO<Owner>:
        render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~RenderInput,~Nat,~List<&2,String>,~renderLive,RenderInput{Handle{handle},working})
        input : Callback.Callback<String,Unit> <- Callback.create(~Handle,~String,~Unit,~inputLive,Handle{handle})
        mouse : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Handle,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouseLive,Handle{handle})
        invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Handle,~Unit,~Unit,~invalidateLive,Handle{handle})
        focus : Callback.Callback<Bool,Unit> <- Callback.create(~Handle,~Bool,~Unit,~focusLive,Handle{handle})
        return Owner{resource,Component.Component{id,render,Some{input},Some{mouse},invalidate,Some{focus},False{}},Handle{handle}}
def create(id: Component.ComponentId,editor: Editor.Editor,words: Segmenter.Source,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{editor,words,bindings,keyboard,rows,None{}})
    created(id,Serial.borrow(State,resource),None{})
def createWithWorking(id: Component.ComponentId,editor: Editor.Editor,words: Segmenter.Source,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,working: Ref.Ref<Maybe<&2,Loader.Handle>>) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{editor,words,bindings,keyboard,rows,None{}})
    created(id,Serial.borrow(State,resource),Some{working})
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
