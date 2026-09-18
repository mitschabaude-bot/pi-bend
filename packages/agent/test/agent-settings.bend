import Base
import ../src/agent.bend as Agent
import ../src/agent-settings.bend as Settings
import ../src/agent-state.bend as State
import ../src/agent-run.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/f64.bend as F
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-run.bend as H
import ./message-events.bend as Test

def budgets() -> Ai.ThinkingBudgets:
  Ai.ThinkingBudgets{Some{F.fromU32(1)}, Some{F.fromU32(2)}, Some{F.fromU32(3)}, Some{F.fromU32(4)}}
def number(value: F.F64, expected: U32) -> Bool: Schema.equal(Schema.Number{value}, Schema.Number{F.fromU32(expected)})
def initial(value: Settings.Settings) -> Bool:
  match value:
    case Settings.Settings{None{}, None{}, Ai.AutoTransport{}, None{}, T.Parallel{}}: True{}
    case _: False{}
def configured(value: Settings.Settings) -> Bool:
  match value:
    case Settings.Settings{Some{"configured"}, Some{Ai.ThinkingBudgets{Some{a}, Some{b}, Some{c}, Some{d}}}, Ai.WebSocket{}, Some{delay}, T.Sequential{}}: number(a, 1) && number(b, 2) && number(c, 3) && number(d, 4) && number(delay, 123)
    case _: False{}
def future(value: Settings.Settings) -> Bool:
  match value:
    case Settings.Settings{None{}, None{}, Ai.Sse{}, None{}, T.Parallel{}}: True{}
    case _: False{}
def read(+agent: Owner.Owner()) -> IO(Settings.Settings):
  do IO<Settings.Settings>:
    session : Maybe<&2, String> <- Agent.getSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    thinking : Maybe<&2, Ai.ThinkingBudgets> <- Agent.getThinkingBudgets(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    transport : Ai.Transport <- Agent.getTransport(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    delay : Maybe<&2, F.F64> <- Agent.getMaxRetryDelayMs(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    execution : T.ToolExecutionMode <- Agent.getToolExecution(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    return Settings.Settings{session, thinking, transport, delay, execution}
def configure(+agent: Owner.Owner()) -> IO(Unit):
  do IO<Unit>:
    Agent.setSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Some{"configured"})
    Agent.setThinkingBudgets(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Some{budgets()})
    Agent.setTransport(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Ai.WebSocket{})
    Agent.setMaxRetryDelayMs(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Some{F.fromU32(123)})
    Agent.setToolExecution(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, T.Sequential{})
def changeFuture(+agent: Owner.Owner()) -> IO(Unit):
  do IO<Unit>:
    Agent.setSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, None{})
    Agent.setThinkingBudgets(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, None{})
    Agent.setTransport(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Ai.Sse{})
    Agent.setMaxRetryDelayMs(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, None{})
    Agent.setToolExecution(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, T.Parallel{})
def requireAgent(value: Maybe<&2, Owner.Owner()>) -> IO(Owner.Owner()):
  match value:
    case Some{agent}: IO.pure(Owner.Owner(), agent)
    case _: IO.die(Owner.Owner(), 1, "provider called before Agent construction")
type Capture is Data:
  Capture{agent: R.Ref<Maybe<&2, Owner.Owner()>>, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}
def increment(+old: U32) -> U32 & U32: (U32.add(old, 1), old)
def checkRequest(index: U32, settings: Settings.Settings) -> IO(Unit):
  match index:
    case 0: Test.assertion(configured(settings), "first request receives all assigned settings")
    case 1: Test.assertion(configured(settings), "second request in current run retains captured settings")
    case 2: Test.assertion(future(settings), "next run receives updated and cleared settings")
    case _: Test.assertion(False{}, "unexpected provider request")
def changeOnce(index: U32, slot: R.Ref<Maybe<&2, Owner.Owner()>>) -> IO(Unit):
  match index:
    case 0:
      do IO<Unit>:
        value : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- requireAgent(value)
        changeFuture(agent)
    case _: IO.pure(Unit, Unit{})
def push(index: U32, stream: H.StreamValue()) -> IO(Unit):
  match index:
    case 0: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneToolUse{}, H.response(True{})})
    case _: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case Capture{slot, calls, streams} T.StreamInput{_, _, Some{config}}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- R.modify(U32, U32, calls, old => increment(old))
        checkRequest(index, Agent.configSettings(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, config))
        changeOnce(index, slot)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        push(index, stream)
        return Done{stream}
    case _ _: IO.die(H.ProviderOutput(), 1, "provider options missing")
def create(capture: Capture) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit, Run.Signal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    init : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(Some{init}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}
def exercise(+agent: Owner.Owner()) -> IO(Unit):
  do IO<Unit>:
    before : Settings.Settings <- read(agent)
    Test.assertion(initial(before), "public setting defaults match the constructor")
    configure(agent)
    assigned : Settings.Settings <- read(agent)
    Test.assertion(configured(assigned), "individual setters preserve all unrelated settings")
    Behavior.prompt(agent, "first")
    changed : Settings.Settings <- read(agent)
    Test.assertion(future(changed), "getters observe assignments made during a run")
    Behavior.prompt(agent, "next")
def main() -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Named.Fixture <- create(Capture{slot, calls, streams})
    +agent : Owner.Owner() = Named.getAgent(fixture)
    R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
    exercise(agent)
    count : U32 <- R.read(U32, calls)
    Test.assertion(U32.is_eq(count, 3), "two requests in first run, one in second")
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    Named.dispose(fixture)
    old : U32 <- R.dispose(U32, calls)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent settings defaults, assignment, clearing and per-run capture")
