import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process

type Edit is Data: Edit{text: Ref.Ref<String>,received: Deferred.Deferred<Unit>}
def noInvalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def render(text: Ref.Ref<String>,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    value : String <- Ref.read(String,text)
    return value <> Nil{}
def edit(environment: Edit,key: String) -> IO(Unit):
  match environment:
    case Edit{text,received}:
      do IO<Unit>:
        Ref.write(String,text,"world")
        settled : Bool <- Deferred.resolve(Unit,received,Unit{})
        return Unit{}
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),component <> Nil{},Component.id(component) <> Nil{},Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Process.Main{Screen.initial()}},component <> Nil{},Component.id(component) <> Nil{})
def requireActive(value: Process.Active) -> IO(Unit):
  match value:
    case Process.Active{_,_,_,None{},_,_}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"TUI listener recorded an error")
def requireRun(value: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match value:
    case Done{state}: requireActive(state)
    case Fail{_}: IO.die(Unit,1,"terminal failed")
def main() -> IO(Unit):
  do IO<Unit>:
    +text : Ref.Ref<String> <- Ref.new(String,"hello")
    +received : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<String>,~Nat,~List<&2,String>,~render,text)
    +editCallback : Callback.Callback<String,Unit> <- Callback.create(~Edit,~String,~Unit,~edit,Edit{text,received})
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{1n},renderCallback,Some{editCallback},None{},invalidateCallback,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcess(state,received,False{})
    requireRun(result)
    IO.print_err("terminal input rendered two frames")
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,editCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,received)
    old : String <- Ref.dispose(String,text)
    return Unit{}
