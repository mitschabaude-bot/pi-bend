import Base
import ../../runtime/src/ref.bend as Ref
import ./tui.bend as T
import ../../runtime/src/callback.bend as C

# IDs belong to a renderer: allocate once per component and do not reuse an ID
# while a layout, focus or mouse capture can still refer to it. Callback handles
# are borrowed; the owner retires components before disposing their callbacks.
type ComponentId is Data:
  ComponentId{value: Nat}
# These recursive interfaces share one receiver parameter; public aliases fix
# it to Component. This avoids untyped payloads or forward type declarations.
type Life<-Receiver: Data> is Type:
  Alive{component: Receiver,retire: Unit -> IO(Unit),references: Nat,nextToken: Nat}
  Closed{}
type Hold<-Receiver: Data> is Data:
  Retention{lifetime: Ref.Ref<Life<Receiver>>,token: Maybe<&2,Nat>}
type Target<-Receiver: Data> is Data:
  IdTarget{component: ComponentId,originX: T.Offset,originY: T.Offset,width: Nat,height: Nat}
  ComponentTarget{component: Receiver,originX: T.Offset,originY: T.Offset,width: Nat,height: Nat,retentions: List<&2,Hold<Receiver>>}
type DispatchResult<-Receiver: Data> is Data:
  TuiMouseDispatchResult{target: Target<Receiver>,focusTarget: Maybe<&2,ComponentId>,capture: Bool,focus: Bool,render: Maybe<&2,Bool>}
type Response<-Receiver: Data> is Data:
  LocalResult{result: T.TuiMouseEventResult}
  DispatchedResult{result: DispatchResult<Receiver>}
type Component is Data:
  Component{id: ComponentId,render: C.Callback<Nat,List<&2,String>>,handleInput: Maybe<&2,C.Callback<String,Unit>>,handleMouse: Maybe<&2,C.Callback<T.TuiMouseEvent,Maybe<&2,Response<Component>>>>,invalidate: C.Callback<Unit,Unit>,setFocused: Maybe<&2,C.Callback<Bool,Unit>>,wantsKeyRelease: Bool}
  Group{component: Component,children: C.Callback<Unit,List<&2,Component>>}
  Managed{component: Component,lifetime: Ref.Ref<Life<Component>>}
type Owner is Type:
  Owner{component: Component,retire: Unit -> IO(Unit)}
def TuiMouseDispatchTarget() -> Data: Target<Component>
def TuiMouseDispatchResult() -> Data: DispatchResult<Component>
def MouseResponse() -> Data: Response<Component>
def Lifetime() -> Type: Life<Component>
def Retention() -> Data: Hold<Component>

def withdrawn(lifetime: Lifetime()) -> Lifetime() & Maybe<&1,Owner>:
  match lifetime:
    case Alive{component,retire,1n,_}: (Closed{},Some{Owner{component,retire}})
    case Alive{component,retire,Succ{count},next}: (Alive{component,retire,count,next},None{})
    case value: (value,None{})
def retired(reference: Ref.Ref<Lifetime()>,owner: Maybe<&1,Owner>) -> IO(Unit):
  match owner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Owner{_,retire}}:
      do IO<Unit>:
        old : Lifetime() <- Ref.dispose(Lifetime(),reference)
        retire(Unit{})
def releaseLifetime(+reference: Ref.Ref<Lifetime()>) -> IO(Unit):
  do IO<Unit>:
    owner : Maybe<&1,Owner> <- Ref.modify(Lifetime(),Maybe<&1,Owner>,reference,withdrawn)
    retired(reference,owner)
