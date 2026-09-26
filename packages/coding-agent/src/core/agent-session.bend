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
import ./compaction/branch-summarization.bend as BranchSummary
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
import ./extensions/context.bend as Ctx
import ./extensions/runner.bend as ExtensionRunner
import ./extensions/types.bend as ExtensionTypes
import ./model-runtime.bend as Models
import ./messages.bend as Messages
import ./skills.bend as Skills
import ./prompt-templates.bend as Templates
import ../utils/frontmatter.bend as Frontmatter
import ../../../runtime/src/yaml.bend as Yaml
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/text.bend as Text
import ./session-manager.bend as S
import ./session-persistence.bend as Sessions
import ./settings-manager.bend as Settings
import ../utils/image-process.bend as Images
import ../utils/image-resize.bend as Resize
import ../utils/tool-result-images.bend as ToolResultImages
import ../../../runtime/src/base64.bend as Base64
import ./session-stats.bend as Stats
import ./cache-warmer.bend as Warmer
import ./tools/index.bend as Tools
import ./system-prompt.bend as Prompt
import ./bash-executor.bend as BashExec
import ./tools/bash.bend as Bash
import ../config.bend as Config
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../ai/src/utils/transcript.bend as Transcript

# The upstream AgentSession core: the owner of one Agent and its session
# record. It subscribes to the agent, republishes agent events to its own
# listeners with the session-level events, persists each finished message
# through session persistence, queues prompts sent while streaming, and
# records model, thinking-level and name changes as session entries,
# retries transient provider errors with the settings' backoff policy, and
# compacts the context manually or when it overflows or crosses the
# settings' threshold, expands /skill: commands and prompt templates, and runs
# user bash commands, and switches and cycles models and thinking levels
# within the available or scoped models. Extensions, reload and the cache
# warmer are not ported.

# The CLI's session codecs: no diagnostic details, tool details as their
# JSON shape (restored ones kept raw), extension payloads as JSON values.
def Session() -> Data: Sessions.Session<Unit, Tools.ToolDetails, V.Value>
def State() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Appended() -> Data: Sessions.Appended<Unit, Tools.ToolDetails, V.Value>
def Message() -> Data: T.AgentMessage<Unit, Runtime.Details(), Runtime.Custom()>
def SessionEvent() -> Data: Agent.RunEvent(Unit, Runtime.Details(), Runtime.Custom())
def AgentState() -> Data: T.AgentState<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>
def Entry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def readUnit(value: V.Value) -> Result<&2, &2, Decode.Error, Unit>: Done{Unit{}}
def readRaw(value: V.Value) -> Result<&2, &2, Decode.Error, V.Value>: Done{value}
def readDetails(value: V.Value) -> Result<&2, &2, Decode.Error, Tools.ToolDetails>: Done{Tools.RawDetails{value}}

def createSession(ids: Uuid.Generator, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.create(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, cwd, sessionDir, agentDir, options)

def openSession(ids: Uuid.Generator, path: String, sessionDir: Maybe<&2, String>, cwd: String) -> IO(Sessions.Outcome(Session())):
  Sessions.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, path, sessionDir, None{}, cwd)

def continueSession(ids: Uuid.Generator, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String) -> IO(Sessions.Outcome(Session())):
  Sessions.continueRecent(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, cwd, sessionDir, agentDir)

def memorySession(ids: Uuid.Generator, cwd: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.inMemory(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, cwd, options, None{})

def forkSession(ids: Uuid.Generator, source: String, cwd: String, sessionDir: Maybe<&2, String>, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session())):
  Sessions.forkFrom(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, source, cwd, sessionDir, agentDir, options)

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

def stateModel(value: AgentState()) -> Maybe<&2, Ai.Model<Ai.JsonValue>>:
  match value:
    case T.AgentState{model, _, _, _, _, _, _, _}: model

def modelIdentity(model: Ai.Model<Ai.JsonValue>) -> Settings.ModelIdentity:
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Settings.ModelIdentity{provider, id}

def stateThinking(value: AgentState()) -> Ai.ModelThinkingLevel:
  match value:
    case T.AgentState{_, thinking, _, _, _, _, _, _}: thinking

def keepAssistant(assistant: Ai.AssistantMessage<V.Value,Unit>,found: Maybe<&2,Ai.AssistantMessage<V.Value,Unit>>) -> Maybe<&2,Ai.AssistantMessage<V.Value,Unit>>:
  match assistant:
    case Ai.AssistantMessage{Nil{},_,_,_,_,_,_,_,_,Ai.Aborted{},_,_,_,_,_}: found
    case other: Some{other}
def lastAssistantIn(messages: List<&2, Message()>, +found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match messages:
    case Nil{}: found
    case T.LlmMessage{Ai.Assistant{assistant}} <> rest: lastAssistantIn(rest, keepAssistant(assistant,found))
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
  SessionTree{oldLeafId: Maybe<&2, String>, newLeafId: Maybe<&2, String>}
  ThinkingLevelChanged{level: Ai.ModelThinkingLevel}
  AutoRetryStart{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  AutoRetryEnd{success: Bool, attempt: Nat, finalError: Maybe<&2, String>}
  CompactionStart{reason: CompactionReason}
  CompactionEnd{reason: CompactionReason, result: Maybe<&2, Compaction.CompactionResult>, aborted: Bool, willRetry: Bool, errorMessage: Maybe<&2, String>}
  SummarizationRetryScheduled{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  SummarizationRetryAttemptStart{source: RetrySource}
  SummarizationRetryFinished{}
  EntryAppended{entry: Entry()}
  BashExecutionUpdate{id: Maybe<&2, String>, delta: String}

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
  CompactionState{overflowRecoveryAttempted: Bool, manual: Maybe<&2, A.AbortController<Unit>>, auto: Maybe<&2, A.AbortController<Unit>>, branch: Maybe<&2, A.AbortController<Unit>>}

# The last assistant message of a run with the session entries that persisted
# it and its turn's tool results; recovery omits them from the projection.
type LastTurn is Data:
  LastTurn{message: Ai.AssistantMessage<V.Value, Unit>, entryId: Maybe<&2, String>, toolResultIds: List<&2, String>}

# The mutable session state shared with the agent's event handler.
# User bash commands: the abort controllers of those running, keyed by the
# ticket each start takes, and results recorded while the agent streams,
# appended once the run settles.
type RunningBash is Data:
  RunningBash{ticket: Nat, controller: A.AbortController<Unit>}
type BashState is Data:
  BashState{running: List<&2, RunningBash>, next: Nat, pending: List<&2, Message()>}
type RunState is Data: RunState{active: Bool,abortRequested: Bool}

type Shared is Data:
  Shared{session: Session(), steering: List<&2, String>, followUp: List<&2, String>, listeners: List<&2, Listener()>, runActive: RunState, lastAssistant: Maybe<&2, LastTurn>, retry: RetryState, compaction: CompactionState, bash: BashState}

def Turn() -> Data: Agent.Turn(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())
def TurnUpdate() -> Data: Agent.Update(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())
def TurnResult() -> Data: Agent.PrepareResult(TurnUpdate(), Runtime.Error())
def NextTurnHook() -> Data: Agent.ContextHook(Turn(), TurnUpdate(), Runtime.Error())
def LegacyTurnHook() -> Data: Agent.LegacyHook(TurnUpdate(), Runtime.Error())

# Cache warming (upstream sdk's CacheWarmer and its streamFn hook): the
# warmer, the stream function that starts it for session requests (replacing
# the agent's own, restored on dispose) and the warmer's injected interfaces.
type Warming is Data:
  Warming{warmer: Warmer.CacheWarmer, stream: Runtime.Stream(), replaced: Runtime.Stream(), replay: C.Callback<Warmer.CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>>, append: C.Callback<Warmer.UsageRecord, Maybe<&2, Entry()>>, branch: C.Callback<Unit, List<&2, Entry()>>, mode: C.Callback<Unit, Settings.CacheWarmingMode>, context: C.Callback<Unit, Warmer.CacheContext>, decide: C.Callback<Warmer.CacheWarmingDecisionEvent, Warmer.CacheWarmingAction>, warmed: C.Callback<Entry(), Unit>}

# What the session binds its extension runner to (upstream
# _bindExtensionCore): the context actions, and the refresh of the current
# model after an extension changed a provider.
type ExtensionBinding is Data:
  ExtensionBinding{actions: Ctx.ExtensionContextActions, providersChanged: C.Callback<Unit, Unit>}

# The session's handles on the agent: its event subscription, the
# next-turn, request and stream hooks that replaced the agent's own
# (restored on dispose) and cache warming.
# getSessionStats is a pure function of the stored entries, the leaf, the
# session file and the model's context window. Entries are append-only, so
# the entry count, leaf and file identify the stored state; frames reading the
# footer reuse the last result until one of them changes.
type StatsKey is Data: StatsKey{count: Nat, leaf: Maybe<&2, String>, file: Maybe<&2, String>, window: F64}
type StatsMemo is Data: StatsMemo{key: StatsKey, stats: Result<&2, &2, S.Error, Stats.Stats>}

def AfterToolInput() -> Data: T.ToolHookInput<T.AfterToolCallContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>
def AfterToolResult() -> Data: Result<&2, &2, Runtime.Error(), Maybe<&2, T.AfterToolCallResult<Runtime.Details()>>>
def AfterToolHook() -> Data: C.Callback<T.ToolHookInput<T.AfterToolCallContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>, Result<&2, &2, Runtime.Error(), Maybe<&2, T.AfterToolCallResult<Runtime.Details()>>>>
type ToolResultHooks is Data: ToolResultHooks{hook: AfterToolHook(), replaced: Maybe<&2, AfterToolHook()>}

type SessionHooks is Data:
  SessionHooks{subscription: Agent.Subscription<SessionEvent(), Runtime.Error()>, handler: Agent.Handler(SessionEvent(), Runtime.Error()), nextTurn: NextTurnHook(), replaced: Maybe<&2, NextTurnHook()>, request: T.PrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()), replacedRequest: Maybe<&2, T.PrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())>, context: ExtensionBinding, warming: Warming, stats: R.Ref<Maybe<&2, StatsMemo>>, toolResults: ToolResultHooks}

type AgentSession is Data:
  AgentSession{agent: Runtime.Owner(), shared: R.Ref<Shared>, hooks: SessionHooks, settings: R.Ref<Settings.SettingsManager>, cwd: String, loadout: R.Ref<Runtime.Loadout>, models: Models.ModelRuntime, scoped: R.Ref<List<&2, Models.ScopedModel>>}

def sharedSession(state: Shared) -> Session():
  match state:
    case Shared{session, _, _, _, _, _, _, _, _}: session

def withSession(state: Shared, session: Session()) -> Shared:
  match state:
    case Shared{_, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}

def withRunActive(state: Shared, +active: Bool) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, RunState{_,requested}, lastAssistant, retry, compaction, bash}:
      Shared{session, steering, followUp, listeners, RunState{active,Bool.pick(Bool,active,False{},requested)}, lastAssistant, retry, compaction, bash}

def deliver(listeners: List<&2, Listener()>, +event: AgentSessionEvent) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit, Unit{})
    case listener <> rest:
      do IO<Unit>:
        C.call(AgentSessionEvent, Unit, listener, event)
        deliver(rest, event)

def listenersOf(state: Shared) -> List<&2, Listener()>:
  match state:
    case Shared{_, _, _, listeners, _, _, _, _, _}: listeners

def emit(shared: R.Ref<Shared>, event: AgentSessionEvent) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    deliver(listenersOf(state), event)

def queueEvent(state: Shared) -> AgentSessionEvent:
  match state:
    case Shared{_, steering, followUp, _, _, _, _, _, _}: QueueUpdate{steering, followUp}

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

def dequeuedFrom(+session: Session(), +steering: List<&2, String>, +followUp: List<&2, String>, listeners: List<&2, Listener()>, +runActive: RunState, +lastAssistant: Maybe<&2, LastTurn>, +retry: RetryState, +compaction: CompactionState, +bash: BashState, fromSteering: Maybe<&2, List<&2, String>>, fromFollowUp: Maybe<&2, List<&2, String>>) -> Shared & Bool:
  match fromSteering fromFollowUp:
    case Some{remaining} _: (Shared{session, remaining, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}, True{})
    case None{} Some{remaining}: (Shared{session, steering, remaining, listeners, runActive, lastAssistant, retry, compaction, bash}, True{})
    case None{} None{}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}, False{})

# The steering queue is searched first, then the follow-up queue, as upstream.
def dequeued(state: Shared, +text: String) -> Shared & Bool:
  match state:
    case Shared{session, +steering, +followUp, listeners, runActive, lastAssistant, retry, compaction, bash}:
      dequeuedFrom(session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash, removeFirst(steering, text), removeFirst(followUp, text))

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

def userContentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: blockText(blocks)

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

def SessionRecord() -> Type: Session() -> IO(Sessions.Outcome(Appended()))

def withOutcome(+state: Shared, outcome: Sessions.Outcome(Appended())) -> Shared & Sessions.Outcome(Appended()):
  match outcome:
    case Done{Sessions.Appended{+session, id}}: (withSession(state, session), Done{Sessions.Appended{session, id}})
    case Fail{error}: (state, Fail{error})

def appendHeld(record: SessionRecord(), +state: Shared) -> IO(Shared & Sessions.Outcome(Appended())):
  do IO<Shared & Sessions.Outcome(Appended())>:
    outcome : Sessions.Outcome(Appended()) <- record(sharedSession(state))
    return withOutcome(state, outcome)

# Appends hold the shared state across their persistence, so an append from
# another task (a cache-warm refresh during a tool run) waits instead of one
# of the two entries being lost.
def appendEntry(shared: R.Ref<Shared>, record: SessionRecord()) -> IO(Sessions.Outcome(Appended())):
  R.update(Shared, Sessions.Outcome(Appended()), shared, state => appendHeld(record, state))

def appendedId(outcome: Sessions.Outcome(Appended())) -> IO(Maybe<&2, String>):
  match outcome:
    case Done{Sessions.Appended{_, id}}: IO.pure(Maybe<&2, String>, Some{id})
    case Fail{error}:
      do IO<Maybe<&2, String>>:
        IO.print_err("Could not persist the session entry: " ++ Sessions.message(error))
        return None{}

def storedId(shared: R.Ref<Shared>, record: SessionRecord()) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    outcome : Sessions.Outcome(Appended()) <- appendEntry(shared, record)
    appendedId(outcome)

def stored(shared: R.Ref<Shared>, record: SessionRecord()) -> IO(Unit):
  do IO<Unit>:
    id : Maybe<&2, String> <- storedId(shared, record)
    return Unit{}

def withLastTurn(state: Shared, lastTurn: Maybe<&2, LastTurn>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, _, retry, compaction, bash}: Shared{session, steering, followUp, listeners, runActive, lastTurn, retry, compaction, bash}

def lastTurnOf(state: Shared) -> Maybe<&2, LastTurn>:
  match state:
    case Shared{_, _, _, _, _, lastTurn, _, _, _}: lastTurn

def withToolResult(lastTurn: Maybe<&2, LastTurn>, id: Maybe<&2, String>) -> Maybe<&2, LastTurn>:
  match lastTurn id:
    case Some{LastTurn{message, entryId, ids}} Some{value}: Some{LastTurn{message, entryId, List.append(&2, String, ids, value <> Nil{})}}
    case other _: other

def remembered(+state: Shared, message: Message(), id: Maybe<&2, String>) -> Shared:
  match message:
    case T.LlmMessage{Ai.Assistant{assistant}}: withLastTurn(state, Some{LastTurn{assistant, id, Nil{}}})
    case T.LlmMessage{Ai.ToolResult{_}}: withLastTurn(state, withToolResult(lastTurnOf(state), id))
    case _: state

# Track the last assistant message and its turn's tool results by the entries
# that persisted them.
def rememberTurn(shared: R.Ref<Shared>, message: Message(), id: Maybe<&2, String>) -> IO(Unit):
  R.modify(Shared, Unit, shared, current => (remembered(current, message, id), Unit{}))

# upstream _handleAgentEvent persistence: LLM messages and extension custom
# messages become session entries; bash executions and summaries are
# persisted where they are produced.
def persistFinished(+shared: R.Ref<Shared>, +message: Message()) -> IO(Unit):
  match message:
    case T.LlmMessage{+value}:
      do IO<Unit>:
        id : Maybe<&2, String> <- storedId(shared, target => recordMessage(target, T.LlmMessage{value}))
        rememberTurn(shared, T.LlmMessage{value}, id)
    case T.CustomMessage{Messages.Custom{Messages.CustomMessage{customType, content, display, details, _}}}:
      stored(shared, target => recordCustomMessage(target, customType, content, display, details))
    case _: IO.pure(Unit, Unit{})

def persist(shared: R.Ref<Shared>, event: SessionEvent()) -> IO(Unit):
  match event:
    case T.MessageEnd{message}: persistFinished(shared, message)
    case _: IO.pure(Unit, Unit{})

def Projection() -> Data: S.SessionProjection<Unit, Tools.ToolDetails, V.Value>

def stateOf(session: Session()) -> State(): Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, session)

# The canonical projection of the session's current branch.
def projectionFrom(result: Result<&2, &2, S.Error, Projection()>) -> Maybe<&2, Projection()>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def projectionOf(session: Session()) -> Maybe<&2, Projection()>:
  projectionFrom(S.sessionProjection(Unit, Tools.ToolDetails, V.Value, stateOf(session)))

def projectedMessages(projection: Maybe<&2, Projection()>) -> List<&2, Message()>:
  match projection:
    case Some{S.SessionProjection{_, contextMessages, _, _}}: contextMessages
    case None{}: Nil{}

def sessionMessages(session: Session()) -> List<&2, Message()>: projectedMessages(projectionOf(session))

def replaceContext(agent: Runtime.Owner(), +messages: List<&2, Message()>) -> IO(F64):
  do IO<F64>:
    Agent.replaceMessages(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, messages)
    return Compaction.estimateMessagesTokens(Unit, Tools.ToolDetails, V.Value, messages, F.fromU32(0))

# upstream _refreshFinalizedContext: the agent's transcript is the session's
# canonical projection.
def refreshContext(agent: Runtime.Owner(), shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    estimated : F64 <- replaceContext(agent, sessionMessages(sharedSession(state)))
    return Unit{}

def announceEntry(shared: R.Ref<Shared>, found: Maybe<&2, Entry()>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{entry}: emit(shared, EntryAppended{entry})

def announce(+shared: R.Ref<Shared>, appended: Maybe<&2, String>) -> IO(Unit):
  match appended:
    case None{}: IO.pure(Unit, Unit{})
    case Some{id}:
      do IO<Unit>:
        state : Shared <- R.read(Shared, shared)
        announceEntry(shared, S.getEntry(Unit, Tools.ToolDetails, V.Value, stateOf(sharedSession(state)), id))

def omitEntries(+shared: R.Ref<Shared>, ids: List<&2, String>) -> IO(Unit):
  match ids:
    case Nil{}: IO.pure(Unit, Unit{})
    case id <> rest:
      do IO<Unit>:
        appended : Maybe<&2, String> <- storedId(shared, target => Sessions.appendContextEdit(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, target, id, None{}))
        announce(shared, appended)
        omitEntries(shared, rest)

# upstream _omitRecoveryAttempt: a failed attempt stays in the session's raw
# history, but append-only edits omit it from the model context for good.
def omitRecoveryAttempt(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, ids: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    omitEntries(shared, ids)
    refreshContext(agent, shared)

def turnMessage(turn: LastTurn) -> Ai.AssistantMessage<V.Value, Unit>:
  match turn:
    case LastTurn{message, _, _}: message

def entryIdOf(turn: LastTurn) -> Maybe<&2, String>:
  match turn:
    case LastTurn{_, entryId, _}: entryId

def assistantIds(turn: LastTurn) -> List<&2, String>:
  match turn:
    case LastTurn{_, Some{id}, _}: id <> Nil{}
    case LastTurn{_, None{}, _}: Nil{}

def turnIds(turn: LastTurn) -> List<&2, String>:
  match turn:
    case LastTurn{_, Some{id}, results}: id <> results
    case LastTurn{_, None{}, results}: results

# Retry
# -----
# upstream _willRetryAfterAgentEnd, _prepareRetry and the message_end reset:
# a transient error (not a context overflow) restarts the assistant turn
# after an abortable backoff while the settings' budget allows.

def retryOf(state: Shared) -> RetryState:
  match state:
    case Shared{_, _, _, _, _, _, retry, _, _}: retry

def withAttempt(state: Shared, attempt: Nat) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, _, contextWindow, sleeping}, compaction, bash}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction, bash}

