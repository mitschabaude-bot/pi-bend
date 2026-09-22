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

def ticketScope(-Error: Data, scope: Scope<Error>, index: Maybe<&2, Nat>) -> Maybe<&1, Ticket<Error>>:
  match index:
    case None{}: None{}
    case Some{value}: Some{Ticket{scope, value}}

def begin(-Error: Data, +scope: Scope<Error>) -> IO(Maybe<&1, Ticket<Error>>):
  match scope:
    case Scope{state, _, _}:
      do IO<Maybe<&1, Ticket<Error>>>:
        index : Maybe<&2, Nat> <- R.modify(State<Error>, Maybe<&2, Nat>, state, current => reserve(Error, current))
        return ticketScope(Error, scope, index)

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

def resultScope(-Error: Data, scope: Scope<Error>) -> IO(ScopeOutcome(Error)):
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
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurnLocal, prepareNextTurnLocal, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, turnReasoning(reasoning, requestedThinking), deferred, thinkingBudgets, choose(Ai.Model<Value>, model, replacementModel), convertToLlm, transformContext, getApiKey, shouldStopAfterTurnLocal, prepareNextTurnLocal, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

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
  AssistantRequest{context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), streamFunction: T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, ExecutionError)}

# The lease is released after the loop's last read. An earlier failure wins
# over a release failure; a clean release keeps the message.
def released(-Arguments: Data, -DiagnosticDetails: Data, -ExecutionError: Data, result: Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, cleanup: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>:
  match result cleanup:
    case Fail{error} _: Fail{error}
    case Done{message} Done{_}: Done{message}
    case Done{_} Fail{error}: Fail{error}

def openedAssistantResponse(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -PartialResult: Data, -ExecutionResult: Data, context: R.Ref<T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, ExecutionError), opened: Result<&2, &1, ExecutionError, T.StreamLease<Arguments, DiagnosticDetails, ExecutionError>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match opened:
    case Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Fail{error})
    case Done{T.StreamLease{events, release}}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        result : Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- consumeAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, AssistantResponseConsumer{context, emit, events})
        cleanup : Result<&2, &2, ExecutionError, Unit> <- release
        return released(Arguments, DiagnosticDetails, ExecutionError, result, cleanup)

def dispatchAssistantRequest(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, -PartialResult: Data, -ExecutionResult: Data, request: AssistantRequest<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, PartialResult, ExecutionResult>, normalized: Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>, resolved: Result<&2, &2, ExecutionError, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>):
  match request resolved:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>, Fail{error})
    case AssistantRequest{context, _, _, emit, streamFunction} Done{+options}:
      do IO<Result<&2, &2, ExecutionError, Ai.AssistantMessage<Arguments, DiagnosticDetails>>>:
        value : T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch> = options
        response : Result<&2, &1, ExecutionError, T.StreamLease<Arguments, DiagnosticDetails, ExecutionError>> <- C.call(T.StreamInput<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>>, Result<&2, &1, ExecutionError, T.StreamLease<Arguments, DiagnosticDetails, ExecutionError>>, streamFunction, T.StreamInput{selectedRequestModel(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, value), normalized, Some{options}})
        openedAssistantResponse(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, PartialResult, ExecutionResult, context, emit, response)

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

def createErrorToolResult(-DetailValue: Data, message: String) -> T.AgentToolResult<Record.Record<DetailValue>>:
  T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, Record.new(DetailValue), None{}, None{}}

# Failure details are supplied by the caller, preserving the tool result type.
type TruncatedToolCallRun<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data> is Data:
  TruncatedToolCallRun{emit: AgentEventSink(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ExecutionError), emptyDetails: Details}

def truncatedCallError(-Arguments: Data, call: Ai.ToolCall<Arguments>) -> String:
  match call:
    case Ai.ToolCall{_, name, _, _, _}: "Tool call \"" ++ name ++ "\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."

def toolExecutionStartEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -Details: Data, call: Ai.ToolCall<Arguments>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

def deliveredTruncatedResult(-Details: Data, -ExecutionError: Data, message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, ExecutionError, Unit>) -> Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{message}

def afterTruncatedExecutionEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, finalized: FinalizedToolCallOutcome<Arguments, Details>, emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>, Fail{error})
    case TruncatedToolCallRun{emit, emptyDetails} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Arguments, Details, finalized)
        delivered : Result<&2, &2, ExecutionError, Unit> <- emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>, ExecutionError, message, emit)
        return deliveredTruncatedResult(Details, ExecutionError, message, delivered)

def afterTruncatedStart(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, +call: T.AgentToolCall(Arguments), emitted: Result<&2, &2, ExecutionError, Unit>) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>, Fail{error})
    case TruncatedToolCallRun{emit, emptyDetails} Done{_}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        result : T.AgentToolResult<Details> = T.AgentToolResult{Ai.TextImageText{Ai.TextContent{truncatedCallError(Arguments, call), None{}}} <> Nil{}, emptyDetails, None{}, None{}}
        +finalized : FinalizedToolCallOutcome<Arguments, Details> = FinalizedToolCallOutcome{call, result, True{}}
        ended : Result<&2, &2, ExecutionError, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionError, finalized, emit)
        afterTruncatedExecutionEnd(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, finalized, ended)

def failTruncatedToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, +call: T.AgentToolCall(Arguments)) -> IO(Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>):
  match run:
    case TruncatedToolCallRun{emit, emptyDetails}:
      do IO<Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>>:
        emitted : Result<&2, &2, ExecutionError, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, T.AgentToolResult<Details>>, Result<&2, &2, ExecutionError, Unit>, emit, toolExecutionStartEvent(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, Details, call))
        afterTruncatedStart(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, call, emitted)

def accumulateTruncated(-Details: Data, -ExecutionError: Data, previous: List<&2, Ai.ToolResultMessage<Details>>, result: Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>>) -> Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Details>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{message}: Done{message <> previous}

def failTruncatedCalls(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, +run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, calls: List<&2, T.AgentToolCall(Arguments)>, state: Result<&2, &2, ExecutionError, List<&2, Ai.ToolResultMessage<Details>>>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>):
  match calls state:
    case _ Fail{error}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>, Fail{error})
    case Nil{} Done{messages}: IO.pure(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>, Done{ExecutedToolCallBatch{List.reverse(&2, Ai.ToolResultMessage<Details>, messages), False{}}})
    case call <> tail Done{messages}:
      do IO<Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>>:
        result : Result<&2, &2, ExecutionError, Ai.ToolResultMessage<Details>> <- failTruncatedToolCall(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, call)
        failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, tail, accumulateTruncated(Details, ExecutionError, messages, result))

def failToolCallsFromTruncatedMessage(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionError: Data, -Details: Data, run: TruncatedToolCallRun<Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details>, calls: List<&2, T.AgentToolCall(Arguments)>) -> IO(Result<&2, &2, ExecutionError, ExecutedToolCallBatch<Details>>):
  failTruncatedCalls(Parameters, Arguments, DiagnosticDetails, Custom, PartialResult, ExecutionError, Details, run, calls, Done{Nil{}})

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

# Error values remain typed; formatting occurs only at the tool-result boundary.
def failedToolOutcome(-Details: Data, -Error: Data, details: Details, renderError: Error -> String, error: Error) -> ExecutedToolCallOutcome<Details>:
  ExecutedToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{renderError(error), None{}}} <> Nil{}, details, None{}, None{}}, True{}}

def resolveToolHookResult(-Details: Data, -Error: Data, executed: ExecutedToolCallOutcome<Details>, failureDetails: Details, renderError: Error -> String, outcome: Result<&2, &2, Error, Maybe<&2, T.AfterToolCallResult<Details>>>) -> ExecutedToolCallOutcome<Details>:
  match outcome:
    case Fail{error}: failedToolOutcome(Details, Error, failureDetails, renderError, error)
    case Done{patch}: applyAfterToolCallResult(Details, executed, patch)

