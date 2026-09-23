import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/terminal-colors.bend as Colors
import ../packages/tui/src/terminal-query.bend as Query
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process

def noInvalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def render(unused: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"hello" <> Nil{})
def edit(received: Deferred.Deferred<Unit>,key: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err("input:" ++ key)
    settled : Bool <- Deferred.resolve(Unit,received,Unit{})
    return Unit{}
def color(value: Maybe<&2,Colors.RgbColor>) -> String:
  match value:
    case None{}: "none"
    case Some{Colors.RgbColor{r,g,b}}: U32.show(r) ++ "," ++ U32.show(g) ++ "," ++ U32.show(b)
def scheme(value: Maybe<&2,Colors.TerminalColorScheme>) -> String:
  match value:
    case None{}: "none"
    case Some{Colors.Dark{}}: "dark"
    case Some{Colors.Light{}}: "light"
def queryReady(unused: Unit,value: Process.QueryReady) -> IO(Unit):
  match value:
    case Process.QueryReady{+queries,_,+write,requestRender}:
      do IO<Unit>:
        Query.setNotifications(queries,write,True{})
        first : Maybe<&2,Colors.RgbColor> <- Query.colorQuery(queries,write,1000)
        IO.print_err("background:" ++ color(first))
        malformed : Maybe<&2,Colors.RgbColor> <- Query.colorQuery(queries,write,1000)
        IO.print_err("malformed:" ++ color(malformed))
        report : Maybe<&2,Colors.TerminalColorScheme> <- Query.schemeQuery(queries,write,1000)
        IO.print_err("scheme:" ++ scheme(report))
        Callback.call(Unit,Unit,requestRender,Unit{})
        IO.print_err("redrawn")
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),component <> Nil{},Component.id(component) <> Nil{},Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Screen.initial()},component <> Nil{},Component.id(component) <> Nil{})
def requireRun(value: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match value:
    case Done{Process.Active{_,_,_,None{}}}: IO.print_err("done")
    case _: IO.die(Unit,1,"query process failed")
def main() -> IO(Unit):
  do IO<Unit>:
    +received : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +editCallback : Callback.Callback<String,Unit> <- Callback.create(~Deferred.Deferred<Unit>,~String,~Unit,~edit,received)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    +readyCallback : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Unit,~Process.QueryReady,~Unit,~queryReady,Unit{})
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{2n},renderCallback,Some{editCallback},None{},invalidateCallback,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithQueries(state,received,False{},readyCallback)
    requireRun(result)
    Callback.dispose(Process.QueryReady,Unit,readyCallback)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,editCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,received)
