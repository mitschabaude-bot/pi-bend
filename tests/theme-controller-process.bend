import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/detection.bend as Detection
import ../packages/coding-agent/src/modes/interactive/theme/theme-controller.bend as Controller
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

type Signals is Data: Signals{observe: Deferred.Deferred<Unit>,stop: Deferred.Deferred<Unit>}
def noInvalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def render(unused: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"theme frame" <> Nil{})
def edit(signals: Signals,key: String) -> IO(Unit):
  match signals:
    case Signals{observe,stop}:
      Bool.pick(Unit -> IO(Unit),String.eq(key,"s"),
        _ => do IO<Unit>:
          settled : Bool <- Deferred.resolve(Unit,observe,Unit{})
          return Unit{},
        _ => do IO<Unit>:
          settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
          return Unit{})(Unit{})
def terminalTheme(theme: Detection.TerminalTheme) -> String:
  match theme:
    case Detection.Dark{}: "dark"
    case Detection.Light{}: "light"
def summarize(selection: Controller.Selection) -> String:
  match selection:
    case Controller.Selection{_,terminal,name,_,auto,persist,error}:
      name ++ ":" ++ terminalTheme(terminal) ++ ":" ++ Bool.show(auto) ++ ":" ++ Bool.show(persist) ++ ":" ++ Bool.show(Bool.not(Maybe.is_none(&2,Theme.LoadError,error)))
def started(result: Result<&2,&1,Theme.LoadError,Controller.Owner & Controller.Handle>,observe: Deferred.Deferred<Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"theme start failed")
    case Done{(owner,+handle)}:
      do IO<Unit>:
        before : Controller.Selection <- Controller.current(handle)
        IO.print_err("theme-initial:" ++ summarize(before))
        observed : Unit <- Deferred.result(Unit,observe)
        after : Controller.Selection <- Controller.current(handle)
        IO.print_err("theme-change:" ++ summarize(after))
        Controller.close(owner)
def ready(observe: Deferred.Deferred<Unit>,value: Process.QueryReady) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&1,Theme.LoadError,Controller.Owner & Controller.Handle> <- Controller.start(value,Some{"light/dark"},Some{"0;15"},"packages/coding-agent/src/modes/interactive/theme","tests",Color.TrueColor{})
    started(result,observe)
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),component <> Nil{},Component.id(component) <> Nil{},Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Screen.initial()},component <> Nil{},Component.id(component) <> Nil{})
def requireRun(result: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match result:
    case Done{Process.Active{_,_,_,None{},_,_}}: IO.print_err("done")
    case _: IO.die(Unit,1,"process failed")
def main() -> IO(Unit):
  do IO<Unit>:
    +observe : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +editCallback : Callback.Callback<String,Unit> <- Callback.create(~Signals,~String,~Unit,~edit,Signals{observe,stop})
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    +readyCallback : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Deferred.Deferred<Unit>,~Process.QueryReady,~Unit,~ready,observe)
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{3n},renderCallback,Some{editCallback},None{},invalidateCallback,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithQueries(state,stop,False{},readyCallback)
    requireRun(result)
    Callback.dispose(Process.QueryReady,Unit,readyCallback)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,editCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,observe)
    Deferred.dispose(Unit,stop)
