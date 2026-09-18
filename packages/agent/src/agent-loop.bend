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

type PreparedToolCall<-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  PreparedToolCall{toolCall: T.AgentToolCall(RawArguments), tool: T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>, args: Arguments}

type ImmediateToolCallOutcome<-Details: Data> is Data:
  ImmediateToolCallOutcome{result: T.AgentToolResult<Details>, isError: Bool}

type ToolCallPreparation<-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  Prepared{value: PreparedToolCall<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>}
  Immediate{value: ImmediateToolCallOutcome<Details>}

def preparationKind(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, preparation: ToolCallPreparation<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>) -> String:
  match preparation:
    case Prepared{_}: "prepared"
    case Immediate{_}: "immediate"

type ExecutedToolCallOutcome<-Details: Data> is Data:
  ExecutedToolCallOutcome{result: T.AgentToolResult<Details>, isError: Bool}

type FinalizedToolCallOutcome<-Arguments: Data, -Details: Data> is Data:
  FinalizedToolCallOutcome{toolCall: T.AgentToolCall(Arguments), result: T.AgentToolResult<Details>, isError: Bool}

def choose(-Value: Data, original: Value, replacement: Maybe<&2, Value>) -> Value:
  match replacement:
    case None{}: original
    case Some{value}: value

def chooseOptional(-Value: Data, original: Maybe<&2, Value>, replacement: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match replacement:
    case None{}: original
    case Some{value}: Some{value}

def mergeResult(-Details: Data, original: T.AgentToolResult<Details>, replacement: T.AfterToolCallResult<Details>) -> T.AgentToolResult<Details> & Maybe<&2, Bool>:
  match original replacement:
    case T.AgentToolResult{content, details, usage, terminate} T.AfterToolCallResult{newContent, newDetails, newIsError, newUsage, newTerminate}:
      (T.AgentToolResult{choose(List<&2, Ai.TextImageContent>, content, newContent), choose(Details, details, newDetails), chooseOptional(Ai.Usage, usage, newUsage), chooseOptional(Bool, terminate, newTerminate)}, newIsError)

def mergedOutcome(-Details: Data, isError: Bool, merged: T.AgentToolResult<Details> & Maybe<&2, Bool>) -> ExecutedToolCallOutcome<Details>:
  match merged:
    case Tuple{value, newIsError}:
      result = {value : T.AgentToolResult<Details>}
      ExecutedToolCallOutcome{result, choose(Bool, isError, newIsError)}

def applyAfterToolCallResult(-Details: Data, executed: ExecutedToolCallOutcome<Details>, replacement: Maybe<&2, T.AfterToolCallResult<Details>>) -> ExecutedToolCallOutcome<Details>:
  match executed replacement:
    case ExecutedToolCallOutcome{result, isError} None{}: {ExecutedToolCallOutcome{result, isError} : ExecutedToolCallOutcome<Details>}
    case ExecutedToolCallOutcome{result, isError} Some{patch}:
      original = {result : T.AgentToolResult<Details>}
      mergedOutcome(Details, isError, mergeResult(Details, original, patch))

def lookupModeStep(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, name: String, tool: T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>) -> Maybe<&2, Maybe<&2, T.ToolExecutionMode>>:
  match tool:
    case T.AgentTool{toolName, _, _, _, _, _, _, _, mode}:
      Bool.pick(Maybe<&2, Maybe<&2, T.ToolExecutionMode>>, String.eq(name, toolName), Some{mode}, None{})

def matchedMode(value: Maybe<&2, Maybe<&2, T.ToolExecutionMode>>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def extractedMode(value: Maybe<&2, Maybe<&2, T.ToolExecutionMode>>) -> Maybe<&2, T.ToolExecutionMode>:
  match value:
    case Some{mode}: mode
    case None{}: None{}

def chooseSearch(more: Bool, found: Maybe<&2, T.ToolExecutionMode>, rest: Maybe<&2, T.ToolExecutionMode>) -> Maybe<&2, T.ToolExecutionMode>:
  match more:
    case True{}: rest
    case False{}: found

def findToolExecutionMode(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, +name: String, tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>) -> Maybe<&2, T.ToolExecutionMode>:
  match tools:
    case Nil{}: {None{} : Maybe<&2, T.ToolExecutionMode>}
    case head <> tail:
      tool = {head : T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>}
      +found = {lookupModeStep(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, name, tool) : Maybe<&2, Maybe<&2, T.ToolExecutionMode>>}
      searchMore = {Bool.not(matchedMode(found)) : Bool}
      chooseSearch(searchMore, {extractedMode(found) : Maybe<&2, T.ToolExecutionMode>}, findToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, name, tail))

def isSequential(mode: Maybe<&2, T.ToolExecutionMode>) -> Bool:
  match mode:
    case Some{T.Sequential{}}: True{}
    case _: False{}

def callName(-RawArguments: Data, toolCall: Ai.ToolCall<RawArguments>) -> String:
  match toolCall:
    case Ai.ToolCall{_, name, _, _, _}: name

def chooseSequential(found: Bool, rest: Bool) -> Bool:
  match found:
    case True{}: {True{} : Bool}
    case False{}: rest

def hasSequentialToolCall(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall(RawArguments)>, +tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>) -> Bool:
  match calls:
    case Nil{}: {False{} : Bool}
    case head <> tail:
      toolCall = {head : Ai.ToolCall<RawArguments>}
      mode = {findToolExecutionMode(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, callName(RawArguments, toolCall), tools) : Maybe<&2, T.ToolExecutionMode>}
      chooseSequential(isSequential(mode), hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, tail, tools))

