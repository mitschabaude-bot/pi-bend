import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R
import ../../runtime/src/record.bend as Record
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as Number
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/transcript.bend as Transcript
import ../../ai/src/utils/event-stream.bend as Stream
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

# Raw and adapter-output argument types may differ. This explicit union retains
# the original call handle when unchanged, without an unsafe reference cast.
# Neither branch means that schema validation has happened yet.
type PreparedToolCallArguments<-RawArguments: Data, -Arguments: Data> is Data:
  OriginalCall{value: T.AgentToolCall(RawArguments)}
  ReplacedCall{value: T.AgentToolCall(Arguments)}

def callArguments(-RawArguments: Data, call: Ai.ToolCall<RawArguments>) -> RawArguments:
  match call:
    case Ai.ToolCall{_, _, arguments, _, _}: arguments

def replaceCallArguments(-RawArguments: Data, -Arguments: Data, call: Ai.ToolCall<RawArguments>, arguments: Arguments) -> Ai.ToolCall<Arguments>:
  match call:
    case Ai.ToolCall{id, name, _, signature, namespace}: Ai.ToolCall{id, name, arguments, signature, namespace}

def preparedCall(-RawArguments: Data, -Arguments: Data, -ExecutionError: Data, original: T.AgentToolCall(RawArguments), current: Ai.ToolCall<RawArguments>, arguments: Arguments, same: Bool) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match same:
    case True{}: IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>, Done{OriginalCall{original}})
    case False{}:
      do IO<Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>>:
        replacement : T.AgentToolCall(Arguments) <- R.new(Ai.ToolCall<Arguments>, replaceCallArguments(RawArguments, Arguments, current, arguments))
        return Done{ReplacedCall{replacement}}

# Compare against the call's arguments AFTER the adapter returns. Adapters can
# mutate their captured call; replacement metadata also comes from this live
# post-callback state. Strict equality is supplied by the typed value adapter.
def afterPrepareArguments(-RawArguments: Data, -Arguments: Data, -ExecutionError: Data, +original: T.AgentToolCall(RawArguments), outcome: Result<&2, &2, ExecutionError, Arguments>, sameArguments: Arguments -> RawArguments -> Bool) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>, Fail{error})
    case Done{+arguments}:
      do IO<Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>>:
        +current : Ai.ToolCall<RawArguments> <- R.read(Ai.ToolCall<RawArguments>, original)
        preparedCall(RawArguments, Arguments, ExecutionError, original, current, arguments, sameArguments(arguments, callArguments(RawArguments, current)))

def prepareArgumentsWith(-RawArguments: Data, -Arguments: Data, -ExecutionError: Data, callback: Maybe<&2, C.Callback<RawArguments, Result<&2, &2, ExecutionError, Arguments>>>, +toolCall: T.AgentToolCall(RawArguments), sameArguments: Arguments -> RawArguments -> Bool) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>, Done{OriginalCall{toolCall}})
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>>:
        current : Ai.ToolCall<RawArguments> <- R.read(Ai.ToolCall<RawArguments>, toolCall)
        outcome : Result<&2, &2, ExecutionError, Arguments> <- C.call(RawArguments, Result<&2, &2, ExecutionError, Arguments>, prepare, callArguments(RawArguments, current))
        afterPrepareArguments(RawArguments, Arguments, ExecutionError, toolCall, outcome, sameArguments)

def prepareToolCallArguments(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, tool: T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>, toolCall: T.AgentToolCall(RawArguments), sameArguments: Arguments -> RawArguments -> Bool) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match tool:
    case T.AgentTool{_, _, _, _, _, prepare, _, _, _}: prepareArgumentsWith(RawArguments, Arguments, ExecutionError, prepare, toolCall, sameArguments)

# Initialization shared by prompt/continuation runs: copy the top-level message
# array, retain its message objects and the optional executable-tools array.
# Dynamic extra context properties are outside the current typed record.
def copyContextMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>, initialMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>>):
  match context:
    case T.AgentContext{messages, tools}:
      do IO<R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>>>:
        previous : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>> <- R.read(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, messages)
        copied : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, Details, Custom) <- R.new(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, previous, initialMessages))
        R.new(T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>, T.AgentContext{copied, tools})

