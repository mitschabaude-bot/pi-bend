import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as AgentRuntime
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/loader.bend as ExtensionLoader
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/coding-agent/src/core/bash-executor.bend as BashExec
import ../packages/runtime/src/filesystem.bend as Files
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/utf8.bend as Utf8
import ./model-runtime-fixture.bend as ModelFixture
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ./agent-session-runtime.bend as Fixture
import ./agent-session.bend as Faux
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/agent-session-runtime.bend as Host
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as Tree
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Controller
import ../packages/coding-agent/src/cli/auth-login.bend as AuthLogin
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/ai/src/utils/uuid.bend as Uuid

def Services() -> Type: Fixture.Services()
def Runtime() -> Data: Host.AgentSessionRuntime<Services()>
type Binding is Data:
  Binding{current: Ref.Ref<Session.AgentSession>,hook: Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>}
def notify(hook: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,live: Session.AgentSession) -> IO(Unit):
  match hook:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(Session.AgentSession,Unit,callback,live)
def reboundCopied(binding: Binding,+live: Session.AgentSession) -> IO(Unit):
  match binding:
    case Binding{current,hook}:
      do IO<Unit>:
        Ref.write(Session.AgentSession,current,live)
        observer : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook)
        notify(observer,live)
def rebound(binding: Binding,live: Session.AgentSession) -> IO(Unit): reboundCopied(binding,live)
def startNew(runtime: Runtime(),_: Unit) -> IO(Result<&2,&2,String,Ctx.SessionChange>): Host.newSessionCancellable(Services(),runtime,None{})
def forkSession(runtime: Runtime(),request: Host.ForkRequest) -> IO(Result<&2,&2,String,Host.ForkOutcome>):
  match request:
    case Host.ForkRequest{entryId,position}: Host.forkCancellable(Services(),runtime,entryId,position)
def importSession(runtime: Runtime(),request: Run.ImportRequest) -> IO(Host.ImportOutcome):
  match request:
    case Run.ImportRequest{path,cwdOverride}: Host.importFromJsonl(Services(),runtime,path,cwdOverride)
def resumeSession(runtime: Runtime(),request: Run.ResumeRequest) -> IO(Host.CancellableResume):
  match request:
    case Run.ResumeRequest{path,cwdOverride}: Host.resumeSessionCancellable(Services(),runtime,path,cwdOverride)
type Listings is Data: Listings{cwd: String,agentDir: String}
def listSessions(source: Listings,_: Unit) -> IO(Run.SessionChoices):
  match source:
    case Listings{+cwd,agentDir}:
      do IO<Run.SessionChoices>:
        current : List<&2,Tree.SessionInfo> <- Sessions.list(cwd,Some{cwd},agentDir,None{})
        all : List<&2,Tree.SessionInfo> <- Sessions.listAll(Some{cwd},cwd,None{})
        return Run.SessionChoices{current,all}
def noLogin(_: Unit,_: Run.LoginRequest) -> IO(AuthLogin.Outcome()): IO.pure(AuthLogin.Outcome(),Fail{"Login fixture is unavailable"})
def models(_: Unit,_: Unit) -> IO(List<&2,Models.Model()>): IO.pure(List<&2,Models.Model()>,Faux.fauxModel() <> Nil{})
def requireSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(),session)
    case Fail{error}: IO.die(Session.Session(),1,Sessions.message(error))
def requireHost(result: Result<&2,&2,String,Runtime()>) -> IO(Runtime()):
  match result:
    case Done{runtime}: IO.pure(Runtime(),runtime)
    case Fail{message}: IO.die(Runtime(),1,message)
def requireLive(value: Maybe<&2,Session.AgentSession>) -> IO(Session.AgentSession):
  match value:
    case Some{live}: IO.pure(Session.AgentSession,live)
    case None{}: IO.die(Session.AgentSession,1,"missing initial session")
