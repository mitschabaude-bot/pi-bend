import Base
import ../../../../../tui/src/tui.bend as T
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../ai/src/types.bend as Ai
import ../../../core/messages.bend as Core
import ../../../core/extensions/types.bend as Extensions
import ../theme/theme.bend as Theme
import ./messages.bend as Messages

type Displayed is Data:
  Displayed{component: Component.Component,width: Nat,height: Nat,start: Nat}
type Content is Type:
  Content{child: Maybe<&1,Component.Owner>,retired: List<&1,Component.Owner>,displayed: Maybe<&2,Displayed>}
type State is Type:
  State{id: Component.ComponentId, message: Core.CustomMessage<Value.Value>, renderer: Maybe<&2, Extensions.MessageRenderer()>, options: Extensions.MessageRenderOptions, theme: Theme.Theme, markdownTheme: Markdown.MarkdownTheme, child: Content, custom: Bool}
type Handle is Data: Handle{state: Serial.Handle<State>}
type Owner is Type:
  Owner{state: Serial.Owner<State>, component: Component.Component, render: Callback.Callback<Nat, List<&2, String>>, invalidate: Callback.Callback<Unit, Unit>,children: Callback.Callback<Unit,List<&2,Component.Component>>,mouse: Callback.Callback<T.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>}

def disposeChild(child: Maybe<&1, Component.Owner>) -> IO(Unit):
  match child:
    case None{}: IO.pure(Unit, Unit{})
    case Some{owner}: Component.dispose(owner)

def contentPieces(blocks: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text <> contentPieces(rest)
    case _ <> rest: contentPieces(rest)
def contentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: String.join(contentPieces(blocks), "\n")
def defaultBody(message: Core.CustomMessage<Value.Value>, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> Messages.Body:
  match message:
    case Core.CustomMessage{label, content, _, _, _}: Messages.NoteBody{Messages.Note{label, None{}, contentText(content), True{}, theme, markdown, ""}}
def ownDefault(pair: Messages.Owner & Component.Component & Messages.Handle) -> Component.Owner:
  match pair:
    case Tuple{owner, Tuple{component, _}}: Component.Owner{component, _ => Messages.dispose(owner)}

def disposeRetired(owners: List<&1,Component.Owner>) -> IO(Unit):
  match owners:
    case Nil{}: IO.pure(Unit,Unit{})
    case owner <> rest:
      do IO<Unit>:
        Component.dispose(owner)
        disposeRetired(rest)
def fallback(state: State) -> IO(State):
  match state:
    case State{+id,+message,renderer,options,+theme,+markdown,Content{_,retired,displayed},_}:
      do IO<State>:
        owner : Messages.Owner <- Messages.create(id,defaultBody(message,theme,markdown))
        return State{id,message,renderer,options,theme,markdown,Content{Some{ownDefault(Messages.borrow(owner))},retired,displayed},False{}}
def installed(state: State,result: Extensions.MessageRenderResult()) -> IO(State):
  match state result:
    case State{id,message,renderer,options,theme,markdown,Content{_,retired,displayed},_} Done{Some{owner}}:
      do IO<State>:
        shared : Component.Owner <- Component.shared(owner)
        return State{id,message,renderer,options,theme,markdown,Content{Some{shared},retired,displayed},True{}}
    case state _: fallback(state)
def renderSelected(state: State) -> IO(State):
  match state:
    case State{+id,+message,Some{+renderer},+options,+theme,markdown,content,_}:
      do IO<State>:
        result : Extensions.MessageRenderResult() <- Callback.call(Extensions.MessageRenderInput,Extensions.MessageRenderResult(),renderer,Extensions.MessageRenderInput{message,options,theme})
        installed(State{id,message,Some{renderer},options,theme,markdown,content,False{}},result)
    case state: fallback(state)
# Cached hit testing owns the last displayed child until the next render.
# Replacements that have never been displayed can be retired immediately.
def replaced(content: Content) -> IO(Content):
  match content:
    case Content{Some{owner},retired,Some{displayed}}:
      IO.pure(Content,Content{None{},owner <> retired,Some{displayed}})
    case Content{child,retired,displayed}:
      do IO<Content>:
        disposeChild(child)
        return Content{None{},retired,displayed}
def rebuild(state: State) -> IO(State):
  match state:
    case State{id,message,renderer,options,theme,markdown,content,_}:
      do IO<State>:
        next : Content <- replaced(content)
        renderSelected(State{id,message,renderer,options,theme,markdown,next,False{}})
def renderState(state: State,+width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{id,message,renderer,options,theme,markdown,Content{Some{Component.Owner{+component,retire}},retired,_},+custom}:
      do IO<State & List<&2,String>>:
        +rows : List<&2,String> <- Component.render(component,width)
        disposeRetired(retired)
        start : Nat = Bool.pick(Nat,custom,1n,0n)
        return (State{id,message,renderer,options,theme,markdown,Content{Some{Component.Owner{component,retire}},Nil{},Some{Displayed{component,width,List.length(&2,String,rows),start}}},custom},Bool.pick(List<&2,String>,custom,"" <> rows,rows))
    case state: IO.pure(State & List<&2,String>,(state,Nil{}))
def render(handle: Handle, width: Nat) -> IO(List<&2, String>):
  match handle:
    case Handle{state}: Serial.run(State, List<&2, String>, state, current => renderState(current, width))

def invalidateChild(state: State) -> IO(State):
  match state:
    case State{id, message, renderer, options, theme, markdown, Content{Some{Component.Owner{+component, retire}},retired,displayed}, custom}:
      do IO<State>:
        Component.invalidate(component)
        return State{id, message, renderer, options, theme, markdown, Content{Some{Component.Owner{component, retire}},retired,displayed}, custom}
    case state: IO.pure(State, state)
def invalidated(state: State) -> IO(State & Unit):
  do IO<State & Unit>:
    current : State <- invalidateChild(state)
    rebuilt : State <- rebuild(current)
    return (rebuilt, Unit{})
def invalidate(handle: Handle, _: Unit) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, invalidated)

def changed(state: State, options: Extensions.MessageRenderOptions) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, _, theme, markdown, child, custom}:
      do IO<State & Unit>:
        current : State <- rebuild(State{id, message, renderer, options, theme, markdown, child, custom})
        return (current, Unit{})
def updateOptions(different: Bool, state: State, options: Extensions.MessageRenderOptions) -> IO(State & Unit):
  match different:
    case False{}: IO.pure(State & Unit, (state, Unit{}))
    case True{}: changed(state, options)
def expanded(state: State, +value: Bool) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, Extensions.MessageRenderOptions{+current, +pad}, theme, markdown, child, custom}:
      updateOptions(Bool.xor(current, value), State{id, message, renderer, Extensions.MessageRenderOptions{current, pad}, theme, markdown, child, custom}, Extensions.MessageRenderOptions{value, pad})
