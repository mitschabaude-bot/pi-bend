import Base
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/types.bend as T
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../ai/src/utils/retry.bend as Retry
import ../../../ai/src/utils/overflow.bend as Overflow
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/timer.bend as Sleep
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/json.bend as Decode
import ./agent-runtime.bend as Runtime
import ./messages.bend as Messages
import ./session-manager.bend as S
import ./session-persistence.bend as Sessions
import ./settings-manager.bend as Settings
import ./tools/index.bend as Tools

# The upstream AgentSession core: the owner of one Agent and its session
# record. It subscribes to the agent, republishes agent events to its own
# listeners with the session-level events, persists each finished message
# through session persistence, queues prompts sent while streaming, and
# records model, thinking-level and name changes as session entries, and
# retries transient provider errors with the settings' backoff policy.
# Compaction, bash execution, extensions, skills, prompt templates and tree
# navigation are not ported yet.

# The CLI's session codecs: no diagnostic details, tool details as their
# JSON shape (restored ones kept raw), extension payloads as JSON values.
def Session() -> Data: Sessions.Session<Unit, Tools.ToolDetails, V.Value>
def State() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Appended() -> Data: Sessions.Appended<Unit, Tools.ToolDetails, V.Value>
def Message() -> Data: T.AgentMessage<Unit, Runtime.Details(), Runtime.Custom()>
def SessionEvent() -> Data: Agent.RunEvent(Unit, Runtime.Details(), Runtime.Custom())
def AgentState() -> Data: T.AgentState<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>

def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def readUnit(value: V.Value) -> Result<&2, &2, Decode.Error, Unit>: Done{Unit{}}
def readRaw(value: V.Value) -> Result<&2, &2, Decode.Error, V.Value>: Done{value}
def readDetails(value: V.Value) -> Result<&2, &2, Decode.Error, Tools.ToolDetails>: Done{Tools.RawDetails{value}}

def createSession(cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.create(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, sessionDir, agentDir, options)

def openSession(path: String, sessionDir: Maybe<&2, String>, cwd: String) -> IO(Sessions.Outcome(Session())):
  Sessions.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, path, sessionDir, None{}, cwd)

def continueSession(cwd: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Sessions.Outcome(Session())):
  Sessions.continueRecent(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, sessionDir, agentDir)

def memorySession(cwd: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.inMemory(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, cwd, options, None{})

def forkSession(source: String, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.forkFrom(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, source, cwd, sessionDir, agentDir, options)

def recordMessage(session: Session(), message: Message()) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendMessage(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, message)

def recordCustomMessage(session: Session(), customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2, V.Value>) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendCustomMessageEntry(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, customType, content, display, details)

def recordName(session: Session(), name: String) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendSessionInfo(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, name)

def recordThinking(session: Session(), level: Ai.ModelThinkingLevel) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendThinkingLevelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, Levels.name(level))

def recordModel(session: Session(), model: Ai.Model<Ai.JsonValue>) -> IO(Sessions.Outcome(Appended())):
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _}: Sessions.appendModelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, provider, id)

def stateMessages(value: AgentState()) -> List<&2, Message()>:
  match value:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def stateModel(value: AgentState()) -> Ai.Model<Ai.JsonValue>:
  match value:
    case T.AgentState{model, _, _, _, _, _, _, _}: model

def modelContextWindow(model: Ai.Model<Ai.JsonValue>) -> F64:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, contextWindow, _, _, _, _}: contextWindow

