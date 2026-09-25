import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/text.bend as Text
import ../../../../tui/src/tui-process.bend as Process
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ../../core/model-runtime.bend as Models
import ../../../../ai/src/auth/types.bend as Auth
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/models.bend as AiModels
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../runtime/src/collation.bend as Collation
import ../../../../runtime/src/stable-sort.bend as Sort
import ../../../../tui/src/autocomplete.bend as AC
import ../../../../tui/src/fuzzy.bend as Fuzzy
import ../../core/prompt-templates.bend as Templates
import ../../core/settings-manager.bend as Settings
import ../../core/skills.bend as Skills
import ../../core/slash-commands.bend as Slash
import ../../core/diagnostics.bend as Diagnostics
import ../../core/extensions/runner.bend as ExtensionRunner
import ../../core/extensions/types.bend as ExtensionTypes
import ./model-search.bend as Search
import ./components/model-selector.bend as ModelPicker
import ./components/thinking-selector.bend as ThinkingPicker
import ./components/scoped-models-selector.bend as ScopePicker
import ./session-controller.bend as Controller
import ./commands.bend as Commands
import ./transcript.bend as Transcript

# Model work runs in SessionController's worker. These callbacks only publish
# immutable event snapshots and ask the TUI process for another frame.
type Events is Data:
  Events{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SubmissionFailure is Data:
  QueueFailure{cause: Controller.SubmitError}
  PromptFailure{message: String}
  CommandFailure{message: String}
  CommandWarning{message: String}
  CommandNotice{message: String}
type StatusSink is Data:
  StatusSink{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SubmissionInput is Data:
  SubmissionInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: StatusSink}
type CommandSink is Data:
  CommandSink{failure: StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,thinking: Ref.Ref<Maybe<&2,ThinkingPicker.Host>>,scoped: Ref.Ref<Maybe<&2,ScopePicker.Host>>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>}
type Startup is Data:
  Startup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: StatusSink}

def failureText(failure: SubmissionFailure) -> String:
  match failure:
    case QueueFailure{Controller.Full{}}: "Submission queue is full"
    case QueueFailure{Controller.Closed{}}: "Session is closed"
    case PromptFailure{message}: message
    case CommandFailure{message}: message
    case CommandWarning{message}: message
    case CommandNotice{message}: message

