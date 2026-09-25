import Base
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/layout-node.bend as N
import ../packages/tui/src/components/scroll-view.bend as S
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/callback.bend as Callback

def draw(lines: List<&2,String>,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,lines)
def ignore(context: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: U.trimEnd(U.stripTerminalSequences(line))
    case line <> rest: U.trimEnd(U.stripTerminalSequences(line)) ++ "|" ++ clean(rest)
def top(root: Maybe<&2,N.LayoutNode>) -> Nat:
  match root:
    case Some{N.ScrollNode{S.ScrollView{_,_,_,_,_,_,offset,_,_,_,_,_,_,_}}}: offset
    case _: 0n
def report(label: String,ready: B.PreparedFrame) -> IO(Unit):
  match ready:
    case B.PreparedFrame{state,_,lines,_,_}:
      IO.print(label ++ ":" ++ Nat.show(top(B.layoutRoot(state))) ++ ":[" ++ clean(lines) ++ "]")
def success(value: B.ResultOf(B.PreparedFrame)) -> IO(B.PreparedFrame):
  match value:
    case Done{frame}: IO.pure(B.PreparedFrame,frame)
    case Fail{_}: IO.die(B.PreparedFrame,1,"renderRoot failed")
def changed(value: B.ScrollChange) -> B.TuiBase:
  match value: case B.ScrollChange{state,_,_}: state
def main() -> IO(Unit):
  do IO<Unit>:
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +renderer : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"one" <> "two" <> "three" <> "four" <> "five" <> "six" <> Nil{})
    +child : C.Component <- IO.pure(C.Component,C.Component{C.ComponentId{1n},renderer,None{},None{},invalidator,None{},False{}})
    +view : S.ScrollView <- IO.pure(S.ScrollView,S.new(child,S.ScrollViewOptions{S.FollowEnd{},True{},S.Chain{},S.Always{},10n}))
    +base : B.TuiBase <- IO.pure(B.TuiBase,B.setLayoutRoot(B.newTui(),Some{N.ScrollNode{view}}))
    first : B.ResultOf(B.PreparedFrame) <- B.renderRoot(base,6n,3n)
    +ready : B.PreparedFrame <- success(first)
    report("initial",ready)
    +committed : B.TuiBase <- IO.pure(B.TuiBase,B.commitFrame(ready))
    +scrolled : B.TuiBase <- IO.pure(B.TuiBase,changed(B.scrollLayoutRootBy(committed,T.Backward{2n},0n)))
    second : B.ResultOf(B.PreparedFrame) <- B.renderRoot(scrolled,6n,3n)
    +back : B.PreparedFrame <- success(second)
    report("back",back)
    +afterBack : B.TuiBase <- IO.pure(B.TuiBase,B.commitFrame(back))
    resized : B.ResultOf(B.PreparedFrame) <- B.renderRoot(afterBack,6n,4n)
    +taller : B.PreparedFrame <- success(resized)
    report("resize",taller)
    +afterResize : B.TuiBase <- IO.pure(B.TuiBase,B.commitFrame(taller))
    +forward : B.TuiBase <- IO.pure(B.TuiBase,changed(B.scrollLayoutRootBy(afterResize,T.Forward{9n},0n)))
    endFrame : B.ResultOf(B.PreparedFrame) <- B.renderRoot(forward,6n,4n)
    +ended : B.PreparedFrame <- success(endFrame)
    report("end",ended)
    Callback.dispose(Nat,List<&2,String>,renderer)
    Callback.dispose(Unit,Unit,invalidator)
