import Base
import ../../runtime/src/callback.bend as C
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as Schema
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/ref.bend as R
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as Number
import ../../ai/src/utils/transcript.bend as Transcript
import ../../ai/src/utils/event-stream.bend as Stream
import ./stream-fn.bend as StreamFn
import ../../runtime/src/record.bend as Record
import ../../runtime/src/utf16.bend as U
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/concurrent-all.bend as All
import ../../ai/src/utils/validation.bend as Validation
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/abort.bend as Abort


# Invocation-owned effect state. Message/tool payloads remain immutable values.
def ScopeOutcome(-Error: Data) -> Data: Result<&2, &2, Error, Unit>
type Failure<-Error: Data> is Data:
  Failure{index: Nat, error: Error}
type State<-Error: Data> is Data:
  State{accepting: Bool, active: Nat, nextIndex: Nat, firstFailure: Maybe<&2, Failure<Error>>, outcome: Maybe<&2, ScopeOutcome(Error)>}
type Scope<-Error: Data> is Data:
  Scope{state: R.Ref<State<Error>>, completion: D.Deferred<ScopeOutcome(Error)>, drained: D.Deferred<Unit>}
# Affine tickets prevent settling an accepted update more than once.
# Owners must complete every accepted ticket before disposing the scope.
type Ticket<-Error: Data> is Type:
  Ticket{scope: Scope<Error>, index: Nat}
type Notification<-Error: Data> is Data:
  Notification{outcome: Maybe<&2, ScopeOutcome(Error)>, drained: Bool}

def new(-Error: Data) -> IO(Scope<Error>):
  do IO<Scope<Error>>:
    state : R.Ref<State<Error>> <- R.new(State<Error>, State{True{}, 0n, 0n, None{}, None{}})
    completion : D.Deferred<ScopeOutcome(Error)> <- D.new(ScopeOutcome(Error))
    drained : D.Deferred<Unit> <- D.new(Unit)
    return Scope{state, completion, drained}

def reserve(-Error: Data, state: State<Error>) -> State<Error> & Maybe<&2, Nat>:
  match state:
    case State{True{}, active, +next, failure, outcome}: {(State{True{}, 1n+active, 1n+next, failure, outcome}, Some{next}) : State<Error> & Maybe<&2, Nat>}
    case other: {(other, None{}) : State<Error> & Maybe<&2, Nat>}

def scopeTicket(-Error: Data, scope: Scope<Error>, index: Maybe<&2, Nat>) -> Maybe<&1, Ticket<Error>>:
  match index:
    case None{}: None{}
    case Some{value}: Some{Ticket{scope, value}}

def begin(-Error: Data, +scope: Scope<Error>) -> IO(Maybe<&1, Ticket<Error>>):
  match scope:
    case Scope{state, _, _}:
      do IO<Maybe<&1, Ticket<Error>>>:
        index : Maybe<&2, Nat> <- R.modify(State<Error>, Maybe<&2, Nat>, state, current => reserve(Error, current))
        return scopeTicket(Error, scope, index)

# Before closing, already-failed updates are selected in registration order.
# After closing, the first arriving failure wins the pending completion.
def earlier(-Error: Data, +index: Nat, error: Error, previous: Maybe<&2, Failure<Error>>) -> Maybe<&2, Failure<Error>>:
  match previous:
    case None{}: Some{Failure{index, error}}
    case Some{Failure{+oldIndex, oldError}}: Some{Bool.pick(Failure<Error>, Nat.is_lt(index, oldIndex), Failure{index, error}, Failure{oldIndex, oldError})}

def preserveOutcome(-Error: Data, error: Error, outcome: Maybe<&2, ScopeOutcome(Error)>) -> Maybe<&2, ScopeOutcome(Error)>:
  match outcome:
    case None{}: Some{Fail{error}}
    case other: other

def failedState(-Error: Data, state: State<Error>, index: Nat, error: Error) -> State<Error>:
  match state:
    case State{True{}, active, next, failure, outcome}: State{True{}, active, next, earlier(Error, index, error, failure), outcome}
    case State{False{}, active, next, failure, outcome}: State{False{}, active, next, failure, preserveOutcome(Error, error, outcome)}

def completedState(-Error: Data, state: State<Error>, index: Nat, completion: ScopeOutcome(Error)) -> State<Error>:
  match completion:
    case Done{_}: state
    case Fail{error}: failedState(Error, state, index, error)

def recordedOutcome(-Error: Data, state: State<Error>) -> Maybe<&2, ScopeOutcome(Error)>:
  match state:
    case State{_, _, _, _, outcome}: outcome

def recordFailure(-Error: Data, state: State<Error>, index: Nat, completion: ScopeOutcome(Error)) -> State<Error> & Maybe<&2, ScopeOutcome(Error)>:
  +updated = completedState(Error, state, index, completion)
  (updated, recordedOutcome(Error, updated))

def publish(-Error: Data, target: D.Deferred<ScopeOutcome(Error)>, outcome: Maybe<&2, ScopeOutcome(Error)>) -> IO(Unit):
  match outcome:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        won : Bool <- D.resolve(ScopeOutcome(Error), target, value)
        return Unit{}

def signalDrained(-Error: Data, drained: D.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- D.resolve(Unit, drained, Unit{})
    return Unit{}

def notify(-Error: Data, completion: D.Deferred<ScopeOutcome(Error)>, drained: D.Deferred<Unit>, action: Notification<Error>) -> IO(Unit):
  match action:
    case Notification{outcome, ready}:
      do IO<Unit>:
        publish(Error, completion, outcome)
        Bool.pick(IO(Unit), ready, signalDrained(Error, drained), IO.pure(Unit, Unit{}))

def retire(-Error: Data, state: State<Error>) -> State<Error> & Notification<Error>:
  match state:
    case State{False{}, 1n+0n, next, failure, None{}}: {(State{False{}, 0n, next, failure, Some{Done{Unit{}}}}, Notification{Some{Done{Unit{}}}, True{}}) : State<Error> & Notification<Error>}
    case State{False{}, 1n+0n, next, failure, Some{+outcome}}: {(State{False{}, 0n, next, failure, Some{outcome}}, Notification{Some{outcome}, True{}}) : State<Error> & Notification<Error>}
    case State{accepting, 1n+active, next, failure, outcome}: {(State{accepting, active, next, failure, outcome}, Notification{None{}, False{}}) : State<Error> & Notification<Error>}
    case other: {(other, Notification{None{}, False{}}) : State<Error> & Notification<Error>}

# Publish failure before retiring the worker. Drain means no worker can still
# access scope resources, including the completion Deferred's notification phase.
def completeScope(-Error: Data, update: Ticket<Error>, outcome: ScopeOutcome(Error)) -> IO(Unit):
  match update:
    case Ticket{Scope{+state, +completion, drained}, index}:
      do IO<Unit>:
        ready : Maybe<&2, ScopeOutcome(Error)> <- R.modify(State<Error>, Maybe<&2, ScopeOutcome(Error)>, state, current => recordFailure(Error, current, index, outcome))
        publish(Error, completion, ready)
        action : Notification<Error> <- R.modify(State<Error>, Notification<Error>, state, current => retire(Error, current))
        notify(Error, completion, drained, action)

def closingOutcome(-Error: Data, active: Nat, failure: Maybe<&2, Failure<Error>>) -> Maybe<&2, ScopeOutcome(Error)>:
  match failure:
    case Some{Failure{_, error}}: Some{Fail{error}}
    case None{}: Bool.pick(Maybe<&2, ScopeOutcome(Error)>, Nat.is_eq(active, 0n), Some{Done{Unit{}}}, None{})

def closeState(-Error: Data, state: State<Error>) -> State<Error> & Notification<Error>:
  match state:
    case State{True{}, +active, next, +failure, _}:
      +outcome = closingOutcome(Error, active, failure)
      {(State{False{}, active, next, failure, outcome}, Notification{outcome, Nat.is_eq(active, 0n)}) : State<Error> & Notification<Error>}
    case other: {(other, Notification{None{}, False{}}) : State<Error> & Notification<Error>}

# Close synchronously when tool execution settles, before awaiting listeners.
def close(-Error: Data, scope: Scope<Error>) -> IO(Unit):
  match scope:
    case Scope{state, completion, drained}:
      do IO<Unit>:
        action : Notification<Error> <- R.modify(State<Error>, Notification<Error>, state, current => closeState(Error, current))
        notify(Error, completion, drained, action)

def scopeOutcome(-Error: Data, scope: Scope<Error>) -> IO(ScopeOutcome(Error)):
  match scope:
    case Scope{_, completion, _}: D.result(ScopeOutcome(Error), completion)

# Retire all retained callback aliases before disposal. Result may fail before
# every accepted update settles; disposal additionally waits for their drain.
def disposeScope(-Error: Data, scope: Scope<Error>) -> IO(Unit):
  match scope:
    case Scope{state, completion, +drained}:
      do IO<Unit>:
        finished : Unit <- D.result(Unit, drained)
        previous : State<Error> <- R.dispose(State<Error>, state)
        D.dispose(ScopeOutcome(Error), completion)
        D.dispose(Unit, drained)


# Starting delivery and awaiting it are distinct. The emitter performs ordered
# enqueue/start effects before returning; listeners may finish concurrently.
# EmissionPending delivery owns one receive and cannot be awaited twice.
type Emission<-Error: Data> is Type:
  EmissionReady{outcome: Result<&2, &2, Error, Unit>}
  EmissionPending{reply: Chan(Result<&2, &2, Error, Unit>)}

def startEmission(-Error: Data, action: IO(Result<&2, &2, Error, Unit>)) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    reply : Chan(Result<&2, &2, Error, Unit>) <- IO.fork(Result<&2, &2, Error, Unit>, action)
    return EmissionPending{reply}

def wait(-Error: Data, emission: Emission<Error>) -> IO(Result<&2, &2, Error, Unit>):
  match emission:
    case EmissionReady{outcome}: IO.pure(Result<&2, &2, Error, Unit>, outcome)
    case EmissionPending{reply}: IO.join(Result<&2, &2, Error, Unit>, reply)


type PreparedToolCall<-Details: Data, -ExecutionError: Data> is Data:
  PreparedToolCall{toolCall: T.AgentToolCall, tool: T.AgentTool<Details, ExecutionError>, args: Schema.Value}

type ImmediateToolCallOutcome<-Details: Data> is Data:
  ImmediateToolCallOutcome{result: T.AgentToolResult<Details>, isError: Bool}

type ToolCallPreparation<-Details: Data, -ExecutionError: Data> is Data:
  Prepared{value: PreparedToolCall<Details, ExecutionError>}
  Immediate{value: ImmediateToolCallOutcome<Details>}

def preparationKind(-Details: Data, -ExecutionError: Data, preparation: ToolCallPreparation<Details, ExecutionError>) -> String:
  match preparation:
    case Prepared{_}: "prepared"
    case Immediate{_}: "immediate"

type ExecutedToolCallOutcome<-Details: Data> is Data:
  ExecutedToolCallOutcome{result: T.AgentToolResult<Details>, isError: Bool}

type FinalizedToolCallOutcome<-Details: Data> is Data:
  FinalizedToolCallOutcome{toolCall: T.AgentToolCall, result: T.AgentToolResult<Details>, isError: Bool}

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

def lookupModeStep(-Details: Data, -ExecutionError: Data, name: String, tool: T.AgentTool<Details, ExecutionError>) -> Maybe<&2, Maybe<&2, T.ToolExecutionMode>>:
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

def findToolExecutionMode(-Details: Data, -ExecutionError: Data, +name: String, tools: List<&2, T.AgentTool<Details, ExecutionError>>) -> Maybe<&2, T.ToolExecutionMode>:
  match tools:
    case Nil{}: {None{} : Maybe<&2, T.ToolExecutionMode>}
    case head <> tail:
      tool = {head : T.AgentTool<Details, ExecutionError>}
      +found = {lookupModeStep(Details, ExecutionError, name, tool) : Maybe<&2, Maybe<&2, T.ToolExecutionMode>>}
      searchMore = {Bool.not(matchedMode(found)) : Bool}
      chooseSearch(searchMore, {extractedMode(found) : Maybe<&2, T.ToolExecutionMode>}, findToolExecutionMode(Details, ExecutionError, name, tail))

def isSequential(mode: Maybe<&2, T.ToolExecutionMode>) -> Bool:
  match mode:
    case Some{T.Sequential{}}: True{}
    case _: False{}

def callName(toolCall: Ai.ToolCall<Schema.Value>) -> String:
  match toolCall:
    case Ai.ToolCall{_, name, _, _, _}: name

def chooseSequential(found: Bool, rest: Bool) -> Bool:
  match found:
    case True{}: {True{} : Bool}
    case False{}: rest

def hasSequentialToolCall(-Details: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall>, +tools: List<&2, T.AgentTool<Details, ExecutionError>>) -> Bool:
  match calls:
    case Nil{}: {False{} : Bool}
    case head <> tail:
      toolCall = {head : Ai.ToolCall<Schema.Value>}
      mode = {findToolExecutionMode(Details, ExecutionError, callName(toolCall), tools) : Maybe<&2, T.ToolExecutionMode>}
      chooseSequential(isSequential(mode), hasSequentialToolCall(Details, ExecutionError, tail, tools))

# Upstream computes the per-tool scan before checking the global setting. A
# single sequential override makes the entire assistant batch sequential.
def selectToolExecutionMode(-Details: Data, -ExecutionError: Data, calls: List<&2, T.AgentToolCall>, tools: List<&2, T.AgentTool<Details, ExecutionError>>, configured: Maybe<&2, T.ToolExecutionMode>) -> T.ToolExecutionMode:
  found = {hasSequentialToolCall(Details, ExecutionError, calls, tools) : Bool}
  Bool.pick(T.ToolExecutionMode, isSequential(configured) || found, T.Sequential{}, T.Parallel{})

def resultTerminates(-Details: Data, result: T.AgentToolResult<Details>) -> Bool:
  match result:
    case T.AgentToolResult{_, _, _, Some{True{}}}: True{}
    case _: False{}

def continueTermination(terminates: Bool, rest: Bool) -> Bool:
  match terminates:
    case False{}: {False{} : Bool}
    case True{}: rest

def allTerminate(-Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Details>>) -> Bool:
  match finalizedCalls:
    case Nil{}: {True{} : Bool}
    case FinalizedToolCallOutcome{_, result, _} <> tail:
      value = {result : T.AgentToolResult<Details>}
      continueTermination(resultTerminates(Details, value), allTerminate(Details, tail))

def shouldTerminateToolBatch(-Details: Data, finalizedCalls: List<&2, FinalizedToolCallOutcome<Details>>) -> Bool:
  match finalizedCalls:
    case Nil{}: {False{} : Bool}
    case +head <> +tail: allTerminate(Details, head <> tail)

# Promise<void> | void becomes an awaited reusable IO callback. Recoverable
# listener failures are explicit; callers must propagate them without emitting
# later events. This does not establish host Promise microtask scheduling.
def AgentEventSink(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data) -> Data:
  C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>>

def toolExecutionEndEvent(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, call: Ai.ToolCall<Schema.Value>, result: T.AgentToolResult<Details>, isError: Bool) -> T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, _, _, _}: T.ToolExecutionEnd{id, name, result, isError}

