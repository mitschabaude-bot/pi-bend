import Base
import ./component.bend as C
import ./keys.bend as Keys
import ./overlays.bend as O
import ./tui.bend as T
import ./layout-node.bend as N
import ./layout-tree.bend as Tree
import ./layout.bend as Layout
import ./components/scroll-view.bend as Scroll
import ../../runtime/src/stable-sort.bend as Sort

# Renderer-owned bindings borrow the component callbacks. Focus policy keeps
# only identities; displayed bounds belong to the frame that produced them.
type Overlay is Data: Overlay{handle: O.OverlayHandle,component: C.Component,geometry: T.OverlayGeometry}
type OverlayBounds is Data: OverlayBounds{handle: O.OverlayHandle,component: C.Component,target: C.TuiMouseDispatchTarget()}
type Frame is Data: Frame{lines: List<&2,String>,overlays: List<&2,OverlayBounds>}
# Raw keys and displayed output are published together after a successful draw.
type DisplayedFrame is Data: DisplayedFrame{source: List<&2,String>,frame: Frame}
type Error is Data:
  MissingOverlay{handle: O.OverlayHandle}
  ComponentMismatch{handle: O.OverlayHandle}
  InvalidLayout{cause: T.LayoutError}
  MissingFocusedComponent{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
type PaintedOverlay is Data: PaintedOverlay{bounds: OverlayBounds,lines: List<&2,String>,row: Nat,col: Nat,width: Nat}

def find(bindings: List<&2,Overlay>,+wanted: O.OverlayHandle) -> Maybe<&2,Overlay>:
  match bindings:
    case Nil{}: None{}
    case Overlay{+handle,component,geometry} <> rest:
      Bool.pick(Unit -> Maybe<&2,Overlay>,O.sameHandle(handle,wanted),_ => Some{Overlay{handle,component,geometry}},_ => find(rest,wanted))(Unit{})
def visible(entries: List<&2,O.Entry>,reversed: List<&2,O.Entry>) -> List<&2,O.Entry>:
  match entries:
    case Nil{}: List.reverse(&2,O.Entry,reversed)
    case +entry <> rest:
      +reversed = {reversed: List<&2,O.Entry>}
      visible(rest,Bool.pick(List<&2,O.Entry>,O.isVisible(entry),entry <> reversed,reversed))
def ordered(state: O.State) -> List<&2,O.Entry>:
  match state:
    case O.State{entries,_,_,_,_}: Sort.sort(~O.Entry,~(left => right => Nat.is_le(O.entryOrder(left),O.entryOrder(right))),visible(entries,Nil{}))
def prefix(lines: List<&2,String>,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match lines count:
    case Nil{} _: List.reverse(&2,String,reversed)
    case _ Zero{}: List.reverse(&2,String,reversed)
    case line <> rest Succ{left}: prefix(rest,left,line <> reversed)
def clipped(lines: List<&2,String>,height: Maybe<&2,Nat>) -> List<&2,String>:
  match height:
    case None{}: lines
    case Some{limit}: prefix(lines,limit,Nil{})
def positioned(handle: O.OverlayHandle,+component: C.Component,+lines: List<&2,String>,layout: Result<&2,&2,T.LayoutError,T.OverlayLayout>) -> ResultOf(PaintedOverlay):
  match layout:
    case Fail{error}: Fail{InvalidLayout{error}}
    case Done{T.OverlayLayout{+width,+row,+col,_}}:
      Done{PaintedOverlay{OverlayBounds{handle,component,C.IdTarget{C.id(component),T.Forward{col},T.Forward{row},width,List.length(&2,String,lines)}},lines,row,col,width}}
def layoutLines(handle: O.OverlayHandle,component: C.Component,geometry: T.OverlayGeometry,termWidth: Nat,termHeight: Nat,+lines: List<&2,String>) -> ResultOf(PaintedOverlay):
  positioned(handle,component,lines,T.resolveOverlayLayout(geometry,List.length(&2,String,lines),termWidth,termHeight))
def measured(handle: O.OverlayHandle,+component: C.Component,+geometry: T.OverlayGeometry,+termWidth: Nat,+termHeight: Nat,layout: Result<&2,&2,T.LayoutError,T.OverlayLayout>) -> IO(ResultOf(PaintedOverlay)):
  match layout:
    case Fail{error}: IO.pure(ResultOf(PaintedOverlay),Fail{InvalidLayout{error}})
    case Done{T.OverlayLayout{width,_,_,maximum}}:
      do IO<ResultOf(PaintedOverlay)>:
        raw : List<&2,String> <- C.render(component,width)
        return layoutLines(handle,component,geometry,termWidth,termHeight,clipped(raw,maximum))
def renderOverlay(+entry: O.Entry,binding: Maybe<&2,Overlay>,+termWidth: Nat,+termHeight: Nat) -> IO(ResultOf(PaintedOverlay)):
  match binding:
    case None{}: IO.pure(ResultOf(PaintedOverlay),Fail{MissingOverlay{O.entryHandle(entry)}})
    case Some{Overlay{+handle,+component,+geometry}}:
      Bool.pick(Unit -> IO(ResultOf(PaintedOverlay)),C.same(O.entryComponent(entry),C.id(component)),
        _ => measured(handle,component,geometry,termWidth,termHeight,T.resolveOverlayLayout(geometry,0n,termWidth,termHeight)),
        _ => IO.pure(ResultOf(PaintedOverlay),Fail{ComponentMismatch{handle}}))(Unit{})
def collected(result: ResultOf(PaintedOverlay),reversed: List<&2,PaintedOverlay>) -> ResultOf(List<&2,PaintedOverlay>):
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{value <> reversed}
def renderVisible(entries: List<&2,O.Entry>,+bindings: List<&2,Overlay>,+width: Nat,+height: Nat,result: ResultOf(List<&2,PaintedOverlay>)) -> IO(ResultOf(List<&2,PaintedOverlay>)):
  match entries result:
    case _ Fail{error}: IO.pure(ResultOf(List<&2,PaintedOverlay>),Fail{error})
    case Nil{} Done{reversed}: IO.pure(ResultOf(List<&2,PaintedOverlay>),Done{List.reverse(&2,PaintedOverlay,reversed)})
    case +entry <> rest Done{reversed}:
      do IO<ResultOf(List<&2,PaintedOverlay>)>:
        value : ResultOf(PaintedOverlay) <- renderOverlay(entry,find(bindings,O.entryHandle(entry)),width,height)
        renderVisible(rest,bindings,width,height,collected(value,reversed))
def minimumHeight(overlays: List<&2,PaintedOverlay>,minimum: Nat) -> Nat:
  match overlays:
    case Nil{}: minimum
    case PaintedOverlay{_,lines,row,_,_} <> rest: minimumHeight(rest,Nat.max(minimum,row + List.length(&2,String,lines)))
def blanks(count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: reversed
    case Succ{left}: blanks(left,"" <> reversed)
def paint(base: List<&2,String>,lines: List<&2,String>,skip: Nat,+col: Nat,+width: Nat,+termWidth: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match base lines skip:
    case Nil{} _ _: List.reverse(&2,String,reversed)
    case remaining Nil{} _: List.append(&2,String,List.reverse(&2,String,reversed),remaining)
    case line <> rest overlays Succ{left}: paint(rest,overlays,left,col,width,termWidth,line <> reversed)
    case line <> rest overlay <> more Zero{}: paint(rest,more,0n,col,width,termWidth,T.compositeTuiLine(line,overlay,col,width,termWidth) <> reversed)
def composite(overlays: List<&2,PaintedOverlay>,lines: List<&2,String>,+viewportStart: Nat,+termWidth: Nat,reversedBounds: List<&2,OverlayBounds>) -> Frame:
  match overlays:
    case Nil{}: Frame{lines,List.reverse(&2,OverlayBounds,reversedBounds)}
    case PaintedOverlay{bounds,overlayLines,row,col,width} <> rest:
      composite(rest,paint(lines,overlayLines,viewportStart + row,col,width,termWidth,Nil{}),viewportStart,termWidth,bounds <> reversedBounds)
def finish(+base: List<&2,String>,termWidth: Nat,+termHeight: Nat,result: ResultOf(List<&2,PaintedOverlay>)) -> ResultOf(Frame):
  match result:
    case Fail{error}: Fail{error}
    case Done{+overlays}:
      +length = List.length(&2,String,base)
      +workingHeight = Nat.max(termHeight,minimumHeight(overlays,length))
      Done{composite(overlays,List.append(&2,String,base,blanks(workingHeight - length,Nil{})),workingHeight - termHeight,termWidth,Nil{})}
def compositeOverlays(+state: O.State,bindings: List<&2,Overlay>,lines: List<&2,String>,+termWidth: Nat,+termHeight: Nat) -> IO(ResultOf(Frame)):
  match state:
    case O.State{Nil{},_,_,_,_}: IO.pure(ResultOf(Frame),Done{Frame{lines,Nil{}}})
    case _:
      do IO<ResultOf(Frame)>:
        overlays : ResultOf(List<&2,PaintedOverlay>) <- renderVisible(ordered(state),bindings,termWidth,termHeight,Done{Nil{}})
        return finish(lines,termWidth,termHeight,overlays)

# Hit testing uses the last displayed bounds and borrowed component, including
# when the live overlay list has changed but no replacement frame was drawn.
type MouseHit is Data: MouseHit{hit: Bool,result: Maybe<&2,C.TuiMouseDispatchResult()>}
def inside(position: T.Offset,origin: T.Offset,extent: Nat) -> Bool:
  match position origin:
    case T.Forward{+position} T.Forward{+origin}: Nat.is_ge(position,origin) && Nat.is_lt(position - origin,extent)
    case _ _: False{}
def containsBounds(bounds: C.TuiMouseDispatchTarget(),event: T.TuiMouseEvent) -> Bool:
  match bounds event:
    case C.IdTarget{_,x,y,width,height} T.TuiMouseEvent{_,_,_,_,screenX,screenY,_,_,_,_,_,_,_}:
      inside(screenX,x,width) && inside(screenY,y,height)
    case _ _: False{}
def contains(bounds: C.TuiMouseDispatchTarget(),event: T.TuiMouseEvent) -> Bool:
  containsBounds(C.targetBounds(bounds),event)
def mouseOwner(owner: C.ComponentId,result: Maybe<&2,C.TuiMouseDispatchResult()>) -> MouseHit:
  match result:
    case None{}: MouseHit{True{},None{}}
    case Some{C.TuiMouseDispatchResult{target,focusTarget,capture,+focus,wantsRender}}:
      MouseHit{True{},Some{C.TuiMouseDispatchResult{target,Bool.pick(Maybe<&2,C.ComponentId>,focus,Some{owner},focusTarget),capture,focus,wantsRender}}}
def dispatchTopmost(reversed: List<&2,OverlayBounds>,+event: T.TuiMouseEvent) -> IO(MouseHit):
  match reversed:
    case Nil{}: IO.pure(MouseHit,MouseHit{False{},None{}})
    case OverlayBounds{_,+component,+target} <> rest:
      Bool.pick(Unit -> IO(MouseHit),contains(target,event),
        _ => do IO<MouseHit>:
          result : Maybe<&2,C.TuiMouseDispatchResult()> <- C.dispatchMouseEvent(component,C.retargetMouseEvent(event,target))
          return mouseOwner(C.id(component),result),
        _ => dispatchTopmost(rest,event))(Unit{})
def dispatchMouseToOverlay(frame: Frame,event: T.TuiMouseEvent) -> IO(MouseHit):
  match frame:
    case Frame{_,bounds}: dispatchTopmost(List.reverse(&2,OverlayBounds,bounds),event)

# Scheduling is an immutable transition system. The owner executes effects
# outside state access, so input/render callbacks may safely request a frame.
# Timer IDs reject callbacks already queued when their timer was cancelled.
type RenderSchedule is Data:
  RenderSchedule{requested: Bool,immediate: Bool,timer: Maybe<&2,Nat>,nextTimer: Nat,lastRenderAt: Nat,stopped: Bool}
type RenderEvent is Data:
  RequestRender{force: Bool}
  RequestImmediate{}
  ScheduleRender{}
  ImmediateRender{}
  TimerFired{id: Nat}
  RenderNow{force: Bool}
  StopRendering{}
  StartRendering{}
type RenderEffect is Data:
  QueueSchedule{}
  QueueImmediate{}
  CancelTimer{id: Nat}
  StartTimer{id: Nat,delayMs: Nat}
  ResetRenderState{}
  DrawFrame{}
type Scheduled is Data: Scheduled{state: RenderSchedule,effects: List<&2,RenderEffect>}
def newRenderSchedule() -> RenderSchedule: RenderSchedule{False{},False{},None{},1n,0n,False{}}
def cancelTimer(timer: Maybe<&2,Nat>,following: List<&2,RenderEffect>) -> List<&2,RenderEffect>:
  match timer:
    case None{}: following
    case Some{id}: CancelTimer{id} <> following
def resetEffect(force: Bool,following: List<&2,RenderEffect>) -> List<&2,RenderEffect>:
  match force:
    case True{}: ResetRenderState{} <> following
    case False{}: following
def immediateSchedule(state: RenderSchedule,force: Bool) -> Scheduled:
  match state:
    case RenderSchedule{_,+immediate,timer,next,last,stopped}:
      Scheduled{RenderSchedule{True{},True{},None{},next,last,stopped},resetEffect(force,cancelTimer(timer,Bool.pick(List<&2,RenderEffect>,immediate,Nil{},QueueImmediate{} <> Nil{})))}
def requestSchedule(force: Bool,+state: RenderSchedule) -> Scheduled:
  match force state:
    case True{} _: immediateSchedule(state,True{})
    case False{} RenderSchedule{+requested,immediate,timer,next,last,stopped}:
      Scheduled{RenderSchedule{True{},immediate,timer,next,last,stopped},Bool.pick(List<&2,RenderEffect>,requested,Nil{},QueueSchedule{} <> Nil{})}
def deferSchedule(state: RenderSchedule,now: Nat) -> Scheduled:
  match state:
    case RenderSchedule{+requested,+immediate,+timer,+next,+last,+stopped}:
      active = requested && Bool.not(stopped) && Maybe.is_none(&2,Nat,timer)
      Bool.pick(Scheduled,active,
        Scheduled{RenderSchedule{requested,immediate,Some{next},Succ{next},last,stopped},StartTimer{next,16n - Nat.min(16n,Nat.max(now,last) - last)} <> Nil{}},
        Scheduled{RenderSchedule{requested,immediate,timer,next,last,stopped},Nil{}})
def drawImmediate(state: RenderSchedule,now: Nat) -> Scheduled:
  match state:
    case RenderSchedule{+requested,_,+timer,+next,+last,+stopped}:
      Bool.pick(Scheduled,requested && Bool.not(stopped),
        Scheduled{RenderSchedule{False{},False{},None{},next,now,stopped},cancelTimer(timer,DrawFrame{} <> Nil{})},
        Scheduled{RenderSchedule{requested,False{},timer,next,last,stopped},Nil{}})
def matchesTimer(timer: Maybe<&2,Nat>,expected: Nat) -> Bool:
  match timer:
    case None{}: False{}
    case Some{id}: Nat.is_eq(id,expected)
def firedSchedule(state: RenderSchedule,id: Nat,now: Nat) -> Scheduled:
  match state:
    case RenderSchedule{+requested,+immediate,+timer,+next,+last,+stopped}:
      Bool.pick(Scheduled,matchesTimer(timer,id),
        Bool.pick(Scheduled,requested && Bool.not(stopped),
          Scheduled{RenderSchedule{False{},immediate,None{},next,now,stopped},DrawFrame{} <> Nil{}},
          Scheduled{RenderSchedule{requested,immediate,None{},next,last,stopped},Nil{}}),
        Scheduled{RenderSchedule{requested,immediate,timer,next,last,stopped},Nil{}})
def schedule(event: RenderEvent,state: RenderSchedule,now: Nat) -> Scheduled:
  match event state:
    case RequestRender{force} state: requestSchedule(force,state)
    case RequestImmediate{} state: immediateSchedule(state,False{})
    case ScheduleRender{} state: deferSchedule(state,now)
    case ImmediateRender{} state: drawImmediate(state,now)
    case TimerFired{id} state: firedSchedule(state,id,now)
    case RenderNow{force} RenderSchedule{_,immediate,timer,next,_,stopped}:
      Scheduled{RenderSchedule{False{},immediate,None{},next,now,stopped},resetEffect(force,cancelTimer(timer,DrawFrame{} <> Nil{}))}
    case StopRendering{} RenderSchedule{requested,immediate,timer,next,last,_}:
      Scheduled{RenderSchedule{requested,immediate,None{},next,last,True{}},cancelTimer(timer,Nil{})}
    case StartRendering{} RenderSchedule{requested,immediate,timer,next,last,_}:
      requestSchedule(False{},RenderSchedule{requested,immediate,timer,next,last,False{}})

# One owner carries the root layout, focus policy, overlay bindings and the
# last displayed hit map. Preparing a frame does not mutate that displayed map;
# the owner installs it only after its terminal renderer accepts the frame.
type FocusBinding is Data: FocusBinding{component: C.Component,retentions: List<&2,C.Retention()>}
type TuiBase is Data:
  TuiBase{root: C.Container,focus: O.State,bindings: List<&2,Overlay>,displayed: DisplayedFrame,renderSchedule: RenderSchedule,showHardwareCursor: Bool,clearOnShrink: Bool,layoutRoot: Maybe<&2,N.LayoutNode>,focusedComponent: Maybe<&2,FocusBinding>}
def scheduledTui(tui: TuiBase,scheduled: Scheduled) -> TuiBase & List<&2,RenderEffect>:
  match tui scheduled:
    case TuiBase{root,focus,bindings,displayed,_,show,clear,layout,+heldFocus} Scheduled{next,effects}: (TuiBase{root,focus,bindings,displayed,next,show,clear,layout,heldFocus},effects)
# Applies a render event to the owner's schedule; the caller carries out the
# returned effects (upstream TUI.requestRender/scheduleRender/doRender).
def scheduleOf(tui: TuiBase) -> RenderSchedule:
  match tui:
    case TuiBase{_,_,_,_,current,_,_,_,+heldFocus}: current
def scheduleRender(+tui: TuiBase,event: RenderEvent,now: Nat) -> TuiBase & List<&2,RenderEffect>:
  scheduledTui(tui,schedule(event,scheduleOf(tui),now))
type PreparedFrame is Data:
  PreparedFrame{tui: TuiBase,frame: Frame,lines: List<&2,String>,cursor: Maybe<&2,T.CursorPosition>,layout: Maybe<&2,Layout.LayoutFrame>,source: List<&2,String>}
type PrimaryContent is Data: PrimaryContent{lines: List<&2,String>,top: Nat,rows: Nat,rect: Layout.LayoutRect,clip: Layout.LayoutRect}
@unsafe def primaryAt(boxes: List<&2,Layout.LayoutBox>,+wanted: C.ComponentId,+top: Nat,+rows: Nat) -> Maybe<&2,PrimaryContent>:
  match boxes:
    case Nil{}: None{}
    case Layout.LayoutBox{Some{component},rect,clip,children,Some{lines},_,_} <> rest:
      Bool.pick(Unit -> Maybe<&2,PrimaryContent>,C.same(component,wanted),
        _ => Some{PrimaryContent{lines,top,rows,rect,clip}},
        _ => primaryAt(List.append(&2,Layout.LayoutBox,children,rest),wanted,top,rows))(Unit{})
    case Layout.LayoutBox{_,_,_,children,_,_,_} <> rest:
      primaryAt(List.append(&2,Layout.LayoutBox,children,rest),wanted,top,rows)
def primaryFrom(layout: Maybe<&2,Layout.LayoutFrame>,view: Maybe<&2,N.Primary>) -> Maybe<&2,PrimaryContent>:
  match layout view:
    case Some{Layout.LayoutFrame{root,_,_,_}} Some{N.Primary{component,top,rows}}:
      primaryAt(root <> Nil{},component,top,rows)
    case _ _: None{}
def primaryContent(frame: PreparedFrame) -> Maybe<&2,PrimaryContent>:
  match frame:
    case PreparedFrame{TuiBase{_,_,_,_,_,_,_,Some{node},+heldFocus},_,_,_,layout,_}: primaryFrom(layout,N.primaryInfo(node))
    case _: None{}
type OverlayChange is Data:
  OverlayChange{tui: TuiBase,handle: O.OverlayHandle,focusChanges: List<&2,O.FocusChange>,hideCursor: Bool,render: Bool}
type ScrollChange is Data: ScrollChange{tui: TuiBase,unused: T.Offset,requestRender: Bool}
# Evaluate dimension-dependent visibility outside the pure owner, then apply
# the resulting snapshot before a render or input transition.
type Visibility is Data: Visibility{handle: O.OverlayHandle,shown: Bool}
def visibleState(values: List<&2,Visibility>,state: O.State) -> O.State:
  match values:
    case Nil{}: state
    case Visibility{handle,shown} <> rest: visibleState(rest,O.setVisibility(state,handle,shown))
def withVisibility(base: TuiBase,values: List<&2,Visibility>) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      TuiBase{root,visibleState(values,focus),bindings,displayed,scheduler,show,clear,layout,heldFocus}
def newTui() -> TuiBase:
  TuiBase{C.new(),O.new(),Nil{},DisplayedFrame{Nil{},Frame{Nil{},Nil{}}},newRenderSchedule(),False{},False{},None{},None{}}
def setLayoutRoot(base: TuiBase,node: Maybe<&2,N.LayoutNode>) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,_,+heldFocus}:
      TuiBase{root,focus,bindings,displayed,scheduler,show,clear,node,heldFocus}
def setTerminalPreferences(base: TuiBase,showHardwareCursor: Bool,clearOnShrink: Bool) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,_,_,layout,+heldFocus}:
      TuiBase{root,focus,bindings,displayed,scheduler,showHardwareCursor,clearOnShrink,layout,heldFocus}
def layoutRoot(base: TuiBase) -> Maybe<&2,N.LayoutNode>:
  match base: case TuiBase{_,_,_,_,_,_,_,node,_}: node
def primaryScrollbarRoot(root: Maybe<&2,N.LayoutNode>,+mode: Scroll.ScrollViewScrollbar,+now: Nat) -> Maybe<&2,N.LayoutNode>:
  match root:
    case Some{node}: Some{N.setPrimaryScrollbar(node,mode,now)}
    case None{}: None{}
def setPrimaryScrollbar(base: TuiBase,mode: Scroll.ScrollViewScrollbar,now: Nat) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      TuiBase{root,focus,bindings,displayed,scheduler,show,clear,primaryScrollbarRoot(layout,mode,now),heldFocus}
def indicatorRow(base: TuiBase) -> Maybe<&2,Nat>:
  match base:
    case TuiBase{_,_,_,_,_,_,_,Some{layout},+heldFocus}: N.indicatorRow(layout)
    case _: None{}
def scrolledRoot(base: TuiBase,result: Scroll.ScrollByResult) -> ScrollChange:
  match result:
    case Scroll.ScrollByResult{next,unused,render}:
      ScrollChange{setLayoutRoot(base,Some{N.ScrollNode{next}}),unused,render}
def scrollRootBy(base: TuiBase,root: Maybe<&2,N.LayoutNode>,delta: T.Offset,now: Nat) -> ScrollChange:
  match root:
    case Some{N.ScrollNode{view}}:
      scrolledRoot(base,Scroll.scrollBy(view,delta,now))
    case _: ScrollChange{base,delta,False{}}
def scrollLayoutRootBy(+base: TuiBase,delta: T.Offset,now: Nat) -> ScrollChange:
  scrollRootBy(base,layoutRoot(base),delta,now)
def scrolledPrimary(base: TuiBase,result: N.ScrollResult) -> ScrollChange:
  match result:
    case N.ScrollResult{node,_,unused,render}: ScrollChange{setLayoutRoot(base,Some{node}),unused,render}
def scrollPrimaryBy(base: TuiBase,motion: N.ScrollMotion,now: Nat) -> ScrollChange:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,Some{layout},+heldFocus}:
      scrolledPrimary(TuiBase{root,focus,bindings,displayed,scheduler,show,clear,None{},heldFocus},N.scrollPrimary(layout,motion,now))
    case _: ScrollChange{base,T.Forward{0n},False{}}
def added(base: TuiBase,component: C.Component) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      TuiBase{C.addChild(root,component),focus,bindings,displayed,scheduler,show,clear,layout,heldFocus}
def removed(base: TuiBase,component: C.ComponentId) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      TuiBase{C.removeChild(root,component),focus,bindings,displayed,scheduler,show,clear,layout,heldFocus}
def cleared(base: TuiBase) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      TuiBase{C.clear(root),focus,bindings,displayed,scheduler,show,clear,layout,heldFocus}
def addedOverlay(root: C.Container,bindings: List<&2,Overlay>,displayed: DisplayedFrame,scheduler: RenderSchedule,show: Bool,clear: Bool,layout: Maybe<&2,N.LayoutNode>,component: C.Component,geometry: T.OverlayGeometry,pair: O.Change & O.OverlayHandle,heldFocus: Maybe<&2,FocusBinding>) -> OverlayChange:
  match pair:
    case (O.Change{focus,assignments,hide,render},+handle):
      OverlayChange{TuiBase{root,focus,List.append(&2,Overlay,bindings,Overlay{handle,component,geometry} <> Nil{}),displayed,scheduler,show,clear,layout,heldFocus},handle,assignments,hide,render}
def addOverlay(base: TuiBase,+component: C.Component,geometry: T.OverlayGeometry,nonCapturing: Bool,visible: Bool,mounted: List<&2,C.ComponentId>) -> OverlayChange:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      addedOverlay(root,bindings,displayed,scheduler,show,clear,layout,component,geometry,O.showOverlay(focus,mounted,C.id(component),nonCapturing,visible),heldFocus)
def bindingHandle(binding: Overlay) -> O.OverlayHandle:
  match binding:
    case Overlay{handle,_,_}: handle
def without(bindings: List<&2,Overlay>,+handle: O.OverlayHandle,+reversed: List<&2,Overlay>) -> List<&2,Overlay>:
  match bindings:
    case Nil{}: List.reverse(&2,Overlay,reversed)
    case +binding <> +rest:
      Bool.pick(Unit -> List<&2,Overlay>,O.sameHandle(bindingHandle(binding),handle),_ => without(rest,handle,reversed),_ => without(rest,handle,binding <> reversed))(Unit{})
def removedOverlay(root: C.Container,bindings: List<&2,Overlay>,displayed: DisplayedFrame,scheduler: RenderSchedule,show: Bool,clear: Bool,layout: Maybe<&2,N.LayoutNode>,+handle: O.OverlayHandle,change: O.Change,heldFocus: Maybe<&2,FocusBinding>) -> OverlayChange:
  match change:
    case O.Change{focus,assignments,hide,render}:
      OverlayChange{TuiBase{root,focus,without(bindings,handle,Nil{}),displayed,scheduler,show,clear,layout,heldFocus},handle,assignments,hide,render}
def overlayRemoved(base: TuiBase,+handle: O.OverlayHandle,components: List<&2,C.ComponentId>) -> OverlayChange:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      removedOverlay(root,bindings,displayed,scheduler,show,clear,layout,handle,O.hide(focus,components,handle),heldFocus)
def hiddenTop(+base: TuiBase,last: Maybe<&2,O.Entry>,components: List<&2,C.ComponentId>) -> Maybe<&2,OverlayChange>:
  match last:
    case None{}: None{}
    case Some{entry}: Some{overlayRemoved(base,O.entryHandle(entry),components)}
# upstream TUI.hideOverlay: removes the overlay shown last, visible or not
# (None when there is none).
def hideOverlay(+base: TuiBase,components: List<&2,C.ComponentId>) -> Maybe<&2,OverlayChange>:
  match base:
    case TuiBase{_,O.State{entries,_,_,_,_},_,_,_,_,_,_,+heldFocus}: hiddenTop(base,O.lastEntry(entries,None{}),components)
# Upstream OverlayHandle.focus/unfocus/setHidden. Like addOverlay and
# overlayRemoved (OverlayHandle.hide), each is a pure transition whose focus
# assignments the owner runs with applyOverlayChange. A handle whose overlay
# was removed is inert (see tests/overlays.md).
def focusTransition(base: TuiBase,+handle: O.OverlayHandle,change: O.Change) -> OverlayChange:
  match base change:
    case TuiBase{root,_,bindings,displayed,scheduler,show,clear,layout,+heldFocus} O.Change{focus,assignments,hide,render}:
      OverlayChange{TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,heldFocus},handle,assignments,hide,render}
