import Base
import ../packages/tui/src/components/scroll-view.bend as S
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/callback.bend as Callback

def draw(context: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"one" <> "two" <> Nil{})
def ignore(context: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def viewOf(transition: S.Transition) -> S.ScrollView: match transition: case S.Transition{view,_}: view
def viewBy(result: S.ScrollByResult) -> S.ScrollView: match result: case S.ScrollByResult{view,_,_}: view
def unused(result: S.ScrollByResult) -> String:
  match result:
    case S.ScrollByResult{_,T.Forward{amount},_}: Nat.show(amount)
    case S.ScrollByResult{_,T.Backward{amount},_}: "-" ++ Nat.show(amount)
def bool(value: Bool) -> String: Bool.pick(String,value,"true","false")
def report(label: String,+view: S.ScrollView) -> IO(Unit):
  match view:
    case S.ScrollView{_,_,_,_,_,_,top,content,viewport,following,_,_,_,_}:
      IO.print(label ++ ":" ++ Nat.show(top) ++ ":" ++ bool(following) ++ ":" ++ Nat.show(content) ++ "/" ++ Nat.show(viewport) ++ ":" ++ bool(S.isScrollbarVisible(view)) ++ ":" ++ Nat.show(S.getContentWidth(view,6n)))
def main() -> IO(Unit):
  do IO<Unit>:
    +renderer : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~draw,Unit{})
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +child : C.Component <- IO.pure(C.Component,C.Component{C.ComponentId{1n},renderer,None{},None{},invalidator,None{},False{}})
    +options : S.ScrollViewOptions <- IO.pure(S.ScrollViewOptions,S.ScrollViewOptions{S.FollowEnd{},True{},S.Chain{},S.Hidden{},10n})
    +v0 : S.ScrollView <- IO.pure(S.ScrollView,S.updateLayout(S.new(child,options),6n,3n))
    report("initial",v0)
    +r1 : S.ScrollByResult <- IO.pure(S.ScrollByResult,S.scrollBy(v0,T.Backward{2n},0n))
    IO.print("unused1:" ++ unused(r1))
    +v1 : S.ScrollView <- IO.pure(S.ScrollView,viewBy(r1))
    report("back2",v1)
    +r2 : S.ScrollByResult <- IO.pure(S.ScrollByResult,S.scrollBy(v1,T.Backward{3n},0n))
    IO.print("unused2:" ++ unused(r2))
    +v2 : S.ScrollView <- IO.pure(S.ScrollView,viewBy(r2))
    report("back3",v2)
    +r3 : S.ScrollByResult <- IO.pure(S.ScrollByResult,S.scrollBy(v2,T.Forward{10n},0n))
    IO.print("unused3:" ++ unused(r3))
    +v3 : S.ScrollView <- IO.pure(S.ScrollView,viewBy(r3))
    report("forward10",v3)
    +v4 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.scrollTo(v3,3n,True{},0n)))
    report("suppressed",v4)
    +v5 : S.ScrollView <- IO.pure(S.ScrollView,S.updateLayout(v4,7n,3n))
    report("grown",v5)
    +v6 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.scrollToEnd(v5,0n)))
    report("end",v6)
    +v7 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.scrollToStart(v6,0n)))
    report("start",v7)
    +v8 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.setScrollbar(v7,S.Always{},0n)))
    report("always",v8)
    +v9 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.setScrollbar(v8,S.Auto{},0n)))
    +r4 : S.ScrollByResult <- IO.pure(S.ScrollByResult,S.scrollBy(v9,T.Forward{1n},0n))
    +v10 : S.ScrollView <- IO.pure(S.ScrollView,viewBy(r4))
    report("auto-active",v10)
    +v11 : S.ScrollView <- IO.pure(S.ScrollView,viewOf(S.advanceTime(v10,11n)))
    report("auto-hidden",v11)
    Callback.dispose(Nat,List<&2,String>,renderer)
    Callback.dispose(Unit,Unit,invalidator)