def emitToolExecutionEnd(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ListenerError: Data, finalized: FinalizedToolCallOutcome<Details>, emit: AgentEventSink(DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<Result<&2, &2, ListenerError, Unit>>:
        call : Ai.ToolCall<Schema.Value> = toolCall
        C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>, Result<&2, &2, ListenerError, Unit>, emit, toolExecutionEndEvent(DiagnosticDetails, Details, Custom, PartialResult, call, result, isError))

def finishToolResultMessage(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, toolResultMessage: Ai.ToolResultMessage<Details>, emit: AgentEventSink(DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError), started: Result<&2, &2, ListenerError, Unit>) -> IO(Result<&2, &2, ListenerError, Unit>):
  match started:
    case Fail{error}: IO.pure(Result<&2, &2, ListenerError, Unit>, Fail{error})
    case Done{Unit{}}: C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})

def emitToolResultMessage(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ListenerError: Data, +toolResultMessage: Ai.ToolResultMessage<Details>, +emit: AgentEventSink(DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError)) -> IO(Result<&2, &2, ListenerError, Unit>):
  do IO<Result<&2, &2, ListenerError, Unit>>:
    started : Result<&2, &2, ListenerError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ListenerError, Unit>, emit, T.MessageStart{T.LlmMessage{Ai.ToolResult{toolResultMessage}}})
    finishToolResultMessage(DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult, ListenerError, toolResultMessage, emit, started)

def toolResultMessageAt(-Details: Data, call: Ai.ToolCall<Schema.Value>, result: T.AgentToolResult<Details>, isError: Bool, timestamp: F64) -> Ai.ToolResultMessage<Details>:
  match call result:
    case Ai.ToolCall{id, name, _, _, _} T.AgentToolResult{content, details, usage, _}:
      Ai.ToolResultMessage{id, name, content, Some{details}, usage, isError, timestamp}

def createToolResultMessage(-Details: Data, finalized: FinalizedToolCallOutcome<Details>) -> IO(Ai.ToolResultMessage<Details>):
  match finalized:
    case FinalizedToolCallOutcome{toolCall, result, isError}:
      do IO<Ai.ToolResultMessage<Details>>:
        call : Ai.ToolCall<Schema.Value> = toolCall
        value : T.AgentToolResult<Details> = result
        timestamp : F64 <- Date.now()
        IO.pure(Ai.ToolResultMessage<Details>, toolResultMessageAt(Details, call, value, isError, timestamp))

# Raw and adapter-output argument types may differ. This explicit union retains
# the original call handle when unchanged, without an unsafe reference cast.
# Neither branch means that schema validation has happened yet.
type PreparedToolCallArguments is Data:
  OriginalCall{value: T.AgentToolCall}
  ReplacedCall{value: T.AgentToolCall}

def callArguments(call: Ai.ToolCall<Schema.Value>) -> Schema.Value:
  match call:
    case Ai.ToolCall{_, _, arguments, _, _}: arguments

def replaceCallArguments(call: Ai.ToolCall<Schema.Value>, arguments: Schema.Value) -> Ai.ToolCall<Schema.Value>:
  match call:
    case Ai.ToolCall{id, name, _, signature, namespace}: Ai.ToolCall{id, name, arguments, signature, namespace}

# An adapter returns a new argument value. No reference comparison or
# observation of mutations to the original call is involved.
def afterPrepareArguments(-ExecutionError: Data, original: T.AgentToolCall, outcome: Result<&2, &2, ExecutionError, Schema.Value>) -> Result<&2, &2, ExecutionError, PreparedToolCallArguments>:
  match outcome:
    case Fail{error}: Fail{error}
    case Done{arguments}: Done{ReplacedCall{replaceCallArguments(original, arguments)}}

def prepareArgumentsWith(-ExecutionError: Data, callback: Maybe<&2, C.Callback<Schema.Value, Result<&2, &2, ExecutionError, Schema.Value>>>, +toolCall: T.AgentToolCall) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments>, Done{OriginalCall{toolCall}})
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedToolCallArguments>>:
        current : Ai.ToolCall<Schema.Value> = toolCall
        outcome : Result<&2, &2, ExecutionError, Schema.Value> <- C.call(Schema.Value, Result<&2, &2, ExecutionError, Schema.Value>, prepare, callArguments(current))
        IO.pure(Result<&2, &2, ExecutionError, PreparedToolCallArguments>, afterPrepareArguments(ExecutionError, toolCall, outcome))

def prepareToolCallArguments(-Details: Data, -ExecutionError: Data, tool: T.AgentTool<Details, ExecutionError>, toolCall: T.AgentToolCall) -> IO(Result<&2, &2, ExecutionError, PreparedToolCallArguments>):
  match tool:
    case T.AgentTool{_, _, _, _, _, prepare, _, _, _}: prepareArgumentsWith(ExecutionError, prepare, toolCall)

def copyContextMessages(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ExecutionError: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, ExecutionError>, initialMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> T.AgentContext<DiagnosticDetails, Details, Custom, ExecutionError>:
  match context:
    case T.AgentContext{messages, tools}:
      previous = {messages : List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>}
      copied = {{List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, previous, initialMessages) : List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>} : T.AgentMessageArray(DiagnosticDetails, Details, Custom)}
      {T.AgentContext{copied, tools} : T.AgentContext<DiagnosticDetails, Details, Custom, ExecutionError>}

# Only omission preserves prior reasoning; explicit off removes the provider
# field. This is the next-turn update rule, not model thinking-level clamping.
def turnReasoning(previous: Maybe<&2, Ai.ThinkingLevel>, requested: Maybe<&2, T.ThinkingLevel()>) -> Maybe<&2, Ai.ThinkingLevel>:
  match requested:
    case None{}: previous
    case Some{Ai.Off{}}: None{}
    case Some{Ai.Thinking{level}}: Some{level}

def withTurnConfig(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, replacementModel: Maybe<&2, Ai.Model<Ai.JsonValue>>, requestedThinking: Maybe<&2, T.ThinkingLevel()>) -> T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>:
  match config:
    case T.AgentLoopConfig{+options, model, convertToLlm, transformContext, getApiKey, stopHook, prepareHook, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{Ai.withReasoning(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError, options, turnReasoning(Ai.reasoningOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError, options), requestedThinking)), choose(Ai.Model<Ai.JsonValue>, model, replacementModel), convertToLlm, transformContext, getApiKey, stopHook, prepareHook, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

type PreparedTurnState<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data> is Data:
  PreparedTurnState{context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, messages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)}

def preparedMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, supplied: Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>) -> T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom):
  match supplied:
    case Some{messages}: {messages : T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)}
    case None{}: {Nil{} : List<&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>>}

def applyTurnSnapshot(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, currentContext: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, snapshot: T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>) -> PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>:
  match snapshot:
    case T.AgentLoopTurnUpdate{context, messages, model, thinkingLevel}:
      prepared = {preparedMessages(DiagnosticDetails, ToolDetails, Custom, messages) : T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)}
      previous = {config : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
      next = {withTurnConfig(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, previous, model, thinkingLevel) : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
      PreparedTurnState{choose(T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, currentContext, context), next, prepared}

def applyTurnUpdate(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, update: Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>) -> PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>:
  match update:
    case None{}:
      messages = {preparedMessages(DiagnosticDetails, ToolDetails, Custom, None{}) : T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)}
      PreparedTurnState{context, config, messages}
    case Some{value}:
      snapshot = {value : T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>}
      applyTurnSnapshot(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, snapshot)

def afterPrepareNextTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>) -> Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>:
  match outcome:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>}
    case Done{update}:
      state = {applyTurnUpdate(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, update) : PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
      Done{state}

def invokePrepareNextTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, completed: T.PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError), callback: Maybe<&2, C.Callback<T.PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>>>) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>, afterPrepareNextTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, Done{None{}}))
    case Some{prepare}:
      do IO<Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>>:
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>> <- C.call(T.PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>, prepare, completed)
        IO.pure(Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>, afterPrepareNextTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, outcome))

def selectedPrepareNextTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, value: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<T.PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, T.AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>>>:
  match value:
    case T.AgentLoopConfig{_, _, _, _, _, _, callback, _, _, _, _, _}: callback

def prepareNextTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, +config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, completed: T.PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>):
  do IO<Result<&2, &2, ExecutionError, PreparedTurnState<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>>:
    value : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    invokePrepareNextTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, completed, selectedPrepareNextTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, value))

def readQueuedMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, callback: Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  match callback:
    case Some{selected}: C.call(Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, selected, Unit{})
    case None{}:
      do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
        empty : T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom) = preparedMessages(DiagnosticDetails, ToolDetails, Custom, None{})
        return Done{empty}

def selectedSteeringMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, selected, _, _, _, _}: selected

def pollSteeringMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    readQueuedMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedSteeringMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current))

def selectedFollowUpMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<Unit, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, selected, _, _, _}: selected

def pollFollowUpMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
    current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    readQueuedMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedFollowUpMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current))

# After preparation, only repoll steering when the previous array is empty.
# A retained pending message must not consume a second one-at-a-time delivery.
# Read its live contents before selecting the current configuration callback.
def repollSteeringContents(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, pending: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), contents: List<&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  match contents:
    case Nil{}: pollSteeringMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config)
    case _ <> _: IO.pure(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Done{pending})

def repollSteeringMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, +pending: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  do IO<Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
    contents : List<&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>> = pending
    repollSteeringContents(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, pending, contents)

# A missing stop hook is false. Recoverable hook errors are not stop requests.
def invokeShouldStopAfterTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, callback: Maybe<&2, C.Callback<T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case Some{selected}: C.call(T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, Result<&2, &2, ExecutionError, Bool>, selected, completed)

def selectedShouldStopAfterTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, callback, _, _, _, _, _, _}: callback

def shouldStopAfterTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  do IO<Result<&2, &2, ExecutionError, Bool>>:
    current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    invokeShouldStopAfterTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, completed, selectedShouldStopAfterTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current))

def stoppedTurnResult(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{None{}}

def queuedTurnResult(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, queued: Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>) -> Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>:
  match queued:
    case Fail{error}: Fail{error}
    case Done{messages}: Done{Some{messages}}

def afterTurnDecision(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, newMessages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), decision: Result<&2, &2, ExecutionError, Bool>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>):
  match decision:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>, Fail{error})
    case Done{True{}}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.AgentEnd{newMessages})
        return stoppedTurnResult(DiagnosticDetails, ToolDetails, Custom, ExecutionError, emitted)
    case Done{False{}}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
        queued : Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)> <- pollSteeringMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config)
        return queuedTurnResult(DiagnosticDetails, ToolDetails, Custom, ExecutionError, queued)

# The runLoop block after turn_end and completed-context construction. None
# means agent_end settled; Some supplies pending steering to the inner loop.
# Hook/emit errors skip polling. The supplied message history is the
# immutable value delivered to agent_end.
def finishCompletedTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data, +config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, newMessages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
    decision : Result<&2, &2, ExecutionError, Bool> <- shouldStopAfterTurn(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, completed)
    afterTurnDecision(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult, config, newMessages, emit, decision)

def contextMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>) -> T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom):
  match context:
    case T.AgentContext{messages, _}: messages

def invokeContextTransform(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, messages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), signal: Maybe<&2, Abort.AbortSignal<Unit>>, callback: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>) -> IO(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Done{messages})
    case Some{selected}: C.call(T.TransformContextInput<T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, selected, T.TransformContextInput{messages, signal})

def selectedContextTransform(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, selected, _, _, _, _, _, _, _, _}: selected

def selectedMessageConverter(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> C.Callback<T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>>:
  match config:
    case T.AgentLoopConfig{_, _, selected, _, _, _, _, _, _, _, _, _}: selected

def convertTransformedMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, transformed: Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>) -> IO(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>):
  match transformed:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>, Fail{error})
    case Done{messages}:
      do IO<Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>>:
        current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
        C.call(T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>, selectedMessageConverter(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current), messages)

def convertContextMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, +config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>):
  do IO<Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>>:
    captured : T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError> = context
    current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    transformed : Result<&2, &2, ExecutionError, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)> <- invokeContextTransform(DiagnosticDetails, ToolDetails, Custom, ExecutionError, contextMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, captured), signal, selectedContextTransform(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current))
    convertTransformedMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, transformed)

def selectedApiKey(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, String>:
  match config:
    case T.AgentLoopConfig{options, _, _, _, _, _, _, _, _, _, _, _}: Ai.apiKeyOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError, options)

def selectedApiKeyResolver(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, selected, _, _, _, _, _, _, _}: selected

def selectedRequestModel(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Ai.Model<Ai.JsonValue>:
  match config:
    case T.AgentLoopConfig{_, selected, _, _, _, _, _, _, _, _, _, _}: selected

def requestModelProvider(-Value: Data, model: Ai.Model<Value>) -> String:
  match model:
    case Ai.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _}: provider

