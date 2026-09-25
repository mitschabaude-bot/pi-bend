import Base
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/coding-agent/src/core/agent-session-runtime.bend as SessionRuntime
import ../packages/coding-agent/src/modes/interactive/commands.bend as Commands
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Controller

# upstream test/interactive-mode-clone-command.test.ts (handleCloneCommand).
# The port's /clone is Controller.cloneLeaf over the session's leaf id: it
# calls the runtime host's fork callback and reports a command action, which
# the interactive run shows (ClonedSession as the "Cloned to new session"
# status, Notice as a status). Upstream's editor.setText("") and the absence
# of renderCurrentSessionState/requestRender are the interactive run's
# handling of those actions and are not observed here.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def positionName(position: SessionRuntime.ForkPosition) -> String:
  match position:
    case SessionRuntime.ForkBefore{}: "before"
    case SessionRuntime.ForkAt{}: "at"

def forked(calls: R.Ref<List<&2, String>>, request: SessionRuntime.ForkRequest) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match request:
    case SessionRuntime.ForkRequest{entry, position}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        R.modify(List<&2, String>, Unit, calls, old => (List.append(&2, String, old, [entry ++ " " ++ positionName(position)]), Unit{}))
        return Done{None{}}

def actionText(action: Commands.Action) -> String:
  match action:
    case Commands.ClonedSession{}: "cloned"
    case Commands.Notice{text}: "notice:" ++ text
    case Commands.CommandError{text}: "error:" ++ text
    case _: "other"

def observed(actions: R.Ref<List<&2, String>>, action: Commands.Action) -> IO(Unit):
  R.modify(List<&2, String>, Unit, actions, old => (List.append(&2, String, old, [actionText(action)]), Unit{}))

def run(leaf: Maybe<&2, String>) -> IO(String):
  do IO<String>:
    +calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +actions : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +fork : C.Callback<SessionRuntime.ForkRequest, Result<&2, &2, String, Maybe<&2, String>>> <- C.create(~R.Ref<List<&2, String>>, ~SessionRuntime.ForkRequest, ~Result<&2, &2, String, Maybe<&2, String>>, ~forked, calls)
    +observer : C.Callback<Commands.Action, Unit> <- C.create(~R.Ref<List<&2, String>>, ~Commands.Action, ~Unit, ~observed, actions)
    result : Result<&2, &2, String, Unit> <- Controller.cloneLeaf(fork, Some{observer}, leaf)
    C.dispose(SessionRuntime.ForkRequest, Result<&2, &2, String, Maybe<&2, String>>, fork)
    C.dispose(Commands.Action, Unit, observer)
    forks : List<&2, String> <- R.dispose(List<&2, String>, calls)
    shown : List<&2, String> <- R.dispose(List<&2, String>, actions)
    return String.join(forks, ",") ++ " | " ++ String.join(shown, ",")

def main() -> IO(Unit):
  do IO<Unit>:
    cloned : String <- run(Some{"leaf-123"})
    check(String.eq(cloned, "leaf-123 at | cloned"), "clones the current leaf into a new session")
    nothing : String <- run(None{})
    check(String.eq(nothing, " | notice:Nothing to clone yet"), "shows a status message when there is nothing to clone")
