import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as State
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/providers/faux.bend as Faux
import ../../ai/src/utils/model-api.bend as ModelApi
import ../../ai/src/utils/message-json.bend as MessageJson
import ../../ai/src/utils/validation.bend as Validation
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/string.bend as Set
import ./agent-run.bend as H
import ./message-events.bend as Test
import ./utils/calculate.bend as Calc

# pi-mono f07218c4d packages/agent/test/e2e.test.ts: the Agent against the
# faux provider. Upstream registers each faux provider in pi-ai's api
# registry and passes pi-ai's `streamSimple` as the Agent's streamFn, which
# dispatches to it by api. The Bend ai package has no process-wide api
# registry (packages/ai/src/providers/faux.bend), so each test's streamFn
# streams from its FauxCore directly; the faux core, the Agent, its loop and
# the calculator tool are the production code paths. Each case prints
# `PASS <upstream test name>`; tests/agent_e2e_check.py compares the names
# with the upstream file.

def Owner() -> Data: Agent.Agent<Unit, Unit, String, String, Unit>
def Outcome() -> Data: Result<&2, &2, Agent.AgentError<String>, Unit>
def Core() -> Data: Faux.FauxCore<Unit, Unit, String>
def Step() -> Data: Faux.FauxResponseStep<Unit, Unit, String>
def Snapshot() -> Data: T.AgentState<Unit, Unit, String, String>
def Message() -> Data: H.Message()
def Assistant() -> Data: Ai.AssistantMessage<V.Value, Unit>
def Stream() -> Data: T.StreamFn(Unit, Unit, H.Config(), String)
def Fallback() -> Data: Provider.Registry(Unit, Unit, H.Config(), String)
def EventListener() -> Data: Listeners.Handler(H.EventValue(), String)
def Emitted() -> Type: Loop.Emission<String>

# The faux provider as the Agent's stream function
# ------------------------------------------------
# The Agent's request options carry the native fetch type; the faux provider
# performs no fetch, so only that member is dropped.
def withoutFetch(options: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>) -> Faux.Options(String):
  match options:
    case Ai.SimpleStreamOptions{signal, telemetry, key, _, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, retention, session, connect, metadata, choice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, key, None{}, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, retention, session, connect, metadata, choice, reasoning, deferred, budgets}

def fauxOptions(config: H.Config()) -> Faux.Options(String):
  withoutFetch(T.toSimpleStreamOptions(Unit, Unit, String, String, Unit, config))

