import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/serial-resource.bend as Serial
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
    return Process.active(Process.Session{tui,Screen.initial()},component <> Nil{},Component.id(component) <> Nil{})
def barrier(current: Process.Active) -> IO(Process.Active & Unit): IO.pure(Process.Active & Unit,(current,Unit{}))
def requireActive(value: Process.Active) -> IO(Unit):
  match value:
    case Process.Active{_,_,_,None{}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"TUI listener recorded an error")
def requireStop(value: Result<&2,&2,Terminal.Error,Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: IO.die(Unit,1,"terminal stop failed")
def runTerminal(pair: Terminal.ProcessTerminal & Terminal.Handle,stateOwner: Serial.Owner<Process.Active>,+stateHandle: Serial.Handle<Process.Active>,ready: Deferred.Deferred<Terminal.Handle>,received: Deferred.Deferred<Unit>) -> IO(Unit):
  match pair:
    case (terminal,+handle):
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Terminal.Handle,ready,handle)
        initial : Unit <- Serial.run(Process.Active,Unit,stateHandle,current => Process.resizeOperation(current,handle,False{}))
        Deferred.result(Unit,received)
        committed : Unit <- Serial.run(Process.Active,Unit,stateHandle,barrier)
        stopped : Result<&2,&2,Terminal.Error,Unit> <- Terminal.stop(terminal)
        state : Process.Active <- Serial.retire(Process.Active,stateOwner)
        requireActive(state)
        requireStop(stopped)
        IO.print_err("terminal input rendered two frames")
def started(result: Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal>,stateOwner: Serial.Owner<Process.Active>,stateHandle: Serial.Handle<Process.Active>,ready: Deferred.Deferred<Terminal.Handle>,received: Deferred.Deferred<Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"terminal start failed")
    case Done{terminal}: runTerminal(Terminal.borrow(terminal),stateOwner,stateHandle,ready,received)
def runLive(pair: Serial.Owner<Process.Active> & Serial.Handle<Process.Active>,+ready: Deferred.Deferred<Terminal.Handle>,received: Deferred.Deferred<Unit>) -> IO(Unit):
  match pair:
    case (stateOwner,+stateHandle):
      do IO<Unit>:
        +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Process.EventSink,~String,~Unit,~Process.onInput,Process.EventSink{stateHandle,ready,False{}})
        +resizeCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Process.EventSink,~Unit,~Unit,~Process.onResize,Process.EventSink{stateHandle,ready,False{}})
        result : Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal> <- Terminal.startProcess(inputCallback,resizeCallback)
        started(result,stateOwner,stateHandle,ready,received)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Unit,Unit,resizeCallback)
        Deferred.dispose(Terminal.Handle,ready)
def main() -> IO(Unit):
  do IO<Unit>:
    +text : Ref.Ref<String> <- Ref.new(String,"hello")
    +received : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<String>,~Nat,~List<&2,String>,~render,text)
    +editCallback : Callback.Callback<String,Unit> <- Callback.create(~Edit,~String,~Unit,~edit,Edit{text,received})
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{1n},renderCallback,Some{editCallback},None{},invalidateCallback,None{},False{}})
    owner : Serial.Owner<Process.Active> <- Serial.create(Process.Active,state)
    +ready : Deferred.Deferred<Terminal.Handle> <- Deferred.new(Terminal.Handle)
    runLive(Serial.borrow(Process.Active,owner),ready,received)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,editCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,received)
    old : String <- Ref.dispose(String,text)
    return Unit{}
