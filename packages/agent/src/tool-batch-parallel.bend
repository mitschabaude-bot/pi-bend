import Base
import ./tool-call.bend as Call
import ./tool-batch.bend as Batch
import ./agent-loop.bend as Loop
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/concurrent-all.bend as All

# Preparation is sequential. Immediate outcomes emit their execution-end here;
# prepared entries are inert until the entire preparation pass has finished.
type Entry<-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Immediate{finalized: Loop.FinalizedToolCallOutcome<Arguments, Details>}
  Prepared{prepared: Loop.PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>}

type Plan<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Plan{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entries: List<&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>>}

type PreparationStep<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Next{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  Started{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>, emitted: Result<&2, &2, Error, Unit>}
  Checked{call: Ai.ToolCall<Arguments>, preparation: Loop.ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  Ended{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>, emitted: Result<&2, &2, Error, Unit>}
  Stopped{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>, aborted: Bool}

# Each Next consumes a call. Other stages settle preparation or terminate it.
@unsafe
def prepare(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, calls: List<&2, Ai.ToolCall<Arguments>>, reversed: List<&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>>, step: PreparationStep<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match capture:
    case Call.Capture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match calls step:
        case Nil{} Next{context}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Plan{context, List.reverse(&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>, reversed)}})
        case +call <> rest Next{context}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, Call.startEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, call))
            prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, rest, reversed, Started{context, call, emitted})
        case _ Started{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
        case remaining Started{context, +call, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            prepared : Loop.ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- Loop.prepareToolCallWith(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Signal>, Bool, isAborted, value), failureDetails, error => renderError(error))
            prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Checked{call, prepared})
        case remaining Checked{call, Loop.ToolPreparationState{context, Loop.Immediate{Loop.ImmediateToolCallOutcome{valueResult, isError}}}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            +finalized : Loop.FinalizedToolCallOutcome<Arguments, Details> = Loop.FinalizedToolCallOutcome{call, valueResult, isError}
            emitted : Result<&2, &2, Error, Unit> <- Loop.emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Ended{context, Immediate{finalized}, emitted})
        case remaining Checked{_, Loop.ToolPreparationState{context, Loop.Prepared{prepared}}}:
          prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Ended{context, Prepared{prepared}, Done{Unit{}}})
        case _ Ended{_, _, Fail{error}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
        case remaining Ended{context, entry, Done{_}}:
          do IO<Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
            stopped : Bool <- C.call(Maybe<&2, Signal>, Bool, isAborted, signal)
            prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, reversed, Stopped{context, entry, stopped})
        case _ Stopped{context, entry, True{}}: IO.pure(Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Plan{context, List.reverse(&2, Entry<Parameters, Arguments, Details, Validated, Signal, Error>, entry <> reversed)}})
        case remaining Stopped{context, entry, False{}}:
          prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, remaining, entry <> reversed, Next{context})

# Every deferred call observes the final preparation context. This explicitly
# carries before-hook context updates without sharing a mutable message object.
type ExecutionCapture<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  ExecutionCapture{capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}

type ExecutionStep<-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Begin{entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>}
  Aborted{prepared: Loop.PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, stopped: Bool}
  Executed{prepared: Loop.PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, outcome: Result<&2, &2, Error, Loop.ExecutedToolCallOutcome<Details>>}
  Finalized{finalized: Loop.FinalizedToolCallOutcome<Arguments, Details>}
  Emitted{finalized: Loop.FinalizedToolCallOutcome<Arguments, Details>, emitted: Result<&2, &2, Error, Unit>}

# Each transition advances one deferred call. Immediate entries already emitted
# end during preparation and must not emit it again or invoke the after hook.
@unsafe
def execute(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +environment: ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, step: ExecutionStep<Parameters, Arguments, Details, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>):
  match environment:
    case ExecutionCapture{Call.Capture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}, +context}:
      match step:
        case Begin{Immediate{finalized}}: IO.pure(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, Done{finalized})
        case Begin{Prepared{prepared}}:
          do IO<Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>>:
            stopped : Bool <- C.call(Maybe<&2, Signal>, Bool, isAborted, signal)
            execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Aborted{prepared, stopped})
        case Aborted{prepared, True{}}:
          execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Finalized{Loop.FinalizedToolCallOutcome{Call.preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Operation aborted", None{}}} <> Nil{}, failureDetails, None{}, None{}}, True{}}})
        case Aborted{+prepared, False{}}:
          do IO<Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>>:
            +updates : Loop.ToolUpdateRun<Details, Error> <- Loop.createToolUpdateRun(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error, Call.preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), emit)
            Call.retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, Loop.ExecutedToolCallOutcome<Details>> <- Loop.executePreparedToolCall(Parameters, Validated, Details, Arguments, Signal, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Executed{prepared, outcome})
        case Executed{_, Fail{error}}: IO.pure(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, Fail{error})
        case Executed{prepared, Done{outcome}}:
          do IO<Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>>:
            finalized : Loop.FinalizedToolCallOutcome<Arguments, Details> <- Loop.finalizeExecutedToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Finalized{finalized})
        case Finalized{+finalized}:
          do IO<Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>>:
            emitted : Result<&2, &2, Error, Unit> <- Loop.emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, Error, finalized, sink)
            execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Emitted{finalized, emitted})
        case Emitted{_, Fail{error}}: IO.pure(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, Fail{error})
        case Emitted{finalized, Done{_}}: IO.pure(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, Done{finalized})

