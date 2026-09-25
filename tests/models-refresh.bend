import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/models-store.bend as Store
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as Context
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/ref.bend as R
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/coding-agent/src/core/model-runtime.bend as Models

# upstream packages/ai/test/models-runtime.test.ts, the refresh cases, run
# against ModelRuntime (the port's Models collection): providers publish
# their catalog through `publish`, whose model list is upstream's `update`.
# Cases that need a provider blocked in auth or in a signal-ignoring fetch
# while the caller aborts are not ported.

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})
def same(+actual: String, +expected: String, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), String.eq(actual, expected), _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  expected " ++ expected ++ "\n  actual   " ++ actual))(Unit{})

def Outcome() -> Data: Result<&2, &2, String, Unit>

def testModel(provider: String, +id: String) -> Models.Model():
  Ai.Model{id, id, Ai.OpenAICompletionsApi{}, provider, "https://example.test/v1", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(10000), U32.to_f64(1000), None{}, None{}, None{}}

# Auth fixtures (upstream ambientAuth, envKeyAuth and testOAuth)
# ---------------------------------------------------------------

def ambient(unit: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, None{}, None{}}}})

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case _: None{}

def keyOutcome(resolved: Maybe<&2, String>) -> Auth.AuthOutcome():
  match resolved:
    case None{}: Done{None{}}
    case Some{value}: Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{value}, None{}, None{}}, None{}, None{}}}}

def keyed(key: Maybe<&2, String>, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{_, credential, _}: IO.pure(Auth.AuthOutcome(), keyOutcome(Maybe.or(&2, String, storedKey(credential), key)))

def ambientAuth() -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~ambient, Unit{})
    return Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Ambient", None{}, resolve}}, None{}}

def envKeyAuth(key: Maybe<&2, String>) -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Maybe<&2, String>, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~keyed, key)
    return Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test API key", None{}, resolve}}, None{}}

def rotated(unit: Unit, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  do IO<Result<&2, &2, String, Auth.Credential>>:
    now : F64 <- Date.now()
    return Done{Auth.OAuthCredential{"rotated", "fresh", F64.add(now, U32.to_f64(60000)), Rec.new(V.Value)}}

def accessKey(unit: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"not oauth"})

def testOAuth() -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    refresh : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Unit, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~rotated, Unit{})
    toAuth : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~accessKey, Unit{})
    return Auth.ProviderAuth{None{}, Some{Auth.OAuthAuth{"Test OAuth", False{}, None{}, refresh, toAuth}}}

# Refresh behaviors
# -----------------

type Script is Data:
  # upstream "dyn": on network, count and publish the `after` catalog.
  PublishOnNetwork{count: R.Ref<Nat>, models: List<&2, Models.Model()>}
  FailOnNetwork{message: String}
  RecordPhases{id: String, calls: R.Ref<List<&2, String>>}
  # Publish a deletion, then an ephemeral catalog, recording what it saw.
  DeleteThenEphemeral{store: Store.ModelsStore, seen: R.Ref<List<&2, String>>}
  CaptureNetwork{seen: R.Ref<List<&2, String>>}
  AbortCaller{controller: Abort.AbortController<Unit>}
  CaptureSignal{seen: R.Ref<List<&2, String>>}
  # The first network refresh waits for `release` after signalling `started`.
  Gated{count: R.Ref<Nat>, started: Chan(Unit), release: Chan(Unit)}

def append(slot: R.Ref<List<&2, String>>, entry: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, slot, current => (List.append(&2, String, current, [entry]), Unit{}))

def publish(context: AiModels.RefreshModelsContext, publication: AiModels.ModelsPublication) -> IO(Bool):
  match context:
    case AiModels.RefreshModelsContext{_, _, callback, _, _, _}: C.call(AiModels.ModelsPublication, Bool, callback, publication)

def networkOf(context: AiModels.RefreshModelsContext) -> Bool:
  match context:
    case AiModels.RefreshModelsContext{_, _, _, network, _, _}: network

def storedIds(stored: Maybe<&2, Store.ModelsStoreEntry>) -> String:
  match stored:
    case None{}: "undefined"
    case Some{Store.ModelsStoreEntry{models, _, _, _}}: String.join(Models.references(models), ",")

def credentialText(credential: Maybe<&2, Auth.Credential>) -> String:
  match credential:
    case None{}: "undefined"
    case Some{Auth.ApiKeyCredential{key, env}}: "api_key " ++ Maybe.default(&2, String, key, "undefined") ++ " env " ++ Bool.show(Maybe.is_some(&2, Rec.Record<String>, env))
    case Some{Auth.OAuthCredential{refresh, access, _, _}}: "oauth " ++ access ++ " " ++ refresh