def lastAssistantIn(messages: List<&2, Message()>, +found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match messages:
    case Nil{}: found
    case T.LlmMessage{Ai.Assistant{assistant}} <> rest: lastAssistantIn(rest, Some{assistant})
    case _ <> rest: lastAssistantIn(rest, found)

# Events
# ------
# Agent events are embedded in one constructor (upstream spreads the union);
# agent_end carries willRetry when the run will continue with a retry.

type AgentSessionEvent is Data:
  AgentEvent{event: SessionEvent()}
  AgentEnd{messages: List<&2, Message()>, willRetry: Bool}
  AgentSettled{}
  QueueUpdate{steering: List<&2, String>, followUp: List<&2, String>}
  SessionInfoChanged{name: Maybe<&2, String>}
  ThinkingLevelChanged{level: Ai.ModelThinkingLevel}
  AutoRetryStart{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  AutoRetryEnd{success: Bool, attempt: Nat, finalError: Maybe<&2, String>}

def Listener() -> Data: C.Callback<AgentSessionEvent, Unit>

# Automatic retry bookkeeping: the settings' policy, the current attempt, the
# model's context window (overflow belongs to compaction, not retry) and the
# abort controller of a backoff sleep in progress.
type RetryState is Data:
  RetryState{policy: Retry.RetryPolicy, attempt: Nat, contextWindow: F64, sleeping: Maybe<&2, A.AbortController<Unit>>}

# The mutable session state shared with the agent's event handler.
type Shared is Data:
  Shared{session: Session(), steering: List<&2, String>, followUp: List<&2, String>, listeners: List<&2, Listener()>, runActive: Bool, lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, retry: RetryState}

type AgentSession is Data:
  AgentSession{agent: Runtime.Owner(), shared: R.Ref<Shared>, subscription: Agent.Subscription<SessionEvent(), Runtime.Error()>, handler: Agent.Handler(SessionEvent(), Runtime.Error()), settings: Settings.SettingsManager, cwd: String}

def sharedSession(state: Shared) -> Session():
  match state:
    case Shared{session, _, _, _, _, _, _}: session

def withSession(state: Shared, session: Session()) -> Shared:
  match state:
    case Shared{_, steering, followUp, listeners, runActive, lastAssistant, retry}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}

def withRunActive(state: Shared, runActive: Bool) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, _, lastAssistant, retry}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}

def deliver(listeners: List<&2, Listener()>, +event: AgentSessionEvent) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit, Unit{})
    case listener <> rest:
      do IO<Unit>:
        C.call(AgentSessionEvent, Unit, listener, event)
        deliver(rest, event)

def listenersOf(state: Shared) -> List<&2, Listener()>:
  match state:
    case Shared{_, _, _, listeners, _, _, _}: listeners

def emit(shared: R.Ref<Shared>, event: AgentSessionEvent) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    deliver(listenersOf(state), event)

def queueEvent(state: Shared) -> AgentSessionEvent:
  match state:
    case Shared{_, steering, followUp, _, _, _, _}: QueueUpdate{steering, followUp}

def emitQueueUpdate(+shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    emit(shared, queueEvent(state))

# Queues
# ------
# Texts queued while streaming are remembered so the queue_update event can
# report them and drop them when their user message starts.

def removeFirst(values: List<&2, String>, +wanted: String) -> Maybe<&2, List<&2, String>>:
  match values:
    case Nil{}: None{}
    case +value <> +rest: Bool.pick(Unit -> Maybe<&2, List<&2, String>>, String.eq(value, wanted), _ => Some{rest}, _ => Maybe.map(&2, List<&2, String>, List<&2, String>, others => value <> others, removeFirst(rest, wanted)))(Unit{})

def dequeuedFrom(+session: Session(), +steering: List<&2, String>, +followUp: List<&2, String>, listeners: List<&2, Listener()>, +runActive: Bool, +lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, +retry: RetryState, fromSteering: Maybe<&2, List<&2, String>>, fromFollowUp: Maybe<&2, List<&2, String>>) -> Shared & Bool:
  match fromSteering fromFollowUp:
    case Some{remaining} _: (Shared{session, remaining, followUp, listeners, runActive, lastAssistant, retry}, True{})
    case None{} Some{remaining}: (Shared{session, steering, remaining, listeners, runActive, lastAssistant, retry}, True{})
    case None{} None{}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}, False{})

# The steering queue is searched first, then the follow-up queue, as upstream.
def dequeued(state: Shared, +text: String) -> Shared & Bool:
  match state:
    case Shared{session, +steering, +followUp, listeners, runActive, lastAssistant, retry}:
      dequeuedFrom(session, steering, followUp, listeners, runActive, lastAssistant, retry, removeFirst(steering, text), removeFirst(followUp, text))

def blockText(blocks: List<&2, Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text ++ blockText(rest)
    case _ <> rest: blockText(rest)

def userText(message: Message()) -> Maybe<&2, String>:
  match message:
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}}: Some{text}
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks}, _}}}: Some{blockText(blocks)}
    case _: None{}

def startedText(event: SessionEvent()) -> Maybe<&2, String>:
  match event:
    case T.MessageStart{message}: userText(message)
    case _: None{}

def updatedQueue(shared: R.Ref<Shared>, removed: Bool) -> IO(Unit):
  match removed:
    case True{}: emitQueueUpdate(shared)
    case False{}: IO.pure(Unit, Unit{})