def invoke(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, environment: ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, entry: Entry<Parameters, Arguments, Details, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>):
  execute(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, environment, Begin{entry})

# Keep worker captures alive after a prompt failure. dispose drains all workers
# before retiring the execution callback; the caller still owns sink/update aliases.
type Run<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Run{context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, collection: All.Run<Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, worker: C.Callback<Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>}

def beginPrepared(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, prepared: Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> IO(Result<&2, &2, Error, Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Call.Capture{_, _, _, _, _, _, sink, _, _} Done{Plan{+context, entries}}:
      do IO<Result<&2, &2, Error, Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        +worker : C.Callback<Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>> <- C.create(~ExecutionCapture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, ~Entry<Parameters, Arguments, Details, Validated, Signal, Error>, ~Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, ~(invoke(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError)), ExecutionCapture{capture, context})
        collection : All.Run<Error, Loop.FinalizedToolCallOutcome<Arguments, Details>> <- All.start(Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>, entries, worker)
        return Done{Run{context, collection, worker, sink}}

def start(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, calls: List<&2, Ai.ToolCall<Arguments>>) -> IO(Result<&2, &2, Error, Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  do IO<Result<&2, &2, Error, Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
    prepared : Result<&2, &2, Error, Plan<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- prepare(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, calls, Nil{}, Next{context})
    beginPrepared(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, prepared)

type DeliveryStep<-Details: Data, -Error: Data> is Data:
  Ready{}
  Delivered{message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

# Successful execution-end events all precede ordered message delivery. A
# message listener failure stops delivery immediately; no later message starts.
@unsafe
def deliver(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, remaining: List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>, reversed: List<&2, Ai.ToolResultMessage<Details>>, terminate: Bool, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: DeliveryStep<Details, Error>) -> IO(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match remaining step:
    case Nil{} Ready{}: IO.pure(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Done{Batch.Batch{context, List.reverse(&2, Ai.ToolResultMessage<Details>, reversed), terminate}})
    case finalized <> rest Ready{}:
      do IO<Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>>:
        +message : Ai.ToolResultMessage<Details> <- Loop.createToolResultMessage(Arguments, Details, finalized)
        emitted : Result<&2, &2, Error, Unit> <- Loop.emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, sink)
        deliver(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, rest, reversed, terminate, sink, Delivered{message, emitted})
    case _ Delivered{_, Fail{error}}: IO.pure(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case rest Delivered{message, Done{_}}: deliver(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, rest, message <> reversed, terminate, sink, Ready{})

def collected(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, valueResult: Result<&2, &2, Error, List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>>) -> IO(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match valueResult:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>, Fail{error})
    case Done{+finalized}: deliver(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, finalized, Nil{}, Loop.shouldTerminateToolBatch(Arguments, Details, finalized), sink, Ready{})

# One consumer owns result-message delivery. On failure this may return while
# sibling execution is still running; dispose is the separate lifetime boundary.
def result(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>):
  match run:
    case Run{context, collection, _, sink}:
      do IO<Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>>:
        finalized : Result<&2, &2, Error, List<&2, Loop.FinalizedToolCallOutcome<Arguments, Details>>> <- All.result(Error, Loop.FinalizedToolCallOutcome<Arguments, Details>, collection)
        collected(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, sink, finalized)

def dispose(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match run:
    case Run{_, collection, worker, _}:
      do IO<Unit>:
        All.dispose(Error, Loop.FinalizedToolCallOutcome<Arguments, Details>, collection)
        C.dispose(Entry<Parameters, Arguments, Details, Validated, Signal, Error>, Result<&2, &2, Error, Loop.FinalizedToolCallOutcome<Arguments, Details>>, worker)