def shared(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{+component,retire}:
      do IO<Owner>:
        +reference : Ref.Ref<Lifetime()> <- Ref.new(Lifetime(),Alive{component,retire,1n,1n})
        return Owner{Managed{component,reference},_ => releaseLifetime(reference)}
def acquired(lifetime: Lifetime()) -> Lifetime() & Maybe<&2,Nat>:
  match lifetime:
    case Alive{component,retire,count,+next}: (Alive{component,retire,count + 1n,next + 1n},Some{next})
    case Closed{}: (Closed{},None{})
def requireToken(token: Maybe<&2,Nat>) -> IO(Nat):
  match token:
    case Some{value}: IO.pure(Nat,value)
    case None{}: IO.die(Nat,1,"Component: retained after retirement")
def retain(retention: Retention()) -> IO(Retention()):
  match retention:
    case Retention{+reference,None{}}:
      do IO<Retention()>:
        result : Maybe<&2,Nat> <- Ref.modify(Lifetime(),Maybe<&2,Nat>,reference,acquired)
        token : Nat <- requireToken(result)
        return Retention{reference,Some{token}}
    case value: IO.pure(Retention(),value)
def retainAll(retentions: List<&2,Retention()>) -> IO(List<&2,Retention()>):
  match retentions:
    case Nil{}: IO.pure(List<&2,Retention()>,Nil{})
    case retention <> rest:
      do IO<List<&2,Retention()>>:
        held : Retention() <- retain(retention)
        following : List<&2,Retention()> <- retainAll(rest)
        return held <> following
def retainIndependent(retentions: List<&2,Retention()>) -> IO(List<&2,Retention()>):
  match retentions:
    case Nil{}: IO.pure(List<&2,Retention()>,Nil{})
    case Retention{reference,_} <> rest:
      do IO<List<&2,Retention()>>:
        held : Retention() <- retain(Retention{reference,None{}})
        following : List<&2,Retention()> <- retainIndependent(rest)
        return held <> following
def withRetentions(component: Component,retentions: List<&2,Retention()>) -> Component:
  match retentions:
    case Nil{}: component
    case Retention{reference,_} <> rest: Managed{withRetentions(component,rest),reference}
def borrow(owner: Owner) -> Owner & Component:
  match owner:
    case Owner{+component, retire}: (Owner{component, retire}, component)

def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_, retire}: retire(Unit{})

def same(left: ComponentId,right: ComponentId) -> Bool:
  match left right:
    case ComponentId{a} ComponentId{b}: Nat.is_eq(a,b)
def id(component: Component) -> ComponentId:
  match component:
    case Component{value,_,_,_,_,_,_}: value
    case Managed{component,_}: id(component)
    case Group{component,_}: id(component)
def withId(component: Component,identifier: ComponentId) -> Component:
  match component:
    case Component{_,render,input,mouse,invalidate,focused,release}: Component{identifier,render,input,mouse,invalidate,focused,release}
    case Managed{component,lifetime}: Managed{withId(component,identifier),lifetime}
    case Group{component,children}: Group{withId(component,identifier),children}
def render(component: Component,width: Nat) -> IO(List<&2,String>):
  match component:
    case Component{_,callback,_,_,_,_,_}: C.call(Nat,List<&2,String>,callback,width)
    case Managed{component,_}: render(component,width)
    case Group{component,_}: render(component,width)
def invalidate(component: Component) -> IO(Unit):
  match component:
    case Component{_,_,_,_,callback,_,_}: C.call(Unit,Unit,callback,Unit{})
    case Managed{component,_}: invalidate(component)
    case Group{component,_}: invalidate(component)
def handleInput(component: Component,data: String) -> IO(Unit):
  match component:
    case Component{_,_,Some{callback},_,_,_,_}: C.call(String,Unit,callback,data)
    case Managed{component,_}: handleInput(component,data)
    case Group{component,_}: handleInput(component,data)
    case _: IO.pure(Unit,Unit{})
def mouseHandler(component: Component) -> Maybe<&2,C.Callback<T.TuiMouseEvent,Maybe<&2,MouseResponse()>>>:
  match component:
    case Component{_,_,_,mouse,_,_,_}: mouse
    case Managed{component,_}: mouseHandler(component)
    case Group{component,_}: mouseHandler(component)
def isFocusable(component: Component) -> Bool:
  match component:
    case Component{_,_,_,_,_,Some{_},_}: True{}
    case Managed{component,_}: isFocusable(component)
    case Group{component,_}: isFocusable(component)
    case _: False{}
def setFocused(component: Component,focused: Bool) -> IO(Unit):
  match component:
    case Component{_,_,_,_,_,Some{callback},_}: C.call(Bool,Unit,callback,focused)
    case Managed{component,_}: setFocused(component,focused)
    case Group{component,_}: setFocused(component,focused)
    case _: IO.pure(Unit,Unit{})

def difference(+left: Nat,+right: Nat) -> T.Offset:
  Bool.pick(T.Offset,Nat.is_le(right,left),T.Forward{left - right},T.Backward{right - left})
