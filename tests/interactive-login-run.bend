import Base
import ../packages/ai/src/providers/radius.bend as Radius
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
import ../packages/ai/src/auth/oauth/openai-codex.bend as Codex
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/ai/src/utils/uuid.bend as Uuid

import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/oauth/anthropic.bend as Anthropic
import ../packages/coding-agent/src/core/agent-runtime.bend as AgentRuntime
import ../packages/coding-agent/src/core/auth-storage.bend as Storage
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/runtime/src/record.bend as Record

# Native auth storage and model availability, with deterministic model responses.
# The session borrows its model runtime; these services own its auth and transport.
type LoginServices is Type:
  LoginServices{fixture: Faux.Fixture,storage: Storage.AuthStorageOwner,store: Auth.CredentialStore,transport: AgentRuntime.Transport}
def Services() -> Type: LoginServices

def requireTransport(result: AgentRuntime.Outcome(AgentRuntime.Transport)) -> IO(AgentRuntime.Transport):
  match result:
    case Done{transport}: IO.pure(AgentRuntime.Transport,transport)
    case Fail{message}: IO.die(AgentRuntime.Transport,1,message)
def factoryTransport(+agentDir: String,request: Host.Request,storage: Storage.AuthStorageOwner,+store: Auth.CredentialStore,transport: AgentRuntime.Transport) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match request transport:
    case Host.Request{+cwd,+stored,_} AgentRuntime.Transport{authorizer,runtime,+fetch}:
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        oauth : Auth.OAuthAuth <- Codex.openaiCodexOAuth(fetch,AgentRuntime.urlContext())
        anthropic : Auth.OAuthAuth <- Anthropic.anthropicOAuth(fetch,AgentRuntime.urlContext())
        +models : Models.ModelRuntime <- Models.createWithAnthropic(store,oauth,Some{anthropic},Radius.RadiusTransport{fetch,AgentRuntime.urlContext()})
        +responses : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,"answer" <> "again" <> Nil{})
        +streams : Ref.Ref<List<&2,Faux.EventStream()>> <- Ref.new(List<&2,Faux.EventStream()>,Nil{})
        +gates : Ref.Ref<List<&2,Faux.Gate>> <- Ref.new(List<&2,Faux.Gate>,Nil{})
        +stream : AgentRuntime.Stream() <- Callback.create(~Faux.Faux,~Faux.Input(),~Faux.Output(),~Faux.provider,Faux.Faux{responses,streams,gates})
        +registry : StreamFn.Registry(Unit,Tools.ToolDetails,AgentRuntime.LoopConfig(),Tools.ToolError) <- StreamFn.create(Unit,Tools.ToolDetails,AgentRuntime.LoopConfig(),Tools.ToolError)
        +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError,~AgentRuntime.validationError)
        +converter : AgentRuntime.Converter() <- AgentRuntime.createConverter(False{})
        created : Result<&2,&2,StreamFn.MissingDefault,AgentRuntime.Owner()> <- Agent.new(~Unit,~Tools.ToolDetails,~AgentRuntime.Custom(),~Tools.ToolError,~Unit,Faux.options(stream,converter,Sessions.getSessionId(Unit,Tools.ToolDetails,Schema.Value,stored),None{}),registry,validator,Tools.emptyDetails())
        +agent : AgentRuntime.Owner() <- Faux.requireAgent(created)
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd,agentDir,Settings.options())
        +session : Session.AgentSession <- Session.create(agent,stored,Faux.settingsOf(loaded),cwd,AgentRuntime.Loadout{Record.new(String),Nil{},Nil{},Nil{},None{},Nil{},None{},Nil{}},models,Nil{})
        +listener : Session.Listener() <- Callback.create(~Unit,~Session.AgentSessionEvent,~Unit,~Faux.observe,Unit{})
        Session.subscribe(session,listener)
        return Done{Host.Created{LoginServices{Faux.Fixture{session,listener,stream,validator,converter,registry,Faux.Faux{responses,streams,gates}},storage,store,AgentRuntime.Transport{authorizer,runtime,fetch}},session}}
