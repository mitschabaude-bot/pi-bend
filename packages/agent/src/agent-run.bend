import Base
import ./types.bend as T
import ./agent-runtime.bend as RuntimeState
import ./agent-lifecycle.bend as Life
import ./agent-continuation.bend as Plan
import ./agent-listeners.bend as Listeners
import ./agent-events.bend as Events
import ./agent-failure.bend as Failure
import ./agent-loop-config.bend as Binding
import ./agent-loop.bend as Loop
import ./loop-entry.bend as Entry
import ./main-loop.bend as Main
import ./tool-call.bend as Call
import ./stream-fn.bend as Provider
import ./event-emission.bend as Emission
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C

def Signal() -> Data: Abort.AbortSignal<Unit>
def Message(-A: Data, -G: Data, -D: Data, -M: Data) -> Data: T.AgentMessage<Schema.Value, A, G, D, M>
def Event(-A: Data, -G: Data, -D: Data, -M: Data) -> Data: T.AgentEvent<Schema.Value, A, G, D, M, T.AgentToolResult<D>, T.AgentToolResult<D>>
def Runtime(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: RuntimeState.Runtime<Schema.Value, A, G, D, M, V, Signal(), E, J>
def Registry(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: Listeners.Listeners<Event(A, G, D, M), Signal(), E>
def Config(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data) -> Data: T.AgentLoopConfig<Schema.Value, A, G, D, M, V, Signal(), E, J, Telemetry, Fetch>
def Pollers(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: Binding.Pollers<Schema.Value, A, G, D, M, V, Signal(), E, J>
def Outcome(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: Result<&2, &2, E, List<&2, Message(A, G, D, M)>>
type Options<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Options{config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), provider: Provider.Selection<Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D}
# A completed run can still own tool-held callback aliases or sibling work.
# Retain these resources until aliases retire; dispose drains batches first.
type Resources<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Resources{pollers: Pollers(A, G, D, M, V, E, J), emit: C.Callback<Event(A, G, D, M), Emission.Emission<E>>, sink: C.Callback<Event(A, G, D, M), Result<&2, &2, E, Unit>>, isAborted: C.Callback<Maybe<&2, Signal()>, Bool>, updates: Call.Owners(D, E), batches: Main.Batches(A, G, D, M, V, Signal(), E)}
type Completed<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Completed{outcome: Result<&2, &2, Events.DeliveryError<E>, Unit>, resources: Resources<A, G, D, M, V, E, J>}
type Capture<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Capture{runtime: Runtime(A, G, D, M, V, E, J), listeners: Registry(A, G, D, M, E)}

def missing(-E: Data, fromString: String -> E, error: Provider.MissingDefault) -> E: fromString(Provider.errorMessage(error))
def invalidEntry(-E: Data, fromString: String -> E, error: Entry.ContinueError) -> E: fromString(Entry.errorMessage(error))
def mapped(-E: Data, fromString: String -> E, outcome: Result<&2, &2, Events.DeliveryError<E>, Unit>) -> Result<&2, &2, E, Unit>:
  match outcome:
    case Done{value}: Done{value}
    case Fail{Events.ListenerFailed{error}}: Fail{error}
    case Fail{Events.OutsideRun{message}}: Fail{fromString(message)}
def finishEmission(-E: Data, fromString: String -> E, delivery: Emission.Emission<Events.DeliveryError<E>>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    outcome : Result<&2, &2, Events.DeliveryError<E>, Unit> <- Emission.wait(Events.DeliveryError<E>, delivery)
    return mapped(E, fromString, outcome)
def emitBody(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, fromString: String -> E, capture: Capture<A, G, D, M, V, E, J>, event: Event(A, G, D, M)) -> IO(Emission.Emission<E>):
  match capture:
    case Capture{runtime, listeners}:
      do IO<Emission.Emission<E>>:
        delivery : Emission.Emission<Events.DeliveryError<E>> <- Events.startEvents(Schema.Value, A, G, D, M, V, Signal(), E, J, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, event)
        Emission.start(E, finishEmission(E, fromString, delivery))
def isAborted(unused: Unit, signal: Maybe<&2, Signal()>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)
def skipInitial(-A: Data, -G: Data, -D: Data, -M: Data, plan: Plan.Plan<Message(A, G, D, M)>) -> Bool:
  match plan:
    case Plan.Prompt{_, skip}: skip
    case Plan.Continue{}: False{}
def allocate(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~fromString: String -> E, +runtime: Runtime(A, G, D, M, V, E, J), listeners: Registry(A, G, D, M, E), skip: Bool) -> IO(Resources<A, G, D, M, V, E, J>):
  do IO<Resources<A, G, D, M, V, E, J>>:
    pollers : Pollers(A, G, D, M, V, E, J) <- Binding.new(~Schema.Value, ~A, ~G, ~D, ~M, ~V, ~Signal(), ~E, ~J, runtime, skip)
    +emit : C.Callback<Event(A, G, D, M), Emission.Emission<E>> <- C.create(~Capture<A, G, D, M, V, E, J>, ~Event(A, G, D, M), ~Emission.Emission<E>, ~(emitBody(A, G, D, M, V, E, J, fromString)), Capture{runtime, listeners})
    sink : C.Callback<Event(A, G, D, M), Result<&2, &2, E, Unit>> <- Loop.createAwaitedEventSink(~Schema.Value, ~A, ~G, ~D, ~M, ~T.AgentToolResult<D>, ~T.AgentToolResult<D>, ~E, emit)
    cancelled : C.Callback<Maybe<&2, Signal()>, Bool> <- C.create(~Unit, ~Maybe<&2, Signal()>, ~Bool, ~isAborted, Unit{})
    updates : Call.Owners(D, E) <- Call.newOwners(D, E)
    batches : Main.Batches(A, G, D, M, V, Signal(), E) <- Main.newBatches(A, G, D, M, V, Signal(), E)
    return Resources{pollers, emit, sink, cancelled, updates, batches}
def executePlan(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, plan: Plan.Plan<Message(A, G, D, M)>, snapshot: Binding.Snapshot<Schema.Value, A, G, D, M, V, Signal(), E, J, Telemetry, Fetch>, capture: Entry.Capture<A, G, D, M, V, Signal(), E, J, Telemetry, Fetch>) -> IO(Outcome(A, G, D, M, E)):
  match plan snapshot:
    case Plan.Prompt{messages, _} Binding.Snapshot{context, config}: Entry.runAgentLoop(~A, ~G, ~D, ~M, ~V, ~Signal(), ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~(missing(E, fromString)), messages, context, config, capture)
    case Plan.Continue{} Binding.Snapshot{context, config}: Entry.runAgentLoopContinue(~A, ~G, ~D, ~M, ~V, ~Signal(), ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~(missing(E, fromString)), ~(invalidEntry(E, fromString)), context, config, capture)
def execute(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, runtime: Runtime(A, G, D, M, V, E, J), options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, resources: Resources<A, G, D, M, V, E, J>, claimed: Life.Claimed<Plan.Plan<Message(A, G, D, M)>>) -> IO(Outcome(A, G, D, M, E)):
  match options resources claimed:
    case Options{base, provider, validate, emptyDetails} Resources{pollers, emit, sink, cancelled, updates, batches} Life.Claimed{run, plan}:
      do IO<Outcome(A, G, D, M, E)>:
        snapshot : Binding.Snapshot<Schema.Value, A, G, D, M, V, Signal(), E, J, Telemetry, Fetch> <- Binding.snapshot(Schema.Value, A, G, D, M, V, Signal(), E, J, Telemetry, Fetch, runtime, base, pollers)
        executePlan(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, plan, snapshot, Entry.Capture{Main.Services{Some{Life.signal(run)}, validate, cancelled, emit, sink, updates, batches, emptyDetails}, provider})
def finishedLoop(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data, outcome: Outcome(A, G, D, M, E)) -> Result<&2, &2, E, Unit>:
  match outcome:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{error}
# Run claims and queue planning happen atomically in agent-runtime. This bridge
# executes that plan through the real loop, recovers, then always marks idle.
# The caller retains Completed.resources until explicit disposal is safe.
def runClaimed(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +runtime: Runtime(A, G, D, M, V, E, J), +listeners: Registry(A, G, D, M, E), options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, claimed: Life.Claimed<Plan.Plan<Message(A, G, D, M)>>) -> IO(Completed<A, G, D, M, V, E, J>):
  match claimed:
    case Life.Claimed{+run, +plan}:
      do IO<Completed<A, G, D, M, V, E, J>>:
        +resources : Resources<A, G, D, M, V, E, J> <- allocate(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~fromString, runtime, listeners, skipInitial(A, G, D, M, plan))
        result : Outcome(A, G, D, M, E) <- execute(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, runtime, options, resources, Life.Claimed{run, plan})
        outcome : Result<&2, &2, Events.DeliveryError<E>, Unit> <- Failure.recover(Schema.Value, A, G, D, M, V, Signal(), E, J, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, run, finishedLoop(A, G, D, M, E, result), renderError)
        finished : Bool <- RuntimeState.finishRun(Schema.Value, A, G, D, M, V, Signal(), E, J, runtime, run)
        return Completed{outcome, resources}
def dispose(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, resources: Resources<A, G, D, M, V, E, J>) -> IO(Unit):
  match resources:
    case Resources{pollers, emit, sink, cancelled, updates, batches}:
      do IO<Unit>:
        Main.disposeBatches(A, G, D, M, V, Signal(), E, batches)
        Call.disposeOwners(D, E, updates)
        C.dispose(Event(A, G, D, M), Result<&2, &2, E, Unit>, sink)
        C.dispose(Event(A, G, D, M), Emission.Emission<E>, emit)
        C.dispose(Maybe<&2, Signal()>, Bool, cancelled)
        Binding.dispose(Schema.Value, A, G, D, M, V, Signal(), E, J, pollers)
