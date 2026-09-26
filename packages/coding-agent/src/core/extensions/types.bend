import Base
import ../../../../ai/src/models.bend as AiModels
import ../../../../ai/src/types.bend as Ai
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../tui/src/autocomplete.bend as AC
import ../messages.bend as Messages
import ../model-runtime.bend as Models
import ../skills.bend as Skills
import ../tools/index.bend as Tools
import ./context.bend as Ctx
import ../session-manager.bend as S
import ../compaction/compaction.bend as Compaction
import ../../../../runtime/src/abort.bend as Abort

# upstream core/extensions/types.ts: registrations, events and the loaded
# extension state. Extensions are Bend code linked into the binary; their
# handlers are callbacks over typed events and results.

# Commands
# --------

def ArgumentCompletions() -> Data: C.Callback<String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)>

type CommandCall is Data:
  CommandCall{args: String, ctx: Ctx.ExtensionCommandContext}

# A failure is the message of upstream's rejected handler promise.
def CommandHandler() -> Data: C.Callback<CommandCall, Result<&2, &2, String, Unit>>

# upstream Omit<RegisteredCommand, "name" | "sourceInfo">
type CommandOptions is Data:
  CommandOptions{description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

type RegisteredCommand is Data:
  RegisteredCommand{name: String, sourceInfo: Skills.SourceInfo, description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

# upstream ResolvedCommand extends RegisteredCommand with invocationName.
type ResolvedCommand is Data:
  ResolvedCommand{name: String, invocationName: String, sourceInfo: Skills.SourceInfo, description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

# Errors
# ------

type ExtensionError is Data:
  ExtensionError{extensionPath: String, event: String, error: String, stack: Maybe<&2, String>}

# Events
# ------

def AgentMessage() -> Data: Agent.AgentMessage<Unit, Tools.ToolDetails, Messages.CodingMessage<V.Value>>
def ToolResult() -> Data: Agent.AgentToolResult<Tools.ToolDetails>

type AgentStartEvent is Data:
  AgentStartEvent{}

type AgentEndEvent is Data:
  AgentEndEvent{messages: List<&2, AgentMessage()>}

type AgentSettledEvent is Data:
  AgentSettledEvent{}

type TurnStartEvent is Data:
  TurnStartEvent{turnIndex: Nat, timestamp: F64}

type MessageStartEvent is Data:
  MessageStartEvent{message: AgentMessage()}

type MessageUpdateEvent is Data:
  MessageUpdateEvent{message: AgentMessage(), assistantMessageEvent: Ai.AssistantMessageEvent<V.Value, Unit>}

type MessageEndEvent is Data:
  MessageEndEvent{message: AgentMessage()}

def SessionEntry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

# Session events
# --------------

# upstream TreePreparation: what navigating to `targetId` abandons.
type TreePreparation is Data:
  TreePreparation{targetId: String, oldLeafId: Maybe<&2, String>, commonAncestorId: Maybe<&2, String>, entriesToSummarize: List<&2, SessionEntry()>, userWantsSummary: Bool, customInstructions: Maybe<&2, String>, replaceInstructions: Maybe<&2, Bool>, label: Maybe<&2, String>}

type SessionBeforeTreeEvent is Data:
  SessionBeforeTreeEvent{preparation: TreePreparation, signal: Abort.AbortSignal<Unit>}

type BranchSummaryOverride is Data:
  BranchSummaryOverride{summary: String, details: Maybe<&2, V.Value>, usage: Maybe<&2, Ai.Usage>}

type SessionBeforeTreeResult is Data:
  SessionBeforeTreeResult{cancel: Maybe<&2, Bool>, summary: Maybe<&2, BranchSummaryOverride>, customInstructions: Maybe<&2, String>, replaceInstructions: Maybe<&2, Bool>, label: Maybe<&2, String>}

type SessionTreeEvent is Data:
  SessionTreeEvent{newLeafId: Maybe<&2, String>, oldLeafId: Maybe<&2, String>, summaryEntry: Maybe<&2, SessionEntry()>, fromExtension: Maybe<&2, Bool>}

# upstream "manual" | "threshold" | "overflow"
type CompactionReason is Data:
  ManualReason{}
  ThresholdReason{}
  OverflowReason{}

type SessionBeforeCompactEvent is Data:
  SessionBeforeCompactEvent{preparation: Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>, branchEntries: List<&2, SessionEntry()>, customInstructions: Maybe<&2, String>, reason: CompactionReason, willRetry: Bool, signal: Abort.AbortSignal<Unit>}

type SessionBeforeCompactResult is Data:
  SessionBeforeCompactResult{cancel: Maybe<&2, Bool>, compaction: Maybe<&2, Compaction.CompactionResult>}

type SessionCompactEvent is Data:
  SessionCompactEvent{compactionEntry: SessionEntry(), fromExtension: Bool, reason: CompactionReason, willRetry: Bool}

type SessionCompactFailedEvent is Data:
  SessionCompactFailedEvent{reason: CompactionReason, errorMessage: Maybe<&2, String>, aborted: Bool, willRetry: Bool, fromExtension: Bool}

# Boundaries (turn_end, agent_before_settle)
# ------------------------------------------
# upstream BoundaryState: handlers see the entry drafts earlier handlers
# returned, whether one asked to continue, and a preview of the context
# those drafts would produce; they may replace the drafts and the decision.

type AgentActivityOutcome is Data:
  OutcomeCompleted{}
  OutcomeAborted{}
  OutcomeError{}

# upstream SessionBoundaryDraft. A compaction draft without a first kept
# entry keeps nothing before it.
type SessionBoundaryDraft is Data:
  CustomEntryDraft{customType: String, data: Maybe<&2, V.Value>}
  CustomMessageEntryDraft{customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2, V.Value>}
  ContextEditEntryDraft{targetId: String, replacement: Maybe<&2, S.ContextEditableContent>}
  CompactionEntryDraft{summary: String, firstKeptEntryId: Maybe<&2, String>, details: Maybe<&2, V.Value>, usage: Maybe<&2, Ai.Usage>}

type BoundaryContextPreview is Data:
  BoundaryContextPreview{contextEntries: List<&2, S.ProjectedSessionEntry<Unit, Tools.ToolDetails, V.Value>>, contextMessages: List<&2, AgentMessage()>, llmMessages: List<&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>>, pendingMessages: List<&2, AgentMessage()>, canContinue: Bool}

type BoundaryResult is Data:
  BoundaryResult{entries: Maybe<&2, List<&2, SessionBoundaryDraft>>, continue: Maybe<&2, Bool>}

type TurnEndEvent is Data:
  TurnEndEvent{turnIndex: Nat, message: AgentMessage(), toolResults: List<&2, Ai.ToolResultMessage<Tools.ToolDetails>>, messageEntryId: String, toolResultEntryIds: List<&2, String>, entries: List<&2, SessionBoundaryDraft>, continue: Bool, context: BoundaryContextPreview, outcome: AgentActivityOutcome}

type AgentBeforeSettleEvent is Data:
  AgentBeforeSettleEvent{entries: List<&2, SessionBoundaryDraft>, continue: Bool, context: BoundaryContextPreview, outcome: AgentActivityOutcome}

# What a boundary dispatch starts from (upstream BoundaryBaseEvent).
type BoundaryBase is Data:
  TurnEndBase{turnIndex: Nat, message: AgentMessage(), toolResults: List<&2, Ai.ToolResultMessage<Tools.ToolDetails>>, messageEntryId: String, toolResultEntryIds: List<&2, String>, outcome: AgentActivityOutcome}
  BeforeSettleBase{outcome: AgentActivityOutcome}

# Request context (upstream context and context_with_system)
# ----------------------------------------------------------
# `context` handlers see the conversation without system messages; Pi keeps
# the prompt and tool state. `context_with_system` handlers see the whole
# transcript. A result without messages leaves them unchanged (handlers
# cannot edit event.messages in place).
type ContextEvent is Data:
  ContextEvent{messages: List<&2, AgentMessage()>}

type ContextWithSystemEvent is Data:
  ContextWithSystemEvent{messages: List<&2, AgentMessage()>}

type ContextEventResult is Data:
  ContextEventResult{messages: Maybe<&2, List<&2, AgentMessage()>>}

# upstream sendUserMessage's deliverAs and an input's streamingBehavior:
# "steer" | "followUp".
type UserDelivery is Data:
  UserSteer{}
  UserFollowUp{}

# upstream InputSource: where user input came from.
type InputSource is Data:
  InteractiveSource{}
  RpcSource{}
  ExtensionSource{}

# upstream InputEvent: user input before skill and template expansion.
# `streamingBehavior` is how the input is queued while streaming (None when
# idle); input without images has an empty list.
type InputEvent is Data:
  InputEvent{text: String, images: List<&2, Ai.ImageContent>, source: InputSource, streamingBehavior: Maybe<&2, UserDelivery>}

# upstream InputEventResult. A transform without images keeps the current
# ones.
type InputEventResult is Data:
  InputContinue{}
  InputTransform{text: String, images: Maybe<&2, List<&2, Ai.ImageContent>>}
  InputHandled{}

# Replace the finalized message; the replacement keeps the original's role.
type MessageEndEventResult is Data:
  MessageEndEventResult{message: Maybe<&2, AgentMessage()>}

type ToolExecutionStartEvent is Data:
  ToolExecutionStartEvent{toolCallId: String, toolName: String, args: V.Value}

type ToolExecutionUpdateEvent is Data:
  ToolExecutionUpdateEvent{toolCallId: String, toolName: String, args: V.Value, partialResult: ToolResult()}

type ToolExecutionEndEvent is Data:
  ToolExecutionEndEvent{toolCallId: String, toolName: String, result: ToolResult(), isError: Bool}

# upstream's per-tool ToolCallEvent variants narrow `input` by tool name; the
# native event carries the validated arguments as JSON for every tool.
type ToolCallEvent is Data:
  ToolCallEvent{toolCallId: String, toolName: String, input: V.Value}

type ToolCallEventResult is Data:
  ToolCallEventResult{block: Maybe<&2, Bool>, reason: Maybe<&2, String>, terminate: Maybe<&2, Bool>}

type ToolResultEvent is Data:
  ToolResultEvent{toolCallId: String, toolName: String, input: V.Value, content: List<&2, Ai.TextImageContent>, details: Maybe<&2, Tools.ToolDetails>, isError: Bool, usage: Maybe<&2, Ai.Usage>}

type ToolResultEventResult is Data:
  ToolResultEventResult{content: Maybe<&2, List<&2, Ai.TextImageContent>>, details: Maybe<&2, Tools.ToolDetails>, isError: Maybe<&2, Bool>, usage: Maybe<&2, Ai.Usage>}

type HandlerCall<-E: Data> is Data:
  HandlerCall{event: E, ctx: Ctx.ExtensionContext}

# upstream ExtensionHandler<E, R>: None is a handler returning nothing; a
# failure is the message of the error it threw.
def ExtensionHandler(-E: Data, -R: Data) -> Data: C.Callback<HandlerCall<E>, Result<&2, &2, String, Maybe<&2, R>>>

# One constructor per event, carrying a handler typed by the event and its
# result (upstream's `on` overloads). Later phases add the other events.
type EventHandler is Data:
  OnAgentStart{handler: ExtensionHandler(AgentStartEvent, Unit)}
  OnAgentEnd{handler: ExtensionHandler(AgentEndEvent, Unit)}
  OnAgentSettled{handler: ExtensionHandler(AgentSettledEvent, Unit)}
  OnTurnStart{handler: ExtensionHandler(TurnStartEvent, Unit)}
  OnMessageStart{handler: ExtensionHandler(MessageStartEvent, Unit)}
  OnMessageUpdate{handler: ExtensionHandler(MessageUpdateEvent, Unit)}
  OnMessageEnd{handler: ExtensionHandler(MessageEndEvent, MessageEndEventResult)}
  OnToolExecutionStart{handler: ExtensionHandler(ToolExecutionStartEvent, Unit)}
  OnToolExecutionUpdate{handler: ExtensionHandler(ToolExecutionUpdateEvent, Unit)}
  OnToolExecutionEnd{handler: ExtensionHandler(ToolExecutionEndEvent, Unit)}
  OnToolCall{handler: ExtensionHandler(ToolCallEvent, ToolCallEventResult)}
  OnToolResult{handler: ExtensionHandler(ToolResultEvent, ToolResultEventResult)}
  OnSessionBeforeTree{handler: ExtensionHandler(SessionBeforeTreeEvent, SessionBeforeTreeResult)}
  OnSessionTree{handler: ExtensionHandler(SessionTreeEvent, Unit)}
  OnSessionBeforeCompact{handler: ExtensionHandler(SessionBeforeCompactEvent, SessionBeforeCompactResult)}
  OnSessionCompact{handler: ExtensionHandler(SessionCompactEvent, Unit)}
  OnSessionCompactFailed{handler: ExtensionHandler(SessionCompactFailedEvent, Unit)}
  OnTurnEnd{handler: ExtensionHandler(TurnEndEvent, BoundaryResult)}
  OnContext{handler: ExtensionHandler(ContextEvent, ContextEventResult)}
  OnContextWithSystem{handler: ExtensionHandler(ContextWithSystemEvent, ContextEventResult)}
  OnAgentBeforeSettle{handler: ExtensionHandler(AgentBeforeSettleEvent, BoundaryResult)}
  OnInput{handler: ExtensionHandler(InputEvent, InputEventResult)}

# Events dispatched without a result (upstream emit). Events with results
# have their own emitters in the runner.
type ExtensionEvent is Data:
  AgentStart{event: AgentStartEvent}
  AgentEnd{event: AgentEndEvent}
  AgentSettled{event: AgentSettledEvent}
  TurnStart{event: TurnStartEvent}
  MessageStart{event: MessageStartEvent}
  MessageUpdate{event: MessageUpdateEvent}
  ToolExecutionStart{event: ToolExecutionStartEvent}
  ToolExecutionUpdate{event: ToolExecutionUpdateEvent}
  ToolExecutionEnd{event: ToolExecutionEndEvent}
  SessionTree{event: SessionTreeEvent}
  SessionCompact{event: SessionCompactEvent}
  SessionCompactFailed{event: SessionCompactFailedEvent}

def handlerEventType(handler: EventHandler) -> String:
  match handler:
    case OnAgentStart{_}: "agent_start"
    case OnAgentEnd{_}: "agent_end"
    case OnAgentSettled{_}: "agent_settled"
    case OnTurnStart{_}: "turn_start"
    case OnMessageStart{_}: "message_start"
    case OnMessageUpdate{_}: "message_update"
    case OnMessageEnd{_}: "message_end"
    case OnToolExecutionStart{_}: "tool_execution_start"
    case OnToolExecutionUpdate{_}: "tool_execution_update"
    case OnToolExecutionEnd{_}: "tool_execution_end"
    case OnToolCall{_}: "tool_call"
    case OnToolResult{_}: "tool_result"
    case OnSessionBeforeTree{_}: "session_before_tree"
    case OnSessionTree{_}: "session_tree"
    case OnSessionBeforeCompact{_}: "session_before_compact"
    case OnSessionCompact{_}: "session_compact"
    case OnSessionCompactFailed{_}: "session_compact_failed"
    case OnTurnEnd{_}: "turn_end"
    case OnContext{_}: "context"
    case OnContextWithSystem{_}: "context_with_system"
    case OnAgentBeforeSettle{_}: "agent_before_settle"
    case OnInput{_}: "input"

def eventType(event: ExtensionEvent) -> String:
  match event:
    case AgentStart{_}: "agent_start"
    case AgentEnd{_}: "agent_end"
    case AgentSettled{_}: "agent_settled"
    case TurnStart{_}: "turn_start"
    case MessageStart{_}: "message_start"
    case MessageUpdate{_}: "message_update"
    case ToolExecutionStart{_}: "tool_execution_start"
    case ToolExecutionUpdate{_}: "tool_execution_update"
    case ToolExecutionEnd{_}: "tool_execution_end"
    case SessionTree{_}: "session_tree"
    case SessionCompact{_}: "session_compact"
    case SessionCompactFailed{_}: "session_compact_failed"

# `on` returns the id its unsubscribe removes (upstream removes the handler
# by function identity).
type Subscription is Data:
  Subscription{id: Nat, handler: EventHandler}

# Loaded extensions (upstream Extension and ExtensionRuntime)
# -----------------------------------------------------------

type LoadState is Data:
  Loading{}
  Active{}
  Failed{}

# Provider changes an extension makes while it loads apply when it has loaded
# (upstream applyRuntimeChange).
type ProviderChange is Data:
  RegisterProvider{provider: AiModels.Provider}
  UnregisterProvider{name: String}

type Extension is Data:
  Extension{id: Nat, path: String, resolvedPath: String, hidden: Bool, sourceInfo: Skills.SourceInfo, handlers: List<&2, Subscription>, commands: List<&2, RegisteredCommand>, state: LoadState, changes: List<&2, ProviderChange>}

type PendingProvider is Data:
  PendingProvider{provider: AiModels.Provider, extensionPath: String}

# Where provider registrations go once they are bound (upstream bindCore's
# providerActions): the model runtime, and what to do after a provider
# changed (the session refreshes its current model).
type ProviderBinding is Data:
  ProviderBinding{models: Models.ModelRuntime, changed: Maybe<&2, C.Callback<Unit, Unit>>}

# Before registrations are bound, they queue (upstream
# pendingNativeProviderRegistrations).
# Session actions (upstream ExtensionActions)
# -------------------------------------------
# What pi.sendMessage and pi.sendUserMessage do once the session has bound
# them (upstream bindCore's actions). Both deliver in the background; a
# failure becomes an extension error of "<runtime>".

# upstream sendMessage's message: Pick<CustomMessage, "customType" |
# "content" | "display" | "details">.
type CustomMessageInput is Data:
  CustomMessageInput{customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2, V.Value>}

type DeliverAs is Data:
  DeliverSteer{}
  DeliverFollowUp{}
  DeliverNextTurn{}

type SendMessageOptions is Data:
  SendMessageOptions{triggerTurn: Maybe<&2, Bool>, deliverAs: Maybe<&2, DeliverAs>}

type SendMessage is Data:
  SendMessage{message: CustomMessageInput, options: SendMessageOptions}

# upstream sendUserMessage's options: expandPromptTemplates dispatches
# extension commands and expands skill commands and prompt templates.
type SendUserMessageOptions is Data:
  SendUserMessageOptions{deliverAs: Maybe<&2, UserDelivery>, expandPromptTemplates: Maybe<&2, Bool>}

type SendUserMessage is Data:
  SendUserMessage{content: Ai.UserContent, options: SendUserMessageOptions}

type ExtensionActions is Data:
  ExtensionActions{sendMessage: C.Callback<SendMessage, Unit>, sendUserMessage: C.Callback<SendUserMessage, Unit>}

# `actions` are the session's, once bound; before that the action methods
# fail (upstream's "not initialized" runtime).
type ExtensionRuntimeState is Data:
  ExtensionRuntimeState{extensions: List<&2, Extension>, pendingProviders: List<&2, PendingProvider>, providers: Maybe<&2, ProviderBinding>, nextId: Nat, actions: Maybe<&2, ExtensionActions>}

def ExtensionRuntime() -> Data: R.Ref<ExtensionRuntimeState>

# Inline extensions
# -----------------

type ExtensionAPI is Data:
  ExtensionAPI{runtime: R.Ref<ExtensionRuntimeState>, extension: Nat}

# upstream ExtensionFactory. A failure is the message the factory threw.
def ExtensionFactory() -> Type: ExtensionAPI -> IO(Result<&2, &2, String, Unit>)

# upstream InlineExtension in its named form: `<inline:name>`, omitted from
# the startup list when hidden. Factories are Bend functions, so the list is
# consumed when it is loaded.
type InlineExtension is Type:
  InlineExtension{name: String, factory: ExtensionFactory(), hidden: Bool}

# upstream LoadExtensionsResult.errors
type LoadError is Data:
  LoadError{path: String, error: String}
