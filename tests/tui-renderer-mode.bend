import Base
import ../packages/tui/src/tui-process.bend as P
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/keys.bend as KeyIds
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui-main-screen.bend as S
import ../packages/tui/src/tui-alt-screen.bend as A
import ../packages/tui/src/layout-node.bend as Layout
import ../packages/tui/src/alt-screen-search.bend as Search
import ../packages/tui/src/keybindings.bend as Keys
import ../packages/runtime/src/callback.bend as K
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/record.bend as Record

def check(value: Bool,message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)
def render(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"document" <> Nil{})
def invalidate(journal: R.Ref<String>,_: Unit) -> IO(Unit): R.modify(String,Unit,journal,old => (old ++ "i",Unit{}))
def focus(journal: R.Ref<String>,value: Bool) -> IO(Unit): R.modify(String,Unit,journal,old => (old ++ Bool.pick(String,value,"+","-"),Unit{}))
def label(_: Unit,_: Unit) -> IO(String): IO.pure(String,"bottom")
def styles(_: Unit,_: Unit) -> IO(Search.Styles): IO.pure(Search.Styles,Search.Styles{"",""})
def focused(result: B.ResultOf(B.TuiBase)) -> IO(B.TuiBase):
  match result:
    case Done{base}: IO.pure(B.TuiBase,base)
    case Fail{_}: IO.die(B.TuiBase,1,"fixture focus failed")
def terminalTransition(output: S.Stream,fullscreen: Bool,changed: Bool) -> Bool:
  match output changed:
    case S.Stream{Nil{},_} False{}: True{}
    case S.Stream{S.Text{value} <> Nil{},_} True{}:
      String.eq(value,Bool.pick(String,fullscreen,A.enter(),A.leave()))
    case _ _: False{}
def mountedFocus(active: P.Active) -> Bool:
  match active:
    case P.Active{P.Session{base,_},component <> Nil{},id <> Nil{},_,_,_}:
      C.same(C.id(component),id)
    case _: False{}
def retainedLayouts(modes: P.RendererModes) -> Bool:
  match modes:
    case P.RendererModes{P.RendererView{_,Some{Layout.Spacer{7n}}},P.RendererView{_,Some{Layout.Spacer{9n}}},_,_,_}: True{}
    case _: False{}
def changedLayout(active: P.Active) -> P.Active:
  match active:
    case P.Active{P.Session{base,screen},components,mounted,error,owed,ticks}:
      P.Active{P.Session{B.setLayoutRoot(base,Some{Layout.Spacer{9n}}),screen},components,mounted,error,owed,ticks}
def switched(result: Maybe<&2,P.RendererSwitch>,+fullscreen: Bool,+changed: Bool) -> IO(P.RendererSwitch):
  match result:
    case Some{P.RendererSwitch{+active,+modes,+output,+actual}}:
      do IO<P.RendererSwitch>:
        check(Bool.not(Bool.xor(P.fullscreenMode(active),fullscreen)) && Bool.not(Bool.xor(actual,changed)),"renderer choice/change differs")
        check(terminalTransition(output,fullscreen,changed),"alternate-screen terminal transition differs")
        check(mountedFocus(active),"renderer component registry was lost")
        return P.RendererSwitch{active,modes,output,actual}
    case None{}: IO.die(P.RendererSwitch,1,"renderer switch rejected")
def baseOf(active: P.Active) -> B.TuiBase:
  match active: case P.Active{P.Session{base,_},_,_,_,_,_}: base
def overlays(change: B.OverlayChange) -> B.TuiBase:
  match change: case B.OverlayChange{base,_,_,_,_}: base
def restored(active: P.Active) -> Bool:
  match active:
    case P.Active{P.Session{_,P.Main{S.State{S.TuiMainScreenRenderState{"previous" <> Nil{},Some{80n},Some{24n},3n,2n,8n,1n},_,_,_}}},_,_,_,_,_}: True{}
    case _: False{}
def switchedResult(result: IO(Maybe<&2,P.RendererSwitch>),fullscreen: Bool,changed: Bool) -> IO(P.RendererSwitch):
  do IO<P.RendererSwitch>:
    value : Maybe<&2,P.RendererSwitch> <- result
    switched(value,fullscreen,changed)
def focusedComponent(value: Maybe<&2,C.Component>) -> IO(C.Component):
  match value:
    case Some{component}: IO.pure(C.Component,component)
    case None{}: IO.die(C.Component,1,"renderer switch lost focus")