# A starting user message leaves its queue before listeners see the event.
def trimQueues(+shared: R.Ref<Shared>, text: Maybe<&2, String>) -> IO(Unit):
  match text:
    case None{}: IO.pure(Unit, Unit{})
    case Some{SNil{}}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        removed : Bool <- R.modify(Shared, Bool, shared, current => dequeued(current, value))
        updatedQueue(shared, removed)

# Persistence
# -----------

def stored(shared: R.Ref<Shared>, outcome: Sessions.Outcome(Appended())) -> IO(Unit):
  match outcome:
    case Done{Sessions.Appended{session, _}}: R.modify(Shared, Unit, shared, current => (withSession(current, session), Unit{}))
    case Fail{error}: IO.print_err("Could not persist the session entry: " ++ Sessions.message(error))

def rememberedAssistant(state: Shared, assistant: Ai.AssistantMessage<V.Value, Unit>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, _, retry}: Shared{session, steering, followUp, listeners, runActive, Some{assistant}, retry}

def rememberAssistant(shared: R.Ref<Shared>, message: Message()) -> IO(Unit):
  match message:
    case T.LlmMessage{Ai.Assistant{assistant}}: R.modify(Shared, Unit, shared, current => (rememberedAssistant(current, assistant), Unit{}))
    case _: IO.pure(Unit, Unit{})

# upstream _handleAgentEvent persistence: LLM messages and extension custom
# messages become session entries; bash executions and summaries are
# persisted where they are produced.
def persistFinished(+shared: R.Ref<Shared>, +message: Message()) -> IO(Unit):
  match message:
    case T.LlmMessage{+value}:
      do IO<Unit>:
        state : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordMessage(sharedSession(state), T.LlmMessage{value})
        stored(shared, outcome)
        rememberAssistant(shared, T.LlmMessage{value})
    case T.CustomMessage{Messages.Custom{Messages.CustomMessage{customType, content, display, details, _}}}:
      do IO<Unit>:
        state : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordCustomMessage(sharedSession(state), customType, content, display, details)
        stored(shared, outcome)
    case _: IO.pure(Unit, Unit{})

def persist(shared: R.Ref<Shared>, event: SessionEvent()) -> IO(Unit):
  match event:
    case T.MessageEnd{message}: persistFinished(shared, message)
    case _: IO.pure(Unit, Unit{})

# Retry
# -----
# upstream _willRetryAfterAgentEnd, _prepareRetry and the message_end reset:
# a transient error (not a context overflow) restarts the assistant turn
# after an abortable backoff while the settings' budget allows.

def retryOf(state: Shared) -> RetryState:
  match state:
    case Shared{_, _, _, _, _, _, retry}: retry

def withAttempt(state: Shared, attempt: Nat) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, _, contextWindow, sleeping}}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}}

# Clears the attempt counter and returns the count it had.
def resetAttempt(state: Shared) -> Shared & Nat:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, previous, contextWindow, sleeping}}:
      (Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, 0n, contextWindow, sleeping}}, previous)

def withSleeping(state: Shared, sleeping: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, _}}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}}

def withContextWindow(state: Shared, contextWindow: F64) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, _, sleeping}}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}}

def retryPolicy(resolved: Settings.ResolvedRetrySettings) -> Retry.RetryPolicy:
  match resolved:
    case Settings.ResolvedRetrySettings{enabled, maxRetries, baseDelayMs, maxAgentDelayMs}: Retry.RetryPolicy{enabled, F.natural(maxRetries), F.fromU64(baseDelayMs), Some{F.fromU64(maxAgentDelayMs)}}

# Context overflow is handled by compaction, not retry.
def isRetryableError(+assistant: Ai.AssistantMessage<V.Value, Unit>, contextWindow: F64) -> Bool:
  Bool.and(Bool.not(Overflow.isContextOverflow(V.Value, Unit, assistant, contextWindow)), Retry.isRetryableAssistantError(V.Value, Unit, assistant))

def retryableLast(found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, contextWindow: F64) -> Bool:
  match found:
    case None{}: False{}
    case Some{assistant}: isRetryableError(assistant, contextWindow)

def willRetryAfterAgentEnd(state: Shared, messages: List<&2, Message()>) -> Bool:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{Retry.RetryPolicy{enabled, maxRetries, _, _}, attempt, contextWindow, _}}:
      Bool.and(enabled, Bool.and(Nat.is_lt(attempt, maxRetries), retryableLast(lastAssistantIn(messages, None{}), contextWindow)))

def sessionEventIn(state: Shared, event: SessionEvent()) -> AgentSessionEvent:
  match event:
    case T.AgentEnd{+messages}: AgentEnd{messages, willRetryAfterAgentEnd(state, messages)}
    case other: AgentEvent{other}

