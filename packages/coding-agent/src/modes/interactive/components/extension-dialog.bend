import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/editor.bend as Editor
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../theme/theme.bend as Theme
import ./extension-selector.bend as Selector
import ./extension-input.bend as Input
import ./extension-editor.bend as Multi

# A prompt temporarily occupies the editor's component slot. Its result
# channel belongs to the requester; closing the slot always resolves it.
def Answer() -> Data: Maybe<&2,String>
def Reply() -> Data: Chan(Answer())
type Modal is Data:
  Closed{}
  Selecting{state: Selector.State,reply: Reply()}
  Typing{state: Input.State,reply: Reply()}
  Editing{state: Multi.State,reply: Reply(),ticket: Nat}
type ExternalRequest is Data:
  ExternalRequest{ticket: Nat,content: String}
type InputEffect is Data:
  Forward{}
  Handled{}
  OpenExternal{request: ExternalRequest}
type Host is Data:
  Host{modal: Serial.Handle<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,source: Ref.Ref<Words.Source>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,redraw: Callback.Callback<Unit,Unit>,nextTicket: Ref.Ref<Nat>,external: Ref.Ref<Maybe<&2,Callback.Callback<ExternalRequest,Unit>>>}
type Owner is Type:
  Owner{modal: Serial.Owner<Modal>,host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}

def selecting(pair: Selector.State & Selector.Action,reply: Reply()) -> IO(Modal):
  match pair:
    case (state,Selector.Continue{}): IO.pure(Modal,Selecting{state,reply})
    case (state,Selector.ToggleTools{}): IO.pure(Modal,Selecting{state,reply})
    case (_,Selector.Select{value}):
      do IO<Modal>:
        sent : Bool <- Chan.send(Answer(),reply,Some{value})
        return Closed{}
    case (_,Selector.Cancel{}):
      do IO<Modal>:
        sent : Bool <- Chan.send(Answer(),reply,None{})
        return Closed{}
def typing(pair: Input.State & Input.Action,reply: Reply()) -> IO(Modal):
  match pair:
    case (state,Input.Continue{}): IO.pure(Modal,Typing{state,reply})
    case (_,Input.Submit{value}):
      do IO<Modal>:
        sent : Bool <- Chan.send(Answer(),reply,Some{value})
        return Closed{}
    case (_,Input.Cancel{}):
      do IO<Modal>:
        sent : Bool <- Chan.send(Answer(),reply,None{})
        return Closed{}
def editing(pair: Multi.State & Multi.Action,reply: Reply(),+ticket: Nat) -> IO(Modal & InputEffect):
  match pair:
    case (state,Multi.Continue{}): IO.pure(Modal & InputEffect,(Editing{state,reply,ticket},Handled{}))
    case (state,Multi.External{content}): IO.pure(Modal & InputEffect,(Editing{state,reply,ticket},OpenExternal{ExternalRequest{ticket,content}}))
    case (_,Multi.Submit{value}):
      do IO<Modal & InputEffect>:
        sent : Bool <- Chan.send(Answer(),reply,Some{value})
        return (Closed{},Handled{})
    case (_,Multi.Cancel{}):
      do IO<Modal & InputEffect>:
        sent : Bool <- Chan.send(Answer(),reply,None{})
        return (Closed{},Handled{})

def inputRows(reply: Reply(),result: Input.State & List<&2,String>) -> Modal & List<&2,String>:
  match result: case (next,lines): (Typing{next,reply},lines)
def editorRows(reply: Reply(),ticket: Nat,result: Multi.State & List<&2,String>) -> Modal & List<&2,String>:
  match result: case (next,lines): (Editing{next,reply,ticket},lines)
def optionalRows(result: Modal & List<&2,String>) -> Modal & Maybe<&2,List<&2,String>>:
  match result: case (next,lines): (next,Some{lines})

def drawModal(modal: Modal,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,width: Nat,rows: Nat) -> IO(Modal & Maybe<&2,List<&2,String>>):
  match modal:
    case Closed{}: IO.pure(Modal & Maybe<&2,List<&2,String>>,(Closed{},None{}))
    case Selecting{+state,reply}:
      do IO<Modal & Maybe<&2,List<&2,String>>>:
        lines : List<&2,String> <- Selector.render(state,theme,bindings,width)
        return (Selecting{state,reply},Some{lines})
    case Typing{+state,reply}:
      do IO<Modal & Maybe<&2,List<&2,String>>>:
        result : Input.State & List<&2,String> <- Input.render(state,theme,bindings,width)
        return optionalRows(inputRows(reply,result))
    case Editing{+state,reply,ticket}:
      do IO<Modal & Maybe<&2,List<&2,String>>>:
        result : Multi.State & List<&2,String> <- Multi.render(state,theme,bindings,width,rows)
        return optionalRows(editorRows(reply,ticket,result))
