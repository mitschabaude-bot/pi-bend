import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/helpers.bend as Helpers
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/auth/resolve.bend as Resolve
import ../packages/ai/src/auth/credential-store.bend as MemoryCredentials
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/provider-composer.bend as Composer
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/agent/src/types.bend as AgentTypes
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref

# The upstream model-runtime-auth-options test exercises a scoped credential
# read, an error visible through getError, and clearing that error on success.
# This also checks that a scoped query does not replace the shared snapshot.
type State is Data:
  State{reads: List<&2, String>, fail: Bool, secondEnabled: Bool, firstEnabled: Bool}

def recorded(reads: List<&2, String>, fail: Bool, second: Bool, first: Bool, id: String) -> State:
  State{id <> reads, fail, second, first}

def observed(state: State, +id: String) -> State & Auth.StoreResult(Maybe<&2, Auth.Credential>):
  match state:
    case State{reads, +fail, +secondEnabled, +firstEnabled}:
      +next = recorded(reads, fail, secondEnabled, firstEnabled, id)
      Bool.pick(State & Auth.StoreResult(Maybe<&2, Auth.Credential>), fail && String.eq(id, "a"),
        (next, Fail{"read failed for a"}),
        (next, Done{Bool.pick(Maybe<&2, Auth.Credential>, (String.eq(id, "b") && Bool.not(secondEnabled)) || (String.eq(id, "a") && Bool.not(firstEnabled)), None{}, Some{Auth.ApiKeyCredential{Some{"stored-key"}, None{}}})}))

def readStore(state: Ref.Ref<State>, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Request{id, _}: Ref.modify(State, Auth.StoreResult(Maybe<&2, Auth.Credential>), state, current => observed(current, id))

def listStore(_: Unit, _: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{Nil{}})

def modifyStore(_: Unit, _: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Fail{"unused"})

def deleted(state: State, id: String) -> State & Auth.StoreResult(Unit):
  match state:
    case State{reads, fail, second, first}:
      (State{reads, fail, second, Bool.pick(Bool, String.eq(id, "a"), False{}, first)}, Done{Unit{}})

def deleteStore(state: Ref.Ref<State>, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match request:
    case Auth.Request{id, _}: Ref.modify(State, Auth.StoreResult(Unit), state, current => deleted(current, id))

def credentials(+state: Ref.Ref<State>) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Ref.Ref<State>, ~Auth.Request, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~readStore, state)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Unit, ~(Auth.Signal()), ~(Auth.StoreResult(List<&2, Auth.CredentialInfo>)), ~listStore, Unit{})
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Unit, ~Auth.Modify, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~modifyStore, Unit{})
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Ref.Ref<State>, ~Auth.Request, ~(Auth.StoreResult(Unit)), ~deleteStore, state)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def model(id: String) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"only", "Only", Ai.OpenAIResponsesApi{}, id, "https://faux.invalid", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(1000), U32.to_f64(100), None{}, None{}, None{}}

def cachedModel(id: String) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"cached", "Cached", Ai.OpenAIResponsesApi{}, id, "https://faux.invalid", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(1000), U32.to_f64(100), None{}, None{}, None{}}

