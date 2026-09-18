import Base
import ./agent-loop.bend as Loop
import ./tool-call.bend as Call
import ./tool-batch.bend as Batch
import ./tool-batch-parallel.bend as Parallel
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C

def Outcome(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data) -> Data:
  Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>

# An execution owns concurrent work independently of result settlement. Tools
# and event sinks remain live through worker draining and update-owner cleanup.
type Execution<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Settled{outcome: Outcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}
  Concurrent{run: Parallel.Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}

type Cancellation<-Signal: Data> is Data:
  Cancellation{signal: Maybe<&2, Signal>, check: C.Callback<Maybe<&2, Signal>, Bool>}

def aborted(-Signal: Data, cancellation: Cancellation<Signal>, unused: Unit) -> IO(Bool):
  match cancellation:
    case Cancellation{signal, check}: C.call(Maybe<&2, Signal>, Bool, check, signal)

def parallelExecution(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, started: Result<&2, &2, Error, Parallel.Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>) -> Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match started:
    case Fail{error}: Settled{Fail{error}}
    case Done{run}: Concurrent{run}

def selected(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, prepared: Loop.PreparedToolCallBatch<Arguments>) -> IO(Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match capture prepared:
    case Call.Capture{_, _, signal, _, isAborted, _, _, _, _} Loop.PreparedToolCallBatch{calls, T.Sequential{}}:
      do IO<Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        +invoke : C.Callback<Call.Input(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Call.Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch)> <- Call.create(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture)
        +cancel : C.Callback<Unit, Bool> <- C.create(~Cancellation<Signal>, ~Unit, ~Bool, ~(aborted(Signal)), Cancellation{signal, isAborted})
        outcome : Outcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- Batch.executeSequential(T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolCall<Arguments>, Ai.ToolResultMessage<Details>, Error, context, calls, invoke, cancel)
        C.dispose(Call.Input(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), Call.Output(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch), invoke)
        C.dispose(Unit, Bool, cancel)
        return Settled{outcome}
    case _ Loop.PreparedToolCallBatch{calls, T.Parallel{}}:
      do IO<Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        started : Result<&2, &2, Error, Parallel.Run<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>> <- Parallel.start(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, calls)
        return parallelExecution(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, started)

# Select once from the assistant's tool calls and original context. A matching
# tool's sequential override applies to the entire batch; missing tools and
# non-tool assistant content do not introduce new scheduling policy.
def executeToolCalls(~Parameters: Data, ~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, +capture: Call.Capture<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match capture:
    case Call.Capture{assistant, config, _, _, _, _, _, _, _}:
      selected(~Parameters, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, capture, context, Loop.prepareToolCallBatch(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, assistant, config))

# The caller consumes result delivery once, then drains before releasing the
# captured resources. A failed parallel result does not cancel sibling tools.
def result(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, execution: Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Outcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)):
  match execution:
    case Settled{outcome}: IO.pure(Outcome(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), outcome)
    case Concurrent{run}: Parallel.result(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, run)

# This drains batch workers. Retained tool-update scopes remain in Capture.owners;
# retire their aliases and dispose that owner before releasing event resources.
def dispose(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, execution: Execution<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match execution:
    case Settled{_}: IO.pure(Unit, Unit{})
    case Concurrent{run}: Parallel.dispose(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, run)
