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
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-settings.bend as SettingsTest
import ./agent-run.bend as H
import ./message-events.bend as Test

def KeyResult() -> Data: Result<&2, &2, String, Maybe<&2, String>>
def KeyCallback() -> Data: C.Callback<String, KeyResult()>
type KeyCapture is Data:
  KeyCapture{mode: U32, trace: R.Ref<String>}
def keyName(mode: U32) -> String:
  match mode:
    case 0: "a"
    case 1: "b"
    case 2: "n"
    case _: "e"
def keyResult(mode: U32) -> KeyResult():
  match mode:
    case 0: Done{Some{"fixture-a"}}
    case 1: Done{Some{"fixture-b"}}
    case 2: Done{None{}}
    case _: Fail{"key lookup failed"}
def key(capture: KeyCapture, provider: String) -> IO(KeyResult()):
  match capture:
    case KeyCapture{+mode, trace}:
      do IO<KeyResult()>:
        Test.assertion(String.eq(provider, "unknown"), "API-key callback receives the model provider ID")
        R.modify(String, Unit, trace, old => (old ++ "k" ++ keyName(mode) ++ ";", Unit{}))
        return keyResult(mode)
def requestKey(config: H.Config()) -> String:
  match config:
    case T.AgentLoopConfig{_, _, Some{"fixture-a"}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: "a"
    case T.AgentLoopConfig{_, _, Some{"fixture-b"}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: "b"
    case T.AgentLoopConfig{_, _, None{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: "-"
    case _: "unexpected"
type ProviderCapture is Data:
  ProviderCapture{slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: KeyCallback(), calls: R.Ref<U32>, trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}
def replaceFirst(index: U32, slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: KeyCallback()) -> IO(Unit):
  match index:
    case 0:
      do IO<Unit>:
        stored : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(stored)
        Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, Some{future})
    case _: IO.pure(Unit, Unit{})
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case ProviderCapture{slot, future, calls, trace, streams} T.StreamInput{_, _, Some{config}}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- R.modify(U32, U32, calls, old => SettingsTest.increment(old))
        R.modify(String, Unit, trace, old => (old ++ "p" ++ requestKey(config) ++ ";", Unit{}))
        replaceFirst(index, slot, future)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        SettingsTest.push(index, stream)
        return Done{T.borrowedStream(Unit, String, stream)}
    case _ _: IO.die(H.ProviderOutput(), 1, "provider options missing")
def create(capture: ProviderCapture) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +registry : Named.Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Unit, Unit, String, String> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, Named.options(Some{initial}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}
def same(value: Maybe<&2, KeyCallback()>, expected: KeyCallback()) -> Bool:
  match value:
    case Some{actual}: C.same(String, KeyResult(), actual, expected)
    case _: False{}
def error(state: Named.Snapshot()) -> String:
  match state:
    case T.AgentState{_, _, _, _, _, _, _, value}: Maybe.default(&2, String, value, "none")
def captureRuns(+agent: Owner.Owner(), first: KeyCallback(), +second: KeyCallback()) -> IO(Unit):
  do IO<Unit>:
    absent : Maybe<&2, KeyCallback()> <- Agent.getGetApiKey(Unit, Unit, String, String, Unit, agent)
    Test.assertion(Maybe.is_none(&2, KeyCallback(), absent), "API-key callback is initially absent")
    Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, Some{first})
    Behavior.prompt(agent, "first")
    current : Maybe<&2, KeyCallback()> <- Agent.getGetApiKey(Unit, Unit, String, String, Unit, agent)
    Test.assertion(same(current, second), "getter sees replacement while the previous run retained its callback")
    Behavior.prompt(agent, "next")
    Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, None{})
    cleared : Maybe<&2, KeyCallback()> <- Agent.getGetApiKey(Unit, Unit, String, String, Unit, agent)
    Test.assertion(Maybe.is_none(&2, KeyCallback(), cleared), "API-key callback can be cleared")
    Behavior.prompt(agent, "cleared")
def failureRuns(+agent: Owner.Owner(), missing: KeyCallback(), failed: KeyCallback(), second: KeyCallback(), +calls: R.Ref<U32>) -> IO(Unit):
  do IO<Unit>:
    Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, Some{missing})
    Behavior.prompt(agent, "no key")
    before : U32 <- R.read(U32, calls)
    Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, Some{failed})
    Behavior.prompt(agent, "failure")
    after : U32 <- R.read(U32, calls)
    failedState : Named.Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(U32.is_eq(before, after) && String.eq(error(failedState), "key lookup failed"), "key failure skips provider and reaches Agent failure recovery")
    Agent.setGetApiKey(Unit, Unit, String, String, Unit, agent, Some{second})
    Behavior.prompt(agent, "recovered")
    recovered : Named.Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(String.eq(error(recovered), "none"), "later successful prompt clears previous key error")
def borrowed(value: KeyResult()) -> Bool:
  match value:
    case Done{Some{"fixture-a"}}: True{}
    case _: False{}
def main() -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +first : KeyCallback() <- C.create(~KeyCapture, ~String, ~KeyResult(), ~key, KeyCapture{0, trace})
    +second : KeyCallback() <- C.create(~KeyCapture, ~String, ~KeyResult(), ~key, KeyCapture{1, trace})
    +missing : KeyCallback() <- C.create(~KeyCapture, ~String, ~KeyResult(), ~key, KeyCapture{2, trace})
    +failed : KeyCallback() <- C.create(~KeyCapture, ~String, ~KeyResult(), ~key, KeyCapture{3, trace})
    +fixture : Named.Fixture <- create(ProviderCapture{slot, second, calls, trace, streams})
    +agent : Owner.Owner() = Named.getAgent(fixture)
    R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
    captureRuns(agent, first, second)
    failureRuns(agent, missing, failed, second, calls)
    observed : String <- R.read(String, trace)
    Test.assertion(String.eq(observed, "ka;pa;ka;pa;kb;pb;p-;kn;p-;ke;kb;pb;"), "key resolution/callback capture/clearing/failure order matches upstream")
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    Named.dispose(fixture)
    stillAlive : KeyResult() <- C.call(String, KeyResult(), first, "unknown")
    Test.assertion(borrowed(stillAlive), "replaced key callback remains caller-owned")
    C.dispose(String, KeyResult(), first)
    C.dispose(String, KeyResult(), second)
    C.dispose(String, KeyResult(), missing)
    C.dispose(String, KeyResult(), failed)
    old : U32 <- R.dispose(U32, calls)
    old : String <- R.dispose(String, trace)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent API-key callback capture, clearing, missing keys and recovery")
