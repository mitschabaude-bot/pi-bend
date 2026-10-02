import Base
import ../packages/ai/src/utils/event-stream.bend as LifecycleEvents
import ../packages/ai/src/models-store.bend as Store
import ../packages/runtime/src/abort.bend as Abort
import ../packages/ai/src/auth/oauth/openrouter.bend as OpenRouterOAuth
import ../packages/ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../packages/ai/src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../packages/ai/src/providers/radius.bend as Radius
import ../packages/ai/src/providers/cloudflare-workers-ai.bend as Workers
import ../packages/ai/src/providers/cloudflare-ai-gateway.bend as Gateway
import ../packages/ai/src/providers/openrouter.bend as OpenRouter
import ../packages/ai/src/providers/openai-codex.bend as Codex
import ../packages/ai/src/providers/anthropic.bend as Anthropic
import ../packages/ai/src/providers/google-vertex.bend as Vertex
import ../packages/ai/src/providers/amazon-bedrock.bend as Bedrock
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
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
    +request : Composer.SimpleStreamRequest() = AgentTypes.StreamInput{model("a"), Ai.TranscriptContext{Nil{}}, None{}}
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

def loggedOut(result: Models.CredentialOutcome(Unit)) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def keyIs(result: Auth.StoreResult(Maybe<&2, Auth.Credential>), expected: String) -> Bool:
  match result:
    case Done{Some{Auth.ApiKeyCredential{Some{key}, _}}}: String.eq(key, expected)
    case _: False{}

def synchronizationFailed(result: Models.CredentialOutcome(Unit)) -> Bool:
  match result:
    case Fail{Models.CredentialSynchronizationError{_, _, _, cause}}: String.contains(Resolve.errorMessage(cause), "cache restore failed")
    case Fail{_}: False{}
    case Done{_}: False{}

def loginSyncFailed(result: Models.LoginOutcome()) -> Bool:
  match result:
    case Fail{Models.CredentialSynchronizationError{_, Models.LoginOperation{}, Some{Auth.ApiKeyCredential{Some{key}, _}}, cause}}: String.eq(key, "login-key") && String.contains(Resolve.errorMessage(cause), "cache restore failed")
    case Fail{_}: False{}
    case Done{_}: False{}
def loginSucceeded(result: Models.LoginOutcome()) -> Bool:
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
    logout : Models.CredentialOutcome(Unit) <- Models.logout(runtime, "a", None{})
    require(loggedOut(logout), "runtime logout failed")
    remaining : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), remaining), "logout returned before availability changed")
    override : Models.CredentialOutcome(Unit) <- Models.setRuntimeApiKey(runtime, "a", "session-key", None{})
    require(loggedOut(override), "runtime key override failed")
    visibleKey : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(Models.credentialsOf(runtime), "a", None{})
    require(keyIs(visibleKey, "session-key"), "runtime key was not used for auth")
    overridden : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), overridden), 1n), "runtime key did not publish availability")
    stored : State <- Ref.read(State, state)
    require(Bool.not(firstStored(stored)), "runtime key modified the injected store")
    removed : Models.CredentialOutcome(Unit) <- Models.removeRuntimeApiKey(runtime, "a", None{})
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
    failed : Models.CredentialOutcome(Unit) <- Models.setRuntimeApiKey(runtime, "dynamic", "runtime-key", None{})
    require(synchronizationFailed(failed), "cache restore failure was swallowed")
    unchanged : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), unchanged), "failed synchronization published availability")
    effective : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(Models.credentialsOf(runtime), "dynamic", None{})
    require(keyIs(effective, "runtime-key"), "committed runtime key was lost after sync failure")
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, False{}))
    restored : Models.CredentialOutcome(Unit) <- Models.setRuntimeApiKey(runtime, "dynamic", "runtime-key", None{})
    require(loggedOut(restored), "successful local refresh failed")
    available : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), available), 2n), "cached catalog did not reach availability")
    removed : Models.CredentialOutcome(Unit) <- Models.removeRuntimeApiKey(runtime, "dynamic", None{})
    require(loggedOut(removed), "runtime key removal failed after local refresh")
    unavailable : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(List.is_empty(&2, AiModels.Model(), unavailable), "removed key left cached models available")
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, True{}))
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    login : Models.LoginOutcome() <- Models.login(runtime, "dynamic", Auth.ApiKeyType{}, Auth.AuthInteraction{None{}, prompt, notify})
    require(loginSyncFailed(login), "login did not report a committed credential and failed refresh")
    persisted : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    require(keyIs(persisted, "login-key"), "failed synchronization lost the stored login credential")
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)
    Ref.modify(RefreshState, Unit, refreshState, state => setRefreshFailure(state, False{}))
    logout : Models.CredentialOutcome(Unit) <- Models.logout(runtime, "dynamic", None{})
    require(loggedOut(logout), "logout did not synchronize cached catalog")
    deleted : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    require(noCredential(deleted), "logout did not delete stored credential")
    count : RefreshState <- Ref.read(RefreshState, refreshState)
    require(fiveCalls(count), "credential operations skipped local cache refresh")
    IO.print("ok does not run network refresh inside the credential operation chain")
    IO.print("ok reports committed credentials when local synchronization fails")
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
    login : Models.LoginOutcome() <- Models.login(runtime,"dynamic",Auth.ApiKeyType{},Auth.AuthInteraction{None{},prompt,notify})
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

# Native ports of the other ten model-runtime-auth-options contracts.
# Authentication methods are typed provider fields, rather than JS properties.
def checked(ok: Bool, +name: String) -> IO(Unit):
  do IO<Unit>:
    require(ok, name)
    IO.print("ok " ++ name)

def storeCredential(value: Auth.Credential, _: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{value}})

def saveCredential(store: Auth.CredentialStore, id: String, value: Auth.Credential) -> IO(Unit):
  do IO<Unit>:
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~storeCredential, value)
    saved : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, id, update, None{})
    require(Result.is_done(&2, &2, String, Maybe<&2, Auth.Credential>, saved), "fixture credential write failed")
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)

def networkForbidden(_: Unit, request: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  IO.die(Fetch.Result_(Unit), 1, "auth-option fixture attempted a network request")

def hasMethod(provider: Maybe<&2, AiModels.Provider>, kind: Auth.CredentialType, name: String, method: String, subscription: Bool) -> Bool:
  match provider kind:
    case Some{AiModels.Provider{_, +actualName, _, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{actualMethod, _, _, _}}, _}, _, _, _, _}} Auth.ApiKeyType{}: String.eq(actualName, name) && String.eq(actualMethod, method)
    case Some{AiModels.Provider{_, +actualName, _, Auth.ProviderAuth{_, Some{Auth.OAuthAuth{actualMethod, +flag, _, _, _, _}}}, _, _, _, _}} Auth.OAuthType{}: String.eq(actualName, name) && String.eq(actualMethod, method) && Bool.pick(Bool, subscription, flag, Bool.not(flag))
    case _ _: False{}

def methodCount(provider: Maybe<&2, AiModels.Provider>) -> Nat:
  match provider:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{key, oauth}, _, _, _, _}}: Bool.pick(Nat, Maybe.is_some(&2, Auth.ApiKeyAuth, key), 1n, 0n) + Bool.pick(Nat, Maybe.is_some(&2, Auth.OAuthAuth, oauth), 1n, 0n)
    case None{}: 0n

def hasKeyLogin(provider: Maybe<&2, AiModels.Provider>) -> Bool:
  match provider:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, Some{_}, _, _}}, None{}}, _, _, _, _}}: True{}
    case _: False{}

def resolvedKey(auth: Resolve.Resolution(), key: String) -> Bool:
  match auth:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{actual}, _, _}, _, _}}}: String.eq(actual, key)
    case _: False{}

def oauthStatus(result: Result<&2, &2, String, Maybe<&2, Auth.AuthCheck>>) -> Bool:
  match result:
    case Done{Some{Auth.AuthCheck{_, Auth.OAuthType{}}}}: True{}
    case _: False{}

def subscription(+runtime: Models.ModelRuntime, +id: String, expected: Bool) -> IO(Bool):
  do IO<Bool>:
    oauth : Bool <- Models.isUsingOAuth(runtime, id)
    +active : Bool <- Models.isUsingSubscription(runtime, id)
    return oauth && Bool.pick(Bool, expected, active, Bool.not(active))