def factoryStored(+agentDir: String,request: Host.Request,pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  match pair:
    case (storage,view):
      do IO<Result<&1,&1,String,Host.Created<Services()>>>:
        store : Auth.CredentialStore <- Storage.store(view)
        connected : AgentRuntime.Outcome(AgentRuntime.Transport) <- AgentRuntime.createTransport("/etc/ssl/certs/ca-certificates.crt")
        transport : AgentRuntime.Transport <- requireTransport(connected)
        factoryTransport(agentDir,request,storage,store,transport)
def factory(agentDir: String,request: Host.Request) -> IO(Result<&1,&1,String,Host.Created<Services()>>):
  do IO<Result<&1,&1,String,Host.Created<Services()>>>:
    +directory : String = agentDir
    storage : Storage.AuthStorageOwner <- Storage.create(directory ++ "/auth.json")
    factoryStored(directory,request,Storage.borrow(storage))
def release(_: Unit,services: Services()) -> IO(Unit):
  match services:
    case LoginServices{+fixture,storage,store,transport}:
      do IO<Unit>:
        Models.dispose(Session.modelRuntime(Faux.sessionOf(fixture)))
        Fixture.release(Unit{},fixture)
        Auth.disposeStore(store)
        Storage.dispose(storage)
        AgentRuntime.disposeTransport(transport)
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
def startNew(runtime: Runtime(),_: Unit) -> IO(Result<&2,&2,String,Unit>): Host.newSession(Services(),runtime,None{})
def forkSession(runtime: Runtime(),request: Host.ForkRequest) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  match request:
    case Host.ForkRequest{entryId,position}: Host.fork(Services(),runtime,entryId,position)
def importSession(runtime: Runtime(),request: Run.ImportRequest) -> IO(Host.ImportOutcome):
  match request:
    case Run.ImportRequest{path,cwdOverride}: Host.importFromJsonl(Services(),runtime,path,cwdOverride)
def resumeSession(runtime: Runtime(),request: Run.ResumeRequest) -> IO(Host.ResumeOutcome):
  match request:
    case Run.ResumeRequest{path,cwdOverride}: Host.resumeSession(Services(),runtime,path,cwdOverride)
type Listings is Data: Listings{cwd: String,agentDir: String}
def listSessions(source: Listings,_: Unit) -> IO(Run.SessionChoices):
  match source:
    case Listings{+cwd,agentDir}:
      do IO<Run.SessionChoices>:
        current : List<&2,Tree.SessionInfo> <- Sessions.list(cwd,Some{cwd},agentDir,None{})
        all : List<&2,Tree.SessionInfo> <- Sessions.listAll(Some{cwd},cwd,None{})
        return Run.SessionChoices{current,all}
def loginOAuth(provider: String,+auth: Auth.OAuthAuth,interaction: Auth.AuthInteraction) -> IO(AuthLogin.Outcome()):
  match auth interaction:
    case Auth.OAuthAuth{_,_,_,callback,_,_} Auth.AuthInteraction{Some{signal},prompt,notify}:
      do IO<AuthLogin.Outcome()>:
        result : AuthLogin.Outcome() <- AuthLogin.authenticateProvider(provider,callback,Auth.ProviderAuthInteraction{signal,prompt,notify})
        Auth.disposeOAuthAuth(auth)
        return result
    case auth _:
      do IO<AuthLogin.Outcome()>:
        Auth.disposeOAuthAuth(auth)
        return Fail{"Fixture expects a login signal"}
def loginTransport(+base: String,provider: String,interaction: Auth.AuthInteraction,transport: AgentRuntime.Transport) -> IO(AuthLogin.Outcome()):
  match transport provider:
    case AgentRuntime.Transport{+authorizer,runtime,+fetch} "anthropic":
      do IO<AuthLogin.Outcome()>:
        auth : Auth.OAuthAuth <- Anthropic.anthropicOAuthWithTokenURL(fetch,AgentRuntime.urlContext(),base ++ "/anthropic-token")
        result : AuthLogin.Outcome() <- loginOAuth("anthropic",auth,interaction)
        AgentRuntime.disposeTransport(AgentRuntime.Transport{authorizer,runtime,fetch})
        return result
    case AgentRuntime.Transport{+authorizer,runtime,+fetch} provider:
      do IO<AuthLogin.Outcome()>:
        auth : Auth.OAuthAuth <- Codex.openaiCodexOAuthWithEndpoints(fetch,AgentRuntime.urlContext(),Codex.DeviceEndpoints{base ++ "/usercode",base ++ "/token",base ++ "/exchange",base ++ "/codex/device"})
        result : AuthLogin.Outcome() <- loginOAuth(provider,auth,interaction)
        AgentRuntime.disposeTransport(AgentRuntime.Transport{authorizer,runtime,fetch})
        return result
def loginCopied(+base: String,request: Run.LoginRequest) -> IO(AuthLogin.Outcome()):
  match request:
    case Run.LoginRequest{runtime,provider,Auth.ApiKeyType{},interaction}:
      do IO<AuthLogin.Outcome()>:
        result : Auth.LoginOutcome() <- Models.login(runtime,provider,Auth.ApiKeyType{},interaction)
        return Run.loginRequestOutcome(result)
    case Run.LoginRequest{_,provider,Auth.OAuthType{},interaction}:
      do IO<AuthLogin.Outcome()>:
        transport : AgentRuntime.Outcome(AgentRuntime.Transport) <- AgentRuntime.createTransport("/etc/ssl/certs/ca-certificates.crt")
        ready : AgentRuntime.Transport <- requireTransport(transport)
        loginTransport(base,provider,interaction,ready)
def login(base: String,request: Run.LoginRequest) -> IO(AuthLogin.Outcome()): loginCopied(base,request)
def models(runtime: Models.ModelRuntime,_: Unit) -> IO(List<&2,Models.Model()>):
  do IO<List<&2,Models.Model()>>:
    +current : Models.ModelRuntime = runtime
    Models.refreshAvailability(current)
    Models.getAvailable(current)
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
def run(args: List<String>) -> IO(Unit):
  match args:
    case assetsRoot <> +cwd <> +agentDir <> +base <> Nil{}:
      do IO<Unit>:
        uuids : Uuid.Generator <- Uuid.generator()
        created : Sessions.Outcome(Session.Session()) <- Session.createSession(uuids,cwd,Some{cwd},agentDir,Sessions.noOptions())
        stored : Session.Session() <- requireSession(created)
        +factory : Host.Factory(Services()) <- Callback.create(~String,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~factory,agentDir)
        +release : Callback.Callback<Services(),Unit> <- Callback.create(~Unit,~Services(),~Unit,~release,Unit{})
        hosted : Result<&2,&2,String,Runtime()> <- Host.create(Services(),factory,release,agentDir,cwd,stored)
        +runtime : Runtime() <- requireHost(hosted)
        currentSession : Maybe<&2,Session.AgentSession> <- Host.session(Services(),runtime)
        +live : Session.AgentSession <- requireLive(currentSession)
        +current : Ref.Ref<Session.AgentSession> <- Ref.new(Session.AgentSession,live)
        +hook : Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,None{})
        +rebinder : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~Binding,~Session.AgentSession,~Unit,~rebound,Binding{current,hook})
        +new : Callback.Callback<Unit,Result<&2,&2,String,Unit>> <- Callback.create(~Runtime(),~Unit,~Result<&2,&2,String,Unit>,~startNew,runtime)
        +forking : Callback.Callback<Host.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>> <- Callback.create(~Runtime(),~Host.ForkRequest,~Result<&2,&2,String,Maybe<&2,String>>,~forkSession,runtime)
        +login : Callback.Callback<Run.LoginRequest,AuthLogin.Outcome()> <- Callback.create(~String,~Run.LoginRequest,~AuthLogin.Outcome(),~login,base)
        +refresh : Callback.Callback<Unit,List<&2,Models.Model()>> <- Callback.create(~Models.ModelRuntime,~Unit,~List<&2,Models.Model()>,~models,Session.modelRuntime(live))
        +importer : Callback.Callback<Run.ImportRequest,Host.ImportOutcome> <- Callback.create(~Runtime(),~Run.ImportRequest,~Host.ImportOutcome,~importSession,runtime)
        +sessions : Callback.Callback<Unit,Run.SessionChoices> <- Callback.create(~Listings,~Unit,~Run.SessionChoices,~listSessions,Listings{cwd,agentDir})
        +resume : Callback.Callback<Run.ResumeRequest,Host.ResumeOutcome> <- Callback.create(~Runtime(),~Run.ResumeRequest,~Host.ResumeOutcome,~resumeSession,runtime)
        Host.setRebindSession(Services(),runtime,Some{rebinder})
        result : Result<&2,&2,Run.Error,Unit> <- Run.runBound(live,Run.Binding{current,Controller.Replacement{new,forking},hook,login,refresh,importer,sessions,resume,None{},False{},None{}},Nil{},cwd,None{},agentDir,assetsRoot,None{},Nil{})
        Host.setRebindSession(Services(),runtime,None{})
        Callback.dispose(Run.LoginRequest,AuthLogin.Outcome(),login)
        Callback.dispose(Unit,List<&2,Models.Model()>,refresh)
        Callback.dispose(Run.ImportRequest,Host.ImportOutcome,importer)
        Callback.dispose(Unit,Run.SessionChoices,sessions)
        Callback.dispose(Run.ResumeRequest,Host.ResumeOutcome,resume)
        Callback.dispose(Unit,Result<&2,&2,String,Unit>,new)
        Callback.dispose(Host.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>,forking)
        Callback.dispose(Session.AgentSession,Unit,rebinder)
        oldHook : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook)
        old : Session.AgentSession <- Ref.dispose(Session.AgentSession,current)
        Host.dispose(Services(),runtime)
        Callback.dispose(Host.Request,Result<&1,&1,String,Host.Created<Services()>>,factory)
        Callback.dispose(Services(),Unit,release)
        checked(result)
    case _: IO.die(Unit,1,"expected assetsRoot cwd agentDir base")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