def forceText(force: Maybe<&2, Bool>) -> String:
  match force:
    case None{}: "undefined"
    case Some{value}: Bool.show(value)

def published(result: Bool) -> Outcome(): Done{Unit{}}

def deletedThenEphemeral(+store: Store.ModelsStore, +seen: R.Ref<List<&2, String>>, +context: AiModels.RefreshModelsContext) -> IO(Outcome()):
  match context:
    case AiModels.RefreshModelsContext{_, stored, _, _, _, _}:
      do IO<Outcome()>:
        append(seen, "stored " ++ storedIds(stored))
        deleted : Bool <- publish(context, AiModels.ModelsPublication{AiModels.DeleteStored{}, Some{[testModel("dynamic", "deleted")]}})
        after : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
        append(seen, "entry " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, after, None{})))
        ephemeral : Bool <- publish(context, AiModels.ModelsPublication{AiModels.KeepStored{}, Some{[testModel("dynamic", "ephemeral")]}})
        return Done{Unit{}}

def incremented(+value: Nat) -> Nat & Nat: (Nat.add(value, 1n), Nat.add(value, 1n))

def waitIfFirst(first: Bool, started: Chan(Unit), release: Chan(Unit)) -> IO(Unit):
  match first:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        received : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Unit{}

def generationPublication(+value: String) -> AiModels.ModelsPublication:
  AiModels.ModelsPublication{AiModels.StoreEntry{Store.ModelsStoreEntry{[testModel("dynamic", value)], None{}, None{}, None{}}}, Some{[testModel("dynamic", value)]}}

def gatedNetwork(+count: R.Ref<Nat>, started: Chan(Unit), release: Chan(Unit), +context: AiModels.RefreshModelsContext) -> IO(Outcome()):
  do IO<Outcome()>:
    +current : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
    waitIfFirst(Nat.is_eq(current, 1n), started, release)
    accepted : Bool <- publish(context, generationPublication("generation-" ++ Nat.show(current)))
    return Done{Unit{}}

def onNetwork(script: Script, +context: AiModels.RefreshModelsContext) -> IO(Outcome()):
  match script:
    case PublishOnNetwork{count, models}:
      do IO<Outcome()>:
        increased : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
        accepted : Bool <- publish(context, AiModels.ModelsPublication{AiModels.KeepStored{}, Some{models}})
        return Done{Unit{}}
    case FailOnNetwork{message}: IO.pure(Outcome(), Fail{message})
    case CaptureNetwork{seen}:
      match context:
        case AiModels.RefreshModelsContext{credential, _, _, _, force, _}:
          do IO<Outcome()>:
            append(seen, credentialText(credential) ++ " force " ++ forceText(force))
            return Done{Unit{}}
    case Gated{count, started, release}: gatedNetwork(count, started, release, context)
    case _: IO.pure(Outcome(), Done{Unit{}})

def networkOnly(network: Bool, script: Script, context: AiModels.RefreshModelsContext) -> IO(Outcome()):
  match network:
    case True{}: onNetwork(script, context)
    case False{}: IO.pure(Outcome(), Done{Unit{}})

def refreshWith(script: Script, +context: AiModels.RefreshModelsContext) -> IO(Outcome()):
  match script:
    case RecordPhases{id, calls}:
      do IO<Outcome()>:
        append(calls, id ++ ":" ++ Bool.pick(String, networkOf(context), "network", "cache"))
        return Done{Unit{}}
    case DeleteThenEphemeral{store, seen}: deletedThenEphemeral(store, seen, context)
    case AbortCaller{controller}:
      do IO<Outcome()>:
        won : Bool <- Abort.abort(Unit, controller, None{})
        return Done{Unit{}}
    case CaptureSignal{seen}:
      match context:
        case AiModels.RefreshModelsContext{_, _, _, _, _, signal}:
          do IO<Outcome()>:
            aborted : Bool <- Abort.aborted(Unit, signal)
            append(seen, "signal aborted " ++ Bool.show(aborted))
            return Done{Unit{}}
    case other: networkOnly(networkOf(context), other, context)

def refreshing(script: Script, context: AiModels.RefreshModelsContext) -> IO(Outcome()): refreshWith(script, context)

