import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as Hooks
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-settings.bend as SettingsTest
import ./agent-run.bend as H
import ./message-events.bend as Test

def Turn() -> Data: Options.Turn(Unit, Unit, Unit, String, Unit, String)
def Update() -> Data: Options.Update(Unit, Unit, Unit, String, Unit, String, Unit)
def Input() -> Data: T.ToolHookInput<Turn(), Run.RunSignal()>
def Prepared() -> Data: Hooks.PrepareResult(Update(), String)
def Stop() -> Data: Hooks.StopHook(Turn(), String)
def Legacy() -> Data: Hooks.LegacyHook(Update(), String)
def ContextHook() -> Data: Hooks.ContextHook(Turn(), Update(), String)
def Values() -> Data: Options.TurnHooks(Unit, Unit, Unit, String, Unit, String, Unit)
type Handlers is Data:
  Handlers{stop: Stop(), legacy: Legacy(), context: ContextHook()}
def install(+agent: Owner.Owner(), values: Values()) -> IO(Unit):
  match values:
    case Hooks.Hooks{stop, legacy, context}:
      do IO<Unit>:
        Agent.setShouldStopAfterTurn(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, stop)
        Agent.setPrepareNextTurn(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, legacy)
        Agent.setPrepareNextTurnWithContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, context)
