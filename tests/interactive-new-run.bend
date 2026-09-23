import Base
import ./agent-session-runtime.bend as Fixture
import ./agent-session.bend as Faux
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/agent-session-runtime.bend as Host
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
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
    case assetsRoot <> +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        created : Sessions.Outcome(Session.Session()) <- Session.createSession(cwd,Some{cwd},agentDir,Sessions.noOptions())
        stored : Session.Session() <- requireSession(created)
        +factory : Host.Factory(Services()) <- Callback.create(~String,~Host.Request,~Result<&1,&1,String,Host.Created<Services()>>,~Fixture.factory,agentDir)
        +release : Callback.Callback<Services(),Unit> <- Callback.create(~Unit,~Services(),~Unit,~Fixture.release,Unit{})
        hosted : Result<&2,&2,String,Runtime()> <- Host.create(Services(),factory,release,agentDir,cwd,stored)
        +runtime : Runtime() <- requireHost(hosted)
        currentSession : Maybe<&2,Session.AgentSession> <- Host.session(Services(),runtime)
        +live : Session.AgentSession <- requireLive(currentSession)
        +current : Ref.Ref<Session.AgentSession> <- Ref.new(Session.AgentSession,live)
        +hook : Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,None{})
        +rebinder : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~Binding,~Session.AgentSession,~Unit,~rebound,Binding{current,hook})
        +new : Callback.Callback<Unit,Result<&2,&2,String,Unit>> <- Callback.create(~Runtime(),~Unit,~Result<&2,&2,String,Unit>,~startNew,runtime)
        Host.setRebindSession(Services(),runtime,Some{rebinder})
        result : Result<&2,&2,Run.Error,Unit> <- Run.runBound(live,Run.Binding{current,new,hook},Nil{},cwd,None{},agentDir,assetsRoot,None{},Faux.fauxModel() <> Nil{})
        Host.setRebindSession(Services(),runtime,None{})
        Callback.dispose(Unit,Result<&2,&2,String,Unit>,new)
        Callback.dispose(Session.AgentSession,Unit,rebinder)
        oldHook : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,hook)
        old : Session.AgentSession <- Ref.dispose(Session.AgentSession,current)
        Host.dispose(Services(),runtime)
        Callback.dispose(Host.Request,Result<&1,&1,String,Host.Created<Services()>>,factory)
        Callback.dispose(Services(),Unit,release)
        checked(result)
    case _: IO.die(Unit,1,"expected assetsRoot cwd agentDir")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
