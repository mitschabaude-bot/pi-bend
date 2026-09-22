import Base
import ../src/agent.bend as Agent
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

def Context() -> Data: T.AgentContext<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String>
def BeforeInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String>, Run.RunSignal()>
def BeforeResult() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<Unit, Context()>>
def Before() -> Data: C.Callback<BeforeInput(), BeforeResult()>
def AfterInput() -> Data: T.ToolHookInput<T.AfterToolCallContext<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String>, Run.RunSignal()>
def AfterResult() -> Data: Result<&2, &2, String, Maybe<&2, T.AfterToolCallResult<Unit>>>
def After() -> Data: C.Callback<AfterInput(), AfterResult()>
type Bindings is Data:
  Bindings{before: Maybe<&2, Before()>, after: Maybe<&2, After()>}
def install(+agent: Owner.Owner(), bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{before, after}:
      do IO<Unit>:
        Agent.setBeforeToolCall(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, before)
        Agent.setAfterToolCall(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, after)
def read(+agent: Owner.Owner()) -> IO(Bindings):
  do IO<Bindings>:
    before : Maybe<&2, Before()> <- Agent.getBeforeToolCall(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    after : Maybe<&2, After()> <- Agent.getAfterToolCall(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    return Bindings{before, after}
def sameBefore(left: Maybe<&2, Before()>, right: Maybe<&2, Before()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(BeforeInput(), BeforeResult(), a, b)
    case _ _: False{}
def sameAfter(left: Maybe<&2, After()>, right: Maybe<&2, After()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(AfterInput(), AfterResult(), a, b)
    case _ _: False{}
def same(left: Bindings, right: Bindings) -> Bool:
  match left right:
    case Bindings{a, b} Bindings{c, d}: sameBefore(a, c) && sameAfter(b, d)
def live(signal: Run.RunSignal()) -> IO(Unit):
  do IO<Unit>:
    cancelled : Bool <- Abort.aborted(Unit, signal)
    Test.assertion(Bool.not(cancelled), "tool hooks receive the active uncancelled signal")
def replace(slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Maybe<&2, Bindings>) -> IO(Unit):
  match future:
    case None{}: IO.pure(Unit, Unit{})
    case Some{bindings}:
      do IO<Unit>:
        stored : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(stored)
        install(agent, bindings)
type Capture is Data:
  Capture{name: String, trace: R.Ref<String>, slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Maybe<&2, Bindings>}
def before(capture: Capture, input: BeforeInput()) -> IO(BeforeResult()):
  match capture input:
    case Capture{name, trace, slot, future} T.ToolHookInput{T.BeforeToolCallContext{_, Ai.ToolCall{"call", "echo", Unit{}, _, _}, Unit{}, context}, Some{signal}}:
      do IO<BeforeResult()>:
        live(signal)
        R.modify(String, Unit, trace, old => (old ++ "b" ++ name ++ ";", Unit{}))
        replace(slot, future)
        return Done{T.BeforeToolCallUpdate{Unit{}, context, None{}}}
    case _ _: IO.die(BeforeResult(), 1, "before hook did not receive validated tool context")
def content(text: String) -> List<&2, Ai.TextImageContent>: Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}
def after(capture: Capture, input: AfterInput()) -> IO(AfterResult()):
  match capture input:
    case Capture{+name, trace, _, _} T.ToolHookInput{T.AfterToolCallContext{_, Ai.ToolCall{"call", "echo", Unit{}, _, _}, Unit{}, T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"executed", None{}}} <> Nil{}, Unit{}, _, _}, False{}, _}, Some{signal}}:
      do IO<AfterResult()>:
        live(signal)
        R.modify(String, Unit, trace, old => (old ++ "a" ++ name ++ ";", Unit{}))
        return Done{Some{T.AfterToolCallResult{Some{content("patched-" ++ name)}, None{}, None{}, None{}, None{}}}}
    case _ _: IO.die(AfterResult(), 1, "after hook did not receive original successful result")
def execute(trace: R.Ref<String>, input: T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>) -> IO(Result<&2, &2, String, T.AgentToolResult<Unit>>):
  do IO<Result<&2, &2, String, T.AgentToolResult<Unit>>>:
    R.modify(String, Unit, trace, old => (old ++ "x;", Unit{}))
    return Done{T.AgentToolResult{content("executed"), Unit{}, None{}, None{}}}
type ProviderCapture is Data:
  ProviderCapture{calls: R.Ref<U32>, trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}
def toolTurn(+index: U32) -> Bool: U32.is_eq(index, 0) || U32.is_eq(index, 2) || U32.is_eq(index, 4)
def push(tool: Bool, stream: H.StreamValue()) -> IO(Unit):
  match tool:
    case True{}: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneToolUse{}, H.response(True{})})
    case False{}: Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case ProviderCapture{calls, trace, streams}:
      do IO<H.ProviderOutput()>:
        index : U32 <- R.modify(U32, U32, calls, old => SettingsTest.increment(old))
        R.modify(String, Unit, trace, old => (old ++ "p;", Unit{}))
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        push(toolTurn(index), stream)
        return Done{T.borrowedStream(Unit, Unit, String, stream)}
