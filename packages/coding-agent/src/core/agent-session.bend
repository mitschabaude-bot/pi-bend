import Base
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/types.bend as T
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../ai/src/utils/retry.bend as Retry
import ../../../ai/src/utils/overflow.bend as Overflow
import ../../../ai/src/utils/event-stream.bend as Stream
import ../../../ai/src/utils/estimate.bend as Estimate
import ../../../ai/src/utils/model-api.bend as ModelApi
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../runtime/src/fetch.bend as Fetch
import ./compaction/compaction.bend as Compaction
import ./compaction/plan.bend as Plan
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/timer.bend as Sleep
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/record.bend as Rec
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
# records model, thinking-level and name changes as session entries,
# retries transient provider errors with the settings' backoff policy, and
# compacts the context manually or when it overflows or crosses the
# settings' threshold. Bash execution, extensions, skills, prompt templates,
# tree navigation and the mid-run threshold check are not ported yet.

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

def textsValue(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> textsValue(rest)

def detailsValue(details: Compaction.CompactionDetails) -> V.Value:
  match details:
    case Compaction.CompactionDetails{readFiles, modifiedFiles}: V.ObjectValue{Rec.Record{Rec.Property{"readFiles", V.ArrayValue{textsValue(readFiles)}} <> Rec.Property{"modifiedFiles", V.ArrayValue{textsValue(modifiedFiles)}} <> Nil{}}}

def textsOf(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{text} <> rest: text <> textsOf(rest)
    case _ <> rest: textsOf(rest)

def textList(value: Maybe<&2, V.Value>) -> List<&2, String>:
  match value:
    case Some{V.ArrayValue{values}}: textsOf(values)
    case _: Nil{}

# Stored compaction details: the read and modified file lists, when present.
def detailsOf(value: V.Value) -> Maybe<&2, Compaction.CompactionDetails>:
  match value:
    case V.ObjectValue{+record}: Some{Compaction.CompactionDetails{textList(Rec.get(V.Value, record, "readFiles")), textList(Rec.get(V.Value, record, "modifiedFiles"))}}
    case _: None{}

def recordCompaction(session: Session(), summary: String, firstKeptEntryId: String, tokensBefore: Nat, details: Maybe<&2, Compaction.CompactionDetails>, usage: Maybe<&2, Ai.Usage>) -> IO(Sessions.Outcome(Appended())):
  Sessions.appendCompaction(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, summary, Some{firstKeptEntryId}, tokensBefore, Maybe.map(&2, Compaction.CompactionDetails, V.Value, detailsValue, details), Some{False{}}, usage)

def recordModel(session: Session(), model: Ai.Model<Ai.JsonValue>) -> IO(Sessions.Outcome(Appended())):
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Sessions.appendModelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, provider, id)

def stateMessages(value: AgentState()) -> List<&2, Message()>:
  match value:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def stateModel(value: AgentState()) -> Ai.Model<Ai.JsonValue>:
  match value:
    case T.AgentState{model, _, _, _, _, _, _, _}: model

def modelIdentity(model: Ai.Model<Ai.JsonValue>) -> Settings.ModelIdentity:
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Settings.ModelIdentity{provider, id}

def stateThinking(value: AgentState()) -> Ai.ModelThinkingLevel:
  match value:
    case T.AgentState{_, thinking, _, _, _, _, _, _}: thinking

def lastAssistantIn(messages: List<&2, Message()>, +found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match messages:
    case Nil{}: found
    case T.LlmMessage{Ai.Assistant{assistant}} <> rest: lastAssistantIn(rest, Some{assistant})
    case _ <> rest: lastAssistantIn(rest, found)

# Events
# ------
# Agent events are embedded in one constructor (upstream spreads the union);
# agent_end carries willRetry when the run will continue with a retry.

type CompactionReason is Data:
  Manual{}
  Threshold{}
  Overflow{}

type RetrySource is Data:
  BranchSummarySource{}
  CompactionSource{reason: CompactionReason}

type AgentSessionEvent is Data:
  AgentEvent{event: SessionEvent()}
  AgentEnd{messages: List<&2, Message()>, willRetry: Bool}
  AgentSettled{}
  QueueUpdate{steering: List<&2, String>, followUp: List<&2, String>}
  SessionInfoChanged{name: Maybe<&2, String>}
  ThinkingLevelChanged{level: Ai.ModelThinkingLevel}
  AutoRetryStart{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  AutoRetryEnd{success: Bool, attempt: Nat, finalError: Maybe<&2, String>}
  CompactionStart{reason: CompactionReason}
  CompactionEnd{reason: CompactionReason, result: Maybe<&2, Compaction.CompactionResult>, aborted: Bool, willRetry: Bool, errorMessage: Maybe<&2, String>}
  SummarizationRetryScheduled{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  SummarizationRetryAttemptStart{source: RetrySource}
  SummarizationRetryFinished{}

def Listener() -> Data: C.Callback<AgentSessionEvent, Unit>

# Automatic retry bookkeeping: the settings' policy, the current attempt, the
# model's context window (overflow belongs to compaction, not retry) and the
# abort controller of a backoff sleep in progress.
type RetryState is Data:
  RetryState{policy: Retry.RetryPolicy, attempt: Nat, contextWindow: F64, sleeping: Maybe<&2, A.AbortController<Unit>>}

# Compaction bookkeeping: whether the one compact-and-retry overflow
# recovery was spent, and the abort controllers of manual and automatic
# compactions in progress.
type CompactionState is Data:
  CompactionState{overflowRecoveryAttempted: Bool, manual: Maybe<&2, A.AbortController<Unit>>, auto: Maybe<&2, A.AbortController<Unit>>}

# The mutable session state shared with the agent's event handler.
type Shared is Data:
  Shared{session: Session(), steering: List<&2, String>, followUp: List<&2, String>, listeners: List<&2, Listener()>, runActive: Bool, lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, retry: RetryState, compaction: CompactionState}

def Turn() -> Data: Agent.Turn(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())
def TurnUpdate() -> Data: Agent.Update(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())
def TurnResult() -> Data: Agent.PrepareResult(TurnUpdate(), Runtime.Error())
def NextTurnHook() -> Data: Agent.ContextHook(Turn(), TurnUpdate(), Runtime.Error())
def LegacyTurnHook() -> Data: Agent.LegacyHook(TurnUpdate(), Runtime.Error())

# The session's handles on the agent: its event subscription and the
# next-turn hook that replaced the agent's own (restored on dispose).
type SessionHooks is Data:
  SessionHooks{subscription: Agent.Subscription<SessionEvent(), Runtime.Error()>, handler: Agent.Handler(SessionEvent(), Runtime.Error()), nextTurn: NextTurnHook(), replaced: Maybe<&2, NextTurnHook()>}

type AgentSession is Data:
  AgentSession{agent: Runtime.Owner(), shared: R.Ref<Shared>, hooks: SessionHooks, settings: Settings.SettingsManager, cwd: String}

def sharedSession(state: Shared) -> Session():
  match state:
    case Shared{session, _, _, _, _, _, _, _}: session

def withSession(state: Shared, session: Session()) -> Shared:
  match state:
    case Shared{_, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}

def withRunActive(state: Shared, runActive: Bool) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, _, lastAssistant, retry, compaction}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}

def deliver(listeners: List<&2, Listener()>, +event: AgentSessionEvent) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit, Unit{})
    case listener <> rest:
      do IO<Unit>:
        C.call(AgentSessionEvent, Unit, listener, event)
        deliver(rest, event)

def listenersOf(state: Shared) -> List<&2, Listener()>:
  match state:
    case Shared{_, _, _, listeners, _, _, _, _}: listeners

def emit(shared: R.Ref<Shared>, event: AgentSessionEvent) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    deliver(listenersOf(state), event)

def queueEvent(state: Shared) -> AgentSessionEvent:
  match state:
    case Shared{_, steering, followUp, _, _, _, _, _}: QueueUpdate{steering, followUp}

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

def dequeuedFrom(+session: Session(), +steering: List<&2, String>, +followUp: List<&2, String>, listeners: List<&2, Listener()>, +runActive: Bool, +lastAssistant: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, +retry: RetryState, +compaction: CompactionState, fromSteering: Maybe<&2, List<&2, String>>, fromFollowUp: Maybe<&2, List<&2, String>>) -> Shared & Bool:
  match fromSteering fromFollowUp:
    case Some{remaining} _: (Shared{session, remaining, followUp, listeners, runActive, lastAssistant, retry, compaction}, True{})
    case None{} Some{remaining}: (Shared{session, steering, remaining, listeners, runActive, lastAssistant, retry, compaction}, True{})
    case None{} None{}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}, False{})

