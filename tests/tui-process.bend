import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process

def noInput(unused: Unit,value: String) -> IO(Unit): IO.pure(Unit,Unit{})
def noResize(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def noInvalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def render(text: Ref.Ref<String>,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    value : String <- Ref.read(String,text)
    return value <> Nil{}
def requireDraw(result: Process.Draw) -> IO(Process.Session):
  match result:
    case Process.Drawn{session}: IO.pure(Process.Session,session)
    case Process.Rejected{_,_}: IO.die(Process.Session,1,"TUI frame rejected")
def runFrames(owner: Terminal.ProcessTerminal,+handle: Terminal.Handle,component: Component.Component,text: Ref.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    first : Process.Draw <- Process.draw(Process.Session{Tui.added(Tui.newTui(),component),Screen.initial()},handle,False{})
    session : Process.Session <- requireDraw(first)
    Ref.write(String,text,"world")
    second : Process.Draw <- Process.draw(session,handle,False{})
    session : Process.Session <- requireDraw(second)
    stopped : Result<&2,&2,Terminal.Error,Unit> <- Terminal.stop(owner)
    IO.print_err("two TUI frames committed")
def borrowed(pair: Terminal.ProcessTerminal & Terminal.Handle,component: Component.Component,text: Ref.Ref<String>) -> IO(Unit):
  match pair:
    case (owner,handle): runFrames(owner,handle,component,text)
def started(result: Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal>,component: Component.Component,text: Ref.Ref<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"terminal start failed")
    case Done{owner}: borrowed(Terminal.borrow(owner),component,text)
def main() -> IO(Unit):
  do IO<Unit>:
    +text : Ref.Ref<String> <- Ref.new(String,"hello")
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<String>,~Nat,~List<&2,String>,~render,text)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~noInput,Unit{})
    +resizeCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noResize,Unit{})
    result : Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal> <- Terminal.startProcess(inputCallback,resizeCallback)
    started(result,Component.Component{Component.ComponentId{1n},renderCallback,None{},None{},invalidateCallback,None{},False{}},text)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Callback.dispose(String,Unit,inputCallback)
    Callback.dispose(Unit,Unit,resizeCallback)
    old : String <- Ref.dispose(String,text)
    return Unit{}