def finalizeToolOutcome(-Arguments: Data, -Details: Data, call: Ai.ToolCall<Arguments>, executed: ExecutedToolCallOutcome<Details>) -> FinalizedToolCallOutcome<Arguments, Details>:
  match executed:
    case ExecutedToolCallOutcome{result, isError}: FinalizedToolCallOutcome{call, result, isError}

def selectedAfterToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hook}: hook

def invokeAfterToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, hook: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>>>, input: T.ToolHookInput<T.AfterToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>) -> IO(Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>, Done{None{}})
    case Some{callback}: C.call(T.ToolHookInput<T.AfterToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>, Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>>, callback, input)

# The hook sees validated execution arguments alongside the original call.
# Failure becomes an error tool result; it is not an event-listener failure.
def finalizeExecutedToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, prepared: PreparedToolCall<Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError>, executed: ExecutedToolCallOutcome<ToolDetails>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, failureDetails: ToolDetails, renderError: ExecutionError -> String) -> IO(FinalizedToolCallOutcome<Arguments, ToolDetails>):
  match prepared executed:
    case PreparedToolCall{+call, _, args} ExecutedToolCallOutcome{+result, +isError}:
      do IO<FinalizedToolCallOutcome<Arguments, ToolDetails>>:
        outcome : Result<&2, &2, ExecutionError, Maybe<&2, T.AfterToolCallResult<ToolDetails>>> <- invokeAfterToolCall(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, selectedAfterToolCall(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch, config), T.ToolHookInput{T.AfterToolCallContext{assistant, call, args, result, isError, context}, signal})
        return finalizeToolOutcome(Arguments, ToolDetails, call, resolveToolHookResult(ToolDetails, ExecutionError, ExecutedToolCallOutcome{result, isError}, failureDetails, renderError, outcome))

# Agent-end settles the returned message history independently of consumption.
def AgentEventStream(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data) -> Data:
  Stream.EventStream<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>

def agentStreamComplete(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, unused: Unit, event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Bool):
  match event:
    case T.AgentEnd{_}: IO.pure(Bool, True{})
    case _: IO.pure(Bool, False{})

def agentStreamExtract(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, unused: Unit, event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)):
  match event:
    case T.AgentEnd{messages}: IO.pure(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), messages)
    case _: IO.pure(T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Nil{})

def createAgentStream(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data) -> IO(AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)):
  do IO<AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)>:
    check : C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Bool> <- C.create(~Unit, ~T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Bool, ~(agentStreamComplete(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)), Unit{})
    extract : C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)> <- C.create(~Unit, ~T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), ~(agentStreamExtract(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)), Unit{})
    Stream.create(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), check, extract)

def disposeAgentStream(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, +stream: AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)) -> IO(Unit):
  match stream:
    case Stream.EventStream{_, _, check, extract}:
      do IO<Unit>:
        Stream.dispose(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), stream)
        C.dispose(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Bool, check)
        C.dispose(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), extract)

# The update emitter returns a delivery handle after its ordered start effects.
# This is the native equivalent of invoking an async sink without awaiting it.
type ToolUpdateCapture<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  ToolUpdateCapture{scope: Scope<Error>, call: Ai.ToolCall<Arguments>, emit: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>}

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

def emitAcceptedToolUpdate(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, ticket: Maybe<&1, Ticket<Error>>, call: Ai.ToolCall<Arguments>, partial: T.AgentToolResult<Details>, emit: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>) -> IO(Unit):
  match ticket call:
    case None{} _: IO.pure(Unit, Unit{})
    case Some{accepted} Ai.ToolCall{id, name, arguments, _, _}:
      do IO<Unit>:
        delivery : Emission<Error> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>, emit, T.ToolExecutionUpdate{id, name, arguments, partial})
        trackToolUpdate(Error, accepted, delivery)

def forwardToolUpdate(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, capture: ToolUpdateCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Error>, partial: T.AgentToolResult<Details>) -> IO(Unit):
  match capture:
    case ToolUpdateCapture{scope, call, emit}:
      do IO<Unit>:
        ticket : Maybe<&1, Ticket<Error>> <- begin(Error, scope)
        emitAcceptedToolUpdate(Parameters, Arguments, DiagnosticDetails, Details, Custom, Error, ticket, call, partial, emit)

def createToolUpdateRun(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data, call: Ai.ToolCall<Arguments>, emit: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>) -> IO(ToolUpdateRun<Details, Error>):
  do IO<ToolUpdateRun<Details, Error>>:
    +scope : Scope<Error> <- new(Error)
    callback : T.AgentToolUpdateCallback(Details) <- C.create(~ToolUpdateCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Error>, ~T.AgentToolResult<Details>, ~Unit, ~(forwardToolUpdate(Parameters, Arguments, DiagnosticDetails, Details, Custom, Error)), ToolUpdateCapture{scope, call, emit})
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
def executePreparedToolCall(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -Error: Data, prepared: PreparedToolCall<Parameters, Arguments, Details, RawArguments, Signal, Error>, signal: Maybe<&2, Signal>, run: ToolUpdateRun<Details, Error>, failureDetails: Details, renderError: Error -> String) -> IO(Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>):
  match prepared run:
    case PreparedToolCall{Ai.ToolCall{id, _, _, _, _}, T.AgentTool{_, _, _, _, _, _, execute, _, _}, args} ToolUpdateRun{+scope, callback}:
      do IO<Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>>:
        executed : Result<&2, &2, Error, T.AgentToolResult<Details>> <- C.call(T.ToolExecutionInput<Arguments, Signal, Details>, Result<&2, &2, Error, T.AgentToolResult<Details>>, execute, T.ToolExecutionInput{id, args, signal, Some{callback}})
        close(Error, scope)
        settled : Result<&2, &2, Error, Unit> <- resultScope(Error, scope)
        return checkedExecutionOutcome(Details, Error, executed, settled, failureDetails, renderError)

# Native sinks distinguish ordered initiation from optional async completion.
def StartingAgentEventSink(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data) -> Data:
  C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Emission<Error>>

def awaitStartedEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data, emitter: StartingAgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error), event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    delivery : Emission<Error> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, Emission<Error>, emitter, event)
    wait(Error, delivery)

# The adapter owns only its wrapper; its emitter remains caller-owned.
def createAwaitedEventSink(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data, ~Error: Data, emitter: StartingAgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)) -> IO(AgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)):
  C.create(~StartingAgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error), ~T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Result<&2, &2, Error, Unit>, ~(awaitStartedEvent(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)), emitter)

def startAgentStreamEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, -Error: Data, stream: AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult), event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    Stream.push(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, T.AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), stream, event)
    return EmissionReady{Done{Unit{}}}

def createAgentStreamEmitter(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~ToolDetails: Data, ~Custom: Data, ~PartialResult: Data, ~ExecutionResult: Data, ~Error: Data, stream: AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult)) -> IO(StartingAgentEventSink(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)):
  C.create(~AgentEventStream(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult), ~T.AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>, ~Emission<Error>, ~(startAgentStreamEvent(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult, Error)), stream)

# Validation remains an explicit required service until the canonical typed
# schema compiler supplies it. Both raw and adapted calls must be validated.
type ToolValidationInput<-Parameters: Data, -Raw: Data, -Adapted: Data> is Data:
  ToolValidationInput{tool: Ai.Tool<Parameters>, call: PreparedToolCallArguments<Raw, Adapted>}

type ToolPreparationState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data> is Data:
  ToolPreparationState{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, preparation: ToolCallPreparation<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>}

def executableToolName(-Parameters: Data, -Arguments: Data, -Details: Data, -Raw: Data, -Signal: Data, -Error: Data, tool: T.AgentTool<Parameters, Arguments, Details, Raw, Signal, Error>) -> String:
  match tool:
    case T.AgentTool{name, _, _, _, _, _, _, _, _}: name