# Clears the attempt counter and returns the count it had.
def resetAttempt(state: Shared) -> Shared & Nat:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, previous, contextWindow, sleeping}, compaction, bash}:
      (Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, 0n, contextWindow, sleeping}, compaction, bash}, previous)

def withSleeping(state: Shared, sleeping: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, _}, compaction, bash}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction, bash}

def withContextWindow(state: Shared, contextWindow: F64) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, _, sleeping}, compaction, bash}:
      Shared{session, steering, followUp, listeners, runActive, lastAssistant, RetryState{policy, attempt, contextWindow, sleeping}, compaction, bash}

def retryPolicy(resolved: Settings.ResolvedRetrySettings) -> Retry.RetryPolicy:
  match resolved:
    case Settings.ResolvedRetrySettings{enabled, maxRetries, baseDelayMs, maxAgentDelayMs}: Retry.RetryPolicy{enabled, F.natural(maxRetries), F.fromU64(baseDelayMs), Some{F.fromU64(maxAgentDelayMs)}}
def withRetryPolicy(state: Shared,policy: Retry.RetryPolicy) -> Shared:
  match state:
    case Shared{session,steering,followUp,listeners,runActive,lastAssistant,RetryState{_,attempt,contextWindow,sleeping},compaction,bash}:
      Shared{session,steering,followUp,listeners,runActive,lastAssistant,RetryState{policy,attempt,contextWindow,sleeping},compaction,bash}

# Context overflow is handled by compaction, not retry.
def isRetryableError(+assistant: Ai.AssistantMessage<V.Value, Unit>, contextWindow: F64) -> Bool:
  Bool.and(Bool.not(Overflow.isContextOverflow(V.Value, Unit, assistant, contextWindow)), Retry.isRetryableAssistantError(V.Value, Unit, assistant))

def retryableLast(found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>, contextWindow: F64) -> Bool:
  match found:
    case None{}: False{}
    case Some{assistant}: isRetryableError(assistant, contextWindow)

def willRetryAfterAgentEnd(state: Shared, messages: List<&2, Message()>) -> Bool:
  match state:
    case Shared{_, _, _, _, RunState{_,True{}}, _, _, _, _}: False{}
    case Shared{_, _, _, _, _, _, RetryState{Retry.RetryPolicy{enabled, maxRetries, _, _}, attempt, contextWindow, _}, _, _}:
      Bool.and(enabled, Bool.and(Nat.is_lt(attempt, maxRetries), retryableLast(lastAssistantIn(messages, None{}), contextWindow)))

def sessionEventIn(state: Shared, event: SessionEvent()) -> AgentSessionEvent:
  match event:
    case T.AgentEnd{+messages}: AgentEnd{messages, willRetryAfterAgentEnd(state, messages)}
    case other: AgentEvent{other}

def retryEnded(shared: R.Ref<Shared>, previous: Nat, success: Bool, finalError: Maybe<&2, String>) -> IO(Unit):
  match previous:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+_: emit(shared, AutoRetryEnd{success, previous, finalError})
def finishCancelledRetry(+shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    previous : Nat <- R.modify(Shared,Nat,shared,current => resetAttempt(current))
    retryEnded(shared,previous,False{},Some{"Retry cancelled"})

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
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{_, manual, auto, branch}, bash}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto, branch}, bash}

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
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}: Shared{session, steering, followUp, List.append(&2, Listener(), listeners, listener <> Nil{}), runActive, lastAssistant, retry, compaction, bash}

def subscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: R.modify(Shared, Unit, shared, current => (addListener(current, listener), Unit{}))

def withoutListener(listeners: List<&2, Listener()>, +listener: Listener()) -> List<&2, Listener()>:
  match listeners:
    case Nil{}: Nil{}
    case +current <> +rest: Bool.pick(List<&2, Listener()>, C.same(AgentSessionEvent, Unit, current, listener), rest, current <> withoutListener(rest, listener))

def removedListener(state: Shared, listener: Listener()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}: Shared{session, steering, followUp, withoutListener(listeners, listener), runActive, lastAssistant, retry, compaction, bash}

def unsubscribe(session: AgentSession, +listener: Listener()) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: R.modify(Shared, Unit, shared, current => (removedListener(current, listener), Unit{}))

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
    case CompactionState{_, manual, auto, _}:
      do IO<Unit>:
        abortController(manual)
        abortController(auto)

# upstream abortBranchSummary: cancel an in-progress branch summarization.
def abortBranchController(compaction: CompactionState) -> IO(Unit):
  match compaction:
    case CompactionState{_, _, _, branch}: abortController(branch)

def setBranchController(state: Shared, controller: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto, _}, bash}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto, controller}, bash}

def compactionOf(state: Shared) -> CompactionState:
  match state:
    case Shared{_, _, _, _, _, _, _, compaction, _}: compaction

# upstream abortCompaction: cancel manual and automatic compaction in progress.
def abortCompactions(shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    abortBoth(compactionOf(state))

def abortBranchSummaryOf(shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    abortBranchController(compactionOf(state))

def runActiveOf(value: Shared) -> Bool:
  match value:
    case Shared{_, _, _, _, RunState{active,_}, _, _, _, _}: active
def abortRequestedOf(value: Shared) -> Bool:
  match value:
    case Shared{_, _, _, _, RunState{_,requested}, _, _, _, _}: requested
def requestRunAbort(value: Shared) -> Shared:
  match value:
    case Shared{session,steering,followUp,listeners,RunState{+active,requested},lastAssistant,retry,compaction,bash}:
      Shared{session,steering,followUp,listeners,RunState{active,active || requested},lastAssistant,retry,compaction,bash}

# User bash
# ---------

type BashOptions is Data:
  BashOptions{excludeFromContext: Maybe<&2, Bool>, id: Maybe<&2, String>, operations: Maybe<&2, Bash.BashOperations>}

def bashDefaults() -> BashOptions: BashOptions{None{}, None{}, None{}}

def bashOf(state: Shared) -> BashState:
  match state:
    case Shared{_, _, _, _, _, _, _, _, bash}: bash

def startedBash(state: Shared, controller: A.AbortController<Unit>) -> Shared & Nat:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, +next, pending}}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{RunningBash{next, controller} <> running, next + 1n, pending}}, next)

def withoutTicket(running: List<&2, RunningBash>, +ticket: Nat) -> List<&2, RunningBash>:
  match running:
    case Nil{}: Nil{}
    case RunningBash{+current, +controller} <> +rest: Bool.pick(Unit -> List<&2, RunningBash>, Nat.is_eq(current, ticket), _ => rest, _ => RunningBash{current, controller} <> withoutTicket(rest, ticket))(Unit{})

def finishedBash(state: Shared, ticket: Nat) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, next, pending}}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{withoutTicket(running, ticket), next, pending}}

def deferredBash(state: Shared, message: Message()) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, next, pending}}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, next, List.append(&2, Message(), pending, message <> Nil{})}}

def takenPending(state: Shared) -> Shared & List<&2, Message()>:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, next, pending}}: (Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, BashState{running, next, Nil{}}}, pending)

def abortRunning(running: List<&2, RunningBash>) -> IO(Unit):
  match running:
    case Nil{}: IO.pure(Unit, Unit{})
    case RunningBash{_, controller} <> rest:
      do IO<Unit>:
        won : Bool <- A.abort(Unit, controller, None{})
        abortRunning(rest)

def runningOf(bash: BashState) -> List<&2, RunningBash>:
  match bash:
    case BashState{running, _, _}: running

def pendingOf(bash: BashState) -> List<&2, Message()>:
  match bash:
    case BashState{_, _, pending}: pending

def abortBashIn(shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    state : Shared <- R.read(Shared, shared)
    abortRunning(runningOf(bashOf(state)))

# upstream abortBash: cancel every running bash command.
def abortBash(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: abortBashIn(shared)

def isBashRunning(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return Bool.not(List.is_empty(&2, RunningBash, runningOf(bashOf(state))))

def hasPendingBashMessages(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return Bool.not(List.is_empty(&2, Message(), pendingOf(bashOf(state))))

def appendAll(+shared: R.Ref<Shared>, messages: List<&2, Message()>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case message <> rest:
      do IO<Unit>:
        stored(shared, target => recordMessage(target, message))
        appendAll(shared, rest)

def appendPending(agent: Runtime.Owner(), +shared: R.Ref<Shared>, pending: List<&2, Message()>) -> IO(Unit):
  match pending:
    case Nil{}: IO.pure(Unit, Unit{})
    case message <> rest:
      do IO<Unit>:
        appendAll(shared, message <> rest)
        refreshContext(agent, shared)

# upstream _flushPendingBashMessages: bash results recorded during a run are
# appended once it settles, keeping tool calls next to their results.
def flushPendingBash(agent: Runtime.Owner(), +shared: R.Ref<Shared>) -> IO(Unit):
  do IO<Unit>:
    pending : List<&2, Message()> <- R.modify(Shared, List<&2, Message()>, shared, takenPending)
    appendPending(agent, shared, pending)

def bashMessage(command: String, result: BashExec.BashResult, excludeFromContext: Maybe<&2, Bool>, timestamp: F64) -> Message():
  match result:
    case BashExec.BashResult{output, exitCode, cancelled, truncated, fullOutputPath}: T.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command, output, exitCode, cancelled, truncated, fullOutputPath, timestamp, excludeFromContext}}}

def recordBashWhile(agent: Runtime.Owner(), +shared: R.Ref<Shared>, streaming: Bool, +message: Message()) -> IO(Unit):
  match streaming:
    case True{}: R.modify(Shared, Unit, shared, current => (deferredBash(current, message), Unit{}))
    case False{}: appendPending(agent, shared, message <> Nil{})

# upstream recordBashResult: while the agent streams the result waits for the
# run to settle.
def recordBashResult(session: AgentSession, command: String, result: BashExec.BashResult, excludeFromContext: Maybe<&2, Bool>) -> IO(Unit):
  match session:
    case AgentSession{agent, +shared, _, _, _, _, _, _}:
      do IO<Unit>:
        now : F64 <- Date.now()
        current : Shared <- R.read(Shared, shared)
        recordBashWhile(agent, shared, runActiveOf(current), bashMessage(command, result, excludeFromContext, now))

type ChunkSink is Data:
  ChunkSink{onChunk: Maybe<&2, C.Callback<String, Unit>>, shared: R.Ref<Shared>, id: Maybe<&2, String>}

def callChunk(onChunk: Maybe<&2, C.Callback<String, Unit>>, delta: String) -> IO(Unit):
  match onChunk:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(String, Unit, callback, delta)

def deliverChunk(sink: ChunkSink, +delta: String) -> IO(Unit):
  match sink:
    case ChunkSink{onChunk, shared, id}:
      do IO<Unit>:
        callChunk(onChunk, delta)
        emit(shared, BashExecutionUpdate{id, delta})

def forwardChunk(sink: ChunkSink, delta: String) -> IO(Unit): deliverChunk(sink, delta)

def prefixedCommand(prefix: Maybe<&2, String>, +command: String) -> String:
  match prefix:
    case None{}: command
    case Some{""}: command
    case Some{value}: value ++ "\n" ++ command

def shellPathResult(result: Result<&2, &2, Paths.Error, Maybe<&2, String>>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match result:
    case Fail{_}: Fail{"Invalid shellPath setting"}
    case Done{path}: Done{path}

def shellPathOf(settings: Settings.SettingsManager, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match environment:
    case Fail{error}: Fail{FS.errorMessage(error)}
    case Done{paths}: shellPathResult(Settings.getShellPath(paths, settings))

def disposeOwnedOperations(owned: Bool, operations: Bash.BashOperations) -> IO(Unit):
  match owned:
    case True{}: Bash.disposeOperations(operations)
    case False{}: IO.pure(Unit, Unit{})

def executed(result: Result<&2, &2, BashExec.Error, BashExec.BashResult>) -> Result<&2, &2, String, BashExec.BashResult>:
  match result:
    case Fail{error}: Fail{BashExec.errorMessage(error)}
    case Done{value}: Done{value}

def runBorrowed(+command: String, cwd: String, operations: Bash.BashOperations, +options: BashExec.BashExecutorOptions, pair: BashExec.ExecutorOwner & BashExec.ExecutorHandle) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  match pair:
    case Tuple{owner, handle}:
      do IO<Result<&2, &2, String, BashExec.BashResult>>:
        result : Result<&2, &2, BashExec.Error, BashExec.BashResult> <- BashExec.executeBashWithOperations(handle, command, cwd, operations, options)
        BashExec.disposeExecutor(owner)
        return executed(result)

def runBash(+command: String, cwd: String, operations: Bash.BashOperations, +options: BashExec.BashExecutorOptions) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  do IO<Result<&2, &2, String, BashExec.BashResult>>:
    owner : BashExec.ExecutorOwner <- BashExec.createExecutor()
    runBorrowed(command, cwd, operations, options, BashExec.borrowExecutor(owner))

def recordedBash(+session: AgentSession, command: String, excludeFromContext: Maybe<&2, Bool>, +result: Result<&2, &2, String, BashExec.BashResult>) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, BashExec.BashResult>, Fail{error})
    case Done{+value}:
      do IO<Result<&2, &2, String, BashExec.BashResult>>:
        recordBashResult(session, command, value, excludeFromContext)
        return Done{value}

def withOperations(+session: AgentSession, +command: String, onChunk: Maybe<&2, C.Callback<String, Unit>>, excludeFromContext: Maybe<&2, Bool>, id: Maybe<&2, String>, owned: Bool, +operations: Bash.BashOperations) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  match session:
    case AgentSession{_, +shared, _, settingsRef, cwd, _, _, _}:
      do IO<Result<&2, &2, String, BashExec.BashResult>>:
        settings : Settings.SettingsManager <- R.read(Settings.SettingsManager, settingsRef)
        +controller : A.AbortController<Unit> <- A.new(Unit)
        ticket : Nat <- R.modify(Shared, Nat, shared, current => startedBash(current, controller))
        +sink : C.Callback<String, Unit> <- C.create(~ChunkSink, ~String, ~Unit, ~forwardChunk, ChunkSink{onChunk, shared, id})
        ran : Result<&2, &2, String, BashExec.BashResult> <- runBash(prefixedCommand(Settings.getShellCommandPrefix(settings), command), cwd, operations, BashExec.BashExecutorOptions{Some{sink}, Some{A.signal(Unit, controller)}})
        result : Result<&2, &2, String, BashExec.BashResult> <- recordedBash(session, command, excludeFromContext, ran)
        R.modify(Shared, Unit, shared, current => (finishedBash(current, ticket), Unit{}))
        C.dispose(String, Unit, sink)
        A.dispose(Unit, controller)
        disposeOwnedOperations(owned, operations)
        return result

def withLocalOperations(+session: AgentSession, +command: String, onChunk: Maybe<&2, C.Callback<String, Unit>>, excludeFromContext: Maybe<&2, Bool>, id: Maybe<&2, String>, binDir: Config.Located(), shellPath: Result<&2, &2, String, Maybe<&2, String>>) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  match binDir shellPath:
    case Fail{error} _: IO.pure(Result<&2, &2, String, BashExec.BashResult>, Fail{FS.errorMessage(error)})
    case Done{_} Fail{error}: IO.pure(Result<&2, &2, String, BashExec.BashResult>, Fail{error})
    case Done{directory} Done{path}:
      do IO<Result<&2, &2, String, BashExec.BashResult>>:
        +operations : Bash.BashOperations <- Bash.createLocalBashOperations(directory, path)
        withOperations(session, command, onChunk, excludeFromContext, id, True{}, operations)

def settingsOf(session: AgentSession) -> R.Ref<Settings.SettingsManager>:
  match session:
    case AgentSession{_, _, _, settings, _, _, _, _}: settings

# upstream executeBash: run a user command with the configured prefix and
# shell, stream its output as bash_execution_update events and record the
# result; abortBash cancels it.
def executeBash(+session: AgentSession, +command: String, onChunk: Maybe<&2, C.Callback<String, Unit>>, options: BashOptions) -> IO(Result<&2, &2, String, BashExec.BashResult>):
  match options:
    case BashOptions{excludeFromContext, id, Some{operations}}: withOperations(session, command, onChunk, excludeFromContext, id, False{}, operations)
    case BashOptions{excludeFromContext, id, None{}}:
      do IO<Result<&2, &2, String, BashExec.BashResult>>:
        binDir : Config.Located() <- Config.getBinDir()
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        settings : Settings.SettingsManager <- R.read(Settings.SettingsManager, settingsOf(session))
        withLocalOperations(session, command, onChunk, excludeFromContext, id, binDir, shellPathOf(settings, environment))

# upstream _bindExtensionCore's context actions: the extension context reads
# the session's model, scope, identity and activity when it is used.
type ContextEnv is Data:
  ContextEnv{agent: Runtime.Owner(), shared: R.Ref<Shared>, scoped: R.Ref<List<&2, Models.ScopedModel>>, settings: R.Ref<Settings.SettingsManager>}

def queuedIn(state: Shared) -> Bool:
  match state:
    case Shared{_, steering, followUp, _, _, _, _, _, _}: Bool.not(List.is_empty(&2, String, steering) && List.is_empty(&2, String, followUp))

def sessionState(env: ContextEnv, unit: Unit) -> IO(Ctx.SessionState):
  match env:
    case ContextEnv{+agent, shared, scoped, settings}:
      do IO<Ctx.SessionState>:
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +stored : Shared <- R.read(Shared, shared)
        +live : Session() = sharedSession(stored)
        models : List<&2, Models.ScopedModel> <- R.read(List<&2, Models.ScopedModel>, scoped)
        manager : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        signal : Maybe<&2, A.AbortSignal<Unit>> <- Agent.signal(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        return Ctx.SessionState{stateModel(current), models, stateThinking(current), S.getSessionId(Unit, Tools.ToolDetails, V.Value, stateOf(live)), Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, live), Bool.not(runActiveOf(stored)), Settings.isProjectTrusted(manager), queuedIn(stored), signal}

# upstream ctx.abort(): the session aborts without waiting for idle, since
# extension code (a tool, say) may call it from within the run.
def contextAbort(env: ContextEnv, unit: Unit) -> IO(Unit):
  match env:
    case ContextEnv{+agent, +shared, _, _}:
      do IO<Unit>:
        R.modify(Shared,Unit,shared,current => (requestRunAbort(current),Unit{}))
        abortSleeping(shared)
        abortCompactions(shared)
        abortBranchSummaryOf(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)

# The mode binds shutdown (upstream bindExtensions); until then it does
# nothing, as upstream's default shutdownHandler.
def contextShutdown(env: ContextEnv, unit: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def createContextActions(+env: ContextEnv) -> IO(Ctx.ExtensionContextActions):
  do IO<Ctx.ExtensionContextActions>:
    reader : C.Callback<Unit, Ctx.SessionState> <- C.create(~ContextEnv, ~Unit, ~Ctx.SessionState, ~sessionState, env)
    aborter : C.Callback<Unit, Unit> <- C.create(~ContextEnv, ~Unit, ~Unit, ~contextAbort, env)
    stopper : C.Callback<Unit, Unit> <- C.create(~ContextEnv, ~Unit, ~Unit, ~contextShutdown, env)
    return Ctx.ExtensionContextActions{reader, aborter, stopper}

type ModelEnv is Data:
  ModelEnv{agent: Runtime.Owner(), models: Models.ModelRuntime}

def refreshedModel(+agent: Runtime.Owner(), found: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{model}: Agent.setModel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, model)

def currentFrom(+agent: Runtime.Owner(), +models: Models.ModelRuntime, current: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+model}:
      do IO<Unit>:
        found : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Models.getModel(models, Models.modelProvider(model), Models.modelId(model))
        refreshedModel(agent, found)

# upstream _refreshCurrentModelFromRegistry: the current model is replaced by
# the catalog's model of the same provider and id, when there is one.
def refreshCurrentModel(env: ModelEnv, unit: Unit) -> IO(Unit):
  match env:
    case ModelEnv{+agent, models}:
      do IO<Unit>:
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        currentFrom(agent, models, stateModel(current))

def createExtensionBinding(+env: ContextEnv, +models: Models.ModelRuntime) -> IO(ExtensionBinding):
  match env:
    case ContextEnv{+agent, shared, scoped, settings}:
      do IO<ExtensionBinding>:
        actions : Ctx.ExtensionContextActions <- createContextActions(ContextEnv{agent, shared, scoped, settings})
        changed : C.Callback<Unit, Unit> <- C.create(~ModelEnv, ~Unit, ~Unit, ~refreshCurrentModel, ModelEnv{agent, models})
        return ExtensionBinding{actions, changed}

def disposeExtensionBinding(binding: ExtensionBinding) -> IO(Unit):
  match binding:
    case ExtensionBinding{Ctx.ExtensionContextActions{reader, aborter, stopper}, changed}:
      do IO<Unit>:
        C.dispose(Unit, Ctx.SessionState, reader)
        C.dispose(Unit, Unit, aborter)
        C.dispose(Unit, Unit, stopper)
        C.dispose(Unit, Unit, changed)

def boundWith(runner: ExtensionRunner.ExtensionRunner, binding: Maybe<&2, ExtensionBinding>) -> IO(Unit):
  match binding:
    case None{}: ExtensionRunner.bindCore(runner, None{}, None{})
    case Some{ExtensionBinding{actions, changed}}: ExtensionRunner.bindCore(runner, Some{actions}, Some{changed})

def bindContext(loadout: Runtime.Loadout, binding: Maybe<&2, ExtensionBinding>) -> IO(Unit):
  match loadout:
    case Runtime.Loadout{_, _, _, _, None{}, _, _, _}: IO.pure(Unit, Unit{})
    case Runtime.Loadout{_, _, _, _, Some{runner}, _, _, _}: boundWith(runner, binding)

def StreamInput() -> Data: T.StreamInput<Unit, Runtime.Details(), Runtime.LoopConfig()>
def StreamOutput() -> Type: Result<&2, &1, Runtime.Error(), T.StreamLease<Unit, Runtime.Error()>>

# Restore the agent's stream function, stop warming (waiting for refreshes in
# flight) and release the warmer's interfaces.
def disposeWarming(agent: Runtime.Owner(), warming: Warming) -> IO(Unit):
  match warming:
    case Warming{warmer, stream, replaced, replay, append, branch, mode, context, decide, warmed}:
      do IO<Unit>:
        Agent.setStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, replaced)
        Warmer.dispose(warmer)
        C.dispose(StreamInput(), StreamOutput(), stream)
        C.dispose(Warmer.CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>, replay)
        C.dispose(Warmer.UsageRecord, Maybe<&2, Entry()>, append)
        C.dispose(Unit, List<&2, Entry()>, branch)
        C.dispose(Unit, Settings.CacheWarmingMode, mode)
        C.dispose(Unit, Warmer.CacheContext, context)
        C.dispose(Warmer.CacheWarmingDecisionEvent, Warmer.CacheWarmingAction, decide)
        C.dispose(Entry(), Unit, warmed)

def warmerOf(hooks: SessionHooks) -> Warmer.CacheWarmer:
  match hooks:
    case SessionHooks{_, _, _, _, _, _, _, Warming{warmer, _, _, _, _, _, _, _, _, _}, _, _}: warmer

# upstream dispose, in two steps. `shutdown` ends the session's activity: work
# is aborted, cache warming stops and listeners are unsubscribed. `retire`
# frees what readers may still hold (hooks and state); a replaced session is
# retired only after the interactive UI has moved to its successor, since
# frames read the live session concurrently. `dispose` does both.
def shutdown(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{+agent, +shared, SessionHooks{subscription, _, _, _, _, _, _, warming, _, _}, _, _, _, _, _}:
      do IO<Unit>:
        abortSleeping(shared)
        abortCompactions(shared)
        abortBranchSummaryOf(shared)
        abortBashIn(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        disposeWarming(agent, warming)
        Agent.unsubscribe(SessionEvent(), Runtime.Error(), subscription)

def retire(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{+agent, shared, SessionHooks{_, handler, nextTurn, replaced, request, replacedRequest, context, _, stats, ToolResultHooks{afterTool, replacedAfterTool}}, settings, _, loadout, _, _}:
      do IO<Unit>:
        C.dispose(Agent.Input<SessionEvent()>, Loop.Emission<Runtime.Error()>, handler)
        Agent.setPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, replaced)
        C.dispose(T.ToolHookInput<Turn()>, TurnResult(), nextTurn)
        Agent.setPrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, replacedRequest)
        Agent.setAfterToolCall(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, replacedAfterTool)
        C.dispose(AfterToolInput(), AfterToolResult(), afterTool)
        C.dispose(T.ToolHookInput<T.PrepareRequestContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>, Result<&2, &2, Runtime.Error(), Maybe<&2, T.AgentRequestUpdate<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>>, request)
        current : Runtime.Loadout <- R.dispose(Runtime.Loadout, loadout)
        bindContext(current, None{})
        disposeExtensionBinding(context)
        oldSettings : Settings.SettingsManager <- R.dispose(Settings.SettingsManager,settings)
        memo : Maybe<&2, StatsMemo> <- R.dispose(Maybe<&2, StatsMemo>, stats)
        released : Shared <- R.dispose(Shared, shared)
        return Unit{}

def dispose(+session: AgentSession) -> IO(Unit):
  do IO<Unit>:
    shutdown(session)
    retire(session)

# State
# -----

def agentOf(session: AgentSession) -> Runtime.Owner():
  match session:
    case AgentSession{agent, _, _, _, _, _, _, _}: agent

def state(session: AgentSession) -> IO(AgentState()):
  Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

def sessionOf(session: AgentSession) -> IO(Session()):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Session()>:
        current : Shared <- R.read(Shared, shared)
        return sharedSession(current)

# The process UUIDv7 generator shared by every session of this process.
def idGenerator(session: AgentSession) -> IO(Uuid.Generator):
  do IO<Uuid.Generator>:
    current : Session() <- sessionOf(session)
    return Sessions.getIdGenerator(Unit, Tools.ToolDetails, V.Value, current)

def messages(session: AgentSession) -> IO(List<&2, Message()>):
  do IO<List<&2, Message()>>:
    current : AgentState() <- state(session)
    return stateMessages(current)

def isStreaming(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
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

def usefulAssistantText(value: Maybe<&2,Ai.AssistantMessage<V.Value,Unit>>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{assistant}:
      +text = Text.trim(assistantTextOf(assistant))
      Bool.pick(Maybe<&2,String>,String.is_empty(text),None{},Some{text})

def getLastAssistantText(session: AgentSession) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    current : List<&2, Message()> <- messages(session)
    return usefulAssistantText(lastAssistantIn(current, None{}))

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

def takeLastAssistant(state: Shared) -> Shared & Maybe<&2, LastTurn>:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash}: (Shared{session, steering, followUp, listeners, runActive, None{}, retry, compaction, bash}, lastAssistant)

def contextWindowOf(state: Shared) -> F64:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{_, _, contextWindow, _}, _, _}: contextWindow

def errorText(errorMessage: Maybe<&2, String>) -> String:
  match errorMessage:
    case Some{SNil{}}: "Unknown error"
    case Some{text}: text
    case None{}: "Unknown error"

def errorMessageOf(assistant: Ai.AssistantMessage<V.Value, Unit>) -> String: errorText(Ai.assistantErrorMessage(V.Value, Unit, assistant))

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

def startRetry(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +turn: LastTurn, +attempt: Nat, maxRetries: Nat, +delay: F64) -> IO(Bool):
  do IO<Bool>:
    R.modify(Shared, Unit, shared, current => (withAttempt(current, attempt), Unit{}))
    emit(shared, AutoRetryStart{attempt, maxRetries, delay, errorMessageOf(turnMessage(turn))})
    omitRecoveryAttempt(agent, shared, assistantIds(turn))
    backoff(shared, attempt, delay)

# upstream _prepareRetry: true when the caller should continue the agent.
def prepareRetry(agent: Runtime.Owner(), +shared: R.Ref<Shared>, turn: LastTurn, retry: RetryState) -> IO(Bool):
  match retry:
    case RetryState{Retry.RetryPolicy{False{}, _, _, _}, _, _, _}: IO.pure(Bool, False{})
    case RetryState{Retry.RetryPolicy{True{}, +maxRetries, baseDelayMs, maxAgentDelayMs}, +attempt, _, _}:
      Bool.pick(Unit -> IO(Bool), Nat.is_lt(maxRetries, Nat.add(attempt, 1n)), _ => IO.pure(Bool, False{}), _ => startRetry(agent, shared, turn, Nat.add(attempt, 1n), maxRetries, Retry.retryDelayMs(baseDelayMs, maxAgentDelayMs, Nat.add(attempt, 1n))))(Unit{})

# Compaction
# ----------
# upstream _checkCompaction, _runAutoCompaction and compact(): overflow or
# threshold compaction after a run and before a prompt, manual compaction on
# request. The summarizer sends each request through the agent's stream
# function under a fresh request id, the settings' retry policy and
# per-attempt notices; extension hooks around compaction are not ported.

def setManualController(state: Shared, manual: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, _, auto, branch}, bash}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto, branch}, bash}

def setAutoController(state: Shared, auto: Maybe<&2, A.AbortController<Unit>>) -> Shared:
  match state:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, _, branch}, bash}: Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, CompactionState{attempted, manual, auto, branch}, bash}

