import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as State
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as Record
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-run.bend as H
import ./message-events.bend as Test

# Upstream agent.test.ts cases for queue selection around continue(),
# finishTurn and peekQueuedMessages. Requests are recorded as the user texts
# the provider received.

def Texts() -> Data: List<&2, String>
def Finish() -> Data: T.FinishTurn(Unit, Unit, String, String)
def FinishInput() -> Data: T.ToolHookInput<Options.Turn(Unit, Unit, String, String)>
def Finished() -> Data: Result<&2, &2, String, Maybe<&2, T.AgentTurnDecision>>

# reason: 0 stop, 1 error, 2 aborted. finish: 0 absent, 1 continue, 2 end.
type Setup is Data:
  Setup{messages: H.Messages(), steering: T.QueueMode, followUp: T.QueueMode, finish: U32, reason: U32}
type Capture is Data:
  Capture{reason: U32, requests: R.Ref<List<&2, Texts()>>, streams: R.Ref<List<&2, H.StreamValue()>>}
type Fixture is Data:
  Fixture{agent: Owner.Owner(), stream: Named.StreamFunction(), validate: Named.Validator(), fallback: Named.Fallback(), finish: Finish(), capture: Capture}

def userTexts(messages: List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, Unit>>) -> Texts():
  match messages:
    case Nil{}: Nil{}
    case Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> rest: text <> userTexts(rest)
    case _ <> rest: userTexts(rest)

def queuedTexts(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}} <> rest: text ++ "|" ++ queuedTexts(rest)
    case _ <> rest: "?|" ++ queuedTexts(rest)

def mentions(texts: Texts(), +text: String) -> Bool:
  match texts:
    case Nil{}: False{}
    case value <> rest: String.eq(value, text) || mentions(rest, text)

def failed(reason: Ai.StopReason, +text: String) -> Ai.AssistantMessage<Schema.Value, Unit>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Agent.emptyUsage(), reason, None{}, Some{text}, None{}, None{}, F.fromU32(0)}

def response(+reason: U32) -> Ai.AssistantMessageEvent<Schema.Value, Unit>:
  match reason:
    case 1: Ai.StreamError{Ai.ErrorError{}, failed(Ai.Error{}, "error")}
    case 2: Ai.StreamError{Ai.ErrorAborted{}, failed(Ai.Aborted{}, "aborted")}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant()}

def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case Capture{reason, requests, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        R.modify(List<&2, Texts()>, Unit, requests, old => (userTexts(messages) <> old, Unit{}))
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, response(reason))
        return Done{T.borrowedStream(Unit, String, stream)}

def decision(mode: U32) -> Maybe<&2, T.AgentTurnDecision>:
  match mode:
    case 1: Some{T.ContinueTurn{}}
    case _: Some{T.EndTurn{}}

def decide(mode: U32, input: FinishInput()) -> IO(Finished()): IO.pure(Finished(), Done{decision(mode)})

def options(setup: Setup, stream: Named.StreamFunction(), finish: Finish()) -> Options.AgentOptions<Unit, Unit, String, String, Unit>:
  match setup:
    case Setup{messages, steering, followUp, mode, _}:
      Options.AgentOptions{Some{State.AgentInitialState{None{}, None{}, None{}, None{}, Some{messages}}}, None{}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, Finish()>, U32.is_eq(mode, 0), None{}, Some{finish}), None{}, None{}, None{}, Some{steering}, Some{followUp}, None{}, None{}, None{}, None{}, None{}}

def create(+setup: Setup) -> IO(Fixture):
  match setup:
    case Setup{_, _, _, mode, reason}:
      do IO<Fixture>:
        requests : R.Ref<List<&2, Texts()>> <- R.new(List<&2, Texts()>, Nil{})
        streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
        +capture : Capture = Capture{reason, requests, streams}
        +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
        +finish : Finish() <- C.create(~U32, ~FinishInput(), ~Finished(), ~decide, mode)
        +validate : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 0)
        +fallback : Named.Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
        result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, options(setup, stream, finish), fallback, validate, Unit{})
        agent : Owner.Owner() <- Owner.requireOwner(result)
        return Fixture{agent, stream, validate, fallback, finish, capture}

def getAgent(fixture: Fixture) -> Owner.Owner():
  match fixture:
    case Fixture{agent, _, _, _, _, _}: agent

def recorded(fixture: Fixture) -> IO(List<&2, Texts()>):
  match fixture:
    case Fixture{_, _, _, _, _, Capture{_, requests, _}}:
      do IO<List<&2, Texts()>>:
        values : List<&2, Texts()> <- R.read(List<&2, Texts()>, requests)
        return List.reverse(&2, Texts(), values)

