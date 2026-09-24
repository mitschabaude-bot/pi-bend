import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/auth/types.bend as Auth
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/filesystem.bend as Filesystem
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/abort.bend as Abort
import ../../cli/auth-login.bend as AuthLogin
import ../../cli/session-picker.bend as SessionPicker
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../runtime/src/word-segmenter.bend as Words
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/editor.bend as Editor
import ../../../../tui/src/components/editor-component.bend as Live
import ../../../../tui/src/components/select-list.bend as Select
import ../../../../tui/src/keybindings.bend as Keybindings
import ../../../../tui/src/keys.bend as Keys
import ../../../../tui/src/tui-base.bend as Tui
import ../../../../tui/src/tui-main-screen.bend as Screen
import ../../../../tui/src/tui-process.bend as Process
import ../../../../tui/src/terminal.bend as Terminal
import ../../../../tui/src/utils.bend as Utils
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ../../core/agent-session-runtime.bend as SessionHost
import ../../core/bash-executor.bend as BashExec
import ../../core/session-cwd.bend as SessionCwd
import ../../core/session-persistence.bend as Persistence
import ../../core/export-html/index.bend as Export
import ../../core/prompt-templates.bend as Templates
import ../../core/session-manager.bend as Tree
import ../../core/session-stats.bend as Stats
import ../../core/tools/index.bend as Tools
import ../../core/settings-manager.bend as Settings
import ../../core/model-runtime.bend as Models
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../core/keybindings.bend as AppKeys
import ./components/footer.bend as Footer
import ./components/header.bend as Header
import ./components/session-selector.bend as Selector
import ./components/model-selector.bend as ModelPicker
import ./components/messages.bend as MessageUI
import ./components/login-dialog.bend as LoginDialog
import ./theme/color.bend as Color
import ./theme/markdown-theme.bend as MarkdownTheme
import ./theme/theme.bend as Theme
import ./theme/theme-controller.bend as ThemeController
import ./interactive-mode.bend as Interactive
import ./commands.bend as Commands
import ./session-controller.bend as Controller
import ./transcript.bend as Transcript
import ./viewport.bend as View

type Error is Data:
  WordData{cause: Words.LoadError}
  ThemeData{cause: Theme.LoadError}
  Layout{cause: Tui.Error}
  TerminalStart{cause: Terminal.Error}

def wordError(error: Words.LoadError) -> String:
  match error:
    case Words.ReadFailed{path,cause}: "Cannot load word data " ++ path ++ ": " ++ Filesystem.errorMessage(cause)
    case Words.InvalidAsset{path}: "Invalid word data: " ++ path
def themeError(error: Theme.LoadError) -> String:
  match error:
    case Theme.Read{cause}: "Cannot load theme: " ++ Filesystem.errorMessage(cause)
    case Theme.Decode{_}: "Invalid theme encoding"
    case Theme.Invalid{_}: "Invalid theme"
    case Theme.NotFound{name}: "Theme not found: " ++ name
def errorMessage(error: Error) -> String:
  match error:
    case WordData{cause}: wordError(cause)
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
def initialFooter(+agentState: Session.AgentState(),messages: List<&2,Session.Message()>,cwd: String,home: Maybe<&2,String>) -> Footer.State:
  +chosen = Maybe.map(&2,Ai.Model<Ai.JsonValue>,Footer.Model,model,Session.stateModel(agentState))
  seedFooter(messages,Footer.State{cwd,home,None{},None{},chosen,Levels.name(Session.stateThinking(agentState)),Footer.emptyUsage(),None{},None{},None{},1n,False{},False{},False{},Nil{}})
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
    case Session.AgentEvent{Agent.AgentStart{}}: (withStatus(state,Footer.Status{"agent","Working"} <> Nil{}),True{})
    case Session.AgentSettled{}: (withStatus(state,Nil{}),True{})
    case Session.AutoRetryStart{attempt,_,_,_}: (withStatus(state,Footer.Status{"retry","Retry " ++ Nat.show(attempt)} <> Nil{}),True{})
    case Session.AutoRetryEnd{_,_,_}: (withStatus(state,Nil{}),True{})
    case Session.CompactionStart{_}: (withStatus(state,Footer.Status{"compact","Compacting"} <> Nil{}),True{})
    case Session.CompactionEnd{_,_,_,_,_}: (withStatus(state,Nil{}),True{})
    case Session.ThinkingLevelChanged{level}: (withThinking(state,level),True{})
    case Session.SessionInfoChanged{name}: (withName(state,name),True{})
    case _: (state,False{})
type Observation is Data:
  Observation{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,footer: Ref.Ref<Footer.State>}
def observeCopied(input: Observation,+event: Session.AgentSessionEvent) -> IO(Unit):
  match input:
    case Observation{transcript,+redraw,footer}:
      do IO<Unit>:
        changed : Bool <- Ref.modify(Footer.State,Bool,footer,state => footerEvent(state,event))
        Interactive.onSessionEvent(Interactive.Events{transcript,redraw},event)
        Bool.pick(Unit -> IO(Unit),changed,_ => Interactive.requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def observed(input: Observation,event: Session.AgentSessionEvent) -> IO(Unit):
  observeCopied(input,event)
type ImportRequest is Data: ImportRequest{path: String,cwdOverride: Maybe<&2,String>}
type ResumeRequest is Data: ResumeRequest{path: String,cwdOverride: Maybe<&2,String>}
type SessionChoices is Data: SessionChoices{current: List<&2,Tree.SessionInfo>,all: List<&2,Tree.SessionInfo>}
type ImportState is Data:
  ImportState{host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,backend: Maybe<&2,Callback.Callback<ImportRequest,SessionHost.ImportOutcome>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type ResumeState is Data:
  ResumeState{picker: Ref.Ref<Maybe<&2,SessionPicker.Host>>,dialog: Ref.Ref<Maybe<&2,LoginDialog.Host>>,sessions: Maybe<&2,Callback.Callback<Unit,SessionChoices>>,backend: Maybe<&2,Callback.Callback<ResumeRequest,SessionHost.ResumeOutcome>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type BashActivity is Data:
  BashActivity{active: Bool,closing: Bool,completion: Maybe<&2,Deferred.Deferred<Unit>>}
type BashInput is Data:
  BashInput{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,activity: Ref.Ref<BashActivity>}
type BashReservation is Data:
  BashReserved{previous: Maybe<&2,Deferred.Deferred<Unit>>,completion: Deferred.Deferred<Unit>}
  BashBusy{unused: Deferred.Deferred<Unit>}
  BashClosed{unused: Deferred.Deferred<Unit>}
type CommandObservation is Data:
  CommandObservation{sink: Interactive.CommandSink,session: Ref.Ref<Session.AgentSession>,footer: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,builtinDir: String,importState: ImportState,resumeState: ResumeState,selector: Ref.Ref<Maybe<&2,Selector.Host>>,bash: BashInput}
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
def exportWithAssets(+session: Session.AgentSession,path: Maybe<&2,String>,assets: Result<&2,&2,String,Export.Assets>) -> IO(Result<&2,&2,String,String>):
  match assets:
    case Fail{message}: IO.pure(Result<&2,&2,String,String>,Fail{message})
    case Done{loaded}:
      do IO<Result<&2,&2,String,String>>:
        stored : Session.Session() <- Session.sessionOf(session)
        agentState : Session.AgentState() <- Session.state(session)
        Export.write(loaded,stored,agentState,path)
def exportHtml(session: Session.AgentSession,builtinDir: String,path: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    assets : Result<&2,&2,String,Export.Assets> <- Export.loadAssets(Path.join(builtinDir,"../../../core/export-html"))
    exportWithAssets(session,path,assets)
def exportWithPath(session: Session.AgentSession,cwd: String,builtinDir: String,+path: String,jsonl: Bool) -> IO(Result<&2,&2,String,String>):
  match jsonl:
    case True{}: exportJsonl(session,cwd,path)
    case False{}: exportHtml(session,builtinDir,Some{path})
def exportChosen(session: Session.AgentSession,cwd: String,builtinDir: String,path: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  match path:
    case Some{+path}: exportWithPath(session,cwd,builtinDir,path,String.ends_with(path,".jsonl"))
    case None{}: exportHtml(session,builtinDir,None{})
def exportCurrent(session: Session.AgentSession,cwd: String,builtinDir: String,requested: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  exportChosen(session,cwd,builtinDir,exportPath(requested))
def exportNotice(result: Result<&2,&2,String,String>) -> Interactive.SubmissionFailure:
  match result:
    case Done{path}: Interactive.CommandNotice{"Session exported to: " ++ path}
    case Fail{message}: Interactive.CommandFailure{"Failed to export session: " ++ message}
def exportObserved(input: CommandObservation,requested: Maybe<&2,String>) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,failure,redraw,cwd,builtinDir,_,_,_,_}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,String> <- exportCurrent(live,cwd,builtinDir,requested)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{exportNotice(result)})
        Interactive.requestRender(redraw)
def importStatus(state: ImportState,status: Interactive.SubmissionFailure) -> IO(Unit):
  match state:
    case ImportState{_,_,failure,redraw}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{status})
        Interactive.requestRender(redraw)
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
        answer : String <- importConfirm(state," Session cwd not found · " ++ missing,LoginDialog.Choice{"yes","Continue in current cwd",fallback},LoginDialog.Choice{"no","Cancel import",""})
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
        answer : String <- importConfirm(state," Import session · Replace current session with " ++ input ++ "?",LoginDialog.Choice{"yes","Yes","Replace current session"},LoginDialog.Choice{"no","No","Keep current session"})
        importConfirmed(state,input,answer)
def importObserved(input: CommandObservation,requested: Maybe<&2,String>) -> IO(Unit):
  match input:
    case CommandObservation{_,_,_,_,_,_,_,state,_,_,_}: importRequested(state,exportPath(requested))
def resumeStatus(state: ResumeState,status: Interactive.SubmissionFailure) -> IO(Unit):
  match state:
    case ResumeState{_,_,_,_,failure,redraw}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{status})
        Interactive.requestRender(redraw)
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
        answer : String <- importAnswer(target,redraw," Session cwd not found · " ++ missing,LoginDialog.Choice{"yes","Continue in current cwd",fallback} <> LoginDialog.Choice{"no","Cancel resume",""} <> Nil{})
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
  match input: case CommandObservation{_,_,_,_,_,_,_,_,state,_,_}: resumeRequested(state)
def selectorNotice(failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,message: String) -> IO(Unit):
  Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{message}})