# Only omission preserves prior reasoning; explicit off removes the provider
# field. This is the next-turn update rule, not model thinking-level clamping.
def turnReasoning(previous: Maybe<&2, Ai.ThinkingLevel>, requested: Maybe<&2, T.ThinkingLevel()>) -> Maybe<&2, Ai.ThinkingLevel>:
  match requested:
    case None{}: previous
    case Some{Ai.Off{}}: None{}
    case Some{Ai.Thinking{level}}: Some{level}

def withTurnConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, replacementModel: Maybe<&2, R.Ref<Ai.Model<Value>>>, requestedThinking: Maybe<&2, T.ThinkingLevel()>) -> T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match config:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, turnReasoning(reasoning, requestedThinking), deferred, thinkingBudgets, choose(R.Ref<Ai.Model<Value>>, model, replacementModel), convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

type PreparedTurnState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  PreparedTurnState{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}

def preparedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, supplied: Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> IO(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)):
  match supplied:
    case Some{messages}: IO.pure(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), messages)
    case None{}: R.new(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, Nil{})

def applyTurnSnapshot(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, currentContext: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, snapshot: T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>) -> IO(PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>):
  match snapshot:
    case T.AgentLoopTurnUpdate{context, messages, model, thinkingLevel}:
      do IO<PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>:
        prepared : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom) <- preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, messages)
        previous : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
        next : R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>> <- R.new(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, withTurnConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, previous, model, thinkingLevel))
        return PreparedTurnState{choose(R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, currentContext, context), next, prepared}

# Absent update retains config/context identity. Any supplied update object,
# even an empty one, causes the source's config spread to allocate a new object.
# Returned empty message arrays and replacement configs are caller-owned; all
# supplied context/model/message/callback handles retain their original owners.
def applyTurnUpdate(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, update: Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>) -> IO(PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>):
  match update:
    case None{}:
      do IO<PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>:
        messages : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom) <- preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, None{})
        return PreparedTurnState{context, config, messages}
    case Some{value}:
      do IO<PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>:
        snapshot : T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value> <- R.read(T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>, value)
        applyTurnSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, snapshot)

def afterPrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, Fail{error})
    case Done{update}:
      do IO<Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
        state : PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- applyTurnUpdate(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, update)
        return Done{state}

def invokePrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, completed: R.Ref<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)>, callback: Maybe<&2, C.Callback<R.Ref<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)>, Result<&2, &2, ExecutionError, Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>>>) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  match callback:
    case None{}: afterPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, Done{None{}})
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>> <- C.call(R.Ref<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)>, Result<&2, &2, ExecutionError, Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>, prepare, completed)
        afterPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, outcome)

def selectedPrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, value: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<R.Ref<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)>, Result<&2, &2, ExecutionError, Maybe<&2, R.Ref<T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>>>:
  match value:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, callback, _, _, _, _, _}: callback

# Called only for a completed turn. Await the hook before reading its update
# and the current configuration for replacement. Failures leave callback-side
# mutations visible and propagate before allocating update-owned state. Queue
# polling, turn-start emission and host Promise scheduling remain separate.
def prepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, +config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, completed: R.Ref<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)>) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
    value : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    invokePrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, completed, selectedPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, value))

# Queue callbacks return shared message arrays. An absent callback allocates a
# caller-owned empty array; supplied arrays and recoverable errors pass through.
def readQueuedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, callback: Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  match callback:
    case Some{selected}: C.call(Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, selected, Unit{})
    case None{}:
      do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
        empty : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom) <- preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, None{})
        return Done{empty}

def selectedSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _}: selected

def pollSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    readQueuedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedSteeringMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

def selectedFollowUpMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _}: selected

def pollFollowUpMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    readQueuedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedFollowUpMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

# After preparation, only repoll steering when the previous array is empty.
# A retained pending message must not consume a second one-at-a-time delivery.
# Read its live contents before selecting the current configuration callback.
def repollSteeringContents(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, pending: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), contents: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  match contents:
    case Nil{}: pollSteeringMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
    case _ <> _: IO.pure(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, Done{pending})

def repollSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, +pending: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    contents : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>> <- R.read(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, pending)
    repollSteeringContents(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, pending, contents)

# A missing stop hook is false. Recoverable hook errors are not stop requests.
def invokeShouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, completed: R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, callback: Maybe<&2, C.Callback<R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, Result<&2, &2, ExecutionError, Bool>>>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case Some{selected}: C.call(R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, Result<&2, &2, ExecutionError, Bool>, selected, completed)

def selectedShouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, Result<&2, &2, ExecutionError, Bool>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, callback, _, _, _, _, _, _}: callback

def shouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, completed: R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  do IO<Result<&2, &2, ExecutionError, Bool>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    invokeShouldStopAfterTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, completed, selectedShouldStopAfterTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

def stoppedTurnResult(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{None{}}

def queuedTurnResult(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, queued: Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
  match queued:
    case Fail{error}: Fail{error}
    case Done{messages}: Done{Some{messages}}

def afterTurnDecision(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, newMessages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), decision: Result<&2, &2, ExecutionError, Bool>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>):
  match decision:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>, Fail{error})
    case Done{True{}}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.AgentEnd{newMessages})
        return stoppedTurnResult(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, emitted)
    case Done{False{}}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
        queued : Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)> <- pollSteeringMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
        return queuedTurnResult(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, queued)

# The runLoop block after turn_end and completed-context construction. None
# means agent_end settled; Some supplies pending steering to the inner loop.
# Hook/emit errors skip polling. Retain the original local newMessages array
# for agent_end even if the callback replaces fields on completed.
def finishCompletedTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, completed: R.Ref<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, newMessages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
    decision : Result<&2, &2, ExecutionError, Bool> <- shouldStopAfterTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, completed)
    afterTurnDecision(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult, config, newMessages, emit, decision)

def contextMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>) -> T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom):
  match context:
    case T.AgentContext{messages, _}: messages

def invokeContextTransform(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -Signal: Data, -ExecutionError: Data, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), signal: Maybe<&2, Signal>, callback: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Signal>, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, Done{messages})
    case Some{selected}: C.call(T.TransformContextInput<T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Signal>, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, selected, T.TransformContextInput{messages, signal})

def selectedContextTransform(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Signal>, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _, _}: selected

def selectedMessageConverter(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> C.Callback<T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _, _, _}: selected

def convertTransformedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, transformed: Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> IO(Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>):
  match transformed:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>, Fail{error})
    case Done{messages}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>>:
        current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
        C.call(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>, selectedMessageConverter(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current), messages)

# The transform/conversion prefix of streamAssistantResponse. Capture the
# context's original message array before transformation. Read the converter
# after awaiting transformation so callback-side config changes remain visible.
# Both arrays are caller-owned; normalization/provider dispatch follow later.
def convertContextMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, +config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, signal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>):
  do IO<Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>>:
    captured : T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError> <- R.read(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, context)
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    transformed : Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)> <- invokeContextTransform(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, Signal, ExecutionError, contextMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, captured), signal, selectedContextTransform(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))
    convertTransformedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, transformed)

def selectedApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, String>:
  match config:
    case T.AgentLoopConfig{_, _, selected, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: selected

def selectedApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _}: selected

def selectedRequestModel(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> R.Ref<Ai.Model<Value>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _, _, _, _}: selected

def requestModelProvider(-Value: Data, model: Ai.Model<Value>) -> String:
  match model:
    case Ai.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _}: provider

# Source uses logical OR, so an empty resolved key falls back just like absence.
# The fallback itself is returned unchanged, including an empty string.
def hasResolvedApiKey(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{key}: Bool.not(String.eq(key, ""))

def fallbackApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    return Done{selectedApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current)}

def selectResolvedApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, resolved: Maybe<&2, String>, present: Bool) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  match present:
    case True{}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, Done{resolved})
    case False{}: fallbackApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)

def afterApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, Fail{error})
    case Done{+key}: selectResolvedApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, key, hasResolvedApiKey(key))

def invokeApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, model: R.Ref<Ai.Model<Value>>, callback: Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  match callback:
    case None{}: fallbackApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
    case Some{selected}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
        currentModel : Ai.Model<Value> <- R.read(Ai.Model<Value>, model)
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- C.call(String, Result<&2, &2, ExecutionError, Maybe<&2, String>>, selected, requestModelProvider(Value, currentModel))
        afterApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, outcome)

# Called after context normalization for every assistant request. Read the
# fallback after the awaited resolver, preserving callback-side key rotation.
def resolveApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
    +current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    invokeApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, selectedRequestModel(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current), selectedApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

# Normalization receives only converted messages, as in the source request
# path. Its message array remains shared; the returned context cell is new.
def normalizeConvertedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -ExecutionError: Data, converted: Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>):
  match converted:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>, Fail{error})
    case Done{messages}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>:
        value : Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails> <- Transcript.normalizeContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Ai.Context{None{}, messages, None{}})
        context : R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>> <- R.new(Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>, value)
        return Done{context}

