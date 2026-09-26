import Base
import ../../../../runtime/src/collation.bend as Collation
import ../../../../runtime/src/stable-sort.bend as Sort
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/models.bend as AiModels
import ../../../../ai/src/auth/types.bend as Auth
import ../../../../ai/src/auth/resolve.bend as AuthResolve
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/filesystem.bend as Filesystem
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/u64.bend as W
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/timer.bend as Timer
import ../../../../runtime/src/abort.bend as Abort
import ../../cli/auth-login.bend as AuthLogin
import ../../cli/session-picker.bend as SessionPicker
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../runtime/src/word-segmenter.bend as Words
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/editor.bend as Editor
import ../../../../tui/src/components/editor-component.bend as Live
import ../../../../tui/src/components/loader.bend as Loader
import ../../../../tui/src/components/select-list.bend as Select
import ../../../../tui/src/keybindings.bend as Keybindings
import ../../../../tui/src/keys.bend as Keys
import ../../../../tui/src/tui-base.bend as Tui
import ../../../../tui/src/tui-main-screen.bend as Screen
import ../../../../tui/src/tui-alt-screen.bend as AltScreen
import ../../../../tui/src/alt-screen-search.bend as AltSearch
import ../../../../tui/src/tui-process.bend as Process
import ../../../../tui/src/terminal.bend as Terminal
import ../../../../tui/src/utils.bend as Utils
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../core/trust-manager.bend as Trust
import ../../core/agent-session-runtime.bend as SessionHost
import ../../core/bash-executor.bend as BashExec
import ../../core/session-cwd.bend as SessionCwd
import ../../core/session-persistence.bend as Persistence
import ../../core/export-html/index.bend as Export
import ../../core/prompt-templates.bend as Templates
import ../../core/session-manager.bend as Tree
import ../../core/session-stats.bend as Stats
import ../../core/tools/index.bend as Tools
import ../../core/skills.bend as Skills
import ../../core/system-prompt.bend as Prompt
import ../../utils/tools-manager.bend as Manager
import ../../core/settings-manager.bend as Settings
import ../../core/model-runtime.bend as Models
import ../../utils/clipboard.bend as Clipboard
import ../../utils/changelog.bend as Changelog
import ../../config.bend as Config
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../core/keybindings.bend as AppKeys
import ./components/footer.bend as Footer
import ./components/status-indicator.bend as Status
import ./components/header.bend as Header
import ./components/keybinding-hints.bend as Hints
import ./components/session-selector.bend as Selector
import ./components/user-message-selector.bend as UserPicker
import ./components/model-selector.bend as ModelPicker
import ./components/thinking-selector.bend as ThinkingPicker
import ./components/scoped-models-selector.bend as ScopePicker
import ./components/settings-selector.bend as SettingsPicker
import ./components/trust-selector.bend as TrustPicker
import ./components/messages.bend as MessageUI
import ./components/custom-editor.bend as CustomEditor
import ./components/session-info.bend as SessionInfo
import ../../core/cache-warmer.bend as Warmer
import ../../core/cache-stats.bend as CacheStats
import ../../core/usage-totals.bend as UsageTotals
import ./components/login-dialog.bend as LoginDialog
import ./theme/color.bend as Color
import ../../../../tui/src/terminal-image.bend as Image
import ./theme/markdown-theme.bend as MarkdownTheme
import ../../utils/syntax-highlight.bend as SyntaxHighlight
import ./theme/theme.bend as Theme
import ./theme/theme-controller.bend as ThemeController
import ./interactive-mode.bend as Interactive
import ./commands.bend as Commands
import ./session-controller.bend as Controller
import ./transcript.bend as Transcript
import ./viewport.bend as View

type Error is Data:
  ThemeData{cause: Theme.LoadError}
  Layout{cause: Tui.Error}
  TerminalStart{cause: Terminal.Error}

def themeError(error: Theme.LoadError) -> String:
  match error:
    case Theme.Read{cause}: "Cannot load theme: " ++ Filesystem.errorMessage(cause)
    case Theme.Decode{_}: "Invalid theme encoding"
    case Theme.Invalid{_}: "Invalid theme"
    case Theme.NotFound{name}: "Theme not found: " ++ name
def errorMessage(error: Error) -> String:
  match error:
    case ThemeData{cause}: themeError(cause)
    case Layout{_}: "Cannot mount interactive layout"
    case TerminalStart{Terminal.System{operation,_,message}}: "Terminal " ++ operation ++ ": " ++ message
    case TerminalStart{_}: "Cannot start terminal"

def converted(result: Result<&2,&2,F.Error,Nat>) -> Nat:
  match result:
    case Done{number}: number
    case Fail{_}: 0n
def count(value: F64) -> Nat: converted(F.convert(value))
def model(value: Ai.Model<Ai.JsonValue>) -> Footer.Model:
  match value:
    case Ai.Model{id,_,_,provider,_,reasoning,_,_,_,_,_,window,_,_,_,_}:
      Footer.Model{id,provider,reasoning,count(window)}
def usage(value: Ai.Usage) -> Footer.Usage:
  match value:
    case Ai.Usage{input,output,read,write,_,_,_,Ai.UsageCost{_,_,_,_,cost}}:
      Footer.Usage{count(input),count(output),count(read),count(write),cost}
def latestModel(previous: Maybe<&2,Footer.Model>,+message: Ai.AssistantMessage<Schema.Value,Unit>) -> Maybe<&2,Footer.Model>:
  match previous:
    case Some{Footer.Model{_,_,reasoning,window}}: Some{Footer.Model{Ai.assistantModel(Schema.Value,Unit,message),Ai.assistantProvider(Schema.Value,Unit,message),reasoning,window}}
    case None{}: previous
def withAssistant(state: Footer.State,+message: Ai.AssistantMessage<Schema.Value,Unit>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,_,context,window,providers,subscription,auto,experimental,statuses}:
      +raw = Ai.assistantUsage(Schema.Value,Unit,message)
      +latest = usage(raw)
      +nextModel = latestModel(chosen,message)
      Footer.State{cwd,home,branch,name,nextModel,thinkingLevel,totals,Some{latest},context,window,providers,subscription,auto,experimental,statuses}
def seedFooter(messages: List<&2,Session.Message()>,state: Footer.State) -> Footer.State:
  match messages:
    case Nil{}: state
    case Agent.LlmMessage{Ai.Assistant{message}} <> rest: seedFooter(rest,withAssistant(state,message))
    case _ <> rest: seedFooter(rest,state)
def initialFooter(+agentState: Session.AgentState(),messages: List<&2,Session.Message()>,cwd: String,home: Maybe<&2,String>,autoCompact: Bool) -> Footer.State:
  +chosen = Maybe.map(&2,Ai.Model<Ai.JsonValue>,Footer.Model,model,Session.stateModel(agentState))
  seedFooter(messages,Footer.State{cwd,home,None{},None{},chosen,Levels.name(Session.stateThinking(agentState)),Footer.emptyUsage(),None{},None{},None{},1n,False{},autoCompact,False{},Nil{}})