def openTree(target: Maybe<&2,Selector.Host>,state: Selector.State) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: Selector.open(host,state)
def openCandidate(selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,+state: Selector.State,empty: String) -> IO(Unit):
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
def matchTree(selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,result: Result<&2,&2,Tree.Error,List<&2,Selector.Node()>>,leaf: Maybe<&2,String>,filter: Selector.Filter) -> IO(Unit):
  match result:
    case Fail{_}: selectorNotice(failure,"Cannot load session tree")
    case Done{nodes}: openCandidate(selector,failure,Selector.createWithFilter(nodes,leaf,Selector.TreeMode{},24n,filter),"No entries in session")
def selectorFromState(mode: Selector.Mode,+state: Session.State(),filter: Selector.Filter,selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>) -> IO(Unit):
  match mode:
    case Selector.TreeMode{}: matchTree(selector,failure,Tree.getTree(Unit,Tools.ToolDetails,Schema.Value,state),Tree.getLeafId(Unit,Tools.ToolDetails,Schema.Value,state),filter)
    case Selector.ForkMode{}: openCandidate(selector,failure,Selector.createFork(Tree.getEntries(Unit,Tools.ToolDetails,Schema.Value,state),24n),"No user messages found")
def openSessionSelector(mode: Selector.Mode,session: Ref.Ref<Session.AgentSession>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    current : Session.Session() <- Session.sessionOf(live)
    settings : Settings.SettingsManager <- Session.getSettings(live)
    filter : Settings.TreeFilterMode = Settings.getTreeFilterMode(settings)
    selectorFromState(mode,Session.stateOf(current),selectorFilter(filter),selector,failure)
    Interactive.requestRender(redraw)
def treeObserved(input: CommandObservation,mode: Selector.Mode) -> IO(Unit):
  match input:
    case CommandObservation{_,session,_,failure,redraw,_,_,_,_,selector,_}: openSessionSelector(mode,session,selector,failure,redraw)
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
        Transcript.failBash(message,error)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{"Bash command failed: " ++ error}})
        Interactive.requestRender(redraw)
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
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{"A bash command is already running. Press Esc to cancel it first."}})
        Interactive.requestRender(redraw)
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
  match input: case CommandObservation{_,_,_,_,_,_,_,_,_,_,bash}: bashRequested(bash,command,excluded)
def ordinaryCommandObserved(input: CommandObservation,action: Commands.Action) -> IO(Unit):
  match input:
    case CommandObservation{sink,session,footer,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        changed : Bool <- Interactive.commandResult(sink,action)
        Bool.pick(Unit -> IO(Unit),changed,_ => do IO<Unit>:
          live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
          state : Session.AgentState() <- Session.state(live)
          Ref.modify(Footer.State,Unit,footer,current => (withChosen(current,state),Unit{})),_ => IO.pure(Unit,Unit{}))(Unit{})
def commandObserved(input: CommandObservation,action: Commands.Action) -> IO(Unit):
  match action:
    case Commands.ExportSession{path}: exportObserved(input,path)
    case Commands.ImportSession{path}: importObserved(input,path)
    case Commands.ResumeSession{}: resumeObserved(input)
    case Commands.OpenTree{}: treeObserved(input,Selector.TreeMode{})
    case Commands.OpenFork{}: treeObserved(input,Selector.ForkMode{})
    case Commands.RunBash{command,excluded}: bashObserved(input,command,excluded)
    case other: ordinaryCommandObserved(input,other)
type WorkerFailure is Data:
  WorkerFailure{failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def promptFailed(input: WorkerFailure,value: Controller.PromptFailure) -> IO(Unit):
  match input value:
    case WorkerFailure{failure,redraw} Controller.PromptFailure{message}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.PromptFailure{message}})
        Interactive.requestRender(redraw)

type FooterPaint is Data: FooterPaint{state: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>}
type FooterOwner is Data: FooterOwner{state: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}

def appendedFailure(lines: List<&2,String>,plain: String,painted: Result<&2,&2,Theme.Error,String>) -> List<&2,String>:
  match painted:
    case Done{colored}: List.append(&2,String,lines,colored <> Nil{})
    case Fail{_}: List.append(&2,String,lines,plain <> Nil{})
def withFailure(lines: List<&2,String>,failure: Maybe<&2,Interactive.SubmissionFailure>,theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match failure:
    case None{}: lines
    case Some{Interactive.CommandNotice{message}}:
      +plain = Utils.truncateToWidth(message,width,"...",False{})
      appendedFailure(lines,plain,Theme.foreground(theme,"accent",plain))
    case Some{value}:
      +plain = Utils.truncateToWidth("Error: " ++ Interactive.failureText(value),width,"...",False{})
      appendedFailure(lines,plain,Theme.foreground(theme,"error",plain))
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
def footerLinesCopied(paint: FooterPaint,+width: Nat) -> IO(List<&2,String>):
  match paint:
    case FooterPaint{state,failure,+theme,session}:
      do IO<List<&2,String>>:
        +selected : Theme.Theme <- Ref.read(Theme.Theme,theme)
        current : Footer.State <- Ref.read(Footer.State,state)
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        stats : Result<&2,&2,Tree.Error,Stats.Stats> <- Session.getSessionStats(live)
        failed : Maybe<&2,Interactive.SubmissionFailure> <- Ref.read(Maybe<&2,Interactive.SubmissionFailure>,failure)
        lines : List<&2,String> <- Footer.render(statsState(current,stats),selected,width)
        return withFailure(lines,failed,selected,width)
def footerLines(paint: FooterPaint,width: Nat) -> IO(List<&2,String>):
  footerLinesCopied(paint,width)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def footer(initial: Footer.State,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>) -> IO(FooterOwner):
  do IO<FooterOwner>:
    +state : Ref.Ref<Footer.State> <- Ref.new(Footer.State,initial)
    +failure : Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>> <- Ref.new(Maybe<&2,Interactive.SubmissionFailure>,None{})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~FooterPaint,~Nat,~List<&2,String>,~footerLines,FooterPaint{state,failure,theme,session})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return FooterOwner{state,failure,Component.Component{Component.ComponentId{3n},render,None{},None{},invalidate,None{},False{}},render,invalidate}
def footerState(owner: FooterOwner) -> Ref.Ref<Footer.State>:
  match owner: case FooterOwner{state,_,_,_,_}: state
def footerFailure(owner: FooterOwner) -> Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>:
  match owner: case FooterOwner{_,failure,_,_,_}: failure
def footerComponent(owner: FooterOwner) -> Component.Component:
  match owner: case FooterOwner{_,_,component,_,_}: component
def disposeFooter(owner: FooterOwner) -> IO(Unit):
  match owner:
    case FooterOwner{state,failure,_,render,invalidate}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        old : Footer.State <- Ref.dispose(Footer.State,state)
        oldFailure : Maybe<&2,Interactive.SubmissionFailure> <- Ref.dispose(Maybe<&2,Interactive.SubmissionFailure>,failure)
        return Unit{}