def findExecutableTool(-Parameters: Data, -Arguments: Data, -Details: Data, -Raw: Data, -Signal: Data, -Error: Data, +name: String, tools: List<&2, T.AgentTool<Parameters, Arguments, Details, Raw, Signal, Error>>) -> Maybe<&2, T.AgentTool<Parameters, Arguments, Details, Raw, Signal, Error>>:
  match tools:
    case Nil{}: None{}
    case +tool <> rest:
      matches = String.eq(name, executableToolName(Parameters, Arguments, Details, Raw, Signal, Error, tool))
      selected = Bool.pick(Unit -> Maybe<&2, T.AgentTool<Parameters, Arguments, Details, Raw, Signal, Error>>, matches, unused => Some{tool}, unused => findExecutableTool(Parameters, Arguments, Details, Raw, Signal, Error, name, rest))
      selected(Unit{})

def immediatePreparation(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, message: String, details: Details, terminate: Bool) -> ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>:
  result = {T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, None{}}} <> Nil{}, details, None{}, Bool.pick(Maybe<&2, Bool>, terminate, Some{True{}}, None{})} : T.AgentToolResult<Details>}
  ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{result, True{}}}}

def checkedArgumentPreparation(-Parameters: Data, -Arguments: Data, -Details: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, tool: T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>, prepared: Result<&2, &2, Error, PreparedToolCallArguments<Arguments, ValidatedArguments>>, validate: C.Callback<ToolValidationInput<Parameters, Arguments, ValidatedArguments>, Result<&2, &2, Error, ValidatedArguments>>) -> IO(Result<&2, &2, Error, ValidatedArguments>):
  match prepared:
    case Fail{error}: IO.pure(Result<&2, &2, Error, ValidatedArguments>, Fail{error})
    case Done{call}: C.call(ToolValidationInput<Parameters, Arguments, ValidatedArguments>, Result<&2, &2, Error, ValidatedArguments>, validate, ToolValidationInput{T.toTool(Parameters, ValidatedArguments, Details, Arguments, Signal, Error, tool), call})

def selectedBeforeToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, Signal>, Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hook, _}: hook

def invokeBeforeToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, call: Ai.ToolCall<Arguments>, args: ValidatedArguments, signal: Maybe<&2, Signal>, hook: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, Signal>, Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>>>) -> IO(Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>, Done{T.BeforeToolCallUpdate{args, context, None{}}})
    case Some{callback}: C.call(T.ToolHookInput<T.BeforeToolCallContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, Signal>, Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>, callback, T.ToolHookInput{T.BeforeToolCallContext{assistant, call, args, context}, signal})

def decidedPreparation(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, tool: T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>, call: Ai.ToolCall<Arguments>, args: ValidatedArguments, failureDetails: Details, decision: BeforeToolCallDecision) -> ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>:
  match decision:
    case ProceedWithToolCall{}: ToolPreparationState{context, Prepared{PreparedToolCall{call, tool, args}}}
    case RejectToolCall{message, terminate}: immediatePreparation(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, message, failureDetails, terminate)

def afterBeforeToolCall(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, tool: T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>, call: Ai.ToolCall<Arguments>, before: Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>, signal: Maybe<&2, Signal>, isAborted: (Maybe<&2, Signal> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>):
  match before:
    case Fail{error}: IO.pure(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>, Fail{error})
    case Done{T.BeforeToolCallUpdate{args, context, decision}}:
      do IO<Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>:
        aborted : Bool <- isAborted(signal)
        return Done{decidedPreparation(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, tool, call, args, failureDetails, beforeToolCallDecision(aborted, decision))}

def withValidatedToolArguments(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, +call: Ai.ToolCall<Arguments>, tool: T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>, validated: Result<&2, &2, Error, ValidatedArguments>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch>, +signal: Maybe<&2, Signal>, isAborted: (Maybe<&2, Signal> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>):
  match validated:
    case Fail{error}: IO.pure(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>, Fail{error})
    case Done{args}:
      do IO<Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>:
        before : Result<&2, &2, Error, T.BeforeToolCallUpdate<ValidatedArguments, T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>> <- invokeBeforeToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, assistant, call, args, signal, selectedBeforeToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch, config))
        afterBeforeToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, tool, call, before, signal, isAborted, failureDetails)

def prepareFoundTool(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, +call: Ai.ToolCall<Arguments>, found: Maybe<&2, T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, validate: C.Callback<ToolValidationInput<Parameters, Arguments, ValidatedArguments>, Result<&2, &2, Error, ValidatedArguments>>, isAborted: (Maybe<&2, Signal> -> IO(Bool)), failureDetails: Details) -> IO(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>):
  match found:
    case None{}: IO.pure(Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>, Done{immediatePreparation(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, "Tool " ++ callName(Arguments, call) ++ " not found", failureDetails, False{})})
    case Some{+tool}:
      do IO<Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>>:
        adapted : Result<&2, &2, Error, PreparedToolCallArguments<Arguments, ValidatedArguments>> <- prepareToolCallArguments(Parameters, ValidatedArguments, Details, Arguments, Signal, Error, tool, call)
        validated : Result<&2, &2, Error, ValidatedArguments> <- checkedArgumentPreparation(Parameters, Arguments, Details, ValidatedArguments, Signal, Error, tool, adapted, validate)
        withValidatedToolArguments(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, tool, validated, config, signal, isAborted, failureDetails)

def preparationError(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, failureDetails: Details, renderError: Error -> String, outcome: Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>) -> ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>:
  match outcome:
    case Done{value}: value
    case Fail{error}: immediatePreparation(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, renderError(error), failureDetails, False{})

# No validation bypass: the caller supplies a real validator/typed decoder.
# The with-suffix marks this injectable path; the default schema-backed entry
# point remains pending until full validation is implemented.
def prepareToolCallWith(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, +call: Ai.ToolCall<Arguments>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, validate: C.Callback<ToolValidationInput<Parameters, Arguments, ValidatedArguments>, Result<&2, &2, Error, ValidatedArguments>>, isAborted: (Maybe<&2, Signal> -> IO(Bool)), +failureDetails: Details, renderError: Error -> String) -> IO(ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>):
  do IO<ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>>:
    found : Maybe<&2, T.AgentTool<Parameters, ValidatedArguments, Details, Arguments, Signal, Error>> = findExecutableTool(Parameters, ValidatedArguments, Details, Arguments, Signal, Error, callName(Arguments, call), availableContextTools(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context))
    outcome : Result<&2, &2, Error, ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error>> <- prepareFoundTool(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, found, config, signal, validate, isAborted, failureDetails)
    return preparationError(Parameters, Arguments, DiagnosticDetails, Details, Custom, ValidatedArguments, Signal, Error, context, failureDetails, renderError, outcome)


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

type CallCapture<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  CallCapture{assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, validate: C.Callback<ToolValidationInput<Parameters, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emit: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, owners: Owners(Details, Error), failureDetails: Details}

def CallInput(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data) -> Data: Invocation<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolCall<Arguments>>
def CallOutput(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data) -> Data: Result<&2, &2, Error, BatchCompleted<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>