def focusState(base: TuiBase) -> O.State:
  match base:
    case TuiBase{_,focus,_,_,_,_,_,_,+heldFocus}: focus
def focusOverlay(+base: TuiBase,+handle: O.OverlayHandle,components: List<&2,C.ComponentId>) -> OverlayChange:
  focusTransition(base,handle,O.focusOverlay(focusState(base),components,handle))
# `target` is upstream's OverlayUnfocusOptions: None when omitted, Some{None}
# for an explicit null target.
def unfocusOverlay(+base: TuiBase,+handle: O.OverlayHandle,target: Maybe<&2,Maybe<&2,C.ComponentId>>,components: List<&2,C.ComponentId>) -> OverlayChange:
  focusTransition(base,handle,O.unfocus(focusState(base),components,handle,target))
def setOverlayHidden(+base: TuiBase,+handle: O.OverlayHandle,hidden: Bool,components: List<&2,C.ComponentId>) -> OverlayChange:
  focusTransition(base,handle,O.setHidden(focusState(base),components,handle,hidden))
def focusedEntry(focus: Maybe<&2,C.ComponentId>,entry: Maybe<&2,O.Entry>) -> Bool:
  match entry:
    case None{}: False{}
    case Some{value}: O.sameFocus(focus,Some{O.entryComponent(value)})
