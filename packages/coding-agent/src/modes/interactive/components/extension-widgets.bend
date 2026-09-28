import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/text.bend as Text
import ../../../../../tui/src/tui.bend as Tui
import ../../../core/extensions/context.bend as Ctx
import ../theme/theme.bend as Theme

# Widgets share the editor dock. A replacement owns and retires its old
# component after the last frame that could render it has completed.
type Widget is Data:
  Widget{key: String,owner: Ref.Ref<Component.Owner>,component: Component.Component}
type State is Data:
  State{above: List<&2,Widget>,below: List<&2,Widget>,nextId: Nat,layout: Maybe<&2,Component.Container>}
type Host is Data:
  Host{state: Serial.Handle<State>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,redraw: Callback.Callback<Unit,Unit>}
type Owner is Type:
  Owner{state: Serial.Owner<State>,host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>,children: Callback.Callback<Unit,List<&2,Component.Component>>}
type Lines is Data:
  Lines{content: List<&2,String>,theme: Ref.Ref<Theme.Theme>}

def components(entries: List<&2,Widget>) -> List<&2,Component.Component>:
  match entries:
    case Nil{}: Nil{}
    case Widget{_,_,component} <> rest: component <> components(rest)
def dockChildren(state: State,editor: Component.Component) -> List<&2,Component.Component>:
  match state:
    case State{above,below,_,_}: List.append(&2,Component.Component,components(above),editor <> components(below))
def currentContainer(state: State,editor: Component.Component) -> Component.Container:
  match state:
    case State{_,_,_,Some{container}}: container
    case state: Component.Container{dockChildren(state,editor),None{}}
def rendered(state: State,result: Component.Container & List<&2,String>) -> State & List<&2,String>:
  match state result:
    case State{above,below,nextId,_} Tuple{container,lines}: (State{above,below,nextId,Some{container}},lines)
def drawState(+state: State,editor: Component.Component,width: Nat) -> IO(State & List<&2,String>):
  do IO<State & List<&2,String>>:
    result : Component.Container & List<&2,String> <- Component.renderContainer(Component.Container{dockChildren(state,editor),None{}},width)
    return rendered(state,result)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{state,editor,_,_}: Serial.run(State,List<&2,String>,state,current => drawState(current,editor,width))
def mouseResult(result: Maybe<&2,Component.TuiMouseDispatchResult()>) -> Maybe<&2,Component.MouseResponse()>:
  Maybe.map(&2,Component.TuiMouseDispatchResult(),Component.MouseResponse(),value => Component.DispatchedResult{value},result)
def mouseState(+state: State,+editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(State & Maybe<&2,Component.MouseResponse()>):
  do IO<State & Maybe<&2,Component.MouseResponse()>>:
    response : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.handleMouse(currentContainer(state,editor),Component.id(editor),False{},event)
    return (state,mouseResult(response))
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match host:
    case Host{state,editor,_,_}: Serial.run(State,Maybe<&2,Component.MouseResponse()>,state,current => mouseState(current,editor,event))
def input(host: Host,data: String) -> IO(Unit):
  match host: case Host{_,editor,_,_}: Component.handleInput(editor,data)
def invalidateEntries(entries: List<&2,Widget>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case Widget{_,_,component} <> rest:
      do IO<Unit>:
        Component.invalidate(component)
        invalidateEntries(rest)
def invalidateState(state: State) -> IO(State & Unit):
  match state:
    case State{+above,+below,nextId,_}:
      do IO<State & Unit>:
        invalidateEntries(above)
        invalidateEntries(below)
        return (State{above,below,nextId,None{}},Unit{})
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host:
    case Host{state,editor,_,_}:
      do IO<Unit>:
        Component.invalidate(editor)
        Serial.run(State,Unit,state,invalidateState)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_}: Component.setFocused(editor,value)
def childState(state: State) -> State & List<&2,Component.Component>:
  match state:
    case State{+above,+below,nextId,layout}: (State{above,below,nextId,layout},List.append(&2,Component.Component,components(above),components(below)))
def children(host: Host,_: Unit) -> IO(List<&2,Component.Component>):
  match host: case Host{state,_,_,_}: Serial.run(State,List<&2,Component.Component>,state,current => IO.pure(State & List<&2,Component.Component>,childState(current)))

def appended(pair: Text.Text & List<&2,String>,following: List<&2,String>) -> List<&2,String>:
  match pair: case Tuple{_,rows}: List.append(&2,String,rows,following)
def textRows(lines: List<&2,String>,+width: Nat) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case line <> rest:
      do IO<List<&2,String>>:
        pair : Text.Text & List<&2,String> <- Text.render(Text.new(line,Some{1n},Some{0n},None{}),width)
        following : List<&2,String> <- textRows(rest,width)
        return appended(pair,following)
def shownLines(+lines: List<&2,String>,theme: Theme.Theme) -> List<&2,String>:
  +shown = List.take(&2,String,lines,10n)
  Bool.pick(List<&2,String>,Nat.is_lt(10n,List.length(&2,String,lines)),List.append(&2,String,shown,[Theme.fg(theme,"muted","... (widget truncated)")]),shown)
def renderLines(env: Lines,width: Nat) -> IO(List<&2,String>):
  match env:
    case Lines{content,theme}:
      do IO<List<&2,String>>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        textRows(shownLines(content,current),width)
def noInvalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def lineOwner(id: Nat,lines: List<&2,String>,theme: Ref.Ref<Theme.Theme>) -> IO(Component.Owner):
  do IO<Component.Owner>:
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Lines,~Nat,~List<&2,String>,~renderLines,Lines{lines,theme})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    return Component.Owner{Component.Component{Component.ComponentId{id},render,None{},None{},invalidate,None{},False{}},_ => do IO<Unit>:
      Callback.dispose(Nat,List<&2,String>,render)
      Callback.dispose(Unit,Unit,invalidate)}
