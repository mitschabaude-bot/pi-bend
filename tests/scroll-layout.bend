import Base
import ./scroll-view.bend as StateTest
import ../packages/tui/src/components/scroll-view.bend as S
import ../packages/tui/src/layout.bend as L
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/callback.bend as Callback

def draw(context: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"1" <> "2" <> "3" <> "4" <> "5" <> "6" <> Nil{})
def ignore(context: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: U.trimEnd(U.stripTerminalSequences(line))
    case line <> rest: U.trimEnd(U.stripTerminalSequences(line)) ++ "|" ++ clean(rest)
def viewOf(value: L.ScrollLayoutFrame) -> S.ScrollView:
  match value: case L.ScrollLayoutFrame{view,_}: view
def linesOf(value: L.ScrollLayoutFrame) -> String:
  match value: case L.ScrollLayoutFrame{_,L.LayoutFrame{_,_,_,lines}}: clean(lines)
def info(label: String,value: L.ScrollLayoutFrame) -> IO(Unit):
  match value:
    case L.ScrollLayoutFrame{view,L.LayoutFrame{L.LayoutBox{_,_,_,children,_,_,_},width,height,lines}}:
      match children:
        case L.LayoutBox{_,L.LayoutRect{_,_,childWidth,childHeight},_,_,_,offset,_} <> rest:
          IO.print(label ++ ":" ++ Nat.show(L.viewTop(view)) ++ ":" ++ Nat.show(childWidth) ++ "x" ++ Nat.show(childHeight) ++ ":" ++ Nat.show(offset) ++ ":[" ++ clean(lines) ++ "]")
        case _: IO.print(label ++ ":empty")
def takeTransition(value: S.Transition) -> S.ScrollView: match value: case S.Transition{view,_}: view
def takeView(value: S.ScrollByResult) -> S.ScrollView: match value: case S.ScrollByResult{view,_,_}: view
def main() -> IO(Unit):
  do IO<Unit>:
    StateTest.main()
    +renderer : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~draw,Unit{})
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +child : C.Component <- IO.pure(C.Component,C.Component{C.ComponentId{1n},renderer,None{},None{},invalidator,None{},False{}})
    +follow : S.ScrollView <- IO.pure(S.ScrollView,S.new(child,S.ScrollViewOptions{S.FollowEnd{},False{},S.Chain{},S.Hidden{},10n}))
    +f0 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(follow,10n,3n)
    info("follow",f0)
    +back : S.ScrollView <- IO.pure(S.ScrollView,takeView(S.scrollBy(viewOf(f0),T.Backward{2n},0n)))
    +f1 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(back,10n,3n)
    info("back",f1)
    +always : S.ScrollView <- IO.pure(S.ScrollView,S.new(child,S.ScrollViewOptions{S.FollowNone{},False{},S.Chain{},S.Always{},10n}))
    +a0 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(always,6n,3n)
    info("always",a0)
    +auto : S.ScrollView <- IO.pure(S.ScrollView,S.new(child,S.ScrollViewOptions{S.FollowNone{},False{},S.Chain{},S.Auto{},10n}))
    +u0 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(auto,6n,3n)
    info("auto-initial",u0)
    +moved : S.ScrollView <- IO.pure(S.ScrollView,takeView(S.scrollBy(viewOf(u0),T.Forward{1n},0n)))
    +u1 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(moved,6n,3n)
    info("auto-moved",u1)
    +u2 : L.ScrollLayoutFrame <- L.renderScrollViewFrame(takeTransition(S.scrollToEnd(viewOf(u1),0n)),6n,3n)
    info("auto-end",u2)
    Callback.dispose(Nat,List<&2,String>,renderer)
    Callback.dispose(Unit,Unit,invalidator)