def release(owner: Faux.FauxStream<Unit>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Faux.disposeStream(Unit, owner)
    return Done{Unit{}}

def leased(pair: Faux.FauxStream<Unit> & Faux.EventStream(Unit)) -> H.ProviderOutput():
  match pair:
    case (owner, events): Done{T.StreamLease{events, release(owner)}}

def render(value: String) -> String: value

def provider(core: Core(), input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match input:
    case T.StreamInput{model, context, options}:
      do IO<H.ProviderOutput()>:
        owner : Faux.FauxStream<Unit> <- Faux.stream(~Unit, ~Unit, ~String, ~render, core, model, context, Maybe.map(&2, H.Config(), Faux.Options(String), fauxOptions, options))
        return leased(Faux.borrowStream(Unit, owner))

# Faux registrations
# ------------------
def newCore(options: Faux.RegisterFauxProviderOptions) -> IO(Core()): Faux.createFauxCore(Unit, Unit, String, options)

def paced(+size: U32, rate: Maybe<&2, F64>) -> Faux.RegisterFauxProviderOptions:
  Faux.RegisterFauxProviderOptions{None{}, None{}, Nil{}, rate, Some{Faux.FauxTokenSize{Some{F.fromU32(size)}, Some{F.fromU32(size)}}}}

def getModel(core: Core()) -> Ai.Model<Ai.JsonValue>:
  Maybe.default(&2, Ai.Model<Ai.JsonValue>, Faux.getModel(Unit, Unit, String, core, None{}), Faux.modelOf("faux", "faux", Faux.defaultDefinition()))

def reply(content: List<&2, Ai.AssistantContent<V.Value>>, stop: Maybe<&2, Ai.StopReason>) -> IO(Step()):
  do IO<Step()>:
    message : Assistant() <- Faux.fauxAssistantMessage(Unit, content, Faux.FauxMessageOptions{stop, None{}, None{}, None{}})
    return Faux.FauxReply{message}

def replyText(text: String) -> IO(Step()): reply(Faux.fauxText(text) <> Nil{}, None{})

def setResponses(core: Core(), responses: List<&2, Step()>) -> IO(Unit): Faux.setResponses(Unit, Unit, String, core, responses)

# Agents
# ------
type Fixture is Data:
  Fixture{agent: Owner(), stream: Stream(), validate: Loop.Validator(String), fallback: Fallback(), tools: List<&2, Calc.Tool()>}

def mapError(error: Validation.ToolValidationError) -> String:
  Maybe.default(&2, String, Validation.formatToolValidationError(error), "unsupported tool schema")

def options(systemPrompt: String, model: Ai.Model<Ai.JsonValue>, thinking: Maybe<&2, T.ThinkingLevel()>, tools: Maybe<&2, List<&2, Calc.Tool()>>, stream: Stream()) -> Options.AgentOptions<Unit, Unit, String, String, Unit>:
  Options.AgentOptions{Some{State.AgentInitialState{Some{systemPrompt}, Some{model}, thinking, tools, None{}}}, None{}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def required(result: Result<&2, &2, Provider.MissingDefault, Owner()>) -> IO(Owner()):
  match result:
    case Done{agent}: IO.pure(Owner(), agent)
    case _: IO.die(Owner(), 1, "Agent construction failed")

# new Agent({ streamFn, initialState: { systemPrompt, model, thinkingLevel?, tools? } }).
def create(core: Core(), systemPrompt: String, model: Ai.Model<Ai.JsonValue>, thinking: Maybe<&2, T.ThinkingLevel()>, +tools: Maybe<&2, List<&2, Calc.Tool()>>) -> IO(Fixture):
  do IO<Fixture>:
    +stream : Stream() <- C.create(~Core(), ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, core)
    +validate : Loop.Validator(String) <- Loop.createPlain(~String, ~mapError)
    +fallback : Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, options(systemPrompt, model, thinking, tools, stream), fallback, validate, Unit{})
    agent : Owner() <- required(result)
    return Fixture{agent, stream, validate, fallback, Maybe.default(&2, List<&2, Calc.Tool()>, tools, Nil{})}

def agentOf(fixture: Fixture) -> Owner():
  match fixture:
    case Fixture{agent, _, _, _, _}: agent

def disposeTools(tools: List<&2, Calc.Tool()>) -> IO(Unit):
  match tools:
    case Nil{}: IO.pure(Unit, Unit{})
    case tool <> rest:
      do IO<Unit>:
        Calc.disposeTool(tool)
        disposeTools(rest)

def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{agent, stream, validate, fallback, tools}:
      do IO<Unit>:
        Agent.dispose(Unit, Unit, String, String, Unit, agent)
        C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
        Loop.disposeValidation(String, validate)
        Provider.dispose(Unit, Unit, H.Config(), String, fallback)
        disposeTools(tools)

def prompt(agent: Owner(), text: String) -> IO(Outcome()):
  Agent.prompt(~Unit, ~Unit, ~String, ~String, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Text{text, Nil{}})

def continued(agent: Owner()) -> IO(Outcome()):
  Agent.continueRun(~Unit, ~Unit, ~String, ~String, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)

def settled(result: Outcome()) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{Agent.ClaimFailed{message}}: IO.die(Unit, 1, "Agent run rejected: " ++ message)
    case Fail{_}: IO.die(Unit, 1, "Agent run failed")

def snapshot(agent: Owner()) -> IO(Snapshot()): Agent.state(Unit, Unit, String, String, Unit, agent)

def replaceMessages(agent: Owner(), messages: List<&2, Message()>) -> IO(Unit):
  Agent.replaceMessages(Unit, Unit, String, String, Unit, agent, messages)

# State views
# -----------
def messagesOf(state: Snapshot()) -> List<&2, Message()>:
  match state:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def streamingOf(state: Snapshot()) -> Bool:
  match state:
    case T.AgentState{_, _, _, _, streaming, _, _, _}: streaming

def pendingOf(state: Snapshot()) -> List<&2, String>:
  match state:
    case T.AgentState{_, _, _, _, _, _, pending, _}: Set.toList(pending)

def errorOf(state: Snapshot()) -> Maybe<&2, String>:
  match state:
    case T.AgentState{_, _, _, _, _, _, _, error}: error

def role(message: Message()) -> String:
  match message:
    case T.LlmMessage{Ai.System{_}}: "system"
    case T.LlmMessage{Ai.User{_}}: "user"
    case T.LlmMessage{Ai.Assistant{_}}: "assistant"
    case T.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case _: "custom"

def roles(messages: List<&2, Message()>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: role(message) <> roles(rest)

def rolesOf(state: Snapshot()) -> String: String.join(roles(messagesOf(state)), ",")

def countOf(state: Snapshot()) -> Nat: List.length(&2, Message(), messagesOf(state))

def assistantTexts(blocks: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text <> assistantTexts(rest)
    case _ <> rest: assistantTexts(rest)

def blockTexts(blocks: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text <> blockTexts(rest)
    case _ <> rest: blockTexts(rest)

# upstream getTextContent: the text blocks joined by newlines.
def getTextContent(message: Message()) -> String:
  match message:
    case T.LlmMessage{Ai.Assistant{assistant}}: String.join(assistantTexts(Ai.assistantContent(V.Value, Unit, assistant)), "\n")
    case T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, content, _, _, _, _}}}: String.join(blockTexts(content), "\n")
    case _: ""

def at(messages: List<&2, Message()>, +index: Nat) -> Maybe<&2, Message()>:
  match messages index:
    case Nil{} _: None{}
    case message <> _ 0n: Some{message}
    case _ <> rest 1n+previous: at(rest, previous)

def last(messages: List<&2, Message()>) -> Maybe<&2, Message()>:
  match messages:
    case Nil{}: None{}
    case message <> Nil{}: Some{message}
    case _ <> rest: last(rest)

def firstToolResult(messages: List<&2, Message()>) -> Maybe<&2, Message()>:
  match messages:
    case Nil{}: None{}
    case T.LlmMessage{Ai.ToolResult{result}} <> _: Some{T.LlmMessage{Ai.ToolResult{result}}}
    case _ <> rest: firstToolResult(rest)

def isRole(message: Maybe<&2, Message()>, +expected: String) -> Bool:
  match message:
    case Some{value}: String.eq(role(value), expected)
    case None{}: False{}

def textOf(message: Maybe<&2, Message()>) -> String:
  match message:
    case Some{value}: getTextContent(value)
    case None{}: ""

def assistantOf(message: Maybe<&2, Message()>) -> Maybe<&2, Assistant()>:
  match message:
    case Some{T.LlmMessage{Ai.Assistant{assistant}}}: Some{assistant}
    case _: None{}

def contains(+text: String, +part: String) -> Bool: String.contains(text, part)

def check(ok: Bool, label: String) -> IO(Unit): Test.assertion(ok, label)

# Listeners
# ---------
def ready() -> Emitted(): Loop.EmissionReady{Done{Unit{}}}

def appended(value: String, old: List<&2, String>) -> List<&2, String> & Unit: (value <> old, Unit{})

def record(trace: R.Ref<List<&2, String>>, value: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, trace, old => appended(value, old))

def recorded(trace: R.Ref<List<&2, String>>) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    values : List<&2, String> <- R.dispose(List<&2, String>, trace)
    return List.reverse(&2, String, values)

def eventName(event: H.EventValue()) -> String:
  T.eventType(Unit, Unit, String, T.AgentToolResult<Unit>, T.AgentToolResult<Unit>, event)

def typeListener(trace: R.Ref<List<&2, String>>, input: Listeners.Input<H.EventValue()>) -> IO(Emitted()):
  match input:
    case Listeners.Input{event, _}:
      do IO<Emitted()>:
        record(trace, eventName(event))
        return ready()

type PendingCapture is Data:
  PendingCapture{agent: Owner(), trace: R.Ref<List<&2, String>>}

# The event type with the ids in agent.state.pendingToolCalls at that moment.
def recordPending(capture: PendingCapture, kind: String) -> IO(Emitted()):
  match capture:
    case PendingCapture{agent, trace}:
      do IO<Emitted()>:
        state : Snapshot() <- snapshot(agent)
        record(trace, kind ++ ":" ++ String.join(pendingOf(state), ","))
        return ready()

def pendingListener(capture: PendingCapture, input: Listeners.Input<H.EventValue()>) -> IO(Emitted()):
  match input:
    case Listeners.Input{T.ToolExecutionStart{_, _, _}, _}: recordPending(capture, "tool_execution_start")
    case Listeners.Input{T.ToolExecutionEnd{_, _, _, _}, _}: recordPending(capture, "tool_execution_end")
    case _: IO.pure(Emitted(), ready())

def subscribe(agent: Owner(), listener: EventListener()) -> IO(Listeners.Subscription<H.EventValue(), String>):
  Agent.subscribe(Unit, Unit, String, String, Unit, agent, listener)

def unsubscribe(token: Listeners.Subscription<H.EventValue(), String>, listener: EventListener()) -> IO(Unit):
  do IO<Unit>:
    Listeners.unsubscribe(H.EventValue(), String, token)
    C.dispose(Listeners.Input<H.EventValue()>, Emitted(), listener)

# Agent integration with faux provider
# ------------------------------------
def basicPrompt(+model: Ai.Model<Ai.JsonValue>, core: Core()) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(core, "You are a helpful assistant. Keep your responses concise.", model, Some{Ai.Off{}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    result : Outcome() <- prompt(agent, "What is 2+2? Answer with just the number.")
    settled(result)
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after the prompt")
    check(String.eq(rolesOf(state), "system,user,assistant"), "system, user and assistant messages: " ++ rolesOf(state))
    check(contains(textOf(at(messagesOf(state), 2n)), "4"), "the assistant answers 4")
    dispose(fixture)

def handlesBasicPrompt() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    four : Step() <- replyText("4")
    setResponses(core, four <> Nil{})
    basicPrompt(getModel(core), core)
    IO.print("PASS handles a basic text prompt")

def expression(value: String) -> V.Value: V.ObjectValue{Record.Record{Record.Property{"expression", V.Text{value}} <> Nil{}}}

def toolExecution(+model: Ai.Model<Ai.JsonValue>, core: Core()) -> IO(Unit):
  do IO<Unit>:
    tool : Calc.Tool() <- Calc.calculateTool()
    +fixture : Fixture <- create(core, "You are a helpful assistant. Always use the calculator tool for math.", model, Some{Ai.Off{}}, Some{tool <> Nil{}})
    +agent : Owner() = agentOf(fixture)
    +trace : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +listener : EventListener() <- C.create(~PendingCapture, ~Listeners.Input<H.EventValue()>, ~Emitted(), ~pendingListener, PendingCapture{agent, trace})
    token : Listeners.Subscription<H.EventValue(), String> <- subscribe(agent, listener)
    result : Outcome() <- prompt(agent, "Calculate 123 * 456 using the calculator tool.")
    settled(result)
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after the prompt")
    check(Nat.is_ge(countOf(state), 4n), "at least four messages")
    +toolResult : Maybe<&2, Message()> = firstToolResult(messagesOf(state))
    check(isRole(toolResult, "toolResult"), "a tool result message was recorded")
    check(contains(textOf(toolResult), "123 * 456 = 56088"), "the tool result is the calculation: " ++ textOf(toolResult))
    +final : Maybe<&2, Message()> = last(messagesOf(state))
    check(isRole(final, "assistant"), "the final message is the assistant's")
    check(contains(textOf(final), "56088"), "the final answer mentions 56088")
    check(Nat.is_eq(List.length(&2, String, pendingOf(state)), 0n), "no tool call is pending after the run")
    unsubscribe(token, listener)
    +events : List<&2, String> <- recorded(trace)
    check(String.eq(String.join(events, ";"), "tool_execution_start:calc-1;tool_execution_end:"), "pending tool calls during tool events: " ++ String.join(events, ";"))
    dispose(fixture)

def executesTools() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    call : Step() <- reply(Faux.fauxText("Let me calculate that.") <> Faux.fauxToolCallWithId("calculate", expression("123 * 456"), "calc-1") <> Nil{}, Some{Ai.ToolUse{}})
    answer : Step() <- replyText("The result is 56088.")
    setResponses(core, call <> answer <> Nil{})
    toolExecution(getModel(core), core)
    IO.print("PASS executes tools and tracks pending tool calls")

# setTimeout(() => agent.abort(), 30)
def abortLater(agent: Owner()) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(30)
    Agent.abort(Unit, Unit, String, String, Unit, agent)

def stopName(message: Maybe<&2, Assistant()>) -> String:
  match message:
    case Some{assistant}: MessageJson.stopReason(Ai.assistantStopReason(V.Value, Unit, assistant))
    case None{}: "(not an assistant message)"

def assistantError(message: Maybe<&2, Assistant()>) -> Maybe<&2, String>:
  match message:
    case Some{assistant}: Ai.assistantErrorMessage(V.Value, Unit, assistant)
    case None{}: None{}

def sameError(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case Some{a} Some{b}: String.eq(a, b)
    case None{} None{}: True{}
    case _ _: False{}

def present(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def abortExecution(+model: Ai.Model<Ai.JsonValue>, core: Core()) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(core, "You are a helpful assistant.", model, Some{Ai.Off{}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    task : Chan(Unit) <- IO.fork(Unit, abortLater(agent))
    result : Outcome() <- prompt(agent, "Count slowly from 1 to 20.")
    done : Unit <- IO.join(Unit, task)
    settled(result)
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after the abort")
    check(Nat.is_ge(countOf(state), 2n), "at least two messages")
    +final : Maybe<&2, Assistant()> = assistantOf(last(messagesOf(state)))
    check(String.eq(stopName(final), "aborted"), "the last message was aborted: " ++ stopName(final))
    check(present(assistantError(final)), "the aborted message has an error message")
    check(sameError(errorOf(state), assistantError(final)), "the state's error message is the aborted message's")
    dispose(fixture)

def handlesAbort() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(paced(2, Some{F.fromU32(20)}))
    count : Step() <- replyText("one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen")
    setResponses(core, count <> Nil{})
    abortExecution(getModel(core), core)
    IO.print("PASS handles abort during streaming")

def firstIndex(values: List<&2, String>, +wanted: String, +position: Nat) -> Nat:
  match values:
    case Nil{}: position
    case value <> rest: Bool.pick(Unit -> Nat, String.eq(value, wanted), _ => position, _ => firstIndex(rest, wanted, 1n + position))(Unit{})

def lastIndex(values: List<&2, String>, +wanted: String, +position: Nat, found: Nat) -> Nat:
  match values:
    case Nil{}: found
    case value <> rest: lastIndex(rest, wanted, 1n + position, Bool.pick(Nat, String.eq(value, wanted), position, found))

def includes(values: List<&2, String>, +wanted: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: Bool.pick(Unit -> Bool, String.eq(value, wanted), _ => True{}, _ => includes(rest, wanted))(Unit{})

def checkIncluded(+events: List<&2, String>, names: List<&2, String>) -> IO(Unit):
  match names:
    case Nil{}: IO.pure(Unit, Unit{})
    case +name <> rest:
      do IO<Unit>:
        check(includes(events, name), "the run emits " ++ name)
        checkIncluded(events, rest)

def stateUpdates(+model: Ai.Model<Ai.JsonValue>, core: Core()) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(core, "You are a helpful assistant.", model, Some{Ai.Off{}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    +trace : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +listener : EventListener() <- C.create(~R.Ref<List<&2, String>>, ~Listeners.Input<H.EventValue()>, ~Emitted(), ~typeListener, trace)
    token : Listeners.Subscription<H.EventValue(), String> <- subscribe(agent, listener)
    result : Outcome() <- prompt(agent, "Count from 1 to 5.")
    settled(result)
    unsubscribe(token, listener)
    +events : List<&2, String> <- recorded(trace)
    checkIncluded(events, "agent_start" <> "turn_start" <> "message_start" <> "message_update" <> "message_end" <> "turn_end" <> "agent_end" <> Nil{})
    check(Nat.is_lt(firstIndex(events, "agent_start", 0n), firstIndex(events, "message_start", 0n)), "agent_start precedes message_start")
    check(Nat.is_lt(firstIndex(events, "message_start", 0n), firstIndex(events, "message_end", 0n)), "message_start precedes message_end")
    check(Nat.is_lt(firstIndex(events, "message_end", 0n), lastIndex(events, "agent_end", 0n, 0n)), "message_end precedes the last agent_end")
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after the prompt")
    check(Nat.is_eq(countOf(state), 3n), "three messages")
    dispose(fixture)

def emitsLifecycle() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(paced(1, None{}))
    count : Step() <- replyText("1 2 3 4 5")
    setResponses(core, count <> Nil{})
    stateUpdates(getModel(core), core)
    IO.print("PASS emits lifecycle updates while streaming")

def blocksMention(blocks: List<&2, Ai.TextImageContent>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case Ai.TextImageText{Ai.TextContent{+text, _}} <> rest: Bool.pick(Unit -> Bool, contains(text, "Alice"), _ => True{}, _ => blocksMention(rest))(Unit{})
    case _ <> rest: blocksMention(rest)

def userMentions(content: Ai.UserContent) -> Bool:
  match content:
    case Ai.UserText{+text}: contains(text, "Alice")
    case Ai.UserBlocks{blocks}: blocksMention(blocks)

def mentionsAlice(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Unit>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.User{Ai.UserMessage{content, _}} <> rest: Bool.pick(Unit -> Bool, userMentions(content), _ => True{}, _ => mentionsAlice(rest))(Unit{})
    case _ <> rest: mentionsAlice(rest)

def FactoryInput() -> Data: Faux.FactoryInput<Unit, Unit, String>
def Factored() -> Data: Result<&2, &2, String, Assistant()>

# The second response answers from the context the provider received.
def aliceFactory(unused: Unit, input: FactoryInput()) -> IO(Factored()):
  match input:
    case Faux.FactoryInput{Ai.TranscriptContext{messages}, _, _, _}:
      do IO<Factored()>:
        message : Assistant() <- Faux.fauxAssistantMessage(Unit, Faux.fauxText(Bool.pick(String, mentionsAlice(messages), "Your name is Alice.", "I do not know your name.")) <> Nil{}, Faux.noOptions())
        return Done{message}

def multiTurnConversation(+model: Ai.Model<Ai.JsonValue>, core: Core()) -> IO(Unit):
  do IO<Unit>:
    +fixture : Fixture <- create(core, "You are a helpful assistant.", model, Some{Ai.Off{}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    first : Outcome() <- prompt(agent, "My name is Alice.")
    settled(first)
    +afterFirst : Snapshot() <- snapshot(agent)
    check(Nat.is_eq(countOf(afterFirst), 3n), "three messages after the first prompt")
    second : Outcome() <- prompt(agent, "What is my name?")
    settled(second)
    +afterSecond : Snapshot() <- snapshot(agent)
    check(Nat.is_eq(countOf(afterSecond), 5n), "five messages after the second prompt")
    +answer : Maybe<&2, Message()> = at(messagesOf(afterSecond), 4n)
    check(isRole(answer, "assistant"), "the fifth message is the assistant's")
    check(contains(String.to_lower(textOf(answer)), "alice"), "the assistant remembers the name: " ++ textOf(answer))
    dispose(fixture)

def maintainsContext() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    greeting : Step() <- replyText("Nice to meet you, Alice.")
    +factory : C.Callback<FactoryInput(), Factored()> <- C.create(~Unit, ~FactoryInput(), ~Factored(), ~aliceFactory, Unit{})
    setResponses(core, greeting <> Faux.FauxFactory{factory} <> Nil{})
    multiTurnConversation(getModel(core), core)
    C.dispose(FactoryInput(), Factored(), factory)
    IO.print("PASS maintains context across multiple turns")

# [{ type: "thinking", thinking: "step by step" }, { type: "text", text: "4" }]
def thinkingThenText(blocks: List<&2, Ai.AssistantContent<V.Value>>) -> Bool:
  match blocks:
    case Ai.AssistantThinking{Ai.ThinkingContent{+thinking, None{}, None{}}} <> Ai.AssistantText{Ai.TextContent{+text, None{}}} <> Nil{}: String.eq(thinking, "step by step") && String.eq(text, "4")
    case _: False{}

def preservedThinking(message: Maybe<&2, Assistant()>) -> Bool:
  match message:
    case Some{assistant}: thinkingThenText(Ai.assistantContent(V.Value, Unit, assistant))
    case None{}: False{}

def preservesThinking() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.RegisterFauxProviderOptions{None{}, None{}, Faux.FauxModelDefinition{"faux-reasoning", None{}, Some{True{}}, None{}, None{}, None{}, None{}, None{}} <> Nil{}, None{}, None{}})
    reasoned : Step() <- reply(Faux.fauxThinking("step by step") <> Faux.fauxText("4") <> Nil{}, None{})
    setResponses(core, reasoned <> Nil{})
    +fixture : Fixture <- create(core, "You are a helpful assistant.", getModel(core), Some{Ai.Thinking{Ai.Low{}}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    result : Outcome() <- prompt(agent, "What is 2+2?")
    settled(result)
    state : Snapshot() <- snapshot(agent)
    check(preservedThinking(assistantOf(at(messagesOf(state), 2n))), "the assistant message keeps its thinking and text blocks")
    dispose(fixture)
    IO.print("PASS preserves thinking content blocks")

# Agent.continue() with faux provider
# -----------------------------------
def rejectedWith(result: Outcome(), +expected: String) -> IO(Unit):
  match result:
    case Fail{Agent.ClaimFailed{+message}}: check(contains(message, expected), "continue() rejects with: " ++ message)
    case _: check(False{}, "continue() was expected to reject with: " ++ expected)

def throwsWithoutMessages() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    +fixture : Fixture <- create(core, "Test", getModel(core), None{}, None{})
    result : Outcome() <- continued(agentOf(fixture))
    rejectedWith(result, "No messages to continue from")
    dispose(fixture)
    IO.print("PASS throws when no messages in context")

def emptyUsage() -> Ai.Usage: Agent.emptyUsage()

def assistantMessage(+model: Ai.Model<Ai.JsonValue>, content: List<&2, Ai.AssistantContent<V.Value>>, stop: Ai.StopReason, timestamp: F64) -> Message():
  T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, ModelApi.name(ModelApi.modelApi(Ai.JsonValue, model)), Ai.modelProvider(model), Ai.modelId(model), None{}, None{}, None{}, None{}, emptyUsage(), stop, None{}, None{}, None{}, None{}, timestamp}}}

def throwsFromAssistant() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    +model : Ai.Model<Ai.JsonValue> = getModel(core)
    +fixture : Fixture <- create(core, "Test", model, None{}, None{})
    +agent : Owner() = agentOf(fixture)
    now : F64 <- Date.now()
    replaceMessages(agent, assistantMessage(model, Ai.AssistantText{Ai.TextContent{"Hello", None{}}} <> Nil{}, Ai.Stop{}, now) <> Nil{})
    result : Outcome() <- continued(agent)
    rejectedWith(result, "Cannot continue from message role: assistant")
    dispose(fixture)
    IO.print("PASS throws when last message is assistant")

def userMessage(text: String, timestamp: F64) -> Message():
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}}, timestamp}}}

def continuesFromUser() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    hello : Step() <- replyText("HELLO WORLD")
    setResponses(core, hello <> Nil{})
    +fixture : Fixture <- create(core, "You are a helpful assistant. Follow instructions exactly.", getModel(core), Some{Ai.Off{}}, Some{Nil{}})
    +agent : Owner() = agentOf(fixture)
    now : F64 <- Date.now()
    replaceMessages(agent, userMessage("Say exactly: HELLO WORLD", now) <> Nil{})
    result : Outcome() <- continued(agent)
    settled(result)
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after continue()")
    check(String.eq(rolesOf(state), "user,assistant"), "user then assistant: " ++ rolesOf(state))
    check(contains(String.to_upper(textOf(at(messagesOf(state), 1n))), "HELLO WORLD"), "the assistant follows the instruction")
    dispose(fixture)
    IO.print("PASS continues and gets a response when last message is user")

def toolResultMessage(timestamp: F64) -> Message():
  T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"calc-1", "calculate", Ai.TextImageText{Ai.TextContent{"5 + 3 = 8", None{}}} <> Nil{}, None{}, None{}, False{}, timestamp}}}

def continuesFromToolResult() -> IO(Unit):
  do IO<Unit>:
    +core : Core() <- newCore(Faux.defaultOptions())
    +model : Ai.Model<Ai.JsonValue> = getModel(core)
    answer : Step() <- replyText("The answer is 8.")
    setResponses(core, answer <> Nil{})
    tool : Calc.Tool() <- Calc.calculateTool()
    +fixture : Fixture <- create(core, "You are a helpful assistant. After getting a calculation result, state the answer clearly.", model, Some{Ai.Off{}}, Some{tool <> Nil{}})
    +agent : Owner() = agentOf(fixture)
    +now : F64 <- Date.now()
    replaceMessages(agent, userMessage("What is 5 + 3?", now) <> assistantMessage(model, Ai.AssistantText{Ai.TextContent{"Let me calculate that.", None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"calc-1", "calculate", expression("5 + 3"), None{}, None{}}} <> Nil{}, Ai.ToolUse{}, now) <> toolResultMessage(now) <> Nil{})
    result : Outcome() <- continued(agent)
    settled(result)
    +state : Snapshot() <- snapshot(agent)
    check(Bool.not(streamingOf(state)), "the agent is idle after continue()")
    check(Nat.is_ge(countOf(state), 4n), "at least four messages")
    +final : Maybe<&2, Message()> = last(messagesOf(state))
    check(isRole(final, "assistant"), "the last message is the assistant's")
    check(contains(textOf(final), "8"), "the assistant states the answer")
    dispose(fixture)
    IO.print("PASS continues and processes tool results")

def main() -> IO(Unit):
  do IO<Unit>:
    handlesBasicPrompt()
    executesTools()
    handlesAbort()
    emitsLifecycle()
    maintainsContext()
    preservesThinking()
    throwsWithoutMessages()
    throwsFromAssistant()
    continuesFromUser()
    continuesFromToolResult()