def providerMetadata() -> IO(Unit):
  do IO<Unit>:
    +fetch : Fetch.Fetch(Unit) <- C.create(~Unit, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~networkForbidden, Unit{})
    anthropicAuth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, Runtime.urlContext())
    codexAuth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch, Runtime.urlContext())
    openrouterAuth : Auth.OAuthAuth <- OpenRouterOAuth.openRouterOAuth(fetch, Runtime.urlContext())
    a : AiModels.Provider <- Anthropic.anthropicProvider(Some{anthropicAuth})
    bedrock : AiModels.Provider <- Bedrock.amazonBedrockProvider()
    vertex : AiModels.Provider <- Vertex.googleVertexProvider()
    gateway : AiModels.Provider <- Gateway.cloudflareAIGatewayProvider()
    workers : AiModels.Provider <- Workers.cloudflareWorkersAIProvider()
    router : AiModels.Provider <- OpenRouter.openrouterProvider(Some{openrouterAuth})
    radius : AiModels.Provider <- Radius.radiusProvider(Radius.defaultOptions(), Radius.RadiusTransport{fetch, Runtime.urlContext()})
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    saveCredential(store, "anthropic", Auth.ApiKeyCredential{Some{"stored-key"}, None{}})
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([a, bedrock, vertex, gateway, workers, Codex.openaiCodexProvider(codexAuth), router, radius], store, context)
    auth : Resolve.Resolution() <- Models.getAuth(runtime, "anthropic", Resolve.noOverrides())
    checked(resolvedKey(auth, "stored-key"), "accepts a pi-ai CredentialStore")
    +providers : List<&2, AiModels.Provider> <- Models.getProviders(runtime)
    checked(hasMethod(AiModels.findProvider(providers, "amazon-bedrock"), Auth.ApiKeyType{}, "Amazon Bedrock", "AWS credentials or bearer token", False{}) && hasMethod(AiModels.findProvider(providers, "google-vertex"), Auth.ApiKeyType{}, "Google Vertex AI", "Google Cloud credentials", False{}) && hasMethod(AiModels.findProvider(providers, "anthropic"), Auth.OAuthType{}, "Anthropic", "Anthropic (Claude Pro/Max)", True{}) && hasMethod(AiModels.findProvider(providers, "cloudflare-ai-gateway"), Auth.ApiKeyType{}, "Cloudflare AI Gateway", "Cloudflare API key", False{}) && hasMethod(AiModels.findProvider(providers, "cloudflare-workers-ai"), Auth.ApiKeyType{}, "Cloudflare Workers AI", "Cloudflare API key", False{}) && hasMethod(AiModels.findProvider(providers, "openai-codex"), Auth.OAuthType{}, "OpenAI Codex", "OpenAI (ChatGPT Plus/Pro)", True{}) && Nat.is_eq(methodCount(AiModels.findProvider(providers, "openai-codex")), 1n), "projects provider-owned methods, names, and status")
    now : F64 <- Date.now()
    +credential : Auth.Credential = Auth.OAuthCredential{"refresh", "access", F.add(now, F.fromU32(3600000)), R.new(V.Value)}
    saveCredential(store, "anthropic", credential)
    saveCredential(store, "openrouter", credential)
    saveCredential(store, "radius", credential)
    status : Result<&2, &2, String, Maybe<&2, Auth.AuthCheck>> <- Models.checkAuth(runtime, "anthropic")
    checked(Nat.is_eq(methodCount(AiModels.findProvider(providers, "anthropic")), 2n) && oauthStatus(status), "attaches the provider's active auth status to every method option")
    anthropicSubscription : Bool <- subscription(runtime, "anthropic", True{})
    routerSubscription : Bool <- subscription(runtime, "openrouter", False{})
    radiusSubscription : Bool <- subscription(runtime, "radius", False{})
    checked(anthropicSubscription && routerSubscription && radiusSubscription, "distinguishes subscription OAuth from generic OAuth sign-in")
    Models.dispose(runtime)
    Auth.disposeStore(store)
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)

# Extension configuration and assembled request headers.
def configModel(+id: String, headers: Maybe<&2, R.Record<String>>) -> Composer.ProviderModelConfig:
  Composer.ProviderModelConfig{id, id, None{}, None{}, False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(10000), F.fromU32(1000), None{}, headers, None{}}

def configProvider(name: String, key: Maybe<&2, String>, headers: Maybe<&2, R.Record<String>>, authHeader: Bool, stream: Maybe<&2, Composer.ProviderStream()>, oauth: Maybe<&2, Auth.OAuthAuth>, modelHeaders: Maybe<&2, R.Record<String>>) -> Composer.ProviderConfigInput:
  Composer.ProviderConfigInput{Some{name}, Some{"https://example.test/v1"}, key, Some{Ai.OpenAICompletionsApi{}}, stream, headers, Some{authHeader}, Some{[configModel("extension-model", modelHeaders)]}, Maybe.map(&2, Auth.OAuthAuth, Composer.OAuthProvider, value => Composer.OAuthProvider{value, None{}}, oauth), None{}}

def registered(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: IO.die(Unit, 1, error)

def requiredModel(found: Maybe<&2, AiModels.Model()>) -> IO(AiModels.Model()):
  match found:
    case Some{value}: IO.pure(AiModels.Model(), value)
    case None{}: IO.die(AiModels.Model(), 1, "registered model missing")

# Capture the typed options that reached the registered provider.
def captureHeaders(slot: Ref.Ref<Maybe<&2, Ai.ProviderHeaders()>>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{_, _, Some{options}}:
      do IO<Composer.StreamOutput()>:
        Ref.write(Maybe<&2, Ai.ProviderHeaders()>, slot, Models.baseHeaders(Composer.requestBase(options)))
        return Fail{Tools.Failure{"captured"}}
    case _: IO.die(Composer.StreamOutput(), 1, "authorized request options missing")

def headerValue(value: Ai.Nullable<String>) -> V.Value:
  match value:
    case Ai.PresentValue{text}: V.Text{text}
    case Ai.NullValue{}: V.Null{}

def headerProperties(properties: List<&2, R.Property<Ai.Nullable<String>>>) -> List<&2, R.Property<V.Value>>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, headerValue(value)} <> headerProperties(rest)

def headerObject(headers: Ai.ProviderHeaders()) -> V.Value:
  V.ObjectValue{R.Record{headerProperties(R.entries(Ai.Nullable<String>, headers))}}

def headersEqual(headers: Maybe<&2, Ai.ProviderHeaders()>, expected: R.Record<Ai.Nullable<String>>) -> Bool:
  match headers:
    case Some{found}: V.equal(headerObject(found), headerObject(expected))
    case None{}: False{}

# A retained composed method must survive registration replacement as well.
def assembledHeaders(count: Ref.Ref<Nat>, headers: Ai.ProviderHeaders()) -> IO(Ai.ProviderHeaders()):
  do IO<Ai.ProviderHeaders()>:
    +assembled : Ai.ProviderHeaders() = headers
    Ref.modify(Nat, Unit, count, value => (value + 1n, Unit{}))
    require(headersEqual(Some{assembled}, R.Record{[R.Property{"Authorization", Ai.PresentValue{"Bearer generated-key"}}, R.Property{"x-provider", Ai.PresentValue{"provider"}}, R.Property{"x-model", Ai.PresentValue{"model"}}, R.Property{"x-explicit", Ai.PresentValue{"explicit"}}]}), "header transform received incomplete headers")
    return R.set(Ai.Nullable<String>, assembled, "x-transformed", Ai.PresentValue{"yes"})

def refreshCapture(slot: Ref.Ref<Maybe<&2, Abort.AbortSignal<Unit>>>, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refresh, access, _, extra}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        Ref.write(Maybe<&2, Abort.AbortSignal<Unit>>, slot, Some{signal})
        now : F64 <- Date.now()
        return Done{Auth.OAuthCredential{refresh, access, F.add(now, F.fromU32(60000)), extra}}
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"expected OAuth credential"})