# The steering queue is searched first, then the follow-up queue, as upstream.
def dequeued(state: Shared, +text: String) -> Shared & Bool:
  match state:
    case Shared{session, +steering, +followUp, listeners, runActive, lastAssistant, retry, compaction}:
      dequeuedFrom(session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, removeFirst(steering, text), removeFirst(followUp, text))

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
    case Shared{session, steering, followUp, listeners, runActive, _, retry, compaction}: Shared{session, steering, followUp, listeners, runActive, Some{assistant}, retry, compaction}

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
    case Shared{_, _, _, _, _, _, retry, _}: retry

def withAttempt(state: Shared, attempt: Nat) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, _, contextWindow, sleeping}, compaction}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction}

# Clears the attempt counter and returns the count it had.
def resetAttempt(state: Shared) -> Shared & Nat:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, previous, contextWindow, sleeping}, compaction}:
      (Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, 0n, contextWindow, sleeping}, compaction}, previous)

def withSleeping(state: Shared, sleeping: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, _}, compaction}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction}

def withContextWindow(state: Shared, contextWindow: F64) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, _, sleeping}, compaction}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction}

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
    case Shared{_, _, _, _, _, _, RetryState{Retry.RetryPolicy{enabled, maxRetries, _, _}, attempt, contextWindow, _}, _}:
      Bool.and(enabled, Bool.and(Nat.is_lt(attempt, maxRetries), retryableLast(lastAssistantIn(messages, None{}), contextWindow)))

def sessionEventIn(state: Shared, event: SessionEvent()) -> AgentSessionEvent:
  match event:
    case T.AgentEnd{+messages}: AgentEnd{messages, willRetryAfterAgentEnd(state, messages)}
    case other: AgentEvent{other}

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

def markOverflow(state: Shared, attempted: Bool) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{_, manual, auto}}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto}}

# A completed or aborted assistant message re-arms the one overflow recovery.
def settleOverflow(shared: R.Ref<Shared>, stopReason: Ai.StopReason) -> IO(Unit):
  match stopReason:
    case Ai.Error{}: IO.pure(Unit, Unit{})
    case Ai.Length{}: IO.pure(Unit, Unit{})
    case _: R.modify(Shared, Unit, shared, current => (markOverflow(current, False{}), Unit{}))

def settleRetry(+shared: R.Ref<Shared>, event: SessionEvent()) -> IO(Unit):
  match event:
    case T.MessageEnd{T.LlmMessage{Ai.Assistant{+assistant}}}:
      do IO<Unit>:
        settleOverflow(shared, Ai.assistantStopReason(V.Value, Unit, assistant))
        succeededRetry(shared, Ai.assistantStopReason(V.Value, Unit, assistant))
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
# create follows the compaction section, whose next-turn hook it installs.

# Listeners are the caller's callbacks: unsubscribe returns them to the caller.
def addListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}: Shared{session, steering, followUp, List.append(&2, Listener(), listeners, listener <> Nil{}), runActive, lastAssistant, retry, compaction}

def subscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _}: R.modify(Shared, Unit, shared, current => (addListener(current, listener), Unit{}))

def withoutListener(listeners: List<&2, Listener()>, +listener: Listener()) -> List<&2, Listener()>:
  match listeners:
    case Nil{}: Nil{}
    case +current <> +rest: Bool.pick(List<&2, Listener()>, C.same(AgentSessionEvent, Unit, current, listener), rest, current <> withoutListener(rest, listener))

def removedListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}: Shared{session, steering, followUp, withoutListener(listeners, listener), runActive, lastAssistant, retry, compaction}

def unsubscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _}: R.modify(Shared, Unit, shared, current => (removedListener(current, listener), Unit{}))

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

def abortBoth(compaction: CompactionState) -> IO(Unit):
  match compaction:
    case CompactionState{_, manual, auto}:
      do IO<Unit>:
        abortController(manual)
        abortController(auto)