def assistantStop(assistant: Ai.AssistantMessage<V.Value, Unit>) -> Ai.StopReason:
  match assistant:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, stopReason, _, _, _, _, _}: stopReason

def assistantError(assistant: Ai.AssistantMessage<V.Value, Unit>) -> Maybe<&2, String>:
  match assistant:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, errorMessage, _, _, _}: errorMessage

def retryEnded(shared: R.Ref<Shared>, previous: Nat, success: Bool, finalError: Maybe<&2, String>) -> IO(Unit):
  match previous:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+_: emit(shared, AutoRetryEnd{success, previous, finalError})

# A successful assistant message resets the attempt counter at once, so
# attempts do not accumulate across the calls of one turn.
def succeededRetry(+shared: R.Ref<Shared>, stopReason: Ai.StopReason) -> IO(Unit):
  match stopReason:
    case Ai.Error{}: IO.pure(Unit, Unit{})
    case _:
      do IO<Unit>:
        previous : Nat <- R.modify(Shared, Nat, shared, current => resetAttempt(current))
        retryEnded(shared, previous, True{}, None{})

def settleRetry(shared: R.Ref<Shared>, event: SessionEvent()) -> IO(Unit):
  match event:
    case T.MessageEnd{T.LlmMessage{Ai.Assistant{assistant}}}: succeededRetry(shared, assistantStop(assistant))
    case _: IO.pure(Unit, Unit{})

def ready() -> Loop.Emission<Runtime.Error()>: Loop.EmissionReady{Done{Unit{}}}

# The agent's event handler: queue bookkeeping, listeners, then persistence.
def handleEvent(+shared: R.Ref<Shared>, input: Agent.Input<SessionEvent()>) -> IO(Loop.Emission<Runtime.Error()>):
  match input:
    case Agent.Input{+event, _}:
      do IO<Loop.Emission<Runtime.Error()>>:
        trimQueues(shared, startedText(event))
        state : Shared <- R.read(Shared, shared)
        emit(shared, sessionEventIn(state, event))
        persist(shared, event)
        settleRetry(shared, event)
        return ready()

# Callback bodies cannot copy their environment; the copy happens inside.
def handleAgentEvent(shared: R.Ref<Shared>, input: Agent.Input<SessionEvent()>) -> IO(Loop.Emission<Runtime.Error()>):
  handleEvent(shared, input)

# Lifecycle
# ---------

def create(+agent: Runtime.Owner(), session: Session(), +settings: Settings.SettingsManager, cwd: String) -> IO(AgentSession):
  do IO<AgentSession>:
    initial : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +shared : R.Ref<Shared> <- R.new(Shared, Shared{session, Nil{}, Nil{}, Nil{}, False{}, None{}, RetryState{retryPolicy(Settings.getRetrySettings(settings)), 0n, modelContextWindow(stateModel(initial)), None{}}})
    +handler : Agent.Handler(SessionEvent(), Runtime.Error()) <- C.create(~R.Ref<Shared>, ~Agent.Input<SessionEvent()>, ~Loop.Emission<Runtime.Error()>, ~handleAgentEvent, shared)
    subscription : Agent.Subscription<SessionEvent(), Runtime.Error()> <- Agent.subscribe(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, handler)
    return AgentSession{agent, shared, subscription, handler, settings, cwd}

# Listeners are the caller's callbacks: unsubscribe returns them to the caller.
def addListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}: Shared{session, steering, followUp, List.append(&2, Listener(), listeners, listener <> Nil{}), runActive, lastAssistant, retry}

def subscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _}: R.modify(Shared, Unit, shared, current => (addListener(current, listener), Unit{}))

def withoutListener(listeners: List<&2, Listener()>, +listener: Listener()) -> List<&2, Listener()>:
  match listeners:
    case Nil{}: Nil{}
    case +current <> +rest: Bool.pick(List<&2, Listener()>, C.same(AgentSessionEvent, Unit, current, listener), rest, current <> withoutListener(rest, listener))

def removedListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}: Shared{session, steering, followUp, withoutListener(listeners, listener), runActive, lastAssistant, retry}

def unsubscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _}: R.modify(Shared, Unit, shared, current => (removedListener(current, listener), Unit{}))

def sleepingOf(retry: RetryState) -> Maybe<&2, A.AbortController<Unit>>:
  match retry:
    case RetryState{_, _, _, sleeping}: sleeping

