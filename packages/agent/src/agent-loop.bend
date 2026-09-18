import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as Number
import ../../ai/src/types.bend as Ai
import ../../runtime/src/utf16.bend as U

# Internal outcome records from upstream agent-loop.ts. The result is a shared
# object: an absent hook return preserves it, while any supplied override
# object causes the source's spread expression to allocate a new result.
type ExecutedToolCallOutcome<-Details: Data> is Data:
  ExecutedToolCallOutcome{result: R.Ref<T.AgentToolResult<Details>>, isError: Bool}

type FinalizedToolCallOutcome<-Arguments: Data, -Details: Data> is Data:
  FinalizedToolCallOutcome{toolCall: T.AgentToolCall(Arguments), result: R.Ref<T.AgentToolResult<Details>>, isError: Bool}

def choose(-Value: Data, original: Value, replacement: Maybe<&2, Value>) -> Value:
  match replacement:
    case None{}: original
    case Some{value}: value

def chooseOptional(-Value: Data, original: Maybe<&2, Value>, replacement: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match replacement:
    case None{}: original
    case Some{value}: Some{value}

# Details is the upstream unknown payload. Its runtime adapter supplies nullish
# classification; false, zero, empty text and empty objects must return false.
# None already represents omitted/undefined, so classification only runs for a
# supplied payload. This does not convert details to JSON or clone it.
def chooseDetails(-Details: Data, original: Details, replacement: Maybe<&2, Details>, isNullish: Details -> Bool) -> Details:
  match replacement:
    case None{}: original
    case Some{+value}: Bool.pick(Details, isNullish(value), original, value)

def mergeResult(-Details: Data, original: T.AgentToolResult<Details>, replacement: T.AfterToolCallResult<Details>, isNullish: Details -> Bool) -> T.AgentToolResult<Details> & Maybe<&2, Bool>:
  match original replacement:
    case T.AgentToolResult{content, details, usage, terminate} T.AfterToolCallResult{newContent, newDetails, newIsError, newUsage, newTerminate}:
      (T.AgentToolResult{choose(List<&2, Ai.TextImageContent>, content, newContent), chooseDetails(Details, details, newDetails, isNullish), chooseOptional(Ai.Usage, usage, newUsage), chooseOptional(Bool, terminate, newTerminate)}, newIsError)

def allocateMerged(-Details: Data, isError: Bool, merged: T.AgentToolResult<Details> & Maybe<&2, Bool>) -> IO(ExecutedToolCallOutcome<Details>):
  match merged:
    case Tuple{value, newIsError}:
      do IO<ExecutedToolCallOutcome<Details>>:
        result : R.Ref<T.AgentToolResult<Details>> <- R.new(T.AgentToolResult<Details>, value)
        return ExecutedToolCallOutcome{result, choose(Bool, isError, newIsError)}

# The merge portion of finalizeExecutedToolCall. Hook invocation, error catch,
# dynamic own-property spreading, emission and scheduling remain pending. The
# caller owns the original and any newly allocated result until aliases retire.
def applyAfterToolCallResult(-Details: Data, executed: ExecutedToolCallOutcome<Details>, replacement: Maybe<&2, T.AfterToolCallResult<Details>>, isNullish: Details -> Bool) -> IO(ExecutedToolCallOutcome<Details>):
  match executed replacement:
    case ExecutedToolCallOutcome{result, isError} None{}: IO.pure(ExecutedToolCallOutcome<Details>, ExecutedToolCallOutcome{result, isError})
    case ExecutedToolCallOutcome{result, isError} Some{patch}:
      do IO<ExecutedToolCallOutcome<Details>>:
        original : T.AgentToolResult<Details> <- R.read(T.AgentToolResult<Details>, result)
        allocateMerged(Details, isError, mergeResult(Details, original, patch, isNullish))

# Array.find uses the first matching definition, including a definition with
# no override. Keep shared tools live while scanning; do not build a last-wins
# name map or invoke preparation/execution callbacks during policy selection.
def lookupModeStep(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, name: String, tool: T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>) -> Maybe<&2, Maybe<&2, T.ToolExecutionMode>>:
  match tool:
    case T.AgentTool{toolName, _, _, _, _, _, _, _, mode}:
      Bool.pick(Maybe<&2, Maybe<&2, T.ToolExecutionMode>>, String.eq(U.normalize(name), U.normalize(toolName)), Some{mode}, None{})

def matchedMode(value: Maybe<&2, Maybe<&2, T.ToolExecutionMode>>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def extractedMode(value: Maybe<&2, Maybe<&2, T.ToolExecutionMode>>) -> Maybe<&2, T.ToolExecutionMode>:
  match value:
    case Some{mode}: mode
    case None{}: None{}

def chooseSearch(more: Bool, found: IO(Maybe<&2, T.ToolExecutionMode>), rest: IO(Maybe<&2, T.ToolExecutionMode>)) -> IO(Maybe<&2, T.ToolExecutionMode>):
  match more:
    case True{}: rest
    case False{}: found

def findToolExecutionMode(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, +name: String, tools: List<&2, R.Ref<T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>>) -> IO(Maybe<&2, T.ToolExecutionMode>):
  match tools:
    case Nil{}: IO.pure(Maybe<&2, T.ToolExecutionMode>, None{})
    case head <> tail:
      do IO<Maybe<&2, T.ToolExecutionMode>>:
        tool : T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError> <- R.read(T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>, head)
        +found : Maybe<&2, Maybe<&2, T.ToolExecutionMode>> = lookupModeStep(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, name, tool)
        searchMore : Bool = Bool.not(matchedMode(found))
        chooseSearch(searchMore, IO.pure(Maybe<&2, T.ToolExecutionMode>, extractedMode(found)), findToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, name, tail))

def isSequential(mode: Maybe<&2, T.ToolExecutionMode>) -> Bool:
  match mode:
    case Some{T.Sequential{}}: True{}
    case _: False{}

def callName(-RawArguments: Data, toolCall: Ai.ToolCall<RawArguments>) -> String:
  match toolCall:
    case Ai.ToolCall{_, name, _, _, _}: name

def chooseSequential(found: Bool, rest: IO(Bool)) -> IO(Bool):
  match found:
    case True{}: IO.pure(Bool, True{})
    case False{}: rest

def hasSequentialToolCall(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall(RawArguments)>, +tools: List<&2, R.Ref<T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>>) -> IO(Bool):
  match calls:
    case Nil{}: IO.pure(Bool, False{})
    case head <> tail:
      do IO<Bool>:
        toolCall : Ai.ToolCall<RawArguments> <- R.read(Ai.ToolCall<RawArguments>, head)
        mode : Maybe<&2, T.ToolExecutionMode> <- findToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, callName(RawArguments, toolCall), tools)
        chooseSequential(isSequential(mode), hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, tail, tools))