def renderRequested(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(Unit,Unit,value,Unit{})
def requestRender(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    renderRequested(callback)
def observed(events: Events,event: Session.SessionEvent()) -> IO(Unit):
  match events:
    case Events{transcript,redraw}:
      do IO<Unit>:
        changed : Bool <- Transcript.accept(Unit,Runtime.Custom(),transcript,event)
        Bool.pick(Unit -> IO(Unit),changed,_ => requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def onSessionEvent(events: Events,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{value}: observed(events,value)
    case _: IO.pure(Unit,Unit{})
def report(sink: StatusSink,status: SubmissionFailure) -> IO(Unit):
  match sink status:
    case StatusSink{transcript,redraw} CommandNotice{message}:
      do IO<Unit>:
        Transcript.status(transcript,message)
        requestRender(redraw)
    case StatusSink{transcript,redraw} CommandWarning{message}:
      do IO<Unit>:
        Transcript.showWarning(transcript,message)
        requestRender(redraw)
    case StatusSink{transcript,redraw} other:
      do IO<Unit>:
        Transcript.showError(transcript,failureText(other))
        requestRender(redraw)
def submittedResult(failure: StatusSink,result: Result<&2,&2,Controller.SubmitError,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{cause}: report(failure,QueueFailure{cause})
def commandStatus(failure: StatusSink,status: SubmissionFailure) -> IO(Unit): report(failure,status)
def pickerCurrent(session: Session.AgentSession) -> IO(Maybe<&2,Models.Model()>):
  do IO<Maybe<&2,Models.Model()>>:
    current : Session.AgentState() <- Session.state(session)
    return Session.stateModel(current)
def referenceOf(provider: Maybe<&2,String>,model: Maybe<&2,String>) -> Maybe<&2,String>:
  match provider model:
    case Some{provider} Some{model}: Some{provider ++ "/" ++ model}
    case _ _: None{}
def defaultReference(+settings: Settings.SettingsManager) -> Maybe<&2,String>:
  referenceOf(Settings.getDefaultProvider(settings),Settings.getDefaultModel(settings))
def openPicker(host: Maybe<&2,ModelPicker.Host>,models: List<&2,Models.Model()>,scoped: List<&2,Models.ScopedModel>,current: Maybe<&2,Models.Model()>,query: Maybe<&2,String>,defaultRef: Maybe<&2,String>) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: ModelPicker.open(value,ModelPicker.createScoped(models,Session.scopedModels(scoped),current,Maybe.default(&2,String,query,""),defaultRef))
def refreshErrorNames(errors: List<&2,Record.Property<String>>) -> List<&2,String>:
  match errors:
    case Nil{}: Nil{}
    case Record.Property{provider,_} <> rest: provider <> refreshErrorNames(rest)
def refreshErrorStatus(+errors: List<&2,Record.Property<String>>) -> String:
  match errors:
    case Nil{}: "Model catalogs refreshed."
    case Record.Property{provider,_} <> Nil{}: "Could not refresh " ++ provider ++ "; showing cached models."
    case _: "Could not refresh " ++ Nat.show(List.length(&2,Record.Property<String>,errors)) ++ " model catalogs (" ++ String.join(refreshErrorNames(errors),", ") ++ "); showing cached models."
def refreshStatus(result: Models.ModelsRefreshResult) -> String:
  match result:
    case Models.ModelsRefreshResult{True{},_}: "Model refresh was canceled; showing cached models."
    case Models.ModelsRefreshResult{_,errors}: refreshErrorStatus(Record.entries(String,errors))
def heldRender(+current: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Maybe<&2,Callback.Callback<Unit,Unit>> & Unit):
  do IO<Maybe<&2,Callback.Callback<Unit,Unit>> & Unit>:
    renderRequested(current)
    return (current,Unit{})
def requestRenderIfLive(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    ignored : Maybe<&1,Unit> <- Ref.tryUpdate(Maybe<&2,Callback.Callback<Unit,Unit>>,Unit,redraw,current => heldRender(current))
    return Unit{}
def replacedModels(_old: List<&2,Models.Model()>,next: List<&2,Models.Model()>) -> List<&2,Models.Model()> & Unit:
  (next,Unit{})
def refreshPicker(host: ModelPicker.Host,catalog: Ref.Ref<List<&2,Models.Model()>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+runtime: Models.ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    result : Models.ModelsRefreshResult <- Models.refresh(runtime,Models.refreshOptions())
    +available : List<&2,Models.Model()> <- Models.getAvailable(runtime)
    updated : Maybe<&1,Unit> <- Ref.tryModify(List<&2,Models.Model()>,Unit,catalog,previous => replacedModels(previous,available))
    shown : Bool <- ModelPicker.refreshed(host,available,refreshStatus(result))
    Bool.pick(Unit -> IO(Unit),shown,_ => requestRenderIfLive(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def startPickerRefresh(host: Maybe<&2,ModelPicker.Host>,catalog: Ref.Ref<List<&2,Models.Model()>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,runtime: Models.ModelRuntime) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{current}: IO.spawn(Unit,refreshPicker(current,catalog,redraw,runtime))
def openPickerResult(failure: StatusSink,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,catalog: Ref.Ref<List<&2,Models.Model()>>,+session: Session.AgentSession,models: List<&2,Models.Model()>,search: Maybe<&2,String>,refresh: Bool) -> IO(Bool):
  match models:
    case Nil{}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{"No models available. Use /login to add a provider."})
        requestRender(redraw)
        return False{}
    case model <> rest:
      do IO<Bool>:
        +current : Maybe<&2,Models.Model()> <- pickerCurrent(session)
        scoped : List<&2,Models.ScopedModel> <- Session.getScopedModels(session)
        settings : Settings.SettingsManager <- Session.getSettings(session)
        +target : Maybe<&2,ModelPicker.Host> <- Ref.read(Maybe<&2,ModelPicker.Host>,picker)
        openPicker(target,model <> rest,scoped,current,search,defaultReference(settings))
        requestRender(redraw)
        Bool.pick(Unit -> IO(Unit),refresh,_ => startPickerRefresh(target,catalog,redraw,Session.modelRuntime(session)),_ => IO.pure(Unit,Unit{}))(Unit{})
        return False{}
def deadlineResult(controller: Abort.AbortController<Unit>,result: Timer & Bool) -> IO(Unit):
  match result:
    case (timer,elapsed):
      do IO<Unit>:
        Timer.close(timer)
        Bool.pick(Unit -> IO(Unit),elapsed,_ => do IO<Unit>:
          won : Bool <- Abort.abort(Unit,controller,None{})
          return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
def modelRefreshDeadline(controller: Abort.AbortController<Unit>,owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    deadlineResult(controller,result)
def refreshWithTimer(runtime: Models.ModelRuntime,+controller: Abort.AbortController<Unit>,timer: Timer & TimerCancel) -> IO(Models.ModelsRefreshResult & Bool):
  match timer:
    case (owner,cancel):
      do IO<Models.ModelsRefreshResult & Bool>:
        task : Chan(Unit) <- IO.fork(Unit,modelRefreshDeadline(controller,owner))
        result : Models.ModelsRefreshResult <- Models.refresh(runtime,Models.ModelsRefreshOptions{None{},None{},None{},Some{Abort.signal(Unit,controller)}})
        cancelled : Bool <- Timer.cancel(cancel)
        IO.join(Unit,task)
        timedOut : Bool <- Abort.aborted(Unit,Abort.signal(Unit,controller))
        Abort.dispose(Unit,controller)
        return (result,timedOut)
def refreshModelMatch(runtime: Models.ModelRuntime) -> IO(Models.ModelsRefreshResult & Bool):
  do IO<Models.ModelsRefreshResult & Bool>:
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    timer : Timer & TimerCancel <- Timer.new(15000)
    refreshWithTimer(runtime,controller,timer)
def refreshErrorWarning(failure: StatusSink,errors: List<&2,Record.Property<String>>) -> IO(Unit):
  match errors:
    case Nil{}: IO.pure(Unit,Unit{})
    case first <> rest: commandStatus(failure,CommandWarning{refreshErrorStatus(first <> rest)})
def modelRefreshWarning(+failure: StatusSink,result: Models.ModelsRefreshResult,timedOut: Bool) -> IO(Unit):
  match result:
    case Models.ModelsRefreshResult{aborted,errors}:
      Bool.pick(Unit -> IO(Unit),timedOut,_ => commandStatus(failure,CommandWarning{"Model refresh timed out; searching cached models."}),_ =>
        Bool.pick(Unit -> IO(Unit),aborted,_ => commandStatus(failure,CommandWarning{"Model refresh was canceled; searching cached models."}),_ =>
          refreshErrorWarning(failure,Record.entries(String,errors)))(Unit{}))(Unit{})
def selectionResult(+failure: StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,model: Models.Model(),selected: Result<&2,&2,String,Unit>) -> IO(Bool):
  match selected:
    case Done{_}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{"Model: " ++ Models.modelId(model)})
        requestRender(redraw)
        return True{}
    case Fail{reason}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{reason})
        return False{}
def refreshedSelection(failure: StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,session: Session.AgentSession,+model: Models.Model()) -> IO(Bool):
  do IO<Bool>:
    selected : Result<&2,&2,String,Unit> <- Session.setModel(session,model,Session.ModelMutationOptions{False{}})
    selectionResult(failure,redraw,model,selected)
def refreshedModelMatch(+failure: StatusSink,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,catalog: Ref.Ref<List<&2,Models.Model()>>,session: Session.AgentSession,+query: String,models: List<&2,Models.Model()>,found: Maybe<&2,Models.Model()>) -> IO(Bool):
  match found:
    case Some{model}: refreshedSelection(failure,redraw,session,model)
    case None{}: openPickerResult(failure,redraw,picker,catalog,session,models,Some{query},False{})
def refreshedModelResult(failure: StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,catalog: Ref.Ref<List<&2,Models.Model()>>,session: Session.AgentSession,+query: String,+models: List<&2,Models.Model()>) -> IO(Bool):
  refreshedModelMatch(failure,redraw,picker,catalog,session,query,models,Commands.exactModel(models,query))
def refreshedOrCached(cached: List<&2,Models.Model()>,available: List<&2,Models.Model()>) -> List<&2,Models.Model()>:
  match available:
    case Nil{}: cached
    case model <> rest: model <> rest
def showRefreshedPicker(host: Maybe<&2,ModelPicker.Host>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,models: List<&2,Models.Model()>,status: String) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}:
      do IO<Unit>:
        changed : Bool <- ModelPicker.refreshed(value,models,status)
        Bool.pick(Unit -> IO(Unit),changed,_ => requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def pickerRefreshDone(picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,models: List<&2,Models.Model()>,status: String) -> IO(Unit):
  do IO<Unit>:
    host : Maybe<&2,ModelPicker.Host> <- Ref.read(Maybe<&2,ModelPicker.Host>,picker)
    showRefreshedPicker(host,redraw,models,status)
def requestedAfterRefresh(+failure: StatusSink,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,+catalog: Ref.Ref<List<&2,Models.Model()>>,+session: Session.AgentSession,+query: String,cached: List<&2,Models.Model()>,result: Models.ModelsRefreshResult & Bool) -> IO(Bool):
  match result:
    case (+outcome,timedOut):
      do IO<Bool>:
        modelRefreshWarning(failure,outcome,timedOut)
        available : List<&2,Models.Model()> <- Models.getAvailable(Session.modelRuntime(session))
        +visible : List<&2,Models.Model()> <- IO.pure(List<&2,Models.Model()>,refreshedOrCached(cached,available))
        Ref.write(List<&2,Models.Model()>,catalog,visible)
        selected : Bool <- refreshedModelResult(failure,redraw,picker,catalog,session,query,visible)
        pickerRefreshDone(picker,redraw,visible,refreshStatus(outcome))
        return selected
def requestedWithinScope(+failure: StatusSink,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,+catalog: Ref.Ref<List<&2,Models.Model()>>,+session: Session.AgentSession,+query: String,models: List<&2,Models.Model()>,scoped: List<&2,Models.ScopedModel>) -> IO(Bool):
  match scoped:
    case _ <> _: openPickerResult(failure,redraw,picker,catalog,session,models,Some{query},True{})
    case Nil{}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{"Refreshing model catalogs…"})
        result : Models.ModelsRefreshResult & Bool <- refreshModelMatch(Session.modelRuntime(session))
        requestedAfterRefresh(failure,redraw,picker,catalog,session,query,models,result)
def requestedModel(failure: StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,catalog: Ref.Ref<List<&2,Models.Model()>>,+session: Session.AgentSession,+query: String,models: List<&2,Models.Model()>) -> IO(Bool):
  do IO<Bool>:
    scoped : List<&2,Models.ScopedModel> <- Session.getScopedModels(session)
    requestedWithinScope(failure,redraw,picker,catalog,session,query,models,scoped)
def openModelCommand(+failure: StatusSink,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,catalog: Ref.Ref<List<&2,Models.Model()>>,session: Session.AgentSession,models: List<&2,Models.Model()>,search: Maybe<&2,String>) -> IO(Bool):
  match search:
    case None{}: openPickerResult(failure,redraw,picker,catalog,session,models,None{},True{})
    case Some{query}: requestedModel(failure,redraw,picker,catalog,session,query,models)
def showThinking(picker: Maybe<&2,ThinkingPicker.Host>,levels: List<&2,Ai.ModelThinkingLevel>,current: Ai.ModelThinkingLevel,defaultLevel: Ai.ModelThinkingLevel) -> IO(Unit):
  match picker:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: ThinkingPicker.open(host,ThinkingPicker.create(levels,current,defaultLevel))
def openThinking(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ThinkingPicker.Host>>,+session: Session.AgentSession) -> IO(Bool):
  do IO<Bool>:
    agent : Session.AgentState() <- Session.state(session)
    settings : Settings.SettingsManager <- Session.getSettings(session)
    levels : List<&2,Ai.ModelThinkingLevel> <- Session.getAvailableThinkingLevels(session)
    host : Maybe<&2,ThinkingPicker.Host> <- Ref.read(Maybe<&2,ThinkingPicker.Host>,picker)
    showThinking(host,levels,Session.stateThinking(agent),Maybe.default(&2,Ai.ModelThinkingLevel,Settings.getDefaultThinkingLevel(settings),Ai.Thinking{Ai.Medium{}}))
    requestRender(redraw)
    return False{}
def scopedIds(items: List<&2,Models.ScopedModel>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case Models.ScopedModel{model,_} <> rest: Models.reference(model) <> scopedIds(rest)
def resolvedResult(patterns: List<&2,String>,result: Result<&2,&2,String,List<&2,Models.ScopedModel>>) -> List<&2,String>:
  match result:
    case Done{scope}: scopedIds(scope)
    case Fail{_}: patterns
def resolvedIds(+patterns: List<&2,String>,models: List<&2,Models.Model()>) -> List<&2,String>:
  resolvedResult(patterns,Models.resolveScope(patterns,models,Nil{}))
def configuredScope(configured: Maybe<&2,List<&2,String>>,models: List<&2,Models.Model()>) -> ScopePicker.Scope:
  match configured:
    case None{}: ScopePicker.All{}
    case Some{Nil{}}: ScopePicker.All{}
    case Some{patterns}: ScopePicker.Selected{resolvedIds(patterns,models)}
def initialScope(scoped: List<&2,Models.ScopedModel>,configured: Maybe<&2,List<&2,String>>,models: List<&2,Models.Model()>) -> ScopePicker.Scope:
  match scoped:
    case Nil{}: configuredScope(configured,models)
    case _: ScopePicker.Selected{scopedIds(scoped)}
def showScoped(picker: Maybe<&2,ScopePicker.Host>,models: List<&2,Models.Model()>,scope: ScopePicker.Scope) -> IO(Unit):
  match picker:
    case None{}: IO.pure(Unit,Unit{})
    case Some{host}: ScopePicker.open(host,ScopePicker.create(models,scope,"Refreshing model catalogs…"))
def refreshScoped(host: ScopePicker.Host,models: Ref.Ref<List<&2,Models.Model()>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+runtime: Models.ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    result : Models.ModelsRefreshResult <- Models.refresh(runtime,Models.refreshOptions())
    +available : List<&2,Models.Model()> <- Models.getAvailable(runtime)
    Ref.write(List<&2,Models.Model()>,models,available)
    ScopePicker.refreshed(host,available,refreshStatus(result))
    requestRender(redraw)
def startScopeRefresh(host: Maybe<&2,ScopePicker.Host>,models: Ref.Ref<List<&2,Models.Model()>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,runtime: Models.ModelRuntime) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{current}: IO.spawn(Unit,refreshScoped(current,models,redraw,runtime))
def openScoped(+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ScopePicker.Host>>,+session: Session.AgentSession,+models: Ref.Ref<List<&2,Models.Model()>>) -> IO(Bool):
  do IO<Bool>:
    +available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
    settings : Settings.SettingsManager <- Session.getSettings(session)
    scoped : List<&2,Models.ScopedModel> <- Session.getScopedModels(session)
    +host : Maybe<&2,ScopePicker.Host> <- Ref.read(Maybe<&2,ScopePicker.Host>,picker)
    showScoped(host,available,initialScope(scoped,Settings.getEnabledModels(settings),available))
    requestRender(redraw)
    startScopeRefresh(host,models,redraw,Session.modelRuntime(session))
    return False{}
def commandResult(+sink: CommandSink,result: Commands.Action) -> IO(Bool):
  match sink result:
    case CommandSink{failure,redraw,_,_,_,_,_} Commands.Notice{message}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_,_,_} Commands.CommandError{message}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_,_,_} Commands.ModelSelected{+model,persist}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{Bool.pick(String,persist,"Default model: " ++ Models.reference(model),"Model: " ++ Models.modelId(model))})
        requestRender(redraw)
        return True{}
    case CommandSink{failure,redraw,picker,_,_,session,models} Commands.OpenModelPicker{search}:
      do IO<Bool>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        openModelCommand(failure,redraw,picker,models,live,available,search)
    case CommandSink{_,redraw,_,thinking,_,session,_} Commands.OpenThinkingPicker{}:
      do IO<Bool>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        openThinking(redraw,thinking,live)
    case CommandSink{_,redraw,_,_,scoped,session,models} Commands.OpenScopedModels{}:
      do IO<Bool>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        openScoped(redraw,scoped,live,models)
    case CommandSink{failure,redraw,_,_,_,_,_} Commands.ThinkingSelected{level,persist}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{Bool.pick(String,persist,"Default thinking level: ","Thinking level: ") ++ Levels.name(level)})
        requestRender(redraw)
        return True{}
    case _ _: IO.pure(Bool,False{})
def act(queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: StatusSink,command: Commands.Command) -> IO(Unit):
  match command:
    case Commands.Stop{}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
    case Commands.Send{message}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitText(queue,message)
        submittedResult(failure,result)
    case other:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,other)
        submittedResult(failure,result)
def submitOwned(input: SubmissionInput,+text: String) -> IO(Unit):
  match input:
    case SubmissionInput{queue,stop,failure}:
      Bool.pick(Unit -> IO(Unit),String.is_empty(Text.trim(text)),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        act(queue,stop,failure,Commands.parse(text)))(Unit{})
def submitted(input: SubmissionInput,text: String) -> IO(Unit): submitOwned(input,text)
def queueInitial(+queue: Controller.Handle,+failure: StatusSink,initial: List<&2,Controller.Submission>) -> IO(Unit):
  match initial:
    case Nil{}: IO.pure(Unit,Unit{})
    case item <> rest:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submit(queue,item)
        submittedResult(failure,result)
        queueInitial(queue,failure,rest)
def onReady(startup: Startup,ready: Process.QueryReady) -> IO(Unit):
  match startup ready:
    case Startup{redraw,queue,initial,failure} Process.QueryReady{_,_,_,request}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,Some{request})
        queueInitial(queue,failure,initial)

# upstream createBaseAutocompleteProvider/setupAutocompleteProvider. Argument
# completions read the live session, so they follow /new, /resume and model
# changes. Extension commands are absent until extensions are ported.
type AutocompleteOwner is Data:
  AutocompleteOwner{provider: AC.AutocompleteProvider,arguments: List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>}

# upstream createFuzzyAutocompleteItems: null when nothing matches.
type Searchable is Data: Searchable{text: String,item: AC.AutocompleteItem}
def searchableText(value: Searchable) -> String:
  match value: case Searchable{text,_}: text
def searchableItems(values: List<&2,Searchable>) -> List<&2,AC.AutocompleteItem>:
  match values:
    case Nil{}: Nil{}
    case Searchable{_,item} <> rest: item <> searchableItems(rest)
def someItems(items: List<&2,AC.AutocompleteItem>) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  match items:
    case Nil{}: Done{None{}}
    case _: Done{Some{items}}
def fuzzyItems(values: List<&2,Searchable>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  someItems(searchableItems(Fuzzy.fuzzyFilter(~Searchable,~searchableText,values,prefix)))

def modelSearchable(item: Search.ModelSearchItem) -> Searchable:
  match item:
    case Search.ModelSearchItem{+id,+provider,+name}: Searchable{Search.getModelSearchText(Search.ModelSearchItem{id,provider,name}),AC.AutocompleteItem{provider ++ "/" ++ id,id,Some{provider}}}
def modelSearchables(items: List<&2,Search.ModelSearchItem>) -> List<&2,Searchable>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: modelSearchable(item) <> modelSearchables(rest)
def searchItems(models: List<&2,Models.Model()>) -> List<&2,Search.ModelSearchItem>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: Search.searchItem(model) <> searchItems(rest)
# upstream /model argument completions over the scoped or available models.
def modelArgumentItems(items: List<&2,Search.ModelSearchItem>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  fuzzyItems(modelSearchables(items),prefix)
def completionModels(scoped: List<&2,Models.ScopedModel>,available: List<&2,Models.Model()>) -> List<&2,Models.Model()>:
  match scoped:
    case Nil{}: available
    case _: Session.scopedModels(scoped)
def modelCompletions(session: Ref.Ref<Session.AgentSession>,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    scoped : List<&2,Models.ScopedModel> <- Session.getScopedModels(live)
    available : List<&2,Models.Model()> <- Models.getAvailable(Session.modelRuntime(live))
    return modelArgumentItems(searchItems(completionModels(scoped,available)),prefix)

def levelSearchables(levels: List<&2,Ai.ModelThinkingLevel>) -> List<&2,Searchable>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest:
      +name = Levels.name(level)
      Searchable{name,AC.AutocompleteItem{name,name,None{}}} <> levelSearchables(rest)
def thinkingCompletions(session: Ref.Ref<Session.AgentSession>,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
    live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    levels : List<&2,Ai.ModelThinkingLevel> <- Session.getAvailableThinkingLevels(live)
    return fuzzyItems(levelSearchables(levels),prefix)

# upstream getLoginProviderOptions: an entry per provider and auth type
# (subscription before API key), ordered by name with localeCompare.
type AuthSelectorProvider is Data: AuthSelectorProvider{id: String,name: String,authType: String}
def formatAuthSelectorProviderType(+authType: String) -> String: Bool.pick(String,String.eq(authType,"oauth"),"subscription","API key")
def providerEntries(+id: String,+name: String,auth: Auth.ProviderAuth,+rest: List<&2,AuthSelectorProvider>) -> List<&2,AuthSelectorProvider>:
  match auth:
    case Auth.ProviderAuth{apiKey,oauth}:
      +keyed = Bool.pick(List<&2,AuthSelectorProvider>,Maybe.is_some(&2,Auth.ApiKeyAuth,apiKey),AuthSelectorProvider{id,name,"api_key"} <> rest,rest)
      Bool.pick(List<&2,AuthSelectorProvider>,Maybe.is_some(&2,Auth.OAuthAuth,oauth),AuthSelectorProvider{id,name,"oauth"} <> keyed,keyed)
def providerOptions(providers: List<&2,AiModels.Provider>) -> List<&2,AuthSelectorProvider>:
  match providers:
    case Nil{}: Nil{}
    case AiModels.Provider{id,name,_,auth,_,_,_} <> rest: providerEntries(id,name,auth,providerOptions(rest))
def notAfter(order: Cmp) -> Bool:
  match order:
    case GT{}: False{}
    case _: True{}
type Keyed is Data: Keyed{key: Collation.Key,index: Nat}
def keyedBefore(left: Keyed,right: Keyed) -> Bool:
  match left right:
    case Keyed{a,_} Keyed{b,_}: notAfter(Collation.compareKeys(a,b))
def keyedNames(+collator: Collation.Collator,names: List<&2,String>,+index: Nat) -> List<&2,Keyed>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Keyed{Collation.key(collator,name),index} <> keyedNames(collator,rest,index + 1n)
def indices(values: List<&2,Keyed>) -> List<&2,Nat>:
  match values:
    case Nil{}: Nil{}
    case Keyed{_,index} <> rest: index <> indices(rest)
# The stable order of `names` by localeCompare, as positions; the input order
# without collation data.
def nameOrder(collator: Maybe<&2,Collation.Collator>,+names: List<&2,String>) -> List<&2,Nat>:
  match collator:
    case Some{value}: indices(Sort.sort(~Keyed,~keyedBefore,keyedNames(value,names,0n)))
    case None{}: List.range(List.length(&2,String,names))
def optionName(option: AuthSelectorProvider) -> String:
  match option: case AuthSelectorProvider{_,name,_}: name
def selectorNames(options: List<&2,AuthSelectorProvider>) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: optionName(option) <> selectorNames(rest)
def picked(-A: Data,found: Maybe<&2,A>,rest: List<&2,A>) -> List<&2,A>:
  match found:
    case None{}: rest
    case Some{value}: value <> rest
def pickAll(-A: Data,positions: List<&2,Nat>,+values: List<&2,A>) -> List<&2,A>:
  match positions:
    case Nil{}: Nil{}
    case index <> rest: picked(A,List.get(&2,A,values,index),pickAll(A,rest,values))
def getLoginProviderOptions(collator: Maybe<&2,Collation.Collator>,providers: List<&2,AiModels.Provider>) -> List<&2,AuthSelectorProvider>:
  +options = providerOptions(providers)
  pickAll(AuthSelectorProvider,nameOrder(collator,selectorNames(options)),options)

# upstream getLoginProviderCompletionOptions: entries grouped by provider id
# (first appearance), auth types in subscription/API key order, then ordered
# by name.
type LoginProviderCompletionOption is Data: LoginProviderCompletionOption{id: String,name: String,authTypes: List<&2,String>}
def hasType(types: List<&2,String>,+wanted: String) -> Bool:
  match types:
    case Nil{}: False{}
    case kind <> rest: String.eq(kind,wanted) || hasType(rest,wanted)
def withAuthType(+types: List<&2,String>,+authType: String) -> List<&2,String>:
  Bool.pick(List<&2,String>,hasType(types,authType),types,
    Bool.pick(List<&2,String>,String.eq(authType,"oauth"),authType <> types,List.append(&2,String,types,[authType])))
def mergedEntry(same: Bool,entry: LoginProviderCompletionOption,+authType: String) -> LoginProviderCompletionOption:
  match same entry:
    case True{} LoginProviderCompletionOption{id,name,types}: LoginProviderCompletionOption{id,name,withAuthType(types,authType)}
    case False{} entry: entry
def mergedAll(entries: List<&2,LoginProviderCompletionOption>,+id: String,+authType: String) -> List<&2,LoginProviderCompletionOption>:
  match entries:
    case Nil{}: Nil{}
    case LoginProviderCompletionOption{+other,name,types} <> rest: mergedEntry(String.eq(other,id),LoginProviderCompletionOption{other,name,types},authType) <> mergedAll(rest,id,authType)
def hasId(entries: List<&2,LoginProviderCompletionOption>,+id: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case LoginProviderCompletionOption{other,_,_} <> rest: String.eq(other,id) || hasId(rest,id)
def groupedWith(found: Bool,entries: List<&2,LoginProviderCompletionOption>,option: AuthSelectorProvider) -> List<&2,LoginProviderCompletionOption>:
  match found option:
    case True{} AuthSelectorProvider{id,_,authType}: mergedAll(entries,id,authType)
    case False{} AuthSelectorProvider{id,name,authType}: List.append(&2,LoginProviderCompletionOption,entries,[LoginProviderCompletionOption{id,name,[authType]}])
def optionId(option: AuthSelectorProvider) -> String:
  match option: case AuthSelectorProvider{id,_,_}: id
def grouped(+entries: List<&2,LoginProviderCompletionOption>,+option: AuthSelectorProvider) -> List<&2,LoginProviderCompletionOption>:
  groupedWith(hasId(entries,optionId(option)),entries,option)
def groupedAll(options: List<&2,AuthSelectorProvider>,entries: List<&2,LoginProviderCompletionOption>) -> List<&2,LoginProviderCompletionOption>:
  match options:
    case Nil{}: entries
    case option <> rest: groupedAll(rest,grouped(entries,option))
def completionName(option: LoginProviderCompletionOption) -> String:
  match option: case LoginProviderCompletionOption{_,name,_}: name
def completionNames(options: List<&2,LoginProviderCompletionOption>) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: completionName(option) <> completionNames(rest)
def getLoginProviderCompletionOptions(collator: Maybe<&2,Collation.Collator>,options: List<&2,AuthSelectorProvider>) -> List<&2,LoginProviderCompletionOption>:
  +entries = groupedAll(options,Nil{})
  pickAll(LoginProviderCompletionOption,nameOrder(collator,completionNames(entries)),entries)
def typeSearchText(types: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: Nil{}
    case +kind <> rest: (kind ++ " " ++ formatAuthSelectorProviderType(kind)) <> typeSearchText(rest)
def typeNames(types: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: Nil{}
    case kind <> rest: formatAuthSelectorProviderType(kind) <> typeNames(rest)
# getLoginProviderSearchText and formatLoginProviderCompletionDescription.
def loginSearchable(option: LoginProviderCompletionOption) -> Searchable:
  match option:
    case LoginProviderCompletionOption{+id,+name,+types}:
      +described = String.join(typeNames(types),"/")
      Searchable{id ++ " " ++ name ++ " " ++ String.join(typeSearchText(types)," "),AC.AutocompleteItem{id,id,Some{Bool.pick(String,String.eq(name,id),described,name ++ " · " ++ described)}}}
def loginSearchables(options: List<&2,LoginProviderCompletionOption>) -> List<&2,Searchable>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: loginSearchable(option) <> loginSearchables(rest)
# upstream /login argument completions.
def loginArgumentItems(+collator: Maybe<&2,Collation.Collator>,options: List<&2,AuthSelectorProvider>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  fuzzyItems(loginSearchables(getLoginProviderCompletionOptions(collator,options)),prefix)
def loadedCollator(loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> Maybe<&2,Collation.Collator>:
  match loaded:
    case Done{collator}: Some{collator}
    case Fail{_}: None{}
type LoginCompletion is Data: LoginCompletion{session: Ref.Ref<Session.AgentSession>,collator: Maybe<&2,Collation.Collator>}
def loginCompletions(state: LoginCompletion,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  match state:
    case LoginCompletion{session,+collator}:
      do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        providers : List<&2,AiModels.Provider> <- Models.getProviders(Session.modelRuntime(live))
        return loginArgumentItems(collator,getLoginProviderOptions(collator,providers),prefix)

# upstream getAutocompleteSourceTag and prefixAutocompleteDescription. Package
# sources (npm and git installs) are not ported, so resources carry auto,
# local or cli sources and the tag is the scope.
def scopePrefix(scope: Skills.SourceScope) -> String:
  match scope:
    case Skills.User{}: "u"
    case Skills.Project{}: "p"
    case Skills.Temporary{}: "t"
def sourceTag(info: Skills.SourceInfo) -> String:
  match info:
    case Skills.SourceInfo{_,source,scope,_,_}:
      +prefix = scopePrefix(scope)
      +trimmed = Text.trim(source)
      Bool.pick(String,String.starts_with(trimmed,"npm:"),prefix ++ ":" ++ trimmed,prefix)
def prefixAutocompleteDescription(+description: String,info: Skills.SourceInfo) -> Maybe<&2,String>:
  +tag = sourceTag(info)
  Some{Bool.pick(String,String.is_empty(description),"[" ++ tag ++ "]","[" ++ tag ++ "] " ++ description)}
def prefixOptionalDescription(description: Maybe<&2,String>,info: Skills.SourceInfo) -> Maybe<&2,String>:
  prefixAutocompleteDescription(Maybe.default(&2,String,description,""),info)

type Arguments is Data: Arguments{model: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>,thinking: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>,login: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>}
def argumentsFor(+name: String,arguments: Arguments) -> Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>:
  match arguments:
    case Arguments{model,thinking,login}:
      Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"model"),Some{model},
        Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"thinking"),Some{thinking},
          Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"login"),Some{login},None{})))
def builtinCommands(commands: List<&2,Slash.BuiltinSlashCommand>,+arguments: Arguments) -> List<&2,AC.Command>:
  match commands:
    case Nil{}: Nil{}
    case Slash.BuiltinSlashCommand{+name,description,hint} <> rest:
      AC.Slash{AC.SlashCommand{name,Some{description},hint,argumentsFor(name,arguments)}} <> builtinCommands(rest,arguments)
def templateCommands(templates: List<&2,Templates.PromptTemplate>) -> List<&2,AC.Command>:
  match templates:
    case Nil{}: Nil{}
    case Templates.PromptTemplate{name,description,hint,_,info,_} <> rest:
      AC.Slash{AC.SlashCommand{name,prefixAutocompleteDescription(description,info),hint,None{}}} <> templateCommands(rest)
def skillCommands(skills: List<&2,Skills.Skill>) -> List<&2,AC.Command>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name,description,_,_,info,_} <> rest:
      AC.Slash{AC.SlashCommand{"skill:" ++ name,prefixAutocompleteDescription(description,info),None{},None{}}} <> skillCommands(rest)
def builtinNames(commands: List<&2,Slash.BuiltinSlashCommand>) -> List<&2,String>:
  match commands:
    case Nil{}: Nil{}
    case Slash.BuiltinSlashCommand{name,_,_} <> rest: name <> builtinNames(rest)
def isBuiltinName(names: List<&2,String>,+name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first,name) || isBuiltinName(rest,name)
# upstream createBaseAutocompleteProvider's extension commands: those whose
# name is not a built-in command, by invocation name, with the source tag and
# their own argument completions (which stay with the extension).
def extensionCommands(commands: List<&2,ExtensionTypes.ResolvedCommand>,+builtins: List<&2,String>) -> List<&2,AC.Command>:
  match commands:
    case Nil{}: Nil{}
    case ExtensionTypes.ResolvedCommand{+name,invocation,info,description,completions,_} <> rest:
      +tail = extensionCommands(rest,builtins)
      Bool.pick(List<&2,AC.Command>,isBuiltinName(builtins,name),tail,AC.Slash{AC.SlashCommand{invocation,prefixOptionalDescription(description,info),None{},completions}} <> tail)
def conflictMessage(+name: String,+invocation: String) -> String:
  Bool.pick(String,String.eq(invocation,name),"Extension command '/" ++ name ++ "' conflicts with built-in interactive command. Skipping in autocomplete.","Extension command '/" ++ name ++ "' conflicts with built-in interactive command. Available as '/" ++ invocation ++ "'.")
def sourcePath(info: Skills.SourceInfo) -> String:
  match info:
    case Skills.SourceInfo{path,_,_,_,_}: path
def conflicts(commands: List<&2,ExtensionTypes.ResolvedCommand>,+builtins: List<&2,String>) -> List<&2,Diagnostics.ResourceDiagnostic>:
  match commands:
    case Nil{}: Nil{}
    case ExtensionTypes.ResolvedCommand{+name,invocation,info,_,_,_} <> rest:
      +tail = conflicts(rest,builtins)
      Bool.pick(List<&2,Diagnostics.ResourceDiagnostic>,isBuiltinName(builtins,name),Diagnostics.warning(conflictMessage(name,invocation),sourcePath(info)) <> tail,tail)
# upstream getBuiltInCommandConflictDiagnostics: a warning for each extension
# command named like a built-in interactive command, which autocomplete skips.
def getBuiltInCommandConflictDiagnostics(commands: List<&2,ExtensionTypes.ResolvedCommand>) -> List<&2,Diagnostics.ResourceDiagnostic>:
  conflicts(commands,builtinNames(Slash.BUILTIN_SLASH_COMMANDS()))
def registeredCommands(runner: Maybe<&2,ExtensionRunner.ExtensionRunner>) -> IO(List<&2,ExtensionTypes.ResolvedCommand>):
  match runner:
    case None{}: IO.pure(List<&2,ExtensionTypes.ResolvedCommand>,Nil{})
    case Some{found}: ExtensionRunner.getRegisteredCommands(found)
# upstream isExtensionCommand: `/name ...` names a registered extension
# command (by invocation name). Input that is one runs at once, even while
# compacting, instead of being queued.
def isExtensionCommand(session: Session.AgentSession,+text: String) -> IO(Bool):
  do IO<Bool>:
    runner : Maybe<&2,ExtensionRunner.ExtensionRunner> <- Session.extensionRunner(session)
    commands : List<&2,ExtensionTypes.ResolvedCommand> <- registeredCommands(runner)
    return String.starts_with(text,"/") && Maybe.is_some(&2,ExtensionTypes.ResolvedCommand,ExtensionRunner.findInvocation(commands,Session.commandName(text)))
def enabledSkills(enabled: Bool,skills: List<&2,Skills.Skill>) -> List<&2,AC.Command>:
  match enabled:
    case True{}: skillCommands(skills)
    case False{}: Nil{}
def sessionCwd(session: Session.AgentSession) -> String:
  match session: case Session.AgentSession{_,_,_,_,cwd,_,_,_}: cwd
def argumentList(arguments: Arguments) -> List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>:
  match arguments: case Arguments{model,thinking,login}: [model,thinking,login]
def disposeArguments(values: List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Callback.dispose(String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),value)
        disposeArguments(rest)
# Without collation data, folded scalar order approximates localeCompare.
def sortPolicy(collator: Maybe<&2,Collation.Collator>) -> AC.SortPolicy:
  match collator:
    case Some{value}: AC.LocaleOrder{value}
    case None{}: AC.FoldedScalarOrder{}
def combinedOwner(+arguments: Arguments,created: AC.ResultOf(AC.CombinedAutocompleteProvider)) -> IO(Maybe<&2,AutocompleteOwner>):
  match created:
    case Fail{_}:
      do IO<Maybe<&2,AutocompleteOwner>>:
        disposeArguments(argumentList(arguments))
        return None{}
    case Done{combined}:
      do IO<Maybe<&2,AutocompleteOwner>>:
        provider : AC.AutocompleteProvider <- AC.asProvider(combined)
        return Some{AutocompleteOwner{provider,argumentList(arguments)}}
# `recursiveFiles` is upstream's fdPath: @ file search runs only when fd is
# available, although the port searches natively. `home` and the session
# cwd must be absolute; otherwise there is no provider.
def createAutocompleteProvider(+session: Ref.Ref<Session.AgentSession>,home: String,data: String,recursiveFiles: Bool) -> IO(Maybe<&2,AutocompleteOwner>):
  do IO<Maybe<&2,AutocompleteOwner>>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    settings : Settings.SettingsManager <- Session.getSettings(live)
    templates : List<&2,Templates.PromptTemplate> <- Session.promptTemplates(live)
    skills : List<&2,Skills.Skill> <- Session.getSkills(live)
    runner : Maybe<&2,ExtensionRunner.ExtensionRunner> <- Session.extensionRunner(live)
    extensions : List<&2,ExtensionTypes.ResolvedCommand> <- registeredCommands(runner)
    model : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~Ref.Ref<Session.AgentSession>,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~modelCompletions,session)
    thinking : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~Ref.Ref<Session.AgentSession>,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~thinkingCompletions,session)
    loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(data)
    +collator : Maybe<&2,Collation.Collator> <- IO.pure(Maybe<&2,Collation.Collator>,loadedCollator(loaded))
    login : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~LoginCompletion,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~loginCompletions,LoginCompletion{session,collator})
    +arguments : Arguments <- IO.pure(Arguments,Arguments{model,thinking,login})
    +commands : List<&2,AC.Command> <- IO.pure(List<&2,AC.Command>,List.append(&2,AC.Command,builtinCommands(Slash.BUILTIN_SLASH_COMMANDS(),arguments),List.concat(&2,AC.Command,[templateCommands(templates),extensionCommands(extensions,builtinNames(Slash.BUILTIN_SLASH_COMMANDS())),enabledSkills(Settings.getEnableSkillCommands(settings),skills)])))
    combinedOwner(arguments,AC.create(commands,sessionCwd(live),home,sortPolicy(collator),recursiveFiles))
def disposeAutocompleteProvider(owner: AutocompleteOwner) -> IO(Unit):
  match owner:
    case AutocompleteOwner{provider,arguments}:
      do IO<Unit>:
        AC.disposeProvider(provider)
        disposeArguments(arguments)