def extensionLogin(_: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    now : F64 <- Date.now()
    return Done{Auth.OAuthCredential{"refresh", "access", F.add(now, F.fromU32(60000)), R.new(V.Value)}}

def extensionAuth(_: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"expected OAuth credential"})

def retainedSignal(found: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Abort.AbortSignal<Unit>):
  match found:
    case Some{signal}: IO.pure(Abort.AbortSignal<Unit>, signal)
    case None{}: IO.die(Abort.AbortSignal<Unit>, 1, "refresh did not receive cancellation signal")

def suppliedUnit(reason: Maybe<&2, Abort.AbortReason<Unit>>) -> Bool:
  match reason:
    case Some{Abort.Supplied{Unit{}}}: True{}
    case _: False{}

def requestEnvironment(result: Resolve.Resolution()) -> Bool:
  match result:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, headers, None{}}, _, _}}}: String.eq(key, "request-key") && headersEqual(headers, R.Record{[R.Property{"x-request-value", Ai.PresentValue{"request-header"}}]})
    case _: False{}

def requestOptions(headers: Ai.ProviderHeaders()) -> Composer.StreamOptions():
  Ai.SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{headers}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def oauthMethod(provider: Maybe<&2, AiModels.Provider>) -> IO(Auth.OAuthAuth):
  match provider:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{_, Some{method}}, _, _, _, _}}: IO.pure(Auth.OAuthAuth, method)
    case _: IO.die(Auth.OAuthAuth, 1, "registered OAuth method missing")

def derivedHeaders(result: Result<&2, &2, String, Auth.ModelAuth>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match result:
    case Done{Auth.ModelAuth{_, headers, _}}: headers
    case _: None{}

def deriveHeaders(method: Auth.OAuthAuth, credential: Auth.Credential) -> IO(Maybe<&2, Ai.ProviderHeaders()>):
  match method:
    case Auth.OAuthAuth{_, _, _, _, _, toAuth}:
      do IO<Maybe<&2, Ai.ProviderHeaders()>>:
        result : Result<&2, &2, String, Auth.ModelAuth> <- C.call(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth, credential)
        return derivedHeaders(result)

def configAuthOptions() -> IO(Unit):
  do IO<Unit>:
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    registration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "extension-api-key", configProvider("Extension API Key", Some{"$EXTENSION_TEST_API_KEY"}, None{}, False{}, None{}, None{}, None{}))
    registered(registration)
    +method : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "extension-api-key")
    checked(hasMethod(method, Auth.ApiKeyType{}, "Extension API Key", "API key", False{}) && hasKeyLogin(method), "constructs an API key method for an extension API-key provider")
    envRegistration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "request-env-provider", configProvider("Request env", Some{"$REQUEST_SCOPED_API_KEY"}, Some{R.Record{[R.Property{"x-request-value", "$REQUEST_SCOPED_HEADER"}]}}, False{}, None{}, None{}, None{}))
    registered(envRegistration)
    envAuth : Resolve.Resolution() <- Models.getAuth(runtime, "request-env-provider", Resolve.AuthResolutionOverrides{None{}, Some{R.Record{[R.Property{"REQUEST_SCOPED_API_KEY", "request-key"}, R.Property{"REQUEST_SCOPED_HEADER", "request-header"}]}}, None{}, None{}})
    checked(requestEnvironment(envAuth), "resolves configured auth from request-scoped environment overrides")
    +slot : Ref.Ref<Maybe<&2, Ai.ProviderHeaders()>> <- Ref.new(Maybe<&2, Ai.ProviderHeaders()>, None{})
    +capture : Composer.ProviderStream() <- C.create(~Ref.Ref<Maybe<&2, Ai.ProviderHeaders()>>, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~captureHeaders, slot)
    headerRegistration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "auth-header-provider", configProvider("Headers", Some{"generated-key"}, None{}, True{}, Some{capture}, None{}, None{}))
    registered(headerRegistration)
    found : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "auth-header-provider", "extension-model")
    selected : AiModels.Model() <- requiredModel(found)
    reply : Ai.AssistantMessage<V.Value, V.Value> <- Models.completeSimple(runtime, selected, Ai.Context{None{}, Nil{}, None{}}, Some{requestOptions(R.Record{[R.Property{"authorization", Ai.PresentValue{"Explicit token"}}]})}, Models.noTransforms())
    actual : Maybe<&2, Ai.ProviderHeaders()> <- Ref.read(Maybe<&2, Ai.ProviderHeaders()>, slot)
    checked(headersEqual(actual, R.Record{[R.Property{"authorization", Ai.PresentValue{"Explicit token"}}]}), "lets an explicit Authorization header override authHeader case-insensitively")
    assembledRegistration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "header-provider", configProvider("Headers", Some{"generated-key"}, Some{R.Record{[R.Property{"x-provider", "provider"}]}}, True{}, Some{capture}, None{}, Some{R.Record{[R.Property{"x-model", "model"}]}}))
    registered(assembledRegistration)
    +count : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    +transform : C.Callback<Ai.ProviderHeaders(), Ai.ProviderHeaders()> <- C.create(~Ref.Ref<Nat>, ~Ai.ProviderHeaders(), ~Ai.ProviderHeaders(), ~assembledHeaders, count)
    assembledFound : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "header-provider", "extension-model")
    assembledModel : AiModels.Model() <- requiredModel(assembledFound)
    transformedReply : Ai.AssistantMessage<V.Value, V.Value> <- Models.completeSimple(runtime, assembledModel, Ai.Context{None{}, Nil{}, None{}}, Some{requestOptions(R.Record{[R.Property{"x-explicit", Ai.PresentValue{"explicit"}}]})}, Models.RequestTransforms{Some{transform}, None{}})
    calls : Nat <- Ref.read(Nat, count)
    transformedHeaders : Maybe<&2, Ai.ProviderHeaders()> <- Ref.read(Maybe<&2, Ai.ProviderHeaders()>, slot)
    checked(Nat.is_eq(calls, 1n) && headersEqual(transformedHeaders, R.Record{[R.Property{"Authorization", Ai.PresentValue{"Bearer generated-key"}}, R.Property{"x-provider", Ai.PresentValue{"provider"}}, R.Property{"x-model", Ai.PresentValue{"model"}}, R.Property{"x-explicit", Ai.PresentValue{"explicit"}}, R.Property{"x-transformed", Ai.PresentValue{"yes"}}]}), "transforms fully assembled headers once without forwarding the transform")
    +signalSlot : Ref.Ref<Maybe<&2, Abort.AbortSignal<Unit>>> <- Ref.new(Maybe<&2, Abort.AbortSignal<Unit>>, None{})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~extensionLogin, Unit{})
    refresh : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Ref.Ref<Maybe<&2, Abort.AbortSignal<Unit>>>, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refreshCapture, signalSlot)
    derive : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~extensionAuth, Unit{})
    +oauth : Auth.OAuthAuth = Auth.OAuthAuth{"Extension subscription", True{}, None{}, login, refresh, derive}
    oauthRegistration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "extension-oauth", configProvider("Extension OAuth", None{}, Some{R.Record{[R.Property{"x-generation", "old"}]}}, False{}, None{}, Some{oauth}, None{}))
    registered(oauthRegistration)
    saveCredential(store, "extension-oauth", Auth.OAuthCredential{"refresh", "expired", F.fromU32(0), R.new(V.Value)})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    auth : Resolve.Resolution() <- Models.getAuth(runtime, "extension-oauth", Resolve.AuthResolutionOverrides{None{}, None{}, None{}, Some{Abort.signal(Unit, controller)}})
    require(resolvedKey(auth, "expired"), "extension refresh did not resolve its credential")
    capturedSignal : Maybe<&2, Abort.AbortSignal<Unit>> <- Ref.read(Maybe<&2, Abort.AbortSignal<Unit>>, signalSlot)
    +signal : Abort.AbortSignal<Unit> <- retainedSignal(capturedSignal)
    before : Bool <- Abort.aborted(Unit, signal)
    cancelled : Bool <- Abort.abort(Unit, controller, Some{Unit{}})
    after : Bool <- Abort.aborted(Unit, signal)
    reason : Maybe<&2, Abort.AbortReason<Unit>> <- Abort.reason(Unit, signal)
    checked(Bool.not(before) && cancelled && after && suppliedUnit(reason), "forwards cancellation to extension OAuth refresh")
    +oauthProvider : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "extension-oauth")
    checked(Nat.is_eq(methodCount(oauthProvider), 1n) && hasMethod(oauthProvider, Auth.OAuthType{}, "Extension OAuth", "Extension subscription", True{}), "does not fabricate an API key method for an extension OAuth-only provider")
    retained : Auth.OAuthAuth <- oauthMethod(oauthProvider)
    replacement : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "extension-oauth", configProvider("Extension OAuth", None{}, Some{R.Record{[R.Property{"x-generation", "new"}]}}, False{}, None{}, Some{oauth}, None{}))
    registered(replacement)
    currentProvider : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "extension-oauth")
    current : Auth.OAuthAuth <- oauthMethod(currentProvider)
    +credential : Auth.Credential = Auth.OAuthCredential{"refresh", "access", F.fromU32(0), R.new(V.Value)}
    oldHeaders : Maybe<&2, Ai.ProviderHeaders()> <- deriveHeaders(retained, credential)
    newHeaders : Maybe<&2, Ai.ProviderHeaders()> <- deriveHeaders(current, credential)
    require(headersEqual(oldHeaders, R.Record{[R.Property{"x-generation", Ai.PresentValue{"old"}}]}) && headersEqual(newHeaders, R.Record{[R.Property{"x-generation", Ai.PresentValue{"new"}}]}), "provider replacement invalidated a retained method or its header snapshot")
    Models.dispose(runtime)
    Auth.disposeOAuthAuth(oauth)
    Auth.disposeStore(store)
    Abort.dispose(Unit, controller)
    C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), capture)
    C.dispose(Ai.ProviderHeaders(), Ai.ProviderHeaders(), transform)
    discardedHeaders : Maybe<&2, Ai.ProviderHeaders()> <- Ref.dispose(Maybe<&2, Ai.ProviderHeaders()>, slot)
    discardedCount : Nat <- Ref.dispose(Nat, count)
    discardedSignal : Maybe<&2, Abort.AbortSignal<Unit>> <- Ref.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, signalSlot)
    return Unit{}