type CallStep<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  CallBegin{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>}
  CallStarted{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>, emitted: Result<&2, &2, Error, Unit>}
  CallPrepared{call: Ai.ToolCall<Arguments>, prepared: ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  CallExecuted{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, prepared: PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>}
  CallFinalized{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, finalized: FinalizedToolCallOutcome<Arguments, Details>}
  CallEnded{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, finalized: FinalizedToolCallOutcome<Arguments, Details>, emitted: Result<&2, &2, Error, Unit>}
  CallDelivered{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, terminate: Bool, message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

def preparedCall(-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data, prepared: PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>) -> Ai.ToolCall<Arguments>:
  match prepared:
    case PreparedToolCall{call, _, _}: call

def startEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, call: Ai.ToolCall<Arguments>) -> T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: T.ToolExecutionStart{id, name, arguments}

# Each stage advances one call's lifecycle. The error renderer is lifted code;
# all changing state and effect resources are explicit capture/input values.
@unsafe
def advanceCall(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, step: CallStep<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)):
  match capture:
    case CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match step:
        case CallBegin{context, +call}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, startEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, call))
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallStarted{context, call, emitted})
        case CallStarted{_, _, Fail{error}}: IO.pure(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case CallStarted{context, +call, Done{_}}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            prepared : ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- prepareToolCallWith(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Signal>, Bool, isAborted, value), failureDetails, error => renderError(error))
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallPrepared{call, prepared})
        case CallPrepared{call, ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{result, isError}}}}:
          advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallFinalized{context, FinalizedToolCallOutcome{call, result, isError}})
        case CallPrepared{_, ToolPreparationState{context, Prepared{+prepared}}}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            +updates : ToolUpdateRun<Details, Error> <- createToolUpdateRun(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error, preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), emit)
            retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, ExecutedToolCallOutcome<Details>> <- executePreparedToolCall(Parameters, Validated, Details, Arguments, Signal, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallExecuted{context, prepared, outcome})
        case CallExecuted{_, _, Fail{error}}: IO.pure(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case CallExecuted{+context, prepared, Done{outcome}}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            finalized : FinalizedToolCallOutcome<Arguments, Details> <- finalizeExecutedToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallFinalized{context, finalized})
        case CallFinalized{context, +finalized}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallEnded{context, finalized, emitted})
        case CallEnded{_, _, Fail{error}}: IO.pure(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case CallEnded{context, +finalized, Done{_}}:
          do IO<CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            terminate : Bool = shouldTerminateToolBatch(Arguments, Details, finalized <> Nil{})
            +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Arguments, Details, finalized)
            emitted : Result<&2, &2, Error, Unit> <- emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, sink)
            advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallDelivered{context, terminate, message, emitted})
        case CallDelivered{_, _, _, Fail{error}}: IO.pure(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case CallDelivered{context, terminate, message, Done{_}}:
          IO.pure(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Done{BatchCompleted{context, message, terminate}})

def invokeCall(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, input: CallInput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)) -> IO(CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)):
  match input:
    case Invocation{context, call}: advanceCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, CallBegin{context, call})

def create(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(C.Callback<CallInput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>):
  C.create(~CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, ~CallInput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), ~CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), ~(invokeCall(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError)), capture)


# Preparation is sequential. ParallelImmediate outcomes emit their execution-end here;
# prepared entries are inert until the entire preparation pass has finished.
type Entry<-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  ParallelImmediate{finalized: FinalizedToolCallOutcome<Arguments, Details>}
  ParallelPrepared{prepared: PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>}

type Plan<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Plan{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entries: List<&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>>}

type PreparationStep<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  ParallelNext{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  ParallelStarted{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>, emitted: Result<&2, &2, Error, Unit>}
  Checked{call: Ai.ToolCall<Arguments>, preparation: ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  ParallelEnded{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>, emitted: Result<&2, &2, Error, Unit>}
  Stopped{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>, aborted: Bool}

# Each ParallelNext consumes a call. Other stages settle preparation or terminate it.
@unsafe
def prepareParallel(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, calls: List<&2, Ai.ToolCall<Arguments>>, reversed: List<&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>>, step: PreparationStep<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match capture:
    case CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match calls step:
        case Nil{} ParallelNext{context}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Plan{context, List.reverse(&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>, reversed)}})
        case +call <> rest ParallelNext{context}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, startEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, call))
            prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, rest, reversed, ParallelStarted{context, call, emitted})
        case _ ParallelStarted{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
        case remaining ParallelStarted{context, +call, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            prepared : ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- prepareToolCallWith(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Signal>, Bool, isAborted, value), failureDetails, error => renderError(error))
            prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Checked{call, prepared})
        case remaining Checked{call, ToolPreparationState{context, Immediate{ImmediateToolCallOutcome{valueResult, isError}}}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            +finalized : FinalizedToolCallOutcome<Arguments, Details> = FinalizedToolCallOutcome{call, valueResult, isError}
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, ParallelEnded{context, ParallelImmediate{finalized}, emitted})
        case remaining Checked{_, ToolPreparationState{context, Prepared{prepared}}}:
          prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, ParallelEnded{context, ParallelPrepared{prepared}, Done{Unit{}}})
        case _ ParallelEnded{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
        case remaining ParallelEnded{context, entry, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            stopped : Bool <- C.call(Maybe<&2, Signal>, Bool, isAborted, signal)
            prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Stopped{context, entry, stopped})
        case _ Stopped{context, entry, True{}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Plan{context, List.reverse(&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>, entry <> reversed)}})
        case remaining Stopped{context, entry, False{}}:
          prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, entry <> reversed, ParallelNext{context})

# Every deferred call observes the final preparation context. This explicitly
# carries before-hook context updates without sharing a mutable message object.
type ExecutionCapture<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  ExecutionCapture{capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}

type ExecutionStep<-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  ParallelBegin{entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>}
  Aborted{prepared: PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, stopped: Bool}
  ParallelExecuted{prepared: PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallOutcome<Details>>}
  ParallelFinalized{finalized: FinalizedToolCallOutcome<Arguments, Details>}
  Emitted{finalized: FinalizedToolCallOutcome<Arguments, Details>, emitted: Result<&2, &2, Error, Unit>}

# Each transition advances one deferred call. ParallelImmediate entries already emitted
# end during preparation and must not emit it again or invoke the after hook.
@unsafe
def executeParallel(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +environment: ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, step: ExecutionStep<Parameters, Arguments, Details, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>):
  match environment:
    case ExecutionCapture{CallCapture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}, +context}:
      match step:
        case ParallelBegin{ParallelImmediate{finalized}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, Done{finalized})
        case ParallelBegin{ParallelPrepared{prepared}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>>:
            stopped : Bool <- C.call(Maybe<&2, Signal>, Bool, isAborted, signal)
            executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Aborted{prepared, stopped})
        case Aborted{prepared, True{}}:
          executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, ParallelFinalized{FinalizedToolCallOutcome{preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Operation aborted", None{}}} <> Nil{}, failureDetails, None{}, None{}}, True{}}})
        case Aborted{+prepared, False{}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>>:
            +updates : ToolUpdateRun<Details, Error> <- createToolUpdateRun(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error, preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), emit)
            retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, ExecutedToolCallOutcome<Details>> <- executePreparedToolCall(Parameters, Validated, Details, Arguments, Signal, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, ParallelExecuted{prepared, outcome})
        case ParallelExecuted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, Fail{error})
        case ParallelExecuted{prepared, Done{outcome}}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>>:
            finalized : FinalizedToolCallOutcome<Arguments, Details> <- finalizeExecutedToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, ParallelFinalized{finalized})
        case ParallelFinalized{+finalized}:
          do IO<Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>>:
            emitted : Result<&2, &2, Error, Unit> <- emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Emitted{finalized, emitted})
        case Emitted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, Fail{error})
        case Emitted{finalized, Done{_}}: IO.pure(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, Done{finalized})

def invokeParallel(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, environment: ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>):
  executeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, ParallelBegin{entry})

# Keep worker captures alive after a prompt failure. dispose drains all workers
# before retiring the execution callback; the caller still owns sink/update aliases.
type ParallelRun<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  ParallelRun{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, collection: All.Run<Error, FinalizedToolCallOutcome<Arguments, Details>>, worker: C.Callback<Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>}