def abortController(sleeping: Maybe<&2, A.AbortController<Unit>>) -> IO(Unit):
  match sleeping:
    case None{}: IO.pure(Unit, Unit{})
    case Some{controller}:
      do IO<Unit>:
        won : Bool <- A.abort(Unit, controller, None{})
        return Unit{}

# upstream abortRetry: cancel a backoff sleep in progress.
def abortSleeping(shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    abortController(sleepingOf(retryOf(state)))

# Abort the agent and disconnect; the agent itself belongs to the runtime.
def dispose(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{agent, +shared, subscription, handler, _, _}:
      do IO<Unit>:
        abortSleeping(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.unsubscribe(SessionEvent(), Runtime.Error(), subscription)
        C.dispose(Agent.Input<SessionEvent()>, Loop.Emission<Runtime.Error()>, handler)
        released : Shared <- R.dispose(Shared, shared)
        return Unit{}

# State
# -----

def agentOf(session: AgentSession) -> Runtime.Owner():
  match session:
    case AgentSession{agent, _, _, _, _, _}: agent

def state(session: AgentSession) -> IO(AgentState()):
  Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

def sessionOf(session: AgentSession) -> IO(Session()):
  match session:
    case AgentSession{_, shared, _, _, _, _}:
      do IO<Session()>:
        current : Shared <- R.read(Shared, shared)
        return sharedSession(current)

def messages(session: AgentSession) -> IO(List<&2, Message()>):
  do IO<List<&2, Message()>>:
    current : AgentState() <- state(session)
    return stateMessages(current)

def runActiveOf(value: Shared) -> Bool:
  match value:
    case Shared{_, _, _, _, runActive, _, _}: runActive

def isStreaming(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _}:
      do IO<Bool>:
        current : Shared <- R.read(Shared, shared)
        return runActiveOf(current)

def assistantText(content: List<&2, Ai.AssistantContent<V.Value>>) -> String:
  match content:
    case Nil{}: ""
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text ++ assistantText(rest)
    case _ <> rest: assistantText(rest)

# upstream getLastAssistantText: the text of the last assistant message.
def assistantTextOf(assistant: Ai.AssistantMessage<V.Value, Unit>) -> String:
  match assistant:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: assistantText(content)

def getLastAssistantText(session: AgentSession) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    current : List<&2, Message()> <- messages(session)
    return Maybe.map(&2, Ai.AssistantMessage<V.Value, Unit>, String, assistant => assistantTextOf(assistant), lastAssistantIn(current, None{}))

# Prompting
# ---------

type StreamingBehavior is Data:
  Steer{}
  FollowUp{}

def promptError(error: Agent.AgentError<Runtime.Error()>) -> String:
  match error:
    case Agent.ClaimFailed{message}: message
    case Agent.DeliveryFailed{Agent.OutsideRun{message}}: message
    case Agent.DeliveryFailed{Agent.ListenerFailed{cause}}: Tools.errorMessage(cause)

def setRunActive(shared: R.Ref<Shared>, active: Bool) -> IO(Unit):
  R.modify(Shared, Unit, shared, current => (withRunActive(current, active), Unit{}))

def failure(result: Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{promptError(error)}
    case Done{Unit{}}: Done{Unit{}}

def resultBranch(outcome: Result<&2, &2, String, Unit>, continuation: Unit -> IO(Result<&2, &2, String, Unit>)) -> IO(Result<&2, &2, String, Unit>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{Unit{}}: continuation(Unit{})

# Continue while messages queued during the run remain (upstream's
# _handlePostAgentRun without retry and compaction). Bend's termination
# check needs a bound; a run never queues anywhere near this many.
def drainQueued(fuel: Nat, +agent: Runtime.Owner()) -> IO(Result<&2, &2, String, Unit>):
  match fuel:
    case 0n: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case 1n+remaining:
      do IO<Result<&2, &2, String, Unit>>:
        queued : Bool <- Agent.hasQueuedMessages(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), queued, _ => IO.bind(Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>, Result<&2, &2, String, Unit>, Agent.continueRun(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent), result => IO.bind(Unit, Result<&2, &2, String, Unit>, Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent), unused => resultBranch(failure(result), again => drainQueued(remaining, agent)))), _ => IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}}))(Unit{})

# One run's outcome and whether post-run handling continues the agent.
type Step is Data:
  Step{again: Bool, outcome: Result<&2, &2, String, Unit>}

def takeLastAssistant(state: Shared) -> Shared & Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry}: (Shared{session, steering, followUp, listeners, runActive, None{}, retry}, lastAssistant)