def create(capture: ProviderCapture, trace: R.Ref<String>) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~R.Ref<String>, ~T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~execute, trace)
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(Some{initial}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}


def outputs(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, _, _, False{}, _}}} <> rest: text ++ ";" ++ outputs(rest)
    case _ <> rest: outputs(rest)
def exercise(+agent: Owner.Owner(), +first: Bindings, +second: Bindings) -> IO(Unit):
  do IO<Unit>:
    empty : Bindings <- read(agent)
    Test.assertion(same(empty, Bindings{None{}, None{}}), "tool hooks initially absent")
    install(agent, first)
    assigned : Bindings <- read(agent)
    Test.assertion(same(assigned, first), "tool hook getters retain assigned handles")
    Behavior.prompt(agent, "first")
    replaced : Bindings <- read(agent)
    Test.assertion(same(replaced, second), "getter observes before-hook replacement")
    Behavior.prompt(agent, "next")
    install(agent, Bindings{None{}, None{}})
    cleared : Bindings <- read(agent)
    Test.assertion(same(cleared, Bindings{None{}, None{}}), "tool hooks can be cleared")
    Behavior.prompt(agent, "cleared")
    state : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(String.eq(outputs(Named.getMessages(state)), "patched-a;patched-b;executed;"), "after-hook replacements persist in transcript and clearing restores original result")
def bindings(+capture: Capture) -> IO(Bindings):
  do IO<Bindings>:
    beforeHook : Before() <- C.create(~Capture, ~BeforeInput(), ~BeforeResult(), ~before, capture)
    afterHook : After() <- C.create(~Capture, ~AfterInput(), ~AfterResult(), ~after, capture)
    return Bindings{Some{beforeHook}, Some{afterHook}}
def disposeBindings(bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{Some{before}, Some{after}}:
      do IO<Unit>:
        C.dispose(BeforeInput(), BeforeResult(), before)
        C.dispose(AfterInput(), AfterResult(), after)
    case _: IO.pure(Unit, Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +second : Bindings <- bindings(Capture{"b", trace, slot, None{}})
    +first : Bindings <- bindings(Capture{"a", trace, slot, Some{second}})
    +fixture : Named.Fixture <- create(ProviderCapture{calls, trace, streams}, trace)
    +agent : Owner.Owner() = Named.getAgent(fixture)
    R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
    exercise(agent, first, second)
    actual : String <- R.read(String, trace)
    Test.assertion(String.eq(actual, "p;ba;x;aa;p;p;bb;x;ab;p;p;x;p;"), "before/execution/after order and run capture match upstream")
    Named.dispose(fixture)
    disposeBindings(first)
    disposeBindings(second)
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    old : U32 <- R.dispose(U32, calls)
    old : String <- R.dispose(String, trace)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent before/after tool hook replacement, capture and transcript updates")
