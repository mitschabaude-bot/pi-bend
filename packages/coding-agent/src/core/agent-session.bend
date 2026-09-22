import Base
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/types.bend as T
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/thinking-levels.bend as Levels
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
# records model, thinking-level and name changes as session entries.
# Compaction, automatic retry, bash execution, extensions, skills, prompt
# templates and tree navigation are not ported yet.

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

# Events
# ------
# Agent events are embedded in one constructor (upstream spreads the union);
# agent_end carries willRetry, which is false until automatic retry is ported.

type AgentSessionEvent is Data:
  AgentEvent{event: SessionEvent()}
  AgentEnd{messages: List<&2, Message()>, willRetry: Bool}
  AgentSettled{}
  QueueUpdate{steering: List<&2, String>, followUp: List<&2, String>}
  SessionInfoChanged{name: Maybe<&2, String>}
  ThinkingLevelChanged{level: Ai.ModelThinkingLevel}

def Listener() -> Data: C.Callback<AgentSessionEvent, Unit>

# The mutable session state shared with the agent's event handler.
type Shared is Data:
  Shared{session: Session(), steering: List<&2, String>, followUp: List<&2, String>, listeners: List<&2, Listener()>, runActive: Bool, lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>}

type AgentSession is Data:
  AgentSession{agent: Runtime.Owner(), shared: R.Ref<Shared>, subscription: Agent.Subscription<SessionEvent(), Runtime.Error()>, handler: Agent.Handler(SessionEvent(), Runtime.Error()), settings: Settings.SettingsManager, cwd: String}

def sharedSession(state: Shared) -> Session():
  match state:
    case Shared{session, _, _, _, _, _}: session

def withSession(state: Shared, session: Session()) -> Shared:
  match state:
    case Shared{_, steering, followUp, listeners, runActive, lastAssistant}: Shared{session, steering, followUp, listeners, runActive, lastAssistant}

def withRunActive(state: Shared, runActive: Bool) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, _, lastAssistant}: Shared{session, steering, followUp, listeners, runActive, lastAssistant}

def deliver(listeners: List<&2, Listener()>, +event: AgentSessionEvent) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit, Unit{})
    case listener <> rest:
      do IO<Unit>:
        C.call(AgentSessionEvent, Unit, listener, event)
        deliver(rest, event)

def listenersOf(state: Shared) -> List<&2, Listener()>:
  match state:
    case Shared{_, _, _, listeners, _, _}: listeners

def emit(shared: R.Ref<Shared>, event: AgentSessionEvent) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    deliver(listenersOf(state), event)

def queueEvent(state: Shared) -> AgentSessionEvent:
  match state:
    case Shared{_, steering, followUp, _, _, _}: QueueUpdate{steering, followUp}

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

def dequeuedFrom(+session: Session(), +steering: List<&2, String>, +followUp: List<&2, String>, listeners: List<&2, Listener()>, +runActive: Bool, +lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, fromSteering: Maybe<&2, List<&2, String>>, fromFollowUp: Maybe<&2, List<&2, String>>) -> Shared & Bool:
  match fromSteering fromFollowUp:
    case Some{remaining} _: (Shared{session, remaining, followUp, listeners, runActive, lastAssistant}, True{})
    case None{} Some{remaining}: (Shared{session, steering, remaining, listeners, runActive, lastAssistant}, True{})
    case None{} None{}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant}, False{})

# The steering queue is searched first, then the follow-up queue, as upstream.
def dequeued(state: Shared, +text: String) -> Shared & Bool:
  match state:
    case Shared{session, +steering, +followUp, listeners, runActive, lastAssistant}:
      dequeuedFrom(session, steering, followUp, listeners, runActive, lastAssistant, removeFirst(steering, text), removeFirst(followUp, text))

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
    case Shared{session, steering, followUp, listeners, runActive, _}: Shared{session, steering, followUp, listeners, runActive, Some{assistant}}

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

def sessionEvent(event: SessionEvent()) -> AgentSessionEvent:
  match event:
    case T.AgentEnd{messages}: AgentEnd{messages, False{}}
    case other: AgentEvent{other}

def ready() -> Loop.Emission<Runtime.Error()>: Loop.EmissionReady{Done{Unit{}}}

