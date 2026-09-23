import Base
import ../packages/tui/src/tui-main-screen.bend as Screen

def verify(result: Result<&2,&2,Screen.RenderError,Screen.Plan>) -> IO(Unit):
  match result:
    case Fail{Screen.LineTooWide{Zero{},6n,5n}}: IO.print("preflight-ok")
    case _: IO.die(Unit,1,"expected pure width validation before output")
def changed(result: Result<&2,&2,Screen.RenderError,Screen.Plan>) -> IO(Unit):
  match result:
    case Done{Screen.Plan{state,_,_}}:
      verify(Screen.checkedPlan(state,Screen.Frame{"123456" <> Nil{},None{},5n,3n},Screen.defaultOptions()))
    case _: IO.die(Unit,1,"expected first render")
def main() -> IO(Unit):
  changed(Screen.checkedPlan(Screen.initial(),Screen.Frame{"ok" <> Nil{},None{},5n,3n},Screen.defaultOptions()))