# Upstream computes the per-tool scan before checking the global setting. A
# single sequential override makes the entire assistant batch sequential.
def selectToolExecutionMode(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall(RawArguments)>, tools: List<&2, T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>, configured: Maybe<&2, T.ToolExecutionMode>) -> T.ToolExecutionMode:
  found = {hasSequentialToolCall(Parameters, Arguments, Details, RawArguments, Signal, ExecutionError, calls, tools) : Bool}
  Bool.pick(T.ToolExecutionMode, isSequential(configured) || found, T.Sequential{}, T.Parallel{})

def resultTerminates(-Details: Data, result: T.AgentToolResult<Details>) -> Bool:
  match result:
    case T.AgentToolResult{_, _, _, Some{True{}}}: True{}
    case _: False{}

def continueTermination(terminates: Bool, rest: Bool) -> Bool:
  match terminates:
    case False{}: {False{} : Bool}
    case True{}: rest

def allTerminate(-Arguments: Data, -Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Arguments, Details>>) -> Bool:
  match finalizedCalls:
    case Nil{}: {True{} : Bool}
    case FinalizedToolCallOutcome{_, result, _} <> tail:
      value = {result : T.AgentToolResult<Details>}
      continueTermination(resultTerminates(Details, value), allTerminate(Arguments, Details, tail))

def shouldTerminateToolBatch(-Arguments: Data, -Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Arguments, Details>>) -> Bool:
  match finalizedCalls:
    case Nil{}: {False{} : Bool}
    case +head <> +tail: allTerminate(Arguments, Details, head <> tail)

# Promise<void> | void becomes an awaited reusable IO callback. Recoverable
# listener failures are explicit; callers must propagate them without emitting
# later events. This does not establish host Promise microtask scheduling.
def AgentEventSink(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data) -> Data:
  C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>>

def toolExecutionEndEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, call: Ai.ToolCall<Arguments>, result: T.AgentToolResult<Details>, isError: Bool) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, _, _, _}: T.ToolExecutionEnd{id, name, result, isError}

def emitToolExecutionEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ListenerError: Data, finalized: FinalizedToolCallOutcome<Arguments, Details>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<Result<&2, &2, ListenerError, Unit>>:
        call : Ai.ToolCall<Arguments> = toolCall
        C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>, Result<&2, &2, ListenerError, Unit>, emit, toolExecutionEndEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, call, result, isError))

def finishToolResultMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, toolResultMessage: Ai.ToolResultMessage<Details>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError), started: Result<&2, &2, ListenerError, Unit>) -> IO(Result<&2, &2, ListenerError, Unit>):
  match started:
    case Fail{error}: IO.pure(Result<&2, &2, ListenerError, Unit>, Fail{error})
    case Done{Unit{}}: C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})

def emitToolResultMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, +toolResultMessage: Ai.ToolResultMessage<Details>, +emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  do IO<Result<&2, &2, ListenerError, Unit>>:
    started : Result<&2, &2, ListenerError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageStart{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})
    finishToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError, toolResultMessage, emit, started)

def toolResultMessageAt(-Arguments: Data, -Details: Data, call: Ai.ToolCall<Arguments>, result: T.AgentToolResult<Details>, isError: Bool, timestamp: Number.F64) -> Ai.ToolResultMessage<Details>:
  match call result:
    case Ai.ToolCall{id, name, _, _, _} T.AgentToolResult{content, details, usage, _}:
      Ai.ToolResultMessage{id, name, content, Some{details}, usage, isError, timestamp}

def createToolResultMessage(-Arguments: Data, -Details: Data, finalized: FinalizedToolCallOutcome<Arguments, Details>) -> IO(Ai.ToolResultMessage<Details>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<Ai.ToolResultMessage<Details>>:
        call : Ai.ToolCall<Arguments> = toolCall
        value : T.AgentToolResult<Details> = result
        timestamp : Number.F64 <- Date.now()
        IO.pure(Ai.ToolResultMessage<Details>, toolResultMessageAt(Arguments, Details, call, value, isError, timestamp))

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

# An adapter returns a new argument value. No reference comparison or
# observation of mutations to the original call is involved.
def afterPrepareArguments(-RawArguments: Data, -Arguments: Data, -ExecutionError: Data, original: T.AgentToolCall(RawArguments), outcome: Result<&2, &2, ExecutionError, Arguments>) -> Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>:
  match outcome:
    case Fail{error}: Fail{error}
    case Done{arguments}: Done{ReplacedCall{replaceCallArguments(RawArguments, Arguments, original, arguments)}}

def prepareArgumentsWith(-RawArguments: Data, -Arguments: Data, -ExecutionError: Data, callback: Maybe<&2, C.Callback<RawArguments, Result<&2, &2, ExecutionError, Arguments>>>, +toolCall: T.AgentToolCall(RawArguments)) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>, Done{OriginalCall{toolCall}})
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>>:
        current : Ai.ToolCall<RawArguments> = toolCall
        outcome : Result<&2, &2, ExecutionError, Arguments> <- C.call(RawArguments, Result<&2, &2, ExecutionError, Arguments>, prepare, callArguments(RawArguments, current))
        IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>, afterPrepareArguments(RawArguments, Arguments, ExecutionError, toolCall, outcome))

def prepareToolCallArguments(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, tool: T.AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>, toolCall: T.AgentToolCall(RawArguments)) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments<RawArguments, Arguments>>):
  match tool:
    case T.AgentTool{_, _, _, _, _, prepare, _, _, _}: prepareArgumentsWith(RawArguments, Arguments, ExecutionError, prepare, toolCall)

def copyContextMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>, initialMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>:
  match context:
    case T.AgentContext{messages, tools}:
      previous = {messages : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>}
      copied = {{List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, previous, initialMessages) : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>} : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, Details, Custom)}
      {T.AgentContext{copied, tools} : T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, ExecutionError>}

# Only omission preserves prior reasoning; explicit off removes the provider
# field. This is the next-turn update rule, not model thinking-level clamping.
def turnReasoning(previous: Maybe<&2, Ai.ThinkingLevel>, requested: Maybe<&2, T.ThinkingLevel()>) -> Maybe<&2, Ai.ThinkingLevel>:
  match requested:
    case None{}: previous
    case Some{Ai.Off{}}: None{}
    case Some{Ai.Thinking{level}}: Some{level}

def withTurnConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, replacementModel: Maybe<&2, Ai.Model<Value>>, requestedThinking: Maybe<&2, T.ThinkingLevel()>) -> T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match config:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, turnReasoning(reasoning, requestedThinking), deferred, thinkingBudgets, choose(Ai.Model<Value>, model, replacementModel), convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

type PreparedTurnState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  PreparedTurnState{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}

def preparedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, supplied: Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom):
  match supplied:
    case Some{messages}: {messages : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}
    case None{}: {Nil{} : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>}