def compactionOf(state: Shared) -> CompactionState:
  match state:
    case Shared{_, _, _, _, _, _, _, compaction}: compaction

# upstream abortCompaction: cancel manual and automatic compaction in progress.
def abortCompactions(shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    abortBoth(compactionOf(state))

# Abort the agent and disconnect; the agent itself belongs to the runtime.
def dispose(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{+agent, +shared, SessionHooks{subscription, handler, nextTurn, replaced}, _, _}:
      do IO<Unit>:
        abortSleeping(shared)
        abortCompactions(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.unsubscribe(SessionEvent(), Runtime.Error(), subscription)
        C.dispose(Agent.Input<SessionEvent()>, Loop.Emission<Runtime.Error()>, handler)
        Agent.setPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, replaced)
        C.dispose(T.ToolHookInput<Turn()>, TurnResult(), nextTurn)
        released : Shared <- R.dispose(Shared, shared)
        return Unit{}

# State
# -----

def agentOf(session: AgentSession) -> Runtime.Owner():
  match session:
    case AgentSession{agent, _, _, _, _}: agent

def state(session: AgentSession) -> IO(AgentState()):
  Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

def sessionOf(session: AgentSession) -> IO(Session()):
  match session:
    case AgentSession{_, shared, _, _, _}:
      do IO<Session()>:
        current : Shared <- R.read(Shared, shared)
        return sharedSession(current)

def messages(session: AgentSession) -> IO(List<&2, Message()>):
  do IO<List<&2, Message()>>:
    current : AgentState() <- state(session)
    return stateMessages(current)

def runActiveOf(value: Shared) -> Bool:
  match value:
    case Shared{_, _, _, _, runActive, _, _, _}: runActive

def isStreaming(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _}:
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
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction}: (Shared{session, steering, followUp, listeners, runActive, None{}, retry, compaction}, lastAssistant)

def contextWindowOf(state: Shared) -> F64:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{_, _, contextWindow, _}, _}: contextWindow

def errorText(errorMessage: Maybe<&2, String>) -> String:
  match errorMessage:
    case Some{SNil{}}: "Unknown error"
    case Some{text}: text
    case None{}: "Unknown error"

def errorMessageOf(assistant: Ai.AssistantMessage<V.Value, Unit>) -> String: errorText(Ai.assistantErrorMessage(V.Value, Unit, assistant))

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

# Compaction
# ----------
# upstream _checkCompaction, _runAutoCompaction and compact(): overflow or
# threshold compaction after a run and before a prompt, manual compaction on
# request. The summarizer sends each request through the agent's stream
# function under a fresh request id, the settings' retry policy and
# per-attempt notices; extension hooks around compaction are not ported.

def setManualController(state: Shared, manual: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, _, auto}}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto}}

def setAutoController(state: Shared, auto: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, _}}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto}}

def overflowAttemptedOf(state: Shared) -> Bool:
  match state:
    case Shared{_, _, _, _, _, _, _, CompactionState{attempted, _, _}}: attempted

def policyOf(state: Shared) -> Retry.RetryPolicy:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{policy, _, _, _}, _}: policy

def compactionSettingsOf(resolved: Settings.ResolvedCompactionSettings) -> Compaction.CompactionSettings:
  match resolved:
    case Settings.ResolvedCompactionSettings{enabled, reserveTokens, keepRecentTokens}: Compaction.CompactionSettings{enabled, F.fromU64(reserveTokens), F.fromU64(keepRecentTokens)}

def compactionSettingsFor(settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>) -> Compaction.CompactionSettings:
  compactionSettingsOf(Settings.getCompactionSettings(settings, Some{modelIdentity(model)}))

def Entry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

def branchOf(session: Session()) -> List<&2, Entry()>:
  Result.default(&2, &2, S.Error, List<&2, Entry()>, S.getBranch(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session), S.Latest{}), Nil{})

def branchEntries(shared: R.Ref<Shared>) -> IO(List<&2, Entry()>):
  do IO<List<&2, Entry()>>:
    state : Shared <- R.read(Shared, shared)
    return branchOf(sharedSession(state))

def parsedTime(parsed: Result<&2, &2, Date.ParseError, F64>) -> Maybe<&2, F64>:
  match parsed:
    case Done{time}: Some{time}
    case Fail{_}: None{}

def compactionTime(entry: Maybe<&2, S.CompactionEntry<V.Value>>) -> Maybe<&2, F64>:
  match entry:
    case Some{S.CompactionEntry{S.SessionEntryBase{_, _, timestamp}, _, _, _, _, _, _, _}}: parsedTime(Date.parseIso(timestamp))
    case None{}: None{}

# The latest compaction boundary as a millisecond time; messages from before
# it must not retrigger compaction.
def compactionTimestamp(entries: List<&2, Entry()>) -> Maybe<&2, F64>:
  compactionTime(S.getLatestCompactionEntry(Unit, Tools.ToolDetails, V.Value, entries))

def isAborted(stopReason: Ai.StopReason) -> Bool:
  match stopReason:
    case Ai.Aborted{}: True{}
    case _: False{}

def isErrorStop(stopReason: Ai.StopReason) -> Bool:
  match stopReason:
    case Ai.Error{}: True{}
    case _: False{}

def isStop(stopReason: Ai.StopReason) -> Bool:
  match stopReason:
    case Ai.Stop{}: True{}
    case _: False{}

def notAfter(time: F64, boundary: Maybe<&2, F64>) -> Bool:
  match boundary:
    case None{}: False{}
    case Some{value}: F.isAtMost(F.compare(time, value))

def staleAnchor(message: Maybe<&2, Message()>, boundary: Maybe<&2, F64>) -> Bool:
  match message:
    case Some{T.LlmMessage{Ai.Assistant{assistant}}}: notAfter(Ai.assistantTimestamp(V.Value, Unit, assistant), boundary)
    case _: False{}

# A usage-backed estimate whose anchor predates the compaction is stale.
def estimateChecked(messages: List<&2, Message()>, boundary: Maybe<&2, F64>, estimate: Estimate.ContextUsageEstimate) -> Maybe<&2, F64>:
  match estimate:
    case Estimate.ContextUsageEstimate{tokens, _, _, None{}}: Some{tokens}
    case Estimate.ContextUsageEstimate{tokens, _, _, Some{index}}: Bool.pick(Maybe<&2, F64>, staleAnchor(List.get(&2, Message(), messages, index), boundary), None{}, Some{tokens})

