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

# upstream test/terminal-colors.test.ts "TUI.queryTerminalBackgroundColor"
# through a real terminal (tests/tui_terminal_colors_check.py). A focused
# InputRecorder reports "input:<codepoints>", an input listener (all modes but
# "plain") reports "listener:<codepoints>" and passes input on, and the
# background query started once the TUI is ready reports
# "background:<r,g,b|none>". "q" stops the TUI. The argument is the mode:
# plain/listening (1000 ms timeout) or late (1 ms timeout).
type Mode is Data: Mode{listening: Bool,timeout: U32}
def codes(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{point},rest}: U32.show(point) ++ " " ++ codes(rest)
def render(unused: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"" <> Nil{})
def noInvalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def record(stop: Deferred.Deferred<Unit>,data: String) -> IO(Unit):
  do IO<Unit>:
    +key : String <- IO.pure(String,data)
    IO.print_err("input:" ++ codes(key))
    Bool.pick(Unit -> IO(Unit),String.eq(key,"q"),
      _ => do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{},
      _ => IO.pure(Unit,Unit{}))(Unit{})
def listen(unused: Unit,data: String) -> IO(Maybe<&2,Query.TuiInputListenerResult>):
  do IO<Maybe<&2,Query.TuiInputListenerResult>>:
    IO.print_err("listener:" ++ codes(data))
    return None{}
def color(value: Maybe<&2,Colors.RgbColor>) -> String:
  match value:
    case None{}: "none"
    case Some{Colors.RgbColor{r,g,b}}: U32.show(r) ++ "," ++ U32.show(g) ++ "," ++ U32.show(b)
def query(queries: Query.Handle,write: Callback.Callback<String,Unit>,timeout: U32) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2,Colors.RgbColor> <- Query.colorQuery(queries,write,timeout)
    IO.print_err("background:" ++ color(value))
def listened(+queries: Query.Handle,listening: Bool) -> IO(Unit):
  match listening:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        callback : Callback.Callback<String,Maybe<&2,Query.TuiInputListenerResult>> <- Callback.create(~Unit,~String,~Maybe<&2,Query.TuiInputListenerResult>,~listen,Unit{})
        id : Nat <- Query.addInputListener(queries,callback)
        return Unit{}
def ready(mode: Mode,value: Process.QueryReady) -> IO(Unit):
  match mode value:
    case Mode{listening,timeout} Process.QueryReady{+queries,_,write,_,_,_}:
      do IO<Unit>:
        listened(queries,listening)
        IO.spawn(Unit,query(queries,write,timeout))
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),component <> Nil{},Component.id(component) <> Nil{},Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Process.Main{Screen.initial()}},component <> Nil{},Component.id(component) <> Nil{})
def requireRun(value: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match value:
    case Done{Process.Active{_,_,_,None{},_,_}}: IO.print_err("done")
    case _: IO.die(Unit,1,"terminal colors process failed")
def mode(args: List<String>) -> Mode:
  match args:
    case "plain" <> _: Mode{False{},1000}
    case "late" <> _: Mode{True{},1}
    case _: Mode{True{},1000}
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Deferred.Deferred<Unit>,~String,~Unit,~record,stop)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    +readyCallback : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Mode,~Process.QueryReady,~Unit,~ready,mode(args))
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{1n},renderCallback,Some{inputCallback},None{},invalidateCallback,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithQueries(state,stop,False{},readyCallback)
    requireRun(result)
    Callback.dispose(Process.QueryReady,Unit,readyCallback)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,inputCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,stop)
    return Unit{}