def editorTheme(theme: Ref.Ref<Theme.Theme>) -> IO(Callback.Callback<String,String> & Editor.EditorTheme):
  do IO<Callback.Callback<String,String> & Editor.EditorTheme>:
    +paint : Callback.Callback<String,String> <- MarkdownTheme.color(theme,"accent")
    return (paint,Editor.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}})
def clear(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,_: Unit) -> IO(Unit):
  Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,None{})

type ThemeLive is Data:
  ThemeLive{selection: Ref.Ref<Maybe<&2,ThemeController.Handle>>,theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,requestRender: Callback.Callback<Unit,Unit>}
type ThemeOwned is Type:
  ThemeOwned{controller: ThemeController.Owner,render: Callback.Callback<Unit,Unit>}
type ThemeStartup is Data:
  ThemeStartup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,stopped: Deferred.Deferred<Unit>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>,error: Ref.Ref<Maybe<&2,Theme.LoadError>>,theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,setting: Maybe<&2,String>,builtinDir: String,customDir: String}
type ThemeStopping is Data:
  ThemeStopping{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>}
type Interaction is Data:
  Interaction{editor: Ref.Ref<Maybe<&2,Live.Handle>>,lastClear: Ref.Ref<Maybe<&2,F64>>,lastEscape: Ref.Ref<Maybe<&2,F64>>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,modelSelector: Ref.Ref<Maybe<&2,ModelPicker.Host>>,header: Maybe<&2,Header.Handle>,bashActivity: Ref.Ref<BashActivity>}
type LoginRequest is Data: LoginRequest{provider: String,signal: Abort.AbortSignal<Unit>,notice: AuthLogin.Notice(),manual: Callback.Callback<AuthLogin.ManualPrompt,Unit>,manualDone: Callback.Callback<Unit,Unit>}
type Binding is Data:
  Binding{current: Ref.Ref<Session.AgentSession>,newSession: Callback.Callback<Unit,Result<&2,&2,String,Unit>>,onRebind: Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>,login: Callback.Callback<LoginRequest,AuthLogin.Outcome()>,refreshModels: Callback.Callback<Unit,List<&2,Models.Model()>>,importer: Callback.Callback<ImportRequest,SessionHost.ImportOutcome>,sessions: Callback.Callback<Unit,SessionChoices>,resume: Callback.Callback<ResumeRequest,SessionHost.ResumeOutcome>}
type LoginState is Data:
  LoginState{host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,abort: Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>,backend: Maybe<&2,Callback.Callback<LoginRequest,AuthLogin.Outcome()>>,refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>}
def showLoginCode(target: Maybe<&2,LoginDialog.Host>,url: String,code: String) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{dialog}: LoginDialog.showCode(dialog,url,code)
def loginNotice(state: LoginState,prompt: AuthLogin.DevicePrompt) -> IO(Unit):
  match state prompt:
    case LoginState{host,_,_,_,_,_,redraw,_} AuthLogin.DevicePrompt{url,code}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        showLoginCode(target,url,code)
        Interactive.requestRender(redraw)
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
    case "openai-codex": "OpenAI Codex"
    case other: other
def defaultId(defaults: List<&2,Models.DefaultModel>,+provider: String) -> Maybe<&2,String>:
  match defaults:
    case Nil{}: None{}
    case Models.DefaultModel{owner,id} <> rest: Bool.pick(Maybe<&2,String>,String.eq(owner,provider),Some{id},defaultId(rest,provider))
def selectedDefault(models: List<&2,Models.Model()>,provider: String,expected: Maybe<&2,String>) -> Maybe<&2,Models.Model()>:
  match expected:
    case None{}: None{}
    case Some{id}: Models.findModel(models,provider,id)
def selectedNotice(provider: String,id: String,result: Result<&2,&2,String,Unit>) -> String:
  match result:
    case Done{_}: "Logged in to " ++ providerName(provider) ++ ". Selected " ++ id
    case Fail{reason}: "Logged in to " ++ providerName(provider) ++ ", but selecting its default model failed: " ++ reason ++ ". Use /model to select a model."
def chooseAfterLogin(provider: String,session: Session.AgentSession,available: List<&2,Models.Model()>,selected: Maybe<&2,Models.Model()>) -> IO(String):
  match selected:
    case None{}: IO.pure(String,"Logged in to " ++ providerName(provider) ++ ", but its default model is unavailable. Use /model to select a model.")
    case Some{+chosen}:
      do IO<String>:
        id : String = Models.modelId(chosen)
        result : Result<&2,&2,String,Unit> <- Session.setModel(session,chosen,Session.ModelMutationOptions{True{}})
        return selectedNotice(provider,id,result)
def loginStatus(+provider: String,session: Ref.Ref<Session.AgentSession>,+available: List<&2,Models.Model()>) -> IO(String):
  do IO<String>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    current : Session.AgentState() <- Session.state(live)
    Bool.pick(Unit -> IO(String),Maybe.is_some(&2,Ai.Model<Ai.JsonValue>,Session.stateModel(current)),_ => IO.pure(String,"Logged in to " ++ providerName(provider)),_ => chooseAfterLogin(provider,live,available,selectedDefault(available,provider,defaultId(Models.defaultModelPerProvider(),provider))))(Unit{})
def loginOutcomeResult(provider: String,result: AuthLogin.Outcome(),refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        available : List<&2,Models.Model()> <- refreshLoginModels(refresh,models)
        message : String <- loginStatus(provider,session,available)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{message}})
    case Fail{message}: Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{message}})
def loginOutcome(provider: String,result: AuthLogin.Outcome(),cancelled: Bool,refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match cancelled:
    case True{}: Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{"Login cancelled"}})
    case False{}: loginOutcomeResult(provider,result,refresh,models,failure,session)
def loginFinished(state: LoginState,provider: String,result: AuthLogin.Outcome(),cancelled: Bool) -> IO(Unit):
  match state:
    case LoginState{host,_,_,refresh,models,failure,redraw,session}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        closeLoginDialog(target)
        loginOutcome(provider,result,cancelled,refresh,models,failure,session)
        Interactive.requestRender(redraw)
def manualLoginDialog(target: Maybe<&2,LoginDialog.Host>,prompt: AuthLogin.ManualPrompt,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match target prompt:
    case None{} _: IO.pure(Unit,Unit{})
    case Some{dialog} AuthLogin.ManualPrompt{url,answer}:
      do IO<Unit>:
        LoginDialog.showManual(dialog,url,answer)
        Interactive.requestRender(redraw)
def manualLogin(state: LoginState,prompt: AuthLogin.ManualPrompt) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,redraw,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        manualLoginDialog(target,prompt,redraw)
def endManualDialog(target: Maybe<&2,LoginDialog.Host>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  match target:
    case None{}: IO.pure(Unit,Unit{})
    case Some{dialog}:
      do IO<Unit>:
        LoginDialog.stopManual(dialog)
        Interactive.requestRender(redraw)
def endManual(state: LoginState,_: Unit) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,redraw,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        endManualDialog(target,redraw)
def loginAbort(state: LoginState) -> Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>:
  match state: case LoginState{_,abort,_,_,_,_,_,_}: abort
def selectedLogin(+state: LoginState,+provider: String,authenticate: Callback.Callback<LoginRequest,AuthLogin.Outcome()>,+controller: Abort.AbortController<Unit>) -> IO(Unit):
  match provider:
    case "":
      do IO<Unit>:
        old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,loginAbort(state),None{})
        Abort.dispose(Unit,controller)
        loginFinished(state,"",Done{Unit{}},True{})
    case +chosen:
      do IO<Unit>:
        +notice : AuthLogin.Notice() <- Callback.create(~LoginState,~AuthLogin.DevicePrompt,~Unit,~loginNotice,state)
        +manual : Callback.Callback<AuthLogin.ManualPrompt,Unit> <- Callback.create(~LoginState,~AuthLogin.ManualPrompt,~Unit,~manualLogin,state)
        +manualDone : Callback.Callback<Unit,Unit> <- Callback.create(~LoginState,~Unit,~Unit,~endManual,state)
        result : AuthLogin.Outcome() <- Callback.call(LoginRequest,AuthLogin.Outcome(),authenticate,LoginRequest{chosen,Abort.signal(Unit,controller),notice,manual,manualDone})
        Callback.dispose(AuthLogin.DevicePrompt,Unit,notice)
        Callback.dispose(AuthLogin.ManualPrompt,Unit,manual)
        Callback.dispose(Unit,Unit,manualDone)
        old : Maybe<&2,Abort.AbortController<Unit>> <- Ref.swap(Maybe<&2,Abort.AbortController<Unit>>,loginAbort(state),None{})
        cancelled : Bool <- Abort.aborted(Unit,Abort.signal(Unit,controller))
        Abort.dispose(Unit,controller)
        loginFinished(state,chosen,result,cancelled)
def activeLogin(+state: LoginState,dialog: LoginDialog.Host,authenticate: Callback.Callback<LoginRequest,AuthLogin.Outcome()>) -> IO(Unit):
  match state:
    case LoginState{_,abort,_,_,_,_,redraw,_}:
      do IO<Unit>:
        +pending : Deferred.Deferred<String> <- LoginDialog.open(dialog)
        Interactive.requestRender(redraw)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        Ref.write(Maybe<&2,Abort.AbortController<Unit>>,abort,Some{controller})
        provider : String <- Deferred.result(String,pending)
        Deferred.dispose(String,pending)
        selectedLogin(state,provider,authenticate,controller)
def canonicalProvider(normalized: String) -> Maybe<&2,String>:
  match normalized:
    case "openai-codex": Some{"openai-codex"}
    case "openai codex": Some{"openai-codex"}
    case "anthropic": Some{"anthropic"}
    case "anthropic (claude pro/max)": Some{"anthropic"}
    case _: None{}
def directProvider(requested: String) -> Maybe<&2,String>: canonicalProvider(String.to_lower(Text.trim(requested)))
def directLogin(+state: LoginState,dialog: LoginDialog.Host,authenticate: Callback.Callback<LoginRequest,AuthLogin.Outcome()>,provider: String) -> IO(Unit):
  match state:
    case LoginState{_,abort,_,_,_,_,redraw,_}:
      do IO<Unit>:
        LoginDialog.openDirect(dialog)
        Interactive.requestRender(redraw)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        Ref.write(Maybe<&2,Abort.AbortController<Unit>>,abort,Some{controller})
        selectedLogin(state,provider,authenticate,controller)
def credentialFailure(state: LoginState,message: String) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,failure,redraw,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{message}})
        Interactive.requestRender(redraw)