def overflowAttemptedOf(state: Shared) -> Bool:
  match state:
    case Shared{_, _, _, _, _, _, _, CompactionState{attempted, _, _, _}, _}: attempted

def policyOf(state: Shared) -> Retry.RetryPolicy:
  match state:
    case Shared{_, _, _, _, _, _, RetryState{policy, _, _, _}, _, _}: policy

def compactionSettingsOf(resolved: Settings.ResolvedCompactionSettings) -> Compaction.CompactionSettings:
  match resolved:
    case Settings.ResolvedCompactionSettings{enabled, reserveTokens, keepRecentTokens}: Compaction.CompactionSettings{enabled, F.fromU64(reserveTokens), F.fromU64(keepRecentTokens)}

def compactionSettingsFor(settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>) -> Compaction.CompactionSettings:
  compactionSettingsOf(Settings.getCompactionSettings(settings, Some{modelIdentity(model)}))

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

# What the canonical projection says about the checked assistant message:
# whether it still contributes an assistant message, whether its usage still
# describes the projected context (no later edit), whether an explicit
# overflow may still be recovered (no later compaction and not omitted), and
# the projected estimate when the context carries edits.
type Facts is Data:
  Facts{projected: Bool, usageMatches: Bool, retained: Bool, editedTokens: Maybe<&2, F64>}

def hasAssistant(messages: List<&2, Message()>) -> Bool:
  match messages:
    case Nil{}: False{}
    case T.LlmMessage{Ai.Assistant{_}} <> _: True{}
    case _ <> rest: hasAssistant(rest)

