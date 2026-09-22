import Base
import ../laws/agent-loop.bend as Laws
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent-loop.bend as Loop
import ./absurd.bend as Absurd

def Laws.configured_sequential_mode_wins(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools): {==}

def or_true_is_sequential(configured: Bool) -> {Bool.pick(T.ToolExecutionMode, Bool.or(configured, True{}), T.Sequential{}, T.Parallel{}) == T.Sequential{} : T.ToolExecutionMode}:
  match configured:
    case True{}: {==}
    case False{}: {==}

def Laws.one_sequential_tool_forces_sequential_execution(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools, configured, found):
  %Equal.sym(Bool, Loop.hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools), True{}, found) : {Bool.pick(T.ToolExecutionMode, Bool.or(Loop.isSequential(configured), _), T.Sequential{}, T.Parallel{}) == T.Sequential{} : T.ToolExecutionMode}
  or_true_is_sequential(Loop.isSequential(configured))

def Laws.parallel_tools_run_in_parallel(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools, configured, none, notSequential):
  %Equal.sym(Bool, Loop.hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools), False{}, none) : {Bool.pick(T.ToolExecutionMode, Bool.or(Loop.isSequential(configured), _), T.Sequential{}, T.Parallel{}) == T.Parallel{} : T.ToolExecutionMode}
  %Equal.sym(Bool, Loop.isSequential(configured), False{}, notSequential) : {Bool.pick(T.ToolExecutionMode, Bool.or(_, False{}), T.Sequential{}, T.Parallel{}) == T.Parallel{} : T.ToolExecutionMode}
  {==}

def Laws.an_empty_batch_terminates(Arguments, Details): {==}

def Laws.terminating_results_terminate(Arguments, Details, outcomes):
  match outcomes:
    case Nil{}: {==}
    case Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, terminate}, isError} <> rest: Laws.terminating_results_terminate(Arguments, Details, rest)

def Laws.one_continuing_result_continues_the_run(Arguments, Details, call, content, details, usage, terminate, isError, rest, continuing):
  match terminate:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: Empty.absurd({Loop.allTerminate(Arguments, Details, Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, Some{True{}}}, isError} <> rest) == False{} : Bool}, Absurd.true_is_not_false(continuing))

def Laws.an_aborted_operation_rejects_the_call(result): {==}

def Laws.without_a_hook_result_the_call_proceeds(): {==}

def Laws.a_non_blocking_hook_lets_the_call_proceed(block, reason, terminate, open):
  match block:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: Empty.absurd({Loop.beforeToolCallDecision(False{}, Some{T.BeforeToolCallResult{Some{True{}}, reason, terminate}}) == Loop.ProceedWithToolCall{} : Loop.BeforeToolCallDecision}, Absurd.true_is_not_false(open))

def Laws.a_blocking_hook_rejects_with_its_reason(head, tail, terminate):
  match terminate:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: {==}

def Laws.a_blocking_hook_without_a_reason_uses_the_default_message(terminate):
  match terminate:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: {==}

def Laws.a_blocking_hook_with_an_empty_reason_uses_the_default_message(terminate):
  match terminate:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: {==}