# upstream OverlayHandle.isFocused
def isOverlayFocused(base: TuiBase,handle: O.OverlayHandle) -> Bool:
  match base:
    case TuiBase{_,O.State{entries,focus,_,_,_},_,_,_,_,_,_,+heldFocus}: focusedEntry(focus,O.find(entries,handle))
def displayedLines(frame: DisplayedFrame) -> List<&2,String>:
  match frame: case DisplayedFrame{_,Frame{lines,_}}: lines
def displayedSource(frame: DisplayedFrame) -> List<&2,String>:
  match frame: case DisplayedFrame{source,_}: source
def cursorPrepared(base: TuiBase,container: C.Container,bounds: List<&2,OverlayBounds>,result: T.CursorFrame,layoutFrame: Maybe<&2,Layout.LayoutFrame>) -> PreparedFrame:
  match base result:
    case TuiBase{_,focus,bindings,+displayed,scheduler,show,clear,layout,+heldFocus} T.CursorFrame{+source,cursor}:
      +lines = T.applyCachedLineResets(source,displayedSource(displayed),displayedLines(displayed))
      PreparedFrame{TuiBase{container,focus,bindings,displayed,scheduler,show,clear,layout,heldFocus},Frame{lines,bounds},lines,cursor,layoutFrame,source}