# Upstream computes the per-tool scan before checking the global setting. A
# single sequential override makes the entire assistant batch sequential.
def selectToolExecutionMode(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall(RawArguments)>, tools: List<&2, R.Ref<T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>>, configured: Maybe<&2, T.ToolExecutionMode>) -> IO(T.ToolExecutionMode):
  do IO<T.ToolExecutionMode>:
    found : Bool <- hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools)
    return Bool.pick(T.ToolExecutionMode, isSequential(configured) || found, T.Sequential{}, T.Parallel{})

def resultTerminates(-Details: Data, result: T.AgentToolResult<Details>) -> Bool:
  match result:
    case T.AgentToolResult{_, _, _, Some{True{}}}: True{}
    case _: False{}

def continueTermination(terminates: Bool, rest: IO(Bool)) -> IO(Bool):
  match terminates:
    case False{}: IO.pure(Bool, False{})
    case True{}: rest

def allTerminate(-Arguments: Data, -Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Arguments, Details>>) -> IO(Bool):
  match finalizedCalls:
    case Nil{}: IO.pure(Bool, True{})
    case FinalizedToolCallOutcome{_, result, _} <> tail:
      do IO<Bool>:
        value : T.AgentToolResult<Details> <- R.read(T.AgentToolResult<Details>, result)
        continueTermination(resultTerminates(Details, value), allTerminate(Arguments, Details, tail))