def applyTurnSnapshot(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, currentContext: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, snapshot: T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>) -> PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match snapshot:
    case T.AgentLoopTurnUpdate{context, messages, model, thinkingLevel}:
      prepared = {preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, messages) : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}
      previous = {config : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
      next = {withTurnConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, previous, model, thinkingLevel) : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
      PreparedTurnState{choose(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, currentContext, context), next, prepared}

def applyTurnUpdate(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, update: Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>) -> PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match update:
    case None{}:
      messages = {preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, None{}) : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}
      PreparedTurnState{context, config, messages}
    case Some{value}:
      snapshot = {value : T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>}
      applyTurnSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, snapshot)

def afterPrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>) -> Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>:
  match outcome:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>}
    case Done{update}:
      state = {applyTurnUpdate(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, update) : PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
      Done{state}

def invokePrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, completed: T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError), callback: Maybe<&2, C.Callback<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>>) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, afterPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, Done{None{}}))
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>> <- C.call(T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>, prepare, completed)
        IO.pure(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, afterPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, outcome))

def selectedPrepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, value: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>>:
  match value:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, callback, _, _, _, _, _}: callback

def prepareNextTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, completed: T.PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, ExecutionError, PreparedTurnState<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
    value : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    invokePrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, completed, selectedPrepareNextTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, value))

def readQueuedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, callback: Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  match callback:
    case Some{selected}: C.call(Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, selected, Unit{})
    case None{}:
      do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
        empty : T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom) = preparedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, None{})
        return Done{empty}

def selectedSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _}: selected

def pollSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    readQueuedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedSteeringMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

def selectedFollowUpMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _}: selected

def pollFollowUpMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    readQueuedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedFollowUpMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

# After preparation, only repoll steering when the previous array is empty.
# A retained pending message must not consume a second one-at-a-time delivery.
# Read its live contents before selecting the current configuration callback.
def repollSteeringContents(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, pending: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), contents: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  match contents:
    case Nil{}: pollSteeringMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
    case _ <> _: IO.pure(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, Done{pending})

def repollSteeringMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, +pending: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
    contents : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>> = pending
    repollSteeringContents(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, pending, contents)

# A missing stop hook is false. Recoverable hook errors are not stop requests.
def invokeShouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, callback: Maybe<&2, C.Callback<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case Some{selected}: C.call(T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Result<&2, &2, ExecutionError, Bool>, selected, completed)

def selectedShouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, callback, _, _, _, _, _, _}: callback

def shouldStopAfterTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  do IO<Result<&2, &2, ExecutionError, Bool>>:
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    invokeShouldStopAfterTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, completed, selectedShouldStopAfterTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

def stoppedTurnResult(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{None{}}

def queuedTurnResult(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, queued: Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>:
  match queued:
    case Fail{error}: Fail{error}
    case Done{messages}: Done{Some{messages}}

def afterTurnDecision(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, newMessages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), decision: Result<&2, &2, ExecutionError, Bool>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>):
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
# Hook/emit errors skip polling. The supplied message history is the
# immutable value delivered to agent_end.
def finishCompletedTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, newMessages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>):
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

def selectedMessageConverter(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> C.Callback<T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _, _, _}: selected

def convertTransformedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, transformed: Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>) -> IO(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>):
  match transformed:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>, Fail{error})
    case Done{messages}:
      do IO<Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>:
        current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
        C.call(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>, selectedMessageConverter(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current), messages)

def convertContextMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>):
  do IO<Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>:
    captured : T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError> = context
    current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    transformed : Result<&2, &2, ExecutionError, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)> <- invokeContextTransform(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, Signal, ExecutionError, contextMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, captured), signal, selectedContextTransform(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))
    convertTransformedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, transformed)

def selectedApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, String>:
  match config:
    case T.AgentLoopConfig{_, _, selected, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: selected

def selectedApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, selected, _, _, _, _, _, _, _}: selected

def selectedRequestModel(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Ai.Model<Value>:
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

def fallbackApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  current = {config : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
  Done{selectedApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current)}

def selectResolvedApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, resolved: Maybe<&2, String>, present: Bool) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  match present:
    case True{}: {Done{resolved} : Result<&2, &2, ExecutionError, Maybe<&2, String>>}
    case False{}: fallbackApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)

def afterApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  match outcome:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, Maybe<&2, String>>}
    case Done{+key}: selectResolvedApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, key, hasResolvedApiKey(key))

def invokeApiKeyResolver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, model: Ai.Model<Value>, callback: Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, fallbackApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config))
    case Some{selected}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
        currentModel : Ai.Model<Value> = model
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- C.call(String, Result<&2, &2, ExecutionError, Maybe<&2, String>>, selected, requestModelProvider(Value, currentModel))
        IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, afterApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, outcome))

# Called after context normalization for every assistant request. A resolver
# can obtain rotated credentials; an empty result uses the configured fallback.
def resolveApiKey(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
    +current : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = config
    invokeApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, selectedRequestModel(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current), selectedApiKeyResolver(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current))

def normalizeConvertedMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -ExecutionError: Data, converted: Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>) -> Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>:
  match converted:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>}
    case Done{messages}:
      value = {Transcript.normalizeContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Ai.Context{None{}, messages, None{}}) : Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>}
      context = {value : Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>}
      Done{context}

def prepareLlmContext(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>):
  do IO<Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>:
    converted : Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>> <- convertContextMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, context, config, signal)
    IO.pure(Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>, normalizeConvertedMessages(Parameters, Arguments, DiagnosticDetails, ToolDetails, ExecutionError, converted))

def withRequestOverrides(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, resolvedApiKey: Maybe<&2, String>, requestSignal: Maybe<&2, Signal>) -> T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>:
  match config:
    case T.AgentLoopConfig{_, telemetryContext, _, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{requestSignal, telemetryContext, resolvedApiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def snapshotRequestConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, requestSignal: Maybe<&2, Signal>, resolved: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>:
  match resolved:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>}
    case Done{apiKey}:
      current = {config : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
      copied = {withRequestOverrides(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current, apiKey, requestSignal) : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>}
      Done{copied}

def resolveRequestConfig(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, requestSignal: Maybe<&2, Signal>) -> IO(Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>>:
    resolved : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- resolveApiKey(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)
    IO.pure(Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, snapshotRequestConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, requestSignal, resolved))

def snapshotAssistantMessage(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> Ai.AssistantMessage<Arguments, DiagnosticDetails>:
  message

type AssistantResponseConsumer<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantResponseConsumer{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), response: Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails)}

type AssistantResponseStep<-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data> is Data:
  ResponseContinue{started: Bool}
  ResponseComplete{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>}
  ResponseFailed{error: ExecutionError}

def replaceLastMessage(-Message: Data, values: List<&2, Message>, replacement: Message) -> List<&2, Message>:
  match values:
    case Nil{}: replacement <> Nil{}
    case _ <> Nil{}: replacement <> Nil{}
    case head <> tail: head <> replaceLastMessage(Message, tail, replacement)

# Pure transition used atomically by the running agent's state cell.
def withAssistantMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, current: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, replace: Bool) -> T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>:
  match current:
    case T.AgentContext{+messages, tools}:
      +wrapped = {T.LlmMessage{Ai.Assistant{message}} : T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>}
      T.AgentContext{Bool.pick(List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>, replace, replaceLastMessage(T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, messages, wrapped), List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, messages, wrapped <> Nil{})), tools}

def recordAssistantMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, replace: Bool) -> IO(Unit):
  R.modify(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Unit, context, current => (withAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, current, message, replace), Unit{}))

def partialAgentEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, source: Maybe<&2, Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>:
  match source:
    case None{}: T.MessageStart{T.LlmMessage{Ai.Assistant{message}}}
    case Some{event}: T.MessageUpdate{T.LlmMessage{Ai.Assistant{message}}, event}

def emitAssistantSnapshot(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, source: Maybe<&2, Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match consumer:
    case AssistantResponseConsumer{_, emit, _}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        +snapshot : Ai.AssistantMessage<Arguments, DiagnosticDetails> = snapshotAssistantMessage(Arguments, DiagnosticDetails, message)
        C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, partialAgentEvent(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, snapshot, source))