def providerWithRefresh(+id: String, refresh: Maybe<&2, AiModels.RefreshModels()>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Test API key", ["PI_AVAILABILITY_TEST_UNUSED"])
    return AiModels.Provider{id, id, "https://faux.invalid", Auth.ProviderAuth{Some{apiKey}, None{}}, [model(id)], AiModels.ApiStreams{}, refresh, None{}}

def provider(+id: String) -> IO(AiModels.Provider): providerWithRefresh(id, None{})

type RefreshState is Data:
  RefreshState{calls: Nat, fail: Bool}

def called(state: RefreshState) -> RefreshState & Bool:
  match state:
    case RefreshState{calls, +fail}: (RefreshState{calls + 1n, fail}, fail)

def setRefreshFailure(state: RefreshState, fail: Bool) -> RefreshState & Unit:
  match state:
    case RefreshState{calls, _}: (RefreshState{calls, fail}, Unit{})

def require(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def streamFailure(message: String, _: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  IO.pure(Composer.StreamOutput(), Fail{Tools.Failure{message}})

def failedWith(result: Composer.StreamOutput(), expected: String) -> Bool:
  match result:
    case Fail{Tools.Failure{message}}: String.eq(message, expected)
    case _: False{}

def checkStreamOwnership(+runtime: Models.ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    +fallback : Composer.ProviderStream() <- C.create(~String, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~streamFailure, "session")
    global : Composer.ProviderStream() <- C.create(~String, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~streamFailure, "runtime")
    +request : Composer.StreamRequest() = AgentTypes.StreamInput{model("a"), Ai.TranscriptContext{Nil{}}, None{}}
    local : Composer.StreamOutput() <- Models.streamSimple(runtime, request, Models.RequestTransforms{None{}, Some{fallback}})
    require(failedWith(local, "session"), "per-request stream did not serve an unconfigured runtime")
    Models.setApiStreams(runtime, Some{global})
    selected : Composer.StreamOutput() <- Models.streamSimple(runtime, request, Models.RequestTransforms{None{}, Some{fallback}})
    require(failedWith(selected, "runtime"), "session stream replaced the injected runtime stream")
    ordinary : Composer.StreamOutput() <- Models.streamSimple(runtime, request, Models.noTransforms())
    require(failedWith(ordinary, "runtime"), "session stream changed ordinary runtime dispatch")
    C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), fallback)

def checkAuthGate(+runtime: Models.ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    missing : Composer.StreamOutput() <- Models.streamSimple(runtime, AgentTypes.StreamInput{model("a"), Ai.TranscriptContext{Nil{}}, None{}}, Models.noTransforms())
    require(failedWith(missing, "Provider is not configured: a"), "unconfigured provider reached the transport")
    unknown : Composer.StreamOutput() <- Models.streamSimple(runtime, AgentTypes.StreamInput{model("missing"), Ai.TranscriptContext{Nil{}}, None{}}, Models.noTransforms())
    require(failedWith(unknown, "Unknown provider: missing"), "unknown provider reached the transport")

def refreshCached(state: Ref.Ref<RefreshState>, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match context:
    case AiModels.RefreshModelsContext{_, _, _, True{}, _, _}: IO.die(Result<&2, &2, String, Unit>, 1, "credential synchronization used the network")
    case AiModels.RefreshModelsContext{_, _, publish, False{}, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        fail : Bool <- Ref.modify(RefreshState, Bool, state, called)
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), fail,
          _ => IO.pure(Result<&2, &2, String, Unit>, Fail{"cache restore failed"}),
          _ => do IO<Result<&2, &2, String, Unit>>:
            accepted : Bool <- C.call(AiModels.ModelsPublication, Bool, publish, AiModels.ModelsPublication{AiModels.KeepStored{}, Some{[model("dynamic"), cachedModel("dynamic")]}})
            require(accepted, "cached model publication was rejected")
            return Done{Unit{}})(Unit{})

def updated(state: State, fail: Bool, enabled: Bool) -> State & Unit:
  match state:
    case State{_, _, _, first}: (State{Nil{}, fail, enabled, first}, Unit{})

def successfulCount(result: AiModels.AvailableResult(), count: Nat) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{models}: Nat.is_eq(List.length(&2, AiModels.Model(), models), count)

def failed(result: AiModels.AvailableResult()) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{_}: False{}

def errorContains(value: Maybe<&2, String>, needle: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: String.contains(text, needle)

def allB(reads: List<&2, String>) -> Bool:
  match reads:
    case Nil{}: True{}
    case id <> rest: String.eq(id, "b") && allB(rest)

def onlyB(state: State) -> Bool:
  match state:
    case State{Nil{}, _, _, _}: False{}
    case State{reads, _, _, _}: allB(reads)

def firstStored(state: State) -> Bool:
  match state:
    case State{_, _, _, enabled}: enabled

def loggedOut(result: Result<&2, &2, Resolve.ModelsError, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def keyIs(result: Auth.StoreResult(Maybe<&2, Auth.Credential>), expected: String) -> Bool:
  match result:
    case Done{Some{Auth.ApiKeyCredential{Some{key}, _}}}: String.eq(key, expected)
    case _: False{}

def synchronizationFailed(result: Result<&2, &2, Resolve.ModelsError, Unit>) -> Bool:
  match result:
    case Fail{error}: String.contains(Resolve.errorMessage(error), "cache restore failed")
    case Done{_}: False{}

def loginSyncFailed(result: Auth.LoginOutcome()) -> Bool:
  match result:
    case Fail{+message}: String.contains(message, "Credential saved") && String.contains(message, "cache restore failed")
    case Done{_}: False{}
def loginSucceeded(result: Auth.LoginOutcome()) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def loginPrompt(_: Unit, _: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  IO.pure(Result<&2, &2, String, String>, Done{"login-key"})

def loginNotice(_: Unit, _: Auth.AuthEvent) -> IO(Unit): IO.pure(Unit, Unit{})

def noCredential(result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Bool:
  match result:
    case Done{None{}}: True{}
    case _: False{}

def check(+runtime: Models.ModelRuntime, +state: Ref.Ref<State>) -> IO(Unit):
  do IO<Unit>:
    Ref.modify(State, Unit, state, current => updated(current, False{}, False{}))
    scoped : AiModels.AvailableResult() <- Models.getAvailable(runtime, Some{"b"}, None{})
    require(successfulCount(scoped, 0n), "scoped query should see changed credentials")
    reads : State <- Ref.read(State, state)
    require(onlyB(reads), "scoped query should read only b")
    snapshot : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), snapshot), 2n), "scoped query changed the snapshot")
    Ref.modify(State, Unit, state, current => updated(current, True{}, False{}))
    failure : AiModels.AvailableResult() <- Models.getAvailable(runtime, Some{"a"}, None{})
    require(failed(failure), "credential read failure was swallowed")
    error : Maybe<&2, String> <- Models.getError(runtime)
    require(errorContains(error, "Availability refresh: Credential store read failed for a"), "availability error missing")
    Ref.modify(State, Unit, state, current => updated(current, False{}, False{}))
    fresh : AiModels.AvailableResult() <- Models.getAvailable(runtime, None{}, None{})
    require(successfulCount(fresh, 1n), "full query did not refresh the snapshot")
    cleared : Maybe<&2, String> <- Models.getError(runtime)
    require(Maybe.is_none(&2, String, cleared), "successful refresh did not clear error")
    final : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), final), 1n), "full query did not publish snapshot")
    logout : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.logout(runtime, "a", None{})
    require(loggedOut(logout), "runtime logout failed")
    remaining : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), remaining), "logout returned before availability changed")
    override : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(runtime, "a", "session-key", None{})
    require(loggedOut(override), "runtime key override failed")
    visibleKey : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(Models.credentialsOf(runtime), "a", None{})
    require(keyIs(visibleKey, "session-key"), "runtime key was not used for auth")
    overridden : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), overridden), 1n), "runtime key did not publish availability")
    stored : State <- Ref.read(State, state)
    require(Bool.not(firstStored(stored)), "runtime key modified the injected store")
    removed : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.removeRuntimeApiKey(runtime, "a", None{})
    require(loggedOut(removed), "runtime key removal failed")
    afterRemoval : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), afterRemoval), "runtime key removal did not publish availability")