def setExpanded(handle: Handle, value: Bool) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => expanded(current, value))
def padded(state: State, +value: Nat) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, Extensions.MessageRenderOptions{+isExpanded, +current}, theme, markdown, child, custom}:
      updateOptions(Bool.not(Nat.is_eq(current, value)), State{id, message, renderer, Extensions.MessageRenderOptions{isExpanded, current}, theme, markdown, child, custom}, Extensions.MessageRenderOptions{isExpanded, value})
def setOutputPad(handle: Handle, value: Nat) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => padded(current, value))

def themed(state: State, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, options, _, _, child, custom}:
      do IO<State & Unit>:
        current : State <- rebuild(State{id, message, renderer, options, theme, markdown, child, custom})
        return (current, Unit{})
def setTheme(handle: Handle, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => themed(current, theme, markdown))

def currentChildren(state: State) -> IO(State & List<&2,Component.Component>):
  match state:
    case State{id,message,renderer,options,theme,markdown,Content{Some{Component.Owner{+component,retire}},retired,displayed},True{}}:
      IO.pure(State & List<&2,Component.Component>,(State{id,message,renderer,options,theme,markdown,Content{Some{Component.Owner{component,retire}},retired,displayed},True{}},component <> Nil{}))
    case state: IO.pure(State & List<&2,Component.Component>,(state,Nil{}))
def children(handle: Handle,_: Unit) -> IO(List<&2,Component.Component>):
  match handle:
    case Handle{state}: Serial.run(State,List<&2,Component.Component>,state,currentChildren)