def contextWindowOf(state: Shared) -> F64:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{_, _, contextWindow, _}}: contextWindow

def errorText(errorMessage: Maybe<&2, String>) -> String:
  match errorMessage:
    case Some{SNil{}}: "Unknown error"
    case Some{text}: text
    case None{}: "Unknown error"

def errorMessageOf(assistant: Ai.AssistantMessage<V.Value, Unit>) -> String: errorText(assistantError(assistant))

def withoutTrailingAssistant(messages: List<&2, Message()>) -> Maybe<&2, List<&2, Message()>>:
  match messages:
    case Nil{}: None{}
    case T.LlmMessage{Ai.Assistant{_}} <> Nil{}: Some{Nil{}}
    case message <> rest: Maybe.map(&2, List<&2, Message()>, List<&2, Message()>, others => message <> others, withoutTrailingAssistant(rest))

def replaceIf(agent: Runtime.Owner(), trimmed: Maybe<&2, List<&2, Message()>>) -> IO(Unit):
  match trimmed:
    case None{}: IO.pure(Unit, Unit{})
    case Some{remaining}: Agent.replaceMessages(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, remaining)

# The failed assistant message leaves the agent's context; the session keeps it as history.
def withoutLastAssistant(+agent: Runtime.Owner()) -> IO(Unit):
  do IO<Unit>:
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    replaceIf(agent, withoutTrailingAssistant(stateMessages(current)))

# Node clamps timer delays beyond its range to one millisecond.
def sleepMilliseconds(delay: F64) -> U32:
  Result.default(&2, &2, Sleep.Error, U32, Sleep.milliseconds(delay), 1)

def sleptOutcome(+shared: R.Ref<Shared>, attempt: Nat, slept: Result<&2, &2, A.AbortReason<Unit>, Unit>) -> IO(Bool):
  match slept:
    case Done{_}: IO.pure(Bool, True{})
    case Fail{_}:
      do IO<Bool>:
        R.modify(Shared, Unit, shared, current => (withAttempt(current, 0n), Unit{}))
        emit(shared, AutoRetryEnd{False{}, attempt, Some{"Retry cancelled"}})
        return False{}

# Wait with exponential backoff; abortRetry cancels the sleep.
def backoff(+shared: R.Ref<Shared>, attempt: Nat, delay: F64) -> IO(Bool):
  do IO<Bool>:
    +controller : A.AbortController<Unit> <- A.new(Unit)
    R.modify(Shared, Unit, shared, current => (withSleeping(current, Some{controller}), Unit{}))
    slept : Result<&2, &2, A.AbortReason<Unit>, Unit> <- Sleep.sleep(Unit, sleepMilliseconds(delay), A.signal(Unit, controller))
    R.modify(Shared, Unit, shared, current => (withSleeping(current, None{}), Unit{}))
    A.dispose(Unit, controller)
    sleptOutcome(shared, attempt, slept)

def startRetry(agent: Runtime.Owner(), +shared: R.Ref<Shared>, assistant: Ai.AssistantMessage<V.Value, Unit>, +attempt: Nat, maxRetries: Nat, +delay: F64) -> IO(Bool):
  do IO<Bool>:
    R.modify(Shared, Unit, shared, current => (withAttempt(current, attempt), Unit{}))
    emit(shared, AutoRetryStart{attempt, maxRetries, delay, errorMessageOf(assistant)})
    withoutLastAssistant(agent)
    backoff(shared, attempt, delay)

# upstream _prepareRetry: true when the caller should continue the agent.
def prepareRetry(agent: Runtime.Owner(), +shared: R.Ref<Shared>, assistant: Ai.AssistantMessage<V.Value, Unit>, retry: RetryState) -> IO(Bool):
  match retry:
    case RetryState{Retry.RetryPolicy{False{}, _, _, _}, _, _, _}: IO.pure(Bool, False{})
    case RetryState{Retry.RetryPolicy{True{}, +maxRetries, baseDelayMs, maxAgentDelayMs}, +attempt, _, _}:
      Bool.pick(Unit -> IO(Bool), Nat.is_lt(maxRetries, Nat.add(attempt, 1n)), _ => IO.pure(Bool, False{}), _ => startRetry(agent, shared, assistant, Nat.add(attempt, 1n), maxRetries, Retry.retryDelayMs(baseDelayMs, maxAgentDelayMs, Nat.add(attempt, 1n))))(Unit{})

