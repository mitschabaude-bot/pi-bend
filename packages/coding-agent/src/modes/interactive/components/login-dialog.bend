import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/deferred.bend as Deferred
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../theme/theme.bend as Theme

# Replaces the editor while the native device flow waits for authorization.
# Esc calls the flow's abort controller; closing restores the original editor.
type State is Data: Closed{} Choosing{} Waiting{} Device{url: String,code: String} Manual{url: String,input: String}
type Host is Data:
  Host{state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>}
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
def clipLines(lines: List<&2,String>,+width: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: clipped(line,width) <> clipLines(rest,width)
def frameLines(+theme: Theme.Theme,+width: Nat,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent"," Login to OpenAI Codex") <> "" <> List.append(&2,String,body,paint(theme,"dim",bar(width)) <> Nil{})
def frame(theme: Theme.Theme,+width: Nat,body: List<&2,String>) -> List<&2,String>:
  clipLines(frameLines(theme,width,body),width)
def waiting(+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  frame(theme,width,paint(theme,"dim"," Requesting device code...") <> "" <> " (Esc to cancel)" <> Nil{})
def choosing(+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  frame(theme,width,paint(theme,"accent"," Choose a provider") <> "  1  OpenAI Codex" <> "  2  Anthropic (Claude Pro/Max)" <> "" <> paint(theme,"dim"," Press 1 or 2 · Esc to cancel") <> Nil{})
def manual(+theme: Theme.Theme,+width: Nat,+url: String,+input: String) -> List<&2,String>:
  +link = "\u{1b}]8;;" ++ url ++ "\u{7}" ++ url ++ "\u{1b}]8;;\u{7}"
  frame(theme,width,clipped(paint(theme,"accent"," " ++ link),width) <> paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"dim"," Copy the final redirect URL from your browser after authorization.") <> paint(theme,"warning"," Paste authorization code or redirect URL:") <> clipped(" " ++ input,width) <> "" <> paint(theme,"dim"," Enter to submit · Esc to cancel") <> Nil{})
def device(+theme: Theme.Theme,+width: Nat,+url: String,code: String) -> List<&2,String>:
  +link = "\u{1b}]8;;" ++ url ++ "\u{7}" ++ url ++ "\u{1b}]8;;\u{7}"
  frame(theme,width,clipped(paint(theme,"accent"," " ++ link),width) <> paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"warning"," Enter code: " ++ code) <> "" <> paint(theme,"dim"," Waiting for authentication...") <> " (Esc to cancel)" <> Nil{})
def drawCurrent(state: State,editor: Component.Component,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match state:
    case Closed{}: Component.render(editor,width)
    case Choosing{}: IO.pure(List<&2,String>,choosing(theme,width))
    case Waiting{}: IO.pure(List<&2,String>,waiting(theme,width))
    case Device{url,code}: IO.pure(List<&2,String>,device(theme,width,url,code))
    case Manual{url,input}: IO.pure(List<&2,String>,manual(theme,width,url,input))
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{state,_,editor,theme,_,_,_}:
      do IO<List<&2,String>>:
        current : State <- Ref.read(State,state)
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,editor,colors,width)
def resolveReply(current: Maybe<&2,Deferred.Deferred<String>>,value: String) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{pending}:
      do IO<Unit>:
        done : Bool <- Deferred.resolve(String,pending,value)
        return Unit{}
def settle(reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,value: String) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Deferred.Deferred<String>> <- Ref.swap(Maybe<&2,Deferred.Deferred<String>>,reply,None{})
    resolveReply(current,value)
def dropReversed(reversed: String) -> String:
  match reversed:
    case SNil{}: ""
    case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: dropReversed(String.reverse(text))
def printableTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code},rest}: U32.is_ge(code,32) && printableTail(rest)
def printable(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code},rest}: U32.is_ge(code,32) && printableTail(rest)
def inputManual(+state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+url: String,+input: String,+data: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => do IO<Unit>:
    Ref.write(State,state,Waiting{})
    settle(reply,input),_ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),_ => Ref.write(State,state,Manual{url,withoutLast(input)}),_ => Bool.pick(Unit -> IO(Unit),printable(data),_ => Ref.write(State,state,Manual{url,input ++ data}),_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{})
def choose(state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,data: String) -> IO(Unit):
  match data:
    case "1":
      do IO<Unit>:
        Ref.write(State,state,Waiting{})
        settle(reply,"openai-codex")
    case "2":
      do IO<Unit>:
        Ref.write(State,state,Waiting{})
        settle(reply,"anthropic")
    case _: IO.pure(Unit,Unit{})
def receiveCurrent(current: State,+state: Ref.Ref<State>,+reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,editor: Component.Component,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+cancel: Callback.Callback<Unit,Unit>,+data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Choosing{}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => Callback.call(Unit,Unit,cancel,Unit{}),_ => choose(state,reply,data))(Unit{})
    case Manual{url,input}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => Callback.call(Unit,Unit,cancel,Unit{}),_ => inputManual(state,reply,bindings,keyboard,url,input,data))(Unit{})
    case _:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => do IO<Unit>:
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
        Callback.call(Unit,Unit,cancel,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+state,reply,editor,_,bindings,keyboard,cancel}:
      do IO<Unit>:
        current : State <- Ref.read(State,state)
        receiveCurrent(current,state,reply,editor,bindings,keyboard,cancel,data)
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
    case Host{state,_,editor,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : State <- Ref.read(State,state)
        mouseCurrent(current,editor,event)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,_,editor,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,_,editor,_,_,_,_}: Component.setFocused(editor,value)
def create(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    state : Ref.Ref<State> <- Ref.new(State,Closed{})
    reply : Ref.Ref<Maybe<&2,Deferred.Deferred<String>>> <- Ref.new(Maybe<&2,Deferred.Deferred<String>>,None{})
    +host : Host <- IO.pure(Host,Host{state,reply,editor,theme,bindings,keyboard,cancel})
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
def open(host: Host) -> IO(Deferred.Deferred<String>):
  match host:
    case Host{state,reply,editor,_,_,_,_}:
      do IO<Deferred.Deferred<String>>:
        +choice : Deferred.Deferred<String> <- Deferred.new(String)
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{choice})
        Component.setFocused(editor,False{})
        Ref.write(State,state,Choosing{})
        return choice
def showManual(host: Host,url: String) -> IO(Deferred.Deferred<String>):
  match host:
    case Host{state,reply,_,_,_,_,_}:
      do IO<Deferred.Deferred<String>>:
        +input : Deferred.Deferred<String> <- Deferred.new(String)
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{input})
        Ref.write(State,state,Manual{url,""})
        return input
def withCode(current: State,url: String,code: String) -> State & Unit:
  match current:
    case Waiting{}: (Device{url,code},Unit{})
    case _: (current,Unit{})
def showCode(host: Host,url: String,code: String) -> IO(Unit):
  match host: case Host{state,_,_,_,_,_,_}: Ref.modify(State,Unit,state,current => withCode(current,url,code))
def close(host: Host) -> IO(Unit):
  match host:
    case Host{state,reply,editor,_,_,_,_}:
      do IO<Unit>:
        settle(reply,"")
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{state,reply,_,_,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : State <- Ref.dispose(State,state)
        pending : Maybe<&2,Deferred.Deferred<String>> <- Ref.dispose(Maybe<&2,Deferred.Deferred<String>>,reply)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
