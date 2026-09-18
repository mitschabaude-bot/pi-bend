import Base
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../ai/src/types.bend as Ai
import ./types.bend as T
import ./agent-options.bend as Options
import ./agent-settings.bend as Settings
import ./agent-state.bend as State
import ./agent-runtime.bend as Runtime
import ./agent-run.bend as Run
import ./agent-lifecycle.bend as Life
import ./agent-continuation.bend as Continue
import ./agent-hooks.bend as Hooks
import ./agent-loop-config.bend as Binding
import ./agent-listeners.bend as Listeners
import ./agent-events.bend as Events
import ./agent-queues.bend as Queues
import ./agent-loop.bend as Loop
import ./stream-fn.bend as Provider
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R

type AgentError<-E: Data> is Data:
  ClaimFailed{message: String}
  DeliveryFailed{error: Events.DeliveryError<E>}
type Retired<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Retired{resources: Run.Resources<A, G, D, M, V, E, J>, hooks: Hooks.Adapters<Options.Turn(A, G, D, M, V, E), Options.Update(A, G, D, M, V, E, J), E>}
# Caller-owned callbacks remain borrowed. Stop new operations and await their
# completion before disposal; retained tool/listener aliases must retire too.
type Agent<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Agent{runtime: Run.Runtime(A, G, D, M, V, E, J), listeners: Run.Registry(A, G, D, M, E), options: R.Ref<Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>>, hooks: R.Ref<Options.TurnHooks(A, G, D, M, V, E, J)>, retired: R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>>, ownedConverter: Maybe<&2, Options.Converter(A, G, D, M, E)>}
def constructed(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, resolved: Result<&2, &2, Provider.MissingDefault, Options.Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match resolved:
    case Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>, Fail{error})
    case Done{Options.Resolved{initial, config, stream, hooks, steering, follow, ownedConverter}}:
      do IO<Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        runtime : Run.Runtime(A, G, D, M, V, E, J) <- Runtime.new(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, initial, steering, follow)
        listeners : Run.Registry(A, G, D, M, E) <- Listeners.new(Run.Event(A, G, D, M), Run.Signal(), E)
        options : R.Ref<Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>> <- R.new(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Run.Options{config, Provider.Explicit{stream}, validate, emptyDetails})
        liveHooks : R.Ref<Options.TurnHooks(A, G, D, M, V, E, J)> <- R.new(Options.TurnHooks(A, G, D, M, V, E, J), hooks)
        retired : R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>> <- R.new(List<&2, Retired<A, G, D, M, V, E, J>>, Nil{})
        return Done{Agent{runtime, listeners, options, liveHooks, retired, ownedConverter}}