def checked(result: Result<&2,&2,Run.Error,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{error}: IO.die(Unit,1,Run.errorMessage(error))
# Visual checks keep fixture diagnostics out of the terminal renderer's stream.
def quietCreated(+fixture: Faux.Fixture) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match fixture:
    case Faux.Fixture{live,listener,_,_,_,_,_}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        Session.unsubscribe(live,listener)
        return Fixture.created(fixture)
def quietFactory(agentDir: String,request: Host.Request) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match request:
    case Host.Request{storedCwd,stored,_}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        fixture : Faux.Fixture <- Faux.fixture(stored,storedCwd,agentDir,"answer" <> "again" <> Nil{},Nil{})
        quietCreated(fixture)
type BashSetup is Data:
  BashSetup{agentDir: String,runners: Ref.Ref<List<&2,Runner.ExtensionRunner>>,operations: Bash.BashOperations}
def bashOutcome(operations: Bash.BashOperations,command: String) -> Result<&2,&2,String,Maybe<&2,Ext.UserBashEventResult>>:
  match command:
    case "touch rejected": Fail{"Routing failed"}
    case "touch overridden": Done{Some{Ext.UserBashResult{BashExec.BashResult{"EXTENSION_RESULT",Some{0},False{},False{},None{}}}}}
    case "touch operations": Done{Some{Ext.UserBashOperations{operations}}}
    case _: Done{None{}}
def interceptedBash(operations: Bash.BashOperations,call: Ext.HandlerCall<Ext.UserBashEvent>) -> IO(Result<&2,&2,String,Maybe<&2,Ext.UserBashEventResult>>):
  match call:
    case Ext.HandlerCall{Ext.UserBashEvent{+command,+excluded,+cwd},_}:
      do IO<Result<&2,&2,String,Maybe<&2,Ext.UserBashEventResult>>>:
        saved : Result<&2,&2,Files.Error,Unit> <- Files.appendFile(Files.child(cwd,"bash-events.jsonl"),"{\"command\":" ++ Json.quote(command) ++ ",\"excludeFromContext\":" ++ Bool.pick(String,excluded,"true","false") ++ ",\"cwd\":" ++ Json.quote(cwd) ++ "}\n")
        return bashOutcome(operations,command)
def bashExtension(operations: Bash.BashOperations,api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    handler : Ext.ExtensionHandler(Ext.UserBashEvent,Ext.UserBashEventResult) <- Callback.create(~Bash.BashOperations,~Ext.HandlerCall<Ext.UserBashEvent>,~Result<&2,&2,String,Maybe<&2,Ext.UserBashEventResult>>,~interceptedBash,operations)
    registered : Result<&2,&2,String,ExtensionLoader.Unsubscribe> <- ExtensionLoader.on(api,Ext.OnUserBash{handler})
    return Result.map(&2,&2,String,ExtensionLoader.Unsubscribe,Unit,_ => Unit{},registered)
def uiAnswer(ctx: Ctx.ExtensionContext,answer: Maybe<&2,String>) -> IO(Unit):
  match answer:
    case None{}: Ctx.notify(ctx,"Extension prompt cancelled",Ctx.InfoNotice{})
    case Some{value}: Ctx.notify(ctx,"Extension chose: " ++ value,Ctx.InfoNotice{})
def uiCommand(_: Unit,call: Ext.CommandCall) -> IO(Result<&2,&2,String,Unit>):
  match call:
    case Ext.CommandCall{_,commandContext}:
      do IO<Result<&2,&2,String,Unit>>:
        +ctx : Ctx.ExtensionContext <- IO.pure(Ctx.ExtensionContext,Ctx.commandContext(commandContext))
        answer : Maybe<&2,String> <- Ctx.select(ctx,"Pick a value",["alpha","beta"],Ctx.dialogOptions())
        uiAnswer(ctx,answer)
        return Done{Unit{}}
def uiInputCommand(_: Unit,call: Ext.CommandCall) -> IO(Result<&2,&2,String,Unit>):
  match call:
    case Ext.CommandCall{_,commandContext}:
      do IO<Result<&2,&2,String,Unit>>:
        +ctx : Ctx.ExtensionContext <- IO.pure(Ctx.ExtensionContext,Ctx.commandContext(commandContext))
        answer : Maybe<&2,String> <- Ctx.input(ctx,"Name a value",None{},Ctx.dialogOptions())
        uiAnswer(ctx,answer)
        return Done{Unit{}}
def uiEditorCommand(_: Unit,call: Ext.CommandCall) -> IO(Result<&2,&2,String,Unit>):
  match call:
    case Ext.CommandCall{_,commandContext}:
      do IO<Result<&2,&2,String,Unit>>:
        +ctx : Ctx.ExtensionContext <- IO.pure(Ctx.ExtensionContext,Ctx.commandContext(commandContext))
        answer : Maybe<&2,String> <- Ctx.editor(ctx,"Write a note",Some{"seed"})
        uiAnswer(ctx,answer)
        return Done{Unit{}}
def uiWidgetCommand(_: Unit,call: Ext.CommandCall) -> IO(Result<&2,&2,String,Unit>):
  match call:
    case Ext.CommandCall{_,commandContext}:
      do IO<Result<&2,&2,String,Unit>>:
        +ctx : Ctx.ExtensionContext <- IO.pure(Ctx.ExtensionContext,Ctx.commandContext(commandContext))
        Ctx.setWidget(ctx,"replay-above",Some{Ctx.WidgetLines{["fixture widget above"]}},None{})
        Ctx.setWidget(ctx,"replay-below",Some{Ctx.WidgetLines{["fixture widget below"]}},Some{Ctx.BelowEditor{}})
        return Done{Unit{}}
def uiExtension(api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    +shared : Ext.ExtensionAPI <- IO.pure(Ext.ExtensionAPI,api)
    handler : Ext.CommandHandler() <- Callback.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~uiCommand,Unit{})
    first : Result<&2,&2,String,Unit> <- ExtensionLoader.registerCommand(shared,"ask",Ext.CommandOptions{Some{"Show a native extension prompt"},None{},handler})
    input : Ext.CommandHandler() <- Callback.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~uiInputCommand,Unit{})
    second : Result<&2,&2,String,Unit> <- ExtensionLoader.registerCommand(shared,"ask-input",Ext.CommandOptions{Some{"Show a native extension input"},None{},input})
    editor : Ext.CommandHandler() <- Callback.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~uiEditorCommand,Unit{})
    third : Result<&2,&2,String,Unit> <- ExtensionLoader.registerCommand(shared,"ask-editor",Ext.CommandOptions{Some{"Show a native extension editor"},None{},editor})
    widget : Ext.CommandHandler() <- Callback.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~uiWidgetCommand,Unit{})
    ExtensionLoader.registerCommand(shared,"show-widget",Ext.CommandOptions{Some{"Show native editor widgets"},None{},widget})