def prepareLlmContext(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, signal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>):
  do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>:
    converted : Result<&2, &2, ExecutionError, R.Ref<List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>> <- convertContextMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, signal)
    normalizeConvertedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, ExecutionError, converted)

# Preserve the complete config spread, including agent-only fields observable
# by an injected stream function. Overrides replace even with absent values.
def withRequestOverrides(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, resolvedApiKey: Maybe<&2, String>, requestSignal: Maybe<&2, Signal>) -> T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match config:
    case T.AgentLoopConfig{_, telemetryContext, _, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{requestSignal, telemetryContext, resolvedApiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def snapshotRequestConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, requestSignal: Maybe<&2, Signal>, resolved: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> IO(Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>):
  match resolved:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>, Fail{error})
    case Done{apiKey}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>>:
        current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
        copied : R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>> <- R.new(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, withRequestOverrides(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current, apiKey, requestSignal))
        return Done{copied}

# The fresh snapshot belongs to the caller; nested handles retain their owners.
# Read config after resolution so resolver-side mutations survive the spread.
def resolveRequestConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, requestSignal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>):
  do IO<Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>>:
    resolved : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- resolveApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
    snapshotRequestConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, requestSignal, resolved)

# message_start/message_update carry a fresh top-level assistant record. Its
# content array and content objects remain shared with the provider message.
# The receiver owns the snapshot cell; borrowed nested handles keep their owners.
def snapshotAssistantMessage(-Arguments: Data, -DiagnosticDetails: Data, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>) -> IO(R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  do IO<R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
    value : Ai.AssistantMessage<Arguments, DiagnosticDetails> <- R.read(Ai.AssistantMessage<Arguments, DiagnosticDetails>, message)
    R.new(Ai.AssistantMessage<Arguments, DiagnosticDetails>, value)

# Explicit ownership until shared handles are managed: the run owns snapshots
# until retained events retire. The provider owns the stream/message objects.
type AssistantResponseConsumer<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantResponseConsumer{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), snapshots: R.Ref<List<&2, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>, response: Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails)}

type AssistantResponseStep<-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data> is Data:
  ResponseContinue{started: Bool}
  ResponseComplete{message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>}
  ResponseFailed{error: ExecutionError}

# Empty arrays keep their indexed elements unchanged under JS's arr[-1] write.
# The non-index property itself awaits the complete dynamic array runtime.
def replaceLastMessage(-Message: Data, values: List<&2, Message>, replacement: Message) -> List<&2, Message>:
  match values:
    case Nil{}: Nil{}
    case _ <> Nil{}: replacement <> Nil{}
    case head <> tail: head <> replaceLastMessage(Message, tail, replacement)

def recordAssistantMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, replace: Bool) -> IO(Unit):
  do IO<Unit>:
    current : T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError> <- R.read(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, context)
    reference : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom) = contextMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, current)
    +wrapped : T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom> = T.LlmMessage{Ai.Assistant{message}}
    R.modify(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, Unit, reference, +values => (Bool.pick(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, replace, replaceLastMessage(T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, values, wrapped), List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, values, wrapped <> Nil{})), Unit{}))

def partialAgentEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, source: Maybe<&2, Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>:
  match source:
    case None{}: T.MessageStart{T.LlmMessage{Ai.Assistant{message}}}
    case Some{event}: T.MessageUpdate{T.LlmMessage{Ai.Assistant{message}}, event}

def emitAssistantSnapshot(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, source: Maybe<&2, Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match consumer:
    case AssistantResponseConsumer{_, emit, snapshots, _}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        +snapshot : R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- snapshotAssistantMessage(Arguments, DiagnosticDetails, message)
        R.modify(List<&2, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, Unit, snapshots, values => (snapshot <> values, Unit{}))
        C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, partialAgentEvent(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, snapshot, source))

def afterResponseEmission(-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data, started: Bool, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseContinue{started}

def startAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +partial: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, _, _}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context, partial, False{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, partial, None{})
        return afterResponseEmission(Arguments, DiagnosticDetails, ExecutionError, True{}, emitted)