# The agent's event handler: queue bookkeeping, listeners, then persistence.
def handleEvent(+shared: R.Ref<Shared>, input: Agent.Input<SessionEvent()>) -> IO(Loop.Emission<Runtime.Error()>):
  match input:
    case Agent.Input{+event, _}:
      do IO<Loop.Emission<Runtime.Error()>>:
        trimQueues(shared, startedText(event))
        emit(shared, sessionEvent(event))
        persist(shared, event)
        return ready()

# Callback bodies cannot copy their environment; the copy happens inside.
def handleAgentEvent(shared: R.Ref<Shared>, input: Agent.Input<SessionEvent()>) -> IO(Loop.Emission<Runtime.Error()>):
  handleEvent(shared, input)

# Lifecycle
# ---------

def create(+agent: Runtime.Owner(), session: Session(), settings: Settings.SettingsManager, cwd: String) -> IO(AgentSession):
  do IO<AgentSession>:
    +shared : R.Ref<Shared> <- R.new(Shared, Shared{session, Nil{}, Nil{}, Nil{}, False{}, None{}})
    +handler : Agent.Handler(SessionEvent(), Runtime.Error()) <- C.create(~R.Ref<Shared>, ~Agent.Input<SessionEvent()>, ~Loop.Emission<Runtime.Error()>, ~handleAgentEvent, shared)
    subscription : Agent.Subscription<SessionEvent(), Runtime.Error()> <- Agent.subscribe(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, handler)
    return AgentSession{agent, shared, subscription, handler, settings, cwd}

# Listeners are the caller's callbacks: unsubscribe returns them to the caller.
def addListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant}: Shared{session, steering, followUp, List.append(&2, Listener(), listeners, listener <> Nil{}), runActive, lastAssistant}

def subscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _}: R.modify(Shared, Unit, shared, current => (addListener(current, listener), Unit{}))

def withoutListener(listeners: List<&2, Listener()>, +listener: Listener()) -> List<&2, Listener()>:
  match listeners:
    case Nil{}: Nil{}
    case +current <> +rest: Bool.pick(List<&2, Listener()>, C.same(AgentSessionEvent, Unit, current, listener), rest, current <> withoutListener(rest, listener))

def removedListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant}: Shared{session, steering, followUp, withoutListener(listeners, listener), runActive, lastAssistant}

def unsubscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _}: R.modify(Shared, Unit, shared, current => (removedListener(current, listener), Unit{}))

# Abort the agent and disconnect; the agent itself belongs to the runtime.
def dispose(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{agent, shared, subscription, handler, _, _}:
      do IO<Unit>:
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

def stateMessages(value: AgentState()) -> List<&2, Message()>:
  match value:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def stateModel(value: AgentState()) -> Ai.Model<Ai.JsonValue>:
  match value:
    case T.AgentState{model, _, _, _, _, _, _, _}: model

def messages(session: AgentSession) -> IO(List<&2, Message()>):
  do IO<List<&2, Message()>>:
    current : AgentState() <- state(session)
    return stateMessages(current)

def runActiveOf(value: Shared) -> Bool:
  match value:
    case Shared{_, _, _, _, runActive, _}: runActive

def isStreaming(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _}:
      do IO<Bool>:
        current : Shared <- R.read(Shared, shared)
        return runActiveOf(current)

def lastAssistantIn(messages: List<&2, Message()>, +found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match messages:
    case Nil{}: found
    case T.LlmMessage{Ai.Assistant{assistant}} <> rest: lastAssistantIn(rest, Some{assistant})
    case _ <> rest: lastAssistantIn(rest, found)

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

def settled(+agent: Runtime.Owner(), result: Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{promptError(error)})
    case Done{Unit{}}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        drainQueued(100000n, agent)

def runAgentPrompt(session: AgentSession, input: Agent.PromptInput<Unit, Runtime.Details(), Runtime.Custom()>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        setRunActive(shared, True{})
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- Agent.prompt(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent, input)
        outcome : Result<&2, &2, String, Unit> <- settled(agent, result)
        setRunActive(shared, False{})
        emit(shared, AgentSettled{})
        return outcome

def queued(state: Shared, behavior: StreamingBehavior, +text: String) -> Shared:
  match state behavior:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant} Steer{}: Shared{session, List.append(&2, String, steering, text <> Nil{}), followUp, listeners, runActive, lastAssistant}
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant} FollowUp{}: Shared{session, steering, List.append(&2, String, followUp, text <> Nil{}), listeners, runActive, lastAssistant}

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

def abort(session: AgentSession) -> IO(Unit):
  Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

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