def unavailableLogin(state: LoginState) -> IO(Unit):
  match state:
    case LoginState{_,_,_,_,_,failure,redraw,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{"Login is unavailable"}})
        Interactive.requestRender(redraw)
def beginDirect(state: LoginState,dialog: LoginDialog.Host,authenticate: Callback.Callback<LoginRequest,AuthLogin.Outcome()>,requested: String,provider: Maybe<&2,String>) -> IO(Unit):
  match provider:
    case Some{chosen}: directLogin(state,dialog,authenticate,chosen)
    case None{}: credentialFailure(state,"Unknown login provider: " ++ requested)
def beginLogin(+state: LoginState,target: Maybe<&2,LoginDialog.Host>,backend: Maybe<&2,Callback.Callback<LoginRequest,AuthLogin.Outcome()>>,+requested: String) -> IO(Unit):
  match target backend:
    case Some{dialog} Some{authenticate}:
      match requested:
        case "": activeLogin(state,dialog,authenticate)
        case _: beginDirect(state,dialog,authenticate,requested,directProvider(requested))
    case _ _: unavailableLogin(state)
def loginRunCopied(+state: LoginState,requested: String) -> IO(Unit):
  match state:
    case LoginState{host,_,+backend,_,_,_,_,_}:
      do IO<Unit>:
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        beginLogin(state,target,backend,requested)
def loginRun(state: LoginState,requested: String) -> IO(Unit): loginRunCopied(state,requested)
def logoutChoice(info: Auth.CredentialInfo) -> LoginDialog.Choice:
  match info:
    case Auth.CredentialInfo{+id,kind}: LoginDialog.Choice{id,providerName(id),Auth.typeName(kind)}
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
def logoutOutcome(+provider: String,kind: Maybe<&2,Auth.CredentialType>,result: AuthLogin.Outcome(),refresh: Maybe<&2,Callback.Callback<Unit,List<&2,Models.Model()>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        available : List<&2,Models.Model()> <- refreshLoginModels(refresh,models)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{logoutNotice(provider,kind)}})
    case Fail{message}: Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{"Logout failed: " ++ message}})
def logoutChosen(state: LoginState,+chosen: String,infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match state:
    case LoginState{_,_,_,refresh,models,failure,redraw,_}:
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
    case LoginState{_,_,_,_,_,_,redraw,_}:
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
    case LoginState{_,_,_,_,_,failure,redraw,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{"No stored credentials to remove. /logout only removes credentials saved by /login; environment variables and models.json config are unchanged."}})
        Interactive.requestRender(redraw)
def logoutAvailable(state: LoginState,target: Maybe<&2,LoginDialog.Host>,infos: List<&2,Auth.CredentialInfo>) -> IO(Unit):
  match target:
    case Some{dialog}: logoutMenu(state,dialog,infos)
    case None{}: unavailableLogin(state)
def logoutListed(state: LoginState,target: Maybe<&2,LoginDialog.Host>,result: AuthLogin.StoredCredentials()) -> IO(Unit):
  match result:
    case Fail{message}: credentialFailure(state,"Could not read stored credentials: " ++ message)
    case Done{Nil{}}: emptyLogout(state)
    case Done{infos}: logoutAvailable(state,target,infos)
def logoutRun(+state: LoginState) -> IO(Unit):
  match state:
    case LoginState{host,_,_,_,_,_,_,_}:
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
def cancelLogin(state: LoginState,_: Unit) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,_,_,_,_}:
      do IO<Unit>:
        active : Maybe<&2,Abort.AbortController<Unit>> <- Ref.read(Maybe<&2,Abort.AbortController<Unit>>,abort)
        abortLogin(active)
        target : Maybe<&2,LoginDialog.Host> <- Ref.read(Maybe<&2,LoginDialog.Host>,host)
        closeLoginDialog(target)
type ThemeContext is Data:
  ThemeContext{theme: Ref.Ref<Theme.Theme>,transcript: Transcript.Handle,session: Ref.Ref<Session.AgentSession>,setting: Maybe<&2,String>,builtinDir: String,customDir: String,interaction: Interaction,models: Ref.Ref<List<&2,Models.Model()>>,binding: Maybe<&2,Binding>,login: LoginState,resume: ResumeState}
type KeyInput is Data:
  KeyInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,lastClear: Ref.Ref<Maybe<&2,F64>>,lastEscape: Ref.Ref<Maybe<&2,F64>>,selector: Ref.Ref<Maybe<&2,Selector.Host>>,session: Ref.Ref<Session.AgentSession>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,header: Maybe<&2,Header.Handle>,transcript: Transcript.Handle}
type ControlSink is Data:
  ControlSink{editor: Ref.Ref<Maybe<&2,Live.Handle>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SelectionSink is Data:
  SelectionSink{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footerRef: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>}
def selectionText(result: Controller.SelectionResult) -> Maybe<&2,String>:
  match result:
    case Controller.Navigated{Session.Navigation{text,_}}: text
    case Controller.Forked{Session.Fork{text,_,_}}: Some{text}
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
        Ref.write(Footer.State,footerRef,initialFooter(agentState,messages,cwd,home))
        updateSelectionEditor(editor,selectionText(result))
        Interactive.requestRender(redraw)
def failedSelection(sink: SelectionSink,message: String) -> IO(Unit):
  match sink:
    case SelectionSink{_,_,_,_,failure,redraw,_,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.PromptFailure{message}})
        Interactive.requestRender(redraw)
def selectionResult(sink: SelectionSink,result: Controller.SelectionResult) -> IO(Unit):
  match result:
    case Controller.Navigated{navigation}: refreshSelection(sink,Controller.Navigated{navigation})
    case Controller.Forked{fork}: refreshSelection(sink,Controller.Forked{fork})
    case Controller.SelectionFailed{message}: failedSelection(sink,message)
type SelectInput is Data: SelectInput{queue: Controller.Handle,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
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
def chosenModel(input: SelectInput,model: Models.Model()) -> IO(Unit):
  match input:
    case SelectInput{queue,failure,_}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,Commands.SwitchModel{model})
        Interactive.submittedResult(failure,result)
def selectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,Selector.Host>>:
  match interaction: case Interaction{_,_,_,selector,_,_,_}: selector
def modelSelectorRefOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,ModelPicker.Host>>:
  match interaction: case Interaction{_,_,_,_,selector,_,_}: selector
def contextTheme(context: ThemeContext) -> Ref.Ref<Theme.Theme>:
  match context: case ThemeContext{theme,_,_,_,_,_,_,_,_,_,_}: theme
def contextTranscript(context: ThemeContext) -> Transcript.Handle:
  match context: case ThemeContext{_,transcript,_,_,_,_,_,_,_,_,_}: transcript
