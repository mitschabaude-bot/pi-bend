import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as Schema

def ToolValue() -> Data: T.AgentTool<Unit, String>
def ExecuteInput() -> Data: T.ToolExecutionInput<Unit>
def ExecuteOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<Unit>>

type ToolSpec is Data:
  ToolSpec{name: String, mode: Maybe<&2, T.ToolExecutionMode>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def forbidden(unused: Unit, input: ExecuteInput()) -> IO(ExecuteOutput()):
  IO.die(ExecuteOutput(), 1, "policy selection must not execute tools")

def makeTools(specs: List<&2, ToolSpec>, +execute: C.Callback<ExecuteInput(), ExecuteOutput()>) -> IO(List<&2, ToolValue()>):
  match specs:
    case Nil{}: IO.pure(List<&2, ToolValue()>, Nil{})
    case ToolSpec{name, mode} <> tail:
      do IO<List<&2, ToolValue()>>:
        tool : ToolValue() <- IO.pure(ToolValue(), T.AgentTool{name, "description", Schema.Null{}, None{}, "label", None{}, execute, None{}, mode})
        rest : List<&2, ToolValue()> <- makeTools(tail, execute)
        return tool <> rest

def makeCalls(names: List<&2, String>) -> IO(List<&2, T.AgentToolCall>):
  match names:
    case Nil{}: IO.pure(List<&2, T.AgentToolCall>, Nil{})
    case name <> tail:
      do IO<List<&2, T.AgentToolCall>>:
        call : T.AgentToolCall = Ai.ToolCall{"id", name, Schema.Null{}, None{}, None{}}
        rest : List<&2, T.AgentToolCall> <- makeCalls(tail)
        return call <> rest

def modeName(mode: T.ToolExecutionMode) -> String:
  match mode:
    case T.Sequential{}: "sequential"
    case T.Parallel{}: "parallel"

def mode(specs: List<&2, ToolSpec>, names: List<&2, String>, configured: Maybe<&2, T.ToolExecutionMode>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +execute : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~Unit, ~ExecuteInput(), ~ExecuteOutput(), ~forbidden, Unit{})
    +tools : List<&2, ToolValue()> <- makeTools(specs, execute)
    +calls : List<&2, T.AgentToolCall> <- makeCalls(names)
    actual : T.ToolExecutionMode = Loop.selectToolExecutionMode(Unit, String, calls, tools, configured)
    assertion(String.eq(modeName(actual), expected), "tool batch mode differs from upstream")
    C.dispose(ExecuteInput(), ExecuteOutput(), execute)

def makeFinalized(values: List<&2, Maybe<&2, Bool>>, +call: T.AgentToolCall) -> IO(List<&2, Loop.FinalizedToolCallOutcome<Unit>>):
  match values:
    case Nil{}: IO.pure(List<&2, Loop.FinalizedToolCallOutcome<Unit>>, Nil{})
    case terminate <> tail:
      do IO<List<&2, Loop.FinalizedToolCallOutcome<Unit>>>:
        result : T.AgentToolResult<Unit> = T.AgentToolResult{Nil{}, Some{Unit{}}, None{}, terminate}
        rest : List<&2, Loop.FinalizedToolCallOutcome<Unit>> <- makeFinalized(tail, call)
        return Loop.FinalizedToolCallOutcome{call, result, False{}} <> rest

def termination(values: List<&2, Maybe<&2, Bool>>, expected: Bool) -> IO(Unit):
  do IO<Unit>:
    +call : T.AgentToolCall = Ai.ToolCall{"id", "tool", Schema.Null{}, None{}, None{}}
    +finalized : List<&2, Loop.FinalizedToolCallOutcome<Unit>> <- makeFinalized(values, call)
    actual : Bool = Loop.shouldTerminateToolBatch(Unit, finalized)
    assertion(String.eq(Bool.show(actual), Bool.show(expected)), "batch termination differs from upstream")
    previous : Ai.ToolCall<Schema.Value> = call
    return Unit{}