def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{agent, stream, validate, fallback, finish, Capture{_, requests, streams}}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, String, String, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
        C.dispose(FinishInput(), Finished(), finish)
        C.dispose(Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>, validate)
        Provider.dispose(Unit, Unit, H.Config(), String, fallback)
        old : List<&2, Texts()> <- R.dispose(List<&2, Texts()>, requests)
        all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
        H.disposeStreams(all)

def continued(agent: Owner.Owner()) -> IO(Owner.Outcome()):
  Agent.continueRun(~Unit, ~Unit, ~String, ~String, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)

def succeeded(result: Owner.Outcome()) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "Agent run unexpectedly failed")

def peeked(agent: Owner.Owner()) -> IO(String):
  do IO<String>:
    messages : H.Messages() <- Agent.peekQueuedMessages(Unit, Unit, String, String, Unit, agent)
    return queuedTexts(messages)

# Both queues keep their messages: steering is previewed first, then follow-up.
def checkQueues(+agent: Owner.Owner(), steering: String, followUp: String) -> IO(Unit):
  do IO<Unit>:
    +first : String <- peeked(agent)
    Test.assertion(String.eq(first, steering ++ "|"), "the steering queue is kept and previewed first: " ++ first)
    Agent.clearSteeringQueue(Unit, Unit, String, String, Unit, agent)
    +second : String <- peeked(agent)
    Test.assertion(String.eq(second, followUp ++ "|"), "the follow-up queue is kept: " ++ second)

def modeName(mode: T.QueueMode) -> String:
  match mode:
    case T.All{}: "all"
    case T.OneAtATime{}: "one-at-a-time"

def firstRequest(requests: List<&2, Texts()>) -> Texts():
  match requests:
    case first <> _: first
    case Nil{}: Nil{}

def secondRequest(requests: List<&2, Texts()>) -> Texts():
  match requests:
    case _ <> second <> _: second
    case _: Nil{}

# The first request takes "first"; one-at-a-time defers "second" to a second
# request, all takes both at once.
def checkSteeringMode(mode: T.QueueMode, +requests: List<&2, Texts()>, first: String, +second: String) -> IO(Unit):
  match mode:
    case T.OneAtATime{}: Test.assertion(Nat.is_eq(List.length(&2, Texts(), requests), 2n) && mentions(firstRequest(requests), first) && Bool.not(mentions(firstRequest(requests), second)) && mentions(secondRequest(requests), second), "one-at-a-time steering takes one message per request")
    case T.All{}: Test.assertion(Nat.is_eq(List.length(&2, Texts(), requests), 1n) && mentions(firstRequest(requests), first) && mentions(firstRequest(requests), second), "all steering takes both messages in one request")

def assistantTailFallback(+mode: T.QueueMode) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{H.user("Initial") <> T.LlmMessage{Ai.Assistant{H.assistant()}} <> Nil{}, mode, T.OneAtATime{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("Steering 1"))
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("Steering 2"))
    result : Owner.Outcome() <- continued(agent)
    succeeded(result)
    requests : List<&2, Texts()> <- recorded(fixture)
    checkSteeringMode(mode, requests, "Steering 1", "Steering 2")
    dispose(fixture)
    IO.print("PASS continue() keeps " ++ modeName(mode) ++ " steering semantics for assistant-tail fallback")

def rejected(result: Owner.Outcome()) -> IO(Unit):
  match result:
    case Fail{Agent.ClaimFailed{message}}: Test.assertion(String.eq(message, "No messages to continue from"), "continuation from an empty context is rejected")
    case _: Test.assertion(False{}, "continuation from an empty context is rejected")

def systemOnly() -> H.Messages():
  T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"system only"}, None{}, None{}, None{}, F.fromU32(1)}}} <> Nil{}

def rejectsEmpty(messages: H.Messages(), name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{messages, T.OneAtATime{}, T.OneAtATime{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("steering"))
    Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("follow-up"))
    result : Owner.Outcome() <- continued(agent)
    rejected(result)
    checkQueues(agent, "steering", "follow-up")
    dispose(fixture)
    IO.print("PASS rejects a queued continuation from " ++ name ++ " context without draining queues")

def toolResultTail() -> H.Messages():
  H.user("existing user") <> T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{"call-1", "noop", Schema.ObjectValue{Record.Record{Nil{}}}, None{}, None{}}} <> Nil{}, "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Agent.emptyUsage(), Ai.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(0)}}} <> T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"call-1", "noop", Ai.TextImageText{Ai.TextContent{"done", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(1)}}} <> Nil{}