# Source uses logical OR, so an empty resolved key falls back just like absence.
# The fallback itself is returned unchanged, including an empty string.
def hasResolvedApiKey(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{key}: Bool.not(String.eq(key, ""))

def fallbackApiKey(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  current = {config : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
  Done{selectedApiKey(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current)}

def selectResolvedApiKey(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, resolved: Maybe<&2, String>, present: Bool) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  match present:
    case True{}: {Done{resolved} : Result<&2, &2, ExecutionError, Maybe<&2, String>>}
    case False{}: fallbackApiKey(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config)

def afterApiKeyResolver(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, outcome: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> Result<&2, &2, ExecutionError, Maybe<&2, String>>:
  match outcome:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, Maybe<&2, String>>}
    case Done{+key}: selectResolvedApiKey(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, key, hasResolvedApiKey(key))

def invokeApiKeyResolver(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, model: Ai.Model<Ai.JsonValue>, callback: Maybe<&2, C.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, fallbackApiKey(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config))
    case Some{selected}:
      do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
        currentModel : Ai.Model<Ai.JsonValue> = model
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- C.call(String, Result<&2, &2, ExecutionError, Maybe<&2, String>>, selected, requestModelProvider(Ai.JsonValue, currentModel))
        IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, String>>, afterApiKeyResolver(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, outcome))

# Called after context normalization for every assistant request. A resolver
# can obtain rotated credentials; an empty result uses the configured fallback.
def resolveApiKey(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, +config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, String>>):
  do IO<Result<&2, &2, ExecutionError, Maybe<&2, String>>>:
    +current : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = config
    invokeApiKeyResolver(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, selectedRequestModel(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current), selectedApiKeyResolver(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current))

def normalizeConvertedMessages(-DiagnosticDetails: Data, -ToolDetails: Data, -ExecutionError: Data, converted: Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>) -> Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>:
  match converted:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>}
    case Done{messages}:
      value = {Transcript.normalizeContext(Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails, Ai.Context{None{}, messages, None{}}) : Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>}
      context = {value : Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>}
      Done{context}

def prepareLlmContext(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>):
  do IO<Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>:
    converted : Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>> <- convertContextMessages(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, context, config, signal)
    IO.pure(Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>, normalizeConvertedMessages(DiagnosticDetails, ToolDetails, ExecutionError, converted))

def withRequestOverrides(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, resolvedApiKey: Maybe<&2, String>, requestSignal: Maybe<&2, Abort.AbortSignal<Unit>>) -> T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>:
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{Ai.withApiKey(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError, Ai.withSignal(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError, options, requestSignal), resolvedApiKey), model, convertToLlm, transformContext, getApiKey, stopCallback, prepareCallback, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def snapshotRequestConfig(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, requestSignal: Maybe<&2, Abort.AbortSignal<Unit>>, resolved: Result<&2, &2, ExecutionError, Maybe<&2, String>>) -> Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>:
  match resolved:
    case Fail{error}: {Fail{error} : Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>}
    case Done{apiKey}:
      current = {config : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
      copied = {withRequestOverrides(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current, apiKey, requestSignal) : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>}
      Done{copied}

def resolveRequestConfig(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, +config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, requestSignal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>):
  do IO<Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>>:
    resolved : Result<&2, &2, ExecutionError, Maybe<&2, String>> <- resolveApiKey(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config)
    IO.pure(Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>, snapshotRequestConfig(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, requestSignal, resolved))

def snapshotAssistantMessage(-DiagnosticDetails: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>) -> Ai.AssistantMessage<Schema.Value, DiagnosticDetails>:
  message

type AssistantResponseConsumer<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantResponseConsumer{context: R.Ref<T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), response: Stream.AssistantMessageEventStream(Schema.Value, DiagnosticDetails)}

type AssistantResponseStep<-DiagnosticDetails: Data, -ExecutionError: Data> is Data:
  ResponseContinue{started: Bool}
  ResponseComplete{message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>}
  ResponseFailed{error: ExecutionError}

def replaceLastMessage(-Message: Data, values: List<&2, Message>, replacement: Message) -> List<&2, Message>:
  match values:
    case Nil{}: replacement <> Nil{}
    case _ <> Nil{}: replacement <> Nil{}
    case head <> tail: head <> replaceLastMessage(Message, tail, replacement)

# Pure transition used atomically by the running agent's state cell.
def withAssistantMessage(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, current: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, replace: Bool) -> T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>:
  match current:
    case T.AgentContext{+messages, tools}:
      +wrapped = {T.LlmMessage{Ai.Assistant{message}} : T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>}
      T.AgentContext{Bool.pick(List<&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>>, replace, replaceLastMessage(T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>, messages, wrapped), List.append(&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>, messages, wrapped <> Nil{})), tools}

def recordAssistantMessage(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, context: R.Ref<T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, replace: Bool) -> IO(Unit):
  R.modify(T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, Unit, context, current => (withAssistantMessage(DiagnosticDetails, ToolDetails, Custom, ExecutionError, current, message, replace), Unit{}))

def partialAgentEvent(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, source: Maybe<&2, Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>>) -> T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>:
  match source:
    case None{}: T.MessageStart{T.LlmMessage{Ai.Assistant{message}}}
    case Some{event}: T.MessageUpdate{T.LlmMessage{Ai.Assistant{message}}, event}

def emitAssistantSnapshot(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, source: Maybe<&2, Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>>) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match consumer:
    case AssistantResponseConsumer{_, emit, _}:
      do IO<Result<&2, &2, ExecutionError, Unit>>:
        +snapshot : Ai.AssistantMessage<Schema.Value, DiagnosticDetails> = snapshotAssistantMessage(DiagnosticDetails, message)
        C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, partialAgentEvent(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, snapshot, source))

def afterResponseEmission(-DiagnosticDetails: Data, -ExecutionError: Data, started: Bool, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseContinue{started}

def startAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, +partial: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, _}:
      do IO<AssistantResponseStep<DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(DiagnosticDetails, ToolDetails, Custom, ExecutionError, context, partial, False{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, partial, None{})
        return afterResponseEmission(DiagnosticDetails, ExecutionError, True{}, emitted)

def responseEventPartial(-DiagnosticDetails: Data, event: Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>) -> Maybe<&2, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>:
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

def updateAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, source: Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, partial: Maybe<&2, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, started: Bool) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match consumer partial started:
    case AssistantResponseConsumer{context, _, _} Some{+message} True{}:
      do IO<AssistantResponseStep<DiagnosticDetails, ExecutionError>>:
        recordAssistantMessage(DiagnosticDetails, ToolDetails, Custom, ExecutionError, context, message, True{})
        emitted : Result<&2, &2, ExecutionError, Unit> <- emitAssistantSnapshot(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, message, Some{source})
        return afterResponseEmission(DiagnosticDetails, ExecutionError, True{}, emitted)
    case _ _ _: IO.pure(AssistantResponseStep<DiagnosticDetails, ExecutionError>, ResponseContinue{started})


def completeResponseEmission(-DiagnosticDetails: Data, -ExecutionError: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, emitted: Result<&2, &2, ExecutionError, Unit>) -> AssistantResponseStep<DiagnosticDetails, ExecutionError>:
  match emitted:
    case Fail{error}: ResponseFailed{error}
    case Done{_}: ResponseComplete{message}

def endAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, +message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, started: Result<&2, &2, ExecutionError, Unit>) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match consumer started:
    case _ Fail{error}: IO.pure(AssistantResponseStep<DiagnosticDetails, ExecutionError>, ResponseFailed{error})
    case AssistantResponseConsumer{_, emit, _} Done{_}:
      do IO<AssistantResponseStep<DiagnosticDetails, ExecutionError>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.MessageEnd{T.LlmMessage{Ai.Assistant{message}}})
        return completeResponseEmission(DiagnosticDetails, ExecutionError, message, emitted)


def maybeStartFinalResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, started: Bool) -> IO(Result<&2, &2, ExecutionError, Unit>):
  match started:
    case True{}: IO.pure(Result<&2, &2, ExecutionError, Unit>, Done{Unit{}})
    case False{}: emitAssistantSnapshot(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, message, None{})

def finishAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, +started: Bool) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match consumer:
    case AssistantResponseConsumer{context, _, response}:
      do IO<AssistantResponseStep<DiagnosticDetails, ExecutionError>>:
        +message : Ai.AssistantMessage<Schema.Value, DiagnosticDetails> <- Stream.resultValue(Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, response)
        recordAssistantMessage(DiagnosticDetails, ToolDetails, Custom, ExecutionError, context, message, started)
        emitted : Result<&2, &2, ExecutionError, Unit> <- maybeStartFinalResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, message, started)
        endAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, message, emitted)

def handleAssistantResponseEvent(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, started: Bool, +event: Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match event:
    case Ai.Start{partial}: startAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, partial)
    case Ai.StreamDone{_, _}: finishAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case Ai.StreamError{_, _}: finishAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case _: updateAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, event, responseEventPartial(DiagnosticDetails, event), started)

def handleAssistantIteration(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, started: Bool, next: Stream.Iteration<Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>>) -> IO(AssistantResponseStep<DiagnosticDetails, ExecutionError>):
  match next:
    case Stream.End{}: finishAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, started)
    case Stream.Yield{event}: handleAssistantResponseEvent(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, started, event)

# Guarded IO recursion: each continuation awaits one iterator result.
@unsafe
def consumeAssistantIterations(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>, +cursor: Stream.Iterator<Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, state: AssistantResponseStep<DiagnosticDetails, ExecutionError>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match state:
    case ResponseFailed{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, Fail{error})
    case ResponseComplete{message}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, Done{message})
    case ResponseContinue{started}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        next : Stream.Iteration<Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>> <- Stream.nextValue(Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, cursor)
        step : AssistantResponseStep<DiagnosticDetails, ExecutionError> <- handleAssistantIteration(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, started, next)
        consumeAssistantIterations(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, step)

def consumeAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, +consumer: AssistantResponseConsumer<DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match consumer:
    case AssistantResponseConsumer{_, _, response}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        +cursor : Stream.Iterator<Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>> <- Stream.iterator(Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, response)
        result : Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>> <- consumeAssistantIterations(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, consumer, cursor, ResponseContinue{False{}})
        Stream.disposeIterator(Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, cursor)
        return result

type AssistantRequest<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AssistantRequest{context: R.Ref<T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), streamFunction: T.StreamFn(DiagnosticDetails, ToolDetails, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, ExecutionError)}

# The lease is released after the loop's last read. An earlier failure wins
# over a release failure; a clean release keeps the message.
def released(-DiagnosticDetails: Data, -ExecutionError: Data, result: Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, cleanup: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>:
  match result cleanup:
    case Fail{error} _: Fail{error}
    case Done{message} Done{_}: Done{message}
    case Done{_} Fail{error}: Fail{error}

def openedAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, context: R.Ref<T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), opened: Result<&2, &1, ExecutionError, T.StreamLease<DiagnosticDetails, ExecutionError>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match opened:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, Fail{error})
    case Done{T.StreamLease{events, release}}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        result : Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>> <- consumeAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, AssistantResponseConsumer{context, emit, events})
        cleanup : Result<&2, &2, ExecutionError, Unit> <- release
        return released(DiagnosticDetails, ExecutionError, result, cleanup)

def dispatchAssistantRequest(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data, request: AssistantRequest<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult>, normalized: Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>, resolved: Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match request resolved:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, Fail{error})
    case AssistantRequest{context, _, _, emit, streamFunction} Done{+options}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        value : T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry> = options
        response : Result<&2, &1, ExecutionError, T.StreamLease<DiagnosticDetails, ExecutionError>> <- C.call(T.StreamInput<DiagnosticDetails, ToolDetails, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>>, Result<&2, &1, ExecutionError, T.StreamLease<DiagnosticDetails, ExecutionError>>, streamFunction, T.StreamInput{selectedRequestModel(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, value), normalized, Some{options}})
        openedAssistantResponse(DiagnosticDetails, ToolDetails, Custom, ExecutionError, PartialResult, ExecutionResult, context, emit, response)

def afterLlmContext(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult>, prepared: Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match request prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>, Fail{error})
    case AssistantRequest{_, config, signal, _, _} Done{+normalized}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        resolved : Result<&2, &2, ExecutionError, T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>> <- resolveRequestConfig(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config, signal)
        dispatchAssistantRequest(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult, request, normalized, resolved)

def streamAssistantResponse(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, -PartialResult: Data, -ExecutionResult: Data, +request: AssistantRequest<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>):
  match request:
    case AssistantRequest{context, config, signal, _, _}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>>:
        current : T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError> <- R.read(T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, context)
        prepared : Result<&2, &2, ExecutionError, Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>> <- prepareLlmContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, current, config, signal)
        afterLlmContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, PartialResult, ExecutionResult, request, prepared)

def assistantFailed(-DiagnosticDetails: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, _, _, _, _}: True{}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, _, _, _, _}: True{}
    case _: False{}

def afterFailedAgentEnd(-ExecutionError: Data, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Bool>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{True{}}

def afterFailedTurnEnd(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, messages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, ExecutionError, Bool>>:
        ended : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.AgentEnd{messages})
        return afterFailedAgentEnd(ExecutionError, ended)

def endFailedAssistantTurn(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, messages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), +emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), failed: Bool) -> IO(Result<&2, &2, ExecutionError, Bool>):
  match failed:
    case False{}: IO.pure(Result<&2, &2, ExecutionError, Bool>, Done{False{}})
    case True{}:
      do IO<Result<&2, &2, ExecutionError, Bool>>:
        +results : List<&2, Ai.ToolResultMessage<ToolDetails>> = Nil{}
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Result<&2, &2, ExecutionError, Unit>, emit, T.TurnEnd{T.LlmMessage{Ai.Assistant{message}}, results})
        afterFailedTurnEnd(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, messages, emit, emitted)

type AssistantCompletion<-Message: Data> is Data:
  AssistantCompletion{messages: List<&2, Message>, failed: Bool}

def completionResult(-Message: Data, -Error: Data, messages: List<&2, Message>, result: Result<&2, &2, Error, Bool>) -> Result<&2, &2, Error, AssistantCompletion<Message>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{failed}: Done{AssistantCompletion{messages, failed}}

def recordAssistantCompletion(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -ExecutionError: Data, +message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, +messages: T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), emit: AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError)) -> IO(Result<&2, &2, ExecutionError, AssistantCompletion<T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>>>):
  do IO<Result<&2, &2, ExecutionError, AssistantCompletion<T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>>>>:
    +updated : List<&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>> = List.append(&2, T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>, messages, T.LlmMessage{Ai.Assistant{message}} <> Nil{})
    outcome : Result<&2, &2, ExecutionError, Bool> <- endFailedAssistantTurn(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError, message, updated, emit, assistantFailed(DiagnosticDetails, message))
    return completionResult(T.AgentMessage<DiagnosticDetails, ToolDetails, Custom>, ExecutionError, updated, outcome)

type ExecutedToolCallBatch<-Details: Data> is Data:
  ExecutedToolCallBatch{messages: List<&2, Ai.ToolResultMessage<Details>>, terminate: Bool}

def createErrorToolResult(-DetailValue: Data, message: String) -> T.AgentToolResult<Record.Record<DetailValue>>:
  T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, Record.new(DetailValue), None{}, None{}}

# Failure details are supplied by the caller, preserving the tool result type.
type TruncatedToolCallRun<-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data> is Data:
  TruncatedToolCallRun{emit: AgentEventSink(DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ExecutionError), emptyDetails: Details}

def truncatedCallError(call: Ai.ToolCall<Schema.Value>) -> String:
  match call:
    case Ai.ToolCall{_, name, _, _, _}: "Tool call \"" ++ name ++ "\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."

def toolExecutionStartEvent(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -Details: Data, call: Ai.ToolCall<Schema.Value>) -> T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

def deliveredTruncatedResult(-Details: Data, -ExecutionError: Data, message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{message}

def afterTruncatedExecutionEnd(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, run: TruncatedToolCallRun<DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, finalized: FinalizedToolCallOutcome<Details>, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>, Fail{error})
    case TruncatedToolCallRun{emit, emptyDetails} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Details, finalized)
        delivered : Result<&2, &2, ExecutionError, Unit> <- emitToolResultMessage(DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ExecutionError, message, emit)
        return deliveredTruncatedResult(Details, ExecutionError, message, delivered)

def afterTruncatedStart(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, +call: T.AgentToolCall, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>, Fail{error})
    case TruncatedToolCallRun{emit, emptyDetails} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        result : T.AgentToolResult<Details> = T.AgentToolResult{Ai.TextImageText{Ai.TextContent{truncatedCallError(call), None{}}} <> Nil{}, emptyDetails, None{}, None{}}
        +finalized : FinalizedToolCallOutcome<Details> = FinalizedToolCallOutcome{call, result, True{}}
        ended : Result<&2, &2, ExecutionError, Unit> <- emitToolExecutionEnd(DiagnosticDetails, Details, Custom, PartialResult, ExecutionError, finalized, emit)
        afterTruncatedExecutionEnd(DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, finalized, ended)

def failTruncatedToolCall(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, +call: T.AgentToolCall) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run:
    case TruncatedToolCallRun{emit, emptyDetails}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>, Result<&2, &2, ExecutionError, Unit>, emit, toolExecutionStartEvent(DiagnosticDetails, Custom, PartialResult, Details, call))
        afterTruncatedStart(DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, call, emitted)

