import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/agent.bend as Failure
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Emission
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/f64.bend as F
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-declarations.bend as Declarations
import ./agent-run.bend as H
import ./message-events.bend as Test

def Update() -> Data: T.AgentToolUpdateCallback(Unit)
def ExecuteInput() -> Data: T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>
def ExecuteResult() -> Data: Result<&2, &2, String, T.AgentToolResult<Unit>>
def result(text: String, terminate: Bool) -> T.AgentToolResult<Unit>:
  T.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, Unit{}, None{}, Some{terminate}}
def requireUpdate(value: Maybe<&2, Update()>) -> IO(Update()):
  match value:
    case Some{callback}: IO.pure(Update(), callback)
    case None{}: IO.die(Update(), 1, "tool update callback was not supplied")
type ExecuteCapture is Data:
  ExecuteCapture{mode: U32, saved: R.Ref<Maybe<&2, Update()>>, slowStarted: Chan(Unit), releaseSlow: Chan(Unit)}
def progress(mode: U32, callback: Update()) -> IO(Unit):
  match mode:
    case 0: C.call(T.AgentToolResult<Unit>, Unit, callback, result("running", False{}))
    case _: IO.pure(Unit, Unit{})
def execute(capture: ExecuteCapture, input: ExecuteInput()) -> IO(ExecuteResult()):
  match capture input:
    case ExecuteCapture{_, _, started, release} T.ToolExecutionInput{"call-2", _, _, _}:
      do IO<ExecuteResult()>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        R.requireSent(sent)
        IO.join(Unit, release)
        return Done{result("done", True{})}
    case ExecuteCapture{+mode, saved, _, _} T.ToolExecutionInput{"call-1", _, _, update}:
      do IO<ExecuteResult()>:
        +callback : Update() <- requireUpdate(update)
        R.write(Maybe<&2, Update()>, saved, Some{callback})
        progress(mode, callback)
        return Done{result(Bool.pick(String, U32.is_eq(mode, 0), "ok", "done"), True{})}
    case _ _: IO.die(ExecuteResult(), 1, "unexpected tool invocation")
def calls(mode: U32) -> List<&2, Ai.AssistantContent<Unit>>:
  match mode:
    case 0: Ai.AssistantToolCall{Ai.ToolCall{"call-1", "delayed_tool", Unit{}, None{}, None{}}} <> Nil{}
    case _: Ai.AssistantToolCall{Ai.ToolCall{"call-1", "settled_tool", Unit{}, None{}, None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"call-2", "slow_tool", Unit{}, None{}, None{}}} <> Nil{}
def assistant(mode: U32) -> Ai.AssistantMessage<Unit, Unit>:
  Ai.AssistantMessage{calls(mode), "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Failure.emptyUsage(), Ai.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(0)}
type ProviderCapture is Data:
  ProviderCapture{mode: U32, streams: R.Ref<List<&2, H.StreamValue()>>}
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case ProviderCapture{mode, streams}:
      do IO<H.ProviderOutput()>:
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneToolUse{}, assistant(mode)})
        return Done{T.borrowedStream(Unit, Unit, String, stream)}
def tools(mode: U32, +executor: Named.Executor()) -> List<&2, Named.Tool()>:
  match mode:
    case 0: Declarations.tool("delayed_tool", "Captures progress callbacks", executor) <> Nil{}
    case _: Declarations.tool("settled_tool", "Captures progress callbacks", executor) <> Declarations.tool("slow_tool", "Keeps the agent run active", executor) <> Nil{}
def create(+mode: U32, capture: ExecuteCapture, streams: R.Ref<List<&2, H.StreamValue()>>) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, ProviderCapture{mode, streams})
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~ExecuteCapture, ~ExecuteInput(), ~ExecuteResult(), ~execute, capture)
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, Some{tools(mode, executor)}, None{}}
    created : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(Some{initial}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(created)
    return Named.Fixture{agent, stream, validator, executor, registry}
def Input() -> Data: Listeners.Input<H.EventValue(), Run.RunSignal()>
type ObserveCapture is Data:
  ObserveCapture{events: R.Ref<U32>, updates: R.Ref<U32>, ended: Chan(Unit)}
def record(event: H.EventValue(), updates: R.Ref<U32>, ended: Chan(Unit)) -> IO(Unit):
  match event:
    case T.ToolExecutionUpdate{_, _, _, _}: R.modify(U32, Unit, updates, old => (U32.add(old, 1), Unit{}))
    case T.ToolExecutionEnd{"call-1", _, _, _}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, ended, Unit{})
        R.requireSent(sent)
    case _: IO.pure(Unit, Unit{})
def observe(capture: ObserveCapture, input: Input()) -> IO(Emission.Emission<String>):
  match capture input:
    case ObserveCapture{events, updates, ended} Listeners.Input{event, _}:
      do IO<Emission.Emission<String>>:
        R.modify(U32, Unit, events, old => (U32.add(old, 1), Unit{}))
        record(event, updates, ended)
        return Emission.EmissionReady{Done{Unit{}}}
def waitBefore(mode: U32, reply: Chan(Unit), started: Chan(Unit), ended: Chan(Unit)) -> IO(Unit):
  match mode:
    case 0: IO.join(Unit, reply)
    case _:
      do IO<Unit>:
        IO.join(Unit, started)
        IO.join(Unit, ended)
def finishPrompt(mode: U32, reply: Chan(Unit), release: Chan(Unit)) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case _:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)
        IO.join(Unit, reply)
def late(+saved: R.Ref<Maybe<&2, Update()>>, +events: R.Ref<U32>) -> IO(Unit):
  do IO<Unit>:
    before : U32 <- R.read(U32, events)
    supplied : Maybe<&2, Update()> <- R.read(Maybe<&2, Update()>, saved)
    callback : Update() <- requireUpdate(supplied)
    C.call(T.AgentToolResult<Unit>, Unit, callback, result("late", False{}))
    after : U32 <- R.read(U32, events)
    Test.assertion(U32.is_eq(before, after), "settled tool update completes without producing any event")
def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +saved : R.Ref<Maybe<&2, Update()>> <- R.new(Maybe<&2, Update()>, None{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +ended : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Named.Fixture <- create(mode, ExecuteCapture{mode, saved, started, release}, streams)
    +events : R.Ref<U32> <- R.new(U32, 0)
    +updates : R.Ref<U32> <- R.new(U32, 0)
    +listener : Listeners.Handler(H.EventValue(), Run.RunSignal(), String) <- C.create(~ObserveCapture, ~Input(), ~Emission.Emission<String>, ~observe, ObserveCapture{events, updates, ended})
    ignored : Listeners.Subscription<H.EventValue(), Run.RunSignal(), String> <- Agent.subscribe(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, Named.getAgent(fixture), listener)
    +reply : Chan(Unit) <- IO.fork(Unit, Behavior.prompt(Named.getAgent(fixture), "run tools"))
    waitBefore(mode, reply, started, ended)
    late(saved, events)
    finishPrompt(mode, reply, release)
    count : U32 <- R.read(U32, updates)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, U32.is_eq(mode, 0), 1, 0)), "only updates from still-active tool invocations reach subscribers")
    old : Maybe<&2, Update()> <- R.dispose(Maybe<&2, Update()>, saved)
    Named.dispose(fixture)
    C.dispose(Input(), Emission.Emission<String>, listener)
    old : U32 <- R.dispose(U32, events)
    old : U32 <- R.dispose(U32, updates)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS " ++ name)
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "should ignore tool updates after the tool execution settles")
    scenario(1, "should ignore a settled parallel tool update while another tool is still running")