# Gates exercise asynchronous boundaries without timing-dependent sleeps.
def blockedLogin(gate: RefreshGate, _: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match gate:
    case RefreshGate{started, release}:
      do IO<Auth.LoginOutcome()>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        resumed : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Done{Auth.ApiKeyCredential{Some{"login-key"}, None{}}}

def storedAuth(_: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{_, Some{Auth.ApiKeyCredential{key, env}}, _}:
      IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{key, None{}, None{}}, env, Some{"stored"}}}})
    case _: IO.pure(Auth.AuthOutcome(), Done{None{}})

def loginProvider(+id: String, gate: RefreshGate) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~RefreshGate, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~blockedLogin, gate)
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~storedAuth, Unit{})
    return AiModels.Provider{id, id, "https://faux.invalid", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"API key", Some{login}, resolve, None{}}}, None{}}, [model(id)], AiModels.ApiStreams{}, None{}, None{}}

def concurrentCredentials() -> IO(Unit):
  do IO<Unit>:
    +startedA : Chan(Unit) <- Chan.new(Unit, 1)
    +releaseA : Chan(Unit) <- Chan.new(Unit, 1)
    +startedB : Chan(Unit) <- Chan.new(Unit, 1)
    +releaseB : Chan(Unit) <- Chan.new(Unit, 1)
    a : AiModels.Provider <- loginProvider("a", RefreshGate{startedA, releaseA})
    b : AiModels.Provider <- loginProvider("b", RefreshGate{startedB, releaseB})
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([a, b], store, context)
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    +interaction : Auth.AuthInteraction = Auth.AuthInteraction{None{}, prompt, notify}
    first : Chan(Models.LoginOutcome()) <- IO.fork(Models.LoginOutcome(), Models.login(runtime, "a", Auth.ApiKeyType{}, interaction))
    beganA : Maybe<&1, Unit> <- Chan.recv(Unit, startedA)
    logout : Chan(Models.CredentialOutcome(Unit)) <- IO.fork(Models.CredentialOutcome(Unit), Models.logout(runtime, "a", None{}))
    second : Chan(Models.LoginOutcome()) <- IO.fork(Models.LoginOutcome(), Models.login(runtime, "b", Auth.ApiKeyType{}, interaction))
    beganB : Maybe<&1, Unit> <- Chan.recv(Unit, startedB)
    releasedB : Bool <- Chan.send(Unit, releaseB, Unit{})
    resultB : Models.LoginOutcome() <- IO.join(Models.LoginOutcome(), second)
    storedB : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "b", None{})
    configuredB : Bool <- Models.hasConfiguredAuth(runtime, "b")
    availableB : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(keyIs(storedB, "login-key") && configuredB && Nat.is_eq(List.length(&2, AiModels.Model(), availableB), 1n), "login resolved before credential, configuration and availability agreed")
    checked(loginSucceeded(resultB), "allows different providers to run credential flows concurrently")
    releasedA : Bool <- Chan.send(Unit, releaseA, Unit{})
    resultA : Models.LoginOutcome() <- IO.join(Models.LoginOutcome(), first)
    removed : Models.CredentialOutcome(Unit) <- IO.join(Models.CredentialOutcome(Unit), logout)
    credential : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "a", None{})
    configured : Bool <- Models.hasConfiguredAuth(runtime, "a")
    availableAfterLogout : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    checked(loginSucceeded(resultA) && loggedOut(removed) && noCredential(credential) && Bool.not(configured), "orders same-provider credential operations through local synchronization")
    checked(Nat.is_eq(List.length(&2, AiModels.Model(), availableAfterLogout), 1n), "publishes locally consistent availability before login and logout resolve")
    Models.dispose(runtime)
    Auth.disposeStore(store)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)

# Block cache restoration only after construction has completed.
type CacheGate is Data:
  CacheGate{enabled: Ref.Ref<Bool>, gate: RefreshGate}

def enableCache(_: Bool) -> Bool & Unit: (True{}, Unit{})

def waitCache(enabled: Bool, gate: RefreshGate) -> IO(Result<&2, &2, String, Unit>):
  match enabled gate:
    case False{} _: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case True{} RefreshGate{started, release}:
      do IO<Result<&2, &2, String, Unit>>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        resumed : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Done{Unit{}}

def blockedCache(state: CacheGate, request: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match state request:
    case CacheGate{enabled, gate} AiModels.RefreshModelsContext{_, _, _, False{}, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        active : Bool <- Ref.read(Bool, enabled)
        waitCache(active, gate)
    case _ _: IO.die(Result<&2, &2, String, Unit>, 1, "credential synchronization used network refresh")

def committedLogin(result: Models.LoginOutcome()) -> Bool:
  match result:
    case Fail{Models.CredentialSynchronizationError{id, Models.LoginOperation{}, Some{Auth.ApiKeyCredential{Some{key}, _}}, _}}:
      String.eq(id, "dynamic") && String.eq(key, "login-key")
    case _: False{}

def cancelledSynchronization() -> IO(Unit):
  do IO<Unit>:
    +enabled : Ref.Ref<Bool> <- Ref.new(Bool, False{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    refresh : AiModels.RefreshModels() <- C.create(~CacheGate, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~blockedCache, CacheGate{enabled, RefreshGate{started, release}})
    dynamic : AiModels.Provider <- gatedProvider(refresh)
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([dynamic], store, context)
    Ref.modify(Bool, Unit, enabled, enableCache)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    login : Chan(Models.LoginOutcome()) <- IO.fork(Models.LoginOutcome(), Models.login(runtime, "dynamic", Auth.ApiKeyType{}, Auth.AuthInteraction{Some{Abort.signal(Unit, controller)}, prompt, notify}))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    stopped : Bool <- Abort.abort(Unit, controller, Some{Unit{}})
    result : Models.LoginOutcome() <- IO.join(Models.LoginOutcome(), login)
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    checked(committedLogin(result) && keyIs(stored, "login-key"), "reports a typed error when cancellation interrupts post-commit synchronization")
    released : Bool <- Chan.send(Unit, release, Unit{})
    Models.dispose(runtime)
    Auth.disposeStore(store)
    Abort.dispose(Unit, controller)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)
    previous : Bool <- Ref.dispose(Bool, enabled)
    return Unit{}

def checkedAvailability(state: CacheGate, request: Auth.ResolveInput) -> IO(Auth.CheckOutcome()):
  match state:
    case CacheGate{enabled, gate}:
      do IO<Auth.CheckOutcome()>:
        active : Bool <- Ref.read(Bool, enabled)
        waited : Result<&2, &2, String, Unit> <- waitCache(active, gate)
        return Done{Some{Auth.AuthCheck{Some{"stored"}, Auth.ApiKeyType{}}}}

def availabilityProvider(+id: String, state: CacheGate) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~gateLogin, Unit{})
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~ambientGateAuth, Unit{})
    check : C.Callback<Auth.ResolveInput, Auth.CheckOutcome()> <- C.create(~CacheGate, ~Auth.ResolveInput, ~Auth.CheckOutcome(), ~checkedAvailability, state)
    return AiModels.Provider{id, id, "https://faux.invalid", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"API key", Some{login}, resolve, Some{check}}}, None{}}, [model(id)], AiModels.ApiStreams{}, None{}, None{}}