def accumulateTruncated(-Details: Data, -ExecutionError: Data, previous: List<&2, Ai.ToolResultMessage<Details>>, result: Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>) -> Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Details>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{message}: Done{message <> previous}

def failTruncatedCalls(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, calls: List<&2, T.AgentToolCall>, state: Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Details>>>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>):
  match calls state:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>, Fail{error})
    case Nil{} Done{messages}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>, Done{ExecutedToolCallBatch{List.reverse(&2, Ai.ToolResultMessage<Details>, messages), False{}}})
    case call <> tail Done{messages}:
      do IO<Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>>:
        result : Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>> <- failTruncatedToolCall(DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, call)
        failTruncatedCalls(DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, tail, accumulateTruncated(Details, ExecutionError, messages, result))

def failToolCallsFromTruncatedMessage(-DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, run: TruncatedToolCallRun<DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, calls: List<&2, T.AgentToolCall>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>):
  failTruncatedCalls(DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, calls, Done{Nil{}})

def toolCallsInContent(content: List<&2, Ai.AssistantContent<Schema.Value>>) -> List<&2, T.AgentToolCall>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantToolCall{call} <> rest: call <> toolCallsInContent(rest)
    case _ <> rest: toolCallsInContent(rest)

def collectAssistantToolCalls(-DiagnosticDetails: Data, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>) -> List<&2, T.AgentToolCall>:
  message = {assistant : Ai.AssistantMessage<Schema.Value, DiagnosticDetails>}
  content = {Ai.assistantContent(Schema.Value, DiagnosticDetails, message) : List<&2, Ai.AssistantContent<Schema.Value>>}
  {toolCallsInContent(content) : List<&2, T.AgentToolCall>}

type PreparedToolCallBatch is Data:
  PreparedToolCallBatch{toolCalls: List<&2, T.AgentToolCall>, executionMode: T.ToolExecutionMode}

def configuredToolExecution(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, T.ToolExecutionMode>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, configured, _, _}: configured

def availableContextTools(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>) -> List<&2, T.AgentTool<ToolDetails, ExecutionError>>:
  match context:
    case T.AgentContext{_, None{}}: {Nil{} : List<&2, T.AgentTool<ToolDetails, ExecutionError>>}
    case T.AgentContext{_, Some{reference}}: {reference : List<&2, T.AgentTool<ToolDetails, ExecutionError>>}

def prepareToolCallBatch(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> PreparedToolCallBatch:
  +calls = collectAssistantToolCalls(DiagnosticDetails, assistant)
  tools = availableContextTools(DiagnosticDetails, ToolDetails, Custom, ExecutionError, context)
  sequential = hasSequentialToolCall(ToolDetails, ExecutionError, calls, tools)
  mode = Bool.pick(T.ToolExecutionMode, sequential || isSequential(configuredToolExecution(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config)), T.Sequential{}, T.Parallel{})
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

# Error values remain typed; formatting occurs only at the tool-result boundary.
def failedToolOutcome(-Details: Data, -Error: Data, details: Details, renderError: Error -> String, error: Error) -> ExecutedToolCallOutcome<Details>:
  ExecutedToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{renderError(error), None{}}} <> Nil{}, details, None{}, None{}}, True{}}

def resolveToolHookResult(-Details: Data, -Error: Data, executed: ExecutedToolCallOutcome<Details>, failureDetails: Details, renderError: Error -> String, outcome: Result<&2, &2, Error, Maybe<&2, T.AfterToolCallResult<Details>>>) -> ExecutedToolCallOutcome<Details>:
  match outcome:
    case Fail{error}: failedToolOutcome(Details, Error, failureDetails, renderError, error)
    case Done{patch}: applyAfterToolCallResult(Details, executed, patch)

def finalizeToolOutcome(-Details: Data, call: Ai.ToolCall<Schema.Value>, executed: ExecutedToolCallOutcome<Details>) -> FinalizedToolCallOutcome<Details>:
  match executed:
    case ExecutedToolCallOutcome{result, isError}: FinalizedToolCallOutcome{call, result, isError}

def selectedAfterToolCall(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, hook}: hook

def invokeAfterToolCall(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, hook: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>>>, input: T.ToolHookInput<T.AfterToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>, Done{None{}})
    case Some{callback}: C.call(T.ToolHookInput<T.AfterToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>, callback, input)

# The hook sees validated execution arguments alongside the original call.
# Failure becomes an error tool result; it is not an event-listener failure.
def finalizeExecutedToolCall(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, prepared: PreparedToolCall<ToolDetails, ExecutionError>, executed: ExecutedToolCallOutcome<ToolDetails>, config: T.AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, failureDetails: ToolDetails, renderError: ExecutionError -> String) -> IO(FinalizedToolCallOutcome<ToolDetails>):
  match prepared executed:
    case PreparedToolCall{+call, _, args} ExecutedToolCallOutcome{+result, +isError}:
      do IO<FinalizedToolCallOutcome<ToolDetails>>:
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>> <- invokeAfterToolCall(DiagnosticDetails, ToolDetails, Custom, ExecutionError, selectedAfterToolCall(DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry, config), T.ToolHookInput{T.AfterToolCallContext{assistant, call, args, result, isError, context}, signal})
        return finalizeToolOutcome(ToolDetails, call, resolveToolHookResult(ToolDetails, ExecutionError, ExecutedToolCallOutcome{result, isError}, failureDetails, renderError, outcome))

# Agent-end settles the returned message history independently of consumption.
def AgentEventStream(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data) -> Data:
  Stream.EventStream<T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>

def agentStreamComplete(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, unused: Unit, event: T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Bool):
  match event:
    case T.AgentEnd{_}: IO.pure(Bool, True{})
    case _: IO.pure(Bool, False{})

def agentStreamExtract(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, unused: Unit, event: T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)):
  match event:
    case T.AgentEnd{messages}: IO.pure(T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), messages)
    case _: IO.pure(T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), Nil{})

def createAgentStream(~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data) -> IO(AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)):
  do IO<AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)>:
    check : C.Callback<T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Bool> <- C.create(~Unit, ~T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Bool, ~(agentStreamComplete(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)), Unit{})
    extract : C.Callback<T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)> <- C.create(~Unit, ~T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), ~(agentStreamExtract(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)), Unit{})
    Stream.create(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), check, extract)

def disposeAgentStream(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, +stream: AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)) -> IO(Unit):
  match stream:
    case Stream.EventStream{_, _, check, extract}:
      do IO<Unit>:
        Stream.dispose(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), stream)
        C.dispose(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Bool, check)
        C.dispose(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), extract)

# The update emitter returns a delivery handle after its ordered start effects.
# This is the native equivalent of invoking an async sink without awaiting it.
type ToolUpdateCapture<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  ToolUpdateCapture{scope: Scope<Error>, call: Ai.ToolCall<Schema.Value>, emit: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>}

type ToolUpdateRun<-Details: Data, -Error: Data> is Data:
  ToolUpdateRun{scope: Scope<Error>, callback: T.AgentToolUpdateCallback(Details)}

def finishToolUpdate(-Error: Data, ticket: Ticket<Error>, emission: Emission<Error>) -> IO(Unit):
  do IO<Unit>:
    outcome : Result<&2, &2, Error, Unit> <- wait(Error, emission)
    completeScope(Error, ticket, outcome)

def trackToolUpdate(-Error: Data, ticket: Ticket<Error>, emission: Emission<Error>) -> IO(Unit):
  match emission:
    case EmissionReady{outcome}: completeScope(Error, ticket, outcome)
    case EmissionPending{reply}: IO.spawn(Unit, finishToolUpdate(Error, ticket, EmissionPending{reply}))

def emitAcceptedToolUpdate(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, ticket: Maybe<&1, Ticket<Error>>, call: Ai.ToolCall<Schema.Value>, partial: T.AgentToolResult<Details>, emit: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>) -> IO(Unit):
  match ticket call:
    case None{} _: IO.pure(Unit, Unit{})
    case Some{accepted} Ai.ToolCall{id, name, arguments, _, _}:
      do IO<Unit>:
        delivery : Emission<Error> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>, emit, T.ToolExecutionUpdate{id, name, arguments, partial})
        trackToolUpdate(Error, accepted, delivery)

def forwardToolUpdate(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, capture: ToolUpdateCapture<DiagnosticDetails, Details, Custom, Error>, partial: T.AgentToolResult<Details>) -> IO(Unit):
  match capture:
    case ToolUpdateCapture{scope, call, emit}:
      do IO<Unit>:
        ticket : Maybe<&1, Ticket<Error>> <- begin(Error, scope)
        emitAcceptedToolUpdate(DiagnosticDetails, Details, Custom, Error, ticket, call, partial, emit)

def createToolUpdateRun(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, call: Ai.ToolCall<Schema.Value>, emit: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>) -> IO(ToolUpdateRun<Details, Error>):
  do IO<ToolUpdateRun<Details, Error>>:
    +scope : Scope<Error> <- new(Error)
    callback : T.AgentToolUpdateCallback(Details) <- C.create(~ToolUpdateCapture<DiagnosticDetails, Details, Custom, Error>, ~T.AgentToolResult<Details>, ~Unit, ~(forwardToolUpdate(DiagnosticDetails, Details, Custom, Error)), ToolUpdateCapture{scope, call, emit})
    return ToolUpdateRun{scope, callback}

# A run owns the callback's tombstone until all tool-held aliases retire.
# Waiting for the update result alone does not establish that lifetime boundary.
def disposeToolUpdateRun(-Details: Data, -Error: Data, run: ToolUpdateRun<Details, Error>) -> IO(Unit):
  match run:
    case ToolUpdateRun{scope, callback}:
      do IO<Unit>:
        disposeScope(Error, scope)
        C.dispose(T.AgentToolResult<Details>, Unit, callback)

def executionOutcome(-Details: Data, -Error: Data, executed: Result<&2, &2, Error, T.AgentToolResult<Details>>, failureDetails: Details, renderError: Error -> String) -> ExecutedToolCallOutcome<Details>:
  match executed:
    case Done{value}: ExecutedToolCallOutcome{value, False{}}
    case Fail{error}: failedToolOutcome(Details, Error, failureDetails, renderError, error)

def checkedExecutionOutcome(-Details: Data, -Error: Data, executed: Result<&2, &2, Error, T.AgentToolResult<Details>>, updates: Result<&2, &2, Error, Unit>, failureDetails: Details, renderError: Error -> String) -> Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>:
  match updates:
    case Fail{error}: Fail{error}
    case Done{_}: Done{executionOutcome(Details, Error, executed, failureDetails, renderError)}

# One fresh update run per invocation. The caller retains its lifetime owner
# after this returns so a tool's retained update callback safely becomes a no-op.
def executePreparedToolCall(-Details: Data, -Error: Data, prepared: PreparedToolCall<Details, Error>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, run: ToolUpdateRun<Details, Error>, failureDetails: Details, renderError: Error -> String) -> IO(Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>):
  match prepared run:
    case PreparedToolCall{Ai.ToolCall{id, _, _, _, _}, T.AgentTool{_, _, _, _, _, _, execute, _, _}, args} ToolUpdateRun{+scope, callback}:
      do IO<Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>>:
        executed : Result<&2, &2, Error, T.AgentToolResult<Details>> <- C.call(T.ToolExecutionInput<Details>, Result<&2, &2, Error, T.AgentToolResult<Details>>, execute, T.ToolExecutionInput{id, args, signal, Some{callback}})
        close(Error, scope)
        settled : Result<&2, &2, Error, Unit> <- scopeOutcome(Error, scope)
        return checkedExecutionOutcome(Details, Error, executed, settled, failureDetails, renderError)

# Native sinks distinguish ordered initiation from optional async completion.
def StartingAgentEventSink(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data) -> Data:
  C.Callback<T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Emission<Error>>

def awaitStartedEvent(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data, emitter: StartingAgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error), event: T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    delivery : Emission<Error> <- C.call(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Emission<Error>, emitter, event)
    wait(Error, delivery)

# The adapter owns only its wrapper; its emitter remains caller-owned.
def createAwaitedEventSink(~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data, ~Error: Data, emitter: StartingAgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)) -> IO(AgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)):
  C.create(~StartingAgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error), ~T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Result<&2, &2, Error, Unit>, ~(awaitStartedEvent(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)), emitter)

def startAgentStreamEvent(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data, stream: AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult), event: T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    Stream.push(T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), stream, event)
    return EmissionReady{Done{Unit{}}}

def createAgentStreamEmitter(~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data, ~Error: Data, stream: AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)) -> IO(StartingAgentEventSink(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)):
  C.create(~AgentEventStream(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult), ~T.AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Emission<Error>, ~(startAgentStreamEvent(DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)), stream)

# Validation remains an explicit required service until the canonical typed
# schema compiler supplies it. Both raw and adapted calls must be validated.
type ToolValidationInput is Data:
  ToolValidationInput{tool: Ai.Tool<Schema.Value>, call: PreparedToolCallArguments}

type ToolPreparationState<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  ToolPreparationState{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, preparation: ToolCallPreparation<Details, Error>}

def executableToolName(-Details: Data, -Error: Data, tool: T.AgentTool<Details, Error>) -> String:
  match tool:
    case T.AgentTool{name, _, _, _, _, _, _, _, _}: name

def findExecutableTool(-Details: Data, -Error: Data, +name: String, tools: List<&2, T.AgentTool<Details, Error>>) -> Maybe<&2, T.AgentTool<Details, Error>>:
  match tools:
    case Nil{}: None{}
    case +tool <> rest:
      matches = String.eq(name, executableToolName(Details, Error, tool))
      selected = Bool.pick(Unit -> Maybe<&2, T.AgentTool<Details, Error>>, matches, unused => Some{tool}, unused => findExecutableTool(Details, Error, name, rest))
      selected(Unit{})

def immediatePreparation(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, message: String, details: Details, terminate: Bool) -> ToolPreparationState<DiagnosticDetails, Details, Custom, Error>:
  result = {T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, details, None{}, Bool.pick(Maybe<&2, Bool>, terminate, Some{True{}}, None{})} : T.AgentToolResult<Details>}
  ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{result, True{}}}}

def checkedArgumentPreparation(-Details: Data, -Error: Data, tool: T.AgentTool<Details, Error>, prepared: Result<&2, &2, Error, PreparedToolCallArguments>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>) -> IO(Result<&2, &2, Error, Schema.Value>):
  match prepared:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Schema.Value>, Fail{error})
    case Done{call}: C.call(ToolValidationInput, Result<&2, &2, Error, Schema.Value>, validate, ToolValidationInput{T.toTool(Details, Error, tool), call})

def selectedBeforeToolCall(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<DiagnosticDetails, Details, Custom, Error>>, Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, hook, _}: hook

def invokeBeforeToolCall(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, call: Ai.ToolCall<Schema.Value>, args: Schema.Value, signal: Maybe<&2, Abort.AbortSignal<Unit>>, hook: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<DiagnosticDetails, Details, Custom, Error>>, Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>>>) -> IO(Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>, Done{T.BeforeToolCallUpdate{args, context, None{}}})
    case Some{callback}: C.call(T.ToolHookInput<T.BeforeToolCallContext<DiagnosticDetails, Details, Custom, Error>>, Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>, callback, T.ToolHookInput{T.BeforeToolCallContext{assistant, call, args, context}, signal})

