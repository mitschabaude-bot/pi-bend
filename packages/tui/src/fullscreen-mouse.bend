import Base
import ./tui.bend as T
import ./tui-base.bend as BaseTui
import ./component.bend as C
import ./layout.bend as L
import ./overlays.bend as O

type Raw is Data: Raw{button: Nat,x: Nat,y: Nat,release: Bool}
type Final is Data: Final{value: Nat,release: Bool}
type Press is Data: Press{target: C.TuiMouseDispatchTarget,x: Nat,y: Nat,moved: Bool}
type Click is Data: Click{component: C.ComponentId,x: Nat,y: Nat,time: Nat,count: Nat}
type State is Data: State{press: Maybe<&2,Press>,capture: Maybe<&2,C.TuiMouseDispatchTarget>,lastClick: Maybe<&2,Click>}
type Outcome is Data: Outcome{state: State,tui: BaseTui.TuiBase,handled: Bool,render: Bool,error: Maybe<&2,BaseTui.Error>}
def initial() -> State: State{None{},None{},None{}}

def digit(char: Char) -> Maybe<&2,Nat>:
  +code = Char.to_u32(char)
  Bool.pick(Maybe<&2,Nat>,U32.is_ge(code,48) && U32.is_le(code,57),Some{U32.to_nat(U32.sub(code,48))},None{})
