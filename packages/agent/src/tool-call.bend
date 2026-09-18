import Base
import ./agent-loop.bend as Loop
import ./tool-batch.bend as Batch
import ./types.bend as Types
import ./event-emission.bend as Emission
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R

# Retain update tombstones beyond execution. The owner releases this collection
# only after tool-held callback aliases have retired, including on delivery failure.
def Owners(-Details: Data, -Error: Data) -> Data: R.Ref<List<&2, Loop.ToolUpdateRun<Details, Error>>>

def newOwners(-Details: Data, -Error: Data) -> IO(Owners(Details, Error)):
  R.new(List<&2, Loop.ToolUpdateRun<Details, Error>>, Nil{})

def retain(-Details: Data, -Error: Data, owner: Owners(Details, Error), run: Loop.ToolUpdateRun<Details, Error>) -> IO(Unit):
  R.modify(List<&2, Loop.ToolUpdateRun<Details, Error>>, Unit, owner, runs => (run <> runs, Unit{}))

def disposeRuns(-Details: Data, -Error: Data, runs: List<&2, Loop.ToolUpdateRun<Details, Error>>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case run <> rest:
      do IO<Unit>:
        Loop.disposeToolUpdateRun(Details, Error, run)
        disposeRuns(Details, Error, rest)

def disposeOwners(-Details: Data, -Error: Data, owner: Owners(Details, Error)) -> IO(Unit):
  do IO<Unit>:
    runs : List<&2, Loop.ToolUpdateRun<Details, Error>> <- R.dispose(List<&2, Loop.ToolUpdateRun<Details, Error>>, owner)
    disposeRuns(Details, Error, runs)

type Capture<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Capture{assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, config: Types.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, signal: Maybe<&2, Signal>, validate: C.Callback<Loop.ToolValidationInput<Parameters, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emit: C.Callback<Types.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Types.AgentToolResult<Details>>, Emission.Emission<Error>>, sink: C.Callback<Types.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Types.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, owners: Owners(Details, Error), failureDetails: Details}

def Input(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data) -> Data: Batch.Invocation<Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolCall<Arguments>>
def Output(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data) -> Data: Result<&2, &2, Error, Batch.Completed<Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>

type Step<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Begin{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>}
  Started{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, call: Ai.ToolCall<Arguments>, emitted: Result<&2, &2, Error, Unit>}
  Prepared{call: Ai.ToolCall<Arguments>, prepared: Loop.ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  Executed{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, prepared: Loop.PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>, outcome: Result<&2, &2, Error, Loop.ExecutedToolCallOutcome<Details>>}
  Finalized{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, finalized: Loop.FinalizedToolCallOutcome<Arguments, Details>}
  Ended{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, finalized: Loop.FinalizedToolCallOutcome<Arguments, Details>, emitted: Result<&2, &2, Error, Unit>}
  Delivered{context: Types.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, terminate: Bool, message: Ai.ToolResultMessage<Details>, emitted: Result<&2, &2, Error, Unit>}

def preparedCall(-Parameters: Data, -Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data, prepared: Loop.PreparedToolCall<Parameters, Validated, Details, Arguments, Signal, Error>) -> Ai.ToolCall<Arguments>:
  match prepared:
    case Loop.PreparedToolCall{call, _, _}: call

def startEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, call: Ai.ToolCall<Arguments>) -> Types.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Types.AgentToolResult<Details>>:
  match call:
    case Ai.ToolCall{id, name, arguments, _, _}: Types.ToolExecutionStart{id, name, arguments}

# Each stage advances one call's lifecycle. The error renderer is lifted code;
# all changing state and effect resources are explicit capture/input values.
@unsafe
def advance(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, step: Step<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)):
  match capture:
    case Capture{+assistant, +config, +signal, +validate, +isAborted, +emit, +sink, +owners, +failureDetails}:
      match step:
        case Begin{context, +call}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(Types.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Types.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, startEvent(Parameters, Arguments, DiagnosticDetails, Details, Custom, call))
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Started{context, call, emitted})
        case Started{_, _, Fail{error}}: IO.pure(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case Started{context, +call, Done{_}}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            prepared : Loop.ToolPreparationState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- Loop.prepareToolCallWith(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, call, config, signal, validate, value => C.call(Maybe<&2, Signal>, Bool, isAborted, value), failureDetails, error => renderError(error))
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Prepared{call, prepared})
        case Prepared{call, Loop.ToolPreparationState{context, Loop.Immediate{Loop.ImmediateToolCallOutcome{result, isError}}}}:
          advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Finalized{context, Loop.FinalizedToolCallOutcome{call, result, isError}})
        case Prepared{_, Loop.ToolPreparationState{context, Loop.Prepared{+prepared}}}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            +updates : Loop.ToolUpdateRun<Details, Error> <- Loop.createToolUpdateRun(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error, preparedCall(Parameters, Arguments, Details, Validated, Signal, Error, prepared), emit)
            retain(Details, Error, owners, updates)
            outcome : Result<&2, &2, Error, Loop.ExecutedToolCallOutcome<Details>> <- Loop.executePreparedToolCall(Parameters, Validated, Details, Arguments, Signal, Error, prepared, signal, updates, failureDetails, error => renderError(error))
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Executed{context, prepared, outcome})
        case Executed{_, _, Fail{error}}: IO.pure(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case Executed{+context, prepared, Done{outcome}}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            finalized : Loop.FinalizedToolCallOutcome<Arguments, Details> <- Loop.finalizeExecutedToolCall(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, prepared, outcome, config, signal, failureDetails, error => renderError(error))
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Finalized{context, finalized})
        case Finalized{context, +finalized}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            emitted : Result<&2, &2, Error, Unit> <- Loop.emitToolExecutionEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Error, finalized, sink)
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Ended{context, finalized, emitted})
        case Ended{_, _, Fail{error}}: IO.pure(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case Ended{context, +finalized, Done{_}}:
          do IO<Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>:
            terminate : Bool = Loop.shouldTerminateToolBatch(Arguments, Details, finalized <> Nil{})
            +message : Ai.ToolResultMessage<Details> <- Loop.createToolResultMessage(Arguments, Details, finalized)
            emitted : Result<&2, &2, Error, Unit> <- Loop.emitToolResultMessage(Parameters, Arguments, DiagnosticDetails, Details, Custom, Types.AgentToolResult<Details>, Types.AgentToolResult<Details>, Error, message, sink)
            advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Delivered{context, terminate, message, emitted})
        case Delivered{_, _, _, Fail{error}}: IO.pure(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Fail{error})
        case Delivered{context, terminate, message, Done{_}}:
          IO.pure(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Done{Batch.Completed{context, message, terminate}})

def invoke(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, input: Input(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)) -> IO(Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)):
  match input:
    case Batch.Invocation{context, call}: advance(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, Begin{context, call})

def create(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, capture: Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(C.Callback<Input(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)>):
  C.create(~Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, ~Input(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), ~Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), ~(invoke(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError)), capture)