def afterResponseEmission(-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data, started: Bool, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseContinue{started}

def startAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +partial: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, _}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context, partial, False{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, partial, None{})
        return afterResponseEmission(Arguments, DiagnosticDetails, ExecutionError, True{}, emitted)

def responseEventPartial(-Arguments: Data, -DiagnosticDetails: Data, event: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>) -> Maybe<&2, Ai.AssistantMessage<Arguments, DiagnosticDetails>>:
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

def updateAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, source: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, partial: Maybe<&2, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, started: Bool) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer partial started:
    case AssistantResponseConsumer{context, _, _} Some{+message} True{}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context, message, True{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, Some{source})
        return afterResponseEmission(Arguments, DiagnosticDetails, ExecutionError, True{}, emitted)
    case _ _ _: IO.pure(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>, ResponseContinue{started})


def completeResponseEmission(-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseComplete{message}

def endAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, started: Result<&2, &2, ExecutionError, Unit>) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer started:
    case _ Fail{error}: IO.pure(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>, ResponseFailed{error})
    case AssistantResponseConsumer{_, emit, _} Done{_}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.Assistant{message}}})
        return completeResponseEmission(Arguments, DiagnosticDetails, ExecutionError, message, emitted)


def maybeStartFinalResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, started: Bool) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match started:
    case True{}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Done{Unit{}})
    case False{}: emitAssistantSnapshot(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, message, None{})

def finishAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +started: Bool) -> IO(AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, response}:
      do IO<AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>>:
        +message : Ai.AssistantMessage<Arguments, DiagnosticDetails> <- Stream.resultValue(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>, response)
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
def consumeAssistantIterations(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>, +cursor: Stream.Iterator<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, state: AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match state:
    case ResponseFailed{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Fail{error})
    case ResponseComplete{message}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Done{message})
    case ResponseContinue{started}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        next : Stream.Iteration<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>> <- Stream.nextValue(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>, cursor)
        step : AssistantResponseStep<Arguments, DiagnosticDetails, ExecutionError> <- handleAssistantIteration(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, started, next)
        consumeAssistantIterations(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, step)

def consumeAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match consumer:
    case AssistantResponseConsumer{_, _, response}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        +cursor : Stream.Iterator<Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- Stream.iterator(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>, response)
        result : Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- consumeAssistantIterations(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, ResponseContinue{False{}})
        Stream.disposeIterator(Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>, Ai.AssistantMessage<Arguments, DiagnosticDetails>, cursor)
        return result

type AssistantRequest<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantRequest{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), streamFunction: T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>)}

def dispatchAssistantRequest(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>, normalized: Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>, resolved: Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match request resolved:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Fail{error})
    case AssistantRequest{context, _, _, emit, streamFunction} Done{+options}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        value : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = options
        response : Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails) <- C.call(T.StreamInput<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails), streamFunction, T.StreamInput{selectedRequestModel(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, value), normalized, Some{options}})
        consumeAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, AssistantResponseConsumer{context, emit, response})

def afterLlmContext(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>, prepared: Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match request prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Fail{error})
    case AssistantRequest{_, config, signal, _, _} Done{+normalized}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        resolved : Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>> <- resolveRequestConfig(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config, signal)
        dispatchAssistantRequest(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult, request, normalized, resolved)

def streamAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match request:
    case AssistantRequest{context, config, signal, _, _}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        current : T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError> <- R.read(T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, context)
        prepared : Result<&2, &2, ExecutionError, Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>> <- prepareLlmContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, current, config, signal)
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

def endFailedAssistantTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), +emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), failed: Bool) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match failed:
    case False{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case True{}:
      do IO<Result<&2, &2, ExecutionError, Bool>>:
        +results : List<&2, Ai.ToolResultMessage<ToolDetails>> = Nil{}
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.TurnEnd{T.LlmMessage{Ai.Assistant{message}}, results})
        afterFailedTurnEnd(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, messages, emit, emitted)

type AssistantCompletion<-Message: Data> is Data:
  AssistantCompletion{messages: List<&2, Message>, failed: Bool}

def completionResult(-Message: Data, -Error: Data, messages: List<&2, Message>, result: Result<&2, &2, Error, Bool>) -> Result<&2, &2, Error, AssistantCompletion<Message>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{failed}: Done{AssistantCompletion{messages, failed}}

