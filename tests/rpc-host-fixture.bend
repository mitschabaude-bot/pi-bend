import Base
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/coding-agent/src/core/agent-session-runtime.bend as SessionRuntime
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

# An RPC host for fixtures without a session runtime: replacement fails.
def refused() -> String: "Session replacement is not available in this fixture"
def refuseNew(env: Unit, parent: Maybe<&2,String>) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Fail{refused()})
def refuseSwitch(env: Unit, path: String) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Fail{refused()})
def refuseFork(env: Unit, request: SessionRuntime.ForkRequest) -> IO(Result<&2,&2,String,Maybe<&2,String>>): IO.pure(Result<&2,&2,String,Maybe<&2,String>>,Fail{refused()})

# A requested shutdown is recorded as a SHUTDOWN line on the given sink
# instead of ending the process.
def recordShutdown(sink: Callback.Callback<String,Unit>, _: Unit) -> IO(Unit): Callback.call(String,Unit,sink,"SHUTDOWN\n")

def createWith(sink: Callback.Callback<String,Unit>) -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    opening : Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~Maybe<&2,String>,~Result<&2,&2,String,Unit>,~refuseNew,Unit{})
    switching : Callback.Callback<String,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~String,~Result<&2,&2,String,Unit>,~refuseSwitch,Unit{})
    forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>> <- Callback.create(~Unit,~SessionRuntime.ForkRequest,~Result<&2,&2,String,Maybe<&2,String>>,~refuseFork,Unit{})
    shutdown : Callback.Callback<Unit,Unit> <- Callback.create(~Callback.Callback<String,Unit>,~Unit,~Unit,~recordShutdown,sink)
    requested : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    return Rpc.Host{opening,switching,forking,shutdown,requested}

def ignore(env: Unit, text: String) -> IO(Unit): IO.pure(Unit,Unit{})
def create() -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    ignored : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~ignore,Unit{})
    createWith(ignored)
