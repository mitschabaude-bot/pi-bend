import Base
import ../../runtime/src/record.bend as Record
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as Run
import ../src/agent.bend as State
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Emission
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/model-api.bend as Api
import ../../ai/test/model-types.bend as Models
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/string.bend as Set
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./agent-owner.bend as Owner
import ./agent-run.bend as H
import ./message-events.bend as Test

def Snapshot() -> Data: T.AgentState<Unit, Unit, String, String>
def Tool() -> Data: T.AgentTool<Unit, String>
def Executor() -> Data: C.Callback<T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>>
def Validator() -> Data: C.Callback<Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>>
def StreamFunction() -> Data: T.StreamFn(Unit, Unit, H.Config(), String)
def Fallback() -> Data: Provider.Registry(Unit, Unit, H.Config(), String)
type Fixture is Data:
  Fixture{agent: Owner.Owner(), stream: StreamFunction(), validate: Validator(), execute: Executor(), fallback: Fallback()}
def unused(unused: Unit, input: H.ProviderInput()) -> IO(H.ProviderOutput()): IO.die(H.ProviderOutput(), 1, "state test unexpectedly invoked the provider")
def initial(mode: U32, execute: Executor()) -> Maybe<&2, State.AgentInitialState<Unit, Unit, String, String>>:
  match mode:
    case 1: Some{State.AgentInitialState{Some{"You are a helpful assistant."}, Some{Models.model(Ai.OpenAIResponsesApi{}, None{})}, Some{Ai.Thinking{Ai.Low{}}}, None{}, None{}}}
    case 2: Some{State.AgentInitialState{Some{"You are helpful."}, None{}, None{}, H.tools(9, execute), None{}}}
    case 3: Some{State.AgentInitialState{Some{"You are helpful."}, None{}, None{}, H.tools(9, execute), Some{H.user("old") <> Nil{}}}}
    case _: None{}
def options(initial: Maybe<&2, State.AgentInitialState<Unit, Unit, String, String>>, stream: StreamFunction()) -> Options.AgentOptions<Unit, Unit, String, String, Unit>:
  Options.AgentOptions{initial, None{}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
def create(mode: U32) -> IO(Fixture):
  do IO<Fixture>:
    +stream : StreamFunction() <- C.create(~Unit, ~H.ProviderInput(), ~H.ProviderOutput(), ~unused, Unit{})
    +validate : Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 0)
    +execute : Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +fallback : Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    created : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, options(initial(mode, execute), stream), fallback, validate, Unit{})
    value : Owner.Owner() <- Owner.requireOwner(created)
    return Fixture{value, stream, validate, execute, fallback}
def getAgent(fixture: Fixture) -> Owner.Owner():
  match fixture:
    case Fixture{agent, _, _, _, _}: agent
def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{agent, stream, validate, execute, fallback}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, String, String, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
        C.dispose(Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>, validate)
        C.dispose(T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>, execute)
        Provider.dispose(Unit, Unit, H.Config(), String, fallback)
def comparison(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{EQ{}}: True{}
    case _: False{}
def equals(value: F64, expected: U32) -> Bool: comparison(F.compare(value, F.fromU32(expected)))
def completeModel(model: Ai.Model<Ai.JsonValue>, expectedApi: String) -> Bool:
  match model:
    case Ai.Model{"test", "Test", api, "test-provider", "https://example.test", True{}, None{}, Ai.InputText{} <> Ai.InputImage{} <> Nil{}, _, Ai.ModelCost{a, b, c, d, None{}}, _, context, output, None{}, None{}, None{}}: String.eq(Api.name(api), expectedApi) && equals(a, 0) && equals(b, 0) && equals(c, 0) && equals(d, 0) && equals(context, 128000) && equals(output, 4096)
    case _: False{}
def emptyPending(values: Set.StringSet) -> Bool: Nat.is_eq(List.length(&2, String, Set.toList(values)), 0n)
def defaultState(value: Snapshot()) -> Bool:
  match value:
    case T.AgentState{None{}, Ai.Off{}, Nil{}, Nil{}, False{}, None{}, pending, None{}}: emptyPending(pending)
    case _: False{}
def customState(value: Snapshot()) -> Bool:
  match value:
    case T.AgentState{Some{model}, Ai.Thinking{Ai.Low{}}, _, T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"You are a helpful assistant."}, _, _, _, stamp}}} <> Nil{}, _, _, _, _}: completeModel(model, "openai-responses") && equals(stamp, 0)
    case _: False{}
def declaredState(value: Snapshot()) -> Bool:
  match value:
    case T.AgentState{_, _, _, T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"You are helpful."}, _, Some{Ai.Tool{"echo", _, _, _} <> Nil{}}, _, _}}} <> _, _, _, _, _}: True{}
    case _: False{}