def routeDisplayed(value: Displayed,+event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match value event:
    case Displayed{component,_,height,start} T.TuiMouseEvent{_,_,_,+y,_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        result : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.routeMouse(Component.ChildLayout{component,height} <> Nil{},event,y,start)
        return Maybe.map(&2,Component.TuiMouseDispatchResult(),Component.MouseResponse(),value => Component.DispatchedResult{value},result)
def measured(content: Content,+width: Nat,+custom: Bool) -> IO(Content & Maybe<&2,Displayed>):
  match content:
    case Content{Some{Component.Owner{+component,retire}},retired,displayed}:
      do IO<Content & Maybe<&2,Displayed>>:
        rows : List<&2,String> <- Component.render(component,width)
        return (Content{Some{Component.Owner{component,retire}},retired,displayed},Some{Displayed{component,width,List.length(&2,String,rows),Bool.pick(Nat,custom,1n,0n)}})
    case content: IO.pure(Content & Maybe<&2,Displayed>,(content,None{}))
def matchingLayout(matches: Bool,content: Content,displayed: Displayed,width: Nat,custom: Bool) -> IO(Content & Maybe<&2,Displayed>):
  match matches:
    case True{}: IO.pure(Content & Maybe<&2,Displayed>,(content,Some{displayed}))
    case False{}: measured(content,width,custom)
def mouseLayout(+width: Nat,custom: Bool,content: Content) -> IO(Content & Maybe<&2,Displayed>):
  match content:
    case Content{child,retired,Some{Displayed{+component,+cachedWidth,+height,+start}}}:
      matchingLayout(Nat.is_eq(width,cachedWidth),Content{child,retired,Some{Displayed{component,cachedWidth,height,start}}},Displayed{component,cachedWidth,height,start},width,custom)
    case content: measured(content,width,custom)
def selectedLayout(state: State,result: Content & Maybe<&2,Displayed>) -> State & Maybe<&2,Displayed>:
  match state result:
    case State{id,message,renderer,options,theme,markdown,_,custom} Tuple{content,displayed}:
      (State{id,message,renderer,options,theme,markdown,content,custom},displayed)
def mouseState(state: State,width: Nat) -> IO(State & Maybe<&2,Displayed>):
  match state:
    case State{id,message,renderer,options,theme,markdown,content,+custom}:
      do IO<State & Maybe<&2,Displayed>>:
        result : Content & Maybe<&2,Displayed> <- mouseLayout(width,custom,content)
        return selectedLayout(State{id,message,renderer,options,theme,markdown,Content{None{},Nil{},None{}},custom},result)
def routeLayout(displayed: Maybe<&2,Displayed>,event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match displayed:
    case None{}: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
    case Some{value}: routeDisplayed(value,event)
def mouseRequest(handle: Handle,+event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match handle event:
    case Handle{state} T.TuiMouseEvent{_,_,_,_,_,_,width,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        displayed : Maybe<&2,Displayed> <- Serial.run(State,Maybe<&2,Displayed>,state,current => mouseState(current,width))
        routeLayout(displayed,event)
def mouse(handle: Handle,event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  mouseRequest(handle,event)

def mounted(id: Component.ComponentId, pair: Serial.Owner<State> & Serial.Handle<State>) -> IO(Owner):
  match pair:
    case Tuple{owner, +state}:
      do IO<Owner>:
        +handle : Handle = Handle{state}
        +renderCallback : Callback.Callback<Nat, List<&2, String>> <- Callback.create(~Handle, ~Nat, ~List<&2, String>, ~render, handle)
        +invalidateCallback : Callback.Callback<Unit, Unit> <- Callback.create(~Handle, ~Unit, ~Unit, ~invalidate, handle)
        +childrenCallback : Callback.Callback<Unit,List<&2,Component.Component>> <- Callback.create(~Handle,~Unit,~List<&2,Component.Component>,~children,handle)
        +mouseCallback : Callback.Callback<T.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Handle,~T.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,handle)
        return Owner{owner,Component.Group{Component.Component{id,renderCallback,None{},Some{mouseCallback},invalidateCallback,None{},False{}},childrenCallback},renderCallback,invalidateCallback,childrenCallback,mouseCallback}
def create(+id: Component.ComponentId, message: Core.CustomMessage<Value.Value>, renderer: Maybe<&2, Extensions.MessageRenderer()>, theme: Theme.Theme, markdown: Markdown.MarkdownTheme, outputPad: Nat) -> IO(Owner):
  do IO<Owner>:
    current : State <- rebuild(State{id, message, renderer, Extensions.MessageRenderOptions{False{}, outputPad}, theme, markdown, Content{None{},Nil{},None{}}, False{}})
    owner : Serial.Owner<State> <- Serial.create(State, current)
    mounted(id, Serial.borrow(State, owner))
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>, +component: Component.Component, renderCallback: Callback.Callback<Nat, List<&2, String>>, invalidateCallback: Callback.Callback<Unit, Unit>,childrenCallback: Callback.Callback<Unit,List<&2,Component.Component>>,mouseCallback: Callback.Callback<T.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>) -> Owner & Component.Component & Handle:
  match pair:
    case Tuple{state, handle}: (Owner{state, component, renderCallback, invalidateCallback,childrenCallback,mouseCallback}, component, Handle{handle})
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{state, component, renderCallback, invalidateCallback,childrenCallback,mouseCallback}: borrowed(Serial.borrow(State, state), component, renderCallback, invalidateCallback,childrenCallback,mouseCallback)
def disposed(state: State) -> IO(Unit):
  match state:
    case State{_,_,_,_,_,_,Content{child,retired,_},_}:
      do IO<Unit>:
        disposeChild(child)
        disposeRetired(retired)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state, _, render, invalidate,children,mouse}:
      do IO<Unit>:
        current : State <- Serial.retire(State, state)
        disposed(current)
        Callback.dispose(Nat, List<&2, String>, render)
        Callback.dispose(Unit, Unit, invalidate)
        Callback.dispose(Unit,List<&2,Component.Component>,children)
        Callback.dispose(T.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)

# Apply a configuration change while retaining the affine component owner.
def updatedOwner(pair: Owner & Component.Component & Handle, change: Handle -> IO(Unit)) -> IO(Owner):
  match pair:
    case (owner, _, handle):
      do IO<Owner>:
        change(handle)
        return owner
def updateOwner(owner: Owner, change: Handle -> IO(Unit)) -> IO(Owner): updatedOwner(borrow(owner), change)