def provider(+id: String, auth: Auth.ProviderAuth, models: List<&2, Models.Model()>, script: Maybe<&2, Script>) -> IO(AiModels.Provider):
  match script:
    case None{}: IO.pure(AiModels.Provider, AiModels.Provider{id, id, "https://example.test/v1", auth, models, AiModels.ApiStreams{}, None{}})
    case Some{script}:
      do IO<AiModels.Provider>:
        refresh : AiModels.RefreshModels() <- C.create(~Script, ~AiModels.RefreshModelsContext, ~Outcome(), ~refreshing, script)
        return AiModels.Provider{id, id, "https://example.test/v1", auth, models, AiModels.ApiStreams{}, Some{refresh}}

def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

def credentials(data: Rec.Record<Auth.Credential>) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(data)
    storeOf(AuthStorage.borrow(owner))

def runtimeWith(providers: List<&2, AiModels.Provider>, credentialData: Rec.Record<Auth.Credential>, store: Store.ModelsStore) -> IO(Models.ModelRuntime):
  do IO<Models.ModelRuntime>:
    stored : Auth.CredentialStore <- credentials(credentialData)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    Models.fromProvidersWithStore(providers, stored, context, store)

def runtimeOf(providers: List<&2, AiModels.Provider>) -> IO(Models.ModelRuntime):
  do IO<Models.ModelRuntime>:
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    runtimeWith(providers, Rec.new(Auth.Credential), store)

def errorEntries(entries: List<&2, Rec.Property<String>>) -> String:
  match entries:
    case Nil{}: ""
    case Rec.Property{key, value} <> rest: " " ++ key ++ "=" ++ value ++ errorEntries(rest)

def errorsText(result: Models.ModelsRefreshResult) -> String:
  match result:
    case Models.ModelsRefreshResult{aborted, +errors}: "aborted " ++ Bool.show(aborted) ++ " errors " ++ Nat.show(List.length(&2, Rec.Property<String>, Rec.entries(String, errors))) ++ errorEntries(Rec.entries(String, errors))

def present(model: Maybe<&2, Models.Model()>) -> String:
  match model:
    case None{}: "undefined"
    case Some{found}: Models.reference(found)

def options(allowNetwork: Maybe<&2, Bool>, providers: Maybe<&2, List<&2, String>>, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> Models.ModelsRefreshOptions:
  Models.ModelsRefreshOptions{allowNetwork, providers, force, signal}

def all() -> Models.ModelsRefreshOptions: Models.refreshOptions()

# Cases
# -----

def updatesEveryConfiguredDynamicProvider() -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    dynamicAuth : Auth.ProviderAuth <- ambientAuth()
    staticAuth : Auth.ProviderAuth <- ambientAuth()
    dyn : AiModels.Provider <- provider("dyn", dynamicAuth, [testModel("dyn", "before")], Some{PublishOnNetwork{count, [testModel("dyn", "after")]}})
    fixed : AiModels.Provider <- provider("static", staticAuth, [testModel("static", "s1")], None{})
    +models : Models.ModelRuntime <- runtimeOf([dyn, fixed])
    before : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "before")
    first : Models.ModelsRefreshResult <- Models.refresh(models, all())
    refreshes : Nat <- R.read(Nat, count)
    after : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "after")
    gone : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "before")
    flakyAuth : Auth.ProviderAuth <- ambientAuth()
    flaky : AiModels.Provider <- provider("flaky", flakyAuth, [testModel("flaky", "model-a")], Some{FailOnNetwork{"fetch failed"}})
    registered : Outcome() <- Models.registerNativeProvider(models, flaky)
    second : Models.ModelsRefreshResult <- Models.refresh(models, all())
    total : Nat <- R.read(Nat, count)
    same(present(before) ++ " | " ++ errorsText(first) ++ " | " ++ Nat.show(refreshes) ++ " | " ++ present(after) ++ " " ++ present(gone) ++ " | " ++ Nat.show(total) ++ " | " ++ errorsText(second), "dyn/before | aborted False errors 0 | 1 | dyn/after undefined | 2 | aborted False errors 1 flaky=fetch failed", "refresh() updates every configured dynamic provider and reports failures")

def restrictsRefreshWorkToSelectedProviders() -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    oneAuth : Auth.ProviderAuth <- ambientAuth()
    twoAuth : Auth.ProviderAuth <- ambientAuth()
    one : AiModels.Provider <- provider("one", oneAuth, [testModel("one", "model-a")], Some{RecordPhases{"one", calls}})
    two : AiModels.Provider <- provider("two", twoAuth, [testModel("two", "model-a")], Some{RecordPhases{"two", calls}})
    models : Models.ModelRuntime <- runtimeOf([one, two])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(None{}, Some{["two", "unknown"]}, None{}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, calls)
    same(errorsText(result) ++ " | " ++ String.join(recorded, ","), "aborted False errors 0 | two:cache,two:network", "restricts refresh work to selected providers")