def prepared(base: TuiBase,container: C.Container,frame: Frame,height: Nat,layoutFrame: Maybe<&2,Layout.LayoutFrame>) -> PreparedFrame:
  match frame:
    case Frame{lines,bounds}: cursorPrepared(base,container,bounds,T.extractCursorPosition(lines,height),layoutFrame)
def preparedResult(base: TuiBase,container: C.Container,result: ResultOf(Frame),height: Nat,layoutFrame: Maybe<&2,Layout.LayoutFrame>) -> ResultOf(PreparedFrame):
  match result:
    case Fail{error}: Fail{error}
    case Done{frame}: Done{prepared(base,container,frame,height,layoutFrame)}
def composeRoot(+base: TuiBase,container: C.Container,lines: List<&2,String>,width: Nat,+height: Nat,layoutFrame: Maybe<&2,Layout.LayoutFrame>) -> IO(ResultOf(PreparedFrame)):
  match base:
    case TuiBase{_,focus,+bindings,_,_,_,_,_,+heldFocus}:
      do IO<ResultOf(PreparedFrame)>:
        result : ResultOf(Frame) <- compositeOverlays(focus,bindings,lines,width,height)
        return preparedResult(base,container,result,height,layoutFrame)
def composedRoot(base: TuiBase,result: C.Container & List<&2,String>,width: Nat,height: Nat) -> IO(ResultOf(PreparedFrame)):
  match result:
    case (container,lines): composeRoot(base,container,lines,width,height,None{})