def bashFactory(setup: BashSetup,request: Host.Request) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match setup request:
    case BashSetup{agentDir,runners,operations} Host.Request{+cwd,stored,_}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        +runtime : Ext.ExtensionRuntime() <- ExtensionLoader.createExtensionRuntime()
        errors : List<&2,Ext.LoadError> <- ExtensionLoader.loadExtensionFactories(runtime,[Ext.InlineExtension{"user-bash",api => bashExtension(operations,api),False{}}])
        models : Models.ModelRuntime <- ModelFixture.create(Faux.fauxSources())
        +runner : Runner.ExtensionRunner <- Runner.create(runtime,cwd,models)
        Ref.modify(List<&2,Runner.ExtensionRunner>,Unit,runners,loaded => (runner <> loaded,Unit{}))
        fixture : Faux.Fixture <- Faux.fixtureWith(stored,cwd,agentDir,"answer" <> "again" <> Nil{},Nil{},AgentRuntime.Loadout{Record.new(String),Nil{},Nil{},Nil{},Some{runner},Nil{},None{},Nil{}})
        quietCreated(fixture)
def uiFactory(setup: BashSetup,request: Host.Request) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match setup request:
    case BashSetup{agentDir,runners,_} Host.Request{+cwd,stored,_}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        +runtime : Ext.ExtensionRuntime() <- ExtensionLoader.createExtensionRuntime()
        errors : List<&2,Ext.LoadError> <- ExtensionLoader.loadExtensionFactories(runtime,[Ext.InlineExtension{"ui",uiExtension,False{}}])
        models : Models.ModelRuntime <- ModelFixture.create(Faux.fauxSources())
        +runner : Runner.ExtensionRunner <- Runner.create(runtime,cwd,models)
        Ref.modify(List<&2,Runner.ExtensionRunner>,Unit,runners,loaded => (runner <> loaded,Unit{}))
        fixture : Faux.Fixture <- Faux.fixtureWith(stored,cwd,agentDir,"answer" <> "again" <> Nil{},Nil{},AgentRuntime.Loadout{Record.new(String),Nil{},Nil{},Nil{},Some{runner},Nil{},None{},Nil{}})
        quietCreated(fixture)