def beginPrepared(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, prepared: Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> IO(Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case CallCapture{_, _, _, _, _, _, sink, _, _} Done{Plan{+context, entries}}:
      do IO<Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        +worker : C.Callback<Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>> <- C.create(~ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, ~Entry<Parameters, Arguments, Details, Validated, Signal, Error>, ~Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, ~(invokeParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError)), ExecutionCapture{capture, context})
        collection : All.Run<Error, FinalizedToolCallOutcome<Arguments, Details>> <- All.start(Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Error, FinalizedToolCallOutcome<Arguments, Details>, entries, worker)
        return Done{ParallelRun{context, collection, worker, sink}}

def startParallel(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, calls: List<&2, Ai.ToolCall<Arguments>>) -> IO(Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  do IO<Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
    prepared : Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- prepareParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, calls, Nil{}, ParallelNext{context})
    beginPrepared(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, prepared)

type ParallelDeliveryStep<-Details: Data, -Error: Data> is Data:
  ParallelReady{}
  ParallelDelivered{message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

# Successful execution-end events all precede ordered message delivery. A
# message listener failure stops delivery immediately; no later message starts.
@unsafe
def deliverParallel(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, remaining: List<&2, FinalizedToolCallOutcome<Arguments, Details>>, reversed: List<&2, Ai.ToolResultMessage<Details>>, terminate: Bool, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: ParallelDeliveryStep<Details, Error>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match remaining step:
    case Nil{} ParallelReady{}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Done{Batch{context, List.reverse(&2, Ai.ToolResultMessage<Details>, reversed), terminate}})
    case finalized <> rest ParallelReady{}:
      do IO<Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>>:
        +message : Ai.ToolResultMessage<Details> <- createToolResultMessage(Arguments, Details, finalized)
        emitted : Result<&2, &2, Error, Unit> <- emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, sink)
        deliverParallel(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, rest, reversed, terminate, sink, ParallelDelivered{message, emitted})
    case _ ParallelDelivered{_, Fail{error}}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case rest ParallelDelivered{message, Done{_}}: deliverParallel(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, rest, message <> reversed, terminate, sink, ParallelReady{})

def collected(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, valueResult: Result<&2, &2, Error, List<&2, FinalizedToolCallOutcome<Arguments, Details>>>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match valueResult:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case Done{+finalized}: deliverParallel(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, finalized, Nil{}, shouldTerminateToolBatch(Arguments, Details, finalized), sink, ParallelReady{})

# One consumer owns result-message delivery. On failure this may return while
# sibling execution is still running; dispose is the separate lifetime boundary.
def resultParallel(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match run:
    case ParallelRun{context, collection, _, sink}:
      do IO<Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>>:
        finalized : Result<&2, &2, Error, List<&2, FinalizedToolCallOutcome<Arguments, Details>>> <- All.result(Error, FinalizedToolCallOutcome<Arguments, Details>, collection)
        collected(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, sink, finalized)

def disposeParallel(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match run:
    case ParallelRun{_, collection, worker, _}:
      do IO<Unit>:
        All.dispose(Error, FinalizedToolCallOutcome<Arguments, Details>, collection)
        C.dispose(Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, FinalizedToolCallOutcome<Arguments, Details>>, worker)


# Split around the last pending system message. Only that message's tool fields
# express pending intent; preceding declarations remain part of the baseline.
type ChangesPending<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Existing{before: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<Schema.Value>, after: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>}
  Absent{messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>}

def splitLast(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, reversed: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, after: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> ChangesPending<Arguments, DiagnosticDetails, Details, Custom>:
  match reversed:
    case Nil{}: Absent{after}
    case T.LlmMessage{Ai.System{system}} <> before: Existing{List.reverse(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, before), system, after}
    case message <> rest: splitLast(Arguments, DiagnosticDetails, Details, Custom, rest, message <> after)

def optional(-A: Data, values: List<&2, A>) -> Maybe<&2, List<&2, A>>:
  match values:
    case Nil{}: None{}
    case head <> tail: Some{head <> tail}

def withToolChanges(message: Ai.SystemMessage<Schema.Value>, changes: Transcript.ToolStateChanges<Schema.Value>) -> Ai.SystemMessage<Schema.Value>:
  match message changes:
    case Ai.SystemMessage{content, sections, _, _, timestamp} Transcript.ToolStateChanges{added, removed}:
      Ai.SystemMessage{content, sections, optional(Ai.Tool<Schema.Value>, added), optional(Ai.ToolReference, removed), timestamp}

def join(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, before: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<Schema.Value>, after: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, before, T.LlmMessage{Ai.System{system}} <> after)

def baseline(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: ChangesPending<Arguments, DiagnosticDetails, Details, Custom>) -> List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match pending:
    case Existing{before, system, after}: join(Arguments, DiagnosticDetails, Details, Custom, before, withToolChanges(system, Transcript.ToolStateChanges{Nil{}, Nil{}}), after)
    case Absent{messages}: messages

# Tool replay reads only native LLM system records. Custom messages do not pass
# through convertToLlm here; that callback is reserved for provider requests.
def llmMessages(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<Schema.Value, Arguments, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{message} <> rest: message <> llmMessages(Arguments, DiagnosticDetails, Details, Custom, rest)
    case T.CustomMessage{_} <> rest: llmMessages(Arguments, DiagnosticDetails, Details, Custom, rest)

def declarations(-Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data, tools: List<&2, T.AgentTool<Schema.Value, Validated, Details, Arguments, Signal, Error>>) -> List<&2, Ai.Tool<Schema.Value>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(Schema.Value, Validated, Details, Arguments, Signal, Error, tool) <> declarations(Arguments, Details, Validated, Signal, Error, rest)

type ChangePlan<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  ChangePlan{pending: ChangesPending<Arguments, DiagnosticDetails, Details, Custom>, changes: Transcript.ToolStateChanges<Schema.Value>}

def packagePlan(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: ChangesPending<Arguments, DiagnosticDetails, Details, Custom>, changes: Declaration.DeclarationResult<Transcript.ToolStateChanges<Schema.Value>>) -> Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>:
  match changes:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{changes}: Declaration.Success{ChangePlan{pending, changes}}

def plan(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pendingMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>:
  +pending = splitLast(Arguments, DiagnosticDetails, Details, Custom, List.reverse(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, pendingMessages), Nil{})
  history = List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, contextMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context), baseline(Arguments, DiagnosticDetails, Details, Custom, pending))
  previous = Transcript.getCurrentTools(Schema.Value, Arguments, DiagnosticDetails, Details, llmMessages(Arguments, DiagnosticDetails, Details, Custom, history))
  current = declarations(Arguments, Details, Validated, Signal, Error, availableContextTools(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context))
  packagePlan(Arguments, DiagnosticDetails, Details, Custom, pending, Transcript.getToolStateChanges(previous, current))

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
def insert(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +update: Ai.SystemMessage<Schema.Value>) -> List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{system}} <> rest: T.LlmMessage{Ai.System{system}} <> insert(Arguments, DiagnosticDetails, Details, Custom, rest, update)
    case remaining: T.LlmMessage{Ai.System{update}} <> remaining

def absent(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, changes: Transcript.ToolStateChanges<Schema.Value>, timestamp: Number.F64, changed: Bool) -> List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match changed:
    case False{}: messages
    case True{}: insert(Arguments, DiagnosticDetails, Details, Custom, messages, withToolChanges(Ai.SystemMessage{Ai.SystemText{""}, None{}, None{}, None{}, timestamp}, changes))

def applyAt(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, timestamp: Number.F64, planned: Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>) -> Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>:
  match planned:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{ChangePlan{Existing{before, +system, after}, +changes}}:
      Declaration.Success{join(Arguments, DiagnosticDetails, Details, Custom, before, replaceSystem(system, changes, hasChanges(changes) || pendingChanges(system)), after)}
    case Declaration.Success{ChangePlan{Absent{messages}, +changes}}:
      Declaration.Success{absent(Arguments, DiagnosticDetails, Details, Custom, messages, changes, timestamp, hasChanges(changes))}

def needsTimestamp(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>) -> Bool:
  match planned:
    case Declaration.Success{ChangePlan{Absent{_}, changes}}: hasChanges(changes)
    case _: False{}

def commit(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>, timestampNeeded: Bool) -> IO(Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match timestampNeeded:
    case False{}: IO.pure(Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, applyAt(Arguments, DiagnosticDetails, Details, Custom, Number.fromU32(0), planned))
    case True{}:
      do IO<Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        timestamp : Number.F64 <- Date.now()
        return applyAt(Arguments, DiagnosticDetails, Details, Custom, timestamp, planned)

def declareToolChanges(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pendingMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    +planned : Declaration.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>> = plan(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, pendingMessages)
    commit(Arguments, DiagnosticDetails, Details, Custom, planned, needsTimestamp(Arguments, DiagnosticDetails, Details, Custom, planned))


def ExecutionOutcome(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> Data:
  Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>

# An execution owns concurrent work independently of result settlement. Tools
# and event sinks remain live through worker draining and update-owner cleanup.
type Execution<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Settled{outcome: ExecutionOutcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}
  Concurrent{run: ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}

type Cancellation<-Signal: Data> is Data:
  Cancellation{signal: Maybe<&2, Signal>, check: C.Callback<Maybe<&2, Signal>, Bool>}

def abortedExecution(-Signal: Data, cancellation: Cancellation<Signal>, unused: Unit) -> IO(Bool):
  match cancellation:
    case Cancellation{signal, check}: C.call(Maybe<&2, Signal>, Bool, check, signal)

def parallelExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, started: Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match started:
    case Fail{error}: Settled{Fail{error}}
    case Done{run}: Concurrent{run}

def selectedExecution(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, prepared: PreparedToolCallBatch<Arguments>) -> IO(Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match capture prepared:
    case CallCapture{_, _, signal, _, isAborted, _, _, _, _} PreparedToolCallBatch{calls, T.Sequential{}}:
      do IO<Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        +invoke : C.Callback<CallInput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)> <- create(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture)
        +cancel : C.Callback<Unit, Bool> <- C.create(~Cancellation<Signal>, ~Unit, ~Bool, ~(abortedExecution(Signal)), Cancellation{signal, isAborted})
        outcome : ExecutionOutcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- executeSequential(T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolCall<Arguments>, Ai.ToolResultMessage<Details>, Error, context, calls, invoke, cancel)
        C.dispose(CallInput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), CallOutput(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), invoke)
        C.dispose(Unit, Bool, cancel)
        return Settled{outcome}
    case _ PreparedToolCallBatch{calls, T.Parallel{}}:
      do IO<Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        started : Result<&2, &2, Error, ParallelRun<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- startParallel(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, calls)
        return parallelExecution(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, started)

# Select once from the assistant's tool calls and original context. A matching
# tool's sequential override applies to the entire batch; missing tools and
# non-tool assistant content do not introduce new scheduling policy.
def executeToolCalls(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: CallCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match capture:
    case CallCapture{assistant, config, _, _, _, _, _, _, _}:
      selectedExecution(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, prepareToolCallBatch(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, config))

# The caller consumes result delivery once, then drains before releasing the
# captured resources. A failed parallel result does not cancel sibling tools.
def resultExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, execution: Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(ExecutionOutcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  match execution:
    case Settled{outcome}: IO.pure(ExecutionOutcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), outcome)
    case Concurrent{run}: resultParallel(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, run)

# This drains batch workers. Retained tool-update scopes remain in Capture.owners;
# retire their aliases and dispose that owner before releasing event resources.
def disposeExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, execution: Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match execution:
    case Settled{_}: IO.pure(Unit, Unit{})
    case Concurrent{run}: disposeParallel(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, run)


# The schema library retains structured failure categories. Applications map
# them into their execution-error type at this boundary, without discarding
# unsupported-schema or normalization failures that have no public formatter.
def ValidationInput() -> Data: ToolValidationInput<Schema.Value, Schema.Value, Schema.Value>
def ValidationOutput(-Error: Data) -> Data: Result<&2, &2, Error, Schema.Value>
def Validator(-Error: Data) -> Data: C.Callback<ValidationInput(), ValidationOutput(Error)>

def validatePlain(input: ValidationInput()) -> Validation.ToolValidation():
  match input:
    case ToolValidationInput{tool, OriginalCall{call}}: Validation.validatePlainToolArguments(tool, call)
    case ToolValidationInput{tool, ReplacedCall{call}}: Validation.validatePlainToolArguments(tool, call)

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


# Successful turn completion returns an immutable snapshot for prepareNextTurnLocal.
# The caller has already recorded the assistant response in both histories.
type NextTurn<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Finished{completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  CompletionContinue{completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pending: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>}

def toolMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, results: List<&2, Ai.ToolResultMessage<Details>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match results:
    case Nil{}: Nil{}
    case message <> rest: T.LlmMessage{Ai.ToolResult{message}} <> toolMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, rest)

def completedTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, newMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, +results: List<&2, Ai.ToolResultMessage<Details>>) -> T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match context:
    case T.AgentContext{messages, tools}:
      +added = toolMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, results)
      T.ShouldStopAfterTurnContext{assistant, results, T.AgentContext{List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, messages, added), tools}, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, newMessages, added)}

def historyCompletion(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, _, messages}: messages

def nonemptyCompletion(-A: Data, values: List<&2, A>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

def endedCompletion(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, emitted: Result<&2, &2, Error, Unit>) -> Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Finished{completed}}

def followed(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, +completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match queued:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{Nil{}}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentEnd{historyCompletion(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)})
        return endedCompletion(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, emitted)
    case Done{head <> tail}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{CompletionContinue{completed, head <> tail}})

def afterSteering(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>>, moreTools: Bool) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match queued moreTools:
    case Fail{error} _: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{None{}} _: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Finished{completed}})
    case Done{Some{pending}} True{}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{CompletionContinue{completed, pending}})
    case Done{Some{head <> tail}} False{}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{CompletionContinue{completed, head <> tail}})
    case Done{Some{Nil{}}} False{}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        followUp : Result<&2, &2, Error, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>> <- pollFollowUpMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config)
        followed(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, sink, followUp)

def afterTurnEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, moreTools: Bool, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        queued : Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>> <- finishCompletedTurn(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, T.AgentToolResult<Details>, T.AgentToolResult<Details>, config, completed, historyCompletion(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed), sink)
        afterSteering(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, completed, sink, queued, moreTools)

# Commit successful tool results to both histories before turn_end and the
# stop hook. Steering is checked after the stop hook; follow-ups are checked
# only when neither continuing tool calls nor steering keeps the inner loop alive.
def completeTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, newMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, batch: Result<&2, &2, Error, Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match batch:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{Batch{context, +results, terminate}}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        +completed : T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = completedTurn(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, assistant, context, newMessages, results)
        moreTools : Bool = nonemptyCompletion(Ai.ToolCall<Arguments>, collectAssistantToolCalls(Arguments, DiagnosticDetails, assistant)) && Bool.not(terminate)
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnEnd{T.LlmMessage{Ai.Assistant{assistant}}, results})
        afterTurnEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, completed, sink, moreTools, emitted)


# Ready for the provider boundary: updated context/config and committed history.
type RequestState<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  RequestState{context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>}

type TurnDeliveryStep<-Message: Data, -Error: Data> is Data:
  TurnNext{}
  TurnStarted{message: Message, emitted: Result<&2, &2, Error, Unit>}
  TurnEnded{message: Message, emitted: Result<&2, &2, Error, Unit>}