def read(+agent: Owner.Owner()) -> IO(Values()):
  do IO<Values()>:
    stop : Maybe<&2, Stop()> <- Agent.getShouldStopAfterTurn(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    legacy : Maybe<&2, Legacy()> <- Agent.getPrepareNextTurn(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    context : Maybe<&2, ContextHook()> <- Agent.getPrepareNextTurnWithContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    return Hooks.Hooks{stop, legacy, context}
def sameStop(left: Maybe<&2, Stop()>, right: Maybe<&2, Stop()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(Input(), Result<&2, &2, String, Bool>, a, b)
    case _ _: False{}
def sameLegacy(left: Maybe<&2, Legacy()>, right: Maybe<&2, Legacy()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(Maybe<&2, Run.RunSignal()>, Prepared(), a, b)
    case _ _: False{}
def sameContext(left: Maybe<&2, ContextHook()>, right: Maybe<&2, ContextHook()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(Input(), Prepared(), a, b)
    case _ _: False{}
def same(left: Values(), right: Values()) -> Bool:
  match left right:
    case Hooks.Hooks{a, b, c} Hooks.Hooks{d, e, f}: sameStop(a, d) && sameLegacy(b, e) && sameContext(c, f)


def initial(mode: U32, handlers: Handlers) -> Values():
  match mode handlers:
    case 1 _: Hooks.Hooks{None{}, None{}, None{}}
    case _ Handlers{stop, legacy, _}: Hooks.Hooks{Some{stop}, Some{legacy}, None{}}
def replacement(mode: U32, handlers: Handlers) -> Values():
  match mode handlers:
    case 0 Handlers{stop, legacy, context}: Hooks.Hooks{Some{stop}, Some{legacy}, Some{context}}
    case 1 Handlers{_, legacy, _}: Hooks.Hooks{None{}, Some{legacy}, None{}}
    case _ _: Hooks.Hooks{None{}, None{}, None{}}
def expectedCurrent(mode: U32, handlers: Handlers) -> Values():
  match mode handlers:
    case 0 Handlers{stop, legacy, _}: Hooks.Hooks{Some{stop}, Some{legacy}, None{}}
    case 1 Handlers{_, legacy, _}: Hooks.Hooks{None{}, Some{legacy}, None{}}
    case _ _: Hooks.Hooks{None{}, None{}, None{}}
def live(value: Maybe<&2, Run.RunSignal()>) -> IO(Unit):
  match value:
    case Some{signal}:
      do IO<Unit>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(Bool.not(cancelled), "turn callbacks receive the active live signal")
    case _: Test.assertion(False{}, "turn callback signal missing")
type Capture is Data:
  Capture{name: String, trace: R.Ref<String>, slot: R.Ref<Maybe<&2, Owner.Owner()>>}
def stop(capture: Capture, input: Input()) -> IO(Result<&2, &2, String, Bool>):
  match capture input:
    case Capture{+name, trace, _} T.ToolHookInput{_, signal}:
      do IO<Result<&2, &2, String, Bool>>:
        live(signal)
        R.modify(String, Unit, trace, old => (old ++ "s" ++ name ++ ";", Unit{}))
        return Done{String.eq(name, "b")}
def legacy(capture: Capture, signal: Maybe<&2, Run.RunSignal()>) -> IO(Prepared()):
  match capture:
    case Capture{name, trace, _}:
      do IO<Prepared()>:
        live(signal)
        R.modify(String, Unit, trace, old => (old ++ "l" ++ name ++ ";", Unit{}))
        return Done{None{}}
def toolTail(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.ToolResult{_}} <> Nil{}: True{}
    case _ <> rest: toolTail(rest)
    case Nil{}: False{}
def context(capture: Capture, input: Input()) -> IO(Prepared()):
  match capture input:
    case Capture{name, trace, slot} T.ToolHookInput{T.ShouldStopAfterTurnContext{_, _ <> Nil{}, T.AgentContext{messages, _}, _}, signal}:
      do IO<Prepared()>:
        live(signal)
        Test.assertion(toolTail(messages), "context preparation sees one completed tool result and transcript tail")
        R.modify(String, Unit, trace, old => (old ++ "c" ++ name ++ ";", Unit{}))
        stored : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(stored)
        Agent.setPrepareNextTurnWithContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, None{})
        return Done{None{}}
    case _ _: IO.die(Prepared(), 1, "unexpected preparation context")
def handlers(+capture: Capture) -> IO(Handlers):
  do IO<Handlers>:
    a : Stop() <- C.create(~Capture, ~Input(), ~Result<&2, &2, String, Bool>, ~stop, capture)
    b : Legacy() <- C.create(~Capture, ~Maybe<&2, Run.RunSignal()>, ~Prepared(), ~legacy, capture)
    c : ContextHook() <- C.create(~Capture, ~Input(), ~Prepared(), ~context, capture)
    return Handlers{a, b, c}
type ProviderCapture is Data:
  ProviderCapture{mode: U32, future: Handlers, slot: R.Ref<Maybe<&2, Owner.Owner()>>, calls: R.Ref<U32>, trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}
def replaceFirst(index: U32, mode: U32, future: Handlers, slot: R.Ref<Maybe<&2, Owner.Owner()>>) -> IO(Unit):
  match index:
    case 0:
      do IO<Unit>:
        stored : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(stored)
        install(agent, replacement(mode, future))
    case _: IO.pure(Unit, Unit{})
def toolTurn(+index: U32) -> Bool: U32.is_eq(index, 0) || U32.is_eq(index, 1) || U32.is_eq(index, 3) || U32.is_eq(index, 4)
def push(tool: Bool, stream: H.StreamValue()) -> IO(Unit):
  match tool:
    case True{}: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneToolUse{}, H.response(True{})})
    case False{}: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case ProviderCapture{mode, future, slot, calls, trace, streams}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- R.modify(U32, U32, calls, old => SettingsTest.increment(old))
        R.modify(String, Unit, trace, old => (old ++ "p;", Unit{}))
        replaceFirst(index, mode, future, slot)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        push(toolTurn(index), stream)
        return Done{stream}
def create(capture: ProviderCapture) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(Some{initial}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}


def exercise(+agent: Owner.Owner(), +mode: U32, first: Handlers, second: Handlers) -> IO(Unit):
  do IO<Unit>:
    empty : Values() <- read(agent)
    Test.assertion(same(empty, Hooks.Hooks{None{}, None{}, None{}}), "all turn callbacks initially absent")
    +values : Values() = initial(mode, first)
    install(agent, values)
    assigned : Values() <- read(agent)
    Test.assertion(same(assigned, values), "individual setters preserve the other turn callbacks")
    Behavior.prompt(agent, "first")
    current : Values() <- read(agent)
    Test.assertion(same(current, expectedCurrent(mode, second)), "getters reflect live replacement and clearing")
    Behavior.prompt(agent, "next")
def disposeHandlers(values: Handlers) -> IO(Unit):
  match values:
    case Handlers{stop, legacy, context}:
      do IO<Unit>:
        C.dispose(Input(), Result<&2, &2, String, Bool>, stop)
        C.dispose(Maybe<&2, Run.RunSignal()>, Prepared(), legacy)
        C.dispose(Input(), Prepared(), context)
def scenario(+mode: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +first : Handlers <- handlers(Capture{"a", trace, slot})
    +second : Handlers <- handlers(Capture{"b", trace, slot})
    +fixture : Named.Fixture <- create(ProviderCapture{mode, second, slot, calls, trace, streams})
    +agent : Owner.Owner() = Named.getAgent(fixture)
    R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
    exercise(agent, mode, first, second)
    +actual : String <- R.read(String, trace)
    Test.assertion(String.eq(actual, expected), "turn hook capture/live-selection order mismatch: " ++ actual)
    count : U32 <- R.read(U32, calls)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, U32.is_eq(mode, 0), 4, 6)), "captured stop hook preserves request count")
    Named.dispose(fixture)
    disposeHandlers(first)
    disposeHandlers(second)
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    old : U32 <- R.dispose(U32, calls)
    old : String <- R.dispose(String, trace)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent turn-hook accessor source scenario")
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "p;sa;cb;p;sa;lb;p;sa;p;sb;")
    scenario(1, "p;p;p;p;lb;p;lb;p;")
    scenario(2, "p;sa;p;sa;p;sa;p;p;p;")