def refreshAborted(result: Models.ModelsRefreshResult) -> Bool:
  match result:
    case Models.ModelsRefreshResult{aborted, _}: aborted

def scopedAvailabilityCancellation() -> IO(Unit):
  do IO<Unit>:
    +enabled : Ref.Ref<Bool> <- Ref.new(Bool, False{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    unrelated : AiModels.Provider <- availabilityProvider("unrelated", CacheGate{enabled, RefreshGate{started, release}})
    target : AiModels.Provider <- provider("target")
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([unrelated, target], store, context)
    Ref.modify(Bool, Unit, enabled, enableCache)
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    login : Models.LoginOutcome() <- Models.login(runtime, "target", Auth.ApiKeyType{}, Auth.AuthInteraction{None{}, prompt, notify})
    refreshed : Models.ModelsRefreshResult <- Models.refresh(runtime, Models.ModelsRefreshOptions{Some{False{}}, Some{["target"]}, None{}, None{}})
    configured : Bool <- Models.hasConfiguredAuth(runtime, "target")
    checked(loginSucceeded(login) && configured && Bool.not(refreshAborted(refreshed)), "does not wait for unrelated provider availability during local synchronization")
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    pending : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult, Models.refresh(runtime, Models.ModelsRefreshOptions{Some{False{}}, Some{["unrelated"]}, None{}, Some{Abort.signal(Unit, controller)}}))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    stopped : Bool <- Abort.abort(Unit, controller, Some{Unit{}})
    result : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult, pending)
    checked(refreshAborted(result), "reports cancellation that occurs during provider-scoped availability")
    released : Bool <- Chan.send(Unit, release, Unit{})
    Models.dispose(runtime)
    Auth.disposeStore(store)
    Abort.dispose(Unit, controller)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)
    previous : Bool <- Ref.dispose(Bool, enabled)
    return Unit{}

type NetworkGate is Data:
  NetworkGate{gate: RefreshGate, signal: Ref.Ref<Maybe<&2, Abort.AbortSignal<Unit>>>}

def retainNetworkSignal(signal: Abort.AbortSignal<Unit>, _: Maybe<&2, Abort.AbortSignal<Unit>>) -> Maybe<&2, Abort.AbortSignal<Unit>> & Unit:
  (Some{signal}, Unit{})

def blockedNetwork(state: NetworkGate, request: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match state request:
    case NetworkGate{gate, slot} AiModels.RefreshModelsContext{_, _, _, True{}, _, signal}:
      do IO<Result<&2, &2, String, Unit>>:
        Ref.modify(Maybe<&2, Abort.AbortSignal<Unit>>, Unit, slot, current => retainNetworkSignal(signal, current))
        waitCache(True{}, gate)
    case _ _: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

def independentRefreshes() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +slot : Ref.Ref<Maybe<&2, Abort.AbortSignal<Unit>>> <- Ref.new(Maybe<&2, Abort.AbortSignal<Unit>>, None{})
    refresh : AiModels.RefreshModels() <- C.create(~NetworkGate, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~blockedNetwork, NetworkGate{RefreshGate{started, release}, slot})
    one : AiModels.Provider <- providerWithRefresh("one", Some{refresh})
    two : AiModels.Provider <- provider("two")
    +store : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([one, two], store, context)
    keyOne : Models.CredentialOutcome(Unit) <- Models.setRuntimeApiKey(runtime, "one", "one-key", None{})
    keyTwo : Models.CredentialOutcome(Unit) <- Models.setRuntimeApiKey(runtime, "two", "two-key", None{})
    pending : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult, Models.refresh(runtime, Models.ModelsRefreshOptions{Some{True{}}, Some{["one"]}, None{}, None{}}))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : Models.ModelsRefreshResult <- Models.refresh(runtime, Models.ModelsRefreshOptions{Some{True{}}, Some{["two"]}, None{}, None{}})
    captured : Maybe<&2, Abort.AbortSignal<Unit>> <- Ref.read(Maybe<&2, Abort.AbortSignal<Unit>>, slot)
    signal : Abort.AbortSignal<Unit> <- retainedSignal(captured)
    aborted : Bool <- Abort.aborted(Unit, signal)
    checked(loggedOut(keyOne) && loggedOut(keyTwo) && Bool.not(refreshAborted(second)) && Bool.not(aborted), "keeps provider-scoped refreshes from superseding unrelated providers")
    released : Bool <- Chan.send(Unit, release, Unit{})
    first : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult, pending)
    require(Bool.not(refreshAborted(first)), "independent provider refresh was aborted")
    Models.dispose(runtime)
    Auth.disposeStore(store)
    previous : Maybe<&2, Abort.AbortSignal<Unit>> <- Ref.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, slot)
    return Unit{}
type DelayedStore is Data:
  DelayedStore{value: Ref.Ref<Maybe<&2, Auth.Credential>>, gate: RefreshGate}

def delayedRead(state: DelayedStore, _: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match state:
    case DelayedStore{value, _}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        credential : Maybe<&2, Auth.Credential> <- Ref.read(Maybe<&2, Auth.Credential>, value)
        return Done{credential}

def replaceCredential(credential: Maybe<&2, Auth.Credential>, _: Maybe<&2, Auth.Credential>) -> Maybe<&2, Auth.Credential> & Unit:
  (credential, Unit{})

def delayedCommit(state: DelayedStore, result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match state result:
    case _ Fail{reason}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Fail{reason})
    case DelayedStore{value, gate} Done{+credential}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        Ref.modify(Maybe<&2, Auth.Credential>, Unit, value, previous => replaceCredential(credential, previous))
        waited : Result<&2, &2, String, Unit> <- waitCache(True{}, gate)
        return Done{credential}

def delayedModify(state: DelayedStore, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match state request:
    case DelayedStore{+value, gate} Auth.Modify{_, update, _}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        current : Maybe<&2, Auth.Credential> <- Ref.read(Maybe<&2, Auth.Credential>, value)
        result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- C.call(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update, current)
        delayedCommit(DelayedStore{value, gate}, result)

def delayedDelete(state: DelayedStore, _: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match state:
    case DelayedStore{value, _}:
      do IO<Auth.StoreResult(Unit)>:
        Ref.modify(Maybe<&2, Auth.Credential>, Unit, value, previous => replaceCredential(None{}, previous))
        return Done{Unit{}}

def delayedStore(+state: DelayedStore) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~DelayedStore, ~Auth.Request, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~delayedRead, state)
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~DelayedStore, ~Auth.Modify, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~delayedModify, state)
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~DelayedStore, ~Auth.Request, ~Auth.StoreResult(Unit), ~delayedDelete, state)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Unit, ~Auth.Signal(), ~Auth.StoreResult(List<&2, Auth.CredentialInfo>), ~listStore, Unit{})
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def settledLogin(settled: Ref.Ref<Bool>, task: IO(Models.LoginOutcome())) -> IO(Models.LoginOutcome()):
  do IO<Models.LoginOutcome()>:
    result : Models.LoginOutcome() <- task
    Ref.modify(Bool, Unit, settled, enableCache)
    return result