def responseEventPartial(-Arguments: Data, -DiagnosticDetails: Data, event: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>) -> Maybe<&2, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
  match event:
    case Ai.TextStart{_, partial}: Some{partial}
    case Ai.TextDelta{_, _, partial}: Some{partial}
    case Ai.TextEnd{_, _, partial}: Some{partial}
    case Ai.ThinkingStart{_, partial}: Some{partial}
    case Ai.ThinkingDelta{_, _, partial}: Some{partial}
    case Ai.ThinkingEnd{_, _, partial}: Some{partial}
    case Ai.ToolcallStart{_, partial}: Some{partial}
    case Ai.ToolcallDelta{_, _, partial}: Some{partial}
    case Ai.ToolcallEnd{_, _, partial}: Some{partial}
    case _: None{}

def updateAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, source: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, partial: Maybe<&2, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, started: Bool) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer partial started:
    case AssistantResponseConsumer{context, _, _, _} Some{+message} True{}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context, message, True{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, Some{source})
        return afterResponseEmission(Arguments, DiagnosticDetails, ExecutionError, True{}, emitted)
    case _ _ _: IO.pure(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>, ResponseContinue{started})


def completeResponseEmission(-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseComplete{message}

def endAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, started: Result<&2, &2, ExecutionError, Unit>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer started:
    case _ Fail{error}: IO.pure(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>, ResponseFailed{error})
    case AssistantResponseConsumer{_, emit, _, _} Done{_}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.Assistant{message}}})
        return completeResponseEmission(Arguments, DiagnosticDetails, ExecutionError, message, emitted)


def maybeStartFinalResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, started: Bool) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match started:
    case True{}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Done{Unit{}})
    case False{}: emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, None{})

def finishAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +started: Bool) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, _, response}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        +message : R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- Stream.resultValue(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, response)
        recordAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context, message, started)
        emitted : Result<&2, &2, ExecutionError, Unit> <- maybeStartFinalResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, started)
        endAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, emitted)

def handleAssistantResponseEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, started: Bool, +event: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match event:
    case Ai.Start{partial}: startAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, partial)
    case Ai.StreamDone{_, _}: finishAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case Ai.StreamError{_, _}: finishAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case _: updateAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, event, responseEventPartial(Arguments, DiagnosticDetails, event), started)

def handleAssistantIteration(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, started: Bool, next: Stream.Iteration<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match next:
    case Stream.End{}: finishAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case Stream.Yield{event}: handleAssistantResponseEvent(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started, event)

# Guarded IO recursion: each continuation awaits one iterator result.
@unsafe
def consumeAssistantIterations(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +cursor: Stream.Iterator<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, state: AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>):
  match state:
    case ResponseFailed{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, Fail{error})
    case ResponseComplete{message}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, Done{message})
    case ResponseContinue{started}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>:
        next : Stream.Iteration<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>> <- Stream.nextValue(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, cursor)
        step : AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError> <- handleAssistantIteration(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started, next)
        consumeAssistantIterations(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, step)

# Consume an already-created provider stream. Listener failures preserve prior
# transcript writes and snapshots and prevent later emissions. Snapshot owners
# and the provider stream remain caller-owned on success and failure alike.
def consumeAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>):
  match consumer:
    case AssistantResponseConsumer{_, _, _, response}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>:
        +cursor : Stream.Iterator<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>> <- Stream.iterator(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, response)
        result : Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>> <- consumeAssistantIterations(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, ResponseContinue{False{}})
        Stream.disposeIterator(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, cursor)
        return result

# Request-scoped ownership is explicit: injected providers may retain context
# and options, and listeners may retain snapshots after this function returns.
# The caller retires those aliases before disposing the three owner lists.
type AssistantRequest<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantRequest{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, signal: Maybe<&2, Signal>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), streamFunction: T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>), contexts: R.Ref<List<&2, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>, configurations: R.Ref<List<&2, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>>, snapshots: R.Ref<List<&2, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>}

def dispatchAssistantRequest(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>, normalized: R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>, resolved: Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>):
  match request resolved:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, Fail{error})
    case AssistantRequest{context, _, _, emit, streamFunction, _, configurations, snapshots} Done{+options}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>:
        R.modify(List<&2, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>, Unit, configurations, values => (options <> values, Unit{}))
        value : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, options)
        response : Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails) <- C.call(T.StreamInput<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails), streamFunction, T.StreamInput{selectedRequestModel(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, value), normalized, Some{options}})
        consumeAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, AssistantResponseConsumer{context, emit, snapshots, response})

