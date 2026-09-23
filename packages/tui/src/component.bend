import Base
import ./tui.bend as T
import ../../runtime/src/callback.bend as C

# IDs belong to a renderer: allocate once per component and do not reuse an ID
# while a layout, focus or mouse capture can still refer to it. Callback handles
# are borrowed; the owner retires components before disposing their callbacks.
type ComponentId is Data:
  ComponentId{value: Nat}
type TuiMouseDispatchTarget is Data:
  TuiMouseDispatchTarget{component: ComponentId,originX: T.Offset,originY: T.Offset,width: Nat,height: Nat}
type TuiMouseDispatchResult is Data:
  TuiMouseDispatchResult{target: TuiMouseDispatchTarget,focusTarget: Maybe<&2,ComponentId>,capture: Bool,focus: Bool,render: Maybe<&2,Bool>}
type MouseResponse is Data:
  LocalResult{result: T.TuiMouseEventResult}
  DispatchedResult{result: TuiMouseDispatchResult}
type Component is Data:
  Component{id: ComponentId,render: C.Callback<Nat,List<&2,String>>,handleInput: Maybe<&2,C.Callback<String,Unit>>,handleMouse: Maybe<&2,C.Callback<T.TuiMouseEvent,Maybe<&2,MouseResponse>>>,invalidate: C.Callback<Unit,Unit>,setFocused: Maybe<&2,C.Callback<Bool,Unit>>,wantsKeyRelease: Bool}

def same(left: ComponentId,right: ComponentId) -> Bool:
  match left right:
    case ComponentId{a} ComponentId{b}: Nat.is_eq(a,b)
def id(component: Component) -> ComponentId:
  match component:
    case Component{value,_,_,_,_,_,_}: value
def render(component: Component,width: Nat) -> IO(List<&2,String>):
  match component:
    case Component{_,callback,_,_,_,_,_}: C.call(Nat,List<&2,String>,callback,width)
def invalidate(component: Component) -> IO(Unit):
  match component:
    case Component{_,_,_,_,callback,_,_}: C.call(Unit,Unit,callback,Unit{})
def handleInput(component: Component,data: String) -> IO(Unit):
  match component:
    case Component{_,_,Some{callback},_,_,_,_}: C.call(String,Unit,callback,data)
    case _: IO.pure(Unit,Unit{})
def isFocusable(component: Component) -> Bool:
  match component:
    case Component{_,_,_,_,_,Some{_},_}: True{}
    case _: False{}
def setFocused(component: Component,focused: Bool) -> IO(Unit):
  match component:
    case Component{_,_,_,_,_,Some{callback},_}: C.call(Bool,Unit,callback,focused)
    case _: IO.pure(Unit,Unit{})

def difference(+left: Nat,+right: Nat) -> T.Offset:
  Bool.pick(T.Offset,Nat.is_le(right,left),T.Forward{left - right},T.Backward{right - left})
def subtract(left: T.Offset,right: T.Offset) -> T.Offset:
  match left right:
    case T.Forward{a} T.Forward{b}: difference(a,b)
    case T.Backward{a} T.Backward{b}: difference(b,a)
    case T.Forward{a} T.Backward{b}: T.Forward{a + b}
    case T.Backward{a} T.Forward{b}: T.Backward{a + b}
def target(component: ComponentId,event: T.TuiMouseEvent) -> TuiMouseDispatchTarget:
  match event:
    case T.TuiMouseEvent{_,_,x,y,screenX,screenY,width,height,_,_,_,_,_}:
      TuiMouseDispatchTarget{component,subtract(screenX,x),subtract(screenY,y),width,height}
def retargetMouseEvent(event: T.TuiMouseEvent,target: TuiMouseDispatchTarget) -> T.TuiMouseEvent:
  match event target:
    case T.TuiMouseEvent{kind,button,_,_,+screenX,+screenY,_,_,shift,alt,ctrl,wheel,clicks} TuiMouseDispatchTarget{_,x,y,width,height}:
      T.TuiMouseEvent{kind,button,subtract(screenX,x),subtract(screenY,y),screenX,screenY,width,height,shift,alt,ctrl,wheel,clicks}