def subtract(left: T.Offset,right: T.Offset) -> T.Offset:
  match left right:
    case T.Forward{a} T.Forward{b}: difference(a,b)
    case T.Backward{a} T.Backward{b}: difference(b,a)
    case T.Forward{a} T.Backward{b}: T.Forward{a + b}
    case T.Backward{a} T.Forward{b}: T.Backward{a + b}
def targetId(target: TuiMouseDispatchTarget()) -> ComponentId:
  match target:
    case IdTarget{component,_,_,_,_}: component
    case ComponentTarget{component,_,_,_,_,_}: id(component)
def targetBounds(target: TuiMouseDispatchTarget()) -> TuiMouseDispatchTarget():
  match target:
    case IdTarget{component,x,y,width,height}: IdTarget{component,x,y,width,height}
    case ComponentTarget{component,x,y,width,height,_}: IdTarget{id(component),x,y,width,height}
def retargetBounds(event: T.TuiMouseEvent,target: TuiMouseDispatchTarget()) -> T.TuiMouseEvent:
  match event target:
    case T.TuiMouseEvent{kind,button,_,_,+screenX,+screenY,_,_,shift,alt,ctrl,wheel,clicks} IdTarget{_,x,y,width,height}:
      T.TuiMouseEvent{kind,button,subtract(screenX,x),subtract(screenY,y),screenX,screenY,width,height,shift,alt,ctrl,wheel,clicks}
    case event _: event

def retargetMouseEvent(event: T.TuiMouseEvent,target: TuiMouseDispatchTarget()) -> T.TuiMouseEvent:
  retargetBounds(event,targetBounds(target))
def hasLifetime(retentions: List<&2,Retention()>,+reference: Ref.Ref<Lifetime()>) -> Bool:
  match retentions:
    case Nil{}: False{}
    case Retention{other,_} <> rest:
      Bool.pick(Unit -> Bool,Ref.same(Lifetime(),other,reference),_ => True{},_ => hasLifetime(rest,reference))(Unit{})
def lifetimeTarget(target: TuiMouseDispatchTarget(),+reference: Ref.Ref<Lifetime()>) -> TuiMouseDispatchTarget():
  match target:
    case ComponentTarget{component,x,y,width,height,+retentions}:
      ComponentTarget{component,x,y,width,height,Bool.pick(List<&2,Retention()>,hasLifetime(retentions,reference),retentions,Retention{reference,None{}} <> retentions)}
    case target: target
def componentRetentions(component: Component) -> List<&2,Retention()>:
  match component:
    case Managed{component,+reference}:
      +retentions = componentRetentions(component)
      Bool.pick(List<&2,Retention()>,hasLifetime(retentions,reference),retentions,Retention{reference,None{}} <> retentions)
    case Group{component,_}: componentRetentions(component)
    case _: Nil{}
def target(+component: Component,event: T.TuiMouseEvent) -> TuiMouseDispatchTarget():
  match event:
    case T.TuiMouseEvent{_,_,x,y,screenX,screenY,width,height,_,_,_,_,_}:
      ComponentTarget{component,subtract(screenX,x),subtract(screenY,y),width,height,componentRetentions(component)}
def lifetimeResult(result: Maybe<&2,TuiMouseDispatchResult()>,reference: Ref.Ref<Lifetime()>) -> Maybe<&2,TuiMouseDispatchResult()>:
  match result:
    case Some{TuiMouseDispatchResult{target,focusTarget,capture,focus,render}}:
      Some{TuiMouseDispatchResult{lifetimeTarget(target,reference),focusTarget,capture,focus,render}}
    case None{}: None{}
def retainTarget(target: TuiMouseDispatchTarget()) -> IO(TuiMouseDispatchTarget()):
  match target:
    case ComponentTarget{component,x,y,width,height,retentions}:
      do IO<TuiMouseDispatchTarget()>:
        held : List<&2,Retention()> <- retainAll(retentions)
        return ComponentTarget{component,x,y,width,height,held}
    case target: IO.pure(TuiMouseDispatchTarget(),target)
def targetRetentions(target: TuiMouseDispatchTarget()) -> List<&2,Retention()>:
  match target:
    case ComponentTarget{_,_,_,_,_,retentions}: retentions
    case _: Nil{}
