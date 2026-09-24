import Base
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/editor-component.bend as Live
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../runtime/src/callback.bend as Callback

# upstream components/custom-editor.ts: the editor with coding-agent's app
# keybindings in front of it. `actions` are the registered app actions in
# registration order (upstream actionHandlers); a matching key calls
# `onAction` with the action name and the editor, otherwise the editor
# handles the key. Extension shortcuts and clipboard image paste are not
# ported yet.
type AppAction is Data: AppAction{name: String,editor: Live.Handle}
type Host is Data:
  Host{editor: Live.Handle,inner: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,actions: List<&2,String>,onAction: Callback.Callback<AppAction,Unit>}
type Owner is Type: Owner{component: Component.Component,input: Callback.Callback<String,Unit>}

def registered(actions: List<&2,String>,+name: String) -> Bool:
  match actions:
    case Nil{}: False{}
    case action <> rest: String.eq(action,name) || registered(rest,name)
def run(+host: Host,+name: String) -> IO(Unit):
  match host:
    case Host{editor,_,_,_,_,onAction}: Callback.call(AppAction,Unit,onAction,AppAction{name,editor})
def forward(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{_,inner,_,_,_,_}: Component.handleInput(inner,data)
def firstMatch(actions: List<&2,String>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> Maybe<&2,String>:
  match actions:
    case Nil{}: None{}
    case +action <> rest:
      Bool.pick(Unit -> Maybe<&2,String>,Bool.not(String.eq(action,"app.interrupt") || String.eq(action,"app.exit")) && Bindings.matches(bindings,keyboard,data,action),_ => Some{action},_ => firstMatch(rest,bindings,keyboard,data))(Unit{})
def otherAction(+host: Host,+data: String,found: Maybe<&2,String>) -> IO(Unit):
  match found:
    case Some{name}: run(host,name)
    case None{}: forward(host,data)
# Explicit history bindings take precedence over app actions, so Ctrl+P can
# be rebound to history even though it cycles models by default.
def otherKey(+host: Host,+data: String) -> IO(Unit):
  match host:
    case Host{editor,inner,+bindings,+keyboard,actions,onAction}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.editor.historyPrevious") || Bindings.matches(bindings,keyboard,data,"tui.editor.historyNext"),
        _ => forward(Host{editor,inner,bindings,keyboard,actions,onAction},data),
        _ => otherAction(Host{editor,inner,bindings,keyboard,actions,onAction},data,firstMatch(actions,bindings,keyboard,data)))(Unit{})
# Exit only from an empty editor; otherwise the key edits (delete forward).
def exitKey(+host: Host,+data: String) -> IO(Unit):
  match host:
    case Host{+editor,inner,bindings,keyboard,+actions,onAction}:
      do IO<Unit>:
        text : String <- Live.text(editor)
        Bool.pick(Unit -> IO(Unit),String.is_empty(text),
          _ => Bool.pick(Unit -> IO(Unit),registered(actions,"app.exit"),_ => run(Host{editor,inner,bindings,keyboard,actions,onAction},"app.exit"),_ => IO.pure(Unit,Unit{}))(Unit{}),
          _ => otherKey(Host{editor,inner,bindings,keyboard,actions,onAction},data))(Unit{})
# Interrupt only without an autocomplete menu; the editor closes the menu.
def interruptKey(+host: Host,+data: String) -> IO(Unit):
  match host:
    case Host{+editor,inner,bindings,keyboard,+actions,onAction}:
      do IO<Unit>:
        menu : Bool <- Live.isShowingAutocomplete(editor)
        Bool.pick(Unit -> IO(Unit),Bool.not(menu) && registered(actions,"app.interrupt"),
          _ => run(Host{editor,inner,bindings,keyboard,actions,onAction},"app.interrupt"),
          _ => forward(Host{editor,inner,bindings,keyboard,actions,onAction},data))(Unit{})
def handleInput(+host: Host,+data: String) -> IO(Unit):
  match host:
    case Host{editor,inner,+bindings,+keyboard,actions,onAction}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"app.interrupt"),
        _ => interruptKey(Host{editor,inner,bindings,keyboard,actions,onAction},data),
        _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"app.exit"),
          _ => exitKey(Host{editor,inner,bindings,keyboard,actions,onAction},data),
          _ => otherKey(Host{editor,inner,bindings,keyboard,actions,onAction},data))(Unit{}))(Unit{})

def receive(host: Host,data: String) -> IO(Unit): handleInput(host,data)
# The wrapped editor keeps its id, rendering, mouse and focus callbacks.
def wrapped(inner: Component.Component,input: Callback.Callback<String,Unit>) -> Component.Component:
  match inner:
    case Component.Component{id,render,_,mouse,invalidate,focus,release}: Component.Component{id,render,Some{input},mouse,invalidate,focus,release}
def create(host: Host) -> IO(Owner):
  match host:
    case Host{editor,+inner,bindings,keyboard,actions,onAction}:
      do IO<Owner>:
        +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,Host{editor,inner,bindings,keyboard,actions,onAction})
        return Owner{wrapped(inner,input),input}
def borrow(owner: Owner) -> Owner & Component.Component:
  match owner:
    case Owner{+component,input}: (Owner{component,input},component)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_,input}: Callback.dispose(String,Unit,input)