def modelIds(models: List<&2, Models.Model()>) -> String: String.join(Models.references(models), ",")

def letsProvidersChoosePersistentDeletionAndEphemeralPublication() -> IO(Unit):
  do IO<Unit>:
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    written : Store.StoreResult(Unit) <- Store.write(store, "dynamic", Store.ModelsStoreEntry{[testModel("dynamic", "stored")], None{}, None{}, None{}}, None{})
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : AiModels.Provider <- provider("dynamic", auth, [testModel("dynamic", "model-a")], Some{DeleteThenEphemeral{store, seen}})
    +models : Models.ModelRuntime <- runtimeWith([dynamic], Rec.new(Auth.Credential), store)
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{False{}}, None{}, None{}, None{}))
    entry : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    catalog : List<&2, Models.Model()> <- Models.getModels(models)
    same(errorsText(result) ++ " | " ++ String.join(recorded, ",") ++ " | " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, entry, None{})) ++ " | " ++ modelIds(catalog), "aborted False errors 0 | stored dynamic/stored,entry undefined | undefined | dynamic/ephemeral", "lets providers choose persistent deletion and ephemeral publication atomically")

def failFetch(unit: Unit, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, List<&2, Models.Model()>>):
  IO.pure(Result<&2, &2, String, List<&2, Models.Model()>>, Fail{"must not fetch"})

def fetched(unit: Unit, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, List<&2, Models.Model()>>):
  IO.pure(Result<&2, &2, String, List<&2, Models.Model()>>, Done{[testModel("dynamic", "fetched")]})

# upstream createProvider({ fetchModels }).
def fetchingProvider(online: Bool) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    auth : Auth.ProviderAuth <- envKeyAuth(None{})
    fetch : AiModels.FetchModels() <- Bool.pick(Unit -> IO(AiModels.FetchModels()), online, _ => C.create(~Unit, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, List<&2, Models.Model()>>, ~fetched, Unit{}), _ => C.create(~Unit, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, List<&2, Models.Model()>>, ~failFetch, Unit{}))(Unit{})
    refresh : AiModels.RefreshModels() <- AiModels.fetchedRefresh("dynamic", Nil{}, fetch)
    return AiModels.Provider{"dynamic", "dynamic", "https://example.test/v1", auth, Nil{}, AiModels.ApiStreams{}, Some{refresh}}

def keyCredential() -> Rec.Record<Auth.Credential>:
  Rec.set(Auth.Credential, Rec.new(Auth.Credential), "dynamic", Auth.ApiKeyCredential{Some{"key"}, None{}})

def persistsDynamicCatalogsAndRestoresThemWithoutNetworkAccess() -> IO(Unit):
  do IO<Unit>:
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    onlineProvider : AiModels.Provider <- fetchingProvider(True{})
    +online : Models.ModelRuntime <- runtimeWith([onlineProvider], keyCredential(), store)
    first : Models.ModelsRefreshResult <- Models.refresh(online, options(Some{True{}}, None{}, None{}, None{}))
    found : Maybe<&2, Models.Model()> <- Models.getModel(online, "dynamic", "fetched")
    offlineProvider : AiModels.Provider <- fetchingProvider(False{})
    +offline : Models.ModelRuntime <- runtimeWith([offlineProvider], keyCredential(), store)
    second : Models.ModelsRefreshResult <- Models.refresh(offline, options(Some{False{}}, None{}, None{}, None{}))
    restored : Maybe<&2, Models.Model()> <- Models.getModel(offline, "dynamic", "fetched")
    same(errorsText(first) ++ " " ++ present(found) ++ " | " ++ errorsText(second) ++ " " ++ present(restored), "aborted False errors 0 dynamic/fetched | aborted False errors 0 dynamic/fetched", "persists dynamic catalogs and restores them without network access")

def passesEffectiveApiKeyCredentials() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    configuredAuth : Auth.ProviderAuth <- envKeyAuth(Some{"ambient-key"})
    unconfiguredAuth : Auth.ProviderAuth <- envKeyAuth(None{})
    configured : AiModels.Provider <- provider("configured", configuredAuth, [testModel("configured", "model-a")], Some{CaptureNetwork{seen}})
    unconfigured : AiModels.Provider <- provider("unconfigured", unconfiguredAuth, [testModel("unconfigured", "model-a")], Some{CaptureNetwork{seen}})
    models : Models.ModelRuntime <- runtimeOf([configured, unconfigured])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{True{}}, None{}, Some{True{}}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    same(String.join(recorded, ","), "api_key ambient-key env False force True", "passes effective API-key credentials and refresh options while skipping unconfigured providers")