def cancellationAfterCommit() -> IO(Unit):
  do IO<Unit>:
    +value : Ref.Ref<Maybe<&2, Auth.Credential>> <- Ref.new(Maybe<&2, Auth.Credential>, None{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +store : Auth.CredentialStore <- delayedStore(DelayedStore{value, RefreshGate{started, release}})
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    dynamic : AiModels.Provider <- provider("dynamic")
    +runtime : Models.ModelRuntime <- Models.fromProviders([dynamic], store, context)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +settled : Ref.Ref<Bool> <- Ref.new(Bool, False{})
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    login : Chan(Models.LoginOutcome()) <- IO.fork(Models.LoginOutcome(), settledLogin(settled, Models.login(runtime, "dynamic", Auth.ApiKeyType{}, Auth.AuthInteraction{Some{Abort.signal(Unit, controller)}, prompt, notify})))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    stopped : Bool <- Abort.abort(Unit, controller, Some{Unit{}})
    IO.sleep(10)
    premature : Bool <- Ref.read(Bool, settled)
    require(Bool.not(premature), "cancelled login settled while committed store mutation was unfinished")
    released : Bool <- Chan.send(Unit, release, Unit{})
    result : Models.LoginOutcome() <- IO.join(Models.LoginOutcome(), login)
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "dynamic", None{})
    checked(committedLogin(result) && keyIs(stored, "login-key"), "waits for a committed credential mutation to settle before reporting cancellation")
    Models.dispose(runtime)
    Auth.disposeStore(store)
    Abort.dispose(Unit, controller)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)
    previous : Maybe<&2, Auth.Credential> <- Ref.dispose(Maybe<&2, Auth.Credential>, value)
    wasSettled : Bool <- Ref.dispose(Bool, settled)
    return Unit{}

# Resolved request-auth contracts from model-registry.test.ts.
def absentAuth(_: Unit, _: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{None{}})

def failedRequestAuth(_: Unit, _: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Fail{"Failed to resolve API key for provider \"failed-request\""})

def requestFailed(result: Models.RequestAuthResult(), expected: String) -> Bool:
  match result:
    case Fail{reason}: String.eq(reason, expected)
    case Done{_}: False{}

def requestHeaders(result: Models.RequestAuthResult(), expected: Ai.ProviderHeaders()) -> Bool:
  match result:
    case Done{Models.ResolvedRequestAuth{None{}, headers, None{}, None{}}}: headersEqual(headers, expected)
    case _: False{}

def requestAuthContracts() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    absent : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~absentAuth, Unit{})
    failed : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~failedRequestAuth, Unit{})
    +runtime : Models.ModelRuntime <- Models.fromProviders([AiModels.Provider{"missing-request", "Missing request", "https://example.test/v1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"API key", None{}, absent, None{}}}, None{}}, [model("missing-request")], AiModels.ApiStreams{}, None{}, None{}}, AiModels.Provider{"failed-request", "Failed request", "https://example.test/v1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"API key", None{}, failed, None{}}}, None{}}, [model("failed-request")], AiModels.ApiStreams{}, None{}, None{}}], credentials, context)
    noKey : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "missing-request", configProvider("Missing request", None{}, Some{R.Record{[R.Property{"x-configured", "yes"}]}}, False{}, None{}, None{}, None{}))
    registered(noKey)
    found : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "missing-request", "extension-model")
    +selected : AiModels.Model() <- requiredModel(found)
    fallback : Models.RequestAuthResult() <- Models.getApiKeyAndHeaders(runtime, selected)
    checked(requestHeaders(fallback, R.Record{[R.Property{"x-configured", Ai.PresentValue{"yes"}}]}), "preserves configured headers without a resolved API key")
    requiringKey : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "missing-request", Composer.ProviderConfigInput{None{}, None{}, None{}, None{}, None{}, None{}, Some{True{}}, None{}, None{}, None{}})
    registered(requiringKey)
    missing : Models.RequestAuthResult() <- Models.getApiKeyAndHeaders(runtime, selected)
    checked(requestFailed(missing, "No API key found for \"missing-request\""), "getApiKeyAndHeaders preserves the legacy missing-key authHeader error")
    rejected : Models.RequestAuthResult() <- Models.getApiKeyAndHeaders(runtime, model("failed-request"))
    checked(requestFailed(rejected, "Failed to resolve API key for provider \"failed-request\""), "getApiKeyAndHeaders returns an error for failed authHeader resolution")
    Models.dispose(runtime)
    Auth.disposeStore(credentials)

# Provider model-lifecycle contracts from model-runtime-modify-models-compat.
def liveModels(_: Unit, _: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, List<&2, Composer.ProviderModelConfig>>):
  IO.pure(Result<&2, &2, String, List<&2, Composer.ProviderModelConfig>>, Done{[configModel("live", None{})]})

def credentialModels(_: Unit, input: Composer.OAuthModelsInput) -> IO(Result<&2, &2, String, List<&2, AiModels.Model()>>):
  match input:
    case Composer.OAuthModelsInput{+models, Auth.OAuthCredential{_, access, _, _}}:
      IO.pure(Result<&2, &2, String, List<&2, AiModels.Model()>>, Done{Bool.pick(List<&2, AiModels.Model()>, String.eq(access, "access"), List.append(&2, AiModels.Model(), models, [Composer.extensionModel("extension-oauth", configModel("credential-model", None{}), Ai.OpenAICompletionsApi{}, "https://example.test/v1")]), models)})
    case Composer.OAuthModelsInput{models, _}: IO.pure(Result<&2, &2, String, List<&2, AiModels.Model()>>, Done{models})

def stableCredential(_: Unit, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{credential, _}: IO.pure(Result<&2, &2, String, Auth.Credential>, Done{credential})

def unstored(result: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)) -> Bool:
  match result:
    case Done{None{}}: True{}
    case _: False{}

def configModelLifecycle() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProvidersWithStore(Nil{}, credentials, context, store)
    +refresh : Composer.ModelRefresh() <- C.create(~Unit, ~AiModels.RefreshModelsContext, ~(Result<&2, &2, String, List<&2, Composer.ProviderModelConfig>>), ~liveModels, Unit{})
    registration : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "extension-dynamic", Composer.ProviderConfigInput{None{}, Some{"http://localhost:8080/v1"}, Some{"local"}, Some{Ai.OpenAICompletionsApi{}}, None{}, None{}, None{}, None{}, None{}, Some{refresh}})
    registered(registration)
    refreshed : Models.ModelsRefreshResult <- Models.refresh(runtime, Models.ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}})
    live : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-dynamic", "live")
    persisted : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "extension-dynamic", None{})
    checked(Maybe.is_some(&2, AiModels.Model(), live) && unstored(persisted), "publishes refreshModels results without forcing ModelsStore persistence")
    now : F64 <- Date.now()
    saveCredential(credentials, "extension-oauth", Auth.OAuthCredential{"refresh", "access", F.add(now, F.fromU32(60000)), R.new(V.Value)})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~extensionLogin, Unit{})
    tokenRefresh : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Unit, ~Auth.RefreshInput, ~(Result<&2, &2, String, Auth.Credential>), ~stableCredential, Unit{})
    derive : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~(Result<&2, &2, String, Auth.ModelAuth>), ~extensionAuth, Unit{})
    +oauth : Auth.OAuthAuth = Auth.OAuthAuth{"Extension OAuth", False{}, None{}, login, tokenRefresh, derive}
    +modify : C.Callback<Composer.OAuthModelsInput, Result<&2, &2, String, List<&2, AiModels.Model()>>> <- C.create(~Unit, ~Composer.OAuthModelsInput, ~(Result<&2, &2, String, List<&2, AiModels.Model()>>), ~credentialModels, Unit{})
    configured : Result<&2, &2, String, Unit> <- Models.registerProvider(runtime, "extension-oauth", Composer.ProviderConfigInput{None{}, Some{"https://example.test/v1"}, None{}, Some{Ai.OpenAICompletionsApi{}}, None{}, None{}, None{}, Some{[configModel("base", None{})]}, Some{Composer.OAuthProvider{oauth, Some{modify}}}, None{}})
    registered(configured)
    initialized : Models.ModelsRefreshResult <- Models.refresh(runtime, Models.ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}})
    base : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-oauth", "base")
    before : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-oauth", "credential-model")
    loggedOut : Models.CredentialOutcome(Unit) <- Models.logout(runtime, "extension-oauth", None{})
    after : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-oauth", "credential-model")
    checked(Maybe.is_some(&2, AiModels.Model(), base) && Maybe.is_some(&2, AiModels.Model(), before) && Maybe.is_none(&2, AiModels.Model(), after), "applies legacy OAuth modifyModels after async credential initialization")
    Models.dispose(runtime)
    Auth.disposeStore(credentials)
    Auth.disposeOAuthAuth(oauth)
    C.dispose(Composer.OAuthModelsInput, Result<&2, &2, String, List<&2, AiModels.Model()>>, modify)
    C.dispose(AiModels.RefreshModelsContext, Result<&2, &2, String, List<&2, Composer.ProviderModelConfig>>, refresh)