def contextInteraction(context: ThemeContext) -> Interaction:
  match context: case ThemeContext{_,_,_,_,_,_,interaction,_,_,_,_}: interaction
def lastClearOf(interaction: Interaction) -> Ref.Ref<Maybe<&2,F64>>:
  match interaction: case Interaction{_,lastClear,_,_,_,_,_}: lastClear
def recordEditor(interaction: Interaction,handle: Live.Handle) -> IO(Unit):
  match interaction: case Interaction{editor,_,_,_,_,_,_}: Ref.write(Maybe<&2,Live.Handle>,editor,Some{handle})
def bashActivityOf(interaction: Interaction) -> Ref.Ref<BashActivity>:
  match interaction: case Interaction{_,_,_,_,_,_,activity}: activity
def contextSession(context: ThemeContext) -> Ref.Ref<Session.AgentSession>:
  match context: case ThemeContext{_,_,session,_,_,_,_,_,_,_,_}: session
def contextLogin(context: ThemeContext) -> LoginState:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,login,_}: login
def contextResume(context: ThemeContext) -> ResumeState:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,_,_,resume}: resume
def resumePickerRef(state: ResumeState) -> Ref.Ref<Maybe<&2,SessionPicker.Host>>:
  match state: case ResumeState{picker,_,_,_,_,_}: picker
def contextBinding(context: ThemeContext) -> Maybe<&2,Binding>:
  match context: case ThemeContext{_,_,_,_,_,_,_,_,binding,_,_}: binding
def loginStateOf(mode: Maybe<&2,Binding>,host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,abort: Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>>,models: Ref.Ref<List<&2,Models.Model()>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Ref.Ref<Session.AgentSession>) -> LoginState:
  match mode:
    case None{}: LoginState{host,abort,None{},None{},models,failure,redraw,session}
    case Some{Binding{_,_,_,backend,refresh,_,_,_}}: LoginState{host,abort,Some{backend},Some{refresh},models,failure,redraw,session}
def importStateOf(mode: Maybe<&2,Binding>,host: Ref.Ref<Maybe<&2,LoginDialog.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> ImportState:
  match mode:
    case None{}: ImportState{host,None{},failure,redraw}
    case Some{Binding{_,_,_,_,_,backend,_,_}}: ImportState{host,Some{backend},failure,redraw}
def resumeStateOf(mode: Maybe<&2,Binding>,picker: Ref.Ref<Maybe<&2,SessionPicker.Host>>,dialog: Ref.Ref<Maybe<&2,LoginDialog.Host>>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> ResumeState:
  match mode:
    case None{}: ResumeState{picker,dialog,None{},None{},failure,redraw}
    case Some{Binding{_,_,_,_,_,_,sessions,resume}}: ResumeState{picker,dialog,Some{sessions},Some{resume},failure,redraw}
def disposeLoginState(state: LoginState) -> IO(Unit):
  match state:
    case LoginState{host,abort,_,_,models,_,_,_}:
      do IO<Unit>:
        oldHost : Maybe<&2,LoginDialog.Host> <- Ref.dispose(Maybe<&2,LoginDialog.Host>,host)
        oldAbort : Maybe<&2,Abort.AbortController<Unit>> <- Ref.dispose(Maybe<&2,Abort.AbortController<Unit>>,abort)
        oldModels : List<&2,Models.Model()> <- Ref.dispose(List<&2,Models.Model()>,models)
        return Unit{}
def keyInput(queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,interaction: Interaction,session: Ref.Ref<Session.AgentSession>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,transcript: Transcript.Handle) -> KeyInput:
  match interaction:
    case Interaction{_,lastClear,lastEscape,selector,_,header,_}: KeyInput{queue,stop,failure,lastClear,lastEscape,selector,session,redraw,header,transcript}
def openedTree(input: KeyInput,mode: Selector.Mode) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,selector,session,redraw,_,_}: openSessionSelector(mode,session,selector,failure,redraw)
def actionDouble(input: KeyInput,action: Settings.DoubleEscapeAction) -> IO(Unit):
  match action:
    case Settings.Tree{}: openedTree(input,Selector.TreeMode{})
    case Settings.Fork{}: openedTree(input,Selector.ForkMode{})
    case Settings.NoDoubleEscape{}: IO.pure(Unit,Unit{})
def triggerDouble(+input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,lastEscape,_,session,_,_,_}:
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
    case KeyInput{queue,_,failure,_,_,_,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitControl(queue,control)
        Interactive.submittedResult(failure,result)
def interrupted(+input: KeyInput,+text: String) -> IO(Unit):
  match input:
    case KeyInput{_,_,_,_,lastEscape,_,session,_,_,_}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        bash : Bool <- Session.isBashRunning(live)
        active : Bool <- Session.isStreaming(live)
        Bool.pick(Unit -> IO(Unit),bash,_ => Session.abortBash(live),_ => Bool.pick(Unit -> IO(Unit),active,_ => keyControl(input,Controller.Interrupt{text}),_ => Bool.pick(Unit -> IO(Unit),String.is_empty(Text.trim(text)),_ => idleEscape(input,lastEscape),_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{})
def doubleClear(previous: Maybe<&2,F64>,now: F64,stop: Deferred.Deferred<Unit>) -> IO(Unit):
  match previous:
    case Some{earlier}: Bool.pick(Unit -> IO(Unit),F64.is_lt(F.subtract(now,earlier),U32.to_f64(500)),_ => do IO<Unit>:
      settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
      return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
    case None{}: IO.pure(Unit,Unit{})
def cleared(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,stop,_,lastClear,_,_,_,_,_,_}:
      do IO<Unit>:
        +now : F64 <- Date.now()
        previous : Maybe<&2,F64> <- Ref.swap(Maybe<&2,F64>,lastClear,Some{now})
        doubleClear(previous,now,stop)
def queuedFollowUp(input: KeyInput,+text: String) -> IO(Unit):
  match input:
    case KeyInput{queue,_,failure,_,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Unit),String.is_empty(text),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submit(queue,Controller.Submission{text,Nil{},Some{Session.FollowUp{}}})
        Interactive.submittedResult(failure,result))(Unit{})
def exited(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,stop,_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
def toggleHeader(header: Maybe<&2,Header.Handle>) -> IO(Unit):
  match header:
    case Some{value}: Header.toggle(value)
    case None{}: IO.pure(Unit,Unit{})
def expandOutput(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,_,_,_,header,transcript}:
      do IO<Unit>:
        expanded : Bool <- Transcript.toggleExpanded(transcript)
        toggleHeader(header)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{Bool.pick(String,expanded,"Tool output: expanded","Tool output: collapsed")}})
def thinkingChanged(result: Result<&2,&2,String,Unit>,transcript: Transcript.Handle,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,+hidden: Bool) -> IO(Unit):
  match result:
    case Fail{reason}: Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandFailure{reason}})
    case Done{_}:
      do IO<Unit>:
        Transcript.setHideThinking(transcript,hidden)
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{Bool.pick(String,hidden,"Thinking blocks: hidden","Thinking blocks: visible")}})
def toggleThinking(input: KeyInput) -> IO(Unit):
  match input:
    case KeyInput{_,_,failure,_,_,_,session,_,_,transcript}:
      do IO<Unit>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        +hidden : Bool <- IO.pure(Bool,Bool.not(Settings.getHideThinkingBlock(settings)))
        result : Result<&2,&2,String,Unit> <- Session.changeSettings(live,current => Settings.setHideThinkingBlock(hidden,current))
        thinkingChanged(result,transcript,failure,hidden)
def keyAction(input: KeyInput,action: Editor.EditorAction) -> IO(Unit):
  match action:
    case Editor.ExpandTools{}: expandOutput(input)
    case Editor.ToggleThinking{}: toggleThinking(input)
    case Editor.Interrupt{text}: interrupted(input,text)
    case Editor.Dequeue{text}: keyControl(input,Controller.Dequeue{text})
    case Editor.Clear{}: cleared(input)
    case Editor.Exit{}: exited(input)
    case Editor.FollowUp{text}: queuedFollowUp(input,text)
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
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.CommandNotice{message}})
        Interactive.requestRender(redraw)
type RebindSink is Data:
  RebindSink{listener: Session.Listener(),transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footerRef: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>}
def reboundCopied(sink: RebindSink,+session: Session.AgentSession) -> IO(Unit):
  match sink:
    case RebindSink{listener,+transcript,editor,footerRef,failure,redraw,cwd,home}:
      do IO<Unit>:
        Session.subscribe(session,listener)
        +messages : List<&2,Session.Message()> <- Session.messages(session)
        Transcript.clear(transcript)
        settings : Settings.SettingsManager <- Session.getSettings(session)
        Transcript.setHideThinking(transcript,Settings.getHideThinkingBlock(settings))
        Transcript.seedSession(transcript,messages)
        state : Session.AgentState() <- Session.state(session)
        Ref.write(Footer.State,footerRef,initialFooter(state,messages,cwd,home))
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,None{})
        target : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        setSelectedDraft(target,"")
        Interactive.requestRender(redraw)