def afterLlmContext(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>, prepared: Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>):
  match request prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>, Fail{error})
    case AssistantRequest{_, config, signal, _, _, contexts, _, _} Done{+normalized}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>:
        R.modify(List<&2, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>, Unit, contexts, values => (normalized <> values, Unit{}))
        resolved : Result<&2, &2, ExecutionError, R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>> <- resolveRequestConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, signal)
        dispatchAssistantRequest(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult, request, normalized, resolved)

# Complete typed request/response sequence: transform, convert, normalize,
# resolve credentials, snapshot options, await stream creation, consume events.
# Provider/network implementations and dynamic receiver/property semantics are
# separate; this function uses the caller's injected canonical StreamFn.
def streamAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>):
  match request:
    case AssistantRequest{context, config, signal, _, _, _, _, _}:
      do IO<Result<&2, &2, ExecutionError, R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>>>:
        prepared : Result<&2, &2, ExecutionError, R.Ref<Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>> <- prepareLlmContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, signal)
        afterLlmContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult, request, prepared)

def assistantFailed(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, _, _, _, _}: True{}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, _, _, _, _}: True{}
    case _: False{}

def afterFailedAgentEnd(-ExecutionError: Data, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Bool>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{True{}}

def afterFailedTurnEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, ExecutionError, Bool>>:
        ended : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.AgentEnd{messages})
        return afterFailedAgentEnd(ExecutionError, ended)

def endFailedAssistantTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), +emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), arrays: R.Ref<List<&2, R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<ToolDetails>>>>>>, failed: Bool) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match failed:
    case False{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case True{}:
      do IO<Result<&2, &2, ExecutionError, Bool>>:
        +results : R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<ToolDetails>>>> <- R.new(List<&2, R.Ref<Ai.ToolResultMessage<ToolDetails>>>, Nil{})
        R.modify(List<&2, R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<ToolDetails>>>>>, Unit, arrays, values => (results <> values, Unit{}))
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.TurnEnd{T.LlmMessage{Ai.Assistant{message}}, results})
        afterFailedTurnEnd(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, messages, emit, emitted)

# The post-response runLoop block: always append to newMessages before checking
# the live stop reason. True means the error/abort branch finished both events;
# false continues normal tool handling. Retained empty result arrays belong to
# the run's owner list, including when an event listener fails.
def recordAssistantCompletion(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, +message: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, +messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), arrays: R.Ref<List<&2, R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<ToolDetails>>>>>>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  do IO<Result<&2, &2, ExecutionError, Bool>>:
    R.modify(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, Unit, messages, values => (List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, values, T.LlmMessage{Ai.Assistant{message}} <> Nil{}), Unit{}))
    value : Ai.AssistantMessage<Arguments, DiagnosticDetails> <- R.read(Ai.AssistantMessage<Arguments, DiagnosticDetails>, message)
    endFailedAssistantTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, message, messages, emit, arrays, assistantFailed(Arguments, DiagnosticDetails, value))

type ExecutedToolCallBatch<-Details: Data> is Data:
  ExecutedToolCallBatch{messages: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<Details>>>>, terminate: Bool}

type TruncatedToolCallScope<-DetailValue: Data> is Data:
  TruncatedToolCallScope{details: R.Ref<List<&2, R.Ref<Record.Record<DetailValue>>>>, results: R.Ref<List<&2, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>>>, messages: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, batches: R.Ref<List<&2, R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>>>}

type TruncatedToolCallRun<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data> is Data:
  TruncatedToolCallRun{emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, R.Ref<Record.Record<DetailValue>>, Custom, PartialResult, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>, ExecutionError), scope: TruncatedToolCallScope<DetailValue>}

# Error details are a fresh ordinary object. DetailValue is the caller's object
# property domain; no JSON conversion or reuse of one shared empty object occurs.
def createErrorToolResult(-DetailValue: Data, scope: TruncatedToolCallScope<DetailValue>, message: String) -> IO(R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>):
  match scope:
    case TruncatedToolCallScope{details, results, _, _}:
      do IO<R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>>:
        +empty : R.Ref<Record.Record<DetailValue>> <- R.new(Record.Record<DetailValue>, Record.new(DetailValue))
        R.modify(List<&2, R.Ref<Record.Record<DetailValue>>>, Unit, details, values => (empty <> values, Unit{}))
        +result : R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>> <- R.new(T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>, T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, empty, None{}, None{}})
        R.modify(List<&2, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>>, Unit, results, values => (result <> values, Unit{}))
        return result