def decidedPreparation(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, tool: T.AgentTool<Details, Error>, call: Ai.ToolCall<Schema.Value>, args: Schema.Value, failureDetails: Details, decision: BeforeToolCallDecision) -> ToolPreparationState<DiagnosticDetails, Details, Custom, Error>:
  match decision:
    case ProceedWithToolCall{}: ToolPreparationState{context, Prepared{PreparedToolCall{call, tool, args}}}
    case RejectToolCall{message, terminate}: immediatePreparation(DiagnosticDetails, Details, Custom, Error, context, message, failureDetails, terminate)

def afterBeforeToolCall(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, tool: T.AgentTool<Details, Error>, call: Ai.ToolCall<Schema.Value>, before: Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, isAborted: (Maybe<&2, Abort.AbortSignal<Unit>> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>):
  match before:
    case Fail{error}: IO.pure(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{T.BeforeToolCallUpdate{args, context, decision}}:
      do IO<Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>>:
        aborted : Bool <- isAborted(signal)
        return Done{decidedPreparation(DiagnosticDetails, Details, Custom, Error, context, tool, call, args, failureDetails, beforeToolCallDecision(aborted, decision))}

def withValidatedToolArguments(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, +call: Ai.ToolCall<Schema.Value>, tool: T.AgentTool<Details, Error>, validated: Result<&2, &2, Error, Schema.Value>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, +signal: Maybe<&2, Abort.AbortSignal<Unit>>, isAborted: (Maybe<&2, Abort.AbortSignal<Unit>> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>):
  match validated:
    case Fail{error}: IO.pure(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{args}:
      do IO<Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>>:
        before : Result<&2, &2, Error, T.BeforeToolCallUpdate<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>> <- invokeBeforeToolCall(DiagnosticDetails, Details, Custom, Error, context, assistant, call, args, signal, selectedBeforeToolCall(DiagnosticDetails, Details, Custom, Error, Telemetry, config))
        afterBeforeToolCall(DiagnosticDetails, Details, Custom, Error, tool, call, before, signal, isAborted, failureDetails)

def prepareFoundTool(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, +call: Ai.ToolCall<Schema.Value>, found: Maybe<&2, T.AgentTool<Details, Error>>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>, isAborted: (Maybe<&2, Abort.AbortSignal<Unit>> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>):
  match found:
    case None{}: IO.pure(Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>, Done{immediatePreparation(DiagnosticDetails, Details, Custom, Error, context, "Tool " ++ callName(call) ++ " not found", failureDetails, False{})})
    case Some{+tool}:
      do IO<Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>>:
        adapted : Result<&2, &2, Error, PreparedToolCallArguments> <- prepareToolCallArguments(Details, Error, tool, call)
        validated : Result<&2, &2, Error, Schema.Value> <- checkedArgumentPreparation(Details, Error, tool, adapted, validate)
        withValidatedToolArguments(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, call, tool, validated, config, signal, isAborted, failureDetails)

def preparationError(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, failureDetails: Details, renderError: Error -> String, outcome: Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>) -> ToolPreparationState<DiagnosticDetails, Details, Custom, Error>:
  match outcome:
    case Done{value}: value
    case Fail{error}: immediatePreparation(DiagnosticDetails, Details, Custom, Error, context, renderError(error), failureDetails, False{})

# No validation bypass: the caller supplies a real validator/typed decoder.
# The with-suffix marks this injectable path; the default schema-backed entry
# point remains pending until full validation is implemented.
def prepareToolCallWith(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, +call: Ai.ToolCall<Schema.Value>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>, isAborted: (Maybe<&2, Abort.AbortSignal<Unit>> -> IO(Bool)), +failureDetails: Details, renderError: Error -> String) -> IO(ToolPreparationState<DiagnosticDetails, Details, Custom, Error>):
  do IO<ToolPreparationState<DiagnosticDetails, Details, Custom, Error>>:
    found : Maybe<&2, T.AgentTool<Details, Error>> = findExecutableTool(Details, Error, callName(call), availableContextTools(DiagnosticDetails, Details, Custom, Error, context))
    outcome : Result<&2, &2, Error, ToolPreparationState<DiagnosticDetails, Details, Custom, Error>> <- prepareFoundTool(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, call, found, config, signal, validate, isAborted, failureDetails)
    return preparationError(DiagnosticDetails, Details, Custom, Error, context, failureDetails, renderError, outcome)


# The per-call operation owns preparation, execution, finalization and result
# delivery. The scheduler owns ordering, cancellation boundaries and reduction.
# State changes are explicit values carried into the next invocation.
type Invocation<-State: Data, -Call: Data> is Data:
  Invocation{state: State, call: Call}

type BatchCompleted<-State: Data, -Message: Data> is Data:
  BatchCompleted{state: State, message: Message, terminate: Bool}

type Batch<-State: Data, -Message: Data> is Data:
  Batch{state: State, messages: List<&2, Message>, terminate: Bool}

type BatchStep<-State: Data, -Message: Data, -Error: Data> is Data:
  BatchReady{state: State}
  Yielded{completed: BatchCompleted<State, Message>}
  Failed{error: Error}
  Cancelled{state: State}

def completedStep(-State: Data, -Message: Data, -Error: Data, result: Result<&2, &2, Error, BatchCompleted<State, Message>>) -> BatchStep<State, Message, Error>:
  match result:
    case Done{value}: Yielded{value}
    case Fail{error}: Failed{error}

def afterAbort(-State: Data, -Message: Data, -Error: Data, stopped: Bool, state: State) -> BatchStep<State, Message, Error>:
  match stopped:
    case True{}: Cancelled{state}
    case False{}: BatchReady{state}

def nonemptyBatch(-Message: Data, values: List<&2, Message>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

def finishBatch(-State: Data, -Message: Data, -Error: Data, state: State, +reversed: List<&2, Message>, allTerminate: Bool) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  IO.pure(Result<&2, &2, Error, Batch<State, Message>>, Done{Batch{state, List.reverse(&2, Message, reversed), nonemptyBatch(Message, reversed) && allTerminate}})

# Check abort only after a completed per-call operation has delivered its
# message. Even an initially aborted signal permits the first immediate result.
# A terminate flag never skips remaining calls; all completed calls must opt in.
# Each BatchReady consumes a call; Yielded and Failed/Cancelled settle that call.
@unsafe
def sequentialBatch(-State: Data, -Call: Data, -Message: Data, -Error: Data, calls: List<&2, Call>, step: BatchStep<State, Message, Error>, reversed: List<&2, Message>, allTerminate: Bool, +invoke: C.Callback<Invocation<State, Call>, Result<&2, &2, Error, BatchCompleted<State, Message>>>, +aborted: C.Callback<Unit, Bool>) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  match calls step:
    case _ Failed{error}: IO.pure(Result<&2, &2, Error, Batch<State, Message>>, Fail{error})
    case _ Cancelled{state}: finishBatch(State, Message, Error, state, reversed, allTerminate)
    case Nil{} BatchReady{state}: finishBatch(State, Message, Error, state, reversed, allTerminate)
    case call <> rest BatchReady{state}:
      do IO<Result<&2, &2, Error, Batch<State, Message>>>:
        result : Result<&2, &2, Error, BatchCompleted<State, Message>> <- C.call(Invocation<State, Call>, Result<&2, &2, Error, BatchCompleted<State, Message>>, invoke, Invocation{state, call})
        sequentialBatch(State, Call, Message, Error, rest, completedStep(State, Message, Error, result), reversed, allTerminate, invoke, aborted)
    case remaining Yielded{BatchCompleted{state, message, terminate}}:
      do IO<Result<&2, &2, Error, Batch<State, Message>>>:
        stopped : Bool <- C.call(Unit, Bool, aborted, Unit{})
        sequentialBatch(State, Call, Message, Error, remaining, afterAbort(State, Message, Error, stopped, state), message <> reversed, allTerminate && terminate, invoke, aborted)

def executeSequential(-State: Data, -Call: Data, -Message: Data, -Error: Data, state: State, calls: List<&2, Call>, invoke: C.Callback<Invocation<State, Call>, Result<&2, &2, Error, BatchCompleted<State, Message>>>, aborted: C.Callback<Unit, Bool>) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  sequentialBatch(State, Call, Message, Error, calls, BatchReady{state}, Nil{}, True{}, invoke, aborted)


# Retain update tombstones beyond execution. The owner releases this collection
# only after tool-held callback aliases have retired, including on delivery failure.
def Owners(-Details: Data, -Error: Data) -> Data: R.Ref<List<&2, ToolUpdateRun<Details, Error>>>

def newOwners(-Details: Data, -Error: Data) -> IO(Owners(Details, Error)):
  R.new(List<&2, ToolUpdateRun<Details, Error>>, Nil{})

def retain(-Details: Data, -Error: Data, owner: Owners(Details, Error), run: ToolUpdateRun<Details, Error>) -> IO(Unit):
  R.modify(List<&2, ToolUpdateRun<Details, Error>>, Unit, owner, runs => (run <> runs, Unit{}))

def disposeRuns(-Details: Data, -Error: Data, runs: List<&2, ToolUpdateRun<Details, Error>>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case run <> rest:
      do IO<Unit>:
        disposeToolUpdateRun(Details, Error, run)
        disposeRuns(Details, Error, rest)

def disposeOwners(-Details: Data, -Error: Data, owner: Owners(Details, Error)) -> IO(Unit):
  do IO<Unit>:
    runs : List<&2, ToolUpdateRun<Details, Error>> <- R.dispose(List<&2, ToolUpdateRun<Details, Error>>, owner)
    disposeRuns(Details, Error, runs)

type CallCapture<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  CallCapture{assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>, isAborted: C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool>, emit: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, owners: Owners(Details, Error), failureDetails: Details}

def CallInput(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data) -> Data: Invocation<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolCall<Schema.Value>>
def CallOutput(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data) -> Data: Result<&2, &2, Error, BatchCompleted<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>

type CallStep<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  CallBegin{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, call: Ai.ToolCall<Schema.Value>}
  CallStarted{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, call: Ai.ToolCall<Schema.Value>, emitted: Result<&2, &2, Error, Unit>}
  CallPrepared{call: Ai.ToolCall<Schema.Value>, prepared: ToolPreparationState<DiagnosticDetails, Details, Custom, Error>}
  CallExecuted{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, prepared: PreparedToolCall<Details, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>}
  CallFinalized{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, finalized: FinalizedToolCallOutcome<Details>}
  CallEnded{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, finalized: FinalizedToolCallOutcome<Details>, emitted: Result<&2, &2, Error, Unit>}
  CallDelivered{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, terminate: Bool, message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

def preparedCall(-Details: Data, -Error: Data, prepared: PreparedToolCall<Details, Error>) -> Ai.ToolCall<Schema.Value>:
  match prepared:
    case PreparedToolCall{call, _, _}: call

def startEvent(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, call: Ai.ToolCall<Schema.Value>) -> T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

# Each stage advances one call's lifecycle. The error renderer is lifted code;
# all changing state and effect resources are explicit capture/input values.
@unsafe
def advanceCall(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, step: CallStep<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)):
  match capture:
    case CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match step:
        case CallBegin{context, +call}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, startEvent(DiagnosticDetails, Details, Custom, call))
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallStarted{context, call, emitted})
        case CallStarted{_, _, Fail{error}}: IO.pure(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), Fail{error})
        case CallStarted{context, +call, Done{_}}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            prepared : ToolPreparationState<DiagnosticDetails, Details, Custom, Error> <- prepareToolCallWith(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, isAborted, value), failureDetails, error => renderError(error))
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallPrepared{call, prepared})
        case CallPrepared{call, ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{result, isError}}}}:
          advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallFinalized{context, FinalizedToolCallOutcome{call, result, isError}})
        case CallPrepared{_, ToolPreparationState{context, Prepared{+prepared}}}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            +updates : ToolUpdateRun<Details, Error> <- createToolUpdateRun(~DiagnosticDetails, ~Details, ~Custom, ~Error, preparedCall(Details, Error, prepared), emit)
            retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, ExecutedToolCallOutcome<Details>> <- executePreparedToolCall(Details, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallExecuted{context, prepared, outcome})
        case CallExecuted{_, _, Fail{error}}: IO.pure(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), Fail{error})
        case CallExecuted{+context, prepared, Done{outcome}}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            finalized : FinalizedToolCallOutcome<Details> <- finalizeExecutedToolCall(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallFinalized{context, finalized})
        case CallFinalized{context, +finalized}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallEnded{context, finalized, emitted})
        case CallEnded{_, _, Fail{error}}: IO.pure(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), Fail{error})
        case CallEnded{context, +finalized, Done{_}}:
          do IO<CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>:
            terminate : Bool = shouldTerminateToolBatch(Details, finalized <> Nil{})
            +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Details, finalized)
            emitted : Result<&2, &2, Error, Unit> <- emitToolResultMessage(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, sink)
            advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallDelivered{context, terminate, message, emitted})
        case CallDelivered{_, _, _, Fail{error}}: IO.pure(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), Fail{error})
        case CallDelivered{context, terminate, message, Done{_}}:
          IO.pure(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), Done{BatchCompleted{context, message, terminate}})

def invokeCall(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, input: CallInput(DiagnosticDetails, Details, Custom, Error, Telemetry)) -> IO(CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)):
  match input:
    case Invocation{context, call}: advanceCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, CallBegin{context, call})

def create(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(C.Callback<CallInput(DiagnosticDetails, Details, Custom, Error, Telemetry), CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)>):
  C.create(~CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, ~CallInput(DiagnosticDetails, Details, Custom, Error, Telemetry), ~CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), ~(invokeCall(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError)), capture)


# Preparation is sequential. ParallelImmediate outcomes emit their execution-end here;
# prepared entries are inert until the entire preparation pass has finished.
type Entry<-Details: Data, -Error: Data> is Data:
  ParallelImmediate{finalized: FinalizedToolCallOutcome<Details>}
  ParallelPrepared{prepared: PreparedToolCall<Details, Error>}

type Plan<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  Plan{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, entries: List<&2, Entry<Details, Error>>}

type PreparationStep<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  ParallelNext{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>}
  ParallelStarted{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, call: Ai.ToolCall<Schema.Value>, emitted: Result<&2, &2, Error, Unit>}
  Checked{call: Ai.ToolCall<Schema.Value>, preparation: ToolPreparationState<DiagnosticDetails, Details, Custom, Error>}
  ParallelEnded{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, entry: Entry<Details, Error>, emitted: Result<&2, &2, Error, Unit>}
  Stopped{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, entry: Entry<Details, Error>, aborted: Bool}