def usageOrEstimate(estimated: Bool, direct: F64, +messages: List<&2, Message()>, boundary: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match estimated:
    case True{}: estimateChecked(messages, boundary, Compaction.estimateContextTokens(Unit, Tools.ToolDetails, V.Value, messages))
    case False{}: Some{direct}

# Error or zero-usage messages fall back to the estimate from the context.
def thresholdTokens(+assistant: Ai.AssistantMessage<V.Value, Unit>, messages: List<&2, Message()>, boundary: Maybe<&2, F64>) -> Maybe<&2, F64>:
  +direct = Compaction.calculateContextTokens(Ai.assistantUsage(V.Value, Unit, assistant))
  usageOrEstimate(Bool.or(isErrorStop(Ai.assistantStopReason(V.Value, Unit, assistant)), F.isEqual(F.compare(direct, F.fromU32(0)))), direct, messages, boundary)

def enabledOf(settings: Compaction.CompactionSettings) -> Bool:
  match settings:
    case Compaction.CompactionSettings{enabled, _, _}: enabled

def thresholdReached(settings: Compaction.CompactionSettings, contextWindow: F64, tokens: Maybe<&2, F64>) -> Bool:
  match tokens:
    case None{}: False{}
    case Some{value}: Compaction.shouldCompact(value, contextWindow, settings)

# Disabled compaction, a skipped aborted message and a message from before
# the latest compaction never compact.
def skipsCheck(settings: Compaction.CompactionSettings, skipAborted: Bool, +assistant: Ai.AssistantMessage<V.Value, Unit>, boundary: Maybe<&2, F64>) -> Bool:
  Bool.or(Bool.not(enabledOf(settings)), Bool.or(Bool.and(skipAborted, isAborted(Ai.assistantStopReason(V.Value, Unit, assistant))), notAfter(Ai.assistantTimestamp(V.Value, Unit, assistant), boundary)))

# upstream _checkCompaction's decision (Plan.decideCompaction) from the
# assistant message, the model and the session's compaction boundary.
def planCompaction(+settings: Compaction.CompactionSettings, skipAborted: Bool, +assistant: Ai.AssistantMessage<V.Value, Unit>, +model: Ai.Model<Ai.JsonValue>, +boundary: Maybe<&2, F64>, messages: List<&2, Message()>, attempted: Bool) -> Plan.CompactionPlan:
  +sameModel = Bool.and(String.eq(Ai.assistantProvider(V.Value, Unit, assistant), Ai.modelProvider(model)), String.eq(Ai.assistantModel(V.Value, Unit, assistant), Ai.modelId(model)))
  Plan.decideCompaction(skipsCheck(settings, skipAborted, assistant, boundary), Bool.and(sameModel, Overflow.isContextOverflow(V.Value, Unit, assistant, Ai.modelContextWindow(model))), Bool.and(sameModel, Overflow.isRecoverableLength(V.Value, Unit, assistant, Ai.modelMaxTokens(model))), isStop(Ai.assistantStopReason(V.Value, Unit, assistant)), attempted, thresholdReached(settings, Ai.modelContextWindow(model), thresholdTokens(assistant, messages, boundary)))

# The summarizer: the agent's stream function with fresh options.
type SummarizerEnv is Data:
  SummarizerEnv{stream: Runtime.Stream(), config: Runtime.LoopConfig(), model: Ai.Model<Ai.JsonValue>, thinking: Ai.ModelThinkingLevel, signal: A.AbortSignal<Unit>, requestId: String}

def reasoningOption(model: Ai.Model<Ai.JsonValue>, thinking: Ai.ModelThinkingLevel) -> Maybe<&2, Ai.ThinkingLevel>:
  match thinking:
    case Ai.Off{}: None{}
    case Ai.Thinking{level}: Bool.pick(Maybe<&2, Ai.ThinkingLevel>, Ai.modelReasoning(model), Some{level}, None{})

def summaryOptions(model: Ai.Model<Ai.JsonValue>, thinking: Ai.ModelThinkingLevel, signal: A.AbortSignal<Unit>, requestId: String, maxTokens: F64) -> Ai.SimpleStreamOptions<Ai.JsonValue, A.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error()>:
  Ai.SimpleStreamOptions{Some{signal}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{maxTokens}, None{}, Some{Ai.CacheNone{}}, Some{requestId}, None{}, None{}, None{}, reasoningOption(model, thinking), None{}, None{}}

def summaryConfig(config: Runtime.LoopConfig(), model: Ai.Model<Ai.JsonValue>, options: Ai.SimpleStreamOptions<Ai.JsonValue, A.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error()>) -> Runtime.LoopConfig():
  match config:
    case T.AgentLoopConfig{_, _, convertToLlm, transformContext, getApiKey, finishTurn, prepareRequest, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}:
      T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, finishTurn, prepareRequest, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def errorReply(model: Ai.Model<Ai.JsonValue>, message: String, now: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Ai.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, Agent.emptyUsage(), Ai.Error{}, None{}, Some{message}, None{}, None{}, now}

def leaseMessage(model: Ai.Model<Ai.JsonValue>, response: Result<&2, &1, Runtime.Error(), T.StreamLease<Unit, Runtime.Error()>>) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match response:
    case Fail{error}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        now : F64 <- Date.now()
        return errorReply(model, Runtime.render(error), now)
    case Done{T.StreamLease{events, release}}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        message : Ai.AssistantMessage<V.Value, Unit> <- Stream.resultValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        released : Result<&2, &2, Runtime.Error(), Unit> <- release
        return message

def summarizeWith(env: SummarizerEnv, request: Compaction.SummaryRequest<Unit, Tools.ToolDetails>) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match env request:
    case SummarizerEnv{stream, config, +model, thinking, signal, requestId} Compaction.SummaryRequest{context, maxTokens}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        response : Result<&2, &1, Runtime.Error(), T.StreamLease<Unit, Runtime.Error()>> <- C.call(T.StreamInput<Unit, Tools.ToolDetails, Runtime.LoopConfig()>, Result<&2, &1, Runtime.Error(), T.StreamLease<Unit, Runtime.Error()>>, stream, T.StreamInput{model, context, Some{summaryConfig(config, model, summaryOptions(model, thinking, signal, requestId, maxTokens))}})
        leaseMessage(model, response)

type RetryNotifier is Data:
  RetryNotifier{shared: R.Ref<Shared>, source: RetrySource}

def notifyRetry(env: RetryNotifier, notice: Retry.RetryNotice) -> IO(Unit):
  match env notice:
    case RetryNotifier{shared, _} Retry.RetryScheduled{attempt, maxAttempts, delayMs, errorMessage}: emit(shared, SummarizationRetryScheduled{attempt, maxAttempts, delayMs, errorMessage})
    case RetryNotifier{shared, source} Retry.RetryAttemptStart{}: emit(shared, SummarizationRetryAttemptStart{source})
    case RetryNotifier{shared, _} Retry.RetryFinished{_, _, _}: emit(shared, SummarizationRetryFinished{})

def requestIdOf(generated: Result<&2, &2, String, String>) -> String:
  Result.default(&2, &2, String, String, generated, "compaction")

# upstream _runDefaultCompaction: summarize with the agent's stream function,
# the session's thinking level, the retry policy and retry notices.
def runDefaultCompaction(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +model: Ai.Model<Ai.JsonValue>, preparation: Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>, customInstructions: Maybe<&2, String>, +signal: A.AbortSignal<Unit>, reason: CompactionReason) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
    stream : Runtime.Stream() <- Agent.getStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    config : Runtime.LoopConfig() <- Agent.getConfig(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    generated : Result<&2, &2, String, String> <- Uuid.generate()
    state : Shared <- R.read(Shared, shared)
    +summarizer : Compaction.Summarizer(Unit, Tools.ToolDetails) <- C.create(~SummarizerEnv, ~Compaction.SummaryRequest<Unit, Tools.ToolDetails>, ~Ai.AssistantMessage<V.Value, Unit>, ~summarizeWith, SummarizerEnv{stream, config, model, stateThinking(current), signal, requestIdOf(generated)})
    +callbacks : Retry.RetryCallbacks() <- C.create(~RetryNotifier, ~Retry.RetryNotice, ~Unit, ~notifyRetry, RetryNotifier{shared, CompactionSource{reason}})
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Compaction.compact(~Unit, ~Tools.ToolDetails, ~V.Value, summarizer, preparation, model, customInstructions, Some{signal}, Some{policyOf(state)}, Some{callbacks})
    C.dispose(Compaction.SummaryRequest<Unit, Tools.ToolDetails>, Ai.AssistantMessage<V.Value, Unit>, summarizer)
    C.dispose(Retry.RetryNotice, Unit, callbacks)
    return result

def tokensNat(value: F64) -> Nat:
  Result.default(&2, &2, F.Error, Nat, F.convert(F.ceil(value)), 0n)

def contextMessagesOf(context: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, Message()>:
  match context:
    case Done{S.SessionContext{contextMessages, _, _}}: contextMessages
    case Fail{_}: Nil{}

def sessionMessages(session: Session()) -> List<&2, Message()>:
  contextMessagesOf(S.sessionContext(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session)))

def replaceContext(agent: Runtime.Owner(), +messages: List<&2, Message()>) -> IO(F64):
  do IO<F64>:
    Agent.replaceMessages(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, messages)
    return Compaction.estimateMessagesTokens(Unit, Tools.ToolDetails, V.Value, messages, F.fromU32(0))

# Record the compaction, rebuild the context from the session and install it
# in the agent; the result gains the estimated size afterwards.
def applyCompaction(agent: Runtime.Owner(), +shared: R.Ref<Shared>, result: Compaction.CompactionResult) -> IO(Compaction.CompactionResult):
  match result:
    case Compaction.CompactionResult{+summary, +firstKeptEntryId, +tokensBefore, _, +usage, +details}:
      do IO<Compaction.CompactionResult>:
        state : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordCompaction(sharedSession(state), summary, firstKeptEntryId, tokensNat(tokensBefore), details, usage)
        stored(shared, outcome)
        rebuilt : Shared <- R.read(Shared, shared)
        estimatedTokensAfter : F64 <- replaceContext(agent, sessionMessages(sharedSession(rebuilt)))
        return Compaction.CompactionResult{summary, firstKeptEntryId, tokensBefore, Some{estimatedTokensAfter}, usage, details}

def trailingFailed(messages: List<&2, Message()>) -> Bool:
  match messages:
    case Nil{}: False{}
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, _, _, _, _}}} <> Nil{}: True{}
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}}} <> Nil{}: True{}
    case _ <> rest: trailingFailed(rest)

