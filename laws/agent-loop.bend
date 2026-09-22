import Base
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/diagnostics.bend as Diagnostics
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F

# Tool execution mode: a single sequential tool or a sequential configuration
# makes the whole assistant batch sequential; otherwise it runs in parallel.

law configured_sequential_mode_wins:
  for -Parameters: Data
  for -Arguments: Data
  for -Details: Data
  for -RawArguments: Data
  for -Signal: Data
  for -ExecutionError: Data
  for calls: List<&2, Ai.ToolCall<RawArguments>>
  for tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>
  {Loop.selectToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools, Some{T.Sequential{}}) == T.Sequential{} : T.ToolExecutionMode}

law one_sequential_tool_forces_sequential_execution:
  for -Parameters: Data
  for -Arguments: Data
  for -Details: Data
  for -RawArguments: Data
  for -Signal: Data
  for -ExecutionError: Data
  for +calls: List<&2, Ai.ToolCall<RawArguments>>
  for +tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>
  for configured: Maybe<&2, T.ToolExecutionMode>
  for found: {Loop.hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools) == True{} : Bool}
  {Loop.selectToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools, configured) == T.Sequential{} : T.ToolExecutionMode}

law parallel_tools_run_in_parallel:
  for -Parameters: Data
  for -Arguments: Data
  for -Details: Data
  for -RawArguments: Data
  for -Signal: Data
  for -ExecutionError: Data
  for +calls: List<&2, Ai.ToolCall<RawArguments>>
  for +tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>
  for +configured: Maybe<&2, T.ToolExecutionMode>
  for none: {Loop.hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools) == False{} : Bool}
  for notSequential: {Loop.isSequential(configured) == False{} : Bool}
  {Loop.selectToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools, configured) == T.Parallel{} : T.ToolExecutionMode}

# Termination after a tool batch: every result must ask to terminate.

def terminating(-Arguments: Data, -Details: Data, outcome: Loop.FinalizedToolCallOutcome<Arguments, Details>) -> Loop.FinalizedToolCallOutcome<Arguments, Details>:
  match outcome:
    case Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, _}, isError}:
      Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, Some{True{}}}, isError}

def allTerminating(-Arguments: Data, -Details: Data, outcomes: List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>) -> List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>:
  match outcomes:
    case Nil{}: Nil{}
    case outcome <> rest: terminating(Arguments, Details, outcome) <> allTerminating(Arguments, Details, rest)

law an_empty_batch_terminates:
  for -Arguments: Data
  for -Details: Data
  {Loop.allTerminate(Arguments, Details, Nil{}) == True{} : Bool}

law terminating_results_terminate:
  for -Arguments: Data
  for -Details: Data
  for outcomes: List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>
  {Loop.allTerminate(Arguments, Details, allTerminating(Arguments, Details, outcomes)) == True{} : Bool}

law one_continuing_result_continues_the_run:
  for -Arguments: Data
  for -Details: Data
  for call: Ai.ToolCall<Arguments>
  for content: List<&2, Ai.TextImageContent>
  for details: Details
  for usage: Maybe<&2, Ai.Usage>
  for terminate: Maybe<&2, Bool>
  for isError: Bool
  for rest: List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>
  for continuing: {Maybe.default(&2, Bool, terminate, False{}) == False{} : Bool}
  {Loop.allTerminate(Arguments, Details, Loop.FinalizedToolCallOutcome{call, T.AgentToolResult{content, details, usage, terminate}, isError} <> rest) == False{} : Bool}

# The beforeToolCall hook decision.

law an_aborted_operation_rejects_the_call:
  for result: Maybe<&2, T.BeforeToolCallResult>
  {Loop.beforeToolCallDecision(True{}, result) == Loop.RejectToolCall{"Operation aborted", False{}} : Loop.BeforeToolCallDecision}

law without_a_hook_result_the_call_proceeds:
  {Loop.beforeToolCallDecision(False{}, None{}) == Loop.ProceedWithToolCall{} : Loop.BeforeToolCallDecision}

law a_non_blocking_hook_lets_the_call_proceed:
  for block: Maybe<&2, Bool>
  for reason: Maybe<&2, String>
  for terminate: Maybe<&2, Bool>
  for open: {Maybe.default(&2, Bool, block, False{}) == False{} : Bool}
  {Loop.beforeToolCallDecision(False{}, Some{T.BeforeToolCallResult{block, reason, terminate}}) == Loop.ProceedWithToolCall{} : Loop.BeforeToolCallDecision}