# Each ParallelNext consumes a call. Other stages settle preparation or terminate it.
@unsafe
def prepareParallel(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, calls: List<&2, Ai.ToolCall<Schema.Value>>, reversed: List<&2, Entry<Details, Error>>, step: PreparationStep<DiagnosticDetails, Details, Custom, Error>) -> IO(Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>):
  match capture:
    case CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match calls step:
        case Nil{} ParallelNext{context}: IO.pure(Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>, Done{Plan{context, List.reverse(&2, Entry<Details, Error>, reversed)}})
        case +call <> rest ParallelNext{context}:
          do IO<Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, startEvent(DiagnosticDetails, Details, Custom, call))
            prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, rest, reversed, ParallelStarted{context, call, emitted})
        case _ ParallelStarted{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
        case remaining ParallelStarted{context, +call, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>>:
            prepared : ToolPreparationState<DiagnosticDetails, Details, Custom, Error> <- prepareToolCallWith(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, isAborted, value), failureDetails, error => renderError(error))
            prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, remaining, reversed, Checked{call, prepared})
        case remaining Checked{call, ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{valueResult, isError}}}}:
          do IO<Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>>:
            +finalized : FinalizedToolCallOutcome<Details> = FinalizedToolCallOutcome{call, valueResult, isError}
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, remaining, reversed, ParallelEnded{context, ParallelImmediate{finalized}, emitted})
        case remaining Checked{_, ToolPreparationState{context, Prepared{prepared}}}:
          prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, remaining, reversed, ParallelEnded{context, ParallelPrepared{prepared}, Done{Unit{}}})
        case _ ParallelEnded{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
        case remaining ParallelEnded{context, entry, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>>:
            stopped : Bool <- C.call(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, isAborted, signal)
            prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, remaining, reversed, Stopped{context, entry, stopped})
        case _ Stopped{context, entry, True{}}: IO.pure(Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>, Done{Plan{context, List.reverse(&2, Entry<Details, Error>, entry <> reversed)}})
        case remaining Stopped{context, entry, False{}}:
          prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, remaining, entry <> reversed, ParallelNext{context})

# Every deferred call observes the final preparation context. This explicitly
# carries before-hook context updates without sharing a mutable message object.
type ExecutionCapture<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  ExecutionCapture{capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>}

type ExecutionStep<-Details: Data, -Error: Data> is Data:
  ParallelBegin{entry: Entry<Details, Error>}
  Aborted{prepared: PreparedToolCall<Details, Error>, stopped: Bool}
  ParallelExecuted{prepared: PreparedToolCall<Details, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>}
  ParallelFinalized{finalized: FinalizedToolCallOutcome<Details>}
  Emitted{finalized: FinalizedToolCallOutcome<Details>, emitted: Result<&2, &2, Error, Unit>}

# Each transition advances one deferred call. ParallelImmediate entries already emitted
# end during preparation and must not emit it again or invoke the after hook.
@unsafe
def executeParallel(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +environment: ExecutionCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, step: ExecutionStep<Details, Error>) -> IO(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>):
  match environment:
    case ExecutionCapture{CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}, +context}:
      match step:
        case ParallelBegin{ParallelImmediate{finalized}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, Done{finalized})
        case ParallelBegin{ParallelPrepared{prepared}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>>:
            stopped : Bool <- C.call(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, isAborted, signal)
            executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, Aborted{prepared, stopped})
        case Aborted{prepared, True{}}:
          executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, ParallelFinalized{FinalizedToolCallOutcome{preparedCall(Details, Error, prepared), T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Operation aborted", None{}}} <> Nil{}, failureDetails, None{}, None{}}, True{}}})
        case Aborted{+prepared, False{}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>>:
            +updates : ToolUpdateRun<Details, Error> <- createToolUpdateRun(~DiagnosticDetails, ~Details, ~Custom, ~Error, preparedCall(Details, Error, prepared), emit)
            retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, ExecutedToolCallOutcome<Details>> <- executePreparedToolCall(Details, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, ParallelExecuted{prepared, outcome})
        case ParallelExecuted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, Fail{error})
        case ParallelExecuted{prepared, Done{outcome}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>>:
            finalized : FinalizedToolCallOutcome<Details> <- finalizeExecutedToolCall(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, ParallelFinalized{finalized})
        case ParallelFinalized{+finalized}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>>:
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, Emitted{finalized, emitted})
        case Emitted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, Fail{error})
        case Emitted{finalized, Done{_}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, Done{finalized})

def invokeParallel(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, environment: ExecutionCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, entry: Entry<Details, Error>) -> IO(Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>):
  executeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, environment, ParallelBegin{entry})

# Keep worker captures alive after a prompt failure. dispose drains all workers
# before retiring the execution callback; the caller still owns sink/update aliases.
type ParallelRun<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  ParallelRun{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, collection: All.Run<Error, FinalizedToolCallOutcome<Details>>, worker: C.Callback<Entry<Details, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>}

def beginPrepared(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, prepared: Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>>) -> IO(Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case CallCapture{_, _, _, _, _, _, sink, _, _} Done{Plan{+context, entries}}:
      do IO<Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>>:
        +worker : C.Callback<Entry<Details, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>> <- C.create(~ExecutionCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, ~Entry<Details, Error>, ~Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, ~(invokeParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError)), ExecutionCapture{capture, context})
        collection : All.Run<Error, FinalizedToolCallOutcome<Details>> <- All.start(Entry<Details, Error>, Error, FinalizedToolCallOutcome<Details>, entries, worker)
        return Done{ParallelRun{context, collection, worker, sink}}

def startParallel(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, calls: List<&2, Ai.ToolCall<Schema.Value>>) -> IO(Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>):
  do IO<Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>>:
    prepared : Result<&2, &2, Error, Plan<DiagnosticDetails, Details, Custom, Error>> <- prepareParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, calls, Nil{}, ParallelNext{context})
    beginPrepared(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, prepared)

type ParallelDeliveryStep<-Details: Data, -Error: Data> is Data:
  ParallelReady{}
  ParallelDelivered{message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

# Successful execution-end events all precede ordered message delivery. A
# message listener failure stops delivery immediately; no later message starts.
@unsafe
def deliverParallel(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, remaining: List<&2, FinalizedToolCallOutcome<Details>>, reversed: List<&2, Ai.ToolResultMessage<Details>>, terminate: Bool, +sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: ParallelDeliveryStep<Details, Error>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>):
  match remaining step:
    case Nil{} ParallelReady{}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>, Done{Batch{context, List.reverse(&2, Ai.ToolResultMessage<Details>, reversed), terminate}})
    case finalized <> rest ParallelReady{}:
      do IO<Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>>:
        +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Details, finalized)
        emitted : Result<&2, &2, Error, Unit> <- emitToolResultMessage(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, sink)
        deliverParallel(DiagnosticDetails, Details, Custom, Error, context, rest, reversed, terminate, sink, ParallelDelivered{message, emitted})
    case _ ParallelDelivered{_, Fail{error}}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case rest ParallelDelivered{message, Done{_}}: deliverParallel(DiagnosticDetails, Details, Custom, Error, context, rest, message <> reversed, terminate, sink, ParallelReady{})

def collected(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, valueResult: Result<&2, &2, Error, List<&2, FinalizedToolCallOutcome<Details>>>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>):
  match valueResult:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case Done{+finalized}: deliverParallel(DiagnosticDetails, Details, Custom, Error, context, finalized, Nil{}, shouldTerminateToolBatch(Details, finalized), sink, ParallelReady{})

# One consumer owns result-message delivery. On failure this may return while
# sibling execution is still running; dispose is the separate lifetime boundary.
def parallelResult(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, run: ParallelRun<DiagnosticDetails, Details, Custom, Error>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>):
  match run:
    case ParallelRun{context, collection, _, sink}:
      do IO<Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>>:
        finalized : Result<&2, &2, Error, List<&2, FinalizedToolCallOutcome<Details>>> <- All.result(Error, FinalizedToolCallOutcome<Details>, collection)
        collected(DiagnosticDetails, Details, Custom, Error, context, sink, finalized)

def disposeParallel(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, run: ParallelRun<DiagnosticDetails, Details, Custom, Error>) -> IO(Unit):
  match run:
    case ParallelRun{_, collection, worker, _}:
      do IO<Unit>:
        All.dispose(Error, FinalizedToolCallOutcome<Details>, collection)
        C.dispose(Entry<Details, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Details>>, worker)


# Split around the last pending system message. Only that message's tool fields
# express pending intent; preceding declarations remain part of the baseline.
type ChangesPending<-DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Existing{before: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<Schema.Value>, after: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>}
  Absent{messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>}

def splitLast(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, reversed: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, after: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> ChangesPending<DiagnosticDetails, Details, Custom>:
  match reversed:
    case Nil{}: Absent{after}
    case T.LlmMessage{Ai.System{system}} <> before: Existing{List.reverse(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, before), system, after}
    case message <> rest: splitLast(DiagnosticDetails, Details, Custom, rest, message <> after)

def optional(-A: Data, values: List<&2, A>) -> Maybe<&2, List<&2, A>>:
  match values:
    case Nil{}: None{}
    case head <> tail: Some{head <> tail}

def withToolChanges(message: Ai.SystemMessage<Schema.Value>, changes: Transcript.ToolStateChanges<Schema.Value>) -> Ai.SystemMessage<Schema.Value>:
  match message changes:
    case Ai.SystemMessage{content, sections, _, _, timestamp} Transcript.ToolStateChanges{added, removed}:
      Ai.SystemMessage{content, sections, optional(Ai.Tool<Schema.Value>, added), optional(Ai.ToolReference, removed), timestamp}

def join(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, before: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<Schema.Value>, after: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, before, T.LlmMessage{Ai.System{system}} <> after)

def baseline(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: ChangesPending<DiagnosticDetails, Details, Custom>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match pending:
    case Existing{before, system, after}: join(DiagnosticDetails, Details, Custom, before, withToolChanges(system, Transcript.ToolStateChanges{Nil{}, Nil{}}), after)
    case Absent{messages}: messages

# Tool replay reads only native LLM system records. Custom messages do not pass
# through convertToLlm here; that callback is reserved for provider requests.
def llmMessages(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{message} <> rest: message <> llmMessages(DiagnosticDetails, Details, Custom, rest)
    case T.CustomMessage{_} <> rest: llmMessages(DiagnosticDetails, Details, Custom, rest)

def declarations(-Details: Data, -Error: Data, tools: List<&2, T.AgentTool<Details, Error>>) -> List<&2, Ai.Tool<Schema.Value>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(Details, Error, tool) <> declarations(Details, Error, rest)

type ChangePlan<-DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  ChangePlan{pending: ChangesPending<DiagnosticDetails, Details, Custom>, changes: Transcript.ToolStateChanges<Schema.Value>}

def packagePlan(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: ChangesPending<DiagnosticDetails, Details, Custom>, changes: Declaration.DeclarationResult<Transcript.ToolStateChanges<Schema.Value>>) -> Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>>:
  match changes:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{changes}: Declaration.Success{ChangePlan{pending, changes}}

def plan(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, pendingMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>>:
  +pending = splitLast(DiagnosticDetails, Details, Custom, List.reverse(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, pendingMessages), Nil{})
  history = List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, contextMessages(DiagnosticDetails, Details, Custom, Error, context), baseline(DiagnosticDetails, Details, Custom, pending))
  previous = Transcript.getCurrentTools(Schema.Value, Schema.Value, DiagnosticDetails, Details, llmMessages(DiagnosticDetails, Details, Custom, history))
  current = declarations(Details, Error, availableContextTools(DiagnosticDetails, Details, Custom, Error, context))
  packagePlan(DiagnosticDetails, Details, Custom, pending, Transcript.getToolStateChanges(previous, current))

def nonemptyChanges(-A: Data, values: Maybe<&2, List<&2, A>>) -> Bool:
  match values:
    case Some{_ <> _}: True{}
    case _: False{}

def hasChanges(changes: Transcript.ToolStateChanges<Schema.Value>) -> Bool:
  match changes:
    case Transcript.ToolStateChanges{Nil{}, Nil{}}: False{}
    case _: True{}

def pendingChanges(message: Ai.SystemMessage<Schema.Value>) -> Bool:
  match message:
    case Ai.SystemMessage{_, _, added, removed, _}: nonemptyChanges(Ai.Tool<Schema.Value>, added) || nonemptyChanges(Ai.ToolReference, removed)

def replaceSystem(original: Ai.SystemMessage<Schema.Value>, changes: Transcript.ToolStateChanges<Schema.Value>, replace: Bool) -> Ai.SystemMessage<Schema.Value>:
  match replace:
    case False{}: original
    case True{}: withToolChanges(original, changes)

# No existing system implies insertion before the first non-system message.
def insert(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, +update: Ai.SystemMessage<Schema.Value>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{system}} <> rest: T.LlmMessage{Ai.System{system}} <> insert(DiagnosticDetails, Details, Custom, rest, update)
    case remaining: T.LlmMessage{Ai.System{update}} <> remaining

def absent(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, changes: Transcript.ToolStateChanges<Schema.Value>, timestamp: F64, changed: Bool) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match changed:
    case False{}: messages
    case True{}: insert(DiagnosticDetails, Details, Custom, messages, withToolChanges(Ai.SystemMessage{Ai.SystemText{""}, None{}, None{}, None{}, timestamp}, changes))

def applyAt(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, timestamp: F64, planned: Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>>) -> Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>:
  match planned:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{ChangePlan{Existing{before, +system, after}, +changes}}:
      Declaration.Success{join(DiagnosticDetails, Details, Custom, before, replaceSystem(system, changes, hasChanges(changes) || pendingChanges(system)), after)}
    case Declaration.Success{ChangePlan{Absent{messages}, +changes}}:
      Declaration.Success{absent(DiagnosticDetails, Details, Custom, messages, changes, timestamp, hasChanges(changes))}

def needsTimestamp(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>>) -> Bool:
  match planned:
    case Declaration.Success{ChangePlan{Absent{_}, changes}}: hasChanges(changes)
    case _: False{}

def commit(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>>, timestampNeeded: Bool) -> IO(Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match timestampNeeded:
    case False{}: IO.pure(Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, applyAt(DiagnosticDetails, Details, Custom, Number.fromU32(0), planned))
    case True{}:
      do IO<Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
        timestamp : F64 <- Date.now()
        return applyAt(DiagnosticDetails, Details, Custom, timestamp, planned)

def declareToolChanges(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, pendingMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> IO(Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  do IO<Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
    +planned : Declaration.DeclarationResult<ChangePlan<DiagnosticDetails, Details, Custom>> = plan(DiagnosticDetails, Details, Custom, Error, context, pendingMessages)
    commit(DiagnosticDetails, Details, Custom, planned, needsTimestamp(DiagnosticDetails, Details, Custom, planned))


def ExecutionOutcome(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data:
  Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>

# An execution owns concurrent work independently of result settlement. Tools
# and event sinks remain live through worker draining and update-owner cleanup.
type Execution<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  Settled{outcome: ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)}
  Concurrent{run: ParallelRun<DiagnosticDetails, Details, Custom, Error>}

type Cancellation is Data:
  Cancellation{signal: Maybe<&2, Abort.AbortSignal<Unit>>, check: C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool>}

def abortedExecution(cancellation: Cancellation, unused: Unit) -> IO(Bool):
  match cancellation:
    case Cancellation{signal, check}: C.call(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, check, signal)

def parallelExecution(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, started: Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>>) -> Execution<DiagnosticDetails, Details, Custom, Error>:
  match started:
    case Fail{error}: Settled{Fail{error}}
    case Done{run}: Concurrent{run}

def selectedExecution(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, prepared: PreparedToolCallBatch) -> IO(Execution<DiagnosticDetails, Details, Custom, Error>):
  match capture prepared:
    case CallCapture{_, _, signal, _, isAborted, _, _, _, _} PreparedToolCallBatch{calls, T.Sequential{}}:
      do IO<Execution<DiagnosticDetails, Details, Custom, Error>>:
        +invoke : C.Callback<CallInput(DiagnosticDetails, Details, Custom, Error, Telemetry), CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry)> <- create(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture)
        +cancel : C.Callback<Unit, Bool> <- C.create(~Cancellation, ~Unit, ~Bool, ~(abortedExecution), Cancellation{signal, isAborted})
        outcome : ExecutionOutcome(DiagnosticDetails, Details, Custom, Error) <- executeSequential(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolCall<Schema.Value>, Ai.ToolResultMessage<Details>, Error, context, calls, invoke, cancel)
        C.dispose(CallInput(DiagnosticDetails, Details, Custom, Error, Telemetry), CallOutput(DiagnosticDetails, Details, Custom, Error, Telemetry), invoke)
        C.dispose(Unit, Bool, cancel)
        return Settled{outcome}
    case _ PreparedToolCallBatch{calls, T.Parallel{}}:
      do IO<Execution<DiagnosticDetails, Details, Custom, Error>>:
        started : Result<&2, &2, Error, ParallelRun<DiagnosticDetails, Details, Custom, Error>> <- startParallel(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, context, calls)
        return parallelExecution(DiagnosticDetails, Details, Custom, Error, started)

# Select once from the assistant's tool calls and original context. A matching
# tool's sequential override applies to the entire batch; missing tools and
# non-tool assistant content do not introduce new scheduling policy.
def executeToolCalls(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, +capture: CallCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>) -> IO(Execution<DiagnosticDetails, Details, Custom, Error>):
  match capture:
    case CallCapture{assistant, config, _, _, _, _, _, _, _}:
      selectedExecution(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, context, prepareToolCallBatch(DiagnosticDetails, Details, Custom, Error, Telemetry, context, assistant, config))

# The caller consumes result delivery once, then drains before releasing the
# captured resources. A failed parallel result does not cancel sibling tools.
def executionResult(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, execution: Execution<DiagnosticDetails, Details, Custom, Error>) -> IO(ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)):
  match execution:
    case Settled{outcome}: IO.pure(ExecutionOutcome(DiagnosticDetails, Details, Custom, Error), outcome)
    case Concurrent{run}: parallelResult(DiagnosticDetails, Details, Custom, Error, run)

# This drains batch workers. Retained tool-update scopes remain in Capture.owners;
# retire their aliases and dispose that owner before releasing event resources.
def disposeExecution(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, execution: Execution<DiagnosticDetails, Details, Custom, Error>) -> IO(Unit):
  match execution:
    case Settled{_}: IO.pure(Unit, Unit{})
    case Concurrent{run}: disposeParallel(DiagnosticDetails, Details, Custom, Error, run)


# The schema library retains structured failure categories. Applications map
# them into their execution-error type at this boundary, without discarding
# unsupported-schema or normalization failures that have no public formatter.
def ValidationInput() -> Data: ToolValidationInput
def ValidationOutput(-Error: Data) -> Data: Result<&2, &2, Error, Schema.Value>
def Validator(-Error: Data) -> Data: C.Callback<ValidationInput(), ValidationOutput(Error)>

def validatePlain(input: ValidationInput()) -> Validation.ToolValidation():
  match input:
    case ToolValidationInput{tool, OriginalCall{call}}: Validation.checkPlainToolArguments(tool, call)
    case ToolValidationInput{tool, ReplacedCall{call}}: Validation.checkPlainToolArguments(tool, call)

def mapped(-Error: Data, mapError: Validation.ToolValidationError -> Error, result: Validation.ToolValidation()) -> ValidationOutput(Error):
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{mapError(error)}

def body(-Error: Data, mapError: Validation.ToolValidationError -> Error, unused: Unit, input: ValidationInput()) -> IO(ValidationOutput(Error)):
  IO.pure(ValidationOutput(Error), mapped(Error, mapError, validatePlain(input)))

# Caller owns this service and disposes it after all borrowing Agents/runs.
def createPlain(~Error: Data, ~mapError: Validation.ToolValidationError -> Error) -> IO(Validator(Error)):
  C.create(~Unit, ~ValidationInput(), ~ValidationOutput(Error), ~(body(Error, mapError)), Unit{})

def disposeValidation(-Error: Data, validator: Validator(Error)) -> IO(Unit):
  C.dispose(ValidationInput(), ValidationOutput(Error), validator)


# Successful turn completion returns an immutable snapshot for prepareNextTurn.
# The caller has already recorded the assistant response in both histories.
type NextTurn<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  Finished{completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>}
  CompletionContinue{completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>, pending: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>}

def toolMessages(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, results: List<&2, Ai.ToolResultMessage<Details>>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match results:
    case Nil{}: Nil{}
    case message <> rest: T.LlmMessage{Ai.ToolResult{message}} <> toolMessages(DiagnosticDetails, Details, Custom, rest)

def completedTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, +results: List<&2, Ai.ToolResultMessage<Details>>) -> T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>:
  match context:
    case T.AgentContext{messages, tools}:
      +added = toolMessages(DiagnosticDetails, Details, Custom, results)
      T.ShouldStopAfterTurnContext{assistant, results, T.AgentContext{List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, messages, added), tools}, List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, newMessages, added)}

def completedHistory(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, _, messages}: messages

def nonemptyCompletion(-A: Data, values: List<&2, A>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

def endedCompletion(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>, emitted: Result<&2, &2, Error, Unit>) -> Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Finished{completed}}

def followed(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, +completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>):
  match queued:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{Nil{}}:
      do IO<Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentEnd{completedHistory(DiagnosticDetails, Details, Custom, Error, completed)})
        return endedCompletion(DiagnosticDetails, Details, Custom, Error, completed, emitted)
    case Done{head <> tail}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Done{CompletionContinue{completed, head <> tail}})

