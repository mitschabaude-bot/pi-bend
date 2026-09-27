import Base
import ../packages/tui/src/fullscreen-mouse.bend as M
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/layout.bend as L
import ../packages/runtime/src/callback.bend as Callback

def flag(value: Bool) -> String: Bool.pick(String,value,"1","0")
def offset(value: T.Offset) -> String:
  match value: case T.Forward{v}: Nat.show(v) case T.Backward{v}: "-" ++ Nat.show(v)
def kind(value: T.TuiMouseEventType) -> String:
  match value:
    case T.MousePress{}: "press" case T.MouseRelease{}: "release" case T.MouseMove{}: "move"
    case T.MouseDrag{}: "drag" case T.MouseClick{}: "click" case T.MouseWheel{}: "wheel"
def button(value: T.TuiMouseButton) -> String:
  match value: case T.MouseLeft{}: "left" case T.MouseMiddle{}: "middle" case T.MouseRight{}: "right" case T.NoButton{}: "none"
def optional(value: Maybe<&2,T.Offset>) -> String:
  match value: case None{}: "0" case Some{v}: offset(v)
def answer(kind: T.TuiMouseEventType) -> Maybe<&2,C.MouseResponse()>:
  match kind:
    case T.MouseRelease{}: None{} case T.MouseMove{}: None{}
    case T.MousePress{}: Some{C.LocalResult{T.TuiMouseEventResult{True{},True{},True{},None{}}}}
    case _: Some{C.LocalResult{T.TuiMouseEventResult{True{},False{},False{},None{}}}}
def receive(_: Unit,event: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse()>):
  match event:
    case T.TuiMouseEvent{+eventKind,btn,x,y,sx,sy,width,height,shift,alt,ctrl,wheel,count}:
      do IO<Maybe<&2,C.MouseResponse()>>:
        IO.print(kind(eventKind) ++ ":" ++ button(btn) ++ ":" ++ offset(x) ++ "," ++ offset(y) ++ ":" ++ offset(sx) ++ "," ++ offset(sy) ++ ":" ++ Nat.show(width) ++ "," ++ Nat.show(height) ++ ":" ++ flag(shift) ++ flag(alt) ++ flag(ctrl) ++ ":" ++ Nat.show(Maybe.default(&2,Nat,count,0n)) ++ ":" ++ optional(wheel))
        return answer(eventKind)
def focused(_: Unit,value: Bool) -> IO(Unit): IO.print("focus:" ++ flag(value))
def render(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,Nil{})
def invalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def frame() -> L.LayoutFrame:
  +leaf = {L.LayoutRect{10n,5n,20n,4n}: L.LayoutRect}
  +middle = {L.LayoutRect{8n,3n,30n,10n}: L.LayoutRect}
  +outer = {L.LayoutRect{0n,0n,80n,24n}: L.LayoutRect}
  L.LayoutFrame{L.LayoutBox{Some{C.ComponentId{3n}},outer,outer,[L.LayoutBox{Some{C.ComponentId{2n}},middle,middle,[L.LayoutBox{Some{C.ComponentId{1n}},leaf,leaf,Nil{},None{},0n,0n}],None{},0n,0n},L.LayoutBox{Some{C.ComponentId{4n}},leaf,leaf,Nil{},None{},0n,1n}],None{},0n,0n},80n,24n,Nil{}}
def children(component: C.Component,_: Unit) -> IO(List<&2,C.Component>):
  IO.pure(List<&2,C.Component>,component <> Nil{})
def step(raw: Maybe<&2,M.Raw>,state: M.State,tui: B.TuiBase,+component: C.Component) -> IO(M.Outcome):
  match raw:
    case None{}: IO.die(M.Outcome,1,"invalid mouse fixture input")
    case Some{raw}: M.dispatch(state,tui,Some{frame()},[component],[C.ComponentId{3n}],raw,80n,24n)
def continue(outcome: M.Outcome,following: M.State -> B.TuiBase -> IO(Unit)) -> IO(Unit):
  match outcome:
    case M.Outcome{_,_,_,_,Some{_}}: IO.die(Unit,1,"mouse focus failed")
    case M.Outcome{state,tui,_,render,None{}}:
      do IO<Unit>:
        IO.print("render:" ++ flag(render))
        following(state)(tui)
@unsafe def run(actions: List<String>,state: M.State,tui: B.TuiBase,+component: C.Component) -> IO(Unit):
  match actions:
    case Nil{}:
      do IO<Unit>:
        M.dispose(state)
        B.disposeFocus(tui)
    case data <> rest:
      do IO<Unit>:
        outcome : M.Outcome <- step(M.parse(data),state,tui,component)
        continue(outcome,state => tui => run(rest,state,tui,component))
def ids(boxes: List<&2,L.LayoutBox>) -> List<&2,String>:
  match boxes:
    case Nil{}: Nil{}
    case L.LayoutBox{Some{C.ComponentId{id}},_,_,_,_,_,_} <> rest: Nat.show(id) <> ids(rest)
    case _ <> rest: ids(rest)
def hits(x: Nat,y: Nat) -> IO(Unit): IO.print("hits:" ++ String.join(ids(L.getLayoutBoxesAt(frame(),x,y)),","))
def main() -> IO(Unit):
  do IO<Unit>:
    hits(12n,6n)
    hits(35n,6n)
    hits(79n,23n)
    hits(80n,23n)
    +mouse : Callback.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse()>> <- Callback.create(~Unit,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse()>,~receive,Unit{})
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~focused,Unit{})
    +draw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +reset : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~invalidate,Unit{})
    +component : C.Component = C.Component{C.ComponentId{1n},draw,None{},Some{mouse},reset,Some{focus},False{}}
    +inner : Callback.Callback<Unit,List<&2,C.Component>> <- Callback.create(~C.Component,~Unit,~List<&2,C.Component>,~children,component)
    +middle : C.Component = C.Group{C.Component{C.ComponentId{2n},draw,None{},None{},reset,None{},False{}},inner}
    +outer : Callback.Callback<Unit,List<&2,C.Component>> <- Callback.create(~C.Component,~Unit,~List<&2,C.Component>,~children,middle)
    root : C.Component = C.Group{C.Component{C.ComponentId{3n},draw,None{},None{},reset,None{},False{}},outer}
    args : List<String> <- IO.args()
    run(args,M.initial(),B.newTui(),root)
    Callback.dispose(Unit,List<&2,C.Component>,outer)
    Callback.dispose(Unit,List<&2,C.Component>,inner)
    Callback.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse()>,mouse)
    Callback.dispose(Bool,Unit,focus)
    Callback.dispose(Nat,List<&2,String>,draw)
    Callback.dispose(Unit,Unit,reset)