def withStatus(state: Footer.State,statuses: List<&2,Footer.Status>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,_}:
      Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def withThinking(state: Footer.State,level: Ai.ModelThinkingLevel) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,_,totals,latest,context,window,providers,subscription,auto,experimental,statuses}:
      Footer.State{cwd,home,branch,name,chosen,Levels.name(level),totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def withChosen(state: Footer.State,+agentState: Session.AgentState()) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,_,_,totals,latest,context,window,providers,subscription,auto,experimental,statuses}:
      Footer.State{cwd,home,branch,name,Maybe.map(&2,Ai.Model<Ai.JsonValue>,Footer.Model,model,Session.stateModel(agentState)),Levels.name(Session.stateThinking(agentState)),totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def withName(state: Footer.State,name: Maybe<&2,String>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,_,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}:
      Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def footerEvent(state: Footer.State,event: Session.AgentSessionEvent) -> Footer.State & Bool:
  match event:
    case Session.AgentEvent{Agent.MessageEnd{Agent.LlmMessage{Ai.Assistant{message}}}}: (withAssistant(state,message),True{})
    case Session.ThinkingLevelChanged{level}: (withThinking(state,level),True{})
    case Session.SessionInfoChanged{name}: (withName(state,name),True{})
    case _: (state,False{})
type WorkingOwned is Type:
  WorkingOwned{indicator: Maybe<&1,Status.Owner>,appearance: Status.Appearance,redraw: Callback.Callback<Unit,Unit>,cancelKey: String}
type Working is Data:
  Working{active: Ref.Ref<Maybe<&2,Loader.Handle>>,owned: Ref.Ref<Maybe<&1,WorkingOwned>>}
type StatusChange is Data:
  ShowStatus{indicator: Status.Indicator}
  ClearStatus{kind: Status.StatusIndicatorKind}
  KeepStatus{}
def workingActive(working: Working) -> Ref.Ref<Maybe<&2,Loader.Handle>>:
  match working: case Working{active,_}: active
def workingRedraw(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,_: Unit) -> IO(Unit):
  Interactive.requestRender(redraw)
def compactionReason(reason: Session.CompactionReason) -> Status.CompactionStatusReason:
  match reason:
    case Session.Manual{}: Status.Manual{}
    case Session.Threshold{}: Status.Threshold{}
    case Session.Overflow{}: Status.Overflow{}
def retryStatus(attempt: Nat,maxAttempts: Nat,delay: Result<&2,&2,Timer.Error,U32>,cancel: String) -> StatusChange:
  match delay:
    case Done{milliseconds}: ShowStatus{Status.RetryStatusIndicator{attempt,maxAttempts,U32.to_nat(milliseconds),cancel}}
    case Fail{_}: ClearStatus{Status.Retry{}}
def statusChange(event: Session.AgentSessionEvent,cancel: String) -> StatusChange:
  match event:
    case Session.AgentEvent{Agent.AgentStart{}}: ShowStatus{Status.WorkingStatusIndicator{"Working",None{}}}
    case Session.AgentEvent{Agent.TurnStart{}}: ShowStatus{Status.WorkingStatusIndicator{"Working",None{}}}
    case Session.AgentEvent{Agent.AgentEnd{_}}: ClearStatus{Status.Working{}}
    case Session.AgentEnd{_,_}: ClearStatus{Status.Working{}}
    case Session.AgentSettled{}: ClearStatus{Status.Working{}}
    case Session.AutoRetryStart{attempt,maxAttempts,delay,_}: retryStatus(attempt,maxAttempts,Timer.milliseconds(delay),cancel)
    case Session.AutoRetryEnd{_,_,_}: ClearStatus{Status.Retry{}}
    case Session.CompactionStart{reason}: ShowStatus{Status.CompactionStatusIndicator{compactionReason(reason),cancel}}
    case Session.CompactionEnd{_,_,_,_,_}: ClearStatus{Status.Compaction{}}
    case Session.SummarizationRetryScheduled{attempt,maxAttempts,delay,_}: retryStatus(attempt,maxAttempts,Timer.milliseconds(delay),cancel)
    case Session.SummarizationRetryAttemptStart{Session.BranchSummarySource{}}: ShowStatus{Status.BranchSummaryStatusIndicator{cancel}}
    case Session.SummarizationRetryAttemptStart{Session.CompactionSource{reason}}: ShowStatus{Status.CompactionStatusIndicator{compactionReason(reason),cancel}}
    case Session.SummarizationRetryFinished{}: ClearStatus{Status.Retry{}}
    case _: KeepStatus{}
def disposeStatus(indicator: Maybe<&1,Status.Owner>) -> IO(Unit):
  match indicator: case None{}: IO.pure(Unit,Unit{}) case Some{owner}: Status.dispose(owner)
def clearStatus(pair: Status.Owner & Status.Handle,kind: Status.StatusIndicatorKind) -> IO(Maybe<&1,Status.Owner>):
  match pair:
    case (owner,Status.Handle{active,_}):
      Bool.pick(Status.Owner -> IO(Maybe<&1,Status.Owner>),Status.sameKind(active,kind),
        retained => do IO<Maybe<&1,Status.Owner>>:
          Status.dispose(retained)
          return None{},
        retained => IO.pure(Maybe<&1,Status.Owner>,Some{retained}))(owner)
def changeStatus(previous: Maybe<&1,Status.Owner>,appearance: Status.Appearance,change: StatusChange) -> IO(Maybe<&1,Status.Owner>):
  match change previous:
    case KeepStatus{} retained: IO.pure(Maybe<&1,Status.Owner>,retained)
    case ClearStatus{_} None{}: IO.pure(Maybe<&1,Status.Owner>,None{})
    case ClearStatus{kind} Some{owner}: clearStatus(Status.borrow(owner),kind)
    case ShowStatus{spec} retained:
      do IO<Maybe<&1,Status.Owner>>:
        disposeStatus(retained)
        next : Status.Owner <- Status.create(spec,appearance)
        return Some{next}
def retainedStatus(indicator: Maybe<&1,Status.Owner>) -> Maybe<&1,Status.Owner> & Maybe<&2,Loader.Handle>:
  match indicator:
    case None{}: (None{},None{})
    case Some{Status.Owner{+spec,appearance,Loader.Owner{resource,+handle,animation},colors,countdown,tick}}:
      (Some{Status.Owner{spec,appearance,Loader.Owner{resource,handle,animation},colors,countdown,tick}},Some{handle})
def workingRetained(pair: Maybe<&1,Status.Owner> & Maybe<&2,Loader.Handle>,appearance: Status.Appearance,request: Callback.Callback<Unit,Unit>,cancel: String,active: Ref.Ref<Maybe<&2,Loader.Handle>>,owned: Ref.Ref<Maybe<&1,WorkingOwned>>) -> IO(Unit):
  match pair:
    case (indicator,handle):
      do IO<Unit>:
        Ref.write(Maybe<&2,Loader.Handle>,active,handle)
        Ref.write(Maybe<&1,WorkingOwned>,owned,Some{WorkingOwned{indicator,appearance,request,cancel}})
def statusChanged(change: StatusChange) -> Bool:
  match change: case KeepStatus{}: False{} case _: True{}
def workingChanged(previous: Maybe<&1,WorkingOwned>,active: Ref.Ref<Maybe<&2,Loader.Handle>>,owned: Ref.Ref<Maybe<&1,WorkingOwned>>,event: Session.AgentSessionEvent) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{WorkingOwned{indicator,+appearance,+request,+cancel}}:
      do IO<Unit>:
        +change : StatusChange <- IO.pure(StatusChange,statusChange(event,cancel))
        next : Maybe<&1,Status.Owner> <- changeStatus(indicator,appearance,change)
        workingRetained(retainedStatus(next),appearance,request,cancel,active,owned)
        Bool.pick(Unit -> IO(Unit),statusChanged(change),_ => Callback.call(Unit,Unit,request,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})
def workingEvent(working: Working,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,event: Session.AgentSessionEvent) -> IO(Unit):
  match working:
    case Working{active,+owned}:
      do IO<Unit>:
        previous : Maybe<&1,WorkingOwned> <- Ref.swap(Maybe<&1,WorkingOwned>,owned,None{})
        workingChanged(previous,active,owned,event)
def setupWorking(working: Working,paint: Callback.Callback<String,String>,theme: Ref.Ref<Theme.Theme>,bindings: Keybindings.KeybindingsManager,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match working:
    case Working{_,owned}:
      do IO<Unit>:
        +request : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,~Unit,~Unit,~workingRedraw,redraw)
        Ref.write(Maybe<&1,WorkingOwned>,owned,Some{WorkingOwned{None{},Status.Appearance{theme,Some{paint},request},request,Hints.keyText(bindings,"app.interrupt")}})
def disposeWorkingOwned(oldOwner: Maybe<&1,WorkingOwned>) -> IO(Unit):
  match oldOwner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{WorkingOwned{indicator,_,request,_}}:
      do IO<Unit>:
        disposeStatus(indicator)
        Callback.dispose(Unit,Unit,request)
def disposeWorking(working: Working) -> IO(Unit):
  match working:
    case Working{active,owned}:
      do IO<Unit>:
        oldActive : Maybe<&2,Loader.Handle> <- Ref.dispose(Maybe<&2,Loader.Handle>,active)
        oldOwner : Maybe<&1,WorkingOwned> <- Ref.dispose(Maybe<&1,WorkingOwned>,owned)
        disposeWorkingOwned(oldOwner)
type Observation is Data:
  Observation{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,footer: Ref.Ref<Footer.State>,working: Working,session: Ref.Ref<Session.AgentSession>}
def warmNoticeShown(show: Bool,transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,text: String) -> IO(Unit):
  match show:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        Transcript.notice(transcript,text)
        Interactive.requestRender(redraw)
# upstream addCacheWarmingUsage: a persisted cache refresh is noted in the
# transcript when cache notices are enabled.
def cacheWarmNotice(transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>,note: Maybe<&2,String>,spent: Ai.Usage) -> IO(Unit):
  do IO<Unit>:
    live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    settings : Settings.SettingsManager <- Session.getSettings(live)
    warmNoticeShown(Settings.getShowCacheMissNotices(settings),transcript,redraw,Warmer.formatCacheWarmingUsage(note,spent))
def usageNotice(transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.EntryAppended{Tree.UsageEntry{_,kind,_,_,spent,note}}: Bool.pick(Unit -> IO(Unit),String.eq(kind,"cache_warm"),_ => cacheWarmNotice(transcript,redraw,session,note,spent),_ => IO.pure(Unit,Unit{}))(Unit{})
    case _: IO.pure(Unit,Unit{})
def structuralResult(transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,result: Result<&2,&2,Tree.Error,List<&2,Session.Message()>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{messages}:
      do IO<Unit>:
        Transcript.seedSession(transcript,messages)
        Interactive.requestRender(redraw)
def structuralEntry(transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,entry: Tree.SessionEntry<Unit,Tools.ToolDetails,Schema.Value>) -> IO(Unit):
  structuralResult(transcript,redraw,Tree.sessionEntryToContextMessages(Unit,Tools.ToolDetails,Schema.Value,entry))
def seedContextEntries(entries: List<&2,Session.Entry()>,+transcript: Transcript.Handle,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case entry <> rest:
      do IO<Unit>:
        structuralEntry(transcript,redraw,entry)
        seedContextEntries(rest,transcript,redraw)
def compactedTranscript(result: Result<&2,&2,Tree.Error,List<&2,Session.Entry()>>,+transcript: Transcript.Handle,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match result:
    case Done{Tree.Compaction{entry} <> retained}:
      do IO<Unit>:
        Transcript.clear(transcript)
        seedContextEntries(retained,transcript,redraw)
        structuralEntry(transcript,redraw,Tree.Compaction{entry})
    case _: Transcript.showError(transcript,"Completed compaction is missing from the session context")
def compactionNotice(+transcript: Transcript.Handle,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.CompactionEnd{_,Some{_},False{},_,_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        current : Session.Session() <- Session.sessionOf(live)
        compactedTranscript(Tree.sessionContextEntries(Unit,Tools.ToolDetails,Schema.Value,Persistence.stateOf(Unit,Tools.ToolDetails,Schema.Value,current)),transcript,redraw)
    case Session.CompactionEnd{Session.Manual{},_,True{},_,_}: Transcript.showError(transcript,"Compaction cancelled")
    case Session.CompactionEnd{_,_,True{},_,_}: Transcript.status(transcript,"Auto-compaction cancelled")
    case Session.CompactionEnd{_,_,_,_,Some{message}}: Transcript.showError(transcript,message)
    case _: IO.pure(Unit,Unit{})
def statusNotice(transcript: Transcript.Handle,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AutoRetryEnd{False{},attempt,error}: Transcript.showError(transcript,"Retry failed after " ++ Nat.show(attempt) ++ " attempts: " ++ Text.orElse(error,"Unknown error"))
    case Session.SummarizationRetryScheduled{_,_,_,message}: Transcript.showError(transcript,message)
    case _: IO.pure(Unit,Unit{})
def structuralNotice(transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.EntryAppended{Tree.Compaction{entry}}: structuralEntry(transcript,redraw,Tree.Compaction{entry})
    case Session.EntryAppended{Tree.BranchSummaryEntry{base,fromId,summary,details,usageValue,fromHook}}: structuralEntry(transcript,redraw,Tree.BranchSummaryEntry{base,fromId,summary,details,usageValue,fromHook})
    case Session.EntryAppended{Tree.CustomMessageEntry{base,kind,content,details,display}}: structuralEntry(transcript,redraw,Tree.CustomMessageEntry{base,kind,content,details,display})
    case _: IO.pure(Unit,Unit{})
def observeCopied(input: Observation,+event: Session.AgentSessionEvent) -> IO(Unit):
  match input:
    case Observation{+transcript,+redraw,footer,working,+session}:
      do IO<Unit>:
        changed : Bool <- Ref.modify(Footer.State,Bool,footer,state => footerEvent(state,event))
        workingEvent(working,redraw,event)
        statusNotice(transcript,event)
        compactionNotice(transcript,redraw,session,event)
        usageNotice(transcript,redraw,session,event)
        structuralNotice(transcript,redraw,event)
        Interactive.onSessionEvent(Interactive.Events{transcript,redraw},event)
        Bool.pick(Unit -> IO(Unit),changed,_ => Interactive.requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def observed(input: Observation,event: Session.AgentSessionEvent) -> IO(Unit):
  observeCopied(input,event)
type ImportRequest is Data: ImportRequest{path: String,cwdOverride: Maybe<&2,String>}
type ResumeRequest is Data: ResumeRequest{path: String,cwdOverride: Maybe<&2,String>}
type SessionChoices is Data: SessionChoices{current: List<&2,Tree.SessionInfo>,all: List<&2,Tree.SessionInfo>}
type ImportState is Data:
  ImportState{host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,backend: Maybe<&2,Callback.Callback<ImportRequest,SessionHost.ImportOutcome>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type ResumeState is Data:
  ResumeState{picker: Ref.Ref<Maybe<&2,SessionPicker.Host>>,dialog: Ref.Ref<Maybe<&2,LoginDialog.Host>>,sessions: Maybe<&2,Callback.Callback<Unit,SessionChoices>>,backend: Maybe<&2,Callback.Callback<ResumeRequest,SessionHost.ResumeOutcome>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type BashActivity is Data:
  BashActivity{active: Bool,closing: Bool,completion: Maybe<&2,Deferred.Deferred<Unit>>}
type BashInput is Data:
  BashInput{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,activity: Ref.Ref<BashActivity>}
type BashReservation is Data:
  BashReserved{previous: Maybe<&2,Deferred.Deferred<Unit>>,completion: Deferred.Deferred<Unit>}
  BashBusy{unused: Deferred.Deferred<Unit>}
  BashClosed{unused: Deferred.Deferred<Unit>}
type TrustContext is Data:
  TrustContext{host: Ref.Ref<Maybe<&2,TrustPicker.Host>>,store: Trust.ProjectTrustStore,autoTrustOnReload: Bool}
def environmentValue(result: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match result:
    case Fail{_}: None{}
    case Done{value}: Some{value}
# upstream autocompleteProvider and fdPath: the provider the editor borrows,
# and whether fd was available when managed tools were set up.
type AutocompleteSlot is Data:
  AutocompleteSlot{owner: Ref.Ref<Maybe<&2,Interactive.AutocompleteOwner>>,files: Ref.Ref<Bool>,home: String,data: String}
type ExportTheme is Data: ExportTheme{active: Ref.Ref<Theme.Theme>,customDir: String}
type CommandObservation is Data:
  CommandObservation{sink: Interactive.CommandSink,session: Ref.Ref<Session.AgentSession>,footer: Ref.Ref<Footer.State>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,builtinDir: String,importState: ImportState,resumeState: ResumeState,selector: Ref.Ref<Maybe<&2,Selector.Host>>,bash: BashInput,settings: Ref.Ref<Maybe<&2,SettingsPicker.Host>>,trust: TrustContext,header: Maybe<&2,Header.Handle>,bindings: Keybindings.KeybindingsManager,autocomplete: AutocompleteSlot,exportTheme: ExportTheme}
# builtinDir is <assets>/packages/coding-agent/src/modes/interactive/theme.
def autocompleteSlot(home: Maybe<&2,String>,builtinDir: String) -> IO(AutocompleteSlot):
  do IO<AutocompleteSlot>:
    owner : Ref.Ref<Maybe<&2,Interactive.AutocompleteOwner>> <- Ref.new(Maybe<&2,Interactive.AutocompleteOwner>,None{})
    files : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    return AutocompleteSlot{owner,files,Maybe.default(&2,String,home,"/"),Path.normalize(builtinDir ++ "/../../../../../runtime/data")}
def disposeOwner(owner: Maybe<&2,Interactive.AutocompleteOwner>) -> IO(Unit):
  match owner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Interactive.disposeAutocompleteProvider(value)
def disposeAutocompleteSlot(slot: AutocompleteSlot) -> IO(Unit):
  match slot:
    case AutocompleteSlot{owner,files,_,_}:
      do IO<Unit>:
        previous : Maybe<&2,Interactive.AutocompleteOwner> <- Ref.dispose(Maybe<&2,Interactive.AutocompleteOwner>,owner)
        disposeOwner(previous)
        found : Bool <- Ref.dispose(Bool,files)
        return Unit{}
def installProvider(editor: Maybe<&2,Live.Handle>,+owner: Interactive.AutocompleteOwner) -> IO(Unit):
  match editor owner:
    case None{} _: IO.pure(Unit,Unit{})
    case Some{handle} Interactive.AutocompleteOwner{provider,_}: Live.setAutocompleteProvider(handle,provider)
def replaceProvider(slot: AutocompleteSlot,editor: Ref.Ref<Maybe<&2,Live.Handle>>,created: Maybe<&2,Interactive.AutocompleteOwner>) -> IO(Unit):
  match slot created:
    case _ None{}: IO.pure(Unit,Unit{})
    case AutocompleteSlot{owner,_,_,_} Some{+next}:
      do IO<Unit>:
        target : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        installProvider(target,next)
        previous : Maybe<&2,Interactive.AutocompleteOwner> <- Ref.swap(Maybe<&2,Interactive.AutocompleteOwner>,owner,Some{next})
        disposeOwner(previous)
# upstream setupAutocompleteProvider: rebuilt at startup and on /reload.
def autocompleteFiles(slot: AutocompleteSlot) -> Ref.Ref<Bool>:
  match slot: case AutocompleteSlot{_,files,_,_}: files
def setupAutocomplete(+slot: AutocompleteSlot,editor: Ref.Ref<Maybe<&2,Live.Handle>>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match slot:
    case AutocompleteSlot{_,files,home,data}:
      do IO<Unit>:
        recursive : Bool <- Ref.read(Bool,files)
        created : Maybe<&2,Interactive.AutocompleteOwner> <- Interactive.createAutocompleteProvider(session,home,data,recursive)
        replaceProvider(slot,editor,created)
def firstPath(args: List<&2,String>) -> Maybe<&2,String>:
  match args:
    case Nil{}: None{}
    case path <> _: Some{path}
def exportPath(requested: Maybe<&2,String>) -> Maybe<&2,String>:
  match requested:
    case None{}: None{}
    case Some{text}: firstPath(Templates.parseCommandArgs(text))
def jsonlWritten(path: String,result: Result<&2,&2,Filesystem.Error,Unit>) -> Result<&2,&2,String,String>:
  match result:
    case Done{_}: Done{path}
    case Fail{error}: Fail{Filesystem.errorMessage(error)}
def branchText(result: Persistence.Outcome(String)) -> Result<&2,&2,String,String>:
  match result:
    case Done{text}: Done{text}
    case Fail{error}: Fail{Persistence.message(error)}
def branchAt(stored: Session.Session(),time: Persistence.Outcome(String)) -> Result<&2,&2,String,String>:
  match time:
    case Fail{error}: Fail{Persistence.message(error)}
    case Done{timestamp}: branchText(Persistence.branchContent(~Unit,~Tools.ToolDetails,~Schema.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,Session.stateOf(stored),timestamp))
def writeBranchCreated(+target: String,+content: String,created: Result<&2,&2,Filesystem.Error,Unit>) -> IO(Result<&2,&2,String,String>):
  match created:
    case Fail{error}: IO.pure(Result<&2,&2,String,String>,Fail{Filesystem.errorMessage(error)})
    case Done{_}:
      do IO<Result<&2,&2,String,String>>:
        result : Result<&2,&2,Filesystem.Error,Unit> <- Filesystem.writeFile(target,content)
        return jsonlWritten(target,result)
def writeBranch(+target: String,content: Result<&2,&2,String,String>) -> IO(Result<&2,&2,String,String>):
  match content:
    case Fail{message}: IO.pure(Result<&2,&2,String,String>,Fail{message})
    case Done{text}:
      do IO<Result<&2,&2,String,String>>:
        created : Result<&2,&2,Filesystem.Error,Unit> <- Filesystem.mkdir(Path.join(target,".."))
        writeBranchCreated(target,text,created)
def exportJsonlResolved(session: Session.AgentSession,resolved: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  match resolved:
    case None{}: IO.pure(Result<&2,&2,String,String>,Fail{"Could not resolve export path"})
    case Some{+target}:
      do IO<Result<&2,&2,String,String>>:
        stored : Session.Session() <- Session.sessionOf(session)
        timestamp : Persistence.Outcome(String) <- Persistence.isoNow()
        writeBranch(target,branchAt(stored,timestamp))
def exportJsonl(session: Session.AgentSession,cwd: String,path: String) -> IO(Result<&2,&2,String,String>):
  exportJsonlResolved(session,Path.resolve(cwd,path))
def exportWithAssets(+session: Session.AgentSession,path: Maybe<&2,String>,theme: Theme.Theme,themePath: String,assets: Result<&2,&2,String,Export.Assets>) -> IO(Result<&2,&2,String,String>):
  match assets:
    case Fail{message}: IO.pure(Result<&2,&2,String,String>,Fail{message})
    case Done{loaded}:
      do IO<Result<&2,&2,String,String>>:
        styled : Export.Assets <- Export.themed(loaded,theme,themePath)
        stored : Session.Session() <- Session.sessionOf(session)
        agentState : Session.AgentState() <- Session.state(session)
        Export.write(styled,stored,agentState,path)
def exportThemePath(theme: Theme.Theme,builtinDir: String,customDir: String) -> String:
  match theme:
    case Theme.Theme{+name,_,_,_,_,_}:
      Bool.pick(String,String.eq(name,"dark") || String.eq(name,"light"),Path.join(builtinDir,name ++ ".json"),Path.join(customDir,name ++ ".json"))
def exportHtml(session: Session.AgentSession,+builtinDir: String,customDir: String,+theme: Theme.Theme,path: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    assets : Result<&2,&2,String,Export.Assets> <- Export.loadAssets(Path.join(builtinDir,"../../../core/export-html"))
    exportWithAssets(session,path,theme,exportThemePath(theme,builtinDir,customDir),assets)
def exportWithPath(session: Session.AgentSession,cwd: String,builtinDir: String,customDir: String,theme: Theme.Theme,+path: String,jsonl: Bool) -> IO(Result<&2,&2,String,String>):
  match jsonl:
    case True{}: exportJsonl(session,cwd,path)
    case False{}: exportHtml(session,builtinDir,customDir,theme,Some{path})
def exportChosen(session: Session.AgentSession,cwd: String,builtinDir: String,customDir: String,theme: Theme.Theme,path: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  match path:
    case Some{+path}: exportWithPath(session,cwd,builtinDir,customDir,theme,path,String.ends_with(path,".jsonl"))
    case None{}: exportHtml(session,builtinDir,customDir,theme,None{})
def exportCurrent(session: Session.AgentSession,cwd: String,builtinDir: String,customDir: String,theme: Theme.Theme,requested: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  exportChosen(session,cwd,builtinDir,customDir,theme,exportPath(requested))
def exportNotice(result: Result<&2,&2,String,String>) -> Interactive.SubmissionFailure:
  match result:
    case Done{path}: Interactive.CommandNotice{"Session exported to: " ++ path}
    case Fail{message}: Interactive.CommandFailure{"Failed to export session: " ++ message}
def exportObserved(input: CommandObservation,requested: Maybe<&2,String>) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,failure,redraw,cwd,builtinDir,_,_,_,_,_,_,_,_,_,ExportTheme{active,customDir}}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        theme : Theme.Theme <- Ref.read(Theme.Theme,active)
        result : Result<&2,&2,String,String> <- exportCurrent(live,cwd,builtinDir,customDir,theme,requested)
        Interactive.report(failure,exportNotice(result))
def importStatus(state: ImportState,status: Interactive.SubmissionFailure) -> IO(Unit):
  match state:
    case ImportState{_,_,failure,redraw}:
      do IO<Unit>:
        Interactive.report(failure,status)
def importAnswer(target: Maybe<&2,LoginDialog.Host>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,title: String,choices: List<&2,LoginDialog.Choice>) -> IO(String):
  match target:
    case None{}: IO.pure(String,"")
    case Some{+dialog}:
      do IO<String>:
        +pending : Deferred.Deferred<String> <- LoginDialog.openChoices(dialog,title,choices)
        Interactive.requestRender(redraw)
        answer : String <- Deferred.result(String,pending)
        Deferred.dispose(String,pending)
        LoginDialog.close(dialog)
        Interactive.requestRender(redraw)
        return answer
def importConfirm(state: ImportState,title: String,yes: LoginDialog.Choice,no: LoginDialog.Choice) -> IO(String):
  match state:
    case ImportState{host,_,_,redraw}:
      do IO<String>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        importAnswer(target,redraw,title,yes <> no <> Nil{})
def importInvoked(state: ImportState,path: String,cwdOverride: Maybe<&2,String>) -> IO(SessionHost.ImportOutcome):
  match state:
    case ImportState{_,None{},_,_}: IO.pure(SessionHost.ImportOutcome,SessionHost.ImportFailed{"Import is unavailable"})
    case ImportState{_,Some{backend},_,_}: Callback.call(ImportRequest,SessionHost.ImportOutcome,backend,ImportRequest{path,cwdOverride})
def importReported(state: ImportState,path: String,result: SessionHost.ImportOutcome) -> IO(Unit):
  match result:
    case SessionHost.Imported{_}: importStatus(state,Interactive.CommandNotice{"Session imported from: " ++ path})
    case SessionHost.ImportFailed{message}: importStatus(state,Interactive.CommandFailure{"Failed to import session: " ++ message})
    case SessionHost.ImportNeedsCwd{issue}: importStatus(state,Interactive.CommandFailure{"Failed to import session: " ++ SessionCwd.formatMissingSessionCwdError(issue)})
def importFallbackChosen(+state: ImportState,+path: String,fallback: String,answer: String) -> IO(Unit):
  match answer:
    case "yes":
      do IO<Unit>:
        result : SessionHost.ImportOutcome <- importInvoked(state,path,Some{fallback})
        importReported(state,path,result)
    case _: importStatus(state,Interactive.CommandNotice{"Import cancelled"})
def importFallback(+state: ImportState,path: String,issue: SessionCwd.SessionCwdIssue) -> IO(Unit):
  match issue:
    case SessionCwd.SessionCwdIssue{_,missing,+fallback}:
      do IO<Unit>:
        answer : String <- importConfirm(state," Session cwd not found · " ++ missing,LoginDialog.Choice{LoginDialog.TextChoice{"yes"},"Continue in current cwd",fallback,"Continue in current cwd"},LoginDialog.Choice{LoginDialog.TextChoice{"no"},"Cancel import","","Cancel import"})
        importFallbackChosen(state,path,fallback,answer)
def importFirstResult(state: ImportState,path: String,result: SessionHost.ImportOutcome) -> IO(Unit):
  match result:
    case SessionHost.ImportNeedsCwd{issue}: importFallback(state,path,issue)
    case other: importReported(state,path,other)
def importConfirmed(+state: ImportState,+path: String,answer: String) -> IO(Unit):
  match answer:
    case "yes":
      do IO<Unit>:
        result : SessionHost.ImportOutcome <- importInvoked(state,path,None{})
        importFirstResult(state,path,result)
    case _: importStatus(state,Interactive.CommandNotice{"Import cancelled"})
def importRequested(+state: ImportState,path: Maybe<&2,String>) -> IO(Unit):
  match path:
    case None{}: importStatus(state,Interactive.CommandFailure{"Usage: /import <path.jsonl>"})
    case Some{+input}:
      do IO<Unit>:
        answer : String <- importConfirm(state," Import session · Replace current session with " ++ input ++ "?",LoginDialog.Choice{LoginDialog.TextChoice{"yes"},"Yes","Replace current session","Yes"},LoginDialog.Choice{LoginDialog.TextChoice{"no"},"No","Keep current session","No"})
        importConfirmed(state,input,answer)
def importObserved(input: CommandObservation,requested: Maybe<&2,String>) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,_,_,_,state,_,_,_,_,_,_,_,_,_}: importRequested(state,exportPath(requested))
def resumeStatus(state: ResumeState,status: Interactive.SubmissionFailure) -> IO(Unit):
  match state:
    case ResumeState{_,_,_,_,failure,redraw}:
      do IO<Unit>:
        Interactive.report(failure,status)
def resumeInvoked(state: ResumeState,path: String,cwdOverride: Maybe<&2,String>) -> IO(SessionHost.ResumeOutcome):
  match state:
    case ResumeState{_,_,_,None{},_,_}: IO.pure(SessionHost.ResumeOutcome,SessionHost.ResumeFailed{"Resume is unavailable"})
    case ResumeState{_,_,_,Some{backend},_,_}: Callback.call(ResumeRequest,SessionHost.ResumeOutcome,backend,ResumeRequest{path,cwdOverride})
def resumeFinal(state: ResumeState,result: SessionHost.ResumeOutcome) -> IO(Unit):
  match result:
    case SessionHost.Resumed{}: resumeStatus(state,Interactive.CommandNotice{"Resumed session"})
    case SessionHost.ResumeFailed{message}: resumeStatus(state,Interactive.CommandFailure{"Failed to resume session: " ++ message})
    case SessionHost.ResumeNeedsCwd{issue}: resumeStatus(state,Interactive.CommandFailure{"Failed to resume session: " ++ SessionCwd.formatMissingSessionCwdError(issue)})
def resumeFallbackResult(+state: ResumeState,path: String,fallback: String,answer: String) -> IO(Unit):
  match answer:
    case "yes":
      do IO<Unit>:
        result : SessionHost.ResumeOutcome <- resumeInvoked(state,path,Some{fallback})
        resumeFinal(state,result)
    case _: resumeStatus(state,Interactive.CommandNotice{"Resume cancelled"})
def resumeMissing(+state: ResumeState,+path: String,issue: SessionCwd.SessionCwdIssue) -> IO(Unit):
  match state issue:
    case ResumeState{_,dialog,_,_,_,redraw} SessionCwd.SessionCwdIssue{_,missing,+fallback}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,dialog)
        answer : String <- importAnswer(target,redraw," Session cwd not found · " ++ missing,LoginDialog.Choice{LoginDialog.TextChoice{"yes"},"Continue in current cwd",fallback,"Continue in current cwd"} <> LoginDialog.Choice{LoginDialog.TextChoice{"no"},"Cancel resume","","Cancel resume"} <> Nil{})
        resumeFallbackResult(state,path,fallback,answer)
def resumeResult(state: ResumeState,path: String,result: SessionHost.ResumeOutcome) -> IO(Unit):
  match result:
    case SessionHost.ResumeNeedsCwd{issue}: resumeMissing(state,path,issue)
    case other: resumeFinal(state,other)
def resumePath(+state: ResumeState,+path: String,cwdOverride: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    result : SessionHost.ResumeOutcome <- resumeInvoked(state,path,cwdOverride)
    resumeResult(state,path,result)
def resumePicked(state: ResumeState,path: String) -> IO(Unit): IO.spawn(Unit,resumePath(state,path,None{}))
def matchResumePicker(target: Maybe<&2,SessionPicker.Host>,current: List<&2,Tree.SessionInfo>,all: List<&2,Tree.SessionInfo>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}:
      do IO<Unit>:
        SessionPicker.openHost(host,current,all)
        Interactive.requestRender(redraw)
def resumeOpen(state: ResumeState,choices: SessionChoices) -> IO(Unit):
  match state choices:
    case ResumeState{picker,_,_,_,_,redraw} SessionChoices{current,all}:
      do IO<Unit>:
        target : Maybe<&2,SessionPicker.Host> <- Ref.read(Maybe<&2,SessionPicker.Host>,picker)
        matchResumePicker(target,current,all,redraw)
def resumeRequested(+state: ResumeState) -> IO(Unit):
  match state:
    case ResumeState{_,_,None{},_,_,_}: resumeStatus(state,Interactive.CommandFailure{"Resume is unavailable"})
    case ResumeState{_,_,Some{backend},_,_,_}:
      do IO<Unit>:
        choices : SessionChoices <- Callback.call(Unit,SessionChoices,backend,Unit{})
        resumeOpen(state,choices)
def resumeObserved(input: CommandObservation) -> IO(Unit):
  match input: case CommandObservation{_,_,_,_,_,_,_,_,state,_,_,_,_,_,_,_,_}: resumeRequested(state)
def selectorNotice(failure: Interactive.StatusSink,message: String) -> IO(Unit):
  Interactive.report(failure,Interactive.CommandNotice{message})
def openTree(target: Maybe<&2,Selector.Host>,state: Selector.State) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: Selector.open(host,state)
def openCandidate(selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Interactive.StatusSink,+state: Selector.State,empty: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),Selector.hasRows(state),_ => do IO<Unit>:
    target : Maybe<&2,Selector.Host> <- Ref.read(Maybe<&2,Selector.Host>,selector)
    openTree(target,state),_ => selectorNotice(failure,empty))(Unit{})
def selectorFilter(value: Settings.TreeFilterMode) -> Selector.Filter:
  match value:
    case Settings.DefaultFilter{}: Selector.Default{}
    case Settings.NoTools{}: Selector.NoTools{}
    case Settings.UserOnly{}: Selector.UserOnly{}
    case Settings.LabeledOnly{}: Selector.LabeledOnly{}
    case Settings.AllEntries{}: Selector.All{}
def matchTree(selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Interactive.StatusSink,result: Result<&2,&2,Tree.Error,List<&2,Selector.Node()>>,leaf: Maybe<&2,String>,filter: Selector.Filter) -> IO(Unit):
  match result:
    case Fail{_}: selectorNotice(failure,"Cannot load session tree")
    case Done{nodes}: openCandidate(selector,failure,Selector.createWithFilter(nodes,leaf,24n,filter),"No entries in session")
def forkItems(entries: List<&2,Selector.Entry()>) -> List<&2,UserPicker.UserMessageItem>:
  match entries:
    case Nil{}: Nil{}
    case Tree.SessionMessageEntry{Tree.SessionEntryBase{id,_,timestamp},Agent.LlmMessage{Ai.User{Ai.UserMessage{content,_}}}} <> rest:
      +text = Selector.contentText(content)
      +tail = forkItems(rest)
      Bool.pick(List<&2,UserPicker.UserMessageItem>,String.is_empty(text),tail,UserPicker.UserMessageItem{id,text,Some{timestamp}} <> tail)
    case _ <> rest: forkItems(rest)
def openForkTarget(target: Maybe<&2,Selector.Host>,component: UserPicker.UserMessageSelectorComponent) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: Selector.openFork(host,component)
def openForkPicker(selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Interactive.StatusSink,items: List<&2,UserPicker.UserMessageItem>) -> IO(Unit):
  match items:
    case Nil{}: selectorNotice(failure,"No messages to fork from")
    case item <> rest:
      do IO<Unit>:
        target : Maybe<&2,Selector.Host> <- Ref.read(Maybe<&2,Selector.Host>,selector)
        openForkTarget(target,UserPicker.new(item <> rest,None{}))
def selectorFromState(mode: Selector.Mode,+state: Session.State(),filter: Selector.Filter,selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Interactive.StatusSink) -> IO(Unit):
  match mode:
    case Selector.TreeMode{}: matchTree(selector,failure,Tree.getTree(Unit,Tools.ToolDetails,Schema.Value,state),Tree.getLeafId(Unit,Tools.ToolDetails,Schema.Value,state),filter)
    case Selector.ForkMode{}: openForkPicker(selector,failure,forkItems(Tree.getEntries(Unit,Tools.ToolDetails,Schema.Value,state)))
def openSessionSelector(mode: Selector.Mode,session: Ref.Ref<Session.AgentSession>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    current : Session.Session() <- Session.sessionOf(live)
    settings : Settings.SettingsManager <- Session.getSettings(live)
    filter : Settings.TreeFilterMode = Settings.getTreeFilterMode(settings)
    selectorFromState(mode,Session.stateOf(current),selectorFilter(filter),selector,failure)
    Interactive.requestRender(redraw)
def treeObserved(input: CommandObservation,mode: Selector.Mode) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,failure,redraw,_,_,_,_,selector,_,_,_,_,_,_,_}: openSessionSelector(mode,session,selector,failure,redraw)
type BashChunk is Data: BashChunk{message: MessageUI.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def bashChunk(target: BashChunk,delta: String) -> IO(Unit):
  match target:
    case BashChunk{message,redraw}:
      do IO<Unit>:
        Transcript.appendBash(message,delta)
        Interactive.requestRender(redraw)
def bashFailed(input: BashInput,message: MessageUI.Handle,+error: String) -> IO(Unit):
  match input:
    case BashInput{_,_,_,failure,redraw,_}:
      do IO<Unit>:
        Transcript.failBash(message)
        Interactive.report(failure,Interactive.CommandFailure{"Bash command failed: " ++ error})
def bashDone(input: BashInput,message: MessageUI.Handle,result: BashExec.BashResult) -> IO(Unit):
  match input result:
    case BashInput{_,_,_,_,redraw,_} BashExec.BashResult{output,exitCode,cancelled,truncated,path}:
      do IO<Unit>:
        Transcript.finishBash(message,output,exitCode,cancelled,truncated,path)
        Interactive.requestRender(redraw)
def bashCompleted(input: BashInput,message: MessageUI.Handle,result: Result<&2,&2,String,BashExec.BashResult>) -> IO(Unit):
  match result:
    case Fail{error}: bashFailed(input,message,error)
    case Done{value}: bashDone(input,message,value)
def idleBash(state: BashActivity) -> BashActivity & Unit:
  match state:
    case BashActivity{_,closing,completion}: (BashActivity{False{},closing,completion},Unit{})
def runBashTask(+input: BashInput,+command: String,+excluded: Bool,completion: Deferred.Deferred<Unit>) -> IO(Unit):
  match input:
    case BashInput{session,transcript,_,_,redraw,activity}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        +message : MessageUI.Handle <- Transcript.startBash(transcript,command,excluded)
        Interactive.requestRender(redraw)
        +chunk : Callback.Callback<String,Unit> <- Callback.create(~BashChunk,~String,~Unit,~bashChunk,BashChunk{message,redraw})
        result : Result<&2,&2,String,BashExec.BashResult> <- Session.executeBash(live,command,Some{chunk},Session.BashOptions{Some{excluded},None{},None{}})
        Callback.dispose(String,Unit,chunk)
        bashCompleted(input,message,result)
        Ref.modify(BashActivity,Unit,activity,idleBash)
        settled : Bool <- Deferred.resolve(Unit,completion,Unit{})
        return Unit{}
def restoreBashEditor(target: Maybe<&2,Live.Handle>,command: String) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}: Live.setText(handle,command)
def bashBusy(input: BashInput,command: String,excluded: Bool) -> IO(Unit):
  match input:
    case BashInput{_,_,editor,failure,redraw,_}:
      do IO<Unit>:
        target : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        restoreBashEditor(target,Bool.pick(String,excluded,"!!","!") ++ command)
        Interactive.report(failure,Interactive.CommandWarning{"A bash command is already running. Press Esc to cancel it first."})
def reserveBash(state: BashActivity,+fresh: Deferred.Deferred<Unit>) -> BashActivity & BashReservation:
  match state:
    case BashActivity{active,True{},completion}: (BashActivity{active,True{},completion},BashClosed{fresh})
    case BashActivity{True{},False{},completion}: (BashActivity{True{},False{},completion},BashBusy{fresh})
    case BashActivity{False{},False{},previous}: (BashActivity{True{},False{},Some{fresh}},BashReserved{previous,fresh})
def disposePrevious(previous: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{+done}:
      do IO<Unit>:
        completed : Unit <- Deferred.result(Unit,done)
        Deferred.dispose(Unit,done)
def disposeBashActivity(state: BashActivity) -> IO(Unit):
  match state:
    case BashActivity{_,_,None{}}: IO.pure(Unit,Unit{})
    case BashActivity{_,_,Some{done}}: Deferred.dispose(Unit,done)
def bashReserved(input: BashInput,command: String,excluded: Bool,reservation: BashReservation) -> IO(Unit):
  match reservation:
    case BashBusy{unused}:
      do IO<Unit>:
        Deferred.dispose(Unit,unused)
        bashBusy(input,command,excluded)
    case BashClosed{unused}: Deferred.dispose(Unit,unused)
    case BashReserved{previous,completion}:
      do IO<Unit>:
        disposePrevious(previous)
        IO.spawn(Unit,runBashTask(input,command,excluded,completion))
def bashRequested(+input: BashInput,+command: String,+excluded: Bool) -> IO(Unit):
  match input:
    case BashInput{session,_,_,_,_,activity}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        running : Bool <- Session.isBashRunning(live)
        Bool.pick(Unit -> IO(Unit),running,_ => bashBusy(input,command,excluded),_ => do IO<Unit>:
          fresh : Deferred.Deferred<Unit> <- Deferred.new(Unit)
          reservation : BashReservation <- Ref.modify(BashActivity,BashReservation,activity,current => reserveBash(current,fresh))
          bashReserved(input,command,excluded,reservation))(Unit{})
def bashObserved(input: CommandObservation,command: String,excluded: Bool) -> IO(Unit):
  match input: case CommandObservation{_,_,_,_,_,_,_,_,_,_,bash,_,_,_,_,_,_}: bashRequested(bash,command,excluded)
def ordinaryCommandObserved(input: CommandObservation,action: Commands.Action) -> IO(Unit):
  match input:
    case CommandObservation{sink,session,footer,_,_,_,_,_,_,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        changed : Bool <- Interactive.commandResult(sink,action)
        Bool.pick(Unit -> IO(Unit),changed,_ => do IO<Unit>:
          live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
          state : Session.AgentState() <- Session.state(live)
          Ref.modify(Footer.State,Unit,footer,current => (withChosen(current,state),Unit{})),_ => IO.pure(Unit,Unit{}))(Unit{})
def copyResult(transcript: Transcript.Handle,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: Transcript.status(transcript,"Copied last agent message to clipboard")
    case Fail{message}: Transcript.showError(transcript,message)
def copyText(transcript: Transcript.Handle,cwd: String,text: Maybe<&2,String>) -> IO(Unit):
  match text:
    case None{}: Transcript.showError(transcript,"No agent messages to copy yet.")
    case Some{value}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Clipboard.copy(value,cwd)
        copyResult(transcript,result)
# upstream handleSessionCommand: session stats, cache waste and the per-model
# cost breakdown over every stored entry.
def sessionInfoOf(stats: Stats.Stats,+state: Tree.SessionManager<Unit,Tools.ToolDetails,Schema.Value>,models: Models.ModelRuntime,warming: SessionInfo.CacheWarmingInfo) -> SessionInfo.SessionInfo:
  match stats:
    case Stats.Stats{file,id,Stats.Totals{users,assistants,calls,results,messages,input,output,cacheRead,cacheWrite,cost},_}:
      +entries = Tree.getEntries(Unit,Tools.ToolDetails,Schema.Value,state)
      SessionInfo.SessionInfo{Tree.getSessionName(Unit,Tools.ToolDetails,Schema.Value,state),file,id,messages,users,assistants,calls,results,input,output,cacheRead,cacheWrite,cost,warming,CacheStats.computeCacheWaste(~Models.ModelRuntime,~Models.cacheReadPrice,Unit,Tools.ToolDetails,Schema.Value,models,entries),UsageTotals.getUsageCostBreakdown(Unit,Tools.ToolDetails,Schema.Value,entries)}
# upstream reads the cache-warming mode from the settings and the status
# from the session, formatted at the time of the command.
def cacheWarmingInfo(+live: Session.AgentSession) -> IO(SessionInfo.CacheWarmingInfo):
  do IO<SessionInfo.CacheWarmingInfo>:
    settings : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,Session.settingsOf(live))
    status : Warmer.CacheWarmingStatus <- Session.cacheWarmingStatus(live)
    now : F64 <- Date.now()
    return SessionInfo.CacheWarmingInfo{Settings.getCacheWarmingMode(settings),status,now}
def sessionInfoShown(transcript: Transcript.Handle,+live: Session.AgentSession,stats: Result<&2,&2,Tree.Error,Stats.Stats>) -> IO(Unit):
  match stats:
    case Fail{_}: Transcript.showError(transcript,"Session history is invalid")
    case Done{value}:
      do IO<Unit>:
        stored : Session.Session() <- Session.sessionOf(live)
        warming : SessionInfo.CacheWarmingInfo <- cacheWarmingInfo(live)
        Transcript.sessionInfo(transcript,sessionInfoOf(value,Session.stateOf(stored),Session.modelRuntime(live),warming))
def sessionInfoObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,_,redraw,_,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,_,_,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        stats : Result<&2,&2,Tree.Error,Stats.Stats> <- Session.getSessionStats(live)
        sessionInfoShown(transcript,live,stats)
        Interactive.requestRender(redraw)
def copyObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,_,redraw,cwd,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,_,_,_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        text : Maybe<&2,String> <- Session.getLastAssistantText(live)
        copyText(transcript,cwd,text)
        Interactive.requestRender(redraw)
# The package's CHANGELOG.md, beside the built-in themes' package
# (upstream getChangelogPath: <package>/CHANGELOG.md).
def changelogPath(builtinDir: String) -> String: Path.join(builtinDir,"../../../../CHANGELOG.md")
def linkedEntries(entries: List<&2,Changelog.ChangelogEntry>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case Changelog.ChangelogEntry{major,minor,patch,content} <> rest:
      Changelog.normalizeChangelogLinks(content,Changelog.entryVersion(Changelog.ChangelogEntry{major,minor,patch,""})) <> linkedEntries(rest)
# upstream handleChangelogCommand: every entry, oldest first.
def changelogText(entries: List<&2,Changelog.ChangelogEntry>) -> String:
  match entries:
    case Nil{}: "No changelog entries found."
    case entries: String.join(linkedEntries(List.reverse(&2,Changelog.ChangelogEntry,entries)),"\n\n")
def changelogObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,redraw,_,builtinDir,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,_,_,_}:
      do IO<Unit>:
        entries : List<&2,Changelog.ChangelogEntry> <- Changelog.parseChangelog(changelogPath(builtinDir))
        Transcript.changelog(transcript,MessageUI.FullChangelog{changelogText(entries)})
        Interactive.requestRender(redraw)
def hotkeyRow(key: String,description: String) -> String:
  "| `" ++ key ++ "` | " ++ description ++ " |"
def boundRow(bindings: Keybindings.KeybindingsManager,action: String,description: String) -> String:
  hotkeyRow(Hints.keyDisplayText(bindings,action),description)
def keyPair(+bindings: Keybindings.KeybindingsManager,left: String,right: String) -> String:
  Hints.keyDisplayText(bindings,left) ++ "` / `" ++ Hints.keyDisplayText(bindings,right)
def keyFour(+bindings: Keybindings.KeybindingsManager,a: String,b: String,c: String,d: String) -> String:
  keyPair(bindings,a,b) ++ "` / `" ++ keyPair(bindings,c,d)
def hotkeysMarkdown(+bindings: Keybindings.KeybindingsManager) -> String:
  String.join([
    "**Navigation**",
    "| Key | Action |", "|-----|--------|",
    hotkeyRow(keyFour(bindings,"tui.editor.cursorUp","tui.editor.cursorDown","tui.editor.cursorLeft","tui.editor.cursorRight"),"Move cursor / browse history"),
    hotkeyRow(keyPair(bindings,"tui.editor.cursorWordLeft","tui.editor.cursorWordRight"),"Move by word"),
    boundRow(bindings,"tui.editor.cursorLineStart","Start of line"),
    boundRow(bindings,"tui.editor.cursorLineEnd","End of line"),
    boundRow(bindings,"tui.editor.jumpForward","Jump forward to character"),
    boundRow(bindings,"tui.editor.jumpBackward","Jump backward to character"),
    hotkeyRow(keyPair(bindings,"tui.editor.pageUp","tui.editor.pageDown"),"Scroll by page"),
    "", "**Editing**", "| Key | Action |", "|-----|--------|",
    boundRow(bindings,"tui.input.submit","Send message"),
    boundRow(bindings,"tui.input.newLine","New line"),
    boundRow(bindings,"tui.editor.deleteWordBackward","Delete word backwards"),
    boundRow(bindings,"tui.editor.deleteWordForward","Delete word forwards"),
    boundRow(bindings,"tui.editor.deleteToLineStart","Delete to start of line"),
    boundRow(bindings,"tui.editor.deleteToLineEnd","Delete to end of line"),
    boundRow(bindings,"tui.editor.yank","Paste the most-recently-deleted text"),
    boundRow(bindings,"tui.editor.yankPop","Cycle through the deleted text after pasting"),
    boundRow(bindings,"tui.editor.undo","Undo"),
    "", "**Other**", "| Key | Action |", "|-----|--------|",
    boundRow(bindings,"tui.input.tab","Path completion / accept autocomplete"),
    boundRow(bindings,"app.interrupt","Cancel autocomplete / abort streaming"),
    boundRow(bindings,"app.clear","Clear editor (first) / exit (second)"),
    boundRow(bindings,"app.exit","Exit (when editor is empty)"),
    boundRow(bindings,"app.suspend","Suspend to background"),
    boundRow(bindings,"app.thinking.cycle","Cycle thinking level"),
    hotkeyRow(keyPair(bindings,"app.model.cycleForward","app.model.cycleBackward"),"Cycle models"),
    boundRow(bindings,"app.model.select","Open model selector"),
    boundRow(bindings,"app.tools.expand","Toggle tool output expansion"),
    boundRow(bindings,"app.thinking.toggle","Toggle thinking block visibility"),
    boundRow(bindings,"app.editor.external","Edit message in external editor"),
    boundRow(bindings,"app.message.copy","Copy selection or last assistant message"),
    boundRow(bindings,"app.message.followUp","Queue follow-up message"),
    boundRow(bindings,"app.message.dequeue","Restore queued messages"),
    boundRow(bindings,"app.clipboard.pasteImage","Paste image or text from clipboard"),
    hotkeyRow("/","Slash commands"),
    hotkeyRow("!","Run bash command"),
    hotkeyRow("!!","Run bash command (excluded from context)")
  ],"\n")
def hotkeysObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,redraw,_,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,bindings,_,_}:
      do IO<Unit>:
        Transcript.hotkeys(transcript,hotkeysMarkdown(bindings))
        Interactive.requestRender(redraw)
def matchSettings(host: Maybe<&2,SettingsPicker.Host>) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: SettingsPicker.open(ready)
def settingsObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,_,_,_,_,_,_,_,settings,_,_,_,_,_}:
      do IO<Unit>:
        host : Maybe<&2,SettingsPicker.Host> <- Ref.read(Maybe<&2,SettingsPicker.Host>,settings)
        matchSettings(host)
def openTrustHost(host: Maybe<&2,TrustPicker.Host>,cwd: String,options: List<&2,Trust.ProjectTrustOption>,saved: Maybe<&2,Trust.ProjectTrustStoreEntry>,trusted: Bool) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: TrustPicker.open(ready,TrustPicker.new(cwd,options,saved,trusted))
def trustOpened(target: Ref.Ref<Maybe<&2,TrustPicker.Host>>,cwd: String,options: List<&2,Trust.ProjectTrustOption>,trusted: Bool,transcript: Transcript.Handle,result: Result<&2,&2,Trust.Error,Maybe<&2,Trust.ProjectTrustStoreEntry>>) -> IO(Unit):
  match result:
    case Fail{Trust.Error{message}}: Transcript.showError(transcript,message)
    case Done{saved}:
      do IO<Unit>:
        host : Maybe<&2,TrustPicker.Host> <- Ref.read(Maybe<&2,TrustPicker.Host>,target)
        openTrustHost(host,cwd,options,saved,trusted)
def trustObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,_,redraw,+cwd,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,TrustContext{host,store,_},_,_,_,_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        options : List<&2,Trust.ProjectTrustOption> <- Trust.getProjectTrustOptions(cwd,False{})
        saved : Result<&2,&2,Trust.Error,Maybe<&2,Trust.ProjectTrustStoreEntry>> <- Trust.getEntry(store,cwd)
        trustOpened(host,cwd,options,Settings.isProjectTrusted(settings),transcript,saved)
        Interactive.requestRender(redraw)
type TrustChoiceInput is Data:
  TrustChoiceInput{store: Trust.ProjectTrustStore,transcript: Transcript.Handle}
def trustSaved(trusted: Bool,transcript: Transcript.Handle,result: Result<&2,&2,Trust.Error,Unit>) -> IO(Unit):
  match result:
    case Fail{Trust.Error{message}}: Transcript.showError(transcript,message)
    case Done{_}: Transcript.status(transcript,"Saved trust decision: " ++ Bool.pick(String,trusted,"trusted","untrusted") ++ ". Restart pi for this to take effect.")
def trustChosen(input: TrustChoiceInput,option: Trust.ProjectTrustOption) -> IO(Unit):
  match input option:
    case TrustChoiceInput{store,transcript} Trust.ProjectTrustOption{_,trusted,updates,_}:
      do IO<Unit>:
        result : Result<&2,&2,Trust.Error,Unit> <- Trust.setMany(store,updates)
        trustSaved(trusted,transcript,result)
# upstream handleReloadCommand (no extensions or keybindings file reload yet):
# the session reloads settings and prompt resources, the header lists them.
def reloadListed(header: Maybe<&2,Header.Handle>,+session: Session.AgentSession) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        files : List<&2,Prompt.ContextFile> <- Session.getAgentsFiles(session)
        skills : List<&2,Skills.Skill> <- Session.getSkills(session)
        Header.setResources(handle,files,skills)
def implicitTrustFailed(transcript: Transcript.Handle,error: Trust.Error) -> IO(Bool):
  match error:
    case Trust.Error{message}:
      do IO<Bool>:
        Transcript.showWarning(transcript,"Could not save project trust after reload: " ++ message)
        return False{}
def implicitTrustWritten(transcript: Transcript.Handle,result: Result<&2,&2,Trust.Error,Unit>) -> IO(Bool):
  match result:
    case Done{_}: IO.pure(Bool,True{})
    case Fail{error}: implicitTrustFailed(transcript,error)
def implicitTrustRead(store: Trust.ProjectTrustStore,+cwd: String,transcript: Transcript.Handle,result: Result<&2,&2,Trust.Error,Maybe<&2,Bool>>) -> IO(Bool):
  match result:
    case Fail{error}: implicitTrustFailed(transcript,error)
    case Done{Some{_}}: IO.pure(Bool,False{})
    case Done{None{}}:
      do IO<Bool>:
        written : Result<&2,&2,Trust.Error,Unit> <- Trust.set(store,cwd,Some{True{}})
        implicitTrustWritten(transcript,written)
def saveImplicitTrust(+store: Trust.ProjectTrustStore,+cwd: String,transcript: Transcript.Handle) -> IO(Bool):
  do IO<Bool>:
    saved : Result<&2,&2,Trust.Error,Maybe<&2,Bool>> <- Trust.get(store,cwd)
    implicitTrustRead(store,cwd,transcript,saved)
def maybeSaveImplicitTrust(trust: TrustContext,+cwd: String,session: Session.AgentSession,transcript: Transcript.Handle) -> IO(Bool):
  match trust:
    case TrustContext{_,_,False{}}: IO.pure(Bool,False{})
    case TrustContext{_,store,True{}}:
      do IO<Bool>:
        settings : Settings.SettingsManager <- Session.getSettings(session)
        home : Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
        resources : Bool <- Trust.hasTrustRequiringProjectResources(cwd,environmentValue(home))
        Bool.pick(Unit -> IO(Bool),Settings.isProjectTrusted(settings) && resources,
          _ => saveImplicitTrust(store,cwd,transcript),_ => IO.pure(Bool,False{}))(Unit{})
def reloadResult(+transcript: Transcript.Handle,header: Maybe<&2,Header.Handle>,+session: Session.AgentSession,trust: TrustContext,cwd: String,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: Transcript.showError(transcript,"Reload failed: " ++ message)
    case Done{_}:
      do IO<Unit>:
        messages : List<&2,Session.Message()> <- Session.messages(session)
        Transcript.clear(transcript)
        Transcript.seedSession(transcript,messages)
        reloadListed(header,session)
        saved : Bool <- maybeSaveImplicitTrust(trust,cwd,session,transcript)
        Transcript.status(transcript,"Reloaded keybindings, extensions, skills, prompts, themes, and context files" ++ Bool.pick(String,saved,"; saved project trust",""))
def reloaded(result: Result<&2,&2,String,Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}
def reloadIdle(transcript: Transcript.Handle,header: Maybe<&2,Header.Handle>,+session: Session.AgentSession,trust: TrustContext,cwd: String,streaming: Bool,compacting: Bool) -> IO(Bool):
  match streaming compacting:
    case True{} _:
      do IO<Bool>:
        Transcript.showWarning(transcript,"Wait for the current response to finish before reloading.")
        return False{}
    case False{} True{}:
      do IO<Bool>:
        Transcript.showWarning(transcript,"Wait for compaction to finish before reloading.")
        return False{}
    case False{} False{}:
      do IO<Bool>:
        +result : Result<&2,&2,String,Unit> <- Session.reload(session)
        reloadResult(transcript,header,session,trust,cwd,result)
        return reloaded(result)
def reloadObserved(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,+session,_,_,redraw,cwd,_,_,_,_,BashInput{_,transcript,editor,_,_,_},_,trust,header,_,+autocomplete,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        streaming : Bool <- Session.isStreaming(live)
        compacting : Bool <- Session.isCompacting(live)
        done : Bool <- reloadIdle(transcript,header,live,trust,cwd,streaming,compacting)
        Bool.pick(Unit -> IO(Unit),done,_ => setupAutocomplete(autocomplete,editor,session),_ => IO.pure(Unit,Unit{}))(Unit{})
        Interactive.requestRender(redraw)
def sessionStatus(input: CommandObservation,message: String) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,_,_,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,_,_,_}: Transcript.status(transcript,message)
def newSessionStatus(input: CommandObservation) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,_,_,_,_,_,_,BashInput{_,transcript,_,_,_,_},_,_,_,_,_,_}: Transcript.newSession(transcript)
def commandObserved(input: CommandObservation,action: Commands.Action) -> IO(Unit):
  match action:
    case Commands.CopyLastAssistant{}: copyObserved(input)
    case Commands.ShowSessionInfo{}: sessionInfoObserved(input)
    case Commands.ShowHotkeys{}: hotkeysObserved(input)
    case Commands.NewSessionStarted{}: newSessionStatus(input)
    case Commands.ClonedSession{}: sessionStatus(input,"Cloned to new session")
    case Commands.OpenSettings{}: settingsObserved(input)
    case Commands.OpenTrust{}: trustObserved(input)
    case Commands.ShowChangelog{}: changelogObserved(input)
    case Commands.ReloadResources{}: reloadObserved(input)
    case Commands.ExportSession{path}: exportObserved(input,path)
    case Commands.ImportSession{path}: importObserved(input,path)
    case Commands.ResumeSession{}: resumeObserved(input)
    case Commands.OpenTree{}: treeObserved(input,Selector.TreeMode{})
    case Commands.OpenFork{}: treeObserved(input,Selector.ForkMode{})
    case Commands.RunBash{command,excluded}: bashObserved(input,command,excluded)
    case other: ordinaryCommandObserved(input,other)
type WorkerFailure is Data:
  WorkerFailure{failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def promptFailed(input: WorkerFailure,value: Controller.PromptFailure) -> IO(Unit):
  match input value:
    case WorkerFailure{failure,redraw} Controller.PromptFailure{message}:
      do IO<Unit>:
        Interactive.report(failure,Interactive.PromptFailure{message})

type FooterPaint is Data: FooterPaint{state: Ref.Ref<Footer.State>,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>}
type FooterOwner is Data: FooterOwner{state: Ref.Ref<Footer.State>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
def contextPercent(value: Maybe<&2,Stats.ContextUsage>) -> Maybe<&2,F64>:
  match value:
    case None{}: None{}
    case Some{Stats.ContextUsage{_,_,percent}}: percent
def contextWindow(value: Maybe<&2,Stats.ContextUsage>) -> Maybe<&2,Nat>:
  match value:
    case None{}: None{}
    case Some{Stats.ContextUsage{_,window,_}}: Some{count(window)}
def withStats(state: Footer.State,stats: Stats.Stats) -> Footer.State:
  match state stats:
    case Footer.State{cwd,home,branch,name,chosen,thinkingLevel,_,latest,_,_,providers,subscription,auto,experimental,statuses} Stats.Stats{_,_,Stats.Totals{_,_,_,_,_,input,output,read,write,cost},+context}:
      Footer.State{cwd,home,branch,name,chosen,thinkingLevel,Footer.Usage{count(input),count(output),count(read),count(write),cost},latest,contextPercent(context),contextWindow(context),providers,subscription,auto,experimental,statuses}
def statsState(state: Footer.State,result: Result<&2,&2,Tree.Error,Stats.Stats>) -> Footer.State:
  match result:
    case Done{stats}: withStats(state,stats)
    case Fail{_}: state
# upstream FooterComponent reads the model and thinking level from the live
# agent state.
def footerLinesCopied(paint: FooterPaint,+width: Nat) -> IO(List<&2,String>):
  match paint:
    case FooterPaint{state,+theme,session}:
      do IO<List<&2,String>>:
        +selected : Theme.Theme <- Ref.read(Theme.Theme,theme)
        current : Footer.State <- Ref.read(Footer.State,state)
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        stats : Result<&2,&2,Tree.Error,Stats.Stats> <- Session.getSessionStats(live)
        agentState : Session.AgentState() <- Session.state(live)
        autoCompact : Bool <- Session.getAutoCompactionEnabled(live)
        Footer.render(Footer.setAutoCompactEnabled(statsState(withChosen(current,agentState),stats),autoCompact),selected,width)
def footerLines(paint: FooterPaint,width: Nat) -> IO(List<&2,String>):
  footerLinesCopied(paint,width)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def footer(initial: Footer.State,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>) -> IO(FooterOwner):
  do IO<FooterOwner>:
    +state : Ref.Ref<Footer.State> <- Ref.new(Footer.State,initial)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~FooterPaint,~Nat,~List<&2,String>,~footerLines,FooterPaint{state,theme,session})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return FooterOwner{state,Component.Component{Component.ComponentId{3n},render,None{},None{},invalidate,None{},False{}},render,invalidate}
def footerState(owner: FooterOwner) -> Ref.Ref<Footer.State>:
  match owner: case FooterOwner{state,_,_,_}: state
def footerComponent(owner: FooterOwner) -> Component.Component:
  match owner: case FooterOwner{_,component,_,_}: component
def disposeFooter(owner: FooterOwner) -> IO(Unit):
  match owner:
    case FooterOwner{state,_,render,invalidate}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        old : Footer.State <- Ref.dispose(Footer.State,state)
        return Unit{}

# upstream getSelectListTheme: accent selection, muted descriptions, scroll
# info and no-match text.
def editorTheme(theme: Ref.Ref<Theme.Theme>) -> IO(Callback.Callback<String,String>):
  MarkdownTheme.color(theme,"accent")
# upstream updateEditorBorderColor, evaluated when the border is painted: bash
# mode (text starting with "!") uses bashMode, otherwise the session's
# thinking level colour.
type BorderStyle is Data: BorderStyle{theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,bash: Ref.Ref<Bool>}
def thinkingBorderKey(level: Ai.ModelThinkingLevel) -> String:
  match level:
    case Ai.Off{}: "thinkingOff"
    case Ai.Thinking{Ai.Minimal{}}: "thinkingMinimal"
    case Ai.Thinking{Ai.Low{}}: "thinkingLow"
    case Ai.Thinking{Ai.Medium{}}: "thinkingMedium"
    case Ai.Thinking{Ai.High{}}: "thinkingHigh"
    case Ai.Thinking{Ai.XHigh{}}: "thinkingXhigh"
    case Ai.Thinking{Ai.Max{}}: "thinkingMax"
def borderPainted(style: BorderStyle,+text: String) -> IO(String):
  match style:
    case BorderStyle{theme,session,bash}:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        agentState : Session.AgentState() <- Session.state(live)
        inBash : Bool <- Ref.read(Bool,bash)
        return Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,Bool.pick(String,inBash,"bashMode",thinkingBorderKey(Session.stateThinking(agentState))),text),text)
def paintBorder(style: BorderStyle,text: String) -> IO(String): borderPainted(style,text)
def bashModeChanged(bash: Ref.Ref<Bool>,text: String) -> IO(Unit):
  Ref.write(Bool,bash,String.starts_with(Text.trimStart(text),"!"))
def clear(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,_: Unit) -> IO(Unit):
  Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,None{})

type ThemeLive is Data:
  ThemeLive{selection: Ref.Ref<Maybe<&2,ThemeController.Handle>>,theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,requestRender: Callback.Callback<Unit,Unit>}
type ThemeOwned is Type:
  ThemeOwned{controller: ThemeController.Owner,render: Callback.Callback<Unit,Unit>}
type ThemeStopping is Data:
  ThemeStopping{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>,view: View.Handle,screen: Process.ScreenState,session: Ref.Ref<Session.AgentSession>}
type Interaction is Data:
  Interaction{editor: Ref.Ref<Maybe<&2,Live.Handle>>,lastClear: Ref.Ref<Maybe<&2,F64>>,lastEscape: Ref.Ref<Maybe<&2,F64>>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,modelSelector: Ref.Ref<Maybe<&2,ModelPicker.Host>>,thinkingSelector: Ref.Ref<Maybe<&2,ThinkingPicker.Host>>,scopedSelector: Ref.Ref<Maybe<&2,ScopePicker.Host>>,settings: Ref.Ref<Maybe<&2,SettingsPicker.Host>>,trust: Ref.Ref<Maybe<&2,TrustPicker.Host>>,header: Maybe<&2,Header.Handle>,bashActivity: Ref.Ref<BashActivity>,working: Working,autocomplete: AutocompleteSlot}
type ThemeStartup is Data:
  ThemeStartup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Interactive.StatusSink,stopped: Deferred.Deferred<Unit>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>,error: Ref.Ref<Maybe<&2,Theme.LoadError>>,theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,session: Ref.Ref<Session.AgentSession>,setting: Maybe<&2,String>,builtinDir: String,customDir: String,managed: Maybe<&2,Manager.ToolsManager>,interaction: Interaction,highlighter: SyntaxHighlight.Highlighter}
type LoginRequest is Data: LoginRequest{runtime: Models.ModelRuntime,provider: String,kind: Auth.CredentialType,interaction: Auth.AuthInteraction}
type Binding is Data:
  Binding{current: Ref.Ref<Session.AgentSession>,replacement: Controller.Replacement,onRebind: Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>,login: Callback.Callback<LoginRequest,AuthLogin.Outcome()>,refreshModels: Callback.Callback<Unit,List<&2,Models.Model()>>,importer: Callback.Callback<ImportRequest,SessionHost.ImportOutcome>,sessions: Callback.Callback<Unit,SessionChoices>,resume: Callback.Callback<ResumeRequest,SessionHost.ResumeOutcome>,managed: Maybe<&2,Manager.ToolsManager>,autoTrustOnReload: Bool,tuiMode: Maybe<&2,Settings.TuiMode>}
type ProviderSort is Data: PendingSort{directory: String} ReadySort{collator: Collation.Collator}
type LoginState is Data:
  LoginState{host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,abort: Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>,backend: Maybe<&2,Callback.Callback<LoginRequest,AuthLogin.Outcome()>>,refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>,sort: Ref.Ref<ProviderSort>}
type ApiPromptState is Data: ApiPromptState{login: LoginState,providerName: String,signal: Abort.AbortSignal<Unit>}
def closeLoginDialog(target: Maybe<&2,LoginDialog.Host>) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{dialog}: LoginDialog.close(dialog)
def refreshLoginModels(refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>) -> IO(List<&2,Models.Model()>):
  match refresh:
    case None{}: Ref.read(List<&2,Models.Model()>,models)
    case Some{callback}:
      do IO<List<&2,Models.Model()>>:
        +available : List<&2,Models.Model()> <- Callback.call(Unit,List<&2,Models.Model()>,callback,Unit{})
        Ref.write(List<&2,Models.Model()>,models,available)
        return available
def providerName(provider: String) -> String:
  match provider:
    case "anthropic": "Anthropic"
    case "openai": "OpenAI"
    case "openai-codex": "OpenAI Codex"
    case other: other
def loginLabel(+provider: String,apiKey: Bool) -> String:
  Bool.pick(String,apiKey,"Saved API key for " ++ providerName(provider),"Logged in to " ++ providerName(provider))
def defaultId(defaults: List<&2,Models.DefaultModel>,+provider: String) -> Maybe<&2,String>:
  match defaults:
    case Nil{}: None{}
    case Models.DefaultModel{owner,id} <> rest: Bool.pick(Maybe<&2,String>,String.eq(owner,provider),Some{id},defaultId(rest,provider))
def selectedDefault(models: List<&2,Models.Model()>,provider: String,expected: Maybe<&2,String>) -> Maybe<&2,Models.Model()>:
  match expected:
    case None{}: None{}
    case Some{id}: Models.findModel(models,provider,id)
def selectedNotice(action: String,id: String,result: Result<&2,&2,String,Unit>) -> String:
  match result:
    case Done{_}: action ++ ". Selected " ++ id
    case Fail{reason}: action ++ ", but selecting its default model failed: " ++ reason ++ ". Use /model to select a model."
def chooseAfterLogin(action: String,session: Session.AgentSession,selected: Maybe<&2,Models.Model()>) -> IO(String):
  match selected:
    case None{}: IO.pure(String,action ++ ", but its default model is unavailable. Use /model to select a model.")
    case Some{+chosen}:
      do IO<String>:
        id : String = Models.modelId(chosen)
        result : Result<&2,&2,String,Unit> <- Session.setModel(session,chosen,Session.ModelMutationOptions{True{}})
        return selectedNotice(action,id,result)
def loginStatus(+provider: String,+apiKey: Bool,session: Ref.Ref<Session.AgentSession>,+available: List<&2,Models.Model()>) -> IO(String):
  do IO<String>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    current : Session.AgentState() <- Session.state(live)
    Bool.pick(Unit -> IO(String),Maybe.is_some(&2,Ai.Model<Ai.JsonValue>,Session.stateModel(current)),_ => IO.pure(String,loginLabel(provider,apiKey)),_ => chooseAfterLogin(loginLabel(provider,apiKey),live,selectedDefault(available,provider,defaultId(Models.defaultModelPerProvider(),provider))))(Unit{})
def credentialsNotice(message: String,path: Result<&2,&2,Filesystem.Error,String>) -> String:
  match path:
    case Fail{_}: message
    case Done{value}: message ++ ". Credentials saved to " ++ value
def loginOutcomeResult(provider: String,apiKey: Bool,result: AuthLogin.Outcome(),refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        available : List<&2,Models.Model()> <- refreshLoginModels(refresh,models)
        message : String <- loginStatus(provider,apiKey,session,available)
        path : Result<&2,&2,Filesystem.Error,String> <- Config.getAuthPath()
        Interactive.report(failure,Interactive.CommandNotice{credentialsNotice(message,path)})
    case Fail{message}: Interactive.report(failure,Interactive.CommandFailure{message})
def loginOutcome(provider: String,apiKey: Bool,result: AuthLogin.Outcome(),cancelled: Bool,refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match cancelled:
    case True{}: Interactive.report(failure,Interactive.CommandNotice{"Login cancelled"})
    case False{}: loginOutcomeResult(provider,apiKey,result,refresh,models,failure,session)
def loginFinished(state: LoginState,provider: String,apiKey: Bool,result: AuthLogin.Outcome(),cancelled: Bool) -> IO(Unit):
  match state:
    case LoginState{host,_,_,refresh,models,failure,redraw,session,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        closeLoginDialog(target)
        loginOutcome(provider,apiKey,result,cancelled,refresh,models,failure,session)
        Interactive.requestRender(redraw)
def loginAbort(state: LoginState) -> Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>:
  match state: case LoginState{_,abort,_,_,_,_,_,_,_}: abort
def promptRestore(prompt: Auth.AuthPrompt,previous: LoginDialog.State) -> Maybe<&2,LoginDialog.State>:
  match prompt:
    case Auth.SelectPrompt{_,_,_}: Some{previous}
    case _: None{}
def apiPromptTarget(target: Maybe<&2,LoginDialog.Host>,name: String,+prompt: Auth.AuthPrompt,signal: Abort.AbortSignal<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Result<&2,&2,String,String>):
  match target:
    case None{}: IO.pure(Result<&2,&2,String,String>,Fail{"Login dialog closed"})
    case Some{+dialog}:
      do IO<Result<&2,&2,String,String>>:
        previous : LoginDialog.State <- LoginDialog.authState(dialog)
        +answer : Deferred.Deferred<String> <- Deferred.new(String)
        LoginDialog.showAuthPrompt(dialog,"Login to " ++ name,prompt,answer)
        Interactive.requestRender(redraw)
        result : Result<&2,&2,String,String> <- LoginDialog.awaitAuthAnswer(answer,signal,Auth.promptSignal(prompt))
        LoginDialog.finishAuthPrompt(dialog,promptRestore(prompt,previous))
        Deferred.dispose(String,answer)
        Interactive.requestRender(redraw)
        return result
def apiPrompt(state: ApiPromptState,prompt: Auth.AuthPrompt) -> IO(Result<&2,&2,String,String>):
  match state:
    case ApiPromptState{LoginState{host,_,_,_,_,_,redraw,_,_},name,signal}:
      do IO<Result<&2,&2,String,String>>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        apiPromptTarget(target,name,prompt,signal,redraw)
def apiNotifyTarget(target: Maybe<&2,LoginDialog.Host>,name: String,event: Auth.AuthEvent,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{dialog}:
      do IO<Unit>:
        LoginDialog.notify(dialog,"Login to " ++ name,event)
        Interactive.requestRender(redraw)
def apiNotify(state: ApiPromptState,event: Auth.AuthEvent) -> IO(Unit):
  match state:
    case ApiPromptState{LoginState{host,_,_,_,_,_,redraw,_,_},name,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        apiNotifyTarget(target,name,event,redraw)
def providerKeyAuth(provider: Maybe<&2,AiModels.Provider>) -> Maybe<&2,Auth.ApiKeyAuth>:
  match provider:
    case None{}: None{}
    case Some{AiModels.Provider{_,_,_,Auth.ProviderAuth{key,_},_,_,_}}: key
def apiKeyAuth(state: LoginState,provider: String) -> IO(Maybe<&2,Auth.ApiKeyAuth>):
  match state:
    case LoginState{_,_,_,_,_,_,_,session,_}:
      do IO<Maybe<&2,Auth.ApiKeyAuth>>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        found : Maybe<&2,AiModels.Provider> <- Models.getProvider(Session.modelRuntime(live),provider)
        return providerKeyAuth(found)
def loginProviderName(found: Maybe<&2,AiModels.Provider>,fallback: String) -> String:
  match found:
    case None{}: fallback
    case Some{AiModels.Provider{_,name,_,_,_,_,_}}: name
def apiKeyProviderName(state: LoginState,+provider: String) -> IO(String):
  match state:
    case LoginState{_,_,_,_,_,_,_,session,_}:
      do IO<String>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        found : Maybe<&2,AiModels.Provider> <- Models.getProvider(Session.modelRuntime(live),provider)
        return loginProviderName(found,providerName(provider))
def loginRequestOutcome(result: Auth.LoginOutcome()) -> AuthLogin.Outcome():
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}
def runProviderLogin(backend: Maybe<&2,Callback.Callback<LoginRequest,AuthLogin.Outcome()>>,request: LoginRequest) -> IO(AuthLogin.Outcome()):
  match backend request:
    case Some{callback} request: Callback.call(LoginRequest,AuthLogin.Outcome(),callback,request)
    case None{} LoginRequest{runtime,provider,kind,interaction}:
      do IO<AuthLogin.Outcome()>:
        result : Auth.LoginOutcome() <- Models.login(runtime,provider,kind,interaction)
        return loginRequestOutcome(result)
def isApiKey(kind: Auth.CredentialType) -> Bool:
  match kind:
    case Auth.ApiKeyType{}: True{}
    case Auth.OAuthType{}: False{}
def beginProviderDialog(target: Maybe<&2,LoginDialog.Host>,title: String) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{dialog}: LoginDialog.beginAuth(dialog,title)
def selectedProvider(+state: LoginState,+provider: String,+kind: Auth.CredentialType,+controller: Abort.AbortController<Unit>) -> IO(Unit):
  match state:
    case LoginState{host,_,backend,_,_,_,redraw,session,_}:
      do IO<Unit>:
        +name : String <- apiKeyProviderName(state,provider)
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        beginProviderDialog(target,"Login to " ++ name)
        Interactive.requestRender(redraw)
        +prompt : Callback.Callback<Auth.AuthPrompt,Result<&2,&2,String,String>> <- Callback.create(~ApiPromptState,~Auth.AuthPrompt,~Result<&2,&2,String,String>,~apiPrompt,ApiPromptState{state,name,Abort.signal(Unit,controller)})
        +notify : Callback.Callback<Auth.AuthEvent,Unit> <- Callback.create(~ApiPromptState,~Auth.AuthEvent,~Unit,~apiNotify,ApiPromptState{state,name,Abort.signal(Unit,controller)})
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : AuthLogin.Outcome() <- runProviderLogin(backend,LoginRequest{Session.modelRuntime(live),provider,kind,Auth.AuthInteraction{Some{Abort.signal(Unit,controller)},prompt,notify}})
        Callback.dispose(Auth.AuthEvent,Unit,notify)
        Callback.dispose(Auth.AuthPrompt,Result<&2,&2,String,String>,prompt)
        old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,loginAbort(state),None{})
        cancelled : Bool <- Abort.aborted(Unit,Abort.signal(Unit,controller))
        Abort.dispose(Unit,controller)
        loginFinished(state,provider,isApiKey(kind),result,cancelled)
def storedKind(infos: List<&2,Auth.CredentialInfo>,+id: String) -> Maybe<&2,Auth.CredentialType>:
  match infos:
    case Nil{}: None{}
    case Auth.CredentialInfo{providerId,kind} <> rest:
      Bool.pick(Maybe<&2,Auth.CredentialType>,String.eq(providerId,id),Some{kind},storedKind(rest,id))
def envNameTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}: ((U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,95)) && envNameTail(rest)
def envName(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,65) && U32.is_le(code,90) && envNameTail(rest)
def envSourceTail(parts: List<&2,String>) -> Bool:
  match parts:
    case Nil{}: True{}
    case SCon{Chr{32},text} <> rest: envName(text) && envSourceTail(rest)
    case _: False{}
def envSource(parts: List<&2,String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case text <> rest: envName(text) && envSourceTail(rest)
def authSourceStatus(source: Maybe<&2,String>) -> String:
  match source:
    case None{}: " ✓ configured"
    case Some{"stored credential"}: " ✓ configured"
    case Some{"OAuth"}: " ✓ configured"
    case Some{+value}: " ✓ " ++ Bool.pick(String,envSource(String.split(value,',')),"env: " ++ value,value)
def resolvedStatus(result: AuthResolve.Resolution()) -> String:
  match result:
    case Done{Some{Auth.AuthResult{_,_,source}}}: authSourceStatus(source)
    case _: " • unconfigured"
def optionMatches(kind: Auth.CredentialType,filter: Maybe<&2,Auth.CredentialType>) -> Bool:
  match filter:
    case None{}: True{}
    case Some{value}: String.eq(Auth.typeName(kind),Auth.typeName(value))
def oauthOption(id: String,name: String,auth: Maybe<&2,Auth.OAuthAuth>,filter: Maybe<&2,Auth.CredentialType>) -> List<&2,LoginDialog.ProviderOption>:
  match auth:
    case None{}: Nil{}
    case Some{Auth.OAuthAuth{method,_,label,_,_,_}}:
      Bool.pick(List<&2,LoginDialog.ProviderOption>,optionMatches(Auth.OAuthType{},filter),[LoginDialog.ProviderOption{id,name,Auth.OAuthType{},method,label,""}],Nil{})
def keyOption(id: String,name: String,auth: Maybe<&2,Auth.ApiKeyAuth>,filter: Maybe<&2,Auth.CredentialType>) -> List<&2,LoginDialog.ProviderOption>:
  match auth:
    case None{}: Nil{}
    case Some{Auth.ApiKeyAuth{method,_,_}}:
      Bool.pick(List<&2,LoginDialog.ProviderOption>,optionMatches(Auth.ApiKeyType{},filter),[LoginDialog.ProviderOption{id,name,Auth.ApiKeyType{},method,None{},""}],Nil{})
def providerOptions(+id: String,+name: String,auth: Auth.ProviderAuth,+filter: Maybe<&2,Auth.CredentialType>) -> List<&2,LoginDialog.ProviderOption>:
  match auth:
    case Auth.ProviderAuth{key,oauth}:
      List.append(&2,LoginDialog.ProviderOption,oauthOption(id,name,oauth,filter),keyOption(id,name,key,filter))
def loginOptions(providers: List<&2,AiModels.Provider>,+filter: Maybe<&2,Auth.CredentialType>) -> List<&2,LoginDialog.ProviderOption>:
  match providers:
    case Nil{}: Nil{}
    case AiModels.Provider{id,name,_,auth,_,_,_} <> rest:
      List.append(&2,LoginDialog.ProviderOption,providerOptions(id,name,auth,filter),loginOptions(rest,filter))
def availableLoginOptions(state: LoginState,filter: Maybe<&2,Auth.CredentialType>) -> IO(List<&2,LoginDialog.ProviderOption>):
  match state:
    case LoginState{_,_,_,_,_,_,_,session,_}:
      do IO<List<&2,LoginDialog.ProviderOption>>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        providers : List<&2,AiModels.Provider> <- Models.getProviders(Session.modelRuntime(live))
        return loginOptions(providers,filter)
def statusKind(selected: Auth.CredentialType,stored: Maybe<&2,Auth.CredentialType>) -> Maybe<&2,String>:
  match selected stored:
    case _ None{}: None{}
    case Auth.OAuthType{} Some{Auth.ApiKeyType{}}: Some{" • API key configured"}
    case Auth.ApiKeyType{} Some{Auth.OAuthType{}}: Some{" • subscription configured"}
    case _ _: Some{" ✓ configured"}
def optionSource(+runtime: Models.ModelRuntime,+id: String,kind: Auth.CredentialType,status: Maybe<&2,String>) -> IO(String):
  match status kind:
    case Some{value} _: IO.pure(String,value)
    case None{} Auth.OAuthType{}: IO.pure(String," • API key configured")
    case None{} Auth.ApiKeyType{}:
      do IO<String>:
        result : AuthResolve.Resolution() <- Models.getAuth(runtime,id,AuthResolve.noOverrides())
        return resolvedStatus(result)
def configuredOption(+runtime: Models.ModelRuntime,+id: String,+kind: Auth.CredentialType,stored: Maybe<&2,Auth.CredentialType>,configured: Bool) -> IO(String):
  match configured:
    case False{}: IO.pure(String," • unconfigured")
    case True{}: optionSource(runtime,id,kind,statusKind(kind,stored))
def optionStatus(+runtime: Models.ModelRuntime,+id: String,+kind: Auth.CredentialType,stored: Maybe<&2,Auth.CredentialType>) -> IO(String):
  do IO<String>:
    configured : Bool <- Models.hasConfiguredAuth(runtime,id)
    configuredOption(runtime,id,kind,stored,configured)
def withOptionStatuses(+runtime: Models.ModelRuntime,options: List<&2,LoginDialog.ProviderOption>,+infos: List<&2,Auth.CredentialInfo>) -> IO(List<&2,LoginDialog.ProviderOption>):
  match options:
    case Nil{}: IO.pure(List<&2,LoginDialog.ProviderOption>,Nil{})
    case LoginDialog.ProviderOption{+id,name,+kind,method,label,_} <> rest:
      do IO<List<&2,LoginDialog.ProviderOption>>:
        status : String <- optionStatus(runtime,id,kind,storedKind(infos,id))
        others : List<&2,LoginDialog.ProviderOption> <- withOptionStatuses(runtime,rest,infos)
        return LoginDialog.ProviderOption{id,name,kind,method,label,status} <> others
def cancelChosen(+state: LoginState,controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,loginAbort(state),None{})
    Abort.dispose(Unit,controller)
    loginFinished(state,"",False{},Done{Unit{}},True{})
def ambientFinished(state: LoginState,controller: Abort.AbortController<Unit>) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,abort,None{})
        Abort.dispose(Unit,controller)
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        closeLoginDialog(target)
        Interactive.requestRender(redraw)
def ambientDialog(+state: LoginState,provider: String,method: String,controller: Abort.AbortController<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,target: Maybe<&2,LoginDialog.Host>) -> IO(Unit):
  match target:
    case None{}: ambientFinished(state,controller)
    case Some{dialog}:
      do IO<Unit>:
        +name : String <- apiKeyProviderName(state,provider)
        +closed : Deferred.Deferred<String> <- LoginDialog.openInfo(dialog,name ++ " setup",method ++ " is configured outside Pi.")
        Interactive.requestRender(redraw)
        answer : String <- Deferred.result(String,closed)
        Deferred.dispose(String,closed)
        ambientFinished(state,controller)
def selectedAmbient(+state: LoginState,provider: String,method: String,controller: Abort.AbortController<Unit>) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        ambientDialog(state,provider,method,controller,redraw,target)
def selectedKeyMethod(state: LoginState,provider: String,controller: Abort.AbortController<Unit>,method: Maybe<&2,Auth.ApiKeyAuth>) -> IO(Unit):
  match method:
    case Some{Auth.ApiKeyAuth{_,Some{_},_}}: selectedProvider(state,provider,Auth.ApiKeyType{},controller)
    case Some{Auth.ApiKeyAuth{name,None{},_}}: selectedAmbient(state,provider,name,controller)
    case None{}: cancelChosen(state,controller)
def apiSelected(+state: LoginState,+provider: String,controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    method : Maybe<&2,Auth.ApiKeyAuth> <- apiKeyAuth(state,provider)
    selectedKeyMethod(state,provider,controller,method)
def redrawLogin(state: LoginState) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,_,redraw,_,_}: Interactive.requestRender(redraw)
type KeyedProviderOption is Data:
  KeyedProviderOption{key: Collation.Key,value: LoginDialog.ProviderOption}
def optionBefore(left: KeyedProviderOption,right: KeyedProviderOption) -> Bool:
  match left right:
    case KeyedProviderOption{a,_} KeyedProviderOption{b,_}: Bool.not(Cmp.is_gt(Collation.compareKeys(a,b)))
def optionKey(+collator: Collation.Collator,+option: LoginDialog.ProviderOption) -> KeyedProviderOption:
  match option:
    case LoginDialog.ProviderOption{_,name,_,_,_,_}: KeyedProviderOption{Collation.key(collator,name),option}
def optionKeys(+collator: Collation.Collator,options: List<&2,LoginDialog.ProviderOption>) -> List<&2,KeyedProviderOption>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: optionKey(collator,option) <> optionKeys(collator,rest)
def providerOptionValues(options: List<&2,KeyedProviderOption>) -> List<&2,LoginDialog.ProviderOption>:
  match options:
    case Nil{}: Nil{}
    case KeyedProviderOption{_,value} <> rest: value <> providerOptionValues(rest)
def sortedOptions(collator: Collation.Collator,options: List<&2,LoginDialog.ProviderOption>) -> List<&2,LoginDialog.ProviderOption>:
  providerOptionValues(Sort.sort(~KeyedProviderOption,~optionBefore,optionKeys(collator,options)))
def collatorLoaded(sort: Ref.Ref<ProviderSort>,options: List<&2,LoginDialog.ProviderOption>,loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>):
  match loaded:
    case Fail{_}: IO.pure(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>,Fail{"Could not load provider collation data"})
    case Done{+collator}:
      do IO<Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>>:
        Ref.write(ProviderSort,sort,ReadySort{collator})
        return Done{sortedOptions(collator,options)}
def optionsSorted(+sort: Ref.Ref<ProviderSort>,options: List<&2,LoginDialog.ProviderOption>,current: ProviderSort) -> IO(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>):
  match current:
    case ReadySort{collator}: IO.pure(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>,Done{sortedOptions(collator,options)})
    case PendingSort{directory}:
      do IO<Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>>:
        loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(directory)
        collatorLoaded(sort,options,loaded)
def listedOptions(+runtime: Models.ModelRuntime,+sort: Ref.Ref<ProviderSort>,options: List<&2,LoginDialog.ProviderOption>,listed: Auth.StoreResult(List<&2,Auth.CredentialInfo>)) -> IO(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>):
  match listed:
    case Fail{message}: IO.pure(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>,Fail{message})
    case Done{infos}:
      do IO<Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>>:
        ready : List<&2,LoginDialog.ProviderOption> <- withOptionStatuses(runtime,options,infos)
        current : ProviderSort <- Ref.read(ProviderSort,sort)
        optionsSorted(sort,ready,current)
def prepareLoginOptions(state: LoginState,options: List<&2,LoginDialog.ProviderOption>) -> IO(Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>):
  match state:
    case LoginState{_,_,_,_,_,_,_,session,sort}:
      do IO<Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        +runtime : Models.ModelRuntime = Session.modelRuntime(live)
        listed : Auth.StoreResult(List<&2,Auth.CredentialInfo>) <- Auth.list(Models.credentialsOf(runtime),None{})
        listedOptions(runtime,sort,options,listed)
def providerChoices(options: List<&2,LoginDialog.ProviderOption>) -> List<&2,LoginDialog.Choice>:
  match options:
    case Nil{}: Nil{}
    case LoginDialog.ProviderOption{+id,+name,+kind,method,_,status} <> rest:
      LoginDialog.Choice{LoginDialog.AuthChoice{LoginDialog.ProviderSelection{id,kind}},name,status,name ++ " " ++ id ++ " " ++ Auth.typeName(kind) ++ " " ++ method} <> providerChoices(rest)
def methodChoices(options: List<&2,LoginDialog.ProviderOption>) -> List<&2,LoginDialog.Choice>:
  match options:
    case Nil{}: Nil{}
    case LoginDialog.ProviderOption{id,_,Auth.OAuthType{},_,label,_} <> rest:
      +text = Maybe.default(&2,String,label,"Sign in with an account")
      LoginDialog.Choice{LoginDialog.AuthChoice{LoginDialog.ProviderSelection{id,Auth.OAuthType{}}},text,"",text} <> methodChoices(rest)
    case LoginDialog.ProviderOption{id,_,Auth.ApiKeyType{},_,_,_} <> rest:
      LoginDialog.Choice{LoginDialog.AuthChoice{LoginDialog.ProviderSelection{id,Auth.ApiKeyType{}}},"Sign in with an API key","",""} <> methodChoices(rest)
def selectionName(options: List<&2,LoginDialog.ProviderOption>) -> String:
  match options:
    case LoginDialog.ProviderOption{_,name,_,_,_,_} <> _: name
    case Nil{}: ""
def matchesProvider(option: LoginDialog.ProviderOption,+requested: String) -> Bool:
  match option:
    case LoginDialog.ProviderOption{id,name,_,_,_,_}: String.eq(String.to_lower(id),requested) || String.eq(String.to_lower(name),requested)
def matchingOptions(options: List<&2,LoginDialog.ProviderOption>,+requested: String) -> List<&2,LoginDialog.ProviderOption>:
  match options:
    case Nil{}: Nil{}
    case +option <> rest:
      +others = matchingOptions(rest,requested)
      Bool.pick(List<&2,LoginDialog.ProviderOption>,matchesProvider(option,requested),option <> others,others)
def sameProvider(options: List<&2,LoginDialog.ProviderOption>,+id: String) -> Bool:
  match options:
    case Nil{}: True{}
    case LoginDialog.ProviderOption{other,_,_,_,_,_} <> rest: String.eq(id,other) && sameProvider(rest,id)
def closeChosen(+state: LoginState,controller: Abort.AbortController<Unit>) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,abort,None{})
        Abort.dispose(Unit,controller)
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        closeLoginDialog(target)
        Interactive.requestRender(redraw)
def credentialFailure(state: LoginState,message: String) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,failure,_,_,_}: Interactive.report(failure,Interactive.CommandFailure{message})
def startProviderSelection(state: LoginState,controller: Abort.AbortController<Unit>,selection: LoginDialog.ProviderSelection) -> IO(Unit):
  match selection:
    case LoginDialog.ProviderSelection{provider,Auth.OAuthType{}}: selectedProvider(state,provider,Auth.OAuthType{},controller)
    case LoginDialog.ProviderSelection{provider,Auth.ApiKeyType{}}: apiSelected(state,provider,controller)
def chosenMethod(state: LoginState,controller: Abort.AbortController<Unit>,selection: Maybe<&2,LoginDialog.ProviderSelection>) -> IO(Unit):
  match selection:
    case None{}: closeChosen(state,controller)
    case Some{value}: startProviderSelection(state,controller,value)
def chooseProviderMethod(+state: LoginState,dialog: LoginDialog.Host,controller: Abort.AbortController<Unit>,options: List<&2,LoginDialog.ProviderOption>) -> IO(Unit):
  +options = {options: List<&2,LoginDialog.ProviderOption>}
  do IO<Unit>:
    +pending : Deferred.Deferred<Maybe<&2,LoginDialog.ProviderSelection>> <- LoginDialog.openAuthMenu(dialog,LoginDialog.Method{},"Select authentication method for " ++ selectionName(options) ++ ":",methodChoices(options),"")
    redrawLogin(state)
    selection : Maybe<&2,LoginDialog.ProviderSelection> <- Deferred.result(Maybe<&2,LoginDialog.ProviderSelection>,pending)
    Deferred.dispose(Maybe<&2,LoginDialog.ProviderSelection>,pending)
    chosenMethod(state,controller,selection)
def authMenuResult(+state: LoginState,dialog: LoginDialog.Host,query: String,prepared: Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>>) -> IO(Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>):
  match prepared:
    case Fail{message}: IO.pure(Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>,Fail{message})
    case Done{options}:
      do IO<Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>>:
        +pending : Deferred.Deferred<Maybe<&2,LoginDialog.ProviderSelection>> <- LoginDialog.openAuthMenu(dialog,LoginDialog.Provider{},"Select provider to configure:",providerChoices(options),query)
        redrawLogin(state)
        selection : Maybe<&2,LoginDialog.ProviderSelection> <- Deferred.result(Maybe<&2,LoginDialog.ProviderSelection>,pending)
        Deferred.dispose(Maybe<&2,LoginDialog.ProviderSelection>,pending)
        return Done{selection}
def noLoginProviders(filter: Maybe<&2,Auth.CredentialType>) -> String:
  match filter:
    case Some{Auth.OAuthType{}}: "No subscription providers available."
    case Some{Auth.ApiKeyType{}}: "No API key providers available."
    case None{}: "No login providers available."
def providerMenuOptions(+state: LoginState,dialog: LoginDialog.Host,filter: Maybe<&2,Auth.CredentialType>,query: String,options: List<&2,LoginDialog.ProviderOption>) -> IO(Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>):
  match options:
    case Nil{}: IO.pure(Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>,Fail{noLoginProviders(filter)})
    case values:
      do IO<Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>>:
        prepared : Result<&2,&2,String,List<&2,LoginDialog.ProviderOption>> <- prepareLoginOptions(state,values)
        authMenuResult(state,dialog,query,prepared)
def providerMenu(+state: LoginState,dialog: LoginDialog.Host,+filter: Maybe<&2,Auth.CredentialType>,query: String) -> IO(Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>):
  do IO<Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>>:
    options : List<&2,LoginDialog.ProviderOption> <- availableLoginOptions(state,filter)
    providerMenuOptions(state,dialog,filter,query,options)
def chosenProvider(+state: LoginState,controller: Abort.AbortController<Unit>,result: Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>) -> IO(Unit):
  match result:
    case Done{selection}: chosenMethod(state,controller,selection)
    case Fail{message}:
      do IO<Unit>:
        closeChosen(state,controller)
        credentialFailure(state,message)
type AuthMenuStep is Data:
  ChooseAuthType{}
  AuthTypeChosen{method: String}
  ProviderMenuChosen{result: Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>>}
# Esc in a provider menu goes back to the auth-type menu without aborting a
# provider operation; no login operation has started during these selections.
@unsafe def authMenu(step: AuthMenuStep,+state: LoginState,+dialog: LoginDialog.Host,+controller: Abort.AbortController<Unit>) -> IO(Unit):
  match step:
    case ChooseAuthType{}:
      do IO<Unit>:
        +pending : Deferred.Deferred<String> <- LoginDialog.open(dialog)
        redrawLogin(state)
        method : String <- Deferred.result(String,pending)
        Deferred.dispose(String,pending)
        authMenu(AuthTypeChosen{method},state,dialog,controller)
    case AuthTypeChosen{"oauth"}:
      do IO<Unit>:
        selection : Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>> <- providerMenu(state,dialog,Some{Auth.OAuthType{}},"")
        authMenu(ProviderMenuChosen{selection},state,dialog,controller)
    case AuthTypeChosen{"api_key"}:
      do IO<Unit>:
        selection : Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>> <- providerMenu(state,dialog,Some{Auth.ApiKeyType{}},"")
        authMenu(ProviderMenuChosen{selection},state,dialog,controller)
    case AuthTypeChosen{_}: closeChosen(state,controller)
    case ProviderMenuChosen{Done{None{}}}: authMenu(ChooseAuthType{},state,dialog,controller)
    case ProviderMenuChosen{Done{Some{value}}}: startProviderSelection(state,controller,value)
    case ProviderMenuChosen{Fail{message}}: chosenProvider(state,controller,Fail{message})
def groupedProvider(+state: LoginState,+dialog: LoginDialog.Host,+controller: Abort.AbortController<Unit>,requested: String,first: LoginDialog.ProviderOption,rest: List<&2,LoginDialog.ProviderOption>) -> IO(Unit):
  match first:
    case LoginDialog.ProviderOption{+id,name,kind,method,label,status}:
      +first = {LoginDialog.ProviderOption{id,name,kind,method,label,status}: LoginDialog.ProviderOption}
      +rest = {rest: List<&2,LoginDialog.ProviderOption>}
      +requested = {requested: String}
      Bool.pick(Unit -> IO(Unit),sameProvider(rest,id),_ => chooseProviderMethod(state,dialog,controller,first <> rest),_ => do IO<Unit>:
        selection : Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>> <- providerMenu(state,dialog,None{},requested)
        chosenProvider(state,controller,selection))(Unit{})
def directGrouped(+state: LoginState,dialog: LoginDialog.Host,+controller: Abort.AbortController<Unit>,requested: String,options: List<&2,LoginDialog.ProviderOption>) -> IO(Unit):
  match options:
    case first <> rest: groupedProvider(state,dialog,controller,requested,first,rest)
    case Nil{}:
      do IO<Unit>:
        selection : Result<&2,&2,String,Maybe<&2,LoginDialog.ProviderSelection>> <- providerMenu(state,dialog,None{},requested)
        chosenProvider(state,controller,selection)
def directOptions(+state: LoginState,dialog: LoginDialog.Host,+controller: Abort.AbortController<Unit>,+requested: String,options: List<&2,LoginDialog.ProviderOption>) -> IO(Unit):
  match options:
    case LoginDialog.ProviderOption{id,_,kind,_,_,_} <> Nil{}: startProviderSelection(state,controller,LoginDialog.ProviderSelection{id,kind})
    case options:
      directGrouped(state,dialog,controller,requested,options)
def beginRequested(+state: LoginState,dialog: LoginDialog.Host,controller: Abort.AbortController<Unit>,requested: String) -> IO(Unit):
  match requested:
    case "": authMenu(ChooseAuthType{},state,dialog,controller)
    case +value:
      do IO<Unit>:
        options : List<&2,LoginDialog.ProviderOption> <- availableLoginOptions(state,None{})
        directOptions(state,dialog,controller,value,matchingOptions(options,String.to_lower(Text.trim(value))))
def activeLogin(+state: LoginState,+dialog: LoginDialog.Host,requested: String) -> IO(Unit):
  match state:
    case LoginState{_,abort,_,_,_,_,_,_,_}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        Ref.write(Maybe<&2,Abort.AbortController<Unit>>,abort,Some{controller})
        beginRequested(state,dialog,controller,requested)
def beginLogin(state: LoginState,target: Maybe<&2,LoginDialog.Host>,requested: String) -> IO(Unit):
  match target:
    case Some{dialog}: activeLogin(state,dialog,requested)
    case None{}: credentialFailure(state,"Login is unavailable")
def loginRunCopied(+state: LoginState,requested: String) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        beginLogin(state,target,requested)
def loginRun(state: LoginState,requested: String) -> IO(Unit): loginRunCopied(state,requested)
def logoutChoice(info: Auth.CredentialInfo) -> LoginDialog.Choice:
  match info:
    case Auth.CredentialInfo{+id,kind}: LoginDialog.Choice{LoginDialog.TextChoice{id},providerName(id),Auth.typeName(kind),id}
def logoutChoices(infos: List<&2,Auth.CredentialInfo>) -> List<&2,LoginDialog.Choice>:
  match infos:
    case Nil{}: Nil{}
    case info <> rest: logoutChoice(info) <> logoutChoices(rest)
def logoutKind(infos: List<&2,Auth.CredentialInfo>,+id: String) -> Maybe<&2,Auth.CredentialType>:
  match infos:
    case Nil{}: None{}
    case Auth.CredentialInfo{provider,kind} <> rest: Bool.pick(Maybe<&2,Auth.CredentialType>,String.eq(provider,id),Some{kind},logoutKind(rest,id))
def logoutNotice(provider: String,kind: Maybe<&2,Auth.CredentialType>) -> String:
  match kind:
    case Some{Auth.ApiKeyType{}}: "Removed stored API key for " ++ providerName(provider) ++ ". Environment variables and models.json config are unchanged."
    case _: "Logged out of " ++ providerName(provider)
def logoutOutcome(+provider: String,kind: Maybe<&2,Auth.CredentialType>,result: AuthLogin.Outcome(),refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        available : List<&2,Models.Model()> <- refreshLoginModels(refresh,models)
        Interactive.report(failure,Interactive.CommandNotice{logoutNotice(provider,kind)})
    case Fail{message}: Interactive.report(failure,Interactive.CommandFailure{"Logout failed: " ++ message})
def logoutChosen(state: LoginState,+chosen: String,infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match state:
    case LoginState{_,_,_,refresh,models,failure,redraw,_,_}:
      do IO<Unit>:
        kind : Maybe<&2,Auth.CredentialType> = logoutKind(infos,chosen)
        result : AuthLogin.Outcome() <- AuthLogin.logout(chosen)
        logoutOutcome(chosen,kind,result,refresh,models,failure)
        Interactive.requestRender(redraw)
def logoutSelected(state: LoginState,provider: String,infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match provider:
    case "": IO.pure(Unit,Unit{})
    case chosen: logoutChosen(state,chosen,infos)
def logoutMenu(+state: LoginState,+dialog: LoginDialog.Host,+infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,_,redraw,_,_}:
      do IO<Unit>:
        +pending : Deferred.Deferred<String> <- LoginDialog.openChoices(dialog," Logout · Stored credentials",logoutChoices(infos))
        Interactive.requestRender(redraw)
        chosen : String <- Deferred.result(String,pending)
        Deferred.dispose(String,pending)
        LoginDialog.close(dialog)
        Interactive.requestRender(redraw)
        logoutSelected(state,chosen,infos)
def emptyLogout(state: LoginState) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,failure,redraw,_,_}:
      do IO<Unit>:
        Interactive.report(failure,Interactive.CommandNotice{"No stored credentials to remove. /logout only removes credentials saved by /login; environment variables and models.json config are unchanged."})
def logoutAvailable(state: LoginState,target: Maybe<&2,LoginDialog.Host>,infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match target:
    case Some{dialog}: logoutMenu(state,dialog,infos)
    case None{}: credentialFailure(state,"Login is unavailable")
def logoutListed(state: LoginState,target: Maybe<&2,LoginDialog.Host>,result: AuthLogin.StoredCredentials()) -> IO(Unit):
  match result:
    case Fail{message}: credentialFailure(state,"Could not read stored credentials: " ++ message)
    case Done{Nil{}}: emptyLogout(state)
    case Done{infos}: logoutAvailable(state,target,infos)
def logoutRun(+state: LoginState) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        stored : AuthLogin.StoredCredentials() <- AuthLogin.storedCredentials()
        logoutListed(state,target,stored)
def credentialRun(state: LoginState,command: Commands.CredentialCommand) -> IO(Unit):
  match command:
    case Commands.BeginLogin{requested}: loginRun(state,Maybe.default(&2,String,requested,""))
    case Commands.BeginLogout{}: logoutRun(state)
def abortLogin(current: Maybe<&2,Abort.AbortController<Unit>>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{controller}:
      do IO<Unit>:
        cancelled : Bool <- Abort.abort(Unit,controller,None{})
        return Unit{}
def cancelLoginOperation(active: Maybe<&2,Abort.AbortController<Unit>>,dialog: LoginDialog.Host,selector: Bool) -> IO(Unit):
  match selector:
    case True{}: IO.pure(Unit,Unit{})
    case False{}:
      do IO<Unit>:
        abortLogin(active)
        LoginDialog.close(dialog)
def cancelLoginDialog(active: Maybe<&2,Abort.AbortController<Unit>>,target: Maybe<&2,LoginDialog.Host>) -> IO(Unit):
  match target:
    case None{}: abortLogin(active)
    case Some{+dialog}:
      do IO<Unit>:
        selector : Bool <- LoginDialog.cancelSelector(dialog)
        cancelLoginOperation(active,dialog,selector)
def cancelLogin(state: LoginState,_: Unit) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,_,_,_,_,_}:
      do IO<Unit>:
        active : Maybe<&2,Abort.AbortController<Unit>> <- Ref.read(Maybe<&2,Abort.AbortController<Unit>>,abort)
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        cancelLoginDialog(active,target)
type ThemeContext is Data:
  ThemeContext{theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,session: Ref.Ref<Session.AgentSession>,setting: Maybe<&2,String>,builtinDir: String,customDir: String,interaction: Interaction,models: Ref.Ref<List<&2,Models.Model()>>,binding: Maybe<&2,Binding>,login: LoginState,resume: ResumeState,keys: Keybindings.KeybindingsManager,highlighter: SyntaxHighlight.Highlighter,status: Interactive.StatusSink}
type KeyInput is Data:
  KeyInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Interactive.StatusSink,lastClear: Ref.Ref<Maybe<&2,F64>>,lastEscape: Ref.Ref<Maybe<&2,F64>>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,session: Ref.Ref<Session.AgentSession>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,header: Maybe<&2,Header.Handle>,transcript: Transcript.Handle,models: Interactive.CommandSink}
type ControlSink is Data:
  ControlSink{editor: Ref.Ref<Maybe<&2,Live.Handle>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SelectionSink is Data:
  SelectionSink{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footerRef: Ref.Ref<Footer.State>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>}
def selectionText(result: Controller.SelectionResult) -> Maybe<&2,String>:
  match result:
    case Controller.Navigated{Session.Navigation{text,_}}: text
    case Controller.Forked{text}: text
    case Controller.SelectionFailed{_}: None{}
def setSelectedDraft(target: Maybe<&2,Live.Handle>,value: String) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}: Live.setText(handle,value)
def updateSelectionEditor(editor: Ref.Ref<Maybe<&2,Live.Handle>>,text: Maybe<&2,String>) -> IO(Unit):
  match text:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}:
      do IO<Unit>:
        target : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        setSelectedDraft(target,value)
def refreshSelection(sink: SelectionSink,result: Controller.SelectionResult) -> IO(Unit):
  match sink:
    case SelectionSink{+session,+transcript,editor,footerRef,failure,redraw,cwd,home}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        +messages : List<&2,Session.Message()> <- Session.messages(live)
        Transcript.clear(transcript)
        Transcript.seedSession(transcript,messages)
        agentState : Session.AgentState() <- Session.state(live)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        Ref.write(Footer.State,footerRef,initialFooter(agentState,messages,cwd,home,Settings.getCompactionEnabled(settings)))
        updateSelectionEditor(editor,selectionText(result))
        Interactive.requestRender(redraw)
def failedSelection(sink: SelectionSink,message: String) -> IO(Unit):
  match sink:
    case SelectionSink{_,_,_,_,failure,redraw,_,_}:
      do IO<Unit>:
        Interactive.report(failure,Interactive.PromptFailure{message})
def forkSelectionNotice(sink: SelectionSink) -> IO(Unit):
  match sink: case SelectionSink{_,_,_,_,failure,_,_,_}: selectorNotice(failure,"Forked to new session")
def selectionResult(sink: SelectionSink,result: Controller.SelectionResult) -> IO(Unit):
  match result:
    case Controller.Navigated{navigation}: refreshSelection(sink,Controller.Navigated{navigation})
    case Controller.Forked{text}:
      +target = {sink: SelectionSink}
      do IO<Unit>:
        refreshSelection(target,Controller.Forked{text})
        forkSelectionNotice(target)
    case Controller.SelectionFailed{message}: failedSelection(sink,message)
type SelectInput is Data: SelectInput{queue: Controller.Handle,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type ScopeInput is Data:
  ScopeInput{session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def selectionJob(mode: Selector.Mode,id: String) -> Controller.Selection:
  match mode:
    case Selector.TreeMode{}: Controller.Navigate{id}
    case Selector.ForkMode{}: Controller.Fork{id}
def chosenSelection(input: SelectInput,choice: Selector.Choice) -> IO(Unit):
  match input choice:
    case SelectInput{queue,failure,redraw} Selector.Choice{mode,id}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitSelection(queue,selectionJob(mode,id))
        Interactive.submittedResult(failure,result)
def chosenModel(input: SelectInput,choice: ModelPicker.Choice) -> IO(Unit):
  match input choice:
    case SelectInput{queue,failure,_} ModelPicker.Choice{chosen,persist}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,Commands.SwitchModel{chosen,persist})
        Interactive.submittedResult(failure,result)
def chosenThinking(input: SelectInput,choice: ThinkingPicker.Choice) -> IO(Unit):
  match input choice:
    case SelectInput{queue,failure,_} ThinkingPicker.Choice{level,persist}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,Commands.SelectThinking{level,persist})
        Interactive.submittedResult(failure,result)
def singletonScope(model: Models.Model()) -> List<&2,Models.ScopedModel>:
  Models.ScopedModel{model,None{}} <> Nil{}
def availableScope(ids: List<&2,String>,+models: List<&2,Models.Model()>) -> List<&2,Models.ScopedModel>:
  match ids:
    case Nil{}: Nil{}
    case id <> rest:
      +found = Maybe.default(&2,List<&2,Models.ScopedModel>,Maybe.map(&2,Models.Model(),List<&2,Models.ScopedModel>,singletonScope,ScopePicker.findModel(models,id)),Nil{})
      List.append(&2,Models.ScopedModel,found,availableScope(rest,models))
def activeScope(scope: ScopePicker.Scope,+models: List<&2,Models.Model()>) -> List<&2,Models.ScopedModel>:
  match scope:
    case ScopePicker.All{}: Nil{}
    case ScopePicker.Selected{ids}:
      +available = availableScope(ids,models)
      Bool.pick(List<&2,Models.ScopedModel>,Nat.is_eq(List.length(&2,Models.ScopedModel,available),List.length(&2,Models.Model(),models)),Nil{},available)
def savedScope(scope: ScopePicker.Scope,session: Session.AgentSession) -> IO(Result<&2,&2,String,Unit>):
  match scope:
    case ScopePicker.All{}: Session.changeSettings(session,current => Settings.setEnabledModels(None{},current))
    case ScopePicker.Selected{ids}: Session.changeSettings(session,current => Settings.setEnabledModels(Some{ids},current))
def scopeSaved(failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        Interactive.report(failure,Interactive.CommandNotice{"Model selection saved to settings"})
        Interactive.requestRender(redraw)
    case Fail{reason}:
      do IO<Unit>:
        Interactive.report(failure,Interactive.CommandFailure{reason})
        Interactive.requestRender(redraw)
def scopeAction(input: ScopeInput,action: ScopePicker.Action) -> IO(Unit):
  match input action:
    case ScopeInput{session,models,_,redraw} ScopePicker.Changed{scope}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        Session.setScopedModels(live,activeScope(scope,available))
        Interactive.requestRender(redraw)
    case ScopeInput{session,_,failure,redraw} ScopePicker.Save{scope}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Unit> <- savedScope(scope,live)
        scopeSaved(failure,redraw,result)
    case _ _: IO.pure(Unit,Unit{})
def selectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,Selector.Host>>:
  match interaction: case Interaction{_,_,_,selector,_,_,_,_,_,_,_,_,_}: selector
def modelSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,ModelPicker.Host>>:
  match interaction: case Interaction{_,_,_,_,selector,_,_,_,_,_,_,_,_}: selector
def thinkingSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,ThinkingPicker.Host>>:
  match interaction: case Interaction{_,_,_,_,_,selector,_,_,_,_,_,_,_}: selector
def scopedSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,ScopePicker.Host>>:
  match interaction: case Interaction{_,_,_,_,_,_,selector,_,_,_,_,_,_}: selector
def settingsSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,SettingsPicker.Host>>:
  match interaction: case Interaction{_,_,_,_,_,_,_,settings,_,_,_,_,_}: settings
def editorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,Live.Handle>>:
  match interaction: case Interaction{editor,_,_,_,_,_,_,_,_,_,_,_,_}: editor
def trustSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,TrustPicker.Host>>:
  match interaction: case Interaction{_,_,_,_,_,_,_,_,trust,_,_,_,_}: trust
def contextStatus(context: ThemeContext) -> Interactive.StatusSink:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,_,_,_,_,status}: status
def contextTheme(context: ThemeContext) -> Ref.Ref<Theme.Theme>:
  match context: case ThemeContext{theme,_,_,_,_,_,_,_,_,_,_,_,_,_}: theme
def contextTranscript(context: ThemeContext) -> Transcript.Handle:
  match context: case ThemeContext{_,transcript,_,_,_,_,_,_,_,_,_,_,_,_}: transcript
def contextAgentDir(context: ThemeContext) -> String:
  match context: case ThemeContext{_,_,_,_,_,customDir,_,_,_,_,_,_,_,_}: Path.normalize(customDir ++ "/..")
def contextInteraction(context: ThemeContext) -> Interaction:
  match context: case ThemeContext{_,_,_,_,_,_,interaction,_,_,_,_,_,_,_}: interaction
def lastClearOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,F64>>:
  match interaction: case Interaction{_,lastClear,_,_,_,_,_,_,_,_,_,_,_}: lastClear
def recordEditor(interaction: Interaction,handle: Live.Handle) -> IO(Unit):
  match interaction: case Interaction{editor,_,_,_,_,_,_,_,_,_,_,_,_}: Ref.write(Maybe<&2,Live.Handle>,editor,Some{handle})
def bashActivityOf(interaction: Interaction) -> Ref.Ref<BashActivity>:
  match interaction: case Interaction{_,_,_,_,_,_,_,_,_,_,activity,_,_}: activity
def workingOf(interaction: Interaction) -> Working:
  match interaction: case Interaction{_,_,_,_,_,_,_,_,_,_,_,working,_}: working
def contextModels(context: ThemeContext) -> Ref.Ref<List<&2,Models.Model()>>:
  match context: case ThemeContext{_,_,_,_,_,_,_,models,_,_,_,_,_,_}: models
def contextSession(context: ThemeContext) -> Ref.Ref<Session.AgentSession>:
  match context: case ThemeContext{_,_,session,_,_,_,_,_,_,_,_,_,_,_}: session
def contextLogin(context: ThemeContext) -> LoginState:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,login,_,_,_,_}: login
def contextResume(context: ThemeContext) -> ResumeState:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,_,resume,_,_,_}: resume
def resumePickerRef(state: ResumeState) -> Ref.Ref<Maybe<&2,SessionPicker.Host>>:
  match state: case ResumeState{picker,_,_,_,_,_}: picker
def contextBinding(context: ThemeContext) -> Maybe<&2,Binding>:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,binding,_,_,_,_,_}: binding
def contextBindings(context: ThemeContext) -> Keybindings.KeybindingsManager:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,_,_,keys,_,_}: keys
def loginStateOf(mode: Maybe<&2,Binding>,host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,abort: Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>,sort: Ref.Ref<ProviderSort>) -> LoginState:
  match mode:
    case None{}: LoginState{host,abort,None{},None{},models,failure,redraw,session,sort}
    case Some{Binding{_,_,_,backend,refresh,_,_,_,_,_,_}}: LoginState{host,abort,Some{backend},Some{refresh},models,failure,redraw,session,sort}
def importStateOf(mode: Maybe<&2,Binding>,host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> ImportState:
  match mode:
    case None{}: ImportState{host,None{},failure,redraw}
    case Some{Binding{_,_,_,_,_,backend,_,_,_,_,_}}: ImportState{host,Some{backend},failure,redraw}
def resumeStateOf(mode: Maybe<&2,Binding>,picker: Ref.Ref<Maybe<&2,SessionPicker.Host>>,dialog: Ref.Ref<Maybe<&2,LoginDialog.Host>>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> ResumeState:
  match mode:
    case None{}: ResumeState{picker,dialog,None{},None{},failure,redraw}
    case Some{Binding{_,_,_,_,_,_,sessions,resume,_,_,_}}: ResumeState{picker,dialog,Some{sessions},Some{resume},failure,redraw}
def disposeLoginState(state: LoginState) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,models,_,_,_,sort}:
      do IO<Unit>:
        oldSort : ProviderSort <- Ref.dispose(ProviderSort,sort)
        oldHost : Maybe<&2,LoginDialog.Host> <- Ref.dispose(Maybe<&2,LoginDialog.Host>,host)
        oldAbort : Maybe<&2,Abort.AbortController<Unit>> <- Ref.dispose(Maybe<&2,Abort.AbortController<Unit>>,abort)
        oldModels : List<&2,Models.Model()> <- Ref.dispose(List<&2,Models.Model()>,models)
        return Unit{}
def keyInput(queue: Controller.Handle,stop: Deferred.Deferred<Unit>,+failure: Interactive.StatusSink,interaction: Interaction,+session: Ref.Ref<Session.AgentSession>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,transcript: Transcript.Handle,models: Ref.Ref<List<&2,Models.Model()>>) -> KeyInput:
  match interaction:
    case Interaction{_,lastClear,lastEscape,selector,+modelSelector,+thinkingSelector,+scopedSelector,_,_,header,_,_,_}: KeyInput{queue,stop,failure,lastClear,lastEscape,selector,session,redraw,header,transcript,Interactive.CommandSink{failure,redraw,modelSelector,thinkingSelector,scopedSelector,session,models}}
def openedTree(input: KeyInput,mode: Selector.Mode) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,selector,session,redraw,_,_,_}: openSessionSelector(mode,session,selector,failure,redraw)
def actionDouble(input: KeyInput,action: Settings.DoubleEscapeAction) -> IO(Unit):
  match action:
    case Settings.Tree{}: openedTree(input,Selector.TreeMode{})
    case Settings.Fork{}: openedTree(input,Selector.ForkMode{})
    case Settings.NoDoubleEscape{}: IO.pure(Unit,Unit{})
def triggerDouble(+input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,lastEscape,_,session,_,_,_,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,F64>,lastEscape,None{})
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        action : Settings.DoubleEscapeAction = Settings.getDoubleEscapeAction(settings)
        actionDouble(input,action)
def doubleEscape(input: KeyInput,previous: Maybe<&2,F64>,now: F64) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{earlier}:
      Bool.pick(Unit -> IO(Unit),F64.is_lt(F.subtract(now,earlier),U32.to_f64(500)),_ => triggerDouble(input),_ => IO.pure(Unit,Unit{}))(Unit{})
def idleEscape(input: KeyInput,lastEscape: Ref.Ref<Maybe<&2,F64>>) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    previous : Maybe<&2,F64> <- Ref.swap(Maybe<&2,F64>,lastEscape,Some{now})
    doubleEscape(input,previous,now)
def keyControl(input: KeyInput,control: Controller.Control) -> IO(Unit):
  match input:
    case KeyInput{queue,_,failure,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitControl(queue,control)
        Interactive.submittedResult(failure,result)
def abortCompaction(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    Session.abortCompaction(session)
    Session.abortBranchSummary(session)
def interrupted(+input: KeyInput,+text: String) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,lastEscape,_,session,_,_,_,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        bash : Bool <- Session.isBashRunning(live)
        retry : Bool <- Session.isRetrying(live)
        compact : Bool <- Session.isCompacting(live)
        active : Bool <- Session.isStreaming(live)
        Bool.pick(Unit -> IO(Unit),bash,_ => Session.abortBash(live),
          _ => Bool.pick(Unit -> IO(Unit),retry,_ => Session.abortRetry(live),
            _ => Bool.pick(Unit -> IO(Unit),compact,_ => abortCompaction(live),
              _ => Bool.pick(Unit -> IO(Unit),active,_ => keyControl(input,Controller.Interrupt{text}),
                _ => Bool.pick(Unit -> IO(Unit),String.is_empty(Text.trim(text)),_ => idleEscape(input,lastEscape),_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def doubleClear(previous: Maybe<&2,F64>,now: F64,stop: Deferred.Deferred<Unit>) -> IO(Unit):
  match previous:
    case Some{earlier}: Bool.pick(Unit -> IO(Unit),F64.is_lt(F.subtract(now,earlier),U32.to_f64(500)),_ => do IO<Unit>:
      settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
      return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
    case None{}: IO.pure(Unit,Unit{})
def cleared(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,stop,_,lastClear,_,_,_,_,_,_,_}:
      do IO<Unit>:
        +now : F64 <- Date.now()
        previous : Maybe<&2,F64> <- Ref.swap(Maybe<&2,F64>,lastClear,Some{now})
        doubleClear(previous,now,stop)
def queuedFollowUp(input: KeyInput,+text: String) -> IO(Unit):
  match input:
    case KeyInput{queue,_,failure,_,_,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Unit),String.is_empty(text),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submit(queue,Controller.Submission{text,Nil{},Some{Session.FollowUp{}}})
        Interactive.submittedResult(failure,result))(Unit{})
def exited(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,stop,_,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
def toggleHeader(header: Maybe<&2,Header.Handle>) -> IO(Unit):
  match header:
    case Some{value}: Header.toggle(value)
    case None{}: IO.pure(Unit,Unit{})
def expandOutput(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,_,_,_,_,header,+transcript,_}:
      do IO<Unit>:
        expanded : Bool <- Transcript.toggleExpanded(transcript)
        toggleHeader(header)
        Transcript.status(transcript,Bool.pick(String,expanded,"Tool output: expanded","Tool output: collapsed"))
def thinkingChanged(result: Result<&2,&2,String,Unit>,+transcript: Transcript.Handle,failure: Interactive.StatusSink,+hidden: Bool) -> IO(Unit):
  match result:
    case Fail{reason}: Interactive.report(failure,Interactive.CommandFailure{reason})
    case Done{_}:
      do IO<Unit>:
        Transcript.setHideThinking(transcript,hidden)
        Transcript.status(transcript,Bool.pick(String,hidden,"Thinking blocks: hidden","Thinking blocks: visible"))
def toggleThinking(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,_,session,_,_,transcript,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        +hidden : Bool <- IO.pure(Bool,Bool.not(Settings.getHideThinkingBlock(settings)))
        result : Result<&2,&2,String,Unit> <- Session.changeSettings(live,current => Settings.setHideThinkingBlock(hidden,current))
        thinkingChanged(result,transcript,failure,hidden)
# upstream cycleThinkingLevel/cycleModel status messages.
def thinkingCycled(transcript: Transcript.Handle,failure: Interactive.StatusSink,result: Result<&2,&2,String,Maybe<&2,Ai.ModelThinkingLevel>>) -> IO(Unit):
  match result:
    case Fail{reason}: Interactive.report(failure,Interactive.CommandFailure{reason})
    case Done{None{}}: Transcript.status(transcript,"Current model does not support thinking")
    case Done{Some{level}}: Transcript.status(transcript,"Thinking level: " ++ Levels.name(level))
def cycleThinking(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,_,session,_,_,transcript,_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Maybe<&2,Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live,Session.ModelMutationOptions{False{}})
        thinkingCycled(transcript,failure,result)
def thinkingSuffix(selected: Models.Model(),level: Ai.ModelThinkingLevel) -> String:
  match level:
    case Ai.Off{}: ""
    case level: Bool.pick(String,Ai.modelReasoning(selected)," (thinking: " ++ Levels.name(level) ++ ")","")
def modelLabel(+selected: Models.Model()) -> String:
  +name = Models.modelName(selected)
  Bool.pick(String,String.is_empty(name),Models.modelId(selected),name)
def switchedModel(+selected: Models.Model(),level: Ai.ModelThinkingLevel) -> String: "Switched to " ++ modelLabel(selected) ++ thinkingSuffix(selected,level)
def switchedTo(cycled: Session.ModelCycleResult) -> String:
  match cycled:
    case Session.ModelCycleResult{selected,level,_}: switchedModel(selected,level)
def modelCycled(transcript: Transcript.Handle,scoped: Bool,result: Result<&2,&2,String,Maybe<&2,Session.ModelCycleResult>>) -> IO(Unit):
  match result:
    case Fail{reason}: Transcript.showError(transcript,reason)
    case Done{None{}}: Transcript.status(transcript,Bool.pick(String,scoped,"Only one model in scope","Only one model available"))
    case Done{Some{cycled}}: Transcript.status(transcript,switchedTo(cycled))
def cycleModel(input: KeyInput,direction: Session.CycleDirection) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,_,_,session,_,_,transcript,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Maybe<&2,Session.ModelCycleResult>> <- Session.cycleModel(live,direction,Session.ModelMutationOptions{False{}})
        scope : List<&2,Models.ScopedModel> <- Session.getScopedModels(live)
        modelCycled(transcript,Bool.not(List.is_empty(&2,Models.ScopedModel,scope)),result)
# upstream showModelSelector, as /model without arguments.
def selectModel(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,_,_,_,_,_,_,sink}:
      do IO<Unit>:
        changed : Bool <- Interactive.commandResult(sink,Commands.OpenModelPicker{None{}})
        return Unit{}
def commandKey(input: KeyInput,command: Commands.Command) -> IO(Unit):
  match input:
    case KeyInput{queue,_,failure,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,command)
        Interactive.submittedResult(failure,result)
# upstream clearEditor and handleFollowUp: the editor is emptied after the key.
def emptied(editor: Live.Handle) -> IO(Unit): Live.setText(editor,"")
def interruptKey(input: KeyInput,editor: Live.Handle) -> IO(Unit):
  do IO<Unit>:
    text : String <- Live.text(editor)
    interrupted(input,text)
def clearKey(input: KeyInput,editor: Live.Handle) -> IO(Unit):
  do IO<Unit>:
    emptied(editor)
    cleared(input)
def followUpKey(input: KeyInput,+editor: Live.Handle) -> IO(Unit):
  do IO<Unit>:
    text : String <- Live.expandedText(editor)
    emptied(editor)
    queuedFollowUp(input,Text.trim(text))
def dequeueKey(input: KeyInput,editor: Live.Handle) -> IO(Unit):
  do IO<Unit>:
    text : String <- Live.text(editor)
    keyControl(input,Controller.Dequeue{text})
# upstream setupKeyHandlers: the app actions the editor intercepts, in
# registration order.
def APP_ACTIONS() -> List<&2,String>:
  ["app.interrupt","app.clear","app.exit","app.thinking.cycle","app.model.cycleForward","app.model.cycleBackward","app.model.select","app.tools.expand","app.thinking.toggle","app.message.copy","app.message.followUp","app.message.dequeue","app.session.new","app.session.tree","app.session.fork","app.session.resume"]
def keyAction(input: KeyInput,action: CustomEditor.AppAction) -> IO(Unit):
  match action:
    case CustomEditor.AppAction{"app.interrupt",editor}: interruptKey(input,editor)
    case CustomEditor.AppAction{"app.clear",editor}: clearKey(input,editor)
    case CustomEditor.AppAction{"app.exit",_}: exited(input)
    case CustomEditor.AppAction{"app.thinking.cycle",_}: cycleThinking(input)
    case CustomEditor.AppAction{"app.model.cycleForward",_}: cycleModel(input,Session.Forward{})
    case CustomEditor.AppAction{"app.model.cycleBackward",_}: cycleModel(input,Session.Backward{})
    case CustomEditor.AppAction{"app.model.select",_}: selectModel(input)
    case CustomEditor.AppAction{"app.tools.expand",_}: expandOutput(input)
    case CustomEditor.AppAction{"app.thinking.toggle",_}: toggleThinking(input)
    case CustomEditor.AppAction{"app.message.copy",_}: commandKey(input,Commands.Copy{})
    case CustomEditor.AppAction{"app.message.followUp",editor}: followUpKey(input,editor)
    case CustomEditor.AppAction{"app.message.dequeue",editor}: dequeueKey(input,editor)
    case CustomEditor.AppAction{"app.session.new",_}: commandKey(input,Commands.NewSession{})
    case CustomEditor.AppAction{"app.session.tree",_}: commandKey(input,Commands.Tree{})
    case CustomEditor.AppAction{"app.session.fork",_}: commandKey(input,Commands.Fork{})
    case CustomEditor.AppAction{"app.session.resume",_}: commandKey(input,Commands.Resume{})
    case _: IO.pure(Unit,Unit{})
def changedEditor(target: Maybe<&2,Live.Handle>,value: String,count: Nat) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}: Bool.pick(Unit -> IO(Unit),Nat.is_gt(count,0n),_ => Live.setText(handle,value),_ => IO.pure(Unit,Unit{}))(Unit{})
def controlResult(sink: ControlSink,result: Controller.ControlResult) -> IO(Unit):
  match sink result:
    case ControlSink{editor,failure,redraw} Controller.ControlResult{text,+total}:
      do IO<Unit>:
        target : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        changedEditor(target,text,total)
        message : String <- IO.pure(String,Bool.pick(String,Nat.is_eq(total,0n),"No queued messages to restore","Restored " ++ Nat.show(total) ++ Bool.pick(String,Nat.is_eq(total,1n)," queued message"," queued messages") ++ " to editor"))
        Interactive.report(failure,Interactive.CommandNotice{message})
type RebindSink is Data:
  RebindSink{listener: Session.Listener(),transcript: Transcript.Handle,footerRef: Ref.Ref<Footer.State>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>}
def reboundCopied(sink: RebindSink,+session: Session.AgentSession) -> IO(Unit):
  match sink:
    case RebindSink{listener,+transcript,footerRef,failure,redraw,cwd,home}:
      do IO<Unit>:
        Session.subscribe(session,listener)
        +messages : List<&2,Session.Message()> <- Session.messages(session)
        Transcript.clear(transcript)
        +settings : Settings.SettingsManager <- Session.getSettings(session)
        Transcript.setHideThinking(transcript,Settings.getHideThinkingBlock(settings))
        Transcript.seedSession(transcript,messages)
        state : Session.AgentState() <- Session.state(session)
        Ref.write(Footer.State,footerRef,initialFooter(state,messages,cwd,home,Settings.getCompactionEnabled(settings)))
        Interactive.requestRender(redraw)
def rebound(sink: RebindSink,session: Session.AgentSession) -> IO(Unit):
  reboundCopied(sink,session)
def bindRebound(binding: Binding,listener: Session.Listener(),transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>) -> IO(Unit):
  match binding:
    case Binding{_,_,hook,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        callback : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~RebindSink,~Session.AgentSession,~Unit,~rebound,RebindSink{listener,transcript,footer,failure,redraw,cwd,home})
        Ref.write(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook,Some{callback})
def bindOptional(mode: Maybe<&2,Binding>,listener: Session.Listener(),transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>) -> IO(Unit):
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{binding}: bindRebound(binding,listener,transcript,editor,footer,failure,redraw,cwd,home)
def disposeRebindCallback(value: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(Session.AgentSession,Unit,callback)
def unbind(mode: Maybe<&2,Binding>) -> IO(Unit):
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Binding{_,_,hook,_,_,_,_,_,_,_,_}}:
      do IO<Unit>:
        callback : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.swap(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook,None{})
        disposeRebindCallback(callback)
def finishSessionRef(session: Ref.Ref<Session.AgentSession>,mode: Maybe<&2,Binding>) -> IO(Unit):
  match mode:
    case None{}:
      do IO<Unit>:
        retired : Session.AgentSession <- Ref.dispose(Session.AgentSession,session)
        return Unit{}
    case Some{_}: IO.pure(Unit,Unit{})
def modeCurrent(mode: Maybe<&2,Binding>,session: Session.AgentSession) -> IO(Ref.Ref<Session.AgentSession>):
  match mode:
    case None{}: Ref.new(Session.AgentSession,session)
    case Some{Binding{current,_,_,_,_,_,_,_,_,_,_}}: IO.pure(Ref.Ref<Session.AgentSession>,current)
def controllerFor(mode: Maybe<&2,Binding>,current: Ref.Ref<Session.AgentSession>,session: Session.AgentSession,listener: Session.Listener(),limit: Nat,failure: Maybe<&2,Callback.Callback<Controller.PromptFailure,Unit>>,command: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,control: Maybe<&2,Callback.Callback<Controller.ControlResult,Unit>>,selection: Maybe<&2,Callback.Callback<Controller.SelectionResult,Unit>>,models: Ref.Ref<List<&2,Models.Model()>>,login: Callback.Callback<Commands.CredentialCommand,Unit>) -> IO(Controller.Controller & Controller.Handle):
  match mode:
    case None{}:
      do IO<Controller.Controller & Controller.Handle>:
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        Callback.dispose(Commands.CredentialCommand,Unit,login)
        Controller.start(session,listener,limit,failure,command,control,selection,available)
    case Some{Binding{_,replacement,_,_,_,_,_,_,_,_,_}}: Controller.startBound(current,listener,replacement,limit,failure,command,control,selection,models,Some{login})
def disposeInteraction(interaction: Interaction) -> IO(Unit):
  match interaction:
    case Interaction{editor,lastClear,lastEscape,selector,modelSelector,thinkingSelector,scopedSelector,settings,trust,_,bashActivity,working,autocomplete}:
      do IO<Unit>:
        disposeAutocompleteSlot(autocomplete)
        oldEditor : Maybe<&2,Live.Handle> <- Ref.dispose(Maybe<&2,Live.Handle>,editor)
        oldClear : Maybe<&2,F64> <- Ref.dispose(Maybe<&2,F64>,lastClear)
        oldEscape : Maybe<&2,F64> <- Ref.dispose(Maybe<&2,F64>,lastEscape)
        oldSelector : Maybe<&2,Selector.Host> <- Ref.dispose(Maybe<&2,Selector.Host>,selector)
        oldModelSelector : Maybe<&2,ModelPicker.Host> <- Ref.dispose(Maybe<&2,ModelPicker.Host>,modelSelector)
        oldThinkingSelector : Maybe<&2,ThinkingPicker.Host> <- Ref.dispose(Maybe<&2,ThinkingPicker.Host>,thinkingSelector)
        oldScopedSelector : Maybe<&2,ScopePicker.Host> <- Ref.dispose(Maybe<&2,ScopePicker.Host>,scopedSelector)
        oldSettings : Maybe<&2,SettingsPicker.Host> <- Ref.dispose(Maybe<&2,SettingsPicker.Host>,settings)
        oldTrust : Maybe<&2,TrustPicker.Host> <- Ref.dispose(Maybe<&2,TrustPicker.Host>,trust)
        oldBash : BashActivity <- Ref.dispose(BashActivity,bashActivity)
        disposeBashActivity(oldBash)
        disposeWorking(working)
        return Unit{}
def managedOf(mode: Maybe<&2,Binding>) -> Maybe<&2,Manager.ToolsManager>:
  match mode:
    case None{}: None{}
    case Some{Binding{_,_,_,_,_,_,_,_,managed,_,_}}: managed
def autoTrustOnReloadOf(mode: Maybe<&2,Binding>) -> Bool:
  match mode:
    case None{}: False{}
    case Some{Binding{_,_,_,_,_,_,_,_,_,eligible,_}}: eligible
def startup(context: ThemeContext,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Interactive.StatusSink,stopped: Deferred.Deferred<Unit>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>,error: Ref.Ref<Maybe<&2,Theme.LoadError>>) -> ThemeStartup:
  match context:
    case ThemeContext{theme,transcript,session,setting,builtinDir,customDir,interaction,_,mode,_,_,_,highlighter,_}:
      ThemeStartup{redraw,queue,initial,failure,stopped,selected,owned,error,theme,transcript,session,setting,builtinDir,customDir,managedOf(mode),interaction,highlighter}
def selectionTheme(value: ThemeController.Selection) -> Theme.Theme:
  match value: case ThemeController.Selection{_,_,_,theme,_,_,_}: theme
def syncSelected(live: ThemeLive,handle: ThemeController.Handle) -> IO(Unit):
  match live:
    case ThemeLive{_,theme,transcript,_}:
      do IO<Unit>:
        chosenSelection : ThemeController.Selection <- ThemeController.current(handle)
        +chosen : Theme.Theme <- IO.pure(Theme.Theme,selectionTheme(chosenSelection))
        Ref.write(Theme.Theme,theme,chosen)
        Transcript.retheme(transcript,chosen)
def syncCurrent(live: ThemeLive,current: Maybe<&2,ThemeController.Handle>) -> IO(Unit):
  match current:
    case Some{handle}: syncSelected(live,handle)
    case None{}: IO.pure(Unit,Unit{})
def syncRender(live: ThemeLive,_: Unit) -> IO(Unit):
  match live:
    case ThemeLive{+selected,+theme,+transcript,+requestRender}:
      do IO<Unit>:
        current : Maybe<&2,ThemeController.Handle> <- Ref.read(Maybe<&2,ThemeController.Handle>,selected)
        syncCurrent(ThemeLive{selected,theme,transcript,requestRender},current)
        Callback.call(Unit,Unit,requestRender,Unit{})
def startInput(handle: ThemeController.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Interactive.StatusSink,render: Callback.Callback<Unit,Unit>) -> IO(Unit):
  match handle:
    case ThemeController.Handle{_,Process.QueryReady{queries,terminal,write,_,preference},_,_,_,_}:
      Interactive.onReady(Interactive.Startup{redraw,queue,initial,failure},Process.QueryReady{queries,terminal,write,render,preference})
type ManagedSink is Data:
  ManagedSink{transcript: Transcript.Handle,render: Callback.Callback<Unit,Unit>,started: Ref.Ref<Bool>}
def managedWarning(kind: Manager.ToolStatusType) -> Bool:
  match kind:
    case Manager.Warning{}: True{}
    case Manager.Info{}: False{}
def managedText(warning: Bool,message: String) -> String:
  match warning:
    case True{}: "Warning: " ++ message
    case False{}: message
# upstream showManagedToolStatus: a spacer before the first status line only.
def managedReported(sink: ManagedSink,status: Manager.ToolStatus) -> IO(Unit):
  match sink status:
    case ManagedSink{transcript,render,started} Manager.ToolStatus{kind,message}:
      do IO<Unit>:
        previous : Bool <- Ref.swap(Bool,started,True{})
        +warning : Bool <- IO.pure(Bool,managedWarning(kind))
        +text : String <- IO.pure(String,managedText(warning,message))
        Transcript.managedStatus(transcript,text,warning,Bool.not(previous))
        Callback.call(Unit,Unit,render,Unit{})
def ensureManagedOne(managed: Manager.ToolsManager,tool: Manager.Tool,status: Callback.Callback<Manager.ToolStatus,Unit>) -> IO(Bool):
  do IO<Bool>:
    path : Maybe<&2,String> <- Manager.ensureTool(managed,tool,Some{status})
    return Maybe.is_some(&2,String,path)
def setupManaged(managed: Maybe<&2,Manager.ToolsManager>,transcript: Transcript.Handle,render: Callback.Callback<Unit,Unit>) -> IO(Bool):
  match managed:
    case None{}: IO.pure(Bool,False{})
    case Some{+manager}:
      do IO<Bool>:
        +started : Ref.Ref<Bool> <- Ref.new(Bool,False{})
        +status : Callback.Callback<Manager.ToolStatus,Unit> <- Callback.create(~ManagedSink,~Manager.ToolStatus,~Unit,~managedReported,ManagedSink{transcript,render,started})
        fd : Bool <- ensureManagedOne(manager,Manager.Fd{},status)
        rg : Bool <- ensureManagedOne(manager,Manager.Rg{},status)
        Callback.dispose(Manager.ToolStatus,Unit,status)
        wasStarted : Bool <- Ref.dispose(Bool,started)
        return fd
# upstream getChangelogForDisplay/showStartupNoticesIfNeeded: a fresh install
# records the version silently; after an update the new entries are shown
# (condensed when collapseChangelog is set). Resumed sessions show nothing.
def firstVersion(entries: List<&2,Changelog.ChangelogEntry>) -> String:
  match entries:
    case Changelog.ChangelogEntry{major,minor,patch,_} <> _: Changelog.entryVersion(Changelog.ChangelogEntry{major,minor,patch,""})
    case Nil{}: Config.version()
def latestVersion(markdown: String) -> String: firstVersion(Changelog.parseChangelogText(markdown))
def whatsNew(collapse: Bool,+markdown: String) -> MessageUI.Changelog:
  match collapse:
    case True{}: MessageUI.UpdatedTo{latestVersion(markdown),False{}}
    case False{}: MessageUI.WhatsNew{Text.trim(markdown),False{}}
def showNewEntries(transcript: Transcript.Handle,session: Session.AgentSession,+settings: Settings.SettingsManager,entries: List<&2,Changelog.ChangelogEntry>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case entries:
      do IO<Unit>:
        recorded : Result<&2,&2,String,Unit> <- Session.changeSettings(session,current => Settings.setLastChangelogVersion(Config.version(),current))
        Transcript.changelog(transcript,whatsNew(Settings.getCollapseChangelog(settings),String.join(linkedEntries(entries),"\n\n")))
def changelogSince(transcript: Transcript.Handle,+session: Session.AgentSession,+settings: Settings.SettingsManager,last: Maybe<&2,String>,builtinDir: String) -> IO(Unit):
  match last:
    case None{}:
      do IO<Unit>:
        recorded : Result<&2,&2,String,Unit> <- Session.changeSettings(session,current => Settings.setLastChangelogVersion(Config.version(),current))
        return Unit{}
    case Some{version}:
      do IO<Unit>:
        entries : List<&2,Changelog.ChangelogEntry> <- Changelog.parseChangelog(changelogPath(builtinDir))
        showNewEntries(transcript,session,settings,Changelog.getNewEntries(entries,version))
def changelogFor(transcript: Transcript.Handle,+session: Session.AgentSession,resumed: Bool,builtinDir: String) -> IO(Unit):
  match resumed:
    case True{}: IO.pure(Unit,Unit{})
    case False{}:
      do IO<Unit>:
        +settings : Settings.SettingsManager <- Session.getSettings(session)
        changelogSince(transcript,session,settings,Settings.getLastChangelogVersion(settings),builtinDir)
def startupChangelog(transcript: Transcript.Handle,session: Ref.Ref<Session.AgentSession>,builtinDir: String) -> IO(Unit):
  do IO<Unit>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    messages : List<&2,Session.Message()> <- Session.messages(live)
    changelogFor(transcript,live,Bool.not(List.is_empty(&2,Session.Message(),messages)),builtinDir)
def sessionCwd(session: Session.AgentSession) -> String:
  match session:
    case Session.AgentSession{_,_,_,_,cwd,_,_,_}: cwd
def startupProjectTrustWarning(transcript: Transcript.Handle,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  do IO<Unit>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    cwd : String <- IO.pure(String,sessionCwd(live))
    settings : Settings.SettingsManager <- Session.getSettings(live)
    home : Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
    resources : Bool <- Trust.hasTrustRequiringProjectResources(cwd,environmentValue(home))
    Bool.pick(Unit -> IO(Unit),resources && Bool.not(Settings.isProjectTrusted(settings)),
      _ => Transcript.showProjectTrustWarning(transcript,"This project is not trusted. Project .pi resources and packages are ignored. Use /trust to save a trust decision, then restart pi."),
      _ => IO.pure(Unit,Unit{}))(Unit{})
# upstream: after fd and rg setup, the session rebinds and builds the
# autocomplete provider with the resolved fd path.
def startAutocomplete(interaction: Interaction,session: Ref.Ref<Session.AgentSession>,found: Bool) -> IO(Unit):
  match interaction:
    case Interaction{editor,_,_,_,_,_,_,_,_,_,_,_,+autocomplete}:
      do IO<Unit>:
        Ref.write(Bool,autocompleteFiles(autocomplete),found)
        setupAutocomplete(autocomplete,editor,session)
def installSettingsTheme(current: Maybe<&2,SettingsPicker.Host>,handle: ThemeController.Handle) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: SettingsPicker.installController(host,handle)
def connectSettingsTheme(interaction: Interaction,handle: ThemeController.Handle) -> IO(Unit):
  match interaction:
    case Interaction{_,_,_,_,_,_,_,settings,_,_,_,_,_}:
      do IO<Unit>:
        current : Maybe<&2,SettingsPicker.Host> <- Ref.read(Maybe<&2,SettingsPicker.Host>,settings)
        installSettingsTheme(current,handle)
def readySelected(result: Result<&2,&1,Theme.LoadError,ThemeController.Owner & ThemeController.Handle>,startup: ThemeStartup,+render: Callback.Callback<Unit,Unit>) -> IO(Unit):
  match result startup:
    case Done{(controller,+handle)} ThemeStartup{redraw,queue,initial,failure,_,+selected,owned,_,theme,+transcript,+session,_,builtinDir,_,managed,+interaction,highlighter}:
      do IO<Unit>:
        Ref.write(Maybe<&2,ThemeController.Handle>,selected,Some{handle})
        connectSettingsTheme(interaction,handle)
        Ref.write(Maybe<&1,ThemeOwned>,owned,Some{ThemeOwned{controller,render}})
        syncSelected(ThemeLive{selected,theme,transcript,render},handle)
        files : Bool <- setupManaged(managed,transcript,render)
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        existing : List<&2,Session.Message()> <- Session.messages(live)
        Transcript.seedSession(transcript,existing)
        startAutocomplete(interaction,session,files)
        startupProjectTrustWarning(transcript,session)
        startupChangelog(transcript,session,builtinDir)
        # upstream init: once startup is rendered, register the remaining
        # highlight.js languages, then invalidate and render again.
        SyntaxHighlight.loadAllHighlightLanguages(highlighter)
        Transcript.invalidate(transcript)
        Callback.call(Unit,Unit,render,Unit{})
        startInput(handle,redraw,queue,initial,failure,render)
    case Fail{cause} ThemeStartup{_,_,_,_,stopped,_,_,error,_,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        Callback.dispose(Unit,Unit,render)
        Ref.write(Maybe<&2,Theme.LoadError>,error,Some{cause})
        settled : Bool <- Deferred.resolve(Unit,stopped,Unit{})
        return Unit{}
def themeReady(startup: ThemeStartup,ready: Process.QueryReady) -> IO(Unit):
  match startup ready:
    case ThemeStartup{redraw,queue,initial,failure,stopped,+selected,owned,error,+theme,+transcript,+session,+setting,+builtinDir,+customDir,+managed,+interaction,highlighter} Process.QueryReady{queries,terminal,write,requestRender,preference}:
      do IO<Unit>:
        +render : Callback.Callback<Unit,Unit> <- Callback.create(~ThemeLive,~Unit,~Unit,~syncRender,ThemeLive{selected,theme,transcript,requestRender})
        detected : Result<&1,&1,U32 & String,String> <- IO.get_env("COLORFGBG")
        initialTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        result : Result<&2,&1,Theme.LoadError,ThemeController.Owner & ThemeController.Handle> <- ThemeController.start(Process.QueryReady{queries,terminal,write,render,preference},setting,environmentValue(detected),builtinDir,customDir,Theme.colorMode(initialTheme))
        readySelected(result,ThemeStartup{redraw,queue,initial,failure,stopped,selected,owned,error,theme,transcript,session,setting,builtinDir,customDir,managed,interaction,highlighter},render)
def closeTheme(current: Maybe<&1,ThemeOwned>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ThemeOwned{controller,render}}:
      do IO<Unit>:
        ThemeController.close(controller)
        Callback.dispose(Unit,Unit,render)
def hasSessionMessages(messages: List<&2,Session.Message()>) -> Bool:
  match messages:
    case Nil{}: False{}
    case _ <> _: True{}
def prepareFullscreenExit(screen: Process.ScreenState,view: View.Handle,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match screen:
    case Process.Main{_}: IO.pure(Unit,Unit{})
    case Process.Fullscreen{_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        messages : List<&2,Session.Message()> <- Session.messages(live)
        View.prepareExit(view,hasSessionMessages(messages))
def themeStopping(stopping: ThemeStopping,_: Unit) -> IO(Unit):
  match stopping:
    case ThemeStopping{redraw,selected,owned,view,screen,session}:
      do IO<Unit>:
        prepareFullscreenExit(screen,view,session)
        Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,None{})
        Ref.write(Maybe<&2,ThemeController.Handle>,selected,None{})
        current : Maybe<&1,ThemeOwned> <- Ref.swap(Maybe<&1,ThemeOwned>,owned,None{})
        closeTheme(current)

def processResult(result: Result<&2,&2,Terminal.Error,Process.Active>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{cause}: Fail{TerminalStart{cause}}
def processThemeResult(result: Result<&2,&2,Terminal.Error,Process.Active>,failure: Maybe<&2,Theme.LoadError>) -> Result<&2,&2,Error,Unit>:
  match failure:
    case None{}: processResult(result)
    case Some{cause}: Fail{ThemeData{cause}}
def configuredTui(base: Tui.TuiBase,session: Ref.Ref<Session.AgentSession>) -> IO(Tui.TuiBase):
  do IO<Tui.TuiBase>:
    live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    +settings : Settings.SettingsManager <- Session.getSettings(live)
    hardwareEnv : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_HARDWARE_CURSOR")
    clearEnv : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_CLEAR_ON_SHRINK")
    hardwareFallback : Bool <- IO.pure(Bool,String.eq(Maybe.default(&2,String,environmentValue(hardwareEnv),""),"1"))
    clearFallback : Bool <- IO.pure(Bool,String.eq(Maybe.default(&2,String,environmentValue(clearEnv),""),"1"))
    show : Bool <- IO.pure(Bool,Maybe.default(&2,Bool,Settings.selectedShowHardwareCursor(Settings.get(Settings.effective(settings),"showHardwareCursor")),hardwareFallback))
    return Tui.setTerminalPreferences(base,show,Settings.resolvedClearOnShrink(Settings.terminalOptions(settings),clearFallback))
type IndicatorStyle is Data: IndicatorStyle{theme: Ref.Ref<Theme.Theme>,bindings: Keybindings.KeybindingsManager}
def styledIndicator(+current: Theme.Theme,bindings: Keybindings.KeybindingsManager) -> String:
  +shortcut = Hints.keyDisplayText(bindings,"tui.altScreen.bottom")
  +text = " ↓ Jump to latest message" ++ Bool.pick(String,String.is_empty(shortcut),""," · " ++ shortcut) ++ " "
  +foreground = Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,"text",text),text)
  Result.default(&2,&2,Theme.Error,String,Theme.background(current,"selectedBg",foreground),foreground)
def indicatorText(style: IndicatorStyle,_: Unit) -> IO(String):
  match style:
    case IndicatorStyle{theme,bindings}:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return styledIndicator(current,bindings)
def searchPalette(theme: Ref.Ref<Theme.Theme>,_: Unit) -> IO(AltSearch.Styles):
  do IO<AltSearch.Styles>:
    +current : Theme.Theme <- Ref.read(Theme.Theme,theme)
    return AltSearch.Styles{Theme.foregroundCode(current,"searchMatchText"),Theme.backgroundCode(current,"searchMatchBg")}
def screenForMode(mode: Settings.TuiMode,indicator: Callback.Callback<Unit,String>,bindings: Ref.Ref<Keybindings.KeybindingsManager>,styles: Callback.Callback<Unit,AltSearch.Styles>) -> Process.ScreenState:
  match mode:
    case Settings.Regular{}: Process.Main{Screen.initial()}
    case Settings.Fullscreen{}: Process.Fullscreen{AltScreen.initial(indicator,bindings,styles)}
def tuiModeOverride(binding: Maybe<&2,Binding>) -> Maybe<&2,Settings.TuiMode>:
  match binding:
    case None{}: None{}
    case Some{Binding{_,_,_,_,_,_,_,_,_,_,mode}}: mode
def configuredScreen(session: Ref.Ref<Session.AgentSession>,override: Maybe<&2,Settings.TuiMode>,indicator: Callback.Callback<Unit,String>,bindings: Ref.Ref<Keybindings.KeybindingsManager>,styles: Callback.Callback<Unit,AltSearch.Styles>) -> IO(Process.ScreenState):
  do IO<Process.ScreenState>:
    live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    +settings : Settings.SettingsManager <- Session.getSettings(live)
    return screenForMode(Maybe.default(&2,Settings.TuiMode,override,Settings.getTuiMode(settings)),indicator,bindings,styles)
def processMounted(mounted: View.View & View.Handle & Tui.ResultOf(Tui.TuiBase),document: Component.Component,editorComponent: Component.Component,+foot: FooterOwner,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+screen: Process.ScreenState,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match mounted:
    case (view,_,Fail{cause}): IO.pure(View.View & Result<&2,&2,Error,Unit>,(view,Fail{Layout{cause}}))
    case (view,viewHandle,Done{base}):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        +selected : Ref.Ref<Maybe<&2,ThemeController.Handle>> <- Ref.new(Maybe<&2,ThemeController.Handle>,None{})
        +owned : Ref.Ref<Maybe<&1,ThemeOwned>> <- Ref.new(Maybe<&1,ThemeOwned>,None{})
        +error : Ref.Ref<Maybe<&2,Theme.LoadError>> <- Ref.new(Maybe<&2,Theme.LoadError>,None{})
        +ready : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~ThemeStartup,~Process.QueryReady,~Unit,~themeReady,startup(context,redraw,queue,initial,contextStatus(context),stopped,selected,owned,error))
        +stopping : Callback.Callback<Unit,Unit> <- Callback.create(~ThemeStopping,~Unit,~Unit,~themeStopping,ThemeStopping{redraw,selected,owned,viewHandle,screen,contextSession(context)})
        +ids : List<&2,Component.ComponentId> <- IO.pure(List<&2,Component.ComponentId>,Component.ComponentId{1n} <> Component.ComponentId{2n} <> Component.ComponentId{3n} <> Nil{})
        +components : List<&2,Component.Component> <- IO.pure(List<&2,Component.Component>,document <> editorComponent <> footerComponent(foot) <> Nil{})
        configured : Tui.TuiBase <- configuredTui(base,contextSession(context))
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{configured,screen},components,ids),stopped,False{},ready,stopping)
        Callback.dispose(Process.QueryReady,Unit,ready)
        Callback.dispose(Unit,Unit,stopping)
        oldSelected : Maybe<&2,ThemeController.Handle> <- Ref.dispose(Maybe<&2,ThemeController.Handle>,selected)
        oldOwned : Maybe<&1,ThemeOwned> <- Ref.dispose(Maybe<&1,ThemeOwned>,owned)
        failure : Maybe<&2,Theme.LoadError> <- Ref.dispose(Maybe<&2,Theme.LoadError>,error)
        return (view,processThemeResult(outcome,failure))

def fullscreenScreen(screen: Process.ScreenState) -> Bool:
  match screen:
    case Process.Main{_}: False{}
    case Process.Fullscreen{_}: True{}
def processEditorBorrowed(borrowed: View.View & Component.Component & View.Handle,+editorComponent: Component.Component,+foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,document,_):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        +indicator : Callback.Callback<Unit,String> <- Callback.create(~IndicatorStyle,~Unit,~String,~indicatorText,IndicatorStyle{contextTheme(context),contextBindings(context)})
        +searchStyles : Callback.Callback<Unit,AltSearch.Styles> <- Callback.create(~Ref.Ref<Theme.Theme>,~Unit,~AltSearch.Styles,~searchPalette,contextTheme(context))
        +viewportBindings : Ref.Ref<Keybindings.KeybindingsManager> <- Ref.new(Keybindings.KeybindingsManager,contextBindings(context))
        +screen : Process.ScreenState <- configuredScreen(contextSession(context),tuiModeOverride(contextBinding(context)),indicator,viewportBindings,searchStyles)
        mounted : View.View & View.Handle & Tui.ResultOf(Tui.TuiBase) <- View.mountFor(view,editorComponent,footerComponent(foot),fullscreenScreen(screen))
        outcome : View.View & Result<&2,&2,Error,Unit> <- processMounted(mounted,document,editorComponent,foot,stopped,redraw,queue,initial,screen,context)
        oldBindings : Keybindings.KeybindingsManager <- Ref.dispose(Keybindings.KeybindingsManager,viewportBindings)
        Callback.dispose(Unit,AltSearch.Styles,searchStyles)
        Callback.dispose(Unit,String,indicator)
        return outcome
def processEditor(view: View.View,editorComponent: Component.Component,foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  processEditorBorrowed(View.borrow(view),editorComponent,foot,stopped,redraw,queue,initial,context)
def process(view: View.View,editor: Component.Component,foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  processEditor(view,editor,foot,stopped,redraw,queue,initial,context)
def markBashClosing(state: BashActivity) -> BashActivity & Maybe<&2,Deferred.Deferred<Unit>>:
  match state:
    case BashActivity{active,_,+completion}: (BashActivity{active,True{},completion},completion)
def awaitBashCompletion(completion: Maybe<&2,Deferred.Deferred<Unit>>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match completion:
    case None{}: IO.pure(Unit,Unit{})
    case Some{done}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        Session.abortBash(live)
        completed : Unit <- Deferred.result(Unit,done)
        return Unit{}
def awaitBash(activity: Ref.Ref<BashActivity>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  do IO<Unit>:
    completion : Maybe<&2,Deferred.Deferred<Unit>> <- Ref.modify(BashActivity,Maybe<&2,Deferred.Deferred<Unit>>,activity,markBashClosing)
    awaitBashCompletion(completion,session)
def finish(outcome: View.View & Result<&2,&2,Error,Unit>,transcript: Transcript.Owner,live: Live.Owner,foot: FooterOwner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,stopped: Deferred.Deferred<Unit>,+interaction: Interaction,+session: Ref.Ref<Session.AgentSession>,+mode: Maybe<&2,Binding>,+login: LoginState) -> IO(Result<&2,&2,Error,Unit>):
  match outcome:
    case (view,result):
      do IO<Result<&2,&2,Error,Unit>>:
        awaitBash(bashActivityOf(interaction),session)
        unbind(mode)
        Transcript.dispose(transcript)
        View.dispose(view)
        Live.dispose(live)
        disposeInteraction(interaction)
        disposeFooter(foot)
        Callback.dispose(String,Unit,submitted)
        Callback.dispose(CustomEditor.AppAction,Unit,keys)
        Callback.dispose(String,String,paint)
        MarkdownTheme.dispose(styles)
        oldRows : Nat <- Ref.dispose(Nat,rows)
        oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
        Deferred.dispose(Unit,stopped)
        disposeLoginState(login)
        finishSessionRef(session,mode)
        return result

def setLoginHost(state: LoginState,value: Maybe<&2,LoginDialog.Host>) -> IO(Unit):
  match state: case LoginState{target,_,_,_,_,_,_,_,_}: Ref.write(Maybe<&2,LoginDialog.Host>,target,value)
def runLoginHosted(borrowed: LoginDialog.Owner & LoginDialog.Host & Component.Component,view: View.View,+foot: FooterOwner,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,controller: Controller.Controller,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match borrowed:
    case (retained,host,component):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        setLoginHost(contextLogin(context),Some{host})
        outcome : View.View & Result<&2,&2,Error,Unit> <- process(view,component,foot,stopped,redraw,queue,initial,context)
        cancelLogin(contextLogin(context),Unit{})
        Controller.stop(controller)
        setLoginHost(contextLogin(context),None{})
        LoginDialog.dispose(retained)
        return outcome
def runPickerHosted(borrowed: SessionPicker.HostOwner & SessionPicker.Host & Component.Component,settings: SettingsPicker.Owner,retained: ModelPicker.Owner,tree: Selector.Owner,live: Live.Owner,words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<ModelPicker.Choice,Unit>,resumeChosen: Callback.Callback<String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (picker,pickerHost,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)),Some{pickerHost})
        +cancel : Callback.Callback<Unit,Unit> <- Callback.create(~LoginState,~Unit,~Unit,~cancelLogin,contextLogin(context))
        dialog : LoginDialog.Owner <- LoginDialog.create(component,contextTheme(context),words,contextBindings(context),Keys.defaults(),cancel)
        outcome : View.View & Result<&2,&2,Error,Unit> <- runLoginHosted(LoginDialog.borrow(dialog),view,foot,stopped,redraw,queue,controller,initial,context)
        Callback.dispose(Unit,Unit,cancel)
        Ref.write(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)),None{})
        SessionPicker.disposeHost(picker)
        Callback.dispose(String,Unit,resumeChosen)
        oldPicker : Maybe<&2,SessionPicker.Host> <- Ref.dispose(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)))
        Ref.write(Maybe<&2,SettingsPicker.Host>,settingsSelectorRefOf(contextInteraction(context)),None{})
        SettingsPicker.disposeHost(settings)
        Ref.write(Maybe<&2,ModelPicker.Host>,modelSelectorRefOf(contextInteraction(context)),None{})
        Ref.write(Maybe<&2,Selector.Host>,selectorRefOf(contextInteraction(context)),None{})
        ModelPicker.disposeHost(retained)
        Selector.disposeHost(tree)
        Callback.dispose(ModelPicker.Choice,Unit,modelChosen)
        Callback.dispose(Selector.Choice,Unit,treeChosen)
        finish(outcome,transcript,live,foot,submitted,keys,paint,styles,rows,redraw,stopped,contextInteraction(context),contextSession(context),contextBinding(context),contextLogin(context))
def runTrustHosted(borrowed: TrustPicker.Owner & TrustPicker.Host & Component.Component,choice: Callback.Callback<Trust.ProjectTrustOption,Unit>,settings: SettingsPicker.Owner,retained: ModelPicker.Owner,tree: Selector.Owner,live: Live.Owner,+words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<ModelPicker.Choice,Unit>,+resumeChosen: Callback.Callback<String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (trust,host,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,TrustPicker.Host>,trustSelectorRefOf(contextInteraction(context)),Some{host})
        current : Session.AgentSession <- Ref.read(Session.AgentSession,contextSession(context))
        ids : Uuid.Generator <- Session.idGenerator(current)
        picker : SessionPicker.HostOwner <- SessionPicker.createHost(ids,component,contextBindings(context),contextTheme(context),words,resumeChosen)
        result : Result<&2,&2,Error,Unit> <- runPickerHosted(SessionPicker.borrowHost(picker),settings,retained,tree,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,modelChosen,resumeChosen)
        TrustPicker.disposeHost(trust)
        Callback.dispose(Trust.ProjectTrustOption,Unit,choice)
        return result
def runSettingsHosted(borrowed: SettingsPicker.Owner & SettingsPicker.Host & Component.Component,retained: ModelPicker.Owner,tree: Selector.Owner,live: Live.Owner,words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<ModelPicker.Choice,Unit>,+resumeChosen: Callback.Callback<String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (settings,host,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,SettingsPicker.Host>,settingsSelectorRefOf(contextInteraction(context)),Some{host})
        +choice : Callback.Callback<Trust.ProjectTrustOption,Unit> <- Callback.create(~TrustChoiceInput,~Trust.ProjectTrustOption,~Unit,~trustChosen,TrustChoiceInput{Trust.create(contextAgentDir(context)),contextTranscript(context)})
        trust : TrustPicker.Owner <- TrustPicker.createHost(component,contextTheme(context),contextBindings(context),Keys.defaults(),choice)
        runTrustHosted(TrustPicker.borrowHost(trust),choice,settings,retained,tree,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,modelChosen,resumeChosen)
def runModelHosted(borrowed: ModelPicker.Owner & ModelPicker.Host & Component.Component,tree: Selector.Owner,treeHandle: Selector.Host,live: Live.Owner,+words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<ModelPicker.Choice,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (retained,modelHandle,modal):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,Selector.Host>,selectorRefOf(contextInteraction(context)),Some{treeHandle})
        Ref.write(Maybe<&2,ModelPicker.Host>,modelSelectorRefOf(contextInteraction(context)),Some{modelHandle})
        +resumeChosen : Callback.Callback<String,Unit> <- Callback.create(~ResumeState,~String,~Unit,~resumePicked,contextResume(context))
        settings : SettingsPicker.Owner <- SettingsPicker.createHost(modal,contextTheme(context),contextSession(context),contextModels(context),contextTranscript(context),editorRefOf(contextInteraction(context)),words,contextBindings(context),Keys.defaults(),redraw)
        runSettingsHosted(SettingsPicker.borrowHost(settings),retained,tree,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,modelChosen,resumeChosen)
def runThinkingHosted(borrowed: ThinkingPicker.Owner & ThinkingPicker.Host & Component.Component,tree: Selector.Owner,treeHandle: Selector.Host,live: Live.Owner,words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,thinkingChosen: Callback.Callback<ThinkingPicker.Choice,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (thinking,thinkingHandle,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,ThinkingPicker.Host>,thinkingSelectorRefOf(contextInteraction(context)),Some{thinkingHandle})
        +modelChosen : Callback.Callback<ModelPicker.Choice,Unit> <- Callback.create(~SelectInput,~ModelPicker.Choice,~Unit,~chosenModel,SelectInput{queue,contextStatus(context),redraw})
        modelHost : ModelPicker.Owner <- ModelPicker.createHost(component,contextTheme(context),contextBindings(context),Keys.defaults(),modelChosen)
        result : Result<&2,&2,Error,Unit> <- runModelHosted(ModelPicker.borrowHost(modelHost),tree,treeHandle,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,modelChosen)
        ThinkingPicker.disposeHost(thinking)
        Callback.dispose(ThinkingPicker.Choice,Unit,thinkingChosen)
        return result
def runScopeHosted(borrowed: ScopePicker.Owner & ScopePicker.Host & Component.Component,tree: Selector.Owner,treeHandle: Selector.Host,live: Live.Owner,+words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,scopeChosen: Callback.Callback<ScopePicker.Action,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (scoped,scopedHandle,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,ScopePicker.Host>,scopedSelectorRefOf(contextInteraction(context)),Some{scopedHandle})
        +thinkingChosen : Callback.Callback<ThinkingPicker.Choice,Unit> <- Callback.create(~SelectInput,~ThinkingPicker.Choice,~Unit,~chosenThinking,SelectInput{queue,contextStatus(context),redraw})
        host : ThinkingPicker.Owner <- ThinkingPicker.createHost(component,contextTheme(context),words,contextBindings(context),Keys.defaults(),thinkingChosen)
        result : Result<&2,&2,Error,Unit> <- runThinkingHosted(ThinkingPicker.borrowHost(host),tree,treeHandle,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,thinkingChosen)
        ScopePicker.disposeHost(scoped)
        Callback.dispose(ScopePicker.Action,Unit,scopeChosen)
        return result
def runHosted(borrowed: Selector.Owner & Selector.Host & Component.Component,live: Live.Owner,+words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,chosen: Callback.Callback<Selector.Choice,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (tree,treeHandle,component):
      do IO<Result<&2,&2,Error,Unit>>:
        +scopeChosen : Callback.Callback<ScopePicker.Action,Unit> <- Callback.create(~ScopeInput,~ScopePicker.Action,~Unit,~scopeAction,ScopeInput{contextSession(context),contextModels(context),contextStatus(context),redraw})
        host : ScopePicker.Owner <- ScopePicker.createHost(component,contextTheme(context),words,contextBindings(context),Keys.defaults(),scopeChosen)
        runScopeHosted(ScopePicker.borrowHost(host),tree,treeHandle,live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,chosen,scopeChosen)
def withCustomEditor(borrowed: CustomEditor.Owner & Component.Component,live: Live.Owner,words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (custom,component):
      do IO<Result<&2,&2,Error,Unit>>:
        +chosen : Callback.Callback<Selector.Choice,Unit> <- Callback.create(~SelectInput,~Selector.Choice,~Unit,~chosenSelection,SelectInput{queue,contextStatus(context),redraw})
        host : Selector.Owner <- Selector.createHost(component,contextTheme(context),contextBindings(context),Keys.defaults(),chosen)
        result : Result<&2,&2,Error,Unit> <- runHosted(Selector.borrowHost(host),live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,chosen)
        CustomEditor.dispose(custom)
        return result
def runLive(borrowed: Live.Owner & Component.Component & Live.Handle,words: Words.Source,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,+keys: Callback.Callback<CustomEditor.AppAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (live,editorComponent,handle):
      do IO<Result<&2,&2,Error,Unit>>:
        +editor : Live.Handle <- IO.pure(Live.Handle,handle)
        recordEditor(contextInteraction(context),editor)
        custom : CustomEditor.Owner <- CustomEditor.create(CustomEditor.Host{editor,editorComponent,contextBindings(context),Keys.defaults(),APP_ACTIONS(),keys})
        withCustomEditor(CustomEditor.borrow(custom),live,words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context)
def smallCount(value: W.U64) -> Nat:
  match value: case W.U64{_,low}: U32.to_nat(low)
def outputPad(value: Settings.OutputPadding) -> Nat:
  match value:
    case Settings.NoPadding{}: 0n
    case Settings.OnePadding{}: 1n
def loadedBindings(result: Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager>,transcript: Transcript.Handle) -> IO(Keybindings.KeybindingsManager):
  match result:
    case Done{AppKeys.KeybindingsManager{bindings,_,_}}: IO.pure(Keybindings.KeybindingsManager,bindings)
    case Fail{_}:
      do IO<Keybindings.KeybindingsManager>:
        Transcript.showError(transcript,"Cannot load keybindings.json; using default shortcuts")
        return Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>))
def updateHeaderBindings(handle: Maybe<&2,Header.Handle>,bindings: Keybindings.KeybindingsManager) -> IO(Unit):
  match handle:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: Header.setBindings(ready,bindings)
# The editor's requestRender: asynchronous autocomplete results repaint.
def editorRenderRequested(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,unit: Unit) -> IO(Unit): Interactive.requestRender(redraw)
def startPaint(pair: Callback.Callback<String,String> & Editor.EditorTheme,changed: Callback.Callback<String,Unit>,controller: Controller.Controller,+queue: Controller.Handle,+submitted: Callback.Callback<String,Unit>,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,+foot: FooterOwner,+words: Words.Source,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (+paint,uiTheme):
      do IO<Result<&2,&2,Error,Unit>>:
        editor : Editor.Editor <- Editor.new(uiTheme,None{})
        session : Session.AgentSession <- Ref.read(Session.AgentSession,contextSession(context))
        +settings : Settings.SettingsManager <- Session.getSettings(session)
        padded : Editor.Editor <- Editor.setPaddingX(editor,smallCount(Settings.getEditorPaddingX(settings)))
        configuredEditor : Editor.Editor <- Editor.setAutocompleteMaxVisible(padded,smallCount(Settings.getAutocompleteMaxVisible(settings)))
        +keys : Callback.Callback<CustomEditor.AppAction,Unit> <- Callback.create(~KeyInput,~CustomEditor.AppAction,~Unit,~keyAction,keyInput(queue,stopped,contextStatus(context),contextInteraction(context),contextSession(context),redraw,contextTranscript(context),contextModels(context)))
        requested : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,~Unit,~Unit,~editorRenderRequested,redraw)
        +configured : Editor.Editor <- IO.pure(Editor.Editor,Editor.setCallbacks(configuredEditor,Editor.EditorCallbacks{Some{changed},Some{submitted},Some{requested}}))
        +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
        +working : Working <- IO.pure(Working,workingOf(contextInteraction(context)))
        setupWorking(working,paint,contextTheme(context),contextBindings(context),redraw)
        live : Live.Owner <- Live.createWithWorking(Component.ComponentId{2n},configured,words,contextBindings(context),Keys.defaults(),rows,workingActive(working))
        runLive(Live.borrow(live),words,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context)
def startController(pair: Controller.Controller & Controller.Handle,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,+foot: FooterOwner,words: Words.Source,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (controller,+queue):
      do IO<Result<&2,&2,Error,Unit>>:
        submitted : Callback.Callback<String,Unit> <- Callback.create(~Interactive.SubmissionInput,~String,~Unit,~Interactive.submitted,Interactive.SubmissionInput{queue,stopped,contextStatus(context)})
        +paint : Callback.Callback<String,String> <- editorTheme(contextTheme(context))
        +muted : Callback.Callback<String,String> <- MarkdownTheme.color(contextTheme(context),"muted")
        +bash : Ref.Ref<Bool> <- Ref.new(Bool,False{})
        +border : Callback.Callback<String,String> <- Callback.create(~BorderStyle,~String,~String,~paintBorder,BorderStyle{contextTheme(context),contextSession(context),bash})
        +changed : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<Bool>,~String,~Unit,~bashModeChanged,bash)
        result : Result<&2,&2,Error,Unit> <- startPaint((paint,Editor.EditorTheme{border,Select.SelectListTheme{paint,paint,muted,muted,muted}}),changed,controller,queue,submitted,view,transcript,styles,initial,foot,words,stopped,redraw,context)
        Callback.dispose(String,String,border)
        Callback.dispose(String,Unit,changed)
        oldBash : Bool <- Ref.dispose(Bool,bash)
        return result
# Upstream prints scoped models before the UI starts, using the configured cycle key.
def scopedLabel(scoped: Models.ScopedModel) -> String:
  match scoped:
    case Models.ScopedModel{selected,thinking}: Models.modelId(selected) ++ Maybe.default(&2,String,Maybe.map(&2,Ai.ModelThinkingLevel,String,level => ":" ++ Levels.name(level),thinking),"")
def scopedLabels(scope: List<&2,Models.ScopedModel>) -> List<&2,String>:
  match scope:
    case Nil{}: Nil{}
    case scoped <> rest: scopedLabel(scoped) <> scopedLabels(rest)
def printModelScope(+theme: Theme.Theme,scope: List<&2,Models.ScopedModel>,quiet: Bool,bindings: Keybindings.KeybindingsManager) -> IO(Unit):
  match scope quiet:
    case Nil{} _: IO.pure(Unit,Unit{})
    case _ True{}: IO.pure(Unit,Unit{})
    case scope False{}:
      +hint = Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,"muted"," (" ++ Hints.keyDisplayText(bindings,"app.model.cycleForward") ++ " to cycle)"),"")
      IO.print(Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,"dim","Model scope: " ++ String.join(scopedLabels(scope),", ") ++ hint),""))
def startTranscript(borrowed: Transcript.Owner & Transcript.Handle,view: View.View,+viewHandle: View.Handle,styles: MarkdownTheme.Styles,highlighter: SyntaxHighlight.Highlighter,+liveTheme: Ref.Ref<Theme.Theme>,+session: Session.AgentSession,initial: List<&2,Controller.Submission>,+cwd: String,+home: Maybe<&2,String>,words: Words.Source,setting: Maybe<&2,String>,+builtinDir: String,+customDir: String,+models: List<&2,Models.Model()>,+mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (transcript,+transcriptHandle):
      do IO<Result<&2,&2,Error,Unit>>:
        +existing : List<&2,Session.Message()> <- Session.messages(session)
        +settings : Settings.SettingsManager <- Session.getSettings(session)
        loaded : Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager> <- AppKeys.create(AppKeys.Environment{"linux",None{},None{}},Path.normalize(customDir ++ "/.."))
        +bindings : Keybindings.KeybindingsManager <- loadedBindings(loaded,transcriptHandle)
        updateHeaderBindings(View.headerHandle(viewHandle),bindings)
        Transcript.setBindings(transcriptHandle,bindings)
        scope : List<&2,Models.ScopedModel> <- Session.getScopedModels(session)
        scopeTheme : Theme.Theme <- Ref.read(Theme.Theme,liveTheme)
        printModelScope(scopeTheme,scope,Settings.getQuietStartup(settings),bindings)
        Transcript.setHideThinking(transcriptHandle,Settings.getHideThinkingBlock(settings))
        Transcript.setOutputPad(transcriptHandle,outputPad(Settings.getOutputPad(settings)))
        agentState : Session.AgentState() <- Session.state(session)
        +current : Ref.Ref<Session.AgentSession> <- modeCurrent(mode,session)
        +foot : FooterOwner <- footer(initialFooter(agentState,existing,cwd,home,Settings.getCompactionEnabled(settings)),liveTheme,current)
        +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
        +status : Interactive.StatusSink <- IO.pure(Interactive.StatusSink,Interactive.StatusSink{transcriptHandle,redraw})
        +workingActiveRef : Ref.Ref<Maybe<&2,Loader.Handle>> <- Ref.new(Maybe<&2,Loader.Handle>,None{})
        +workingOwnerRef : Ref.Ref<Maybe<&1,WorkingOwned>> <- Ref.new(Maybe<&1,WorkingOwned>,None{})
        +working : Working <- IO.pure(Working,Working{workingActiveRef,workingOwnerRef})
        +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        +listener : Callback.Callback<Session.AgentSessionEvent,Unit> <- Callback.create(~Observation,~Session.AgentSessionEvent,~Unit,~observed,Observation{transcriptHandle,redraw,footerState(foot),working,current})
        failureObserver : Callback.Callback<Controller.PromptFailure,Unit> <- Callback.create(~WorkerFailure,~Controller.PromptFailure,~Unit,~promptFailed,WorkerFailure{status,redraw})
        +modelSelectorRef : Ref.Ref<Maybe<&2,ModelPicker.Host>> <- Ref.new(Maybe<&2,ModelPicker.Host>,None{})
        +thinkingSelectorRef : Ref.Ref<Maybe<&2,ThinkingPicker.Host>> <- Ref.new(Maybe<&2,ThinkingPicker.Host>,None{})
        +scopedSelectorRef : Ref.Ref<Maybe<&2,ScopePicker.Host>> <- Ref.new(Maybe<&2,ScopePicker.Host>,None{})
        +settingsSelectorRef : Ref.Ref<Maybe<&2,SettingsPicker.Host>> <- Ref.new(Maybe<&2,SettingsPicker.Host>,None{})
        +trustSelectorRef : Ref.Ref<Maybe<&2,TrustPicker.Host>> <- Ref.new(Maybe<&2,TrustPicker.Host>,None{})
        +selectorRef : Ref.Ref<Maybe<&2,Selector.Host>> <- Ref.new(Maybe<&2,Selector.Host>,None{})
        +modelsRef : Ref.Ref<List<&2,Models.Model()>> <- Ref.new(List<&2,Models.Model()>,models)
        +loginHost : Ref.Ref<Maybe<&2,LoginDialog.Host>> <- Ref.new(Maybe<&2,LoginDialog.Host>,None{})
        +resumePicker : Ref.Ref<Maybe<&2,SessionPicker.Host>> <- Ref.new(Maybe<&2,SessionPicker.Host>,None{})
        +loginAbort : Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>> <- Ref.new(Maybe<&2,Abort.AbortController<Unit>>,None{})
        +providerSort : Ref.Ref<ProviderSort> <- Ref.new(ProviderSort,PendingSort{Path.normalize(builtinDir ++ "/../../../../../runtime/data")})
        +loginState : LoginState <- IO.pure(LoginState,loginStateOf(mode,loginHost,loginAbort,modelsRef,status,redraw,current,providerSort))
        +resumeState : ResumeState <- IO.pure(ResumeState,resumeStateOf(mode,resumePicker,loginHost,status,redraw))
        loginCallback : Callback.Callback<Commands.CredentialCommand,Unit> <- Callback.create(~LoginState,~Commands.CredentialCommand,~Unit,~credentialRun,loginState)
        +commandSink : Interactive.CommandSink <- IO.pure(Interactive.CommandSink,Interactive.CommandSink{status,redraw,modelSelectorRef,thinkingSelectorRef,scopedSelectorRef,current,modelsRef})
        +editorHandle : Ref.Ref<Maybe<&2,Live.Handle>> <- Ref.new(Maybe<&2,Live.Handle>,None{})
        +bashActivity : Ref.Ref<BashActivity> <- Ref.new(BashActivity,BashActivity{False{},False{},None{}})
        +autocomplete : AutocompleteSlot <- autocompleteSlot(home,builtinDir)
        commandObserver : Callback.Callback<Commands.Action,Unit> <- Callback.create(~CommandObservation,~Commands.Action,~Unit,~commandObserved,CommandObservation{commandSink,current,footerState(foot),status,redraw,cwd,builtinDir,importStateOf(mode,loginHost,status,redraw),resumeState,selectorRef,BashInput{current,transcriptHandle,editorHandle,status,redraw,bashActivity},settingsSelectorRef,TrustContext{trustSelectorRef,Trust.create(Path.normalize(customDir ++ "/..")),autoTrustOnReloadOf(mode)},View.headerHandle(viewHandle),bindings,autocomplete,ExportTheme{liveTheme,customDir}})
        +lastClear : Ref.Ref<Maybe<&2,F64>> <- Ref.new(Maybe<&2,F64>,None{})
        +lastEscape : Ref.Ref<Maybe<&2,F64>> <- Ref.new(Maybe<&2,F64>,None{})
        selectionObserver : Callback.Callback<Controller.SelectionResult,Unit> <- Callback.create(~SelectionSink,~Controller.SelectionResult,~Unit,~selectionResult,SelectionSink{current,transcriptHandle,editorHandle,footerState(foot),status,redraw,cwd,home})
        controlObserver : Callback.Callback<Controller.ControlResult,Unit> <- Callback.create(~ControlSink,~Controller.ControlResult,~Unit,~controlResult,ControlSink{editorHandle,status,redraw})
        bindOptional(mode,listener,transcriptHandle,editorHandle,footerState(foot),status,redraw,cwd,home)
        controllerPair : Controller.Controller & Controller.Handle <- controllerFor(mode,current,session,listener,32n,Some{failureObserver},Some{commandObserver},Some{controlObserver},Some{selectionObserver},modelsRef,loginCallback)
        startController(controllerPair,view,transcript,styles,initial,foot,words,stopped,redraw,ThemeContext{liveTheme,transcriptHandle,current,setting,builtinDir,customDir,Interaction{editorHandle,lastClear,lastEscape,selectorRef,modelSelectorRef,thinkingSelectorRef,scopedSelectorRef,settingsSelectorRef,trustSelectorRef,View.headerHandle(viewHandle),bashActivity,working,autocomplete},modelsRef,mode,loginState,resumeState,bindings,highlighter,status})
def startStyles(styles: MarkdownTheme.Styles,view: View.View,+viewHandle: View.Handle,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Source,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match styles:
    case MarkdownTheme.Styles{+markdown,callbacks,+live,+highlighter}:
      do IO<Result<&2,&2,Error,Unit>>:
        transcript : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
        startTranscript(Transcript.borrow(transcript),view,viewHandle,MarkdownTheme.Styles{markdown,callbacks,live,highlighter},highlighter,live,session,initial,cwd,home,words,setting,builtinDir,customDir,models,mode)
def startView(borrowed: View.View & Component.Component & View.Handle,styles: MarkdownTheme.Styles,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,theme: Theme.Theme,words: Words.Source,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,_,viewHandle):
      startStyles(styles,view,viewHandle,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def withHeader(styles: MarkdownTheme.Styles,quiet: Bool,+session: Session.AgentSession,cwd: String,home: Maybe<&2,String>,themeDir: String) -> IO(View.View & MarkdownTheme.Styles):
  match styles:
    case MarkdownTheme.Styles{markdown,callbacks,+live,highlighter}:
      do IO<View.View & MarkdownTheme.Styles>:
        files : List<&2,Prompt.ContextFile> <- Session.getAgentsFiles(session)
        skills : List<&2,Skills.Skill> <- Session.getSkills(session)
        view : View.View <- View.createWithHeader(Component.ComponentId{1n},live,quiet,cwd,home,files,skills,themeDir)
        return (view,MarkdownTheme.Styles{markdown,callbacks,live,highlighter})
def prepared(pair: View.View & MarkdownTheme.Styles,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,theme: Theme.Theme,words: Words.Source,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (view,styles): startView(View.borrow(view),styles,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def started(+session: Session.AgentSession,initial: List<&2,Controller.Submission>,+cwd: String,+home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Source,setting: Maybe<&2,String>,+builtinDir: String,+customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create(Path.join(builtinDir,"../../../../../runtime/data/highlight"))
    styles : MarkdownTheme.Styles <- MarkdownTheme.create(theme,highlighter)
    +settings : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,Session.settingsOf(session))
    pair : View.View & MarkdownTheme.Styles <- withHeader(styles,Settings.getQuietStartup(settings),session,cwd,home,customDir)
    prepared(pair,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def themed(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,words: Words.Source,loaded: Result<&2,&2,Theme.LoadError,Theme.Theme>,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Unit>,Fail{ThemeData{cause}})
    case Done{theme}: started(session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
# upstream theme colour mode: getCapabilities().trueColor, with the settings'
# terminal capability override taking precedence over detection.
def trueColorOverride(capabilities: Settings.TerminalCapabilities) -> Maybe<&2,Bool>:
  match capabilities: case Settings.TerminalCapabilities{_,color,_}: color
def colorMode(session: Session.AgentSession,home: Maybe<&2,String>) -> IO(Color.Mode):
  do IO<Color.Mode>:
    settings : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,Session.settingsOf(session))
    environment : Image.Environment <- Image.processEnvironment("linux",Maybe.default(&2,String,home,""))
    return Color.modeFor(Image.trueColor(environment,trueColorOverride(Settings.getTerminalCapabilityOverrides(settings))))
def withWords(+session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,+home: Maybe<&2,String>,agentDir: String,assetsRoot: String,setting: Maybe<&2,String>,words: Words.Source,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    +builtinDir : String <- IO.pure(String,Path.join(assetsRoot,"packages/coding-agent/src/modes/interactive/theme"))
    +customDir : String <- IO.pure(String,Path.join(agentDir,"themes"))
    colors : Color.Mode <- colorMode(session,home)
    theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName("dark",builtinDir,customDir,colors)
    themed(session,initial,cwd,home,words,theme,setting,builtinDir,customDir,models,mode)
def run(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,+assetsRoot: String,themeSetting: Maybe<&2,String>,models: List<&2,Models.Model()>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    withWords(session,initial,cwd,home,agentDir,assetsRoot,themeSetting,Words.Pending{Path.join(assetsRoot,"packages/runtime/data")},models,None{})
def runBound(session: Session.AgentSession,binding: Binding,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,+assetsRoot: String,themeSetting: Maybe<&2,String>,models: List<&2,Models.Model()>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    withWords(session,initial,cwd,home,agentDir,assetsRoot,themeSetting,Words.Pending{Path.join(assetsRoot,"packages/runtime/data")},models,Some{binding})