def drawLines(editor: Component.Component,width: Nat,lines: Maybe<&2,List<&2,String>>) -> IO(List<&2,String>):
  match lines:
    case None{}: Component.render(editor,width)
    case Some{value}: IO.pure(List<&2,String>,value)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,_,bindings,_,rows,_,_,_}:
      do IO<List<&2,String>>:
        +width : Nat <- IO.pure(Nat,width)
        palette : Theme.Theme <- Ref.read(Theme.Theme,theme)
        height : Nat <- Ref.read(Nat,rows)
        lines : Maybe<&2,List<&2,String>> <- Serial.run(Modal,Maybe<&2,List<&2,String>>,modal,current => drawModal(current,palette,bindings,width,height))
        drawLines(editor,width,lines)
def wordSource(+words: Ref.Ref<Words.Source>,text: String) -> IO(Words.Source):
  do IO<Words.Source>:
    old : Words.Source <- Ref.read(Words.Source,words)
    +ready : Words.Source <- Words.readyFor(old,text)
    Ref.write(Words.Source,words,ready)
    return ready
def receiveModal(modal: Modal,source: Ref.Ref<Words.Source>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String,rows: Nat) -> IO(Modal & InputEffect):
  match modal:
    case Closed{}: IO.pure(Modal & InputEffect,(Closed{},Forward{}))
    case Selecting{state,reply}:
      do IO<Modal & InputEffect>:
        next : Modal <- selecting(Selector.handleInput(state,bindings,keyboard,data),reply)
        return (next,Handled{})
    case Typing{+state,reply}:
      do IO<Modal & InputEffect>:
        words : Words.Source <- wordSource(source,Input.value(state))
        outcome : Input.State & Input.Action <- Input.handleInput(state,words,bindings,keyboard,data)
        next : Modal <- typing(outcome,reply)
        return (next,Handled{})
    case Editing{+state,reply,ticket}:
      do IO<Modal & InputEffect>:
        words : Words.Source <- wordSource(source,Multi.value(state))
        outcome : Multi.State & Multi.Action <- Multi.handleInput(state,words,bindings,keyboard,data,rows)
        editing(outcome,reply,ticket)
def callExternal(callback: Maybe<&2,Callback.Callback<ExternalRequest,Unit>>,request: ExternalRequest) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: Callback.call(ExternalRequest,Unit,ready,request)
def applyEffect(editor: Component.Component,external: Ref.Ref<Maybe<&2,Callback.Callback<ExternalRequest,Unit>>>,data: String,effect: InputEffect) -> IO(Unit):
  match effect:
    case Forward{}: Component.handleInput(editor,data)
    case Handled{}: IO.pure(Unit,Unit{})
    case OpenExternal{request}:
      do IO<Unit>:
        callback : Maybe<&2,Callback.Callback<ExternalRequest,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<ExternalRequest,Unit>>,external)
        callExternal(callback,request)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{modal,editor,_,source,bindings,keyboard,rows,_,_,external}:
      do IO<Unit>:
        +data : String <- IO.pure(String,data)
        height : Nat <- Ref.read(Nat,rows)
        effect : InputEffect <- Serial.run(Modal,InputEffect,modal,current => receiveModal(current,source,bindings,keyboard,data,height))
        applyEffect(editor,external,data,effect)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
def isClosed(current: Modal) -> Modal & Bool:
  match current:
    case Closed{}: (Closed{},True{})
    case value: (value,False{})
def mouseCurrent(editor: Component.Component,event: Tui.TuiMouseEvent,closed: Bool) -> IO(Maybe<&2,Component.MouseResponse()>):
  Bool.pick(Unit -> IO(Maybe<&2,Component.MouseResponse()>),closed,_ => editorMouse(editor,event),_ => IO.pure(Maybe<&2,Component.MouseResponse()>,None{}))(Unit{})
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match host:
    case Host{modal,editor,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        closed : Bool <- Serial.run(Modal,Bool,modal,current => IO.pure(Modal & Bool,isClosed(current)))
        mouseCurrent(editor,event,closed)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_,_}: Component.invalidate(editor)
def focusCurrent(editor: Component.Component,focused: Bool,closed: Bool) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),closed,_ => Component.setFocused(editor,focused),_ => IO.pure(Unit,Unit{}))(Unit{})
def focus(host: Host,focused: Bool) -> IO(Unit):
  match host:
    case Host{modal,editor,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        closed : Bool <- Serial.run(Modal,Bool,modal,current => IO.pure(Modal & Bool,isClosed(current)))
        focusCurrent(editor,focused,closed)
def built(pair: Serial.Owner<Modal> & Serial.Handle<Modal>,+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  match pair:
    case (modalOwner,modal):
      do IO<Owner>:
        +source : Ref.Ref<Words.Source> <- Ref.new(Words.Source,words)
        +nextTicket : Ref.Ref<Nat> <- Ref.new(Nat,0n)
        +external : Ref.Ref<Maybe<&2,Callback.Callback<ExternalRequest,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<ExternalRequest,Unit>>,None{})
        +host : Host <- IO.pure(Host,Host{modal,editor,theme,source,bindings,keyboard,rows,redraw,nextTicket,external})
        +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
        +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
        +mouseInput : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,host)
        +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
        +focusing : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
        +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouseInput},invalidator,Some{focusing},False{}})
        return Owner{modalOwner,host,component,render,input,mouseInput,invalidator,focusing}