def composedLayout(base: TuiBase,root: C.Container,tree: Tree.TreeFrame,width: Nat,height: Nat) -> IO(ResultOf(PreparedFrame)):
  match tree:
    case Tree.TreeFrame{node,Layout.LayoutFrame{box,frameWidth,frameHeight,+lines}}:
      composeRoot(setLayoutRoot(base,Some{node}),root,lines,width,height,Some{Layout.LayoutFrame{box,frameWidth,frameHeight,lines}})
def renderRoot(+base: TuiBase,+width: Nat,+height: Nat) -> IO(ResultOf(PreparedFrame)):
  match base:
    case TuiBase{root,_,_,_,_,_,_,layout,+heldFocus}:
      match layout:
        case None{}:
          do IO<ResultOf(PreparedFrame)>:
            result : C.Container & List<&2,String> <- C.renderContainer(root,width)
            composedRoot(base,result,width,height)
        case Some{node}:
          do IO<ResultOf(PreparedFrame)>:
          tree : Tree.TreeFrame <- Tree.renderTreeFrame(node,width,height)
          composedLayout(base,root,tree,width,height)

# The alternate screen restores its complete document to the regular terminal
# on exit. Rendering the child container here includes offscreen transcript
# rows, unlike the viewport-sized layout frame.
def renderedDocument(result: C.Container & List<&2,String>,focus: O.State,bindings: List<&2,Overlay>,displayed: DisplayedFrame,scheduler: RenderSchedule,show: Bool,clear: Bool,layout: Maybe<&2,N.LayoutNode>,heldFocus: Maybe<&2,FocusBinding>) -> TuiBase & List<&2,String>:
  match result:
    case (next,lines): (TuiBase{next,focus,bindings,displayed,scheduler,show,clear,layout,heldFocus},lines)