def recordAssistantCompletion(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, +message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, +messages: T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, AssistantCompletion<T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>>):
  do IO<Result<&2, &2, ExecutionError, AssistantCompletion<T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>>>:
    +updated : List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>> = List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, messages, T.LlmMessage{Ai.Assistant{message}} <> Nil{})
    outcome : Result<&2, &2, ExecutionError, Bool> <- endFailedAssistantTurn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, message, updated, emit, assistantFailed(Arguments, DiagnosticDetails, message))
    return completionResult(T.AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, ExecutionError, updated, outcome)

type ExecutedToolCallBatch<-Details: Data> is Data:
  ExecutedToolCallBatch{messages: List<&2, Ai.ToolResultMessage<Details>>, terminate: Bool}

type TruncatedToolCallRun<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data> is Data:
  TruncatedToolCallRun{emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Record.Record<DetailValue>, Custom, PartialResult, T.AgentToolResult<Record.Record<DetailValue>>, ExecutionError)}

def createErrorToolResult(-DetailValue: Data, message: String) -> T.AgentToolResult<Record.Record<DetailValue>>:
  T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, Record.new(DetailValue), None{}, None{}}

def truncatedCallError(-Arguments: Data, call: Ai.ToolCall<Arguments>) -> String:
  match call:
    case Ai.ToolCall{_, name, _, _, _}: "Tool call \"" ++ name ++ "\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."

def toolExecutionStartEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -DetailValue: Data, call: Ai.ToolCall<Arguments>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Record.Record<DetailValue>, Custom, PartialResult, T.AgentToolResult<Record.Record<DetailValue>>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

def deliveredTruncatedResult(-DetailValue: Data, -ExecutionError: Data, message: Ai.ToolResultMessage<Record.Record<DetailValue>>, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{message}

def afterTruncatedExecutionEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, finalized: FinalizedToolCallOutcome<Arguments, Record.Record<DetailValue>>, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>, Fail{error})
    case TruncatedToolCallRun{emit} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>>:
        +message : Ai.ToolResultMessage<Record.Record<DetailValue>> <- createToolResultMessage(Arguments, Record.Record<DetailValue>, finalized)
        delivered : Result<&2, &2, ExecutionError, Unit> <- emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Record.Record<DetailValue>, Custom, PartialResult, T.AgentToolResult<Record.Record<DetailValue>>, ExecutionError, message, emit)
        return deliveredTruncatedResult(DetailValue, ExecutionError, message, delivered)

def afterTruncatedStart(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, +call: T.AgentToolCall(Arguments), emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>, Fail{error})
    case TruncatedToolCallRun{emit} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>>:
        result : T.AgentToolResult<Record.Record<DetailValue>> = createErrorToolResult(DetailValue, truncatedCallError(Arguments, call))
        +finalized : FinalizedToolCallOutcome<Arguments, Record.Record<DetailValue>> = FinalizedToolCallOutcome{call, result, True{}}
        ended : Result<&2, &2, ExecutionError, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Record.Record<DetailValue>, Custom, PartialResult, ExecutionError, finalized, emit)
        afterTruncatedExecutionEnd(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, finalized, ended)

def failTruncatedToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, +call: T.AgentToolCall(Arguments)) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>):
  match run:
    case TruncatedToolCallRun{emit}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Record.Record<DetailValue>, Custom, PartialResult, T.AgentToolResult<Record.Record<DetailValue>>>, Result<&2, &2, ExecutionError, Unit>, emit, toolExecutionStartEvent(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, DetailValue, call))
        afterTruncatedStart(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, call, emitted)

def accumulateTruncated(-DetailValue: Data, -ExecutionError: Data, previous: List<&2, Ai.ToolResultMessage<Record.Record<DetailValue>>>, result: Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>>) -> Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Record.Record<DetailValue>>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{message}: Done{message <> previous}

