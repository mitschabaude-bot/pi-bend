import Base
import ../laws/agent-loop.bend as Laws
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/ai/src/types.bend as Ai
import ./absurd.bend as Absurd
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch

def Laws.configured_sequential_mode_wins(Details, ExecutionError, calls, tools): {==}

def or_true_is_sequential(configured: Bool) -> {Bool.pick(T.ToolExecutionMode, Bool.or(configured, True{}), T.Sequential{}, T.Parallel{}) == T.Sequential{} : T.ToolExecutionMode}:
  match configured:
    case True{}: {==}
    case False{}: {==}

def Laws.one_sequential_tool_forces_sequential_execution(Details, ExecutionError, calls, tools, configured, found):
  %Equal.sym(Bool, Loop.hasSequentialToolCall(Details, ExecutionError, calls, tools), True{}, found) : {Bool.pick(T.ToolExecutionMode, Bool.or(Loop.isSequential(configured), _), T.Sequential{}, T.Parallel{}) == T.Sequential{} : T.ToolExecutionMode}
  or_true_is_sequential(Loop.isSequential(configured))

def Laws.parallel_tools_run_in_parallel(Details, ExecutionError, calls, tools, configured, none, notSequential):
  %Equal.sym(Bool, Loop.hasSequentialToolCall(Details, ExecutionError, calls, tools), False{}, none) : {Bool.pick(T.ToolExecutionMode, Bool.or(Loop.isSequential(configured), _), T.Sequential{}, T.Parallel{}) == T.Parallel{} : T.ToolExecutionMode}
  %Equal.sym(Bool, Loop.isSequential(configured), False{}, notSequential) : {Bool.pick(T.ToolExecutionMode, Bool.or(_, False{}), T.Sequential{}, T.Parallel{}) == T.Parallel{} : T.ToolExecutionMode}
  {==}

def Laws.an_empty_batch_terminates(Details): {==}

def Laws.terminating_results_terminate(Details, outcomes):
  match outcomes:
    case Nil{}: {==}
    case Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, terminate}, isError} <> rest: Laws.terminating_results_terminate(Details, rest)

def Laws.one_continuing_result_continues_the_run(Details, call, content, details, usage, terminate, isError, rest, continuing):
  match terminate:
    case None{}: {==}
    case Some{False{}}: {==}
    case Some{True{}}: Empty.absurd({Loop.allTerminate(Details, Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, Some{True{}}}, isError} <> rest) == False{} : Bool}, Absurd.true_is_not_false(continuing))

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

def Laws.an_empty_batch_never_terminates(State, Message, Error, state, allTerminate): {==}

def Laws.a_batch_terminates_only_when_every_call_opted_in(State, Message, Error, state, message, rest, allTerminate):
  match allTerminate:
    case True{}: {==}
    case False{}: {==}

def Laws.queued_messages_continue_the_run_without_ending_it(DiagnosticDetails, Details, Custom, Error, completed, sink, explicit, head, tail):
  match explicit:
    case True{}: {==}
    case False{}: {==}

def Laws.a_failed_queue_read_fails_the_turn(DiagnosticDetails, Details, Custom, Error, completed, sink, explicit, error):
  match explicit:
    case True{}: {==}
    case False{}: {==}

def Laws.an_explicit_continuation_without_queued_messages_continues_on_the_current_context(DiagnosticDetails, Details, Custom, Error, completed, sink): {==}

def Laws.only_length_stops_are_truncated(DiagnosticDetails, content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp):
  match reason:
    case Ai.Pending{}: {==}
    case Ai.Stop{}: {==}
    case Ai.Length{}: {==}
    case Ai.ToolUse{}: {==}
    case Ai.Error{}: {==}
    case Ai.Aborted{}: {==}
    case Ai.Deferred{}: {==}

def Laws.a_failed_open_has_nothing_to_release(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, context, emit, error): {==}

def Laws.an_earlier_failure_survives_the_release(DiagnosticDetails, ExecutionError, error, cleanup):
  match cleanup:
    case Done{unit}: {==}
    case Fail{failure}: {==}

def Laws.a_release_failure_fails_a_consumed_response(DiagnosticDetails, ExecutionError, message, error): {==}

def Laws.a_clean_release_keeps_the_message(DiagnosticDetails, ExecutionError, message): {==}
