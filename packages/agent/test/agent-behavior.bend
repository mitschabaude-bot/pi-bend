import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-run.bend as H
import ./message-events.bend as Test

type Capture is Data:
  Capture{calls: R.Ref<U32>, sessions: R.Ref<List<&2, Maybe<&2, String>>>, requests: R.Ref<List<&2, String>>, streams: R.Ref<List<&2, H.StreamValue()>>}
type Fixture is Data:
  Fixture{agent: Owner.Owner(), stream: Named.StreamFunction(), validate: Named.Validator(), fallback: Named.Fallback(), capture: Capture}
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case Capture{calls, sessions, requests, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, Some{config}}:
      do IO<H.ProviderOutput()>:
        R.modify(U32, Unit, calls, old => (U32.add(old, 1), Unit{}))
        R.modify(List<&2, Maybe<&2, String>>, Unit, sessions, old => (Agent.configSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, config) <> old, Unit{}))
        R.modify(List<&2, String>, Unit, requests, old => (H.llmRoles(messages) <> old, Unit{}))
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
        return Done{stream}
    case _ _: IO.die(H.ProviderOutput(), 1, "provider did not receive request options")
def options(stream: Maybe<&2, Named.StreamFunction()>, session: Maybe<&2, String>) -> Options.AgentOptions<Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit>:
  Options.AgentOptions{None{}, None{}, None{}, stream, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, session, None{}, None{}, None{}, None{}}
def create(+legacy: Bool, session: Maybe<&2, String>) -> IO(Fixture):
  do IO<Fixture>:
    calls : R.Ref<U32> <- R.new(U32, 0)
    sessions : R.Ref<List<&2, Maybe<&2, String>>> <- R.new(List<&2, Maybe<&2, String>>, Nil{})
    requests : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +capture : Capture = Capture{calls, sessions, requests, streams}
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validate : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 0)
    +fallback : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    Provider.setDefaultStreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, fallback, Some{stream})
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, options(Bool.pick(Maybe<&2, Named.StreamFunction()>, legacy, None{}, Some{stream}), session), fallback, validate, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Fixture{agent, stream, validate, fallback, capture}
def getAgent(fixture: Fixture) -> Owner.Owner():
  match fixture:
    case Fixture{agent, _, _, _, _}: agent
def count(fixture: Fixture) -> IO(U32):
  match fixture:
    case Fixture{_, _, _, _, Capture{calls, _, _, _}}: R.read(U32, calls)
def readSessions(fixture: Fixture) -> IO(List<&2, Maybe<&2, String>>):
  match fixture:
    case Fixture{_, _, _, _, Capture{_, values, _, _}}:
      do IO<List<&2, Maybe<&2, String>>>:
        values : List<&2, Maybe<&2, String>> <- R.read(List<&2, Maybe<&2, String>>, values)
        return List.reverse(&2, Maybe<&2, String>, values)
def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{agent, stream, validate, fallback, Capture{calls, sessions, requests, streams}}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
        C.dispose(Loop.ToolValidationInput<Schema.Value, Unit, Unit>, Result<&2, &2, String, Unit>, validate)
        Provider.dispose(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, fallback)
        old : U32 <- R.dispose(U32, calls)
        old : List<&2, Maybe<&2, String>> <- R.dispose(List<&2, Maybe<&2, String>>, sessions)
        old : List<&2, String> <- R.dispose(List<&2, String>, requests)
        all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
        H.disposeStreams(all)
def success(value: Owner.Outcome()) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "Agent method unexpectedly failed")
def prompt(agent: Owner.Owner(), text: String) -> IO(Unit):
  do IO<Unit>:
    result : Owner.Outcome() <- Agent.prompt(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Text{text, Nil{}})
    success(result)
def continuation(agent: Owner.Owner()) -> IO(Unit):
  do IO<Unit>:
    result : Owner.Outcome() <- Agent.continueRun(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)
    success(result)
def legacyDefault() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(True{}, None{})
    prompt(getAgent(fixture), "Hello")
    calls : U32 <- count(fixture)
    Test.assertion(U32.is_eq(calls, 1), "legacy caller uses the configured default exactly once")
    dispose(fixture)
    IO.print("PASS uses the configured default when a legacy caller omits streamFn")
def sessionValue(value: Maybe<&2, String>, expected: String) -> Bool:
  match value:
    case Some{actual}: String.eq(actual, expected)
    case _: False{}
def sessionValues(values: List<&2, Maybe<&2, String>>) -> Bool:
  match values:
    case Some{"session-abc"} <> Some{"session-def"} <> Nil{}: True{}
    case _: False{}
def sessionId() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(False{}, Some{"session-abc"})
    +agent : Owner.Owner() = getAgent(fixture)
    prompt(agent, "hello")
    Agent.setSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Some{"session-def"})
    value : Maybe<&2, String> <- Agent.getSessionId(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(sessionValue(value, "session-def"), "session getter observes assigned value")
    prompt(agent, "hello again")
    received : List<&2, Maybe<&2, String>> <- readSessions(fixture)
    Test.assertion(sessionValues(received), "both requests receive their configured session ID")
    dispose(fixture)
    IO.print("PASS forwards sessionId to streamFunction options")
def initialHistory() -> H.Messages(): H.user("Initial") <> T.LlmMessage{Ai.Assistant{H.assistant()}} <> Nil{}
def followUpPresent(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"Queued follow-up"}, _}}} <> _: True{}
    case _ <> rest: followUpPresent(rest)
    case Nil{}: False{}
def assistantTail(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.Assistant{_}} <> Nil{}: True{}
    case _ <> rest: assistantTail(rest)
    case Nil{}: False{}
def followUp() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(False{}, None{})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.replaceMessages(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, initialHistory())
    Agent.followUp(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("Queued follow-up"))
    continuation(agent)
    value : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    +messages : H.Messages() = Named.getMessages(value)
    Test.assertion(followUpPresent(messages) && assistantTail(messages), "queued follow-up is processed and assistant response ends history")
    dispose(fixture)
    IO.print("PASS continue() should process queued follow-up messages after an assistant turn")
def steering() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(False{}, None{})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.replaceMessages(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, initialHistory())
    Agent.steer(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("Steering 1"))
    Agent.steer(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("Steering 2"))
    continuation(agent)
    value : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    calls : U32 <- count(fixture)
    Test.assertion(String.eq(H.roles(Named.getMessages(value)), "uauaua") && U32.is_eq(calls, 2), "one-at-a-time steering preserves alternating user/assistant history and two requests")
    dispose(fixture)
    IO.print("PASS continue() should keep one-at-a-time steering semantics from assistant tail")
def main() -> IO(Unit):
  do IO<Unit>:
    legacyDefault()
    sessionId()
    followUp()
    steering()
