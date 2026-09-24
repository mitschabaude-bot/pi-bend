import Base
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/coding-agent/src/core/agent-session-runtime.bend as SessionRuntime
import ../packages/runtime/src/callback.bend as Callback

# An RPC host for fixtures without a session runtime: replacement fails.
def refused() -> String: "Session replacement is not available in this fixture"
def refuseNew(env: Unit, parent: Maybe<&2,String>) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Fail{refused()})
def refuseSwitch(env: Unit, path: String) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Fail{refused()})
def refuseFork(env: Unit, request: SessionRuntime.ForkRequest) -> IO(Result<&2,&2,String,Maybe<&2,String>>): IO.pure(Result<&2,&2,String,Maybe<&2,String>>,Fail{refused()})

def create() -> IO(Rpc.Host):
  do IO<Rpc.Host>:
    opening : Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~Maybe<&2,String>,~Result<&2,&2,String,Unit>,~refuseNew,Unit{})
    switching : Callback.Callback<String,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~String,~Result<&2,&2,String,Unit>,~refuseSwitch,Unit{})
    forking : Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>> <- Callback.create(~Unit,~SessionRuntime.ForkRequest,~Result<&2,&2,String,Maybe<&2,String>>,~refuseFork,Unit{})
    return Rpc.Host{opening,switching,forking}
