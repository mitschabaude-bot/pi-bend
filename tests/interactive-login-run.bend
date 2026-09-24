import Base
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
import ../packages/ai/src/providers/openai-codex.models.bend as CodexModels
import ../packages/ai/src/providers/anthropic.models.bend as AnthropicModels
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as Schema

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
        current : List<&2,Tree.SessionInfo> <- Sessions.list(cwd,Some{cwd},agentDir)
        all : List<&2,Tree.SessionInfo> <- Sessions.listAll(Some{cwd},cwd)
        return Run.SessionChoices{current,all}
def loginCopied(+base: String,request: Run.LoginRequest) -> IO(AuthLogin.Outcome()):
  match request:
    case Run.LoginRequest{provider,signal,notice,manual,manualDone}:
      match provider:
        case "anthropic": AuthLogin.authenticateAnthropicWithTokenURL(base ++ "/anthropic-token",AuthLogin.BrowserInteraction{signal,manual,manualDone})
        case _: AuthLogin.authenticate(Codex.DeviceEndpoints{base ++ "/usercode",base ++ "/token",base ++ "/exchange",base ++ "/codex/device"},signal,notice)
def login(base: String,request: Run.LoginRequest) -> IO(AuthLogin.Outcome()): loginCopied(base,request)
def models(_: Unit,_: Unit) -> IO(List<&2,Models.Model()>): IO.pure(List<&2,Models.Model()>,Faux.fauxModel() <> List.append(&2,Models.Model(),CodexModels.OPENAI_CODEX_MODELS(),AnthropicModels.ANTHROPIC_MODELS()))
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
        created : Sessions.Outcome(Session.Session()) <- Session.createSession(cwd,Some{cwd},agentDir,Sessions.noOptions())
        stored : Session.Session() <- requireSession(created)
        +factory : Host.Factory(Services()) <- Callback.create(~String,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~Fixture.factoryNoModel,agentDir)
        +release : Callback.Callback<Services(),Unit> <- Callback.create(~Unit,~Services(),~Unit,~Fixture.release,Unit{})
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
        +refresh : Callback.Callback<Unit,List<&2,Models.Model()>> <- Callback.create(~Unit,~Unit,~List<&2,Models.Model()>,~models,Unit{})
        +importer : Callback.Callback<Run.ImportRequest,Host.ImportOutcome> <- Callback.create(~Runtime(),~Run.ImportRequest,~Host.ImportOutcome,~importSession,runtime)
        +sessions : Callback.Callback<Unit,Run.SessionChoices> <- Callback.create(~Listings,~Unit,~Run.SessionChoices,~listSessions,Listings{cwd,agentDir})
        +resume : Callback.Callback<Run.ResumeRequest,Host.ResumeOutcome> <- Callback.create(~Runtime(),~Run.ResumeRequest,~Host.ResumeOutcome,~resumeSession,runtime)
        Host.setRebindSession(Services(),runtime,Some{rebinder})
        result : Result<&2,&2,Run.Error,Unit> <- Run.runBound(live,Run.Binding{current,Controller.Replacement{new,forking},hook,login,refresh,importer,sessions,resume,None{}},Nil{},cwd,None{},agentDir,assetsRoot,None{},Nil{})
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