def expiredOAuth() -> Rec.Record<Auth.Credential>:
  Rec.set(Auth.Credential, Rec.new(Auth.Credential), "oauth-dynamic", Auth.OAuthCredential{"refresh", "expired", U32.to_f64(0), Rec.new(V.Value)})

def refreshesExpiredOAuthBeforeRefreshingModels() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    auth : Auth.ProviderAuth <- testOAuth()
    dynamic : AiModels.Provider <- provider("oauth-dynamic", auth, [testModel("oauth-dynamic", "model-a")], Some{CaptureNetwork{seen}})
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    +stored : Auth.CredentialStore <- credentials(expiredOAuth())
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProvidersWithStore([dynamic], stored, context, store)
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{True{}}, None{}, None{}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    persisted : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(stored, "oauth-dynamic", None{})
    same(errorsText(result) ++ " | " ++ String.join(recorded, ",") ++ " | " ++ credentialText(Result.default(&2, &2, String, Maybe<&2, Auth.Credential>, persisted, None{})), "aborted False errors 0 | oauth fresh rotated force undefined | oauth fresh rotated", "refreshes expired OAuth before refreshing models")

def alwaysGivesProvidersAConcreteSignal() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : AiModels.Provider <- provider("dynamic", auth, [testModel("dynamic", "model-a")], Some{CaptureSignal{seen}})
    models : Models.ModelRuntime <- runtimeOf([dynamic])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{True{}}, None{}, None{}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    same(errorsText(result) ++ " | " ++ String.join(recorded, ","), "aborted False errors 0 | signal aborted False,signal aborted False", "always gives providers a concrete signal")

def returnsAbortedStateWithoutReportingCancellation() -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : AiModels.Provider <- provider("dynamic", auth, [testModel("dynamic", "model-a")], Some{AbortCaller{controller}})
    models : Models.ModelRuntime <- runtimeOf([dynamic])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{True{}}, None{}, None{}, Some{Abort.signal(Unit, controller)}))
    same(errorsText(result), "aborted True errors 0", "returns aborted state without reporting cancellation as a provider error")

def rejectsLatePublicationFromASupersededProvider() -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : AiModels.Provider <- provider("dynamic", auth, Nil{}, Some{Gated{count, started, release}})
    +models : Models.ModelRuntime <- runtimeWith([dynamic], Rec.new(Auth.Credential), store)
    +first : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult, Models.refresh(models, options(Some{True{}}, Some{["dynamic"]}, None{}, None{})))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{True{}}, Some{["dynamic"]}, None{}, None{}))
    released : Bool <- Chan.send(Unit, release, Unit{})
    late : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult, first)
    catalog : List<&2, Models.Model()> <- Models.getModels(models)
    entry : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
    same(errorsText(second) ++ " | " ++ errorsText(late) ++ " | " ++ modelIds(catalog) ++ " | " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, entry, None{})), "aborted False errors 0 | aborted False errors 0 | dynamic/generation-2 | dynamic/generation-2", "rejects late publication from a superseded non-cooperative provider")

# upstream createProvider getModels: dynamic models replace baseline models of
# their id in place (the last one wins) and the others are appended.
def mergesDynamicModelsOverTheBaseline() -> IO(Unit):
  same(modelIds(AiModels.mergeModels([testModel("p", "a"), testModel("p", "b")], [testModel("q", "c"), testModel("q", "a"), testModel("r", "c")])), "q/a,p/b,r/c", "createProvider merges dynamic models over the baseline")

def main() -> IO(Unit):
  do IO<Unit>:
    updatesEveryConfiguredDynamicProvider()
    restrictsRefreshWorkToSelectedProviders()
    letsProvidersChoosePersistentDeletionAndEphemeralPublication()
    persistsDynamicCatalogsAndRestoresThemWithoutNetworkAccess()
    passesEffectiveApiKeyCredentials()
    refreshesExpiredOAuthBeforeRefreshingModels()
    alwaysGivesProvidersAConcreteSignal()
    returnsAbortedStateWithoutReportingCancellation()
    rejectsLatePublicationFromASupersededProvider()
    mergesDynamicModelsOverTheBaseline()