def rebound(sink: RebindSink,session: Session.AgentSession) -> IO(Unit):
  reboundCopied(sink,session)
def bindRebound(binding: Binding,listener: Session.Listener(),transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>) -> IO(Unit):
  match binding:
    case Binding{_,_,hook,_,_,_,_,_}:
      do IO<Unit>:
        callback : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~RebindSink,~Session.AgentSession,~Unit,~rebound,RebindSink{listener,transcript,editor,footer,failure,redraw,cwd,home})
        Ref.write(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook,Some{callback})
def bindOptional(mode: Maybe<&2,Binding>,listener: Session.Listener(),transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cwd: String,home: Maybe<&2,String>) -> IO(Unit):
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
    case Some{Binding{_,_,hook,_,_,_,_,_}}:
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
    case Some{Binding{current,_,_,_,_,_,_,_}}: IO.pure(Ref.Ref<Session.AgentSession>,current)
def controllerFor(mode: Maybe<&2,Binding>,current: Ref.Ref<Session.AgentSession>,session: Session.AgentSession,listener: Session.Listener(),limit: Nat,failure: Maybe<&2,Callback.Callback<Controller.PromptFailure,Unit>>,command: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,control: Maybe<&2,Callback.Callback<Controller.ControlResult,Unit>>,selection: Maybe<&2,Callback.Callback<Controller.SelectionResult,Unit>>,models: Ref.Ref<List<&2,Models.Model()>>,login: Callback.Callback<Commands.CredentialCommand,Unit>) -> IO(Controller.Controller & Controller.Handle):
  match mode:
    case None{}:
      do IO<Controller.Controller & Controller.Handle>:
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        Callback.dispose(Commands.CredentialCommand,Unit,login)
        Controller.start(session,listener,limit,failure,command,control,selection,available)
    case Some{Binding{_,newSession,_,_,_,_,_,_}}: Controller.startBound(current,listener,newSession,limit,failure,command,control,selection,models,Some{login})
def disposeInteraction(interaction: Interaction) -> IO(Unit):
  match interaction:
    case Interaction{editor,lastClear,lastEscape,selector,modelSelector,_,bashActivity}:
      do IO<Unit>:
        oldEditor : Maybe<&2,Live.Handle> <- Ref.dispose(Maybe<&2,Live.Handle>,editor)
        oldClear : Maybe<&2,F64> <- Ref.dispose(Maybe<&2,F64>,lastClear)
        oldEscape : Maybe<&2,F64> <- Ref.dispose(Maybe<&2,F64>,lastEscape)
        oldSelector : Maybe<&2,Selector.Host> <- Ref.dispose(Maybe<&2,Selector.Host>,selector)
        oldModelSelector : Maybe<&2,ModelPicker.Host> <- Ref.dispose(Maybe<&2,ModelPicker.Host>,modelSelector)
        oldBash : BashActivity <- Ref.dispose(BashActivity,bashActivity)
        disposeBashActivity(oldBash)
        return Unit{}
def startup(context: ThemeContext,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,stopped: Deferred.Deferred<Unit>,selected: Ref.Ref<Maybe<&2,ThemeController.Handle>>,owned: Ref.Ref<Maybe<&1,ThemeOwned>>,error: Ref.Ref<Maybe<&2,Theme.LoadError>>) -> ThemeStartup:
  match context:
    case ThemeContext{theme,transcript,_,setting,builtinDir,customDir,_,_,_,_,_}:
      ThemeStartup{redraw,queue,initial,failure,stopped,selected,owned,error,theme,transcript,setting,builtinDir,customDir}
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
def startInput(handle: ThemeController.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,render: Callback.Callback<Unit,Unit>) -> IO(Unit):
  match handle:
    case ThemeController.Handle{_,Process.QueryReady{queries,terminal,write,_},_,_,_,_}:
      Interactive.onReady(Interactive.Startup{redraw,queue,initial,failure},Process.QueryReady{queries,terminal,write,render})
def readySelected(result: Result<&2,&1,Theme.LoadError,ThemeController.Owner & ThemeController.Handle>,startup: ThemeStartup,+render: Callback.Callback<Unit,Unit>) -> IO(Unit):
  match result startup:
    case Done{(controller,+handle)} ThemeStartup{redraw,queue,initial,failure,_,+selected,owned,_,theme,transcript,_,_,_}:
      do IO<Unit>:
        Ref.write(Maybe<&2,ThemeController.Handle>,selected,Some{handle})
        Ref.write(Maybe<&1,ThemeOwned>,owned,Some{ThemeOwned{controller,render}})
        syncSelected(ThemeLive{selected,theme,transcript,render},handle)
        startInput(handle,redraw,queue,initial,failure,render)
    case Fail{cause} ThemeStartup{_,_,_,_,stopped,_,_,error,_,_,_,_,_}:
      do IO<Unit>:
        Callback.dispose(Unit,Unit,render)
        Ref.write(Maybe<&2,Theme.LoadError>,error,Some{cause})
        settled : Bool <- Deferred.resolve(Unit,stopped,Unit{})
        return Unit{}
def colorEnvironment(result: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match result:
    case Fail{_}: None{}
    case Done{value}: Some{value}
def themeReady(startup: ThemeStartup,ready: Process.QueryReady) -> IO(Unit):
  match startup ready:
    case ThemeStartup{redraw,queue,initial,failure,stopped,+selected,owned,error,+theme,+transcript,+setting,+builtinDir,+customDir} Process.QueryReady{queries,terminal,write,requestRender}:
      do IO<Unit>:
        +render : Callback.Callback<Unit,Unit> <- Callback.create(~ThemeLive,~Unit,~Unit,~syncRender,ThemeLive{selected,theme,transcript,requestRender})
        detected : Result<&1,&1,U32 & String,String> <- IO.get_env("COLORFGBG")
        result : Result<&2,&1,Theme.LoadError,ThemeController.Owner & ThemeController.Handle> <- ThemeController.start(Process.QueryReady{queries,terminal,write,render},setting,colorEnvironment(detected),builtinDir,customDir,Color.TrueColor{})
        readySelected(result,ThemeStartup{redraw,queue,initial,failure,stopped,selected,owned,error,theme,transcript,setting,builtinDir,customDir},render)
def closeTheme(current: Maybe<&1,ThemeOwned>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ThemeOwned{controller,render}}:
      do IO<Unit>:
        ThemeController.close(controller)
        Callback.dispose(Unit,Unit,render)
def themeStopping(stopping: ThemeStopping,_: Unit) -> IO(Unit):
  match stopping:
    case ThemeStopping{redraw,selected,owned}:
      do IO<Unit>:
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
def processMounted(mounted: View.View & View.Handle & Tui.ResultOf(Tui.TuiBase),document: Component.Component,editorComponent: Component.Component,+foot: FooterOwner,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match mounted:
    case (view,_,Fail{cause}): IO.pure(View.View & Result<&2,&2,Error,Unit>,(view,Fail{Layout{cause}}))
    case (view,_,Done{base}):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        +selected : Ref.Ref<Maybe<&2,ThemeController.Handle>> <- Ref.new(Maybe<&2,ThemeController.Handle>,None{})
        +owned : Ref.Ref<Maybe<&1,ThemeOwned>> <- Ref.new(Maybe<&1,ThemeOwned>,None{})
        +error : Ref.Ref<Maybe<&2,Theme.LoadError>> <- Ref.new(Maybe<&2,Theme.LoadError>,None{})
        +ready : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~ThemeStartup,~Process.QueryReady,~Unit,~themeReady,startup(context,redraw,queue,initial,footerFailure(foot),stopped,selected,owned,error))
        +stopping : Callback.Callback<Unit,Unit> <- Callback.create(~ThemeStopping,~Unit,~Unit,~themeStopping,ThemeStopping{redraw,selected,owned})
        +ids : List<&2,Component.ComponentId> <- IO.pure(List<&2,Component.ComponentId>,Component.ComponentId{1n} <> Component.ComponentId{2n} <> Component.ComponentId{3n} <> Nil{})
        +components : List<&2,Component.Component> <- IO.pure(List<&2,Component.Component>,document <> editorComponent <> footerComponent(foot) <> Nil{})
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{base,Screen.initial()},components,ids),stopped,False{},ready,stopping)
        Callback.dispose(Process.QueryReady,Unit,ready)
        Callback.dispose(Unit,Unit,stopping)
        oldSelected : Maybe<&2,ThemeController.Handle> <- Ref.dispose(Maybe<&2,ThemeController.Handle>,selected)
        oldOwned : Maybe<&1,ThemeOwned> <- Ref.dispose(Maybe<&1,ThemeOwned>,owned)
        failure : Maybe<&2,Theme.LoadError> <- Ref.dispose(Maybe<&2,Theme.LoadError>,error)
        return (view,processThemeResult(outcome,failure))

