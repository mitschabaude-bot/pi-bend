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