# Validation is an explicit typed dependency, never an implicit permissive check.
def new(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, options: Options.AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
    resolved : Result<&2, &2, Provider.MissingDefault, Options.Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>> <- Options.resolve(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, options, fallback)
    constructed(A, G, D, M, V, E, J, Telemetry, Fetch, resolved, validate, emptyDetails)
def state(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.AgentState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.read(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
def subscribe(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, listener: Listeners.Handler(Run.Event(A, G, D, M), Run.Signal(), E)) -> IO(Listeners.Subscription<Run.Event(A, G, D, M), Run.Signal(), E>):
  match agent:
    case Agent{_, listeners, _, _, _, _}: Listeners.subscribe(Run.Event(A, G, D, M), Run.Signal(), E, listeners, listener)
def runOptions(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, hooks: Hooks.Adapters<Options.Turn(A, G, D, M, V, E), Options.Update(A, G, D, M, V, E, J), E>) -> Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>:
  match options:
    case Run.Options{config, stream, validate, emptyDetails}: Run.Options{Binding.applyHooks(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, Telemetry, Fetch, config, hooks), stream, validate, emptyDetails}
def settled(-E: Data, outcome: Result<&2, &2, Events.DeliveryError<E>, Unit>) -> Result<&2, &2, AgentError<E>, Unit>:
  match outcome:
    case Done{value}: Done{value}
    case Fail{error}: Fail{DeliveryFailed{error}}
def retire(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, retired: R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>>, hooks: Hooks.Adapters<Options.Turn(A, G, D, M, V, E), Options.Update(A, G, D, M, V, E, J), E>, completed: Run.Completed<A, G, D, M, V, E, J>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match completed:
    case Run.Completed{outcome, resources}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        R.modify(List<&2, Retired<A, G, D, M, V, E, J>>, Unit, retired, previous => (Retired{resources, hooks} <> previous, Unit{}))
        return settled(E, outcome)
def runClaimed(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, claimed: Life.Claimed<Continue.Plan<Run.Message(A, G, D, M)>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{Runtime.Runtime{+lifecycle}, listeners, options, hooks, retired, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        +adapters : Hooks.Adapters<Options.Turn(A, G, D, M, V, E), Options.Update(A, G, D, M, V, E, J), E> <- Hooks.create(~Runtime.OwnedState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>, ~Options.Turn(A, G, D, M, V, E), ~Options.Update(A, G, D, M, V, E, J), ~E, lifecycle, hooks)
        base : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        completed : Run.Completed<A, G, D, M, V, E, J> <- Run.runClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, Runtime.Runtime{lifecycle}, listeners, runOptions(A, G, D, M, V, E, J, Telemetry, Fetch, base, adapters), claimed)
        retire(A, G, D, M, V, E, J, retired, adapters, completed)
def claimError(error: Life.ClaimError<String>, continuation: Bool) -> String:
  match error:
    case Life.Rejected{message}: message
    case Life.Busy{}: Bool.pick(String, continuation, "Agent is already processing. Wait for completion before continuing.", "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.")
def startClaimed(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, continuation: Bool, claim: Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Continue.Plan<Run.Message(A, G, D, M)>>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match claim:
    case Fail{error}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(error, continuation)}})
    case Done{claimed}: runClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, claimed)
def promptMessages(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, messages: List<&2, Run.Message(A, G, D, M)>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Continue.Plan<Run.Message(A, G, D, M)>>> <- Runtime.beginPrompt(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, messages)
        startClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, False{}, claim)
def continueRun(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Continue.Plan<Run.Message(A, G, D, M)>>> <- Runtime.beginContinue(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
        startClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, True{}, claim)
def steer(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, message: Run.Message(A, G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.steer(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, message)
def followUp(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, message: Run.Message(A, G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.followUp(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, message)
def abort(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.abort(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
def waitForIdle(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.waitForIdle(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
def clearAllQueues(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.clearAllQueues(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
def reset(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Result<&2, &2, String, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.reset(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
def clearSteeringQueue(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.clearQueue(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, Queues.Steering{})
def clearFollowUpQueue(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.clearQueue(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, Queues.FollowUp{})
def signal(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, Run.Signal()>):
  match agent:
    case Agent{Runtime.Runtime{lifecycle}, _, _, _, _, _}: Hooks.signal(Runtime.OwnedState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>, lifecycle)
def setHooks(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Options.TurnHooks(A, G, D, M, V, E, J)) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.write(Options.TurnHooks(A, G, D, M, V, E, J), hooks, value)
def disposeRuns(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, runs: List<&2, Retired<A, G, D, M, V, E, J>>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Retired{resources, hooks} <> rest:
      do IO<Unit>:
        Run.dispose(A, G, D, M, V, E, J, resources)
        Hooks.dispose(Options.Turn(A, G, D, M, V, E), Options.Update(A, G, D, M, V, E, J), E, hooks)
        disposeRuns(A, G, D, M, V, E, J, rest)
# Join public calls and retire borrowed aliases before disposal. waitForIdle
# covers awaited listeners; surviving failed tool batches drain here.
def dispose(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, listeners, options, hooks, retired, converter}:
      do IO<Unit>:
        runs : List<&2, Retired<A, G, D, M, V, E, J>> <- R.dispose(List<&2, Retired<A, G, D, M, V, E, J>>, retired)
        disposeRuns(A, G, D, M, V, E, J, runs)
        Listeners.dispose(Run.Event(A, G, D, M), Run.Signal(), E, listeners)
        old : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.dispose(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        old : Options.TurnHooks(A, G, D, M, V, E, J) <- R.dispose(Options.TurnHooks(A, G, D, M, V, E, J), hooks)
        Hooks.disposeCallback(List<&2, Run.Message(A, G, D, M)>, Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, converter)
        old : Runtime.OwnedState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J> <- Runtime.dispose(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
        return Unit{}

# Native sum types represent the source's text/single-message/batch overloads.
type PromptInput<-A: Data, -G: Data, -D: Data, -M: Data> is Data:
  Text{text: String, images: List<&2, Ai.ImageContent>}
  Message{message: Run.Message(A, G, D, M)}
  Messages{messages: List<&2, Run.Message(A, G, D, M)>}
def imageBlocks(images: List<&2, Ai.ImageContent>) -> List<&2, Ai.TextImageContent>:
  match images:
    case Nil{}: Nil{}
    case image <> rest: Ai.TextImageImage{image} <> imageBlocks(rest)
def normalizePromptInputAt(-A: Data, -G: Data, -D: Data, -M: Data, input: PromptInput<A, G, D, M>, timestamp: F.F64) -> List<&2, Run.Message(A, G, D, M)>:
  match input:
    case Text{text, images}: T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> imageBlocks(images)}, timestamp}}} <> Nil{}
    case Message{message}: message <> Nil{}
    case Messages{messages}: messages
def normalizePromptInput(-A: Data, -G: Data, -D: Data, -M: Data, input: PromptInput<A, G, D, M>) -> IO(List<&2, Run.Message(A, G, D, M)>):
  match input:
    case Text{text, images}:
      do IO<List<&2, Run.Message(A, G, D, M)>>:
        timestamp : F.F64 <- Date.now()
        return normalizePromptInputAt(A, G, D, M, Text{text, images}, timestamp)
    case Message{message}: IO.pure(List<&2, Run.Message(A, G, D, M)>, message <> Nil{})
    case Messages{messages}: IO.pure(List<&2, Run.Message(A, G, D, M)>, messages)
def promptReady(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, input: PromptInput<A, G, D, M>, active: Maybe<&2, Run.Signal()>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match active:
    case Some{_}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(Life.Busy{}, False{})}})
    case None{}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        messages : List<&2, Run.Message(A, G, D, M)> <- normalizePromptInput(A, G, D, M, input)
        promptMessages(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, messages)
def prompt(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, input: PromptInput<A, G, D, M>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  do IO<Result<&2, &2, AgentError<E>, Unit>>:
    active : Maybe<&2, Run.Signal()> <- signal(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    promptReady(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, input, active)

def updateState(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, change: State.Change<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.updateState(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, change)
def setModel(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Ai.Model<J>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, State.SetModel{value})
def setThinkingLevel(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.ThinkingLevel()) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, State.SetThinkingLevel{value})
def setTools(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: List<&2, T.AgentTool<Schema.Value, V, D, A, Run.Signal(), E>>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, State.SetTools{value})
def replaceMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: List<&2, Run.Message(A, G, D, M)>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, State.ReplaceMessages{value})
def appendMessage(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Run.Message(A, G, D, M)) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, State.AppendMessage{value})
def clearMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit): replaceMessages(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Nil{})
def systemPrompt(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(String):
  do IO<String>:
    value : T.AgentState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J> <- state(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return State.systemPrompt(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, value)
def queueValues(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, owned: Runtime.OwnedState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>) -> Queues.Queues<Run.Message(A, G, D, M)>:
  match owned:
    case Runtime.OwnedState{_, queues}: queues
def queueSnapshot(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Queues.Queues<Run.Message(A, G, D, M)>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Queues.Queues<Run.Message(A, G, D, M)>>:
        owned : Runtime.OwnedState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J> <- Runtime.snapshot(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime)
        return queueValues(A, G, D, M, V, E, J, owned)
def hasQueuedMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Bool):
  do IO<Bool>:
    queues : Queues.Queues<Run.Message(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Queues.hasQueuedMessages(Run.Message(A, G, D, M), queues)
def setSteeringMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.setQueueMode(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, Queues.Steering{}, mode)
def getSteeringMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues.Queues<Run.Message(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Queues.getMode(Run.Message(A, G, D, M), queues, Queues.Steering{})
def setFollowUpMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: Runtime.setQueueMode(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, runtime, Queues.FollowUp{}, mode)
def getFollowUpMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues.Queues<Run.Message(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Queues.getMode(Run.Message(A, G, D, M), queues, Queues.FollowUp{})

def configSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Settings.Settings:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, maxRetryDelayMs, _, _, _, transport, _, sessionId, _, _, _, _, _, thinkingBudgets, _, _, _, _, _, _, _, _, toolExecution, _, _}: Settings.Settings{sessionId, thinkingBudgets, Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{}), maxRetryDelayMs, Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}
def settingsConfig(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), settings: Settings.Settings) -> Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config settings:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, _, temperature, samplingParams, maxTokens, _, cacheRetention, _, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, _, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, _, beforeToolCall, afterToolCall} Settings.Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, Some{transport}, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, Some{toolExecution}, beforeToolCall, afterToolCall}
def changedSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, change: Settings.Change) -> Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Run.Options{+config, provider, validate, emptyDetails}: (Run.Options{settingsConfig(A, G, D, M, V, E, J, Telemetry, Fetch, config, Settings.apply(configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config), change)), provider, validate, emptyDetails}, Unit{})
def updateSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, change: Settings.Change) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedSettings(A, G, D, M, V, E, J, Telemetry, Fetch, current, change))
def optionsSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Settings.Settings:
  match options:
    case Run.Options{config, _, _, _}: configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Settings.Settings):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Settings.Settings>:
        current : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsSettings(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def setSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, String>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Settings.SetSessionId{value})
def getSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    settings : Settings.Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Settings.getSessionId(settings)
def setThinkingBudgets(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.ThinkingBudgets>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Settings.SetThinkingBudgets{value})
def getThinkingBudgets(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, Ai.ThinkingBudgets>):
  do IO<Maybe<&2, Ai.ThinkingBudgets>>:
    settings : Settings.Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Settings.getThinkingBudgets(settings)
def setTransport(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Ai.Transport) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Settings.SetTransport{value})
def getTransport(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Ai.Transport):
  do IO<Ai.Transport>:
    settings : Settings.Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Settings.getTransport(settings)
def setMaxRetryDelayMs(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, F.F64>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Settings.SetMaxRetryDelayMs{value})
def getMaxRetryDelayMs(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, F.F64>):
  do IO<Maybe<&2, F.F64>>:
    settings : Settings.Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Settings.getMaxRetryDelayMs(settings)
def setToolExecution(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.ToolExecutionMode) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Settings.SetToolExecution{value})
def getToolExecution(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.ToolExecutionMode):
  do IO<T.ToolExecutionMode>:
    settings : Settings.Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return Settings.getToolExecution(settings)
def configSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, String>:
  Settings.getSessionId(configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config))

# Replacement borrows the new callback. Keep old and new caller-owned handles
# alive through every run that captured them. The owned default converter stays
# alive until Agent disposal, even after replacement.
def changedStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Run.Options{config, _, validate, emptyDetails}: (Run.Options{config, Provider.Explicit{value}, validate, emptyDetails}, Unit{})
def setStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedStreamFunction(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)):
  match options:
    case Run.Options{_, Provider.Explicit{value}, _, _}: IO.pure(T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), value)
    case _: IO.die(T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), 1, "Agent provider selection must be resolved at construction")
def getStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>:
        current : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        optionsStreamFunction(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def configConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Options.Converter(A, G, D, M, E):
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _}: value
def replaceConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Options.Converter(A, G, D, M, E)) -> Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, _, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, value, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Options.Converter(A, G, D, M, E)) -> Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Run.Options{config, provider, validate, emptyDetails}: (Run.Options{replaceConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Options.Converter(A, G, D, M, E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Options.Converter(A, G, D, M, E):
  match options:
    case Run.Options{config, _, _, _}: configConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Options.Converter(A, G, D, M, E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Options.Converter(A, G, D, M, E)>:
        current : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def configTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _}: value
def replaceTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>) -> Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, _, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, value, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>) -> Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Run.Options{config, provider, validate, emptyDetails}: (Run.Options{replaceTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>:
  match options:
    case Run.Options{config, _, _, _}: configTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.TransformContextInput<List<&2, Run.Message(A, G, D, M)>, Run.Signal()>, Result<&2, &2, E, List<&2, Run.Message(A, G, D, M)>>>>>:
        current : Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Run.Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, current)