def processEditorBorrowed(borrowed: View.View & Component.Component & View.Handle,+editorComponent: Component.Component,+foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,document,_):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        mounted : View.View & View.Handle & Tui.ResultOf(Tui.TuiBase) <- View.mount(view,editorComponent,footerComponent(foot))
        processMounted(mounted,document,editorComponent,foot,stopped,redraw,queue,initial,context)
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
def finish(outcome: View.View & Result<&2,&2,Error,Unit>,transcript: Transcript.Owner,live: Live.Owner,foot: FooterOwner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<Editor.EditorAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,stopped: Deferred.Deferred<Unit>,+interaction: Interaction,+session: Ref.Ref<Session.AgentSession>,+mode: Maybe<&2,Binding>,+login: LoginState) -> IO(Result<&2,&2,Error,Unit>):
  match outcome:
    case (view,result):
      do IO<Result<&2,&2,Error,Unit>>:
        awaitBash(bashActivityOf(interaction),session)
        unbind(mode)
        Transcript.dispose(transcript)
        View.dispose(view)
        Live.dispose(live)
        disposeFooter(foot)
        Callback.dispose(String,Unit,submitted)
        Callback.dispose(Editor.EditorAction,Unit,keys)
        Callback.dispose(String,String,paint)
        MarkdownTheme.dispose(styles)
        oldRows : Nat <- Ref.dispose(Nat,rows)
        oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
        Deferred.dispose(Unit,stopped)
        disposeInteraction(interaction)
        disposeLoginState(login)
        finishSessionRef(session,mode)
        return result

def setLoginHost(state: LoginState,value: Maybe<&2,LoginDialog.Host>) -> IO(Unit):
  match state: case LoginState{target,_,_,_,_,_,_,_}: Ref.write(Maybe<&2,LoginDialog.Host>,target,value)
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
def runPickerHosted(borrowed: SessionPicker.HostOwner & SessionPicker.Host & Component.Component,retained: ModelPicker.Owner,tree: Selector.Owner,live: Live.Owner,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<Editor.EditorAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<Models.Model(),Unit>,resumeChosen: Callback.Callback<String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (picker,pickerHost,component):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)),Some{pickerHost})
        +cancel : Callback.Callback<Unit,Unit> <- Callback.create(~LoginState,~Unit,~Unit,~cancelLogin,contextLogin(context))
        dialog : LoginDialog.Owner <- LoginDialog.create(component,contextTheme(context),Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),cancel)
        outcome : View.View & Result<&2,&2,Error,Unit> <- runLoginHosted(LoginDialog.borrow(dialog),view,foot,stopped,redraw,queue,controller,initial,context)
        Callback.dispose(Unit,Unit,cancel)
        Ref.write(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)),None{})
        SessionPicker.disposeHost(picker)
        Callback.dispose(String,Unit,resumeChosen)
        oldPicker : Maybe<&2,SessionPicker.Host> <- Ref.dispose(Maybe<&2,SessionPicker.Host>,resumePickerRef(contextResume(context)))
        Ref.write(Maybe<&2,ModelPicker.Host>,modelSelectorRefOf(contextInteraction(context)),None{})
        Ref.write(Maybe<&2,Selector.Host>,selectorRefOf(contextInteraction(context)),None{})
        ModelPicker.disposeHost(retained)
        Selector.disposeHost(tree)
        Callback.dispose(Models.Model(),Unit,modelChosen)
        Callback.dispose(Selector.Choice,Unit,treeChosen)
        finish(outcome,transcript,live,foot,submitted,keys,paint,styles,rows,redraw,stopped,contextInteraction(context),contextSession(context),contextBinding(context),contextLogin(context))
def runModelHosted(borrowed: ModelPicker.Owner & ModelPicker.Host & Component.Component,tree: Selector.Owner,treeHandle: Selector.Host,live: Live.Owner,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<Editor.EditorAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,treeChosen: Callback.Callback<Selector.Choice,Unit>,modelChosen: Callback.Callback<Models.Model(),Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (retained,modelHandle,modal):
      do IO<Result<&2,&2,Error,Unit>>:
        Ref.write(Maybe<&2,Selector.Host>,selectorRefOf(contextInteraction(context)),Some{treeHandle})
        Ref.write(Maybe<&2,ModelPicker.Host>,modelSelectorRefOf(contextInteraction(context)),Some{modelHandle})
        +resumeChosen : Callback.Callback<String,Unit> <- Callback.create(~ResumeState,~String,~Unit,~resumePicked,contextResume(context))
        picker : SessionPicker.HostOwner <- SessionPicker.createHost(modal,Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),resumeChosen)
        runPickerHosted(SessionPicker.borrowHost(picker),retained,tree,live,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,treeChosen,modelChosen,resumeChosen)
def runHosted(borrowed: Selector.Owner & Selector.Host & Component.Component,live: Live.Owner,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<Editor.EditorAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext,chosen: Callback.Callback<Selector.Choice,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (tree,treeHandle,component):
      do IO<Result<&2,&2,Error,Unit>>:
        +modelChosen : Callback.Callback<Models.Model(),Unit> <- Callback.create(~SelectInput,~Models.Model(),~Unit,~chosenModel,SelectInput{queue,footerFailure(foot),redraw})
        modelHost : ModelPicker.Owner <- ModelPicker.createHost(component,contextTheme(context),Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),modelChosen)
        runModelHosted(ModelPicker.borrowHost(modelHost),tree,treeHandle,live,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,chosen,modelChosen)
def runLive(borrowed: Live.Owner & Component.Component & Live.Handle,view: View.View,+foot: FooterOwner,controller: Controller.Controller,+queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,keys: Callback.Callback<Editor.EditorAction,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (live,component,handle):
      do IO<Result<&2,&2,Error,Unit>>:
        recordEditor(contextInteraction(context),handle)
        +chosen : Callback.Callback<Selector.Choice,Unit> <- Callback.create(~SelectInput,~Selector.Choice,~Unit,~chosenSelection,SelectInput{queue,footerFailure(foot),redraw})
        host : Selector.Owner <- Selector.createHost(component,contextTheme(context),Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),chosen)
        runHosted(Selector.borrowHost(host),live,view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context,chosen)
def startPaint(pair: Callback.Callback<String,String> & Editor.EditorTheme,controller: Controller.Controller,+queue: Controller.Handle,+submitted: Callback.Callback<String,Unit>,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,+foot: FooterOwner,words: Words.Context,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (paint,uiTheme):
      do IO<Result<&2,&2,Error,Unit>>:
        editor : Editor.Editor <- Editor.new(uiTheme,None{})
        +keys : Callback.Callback<Editor.EditorAction,Unit> <- Callback.create(~KeyInput,~Editor.EditorAction,~Unit,~keyAction,keyInput(queue,stopped,footerFailure(foot),contextInteraction(context),contextSession(context),redraw,contextTranscript(context)))
        +configured : Editor.Editor <- IO.pure(Editor.Editor,Editor.setCallbacks(editor,Editor.EditorCallbacks{None{},Some{submitted},None{},Some{keys}}))
        +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
        live : Live.Owner <- Live.create(Component.ComponentId{2n},configured,words,Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),rows)
        runLive(Live.borrow(live),view,foot,controller,queue,transcript,submitted,keys,paint,styles,rows,redraw,stopped,initial,context)
def startController(pair: Controller.Controller & Controller.Handle,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,+foot: FooterOwner,words: Words.Context,+stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+context: ThemeContext) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (controller,+queue):
      do IO<Result<&2,&2,Error,Unit>>:
        submitted : Callback.Callback<String,Unit> <- Callback.create(~Interactive.SubmissionInput,~String,~Unit,~Interactive.submitted,Interactive.SubmissionInput{queue,stopped,footerFailure(foot)})
        paintPair : Callback.Callback<String,String> & Editor.EditorTheme <- editorTheme(contextTheme(context))
        startPaint(paintPair,controller,queue,submitted,view,transcript,styles,initial,foot,words,stopped,redraw,context)
