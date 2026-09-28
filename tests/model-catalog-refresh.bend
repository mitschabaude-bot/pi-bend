import Base
import ../packages/coding-agent/src/core/model-runtime.bend as Runtime
import ../packages/ai/src/models.bend as Models
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/auth/credential-store.bend as Credentials
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

# The three contracts of upstream model-catalog-refresh.test.ts, exercised
# through the actual ModelRuntime rather than a mocked Promise.
type Gate is Data:
  Gate{calls: Ref.Ref<Nat>,entered: Chan(Unit),release: Chan(Unit),signal: Ref.Ref<Maybe<&2,Abort.AbortSignal<Unit>>>}

def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})

def nextCount(count: Nat) -> Nat & Unit: (count + 1n,Unit{})

def fetched(gate: Gate,context: Models.RefreshModelsContext) -> IO(Result<&2,&2,String,Unit>):
  match gate context:
    case Gate{calls,entered,release,signal} Models.RefreshModelsContext{_,_,_,False{},_,_}:
      IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case Gate{calls,entered,release,signal} Models.RefreshModelsContext{_,_,_,True{},_,current}:
      do IO<Result<&2,&2,String,Unit>>:
        Ref.modify(Nat,Unit,calls,nextCount)
        Ref.write(Maybe<&2,Abort.AbortSignal<Unit>>,signal,Some{current})
        started : Bool <- Chan.send(Unit,entered,Unit{})
        Ref.requireSent(started)
        released : Maybe<&1,Unit> <- Chan.recv(Unit,release)
        return Done{Unit{}}

def ambient(_: Unit,_: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(),Done{Some{Auth.AuthResult{Auth.ModelAuth{None{},None{},None{}},None{},None{}}}})

def runtime(gate: Gate) -> IO(Runtime.ModelRuntime):
  do IO<Runtime.ModelRuntime>:
    auth : Callback.Callback<Auth.ResolveInput,Auth.AuthOutcome()> <- Callback.create(~Unit,~Auth.ResolveInput,~Auth.AuthOutcome(),~ambient,Unit{})
    refresh : Models.RefreshModels() <- Callback.create(~Gate,~Models.RefreshModelsContext,~Result<&2,&2,String,Unit>,~fetched,gate)
    credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    Runtime.fromProviders([Models.Provider{"test","test","https://example.invalid",Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"test",None{},auth,None{}}},None{}},Nil{},Models.ApiStreams{},Some{refresh},None{}}],credentials,context)

def gate() -> IO(Gate):
  do IO<Gate>:
    calls : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    entered : Chan(Unit) <- Chan.new(Unit,3)
    release : Chan(Unit) <- Chan.new(Unit,3)
    signal : Ref.Ref<Maybe<&2,Abort.AbortSignal<Unit>>> <- Ref.new(Maybe<&2,Abort.AbortSignal<Unit>>,None{})
    return Gate{calls,entered,release,signal}

def waitStarted(gate: Gate) -> IO(Unit):
  match gate:
    case Gate{_,entered,_,_}:
      do IO<Unit>:
        received : Maybe<&1,Unit> <- Chan.recv(Unit,entered)
        return Unit{}

def releaseOne(gate: Gate) -> IO(Unit):
  match gate:
    case Gate{_,_,release,_}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit,release,Unit{})
        Ref.requireSent(sent)

def calls(gate: Gate) -> IO(Nat):
  match gate:
    case Gate{count,_,_,_}: Ref.read(Nat,count)

def activeWaiters(state: Runtime.SharedRefresh) -> Nat:
  match state:
    case Runtime.RefreshActive{_,_,_,waiters,_,_}: waiters
    case _: 0n

def waitForWaiters(+runtime: Runtime.ModelRuntime,+target: Nat,remaining: Nat) -> IO(Unit):
  match remaining:
    case 0n: IO.die(Unit,1,"shared refresh did not enroll both callers")
    case 1n+(rest):
      do IO<Unit>:
        state : Runtime.SharedRefresh <- Ref.read(Runtime.SharedRefresh,Runtime.sharedRef(runtime))
        Bool.pick(Unit -> IO(Unit),Nat.is_eq(activeWaiters(state),target),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          IO.sleep(1)
          waitForWaiters(runtime,target,rest))(Unit{})

