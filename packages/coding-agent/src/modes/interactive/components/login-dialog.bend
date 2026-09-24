import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/deferred.bend as Deferred
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../theme/theme.bend as Theme

# Replaces the editor while the native device flow waits for authorization.
# Esc calls the flow's abort controller; closing restores the original editor.
type Choice is Data: Choice{id: String,label: String,description: String}
type State is Data: Closed{} Choosing{title: String,all: List<&2,Choice>,visible: List<&2,Choice>,selected: Nat,query: String} Waiting{} Device{url: String,code: String} Manual{url: String,input: String}
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
def linked(+url: String,width: Nat) -> String:
  +label = clipped(url,width - 1n)
  " \u{1b}]8;;" ++ url ++ "\u{7}" ++ label ++ "\u{1b}]8;;\u{7}"
def clipLines(lines: List<&2,String>,+width: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: clipped(line,width) <> clipLines(rest,width)
def frameLines(+theme: Theme.Theme,+width: Nat,title: String,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent",title) <> "" <> List.append(&2,String,body,paint(theme,"dim",bar(width)) <> Nil{})
def frame(theme: Theme.Theme,+width: Nat,title: String,body: List<&2,String>) -> List<&2,String>:
  clipLines(frameLines(theme,width,title,body),width)
def linkedFrame(+theme: Theme.Theme,+width: Nat,title: String,url: String,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent",title) <> "" <> paint(theme,"accent",linked(url,width)) <> List.append(&2,String,clipLines(body,width),paint(theme,"dim",bar(width)) <> Nil{})
def waiting(+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  frame(theme,width," Login to OpenAI Codex",paint(theme,"dim"," Requesting device code...") <> "" <> " (Esc to cancel)" <> Nil{})
def searchText(choice: Choice) -> String:
  match choice: case Choice{id,label,description}: id ++ " " ++ label ++ " " ++ description
def filtered(+choices: List<&2,Choice>,+query: String) -> List<&2,Choice>:
  Bool.pick(List<&2,Choice>,String.is_empty(query),choices,Fuzzy.fuzzyFilter(~Choice,~searchText,choices,query))
def choiceRow(choice: Choice,+index: Nat,+selected: Nat,width: Nat,theme: Theme.Theme) -> String:
  match choice:
    case Choice{_,label,+description}:
      +text = Bool.pick(String,Nat.is_eq(index,selected)," › ","   ") ++ label ++ Bool.pick(String,String.is_empty(description),""," · " ++ description)
      Utils.truncateToWidth(paint(theme,Bool.pick(String,Nat.is_eq(index,selected),"accent","muted"),text),width,"",False{})
def choiceRows(choices: List<&2,Choice>,+index: Nat,+selected: Nat,+width: Nat,+theme: Theme.Theme) -> List<&2,String>:
  match choices:
    case Nil{}: Nil{}
    case choice <> rest: choiceRow(choice,index,selected,width,theme) <> choiceRows(rest,index + 1n,selected,width,theme)
def choosing(+theme: Theme.Theme,+width: Nat,title: String,+visible: List<&2,Choice>,+selected: Nat,query: String) -> List<&2,String>:
  +count = List.length(&2,Choice,visible)
  +start = Nat.min(selected - 5n,count - Nat.min(count,10n))
  +body = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching credentials") <> Nil{},choiceRows(List.take(&2,Choice,List.drop(&2,Choice,visible,start),10n),start,selected,width,theme))
  frame(theme,width,title,(paint(theme,"muted"," Search: ") ++ paint(theme,"accent",query)) <> List.append(&2,String,body,"" <> paint(theme,"dim"," ↑/↓ select · Enter confirm · Esc cancel") <> Nil{}))
def manual(+theme: Theme.Theme,+width: Nat,+url: String,+input: String) -> List<&2,String>:
  linkedFrame(theme,width," Login to Anthropic",url,paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"dim"," Complete login in your browser; paste the redirect URL if it is on another machine.") <> paint(theme,"warning"," Paste authorization code or redirect URL:") <> clipped(" " ++ input,width) <> "" <> paint(theme,"dim"," Enter to submit · Esc to cancel") <> Nil{})
def device(+theme: Theme.Theme,+width: Nat,+url: String,code: String) -> List<&2,String>:
  linkedFrame(theme,width," Login to OpenAI Codex",url,paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"warning"," Enter code: " ++ code) <> "" <> paint(theme,"dim"," Waiting for authentication...") <> " (Esc to cancel)" <> Nil{})
def drawCurrent(state: State,editor: Component.Component,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match state:
    case Closed{}: Component.render(editor,width)
    case Choosing{title,_,visible,selected,query}: IO.pure(List<&2,String>,choosing(theme,width,title,visible,selected,query))
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
def choiceId(choice: Maybe<&2,Choice>) -> Maybe<&2,String>:
  match choice:
    case None{}: None{}
    case Some{Choice{id,_,_}}: Some{id}
def selectedChoice(state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,choice: Maybe<&2,String>) -> IO(Unit):
  match choice:
    case None{}: IO.pure(Unit,Unit{})
    case Some{id}:
      do IO<Unit>:
        Ref.write(State,state,Waiting{})
        settle(reply,id)
def chooseIndex(state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,choices: List<&2,Choice>,index: Nat) -> IO(Unit):
  selectedChoice(state,reply,choiceId(List.get(&2,Choice,choices,index)))
def menuChanged(state: Ref.Ref<State>,title: String,+all: List<&2,Choice>,selected: Nat,+query: String) -> IO(Unit):
  Ref.write(State,state,Choosing{title,all,filtered(all,query),selected,query})
def moveChoice(state: Ref.Ref<State>,title: String,all: List<&2,Choice>,visible: List<&2,Choice>,+selected: Nat,query: String,up: Bool) -> IO(Unit):
  +count = List.length(&2,Choice,visible)
  +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(selected,0n),count - 1n,selected - 1n),Bool.pick(Nat,Nat.is_eq(selected,count - 1n),0n,selected + 1n))
  menuChanged(state,title,all,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),query)
