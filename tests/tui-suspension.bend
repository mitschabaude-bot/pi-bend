import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process
import ../packages/coding-agent/src/modes/interactive/external-editor.bend as Editor

type Edit is Data:
  Edit{text: Ref.Ref<String>,stopped: Deferred.Deferred<Unit>,suspension: Process.SuspensionHandle,command: String}
type Invocation is Data:
  Invocation{text: Ref.Ref<String>,command: String}
def noInvalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def render(text: Ref.Ref<String>,_: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    value : String <- Ref.read(String,text)
    return [value]
def edited(text: Ref.Ref<String>,result: Editor.ExternalEditorResult) -> IO(Unit):
  match result:
    case Editor.Failed{}: IO.print_err("editor:failed")
    case Editor.Complete{content}:
      do IO<Unit>:
        Ref.write(String,text,content)
        IO.print_err("editor:complete")
def invoke(environment: Invocation,_: Unit) -> IO(Unit):
  match environment:
    case Invocation{+text,command}:
      do IO<Unit>:
        content : String <- Ref.read(String,text)
        result : Editor.ExternalEditorResult <- Editor.editInExternalEditor(Editor.ExternalEditorOptions{command,content})
        edited(text,result)
def edit(environment: Edit,key: String) -> IO(Unit):
  match environment key:
    case Edit{text,_,suspension,command} "g":
      do IO<Unit>:
        operation : Callback.Callback<Unit,Unit> <- Callback.create(~Invocation,~Unit,~Unit,~invoke,Invocation{text,command})
        accepted : Bool <- Process.suspendWith(suspension,operation)
        IO.print_err("suspended:" ++ Bool.show(accepted))
    case Edit{_,stopped,_,_} "q":
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stopped,Unit{})
        return Unit{}
    case _ _: IO.pure(Unit,Unit{})
def ready(label: String,value: Process.QueryReady) -> IO(Unit):
  match value:
    case Process.QueryReady{_,_,_,request,_}:
      do IO<Unit>:
        Callback.call(Unit,Unit,request,Unit{})
        IO.print_err(label)
def stopping(suspension: Process.SuspensionHandle,_: Unit) -> IO(Unit):
  do IO<Unit>:
    pending : Bool <- Process.isSuspending(suspension)
    IO.print_err("stopping:" ++ Bool.show(pending))
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.id(component)],Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Process.Main{Screen.initial()}},[component],[Component.id(component)])
def requireRun(result: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match result:
    case Done{Process.Active{_,_,_,None{},_,_}}: IO.print_err("done")
    case _: IO.die(Unit,1,"suspendable process failed")
def run(command: String) -> IO(Unit):
  do IO<Unit>:
    +text : Ref.Ref<String> <- Ref.new(String,"before")
    +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +suspension : Process.SuspensionHandle <- Process.createSuspension()
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<String>,~Nat,~List<&2,String>,~render,text)
    +editCallback : Callback.Callback<String,Unit> <- Callback.create(~Edit,~String,~Unit,~edit,Edit{text,stopped,suspension,command})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    +first : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~String,~Process.QueryReady,~Unit,~ready,"ready")
    +resumed : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~String,~Process.QueryReady,~Unit,~ready,"resumed")
    +stop : Callback.Callback<Unit,Unit> <- Callback.create(~Process.SuspensionHandle,~Unit,~Unit,~stopping,suspension)
    initial : Process.Active <- prepare(Component.Component{Component.ComponentId{1n},renderCallback,Some{editCallback},None{},invalidate,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runSuspendable(initial,stopped,suspension,False{},first,resumed,stop)
    requireRun(result)
    Callback.dispose(Process.QueryReady,Unit,first)
    Callback.dispose(Process.QueryReady,Unit,resumed)
    Callback.dispose(Unit,Unit,stop)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,editCallback)
    Callback.dispose(Unit,Unit,invalidate)
    Deferred.dispose(Unit,stopped)
    Process.disposeSuspension(suspension)
    old : String <- Ref.dispose(String,text)
    return Unit{}
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case command <> Nil{}: run(command)
    case _: IO.die(Unit,1,"usage: EDITOR_COMMAND")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