def renderDocument(base: TuiBase,width: Nat) -> IO(TuiBase & List<&2,String>):
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,+heldFocus}:
      do IO<TuiBase & List<&2,String>>:
        result : C.Container & List<&2,String> <- C.renderContainer(root,width)
        return renderedDocument(result,focus,bindings,displayed,scheduler,show,clear,layout,heldFocus)

# A stopped fullscreen layout uses each stack's natural allocation. Scroll
# children render from their beginning, rather than their current viewport.
# Keep the live layout unchanged so resuming preserves its scroll position.
def documentNode(node: N.LayoutNode) -> N.LayoutNode:
  match node:
    case N.ScrollNode{Scroll.ScrollView{child,_,_,_,_,_,_,_,_,_,_,_,_,_}}: N.Leaf{child}
    case N.Inline{child}: N.Inline{documentNode(child)}
    case N.VStack{entries,gap}: N.VStack{documentNode(entries),gap}
    case N.HStack{entries,gap,align}: N.HStack{documentNode(entries),gap,align}
    case N.Entry{child,size,condition}: N.Entry{documentNode(child),size,condition}
    case N.Children{first,rest}: N.Children{documentNode(first),documentNode(rest)}
    case node: node
def layoutDocument(frame: Tree.TreeFrame) -> List<&2,String>:
  match frame:
    case Tree.TreeFrame{_,Layout.LayoutFrame{_,_,_,lines}}: lines
def renderLayoutDocument(+base: TuiBase,width: Nat) -> IO(TuiBase & List<&2,String>):
  match base:
    case TuiBase{_,_,_,_,_,_,_,None{},+heldFocus}: renderDocument(base,width)
    case TuiBase{_,_,_,_,_,_,_,Some{node},+heldFocus}:
      do IO<TuiBase & List<&2,String>>:
        frame : Tree.TreeFrame <- Tree.renderInline(documentNode(node),width,4294967295n)
        return (base,layoutDocument(frame))

# Publish displayed hit bounds only after the terminal accepted the prepared frame.
def commitFrame(value: PreparedFrame) -> TuiBase:
  match value:
    case PreparedFrame{TuiBase{root,focus,bindings,_,scheduler,show,clear,layout,+heldFocus},frame,_,_,_,source}:
      TuiBase{root,focus,bindings,DisplayedFrame{source,frame},scheduler,show,clear,layout,heldFocus}