def menuInput(+state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+title: String,+all: List<&2,Choice>,+visible: List<&2,Choice>,+selected: Nat,+query: String,+data: String) -> IO(Unit):
  match data:
    case "1": chooseIndex(state,reply,visible,0n)
    case "2": chooseIndex(state,reply,visible,1n)
    case _:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.up"),
        _ => moveChoice(state,title,all,visible,selected,query,True{}),
        _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.down"),
          _ => moveChoice(state,title,all,visible,selected,query,False{}),
          _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),
            _ => chooseIndex(state,reply,visible,selected),
            _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),
              _ => menuChanged(state,title,all,0n,withoutLast(query)),
              _ => Bool.pick(Unit -> IO(Unit),printable(data),
                _ => menuChanged(state,title,all,0n,query ++ data),
                _ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def receiveCurrent(current: State,+state: Ref.Ref<State>,+reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,editor: Component.Component,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+cancel: Callback.Callback<Unit,Unit>,+data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Choosing{title,all,visible,selected,query}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => Callback.call(Unit,Unit,cancel,Unit{}),_ => menuInput(state,reply,bindings,keyboard,title,all,visible,selected,query,data))(Unit{})
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
def openChoices(host: Host,title: String,+choices: List<&2,Choice>) -> IO(Deferred.Deferred<String>):
  match host:
    case Host{state,reply,editor,_,_,_,_}:
      do IO<Deferred.Deferred<String>>:
        +choice : Deferred.Deferred<String> <- Deferred.new(String)
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{choice})
        Component.setFocused(editor,False{})
        Ref.write(State,state,Choosing{title,choices,choices,0n,""})
        return choice
def open(host: Host) -> IO(Deferred.Deferred<String>):
  openChoices(host," Login · Choose a provider",Choice{"openai-codex","OpenAI Codex","subscription"} <> Choice{"anthropic","Anthropic (Claude Pro/Max)","subscription"} <> Nil{})
def openDirect(host: Host) -> IO(Unit):
  match host:
    case Host{state,_,editor,_,_,_,_}:
      do IO<Unit>:
        Component.setFocused(editor,False{})
        Ref.write(State,state,Waiting{})
def showManual(host: Host,url: String,answer: Deferred.Deferred<String>) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{answer})
        Ref.write(State,state,Manual{url,""})
def waitingAfterManual(current: State) -> State & Unit:
  match current:
    case Closed{}: (Closed{},Unit{})
    case _: (Waiting{},Unit{})
def stopManual(host: Host) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,_}:
      do IO<Unit>:
        settle(reply,"")
        Ref.modify(State,Unit,state,waitingAfterManual)
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