def decimal(text: String,+value: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Some{value}
    case SCon{char,rest}: Maybe.bind(&2,Nat,Nat,digit(char),number => decimal(rest,value * 10n + number))
def final(text: String,+value: Nat) -> Maybe<&2,Final>:
  match text:
    case SCon{'M',SNil{}}: Some{Final{value,False{}}}
    case SCon{'m',SNil{}}: Some{Final{value,True{}}}
    case SCon{char,rest}: Maybe.bind(&2,Nat,Final,digit(char),number => final(rest,value * 10n + number))
    case _: None{}
def parsed(button: Maybe<&2,Nat>,x: Maybe<&2,Nat>,y: Maybe<&2,Final>) -> Maybe<&2,Raw>:
  match button x y:
    case Some{button} Some{+x} Some{Final{+y,release}}:
      Bool.pick(Maybe<&2,Raw>,Nat.is_lt(0n,x) && Nat.is_lt(0n,y),Some{Raw{button,x - 1n,y - 1n,release}},None{})
    case _ _ _: None{}
def fields(parts: List<&2,String>) -> Maybe<&2,Raw>:
  match parts:
    case SCon{b,bs} <> SCon{x,xs} <> SCon{y,ys} <> Nil{}:
      parsed(decimal(SCon{b,bs},0n),decimal(SCon{x,xs},0n),final(SCon{y,ys},0n))
    case _: None{}
def parse(data: String) -> Maybe<&2,Raw>:
  match data:
    case SCon{'\u{1b}',SCon{'[',SCon{'<',rest}}}: fields(String.split(rest,';'))
    case _: None{}
def bit(value: Nat,mask: Nat) -> Bool: Nat.is_eq((value / mask) % 2n,1n)
def decodeButton(value: Nat) -> T.TuiMouseButton:
  match value:
    case 0n: T.MouseLeft{}
    case 1n: T.MouseMiddle{}
    case 2n: T.MouseRight{}
    case _: T.NoButton{}
def button(value: Nat) -> T.TuiMouseButton: decodeButton(value % 4n)
def kind(release: Bool,motion: Bool,button: T.TuiMouseButton) -> T.TuiMouseEventType:
  match release motion button:
    case True{} _ _: T.MouseRelease{}
    case _ True{} T.NoButton{}: T.MouseMove{}
    case _ True{} _: T.MouseDrag{}
    case _ _ _: T.MousePress{}
def event(raw: Raw,width: Nat,height: Nat,+wheel: Maybe<&2,T.Offset>) -> T.TuiMouseEvent:
  match raw:
    case Raw{+code,+x,+y,release}:
      T.TuiMouseEvent{Bool.pick(T.TuiMouseEventType,Maybe.is_none(&2,T.Offset,wheel),kind(release,bit(code,32n),button(code)),T.MouseWheel{}),Bool.pick(T.TuiMouseButton,Maybe.is_none(&2,T.Offset,wheel),button(code),T.NoButton{}),T.Forward{x},T.Forward{y},T.Forward{x},T.Forward{y},width,height,bit(code,4n),bit(code,8n),bit(code,16n),wheel,None{}}
def wheel(raw: Raw) -> Maybe<&2,T.Offset>:
  match raw:
    case Raw{+code,_,_,_}:
      +lines = Bool.pick(Nat,bit(code,8n),5n,1n)
      Bool.pick(Maybe<&2,T.Offset>,bit(code,64n) && Nat.is_lt(code % 4n,2n),Some{Bool.pick(T.Offset,Nat.is_eq(code % 4n,0n),T.Backward{lines},T.Forward{lines})},None{})

def dispatchRegistered(value: Maybe<&2,C.Component>,event: T.TuiMouseEvent,target: C.TuiMouseDispatchTarget) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match value:
    case None{}: IO.pure(Maybe<&2,C.TuiMouseDispatchResult>,None{})
    case Some{component}: C.dispatchMouseEvent(component,C.retargetMouseEvent(event,target))
def dispatchTarget(registry: List<&2,C.Component>,event: T.TuiMouseEvent,+target: C.TuiMouseDispatchTarget) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match target:
    case C.TuiMouseDispatchTarget{id,_,_,_,_}:
      dispatchRegistered(BaseTui.registered(registry,id),event,target)
def dispatchNext(result: Maybe<&2,C.TuiMouseDispatchResult>,following: Unit -> IO(Maybe<&2,C.TuiMouseDispatchResult>)) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match result: case Some{value}: IO.pure(Maybe<&2,C.TuiMouseDispatchResult>,Some{value}) case None{}: following(Unit{})
@unsafe def dispatchBoxes(boxes: List<&2,L.LayoutBox>,+registry: List<&2,C.Component>,+event: T.TuiMouseEvent,+visited: List<&2,C.ComponentId>) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match boxes:
    case Nil{}: IO.pure(Maybe<&2,C.TuiMouseDispatchResult>,None{})
    case L.LayoutBox{None{},_,_,_,_,_,_} <> rest: dispatchBoxes(rest,registry,event,visited)
    case L.LayoutBox{Some{+id},L.LayoutRect{x,y,width,height},_,_,_,_,_} <> +rest:
      Bool.pick(Unit -> IO(Maybe<&2,C.TuiMouseDispatchResult>),O.mounted(visited,id),
        _ => dispatchBoxes(rest,registry,event,visited),
        _ => do IO<Maybe<&2,C.TuiMouseDispatchResult>>:
          result : Maybe<&2,C.TuiMouseDispatchResult> <- dispatchTarget(registry,event,C.TuiMouseDispatchTarget{id,T.Forward{x},T.Forward{y},width,height})
          dispatchNext(result,_ => dispatchBoxes(rest,registry,event,id <> visited)))(Unit{})
def layoutHits(frame: Maybe<&2,L.LayoutFrame>,raw: Raw) -> List<&2,L.LayoutBox>:
  match frame raw: case Some{frame} Raw{_,x,y,_}: L.getLayoutBoxesAt(frame,x,y) case _ _: Nil{}
def afterOverlay(hit: BaseTui.MouseHit,frame: Maybe<&2,L.LayoutFrame>,raw: Raw,registry: List<&2,C.Component>,event: T.TuiMouseEvent) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match hit:
    case BaseTui.MouseHit{True{},result}: IO.pure(Maybe<&2,C.TuiMouseDispatchResult>,result)
    case BaseTui.MouseHit{False{},_}: dispatchBoxes(layoutHits(frame,raw),registry,event,Nil{})
def hit(tui: BaseTui.TuiBase,frame: Maybe<&2,L.LayoutFrame>,+raw: Raw,registry: List<&2,C.Component>,+event: T.TuiMouseEvent) -> IO(Maybe<&2,C.TuiMouseDispatchResult>):
  match tui:
    case BaseTui.TuiBase{_,_,_,displayed,_,_,_,_}:
      do IO<Maybe<&2,C.TuiMouseDispatchResult>>:
        overlay : BaseTui.MouseHit <- BaseTui.dispatchMouseToOverlay(displayed,event)
        afterOverlay(overlay,frame,raw,registry,event)

def focusTarget(target: C.TuiMouseDispatchTarget,value: Maybe<&2,C.ComponentId>) -> C.ComponentId:
  match target: case C.TuiMouseDispatchTarget{id,_,_,_,_}: Maybe.default(&2,C.ComponentId,value,id)
def defaultRender(kind: T.TuiMouseEventType,changed: Bool) -> Bool:
  match kind: case T.MousePress{}: True{} case T.MouseClick{}: True{} case T.MouseDrag{}: True{} case T.MouseWheel{}: True{} case _: changed
def appliedFocus(result: BaseTui.ResultOf(BaseTui.TuiBase),old: BaseTui.TuiBase,state: State,render: Bool) -> Outcome:
  match result: case Done{tui}: Outcome{state,tui,True{},render,None{}} case Fail{error}: Outcome{state,old,True{},False{},Some{error}}
def focused(tui: BaseTui.TuiBase,wanted: C.ComponentId) -> Bool:
  match tui:
    case BaseTui.TuiBase{_,O.State{_,Some{id},_,_,_},_,_,_,_,_,_}: C.same(id,wanted)
    case _: False{}
def capture(state: State,target: C.TuiMouseDispatchTarget,captures: Bool) -> State:
  match state: case State{press,old,last}: State{press,Bool.pick(Maybe<&2,C.TuiMouseDispatchTarget>,captures,Some{target},old),last}
def apply(+state: State,+tui: BaseTui.TuiBase,registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,event: T.TuiMouseEvent,result: Maybe<&2,C.TuiMouseDispatchResult>) -> IO(Outcome):
  match result event:
    case None{} _: IO.pure(Outcome,Outcome{state,tui,False{},False{},None{}})
    case Some{C.TuiMouseDispatchResult{+target,nextFocus,captures,+focus,render}} T.TuiMouseEvent{kind,_,_,_,_,_,_,_,_,_,_,_,_}:
      +wanted = focusTarget(target,nextFocus)
      +redraw = Maybe.default(&2,Bool,render,defaultRender(kind,focus && Bool.not(focused(tui,wanted))))
      +next = capture(state,target,captures)
      Bool.pick(Unit -> IO(Outcome),focus,
        _ => do IO<Outcome>:
          result : BaseTui.ResultOf(BaseTui.TuiBase) <- BaseTui.setFocus(tui,registry,mounted,Some{wanted})
          return appliedFocus(result,tui,next,redraw),
        _ => IO.pure(Outcome,Outcome{next,tui,True{},redraw,None{}}))(Unit{})
def pressed(+outcome: Outcome,raw: Raw,result: Maybe<&2,C.TuiMouseDispatchResult>) -> Outcome:
  match outcome raw result:
    case Outcome{State{_,capture,last},tui,handled,render,error} Raw{code,x,y,False{}} Some{C.TuiMouseDispatchResult{target,_,_,_,_}}:
      Bool.pick(Outcome,bit(code,32n),outcome,Outcome{State{Some{Press{target,x,y,False{}}},capture,last},tui,handled,render,error})
    case outcome _ _: outcome
def begin(+state: State,+tui: BaseTui.TuiBase,frame: Maybe<&2,L.LayoutFrame>,+registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,+raw: Raw,+event: T.TuiMouseEvent) -> IO(Outcome):
  do IO<Outcome>:
    +result : Maybe<&2,C.TuiMouseDispatchResult> <- hit(tui,frame,raw,registry,event)
    outcome : Outcome <- apply(state,tui,registry,mounted,event,result)
    return pressed(outcome,raw,result)
def gestureTarget(state: State) -> Maybe<&2,C.TuiMouseDispatchTarget>:
  match state:
    case State{_,Some{target},_}: Some{target}
    case State{Some{Press{target,_,_,_}},_,_}: Some{target}
    case _: None{}
def moved(state: State,raw: Raw) -> State:
  match state raw:
    case State{Some{Press{target,+x,+y,+old}},capture,last} Raw{_,nx,ny,_}:
      +changed = old || Bool.not(Nat.is_eq(x,nx) && Nat.is_eq(y,ny))
      State{Some{Press{target,x,y,changed}},capture,Bool.pick(Maybe<&2,Click>,changed,None{},last)}
    case state _: state
def shouldClick(state: State,raw: Raw) -> Bool:
  match state raw:
    case State{Some{Press{_,x,y,moved}},_,_} Raw{_,nx,ny,True{}}: Bool.not(moved) && Nat.is_eq(x,nx) && Nat.is_eq(y,ny)
    case _ _: False{}
def clickCount(last: Maybe<&2,Click>,target: C.TuiMouseDispatchTarget,raw: Raw,+now: Nat) -> Nat:
  match last target raw:
    case Some{Click{id,x,y,+time,count}} C.TuiMouseDispatchTarget{wanted,_,_,_,_} Raw{_,nx,ny,_}:
      Bool.pick(Nat,C.same(id,wanted) && Nat.is_eq(x,nx) && Nat.is_eq(y,ny) && Nat.is_le(time,now) && Nat.is_le(now - time,500n),count % 3n + 1n,1n)
    case _ _ _: 1n
def clickEvent(event: T.TuiMouseEvent,count: Nat) -> T.TuiMouseEvent:
  match event:
    case T.TuiMouseEvent{_,button,x,y,sx,sy,width,height,shift,alt,ctrl,_,_}:
      T.TuiMouseEvent{T.MouseClick{},button,x,y,sx,sy,width,height,shift,alt,ctrl,None{},Some{count}}
def clicking(state: State,target: C.TuiMouseDispatchTarget,raw: Raw,+now: Nat,+count: Nat) -> State:
  match state target raw:
    case State{press,capture,_} C.TuiMouseDispatchTarget{id,_,_,_,_} Raw{_,x,y,_}:
      State{press,capture,Some{Click{id,x,y,now,count}}}
def ended(outcome: Outcome,+release: Bool,priorRender: Bool) -> Outcome:
  match outcome:
    case Outcome{State{press,capture,last},tui,handled,render,error}:
      Outcome{State{Bool.pick(Maybe<&2,Press>,release,None{},press),Bool.pick(Maybe<&2,C.TuiMouseDispatchTarget>,release,None{},capture),last},tui,handled,render || priorRender,error}
def released(raw: Raw) -> Bool: match raw: case Raw{_,_,_,value}: value
def lastClick(state: State) -> Maybe<&2,Click>: match state: case State{_,_,last}: last
def releaseClick(outcome: Outcome,+registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,+raw: Raw,+event: T.TuiMouseEvent,+target: C.TuiMouseDispatchTarget) -> IO(Outcome):
  match outcome:
    case Outcome{+state,+tui,handled,+render,+error}:
      Bool.pick(Unit -> IO(Outcome),shouldClick(state,raw) && Maybe.is_none(&2,BaseTui.Error,error),
        _ => do IO<Outcome>:
          +now : Nat <- IO.now()
          +count : Nat = clickCount(lastClick(state),target,raw,now)
          +clicked : T.TuiMouseEvent = clickEvent(event,count)
          result : Maybe<&2,C.TuiMouseDispatchResult> <- dispatchTarget(registry,clicked,target)
          next : Outcome <- apply(clicking(state,target,raw,now,count),tui,registry,mounted,clicked,result)
          return ended(next,True{},render),
        _ => IO.pure(Outcome,ended(Outcome{state,tui,handled,render,error},released(raw),False{})))(Unit{})
def continueGesture(state: State,+tui: BaseTui.TuiBase,+registry: List<&2,C.Component>,+mounted: List<&2,C.ComponentId>,+raw: Raw,+event: T.TuiMouseEvent,+target: C.TuiMouseDispatchTarget) -> IO(Outcome):
  do IO<Outcome>:
    result : Maybe<&2,C.TuiMouseDispatchResult> <- dispatchTarget(registry,event,target)
    outcome : Outcome <- apply(moved(state,raw),tui,registry,mounted,event,result)
    releaseClick(outcome,registry,mounted,raw,event,target)
def route(target: Maybe<&2,C.TuiMouseDispatchTarget>,state: State,tui: BaseTui.TuiBase,frame: Maybe<&2,L.LayoutFrame>,registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,raw: Raw,event: T.TuiMouseEvent) -> IO(Outcome):
  match target:
    case Some{target}: continueGesture(state,tui,registry,mounted,raw,event,target)
    case None{}: begin(state,tui,frame,registry,mounted,raw,event)
def dispatch(+state: State,+tui: BaseTui.TuiBase,+frame: Maybe<&2,L.LayoutFrame>,+registry: List<&2,C.Component>,+mounted: List<&2,C.ComponentId>,+raw: Raw,width: Nat,height: Nat) -> IO(Outcome):
  +scroll = wheel(raw)
  +normalized = event(raw,width,height,scroll)
  Bool.pick(Unit -> IO(Outcome),Maybe.is_none(&2,T.Offset,scroll),
    _ => route(gestureTarget(state),state,tui,frame,registry,mounted,raw,normalized),
    _ => do IO<Outcome>:
      result : Maybe<&2,C.TuiMouseDispatchResult> <- hit(tui,frame,raw,registry,normalized)
      apply(state,tui,registry,mounted,normalized,result))(Unit{})
