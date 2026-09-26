import Base
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Control
import ../packages/coding-agent/src/modes/interactive/commands.bend as Commands
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/agent-session-runtime.bend as Host
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

# These observers stand at the UI boundary: only successful replacements may
# publish actions that clear the transcript or replace the editor's draft.
def actionName(action: Commands.Action) -> String:
  match action:
    case Commands.NewSessionStarted{}: "new"
    case Commands.ClonedSession{}: "clone"
    case Commands.CommandError{message}: "error:" ++ message
    case _: "unexpected"
def command(seen: Ref.Ref<List<&2,String>>,action: Commands.Action) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,seen,old => (actionName(action) <> old,Unit{}))
def selectionName(result: Control.SelectionResult) -> String:
  match result:
    case Control.Forked{Some{text}}: "fork:" ++ text
    case Control.Forked{None{}}: "fork:"
    case Control.SelectionFailed{message}: "error:" ++ message
    case _: "unexpected"
def selected(seen: Ref.Ref<List<&2,String>>,result: Control.SelectionResult) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,seen,old => (selectionName(result) <> old,Unit{}))
def checked(condition: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),condition,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def history(seen: Ref.Ref<List<&2,String>>,expected: String) -> IO(Unit):
  do IO<Unit>:
    values : List<&2,String> <- Ref.read(List<&2,String>,seen)
    checked(String.eq(String.join(List.reverse(&2,String,values),","),expected),"replacement notifications differ")
def stillPending(task: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match task:
    case Some{_}: IO.pure(Unit,Unit{})
    case None{}: IO.die(Unit,1,"cancelled new consumed the active prompt task")
def newSession(cancelled: Bool,_: Unit) -> IO(Result<&2,&2,String,Ctx.SessionChange>):
  IO.pure(Result<&2,&2,String,Ctx.SessionChange>,Done{Ctx.SessionChange{cancelled}})
def fork(cancelled: Bool,request: Host.ForkRequest) -> IO(Result<&2,&2,String,Host.ForkOutcome>):
  match request:
    case Host.ForkRequest{_,Host.ForkAt{}}: IO.pure(Result<&2,&2,String,Host.ForkOutcome>,Done{Host.ForkOutcome{cancelled,None{}}})
    case _: IO.die(Result<&2,&2,String,Host.ForkOutcome>,1,"clone must fork at the current leaf")
def main() -> IO(Unit):
  do IO<Unit>:
    +seen : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +commands : Callback.Callback<Commands.Action,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~Commands.Action,~Unit,~command,seen)
    +selections : Callback.Callback<Control.SelectionResult,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~Control.SelectionResult,~Unit,~selected,seen)
    +cancelNew : Callback.Callback<Unit,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Bool,~Unit,~Result<&2,&2,String,Ctx.SessionChange>,~newSession,True{})
    +cancelFork : Callback.Callback<Host.ForkRequest,Result<&2,&2,String,Host.ForkOutcome>> <- Callback.create(~Bool,~Host.ForkRequest,~Result<&2,&2,String,Host.ForkOutcome>,~fork,True{})
    +running : Ref.Ref<Bool> <- Ref.new(Bool,True{})
    +pending : Chan(Unit) <- Chan.new(Unit,1)
    +task : Ref.Ref<Maybe<&2,Chan(Unit)>> <- Ref.new(Maybe<&2,Chan(Unit)>,Some{pending})
    +run : Control.PromptRun = Control.PromptRun{running,task}
    newResult : Result<&2,&2,String,Unit> <- Control.performNew(cancelNew,Some{commands},run)
    cloneResult : Result<&2,&2,String,Unit> <- Control.cloneLeaf(cancelFork,Some{commands},Some{"leaf"})
    Control.forkCompleted(Some{selections},Done{Host.ForkOutcome{True{},Some{"must not replace draft"}}})
    history(seen,"")
    active : Bool <- Control.isRunning(run)
    checked(active,"cancelled new changed prompt state")
    retained : Maybe<&2,Chan(Unit)> <- Ref.read(Maybe<&2,Chan(Unit)>,task)
    stillPending(retained)
    # Completing the original prompt remains possible; successful replacement
    # must join it and consume its task before publishing the success action.
    sent : Bool <- Chan.send(Unit,pending,Unit{})
    Ref.requireSent(sent)
    Control.newCompleted(Some{commands},run,Done{Ctx.SessionChange{False{}}})
    Control.cloneCompleted(Some{commands},Done{Host.ForkOutcome{False{},None{}}})
    Control.forkCompleted(Some{selections},Done{Host.ForkOutcome{False{},Some{"selected draft"}}})
    Control.newCompleted(Some{commands},run,Fail{"new failed"})
    Control.cloneCompleted(Some{commands},Fail{"clone failed"})
    Control.forkCompleted(Some{selections},Fail{"fork failed"})
    history(seen,"new,clone,fork:selected draft,error:new failed,error:clone failed,error:fork failed")
    retiredTask : Maybe<&2,Chan(Unit)> <- Ref.dispose(Maybe<&2,Chan(Unit)>,task)
    retiredRun : Bool <- Ref.dispose(Bool,running)
    Callback.dispose(Unit,Result<&2,&2,String,Ctx.SessionChange>,cancelNew)
    Callback.dispose(Host.ForkRequest,Result<&2,&2,String,Host.ForkOutcome>,cancelFork)
    Callback.dispose(Commands.Action,Unit,commands)
    Callback.dispose(Control.SelectionResult,Unit,selections)
    retired : List<&2,String> <- Ref.dispose(List<&2,String>,seen)
    IO.print("cancelled replacements preserve prompt and UI; successful replacements and failures notify once")