def truncatedCallError(-Arguments: Data, call: Ai.ToolCall<Arguments>) -> String:
  match call:
    case Ai.ToolCall{_, name, _, _, _}: "Tool call \"" ++ name ++ "\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."

def toolExecutionStartEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -DetailValue: Data, call: Ai.ToolCall<Arguments>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, R.Ref<Record.Record<DetailValue>>, Custom, PartialResult, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

def appendTruncatedResult(-DetailValue: Data, -ExecutionError: Data, batch: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, message: R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        R.modify(List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>, Unit, batch, values => (List.append(&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>, values, message <> Nil{}), Unit{}))
        return Done{Unit{}}

def afterTruncatedExecutionEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, batch: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, finalized: FinalizedToolCallOutcome<Arguments, R.Ref<Record.Record<DetailValue>>>, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Fail{error})
    case TruncatedToolCallRun{emit, TruncatedToolCallScope{_, _, messages, _}} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        +message : R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>> <- createToolResultMessage(Arguments, R.Ref<Record.Record<DetailValue>>, finalized)
        R.modify(List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>, Unit, messages, values => (message <> values, Unit{}))
        delivered : Result<&2, &2, ExecutionError, Unit> <- emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, R.Ref<Record.Record<DetailValue>>, Custom, PartialResult, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>, ExecutionError, message, emit)
        appendTruncatedResult(DetailValue, ExecutionError, batch, message, delivered)

def afterTruncatedStart(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, batch: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, +call: T.AgentToolCall(Arguments), emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Fail{error})
    case TruncatedToolCallRun{emit, scope} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        current : Ai.ToolCall<Arguments> <- R.read(Ai.ToolCall<Arguments>, call)
        result : R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>> <- createErrorToolResult(DetailValue, scope, truncatedCallError(Arguments, current))
        +finalized : FinalizedToolCallOutcome<Arguments, R.Ref<Record.Record<DetailValue>>> = FinalizedToolCallOutcome{call, result, True{}}
        ended : Result<&2, &2, ExecutionError, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, R.Ref<Record.Record<DetailValue>>, Custom, PartialResult, ExecutionError, finalized, emit)
        afterTruncatedExecutionEnd(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, batch, finalized, ended)

def failTruncatedToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, batch: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, +call: T.AgentToolCall(Arguments)) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match run:
    case TruncatedToolCallRun{emit, _}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        current : Ai.ToolCall<Arguments> <- R.read(Ai.ToolCall<Arguments>, call)
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, R.Ref<Record.Record<DetailValue>>, Custom, PartialResult, R.Ref<T.AgentToolResult<R.Ref<Record.Record<DetailValue>>>>>, Result<&2, &2, ExecutionError, Unit>, emit, toolExecutionStartEvent(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, DetailValue, current))
        afterTruncatedStart(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, batch, call, emitted)

# Read each index from the live array, matching for-of when listeners append.
def truncatedCallAt(-Arguments: Data, values: List<&2, T.AgentToolCall(Arguments)>, +index: Nat) -> Maybe<&2, T.AgentToolCall(Arguments)>:
  match values:
    case Nil{}: None{}
    case head <> tail: Bool.pick(Maybe<&2, T.AgentToolCall(Arguments)>, Nat.is_eq(index, 0n), Some{head}, truncatedCallAt(Arguments, tail, (index - 1n : Nat)))

def nextTruncatedCall(-Arguments: Data, -ExecutionError: Data, calls: R.Ref<List<&2, T.AgentToolCall(Arguments)>>, index: Nat, previous: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>>):
  match previous:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>>>:
        values : List<&2, T.AgentToolCall(Arguments)> <- R.read(List<&2, T.AgentToolCall(Arguments)>, calls)
        return Done{truncatedCallAt(Arguments, values, index)}

# Guarded IO recursion advances an index after one fully awaited call sequence.
@unsafe
def failTruncatedCalls(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, +calls: R.Ref<List<&2, T.AgentToolCall(Arguments)>>, +batch: R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>, +index: Nat, next: Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>):
  match next:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>, Fail{error})
    case Done{None{}}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>, Done{ExecutedToolCallBatch{batch, False{}}})
    case Done{Some{call}}:
      do IO<Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- failTruncatedToolCall(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, batch, call)
        +followingIndex : Nat = (index + 1n : Nat)
        following : Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>> <- nextTruncatedCall(Arguments, ExecutionError, calls, followingIndex, emitted)
        failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, calls, batch, followingIndex, following)

def failToolCallsFromTruncatedMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, +calls: R.Ref<List<&2, T.AgentToolCall(Arguments)>>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>):
  match run:
    case TruncatedToolCallRun{_, TruncatedToolCallScope{_, _, _, batches}}:
      do IO<Result<&2, &2, ExecutionError, ExecutedToolCallBatch<R.Ref<Record.Record<DetailValue>>>>>:
        +batch : R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>> <- R.new(List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>, Nil{})
        R.modify(List<&2, R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<R.Ref<Record.Record<DetailValue>>>>>>>, Unit, batches, values => (batch <> values, Unit{}))
        first : Result<&2, &2, ExecutionError, Maybe<&2, T.AgentToolCall(Arguments)>> <- nextTruncatedCall(Arguments, ExecutionError, calls, 0n, Done{Unit{}})
        failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, calls, batch, 0n, first)

# Array.filter creates a new array but retains each selected call object,
# including repeated references. Non-tool content is never dereferenced.
def toolCallsInContent(-Arguments: Data, content: List<&2, Ai.AssistantContent<Arguments>>) -> List<&2, T.AgentToolCall(Arguments)>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantToolCall{call} <> rest: call <> toolCallsInContent(Arguments, rest)
    case _ <> rest: toolCallsInContent(Arguments, rest)

def assistantContent(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> R.Ref<List<&2, Ai.AssistantContent<Arguments>>>:
  match message:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def collectAssistantToolCalls(-Arguments: Data, -DiagnosticDetails: Data, assistant: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>) -> IO(R.Ref<List<&2, T.AgentToolCall(Arguments)>>):
  do IO<R.Ref<List<&2, T.AgentToolCall(Arguments)>>>:
    message : Ai.AssistantMessage<Arguments, DiagnosticDetails> <- R.read(Ai.AssistantMessage<Arguments, DiagnosticDetails>, assistant)
    content : List<&2, Ai.AssistantContent<Arguments>> <- R.read(List<&2, Ai.AssistantContent<Arguments>>, assistantContent(Arguments, DiagnosticDetails, message))
    R.new(List<&2, T.AgentToolCall(Arguments)>, toolCallsInContent(Arguments, content))

type PreparedToolCallBatch<-Arguments: Data> is Data:
  PreparedToolCallBatch{toolCalls: R.Ref<List<&2, T.AgentToolCall(Arguments)>>, executionMode: T.ToolExecutionMode}

def configuredToolExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, T.ToolExecutionMode>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, configured, _, _}: configured

def availableContextTools(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>) -> IO(List<&2, R.Ref<T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>>):
  match context:
    case T.AgentContext{_, None{}}: IO.pure(List<&2, R.Ref<T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>>, Nil{})
    case T.AgentContext{_, Some{reference}}: R.read(List<&2, R.Ref<T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>>, reference)

# Prepare the exact call array and whole-batch mode for normal execution.
# Read the global setting after the per-tool scan, as the source does.
# The returned call-array cell is new and caller-owned; calls/tools are borrowed.
def prepareToolCallBatch(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, assistant: R.Ref<Ai.AssistantMessage<Arguments, DiagnosticDetails>>, config: R.Ref<T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(PreparedToolCallBatch<Arguments>):
  do IO<PreparedToolCallBatch<Arguments>>:
    +calls : R.Ref<List<&2, T.AgentToolCall(Arguments)>> <- collectAssistantToolCalls(Arguments, DiagnosticDetails, assistant)
    currentContext : T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError> <- R.read(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, context)
    tools : List<&2, R.Ref<T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>> <- availableContextTools(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, currentContext)
    values : List<&2, T.AgentToolCall(Arguments)> <- R.read(List<&2, T.AgentToolCall(Arguments)>, calls)
    sequential : Bool <- hasSequentialToolCall(Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError, values, tools)
    currentConfig : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> <- R.read(T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, config)
    mode : T.ToolExecutionMode = Bool.pick(T.ToolExecutionMode, sequential || isSequential(configuredToolExecution(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, currentConfig)), T.Sequential{}, T.Parallel{})
    return PreparedToolCallBatch{calls, mode}