def advance(state: State) -> State & Nat:
  match state:
    case State{above,below,nextId,layout}:
      +id = nextId + 1n
      (State{above,below,id,layout},id)
def freshId(host: Host) -> IO(Nat):
  match host: case Host{state,_,_,_}: Serial.run(State,Nat,state,current => IO.pure(State & Nat,advance(current)))
def withOwner(key: String,owner: Component.Owner) -> IO(Widget):
  match owner:
    case Component.Owner{+component,retire}:
      do IO<Widget>:
        reference : Ref.Ref<Component.Owner> <- Ref.new(Component.Owner,Component.Owner{component,retire})
        return Widget{key,reference,component}
def lineWidget(host: Host,key: String,lines: List<&2,String>,id: Nat) -> IO(Maybe<&2,Widget>):
  match host:
    case Host{_,_,theme,_}:
      do IO<Maybe<&2,Widget>>:
        owner : Component.Owner <- lineOwner(id,lines,theme)
        widget : Widget <- withOwner(key,owner)
        return Some{widget}
def createWidget(+host: Host,key: String,content: Maybe<&2,Ctx.WidgetContent>) -> IO(Maybe<&2,Widget>):
  match content:
    case None{}: IO.pure(Maybe<&2,Widget>,None{})
    case Some{Ctx.WidgetLines{lines}}:
      do IO<Maybe<&2,Widget>>:
        id : Nat <- freshId(host)
        lineWidget(host,key,lines,id)
    case Some{Ctx.WidgetComponent{factory}}:
      do IO<Maybe<&2,Widget>>:
        owner : Component.Owner <- Callback.call(Unit,Component.Owner,factory,Unit{})
        widget : Widget <- withOwner(key,owner)
        return Some{widget}
def kept(widget: Widget,result: List<&2,Widget> & Maybe<&2,Widget>) -> List<&2,Widget> & Maybe<&2,Widget>:
  match result: case (rest,removed): (widget <> rest,removed)
def without(entries: List<&2,Widget>,+key: String) -> List<&2,Widget> & Maybe<&2,Widget>:
  match entries:
    case Nil{}: (Nil{},None{})
    case Widget{+found,+owner,+component} <> +rest:
      Bool.pick(Unit -> List<&2,Widget> & Maybe<&2,Widget>,String.eq(found,key),
        _ => (rest,Some{Widget{found,owner,component}}),
        _ => kept(Widget{found,owner,component},without(rest,key)))(Unit{})
