import Base
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/overlays.bend as O
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/callback.bend as K
import ../packages/runtime/src/ref.bend as Ref

type Child is Data: Child{number: Nat,lines: List<&2,String>,journal: Ref.Ref<String>}
def append(journal: Ref.Ref<String>,entry: String) -> IO(Unit): Ref.modify(String,Unit,journal,old => (old ++ entry ++ ",",Unit{}))
def render(child: Child,width: Nat) -> IO(List<&2,String>):
  match child:
    case Child{number,lines,journal}:
      do IO<List<&2,String>>:
        append(journal,"R" ++ Nat.show(number) ++ "/" ++ Nat.show(width))
        return lines
def input(child: Child,data: String) -> IO(Unit):
  match child:
    case Child{number,_,journal}: append(journal,"I" ++ Nat.show(number))
def focused(child: Child,value: Bool) -> IO(Unit):
  match child:
    case Child{number,_,journal}: append(journal,"F" ++ Nat.show(number) ++ Bool.pick(String,value,"+","-"))
def invalidated(child: Child,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def component(+number: Nat,+lines: List<&2,String>,+journal: Ref.Ref<String>,wantsRelease: Bool) -> IO(C.Component):
  do IO<C.Component>:
    r : K.Callback<Nat,List<&2,String>> <- K.create(~Child,~Nat,~List<&2,String>,~render,Child{number,lines,journal})
    i : K.Callback<String,Unit> <- K.create(~Child,~String,~Unit,~input,Child{number,lines,journal})
    f : K.Callback<Bool,Unit> <- K.create(~Child,~Bool,~Unit,~focused,Child{number,lines,journal})
    v : K.Callback<Unit,Unit> <- K.create(~Child,~Unit,~Unit,~invalidated,Child{number,lines,journal})
    return C.Component{C.ComponentId{number},r,Some{i},None{},v,Some{f},wantsRelease}
def dispose(component: C.Component) -> IO(Unit):
  match component:
    case C.Component{_,r,Some{i},_,v,Some{f},_}:
      do IO<Unit>:
        K.dispose(Nat,List<&2,String>,r)
        K.dispose(String,Unit,i)
        K.dispose(Bool,Unit,f)
        K.dispose(Unit,Unit,v)
    case _: IO.pure(Unit,Unit{})
def joined(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: line
    case line <> rest: line ++ "|" ++ joined(rest)
def ids(bounds: List<&2,B.OverlayBounds>) -> String:
  match bounds:
    case Nil{}: ""
    case B.OverlayBounds{_,_,C.TuiMouseDispatchTarget{C.ComponentId{id},_,_,_,_}} <> rest: Nat.show(id) ++ ids(rest)
def frame(value: B.Frame) -> String:
  match value:
    case B.Frame{lines,bounds}: joined(lines) ++ "#" ++ ids(bounds)
def displayed(value: B.TuiBase) -> String:
  match value:
    case B.TuiBase{_,_,_,shown,_,_,_,_}: frame(shown)
def prepared(value: B.PreparedFrame) -> String:
  match value:
    case B.PreparedFrame{_,shown,_,_,_}: frame(shown)
def stagedDisplayed(value: B.PreparedFrame) -> String:
  match value:
    case B.PreparedFrame{tui,_,_,_,_}: displayed(tui)
def committed(value: B.PreparedFrame) -> B.TuiBase: B.commitFrame(value)
def success(value: B.ResultOf(B.PreparedFrame)) -> IO(B.PreparedFrame):
  match value:
    case Done{frame}: IO.pure(B.PreparedFrame,frame)
    case Fail{_}: IO.die(B.PreparedFrame,1,"renderRoot failed")
def inputSuccess(value: B.ResultOf(B.InputResult)) -> IO(B.InputResult):
  match value:
    case Done{result}: IO.pure(B.InputResult,result)
    case Fail{_}: IO.die(B.InputResult,1,"dispatchInput failed")
def inputText(value: B.InputResult) -> String:
  match value:
    case B.InputResult{tui,handled,immediate}: displayed(tui) ++ ":" ++ Bool.pick(String,handled,"1","0") ++ Bool.pick(String,immediate,"1","0")
def inputState(value: B.InputResult) -> B.TuiBase:
  match value:
    case B.InputResult{tui,_,_}: tui
def snapshot(value: B.TuiBase,journal: Ref.Ref<String>,shown: Bool) -> IO(B.TuiBase):
  do IO<B.TuiBase>:
    append(journal,"V3/8x3")
    return B.withVisibility(value,B.Visibility{O.OverlayHandle{3n},shown} <> Nil{})
def run() -> IO(Unit):
  do IO<Unit>:
    +journal : Ref.Ref<String> <- Ref.new(String,"")
    +a : C.Component <- component(1n,"A" <> "B" <> Nil{},journal,False{})
    +b : C.Component <- component(2n,"C" <> Nil{},journal,False{})
    +overlay : C.Component <- component(3n,"OV" <> Nil{},journal,False{})
    +old : C.Component <- component(9n,"old" <> Nil{},journal,False{})
    +base : B.TuiBase = B.TuiBase{C.Container{a <> b <> Nil{},None{}},O.State{O.Entry{O.OverlayHandle{3n},C.ComponentId{3n},Some{C.ComponentId{1n}},False{},True{},False{},1n} <> Nil{},Some{C.ComponentId{3n}},O.Eligible{O.OverlayHandle{3n}},1n,4n},B.Overlay{O.OverlayHandle{3n},overlay,T.OverlayGeometry{Some{T.Cells{2n}},0n,None{},T.TopLeft{},T.Forward{0n},T.Forward{0n},Some{T.Cells{0n}},Some{T.Cells{1n}},T.OverlayMargin{0n,0n,0n,0n}}} <> Nil{},B.Frame{"old" <> Nil{},B.OverlayBounds{O.OverlayHandle{9n},old,C.TuiMouseDispatchTarget{C.ComponentId{9n},T.Forward{0n},T.Forward{0n},3n,1n}} <> Nil{}},B.newRenderSchedule(),False{},False{},None{}}
    +before : String = displayed(base)
    visibleBase : B.TuiBase <- snapshot(base,journal,True{})
    made : B.ResultOf(B.PreparedFrame) <- B.renderRoot(visibleBase,8n,3n)
    +ready : B.PreparedFrame <- success(made)
    +stage : String = prepared(ready)
    +stillOld : String = stagedDisplayed(ready)
    +after : B.TuiBase = committed(ready)
    +published : String = displayed(after)
    releaseBase : B.TuiBase <- snapshot(after,journal,True{})
    release : B.ResultOf(B.InputResult) <- B.dispatchInput(releaseBase,a <> b <> overlay <> Nil{},C.ComponentId{1n} <> C.ComponentId{2n} <> Nil{},"\u{1b}[97;1:3u")
    +released : B.InputResult <- inputSuccess(release)
    +releaseText : String = inputText(released)
    pressBase : B.TuiBase <- snapshot(inputState(released),journal,True{})
    press : B.ResultOf(B.InputResult) <- B.dispatchInput(pressBase,a <> b <> overlay <> Nil{},C.ComponentId{1n} <> C.ComponentId{2n} <> Nil{},"a")
    +pressed : B.InputResult <- inputSuccess(press)
    +pressText : String = inputText(pressed)
    hiddenBase : B.TuiBase <- snapshot(inputState(pressed),journal,False{})
    hiddenMade : B.ResultOf(B.PreparedFrame) <- B.renderRoot(hiddenBase,8n,3n)
    +hiddenReady : B.PreparedFrame <- success(hiddenMade)
    +hiddenStage : String = prepared(hiddenReady)
    +hiddenStillOld : String = stagedDisplayed(hiddenReady)
    +hiddenCommitted : B.TuiBase = committed(hiddenReady)
    +hiddenPublished : String = displayed(hiddenCommitted)
    hiddenInputBase : B.TuiBase <- snapshot(hiddenCommitted,journal,False{})
    hidden : B.ResultOf(B.InputResult) <- B.dispatchInput(hiddenInputBase,a <> b <> overlay <> Nil{},C.ComponentId{1n} <> C.ComponentId{2n} <> Nil{},"b")
    +hiddenResult : B.InputResult <- inputSuccess(hidden)
    +hiddenText : String = inputText(hiddenResult)
    +entries : String <- Ref.dispose(String,journal)
    dispose(a)
    dispose(b)
    dispose(overlay)
    dispose(old)
    IO.print(before ++ "\u{1e}" ++ stillOld ++ "\u{1e}" ++ stage ++ "\u{1e}" ++ published ++ "\u{1e}" ++ releaseText ++ "\u{1e}" ++ pressText ++ "\u{1e}" ++ hiddenStillOld ++ "\u{1e}" ++ hiddenStage ++ "\u{1e}" ++ hiddenPublished ++ "\u{1e}" ++ hiddenText ++ "\u{1e}" ++ entries)
def main() -> IO(Unit): run()