def extraRetentions(incoming: List<&2,Retention()>,+held: List<&2,Retention()>) -> List<&2,Retention()>:
  match incoming:
    case Nil{}: Nil{}
    case Retention{+reference,token} <> +rest:
      Bool.pick(Unit -> List<&2,Retention()>,hasLifetime(held,reference),_ => extraRetentions(rest,held),_ => Retention{reference,token} <> extraRetentions(rest,held))(Unit{})
def inheritTarget(target: TuiMouseDispatchTarget(),prior: TuiMouseDispatchTarget()) -> TuiMouseDispatchTarget():
  match target:
    case ComponentTarget{component,x,y,width,height,retentions}:
      +held = targetRetentions(prior)
      ComponentTarget{component,x,y,width,height,List.append(&2,Retention(),held,extraRetentions(retentions,held))}
    case target: target
def inheritResult(result: Maybe<&2,TuiMouseDispatchResult()>,prior: TuiMouseDispatchTarget()) -> Maybe<&2,TuiMouseDispatchResult()>:
  match result:
    case Some{TuiMouseDispatchResult{target,focusTarget,capture,focus,render}}:
      Some{TuiMouseDispatchResult{inheritTarget(target,prior),focusTarget,capture,focus,render}}
    case None{}: None{}
def targetComponent(target: TuiMouseDispatchTarget()) -> Maybe<&2,Component>:
  match target:
    case ComponentTarget{component,_,_,_,_,retentions}: Some{withRetentions(component,retentions)}
    case _: None{}
def sameRetention(left: Retention(),right: Retention()) -> Bool:
  match left right:
    case Retention{left,Some{a}} Retention{right,Some{b}}: Ref.same(Lifetime(),left,right) && Nat.is_eq(a,b)
    case _ _: False{}
def includesRetention(retentions: List<&2,Retention()>,+wanted: Retention()) -> Bool:
  match retentions:
    case Nil{}: False{}
    case retention <> rest:
      Bool.pick(Unit -> Bool,sameRetention(retention,wanted),_ => True{},_ => includesRetention(rest,wanted))(Unit{})
def releaseRetentions(retentions: List<&2,Retention()>,+keeping: List<&2,Retention()>) -> IO(Unit):
  match retentions:
    case Nil{}: IO.pure(Unit,Unit{})
    case Retention{_,None{}} <> rest: releaseRetentions(rest,keeping)
    case Retention{+reference,Some{+token}} <> rest:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),includesRetention(keeping,Retention{reference,Some{token}}),_ => IO.pure(Unit,Unit{}),_ => releaseLifetime(reference))(Unit{})
        releaseRetentions(rest,keeping)
def releaseTarget(target: TuiMouseDispatchTarget(),keeping: Maybe<&2,TuiMouseDispatchTarget()>) -> IO(Unit):
  releaseRetentions(targetRetentions(target),Maybe.default(&2,List<&2,Retention()>,Maybe.map(&2,TuiMouseDispatchTarget(),List<&2,Retention()>,targetRetentions,keeping),Nil{}))
def dispatched(+component: Component,event: T.TuiMouseEvent,response: Maybe<&2,MouseResponse()>) -> Maybe<&2,TuiMouseDispatchResult()>:
  match response:
    case None{}: None{}
    case Some{DispatchedResult{result}}: Some{result}
    case Some{LocalResult{T.TuiMouseEventResult{handled,+capture,+focus,wantsRender}}}:
      Bool.pick(Maybe<&2,TuiMouseDispatchResult()>,handled || capture || focus,
        Some{TuiMouseDispatchResult{target(component,event),Bool.pick(Maybe<&2,ComponentId>,focus,Some{id(component)},None{}),capture,focus,wantsRender}},None{})
def dispatchMouseEvent(+component: Component,+event: T.TuiMouseEvent) -> IO(Maybe<&2,TuiMouseDispatchResult()>):
  match component:
    case Component{identifier,_,_,Some{callback},_,_,_}:
      do IO<Maybe<&2,TuiMouseDispatchResult()>>:
        response : Maybe<&2,MouseResponse()> <- C.call(T.TuiMouseEvent,Maybe<&2,MouseResponse()>,callback,event)
        return dispatched(component,event,response)
    case Managed{component,+reference}:
      do IO<Maybe<&2,TuiMouseDispatchResult()>>:
        result : Maybe<&2,TuiMouseDispatchResult()> <- dispatchMouseEvent(component,event)
        return lifetimeResult(result,reference)
    case Group{component,_}: dispatchMouseEvent(component,event)
    case _: IO.pure(Maybe<&2,TuiMouseDispatchResult()>,None{})

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
def routeMouse(children: List<&2,ChildLayout>,+event: T.TuiMouseEvent,+y: T.Offset,+start: Nat) -> IO(Maybe<&2,TuiMouseDispatchResult()>):
  match children:
    case Nil{}: IO.pure(Maybe<&2,TuiMouseDispatchResult()>,None{})
    case ChildLayout{child,+height} <> rest:
      Bool.pick(Unit -> IO(Maybe<&2,TuiMouseDispatchResult()>),within(y,start,height),
        _ => dispatchMouseEvent(child,childEvent(event,start,height)),
        _ => routeMouse(rest,event,y,start + height))(Unit{})