def startTranscript(borrowed: Transcript.Owner & Transcript.Handle,view: View.View,viewHandle: View.Handle,styles: MarkdownTheme.Styles,+liveTheme: Ref.Ref<Theme.Theme>,+session: Session.AgentSession,initial: List<&2,Controller.Submission>,+cwd: String,+home: Maybe<&2,String>,words: Words.Context,setting: Maybe<&2,String>,+builtinDir: String,customDir: String,+models: List<&2,Models.Model()>,+mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (transcript,+transcriptHandle):
      do IO<Result<&2,&2,Error,Unit>>:
        +existing : List<&2,Session.Message()> <- Session.messages(session)
        settings : Settings.SettingsManager <- Session.getSettings(session)
        Transcript.setHideThinking(transcriptHandle,Settings.getHideThinkingBlock(settings))
        Transcript.seedSession(transcriptHandle,existing)
        agentState : Session.AgentState() <- Session.state(session)
        +current : Ref.Ref<Session.AgentSession> <- modeCurrent(mode,session)
        +foot : FooterOwner <- footer(initialFooter(agentState,existing,cwd,home),liveTheme,current)
        +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
        +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        +listener : Callback.Callback<Session.AgentSessionEvent,Unit> <- Callback.create(~Observation,~Session.AgentSessionEvent,~Unit,~observed,Observation{transcriptHandle,redraw,footerState(foot)})
        failureObserver : Callback.Callback<Controller.PromptFailure,Unit> <- Callback.create(~WorkerFailure,~Controller.PromptFailure,~Unit,~promptFailed,WorkerFailure{footerFailure(foot),redraw})
        +modelSelectorRef : Ref.Ref<Maybe<&2,ModelPicker.Host>> <- Ref.new(Maybe<&2,ModelPicker.Host>,None{})
        +selectorRef : Ref.Ref<Maybe<&2,Selector.Host>> <- Ref.new(Maybe<&2,Selector.Host>,None{})
        +modelsRef : Ref.Ref<List<&2,Models.Model()>> <- Ref.new(List<&2,Models.Model()>,models)
        +loginHost : Ref.Ref<Maybe<&2,LoginDialog.Host>> <- Ref.new(Maybe<&2,LoginDialog.Host>,None{})
        +resumePicker : Ref.Ref<Maybe<&2,SessionPicker.Host>> <- Ref.new(Maybe<&2,SessionPicker.Host>,None{})
        +loginAbort : Ref.Ref<Maybe<&2,Abort.AbortController<Unit>>> <- Ref.new(Maybe<&2,Abort.AbortController<Unit>>,None{})
        +loginState : LoginState <- IO.pure(LoginState,loginStateOf(mode,loginHost,loginAbort,modelsRef,footerFailure(foot),redraw,current))
        +resumeState : ResumeState <- IO.pure(ResumeState,resumeStateOf(mode,resumePicker,loginHost,footerFailure(foot),redraw))
        loginCallback : Callback.Callback<Commands.CredentialCommand,Unit> <- Callback.create(~LoginState,~Commands.CredentialCommand,~Unit,~credentialRun,loginState)
        +commandSink : Interactive.CommandSink <- IO.pure(Interactive.CommandSink,Interactive.CommandSink{footerFailure(foot),redraw,modelSelectorRef,current,modelsRef})
        +editorHandle : Ref.Ref<Maybe<&2,Live.Handle>> <- Ref.new(Maybe<&2,Live.Handle>,None{})
        +bashActivity : Ref.Ref<BashActivity> <- Ref.new(BashActivity,BashActivity{False{},False{},None{}})
        commandObserver : Callback.Callback<Commands.Action,Unit> <- Callback.create(~CommandObservation,~Commands.Action,~Unit,~commandObserved,CommandObservation{commandSink,current,footerState(foot),footerFailure(foot),redraw,cwd,builtinDir,importStateOf(mode,loginHost,footerFailure(foot),redraw),resumeState,selectorRef,BashInput{current,transcriptHandle,editorHandle,footerFailure(foot),redraw,bashActivity}})
        +lastClear : Ref.Ref<Maybe<&2,F64>> <- Ref.new(Maybe<&2,F64>,None{})
        +lastEscape : Ref.Ref<Maybe<&2,F64>> <- Ref.new(Maybe<&2,F64>,None{})
        selectionObserver : Callback.Callback<Controller.SelectionResult,Unit> <- Callback.create(~SelectionSink,~Controller.SelectionResult,~Unit,~selectionResult,SelectionSink{current,transcriptHandle,editorHandle,footerState(foot),footerFailure(foot),redraw,cwd,home})
        controlObserver : Callback.Callback<Controller.ControlResult,Unit> <- Callback.create(~ControlSink,~Controller.ControlResult,~Unit,~controlResult,ControlSink{editorHandle,footerFailure(foot),redraw})
        bindOptional(mode,listener,transcriptHandle,editorHandle,footerState(foot),footerFailure(foot),redraw,cwd,home)
        controllerPair : Controller.Controller & Controller.Handle <- controllerFor(mode,current,session,listener,32n,Some{failureObserver},Some{commandObserver},Some{controlObserver},Some{selectionObserver},modelsRef,loginCallback)
        startController(controllerPair,view,transcript,styles,initial,foot,words,stopped,redraw,ThemeContext{liveTheme,transcriptHandle,current,setting,builtinDir,customDir,Interaction{editorHandle,lastClear,lastEscape,selectorRef,modelSelectorRef,View.headerHandle(viewHandle),bashActivity},modelsRef,mode,loginState,resumeState})
def startStyles(styles: MarkdownTheme.Styles,view: View.View,+viewHandle: View.Handle,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Context,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match styles:
    case MarkdownTheme.Styles{+markdown,callbacks,+live}:
      do IO<Result<&2,&2,Error,Unit>>:
        transcript : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
        startTranscript(Transcript.borrow(transcript),view,viewHandle,MarkdownTheme.Styles{markdown,callbacks,live},live,session,initial,cwd,home,words,setting,builtinDir,customDir,models,mode)
def startView(borrowed: View.View & Component.Component & View.Handle,styles: MarkdownTheme.Styles,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,theme: Theme.Theme,words: Words.Context,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,_,viewHandle):
      startStyles(styles,view,viewHandle,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def withHeader(styles: MarkdownTheme.Styles,quiet: Bool) -> IO(View.View & MarkdownTheme.Styles):
  match styles:
    case MarkdownTheme.Styles{markdown,callbacks,+live}:
      do IO<View.View & MarkdownTheme.Styles>:
        view : View.View <- View.createWithHeader(Component.ComponentId{1n},live,quiet)
        return (view,MarkdownTheme.Styles{markdown,callbacks,live})
def prepared(pair: View.View & MarkdownTheme.Styles,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,theme: Theme.Theme,words: Words.Context,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (view,styles): startView(View.borrow(view),styles,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def started(+session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Context,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    styles : MarkdownTheme.Styles <- MarkdownTheme.create(theme)
    settings : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,Session.settingsOf(session))
    pair : View.View & MarkdownTheme.Styles <- withHeader(styles,Settings.getQuietStartup(settings))
    prepared(pair,session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def themed(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,words: Words.Context,loaded: Result<&2,&2,Theme.LoadError,Theme.Theme>,setting: Maybe<&2,String>,builtinDir: String,customDir: String,models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Unit>,Fail{ThemeData{cause}})
    case Done{theme}: started(session,initial,cwd,home,theme,words,setting,builtinDir,customDir,models,mode)
def withWords(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,assetsRoot: String,setting: Maybe<&2,String>,loaded: Words.Loaded(Words.Context),models: List<&2,Models.Model()>,mode: Maybe<&2,Binding>) -> IO(Result<&2,&2,Error,Unit>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Unit>,Fail{WordData{cause}})
    case Done{words}:
      do IO<Result<&2,&2,Error,Unit>>:
        +builtinDir : String <- IO.pure(String,Path.join(assetsRoot,"packages/coding-agent/src/modes/interactive/theme"))
        +customDir : String <- IO.pure(String,Path.join(agentDir,"themes"))
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName("dark",builtinDir,customDir,Color.TrueColor{})
        themed(session,initial,cwd,home,words,theme,setting,builtinDir,customDir,models,mode)
def run(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,+assetsRoot: String,themeSetting: Maybe<&2,String>,models: List<&2,Models.Model()>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    words : Words.Loaded(Words.Context) <- Words.loadDefault(Path.join(assetsRoot,"packages/runtime/data"))
    withWords(session,initial,cwd,home,agentDir,assetsRoot,themeSetting,words,models,None{})
def runBound(session: Session.AgentSession,binding: Binding,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,+assetsRoot: String,themeSetting: Maybe<&2,String>,models: List<&2,Models.Model()>) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    words : Words.Loaded(Words.Context) <- Words.loadDefault(Path.join(assetsRoot,"packages/runtime/data"))
    withWords(session,initial,cwd,home,agentDir,assetsRoot,themeSetting,words,models,Some{binding})