def afterSteering(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>, moreTools: Bool) -> IO(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>):
  match queued moreTools:
    case Fail{error} _: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{None{}} _: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Done{Finished{completed}})
    case Done{Some{pending}} True{}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Done{CompletionContinue{completed, pending}})
    case Done{Some{head <> tail}} False{}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Done{CompletionContinue{completed, head <> tail}})
    case Done{Some{Nil{}}} False{}:
      do IO<Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>>:
        followUp : Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- pollFollowUpMessages(DiagnosticDetails, Details, Custom, Error, Telemetry, config)
        followed(DiagnosticDetails, Details, Custom, Error, completed, sink, followUp)

def afterTurnEnd(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, +config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, +completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>, +sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, moreTools: Bool, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>>:
        queued : Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>> <- finishCompletedTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, T.AgentToolResult<Details>, T.AgentToolResult<Details>, config, completed, completedHistory(DiagnosticDetails, Details, Custom, Error, completed), sink)
        afterSteering(DiagnosticDetails, Details, Custom, Error, Telemetry, config, completed, sink, queued, moreTools)

# Commit successful tool results to both histories before turn_end and the
# stop hook. Steering is checked after the stop hook; follow-ups are checked
# only when neither continuing tool calls nor steering keeps the inner loop alive.
def completeTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, +assistant: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, +sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, batch: Result<&2, &2, Error, Batch<T.AgentContext<DiagnosticDetails, Details, Custom, Error>, Ai.ToolResultMessage<Details>>>) -> IO(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>):
  match batch:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>, Fail{error})
    case Done{Batch{context, +results, terminate}}:
      do IO<Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>>:
        +completed : T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error> = completedTurn(DiagnosticDetails, Details, Custom, Error, assistant, context, newMessages, results)
        moreTools : Bool = nonemptyCompletion(Ai.ToolCall<Schema.Value>, collectAssistantToolCalls(DiagnosticDetails, assistant)) && Bool.not(terminate)
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnEnd{T.LlmMessage{Ai.Assistant{assistant}}, results})
        afterTurnEnd(DiagnosticDetails, Details, Custom, Error, Telemetry, config, completed, sink, moreTools, emitted)


# Ready for the provider boundary: updated context/config and committed history.
type RequestState<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  RequestState{context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>}

type TurnDeliveryStep<-Message: Data, -Error: Data> is Data:
  TurnNext{}
  TurnStarted{message: Message, emitted: Result<&2, &2, Error, Unit>}
  TurnEnded{message: Message, emitted: Result<&2, &2, Error, Unit>}

# Each TurnNext consumes a declared message. Commit only after both events settle,
# preserving source order and skipping every later event on listener failure.
@unsafe
def deliverTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, state: RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>, remaining: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: TurnDeliveryStep<T.AgentMessage<DiagnosticDetails, Details, Custom>, Error>) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  match state:
    case RequestState{context, config, newMessages}:
      match remaining step:
        case Nil{} TurnNext{}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Done{RequestState{context, config, newMessages}})
        case +message <> rest TurnNext{}:
          do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageStart{message})
            deliverTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, RequestState{context, config, newMessages}, rest, sink, TurnStarted{message, emitted})
        case _ TurnStarted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{error})
        case rest TurnStarted{+message, Done{_}}:
          do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageEnd{message})
            deliverTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, RequestState{context, config, newMessages}, rest, sink, TurnEnded{message, emitted})
        case _ TurnEnded{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{error})
        case rest TurnEnded{+message, Done{_}}:
          deliverTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, RequestState{copyContextMessages(DiagnosticDetails, Details, Custom, Error, context, message <> Nil{}), config, List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, newMessages, message <> Nil{})}, rest, sink, TurnNext{})

def declaredTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, state: RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  match outcome:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{declarationError(error)})
    case Declaration.Success{messages}: deliverTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, state, messages, sink, TurnNext{})

def declare(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
    +current : T.AgentContext<DiagnosticDetails, Details, Custom, Error> = context
    outcome : Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- declareToolChanges(DiagnosticDetails, Details, Custom, Error, current, messages)
    declaredTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, RequestState{current, config, newMessages}, sink, declarationError, outcome)

def startedTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{error})
    case Done{_}: declare(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, newMessages, messages, sink, declarationError)

def queuedTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, prepared: PreparedTurnState<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, pending: Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  match prepared pending:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{error})
    case PreparedTurnState{context, config, messages} Done{steering}:
      do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        startedTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, newMessages, List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, messages, steering), sink, declarationError, emitted)

def afterPreparation(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Result<&2, &2, Error, PreparedTurnState<DiagnosticDetails, Details, Custom, Error, Telemetry>>) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>, Fail{error})
    case Done{PreparedTurnState{context, +config, messages}}:
      do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
        steering : Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- repollSteeringMessages(DiagnosticDetails, Details, Custom, Error, Telemetry, config, pending)
        queuedTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, PreparedTurnState{context, config, messages}, newMessages, sink, declarationError, steering)

# A retained steering item must not consume another one-at-a-time queue item.
# Preparation updates context/model/reasoning before any turn_start event.
def nextTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, completed: T.PrepareNextTurnContext(DiagnosticDetails, Details, Custom, Error), newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  do IO<Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>>:
    outcome : Result<&2, &2, Error, PreparedTurnState<DiagnosticDetails, Details, Custom, Error, Telemetry>> <- prepareNextTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, completed)
    afterPreparation(DiagnosticDetails, Details, Custom, Error, Telemetry, newMessages, pending, sink, declarationError, outcome)

# The initial turn_start belongs to runAgentLoop/runAgentLoopContinue. The first
# inner iteration declares and delivers already-polled steering without a hook
# or another turn_start event.
def initialTurn(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>):
  declare(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, newMessages, pending, sink, declarationError)


# Batches may fail before sibling work drains. The loop owner retains executions
# until explicit disposal; tool-held update aliases have their separate owner.
def Batches(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: R.Ref<List<&2, Execution<DiagnosticDetails, Details, Custom, Error>>>

def newBatches(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> IO(Batches(DiagnosticDetails, Details, Custom, Error)):
  R.new(List<&2, Execution<DiagnosticDetails, Details, Custom, Error>>, Nil{})

def disposeExecutions(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, executions: List<&2, Execution<DiagnosticDetails, Details, Custom, Error>>) -> IO(Unit):
  match executions:
    case Nil{}: IO.pure(Unit, Unit{})
    case execution <> rest:
      do IO<Unit>:
        disposeExecution(DiagnosticDetails, Details, Custom, Error, execution)
        disposeExecutions(DiagnosticDetails, Details, Custom, Error, rest)

def disposeBatches(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, owner: Batches(DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  do IO<Unit>:
    executions : List<&2, Execution<DiagnosticDetails, Details, Custom, Error>> <- R.dispose(List<&2, Execution<DiagnosticDetails, Details, Custom, Error>>, owner)
    disposeExecutions(DiagnosticDetails, Details, Custom, Error, executions)

type Services<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  Services{signal: Maybe<&2, Abort.AbortSignal<Unit>>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>, isAborted: C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool>, emit: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>, sink: C.Callback<T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, updates: Owners(Details, Error), batches: Batches(DiagnosticDetails, Details, Custom, Error), emptyDetails: Details}

type LoopCapture<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  LoopCapture{services: Services<DiagnosticDetails, Details, Custom, Error>, streamFunction: T.StreamFn(DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error)}

type LoopStep<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  Initial{pending: Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>}
  LoopPrepared{state: Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>}
  Responded{message: Result<&2, &2, Error, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>>}
  Recorded{message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, recorded: Result<&2, &2, Error, AssistantCompletion<T.AgentMessage<DiagnosticDetails, Details, Custom>>>}
  LoopExecuted{message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, batch: ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)}
  LoopCompleted{turn: Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>>}

def lengthLimited(-DiagnosticDetails: Data, message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}: True{}
    case _: False{}

def truncatedResult(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallBatch<Details>>) -> ExecutionOutcome(DiagnosticDetails, Details, Custom, Error):
  match outcome:
    case Fail{error}: Fail{error}
    case Done{ExecutedToolCallBatch{messages, terminate}}: Done{Batch{context, messages, terminate}}

def executeLoop(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, capture: LoopCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, +message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, calls: List<&2, Ai.ToolCall<Schema.Value>>, truncated: Bool) -> IO(ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)):
  match capture calls truncated:
    case _ Nil{} _: IO.pure(ExecutionOutcome(DiagnosticDetails, Details, Custom, Error), Done{Batch{context, Nil{}, False{}}})
    case LoopCapture{Services{_, _, _, _, sink, _, _, emptyDetails}, _} remaining True{}:
      do IO<ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)>:
        outcome : Result<&2, &2, Error, ExecutedToolCallBatch<Details>> <- failToolCallsFromTruncatedMessage(DiagnosticDetails, Custom, T.AgentToolResult<Details>, Error, Details, TruncatedToolCallRun{sink, emptyDetails}, remaining)
        return truncatedResult(DiagnosticDetails, Details, Custom, Error, context, outcome)
    case LoopCapture{Services{signal, validate, isAborted, emit, sink, updates, +batches, emptyDetails}, _} _ False{}:
      do IO<ExecutionOutcome(DiagnosticDetails, Details, Custom, Error)>:
        +execution : Execution<DiagnosticDetails, Details, Custom, Error> <- executeToolCalls(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, CallCapture{message, config, signal, validate, isAborted, emit, sink, updates, emptyDetails}, context)
        R.modify(List<&2, Execution<DiagnosticDetails, Details, Custom, Error>>, Unit, batches, entries => (execution <> entries, Unit{}))
        executionResult(DiagnosticDetails, Details, Custom, Error, execution)

def completedContext(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<DiagnosticDetails, Details, Custom, Error>) -> T.AgentContext<DiagnosticDetails, Details, Custom, Error>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, context, _}: context