def focusedBinding(base: TuiBase) -> Maybe<&2,FocusBinding>:
  match base:
    case TuiBase{_,_,_,_,_,_,_,_,held}: held
def focusedValue(binding: FocusBinding) -> C.Component:
  match binding: case FocusBinding{component,_}: component
def getFocusedComponent(base: TuiBase) -> Maybe<&2,C.Component>:
  Maybe.map(&2,FocusBinding,C.Component,focusedValue,focusedBinding(base))
def withFocusedBinding(base: TuiBase,held: Maybe<&2,FocusBinding>) -> TuiBase:
  match base:
    case TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,_}: TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,held}
def focusRegistry(base: TuiBase,registry: List<&2,C.Component>) -> List<&2,C.Component>:
  match base:
    case TuiBase{_,_,_,_,_,_,_,_,Some{FocusBinding{component,_}}}: List.append(&2,C.Component,registry,component <> Nil{})
    case _: registry
def releaseFocusBinding(binding: Maybe<&2,FocusBinding>) -> IO(Unit):
  match binding:
    case None{}: IO.pure(Unit,Unit{})
    case Some{FocusBinding{_,retentions}}: C.releaseRetentions(retentions,Nil{})
def disposeFocus(base: TuiBase) -> IO(Unit): releaseFocusBinding(focusedBinding(base))
def retainFocused(component: Maybe<&2,C.Component>) -> IO(Maybe<&2,FocusBinding>):
  match component:
    case None{}: IO.pure(Maybe<&2,FocusBinding>,None{})
    case Some{+component}:
      do IO<Maybe<&2,FocusBinding>>:
        retentions : List<&2,C.Retention()> <- C.retainIndependent(C.componentRetentions(component))
        return Some{FocusBinding{component,retentions}}

# Registries hold mounted roots; groups expose their current descendants.
# Focus assignments run in source order before the focused component sees input.
type InputResult is Data: InputResult{tui: TuiBase,handled: Bool,requestImmediateRender: Bool}
def registered(components: List<&2,C.Component>,wanted: C.ComponentId) -> IO(Maybe<&2,C.Component>):
  C.lookup(components,wanted)
def registeredMaybe(registry: List<&2,C.Component>,target: Maybe<&2,C.ComponentId>) -> IO(Maybe<&2,C.Component>):
  match target:
    case None{}: IO.pure(Maybe<&2,C.Component>,None{})
    case Some{wanted}: registered(registry,wanted)
def present(registry: List<&2,C.Component>,target: Maybe<&2,C.ComponentId>) -> IO(Bool):
  match target:
    case None{}: IO.pure(Bool,True{})
    case Some{wanted}:
      do IO<Bool>:
        found : Maybe<&2,C.Component> <- registered(registry,wanted)
        return Bool.not(Maybe.is_none(&2,C.Component,found))
def validateChanges(changes: List<&2,O.FocusChange>,+registry: List<&2,C.Component>) -> IO(ResultOf(Unit)):
  match changes:
    case Nil{}: IO.pure(ResultOf(Unit),Done{Unit{}})
    case O.FocusChange{previous,next} <> rest:
      do IO<ResultOf(Unit)>:
        previousPresent : Bool <- present(registry,previous)
        nextPresent : Bool <- present(registry,next)
        Bool.pick(Unit -> IO(ResultOf(Unit)),previousPresent && nextPresent,
          _ => validateChanges(rest,registry),_ => IO.pure(ResultOf(Unit),Fail{MissingFocusedComponent{}}))(Unit{})
def setIfPresent(value: Maybe<&2,C.Component>,focused: Bool) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{component}: C.setFocused(component,focused)
def focusAssignment(+base: TuiBase,+registry: List<&2,C.Component>,previous: Maybe<&2,C.ComponentId>,next: Maybe<&2,C.ComponentId>) -> IO(TuiBase):
  do IO<TuiBase>:
    +all : List<&2,C.Component> = focusRegistry(base,registry)
    old : Maybe<&2,C.Component> <- registeredMaybe(all,previous)
    +new : Maybe<&2,C.Component> <- registeredMaybe(all,next)
    held : Maybe<&2,FocusBinding> <- retainFocused(new)
    setIfPresent(old,False{})
    setIfPresent(new,True{})
    releaseFocusBinding(focusedBinding(base))
    return withFocusedBinding(base,held)
def applyChanges(changes: List<&2,O.FocusChange>,+registry: List<&2,C.Component>,base: TuiBase) -> IO(TuiBase):
  match changes:
    case Nil{}: IO.pure(TuiBase,base)
    case O.FocusChange{previous,next} <> rest:
      do IO<TuiBase>:
        current : TuiBase <- focusAssignment(base,registry,previous,next)
        applyChanges(rest,registry,current)
def acceptsKey(component: C.Component,data: String) -> Bool:
  match component:
    case C.Group{component,_}: acceptsKey(component,data)
    case C.Managed{component,_}: acceptsKey(component,data)
    case C.Component{_,_,Some{_},_,_,_,+wantsRelease}: Bool.not(Keys.isKeyRelease(data)) || wantsRelease
    case _: False{}
def deliverKey(+state: TuiBase,component: Maybe<&2,C.Component>,+data: String) -> IO(ResultOf(InputResult)):
  match component:
    case None{}: IO.pure(ResultOf(InputResult),Done{InputResult{state,False{},False{}}})
    case Some{+component}:
      Bool.pick(Unit -> IO(ResultOf(InputResult)),acceptsKey(component,data),
        _ => do IO<ResultOf(InputResult)>:
          C.handleInput(component,data)
          return Done{InputResult{state,True{},True{}}},
        _ => IO.pure(ResultOf(InputResult),Done{InputResult{state,False{},False{}}}))(Unit{})
def focusedReceiver(binding: Maybe<&2,FocusBinding>,+registry: List<&2,C.Component>,+wanted: Maybe<&2,C.ComponentId>) -> IO(Maybe<&2,C.Component>):
  match binding wanted:
    case Some{FocusBinding{+component,_}} Some{id}:
      Bool.pick(Unit -> IO(Maybe<&2,C.Component>),C.same(C.id(component),id),
        _ => IO.pure(Maybe<&2,C.Component>,Some{component}),
        _ => registeredMaybe(registry,wanted))(Unit{})
    case _ _: registeredMaybe(registry,wanted)
