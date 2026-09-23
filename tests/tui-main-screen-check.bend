import Base
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui.bend as Tui
import ../packages/runtime/src/json.bend as Json

def event(value: Screen.Effect) -> String:
  match value:
    case Screen.Write{text}: Json.quote("W" ++ text)
    case Screen.Visibility{True{}}: "\"S\""
    case Screen.Visibility{False{}}: "\"H\""
type Scan is Data: Pending{stream: Screen.Stream} Ready{batch: Maybe<&2,Screen.Batch>}
@unsafe def events(scan: Scan,first: Bool,acc: String) -> String:
  match scan:
    case Pending{stream}: events(Ready{Screen.nextEffect(stream)},first,acc)
    case Ready{None{}}: acc
    case Ready{Some{Screen.Batch{effect,rest}}}:
      events(Pending{rest},False{},acc ++ Bool.pick(String,first,"",",") ++ event(effect))
def dimension(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "-1"
    case Some{value}: Nat.show(value)
def imageIds(ids: List<&2,U32>,first: Bool,acc: String) -> String:
  match ids:
    case Nil{}: acc
    case id <> rest: imageIds(rest,False{},acc ++ Bool.pick(String,first,"",",") ++ U32.show(id))
def stateLine(state: Screen.State) -> String:
  match state:
    case Screen.State{Screen.TuiMainScreenRenderState{lines,width,height,cursor,hardware,maximum,top},ids,count}:
      "[" ++ Nat.show(List.length(&2,String,lines)) ++ "," ++ dimension(width) ++ "," ++ dimension(height) ++ "," ++ Nat.show(cursor) ++ "," ++ Nat.show(hardware) ++ "," ++ Nat.show(maximum) ++ "," ++ Nat.show(top) ++ "," ++ Nat.show(count) ++ ",[" ++ imageIds(ids,True{},"") ++ "]]"
def stepResult(result: Result<&2,&2,Screen.RenderError,Screen.Plan>) -> IO(Screen.State):
  match result:
    case Fail{_}: IO.die(Screen.State,1,"main-screen render failed")
    case Done{Screen.Plan{+next,output,_}}:
      do IO<Screen.State>:
        IO.print("[" ++ events(Pending{output},True{},"") ++ "]")
        IO.print(stateLine(next))
        IO.pure(Screen.State,next)
def step(state: Screen.State,lines: List<&2,String>,width: Nat,height: Nat,options: Screen.Options) -> IO(Screen.State):
  stepResult(Screen.checkedPlan(state,Screen.Frame{Tui.applyLineResets(lines),None{},width,height},options))
def stepCursor(state: Screen.State,lines: List<&2,String>,width: Nat,height: Nat,row: Nat,col: Nat,show: Bool) -> IO(Screen.State):
  stepResult(Screen.checkedPlan(state,Screen.Frame{Tui.applyLineResets(lines),Some{Tui.CursorPosition{row,col}},width,height},Screen.Options{False{},False{},False{},show,False{}}))
def main() -> IO(Unit):
  do IO<Unit>:
    s1 : Screen.State <- step(Screen.initial(),"a" <> "b" <> Nil{},20n,5n,Screen.defaultOptions())
    s2 : Screen.State <- step(s1,"a" <> "c" <> Nil{},20n,5n,Screen.defaultOptions())
    s3 : Screen.State <- step(s2,"a" <> "c" <> "d" <> Nil{},20n,5n,Screen.defaultOptions())
    s4 : Screen.State <- step(s3,"a" <> Nil{},20n,5n,Screen.defaultOptions())
    s5 : Screen.State <- step(s4,"a" <> Nil{},21n,5n,Screen.defaultOptions())
    _ : Screen.State <- step(s5,"a" <> Nil{},21n,4n,Screen.Options{True{},False{},False{},False{},False{}})
    kitty : Screen.State <- step(Screen.initial(),"\u{1b}_Gi=7,r=2;abc\u{1b}\\" <> "" <> "tail" <> Nil{},20n,5n,Screen.defaultOptions())
    _ : Screen.State <- step(kitty,"plain" <> "" <> "tail" <> Nil{},20n,5n,Screen.defaultOptions())
    shrink1 : Screen.State <- step(Screen.initial(),"one" <> "two" <> "three" <> Nil{},20n,5n,Screen.Options{False{},True{},False{},False{},False{}})
    _ : Screen.State <- step(shrink1,"one" <> Nil{},20n,5n,Screen.Options{False{},True{},False{},False{},False{}})
    above1 : Screen.State <- step(Screen.initial(),"0" <> "1" <> "2" <> "3" <> "4" <> "5" <> Nil{},20n,3n,Screen.defaultOptions())
    above2 : Screen.State <- step(above1,"changed" <> "1" <> "2" <> "3" <> "4" <> "5" <> Nil{},20n,3n,Screen.defaultOptions())
    _ : Screen.State <- step(above2,"0" <> "1" <> Nil{},20n,3n,Screen.defaultOptions())
    scroll1 : Screen.State <- step(Screen.initial(),"0" <> "1" <> "2" <> "3" <> "4" <> Nil{},20n,5n,Screen.defaultOptions())
    _ : Screen.State <- step(scroll1,"0" <> "1" <> "2" <> "3" <> "\u{1b}_Gi=8,r=2;abc\u{1b}\\" <> "" <> Nil{},20n,5n,Screen.defaultOptions())
    marked1 : Screen.State <- stepCursor(Screen.initial(),"left" <> "tail" <> Nil{},20n,5n,0n,4n,False{})
    marked2 : Screen.State <- stepCursor(marked1,"left" <> "tail" <> Nil{},20n,5n,0n,4n,False{})
    marked3 : Screen.State <- stepCursor(marked2,"left" <> "tail" <> Nil{},20n,5n,1n,4n,False{})
    _ : Screen.State <- stepCursor(marked3,"left" <> "tail" <> Nil{},20n,5n,1n,4n,True{})
    middle1 : Screen.State <- step(Screen.initial(),"0" <> "1" <> "2" <> "3" <> Nil{},20n,5n,Screen.defaultOptions())
    middle2 : Screen.State <- step(middle1,"0" <> "X" <> "2" <> "3" <> Nil{},20n,5n,Screen.defaultOptions())
    middle3 : Screen.State <- step(middle2,"0" <> "X" <> "2" <> Nil{},20n,5n,Screen.defaultOptions())
    middle4 : Screen.State <- step(middle3,"0" <> "Y" <> Nil{},20n,5n,Screen.defaultOptions())
    _ : Screen.State <- step(middle4,"0" <> "Y" <> "2" <> "3" <> "4" <> "5" <> "6" <> Nil{},20n,3n,Screen.defaultOptions())
    ids1 : Screen.State <- step(Screen.initial(),"\u{1b}_Gi=1;abc\u{1b}\\" <> "\u{1b}_Gi=2;def\u{1b}\\" <> Nil{},20n,5n,Screen.defaultOptions())
    _ : Screen.State <- step(ids1,"plain" <> Nil{},21n,5n,Screen.defaultOptions())
    IO.pure(Unit,Unit{})