def nativeAuth(_: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{_, Some{Auth.ApiKeyCredential{Some{key}, _}}, _}:
      IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, Some{"https://resolved.test/v1"}}, None{}, Some{"stored native key"}}}})
    case _: IO.pure(Auth.AuthOutcome(), Done{None{}})

def nativeCheck(_: Unit, input: Auth.ResolveInput) -> IO(Auth.CheckOutcome()):
  match input:
    case Auth.ResolveInput{_, Some{Auth.ApiKeyCredential{Some{_}, _}}, _}: IO.pure(Auth.CheckOutcome(), Done{Some{Auth.AuthCheck{Some{"stored native key"}, Auth.ApiKeyType{}}}})
    case _: IO.pure(Auth.CheckOutcome(), Done{None{}})

def providerResolver(found: Maybe<&2, AiModels.Provider>, resolver: C.Callback<Auth.ResolveInput, Auth.AuthOutcome()>) -> Bool:
  match found:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, _, method, _}}, _}, _, _, _, _}}: C.same(Auth.ResolveInput, Auth.AuthOutcome(), method, resolver)
    case _: False{}

def nativeRegistration() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders(Nil{}, credentials, context)
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Helpers.EnvApiKey, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~Helpers.loginEnv, Helpers.EnvApiKey{"API key", Nil{}})
    +resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~nativeAuth, Unit{})
    check : C.Callback<Auth.ResolveInput, Auth.CheckOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.CheckOutcome(), ~nativeCheck, Unit{})
    +provider : AiModels.Provider = AiModels.Provider{"extension-native", "Extension Native", "https://fallback.test/v1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Native setup", Some{login}, resolve, Some{check}}}, None{}}, [Composer.extensionModel("extension-native", configModel("native", None{}), Ai.OpenAICompletionsApi{}, "https://fallback.test/v1")], AiModels.ApiStreams{}, None{}, None{}}
    registration : Result<&2, &2, String, Unit> <- Models.registerNativeProvider(runtime, provider)
    registered(registration)
    composed : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "extension-native")
    source : Maybe<&2, AiModels.Provider> <- Models.getRegisteredNativeProvider(runtime, "extension-native")
    ids : List<&2, String> <- Models.getRegisteredProviderIds(runtime)
    found : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-native", "native")
    +prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~(Result<&2, &2, String, String>), ~loginPrompt, Unit{})
    +notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~loginNotice, Unit{})
    loggedIn : Models.LoginOutcome() <- Models.login(runtime, "extension-native", Auth.ApiKeyType{}, Auth.AuthInteraction{None{}, prompt, notify})
    +auth : Resolve.Resolution() <- Models.getAuth(runtime, "extension-native", Resolve.noOverrides())
    resolved : String = Composer.modelBaseUrl(Models.preparedModel(auth, model("extension-native")))
    Models.unregisterProvider(runtime, "extension-native")
    removed : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "extension-native")
    checked(providerResolver(composed, resolve) && providerResolver(source, resolve) && Models.containsId(ids, "extension-native") && Maybe.is_some(&2, AiModels.Model(), found) && loginSucceeded(loggedIn) && resolvedKey(auth, "login-key") && String.eq(resolved, "https://resolved.test/v1") && Maybe.is_none(&2, AiModels.Provider, removed), "registers native pi-ai providers with their auth implementation")
    Models.dispose(runtime)
    AiModels.disposeProvider(provider)
    Auth.disposeStore(credentials)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt)
    C.dispose(Auth.AuthEvent, Unit, notify)

def deferredTransform(tag: String, headers: Ai.ProviderHeaders()) -> IO(Ai.ProviderHeaders()):
  IO.pure(Ai.ProviderHeaders(), R.set(Ai.Nullable<String>, headers, "X-Transformed", Ai.PresentValue{tag}))

def releaseDeferred(events: LifecycleEvents.AssistantMessageEventStream(V.Value, V.Value)) -> IO(AiModels.DeferredCancelResult()):
  do IO<AiModels.DeferredCancelResult()>:
    LifecycleEvents.disposeAssistantMessageEventStream(V.Value, V.Value, events)
    return Done{Unit{}}

def deferredMessage(model: AiModels.Model()) -> Ai.AssistantMessage<V.Value, V.Value>:
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      Ai.AssistantMessage{Nil{}, "openai-completions", provider, id, None{}, None{}, None{}, None{}, Ai.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, Ai.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}

def captureDeferredFetch(slot: Ref.Ref<Maybe<&2, AiModels.DeferredFetchInput>>, input: AiModels.DeferredFetchInput) -> IO(AiModels.DeferredFetchResult()):
  match input:
    case AiModels.DeferredFetchInput{+model, handle, options}:
      do IO<AiModels.DeferredFetchResult()>:
        Ref.write(Maybe<&2, AiModels.DeferredFetchInput>, slot, Some{AiModels.DeferredFetchInput{model, handle, options}})
        +events : LifecycleEvents.AssistantMessageEventStream(V.Value, V.Value) <- LifecycleEvents.createAssistantMessageEventStream(~V.Value, ~V.Value)
        +message : Ai.AssistantMessage<V.Value, V.Value> = deferredMessage(model)
        LifecycleEvents.push(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Ai.Start{message})
        LifecycleEvents.push(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Ai.StreamDone{Ai.DoneStop{}, message})
        LifecycleEvents.end(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Some{message})
        return Done{AiModels.DeferredStream{events, releaseDeferred(events)}}

def captureDeferredCancel(slot: Ref.Ref<Maybe<&2, AiModels.DeferredCancelInput>>, input: AiModels.DeferredCancelInput) -> IO(AiModels.DeferredCancelResult()):
  do IO<AiModels.DeferredCancelResult()>:
    Ref.write(Maybe<&2, AiModels.DeferredCancelInput>, slot, Some{input})
    return Done{Unit{}}

def fetchedCorrect(input: Maybe<&2, AiModels.DeferredFetchInput>) -> Bool:
  match input:
    case Some{AiModels.DeferredFetchInput{model, _, Some{Ai.DeferredFetchOptions{Ai.ProviderRequestOptions{_, _, Some{key}, _, _, _, _, headers, _, _, _}, Some{wait}}}}}:
      String.eq(Composer.modelBaseUrl(model), "https://overlay.test/v1") && String.eq(key, "key") && F64.is_eq(wait, F.fromU32(25)) && headersEqual(headers, R.Record{[R.Property{"X-Fetch", Ai.PresentValue{"fetch"}}, R.Property{"X-Transformed", Ai.PresentValue{"fetch"}}]})
    case _: False{}

def cancelledCorrect(input: Maybe<&2, AiModels.DeferredCancelInput>) -> Bool:
  match input:
    case Some{AiModels.DeferredCancelInput{_, Ai.DeferredHandle{_, _, _, id, _, _, _}, Some{Ai.ProviderRequestOptions{_, _, Some{key}, _, _, _, _, headers, Some{timeout}, _, _}}}}:
      String.eq(id, "cancel-id") && String.eq(key, "key") && F64.is_eq(timeout, F.fromU32(100)) && headersEqual(headers, R.Record{[R.Property{"X-Transformed", Ai.PresentValue{"cancel"}}]})
    case _: False{}

