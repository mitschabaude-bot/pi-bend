import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui.bend as Marker
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process

type Context is Data:
  Context{stop: Deferred.Deferred<Unit>,setter: Ref.Ref<Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>>,write: Ref.Ref<Maybe<&2,Callback.Callback<String,Unit>>>}
def ignored(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def rendered(_: Unit,_: Nat) -> IO(List<&2,String>):
  IO.pure(List<&2,String>,["live preferences " ++ Marker.CURSOR_MARKER()])
def ready(context: Context,value: Process.QueryReady) -> IO(Unit):
  match context value:
    case Context{_,setter,output} Process.QueryReady{_,_,writer,_,callback}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,setter,Some{callback})
        Ref.write(Maybe<&2,Callback.Callback<String,Unit>>,output,Some{writer})
        IO.print_err("ready")
def changed(callback: Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,key: String) -> IO(Unit):
  match callback key:
    case Some{+setter} "b":
      do IO<Unit>:
        Callback.call(Process.TerminalPreference,Unit,setter,Process.HardwareCursor{True{}})
        Callback.call(Process.TerminalPreference,Unit,setter,Process.ClearOnShrink{True{}})
        IO.print_err("changed")
    case Some{setter} "c": Callback.call(Process.TerminalPreference,Unit,setter,Process.ClearOnShrink{False{}})
    case Some{setter} "h": Callback.call(Process.TerminalPreference,Unit,setter,Process.HardwareCursor{False{}})
    case _ _: IO.pure(Unit,Unit{})
def returnedMarker(writer: Maybe<&2,Callback.Callback<String,Unit>>,key: String) -> IO(Unit):
  match writer key:
    case Some{output} "h": Callback.call(String,Unit,output,"hide-returned")
    case _ _: IO.pure(Unit,Unit{})
def edited(context: Context,key: String) -> IO(Unit):
  match context key:
    case Context{stop,_,_} "q":
      do IO<Unit>:
        resolved : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
    case Context{_,setter,write} key:
      do IO<Unit>:
        callback : Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,setter)
        +key : String = key
        changed(callback,key)
        writer : Maybe<&2,Callback.Callback<String,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<String,Unit>>,write)
        returnedMarker(writer,key)
def stopping(context: Context,_: Unit) -> IO(Unit):
  match context:
    case Context{_,setter,write}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,setter,None{})
        Ref.write(Maybe<&2,Callback.Callback<String,Unit>>,write,None{})
def result(value: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match value:
    case Done{Process.Active{Process.Session{Tui.TuiBase{_,_,_,_,_,True{},False{},_},_},_,_,None{},_,_}}:
      IO.print_err("preferences:cursor=true,clear=false")
    case _: IO.die(Unit,1,"live preference update failed")
def focused(value: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match value:
    case Done{base}: IO.pure(Tui.TuiBase,base)
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus failed")
def main() -> IO(Unit):
  do IO<Unit>:
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +setter : Ref.Ref<Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,None{})
    +write : Ref.Ref<Maybe<&2,Callback.Callback<String,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<String,Unit>>,None{})
    +context : Context = Context{stop,setter,write}
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~rendered,Unit{})
    +input : Callback.Callback<String,Unit> <- Callback.create(~Context,~String,~Unit,~edited,context)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignored,Unit{})
    +onReady : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Context,~Process.QueryReady,~Unit,~ready,context)
    +onStopping : Callback.Callback<Unit,Unit> <- Callback.create(~Context,~Unit,~Unit,~stopping,context)
    +component : Component.Component = Component.Component{Component.ComponentId{1n},render,Some{input},None{},invalidate,None{},False{}}
    selected : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.id(component)],Some{Component.id(component)})
    base : Tui.TuiBase <- focused(selected)
    outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{base,Process.Main{Screen.initial()}},[component],[Component.id(component)]),stop,False{},onReady,onStopping)
    result(outcome)
    Callback.dispose(Nat,List<&2,String>,render)
    Callback.dispose(String,Unit,input)
    Callback.dispose(Unit,Unit,invalidate)
    Callback.dispose(Process.QueryReady,Unit,onReady)
    Callback.dispose(Unit,Unit,onStopping)
    Deferred.dispose(Unit,stop)
    old : Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Process.TerminalPreference,Unit>>,setter)
    oldWriter : Maybe<&2,Callback.Callback<String,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<String,Unit>>,write)
    return Unit{}
