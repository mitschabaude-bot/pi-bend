import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Run
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Emission
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/deferred.bend as D
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-run.bend as H
import ./message-events.bend as Test

type Capture is Data:
  Capture{entered: Chan(Unit), done: Chan(Unit), streams: R.Ref<List<&2, H.StreamValue()>>}
type Fixture is Data:
  Fixture{agent: Owner.Owner(), provider: Named.StreamFunction(), validator: Named.Validator(), registry: Named.Fallback()}
def requireSignal(value: Maybe<&2, Run.RunSignal()>) -> IO(Run.RunSignal()):
  match value:
    case Some{signal}: IO.pure(Run.RunSignal(), signal)
    case None{}: IO.die(Run.RunSignal(), 1, "active abort signal is missing")
def requestSignal(input: H.ProviderInput()) -> IO(Run.RunSignal()):
  match input:
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _}}}: requireSignal(signal)
    case _: IO.die(Run.RunSignal(), 1, "provider options are missing")
def awaitAbort(observation: D.Observation<Abort.AbortReason<Unit>>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, _}:
      do IO<Unit>:
        reason : Maybe<&2, Abort.AbortReason<Unit>> <- D.wait(Maybe<&2, Abort.AbortReason<Unit>>, ticket)
        Test.assertion(Maybe.is_some(&2, Abort.AbortReason<Unit>, reason), "abort observation completed with a cancellation reason")
def produce(+signal: Run.RunSignal(), +stream: H.StreamValue(), entered: Chan(Unit), done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    observation : D.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit, signal)
    Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.Start{H.assistant()})
    sent : Bool <- Chan.send(Unit, entered, Unit{})
    R.requireSent(sent)
    awaitAbort(observation)
    cancelled : Bool <- Abort.aborted(Unit, signal)
    Test.assertion(cancelled, "provider observes cancellation through request options")
    Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.StreamError{Ai.ErrorAborted{}, H.assistant()})
    sent : Bool <- Chan.send(Unit, done, Unit{})
    R.requireSent(sent)
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case Capture{entered, done, streams}:
      do IO<H.ProviderOutput()>:
        signal : Run.RunSignal() <- requestSignal(input)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        IO.spawn(Unit, produce(signal, stream, entered, done))
        return Done{T.borrowedStream(Unit, String, stream)}
def create(capture: Capture) -> IO(Fixture):
  do IO<Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 0)
    +registry : Named.Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, Behavior.options(Some{stream}, None{}), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Fixture{agent, stream, validator, registry}
def getAgent(fixture: Fixture) -> Owner.Owner():
  match fixture:
    case Fixture{agent, _, _, _}: agent
def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{agent, stream, validator, registry}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, String, String, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
        C.dispose(Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>, validator)
        Provider.dispose(Unit, Unit, H.Config(), String, registry)
def Input() -> Data: Listeners.Input<H.EventValue()>
def captureSignal(slot: R.Ref<Maybe<&2, Run.RunSignal()>>, input: Input()) -> IO(Emission.Emission<String>):
  match input:
    case Listeners.Input{T.AgentStart{}, signal}:
      do IO<Emission.Emission<String>>:
        R.write(Maybe<&2, Run.RunSignal()>, slot, Some{signal})
        return Emission.EmissionReady{Done{Unit{}}}
    case _: IO.pure(Emission.Emission<String>, Emission.EmissionReady{Done{Unit{}}})
def main() -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Fixture <- create(Capture{entered, done, streams})
    +agent : Owner.Owner() = getAgent(fixture)
    +slot : R.Ref<Maybe<&2, Run.RunSignal()>> <- R.new(Maybe<&2, Run.RunSignal()>, None{})
    +observe : Listeners.Handler(H.EventValue(), String) <- C.create(~R.Ref<Maybe<&2, Run.RunSignal()>>, ~Input(), ~Emission.Emission<String>, ~captureSignal, slot)
    ignored : Listeners.Subscription<H.EventValue(), String> <- Agent.subscribe(Unit, Unit, String, String, Unit, agent, observe)
    promptReply : Chan(Unit) <- IO.fork(Unit, Behavior.prompt(agent, "hello"))
    IO.join(Unit, entered)
    received : Maybe<&2, Run.RunSignal()> <- R.read(Maybe<&2, Run.RunSignal()>, slot)
    +signal : Run.RunSignal() <- requireSignal(received)
    before : Bool <- Abort.aborted(Unit, signal)
    Test.assertion(Bool.not(before), "subscriber receives a defined, initially un-aborted signal")
    Agent.abort(Unit, Unit, String, String, Unit, agent)
    IO.join(Unit, promptReply)
    IO.join(Unit, done)
    after : Bool <- Abort.aborted(Unit, signal)
    Test.assertion(after, "retained subscriber signal observes cancellation after prompt finishes")
    dispose(fixture)
    C.dispose(Input(), Emission.Emission<String>, observe)
    old : Maybe<&2, Run.RunSignal()> <- R.dispose(Maybe<&2, Run.RunSignal()>, slot)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS should pass the active abort signal to subscribers")
