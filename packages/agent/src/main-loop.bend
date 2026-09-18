import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ./tool-call.bend as Call
import ./tool-batch.bend as Batch
import ./tool-execution.bend as Execution
import ./turn-preparation.bend as Preparation
import ./turn-completion.bend as Completion
import ./event-emission.bend as Emission
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R

# Batches may fail before sibling work drains. The loop owner retains executions
# until explicit disposal; tool-held update aliases have their separate owner.
def Batches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> Data: R.Ref<List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>

def newBatches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> IO(Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  R.new(List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Nil{})

def disposeExecutions(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, executions: List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> IO(Unit):
  match executions:
    case Nil{}: IO.pure(Unit, Unit{})
    case execution <> rest:
      do IO<Unit>:
        Execution.dispose(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, execution)
        disposeExecutions(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, rest)

def disposeBatches(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, owner: Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)) -> IO(Unit):
  do IO<Unit>:
    executions : List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- R.dispose(List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, owner)
    disposeExecutions(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, executions)

type Capture<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Capture{signal: Maybe<&2, Signal>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emit: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Emission.Emission<Error>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, updates: Call.Owners(Details, Error), batches: Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), emptyDetails: Details, streamFunction: T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>)}

type Step<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Initial{pending: Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>}
  Prepared{state: Result<&2, &2, Error, Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>}
  Responded{message: Result<&2, &2, Error, Ai.AssistantMessage<Arguments, DiagnosticDetails>>}
  Recorded{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, recorded: Result<&2, &2, Error, Loop.AssistantCompletion<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>}
  Executed{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, batch: Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}
  Completed{turn: Result<&2, &2, Error, Completion.NextTurn<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>}

def lengthLimited(-Arguments: Data, -DiagnosticDetails: Data, message: Ai.AssistantMessage<Arguments, DiagnosticDetails>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}: True{}
    case _: False{}

def truncatedResult(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, outcome: Result<&2, &2, Error, Loop.ExecutedToolCallBatch<Details>>) -> Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error):
  match outcome:
    case Fail{error}: Fail{error}
    case Done{Loop.ExecutedToolCallBatch{messages, terminate}}: Done{Batch.Batch{context, messages, terminate}}

def execute(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, calls: List<&2, Ai.ToolCall<Arguments>>, truncated: Bool) -> IO(Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  match capture calls truncated:
    case _ Nil{} _: IO.pure(Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), Done{Batch.Batch{context, Nil{}, False{}}})
    case Capture{_, _, _, _, sink, _, _, emptyDetails, _} remaining True{}:
      do IO<Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)>:
        outcome : Result<&2, &2, Error, Loop.ExecutedToolCallBatch<Details>> <- Loop.failToolCallsFromTruncatedMessage(Schema.Value, Arguments, DiagnosticDetails, Custom, T.AgentToolResult<Details>, Error, Details, Loop.TruncatedToolCallRun{sink, emptyDetails}, remaining)
        return truncatedResult(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, outcome)
    case Capture{signal, validate, isAborted, emit, sink, updates, +batches, emptyDetails, _} _ False{}:
      do IO<Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)>:
        +execution : Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- Execution.executeToolCalls(~Schema.Value, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, Call.Capture{message, config, signal, validate, isAborted, emit, sink, updates, emptyDetails}, context)
        R.modify(List<&2, Execution.Execution<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Unit, batches, entries => (execution <> entries, Unit{}))
        Execution.result(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, execution)

def completedContext(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, context, _}: context

# One completed response advances to preparation or finishes. IO may suspend at
# any stage; records and retained event histories stay immutable. Only the live
# response consumer shares the context cell, which is retired on loop return.
@unsafe
def advance(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, +capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +contextCell: R.Ref<T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, +config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, history: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, step: Step<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture:
    case Capture{+signal, +validate, +isAborted, +emit, +sink, +updates, +batches, +emptyDetails, +streamFunction}:
      match step:
        case Initial{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Initial{Done{pending}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.read(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
            prepared : Result<&2, &2, Error, Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- Preparation.initial(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, history, pending, sink, error => declarationError(error))
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Prepared{prepared})
        case Prepared{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Prepared{Done{Preparation.RequestState{context, +nextConfig, newMessages}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            R.write(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell, context)
            response : Result<&2, &2, Error, Ai.AssistantMessage<Arguments, DiagnosticDetails>> <- Loop.streamAssistantResponse(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Loop.AssistantRequest{contextCell, nextConfig, signal, sink, streamFunction})
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, nextConfig, newMessages, Responded{response})
        case Responded{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Responded{Done{+message}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            recorded : Result<&2, &2, Error, Loop.AssistantCompletion<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- Loop.recordAssistantCompletion(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>, Error, message, history, sink)
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Recorded{message, recorded})
        case Recorded{_, Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Recorded{_, Done{Loop.AssistantCompletion{messages, True{}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Done{messages})
        case Recorded{+message, Done{Loop.AssistantCompletion{+messages, False{}}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.read(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
            outcome : Execution.Outcome(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- execute(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, config, message, Loop.collectAssistantToolCalls(Arguments, DiagnosticDetails, message), lengthLimited(Arguments, DiagnosticDetails, message))
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, messages, Executed{message, outcome})
        case Executed{message, batch}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            completed : Result<&2, &2, Error, Completion.NextTurn<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- Completion.complete(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, message, history, config, sink, batch)
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Completed{completed})
        case Completed{Fail{error}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
        case Completed{Done{Completion.Finished{T.ShouldStopAfterTurnContext{_, _, _, messages}}}}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Done{messages})
        case Completed{Done{Completion.Continue{+completed, pending}}}:
          do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
            +context : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = completedContext(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)
            messages : List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>> = Completion.history(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)
            R.write(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell, context)
            prepared : Result<&2, &2, Error, Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- Preparation.next(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, completed, messages, pending, sink, error => declarationError(error))
            advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, Nil{}, Prepared{prepared})

# Internal loop: entry points emit agent_start/first turn_start and prompt events
# before calling this. The supplied stream function is always the real provider
# interface; only its implementation is injectable, as in upstream pi.
def runLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, +config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    +contextCell : R.Ref<T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- R.new(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, context)
    pending : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- Loop.pollSteeringMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config)
    outcome : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- advance(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, capture, contextCell, config, newMessages, Initial{pending})
    discarded : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- R.dispose(T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, contextCell)
    return outcome