# Each TurnNext consumes a declared message. Commit only after both events settle,
# preserving source order and skipping every later event on listener failure.
@unsafe
def deliverTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, state: RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, remaining: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: TurnDeliveryStep<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, Error>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match state:
    case RequestState{context, config, newMessages}:
      match remaining step:
        case Nil{} TurnNext{}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Done{RequestState{context, config, newMessages}})
        case +message <> rest TurnNext{}:
          do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageStart{message})
            deliverTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{context, config, newMessages}, rest, sink, TurnStarted{message, emitted})
        case _ TurnStarted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
        case rest TurnStarted{+message, Done{_}}:
          do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageEnd{message})
            deliverTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{context, config, newMessages}, rest, sink, TurnEnded{message, emitted})
        case _ TurnEnded{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
        case rest TurnEnded{+message, Done{_}}:
          deliverTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{copyContextMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, message <> Nil{}), config, List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, newMessages, message <> Nil{})}, rest, sink, TurnNext{})

def declaredTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, state: RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match outcome:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{declarationError(error)})
    case Declaration.Success{messages}: deliverTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, state, messages, sink, TurnNext{})

def declare(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
    +current : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = context
    outcome : Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- declareToolChanges(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, current, messages)
    declaredTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{current, config, newMessages}, sink, declarationError, outcome)

def startedTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case Done{_}: declare(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, messages, sink, declarationError)

def queuedTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, prepared: PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, pending: Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match prepared pending:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case PreparedTurnState{context, config, messages} Done{steering}:
      do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        startedTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, messages, steering), sink, declarationError, emitted)

def afterPreparation(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Result<&2, &2, Error, PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case Done{PreparedTurnState{context, +config, messages}}:
      do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
        steering : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- repollSteeringMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, pending)
        queuedTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, PreparedTurnState{context, config, messages}, newMessages, sink, declarationError, steering)

# A retained steering item must not consume another one-at-a-time queue item.
# Preparation updates context/model/reasoning before any turn_start event.
def nextTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, completed: T.PrepareNextTurnContext(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
    outcome : Result<&2, &2, Error, PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- prepareNextTurn(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, completed)
    afterPreparation(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, newMessages, pending, sink, declarationError, outcome)

# The initial turn_start belongs to runAgentLoop/runAgentLoopContinue. The first
# inner iteration declares and delivers already-polled steering without a hook
# or another turn_start event.
def initialTurn(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  declare(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, pending, sink, declarationError)


# Batches may fail before sibling work drains. The loop owner retains executions
# until explicit disposal; tool-held update aliases have their separate owner.
def Batches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> Data: R.Ref<List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>

def newBatches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> IO(Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  R.new(List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Nil{})

def disposeExecutions(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, executions: List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> IO(Unit):
  match executions:
    case Nil{}: IO.pure(Unit, Unit{})
    case execution <> rest:
      do IO<Unit>:
        disposeExecution(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, execution)
        disposeExecutions(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, rest)

def disposeBatches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, owner: Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)) -> IO(Unit):
  do IO<Unit>:
    executions : List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- R.dispose(List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, owner)
    disposeExecutions(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, executions)

type Services<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Services{signal: Maybe<&2, Signal>, validate: C.Callback<ToolValidationInput<Schema.Value, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emit: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission<Error>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, updates: Owners(Details, Error), batches: Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), emptyDetails: Details}

type LoopCapture<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  LoopCapture{services: Services<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, streamFunction: T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error)}

type LoopStep<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Initial{pending: Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>}
  LoopPrepared{state: Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>}
  Responded{message: Result<&2, &2, Error, Ai.AssistantMessage<Arguments, DiagnosticDetails>>}
  Recorded{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, recorded: Result<&2, &2, Error, AssistantCompletion<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>}
  LoopExecuted{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, batch: ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}
  LoopCompleted{turn: Result<&2, &2, Error, NextTurn<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>}

def lengthLimited(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}: True{}
    case _: False{}

def truncatedResult(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, outcome: Result<&2, &2, Error, ExecutedToolCallBatch<Details>>) -> ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error):
  match outcome:
    case Fail{error}: Fail{error}
    case Done{ExecutedToolCallBatch{messages, terminate}}: Done{Batch{context, messages, terminate}}

def executeLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: LoopCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, calls: List<&2, Ai.ToolCall<Arguments>>, truncated: Bool) -> IO(ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  match capture calls truncated:
    case _ Nil{} _: IO.pure(ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), Done{Batch{context, Nil{}, False{}}})
    case LoopCapture{Services{_, _, _, _, sink, _, _, emptyDetails}, _} remaining True{}:
      do IO<ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)>:
        outcome : Result<&2, &2, Error, ExecutedToolCallBatch<Details>> <- failToolCallsFromTruncatedMessage(Schema.Value, Arguments, DiagnosticDetails, Custom, T.AgentToolResult<Details>, Error, Details, TruncatedToolCallRun{sink, emptyDetails}, remaining)
        return truncatedResult(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, outcome)
    case LoopCapture{Services{signal, validate, isAborted, emit, sink, updates, +batches, emptyDetails}, _} _ False{}:
      do IO<ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)>:
        +execution : Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- executeToolCalls(~Schema.Value, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, CallCapture{message, config, signal, validate, isAborted, emit, sink, updates, emptyDetails}, context)
        R.modify(List<&2, Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Unit, batches, entries => (execution <> entries, Unit{}))
        resultExecution(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, execution)

def completedContext(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, context, _}: context