# A final error after retries reports the failure and resets the counter.
def failedRetry(+shared: R.Ref<Shared>, stopReason: Ai.StopReason, finalError: Maybe<&2, String>) -> IO(Unit):
  match stopReason:
    case Ai.Error{}:
      do IO<Unit>:
        previous : Nat <- R.modify(Shared, Nat, shared, current => resetAttempt(current))
        retryEnded(shared, previous, False{}, finalError)
    case _: IO.pure(Unit, Unit{})

def finishFailed(shared: R.Ref<Shared>, +assistant: Ai.AssistantMessage<V.Value, Unit>) -> IO(Bool):
  do IO<Bool>:
    failedRetry(shared, assistantStop(assistant), assistantError(assistant))
    return False{}

def retryOrFinish(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +assistant: Ai.AssistantMessage<V.Value, Unit>) -> IO(Bool):
  do IO<Bool>:
    state : Shared <- R.read(Shared, shared)
    prepared : Bool <- prepareRetry(agent, shared, assistant, retryOf(state))
    Bool.pick(Unit -> IO(Bool), prepared, _ => IO.pure(Bool, True{}), _ => finishFailed(shared, assistant))(Unit{})

def afterRun(agent: Runtime.Owner(), +shared: R.Ref<Shared>, taken: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, contextWindow: F64) -> IO(Bool):
  match taken:
    case None{}: IO.pure(Bool, False{})
    case Some{+assistant}: Bool.pick(Unit -> IO(Bool), isRetryableError(assistant, contextWindow), _ => retryOrFinish(agent, shared, assistant), _ => finishFailed(shared, assistant))(Unit{})

# upstream _handlePostAgentRun: retry a transient error (compaction follows later).
def handlePostAgentRun(agent: Runtime.Owner(), +shared: R.Ref<Shared>) -> IO(Bool):
  do IO<Bool>:
    taken : Maybe<&2, Ai.AssistantMessage<V.Value, Unit>> <- R.modify(Shared, Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, shared, current => takeLastAssistant(current))
    state : Shared <- R.read(Shared, shared)
    afterRun(agent, shared, taken, contextWindowOf(state))

def stepOf(+agent: Runtime.Owner(), shared: R.Ref<Shared>, result: Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>) -> IO(Step):
  match result:
    case Fail{error}: IO.pure(Step, Step{False{}, Fail{promptError(error)}})
    case Done{Unit{}}:
      do IO<Step>:
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        drained : Result<&2, &2, String, Unit> <- drainQueued(100000n, agent)
        again : Bool <- handlePostAgentRun(agent, shared)
        return Step{again, drained}

def continueRun(agent: Runtime.Owner()) -> IO(Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>):
  Agent.continueRun(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent)

# upstream _runAgentPrompt: continue the agent while post-run handling asks for it.
def runUntilSettled(fuel: Nat, +agent: Runtime.Owner(), +shared: R.Ref<Shared>, step: Step) -> IO(Result<&2, &2, String, Unit>):
  match fuel step:
    case _ Step{False{}, outcome}: IO.pure(Result<&2, &2, String, Unit>, outcome)
    case 0n Step{True{}, outcome}: IO.pure(Result<&2, &2, String, Unit>, outcome)
    case 1n+rest Step{True{}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- continueRun(agent)
        next : Step <- stepOf(agent, shared, result)
        runUntilSettled(rest, agent, shared, next)

def runAgentPrompt(session: AgentSession, input: Agent.PromptInput<Unit, Runtime.Details(), Runtime.Custom()>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        setRunActive(shared, True{})
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- Agent.prompt(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent, input)
        step : Step <- stepOf(agent, shared, result)
        outcome : Result<&2, &2, String, Unit> <- runUntilSettled(1000n, agent, shared, step)
        setRunActive(shared, False{})
        emit(shared, AgentSettled{})
        return outcome

def queued(state: Shared, behavior: StreamingBehavior, +text: String) -> Shared:
  match state behavior:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry} Steer{}: Shared{session, List.append(&2, String, steering, text <> Nil{}), followUp, listeners, runActive, lastAssistant, retry}
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry} FollowUp{}: Shared{session, steering, List.append(&2, String, followUp, text <> Nil{}), listeners, runActive, lastAssistant, retry}

def firstMessage(messages: List<&2, Message()>, fallback: Message()) -> Message():
  match messages:
    case message <> _: message
    case Nil{}: fallback

def userMessageAt(+text: String, images: List<&2, Ai.ImageContent>, +now: F64) -> Message():
  firstMessage(Agent.normalizePromptInputAt(Unit, Runtime.Details(), Runtime.Custom(), Agent.Text{text, images}, now), T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, now}}})