def dropFailed(agent: Runtime.Owner(), +messages: List<&2, Message()>) -> IO(Unit):
  replaceIf(agent, Bool.pick(Maybe<&2, List<&2, Message()>>, trailingFailed(messages), withoutTrailingAssistant(messages), None{}))

# After overflow compaction the failed or truncated response leaves the
# context and the turn is retried; otherwise queued messages decide.
def continueAfterAuto(+agent: Runtime.Owner(), willRetry: Bool) -> IO(Bool):
  match willRetry:
    case True{}:
      do IO<Bool>:
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        dropFailed(agent, stateMessages(current))
        return True{}
    case False{}: Agent.hasQueuedMessages(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)

def autoFailure(reason: CompactionReason, message: String) -> String:
  match reason:
    case Overflow{}: "Context overflow recovery failed: " ++ message
    case _: "Auto-compaction failed: " ++ message

def finishAuto(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +reason: CompactionReason, +willRetry: Bool, aborted: Bool, result: Result<&2, &2, String, Compaction.CompactionResult>) -> IO(Bool):
  match aborted result:
    case True{} _:
      do IO<Bool>:
        emit(shared, CompactionEnd{reason, None{}, True{}, False{}, None{}})
        return False{}
    case False{} Fail{message}:
      do IO<Bool>:
        emit(shared, CompactionEnd{reason, None{}, False{}, False{}, Some{autoFailure(reason, message)}})
        return False{}
    case False{} Done{compacted}:
      do IO<Bool>:
        applied : Compaction.CompactionResult <- applyCompaction(agent, shared, compacted)
        emit(shared, CompactionEnd{reason, Some{applied}, False{}, willRetry, None{}})
        continueAfterAuto(agent, willRetry)