def dispatched(+component: ComponentId,event: T.TuiMouseEvent,response: Maybe<&2,MouseResponse>) -> Maybe<&2,TuiMouseDispatchResult>:
  match response:
    case None{}: None{}
    case Some{DispatchedResult{result}}: Some{result}
    case Some{LocalResult{T.TuiMouseEventResult{handled,+capture,+focus,wantsRender}}}:
      Bool.pick(Maybe<&2,TuiMouseDispatchResult>,handled || capture || focus,
        Some{TuiMouseDispatchResult{target(component,event),Bool.pick(Maybe<&2,ComponentId>,focus,Some{component},None{}),capture,focus,wantsRender}},None{})
def dispatchMouseEvent(component: Component,+event: T.TuiMouseEvent) -> IO(Maybe<&2,TuiMouseDispatchResult>):
  match component:
    case Component{identifier,_,_,Some{callback},_,_,_}:
      do IO<Maybe<&2,TuiMouseDispatchResult>>:
        response : Maybe<&2,MouseResponse> <- C.call(T.TuiMouseEvent,Maybe<&2,MouseResponse>,callback,event)
        return dispatched(identifier,event,response)
    case _: IO.pure(Maybe<&2,TuiMouseDispatchResult>,None{})

type ChildLayout is Data:
  ChildLayout{component: Component,height: Nat}
type MouseLayout is Data:
  MouseLayout{width: Nat,children: List<&2,ChildLayout>}
type Container is Data:
  Container{children: List<&2,Component>,mouseLayout: Maybe<&2,MouseLayout>}

def new() -> Container: Container{Nil{},None{}}
def addChild(container: Container,component: Component) -> Container:
  match container:
    case Container{children,layout}: Container{List.append(&2,Component,children,component <> Nil{}),layout}
def removeFirst(children: List<&2,Component>,+removed: ComponentId) -> List<&2,Component>:
  match children:
    case Nil{}: Nil{}
    case +child <> +rest:
      Bool.pick(Unit -> List<&2,Component>,same(id(child),removed),_ => rest,_ => child <> removeFirst(rest,removed))(Unit{})
def removeChild(container: Container,removed: ComponentId) -> Container:
  match container:
    case Container{children,layout}: Container{removeFirst(children,removed),layout}
def clear(container: Container) -> Container:
  match container:
    case Container{_,layout}: Container{Nil{},layout}
def invalidateChildren(children: List<&2,Component>) -> IO(Unit):
  match children:
    case Nil{}: IO.pure(Unit,Unit{})
    case child <> rest:
      do IO<Unit>:
        invalidate(child)
        invalidateChildren(rest)
def invalidateContainer(container: Container) -> IO(Unit):
  match container:
    case Container{children,_}: invalidateChildren(children)

# Mouse layout describes the last displayed frame, even if children have since
# changed. This preserves upstream hit testing until the next render. A width
# mismatch measures current children without replacing that displayed layout.
def renderChildren(children: List<&2,Component>,+width: Nat,reversedLines: List<&2,String>,reversedLayout: List<&2,ChildLayout>) -> IO(List<&2,String> & MouseLayout):
  match children:
    case Nil{}: IO.pure(List<&2,String> & MouseLayout,(List.reverse(&2,String,reversedLines),MouseLayout{width,List.reverse(&2,ChildLayout,reversedLayout)}))
    case +child <> rest:
      do IO<List<&2,String> & MouseLayout>:
        +lines : List<&2,String> <- render(child,width)
        renderChildren(rest,width,List.append(&2,String,List.reverse(&2,String,lines),reversedLines),ChildLayout{child,List.length(&2,String,lines)} <> reversedLayout)
def rendered(children: List<&2,Component>,result: List<&2,String> & MouseLayout) -> Container & List<&2,String>:
  match result:
    case Tuple{lines,layout}: (Container{children,Some{layout}},lines)