def finish(value: P.RendererSwitch,+journal: R.Ref<String>) -> IO(Unit):
  match value:
    case P.RendererSwitch{+active,+modes,_,_}:
      do IO<Unit>:
        check(restored(active),"regular screen snapshot was lost")
        check(retainedLayouts(modes),"renderer layouts did not retain their latest state")
        +callbacks : String <- R.read(String,journal)
        check(String.eq(callbacks,"-i+-i+"),"focus/invalidation order differs")
        +base : B.TuiBase = baseOf(active)
        +component : C.Component <- focusedComponent(B.getFocusedComponent(base))
        overlay : B.TuiBase = overlays(B.addOverlay(base,component,T.defaultOverlayGeometry(),True{},False{},Nil{}))
        +withOverlay : P.Active = P.active(P.Session{overlay,P.Main{S.initial()}},component <> Nil{},C.id(component) <> Nil{})
        unchanged : P.RendererSwitch <- switchedResult(P.switchRenderer(withOverlay,modes,False{}),False{},False{})
        blocked : Maybe<&2,P.RendererSwitch> <- P.switchRenderer(withOverlay,modes,True{})
        check(Maybe.is_none(&2,P.RendererSwitch,blocked),"hidden overlay did not block mode change")
        afterRejection : String <- R.read(String,journal)
        check(String.eq(callbacks,afterRejection),"rejected renderer switch invoked callbacks")
        B.disposeFocus(base)
def returning(value: P.RendererSwitch,+journal: R.Ref<String>) -> IO(Unit):
  match value:
    case P.RendererSwitch{+active,+modes,_,_}:
      do IO<Unit>:
        same : P.RendererSwitch <- switchedResult(P.switchRenderer(active,modes,True{}),True{},False{})
        unchanged : String <- R.read(String,journal)
        check(String.eq(unchanged,"-i+"),"same-mode request invoked callbacks")
        regular : P.RendererSwitch <- switchedResult(P.switchRenderer(changedLayout(active),modes,False{}),False{},True{})
        finish(regular,journal)
def run(+component: C.Component,+alternate: A.State,+journal: R.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    focusResult : B.ResultOf(B.TuiBase) <- B.setFocus(B.added(B.newTui(),component),component <> Nil{},C.id(component) <> Nil{},Some{C.id(component)})
    focusedBase : B.TuiBase <- focused(focusResult)
    +base : B.TuiBase = B.setLayoutRoot(focusedBase,Some{Layout.Spacer{7n}})
    R.write(String,journal,"")
    snapshot : S.TuiMainScreenRenderState = S.TuiMainScreenRenderState{"previous" <> Nil{},Some{80n},Some{24n},3n,2n,8n,1n}
    initial : P.Active = P.active(P.Session{base,P.Main{S.restoreRenderState(S.initial(),snapshot)}},component <> Nil{},C.id(component) <> Nil{})
    regular : P.RendererView = P.RendererView{C.Container{component <> Nil{},None{}},Some{Layout.Spacer{3n}}}
    fullscreen : P.RendererView = P.RendererView{C.Container{component <> Nil{},None{}},Some{Layout.Spacer{5n}}}
    value : P.RendererSwitch <- switchedResult(P.switchRenderer(initial,P.RendererModes{regular,fullscreen,alternate,None{},False{}},True{}),True{},True{})
    returning(value,journal)
def main() -> IO(Unit):
  do IO<Unit>:
    +journal : R.Ref<String> <- R.new(String,"")
    +render : K.Callback<Nat,List<&2,String>> <- K.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +invalidate : K.Callback<Unit,Unit> <- K.create(~R.Ref<String>,~Unit,~Unit,~invalidate,journal)
    +focus : K.Callback<Bool,Unit> <- K.create(~R.Ref<String>,~Bool,~Unit,~focus,journal)
    +label : K.Callback<Unit,String> <- K.create(~Unit,~Unit,~String,~label,Unit{})
    +styles : K.Callback<Unit,Search.Styles> <- K.create(~Unit,~Unit,~Search.Styles,~styles,Unit{})
    +keys : R.Ref<Keys.KeybindingsManager> <- R.new(Keys.KeybindingsManager,Keys.create(Record.new(Keys.KeybindingDefinition),Record.new(List<&2,KeyIds.KeyId>)))
    run(C.Component{C.ComponentId{1n},render,None{},None{},invalidate,Some{focus},False{}},A.initial(label,keys,styles),journal)
    K.dispose(Nat,List<&2,String>,render)
    K.dispose(Unit,Unit,invalidate)
    K.dispose(Bool,Unit,focus)
    K.dispose(Unit,String,label)
    K.dispose(Unit,Search.Styles,styles)
    oldKeys : Keys.KeybindingsManager <- R.dispose(Keys.KeybindingsManager,keys)
    oldJournal : String <- R.dispose(String,journal)
    IO.print("renderer mode round-trip, focus order, same-mode reuse and overlay rejection pass")