# One completed response advances to preparation or finishes. IO may suspend at
# any stage; records and retained event histories stay immutable. Only the live
# response consumer shares the context cell, which is retired on loop return.
@unsafe
def advanceLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, +capture: LoopCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +contextCell: R.Ref<T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, +config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, history: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, step: LoopStep<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture:
    case LoopCapture{Services{+signal, +validate, +isAborted, +emit, +sink, +updates, +batches, +emptyDetails}, +streamFunction}:
      match step:
        case Initial{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Initial{Done{pending}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.read(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
            prepared : Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- initialTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, history, pending, sink, error => declarationError(error))
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopPrepared{prepared})
        case LoopPrepared{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case LoopPrepared{Done{RequestState{context, +nextConfig, newMessages}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            R.write(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell, context)
            response : Result<&2, &2, Error, Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- streamAssistantResponse(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, T.AgentToolResult<Details>, T.AgentToolResult<Details>, AssistantRequest{contextCell, nextConfig, signal, sink, streamFunction})
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, nextConfig, newMessages, Responded{response})
        case Responded{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Responded{Done{+message}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            recorded : Result<&2, &2, Error, AssistantCompletion<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- recordAssistantCompletion(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, history, sink)
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Recorded{message, recorded})
        case Recorded{_, Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Recorded{_, Done{AssistantCompletion{messages, True{}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Done{messages})
        case Recorded{+message, Done{AssistantCompletion{+messages, False{}}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.read(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
            outcome : ExecutionOutcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- executeLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, config, message, collectAssistantToolCalls(Arguments, DiagnosticDetails, message), lengthLimited(Arguments, DiagnosticDetails, message))
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, messages, LoopExecuted{message, outcome})
        case LoopExecuted{message, batch}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            completed : Result<&2, &2, Error, NextTurn<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- completeTurn(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, message, history, config, sink, batch)
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopCompleted{completed})
        case LoopCompleted{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case LoopCompleted{Done{Finished{T.ShouldStopAfterTurnContext{_, _, _, messages}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Done{messages})
        case LoopCompleted{Done{CompletionContinue{+completed, pending}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            +context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = completedContext(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)
            messages : List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>> = historyCompletion(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)
            R.write(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell, context)
            prepared : Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- nextTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, completed, messages, pending, sink, error => declarationError(error))
            advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, LoopPrepared{prepared})

# Internal loop: entry points emit agent_start/first turn_start and prompt events
# before calling this. The supplied stream function is always the real provider
# interface; only its implementation is injectable, as in upstream pi.
def runLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, capture: LoopCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, +config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    +contextCell : R.Ref<T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- R.new(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, context)
    pending : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- pollSteeringMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config)
    outcome : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- advanceLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, newMessages, Initial{pending})
    discarded : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.dispose(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
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
def validateContinuation(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> Maybe<&2, ContinueError>:
  match messages:
    case Nil{}: Some{NoMessages{}}
    case T.LlmMessage{Ai.Assistant{_}} <> Nil{}: Some{AssistantLast{}}
    case _ <> Nil{}: None{}
    case _ <> rest: validateContinuation(Arguments, DiagnosticDetails, Details, Custom, rest)

type EntryCapture<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  EntryCapture{services: Services<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, stream: StreamFn.Selection<Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error>}

def explicit(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, capture: LoopCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>:
  match capture:
    case LoopCapture{services, stream}: EntryCapture{services, StreamFn.Explicit{stream}}

def resolvedEntry(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, services: Services<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, state: RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, stream: Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error)>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match state stream:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{streamError(error)})
    case RequestState{context, config, messages} Done{provider}: runLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, LoopCapture{services, provider}, context, config, messages)

def enter(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, prepared: Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{services, selection} Done{state}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        stream : Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error)> <- StreamFn.resolve(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error, selection)
        resolvedEntry(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, services, state, stream)

def afterTurnStart(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        prepared : Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- deliverTurn(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{context, config, Nil{}}, messages, sink, TurnNext{})
        enter(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, prepared)

def afterAgentStart(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        started : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        afterTurnStart(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, started)

def startEntry(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture:
    case EntryCapture{Services{_, _, _, _, sink, _, _, _}, _}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentStart{})
        afterAgentStart(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, emitted)

def declaredEntry(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match messages:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{declarationError(error)})
    case Declaration.Success{initial}: startEntry(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, initial)

# Reconcile prompt declarations before emitting the initial event prefix.
# Callback/update/batch ownership follows runLoop's explicit lifetime.
def runAgentLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, prompts: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    messages : Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- declareToolChanges(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, prompts)
    declaredEntry(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages)

def continueValidatedEntry(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, error: Maybe<&2, ContinueError>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{entryError(cause)})
    case None{}: startEntry(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, Nil{})

def runAgentLoopContinue(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match context:
    case T.AgentContext{messages, _}: continueValidatedEntry(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, capture, context, config, validateContinuation(Arguments, DiagnosticDetails, Details, Custom, messages))


def Messages(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>
def LoopEvent(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>
def StreamOutcome(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: Result<&2, &2, Error, Messages(Arguments, DiagnosticDetails, Details, Custom)>
def Stream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: Stream.EventStream<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)>

# Provider, validator, cancellation and configuration callbacks are borrowed.
# Keep them alive until disposal has drained the loop and its tool batches.
type Options<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Options{signal: Maybe<&2, Signal>, validate: C.Callback<ToolValidationInput<Schema.Value, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emptyDetails: Details, stream: StreamFn.Selection<Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error>}

type StreamRun<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  StreamRun{stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error), worker: Chan(Unit), emitStream: C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Emission<Error>>, sink: C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>>, updates: Owners(Details, Error), batches: Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}

type Start<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Prompt{messages: Messages(Arguments, DiagnosticDetails, Details, Custom)}
  StreamContinue{}

def extractStream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, unused: Unit, event: LoopEvent(Arguments, DiagnosticDetails, Details, Custom)) -> IO(StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match event:
    case T.AgentEnd{messages}: IO.pure(StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), Done{messages})
    case _: IO.pure(StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), Done{Nil{}})

def createStream(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data) -> IO(Stream(Arguments, DiagnosticDetails, Details, Custom, Error)):
  do IO<Stream(Arguments, DiagnosticDetails, Details, Custom, Error)>:
    check : C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Bool> <- C.create(~Unit, ~LoopEvent(Arguments, DiagnosticDetails, Details, Custom), ~Bool, ~(agentStreamComplete(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>)), Unit{})
    finish : C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)> <- C.create(~Unit, ~LoopEvent(Arguments, DiagnosticDetails, Details, Custom), ~StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), ~(extractStream(Arguments, DiagnosticDetails, Details, Custom, Error)), Unit{})
    Stream.create(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), check, finish)

def emitStream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error), event: LoopEvent(Arguments, DiagnosticDetails, Details, Custom)) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    Stream.push(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream, event)
    return EmissionReady{Done{Unit{}}}

def executeStream(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match start:
    case Prompt{messages}: runAgentLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, messages, context, config, capture)
    case StreamContinue{}: runAgentLoopContinue(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, capture)

# On success agent_end has already settled the result. On failure, end closes
# event iteration and settles a typed error without inventing an agent_end.
def work(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  do IO<Unit>:
    outcome : StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error) <- executeStream(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture)
    Stream.end(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream, Some{outcome})

def launch(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match options:
    case Options{signal, validate, isAborted, emptyDetails, selection}:
      do IO<StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        +stream : Stream(Arguments, DiagnosticDetails, Details, Custom, Error) <- createStream(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error)
        +emitter : C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Emission<Error>> <- C.create(~Stream(Arguments, DiagnosticDetails, Details, Custom, Error), ~LoopEvent(Arguments, DiagnosticDetails, Details, Custom), ~Emission<Error>, ~(emitStream(Arguments, DiagnosticDetails, Details, Custom, Error)), stream)
        +sink : C.Callback<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>> <- createAwaitedEventSink(~Schema.Value, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~T.AgentToolResult<Details>, ~T.AgentToolResult<Details>, ~Error, emitter)
        +updates : Owners(Details, Error) <- newOwners(Details, Error)
        +batches : Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- newBatches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)
        capture : EntryCapture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch> = EntryCapture{Services{signal, validate, isAborted, emitter, sink, updates, batches, emptyDetails}, selection}
        worker : Chan(Unit) <- IO.fork(Unit, work(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture, stream))
        return StreamRun{stream, worker, emitter, sink, updates, batches}

def agentLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, prompts: Messages(Arguments, DiagnosticDetails, Details, Custom), context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  launch(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, Prompt{prompts}, context, config, options)

def continueValidatedStream(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, error: Maybe<&2, ContinueError>) -> IO(Result<&2, &2, Error, StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{entryError(cause)})
    case None{}:
      do IO<Result<&2, &2, Error, StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        run : StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- launch(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, StreamContinue{}, context, config, options)
        return Done{run}

# Invalid continuation is rejected before allocating a stream or starting work.
def agentLoopContinue(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match context:
    case T.AgentContext{messages, _}: continueValidatedStream(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, options, validateContinuation(Arguments, DiagnosticDetails, Details, Custom, messages))

def resultStream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match run:
    case StreamRun{stream, _, _, _, _, _}: Stream.resultValue(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)

def iterator(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Stream.Iterator<LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error)>):
  match run:
    case StreamRun{stream, _, _, _, _, _}: Stream.iterator(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)

# Single-owner disposal: retire iterators/result observers and retained tool
# update aliases first. Failed results may settle while sibling tools still run.
def disposeStream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, +stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  match stream:
    case Stream.EventStream{_, _, check, finish}:
      do IO<Unit>:
        Stream.dispose(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)
        C.dispose(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Bool, check)
        C.dispose(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), StreamOutcome(Arguments, DiagnosticDetails, Details, Custom, Error), finish)

def disposeStreamRun(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: StreamRun<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match run:
    case StreamRun{stream, worker, emitter, sink, updates, batches}:
      do IO<Unit>:
        joined : Unit <- IO.join(Unit, worker)
        disposeBatches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, batches)
        disposeOwners(Details, Error, updates)
        C.dispose(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>, sink)
        C.dispose(LoopEvent(Arguments, DiagnosticDetails, Details, Custom), Emission<Error>, emitter)
        disposeStream(Arguments, DiagnosticDetails, Details, Custom, Error, stream)