def autoCompactPrepared(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +model: Ai.Model<Ai.JsonValue>, +reason: CompactionReason, willRetry: Bool, preparation: Maybe<&2, Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>>) -> IO(Bool):
  match preparation:
    case None{}: IO.pure(Bool, False{})
    case Some{prepared}:
      do IO<Bool>:
        emit(shared, CompactionStart{reason})
        +controller : A.AbortController<Unit> <- A.new(Unit)
        R.modify(Shared, Unit, shared, current => (setAutoController(current, Some{controller}), Unit{}))
        result : Result<&2, &2, String, Compaction.CompactionResult> <- runDefaultCompaction(agent, shared, model, prepared, None{}, A.signal(Unit, controller), reason)
        aborted : Bool <- A.aborted(Unit, A.signal(Unit, controller))
        R.modify(Shared, Unit, shared, current => (setAutoController(current, None{}), Unit{}))
        A.dispose(Unit, controller)
        finishAuto(agent, shared, reason, willRetry, aborted, result)

# upstream _runAutoCompaction: true when the run should continue.
def runAutoCompaction(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, reason: CompactionReason, willRetry: Bool) -> IO(Bool):
  do IO<Bool>:
    entries : List<&2, Entry()> <- branchEntries(shared)
    autoCompactPrepared(agent, shared, model, reason, willRetry, Compaction.prepareCompaction(~Unit, ~Tools.ToolDetails, ~V.Value, ~detailsOf, entries, compactionSettingsFor(settings, model)))

def executePlan(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>, plan: Plan.CompactionPlan) -> IO(Bool):
  match plan:
    case Plan.NoCompaction{}: IO.pure(Bool, False{})
    case Plan.RecoveryExhausted{errorMessage}:
      do IO<Bool>:
        emit(shared, CompactionEnd{Overflow{}, None{}, False{}, False{}, Some{errorMessage}})
        return False{}
    case Plan.OverflowCompaction{False{}}: runAutoCompaction(agent, shared, settings, model, Overflow{}, False{})
    case Plan.OverflowCompaction{True{}}:
      do IO<Bool>:
        R.modify(Shared, Unit, shared, current => (markOverflow(current, True{}), Unit{}))
        withoutLastAssistant(agent)
        runAutoCompaction(agent, shared, settings, model, Overflow{}, True{})
    case Plan.ThresholdCompaction{}: runAutoCompaction(agent, shared, settings, model, Threshold{}, False{})

# upstream _checkCompaction: true when the run should continue.
def checkCompaction(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, assistant: Ai.AssistantMessage<V.Value, Unit>, skipAborted: Bool) -> IO(Bool):
  do IO<Bool>:
    +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    entries : List<&2, Entry()> <- branchEntries(shared)
    state : Shared <- R.read(Shared, shared)
    executePlan(agent, shared, settings, stateModel(current), planCompaction(compactionSettingsFor(settings, stateModel(current)), skipAborted, assistant, stateModel(current), compactionTimestamp(entries), stateMessages(current), overflowAttemptedOf(state)))