def failTruncatedCalls(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, calls: List<&2, T.AgentToolCall(Arguments)>, state: Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Record.Record<DetailValue>>>>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Record.Record<DetailValue>>>):
  match calls state:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Record.Record<DetailValue>>>, Fail{error})
    case Nil{} Done{messages}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Record.Record<DetailValue>>>, Done{ExecutedToolCallBatch{List.reverse(&2, Ai.ToolResultMessage<Record.Record<DetailValue>>, messages), False{}}})
    case call <> tail Done{messages}:
      do IO<Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Record.Record<DetailValue>>>>:
        result : Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Record.Record<DetailValue>>> <- failTruncatedToolCall(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, call)
        failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, tail, accumulateTruncated(DetailValue, ExecutionError, messages, result))

def failToolCallsFromTruncatedMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -DetailValue: Data, run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue>, calls: List<&2, T.AgentToolCall(Arguments)>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Record.Record<DetailValue>>>):
  failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, DetailValue, run, calls, Done{Nil{}})

def toolCallsInContent(-Arguments: Data, content: List<&2, Ai.AssistantContent<Arguments>>) -> List<&2, T.AgentToolCall(Arguments)>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantToolCall{call} <> rest: call <> toolCallsInContent(Arguments, rest)
    case _ <> rest: toolCallsInContent(Arguments, rest)

def assistantContent(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> List<&2, Ai.AssistantContent<Arguments>>:
  match message:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def collectAssistantToolCalls(-Arguments: Data, -DiagnosticDetails: Data, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> List<&2, T.AgentToolCall(Arguments)>:
  message = {assistant : Ai.AssistantMessage<Arguments, DiagnosticDetails>}
  content = {assistantContent(Arguments, DiagnosticDetails, message) : List<&2, Ai.AssistantContent<Arguments>>}
  {toolCallsInContent(Arguments, content) : List<&2, T.AgentToolCall(Arguments)>}

type PreparedToolCallBatch<-Arguments: Data> is Data:
  PreparedToolCallBatch{toolCalls: List<&2, T.AgentToolCall(Arguments)>, executionMode: T.ToolExecutionMode}

def configuredToolExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, T.ToolExecutionMode>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, configured, _, _}: configured

def availableContextTools(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>) -> List<&2, T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>:
  match context:
    case T.AgentContext{_, None{}}: {Nil{} : List<&2, T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>}
    case T.AgentContext{_, Some{reference}}: {reference : List<&2, T.AgentTool<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>>}

def prepareToolCallBatch(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> PreparedToolCallBatch<Arguments>:
  +calls = collectAssistantToolCalls(Arguments, DiagnosticDetails, assistant)
  tools = availableContextTools(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, context)
  sequential = hasSequentialToolCall(Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError, calls, tools)
  mode = Bool.pick(T.ToolExecutionMode, sequential || isSequential(configuredToolExecution(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config)), T.Sequential{}, T.Parallel{})
  PreparedToolCallBatch{calls, mode}

# The before-hook decision block after successful argument validation. The
# runtime supplies the current aborted state after the callback has settled.
type BeforeToolCallDecision is Data:
  ProceedWithToolCall{}
  RejectToolCall{message: String, terminate: Bool}

def toolBlockReason(reason: Maybe<&2, String>) -> String:
  match reason:
    case None{}: "Tool execution was blocked"
    case Some{+value}: Bool.pick(String, String.is_empty(value), "Tool execution was blocked", value)

def blockedToolCallDecision(result: T.BeforeToolCallResult) -> BeforeToolCallDecision:
  match result:
    case T.BeforeToolCallResult{Some{True{}}, reason, Some{True{}}}: RejectToolCall{toolBlockReason(reason), True{}}
    case T.BeforeToolCallResult{Some{True{}}, reason, _}: RejectToolCall{toolBlockReason(reason), False{}}
    case _: ProceedWithToolCall{}

def beforeToolCallDecision(aborted: Bool, result: Maybe<&2, T.BeforeToolCallResult>) -> BeforeToolCallDecision:
  match aborted result:
    case True{} _: {RejectToolCall{"Operation aborted", False{}} : BeforeToolCallDecision}
    case False{} None{}: {ProceedWithToolCall{} : BeforeToolCallDecision}
    case False{} Some{reference}:
      value = {reference : T.BeforeToolCallResult}
      blockedToolCallDecision(value)