def aborted(result: Runtime.ModelsRefreshResult) -> Bool:
  match result:
    case Runtime.ModelsRefreshResult{value,_}: value

def abortedSignal(current: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match current:
    case None{}: IO.pure(Bool,False{})
    case Some{value}: Abort.aborted(Unit,value)

def underlyingAborted(gate: Gate) -> IO(Bool):
  match gate:
    case Gate{_,_,_,signal}:
      do IO<Bool>:
        current : Maybe<&2,Abort.AbortSignal<Unit>> <- Ref.read(Maybe<&2,Abort.AbortSignal<Unit>>,signal)
        abortedSignal(current)

def sharedCall(runtime: Runtime.ModelRuntime,controller: Abort.AbortController<Unit>) -> IO(Runtime.ModelsRefreshResult):
  Runtime.refreshShared(runtime,Some{Abort.signal(Unit,controller)})

def sharedBetweenCallers() -> IO(Unit):
  do IO<Unit>:
    +g : Gate <- gate()
    +r : Runtime.ModelRuntime <- runtime(g)
    +a : Abort.AbortController<Unit> <- Abort.new(Unit)
    +b : Abort.AbortController<Unit> <- Abort.new(Unit)
    first : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,a))
    waitStarted(g)
    second : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,b))
    waitForWaiters(r,2n,1000n)
    count : Nat <- calls(g)
    check(Nat.is_eq(count,1n),"concurrent callers share one request")
    releaseOne(g)
    one : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,first)
    two : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,second)
    check(Bool.not(aborted(one)) && Bool.not(aborted(two)),"both callers receive completion")
    Abort.dispose(Unit,a)
    Abort.dispose(Unit,b)
    Runtime.dispose(r)

def independentCancellation() -> IO(Unit):
  do IO<Unit>:
    +g : Gate <- gate()
    +r : Runtime.ModelRuntime <- runtime(g)
    +a : Abort.AbortController<Unit> <- Abort.new(Unit)
    +b : Abort.AbortController<Unit> <- Abort.new(Unit)
    first : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,a))
    waitStarted(g)
    second : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,b))
    waitForWaiters(r,2n,1000n)
    stopped : Bool <- Abort.abort(Unit,a,None{})
    one : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,first)
    active : Bool <- underlyingAborted(g)
    check(aborted(one) && Bool.not(active),"one caller can stop without canceling the other")
    releaseOne(g)
    two : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,second)
    check(Bool.not(aborted(two)),"remaining caller completes")
    Abort.dispose(Unit,a)
    Abort.dispose(Unit,b)
    Runtime.dispose(r)

def abandonedRefresh() -> IO(Unit):
  do IO<Unit>:
    +g : Gate <- gate()
    +r : Runtime.ModelRuntime <- runtime(g)
    +a : Abort.AbortController<Unit> <- Abort.new(Unit)
    +b : Abort.AbortController<Unit> <- Abort.new(Unit)
    first : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,a))
    waitStarted(g)
    stopped : Bool <- Abort.abort(Unit,a,None{})
    one : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,first)
    active : Bool <- underlyingAborted(g)
    check(aborted(one) && active,"last caller aborts underlying request")
    second : Chan(Runtime.ModelsRefreshResult) <- IO.fork(Runtime.ModelsRefreshResult,sharedCall(r,b))
    waitStarted(g)
    count : Nat <- calls(g)
    check(Nat.is_eq(count,2n),"later caller starts a fresh request")
    releaseOne(g)
    releaseOne(g)
    two : Runtime.ModelsRefreshResult <- IO.join(Runtime.ModelsRefreshResult,second)
    check(Bool.not(aborted(two)),"fresh request completes")
    Abort.dispose(Unit,a)
    Abort.dispose(Unit,b)
    Runtime.dispose(r)

def main() -> IO(Unit):
  do IO<Unit>:
    sharedBetweenCallers()
    independentCancellation()
    abandonedRefresh()