def checkLastAssistant(agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: Settings.SettingsManager, found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{assistant}:
      do IO<Unit>:
        continued : Bool <- checkCompaction(agent, shared, settings, assistant, False{})
        return Unit{}

# upstream prompt(): before a new prompt, the last assistant message (even an
# aborted one) may trigger compaction.
def compactBeforePrompt(+agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: Settings.SettingsManager) -> IO(Unit):
  do IO<Unit>:
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    checkLastAssistant(agent, shared, settings, lastAssistantIn(stateMessages(current), None{}))

# Next-turn refresh
# -----------------
# upstream _installAgentNextTurnRefresh: before each further assistant
# response the context compacts at the threshold, a hook the agent had before
# the session still runs, and the turn picks up the agent's current model,
# thinking level and tools. The system-prompt and tool-loadout refresh is not
# ported.

def Context() -> Data: T.AgentContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>

type NextTurnEnv is Data:
  NextTurnEnv{agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: Settings.SettingsManager, previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>}

def turnContext(turn: Turn()) -> Context():
  match turn:
    case T.AgentTurnContext{_, _, context, _}: context

def withTurnContext(turn: Turn(), context: Context()) -> Turn():
  match turn:
    case T.AgentTurnContext{message, toolResults, _, newMessages}: T.AgentTurnContext{message, toolResults, context, newMessages}

def withContextMessages(context: Context(), messages: List<&2, Message()>) -> Context():
  match context:
    case T.AgentContext{_, tools}: T.AgentContext{messages, tools}

def withContextTools(context: Context(), tools: List<&2, T.AgentTool<Runtime.Details(), Runtime.Error()>>) -> Context():
  match context:
    case T.AgentContext{kept, _}: T.AgentContext{kept, Some{tools}}

def stateTools(value: AgentState()) -> List<&2, T.AgentTool<Runtime.Details(), Runtime.Error()>>:
  match value:
    case T.AgentState{_, _, tools, _, _, _, _, _}: tools

def contextMessagesIn(context: Context()) -> List<&2, Message()>:
  match context:
    case T.AgentContext{kept, _}: kept

def overThreshold(settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, messages: List<&2, Message()>) -> Bool:
  +contextWindow = Ai.modelContextWindow(model)
  Bool.and(F.isGreater(F.compare(contextWindow, F.fromU32(0))), Compaction.shouldCompact(Compaction.estimateTokensOf(Compaction.estimateContextTokens(Unit, Tools.ToolDetails, V.Value, messages)), contextWindow, compactionSettingsFor(settings, model)))

def compactIfOver(over: Bool, +agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>, +context: Context()) -> IO(Context()):
  match over:
    case False{}: IO.pure(Context(), context)
    case True{}:
      do IO<Context()>:
        continued : Bool <- runAutoCompaction(agent, shared, settings, model, Threshold{}, False{})
        after : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        return withContextMessages(context, stateMessages(after))

# upstream _compactBeforeNextAssistantResponse: the context is estimated
# before the next request, not from the last response's usage.
def compactBeforeNextResponse(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +context: Context()) -> IO(Context()):
  do IO<Context()>:
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +model : Ai.Model<Ai.JsonValue> = stateModel(current)
    compactIfOver(overThreshold(settings, model, contextMessagesIn(context)), agent, shared, settings, model, context)

# A hook given to the agent before the session runs next, with precedence
# for the context-aware one as in upstream Agent.
def previousUpdate(previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>, turn: Turn(), signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(TurnResult()):
  match previous legacy:
    case Some{hook} _: C.call(T.ToolHookInput<Turn()>, TurnResult(), hook, T.ToolHookInput{turn, signal})
    case None{} Some{hook}: C.call(Maybe<&2, Agent.HooksSignal()>, TurnResult(), hook, signal)
    case None{} None{}: IO.pure(TurnResult(), Done{None{}})

# The turn continues with the agent's current model, thinking level and tools.
def refreshedUpdate(+context: Context(), +current: AgentState(), result: TurnResult()) -> TurnResult():
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{Some{T.AgentLoopTurnUpdate{Some{withContextTools(context, stateTools(current))}, None{}, Some{stateModel(current)}, Some{stateThinking(current)}}}}
    case Done{Some{T.AgentLoopTurnUpdate{replaced, added, _, _}}}: Done{Some{T.AgentLoopTurnUpdate{Some{withContextTools(Maybe.default(&2, Context(), replaced, context), stateTools(current))}, added, Some{stateModel(current)}, Some{stateThinking(current)}}}}

def refreshTurn(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>, +turn: Turn(), signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(TurnResult()):
  do IO<TurnResult()>:
    +context : Context() <- compactBeforeNextResponse(agent, shared, settings, turnContext(turn))
    result : TurnResult() <- previousUpdate(previous, legacy, withTurnContext(turn, context), signal)
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    return refreshedUpdate(context, current, result)

# Callback bodies cannot copy their environment; the copy happens inside.
def nextTurnHook(env: NextTurnEnv, input: T.ToolHookInput<Turn()>) -> IO(TurnResult()):
  match env input:
    case NextTurnEnv{agent, shared, settings, previous, legacy} T.ToolHookInput{turn, signal}: refreshTurn(agent, shared, settings, previous, legacy, turn, signal)

def create(+agent: Runtime.Owner(), session: Session(), +settings: Settings.SettingsManager, cwd: String) -> IO(AgentSession):
  do IO<AgentSession>:
    initial : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +shared : R.Ref<Shared> <- R.new(Shared, Shared{session, Nil{}, Nil{}, Nil{}, False{}, None{}, RetryState{retryPolicy(Settings.getRetrySettings(settings)), 0n, Ai.modelContextWindow(stateModel(initial)), None{}}, CompactionState{False{}, None{}, None{}}})
    +handler : Agent.Handler(SessionEvent(), Runtime.Error()) <- C.create(~R.Ref<Shared>, ~Agent.Input<SessionEvent()>, ~Loop.Emission<Runtime.Error()>, ~handleAgentEvent, shared)
    subscription : Agent.Subscription<SessionEvent(), Runtime.Error()> <- Agent.subscribe(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, handler)
    +replaced : Maybe<&2, NextTurnHook()> <- Agent.getPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    legacy : Maybe<&2, LegacyTurnHook()> <- Agent.getPrepareNextTurn(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +nextTurn : NextTurnHook() <- C.create(~NextTurnEnv, ~T.ToolHookInput<Turn()>, ~TurnResult(), ~nextTurnHook, NextTurnEnv{agent, shared, settings, replaced, legacy})
    Agent.setPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, Some{nextTurn})
    return AgentSession{agent, shared, SessionHooks{subscription, handler, nextTurn, replaced}, settings, cwd}

# A final error after retries reports the failure and resets the counter.
def failedRetry(+shared: R.Ref<Shared>, stopReason: Ai.StopReason, finalError: Maybe<&2, String>) -> IO(Unit):
  match stopReason:
    case Ai.Error{}:
      do IO<Unit>:
        previous : Nat <- R.modify(Shared, Nat, shared, current => resetAttempt(current))
        retryEnded(shared, previous, False{}, finalError)
    case _: IO.pure(Unit, Unit{})

# Without a retry, a final error is reported and compaction gets its turn.
def finishFailed(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, +assistant: Ai.AssistantMessage<V.Value, Unit>) -> IO(Bool):
  do IO<Bool>:
    failedRetry(shared, Ai.assistantStopReason(V.Value, Unit, assistant), Ai.assistantErrorMessage(V.Value, Unit, assistant))
    checkCompaction(agent, shared, settings, assistant, True{})

def retryOrFinish(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, +assistant: Ai.AssistantMessage<V.Value, Unit>) -> IO(Bool):
  do IO<Bool>:
    state : Shared <- R.read(Shared, shared)
    prepared : Bool <- prepareRetry(agent, shared, assistant, retryOf(state))
    Bool.pick(Unit -> IO(Bool), prepared, _ => IO.pure(Bool, True{}), _ => finishFailed(agent, shared, settings, assistant))(Unit{})

def afterRun(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, taken: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, contextWindow: F64) -> IO(Bool):
  match taken:
    case None{}: IO.pure(Bool, False{})
    case Some{+assistant}: Bool.pick(Unit -> IO(Bool), isRetryableError(assistant, contextWindow), _ => retryOrFinish(agent, shared, settings, assistant), _ => finishFailed(agent, shared, settings, assistant))(Unit{})

# upstream _handlePostAgentRun: retry a transient error, else check compaction.
def handlePostAgentRun(agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager) -> IO(Bool):
  do IO<Bool>:
    taken : Maybe<&2, Ai.AssistantMessage<V.Value, Unit>> <- R.modify(Shared, Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, shared, current => takeLastAssistant(current))
    state : Shared <- R.read(Shared, shared)
    afterRun(agent, shared, settings, taken, contextWindowOf(state))

def stepOf(+agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: Settings.SettingsManager, result: Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>) -> IO(Step):
  match result:
    case Fail{error}: IO.pure(Step, Step{False{}, Fail{promptError(error)}})
    case Done{Unit{}}:
      do IO<Step>:
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        drained : Result<&2, &2, String, Unit> <- drainQueued(100000n, agent)
        again : Bool <- handlePostAgentRun(agent, shared, settings)
        return Step{again, drained}

def continueRun(agent: Runtime.Owner()) -> IO(Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>):
  Agent.continueRun(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent)

# upstream _runAgentPrompt: continue the agent while post-run handling asks for it.
def runUntilSettled(fuel: Nat, +agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, step: Step) -> IO(Result<&2, &2, String, Unit>):
  match fuel step:
    case _ Step{False{}, outcome}: IO.pure(Result<&2, &2, String, Unit>, outcome)
    case 0n Step{True{}, outcome}: IO.pure(Result<&2, &2, String, Unit>, outcome)
    case 1n+rest Step{True{}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- continueRun(agent)
        next : Step <- stepOf(agent, shared, settings, result)
        runUntilSettled(rest, agent, shared, settings, next)

def runAgentPrompt(session: AgentSession, input: Agent.PromptInput<Unit, Runtime.Details(), Runtime.Custom()>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, +settings, _}:
      do IO<Result<&2, &2, String, Unit>>:
        compactBeforePrompt(agent, shared, settings)
        setRunActive(shared, True{})
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- Agent.prompt(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent, input)
        step : Step <- stepOf(agent, shared, settings, result)
        outcome : Result<&2, &2, String, Unit> <- runUntilSettled(1000n, agent, shared, settings, step)
        setRunActive(shared, False{})
        emit(shared, AgentSettled{})
        return outcome

def queued(state: Shared, behavior: StreamingBehavior, +text: String) -> Shared:
  match state behavior:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction} Steer{}: Shared{session, List.append(&2, String, steering, text <> Nil{}), followUp, listeners, runActive, lastAssistant, retry, compaction}
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction} FollowUp{}: Shared{session, steering, List.append(&2, String, followUp, text <> Nil{}), listeners, runActive, lastAssistant, retry, compaction}

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
    case AgentSession{agent, shared, _, _, _}:
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
    case AgentSession{_, shared, _, _, _}: abortSleeping(shared)

def isRetrying(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, sleepingOf(retryOf(state))))

def abortCompaction(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _}: abortCompactions(shared)

def hasController(compaction: CompactionState) -> Bool:
  match compaction:
    case CompactionState{_, manual, auto}: Bool.or(Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, manual)), Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, auto)))

