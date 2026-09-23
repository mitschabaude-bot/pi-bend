import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as State
import ../src/agent.bend as Hooks
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/agent.bend as Failure
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-declarations.bend as Declarations
import ./agent-run.bend as H
import ./message-events.bend as Test

def Turn() -> Data: Options.Turn(Unit, Unit, String, String)
def Update() -> Data: Options.Update(Unit, Unit, String, String)
def PrepareResult() -> Data: Hooks.PrepareResult(Update(), String)
def StopInput() -> Data: T.ToolHookInput<Turn()>
def Finish() -> Data: T.FinishTurn(Unit, Unit, String, String)
def Finished() -> Data: Result<&2, &2, String, Maybe<&2, T.AgentTurnDecision>>
type Capture is Data:
  Capture{count: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}
def toolAssistant() -> Ai.AssistantMessage<Schema.Value, Unit>:
  Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{"tool-1", "noop", Schema.Null{}, None{}, None{}}} <> Nil{}, "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Failure.emptyUsage(), Ai.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(0)}
def finish(stream: H.StreamValue(), count: U32) -> IO(Unit):
  match count:
    case 0: Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.StreamDone{Ai.DoneToolUse{}, toolAssistant()})
    case _: Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
def increment(+old: U32) -> U32 & U32: (U32.add(old, 1), old)
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case Capture{count, streams}:
      do IO<H.ProviderOutput()>:
        previous : U32 <- R.modify(U32, U32, count, old => increment(old))
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        finish(stream, previous)
        return Done{T.borrowedStream(Unit, String, stream)}
def inspectSignal(slot: R.Ref<Bool>, value: Maybe<&2, Run.RunSignal()>) -> IO(Unit):
  match value:
    case Some{signal}:
      do IO<Unit>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(Bool.not(cancelled), "turn hook receives the live uncancelled signal")
        R.write(Bool, slot, True{})
    case _: Test.assertion(False{}, "turn hook signal is missing")
def prepare(seen: R.Ref<Bool>, value: Maybe<&2, Run.RunSignal()>) -> IO(PrepareResult()):
  do IO<PrepareResult()>:
    inspectSignal(seen, value)
    return Done{None{}}
def roles(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.LlmMessage{Ai.ToolResult{_}} <> rest: "t" ++ roles(rest)
    case message <> rest: H.role(message) ++ roles(rest)
def stop(seen: R.Ref<Bool>, input: StopInput()) -> IO(Finished()):
  match input:
    case T.ToolHookInput{T.AgentTurnContext{_, _, T.AgentContext{messages, _}, _}, signal}:
      do IO<Finished()>:
        inspectSignal(seen, signal)
        Test.assertion(String.eq(roles(messages), "suat"), "finishTurn receives system/user/assistant/toolResult context")
        return Done{Some{T.EndTurn{}}}
def execute(mode: U32, input: T.ToolExecutionInput<Unit>) -> IO(Result<&2, &2, String, T.AgentToolResult<Unit>>):
  IO.pure(Result<&2, &2, String, T.AgentToolResult<Unit>>, Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{Bool.pick(String, U32.is_eq(mode, 0), "ok", "tool complete"), None{}}} <> Nil{}, Unit{}, None{}, None{}}})
def options(+mode: U32, stream: Named.StreamFunction(), executor: Named.Executor(), prepareHook: Hooks.LegacyHook(Update(), String), stopHook: Finish()) -> Options.AgentOptions<Unit, Unit, String, String, Unit>:
  Options.AgentOptions{Some{State.AgentInitialState{None{}, None{}, None{}, Some{Declarations.tool("noop", "Noop tool", executor) <> Nil{}}, None{}}}, None{}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, Finish()>, U32.is_eq(mode, 1), Some{stopHook}, None{}), None{}, Bool.pick(Maybe<&2, Hooks.LegacyHook(Update(), String)>, U32.is_eq(mode, 0), Some{prepareHook}, None{}), None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
def create(+mode: U32, capture: Capture, prepareHook: Hooks.LegacyHook(Update(), String), stopHook: Finish()) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~U32, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~execute, mode)
    +registry : Named.Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, options(mode, stream, executor, prepareHook, stopHook), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}
def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +seen : R.Ref<Bool> <- R.new(Bool, False{})
    +prepareHook : Hooks.LegacyHook(Update(), String) <- C.create(~R.Ref<Bool>, ~Maybe<&2, Run.RunSignal()>, ~PrepareResult(), ~prepare, seen)
    +stopHook : Finish() <- C.create(~R.Ref<Bool>, ~StopInput(), ~Finished(), ~stop, seen)
    +fixture : Named.Fixture <- create(mode, Capture{count, streams}, prepareHook, stopHook)
    Behavior.prompt(Named.getAgent(fixture), "start")
    calls : U32 <- R.read(U32, count)
    sawSignal : Bool <- R.read(Bool, seen)
    Test.assertion(sawSignal && U32.is_eq(calls, Bool.pick(U32, U32.is_eq(mode, 0), 2, 1)), "AgentOptions forwards turn hook and preserves original request count")
    Named.dispose(fixture)
    C.dispose(Maybe<&2, Run.RunSignal()>, PrepareResult(), prepareHook)
    C.dispose(StopInput(), Finished(), stopHook)
    old : U32 <- R.dispose(U32, count)
    old : Bool <- R.dispose(Bool, seen)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS " ++ name)
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "keeps legacy prepareNextTurn signal callback behavior")
    scenario(1, "forwards finishTurn through AgentOptions with the active abort signal")