def fiveCalls(state: RefreshState) -> Bool:
  match state:
    case RefreshState{calls, _}: Nat.is_eq(calls, 5n)

def checkDynamicSynchronization() -> IO(Unit):
  do IO<Unit>:
    +refreshState : Ref.Ref<RefreshState> <- Ref.new(RefreshState, RefreshState{0n, True{}})
    +refresh : AiModels.RefreshModels() <- C.create(~Ref.Ref<RefreshState>, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshCached, refreshState)
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    dynamic : AiModels.Provider <- providerWithRefresh("dynamic", Some{refresh})
    +runtime : Models.ModelRuntime <- Models.fromProviders([dynamic], store, context)
    failed : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(runtime, "dynamic", "runtime-key", None{})
    require(synchronizationFailed(failed), "cache restore failure was swallowed")
    unchanged : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), unchanged), "failed synchronization published availability")
    effective : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(Models.credentialsOf(runtime), "dynamic", None{})
    require(keyIs(effective, "runtime-key"), "committed runtime key was lost after sync failure")
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, False{}))
    restored : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(runtime, "dynamic", "runtime-key", None{})
    require(loggedOut(restored), "successful local refresh failed")
    available : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), available), 2n), "cached catalog did not reach availability")
    removed : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.removeRuntimeApiKey(runtime, "dynamic", None{})
    require(loggedOut(removed), "runtime key removal failed after local refresh")
    unavailable : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), unavailable), "removed key left cached models available")
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, True{}))
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    login : Auth.LoginOutcome() <- Models.login(runtime, "dynamic", Auth.ApiKeyType{}, Auth.AuthInteraction{None{}, prompt, notify})
    require(loginSyncFailed(login), "login did not report a committed credential and failed refresh")
    persisted : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    require(keyIs(persisted, "login-key"), "failed synchronization lost the stored login credential")
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, False{}))
    logout : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.logout(runtime, "dynamic", None{})
    require(loggedOut(logout), "logout did not synchronize cached catalog")
    deleted : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    require(noCredential(deleted), "logout did not delete stored credential")
    count : RefreshState <- Ref.read(RefreshState, refreshState)
    require(fiveCalls(count), "credential operations skipped local cache refresh")
    Models.dispose(runtime)
    Auth.disposeStore(store)
    previous : RefreshState <- Ref.dispose(RefreshState, refreshState)
    return Unit{}