# One completed response advances to preparation or finishes. IO may suspend at
# any stage; records and retained event histories stay immutable. Only the live
# response consumer shares the context cell, which is retired on loop return.
@unsafe
def advanceLoop(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, +capture: LoopCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, +contextCell: R.Ref<T.AgentContext<DiagnosticDetails, Details, Custom, Error>>, +config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, history: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, step: LoopStep<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match capture:
    case LoopCapture{Services{+signal, +validate, +isAborted, +emit, +sink, +updates, +batches, +emptyDetails}, +streamFunction}:
      match step:
        case Initial{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Initial{Done{pending}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<DiagnosticDetails, Details, Custom, Error> <- R.read(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, contextCell)
            prepared : Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>> <- initialTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, history, pending, sink, error => declarationError(error))
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopPrepared{prepared})
        case LoopPrepared{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
        case LoopPrepared{Done{RequestState{context, +nextConfig, newMessages}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            R.write(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, contextCell, context)
            response : Result<&2, &2, Error, Ai.AssistantMessage<Schema.Value, DiagnosticDetails>> <- streamAssistantResponse(DiagnosticDetails, Details, Custom, Error, Telemetry, T.AgentToolResult<Details>, T.AgentToolResult<Details>, AssistantRequest{contextCell, nextConfig, signal, sink, streamFunction})
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, nextConfig, newMessages, Responded{response})
        case Responded{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Responded{Done{+message}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            recorded : Result<&2, &2, Error, AssistantCompletion<T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- recordAssistantCompletion(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, history, sink)
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Recorded{message, recorded})
        case Recorded{_, Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Recorded{_, Done{AssistantCompletion{messages, True{}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Done{messages})
        case Recorded{+message, Done{AssistantCompletion{+messages, False{}}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<DiagnosticDetails, Details, Custom, Error> <- R.read(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, contextCell)
            outcome : ExecutionOutcome(DiagnosticDetails, Details, Custom, Error) <- executeLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, capture, context, config, message, collectAssistantToolCalls(DiagnosticDetails, message), lengthLimited(DiagnosticDetails, message))
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, messages, LoopExecuted{message, outcome})
        case LoopExecuted{message, batch}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            completed : Result<&2, &2, Error, NextTurn<DiagnosticDetails, Details, Custom, Error>> <- completeTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, message, history, config, sink, batch)
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopCompleted{completed})
        case LoopCompleted{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
        case LoopCompleted{Done{Finished{T.ShouldStopAfterTurnContext{_, _, _, messages}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Done{messages})
        case LoopCompleted{Done{CompletionContinue{+completed, pending}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
            +context : T.AgentContext<DiagnosticDetails, Details, Custom, Error> = completedContext(DiagnosticDetails, Details, Custom, Error, completed)
            messages : List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>> = completedHistory(DiagnosticDetails, Details, Custom, Error, completed)
            R.write(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, contextCell, context)
            prepared : Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>> <- nextTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, context, config, completed, messages, pending, sink, error => declarationError(error))
            advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopPrepared{prepared})

# Internal loop: entry points emit agent_start/first turn_start and prompt events
# before calling this. The supplied stream function is always the real provider
# interface; only its implementation is injectable, as in upstream pi.
def runLoop(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, capture: LoopCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, +config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, newMessages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
    +contextCell : R.Ref<T.AgentContext<DiagnosticDetails, Details, Custom, Error>> <- R.new(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, context)
    pending : Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- pollSteeringMessages(DiagnosticDetails, Details, Custom, Error, Telemetry, config)
    outcome : Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- advanceLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, capture, contextCell, config, newMessages, Initial{pending})
    discarded : T.AgentContext<DiagnosticDetails, Details, Custom, Error> <- R.dispose(T.AgentContext<DiagnosticDetails, Details, Custom, Error>, contextCell)
    return outcome


type ContinueError is Data:
  NoMessages{}
  AssistantLast{}

def errorMessage(error: ContinueError) -> String:
  match error:
    case NoMessages{}: "Cannot continue: no messages in context"
    case AssistantLast{}: "Cannot continue from message role: assistant"

# Validate only the agent message role. Conversion belongs at the provider
# boundary; custom messages remain the caller's responsibility, as in pi.
def validateContinuation(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> Maybe<&2, ContinueError>:
  match messages:
    case Nil{}: Some{NoMessages{}}
    case T.LlmMessage{Ai.Assistant{_}} <> Nil{}: Some{AssistantLast{}}
    case _ <> Nil{}: None{}
    case _ <> rest: validateContinuation(DiagnosticDetails, Details, Custom, rest)

type EntryCapture<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  EntryCapture{services: Services<DiagnosticDetails, Details, Custom, Error>, stream: StreamFn.Selection<DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error>}

def explicit(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data, capture: LoopCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>:
  match capture:
    case LoopCapture{services, stream}: EntryCapture{services, StreamFn.Explicit{stream}}

def resolvedEntry(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, services: Services<DiagnosticDetails, Details, Custom, Error>, state: RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>, stream: Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error)>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match state stream:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{streamError(error)})
    case RequestState{context, config, messages} Done{provider}: runLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, LoopCapture{services, provider}, context, config, messages)

def enter(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, prepared: Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{services, selection} Done{state}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
        stream : Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error)> <- StreamFn.resolve(DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error, selection)
        resolvedEntry(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, services, state, stream)

def afterTurnStart(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
        prepared : Result<&2, &2, Error, RequestState<DiagnosticDetails, Details, Custom, Error, Telemetry>> <- deliverTurn(DiagnosticDetails, Details, Custom, Error, Telemetry, RequestState{context, config, Nil{}}, messages, sink, TurnNext{})
        enter(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, prepared)

def afterAgentStart(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
        started : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        afterTurnStart(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, started)

def startEntry(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match capture:
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentStart{})
        afterAgentStart(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, emitted)

def declaredEntry(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, messages: Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match messages:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{declarationError(error)})
    case Declaration.Success{initial}: startEntry(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, context, config, initial)

# Reconcile prompt declarations before emitting the initial event prefix.
# Callback/update/batch ownership follows runLoop's explicit lifetime.
def runAgentLoop(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, prompts: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>>:
    messages : Declaration.DeclarationResult<List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>> <- declareToolChanges(DiagnosticDetails, Details, Custom, Error, context, prompts)
    declaredEntry(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, context, config, messages)

def continueValidatedEntry(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, error: Maybe<&2, ContinueError>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>, Fail{entryError(cause)})
    case None{}: startEntry(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, capture, context, config, Nil{})

def runAgentLoopContinue(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>):
  match context:
    case T.AgentContext{messages, _}: continueValidatedEntry(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, capture, context, config, validateContinuation(DiagnosticDetails, Details, Custom, messages))


def Messages(-DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>
def LoopEvent(-DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: T.AgentEvent<DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>
def StreamOutcome(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: Result<&2, &2, Error, Messages(DiagnosticDetails, Details, Custom)>
def Stream(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: Stream.EventStream<LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error)>

# Provider, validator, cancellation and configuration callbacks are borrowed.
# Keep them alive until disposal has drained the loop and its tool batches.
type Options<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -Telemetry: Data> is Data:
  Options{signal: Maybe<&2, Abort.AbortSignal<Unit>>, validate: C.Callback<ToolValidationInput, Result<&2, &2, Error, Schema.Value>>, isAborted: C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool>, emptyDetails: Details, stream: StreamFn.Selection<DiagnosticDetails, Details, T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, Error>}

type StreamRun<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  StreamRun{stream: Stream(DiagnosticDetails, Details, Custom, Error), worker: Chan(Unit), emitStream: C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), Emission<Error>>, sink: C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>>, updates: Owners(Details, Error), batches: Batches(DiagnosticDetails, Details, Custom, Error)}

type Start<-DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Prompt{messages: Messages(DiagnosticDetails, Details, Custom)}
  StreamContinue{}

def extractStream(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, unused: Unit, event: LoopEvent(DiagnosticDetails, Details, Custom)) -> IO(StreamOutcome(DiagnosticDetails, Details, Custom, Error)):
  match event:
    case T.AgentEnd{messages}: IO.pure(StreamOutcome(DiagnosticDetails, Details, Custom, Error), Done{messages})
    case _: IO.pure(StreamOutcome(DiagnosticDetails, Details, Custom, Error), Done{Nil{}})

def createStream(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data) -> IO(Stream(DiagnosticDetails, Details, Custom, Error)):
  do IO<Stream(DiagnosticDetails, Details, Custom, Error)>:
    check : C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), Bool> <- C.create(~Unit, ~LoopEvent(DiagnosticDetails, Details, Custom), ~Bool, ~(agentStreamComplete(DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>)), Unit{})
    finish : C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error)> <- C.create(~Unit, ~LoopEvent(DiagnosticDetails, Details, Custom), ~StreamOutcome(DiagnosticDetails, Details, Custom, Error), ~(extractStream(DiagnosticDetails, Details, Custom, Error)), Unit{})
    Stream.create(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), check, finish)

def emitStream(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, stream: Stream(DiagnosticDetails, Details, Custom, Error), event: LoopEvent(DiagnosticDetails, Details, Custom)) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    Stream.push(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), stream, event)
    return EmissionReady{Done{Unit{}}}

def executeStream(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<DiagnosticDetails, Details, Custom>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(StreamOutcome(DiagnosticDetails, Details, Custom, Error)):
  match start:
    case Prompt{messages}: runAgentLoop(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, messages, context, config, capture)
    case StreamContinue{}: runAgentLoopContinue(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, capture)

# On success agent_end has already settled the result. On failure, end closes
# event iteration and settles a typed error without inventing an agent_end.
def work(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<DiagnosticDetails, Details, Custom>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, capture: EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry>, stream: Stream(DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  do IO<Unit>:
    outcome : StreamOutcome(DiagnosticDetails, Details, Custom, Error) <- executeStream(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture)
    Stream.end(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), stream, Some{outcome})

def launch(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<DiagnosticDetails, Details, Custom>, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, options: Options<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(StreamRun<DiagnosticDetails, Details, Custom, Error>):
  match options:
    case Options{signal, validate, isAborted, emptyDetails, selection}:
      do IO<StreamRun<DiagnosticDetails, Details, Custom, Error>>:
        +stream : Stream(DiagnosticDetails, Details, Custom, Error) <- createStream(~DiagnosticDetails, ~Details, ~Custom, ~Error)
        +emitter : C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), Emission<Error>> <- C.create(~Stream(DiagnosticDetails, Details, Custom, Error), ~LoopEvent(DiagnosticDetails, Details, Custom), ~Emission<Error>, ~(emitStream(DiagnosticDetails, Details, Custom, Error)), stream)
        +sink : C.Callback<LoopEvent(DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>> <- createAwaitedEventSink(~DiagnosticDetails, ~Details, ~Custom, ~T.AgentToolResult<Details>, ~T.AgentToolResult<Details>, ~Error, emitter)
        +updates : Owners(Details, Error) <- newOwners(Details, Error)
        +batches : Batches(DiagnosticDetails, Details, Custom, Error) <- newBatches(DiagnosticDetails, Details, Custom, Error)
        capture : EntryCapture<DiagnosticDetails, Details, Custom, Error, Telemetry> = EntryCapture{Services{signal, validate, isAborted, emitter, sink, updates, batches, emptyDetails}, selection}
        worker : Chan(Unit) <- IO.fork(Unit, work(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture, stream))
        return StreamRun{stream, worker, emitter, sink, updates, batches}

def agentLoop(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, prompts: Messages(DiagnosticDetails, Details, Custom), context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, options: Options<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(StreamRun<DiagnosticDetails, Details, Custom, Error>):
  launch(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, Prompt{prompts}, context, config, options)

def continueValidatedStream(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, options: Options<DiagnosticDetails, Details, Custom, Error, Telemetry>, error: Maybe<&2, ContinueError>) -> IO(Result<&2, &2, Error, StreamRun<DiagnosticDetails, Details, Custom, Error>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, StreamRun<DiagnosticDetails, Details, Custom, Error>>, Fail{entryError(cause)})
    case None{}:
      do IO<Result<&2, &2, Error, StreamRun<DiagnosticDetails, Details, Custom, Error>>>:
        run : StreamRun<DiagnosticDetails, Details, Custom, Error> <- launch(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, StreamContinue{}, context, config, options)
        return Done{run}

# Invalid continuation is rejected before allocating a stream or starting work.
def agentLoopContinue(~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, ~Telemetry: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, +context: T.AgentContext<DiagnosticDetails, Details, Custom, Error>, config: T.AgentLoopConfig<DiagnosticDetails, Details, Custom, Error, Telemetry>, options: Options<DiagnosticDetails, Details, Custom, Error, Telemetry>) -> IO(Result<&2, &2, Error, StreamRun<DiagnosticDetails, Details, Custom, Error>>):
  match context:
    case T.AgentContext{messages, _}: continueValidatedStream(~DiagnosticDetails, ~Details, ~Custom, ~Error, ~Telemetry, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, options, validateContinuation(DiagnosticDetails, Details, Custom, messages))

def streamOutcome(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, run: StreamRun<DiagnosticDetails, Details, Custom, Error>) -> IO(StreamOutcome(DiagnosticDetails, Details, Custom, Error)):
  match run:
    case StreamRun{stream, _, _, _, _, _}: Stream.resultValue(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), stream)

def iterator(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, run: StreamRun<DiagnosticDetails, Details, Custom, Error>) -> IO(Stream.Iterator<LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error)>):
  match run:
    case StreamRun{stream, _, _, _, _, _}: Stream.iterator(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), stream)

# Single-owner disposal: retire iterators/result observers and retained tool
# update aliases first. Failed results may settle while sibling tools still run.
def disposeStream(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, +stream: Stream(DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  match stream:
    case Stream.EventStream{_, _, check, finish}:
      do IO<Unit>:
        Stream.dispose(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), stream)
        C.dispose(LoopEvent(DiagnosticDetails, Details, Custom), Bool, check)
        C.dispose(LoopEvent(DiagnosticDetails, Details, Custom), StreamOutcome(DiagnosticDetails, Details, Custom, Error), finish)

def disposeStreamRun(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, run: StreamRun<DiagnosticDetails, Details, Custom, Error>) -> IO(Unit):
  match run:
    case StreamRun{stream, worker, emitter, sink, updates, batches}:
      do IO<Unit>:
        joined : Unit <- IO.join(Unit, worker)
        disposeBatches(DiagnosticDetails, Details, Custom, Error, batches)
        disposeOwners(Details, Error, updates)
        C.dispose(LoopEvent(DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>, sink)
        C.dispose(LoopEvent(DiagnosticDetails, Details, Custom), Emission<Error>, emitter)
        disposeStream(DiagnosticDetails, Details, Custom, Error, stream)