def checkConstructor(mode: U32, value: Snapshot()) -> IO(Unit):
  match mode:
    case 0: Test.assertion(defaultState(value), "complete default Agent state")
    case 1: Test.assertion(customState(value), "custom model, low thinking and initial system message")
    case _: Test.assertion(declaredState(value), "initial prompt and executable tools become transcript declarations")
def constructor(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(mode)
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, getAgent(fixture))
    checkConstructor(mode, value)
    dispose(fixture)
    IO.print("PASS " ++ name)
def thinking(value: Snapshot(), expected: String) -> Bool:
  match value:
    case T.AgentState{_, Ai.Thinking{Ai.Low{}}, _, _, _, _, _, _}: String.eq(expected, "low")
    case T.AgentState{_, Ai.Thinking{Ai.High{}}, _, _, _, _, _, _}: String.eq(expected, "high")
    case _: False{}
def countEvent(count: R.Ref<U32>, input: Listeners.Input<H.EventValue()>) -> IO(Emission.Emission<String>):
  do IO<Emission.Emission<String>>:
    R.modify(U32, Unit, count, old => (U32.add(old, 1), Unit{}))
    return Emission.EmissionReady{Done{Unit{}}}
def subscription() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(0)
    +agent : Owner.Owner() = getAgent(fixture)
    +count : R.Ref<U32> <- R.new(U32, 0)
    +callback : Listeners.Handler(H.EventValue(), String) <- C.create(~R.Ref<U32>, ~Listeners.Input<H.EventValue()>, ~Emission.Emission<String>, ~countEvent, count)
    token : Listeners.Subscription<H.EventValue(), String> <- Agent.subscribe(Unit, Unit, String, String, Unit, agent, callback)
    calls : U32 <- R.read(U32, count)
    Test.assertion(U32.is_eq(calls, 0), "subscribe emits no initial event")
    Agent.setThinkingLevel(Unit, Unit, String, String, Unit, agent, Ai.Thinking{Ai.Low{}})
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    calls : U32 <- R.read(U32, count)
    Test.assertion(thinking(value, "low") && U32.is_eq(calls, 0), "state update takes effect without emitting")
    Listeners.unsubscribe(H.EventValue(), String, token)
    Agent.setThinkingLevel(Unit, Unit, String, String, Unit, agent, Ai.Thinking{Ai.High{}})
    calls : U32 <- R.read(U32, count)
    Test.assertion(U32.is_eq(calls, 0), "unsubscribe and later mutation emit no event")
    dispose(fixture)
    C.dispose(Listeners.Input<H.EventValue()>, Emission.Emission<String>, callback)
    old : U32 <- R.dispose(U32, count)
    IO.print("PASS should subscribe to events")
def getMessages(value: Snapshot()) -> H.Messages():
  match value:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages
def enqueue(agent: Owner.Owner(), follow: Bool) -> IO(Unit):
  match follow:
    case False{}: Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("Steering message"))
    case True{}: Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("Follow-up message"))
def queueCase(follow: Bool, name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(0)
    +agent : Owner.Owner() = getAgent(fixture)
    enqueue(agent, follow)
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(Nat.is_eq(List.length(&2, H.Message(), getMessages(value)), 0n), "queued messages are not inserted into the transcript")
    queued : Bool <- Agent.hasQueuedMessages(Unit, Unit, String, String, Unit, agent)
    Test.assertion(queued, "queue query observes the queued message")
    Agent.clearAllQueues(Unit, Unit, String, String, Unit, agent)
    queued : Bool <- Agent.hasQueuedMessages(Unit, Unit, String, String, Unit, agent)
    Test.assertion(Bool.not(queued), "queue clearing preserves empty transcript")
    dispose(fixture)
    IO.print("PASS " ++ name)
def abortIdle() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(0)
    Agent.abort(Unit, Unit, String, String, Unit, getAgent(fixture))
    dispose(fixture)
    IO.print("PASS should handle abort controller")

def executor(fixture: Fixture) -> Executor():
  match fixture:
    case Fixture{_, _, _, execute, _}: execute
def changedModel(value: Snapshot()) -> Bool:
  match value:
    case T.AgentState{Some{model}, _, _, _, _, _, _, _}: completeModel(model, "google-generative-ai")
    case _: False{}
def toolList(execute: Executor()) -> List<&2, Tool()>:
  T.AgentTool{"test", "test tool", Schema.ObjectValue{Record.Record{Nil{}}}, None{}, "Test", None{}, execute, None{}, None{}} <> Nil{}
def exactTools(values: List<&2, Tool()>, expected: Executor()) -> Bool:
  match values:
    case T.AgentTool{"test", "test tool", Schema.ObjectValue{Record.Record{Nil{}}}, None{}, "Test", None{}, execute, None{}, None{}} <> Nil{}:
      C.same(T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>, execute, expected)
    case _: False{}
def changedTools(value: Snapshot(), expected: Executor()) -> Bool:
  match value:
    case T.AgentState{_, _, tools, _, _, _, _, _}: exactTools(tools, expected)
def singleUser(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"Hello"}, stamp}}} <> Nil{}: equals(stamp, 0)
    case _: False{}