def successfulDeferredReply(message: Ai.AssistantMessage<V.Value, V.Value>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, id, _, _, _, _, _, Ai.Stop{}, _, _, _, _, _}: String.eq(id, "native-deferred")
    case _: False{}

def windowIs(model: AiModels.Model(), value: F64) -> Bool:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, window, _, _, _, _}: F64.is_eq(window, value)

# The caller supplies a models.json with both native overlays, just as upstream.
def nativeModelLifecycle(path: String) -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- MemoryCredentials.inMemoryCredentialStore()
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    +fetch : Fetch.Fetch(Unit) <- C.create(~Unit, ~(Fetch.Input<Unit>), ~(Fetch.Result_(Unit)), ~networkForbidden, Unit{})
    +runtime : Models.ModelRuntime <- Models.createWithProviders(credentials, Nil{}, Some{path}, Radius.RadiusTransport{fetch, Runtime.urlContext()}, Models.CreateModelRuntimeOptions{Some{store}, None{}, False{}, None{}, None{}, False{}})
    +keyAuth : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Native key", Nil{})
    # Explicit stored native key keeps this fixture independent of environment.
    saveCredential(credentials, "extension-native-deferred", Auth.ApiKeyCredential{Some{"key"}, None{}})
    saveCredential(credentials, "extension-native", Auth.ApiKeyCredential{Some{"key"}, None{}})
    +fetchSlot : Ref.Ref<Maybe<&2, AiModels.DeferredFetchInput>> <- Ref.new(Maybe<&2, AiModels.DeferredFetchInput>, None{})
    +cancelSlot : Ref.Ref<Maybe<&2, AiModels.DeferredCancelInput>> <- Ref.new(Maybe<&2, AiModels.DeferredCancelInput>, None{})
    +fetchDeferred : AiModels.FetchDeferred() <- C.create(~Ref.Ref<Maybe<&2, AiModels.DeferredFetchInput>>, ~AiModels.DeferredFetchInput, ~(AiModels.DeferredFetchResult()), ~captureDeferredFetch, fetchSlot)
    +cancelDeferred : AiModels.CancelDeferred() <- C.create(~Ref.Ref<Maybe<&2, AiModels.DeferredCancelInput>>, ~AiModels.DeferredCancelInput, ~(AiModels.DeferredCancelResult()), ~captureDeferredCancel, cancelSlot)
    deferredRegistration : Result<&2, &2, String, Unit> <- Models.registerNativeProvider(runtime, AiModels.Provider{"extension-native-deferred", "Extension Native Deferred", "https://native.test/v1", Auth.ProviderAuth{Some{keyAuth}, None{}}, [Composer.extensionModel("extension-native-deferred", configModel("native-deferred", None{}), Ai.OpenAICompletionsApi{}, "https://native.test/v1")], AiModels.DeferredStreams{AiModels.ApiStreams{}, Some{fetchDeferred}, Some{cancelDeferred}}, None{}, None{}})
    nativeRegistration : Result<&2, &2, String, Unit> <- Models.registerNativeProvider(runtime, AiModels.Provider{"extension-native", "Extension Native", "https://native.test/v1", Auth.ProviderAuth{Some{keyAuth}, None{}}, [Composer.extensionModel("extension-native", configModel("native", None{}), Ai.OpenAICompletionsApi{}, "https://native.test/v1")], AiModels.ApiStreams{}, None{}, None{}})
    registered(deferredRegistration)
    registered(nativeRegistration)
    override : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-native", "native")
    native : AiModels.Model() <- requiredModel(override)
    checked(windowIs(native, F.fromU32(4242)), "applies models.json overrides above native providers")
    selected : Maybe<&2, AiModels.Model()> <- Models.getModel(runtime, "extension-native-deferred", "native-deferred")
    +model : AiModels.Model() <- requiredModel(selected)
    +fetchTransform : C.Callback<Ai.ProviderHeaders(), Ai.ProviderHeaders()> <- C.create(~String, ~Ai.ProviderHeaders(), ~Ai.ProviderHeaders(), ~deferredTransform, "fetch")
    +cancelTransform : C.Callback<Ai.ProviderHeaders(), Ai.ProviderHeaders()> <- C.create(~String, ~Ai.ProviderHeaders(), ~Ai.ProviderHeaders(), ~deferredTransform, "cancel")
    reply : Ai.AssistantMessage<V.Value, V.Value> <- Models.fetchDeferred(runtime, model, Ai.DeferredHandle{"extension-native-deferred", "native-deferred", "openai-completions", "fetch-id", None{}, None{}, None{}}, Some{Ai.DeferredFetchOptions{Ai.ProviderRequestOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{R.Record{[R.Property{"X-Fetch", Ai.PresentValue{"fetch"}}]}}, None{}, None{}, None{}}, Some{F.fromU32(25)}}}, Models.RequestTransforms{Some{fetchTransform}, None{}})
    cancelled : AiModels.DeferredCancelResult() <- Models.cancelDeferred(runtime, model, Ai.DeferredHandle{"extension-native-deferred", "native-deferred", "openai-completions", "cancel-id", None{}, None{}, None{}}, Some{Ai.ProviderRequestOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(100)}, None{}, None{}}}, Models.RequestTransforms{Some{cancelTransform}, None{}})
    fetched : Maybe<&2, AiModels.DeferredFetchInput> <- Ref.read(Maybe<&2, AiModels.DeferredFetchInput>, fetchSlot)
    stopped : Maybe<&2, AiModels.DeferredCancelInput> <- Ref.read(Maybe<&2, AiModels.DeferredCancelInput>, cancelSlot)
    checked(fetchedCorrect(fetched) && cancelledCorrect(stopped) && successfulDeferredReply(reply), "preserves native deferred methods through provider overlays")
    Models.dispose(runtime)
    Auth.disposeStore(credentials)
    Auth.disposeApiKeyAuth(keyAuth)
    C.dispose(AiModels.DeferredFetchInput, AiModels.DeferredFetchResult(), fetchDeferred)
    C.dispose(AiModels.DeferredCancelInput, AiModels.DeferredCancelResult(), cancelDeferred)
    C.dispose(Ai.ProviderHeaders(), Ai.ProviderHeaders(), fetchTransform)
    C.dispose(Ai.ProviderHeaders(), Ai.ProviderHeaders(), cancelTransform)
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)
    fetchedFinal : Maybe<&2, AiModels.DeferredFetchInput> <- Ref.dispose(Maybe<&2, AiModels.DeferredFetchInput>, fetchSlot)
    cancelledFinal : Maybe<&2, AiModels.DeferredCancelInput> <- Ref.dispose(Maybe<&2, AiModels.DeferredCancelInput>, cancelSlot)
    return Unit{}

def checks() -> IO(Unit):
  do IO<Unit>:
    +state : Ref.Ref<State> <- Ref.new(State, State{Nil{}, False{}, True{}, True{}})
    +store : Auth.CredentialStore <- credentials(state)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    a : AiModels.Provider <- provider("a")
    b : AiModels.Provider <- provider("b")
    +runtime : Models.ModelRuntime <- Models.fromProviders([a, b], store, context)
    checkStreamOwnership(runtime)
    check(runtime, state)
    IO.print("ok scopes provider availability reads and records refresh failures")
    checkAuthGate(runtime)
    Models.dispose(runtime)
    Auth.disposeStore(store)
    previous : State <- Ref.dispose(State, state)
    checkDynamicSynchronization()
    loginBesideStalledRefresh()
    concurrentCredentials()
    cancelledSynchronization()
    scopedAvailabilityCancellation()
    independentRefreshes()
    cancellationAfterCommit()
    providerMetadata()
    configAuthOptions()
    requestAuthContracts()
    configModelLifecycle()
    nativeRegistration()
    IO.print("model availability: scoped reads, credential synchronization, snapshots, stream ownership, and auth gating pass")

# An optional fixture path adds the two models.json lifecycle contracts.
def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: checks()
    case path <> Nil{}:
      do IO<Unit>:
        checks()
        nativeModelLifecycle(path)
    case _: IO.die(Unit, 2, "usage: model-availability [models.json]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)
