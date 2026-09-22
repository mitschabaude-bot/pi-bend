import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Run
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Emission
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-run.bend as H
import ./message-events.bend as Test

def Input() -> Data: Listeners.Input<H.EventValue(), Run.RunSignal()>
def Handler() -> Data: Listeners.Handler(H.EventValue(), Run.RunSignal(), String)
def streaming(value: Named.Snapshot()) -> Bool:
  match value:
    case T.AgentState{_, _, _, _, active, _, _, _}: active

type Gate is Data:
  Gate{mode: U32, entered: Chan(Unit), release: Chan(Unit), finished: R.Ref<Bool>}
def selected(mode: U32, event: H.EventValue()) -> Bool:
  match mode event:
    case 0 T.AgentEnd{_}: True{}
    case 1 T.MessageEnd{T.LlmMessage{Ai.Assistant{_}}}: True{}
    case _ _: False{}
def delayed(entered: Chan(Unit), release: Chan(Unit), finished: R.Ref<Bool>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    sent : Bool <- Chan.send(Unit, entered, Unit{})
    R.requireSent(sent)
    IO.join(Unit, release)
    R.write(Bool, finished, True{})
    return Done{Unit{}}
def chooseListener(block: Bool, entered: Chan(Unit), release: Chan(Unit), finished: R.Ref<Bool>) -> IO(Emission.Emission<String>):
  match block:
    case True{}: Emission.startEmission(String, delayed(entered, release, finished))
    case False{}: IO.pure(Emission.Emission<String>, Emission.EmissionReady{Done{Unit{}}})
def listener(gate: Gate, input: Input()) -> IO(Emission.Emission<String>):
  match gate input:
    case Gate{mode, entered, release, finished} Listeners.Input{event, _}:
      chooseListener(selected(mode, event), entered, release, finished)
def promptWorker(agent: Owner.Owner(), resolved: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    Behavior.prompt(agent, "hello")
    R.write(Bool, resolved, True{})
def idleWorker(agent: Owner.Owner(), started: Chan(Unit), resolved: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, started, Unit{})
    R.requireSent(sent)
    Agent.waitForIdle(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    R.write(Bool, resolved, True{})
def checkSuspended(+agent: Owner.Owner(), finished: R.Ref<Bool>, prompted: R.Ref<Bool>, idle: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    # Preserve upstream's bounded observation of noncompletion, after a causal
    # barrier confirms that the subscriber is suspended.
    IO.sleep(10)
    listenerDone : Bool <- R.read(Bool, finished)
    promptDone : Bool <- R.read(Bool, prompted)
    idleDone : Bool <- R.read(Bool, idle)
    value : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(Bool.not(listenerDone) && Bool.not(promptDone) && Bool.not(idleDone) && streaming(value), "suspended subscriber keeps prompt and idle pending and state streaming")
def checkFinished(agent: Owner.Owner(), finished: R.Ref<Bool>, prompted: R.Ref<Bool>, idle: R.Ref<Bool>) -> IO(Unit):
  do IO<Unit>:
    listenerDone : Bool <- R.read(Bool, finished)
    promptDone : Bool <- R.read(Bool, prompted)
    idleDone : Bool <- R.read(Bool, idle)
    value : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(listenerDone && promptDone && idleDone && Bool.not(streaming(value)), "listener completion precedes resolved prompt and idle state")
def awaitCase(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Behavior.Fixture <- Behavior.create(False{}, None{})
    +agent : Owner.Owner() = Behavior.getAgent(fixture)
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +finished : R.Ref<Bool> <- R.new(Bool, False{})
    +prompted : R.Ref<Bool> <- R.new(Bool, False{})
    +idle : R.Ref<Bool> <- R.new(Bool, False{})
    +observe : Handler() <- C.create(~Gate, ~Input(), ~Emission.Emission<String>, ~listener, Gate{mode, entered, release, finished})
    ignored : Listeners.Subscription<H.EventValue(), Run.RunSignal(), String> <- Agent.subscribe(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, observe)
    promptReply : Chan(Unit) <- IO.fork(Unit, promptWorker(agent, prompted))
    IO.join(Unit, entered)
    +idleStarted : Chan(Unit) <- Chan.new(Unit, 1)
    idleReply : Chan(Unit) <- IO.fork(Unit, idleWorker(agent, idleStarted, idle))
    IO.join(Unit, idleStarted)
    checkSuspended(agent, finished, prompted, idle)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    IO.join(Unit, promptReply)
    IO.join(Unit, idleReply)
    checkFinished(agent, finished, prompted, idle)
    Behavior.dispose(fixture)
    C.dispose(Input(), Emission.Emission<String>, observe)
    old : Bool <- R.dispose(Bool, finished)
    old : Bool <- R.dispose(Bool, prompted)
    old : Bool <- R.dispose(Bool, idle)
    IO.print("PASS " ++ name)

type FailureFixture is Data:
  FailureFixture{agent: Owner.Owner(), provider: Named.StreamFunction(), validator: Named.Validator(), registry: Named.Fallback()}
def failProvider(unused: Unit, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  IO.pure(H.ProviderOutput(), Fail{"provider exploded"})
def failureFixture() -> IO(FailureFixture):
  do IO<FailureFixture>:
    +provider : Named.StreamFunction() <- C.create(~Unit, ~H.ProviderInput(), ~H.ProviderOutput(), ~failProvider, Unit{})
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 0)
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Behavior.options(Some{provider}, None{}), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return FailureFixture{agent, provider, validator, registry}
def failureAgent(fixture: FailureFixture) -> Owner.Owner():
  match fixture:
    case FailureFixture{agent, _, _, _}: agent
def disposeFailure(fixture: FailureFixture) -> IO(Unit):
  match fixture:
    case FailureFixture{agent, provider, validator, registry}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), provider)
        C.dispose(Loop.ToolValidationInput<Schema.Value, Unit, Unit>, Result<&2, &2, String, Unit>, validator)
        Provider.dispose(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, registry)
def record(trace: R.Ref<String>, input: Input()) -> IO(Emission.Emission<String>):
  match input:
    case Listeners.Input{event, _}:
      do IO<Emission.Emission<String>>:
        R.modify(String, Unit, trace, old => (old ++ H.eventName(event) ++ ";", Unit{}))
        return Emission.EmissionReady{Done{Unit{}}}
def failedAssistant(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, Some{"provider exploded"}, _, _, _}}} <> Nil{}: True{}
    case _ <> rest: failedAssistant(rest)
    case Nil{}: False{}
def failedState(state: Named.Snapshot()) -> Bool:
  match state:
    case T.AgentState{_, _, _, messages, False{}, _, _, Some{"provider exploded"}}: failedAssistant(messages)
    case _: False{}
def failureCase() -> IO(Unit):
  do IO<Unit>:
    +fixture : FailureFixture <- failureFixture()
    +agent : Owner.Owner() = failureAgent(fixture)
    +trace : R.Ref<String> <- R.new(String, "")
    +observe : Handler() <- C.create(~R.Ref<String>, ~Input(), ~Emission.Emission<String>, ~record, trace)
    ignored : Listeners.Subscription<H.EventValue(), Run.RunSignal(), String> <- Agent.subscribe(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, observe)
    Behavior.prompt(agent, "hello")
    events : String <- R.read(String, trace)
    Test.assertion(String.eq(events, "agent_start;turn_start;start:u;end:u;start:a;end:a;turn_end;agent_end;"), "provider failure emits the exact full recovery lifecycle")
    value : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(failedState(value), "last assistant and Agent state retain provider error and error stop reason")
    disposeFailure(fixture)
    C.dispose(Input(), Emission.Emission<String>, observe)
    old : String <- R.dispose(String, trace)
    IO.print("PASS emits full lifecycle events for thrown run failures")
def main() -> IO(Unit):
  do IO<Unit>:
    failureCase()
    awaitCase(0, "should await async subscribers before prompt resolves")
    awaitCase(1, "waitForIdle should wait for async subscribers")