def shouldTerminateToolBatch(-Arguments: Data, -Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Arguments, Details>>) -> IO(Bool):
  match finalizedCalls:
    case Nil{}: IO.pure(Bool, False{})
    case +head <> +tail: allTerminate(Arguments, Details, head <> tail)

# Promise<void> | void becomes an awaited reusable IO callback. Recoverable
# listener failures are explicit; callers must propagate them without emitting
# later events. This does not establish host Promise microtask scheduling.
def AgentEventSink(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data) -> Data:
  C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>>

def toolExecutionEndEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, call: Ai.ToolCall<Arguments>, result: R.Ref<T.AgentToolResult<Details>>, isError: Bool) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, R.Ref<T.AgentToolResult<Details>>>:
  match call:
    case Ai.ToolCall{id, name, _, _, _}: T.ToolExecutionEnd{id, name, result, isError}

def emitToolExecutionEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ListenerError: Data, finalized: FinalizedToolCallOutcome<Arguments, Details>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, R.Ref<T.AgentToolResult<Details>>, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<Result<&2, &2, ListenerError, Unit>>:
        call : Ai.ToolCall<Arguments> <- R.read(Ai.ToolCall<Arguments>, toolCall)
        C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, R.Ref<T.AgentToolResult<Details>>>, Result<&2, &2, ListenerError, Unit>, emit, toolExecutionEndEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, call, result, isError))

def finishToolResultMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, toolResultMessage: R.Ref<Ai.ToolResultMessage<Details>>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError), started: Result<&2, &2, ListenerError, Unit>) -> IO(Result<&2, &2, ListenerError, Unit>):
  match started:
    case Fail{error}: IO.pure(Result<&2, &2, ListenerError, Unit>, Fail{error})
    case Done{Unit{}}: C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})

def emitToolResultMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, +toolResultMessage: R.Ref<Ai.ToolResultMessage<Details>>, +emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  do IO<Result<&2, &2, ListenerError, Unit>>:
    started : Result<&2, &2, ListenerError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageStart{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})
    finishToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError, toolResultMessage, emit, started)

# The canonical typed result always supplies content. Dynamic null/absent
# content normalization still belongs at the untyped runtime boundary.
def toolResultMessageAt(-Arguments: Data, -Details: Data, call: Ai.ToolCall<Arguments>, result: T.AgentToolResult<Details>, isError: Bool, timestamp: Number.F64) -> Ai.ToolResultMessage<Details>:
  match call result:
    case Ai.ToolCall{id, name, _, _, _} T.AgentToolResult{content, details, usage, _}:
      Ai.ToolResultMessage{id, name, content, Some{details}, usage, isError, timestamp}

# Date.now is read after projecting the finalized call/result, as upstream.
# The new message is owned by its caller; payload references stay shared.
def createToolResultMessage(-Arguments: Data, -Details: Data, finalized: FinalizedToolCallOutcome<Arguments, Details>) -> IO(R.Ref<Ai.ToolResultMessage<Details>>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<R.Ref<Ai.ToolResultMessage<Details>>>:
        call : Ai.ToolCall<Arguments> <- R.read(Ai.ToolCall<Arguments>, toolCall)
        value : T.AgentToolResult<Details> <- R.read(T.AgentToolResult<Details>, result)
        timestamp : Number.F64 <- Date.now()
        R.new(Ai.ToolResultMessage<Details>, toolResultMessageAt(Arguments, Details, call, value, isError, timestamp))