law a_blocking_hook_rejects_with_its_reason:
  for head: Char
  for tail: String
  for terminate: Maybe<&2, Bool>
  {Loop.beforeToolCallDecision(False{}, Some{T.BeforeToolCallResult{Some{True{}}, Some{SCon{head, tail}}, terminate}}) == Loop.RejectToolCall{SCon{head, tail}, Maybe.default(&2, Bool, terminate, False{})} : Loop.BeforeToolCallDecision}

law a_blocking_hook_without_a_reason_uses_the_default_message:
  for terminate: Maybe<&2, Bool>
  {Loop.beforeToolCallDecision(False{}, Some{T.BeforeToolCallResult{Some{True{}}, None{}, terminate}}) == Loop.RejectToolCall{"Tool execution was blocked", Maybe.default(&2, Bool, terminate, False{})} : Loop.BeforeToolCallDecision}

law a_blocking_hook_with_an_empty_reason_uses_the_default_message:
  for terminate: Maybe<&2, Bool>
  {Loop.beforeToolCallDecision(False{}, Some{T.BeforeToolCallResult{Some{True{}}, Some{""}, terminate}}) == Loop.RejectToolCall{"Tool execution was blocked", Maybe.default(&2, Bool, terminate, False{})} : Loop.BeforeToolCallDecision}

# Batch completion and the next turn.

law an_empty_batch_never_terminates:
  for -State: Data
  for -Message: Data
  for -Error: Data
  for state: State
  for allTerminate: Bool
  {Loop.finishBatch(State, Message, Error, state, Nil{}, allTerminate) == IO.pure(Result<&2, &2, Error, Loop.Batch<State, Message>>, Done{Loop.Batch{state, Nil{}, False{}}}) : IO(Result<&2, &2, Error, Loop.Batch<State, Message>>)}

law a_batch_terminates_only_when_every_call_opted_in:
  for -State: Data
  for -Message: Data
  for -Error: Data
  for state: State
  for message: Message
  for +rest: List<&2, Message>
  for allTerminate: Bool
  {Loop.finishBatch(State, Message, Error, state, message <> rest, allTerminate) == IO.pure(Result<&2, &2, Error, Loop.Batch<State, Message>>, Done{Loop.Batch{state, List.reverse(&2, Message, message <> rest), allTerminate}}) : IO(Result<&2, &2, Error, Loop.Batch<State, Message>>)}

law queued_messages_continue_the_run_without_ending_it:
  for -Parameters: Data
  for -Arguments: Data
  for -DiagnosticDetails: Data
  for -Details: Data
  for -Custom: Data
  for -Validated: Data
  for -Signal: Data
  for -Error: Data
  for completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>
  for sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>
  for head: T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>
  for tail: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>
  {Loop.followed(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, sink, Done{head <> tail}) == IO.pure(Result<&2, &2, Error, Loop.NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Loop.CompletionContinue{completed, head <> tail}}) : IO(Result<&2, &2, Error, Loop.NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>)}

law a_failed_queue_read_fails_the_turn:
  for -Parameters: Data
  for -Arguments: Data
  for -DiagnosticDetails: Data
  for -Details: Data
  for -Custom: Data
  for -Validated: Data
  for -Signal: Data
  for -Error: Data
  for completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>
  for sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>
  for error: Error
  {Loop.followed(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, sink, Fail{error}) == IO.pure(Result<&2, &2, Error, Loop.NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error}) : IO(Result<&2, &2, Error, Loop.NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>)}

def isLength(reason: Ai.StopReason) -> Bool:
  match reason:
    case Ai.Length{}: True{}
    case _: False{}

law only_length_stops_are_truncated:
  for -Arguments: Data
  for -DiagnosticDetails: Data
  for content: List<&2, Ai.AssistantContent<Arguments>>
  for api: String
  for provider: String
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for level: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<DiagnosticDetails>>>
  for usage: Ai.Usage
  for reason: Ai.StopReason
  for deferred: Maybe<&2, Ai.DeferredHandle>
  for error: Maybe<&2, String>
  for rawReason: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F.F64
  {Loop.lengthLimited(Arguments, DiagnosticDetails, Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}) == isLength(reason) : Bool}