# An older network refresh must not hold a new login or its local catalog
# synchronization. The gated refresh is released only after login completes.
type RefreshGate is Data: RefreshGate{started: Chan(Unit),release: Chan(Unit)}
def ambientGateAuth(_: Unit,_: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(),Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{"ambient-key"},None{},None{}},None{},Some{"ambient"}}}})
def gateLogin(_: Unit,_: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  IO.pure(Auth.LoginOutcome(),Done{Auth.ApiKeyCredential{Some{"login-key"},None{}}})
def gatedProvider(refresh: AiModels.RefreshModels()) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    login : C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()> <- C.create(~Unit,~Auth.ProviderAuthInteraction,~Auth.LoginOutcome(),~gateLogin,Unit{})
    resolve : C.Callback<Auth.ResolveInput,Auth.AuthOutcome()> <- C.create(~Unit,~Auth.ResolveInput,~Auth.AuthOutcome(),~ambientGateAuth,Unit{})
    return AiModels.Provider{"dynamic","dynamic","https://faux.invalid",Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test API key",Some{login},resolve,None{}}},None{}},[model("dynamic")],AiModels.ApiStreams{},Some{refresh},None{}}
def gatedRefresh(gate: RefreshGate,context: AiModels.RefreshModelsContext) -> IO(Result<&2,&2,String,Unit>):
  match gate context:
    case RefreshGate{started,release} AiModels.RefreshModelsContext{_,_,_,True{},_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        sent : Bool <- Chan.send(Unit,started,Unit{})
        done : Maybe<&1,Unit> <- Chan.recv(Unit,release)
        return Done{Unit{}}
    case _ _: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
def loginBesideStalledRefresh() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit,1)
    +release : Chan(Unit) <- Chan.new(Unit,1)
    +refresh : AiModels.RefreshModels() <- C.create(~RefreshGate,~AiModels.RefreshModelsContext,~Result<&2,&2,String,Unit>,~gatedRefresh,RefreshGate{started,release})
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    provider : AiModels.Provider <- gatedProvider(refresh)
    +runtime : Models.ModelRuntime <- Models.fromProviders([provider],store,context)
    +old : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult,Models.refresh(runtime,Models.ModelsRefreshOptions{Some{True{}},Some{["dynamic"]},None{},None{}}))
    began : Maybe<&1,Unit> <- Chan.recv(Unit,started)
    +prompt : C.Callback<Auth.AuthPrompt,Result<&2,&2,String,String>> <- C.create(~Unit,~Auth.AuthPrompt,~Result<&2,&2,String,String>,~loginPrompt,Unit{})
    +notify : C.Callback<Auth.AuthEvent,Unit> <- C.create(~Unit,~Auth.AuthEvent,~Unit,~loginNotice,Unit{})
    login : Auth.LoginOutcome() <- Models.login(runtime,"dynamic",Auth.ApiKeyType{},Auth.AuthInteraction{None{},prompt,notify})
    require(loginSucceeded(login),"login waited for an older stalled network refresh")
    stored : Auth.StoreResult(Maybe<&2,Auth.Credential>) <- Auth.read(store,"dynamic",None{})
    require(keyIs(stored,"login-key"),"login did not persist its credential")
    available : List<&2,AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2,AiModels.Model(),available),1n),"login did not publish local availability")
    released : Bool <- Chan.send(Unit,release,Unit{})
    late : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult,old)
    C.dispose(Auth.AuthPrompt,Result<&2,&2,String,String>,prompt)
    C.dispose(Auth.AuthEvent,Unit,notify)
    Models.dispose(runtime)
    Auth.disposeStore(store)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    +state : Ref.Ref<State> <- Ref.new(State, State{Nil{}, False{}, True{}, True{}})
    +store : Auth.CredentialStore <- credentials(state)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    a : AiModels.Provider <- provider("a")
    b : AiModels.Provider <- provider("b")
    +runtime : Models.ModelRuntime <- Models.fromProviders([a, b], store, context)
    checkStreamOwnership(runtime)
    check(runtime, state)
    checkAuthGate(runtime)
    Models.dispose(runtime)
    Auth.disposeStore(store)
    previous : State <- Ref.dispose(State, state)
    checkDynamicSynchronization()
    loginBesideStalledRefresh()
    IO.print("model availability: scoped reads, credential synchronization, snapshots, stream ownership, and auth gating pass")