def projectsAssistant(entries: List<&2, S.ProjectedSessionEntry<Unit, Tools.ToolDetails, V.Value>>, +id: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.ProjectedSessionEntry{source, contextMessages} <> rest: Bool.or(Bool.and(String.eq(S.entryId(Unit, Tools.ToolDetails, V.Value, source), id), hasAssistant(contextMessages)), projectsAssistant(rest, id))

def entriesAfter(entries: List<&2, Entry()>, +id: String) -> List<&2, Entry()>:
  match entries:
    case Nil{}: Nil{}
    case entry <> +rest: Bool.pick(Unit -> List<&2, Entry()>, String.eq(S.entryId(Unit, Tools.ToolDetails, V.Value, entry), id), _ => rest, _ => entriesAfter(rest, id))(Unit{})

def hasContextEdit(entries: List<&2, Entry()>) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.ContextEditEntry{_, _, _} <> _: True{}
    case _ <> rest: hasContextEdit(rest)

def hasCompaction(entries: List<&2, Entry()>) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.Compaction{_} <> _: True{}
    case _ <> rest: hasCompaction(rest)

# The latest edit of `id` omits it.
def omittedBy(entries: List<&2, Entry()>, +id: String, found: Bool) -> Bool:
  match entries:
    case Nil{}: found
    case S.ContextEditEntry{_, target, replacement} <> rest: omittedBy(rest, id, Bool.pick(Bool, String.eq(target, id), Maybe.is_none(&2, S.ContextEditableContent, replacement), found))
    case _ <> rest: omittedBy(rest, id, found)

def projectedSources(entries: List<&2, S.ProjectedSessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, Entry()>:
  match entries:
    case Nil{}: Nil{}
    case S.ProjectedSessionEntry{source, _} <> rest: source <> projectedSources(rest)

def editedTokens(+projection: Projection(), +branch: List<&2, Entry()>) -> Maybe<&2, F64>:
  match projection:
    case S.SessionProjection{entries, _, _, _}: Bool.pick(Maybe<&2, F64>, hasContextEdit(projectedSources(entries)), Some{Compaction.estimateTokensOf(Compaction.estimateProjectedContextTokens(Unit, Tools.ToolDetails, V.Value, projection, branch))}, None{})

def factsFor(+projection: Projection(), +branch: List<&2, Entry()>, entryId: Maybe<&2, String>) -> Facts:
  match projection entryId:
    case S.SessionProjection{+entries, contextMessages, level, model} None{}: Facts{True{}, True{}, True{}, editedTokens(S.SessionProjection{entries, contextMessages, level, model}, branch)}
    case S.SessionProjection{+entries, contextMessages, level, model} Some{+id}:
      +after = entriesAfter(branch, id)
      +projected = projectsAssistant(entries, id)
      Facts{projected, Bool.and(projected, Bool.not(hasContextEdit(after))), Bool.and(Bool.not(hasCompaction(after)), Bool.not(omittedBy(after, id, False{}))), editedTokens(S.SessionProjection{entries, contextMessages, level, model}, branch)}

# Without a readable projection nothing is known to have changed.
def factsOf(projection: Maybe<&2, Projection()>, +branch: List<&2, Entry()>, entryId: Maybe<&2, String>) -> Facts:
  match projection:
    case None{}: Facts{True{}, True{}, True{}, None{}}
    case Some{value}: factsFor(value, branch, entryId)

def orEdited(edited: Maybe<&2, F64>, measured: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match edited:
    case Some{tokens}: Some{tokens}
    case None{}: measured

# upstream _checkCompaction's decision (Plan.decideCompaction) from the
# assistant message, the model, the session's compaction boundary and the
# projection facts.
def planCompaction(+settings: Compaction.CompactionSettings, skipAborted: Bool, +assistant: Ai.AssistantMessage<V.Value, Unit>, +model: Ai.Model<Ai.JsonValue>, +boundary: Maybe<&2, F64>, messages: List<&2, Message()>, attempted: Bool, facts: Facts) -> Plan.CompactionPlan:
  match facts:
    case Facts{+projected, usageMatches, retained, edited}:
      +sameModel = Bool.and(String.eq(Ai.assistantProvider(V.Value, Unit, assistant), Ai.modelProvider(model)), String.eq(Ai.assistantModel(V.Value, Unit, assistant), Ai.modelId(model)))
      +explicit = Bool.and(isErrorStop(Ai.assistantStopReason(V.Value, Unit, assistant)), Overflow.isContextOverflow(V.Value, Unit, assistant, F.fromU32(0)))
      Plan.decideCompaction(skipsCheck(settings, skipAborted, assistant, boundary), Bool.and(sameModel, Bool.or(Bool.and(explicit, retained), Bool.and(usageMatches, Overflow.isContextOverflow(V.Value, Unit, assistant, Ai.modelContextWindow(model))))), Bool.and(sameModel, Bool.and(projected, Overflow.isRecoverableLength(V.Value, Unit, assistant, Ai.modelMaxTokens(model)))), isStop(Ai.assistantStopReason(V.Value, Unit, assistant)), attempted, thresholdReached(settings, Ai.modelContextWindow(model), orEdited(edited, thresholdTokens(assistant, messages, boundary))))

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

def requestIdOf(generated: Result<&2, &2, Uuid.Error, String>) -> String:
  Result.default(&2, &2, Uuid.Error, String, generated, "compaction")

# Summaries get a fresh routing id from the process generator (upstream
# completeSummarization's uuidv7()).
def sessionIds(state: Shared) -> Uuid.Generator:
  Sessions.getIdGenerator(Unit, Tools.ToolDetails, V.Value, sharedSession(state))

# upstream _runDefaultCompaction: summarize with the agent's stream function,
# the session's thinking level, the retry policy and retry notices.
def runDefaultCompaction(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +model: Ai.Model<Ai.JsonValue>, preparation: Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>, customInstructions: Maybe<&2, String>, +signal: A.AbortSignal<Unit>, reason: CompactionReason) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
    stream : Runtime.Stream() <- Agent.getStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    config : Runtime.LoopConfig() <- Agent.getConfig(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +state : Shared <- R.read(Shared, shared)
    generated : Result<&2, &2, Uuid.Error, String> <- Uuid.uuidv7(sessionIds(state), None{})
    +summarizer : Compaction.Summarizer(Unit, Tools.ToolDetails) <- C.create(~SummarizerEnv, ~Compaction.SummaryRequest<Unit, Tools.ToolDetails>, ~Ai.AssistantMessage<V.Value, Unit>, ~summarizeWith, SummarizerEnv{stream, config, model, stateThinking(current), signal, requestIdOf(generated)})
    +callbacks : Retry.RetryCallbacks() <- C.create(~RetryNotifier, ~Retry.RetryNotice, ~Unit, ~notifyRetry, RetryNotifier{shared, CompactionSource{reason}})
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Compaction.compact(~Unit, ~Tools.ToolDetails, ~V.Value, summarizer, preparation, model, customInstructions, Some{signal}, Some{policyOf(state)}, Some{callbacks})
    C.dispose(Compaction.SummaryRequest<Unit, Tools.ToolDetails>, Ai.AssistantMessage<V.Value, Unit>, summarizer)
    C.dispose(Retry.RetryNotice, Unit, callbacks)
    return result

def tokensNat(value: F64) -> Nat:
  Result.default(&2, &2, F.Error, Nat, F.convert(F.ceil(value)), 0n)

# Record the compaction, rebuild the context from the session and install it
# in the agent; the result gains the estimated size afterwards.
def applyCompaction(agent: Runtime.Owner(), +shared: R.Ref<Shared>, result: Compaction.CompactionResult) -> IO(Compaction.CompactionResult):
  match result:
    case Compaction.CompactionResult{+summary, +firstKeptEntryId, +tokensBefore, _, +usage, +details}:
      do IO<Compaction.CompactionResult>:
        stored(shared, target => recordCompaction(target, summary, firstKeptEntryId, tokensNat(tokensBefore), details, usage))
        rebuilt : Shared <- R.read(Shared, shared)
        estimatedTokensAfter : F64 <- replaceContext(agent, sessionMessages(sharedSession(rebuilt)))
        return Compaction.CompactionResult{summary, firstKeptEntryId, tokensBefore, Some{estimatedTokensAfter}, usage, details}

# After overflow compaction the omitted attempt is retried; otherwise queued
# messages decide.
def continueAfterAuto(+agent: Runtime.Owner(), willRetry: Bool) -> IO(Bool):
  match willRetry:
    case True{}: IO.pure(Bool, True{})
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
        +controller : A.AbortController<Unit> <- A.new(Unit)
        R.modify(Shared, Unit, shared, current => (setAutoController(current, Some{controller}), Unit{}))
        emit(shared, CompactionStart{reason})
        cancelledAtStart : Bool <- A.aborted(Unit, A.signal(Unit, controller))
        result : Result<&2, &2, String, Compaction.CompactionResult> <- Bool.pick(Unit -> IO(Result<&2, &2, String, Compaction.CompactionResult>), cancelledAtStart, _ => IO.pure(Result<&2, &2, String, Compaction.CompactionResult>, Fail{"Compaction cancelled"}), _ => runDefaultCompaction(agent, shared, model, prepared, None{}, A.signal(Unit, controller), reason))(Unit{})
        aborted : Bool <- A.aborted(Unit, A.signal(Unit, controller))
        R.modify(Shared, Unit, shared, current => (setAutoController(current, None{}), Unit{}))
        A.dispose(Unit, controller)
        finishAuto(agent, shared, reason, willRetry, aborted, result)

# upstream _runAutoCompaction: true when the run should continue.
def runAutoCompaction(agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, reason: CompactionReason, willRetry: Bool) -> IO(Bool):
  do IO<Bool>:
    entries : List<&2, Entry()> <- branchEntries(shared)
    autoCompactPrepared(agent, shared, model, reason, willRetry, Compaction.prepareCompaction(~Unit, ~Tools.ToolDetails, ~V.Value, ~detailsOf, entries, compactionSettingsFor(settings, model)))

def executePlan(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>, turn: LastTurn, plan: Plan.CompactionPlan) -> IO(Bool):
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
        omitRecoveryAttempt(agent, shared, turnIds(turn))
        runAutoCompaction(agent, shared, settings, model, Overflow{}, True{})
    case Plan.ThresholdCompaction{}: runAutoCompaction(agent, shared, settings, model, Threshold{}, False{})

# upstream _checkCompaction: true when the run should continue.
def checkCompactionFor(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +turn: LastTurn, skipAborted: Bool, current: AgentState(), entries: List<&2, Entry()>, state: Shared, facts: Facts, selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Bool):
  match selected:
    case None{}: IO.pure(Bool, False{})
    case Some{+model}: executePlan(agent, shared, settings, model, turn, planCompaction(compactionSettingsFor(settings, model), skipAborted, turnMessage(turn), model, compactionTimestamp(entries), stateMessages(current), overflowAttemptedOf(state), facts))
def checkCompaction(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +turn: LastTurn, skipAborted: Bool) -> IO(Bool):
  do IO<Bool>:
    +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +entries : List<&2, Entry()> <- branchEntries(shared)
    +state : Shared <- R.read(Shared, shared)
    +facts : Facts = factsOf(projectionOf(sharedSession(state)), entries, entryIdOf(turn))
    checkCompactionFor(agent, shared, settings, turn, skipAborted, current, entries, state, facts, stateModel(current))

# The entry of the last projected assistant message: the agent's transcript
# is the projection, so this is the entry of its last assistant message.
def lastAssistantEntry(entries: List<&2, S.ProjectedSessionEntry<Unit, Tools.ToolDetails, V.Value>>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match entries:
    case Nil{}: found
    case S.ProjectedSessionEntry{source, contextMessages} <> rest: lastAssistantEntry(rest, Bool.pick(Maybe<&2, String>, hasAssistant(contextMessages), Some{S.entryId(Unit, Tools.ToolDetails, V.Value, source)}, found))

def projectedAssistantEntry(projection: Maybe<&2, Projection()>) -> Maybe<&2, String>:
  match projection:
    case Some{S.SessionProjection{entries, _, _, _}}: lastAssistantEntry(entries, None{})
    case None{}: None{}

def checkLastAssistant(agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, found: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{assistant}:
      do IO<Unit>:
        state : Shared <- R.read(Shared, shared)
        continued : Bool <- checkCompaction(agent, shared, settings, LastTurn{assistant, projectedAssistantEntry(projectionOf(sharedSession(state))), Nil{}}, False{})
        return Unit{}

# upstream prompt(): before a new prompt, the last assistant message (even an
# aborted one) may trigger compaction.
def compactBeforePrompt(+agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: Settings.SettingsManager) -> IO(Unit):
  do IO<Unit>:
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    checkLastAssistant(agent, shared, settings, lastAssistantIn(stateMessages(current), None{}))

def firstMessage(messages: List<&2, Message()>, fallback: Message()) -> Message():
  match messages:
    case message <> _: message
    case Nil{}: fallback

# upstream _normalizePromptImages (f5c946480): prompt images are processed
# with the image auto-resize setting and the request model's resize profile
# (Model.inputLimits.images.resize) once the model is settled; an image that
# cannot be processed is replaced by its message, and processing hints join
# the prompt text. Base64 that does not decode is processed as no bytes
# (Node's decoder is lenient), so it is omitted with processImage's message.
type NormalizedImages is Data: NormalizedImages{images: List<&2, Ai.ImageContent>, hints: List<&2, String>}
def decodedImage(value: Result<&2, &2, Base64.Error, List<&2, U32>>) -> List<&2, U32>:
  match value:
    case Done{bytes}: bytes
    case Fail{_}: Nil{}
def normalizedImage(result: Images.ProcessImageResult, found: NormalizedImages) -> NormalizedImages:
  match result found:
    case Images.Processed{data, mime, processedHints} NormalizedImages{images, hints}: NormalizedImages{List.append(&2, Ai.ImageContent, images, Ai.ImageContent{data, mime} <> Nil{}), List.append(&2, String, hints, processedHints)}
    case Images.Unsupported{message} NormalizedImages{images, hints}: NormalizedImages{images, List.append(&2, String, hints, message <> Nil{})}
def normalizePromptImages(+options: Images.ProcessImageOptions, images: List<&2, Ai.ImageContent>, found: NormalizedImages) -> NormalizedImages:
  match images:
    case Nil{}: found
    case Ai.ImageContent{data, mime} <> rest: normalizePromptImages(options, rest, normalizedImage(Images.processImage(decodedImage(Base64.decode(data)), mime, options), found))
def promptImageOptions(settings: Settings.SettingsManager, model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Images.ProcessImageOptions:
  Images.ProcessImageOptions{Some{Settings.getImageAutoResize(settings)}, Maybe.bind(&2, Ai.Model<Ai.JsonValue>, Resize.ImageResizeOptions, model, found => Images.modelResizeOptions(found))}
def hintedText(+text: String, hints: List<&2, String>) -> String:
  match hints:
    case Nil{}: text
    case _: text ++ "\n\n" ++ String.join(hints, "\n")
def userMessageAt(+text: String, images: List<&2, Ai.ImageContent>, +now: F64) -> Message():
  firstMessage(Agent.normalizePromptInputAt(Unit, Runtime.Details(), Runtime.Custom(), Agent.Text{text, images}, now), T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, now}}})
def normalizedUserMessage(+text: String, normalized: NormalizedImages, +now: F64) -> Message():
  match normalized:
    case NormalizedImages{images, hints}: userMessageAt(hintedText(text, hints), images, now)

# Prompt and tool loadout
# -----------------------
# upstream _preparePromptAndToolLoadout: the session's tools become the
# agent's executable tools, and a system message patches the prompt sections
# the model currently has (replayed from the transcript) when they differ.
# The agent loop declares tool changes on that message before the request.

def llmOnly(messages: List<&2, Message()>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Runtime.Details()>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{value} <> rest: value <> llmOnly(rest)
    case _ <> rest: llmOnly(rest)

def sectionsOf(current: Maybe<&2, Ai.SystemMessage<V.Value>>) -> Rec.Record<Maybe<&2, String>>:
  match current:
    case Some{Ai.SystemMessage{_, Some{sections}, _, _, _}}: sections
    case _: Rec.new(Maybe<&2, String>)

def sectionPatch(patch: Maybe<&2, Rec.Record<Maybe<&2, String>>>, now: F64) -> Maybe<&2, Message()>:
  Maybe.map(&2, Rec.Record<Maybe<&2, String>>, Message(), sections => T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, Some{sections}, None{}, None{}, now}}}, patch)

def prepareLoadout(agent: Runtime.Owner(), loadout: Runtime.Loadout, messages: List<&2, Message()>, now: F64) -> IO(Maybe<&2, Message()>):
  match loadout:
    case Runtime.Loadout{sections, tools, _, _, _, _, _, _}:
      do IO<Maybe<&2, Message()>>:
        Agent.setTools(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, tools)
        return sectionPatch(Prompt.diffSystemPromptSections(sectionsOf(Transcript.getCurrentSystemMessage(V.Value, V.Value, Unit, Runtime.Details(), llmOnly(messages))), sections), now)

def withPatch(patch: Maybe<&2, Message()>, messages: List<&2, Message()>) -> List<&2, Message()>:
  match patch:
    case None{}: messages
    case Some{message}: message <> messages

# Next-turn refresh
# -----------------
# upstream _installAgentNextTurnRefresh: before each further assistant
# response the context compacts at the threshold, a hook the agent had before
# the session still runs, and the turn picks up the agent's current model,
# thinking level and tools. The system-prompt and tool-loadout refresh is not
# ported.

def Context() -> Data: T.AgentContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>

type NextTurnEnv is Data:
  NextTurnEnv{agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: R.Ref<Settings.SettingsManager>, previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>, loadout: R.Ref<Runtime.Loadout>}

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

def projectedTokens(projection: Maybe<&2, Projection()>, +branch: List<&2, Entry()>) -> F64:
  match projection:
    case Some{value}: Compaction.estimateTokensOf(Compaction.estimateProjectedContextTokens(Unit, Tools.ToolDetails, V.Value, value, branch))
    case None{}: F.fromU32(0)

def overThreshold(settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, +session: Session()) -> Bool:
  +contextWindow = Ai.modelContextWindow(model)
  Bool.and(F.isGreater(F.compare(contextWindow, F.fromU32(0))), Compaction.shouldCompact(projectedTokens(projectionOf(session), branchOf(session)), contextWindow, compactionSettingsFor(settings, model)))

def compactIfOver(over: Bool, +agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, model: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match over:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        continued : Bool <- runAutoCompaction(agent, shared, settings, model, Threshold{}, False{})
        return Unit{}

# upstream _compactBeforeNextAssistantResponse: the projected context is
# estimated before the next request, not from the last response's usage, and
# the request continues on the (possibly compacted) projection.
def compactBeforeFor(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +context: Context(), selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Context()):
  match selected:
    case None{}: IO.pure(Context(), context)
    case Some{+model}:
      do IO<Context()>:
        before : Shared <- R.read(Shared, shared)
        compactIfOver(overThreshold(settings, model, sharedSession(before)), agent, shared, settings, model)
        after : Shared <- R.read(Shared, shared)
        return withContextMessages(context, sessionMessages(sharedSession(after)))
def compactBeforeNextResponse(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +context: Context()) -> IO(Context()):
  do IO<Context()>:
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    compactBeforeFor(agent, shared, settings, context, stateModel(current))

# A hook given to the agent before the session runs next, with precedence
# for the context-aware one as in upstream Agent.
def previousUpdate(previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>, turn: Turn(), signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(TurnResult()):
  match previous legacy:
    case Some{hook} _: C.call(T.ToolHookInput<Turn()>, TurnResult(), hook, T.ToolHookInput{turn, signal})
    case None{} Some{hook}: C.call(Maybe<&2, Agent.HooksSignal()>, TurnResult(), hook, signal)
    case None{} None{}: IO.pure(TurnResult(), Done{None{}})

def withPatchAfter(added: Maybe<&2, List<&2, Message()>>, patch: Maybe<&2, Message()>) -> Maybe<&2, List<&2, Message()>>:
  match patch:
    case None{}: added
    case Some{message}: Some{List.append(&2, Message(), Maybe.default(&2, List<&2, Message()>, added, Nil{}), message <> Nil{})}

# The context the next request continues from.
def nextContext(+context: Context(), result: TurnResult()) -> Context():
  match result:
    case Done{Some{T.AgentLoopTurnUpdate{Some{replaced}, _, _, _}}}: replaced
    case _: context

# The turn continues with the agent's current model, thinking level and tools,
# and a prompt patch after any messages the earlier hook added.
def refreshedUpdate(+context: Context(), +current: AgentState(), result: TurnResult(), patch: Maybe<&2, Message()>) -> TurnResult():
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{Some{T.AgentLoopTurnUpdate{Some{withContextTools(context, stateTools(current))}, withPatchAfter(None{}, patch), stateModel(current), Some{stateThinking(current)}}}}
    case Done{Some{T.AgentLoopTurnUpdate{replaced, added, _, _}}}: Done{Some{T.AgentLoopTurnUpdate{Some{withContextTools(Maybe.default(&2, Context(), replaced, context), stateTools(current))}, withPatchAfter(added, patch), stateModel(current), Some{stateThinking(current)}}}}

def refreshTurn(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, previous: Maybe<&2, NextTurnHook()>, legacy: Maybe<&2, LegacyTurnHook()>, loadout: Runtime.Loadout, +turn: Turn(), signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(TurnResult()):
  do IO<TurnResult()>:
    +context : Context() <- compactBeforeNextResponse(agent, shared, settings, turnContext(turn))
    +result : TurnResult() <- previousUpdate(previous, legacy, withTurnContext(turn, context), signal)
    now : F64 <- Date.now()
    patch : Maybe<&2, Message()> <- prepareLoadout(agent, loadout, contextMessagesIn(nextContext(context, result)), now)
    current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    return refreshedUpdate(context, current, result, patch)

# Callback bodies cannot copy their environment; the copy happens inside.
def nextTurnHook(env: NextTurnEnv, input: T.ToolHookInput<Turn()>) -> IO(TurnResult()):
  match env input:
    case NextTurnEnv{agent, shared, settings, previous, legacy, loadout} T.ToolHookInput{turn, signal}:
      do IO<TurnResult()>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager,settings)
        +resources : Runtime.Loadout <- R.read(Runtime.Loadout, loadout)
        refreshTurn(agent, shared, current, previous, legacy, resources, turn, signal)

# Request projection
# ------------------
# upstream _installAgentRequestProjection: every provider request is built
# from the session's canonical projection, with the agent's executable tools,
# model and thinking level; a request hook the agent had before the session
# still runs on that context and may replace any part.

def RequestHook() -> Data: T.PrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error())
def RequestInput() -> Data: T.ToolHookInput<T.PrepareRequestContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>
def RequestResult() -> Data: Result<&2, &2, Runtime.Error(), Maybe<&2, T.AgentRequestUpdate<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>>>

type RequestEnv is Data:
  RequestEnv{agent: Runtime.Owner(), shared: R.Ref<Shared>, previous: Maybe<&2, RequestHook()>}

def previousRequest(previous: Maybe<&2, RequestHook()>, request: T.PrepareRequestContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>, signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(RequestResult()):
  match previous:
    case None{}: IO.pure(RequestResult(), Done{None{}})
    case Some{hook}: C.call(RequestInput(), RequestResult(), hook, T.ToolHookInput{request, signal})

def mergedRequest(+canonical: Context(), +current: AgentState(), result: RequestResult()) -> RequestResult():
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{Some{T.AgentRequestUpdate{Some{canonical}, stateModel(current), Some{stateThinking(current)}}}}
    case Done{Some{T.AgentRequestUpdate{replaced, model, thinking}}}: Done{Some{T.AgentRequestUpdate{Some{Maybe.default(&2, Context(), replaced, canonical)}, Maybe.or(&2, Ai.Model<Ai.JsonValue>, model, stateModel(current)), Some{Maybe.default(&2, Ai.ModelThinkingLevel, thinking, stateThinking(current))}}}}

def projectRequestFor(previous: Maybe<&2, RequestHook()>, +canonical: Context(), +current: AgentState(), signal: Maybe<&2, A.AbortSignal<Unit>>, selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(RequestResult()):
  match selected:
    case None{}: IO.pure(RequestResult(), Fail{Tools.Failure{"No model selected"}})
    case Some{model}:
      do IO<RequestResult()>:
        result : RequestResult() <- previousRequest(previous, T.PrepareRequestContext{canonical, model, stateThinking(current)}, signal)
        return mergedRequest(canonical, current, result)
def projectRequest(+agent: Runtime.Owner(), shared: R.Ref<Shared>, previous: Maybe<&2, RequestHook()>, context: Context(), signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(RequestResult()):
  do IO<RequestResult()>:
    state : Shared <- R.read(Shared, shared)
    +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +canonical : Context() = withContextTools(withContextMessages(context, sessionMessages(sharedSession(state))), stateTools(current))
    projectRequestFor(previous, canonical, current, signal, stateModel(current))

def requestHook(env: RequestEnv, input: RequestInput()) -> IO(RequestResult()):
  match env input:
    case RequestEnv{agent, shared, previous} T.ToolHookInput{T.PrepareRequestContext{context, _, _}, signal}: projectRequest(agent, shared, previous, context, signal)

# Tool result images
# ------------------
# upstream _installAgentToolHooks' afterToolCall: tool results enter the
# history with their images normalized (normalizeToolResultImages) under the
# image auto-resize setting and the current model's resize profile. It runs
# after a hook the agent already had (upstream: the extension tool_result
# handlers, not ported), so images such a hook injects are normalized too.

type AfterToolEnv is Data:
  AfterToolEnv{agent: Runtime.Owner(), settings: R.Ref<Settings.SettingsManager>, previous: Maybe<&2, AfterToolHook()>}

def previousAfterTool(previous: Maybe<&2, AfterToolHook()>, +input: AfterToolInput()) -> IO(AfterToolResult()):
  match previous:
    case None{}: IO.pure(AfterToolResult(), Done{None{}})
    case Some{hook}: C.call(AfterToolInput(), AfterToolResult(), hook, input)

def resultContent(result: T.AgentToolResult<Runtime.Details()>) -> List<&2, Ai.TextImageContent>:
  match result:
    case T.AgentToolResult{content, _, _, _}: content

def hookContent(hooked: Maybe<&2, T.AfterToolCallResult<Runtime.Details()>>) -> Maybe<&2, List<&2, Ai.TextImageContent>>:
  match hooked:
    case Some{T.AfterToolCallResult{content, _, _, _, _}}: content
    case None{}: None{}

def withNormalized(hooked: Maybe<&2, T.AfterToolCallResult<Runtime.Details()>>, normalized: Maybe<&2, List<&2, Ai.TextImageContent>>) -> Maybe<&2, T.AfterToolCallResult<Runtime.Details()>>:
  match hooked normalized:
    case hooked None{}: hooked
    case None{} Some{content}: Some{T.AfterToolCallResult{Some{content}, None{}, None{}, None{}, None{}}}
    case Some{T.AfterToolCallResult{_, details, isError, usage, terminate}} Some{content}: Some{T.AfterToolCallResult{Some{content}, details, isError, usage, terminate}}

def toolImageOptions(settings: Settings.SettingsManager, model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> ToolResultImages.NormalizeToolResultImagesOptions:
  ToolResultImages.NormalizeToolResultImagesOptions{Some{Settings.getImageAutoResize(settings)}, Maybe.bind(&2, Ai.Model<Ai.JsonValue>, Resize.ImageResizeOptions, model, found => Images.modelResizeOptions(found))}

def normalizedToolResult(+original: List<&2, Ai.TextImageContent>, options: ToolResultImages.NormalizeToolResultImagesOptions, hooked: AfterToolResult()) -> AfterToolResult():
  match hooked:
    case Fail{error}: Fail{error}
    case Done{+found}: Done{withNormalized(found, ToolResultImages.normalizeToolResultImages(Maybe.default(&2, List<&2, Ai.TextImageContent>, hookContent(found), original), options))}

def toolCallResult(context: T.AfterToolCallContext<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>) -> T.AgentToolResult<Runtime.Details()>:
  match context:
    case T.AfterToolCallContext{_, _, _, result, _, _}: result

def afterToolHook(env: AfterToolEnv, input: AfterToolInput()) -> IO(AfterToolResult()):
  match env input:
    case AfterToolEnv{+agent, settingsRef, previous} T.ToolHookInput{+context, signal}:
      do IO<AfterToolResult()>:
        hooked : AfterToolResult() <- previousAfterTool(previous, T.ToolHookInput{context, signal})
        +result : T.AgentToolResult<Runtime.Details()> = toolCallResult(context)
        settings : Settings.SettingsManager <- R.read(Settings.SettingsManager, settingsRef)
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        return normalizedToolResult(resultContent(result), toolImageOptions(settings, stateModel(current)), hooked)

# Cache warming
# -------------

type WarmingEnv is Data:
  WarmingEnv{agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: R.Ref<Settings.SettingsManager>, stream: Runtime.Stream()}

# The warmer replays through the agent's own stream function (upstream's
# modelRuntime.streamSimple), not the warming hook.
def replayWarm(env: WarmingEnv, request: Warmer.CacheWarmRequest) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match env request:
    case WarmingEnv{_, _, _, stream} Warmer.CacheWarmRequest{+model, context, options}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        response : StreamOutput() <- C.call(StreamInput(), StreamOutput(), stream, T.StreamInput{model, context, Some{options}})
        leaseMessage(model, response)

def appendedEntry(outcome: Sessions.Outcome(Appended())) -> IO(Maybe<&2, Entry()>):
  match outcome:
    case Done{Sessions.Appended{session, id}}: IO.pure(Maybe<&2, Entry()>, S.getEntry(Unit, Tools.ToolDetails, V.Value, stateOf(session), id))
    case Fail{error}:
      do IO<Maybe<&2, Entry()>>:
        IO.print_err("Could not persist the session entry: " ++ Sessions.message(error))
        return None{}

def appendWarmUsage(env: WarmingEnv, record: Warmer.UsageRecord) -> IO(Maybe<&2, Entry()>):
  match env record:
    case WarmingEnv{_, shared, _, _} Warmer.UsageRecord{kind, provider, model, usage, note}:
      do IO<Maybe<&2, Entry()>>:
        outcome : Sessions.Outcome(Appended()) <- appendEntry(shared, target => Sessions.appendUsage(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, target, kind, provider, model, usage, note))
        appendedEntry(outcome)

def warmBranch(env: WarmingEnv, unit: Unit) -> IO(List<&2, Entry()>):
  match env:
    case WarmingEnv{_, shared, _, _}: branchEntries(shared)

def warmingMode(env: WarmingEnv, unit: Unit) -> IO(Settings.CacheWarmingMode):
  match env:
    case WarmingEnv{_, _, settings, _}:
      do IO<Settings.CacheWarmingMode>:
        current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        return Settings.getCacheWarmingMode(current)

def modelKey(model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> String & String:
  match model:
    case Some{Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}}: (provider, id)
    case None{}: ("", "")

def cacheContextOf(key: String & String, current: AgentState()) -> Warmer.CacheContext:
  match key:
    case (provider, id): Warmer.CacheContext{provider, id, stateMessages(current)}

def warmContext(env: WarmingEnv, unit: Unit) -> IO(Warmer.CacheContext):
  match env:
    case WarmingEnv{agent, _, _, _}:
      do IO<Warmer.CacheContext>:
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        return cacheContextOf(modelKey(stateModel(current)), current)

def announceWarm(env: WarmingEnv, entry: Entry()) -> IO(Unit):
  match env:
    case WarmingEnv{_, shared, _, _}: emit(shared, EntryAppended{entry})

type StreamEnv is Data:
  StreamEnv{stream: Runtime.Stream(), warmer: Warmer.CacheWarmer, agent: Runtime.Owner(), shared: R.Ref<Shared>}

def configSessionId(config: Runtime.LoopConfig()) -> Maybe<&2, String>:
  match config:
    case T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, sessionId, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}: sessionId

def isSessionRequest(requested: Maybe<&2, String>, state: Shared) -> Bool:
  match requested:
    case Some{id}: String.eq(id, S.getSessionId(Unit, Tools.ToolDetails, V.Value, stateOf(sharedSession(state))))
    case None{}: False{}

def warmRequest(warmer: Warmer.CacheWarmer, agent: Runtime.Owner(), +model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<V.Value, V.Value, Unit, Runtime.Details()>, config: Runtime.LoopConfig()) -> IO(Unit):
  do IO<Unit>:
    +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    Warmer.start(warmer, Warmer.CacheWarmRequest{model, context, config}, cacheContextOf(modelKey(Some{model}), current))

def warmIfSession(warmer: Warmer.CacheWarmer, agent: Runtime.Owner(), shared: R.Ref<Shared>, model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<V.Value, V.Value, Unit, Runtime.Details()>, options: Maybe<&2, Runtime.LoopConfig()>) -> IO(Unit):
  match options:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+config}:
      do IO<Unit>:
        state : Shared <- R.read(Shared, shared)
        Bool.pick(Unit -> IO(Unit), isSessionRequest(configSessionId(config), state), _ => warmRequest(warmer, agent, model, context, config), _ => IO.pure(Unit, Unit{}))(Unit{})

# upstream sdk streamFn: compaction and summaries use their own request ids;
# only session requests replace the cache entry, so warming restarts from
# them and continues while the transcript still extends the request's prefix.
def warmingStream(env: StreamEnv, input: StreamInput()) -> IO(StreamOutput()):
  match env input:
    case StreamEnv{stream, warmer, agent, shared} T.StreamInput{+model, +context, +options}:
      do IO<StreamOutput()>:
        warmIfSession(warmer, agent, shared, model, context, options)
        C.call(StreamInput(), StreamOutput(), stream, T.StreamInput{model, context, options})

def createWarming(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: R.Ref<Settings.SettingsManager>, +inner: Runtime.Stream()) -> IO(Warming):
  do IO<Warming>:
    +env : WarmingEnv = WarmingEnv{agent, shared, settings, inner}
    +replay : C.Callback<Warmer.CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>> <- C.create(~WarmingEnv, ~Warmer.CacheWarmRequest, ~Ai.AssistantMessage<V.Value, Unit>, ~replayWarm, env)
    +append : C.Callback<Warmer.UsageRecord, Maybe<&2, Entry()>> <- C.create(~WarmingEnv, ~Warmer.UsageRecord, ~Maybe<&2, Entry()>, ~appendWarmUsage, env)
    +branch : C.Callback<Unit, List<&2, Entry()>> <- C.create(~WarmingEnv, ~Unit, ~List<&2, Entry()>, ~warmBranch, env)
    +mode : C.Callback<Unit, Settings.CacheWarmingMode> <- C.create(~WarmingEnv, ~Unit, ~Settings.CacheWarmingMode, ~warmingMode, env)
    +context : C.Callback<Unit, Warmer.CacheContext> <- C.create(~WarmingEnv, ~Unit, ~Warmer.CacheContext, ~warmContext, env)
    +decide : C.Callback<Warmer.CacheWarmingDecisionEvent, Warmer.CacheWarmingAction> <- C.create(~Unit, ~Warmer.CacheWarmingDecisionEvent, ~Warmer.CacheWarmingAction, ~Warmer.piDecision, Unit{})
    +warmed : C.Callback<Entry(), Unit> <- C.create(~WarmingEnv, ~Entry(), ~Unit, ~announceWarm, env)
    +warmer : Warmer.CacheWarmer <- Warmer.create(replay, Warmer.CacheWarmerSession{append, branch}, mode, context, decide, warmed)
    +stream : Runtime.Stream() <- C.create(~StreamEnv, ~StreamInput(), ~StreamOutput(), ~warmingStream, StreamEnv{inner, warmer, agent, shared})
    Agent.setStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, stream)
    return Warming{warmer, stream, inner, replay, append, branch, mode, context, decide, warmed}

def create(+agent: Runtime.Owner(), session: Session(), +settings: Settings.SettingsManager, +cwd: String, +loadout: Runtime.Loadout, +models: Models.ModelRuntime, scopedModels: List<&2, Models.ScopedModel>) -> IO(AgentSession):
  do IO<AgentSession>:
    +scoped : R.Ref<List<&2, Models.ScopedModel>> <- R.new(List<&2, Models.ScopedModel>, scopedModels)
    initial : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +window : F64 = Maybe.default(&2, F64, Maybe.map(&2, Ai.Model<Ai.JsonValue>, F64, Ai.modelContextWindow, stateModel(initial)), F.fromU32(0))
    +shared : R.Ref<Shared> <- R.new(Shared, Shared{session, Nil{}, Nil{}, Nil{}, RunState{False{},False{}}, None{}, RetryState{retryPolicy(Settings.getRetrySettings(settings)), 0n, window, None{}}, CompactionState{False{}, None{}, None{}, None{}}, BashState{Nil{}, 0n, Nil{}}})
    +settingsRef : R.Ref<Settings.SettingsManager> <- R.new(Settings.SettingsManager,settings)
    +handler : Agent.Handler(SessionEvent(), Runtime.Error()) <- C.create(~R.Ref<Shared>, ~Agent.Input<SessionEvent()>, ~Loop.Emission<Runtime.Error()>, ~handleAgentEvent, shared)
    subscription : Agent.Subscription<SessionEvent(), Runtime.Error()> <- Agent.subscribe(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, handler)
    +replaced : Maybe<&2, NextTurnHook()> <- Agent.getPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    legacy : Maybe<&2, LegacyTurnHook()> <- Agent.getPrepareNextTurn(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +loadoutRef : R.Ref<Runtime.Loadout> <- R.new(Runtime.Loadout, loadout)
    +nextTurn : NextTurnHook() <- C.create(~NextTurnEnv, ~T.ToolHookInput<Turn()>, ~TurnResult(), ~nextTurnHook, NextTurnEnv{agent, shared, settingsRef, replaced, legacy, loadoutRef})
    Agent.setPrepareNextTurnWithContext(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, Some{nextTurn})
    +replacedRequest : Maybe<&2, RequestHook()> <- Agent.getPrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +request : RequestHook() <- C.create(~RequestEnv, ~RequestInput(), ~RequestResult(), ~requestHook, RequestEnv{agent, shared, replacedRequest})
    Agent.setPrepareRequest(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, Some{request})
    +context : ExtensionBinding <- createExtensionBinding(ContextEnv{agent, shared, scoped, settingsRef}, models)
    bindContext(loadout, Some{context})
    inner : Runtime.Stream() <- Agent.getStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    warming : Warming <- createWarming(agent, shared, settingsRef, inner)
    stats : R.Ref<Maybe<&2, StatsMemo>> <- R.new(Maybe<&2, StatsMemo>, None{})
    +replacedAfterTool : Maybe<&2, AfterToolHook()> <- Agent.getAfterToolCall(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +afterTool : AfterToolHook() <- C.create(~AfterToolEnv, ~AfterToolInput(), ~AfterToolResult(), ~afterToolHook, AfterToolEnv{agent, settingsRef, replacedAfterTool})
    Agent.setAfterToolCall(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, Some{afterTool})
    return AgentSession{agent, shared, SessionHooks{subscription, handler, nextTurn, replaced, request, replacedRequest, context, warming, stats, ToolResultHooks{afterTool, replacedAfterTool}}, settingsRef, cwd, loadoutRef, models, scoped}

# A final error after retries reports the failure and resets the counter.
def failedRetry(+shared: R.Ref<Shared>, stopReason: Ai.StopReason, finalError: Maybe<&2, String>) -> IO(Unit):
  match stopReason:
    case Ai.Error{}:
      do IO<Unit>:
        previous : Nat <- R.modify(Shared, Nat, shared, current => resetAttempt(current))
        retryEnded(shared, previous, False{}, finalError)
    case _: IO.pure(Unit, Unit{})

# Without a retry, a final error is reported and compaction gets its turn.
def finishFailed(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, +turn: LastTurn) -> IO(Bool):
  do IO<Bool>:
    failedRetry(shared, Ai.assistantStopReason(V.Value, Unit, turnMessage(turn)), Ai.assistantErrorMessage(V.Value, Unit, turnMessage(turn)))
    state : Shared <- R.read(Shared,shared)
    Bool.pick(Unit -> IO(Bool),abortRequestedOf(state),_ => IO.pure(Bool,False{}),_ => checkCompaction(agent, shared, settings, turn, True{}))(Unit{})

def retryOrFinish(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager, +turn: LastTurn) -> IO(Bool):
  do IO<Bool>:
    state : Shared <- R.read(Shared, shared)
    prepared : Bool <- prepareRetry(agent, shared, turn, retryOf(state))
    latest : Shared <- R.read(Shared,shared)
    Bool.pick(Unit -> IO(Bool),abortRequestedOf(latest),_ => do IO<Bool>:
      finishCancelledRetry(shared)
      return False{},_ => Bool.pick(Unit -> IO(Bool), prepared, _ => IO.pure(Bool, True{}), _ => finishFailed(agent, shared, settings, turn))(Unit{}))(Unit{})

def afterRun(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, taken: Maybe<&2, LastTurn>, contextWindow: F64) -> IO(Bool):
  match taken:
    case None{}: IO.pure(Bool, False{})
    case Some{+turn}: Bool.pick(Unit -> IO(Bool), isRetryableError(turnMessage(turn), contextWindow), _ => retryOrFinish(agent, shared, settings, turn), _ => finishFailed(agent, shared, settings, turn))(Unit{})

# upstream _handlePostAgentRun: retry a transient error, else check compaction.
def handlePostAgentRun(agent: Runtime.Owner(), +shared: R.Ref<Shared>, settings: Settings.SettingsManager) -> IO(Bool):
  do IO<Bool>:
    taken : Maybe<&2, LastTurn> <- R.modify(Shared, Maybe<&2, LastTurn>, shared, current => takeLastAssistant(current))
    +state : Shared <- R.read(Shared, shared)
    Bool.pick(Unit -> IO(Bool),abortRequestedOf(state),_ => do IO<Bool>:
      finishCancelledRetry(shared)
      return False{},_ => afterRun(agent, shared, settings, taken, contextWindowOf(state)))(Unit{})

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
        state : Shared <- R.read(Shared,shared)
        Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),abortRequestedOf(state),_ => do IO<Result<&2,&2,String,Unit>>:
          finishCancelledRetry(shared)
          return Done{Unit{}},_ => do IO<Result<&2,&2,String,Unit>>:
          result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- continueRun(agent)
          next : Step <- stepOf(agent, shared, settings, result)
          runUntilSettled(rest, agent, shared, settings, next))(Unit{})

# upstream prompt() and _runAgentPrompt: compaction is checked before
# sending, the prompt and tool loadout are declared ahead of the user message,
# and the agent runs until post-run handling settles.
def runAgentPrompt(session: AgentSession, +text: String, images: List<&2, Ai.ImageContent>) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, hooks, settingsRef, _, loadoutRef, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        +settings : Settings.SettingsManager <- R.read(Settings.SettingsManager,settingsRef)
        loadout : Runtime.Loadout <- R.read(Runtime.Loadout, loadoutRef)
        compactBeforePrompt(agent, shared, settings)
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +now : F64 <- Date.now()
        +user : Message() = normalizedUserMessage(text, normalizePromptImages(promptImageOptions(settings, stateModel(current)), images, NormalizedImages{Nil{}, Nil{}}), now)
        patch : Maybe<&2, Message()> <- prepareLoadout(agent, loadout, stateMessages(current), now)
        setRunActive(shared, True{})
        result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- Agent.prompt(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent, Agent.Messages{withPatch(patch, user <> Nil{})})
        step : Step <- stepOf(agent, shared, settings, result)
        outcome : Result<&2, &2, String, Unit> <- runUntilSettled(1000n, agent, shared, settings, step)
        setRunActive(shared, False{})
        flushPendingBash(agent, shared)
        Warmer.onAgentSettled(warmerOf(hooks))
        emit(shared, AgentSettled{})
        return outcome

def queued(state: Shared, behavior: StreamingBehavior, +text: String) -> Shared:
  match state behavior:
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash} Steer{}: Shared{session, List.append(&2, String, steering, text <> Nil{}), followUp, listeners, runActive, lastAssistant, retry, compaction, bash}
    case Shared{session, steering, followUp, listeners, runActive, lastAssistant, retry, compaction, bash} FollowUp{}: Shared{session, steering, List.append(&2, String, followUp, text <> Nil{}), listeners, runActive, lastAssistant, retry, compaction, bash}

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

# Input expansion
# ---------------

def loadoutOf(session: AgentSession) -> IO(Runtime.Loadout):
  match session:
    case AgentSession{_, _, _, _, _, loadout, _, _}: R.read(Runtime.Loadout, loadout)

def skillNamed(skills: List<&2, Skills.Skill>, +name: String) -> Maybe<&2, Skills.Skill>:
  match skills:
    case Nil{}: None{}
    case Skills.Skill{+known, description, filePath, baseDir, source, disabled} <> rest:
      Bool.pick(Unit -> Maybe<&2, Skills.Skill>, String.eq(known, name), _ => Some{Skills.Skill{known, description, filePath, baseDir, source, disabled}}, _ => skillNamed(rest, name))(Unit{})

def skillBlock(skill: Skills.Skill, body: String, +args: String) -> String:
  match skill:
    case Skills.Skill{name, _, filePath, baseDir, _, _}:
      +block = "<skill name=\"" ++ name ++ "\" location=\"" ++ filePath ++ "\">\nReferences are relative to " ++ baseDir ++ ".\n\n" ++ body ++ "\n</skill>"
      Bool.pick(String, String.is_empty(args), block, block ++ "\n\n" ++ args)

# A skill file that cannot be read or whose frontmatter does not parse leaves
# the input unchanged (upstream reports it to extensions, not ported).
def skillRead(+text: String, skill: Skills.Skill, args: String, read: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match read:
    case Fail{_}: text
    case Done{bytes}: Result.default(&2, &2, Yaml.Error, String, Result.map(&2, &2, Yaml.Error, String, String, body => skillBlock(skill, Text.trim(body), args), Frontmatter.stripFrontmatter(Utf8.decodeBuffer(bytes))), text)

def skillFound(+text: String, args: String, found: Maybe<&2, Skills.Skill>) -> IO(String):
  match found:
    case None{}: IO.pure(String, text)
    case Some{+skill}:
      do IO<String>:
        read : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(Skills.skillPath(skill))
        return skillRead(text, skill, args, read)

# The skill name runs to the first space; the rest, trimmed, are its arguments.
def splitSkill(command: String, +name: String) -> String & String:
  match command:
    case SNil{}: (String.reverse(name), "")
    case SCon{' ', rest}: (String.reverse(name), Text.trim(rest))
    case SCon{char, rest}: splitSkill(rest, SCon{char, name})

def skillCommand(skills: List<&2, Skills.Skill>, +text: String, parts: String & String) -> IO(String):
  match parts:
    case (+name, args): skillFound(text, args, skillNamed(skills, name))

# upstream _expandSkillCommand: "/skill:name args" becomes the skill's body in
# a <skill> block followed by the arguments; unknown skills pass through.
def expandSkillCommand(skills: List<&2, Skills.Skill>, +text: String) -> IO(String):
  Bool.pick(Unit -> IO(String), String.starts_with(text, "/skill:"), _ => skillCommand(skills, text, splitSkill(String.drop(text, 7n), "")), _ => IO.pure(String, text))(Unit{})

def expandWith(loadout: Runtime.Loadout, +text: String) -> IO(String):
  match loadout:
    case Runtime.Loadout{_, _, skills, templates, _, _, _, _}:
      do IO<String>:
        expanded : String <- expandSkillCommand(skills, text)
        return Templates.expandPromptTemplate(expanded, templates)

# Skill commands, then prompt templates.
def expandInput(session: AgentSession, +text: String) -> IO(String):
  do IO<String>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    expandWith(loadout, text)

def queueExpanded(session: AgentSession, behavior: StreamingBehavior, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit):
  match session:
    case AgentSession{agent, shared, _, _, _, _, _, _}:
      do IO<Unit>:
        now : F64 <- Date.now()
        queueAt(agent, shared, behavior, text, images, now)

# upstream _queueUserInput: queued input is expanded like a prompt.
def queue(+session: AgentSession, behavior: StreamingBehavior, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit):
  do IO<Unit>:
    expanded : String <- expandInput(session, text)
    queueExpanded(session, behavior, expanded, images)

def steer(session: AgentSession, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit): queue(session, Steer{}, text, images)
def followUp(session: AgentSession, text: String, images: List<&2, Ai.ImageContent>) -> IO(Unit): queue(session, FollowUp{}, text, images)

type QueuedMessages is Data:
  QueuedMessages{steering: List<&2, String>, followUp: List<&2, String>}
def clearedQueues(state: Shared) -> Shared & QueuedMessages:
  match state:
    case Shared{session, steering, following, listeners, active, lastAssistant, retry, compaction, bash}:
      (Shared{session, Nil{}, Nil{}, listeners, active, lastAssistant, retry, compaction, bash}, QueuedMessages{steering, following})
def clearQueue(session: AgentSession) -> IO(QueuedMessages):
  match session:
    case AgentSession{+agent, +shared, _, _, _, _, _, _}:
      do IO<QueuedMessages>:
        cleared : QueuedMessages <- R.modify(Shared, QueuedMessages, shared, clearedQueues)
        Agent.clearSteeringQueue(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.clearFollowUpQueue(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        emitQueueUpdate(shared)
        return cleared

def flushPending(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{agent, shared, _, _, _, _, _, _}: flushPendingBash(agent, shared)

def promptWhile(+session: AgentSession, streaming: Bool, +text: String, +images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  match streaming behavior:
    case False{} _:
      do IO<Result<&2, &2, String, Unit>>:
        flushPending(session)
        runAgentPrompt(session, text, images)
    case True{} None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message."})
    case True{} Some{chosen}:
      do IO<Result<&2, &2, String, Unit>>:
        queueExpanded(session, chosen, text, images)
        return Done{Unit{}}

def manualIn(compaction: CompactionState) -> Bool:
  match compaction:
    case CompactionState{_, manual, _, _}: Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, manual))

def manualCompacting(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return manualIn(compactionOf(state))

def promptSelected(+session: AgentSession, text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>, selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Result<&2, &2, String, Unit>):
  match selected:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"No model selected. Use /login to add a provider, then /model to select a model."})
    case Some{_}:
      do IO<Result<&2, &2, String, Unit>>:
        expanded : String <- expandInput(session, text)
        streaming : Bool <- isStreaming(session)
        promptWhile(session, streaming, expanded, images, behavior)
def promptExpanded(+session: AgentSession, text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    current : AgentState() <- state(session)
    promptSelected(session, text, images, behavior, stateModel(current))

# Extension commands
# ------------------

def runnerOf(loadout: Runtime.Loadout) -> Maybe<&2, ExtensionRunner.ExtensionRunner>:
  match loadout:
    case Runtime.Loadout{_, _, _, _, runner, _, _, _}: runner

# The session's extension runner (upstream session.extensionRunner); None for
# sessions created without one.
def extensionRunner(session: AgentSession) -> IO(Maybe<&2, ExtensionRunner.ExtensionRunner>):
  do IO<Maybe<&2, ExtensionRunner.ExtensionRunner>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return runnerOf(loadout)

type CommandText is Data:
  CommandText{name: String, args: String}

def splitCommand(chars: List<&2, Char>, reversed: List<&2, Char>) -> CommandText:
  match chars:
    case Nil{}: CommandText{String.from_list(List.reverse(&2, Char, reversed)), ""}
    case ' ' <> rest: CommandText{String.from_list(List.reverse(&2, Char, reversed)), String.from_list(rest)}
    case char <> rest: splitCommand(rest, char <> reversed)

# `/name args`: the name up to the first space, the rest after it.
def commandText(text: String) -> CommandText:
  splitCommand(String.to_list(String.drop(text, 1n)), Nil{})

def nameOf(command: CommandText) -> String:
  match command:
    case CommandText{name, _}: name

def commandName(text: String) -> String: nameOf(commandText(text))

def commandFailed(+runner: ExtensionRunner.ExtensionRunner, name: String, result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: ExtensionRunner.emitError(runner, ExtensionTypes.ExtensionError{"command:" ++ name, "command", error, None{}})

def executeCommand(+runner: ExtensionRunner.ExtensionRunner, +name: String, args: String, found: Maybe<&2, ExtensionTypes.ResolvedCommand>) -> IO(Bool):
  match found:
    case None{}: IO.pure(Bool, False{})
    case Some{ExtensionTypes.ResolvedCommand{_, _, _, _, _, handler}}:
      do IO<Bool>:
        result : Result<&2, &2, String, Unit> <- C.call(ExtensionTypes.CommandCall, Result<&2, &2, String, Unit>, handler, ExtensionTypes.CommandCall{args, ExtensionRunner.createCommandContext(runner)})
        commandFailed(runner, name, result)
        return True{}

def executeWith(runner: Maybe<&2, ExtensionRunner.ExtensionRunner>, command: CommandText) -> IO(Bool):
  match runner command:
    case None{} _: IO.pure(Bool, False{})
    case Some{+runner} CommandText{+name, args}:
      do IO<Bool>:
        found : Maybe<&2, ExtensionTypes.ResolvedCommand> <- ExtensionRunner.getCommand(runner, name)
        executeCommand(runner, name, args, found)

def executeSlash(+session: AgentSession, +text: String, slash: Bool) -> IO(Bool):
  match slash:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        runner : Maybe<&2, ExtensionRunner.ExtensionRunner> <- extensionRunner(session)
        executeWith(runner, commandText(text))

# upstream _tryExecuteExtensionCommand: `/name args` runs the extension
# command invoked as `name` with the command context; a failing handler is
# reported as an extension error of `command:name`. True when a command ran.
def tryExecuteExtensionCommand(+session: AgentSession, +text: String) -> IO(Bool):
  executeSlash(session, text, String.starts_with(text, "/"))

def promptUnlessCompacting(+session: AgentSession, text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    compacting : Bool <- manualCompacting(session)
    Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), compacting,
      _ => IO.pure(Result<&2, &2, String, Unit>, Fail{"Cannot submit a prompt while compaction is in progress. Wait for compaction to finish and retry."}),
      _ => promptExpanded(session, text, images, behavior))(Unit{})

def promptUnlessHandled(+session: AgentSession, text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>, handled: Bool) -> IO(Result<&2, &2, String, Unit>):
  match handled:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{}: promptUnlessCompacting(session, text, images, behavior)

# upstream prompt(): an extension command runs first, even while streaming or
# compacting, and nothing is sent. Otherwise no prompt runs while a manual
# compaction does; skill commands and prompt templates are expanded, then the
# message runs or, while streaming, is queued by streamingBehavior. Input
# handlers are not ported.
def prompt(+session: AgentSession, +text: String, images: List<&2, Ai.ImageContent>, behavior: Maybe<&2, StreamingBehavior>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handled : Bool <- tryExecuteExtensionCommand(session, text)
    promptUnlessHandled(session, text, images, behavior, handled)

def abortRetry(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: abortSleeping(shared)

def isRetrying(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, sleepingOf(retryOf(state))))

def attemptOfRetry(retry: RetryState) -> Nat:
  match retry:
    case RetryState{_, attempt, _, _}: attempt

# upstream retryAttempt: the current automatic retry attempt, 0 when none.
def retryAttempt(session: AgentSession) -> IO(Nat):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Nat>:
        state : Shared <- R.read(Shared, shared)
        return attemptOfRetry(retryOf(state))

def abortCompaction(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: abortCompactions(shared)

def hasController(compaction: CompactionState) -> Bool:
  match compaction:
    case CompactionState{_, manual, auto, branch}: Bool.or(Bool.or(Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, manual)), Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, auto))), Bool.not(Maybe.is_none(&2, A.AbortController<Unit>, branch)))

def isCompacting(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}:
      do IO<Bool>:
        state : Shared <- R.read(Shared, shared)
        return hasController(compactionOf(state))

# The part of upstream abort() that runs before it first awaits (what an
# unawaited `void session.abort()` does at once): mark an active run as
# aborted, cancel retry sleeps and compactions and abort the agent.
def requestAbort(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{+agent, +shared, _, _, _, _, _, _}:
      do IO<Unit>:
        R.modify(Shared,Unit,shared,current => (requestRunAbort(current),Unit{}))
        abortSleeping(shared)
        abortCompactions(shared)
        abortBranchSummaryOf(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)

# upstream abort: requestAbort, then wait until the agent is idle.
def abort(+session: AgentSession) -> IO(Unit):
  do IO<Unit>:
    requestAbort(session)
    Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

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

# Whether compaction was cancelled comes from its abort signal, not from the
# error text (de2de549b): a failure reading "Compaction cancelled" is a failure.
def manualEndEvent(aborted: Bool, +message: String) -> AgentSessionEvent:
  Bool.pick(AgentSessionEvent, aborted, CompactionEnd{Manual{}, None{}, True{}, False{}, None{}}, CompactionEnd{Manual{}, None{}, False{}, False{}, Some{"Compaction failed: " ++ message}})

def finishManual(agent: Runtime.Owner(), +shared: R.Ref<Shared>, aborted: Bool, result: Result<&2, &2, String, Compaction.CompactionResult>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match result:
    case Fail{+message}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        emit(shared, manualEndEvent(aborted, message))
        return Fail{message}
    case Done{compacted}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        +applied : Compaction.CompactionResult <- applyCompaction(agent, shared, compacted)
        emit(shared, CompactionEnd{Manual{}, Some{applied}, False{}, False{}, None{}})
        return Done{applied}

# upstream compact(): abort the agent, then summarize the branch; the result
# is returned, a failure or cancellation is reported in compaction_end.
def manualFor(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +customInstructions: Maybe<&2, String>, signal: A.AbortSignal<Unit>, +entries: List<&2, Entry()>, selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match selected:
    case None{}: IO.pure(Result<&2, &2, String, Compaction.CompactionResult>, Fail{"No model selected"})
    case Some{+model}: manualPrepared(agent, shared, model, customInstructions, signal, entries, Compaction.prepareCompaction(~Unit, ~Tools.ToolDetails, ~V.Value, ~detailsOf, entries, compactionSettingsFor(settings, model)))
def compact(session: AgentSession, customInstructions: Maybe<&2, String>) -> IO(Result<&2, &2, String, Compaction.CompactionResult>):
  match session:
    case AgentSession{+agent, +shared, _, settingsRef, _, _, _, _}:
      do IO<Result<&2, &2, String, Compaction.CompactionResult>>:
        +settings : Settings.SettingsManager <- R.read(Settings.SettingsManager,settingsRef)
        abortSleeping(shared)
        abortCompactions(shared)
        abortBranchSummaryOf(shared)
        Agent.abort(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +controller : A.AbortController<Unit> <- A.new(Unit)
        R.modify(Shared, Unit, shared, current => (setManualController(current, Some{controller}), Unit{}))
        emit(shared, CompactionStart{Manual{}})
        +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +entries : List<&2, Entry()> <- branchEntries(shared)
        result : Result<&2, &2, String, Compaction.CompactionResult> <- manualFor(agent, shared, settings, customInstructions, A.signal(Unit, controller), entries, stateModel(current))
        +aborted : Bool <- A.aborted(Unit, A.signal(Unit, controller))
        R.modify(Shared, Unit, shared, current => (setManualController(current, None{}), Unit{}))
        A.dispose(Unit, controller)
        finishManual(agent, shared, aborted, compactionOutcome(aborted, result))

def waitForIdle(session: AgentSession) -> IO(Unit):
  Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agentOf(session))

# Tree navigation keeps the session file and its full append-only history.
# Selecting an editable user message positions the leaf at its parent and
# returns the text to put back in the editor, as upstream navigateTree does.
type Navigation is Data:
  Navigation{editorText: Maybe<&2, String>, leafId: Maybe<&2, String>}

def navigationLeaf(result: Navigation) -> Maybe<&2, String>:
  match result: case Navigation{_, leafId}: leafId

def userNavigation(text: Maybe<&2, String>, parent: Maybe<&2, String>, targetId: String) -> Navigation:
  match text:
    case Some{value}: Navigation{Some{value}, parent}
    case None{}: Navigation{None{}, Some{targetId}}

def navigationTarget(entry: Entry(), targetId: String) -> Navigation:
  match entry:
    case S.SessionMessageEntry{S.SessionEntryBase{_,parent,_}, message}:
      userNavigation(userText(message), parent, targetId)
    case S.CustomMessageEntry{S.SessionEntryBase{_,parent,_}, _, content, _, _}: Navigation{Some{userContentText(content)}, parent}
    case _: Navigation{None{}, Some{targetId}}

def branchTo(session: Session(), leafId: Maybe<&2, String>) -> Sessions.Outcome(Session()):
  match leafId:
    case None{}: Sessions.resetLeaf(Unit, Tools.ToolDetails, V.Value, session)
    case Some{id}: Sessions.branch(Unit, Tools.ToolDetails, V.Value, session, id)

# upstream navigateTree options.
type NavigateTreeOptions is Data:
  NavigateTreeOptions{summarize: Bool, customInstructions: Maybe<&2, String>, replaceInstructions: Maybe<&2, Bool>, label: Maybe<&2, String>}

def noSummary() -> NavigateTreeOptions: NavigateTreeOptions{False{}, None{}, None{}, None{}}

# upstream's navigateTree result: the editor text, the new leaf and the branch
# summary entry; an aborted summarization is upstream's
# `{cancelled: true, aborted: true}`.
type TreeNavigation is Data:
  TreeNavigated{editorText: Maybe<&2, String>, leafId: Maybe<&2, String>, summaryEntry: Maybe<&2, Entry()>}
  TreeNavigationAborted{}

def TreeResult() -> Data: Result<&2, &2, String, TreeNavigation>

def branchReserve(value: Settings.ResolvedBranchSummarySettings) -> F64:
  match value:
    case Settings.ResolvedBranchSummarySettings{reserveTokens, _}: F.fromU64(reserveTokens)

def labelOf(+options: NavigateTreeOptions) -> Maybe<&2, String>:
  match options:
    case NavigateTreeOptions{_, _, _, label}: label

def wantsSummary(+options: NavigateTreeOptions) -> Bool:
  match options:
    case NavigateTreeOptions{summarize, _, _, _}: summarize

def collectedEntries(collected: Result<&2, &2, S.Error, BranchSummary.Collected<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, Entry()>:
  match collected:
    case Done{BranchSummary.Collected{entries, _}}: entries
    case Fail{_}: Nil{}

def missingModel(+options: NavigateTreeOptions, +model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Bool:
  Bool.and(wantsSummary(options), Maybe.is_none(&2, Ai.Model<Ai.JsonValue>, model))

def leafOfSession(session: Session()) -> Maybe<&2, String>: S.getLeafId(Unit, Tools.ToolDetails, V.Value, stateOf(session))

def appendedSession(outcome: Sessions.Outcome(Appended())) -> Result<&2, &2, String, Session()>:
  match outcome:
    case Done{Sessions.Appended{session, _}}: Done{session}
    case Fail{error}: Fail{Sessions.message(error)}

# The label goes on the summary entry, or on the target without a summary.
def labelled(+session: Session(), labelTarget: String, +label: Maybe<&2, String>) -> IO(Result<&2, &2, String, Session()>):
  match label:
    case None{}: IO.pure(Result<&2, &2, String, Session()>, Done{session})
    case Some{text}:
      do IO<Result<&2, &2, String, Session()>>:
        appended : Sessions.Outcome(Appended()) <- Sessions.appendLabelChange(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, session, labelTarget, Some{text})
        return appendedSession(appended)

def branchedAndLabelled(branched: Sessions.Outcome(Session()), +targetId: String, +label: Maybe<&2, String>) -> IO(Result<&2, &2, String, Session()>):
  match branched:
    case Fail{error}: IO.pure(Result<&2, &2, String, Session()>, Fail{Sessions.message(error)})
    case Done{session}: labelled(session, targetId, label)

def settledNavigation(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +editorText: Maybe<&2, String>, summaryEntry: Maybe<&2, Entry()>, +oldLeafId: Maybe<&2, String>, outcome: Result<&2, &2, String, Session()>) -> IO(TreeResult()):
  match outcome:
    case Fail{message}: IO.pure(TreeResult(), Fail{message})
    case Done{+next}:
      +leaf = leafOfSession(next)
      do IO<TreeResult()>:
        R.modify(Shared, Unit, shared, previous => (withSession(previous, next), Unit{}))
        refreshContext(agent, shared)
        emit(shared, SessionTree{oldLeafId, leaf})
        return Done{TreeNavigated{editorText, leaf, summaryEntry}}

def summaryDetails(summary: BranchSummary.Summary) -> V.Value:
  match summary:
    case BranchSummary.Summary{_, _, details}: details

def summaryEntryOf(session: Session(), id: String) -> Maybe<&2, Entry()>:
  S.getEntry(Unit, Tools.ToolDetails, V.Value, stateOf(session), id)

def summaryLabelled(+label: Maybe<&2, String>, outcome: Sessions.Outcome(Appended())) -> IO(Result<&2, &2, String, Session()> & Maybe<&2, Entry()>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, String, Session()> & Maybe<&2, Entry()>, (Fail{Sessions.message(error)}, None{}))
    case Done{Sessions.Appended{+session, +id}}:
      +entry = summaryEntryOf(session, id)
      do IO<Result<&2, &2, String, Session()> & Maybe<&2, Entry()>>:
        result : Result<&2, &2, String, Session()> <- labelled(session, id, label)
        return (result, entry)

def settledPair(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +editorText: Maybe<&2, String>, +oldLeafId: Maybe<&2, String>, pair: Result<&2, &2, String, Session()> & Maybe<&2, Entry()>) -> IO(TreeResult()):
  match pair:
    case (outcome, entry): settledNavigation(agent, shared, editorText, entry, oldLeafId, outcome)

# upstream: the summary is attached at the navigation target position (the
# new leaf); without one the leaf moves there and the label goes on the target.
def navigateTo(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +current: Session(), +target: Navigation, +targetId: String, +oldLeafId: Maybe<&2, String>, +label: Maybe<&2, String>, summary: Maybe<&2, BranchSummary.Summary>) -> IO(TreeResult()):
  match target summary:
    case Navigation{editorText, leafId} None{}:
      do IO<TreeResult()>:
        labelledTarget : Result<&2, &2, String, Session()> <- branchedAndLabelled(branchTo(current, leafId), targetId, label)
        settledNavigation(agent, shared, editorText, None{}, oldLeafId, labelledTarget)
    case Navigation{editorText, leafId} Some{BranchSummary.Summary{text, usage, details}}:
      do IO<TreeResult()>:
        appended : Sessions.Outcome(Appended()) <- Sessions.branchWithSummary(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, current, leafId, text, Some{details}, Some{False{}}, usage)
        pair : Result<&2, &2, String, Session()> & Maybe<&2, Entry()> <- summaryLabelled(label, appended)
        settledPair(agent, shared, editorText, oldLeafId, pair)

# The branch summarizer: the agent's stream function, the session's thinking
# level, the settings' branch-summary reserve and retry policy, and retry
# notices with the branch-summary source (upstream generateBranchSummary).
def summarizeBranch(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, entries: List<&2, Entry()>, +options: NavigateTreeOptions, +signal: A.AbortSignal<Unit>) -> IO(Result<&2, &2, String, BranchSummary.Summary>):
  match options:
    case NavigateTreeOptions{_, custom, replace, _}:
      do IO<Result<&2, &2, String, BranchSummary.Summary>>:
        stream : Runtime.Stream() <- Agent.getStreamFunction(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        config : Runtime.LoopConfig() <- Agent.getConfig(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +state : Shared <- R.read(Shared, shared)
        generated : Result<&2, &2, Uuid.Error, String> <- Uuid.uuidv7(sessionIds(state), None{})
        +summarizer : Compaction.Summarizer(Unit, Tools.ToolDetails) <- C.create(~SummarizerEnv, ~Compaction.SummaryRequest<Unit, Tools.ToolDetails>, ~Ai.AssistantMessage<V.Value, Unit>, ~summarizeWith, SummarizerEnv{stream, config, model, stateThinking(current), signal, requestIdOf(generated)})
        +callbacks : Retry.RetryCallbacks() <- C.create(~RetryNotifier, ~Retry.RetryNotice, ~Unit, ~notifyRetry, RetryNotifier{shared, BranchSummarySource{}})
        result : Result<&2, &2, String, BranchSummary.Summary> <- BranchSummary.generate(~Unit, ~Tools.ToolDetails, summarizer, entries, model, branchReserve(Settings.getBranchSummarySettings(settings)), signal, custom, Maybe.default(&2, Bool, replace, False{}), Some{policyOf(state)}, Some{callbacks})
        C.dispose(Compaction.SummaryRequest<Unit, Tools.ToolDetails>, Ai.AssistantMessage<V.Value, Unit>, summarizer)
        C.dispose(Retry.RetryNotice, Unit, callbacks)
        return result

def summarized(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +current: Session(), +target: Navigation, +targetId: String, +oldLeafId: Maybe<&2, String>, +label: Maybe<&2, String>, aborted: Bool, result: Result<&2, &2, String, BranchSummary.Summary>) -> IO(TreeResult()):
  match aborted result:
    case True{} _: IO.pure(TreeResult(), Done{TreeNavigationAborted{}})
    case False{} Fail{message}: IO.pure(TreeResult(), Fail{message})
    case False{} Done{summary}: navigateTo(agent, shared, current, target, targetId, oldLeafId, label, Some{summary})

# Summarization runs under the branch-summary abort controller, which makes
# the session count as compacting (upstream _branchSummaryAbortController).
def summarizedNavigation(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, +current: Session(), +target: Navigation, +targetId: String, +oldLeafId: Maybe<&2, String>, entries: List<&2, Entry()>, +options: NavigateTreeOptions) -> IO(TreeResult()):
  do IO<TreeResult()>:
    +controller : A.AbortController<Unit> <- A.new(Unit)
    R.modify(Shared, Unit, shared, previous => (setBranchController(previous, Some{controller}), Unit{}))
    result : Result<&2, &2, String, BranchSummary.Summary> <- summarizeBranch(agent, shared, settings, model, entries, options, A.signal(Unit, controller))
    aborted : Bool <- A.aborted(Unit, A.signal(Unit, controller))
    R.modify(Shared, Unit, shared, previous => (setBranchController(previous, None{}), Unit{}))
    A.dispose(Unit, controller)
    summarized(agent, shared, current, target, targetId, oldLeafId, labelOf(options), aborted, result)

def navigateCollected(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Maybe<&2, Ai.Model<Ai.JsonValue>>, +current: Session(), +target: Navigation, +targetId: String, +oldLeafId: Maybe<&2, String>, entries: List<&2, Entry()>, +options: NavigateTreeOptions) -> IO(TreeResult()):
  match model entries:
    case Some{+chosen} +first <> rest: Bool.pick(Unit -> IO(TreeResult()), wantsSummary(options), _ => summarizedNavigation(agent, shared, settings, chosen, current, target, targetId, oldLeafId, first <> rest, options), _ => navigateTo(agent, shared, current, target, targetId, oldLeafId, labelOf(options), None{}))(Unit{})
    case _ _: navigateTo(agent, shared, current, target, targetId, oldLeafId, labelOf(options), None{})

def navigateFound(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Maybe<&2, Ai.Model<Ai.JsonValue>>, +current: Session(), +targetId: String, +tree: State(), +oldLeafId: Maybe<&2, String>, +options: NavigateTreeOptions, entry: Maybe<&2, Entry()>) -> IO(TreeResult()):
  match entry:
    case None{}: IO.pure(TreeResult(), Fail{"Entry " ++ targetId ++ " not found"})
    case Some{selected}: navigateCollected(agent, shared, settings, model, current, navigationTarget(selected, targetId), targetId, oldLeafId, collectedEntries(BranchSummary.collect(Unit, Tools.ToolDetails, V.Value, tree, oldLeafId, targetId)), options)

def sameLeaf(leafId: Maybe<&2, String>, +targetId: String) -> Bool:
  match leafId:
    case None{}: False{}
    case Some{id}: String.eq(id, targetId)

def navigateLocated(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Maybe<&2, Ai.Model<Ai.JsonValue>>, +current: Session(), +targetId: String, +tree: State(), +oldLeafId: Maybe<&2, String>, +options: NavigateTreeOptions) -> IO(TreeResult()):
  Bool.pick(Unit -> IO(TreeResult()), sameLeaf(oldLeafId, targetId),
    _ => IO.pure(TreeResult(), Done{TreeNavigated{None{}, oldLeafId, None{}}}),
    _ => Bool.pick(Unit -> IO(TreeResult()), missingModel(options, model),
      _ => IO.pure(TreeResult(), Fail{"No model available for summarization"}),
      _ => navigateFound(agent, shared, settings, model, current, targetId, tree, oldLeafId, options, S.getEntry(Unit, Tools.ToolDetails, V.Value, tree, targetId)))(Unit{}))(Unit{})

def navigateSnapshot(+agent: Runtime.Owner(), +shared: R.Ref<Shared>, +settings: Settings.SettingsManager, +model: Maybe<&2, Ai.Model<Ai.JsonValue>>, snapshot: Shared, +targetId: String, +options: NavigateTreeOptions) -> IO(TreeResult()):
  match snapshot:
    case Shared{+current, _, _, _, _, _, _, _, _}:
      +tree = stateOf(current)
      navigateLocated(agent, shared, settings, model, current, targetId, tree, S.getLeafId(Unit, Tools.ToolDetails, V.Value, tree), options)

# upstream navigateTree(targetId, options): move the leaf within the same
# session file; with `summarize`, the abandoned branch (old leaf back to the
# common ancestor) is summarized first and the summary becomes the new leaf.
def navigateTreeWith(+session: AgentSession, +targetId: String, +options: NavigateTreeOptions) -> IO(TreeResult()):
  match session:
    case AgentSession{agent, shared, _, settingsRef, _, _, _, _}:
      do IO<TreeResult()>:
        streaming : Bool <- isStreaming(session)
        compacting : Bool <- isCompacting(session)
        Bool.pick(Unit -> IO(TreeResult()), streaming,
          _ => IO.pure(TreeResult(), Fail{"Wait for the current response to finish before navigating the session tree."}),
          _ => Bool.pick(Unit -> IO(TreeResult()), compacting,
            _ => IO.pure(TreeResult(), Fail{"Wait for the current compaction or tree navigation to finish before navigating the session tree."}),
            _ => do IO<TreeResult()>:
              snapshot : Shared <- R.read(Shared, shared)
              settings : Settings.SettingsManager <- R.read(Settings.SettingsManager, settingsRef)
              current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
              navigateSnapshot(agent, shared, settings, stateModel(current), snapshot, targetId, options))(Unit{}))(Unit{})

# upstream abortBranchSummary: cancel an in-progress branch summarization;
# the navigation then reports it as aborted and leaves the session unchanged.
def abortBranchSummary(session: AgentSession) -> IO(Unit):
  match session:
    case AgentSession{_, shared, _, _, _, _, _, _}: abortBranchSummaryOf(shared)

def plainNavigation(result: TreeResult()) -> Result<&2, &2, String, Navigation>:
  match result:
    case Done{TreeNavigated{editorText, leafId, _}}: Done{Navigation{editorText, leafId}}
    case Done{TreeNavigationAborted{}}: Fail{"Branch summarization aborted"}
    case Fail{message}: Fail{message}

# Navigation without a summary.
def navigateTree(+session: AgentSession, +targetId: String) -> IO(Result<&2, &2, String, Navigation>):
  do IO<Result<&2, &2, String, Navigation>>:
    result : TreeResult() <- navigateTreeWith(session, targetId, noSummary())
    return plainNavigation(result)

def forkText(text: Maybe<&2, String>, parent: Maybe<&2, String>) -> Maybe<&2, Navigation>:
  match text:
    case Some{value}: Some{Navigation{Some{value}, parent}}
    case None{}: None{}

def forkTarget(entry: Entry()) -> Maybe<&2, Navigation>:
  match entry:
    case S.SessionMessageEntry{S.SessionEntryBase{_,parent,_}, message}: forkText(userText(message), parent)
    case _: None{}

# Mutations
# ---------

def outcomeResult(outcome: Sessions.Outcome(Appended())) -> Result<&2, &2, String, Unit>:
  match outcome:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{Sessions.message(error)}

def recorded(shared: R.Ref<Shared>, record: SessionRecord()) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    outcome : Sessions.Outcome(Appended()) <- appendEntry(shared, record)
    return outcomeResult(outcome)

def checkedSetting(value: Settings.SettingsManager & List<&2,Settings.SettingsError>) -> Result<&2,&2,String,Settings.SettingsManager>:
  match value:
    case (manager,Nil{}): Done{manager}
    case (_, _): Fail{"Could not persist settings"}
def persistedSetting(result: Settings.Outcome(Settings.SettingsManager)) -> IO(Result<&2,&2,String,Settings.SettingsManager>):
  match result:
    case Fail{_}: IO.pure(Result<&2,&2,String,Settings.SettingsManager>,Fail{"Could not update settings"})
    case Done{manager}:
      do IO<Result<&2,&2,String,Settings.SettingsManager>>:
        saved : Settings.SettingsManager <- Settings.flushFiles(manager)
        return checkedSetting(Settings.drainErrors(saved))
def settingApplied(settings: R.Ref<Settings.SettingsManager>,result: Result<&2,&2,String,Settings.SettingsManager>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Unit>,Fail{message})
    case Done{manager}:
      do IO<Result<&2,&2,String,Unit>>:
        R.write(Settings.SettingsManager,settings,manager)
        return Done{Unit{}}
def setAutoCompactionEnabled(session: AgentSession,enabled: Bool) -> IO(Result<&2,&2,String,Unit>):
  match session:
    case AgentSession{_,_,_,+settings,_,_,_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager,settings)
        updated : Result<&2,&2,String,Settings.SettingsManager> <- persistedSetting(Settings.setCompactionEnabled(enabled,current))
        settingApplied(settings,updated)
def getAutoCompactionEnabled(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_,_,_,settings,_,_,_,_}:
      do IO<Bool>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager,settings)
        return Settings.getCompactionEnabled(current)
def retryApplied(settings: R.Ref<Settings.SettingsManager>,shared: R.Ref<Shared>,result: Result<&2,&2,String,Settings.SettingsManager>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Unit>,Fail{message})
    case Done{+manager}:
      do IO<Result<&2,&2,String,Unit>>:
        R.modify(Shared,Unit,shared,current => (withRetryPolicy(current,retryPolicy(Settings.getRetrySettings(manager))),Unit{}))
        R.write(Settings.SettingsManager,settings,manager)
        return Done{Unit{}}
def setAutoRetryEnabled(session: AgentSession,enabled: Bool) -> IO(Result<&2,&2,String,Unit>):
  match session:
    case AgentSession{_,shared,_,+settings,_,_,_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager,settings)
        updated : Result<&2,&2,String,Settings.SettingsManager> <- persistedSetting(Settings.setRetryEnabled(enabled,current))
        retryApplied(settings,shared,updated)
def getAutoRetryEnabled(session: AgentSession) -> IO(Bool):
  match session:
    case AgentSession{_,_,_,settings,_,_,_,_}:
      do IO<Bool>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager,settings)
        return Settings.getRetryEnabled(current)

# upstream cacheWarmingStatus: the current cache-warming state and the policy
# inputs that produced it.
def cacheWarmingStatus(session: AgentSession) -> IO(Warmer.CacheWarmingStatus):
  match session:
    case AgentSession{_, _, hooks, _, _, _, _, _}: Warmer.status(warmerOf(hooks))

def modeApplied(warmer: Warmer.CacheWarmer, settings: R.Ref<Settings.SettingsManager>, updated: Result<&2, &2, String, Settings.SettingsManager>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Unit> <- settingApplied(settings, updated)
    Warmer.onModeChanged(warmer)
    return result

# upstream setCacheWarmingMode: persist the mode and immediately reconcile
# active warming.
def setCacheWarmingMode(session: AgentSession, mode: Settings.CacheWarmingMode) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, _, hooks, +settings, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        updated : Result<&2, &2, String, Settings.SettingsManager> <- persistedSetting(Settings.setCacheWarmingMode(mode, current))
        modeApplied(warmerOf(hooks), settings, updated)

# upstream setSteeringMode / setFollowUpMode: the agent's queue mode, persisted
# to the settings.
def setSteeringMode(session: AgentSession, +mode: T.QueueMode) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{agent, _, _, +settings, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.setSteeringMode(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, mode)
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        updated : Result<&2, &2, String, Settings.SettingsManager> <- persistedSetting(Settings.setSteeringMode(mode, current))
        settingApplied(settings, updated)

def setFollowUpMode(session: AgentSession, +mode: T.QueueMode) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{agent, _, _, +settings, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.setFollowUpMode(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, mode)
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        updated : Result<&2, &2, String, Settings.SettingsManager> <- persistedSetting(Settings.setFollowUpMode(mode, current))
        settingApplied(settings, updated)

def setTransport(session: AgentSession, +transport: Ai.Transport) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{agent, _, _, +settings, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.setTransport(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, transport)
        +current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        updated : Result<&2, &2, String, Settings.SettingsManager> <- persistedSetting(Settings.setTransport(transport, current))
        settingApplied(settings, updated)

# Models and thinking levels
# --------------------------

type ModelMutationOptions is Data:
  ModelMutationOptions{persist: Bool}

type CycleDirection is Data:
  Forward{}
  Backward{}

type ModelCycleResult is Data:
  ModelCycleResult{model: Ai.Model<Ai.JsonValue>, thinkingLevel: Ai.ModelThinkingLevel, isScoped: Bool}

def both(first: Result<&2, &2, String, Unit>, second: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match first:
    case Fail{message}: Fail{message}
    case Done{_}: second

def done() -> IO(Result<&2, &2, String, Unit>): IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

def updateSettings(+settings: R.Ref<Settings.SettingsManager>, change: Settings.SettingsManager -> Settings.Outcome(Settings.SettingsManager)) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
    updated : Result<&2, &2, String, Settings.SettingsManager> <- persistedSetting(change(current))
    settingApplied(settings, updated)

def levelsFor(model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> List<&2, Ai.ModelThinkingLevel>:
  match model:
    case None{}: Levels.all()
    case Some{found}: AiModels.getSupportedThinkingLevels(Ai.JsonValue, found)

def clamped(value: AgentState(), +level: Ai.ModelThinkingLevel) -> Ai.ModelThinkingLevel:
  Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.map(&2, Ai.Model<Ai.JsonValue>, Ai.ModelThinkingLevel, model => AiModels.clampThinkingLevel(Ai.JsonValue, model, level), stateModel(value)), level)

def sameLevel(left: Ai.ModelThinkingLevel, right: Ai.ModelThinkingLevel) -> Bool:
  U32.is_eq(Levels.rank(left), Levels.rank(right))

def recordThinkingChange(+shared: R.Ref<Shared>, +level: Ai.ModelThinkingLevel) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Unit> <- recorded(shared, target => recordThinking(target, level))
    emit(shared, ThinkingLevelChanged{level})
    return result

def persistThinking(settings: R.Ref<Settings.SettingsManager>, level: Ai.ModelThinkingLevel, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  match options:
    case ModelMutationOptions{False{}}: done()
    case ModelMutationOptions{True{}}: updateSettings(settings, current => Settings.setDefaultThinkingLevel(level, current))

# upstream setThinkingLevel: clamp to the model, persist the requested level
# on request, and record and announce the clamped level only when it changes.
def applyThinking(+agent: Runtime.Owner(), shared: R.Ref<Shared>, settings: R.Ref<Settings.SettingsManager>, +level: Ai.ModelThinkingLevel, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    +current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
    +effective : Ai.ModelThinkingLevel = clamped(current, level)
    +previous : Ai.ModelThinkingLevel = stateThinking(current)
    Agent.setThinkingLevel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, effective)
    persisted : Result<&2, &2, String, Unit> <- persistThinking(settings, level, options)
    changed : Result<&2, &2, String, Unit> <- Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), sameLevel(effective, previous), _ => done(), _ => recordThinkingChange(shared, effective))(Unit{})
    return both(persisted, changed)

def setThinkingLevel(session: AgentSession, level: Ai.ModelThinkingLevel, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{agent, shared, _, settings, _, _, _, _}: applyThinking(agent, shared, settings, level, options)

def getAvailableThinkingLevels(session: AgentSession) -> IO(List<&2, Ai.ModelThinkingLevel>):
  do IO<List<&2, Ai.ModelThinkingLevel>>:
    current : AgentState() <- state(session)
    return levelsFor(stateModel(current))

def reasoningModel(model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Bool:
  match model:
    case Some{Ai.Model{_, _, _, _, _, reasoning, _, _, _, _, _, _, _, _, _, _}}: reasoning
    case None{}: False{}

def supportsThinking(session: AgentSession) -> IO(Bool):
  do IO<Bool>:
    current : AgentState() <- state(session)
    return reasoningModel(stateModel(current))

def levelIndex(levels: List<&2, Ai.ModelThinkingLevel>, +current: Ai.ModelThinkingLevel, +index: Nat) -> Maybe<&2, Nat>:
  match levels:
    case Nil{}: None{}
    case level <> rest: Bool.pick(Maybe<&2, Nat>, sameLevel(level, current), Some{index}, levelIndex(rest, current, index + 1n))

# upstream indexOf + 1: an unlisted current level starts at the first.
def followingLevel(+levels: List<&2, Ai.ModelThinkingLevel>, current: Ai.ModelThinkingLevel) -> Ai.ModelThinkingLevel:
  +next = Maybe.default(&2, Nat, Maybe.map(&2, Nat, Nat, index => index + 1n, levelIndex(levels, current, 0n)), 0n)
  Maybe.default(&2, Ai.ModelThinkingLevel, List.get(&2, Ai.ModelThinkingLevel, levels, next % List.length(&2, Ai.ModelThinkingLevel, levels)), Ai.Off{})

def cycleThinkingFrom(session: AgentSession, +current: AgentState(), options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>):
  +model = stateModel(current)
  Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>), reasoningModel(model),
    _ => do IO<Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>>:
      +next : Ai.ModelThinkingLevel = followingLevel(levelsFor(model), stateThinking(current))
      result : Result<&2, &2, String, Unit> <- setThinkingLevel(session, next, options)
      return Result.map(&2, &2, String, Unit, Maybe<&2, Ai.ModelThinkingLevel>, _ => Some{next}, result),
    _ => IO.pure(Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>, Done{None{}}))(Unit{})

# upstream cycleThinkingLevel: the next supported level, or None for a model
# without reasoning.
def cycleThinkingLevel(+session: AgentSession, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>):
  do IO<Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>>:
    current : AgentState() <- state(session)
    cycleThinkingFrom(session, current, options)

def getScopedModels(session: AgentSession) -> IO(List<&2, Models.ScopedModel>):
  match session:
    case AgentSession{_, _, _, _, _, _, _, scoped}: R.read(List<&2, Models.ScopedModel>, scoped)

def setScopedModels(session: AgentSession, scopedModels: List<&2, Models.ScopedModel>) -> IO(Unit):
  match session:
    case AgentSession{_, _, _, _, _, _, _, scoped}: R.write(List<&2, Models.ScopedModel>, scoped, scopedModels)

def modelRuntime(session: AgentSession) -> Models.ModelRuntime:
  match session:
    case AgentSession{_, _, _, _, _, _, models, _}: models

# The per-model setting, then the default setting, then the current level.
def switchThinking(+settings: Settings.SettingsManager, +model: Ai.Model<Ai.JsonValue>, explicit: Maybe<&2, Ai.ModelThinkingLevel>, current: Ai.ModelThinkingLevel) -> Ai.ModelThinkingLevel:
  match explicit:
    case Some{level}: level
    case None{}: Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.or(&2, Ai.ModelThinkingLevel, Settings.getModelThinkingLevel(Models.modelProvider(model), Models.modelId(model), settings), Settings.getDefaultThinkingLevel(settings)), current)

def listsPattern(patterns: List<&2, String>, +wanted: String) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: String.eq(String.to_lower(pattern), wanted) || listsPattern(rest, wanted)

def enableDefault(settings: R.Ref<Settings.SettingsManager>, enabled: Maybe<&2, List<&2, String>>, +reference: String) -> IO(Result<&2, &2, String, Unit>):
  match enabled:
    case None{}: done()
    case Some{Nil{}}: done()
    case Some{+patterns}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), listsPattern(patterns, String.to_lower(reference)),
        _ => done(),
        _ => updateSettings(settings, current => Settings.setEnabledModels(Some{List.append(&2, String, patterns, reference <> Nil{})}, current)))(Unit{})

# upstream _addPersistedDefaultToNonEmptyScope: a persisted default joins a
# non-empty scope and the enabledModels setting that defines it.
def scopeDefault(+settings: R.Ref<Settings.SettingsManager>, +scoped: R.Ref<List<&2, Models.ScopedModel>>, +model: Ai.Model<Ai.JsonValue>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    +items : List<&2, Models.ScopedModel> <- R.read(List<&2, Models.ScopedModel>, scoped)
    Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), List.is_empty(&2, Models.ScopedModel, items) || Models.scopedContains(items, model),
      _ => done(),
      _ => do IO<Result<&2, &2, String, Unit>>:
        R.write(List<&2, Models.ScopedModel>, scoped, Models.addScoped(items, model, None{}))
        current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        enableDefault(settings, Settings.getEnabledModels(current), Models.reference(model)))(Unit{})

def persistModel(+settings: R.Ref<Settings.SettingsManager>, scoped: R.Ref<List<&2, Models.ScopedModel>>, +model: Ai.Model<Ai.JsonValue>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  match options:
    case ModelMutationOptions{False{}}: done()
    case ModelMutationOptions{True{}}:
      do IO<Result<&2, &2, String, Unit>>:
        saved : Result<&2, &2, String, Unit> <- updateSettings(settings, current => Settings.setDefaultModelAndProvider(Models.modelProvider(model), Models.modelId(model), current))
        scopedResult : Result<&2, &2, String, Unit> <- scopeDefault(settings, scoped, model)
        return both(saved, scopedResult)

# The shared body of upstream setModel and the cycles: apply the model, record
# the change, persist it on request, then apply its thinking level.
def switchModel(session: AgentSession, +model: Ai.Model<Ai.JsonValue>, explicit: Maybe<&2, Ai.ModelThinkingLevel>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{+agent, +shared, _, +settings, _, _, _, scoped}:
      do IO<Result<&2, &2, String, Unit>>:
        manager : Settings.SettingsManager <- R.read(Settings.SettingsManager, settings)
        current : AgentState() <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        +level : Ai.ModelThinkingLevel = switchThinking(manager, model, explicit, stateThinking(current))
        Agent.setModel(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, model)
        R.modify(Shared, Unit, shared, value => (withContextWindow(value, Ai.modelContextWindow(model)), Unit{}))
        modelResult : Result<&2, &2, String, Unit> <- recorded(shared, target => recordModel(target, model))
        persisted : Result<&2, &2, String, Unit> <- persistModel(settings, scoped, model, options)
        thought : Result<&2, &2, String, Unit> <- applyThinking(agent, shared, settings, level, ModelMutationOptions{False{}})
        return both(modelResult, both(persisted, thought))

# upstream setModel: the provider must have configured auth.
def setModel(+session: AgentSession, +model: Ai.Model<Ai.JsonValue>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    authorized : Bool <- Models.hasConfiguredAuth(modelRuntime(session), Models.modelProvider(model))
    Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), authorized,
      _ => switchModel(session, model, None{}, options),
      _ => IO.pure(Result<&2, &2, String, Unit>, Fail{"No API key for " ++ Models.reference(model)}))(Unit{})

def sameModel(+left: Ai.Model<Ai.JsonValue>, +right: Ai.Model<Ai.JsonValue>) -> Bool:
  String.eq(Models.modelProvider(left), Models.modelProvider(right)) && String.eq(Models.modelId(left), Models.modelId(right))

def modelIndex(models: List<&2, Ai.Model<Ai.JsonValue>>, +current: Ai.Model<Ai.JsonValue>, +index: Nat) -> Nat:
  match models:
    case Nil{}: 0n
    case model <> rest: Bool.pick(Nat, sameModel(model, current), index, modelIndex(rest, current, index + 1n))

# upstream cycling: from the current model's position (the first when it is
# not listed), wrapping in either direction.
def stepped(direction: CycleDirection, +index: Nat, +count: Nat) -> Nat:
  match direction:
    case Forward{}: (index + 1n) % count
    case Backward{}: (index + count - 1n) % count

def cycledIndex(direction: CycleDirection, +models: List<&2, Ai.Model<Ai.JsonValue>>, current: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Nat:
  stepped(direction, Maybe.default(&2, Nat, Maybe.map(&2, Ai.Model<Ai.JsonValue>, Nat, model => modelIndex(models, model, 0n), current), 0n), List.length(&2, Ai.Model<Ai.JsonValue>, models))

def scopedModels(items: List<&2, Models.ScopedModel>) -> List<&2, Ai.Model<Ai.JsonValue>>:
  match items:
    case Nil{}: Nil{}
    case Models.ScopedModel{model, _} <> rest: model <> scopedModels(rest)

def listsModel(models: List<&2, Ai.Model<Ai.JsonValue>>, +wanted: Ai.Model<Ai.JsonValue>) -> Bool:
  match models:
    case Nil{}: False{}
    case model <> rest: sameModel(model, wanted) || listsModel(rest, wanted)

def availableScope(items: List<&2, Models.ScopedModel>, +available: List<&2, Ai.Model<Ai.JsonValue>>) -> List<&2, Models.ScopedModel>:
  match items:
    case Nil{}: Nil{}
    case Models.ScopedModel{+model, thinking} <> rest:
      +tail = availableScope(rest, available)
      Bool.pick(List<&2, Models.ScopedModel>, listsModel(available, model), Models.ScopedModel{model, thinking} <> tail, tail)

def cycled(+session: AgentSession, +model: Ai.Model<Ai.JsonValue>, explicit: Maybe<&2, Ai.ModelThinkingLevel>, scoped: Bool, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  do IO<Result<&2, &2, String, Maybe<&2, ModelCycleResult>>>:
    result : Result<&2, &2, String, Unit> <- switchModel(session, model, explicit, options)
    current : AgentState() <- state(session)
    return Result.map(&2, &2, String, Unit, Maybe<&2, ModelCycleResult>, _ => Some{ModelCycleResult{model, stateThinking(current), scoped}}, result)

def cycleScopedTo(session: AgentSession, chosen: Maybe<&2, Models.ScopedModel>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  match chosen:
    case Some{Models.ScopedModel{model, thinking}}: cycled(session, model, thinking, True{}, options)
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>, Done{None{}})

def cycleScopedFrom(session: AgentSession, +items: List<&2, Models.ScopedModel>, direction: CycleDirection, current: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  cycleScopedTo(session, List.get(&2, Models.ScopedModel, items, cycledIndex(direction, scopedModels(items), current)), options)

def cycleAvailableTo(session: AgentSession, chosen: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  match chosen:
    case Some{model}: cycled(session, model, None{}, False{}, options)
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>, Done{None{}})

def cycleAvailableFrom(session: AgentSession, +models: List<&2, Ai.Model<Ai.JsonValue>>, direction: CycleDirection, current: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  cycleAvailableTo(session, List.get(&2, Ai.Model<Ai.JsonValue>, models, cycledIndex(direction, models, current)), options)

def cycleScoped(session: AgentSession, +scope: List<&2, Models.ScopedModel>, available: List<&2, Ai.Model<Ai.JsonValue>>, direction: CycleDirection, current: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  +usable = availableScope(scope, available)
  Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>), Nat.is_le(List.length(&2, Models.ScopedModel, usable), 1n),
    _ => IO.pure(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>, Done{None{}}),
    _ => cycleScopedFrom(session, usable, direction, current, options))(Unit{})

def cycleAvailable(session: AgentSession, +available: List<&2, Ai.Model<Ai.JsonValue>>, direction: CycleDirection, current: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>), Nat.is_le(List.length(&2, Ai.Model<Ai.JsonValue>, available), 1n),
    _ => IO.pure(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>, Done{None{}}),
    _ => cycleAvailableFrom(session, available, direction, current, options))(Unit{})

def cycleWithin(session: AgentSession, scope: List<&2, Models.ScopedModel>, available: List<&2, Ai.Model<Ai.JsonValue>>, direction: CycleDirection, current: Maybe<&2, Ai.Model<Ai.JsonValue>>, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  match scope:
    case Nil{}: cycleAvailable(session, available, direction, current, options)
    case item <> rest: cycleScoped(session, item <> rest, available, direction, current, options)

# upstream cycleModel: within the scoped models that are available, else
# within all available models; None when there is nothing to cycle to.
def cycleModel(+session: AgentSession, direction: CycleDirection, options: ModelMutationOptions) -> IO(Result<&2, &2, String, Maybe<&2, ModelCycleResult>>):
  do IO<Result<&2, &2, String, Maybe<&2, ModelCycleResult>>>:
    scope : List<&2, Models.ScopedModel> <- getScopedModels(session)
    available : List<&2, Ai.Model<Ai.JsonValue>> <- Models.getAvailable(modelRuntime(session))
    current : AgentState() <- state(session)
    cycleWithin(session, scope, available, direction, stateModel(current), options)

# upstream setSessionName: record the name and notify.
# upstream emits sessionManager.getSessionName(): the sanitized name the
# session info entry recorded (newlines become spaces, trimmed, empty unset).
def sessionName(state: Shared) -> Maybe<&2, String>:
  S.getSessionName(Unit, Tools.ToolDetails, V.Value, stateOf(sharedSession(state)))

def setSessionName(session: AgentSession, +name: String) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, +shared, _, _, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- recorded(shared, target => recordName(target, name))
        state : Shared <- R.read(Shared, shared)
        emit(shared, SessionInfoChanged{sessionName(state)})
        return result

# upstream session.promptTemplates and resourceLoader.getSkills(): the
# resources this session was loaded (or last reloaded) with.
def templatesOf(loadout: Runtime.Loadout) -> List<&2, Templates.PromptTemplate>:
  match loadout:
    case Runtime.Loadout{_, _, _, templates, _, _, _, _}: templates
def skillsOf(loadout: Runtime.Loadout) -> List<&2, Skills.Skill>:
  match loadout:
    case Runtime.Loadout{_, _, loaded, _, _, _, _, _}: loaded
def agentsFilesOf(loadout: Runtime.Loadout) -> List<&2, Prompt.ContextFile>:
  match loadout:
    case Runtime.Loadout{_, _, _, _, _, agentsFiles, _, _}: agentsFiles
def promptTemplates(session: AgentSession) -> IO(List<&2, Templates.PromptTemplate>):
  do IO<List<&2, Templates.PromptTemplate>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return templatesOf(loadout)
def getSkills(session: AgentSession) -> IO(List<&2, Skills.Skill>):
  do IO<List<&2, Skills.Skill>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return skillsOf(loadout)
def getAgentsFiles(session: AgentSession) -> IO(List<&2, Prompt.ContextFile>):
  do IO<List<&2, Prompt.ContextFile>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return agentsFilesOf(loadout)

# Tools
# -----

def toolNamesOf(tools: List<&2, Tools.Tool()>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case T.AgentTool{name, _, _, _, _, _, _, _, _} <> rest: name <> toolNamesOf(rest)

# upstream ToolInfo without source metadata.
type ToolInfo is Data:
  ToolInfo{name: String, description: String, parameters: V.Value}

def toolInfos(tools: List<&2, Tools.Tool()>) -> List<&2, ToolInfo>:
  match tools:
    case Nil{}: Nil{}
    case T.AgentTool{name, description, parameters, _, _, _, _, _, _} <> rest: ToolInfo{name, description, parameters} <> toolInfos(rest)

def activeNamesIn(loadout: Runtime.Loadout) -> List<&2, String>:
  match loadout:
    case Runtime.Loadout{_, tools, _, _, _, _, _, _}: toolNamesOf(tools)

def registryIn(loadout: Runtime.Loadout) -> List<&2, ToolInfo>:
  match loadout:
    case Runtime.Loadout{_, _, _, _, _, _, _, registry}: toolInfos(registry)

# upstream getActiveToolNames: the active tools, in activation order.
def getActiveToolNames(session: AgentSession) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return activeNamesIn(loadout)

# upstream getAllTools: every tool that can be activated.
def getAllTools(session: AgentSession) -> IO(List<&2, ToolInfo>):
  do IO<List<&2, ToolInfo>>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return registryIn(loadout)

def sectionsAfter(+sections: Prompt.SystemPromptSections(), source: Maybe<&2, Runtime.LoadoutSource>, +names: List<&2, String>, contextFiles: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>) -> Prompt.SystemPromptSections():
  match source:
    case None{}: sections
    case Some{found}: Result.default(&2, &2, String, Prompt.SystemPromptSections(), Runtime.sectionsForTools(found, names, contextFiles, skills), sections)

def activated(loadout: Runtime.Loadout, +names: List<&2, String>) -> Runtime.Loadout:
  match loadout:
    case Runtime.Loadout{+sections, _, +skills, templates, extensions, +files, +source, +registry}:
      +active = Runtime.activeTools(registry, names)
      Runtime.Loadout{sectionsAfter(sections, source, toolNamesOf(active), files, skills), active, skills, templates, extensions, files, source, registry}

# upstream setActiveToolsByName: only registered tools can be activated,
# unknown names are ignored, and the system prompt is rebuilt for the new set;
# the next request declares it (the loadout diff).
def setActiveToolsByName(session: AgentSession, names: List<&2, String>) -> IO(Unit):
  match session:
    case AgentSession{_, _, _, _, _, loadoutRef, _, _}: R.modify(Runtime.Loadout, Unit, loadoutRef, current => (activated(current, names), Unit{}))

def sectionsIn(loadout: Runtime.Loadout) -> Prompt.SystemPromptSections():
  match loadout:
    case Runtime.Loadout{sections, _, _, _, _, _, _, _}: sections

# upstream systemPrompt: the effective system prompt for the next request.
def systemPrompt(session: AgentSession) -> IO(String):
  do IO<String>:
    loadout : Runtime.Loadout <- loadoutOf(session)
    return Result.default(&2, &2, Prompt.Error, String, Prompt.promptText(Done{Prompt.SystemPromptState{"", Some{sectionsIn(loadout)}}}), "")

# upstream AgentSession.reload without extensions: settings are reloaded from
# their files, then skills, prompt templates, context files and the system
# prompt are prepared again; the tools stay. The next request declares the new
# system prompt (the loadout diff), as after any change.
def reloadedLoadout(loadout: Runtime.Loadout, prepared: Result<&2, &2, String, Runtime.Prepared>) -> Result<&2, &2, String, Runtime.Loadout>:
  match loadout prepared:
    case _ Fail{message}: Fail{message}
    case Runtime.Loadout{_, tools, _, _, context, _, source, registry} Done{Runtime.Prepared{sections, skills, templates, files}}: Done{Runtime.Loadout{sections, tools, skills, templates, context, files, source, registry}}
def storeReloaded(+loadoutRef: R.Ref<Runtime.Loadout>, result: Result<&2, &2, String, Runtime.Loadout>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case Done{next}:
      do IO<Result<&2, &2, String, Unit>>:
        R.write(Runtime.Loadout, loadoutRef, next)
        return Done{Unit{}}
def reloadFrom(+loadoutRef: R.Ref<Runtime.Loadout>, +loadout: Runtime.Loadout, settings: Settings.SettingsManager) -> IO(Result<&2, &2, String, Unit>):
  match loadout:
    case Runtime.Loadout{_, _, _, _, _, _, None{}, _}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Runtime.Loadout{_, tools, _, _, _, _, Some{source}, _}:
      do IO<Result<&2, &2, String, Unit>>:
        prepared : Result<&2, &2, String, Runtime.Prepared> <- Runtime.reprepare(source, settings, toolNamesOf(tools))
        storeReloaded(loadoutRef, reloadedLoadout(loadout, prepared))
def reload(session: AgentSession) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, _, _, +settingsRef, _, +loadoutRef, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        current : Settings.SettingsManager <- R.read(Settings.SettingsManager, settingsRef)
        +reloaded : Settings.SettingsManager <- Settings.reloadFiles(current)
        R.write(Settings.SettingsManager, settingsRef, reloaded)
        loadout : Runtime.Loadout <- R.read(Runtime.Loadout, loadoutRef)
        reloadFrom(loadoutRef, loadout, reloaded)

# upstream getSessionStats: counts and billed usage over every stored entry,
# with the current context usage.
def statsKey(+stored: Session(), model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> StatsKey:
  +manager = stateOf(stored)
  StatsKey{List.length(&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>, S.getEntries(Unit, Tools.ToolDetails, V.Value, manager)), S.getLeafId(Unit, Tools.ToolDetails, V.Value, manager), Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored), Maybe.default(&2, F64, Maybe.map(&2, Ai.Model<Ai.JsonValue>, F64, Ai.modelContextWindow, model), F.fromU32(0))}
def sameText(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}
def sameKey(left: StatsKey, right: StatsKey) -> Bool:
  match left right:
    case StatsKey{count, leaf, file, window} StatsKey{otherCount, otherLeaf, otherFile, otherWindow}: Nat.is_eq(count, otherCount) && sameText(leaf, otherLeaf) && sameText(file, otherFile) && F64.is_eq(window, otherWindow)
def statsRefOf(session: AgentSession) -> R.Ref<Maybe<&2, StatsMemo>>:
  match session:
    case AgentSession{_, _, SessionHooks{_, _, _, _, _, _, _, _, stats, _}, _, _, _, _, _}: stats
def recomputed(+memo: R.Ref<Maybe<&2, StatsMemo>>, +key: StatsKey, stored: Session(), model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Result<&2, &2, S.Error, Stats.Stats>):
  do IO<Result<&2, &2, S.Error, Stats.Stats>>:
    +result : Result<&2, &2, S.Error, Stats.Stats> <- IO.pure(Result<&2, &2, S.Error, Stats.Stats>, Stats.stats(stored, model))
    R.write(Maybe<&2, StatsMemo>, memo, Some{StatsMemo{key, result}})
    return result
def memoized(cached: Maybe<&2, StatsMemo>, +memo: R.Ref<Maybe<&2, StatsMemo>>, +key: StatsKey, stored: Session(), model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Result<&2, &2, S.Error, Stats.Stats>):
  match cached:
    case Some{StatsMemo{previous, result}}: Bool.pick(Unit -> IO(Result<&2, &2, S.Error, Stats.Stats>), sameKey(previous, key), _ => IO.pure(Result<&2, &2, S.Error, Stats.Stats>, result), _ => recomputed(memo, key, stored, model))(Unit{})
    case None{}: recomputed(memo, key, stored, model)
def getSessionStats(+session: AgentSession) -> IO(Result<&2, &2, S.Error, Stats.Stats>):
  do IO<Result<&2, &2, S.Error, Stats.Stats>>:
    +stored : Session() <- sessionOf(session)
    current : AgentState() <- state(session)
    +model : Maybe<&2, Ai.Model<Ai.JsonValue>> <- IO.pure(Maybe<&2, Ai.Model<Ai.JsonValue>>, stateModel(current))
    +memo : R.Ref<Maybe<&2, StatsMemo>> <- IO.pure(R.Ref<Maybe<&2, StatsMemo>>, statsRefOf(session))
    cached : Maybe<&2, StatsMemo> <- R.read(Maybe<&2, StatsMemo>, memo)
    memoized(cached, memo, statsKey(stored, model), stored, model)

# upstream getContextUsage: None without a model or context window; unknown
# tokens after a compaction until an assistant responds.
def getContextUsage(+session: AgentSession) -> IO(Result<&2, &2, S.Error, Maybe<&2, Stats.ContextUsage>>):
  do IO<Result<&2, &2, S.Error, Maybe<&2, Stats.ContextUsage>>>:
    stored : Session() <- sessionOf(session)
    current : AgentState() <- state(session)
    return Stats.context(stateOf(stored), Maybe.default(&2, F64, Maybe.map(&2, Ai.Model<Ai.JsonValue>, F64, Ai.modelContextWindow, stateModel(current)), F.fromU32(0)))

# upstream session.settingsManager: the modes read the effective settings and
# change them through the session, which persists each change.
def getSettings(session: AgentSession) -> IO(Settings.SettingsManager):
  match session:
    case AgentSession{_, _, _, settings, _, _, _, _}: R.read(Settings.SettingsManager, settings)

def changeSettings(session: AgentSession, change: Settings.SettingsManager -> Settings.Outcome(Settings.SettingsManager)) -> IO(Result<&2, &2, String, Unit>):
  match session:
    case AgentSession{_, _, _, settings, _, _, _, _}: updateSettings(settings, change)
