import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./turn-update.bend as U
import ./message-events.bend as Test
import ../../runtime/src/ref.bend as R

def shown(value: Loop.BeforeToolCallDecision) -> String:
  match value:
    case Loop.ProceedWithToolCall{}: "proceed"
    case Loop.RejectToolCall{message, terminate}: message ++ "|" ++ U.boolean(terminate)

def run(aborted: Bool, present: Bool, block: Maybe<&2, Bool>, reason: Maybe<&2, String>, terminate: Maybe<&2, Bool>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +result : R.Ref<T.BeforeToolCallResult> <- R.new(T.BeforeToolCallResult, T.BeforeToolCallResult{block, reason, terminate})
    decision : Loop.BeforeToolCallDecision <- Loop.beforeToolCallDecision(aborted, U.selected(R.Ref<T.BeforeToolCallResult>, present, result))
    Test.assertion(String.eq(shown(decision), expected), "before-hook abort/block decision differs from upstream")
    previous : T.BeforeToolCallResult <- R.dispose(T.BeforeToolCallResult, result)
    return Unit{}

# The shared hook object is read at decision time, not when the hook is selected.
def live() -> IO(Unit):
  do IO<Unit>:
    +result : R.Ref<T.BeforeToolCallResult> <- R.new(T.BeforeToolCallResult, T.BeforeToolCallResult{None{}, None{}, None{}})
    R.write(T.BeforeToolCallResult, result, T.BeforeToolCallResult{Some{True{}}, Some{"changed"}, Some{True{}}})
    value : Loop.BeforeToolCallDecision <- Loop.beforeToolCallDecision(False{}, Some{result})
    Test.assertion(String.eq(shown(value), "changed|true"), "before-hook decision ignored live result changes")
    old : T.BeforeToolCallResult <- R.dispose(T.BeforeToolCallResult, result)
    return Unit{}