def appended(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"Hello"}, stamp}}} <> T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"answer", None{}}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} <> Nil{}: equals(stamp, 0)
    case _: False{}
def cleared(value: Snapshot()) -> Bool:
  match value:
    case T.AgentState{_, Ai.Thinking{Ai.High{}}, _, Nil{}, False{}, None{}, pending, None{}}: emptyPending(pending)
    case _: False{}
def mutateConfiguration(+agent: Owner.Owner(), +execute: Executor()) -> IO(Unit):
  do IO<Unit>:
    Agent.setModel(Unit, Unit, String, String, Unit, agent, Models.model(Ai.GoogleGenerativeAiApi{}, None{}))
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(changedModel(value), "setModel retains the complete supplied model value")
    Agent.setThinkingLevel(Unit, Unit, String, String, Unit, agent, Ai.Thinking{Ai.High{}})
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(thinking(value, "high"), "setThinkingLevel updates thinking")
    +suppliedTools : List<&2, Tool()> = toolList(execute)
    Agent.setTools(Unit, Unit, String, String, Unit, agent, suppliedTools)
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(changedTools(value, execute), "setTools retains declarations and borrowed callbacks")
    Test.assertion(exactTools(suppliedTools, execute), "supplied immutable tools stay unchanged")
def mutateMessages(+agent: Owner.Owner()) -> IO(Unit):
  do IO<Unit>:
    +suppliedMessages : H.Messages() = H.user("Hello") <> Nil{}
    Agent.replaceMessages(Unit, Unit, String, String, Unit, agent, suppliedMessages)
    +retained : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(singleUser(getMessages(retained)), "replaceMessages retains the supplied contents")
    Agent.appendMessage(Unit, Unit, String, String, Unit, agent, T.LlmMessage{Ai.Assistant{H.assistant()}})
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(appended(getMessages(value)), "appendMessage appends the complete supplied message")
    Agent.clearMessages(Unit, Unit, String, String, Unit, agent)
    value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(cleared(value), "clearMessages preserves thinking and runtime-owned fields")
    Test.assertion(singleUser(getMessages(retained)) && singleUser(suppliedMessages), "immutable message inputs and retained snapshots survive later edits")
def mutators() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(0)
    +agent : Owner.Owner() = getAgent(fixture)
    original : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    mutateConfiguration(agent, executor(fixture))
    mutateMessages(agent)
    Test.assertion(defaultState(original), "previous Agent state snapshots remain immutable")
    dispose(fixture)
    IO.print("PASS should update state with mutators")
def isAll(value: T.QueueMode) -> Bool:
  match value:
    case T.All{}: True{}
    case _: False{}
def queueModes() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(0)
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.setSteeringMode(Unit, Unit, String, String, Unit, agent, T.All{})
    steering : T.QueueMode <- Agent.getSteeringMode(Unit, Unit, String, String, Unit, agent)
    follow : T.QueueMode <- Agent.getFollowUpMode(Unit, Unit, String, String, Unit, agent)
    Test.assertion(isAll(steering) && Bool.not(isAll(follow)), "steering mode update leaves follow-up mode unchanged")
    Agent.setFollowUpMode(Unit, Unit, String, String, Unit, agent, T.All{})
    follow : T.QueueMode <- Agent.getFollowUpMode(Unit, Unit, String, String, Unit, agent)
    Test.assertion(isAll(follow), "follow-up mode is readable after setting")
    dispose(fixture)
    IO.print("PASS native Agent queue-mode accessors")
def resetResult(value: Result<&2, &2, String, Unit>) -> Bool:
  match value:
    case Done{_}: True{}
    case _: False{}
def resetBaseline() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(3)
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("queued"))
    result : Result<&2, &2, String, Unit> <- Agent.reset(Unit, Unit, String, String, Unit, agent)
    +value : Snapshot() <- Agent.state(Unit, Unit, String, String, Unit, agent)
    Test.assertion(resetResult(result) && Nat.is_eq(List.length(&2, H.Message(), getMessages(value)), 1n) && declaredState(value), "reset restores the exact prompt and tool declaration baseline")
    queued : Bool <- Agent.hasQueuedMessages(Unit, Unit, String, String, Unit, agent)
    Test.assertion(Bool.not(queued), "reset clears queued messages")
    dispose(fixture)
    IO.print("PASS restores the transcript baseline when reset")
def main() -> IO(Unit):
  do IO<Unit>:
    constructor(0, "should create an agent instance with default state")
    constructor(1, "should create an agent instance with custom initial state")
    constructor(2, "converts initial prompt and tools into transcript state")
    resetBaseline()
    subscription()
    mutators()
    queueCase(False{}, "should support steering message queue")
    queueCase(True{}, "should support follow-up message queue")
    abortIdle()
    queueModes()