def customBash(_: Unit,input: Bash.BashExecutionInput) -> IO(Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>):
  match input:
    case Bash.BashExecutionInput{_,_,chunk,_,_,_}:
      do IO<Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>>:
        emitted : Result<&2,&2,String,Unit> <- Callback.call(List<&2,U32>,Result<&2,&2,String,Unit>,chunk,Utf8.encode("CUSTOM_OPERATIONS"))
        return Done{Some{0}}
def factoryFor(cancel: Bool,mode: String,setup: BashSetup,cancelFork: Ref.Ref<Bool>) -> IO(Host.Factory(Services())):
  match cancel mode setup:
    case True{} _ BashSetup{agentDir,runners,_}: Callback.create(~Fixture.EventsEnv,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~Fixture.eventsFactoryCall,Fixture.EventsEnv{agentDir,True{},cancelFork,runners})
    case False{} "bash" setup: Callback.create(~BashSetup,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~bashFactory,setup)
    case False{} "ui" setup: Callback.create(~BashSetup,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~uiFactory,setup)
    case False{} "quiet" BashSetup{agentDir,_,_}: Callback.create(~String,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~quietFactory,agentDir)
    case False{} _ BashSetup{agentDir,_,_}: Callback.create(~String,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~Fixture.factory,agentDir)