def isCompacting(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return hasController(compactionOf(state))

# upstream abort: cancel retry sleeps and compactions, abort the agent and
# wait until it is idle.
def abort(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{+agent, +shared, _, _, _}:
      do IO<Unit>:
        abortSleeping(shared)
        abortCompactions(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)

def nothingToCompact(entries: List<&2, Entry()>) -> String:
  Bool.pick(String, Compaction.lastIsCompaction(Unit, Tools.ToolDetails, V.Value, entries), "Already compacted", "Nothing to compact (session too small)")

def manualPrepared(agent: Runtime.Owner(), shared: R.Ref<Shared>, model: Ai.Model<Ai.JsonValue>, customInstructions: Maybe<&2, String>, signal: A.AbortSignal<Unit>, entries: List<&2, Entry()>, preparation: Maybe<&2, Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match preparation:
    case None{}: IO.pure(Result<&2, &2, String, Compaction.CompactionResult>, Fail{nothingToCompact(entries)})
    case Some{prepared}: runDefaultCompaction(agent, shared, model, prepared, customInstructions, signal, Manual{})

def compactionOutcome(aborted: Bool, result: Result<&2, &2, String, Compaction.CompactionResult>) -> Result<&2, &2, String, Compaction.CompactionResult>:
  match aborted:
    case True{}: Fail{"Compaction cancelled"}
    case False{}: result

def manualEndEvent(+message: String) -> AgentSessionEvent:
  Bool.pick(AgentSessionEvent, String.eq(message, "Compaction cancelled"), CompactionEnd{Manual{}, None{}, True{}, False{}, None{}}, CompactionEnd{Manual{}, None{}, False{}, False{}, Some{"Compaction failed: " ++ message}})

def finishManual(agent: Runtime.Owner(), +shared: R.Ref<Shared>, result: Result<&2, &2, String, Compaction.CompactionResult>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match result:
    case Fail{+message}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        emit(shared, manualEndEvent(message))
        return Fail{message}
    case Done{compacted}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        +applied : Compaction.CompactionResult <- applyCompaction(agent, shared, compacted)
        emit(shared, CompactionEnd{Manual{}, Some{applied}, False{}, False{}, None{}})
        return Done{applied}

# upstream compact(): abort the agent, then summarize the branch; the result
# is returned, a failure or cancellation is reported in compaction_end.
def compact(session: AgentSession, customInstructions: Maybe<&2, String>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match session:
    case AgentSession{+agent, +shared, _, +settings, _}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        abortSleeping(shared)
        abortCompactions(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +controller : A.AbortController<Unit> <- A.new(Unit)
        R.modify(Shared, Unit, shared, current => (setManualController(current, Some{controller}), Unit{}))
        emit(shared, CompactionStart{Manual{}})
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +entries : List<&2, Entry()> <- branchEntries(shared)
        result : Result<&2, &2, String, Compaction.CompactionResult> <- manualPrepared(agent, shared, stateModel(current), customInstructions, A.signal(Unit, controller), entries, Compaction.prepareCompaction(~Unit, ~Tools.ToolDetails, ~V.Value, ~detailsOf, entries, compactionSettingsFor(settings, stateModel(current))))
        aborted : Bool <- A.aborted(Unit, A.signal(Unit, controller))
        R.modify(Shared, Unit, shared, current => (setManualController(current, None{}), Unit{}))
        A.dispose(Unit, controller)
        finishManual(agent, shared, compactionOutcome(aborted, result))

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
    case AgentSession{+agent, shared, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        applyThinking(agent, shared, clamped(current, level))

# upstream setModel: apply the model, keep the thinking level within its
# range, record the change (extension model_select events are not ported).
def setModel(+session: AgentSession, +model: Ai.Model<Ai.JsonValue>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.setModel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, model)
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.setThinkingLevel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, clamped(current, stateThinking(current)))
        R.modify(Shared, Unit, shared, current => (withContextWindow(current, Ai.modelContextWindow(model)), Unit{}))
        stored : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordModel(sharedSession(stored), model)
        recorded(shared, outcome)

# upstream setSessionName: record the name and notify.
def setSessionName(session: AgentSession, +name: String) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, +shared, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        stored : Shared <- R.read(Shared, shared)
        outcome : Sessions.Outcome(Appended()) <- recordName(sharedSession(stored), name)
        result : Result<&2, &2, String, Unit> <- recorded(shared, outcome)
        emit(shared, SessionInfoChanged{Some{name}})
        return result
