import Base
import ../../../../../runtime/src/abort.bend as Abort
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/date.bend as Date
import ../../../../../runtime/src/f64.bend as F
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/keybindings.bend as Bindings
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints

# A focused progress view in place of the editor. The editor and its nested
# components stay mounted and resume when the operation clears the activity.
type Activity is Data: Activity{controller: Abort.AbortController<Unit>,message: String,startedAt: F64}
type Context is Data:
  Context{editor: Component.Component,activity: Ref.Ref<Maybe<&2,Activity>>,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager}
type Owner is Type:
  Owner{component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>,children: Callback.Callback<Unit,List<&2,Component.Component>>}

def color(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)

def frame(now: F64,startedAt: F64) -> String:
  +index = U32.to_nat(F64.to_u32(F64.floor(F.divide(F.subtract(now,startedAt),F.fromU32(80))))) % 10n
  Maybe.default(&2,String,List.get(&2,String,["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"],index),"⠋")

def progress(+theme: Theme.Theme,bindings: Bindings.KeybindingsManager,+message: String,+spinnerFrame: String,+width: Nat) -> List<&2,String>:
  +border = color(theme,"border",String.repeat("─",Nat.max(1n,width)))
  +spinner = " " ++ color(theme,"accent",spinnerFrame) ++ " " ++ color(theme,"muted",message)
  +hint = " " ++ color(theme,"dim",Hints.keyText(bindings,"tui.select.cancel")) ++ color(theme,"muted"," cancel")
  [border,"",spinner,"",hint,"",border]

def renderActive(editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,width: Nat,active: Maybe<&2,Activity>) -> IO(List<&2,String>):
  match active:
    case None{}: Component.render(editor,width)
    case Some{Activity{_,message,startedAt}}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        now : F64 <- Date.now()
        return progress(chosen,bindings,message,frame(now,startedAt),width)

def render(context: Context,width: Nat) -> IO(List<&2,String>):
  match context:
    case Context{editor,activity,theme,bindings}:
      do IO<List<&2,String>>:
        active : Maybe<&2,Activity> <- Ref.read(Maybe<&2,Activity>,activity)
        renderActive(editor,theme,bindings,width,active)

def input(context: Context,data: String) -> IO(Unit):
  match context: case Context{editor,_,_,_}: Component.handleInput(editor,data)

def forwardedMouse(event: Tui.TuiMouseEvent,handler: Maybe<&2,Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>>) -> IO(Maybe<&2,Component.MouseResponse()>):
  match handler:
    case None{}: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
    case Some{callback}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,callback,event)

def mouseActive(editor: Component.Component,event: Tui.TuiMouseEvent,active: Maybe<&2,Activity>) -> IO(Maybe<&2,Component.MouseResponse()>):
  match active:
    case Some{_}: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
    case None{}: forwardedMouse(event,Component.mouseHandler(editor))

def mouse(context: Context,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match context:
    case Context{editor,activity,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        active : Maybe<&2,Activity> <- Ref.read(Maybe<&2,Activity>,activity)
        mouseActive(editor,event,active)

def invalidate(context: Context,ignored: Unit) -> IO(Unit):
  match context: case Context{editor,_,_,_}: Component.invalidate(editor)

def focus(context: Context,focused: Bool) -> IO(Unit):
  match context: case Context{editor,_,_,_}: Component.setFocused(editor,focused)

def childrenActive(editor: Component.Component,active: Maybe<&2,Activity>) -> IO(List<&2,Component.Component>):
  match active:
    case Some{_}: IO.pure(List<&2,Component.Component>,Nil{})
    case None{}: Component.children(editor)

def children(context: Context,ignored: Unit) -> IO(List<&2,Component.Component>):
  match context:
    case Context{editor,activity,_,_}:
      do IO<List<&2,Component.Component>>:
        active : Maybe<&2,Activity> <- Ref.read(Maybe<&2,Activity>,activity)
        childrenActive(editor,active)

def wantsRelease(component: Component.Component) -> Bool:
  match component:
    case Component.Component{_,_,_,_,_,_,release}: release
    case Component.Group{child,_}: wantsRelease(child)
    case Component.Managed{child,_}: wantsRelease(child)

def create(+editor: Component.Component,+activity: Ref.Ref<Maybe<&2,Activity>>,+theme: Ref.Ref<Theme.Theme>,+bindings: Bindings.KeybindingsManager) -> IO(Owner):
  do IO<Owner>:
    +context : Context <- IO.pure(Context,Context{editor,activity,theme,bindings})
    +rendered : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Context,~Nat,~List<&2,String>,~render,context)
    +typed : Callback.Callback<String,Unit> <- Callback.create(~Context,~String,~Unit,~input,context)
    +moused : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Context,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,context)
    +invalidated : Callback.Callback<Unit,Unit> <- Callback.create(~Context,~Unit,~Unit,~invalidate,context)
    +focused : Callback.Callback<Bool,Unit> <- Callback.create(~Context,~Bool,~Unit,~focus,context)
    +nested : Callback.Callback<Unit,List<&2,Component.Component>> <- Callback.create(~Context,~Unit,~List<&2,Component.Component>,~children,context)
    +root : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),rendered,Some{typed},Some{moused},invalidated,Some{focused},wantsRelease(editor)})
    return Owner{Component.Group{root,nested},rendered,typed,moused,invalidated,focused,nested}

def borrow(owner: Owner) -> Owner & Component.Component:
  match owner:
    case Owner{+component,render,input,mouse,invalidate,focus,children}: (Owner{component,render,input,mouse,invalidate,focus,children},component)

def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_,render,input,mouse,invalidate,focus,children}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Callback.dispose(Unit,List<&2,Component.Component>,children)