def afterRemoval(upper: List<&2,Widget> & Maybe<&2,Widget>,lower: List<&2,Widget> & Maybe<&2,Widget>,entry: Maybe<&2,Widget>,placement: Maybe<&2,Ctx.WidgetPlacement>,nextId: Nat) -> State & (Maybe<&2,Widget> & Maybe<&2,Widget>):
  match upper lower entry placement:
    case Tuple{above,oldAbove} Tuple{below,oldBelow} None{} _:
      (State{above,below,nextId,None{}},(oldAbove,oldBelow))
    case Tuple{above,oldAbove} Tuple{below,oldBelow} Some{widget} Some{Ctx.BelowEditor{}}:
      (State{above,List.append(&2,Widget,below,[widget]),nextId,None{}},(oldAbove,oldBelow))
    case Tuple{above,oldAbove} Tuple{below,oldBelow} Some{widget} _:
      (State{List.append(&2,Widget,above,[widget]),below,nextId,None{}},(oldAbove,oldBelow))
def replaced(state: State,+key: String,entry: Maybe<&2,Widget>,placement: Maybe<&2,Ctx.WidgetPlacement>) -> State & (Maybe<&2,Widget> & Maybe<&2,Widget>):
  match state:
    case State{above,below,nextId,_}: afterRemoval(without(above,key),without(below,key),entry,placement,nextId)
def disposeOne(entry: Maybe<&2,Widget>) -> IO(Unit):
  match entry:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Widget{_,reference,_}}:
      do IO<Unit>:
        owner : Component.Owner <- Ref.dispose(Component.Owner,reference)
        Component.dispose(owner)
def disposeEntries(entries: List<&2,Widget>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case Widget{_,reference,_} <> rest:
      do IO<Unit>:
        owner : Component.Owner <- Ref.dispose(Component.Owner,reference)
        Component.dispose(owner)
        disposeEntries(rest)
def disposeRemoved(pair: Maybe<&2,Widget> & Maybe<&2,Widget>) -> IO(Unit):
  match pair:
    case (above,below):
      do IO<Unit>:
        disposeOne(above)
        disposeOne(below)
def setWidget(host: Host,update: Ctx.WidgetUpdate) -> IO(Unit):
  match host update:
    case Host{+state,editor,theme,+redraw} Ctx.WidgetUpdate{+key,content,placement}:
      do IO<Unit>:
        +entry : Maybe<&2,Widget> <- createWidget(Host{state,editor,theme,redraw},key,content)
        old : Maybe<&2,Widget> & Maybe<&2,Widget> <- Serial.run(State,Maybe<&2,Widget> & Maybe<&2,Widget>,state,current => IO.pure(State & (Maybe<&2,Widget> & Maybe<&2,Widget>),replaced(current,key,entry,placement)))
        disposeRemoved(old)
        Callback.call(Unit,Unit,redraw,Unit{})
def built(pair: Serial.Owner<State> & Serial.Handle<State>,+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  match pair:
    case (stateOwner,state):
      do IO<Owner>:
        +host : Host <- IO.pure(Host,Host{state,editor,theme,redraw})
        +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
        +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~input,host)
        +mouse : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,host)
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
        +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
        +children : Callback.Callback<Unit,List<&2,Component.Component>> <- Callback.create(~Host,~Unit,~List<&2,Component.Component>,~children,host)
        +base : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouse},invalidate,Some{focus},False{}})
        return Owner{stateOwner,host,Component.Group{base,children},render,input,mouse,invalidate,focus,children}
def create(editor: Component.Component,theme: Ref.Ref<Theme.Theme>,redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    owner : Serial.Owner<State> <- Serial.create(State,State{Nil{},Nil{},1000000n,None{}})
    built(Serial.borrow(State,owner),editor,theme,redraw)
def borrow(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{state,+host,+component,render,input,mouse,invalidate,focus,children}: (Owner{state,host,component,render,input,mouse,invalidate,focus,children},host,component)
def retire(state: State,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>,children: Callback.Callback<Unit,List<&2,Component.Component>>) -> IO(Unit):
  match state:
    case State{above,below,_,_}:
      do IO<Unit>:
        disposeEntries(above)
        disposeEntries(below)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Callback.dispose(Unit,List<&2,Component.Component>,children)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,_,_,render,input,mouse,invalidate,focus,children}:
      do IO<Unit>:
        current : State <- Serial.retire(State,state)
        retire(current,render,input,mouse,invalidate,focus,children)
