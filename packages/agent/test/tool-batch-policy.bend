import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C

def ToolValue() -> Data: T.AgentTool<Unit, Unit, Unit, Unit, Unit, String>
def ExecuteInput() -> Data: T.ToolExecutionInput<Unit, Unit, Unit>
def ExecuteOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<Unit>>

type ToolSpec is Data:
  ToolSpec{name: String, mode: Maybe<&2, T.ToolExecutionMode>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def forbidden(unused: Unit, input: ExecuteInput()) -> IO(ExecuteOutput()):
  IO.die(ExecuteOutput(), 1, "policy selection must not execute tools")

def makeTools(specs: List<&2, ToolSpec>, +execute: C.Callback<ExecuteInput(), ExecuteOutput()>) -> IO(List<&2, R.Ref<ToolValue()>>):
  match specs:
    case Nil{}: IO.pure(List<&2, R.Ref<ToolValue()>>, Nil{})
    case ToolSpec{name, mode} <> tail:
      do IO<List<&2, R.Ref<ToolValue()>>>:
        tool : R.Ref<ToolValue()> <- R.new(ToolValue(), T.AgentTool{name, "description", Unit{}, None{}, "label", None{}, execute, None{}, mode})
        rest : List<&2, R.Ref<ToolValue()>> <- makeTools(tail, execute)
        return tool <> rest

def makeCalls(names: List<&2, String>) -> IO(List<&2, T.AgentToolCall(Unit)>):
  match names:
    case Nil{}: IO.pure(List<&2, T.AgentToolCall(Unit)>, Nil{})
    case name <> tail:
      do IO<List<&2, T.AgentToolCall(Unit)>>:
        call : T.AgentToolCall(Unit) <- R.new(Ai.ToolCall<Unit>, Ai.ToolCall{"id", name, Unit{}, None{}, None{}})
        rest : List<&2, T.AgentToolCall(Unit)> <- makeCalls(tail)
        return call <> rest

def disposeRefs(-Value: Data, refs: List<&2, R.Ref<Value>>) -> IO(Unit):
  match refs:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        previous : Value <- R.dispose(Value, head)
        disposeRefs(Value, tail)

def modeName(mode: T.ToolExecutionMode) -> String:
  match mode:
    case T.Sequential{}: "sequential"
    case T.Parallel{}: "parallel"

def mode(specs: List<&2, ToolSpec>, names: List<&2, String>, configured: Maybe<&2, T.ToolExecutionMode>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +execute : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~Unit, ~ExecuteInput(), ~ExecuteOutput(), ~forbidden, Unit{})
    +tools : List<&2, R.Ref<ToolValue()>> <- makeTools(specs, execute)
    +calls : List<&2, T.AgentToolCall(Unit)> <- makeCalls(names)
    actual : T.ToolExecutionMode <- Loop.selectToolExecutionMode(Unit, Unit, Unit, Unit, Unit, String, calls, tools, configured)
    assertion(String.eq(modeName(actual), expected), "tool batch mode differs from upstream")
    disposeRefs(Ai.ToolCall<Unit>, calls)
    disposeRefs(ToolValue(), tools)
    C.dispose(ExecuteInput(), ExecuteOutput(), execute)

def makeFinalized(values: List<&2, Maybe<&2, Bool>>, +call: T.AgentToolCall(Unit)) -> IO(List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>>):
  match values:
    case Nil{}: IO.pure(List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>>, Nil{})
    case terminate <> tail:
      do IO<List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>>>:
        result : R.Ref<T.AgentToolResult<Unit>> <- R.new(T.AgentToolResult<Unit>, T.AgentToolResult{Nil{}, Unit{}, None{}, terminate})
        rest : List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>> <- makeFinalized(tail, call)
        return Loop.FinalizedToolCallOutcome{call, result, False{}} <> rest

def disposeFinalized(values: List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case Loop.FinalizedToolCallOutcome{_, result, _} <> tail:
      do IO<Unit>:
        previous : T.AgentToolResult<Unit> <- R.dispose(T.AgentToolResult<Unit>, result)
        disposeFinalized(tail)

def termination(values: List<&2, Maybe<&2, Bool>>, expected: Bool) -> IO(Unit):
  do IO<Unit>:
    +call : T.AgentToolCall(Unit) <- R.new(Ai.ToolCall<Unit>, Ai.ToolCall{"id", "tool", Unit{}, None{}, None{}})
    +finalized : List<&2, Loop.FinalizedToolCallOutcome<Unit, Unit>> <- makeFinalized(values, call)
    actual : Bool <- Loop.shouldTerminateToolBatch(Unit, Unit, finalized)
    assertion(String.eq(Bool.show(actual), Bool.show(expected)), "batch termination differs from upstream")
    disposeFinalized(finalized)
    previous : Ai.ToolCall<Unit> <- R.dispose(Ai.ToolCall<Unit>, call)
    return Unit{}

# Policy is derived from current shared state, not frozen at tool registration.
def liveState() -> IO(Unit):
  do IO<Unit>:
    +execute : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~Unit, ~ExecuteInput(), ~ExecuteOutput(), ~forbidden, Unit{})
    +tool : R.Ref<ToolValue()> <- R.new(ToolValue(), T.AgentTool{"a", "description", Unit{}, None{}, "label", None{}, execute, None{}, None{}})
    +call : T.AgentToolCall(Unit) <- R.new(Ai.ToolCall<Unit>, Ai.ToolCall{"id", "a", Unit{}, None{}, None{}})
    before : T.ToolExecutionMode <- Loop.selectToolExecutionMode(Unit, Unit, Unit, Unit, Unit, String, call <> Nil{}, tool <> Nil{}, None{})
    assertion(String.eq(modeName(before), "parallel"), "initial tool mode must use parallel default")
    R.write(ToolValue(), tool, T.AgentTool{"a", "description", Unit{}, None{}, "label", None{}, execute, None{}, Some{T.Sequential{}}})
    changed : T.ToolExecutionMode <- Loop.selectToolExecutionMode(Unit, Unit, Unit, Unit, Unit, String, call <> Nil{}, tool <> Nil{}, None{})
    assertion(String.eq(modeName(changed), "sequential"), "policy must read current shared tool definition")
    R.write(Ai.ToolCall<Unit>, call, Ai.ToolCall{"id", "missing", Unit{}, None{}, None{}})
    missing : T.ToolExecutionMode <- Loop.selectToolExecutionMode(Unit, Unit, Unit, Unit, Unit, String, call <> Nil{}, tool <> Nil{}, None{})
    assertion(String.eq(modeName(missing), "parallel"), "policy must read current shared call name")
    +result : R.Ref<T.AgentToolResult<Unit>> <- R.new(T.AgentToolResult<Unit>, T.AgentToolResult{Nil{}, Unit{}, None{}, Some{True{}}})
    +outcome : Loop.FinalizedToolCallOutcome<Unit, Unit> = Loop.FinalizedToolCallOutcome{call, result, True{}}
    terminates : Bool <- Loop.shouldTerminateToolBatch(Unit, Unit, outcome <> Nil{})
    assertion(terminates, "error outcomes can still request termination")
    R.write(T.AgentToolResult<Unit>, result, T.AgentToolResult{Nil{}, Unit{}, None{}, Some{False{}}})
    continues : Bool <- Loop.shouldTerminateToolBatch(Unit, Unit, outcome <> Nil{})
    assertion(Bool.not(continues), "termination must read current shared finalized result")
    oldResult : T.AgentToolResult<Unit> <- R.dispose(T.AgentToolResult<Unit>, result)
    oldTool : ToolValue() <- R.dispose(ToolValue(), tool)
    oldCall : Ai.ToolCall<Unit> <- R.dispose(Ai.ToolCall<Unit>, call)
    C.dispose(ExecuteInput(), ExecuteOutput(), execute)
    IO.print("PASS policy reads live tool/call/result objects without executing tools")