def defersFollowUp(messages: H.Messages(), name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{messages, T.OneAtATime{}, T.OneAtATime{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("follow-up"))
    result : Owner.Outcome() <- continued(agent)
    succeeded(result)
    +requests : List<&2, Texts()> <- recorded(fixture)
    Test.assertion(Nat.is_eq(List.length(&2, Texts(), requests), 2n) && Bool.not(mentions(firstRequest(requests), "follow-up")) && mentions(secondRequest(requests), "follow-up"), "follow-up waits for the second request")
    dispose(fixture)
    IO.print("PASS defers follow-up input on the first continuation request from a " ++ name ++ " tail")

def startupSteering(+mode: T.QueueMode) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{H.user("existing") <> Nil{}, mode, T.OneAtATime{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("first"))
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("second"))
    result : Owner.Outcome() <- continued(agent)
    succeeded(result)
    requests : List<&2, Texts()> <- recorded(fixture)
    checkSteeringMode(mode, requests, "first", "second")
    dispose(fixture)
    IO.print("PASS polls " ++ modeName(mode) ++ " steering at continuation startup")

def steeringBeforeFollowUp() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{H.user("existing") <> Nil{}, T.OneAtATime{}, T.OneAtATime{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("steering"))
    Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("follow-up"))
    result : Owner.Outcome() <- continued(agent)
    succeeded(result)
    +requests : List<&2, Texts()> <- recorded(fixture)
    Test.assertion(Nat.is_eq(List.length(&2, Texts(), requests), 2n) && mentions(firstRequest(requests), "steering") && Bool.not(mentions(firstRequest(requests), "follow-up")) && mentions(secondRequest(requests), "follow-up"), "steering is taken before follow-up")
    dispose(fixture)
    IO.print("PASS keeps steering ahead of follow-up from a non-assistant continuation tail")

# Queues a steering message when the assistant response completes.
def steerOnResponse(agent: Owner.Owner(), input: Listeners.Input<H.EventValue()>) -> IO(Loop.Emission<String>):
  match input:
    case Listeners.Input{T.MessageEnd{T.LlmMessage{Ai.Assistant{_}}}, _}:
      do IO<Loop.Emission<String>>:
        Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("steering"))
        return Loop.EmissionReady{Done{Unit{}}}
    case _: IO.pure(Loop.Emission<String>, Loop.EmissionReady{Done{Unit{}}})

def keepsQueues(finish: U32, reason: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{Nil{}, T.OneAtATime{}, T.OneAtATime{}, finish, reason})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("follow-up"))
    +listener : Listeners.Handler(H.EventValue(), String) <- C.create(~Owner.Owner(), ~Listeners.Input<H.EventValue()>, ~Loop.Emission<String>, ~steerOnResponse, agent)
    token : Listeners.Subscription<H.EventValue(), String> <- Agent.subscribe(Unit, Unit, String, String, Unit, agent, listener)
    result : Owner.Outcome() <- Agent.prompt(~Unit, ~Unit, ~String, ~String, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Text{"start", Nil{}})
    succeeded(result)
    checkQueues(agent, "steering", "follow-up")
    Listeners.unsubscribe(H.EventValue(), String, token)
    dispose(fixture)
    C.dispose(Listeners.Input<H.EventValue()>, Loop.Emission<String>, listener)
    IO.print("PASS " ++ name)

def previews() -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(Setup{Nil{}, T.OneAtATime{}, T.All{}, 0, 0})
    +agent : Owner.Owner() = getAgent(fixture)
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("first steering"))
    Agent.steer(Unit, Unit, String, String, Unit, agent, H.user("second steering"))
    Agent.followUp(Unit, Unit, String, String, Unit, agent, H.user("follow-up"))
    +first : String <- peeked(agent)
    again : String <- peeked(agent)
    Test.assertion(String.eq(first, "first steering|") && String.eq(again, "first steering|"), "previewing does not consume the steering message")
    Agent.clearSteeringQueue(Unit, Unit, String, String, Unit, agent)
    rest : String <- peeked(agent)
    Test.assertion(String.eq(rest, "follow-up|"), "the follow-up queue is previewed after steering")
    dispose(fixture)
    IO.print("PASS previews the next selected queued messages without consuming them")

def main() -> IO(Unit):
  do IO<Unit>:
    assistantTailFallback(T.OneAtATime{})
    assistantTailFallback(T.All{})
    rejectsEmpty(Nil{}, "empty")
    rejectsEmpty(systemOnly(), "system-only")
    defersFollowUp(H.user("existing user") <> Nil{}, "user")
    defersFollowUp(toolResultTail(), "toolResult")
    startupSteering(T.OneAtATime{})
    startupSteering(T.All{})
    steeringBeforeFollowUp()
    keepsQueues(1, 1, "keeps queues on a error response even when finishTurn requests continuation")
    keepsQueues(1, 2, "keeps queues on a aborted response even when finishTurn requests continuation")
    keepsQueues(2, 0, "keeps queues when finishTurn ends the run")
    previews()