def runWith(+cancel: Bool,+mode: String,args: List<String>) -> IO(Unit):
  match args:
    case assetsRoot <> +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        uuids : Uuid.Generator <- Uuid.generator()
        created : Sessions.Outcome(Session.Session()) <- Session.createSession(uuids,cwd,Some{cwd},agentDir,Sessions.noOptions())
        stored : Session.Session() <- requireSession(created)
        +cancelFork : Ref.Ref<Bool> <- Ref.new(Bool,cancel)
        +runners : Ref.Ref<List<&2,Runner.ExtensionRunner>> <- Ref.new(List<&2,Runner.ExtensionRunner>,Nil{})
        +operations : Callback.Callback<Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>> <- Callback.create(~Unit,~Bash.BashExecutionInput,~Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,~customBash,Unit{})
        +factory : Host.Factory(Services()) <- factoryFor(cancel,mode,BashSetup{agentDir,runners,Bash.BashOperations{operations}},cancelFork)
        +release : Callback.Callback<Services(),Unit> <- Callback.create(~Unit,~Services(),~Unit,~Fixture.release,Unit{})
        hosted : Result<&2,&2,String,Runtime()> <- Host.create(Services(),factory,release,agentDir,cwd,stored)
        +runtime : Runtime() <- requireHost(hosted)
        currentSession : Maybe<&2,Session.AgentSession> <- Host.session(Services(),runtime)
        +live : Session.AgentSession <- requireLive(currentSession)
        +current : Ref.Ref<Session.AgentSession> <- Ref.new(Session.AgentSession,live)
        +hook : Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,None{})
        +rebinder : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~Binding,~Session.AgentSession,~Unit,~rebound,Binding{current,hook})
        +new : Callback.Callback<Unit,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Runtime(),~Unit,~Result<&2,&2,String,Ctx.SessionChange>,~startNew,runtime)
        +forking : Callback.Callback<Host.ForkRequest,Result<&2,&2,String,Host.ForkOutcome>> <- Callback.create(~Runtime(),~Host.ForkRequest,~Result<&2,&2,String,Host.ForkOutcome>,~forkSession,runtime)
        +login : Callback.Callback<Run.LoginRequest,AuthLogin.Outcome()> <- Callback.create(~Unit,~Run.LoginRequest,~AuthLogin.Outcome(),~noLogin,Unit{})
        +refresh : Callback.Callback<Unit,List<&2,Models.Model()>> <- Callback.create(~Unit,~Unit,~List<&2,Models.Model()>,~models,Unit{})
        +importer : Callback.Callback<Run.ImportRequest,Host.ImportOutcome> <- Callback.create(~Runtime(),~Run.ImportRequest,~Host.ImportOutcome,~importSession,runtime)
        +sessions : Callback.Callback<Unit,Run.SessionChoices> <- Callback.create(~Listings,~Unit,~Run.SessionChoices,~listSessions,Listings{cwd,agentDir})
        +resume : Callback.Callback<Run.ResumeRequest,Host.CancellableResume> <- Callback.create(~Runtime(),~Run.ResumeRequest,~Host.CancellableResume,~resumeSession,runtime)
        Host.setRebindSession(Services(),runtime,Some{rebinder})
        result : Result<&2,&2,Run.Error,Unit> <- Run.runBound(live,Run.Binding{current,Controller.Replacement{new,forking},hook,login,refresh,importer,sessions,resume,None{},False{},None{}},Nil{},cwd,None{},agentDir,assetsRoot,None{},Faux.fauxModel() <> Nil{})
        Host.setRebindSession(Services(),runtime,None{})
        Callback.dispose(Run.LoginRequest,AuthLogin.Outcome(),login)
        Callback.dispose(Unit,List<&2,Models.Model()>,refresh)
        Callback.dispose(Run.ImportRequest,Host.ImportOutcome,importer)
        Callback.dispose(Unit,Run.SessionChoices,sessions)
        Callback.dispose(Run.ResumeRequest,Host.CancellableResume,resume)
        Callback.dispose(Unit,Result<&2,&2,String,Ctx.SessionChange>,new)
        Callback.dispose(Host.ForkRequest,Result<&2,&2,String,Host.ForkOutcome>,forking)
        Callback.dispose(Session.AgentSession,Unit,rebinder)
        oldHook : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook)
        old : Session.AgentSession <- Ref.dispose(Session.AgentSession,current)
        Host.dispose(Services(),runtime)
        Callback.dispose(Host.Request,Result<&1,&1,String,Host.Created<Services()>>,factory)
        Callback.dispose(Services(),Unit,release)
        loaded : List<&2,Runner.ExtensionRunner> <- Ref.dispose(List<&2,Runner.ExtensionRunner>,runners)
        Fixture.disposeRunners(loaded)
        Callback.dispose(Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,operations)
        retiredCancel : Bool <- Ref.dispose(Bool,cancelFork)
        checked(result)
    case _: IO.die(Unit,1,"expected assetsRoot cwd agentDir")
def run(args: List<String>) -> IO(Unit):
  match args:
    case "cancel" <> rest: runWith(True{},"",rest)
    case "quiet" <> rest: runWith(False{},"quiet",rest)
    case "bash" <> rest: runWith(False{},"bash",rest)
    case "ui" <> rest: runWith(False{},"ui",rest)
    case rest: runWith(False{},"",rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