# Queue a message for the running agent: steering interrupts after the
# current turn, follow-ups wait for the run to end.
def deliverQueued(agent: Runtime.Owner(), +behavior: StreamingBehavior, +message: Message()) -> IO(Unit):
  match behavior:
    case Steer{}: Agent.steer(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, message)
    case FollowUp{}: Agent.followUp(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, message)

def queueAt(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +behavior: StreamingBehavior, +text: String, images: List<&2, Ai.ImageContent>, now: F64) -> IO(Unit):
  do IO<Unit>:
    R.modify(Shared, Unit, shared, current => (queued(current, behavior, text), Unit{}))
    deliverQueued(agent, behavior, userMessageAt(text, images, now))
    emitQueueUpdate(shared)

def queue(session: AgentSession, behavior: StreamingBehavior, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit):
  match session:
    case AgentSession{agent, shared, _, _, _, _}:
      do IO<Unit>:
        now : F64 <- Date.now()
        queueAt(agent, shared, behavior, text, images, now)

def steer(session: AgentSession, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit): queue(session, Steer{}, text, images)
def followUp(session: AgentSession, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit): queue(session, FollowUp{}, text, images)

def promptWhile(session: AgentSession, streaming: Bool, +text: String, +images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  match streaming behavior:
    case False{} _: runAgentPrompt(session, Agent.Text{text, images})
    case True{} None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message."})
    case True{} Some{chosen}:
      do IO<Result<&2, &2, String, Unit>>:
        queue(session, chosen, text, images)
        return Done{Unit{}}

# upstream prompt(): extension commands, skill and prompt-template expansion
# are not ported; while streaming the message is queued by streamingBehavior.
def prompt(+session: AgentSession, text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    streaming : Bool <- isStreaming(session)
    promptWhile(session, streaming, text, images, behavior)

def abortRetry(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _}: abortSleeping(shared)

def isRetrying(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, sleepingOf(retryOf(state))))

# upstream abort: cancel a retry sleep, then abort the agent.
def abort(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{agent, shared, _, _, _, _}:
      do IO<Unit>:
        abortSleeping(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)

def waitForIdle(session: AgentSession) -> IO(Unit):
  Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

# Mutations
# ---------

def recorded(shared: R.Ref<Shared>, outcome: Sessions.Outcome(Appended())) -> IO(Result<&2, &2, String, Unit>):
  match outcome:
    case Done{Sessions.Appended{session, _}}:
      do IO<Result<&2, &2, String, Unit>>:
        R.modify(Shared, Unit, shared, current => (withSession(current, session), Unit{}))
        return Done{Unit{}}
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{Sessions.message(error)})

def clamped(value: AgentState(), level: Ai.ModelThinkingLevel) -> Ai.ModelThinkingLevel:
  AiModels.clampThinkingLevel(Ai.JsonValue, stateModel(value), level)

# upstream setThinkingLevel: clamp to the model, apply, record, notify.
def applyThinking(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +chosen: Ai.ModelThinkingLevel) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Agent.setThinkingLevel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, chosen)
    stored : Shared <- R.read(Shared, shared)
    outcome : Sessions.Outcome(Appended()) <- recordThinking(sharedSession(stored), chosen)
    result : Result<&2, &2, String, Unit> <- recorded(shared, outcome)
    emit(shared, ThinkingLevelChanged{chosen})
    return result

def setThinkingLevel(session: AgentSession, level: Ai.ModelThinkingLevel) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, shared, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        applyThinking(agent, shared, clamped(current, level))

# upstream setModel: apply the model, keep the thinking level within its
# range, record the change (extension model_select events are not ported).
def stateThinking(value: AgentState()) -> Ai.ModelThinkingLevel:
  match value:
    case T.AgentState{_, thinking, _, _, _, _, _, _}: thinking

def setModel(+session: AgentSession, +model: Ai.Model<Ai.JsonValue>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.setModel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, model)
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.setThinkingLevel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, clamped(current, stateThinking(current)))
        R.modify(Shared, Unit, shared, current => (withContextWindow(current, modelContextWindow(model)), Unit{}))
        stored : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordModel(sharedSession(stored), model)
        recorded(shared, outcome)

# upstream setSessionName: record the name and notify.
def setSessionName(session: AgentSession, +name: String) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, +shared, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        stored : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordName(sharedSession(stored), name)
        result : Result<&2, &2, String, Unit> <- recorded(shared, outcome)
        emit(shared, SessionInfoChanged{Some{name}})
        return result