def renderContainer(container: Container,width: Nat) -> IO(Container & List<&2,String>):
  match container:
    case Container{+children,_}:
      do IO<Container & List<&2,String>>:
        result : List<&2,String> & MouseLayout <- renderChildren(children,width,Nil{},Nil{})
        return rendered(children,result)
def measure(children: List<&2,Component>,+width: Nat,reversed: List<&2,ChildLayout>) -> IO(List<&2,ChildLayout>):
  match children:
    case Nil{}: IO.pure(List<&2,ChildLayout>,List.reverse(&2,ChildLayout,reversed))
    case +child <> rest:
      do IO<List<&2,ChildLayout>>:
        lines : List<&2,String> <- render(child,width)
        measure(rest,width,ChildLayout{child,List.length(&2,String,lines)} <> reversed)
def mouseChildren(container: Container,+width: Nat) -> IO(List<&2,ChildLayout>):
  match container:
    case Container{children,Some{MouseLayout{cachedWidth,cached}}}:
      Bool.pick(Unit -> IO(List<&2,ChildLayout>),Nat.is_eq(width,cachedWidth),_ => IO.pure(List<&2,ChildLayout>,cached),_ => measure(children,width,Nil{}))(Unit{})
    case Container{children,None{}}: measure(children,width,Nil{})
def childEvent(event: T.TuiMouseEvent,start: Nat,height: Nat) -> T.TuiMouseEvent:
  match event:
    case T.TuiMouseEvent{kind,button,x,y,sx,sy,width,_,shift,alt,ctrl,wheel,clicks}:
      T.TuiMouseEvent{kind,button,x,subtract(y,T.Forward{start}),sx,sy,width,height,shift,alt,ctrl,wheel,clicks}
def within(y: T.Offset,+start: Nat,height: Nat) -> Bool:
  match y:
    case T.Forward{+row}: Nat.is_le(start,row) && Nat.is_lt(row - start,height)
    case T.Backward{value}: Nat.is_eq(value,0n) && Nat.is_eq(start,0n) && Nat.is_lt(0n,height)
def routeMouse(children: List<&2,ChildLayout>,+event: T.TuiMouseEvent,+y: T.Offset,+start: Nat) -> IO(Maybe<&2,TuiMouseDispatchResult>):
  match children:
    case Nil{}: IO.pure(Maybe<&2,TuiMouseDispatchResult>,None{})
    case ChildLayout{child,+height} <> rest:
      Bool.pick(Unit -> IO(Maybe<&2,TuiMouseDispatchResult>),within(y,start,height),
        _ => dispatchMouseEvent(child,childEvent(event,start,height)),
        _ => routeMouse(rest,event,y,start + height))(Unit{})
def delegateFocus(self: ComponentId,delegatesInput: Bool,result: Maybe<&2,TuiMouseDispatchResult>) -> Maybe<&2,TuiMouseDispatchResult>:
  match result:
    case Some{TuiMouseDispatchResult{hitTarget,focusTarget,capture,+focus,wantsRender}}:
      Some{TuiMouseDispatchResult{hitTarget,Bool.pick(Maybe<&2,ComponentId>,focus && delegatesInput,Some{self},focusTarget),capture,focus,wantsRender}}
    case None{}: None{}
def handleMouse(container: Container,self: ComponentId,delegatesInput: Bool,+event: T.TuiMouseEvent) -> IO(Maybe<&2,TuiMouseDispatchResult>):
  match event:
    case T.TuiMouseEvent{_,_,_,+y,_,_,width,height,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Maybe<&2,TuiMouseDispatchResult>),within(y,0n,height),
        _ =>
          do IO<Maybe<&2,TuiMouseDispatchResult>>:
            children : List<&2,ChildLayout> <- mouseChildren(container,width)
            result : Maybe<&2,TuiMouseDispatchResult> <- routeMouse(children,event,y,0n)
            return delegateFocus(self,delegatesInput,result),
        _ => IO.pure(Maybe<&2,TuiMouseDispatchResult>,None{}))(Unit{})