def create(editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,rows: Ref.Ref<Nat>,redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    owner : Serial.Owner<Modal> <- Serial.create(Modal,Closed{})
    built(Serial.borrow(Modal,owner),editor,theme,words,bindings,keyboard,rows,redraw)
def borrow(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{modal,+host,+component,render,input,mouse,invalidate,focus}: (Owner{modal,host,component,render,input,mouse,invalidate,focus},host,component)
def cancel(modal: Modal) -> IO(Unit):
  match modal:
    case Closed{}: IO.pure(Unit,Unit{})
    case Selecting{_,reply}: IO.bind(Bool,Unit,Chan.send(Answer(),reply,None{}),_ => IO.pure(Unit,Unit{}))
    case Typing{_,reply}: IO.bind(Bool,Unit,Chan.send(Answer(),reply,None{}),_ => IO.pure(Unit,Unit{}))
    case Editing{_,reply,_}: IO.bind(Bool,Unit,Chan.send(Answer(),reply,None{}),_ => IO.pure(Unit,Unit{}))
def replaced(next: Modal,current: Modal) -> IO(Modal & Unit):
  do IO<Modal & Unit>:
    cancel(current)
    return (next,Unit{})
def replace(host: Host,next: Modal) -> IO(Unit):
  match host:
    case Host{modal,_,_,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        Serial.run(Modal,Unit,modal,current => replaced(next,current))
        Callback.call(Unit,Unit,redraw,Unit{})
def close(host: Host) -> IO(Unit): replace(host,Closed{})
def bindExternal(host: Host,callback: Maybe<&2,Callback.Callback<ExternalRequest,Unit>>) -> IO(Unit):
  match host: case Host{_,_,_,_,_,_,_,_,_,external}: Ref.write(Maybe<&2,Callback.Callback<ExternalRequest,Unit>>,external,callback)
def nextTicket(current: Nat) -> Nat & Nat:
  +next = Nat.add(current,1n)
  (next,next)
def changedExternal(modal: Modal,ticket: Nat,content: String) -> IO(Modal & Unit):
  match modal:
    case Editing{+state,+reply,+current}:
      Bool.pick(Unit -> IO(Modal & Unit),Nat.is_eq(current,ticket),
        _ => do IO<Modal & Unit>:
          updated : Multi.State <- Multi.setText(state,content)
          return (Editing{updated,reply,current},Unit{}),
        _ => IO.pure(Modal & Unit,(Editing{state,reply,current},Unit{})))(Unit{})
    case other: IO.pure(Modal & Unit,(other,Unit{}))
def applyExternal(host: Host,ticket: Nat,content: String) -> IO(Unit):
  match host:
    case Host{modal,_,_,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        Serial.run(Modal,Unit,modal,current => changedExternal(current,ticket,content))
        Callback.call(Unit,Unit,redraw,Unit{})
def select(host: Host,state: Selector.State) -> IO(Answer()):
  do IO<Answer()>:
    +reply : Reply() <- Chan.new(Answer(),1)
    replace(host,Selecting{state,reply})
    received : Maybe<&1,Answer()> <- Chan.recv(Answer(),reply)
    Chan.close(Answer(),reply)
    return Maybe.default(&1,Answer(),received,None{})
def input(host: Host,state: Input.State) -> IO(Answer()):
  do IO<Answer()>:
    +reply : Reply() <- Chan.new(Answer(),1)
    replace(host,Typing{state,reply})
    received : Maybe<&1,Answer()> <- Chan.recv(Answer(),reply)
    Chan.close(Answer(),reply)
    return Maybe.default(&1,Answer(),received,None{})
def editor(+host: Host,state: Multi.State) -> IO(Answer()):
  match host:
    case Host{_,_,_,_,_,_,_,_,counter,_}:
      do IO<Answer()>:
        ticket : Nat <- Ref.modify(Nat,Nat,counter,nextTicket)
        +reply : Reply() <- Chan.new(Answer(),1)
        replace(host,Editing{state,reply,ticket})
        received : Maybe<&1,Answer()> <- Chan.recv(Answer(),reply)
        Chan.close(Answer(),reply)
        return Maybe.default(&1,Answer(),received,None{})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{modal,Host{_,_,_,source,_,_,_,_,counter,external},_,render,input,mouse,invalidate,focus}:
      do IO<Unit>:
        old : Modal <- Serial.retire(Modal,modal)
        cancel(old)
        words : Words.Source <- Ref.dispose(Words.Source,source)
        retired : Nat <- Ref.dispose(Nat,counter)
        bound : Maybe<&2,Callback.Callback<ExternalRequest,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<ExternalRequest,Unit>>,external)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