def delegateFocus(self: ComponentId,delegatesInput: Bool,result: Maybe<&2,TuiMouseDispatchResult()>) -> Maybe<&2,TuiMouseDispatchResult()>:
  match result:
    case Some{TuiMouseDispatchResult{hitTarget,focusTarget,capture,+focus,wantsRender}}:
      Some{TuiMouseDispatchResult{hitTarget,Bool.pick(Maybe<&2,ComponentId>,focus && delegatesInput,Some{self},focusTarget),capture,focus,wantsRender}}
    case None{}: None{}
def handleMouse(container: Container,self: ComponentId,delegatesInput: Bool,+event: T.TuiMouseEvent) -> IO(Maybe<&2,TuiMouseDispatchResult()>):
  match event:
    case T.TuiMouseEvent{_,_,_,+y,_,_,width,height,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Maybe<&2,TuiMouseDispatchResult()>),within(y,0n,height),
        _ =>
          do IO<Maybe<&2,TuiMouseDispatchResult()>>:
            children : List<&2,ChildLayout> <- mouseChildren(container,width)
            result : Maybe<&2,TuiMouseDispatchResult()> <- routeMouse(children,event,y,0n)
            return delegateFocus(self,delegatesInput,result),
        _ => IO.pure(Maybe<&2,TuiMouseDispatchResult()>,None{}))(Unit{})

# Groups describe current ownership topology, independently of the last
# displayed mouse layout. Lookups inspect direct roots before descendants.
def direct(components: List<&2,Component>, +wanted: ComponentId) -> Maybe<&2,Component>:
  match components:
    case Nil{}: None{}
    case +component <> rest:
      Bool.pick(Unit -> Maybe<&2,Component>,same(id(component),wanted),_ => Some{component},_ => direct(rest,wanted))(Unit{})
def managedChildren(children: List<&2,Component>,+reference: Ref.Ref<Lifetime()>) -> List<&2,Component>:
  match children:
    case Nil{}: Nil{}
    case child <> rest: Managed{child,reference} <> managedChildren(rest,reference)
def children(component: Component) -> IO(List<&2,Component>):
  match component:
    case Group{_,callback}: C.call(Unit,List<&2,Component>,callback,Unit{})
    case Managed{component,+reference}:
      do IO<List<&2,Component>>:
        nested : List<&2,Component> <- children(component)
        return managedChildren(nested,reference)
    case _: IO.pure(List<&2,Component>,Nil{})
def continueLookup(found: Maybe<&2,Component>, next: Unit -> IO(Maybe<&2,Component>)) -> IO(Maybe<&2,Component>):
  match found:
    case Some{component}: IO.pure(Maybe<&2,Component>,Some{component})
    case None{}: next(Unit{})
# Runtime child callbacks hide the finite mounted tree from the structural
# termination checker. Groups must expose an acyclic ownership tree.
@unsafe def lookupPending(pending: List<&2,Component>, +wanted: ComponentId) -> IO(Maybe<&2,Component>):
  match pending:
    case Nil{}: IO.pure(Maybe<&2,Component>,None{})
    case Component{_,_,_,_,_,_,_} <> rest: lookupPending(rest,wanted)
    case +component <> rest:
      do IO<Maybe<&2,Component>>:
        +nested : List<&2,Component> <- children(component)
        continueLookup(direct(nested,wanted),_ => lookupPending(List.append(&2,Component,nested,rest),wanted))
def lookup(+roots: List<&2,Component>, +wanted: ComponentId) -> IO(Maybe<&2,Component>):
  continueLookup(direct(roots,wanted),_ => lookupPending(roots,wanted))
