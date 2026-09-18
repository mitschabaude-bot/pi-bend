import Base
import ../src/agent.bend as Agent
import ../src/agent-loop.bend as Loop
import ../src/agent-run.bend as Run
import ../src/stream-fn.bend as Provider
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-signal.bend as Signal
import ./agent-await.bend as Await
import ./agent-run.bend as H
import ./message-events.bend as Test

type Capture is Data:
  Capture{mode: U32, entered: Chan(Unit), release: Chan(Unit), done: Chan(Unit), streams: R.Ref<List<&2, H.StreamValue()>>}
def produce(+stream: H.StreamValue(), entered: Chan(Unit), release: Chan(Unit), done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.Start{H.assistant()})
    sent : Bool <- Chan.send(Unit, entered, Unit{})
    R.requireSent(sent)
    IO.join(Unit, release)
    Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
    sent : Bool <- Chan.send(Unit, done, Unit{})
    R.requireSent(sent)
def dispatch(mode: U32, stream: H.StreamValue(), entered: Chan(Unit), release: Chan(Unit), done: Chan(Unit), input: H.ProviderInput()) -> IO(Unit):
  match mode:
    case 0: IO.spawn(Unit, produce(stream, entered, release, done))
    case _:
      do IO<Unit>:
        signal : Run.Signal() <- Signal.requestSignal(input)
        IO.spawn(Unit, Signal.produce(signal, stream, entered, done))
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case Capture{mode, entered, release, done, streams}:
      do IO<H.ProviderOutput()>:
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        dispatch(mode, stream, entered, release, done, input)
        return Done{stream}
def create(capture: Capture) -> IO(Signal.Fixture):
  do IO<Signal.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 0)
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Behavior.options(Some{stream}, None{}), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Signal.Fixture{agent, stream, validator, registry}
def assertTranscript(+agent: Owner.Owner(), active: Bool, roles: String) -> IO(Unit):
  do IO<Unit>:
    +state : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(Bool.pick(Bool, active, Await.streaming(state), Bool.not(Await.streaming(state))) && String.eq(H.roles(Named.getMessages(state)), roles), "busy-operation transcript and streaming state")
def rejected(+agent: Owner.Owner(), mode: U32) -> IO(Unit):
  match mode:
    case 0:
      do IO<Unit>:
        assertTranscript(agent, True{}, "u")
        result : Result<&2, &2, String, Unit> <- Agent.reset(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(Owner.resetRejected(result), "reset rejects with the original busy error")
        assertTranscript(agent, True{}, "u")
    case 1:
      do IO<Unit>:
        result : Owner.Outcome() <- Agent.prompt(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Text{"Second message", Nil{}})
        Test.assertion(Owner.isRejected(result, "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion."), "second prompt rejects with original busy error")
    case _:
      do IO<Unit>:
        result : Owner.Outcome() <- Agent.continueRun(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)
        Test.assertion(Owner.isRejected(result, "Agent is already processing. Wait for completion before continuing."), "continuation rejects with original busy error")
def releaseRun(mode: U32, agent: Owner.Owner(), release: Chan(Unit)) -> IO(Unit):
  match mode:
    case 0:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)
    case _: Agent.abort(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Signal.Fixture <- create(Capture{mode, entered, release, done, streams})
    +agent : Owner.Owner() = Signal.getAgent(fixture)
    promptReply : Chan(Unit) <- IO.fork(Unit, Behavior.prompt(agent, "First message"))
    IO.join(Unit, entered)
    assertTranscript(agent, True{}, "u")
    rejected(agent, mode)
    releaseRun(mode, agent, release)
    IO.join(Unit, promptReply)
    IO.join(Unit, done)
    assertTranscript(agent, False{}, "ua")
    Signal.dispose(fixture)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS " ++ name)
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "should reject reset while processing without corrupting the transcript")
    scenario(1, "should throw when prompt() called while streaming")
    scenario(2, "should throw when continue() called while streaming")