def inputFocused(result: ResultOf(Unit),+state: TuiBase,+registry: List<&2,C.Component>,changes: List<&2,O.FocusChange>,focused: Maybe<&2,C.ComponentId>,data: String) -> IO(ResultOf(InputResult)):
  match result:
    case Fail{error}: IO.pure(ResultOf(InputResult),Fail{error})
    case Done{_}:
      do IO<ResultOf(InputResult)>:
        +state : TuiBase <- applyChanges(changes,registry,state)
        component : Maybe<&2,C.Component> <- focusedReceiver(focusedBinding(state),registry,focused)
        deliverKey(state,component,data)
def preparedInput(+base: TuiBase,+registry: List<&2,C.Component>,change: O.Change,data: String) -> IO(ResultOf(InputResult)):
  match base change:
    case TuiBase{root,_,bindings,displayed,scheduler,show,clear,layout,+heldFocus} O.Change{O.State{entries,+focused,restore,order,nextId},+changes,_,_}:
      do IO<ResultOf(InputResult)>:
        validation : ResultOf(Unit) <- validateChanges(changes,focusRegistry(base,registry))
        inputFocused(validation,TuiBase{root,O.State{entries,focused,restore,order,nextId},bindings,displayed,scheduler,show,clear,layout,heldFocus},registry,changes,focused,data)
def mountedRoots(registry: List<&2,C.Component>,+mounted: List<&2,C.ComponentId>) -> List<&2,C.Component>:
  match registry:
    case Nil{}: Nil{}
    case +component <> +rest:
      Bool.pick(Unit -> List<&2,C.Component>,O.mounted(mounted,C.id(component)),_ => component <> mountedRoots(rest,mounted),_ => mountedRoots(rest,mounted))(Unit{})
def mountedFocus(registry: List<&2,C.Component>,+mounted: List<&2,C.ComponentId>,target: Maybe<&2,C.ComponentId>) -> IO(List<&2,C.ComponentId>):
  match target:
    case None{}: IO.pure(List<&2,C.ComponentId>,mounted)
    case Some{+wanted}:
      Bool.pick(Unit -> IO(List<&2,C.ComponentId>),O.mounted(mounted,wanted),
        _ => IO.pure(List<&2,C.ComponentId>,mounted),
        _ => do IO<List<&2,C.ComponentId>>:
          found : Maybe<&2,C.Component> <- C.lookup(mountedRoots(registry,mounted),wanted)
          return Bool.pick(List<&2,C.ComponentId>,Maybe.is_none(&2,C.Component,found),mounted,wanted <> mounted))(Unit{})
def mountedState(registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,state: O.State) -> IO(List<&2,C.ComponentId>):
  match state:
    case O.State{_,current,_,_,_}: mountedFocus(registry,mounted,current)
def dispatchInput(+base: TuiBase,+registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,data: String) -> IO(ResultOf(InputResult)):
  match base:
    case TuiBase{_,+focus,_,_,_,_,_,_,+heldFocus}:
      do IO<ResultOf(InputResult)>:
        mounted : List<&2,C.ComponentId> <- mountedState(registry,mounted,focus)
        preparedInput(base,registry,O.prepareInput(focus,mounted),data)

def focusResult(result: ResultOf(Unit),base: TuiBase,registry: List<&2,C.Component>,changes: List<&2,O.FocusChange>) -> IO(ResultOf(TuiBase)):
  match result:
    case Fail{error}: IO.pure(ResultOf(TuiBase),Fail{error})
    case Done{_}:
      do IO<ResultOf(TuiBase)>:
        current : TuiBase <- applyChanges(changes,registry,base)
        return Done{current}
def focusChange(+base: TuiBase,change: O.Change,+registry: List<&2,C.Component>) -> IO(ResultOf(TuiBase)):
  match base change:
    case TuiBase{root,_,bindings,displayed,scheduler,show,clear,layout,+heldFocus} O.Change{focus,+changes,_,_}:
      do IO<ResultOf(TuiBase)>:
        validation : ResultOf(Unit) <- validateChanges(changes,focusRegistry(base,registry))
        focusResult(validation,TuiBase{root,focus,bindings,displayed,scheduler,show,clear,layout,heldFocus},registry,changes)
# Runs an overlay transition's focus assignments in source order, as upstream
# showOverlay and the handle methods set `focused` synchronously.
def applyOverlayChange(change: OverlayChange,+registry: List<&2,C.Component>) -> IO(ResultOf(TuiBase)):
  match change:
    case OverlayChange{+tui,_,+changes,_,_}:
      do IO<ResultOf(TuiBase)>:
        validation : ResultOf(Unit) <- validateChanges(changes,focusRegistry(tui,registry))
        focusResult(validation,tui,registry,changes)
def setFocus(+base: TuiBase,+registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,target: Maybe<&2,C.ComponentId>) -> IO(ResultOf(TuiBase)):
  match base:
    case TuiBase{_,+focus,_,_,_,_,_,_,+heldFocus}:
      do IO<ResultOf(TuiBase)>:
        mounted : List<&2,C.ComponentId> <- mountedState(registry,mounted,focus)
        focusChange(base,O.setFocus(focus,mounted,target),registry)

def focusedTarget(component: Maybe<&2,C.Component>,+base: TuiBase,+registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,+target: C.TuiMouseDispatchTarget(),+wanted: C.ComponentId) -> IO(ResultOf(TuiBase)):
  match component:
    case Some{component}:
      setFocus(base,Bool.pick(List<&2,C.Component>,C.same(C.targetId(target),wanted),component <> registry,registry),mounted,Some{wanted})
    case None{}: setFocus(base,registry,mounted,Some{wanted})
def setFocusFromTarget(base: TuiBase,registry: List<&2,C.Component>,mounted: List<&2,C.ComponentId>,+target: C.TuiMouseDispatchTarget(),wanted: C.ComponentId) -> IO(ResultOf(TuiBase)):
  focusedTarget(C.targetComponent(target),base,registry,mounted,target,wanted)
