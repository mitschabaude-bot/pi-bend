import Base
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/coding-agent/src/core/agent-session-runtime.bend as SessionRuntime
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

# An RPC host for fixtures without a session runtime: replacement fails.
def refused() -> String: "Session replacement is not available in this fixture"
def refuseNew(env: Unit, parent: Maybe<&2,String>) -> IO(Result<&2,&2,String,Ctx.SessionChange>): IO.pure(Result<&2,&2,String,Ctx.SessionChange>,Fail{refused()})
def refuseSwitch(env: Unit, path: String) -> IO(Result<&2,&2,String,Ctx.SessionChange>): IO.pure(Result<&2,&2,String,Ctx.SessionChange>,Fail{refused()})
def refuseFork(env: Unit, request: SessionRuntime.ForkRequest) -> IO(Result<&2,&2,String,SessionRuntime.ForkOutcome>): IO.pure(Result<&2,&2,String,SessionRuntime.ForkOutcome>,Fail{refused()})

# A requested shutdown is recorded as a SHUTDOWN line on the given sink
# instead of ending the process.
def recordShutdown(sink: Callback.Callback<String,Unit>, _: Unit) -> IO(Unit): Callback.call(String,Unit,sink,"SHUTDOWN\n")

def createWith(sink: Callback.Callback<String,Unit>) -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    opening : Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Unit,~Maybe<&2,String>,~Result<&2,&2,String,Ctx.SessionChange>,~refuseNew,Unit{})
    switching : Callback.Callback<String,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Unit,~String,~Result<&2,&2,String,Ctx.SessionChange>,~refuseSwitch,Unit{})
    forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,SessionRuntime.ForkOutcome>> <- Callback.create(~Unit,~SessionRuntime.ForkRequest,~Result<&2,&2,String,SessionRuntime.ForkOutcome>,~refuseFork,Unit{})
    shutdown : Callback.Callback<Unit,Unit> <- Callback.create(~Callback.Callback<String,Unit>,~Unit,~Unit,~recordShutdown,sink)
    requested : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    return Rpc.Host{opening,switching,forking,shutdown,requested}

def ignore(env: Unit, text: String) -> IO(Unit): IO.pure(Unit,Unit{})
def create() -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    ignored : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~ignore,Unit{})
    createWith(ignored)

# A host whose extensions cancel every session change (session_before_switch
# and session_before_fork answering { cancel: true }).
def cancelNew(env: Unit, parent: Maybe<&2,String>) -> IO(Result<&2,&2,String,Ctx.SessionChange>): IO.pure(Result<&2,&2,String,Ctx.SessionChange>,Done{Ctx.SessionChange{True{}}})
def cancelSwitch(env: Unit, path: String) -> IO(Result<&2,&2,String,Ctx.SessionChange>): IO.pure(Result<&2,&2,String,Ctx.SessionChange>,Done{Ctx.SessionChange{True{}}})
def cancelFork(env: Unit, request: SessionRuntime.ForkRequest) -> IO(Result<&2,&2,String,SessionRuntime.ForkOutcome>): IO.pure(Result<&2,&2,String,SessionRuntime.ForkOutcome>,Done{SessionRuntime.ForkOutcome{True{},None{}}})
def createCancelling(sink: Callback.Callback<String,Unit>) -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    opening : Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Unit,~Maybe<&2,String>,~Result<&2,&2,String,Ctx.SessionChange>,~cancelNew,Unit{})
    switching : Callback.Callback<String,Result<&2,&2,String,Ctx.SessionChange>> <- Callback.create(~Unit,~String,~Result<&2,&2,String,Ctx.SessionChange>,~cancelSwitch,Unit{})
    forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,SessionRuntime.ForkOutcome>> <- Callback.create(~Unit,~SessionRuntime.ForkRequest,~Result<&2,&2,String,SessionRuntime.ForkOutcome>,~cancelFork,Unit{})
    shutdown : Callback.Callback<Unit,Unit> <- Callback.create(~Callback.Callback<String,Unit>,~Unit,~Unit,~recordShutdown,sink)
    requested : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    return Rpc.Host{opening,switching,forking,shutdown,requested}
