import Base
import ../src/types.bend as Ai
import ../src/models.bend as Models
import ../src/models-store.bend as Store
import ../src/auth/types.bend as Auth
import ../src/auth/resolve.bend as Resolve
import ../src/auth/credential-store.bend as Credentials
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Rec
import ../../runtime/src/ref.bend as R

# upstream packages/ai/test/models-runtime.test.ts against the Models
# collection (models.bend). A publication's `update` closure is its model
# list. Adaptations: upstream's `toBe` identity checks compare what makes the
# values distinct (a replacement provider's base URL; a signal's link to the
# caller's controller); getModels() cannot fail here (catalogs are values),
# so 'swallows provider source failures ...' has no counterpart. Pending:
# cases where the caller stops waiting for a blocked provider, store or auth
# callback (the collection waits for them), model-store signal identity, and
# the stream/complete cases (requests stream through the application's stream
# functions, not the collection).

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})
def same(+actual: String, +expected: String, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), String.eq(actual, expected), _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  expected " ++ expected ++ "\n  actual   " ++ actual))(Unit{})

def Outcome() -> Data: Result<&2, &2, String, Unit>

def testModel(provider: String, +id: String) -> Models.Model():
  Ai.Model{id, id, Ai.CustomModelApi{"test-api"}, provider, "https://example.test/v1", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(10000), U32.to_f64(1000), None{}, None{}, None{}}

def reference(+model: Models.Model()) -> String: Ai.modelProvider(model) ++ "/" ++ Ai.modelId(model)

def references(models: List<&2, Models.Model()>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: reference(model) <> references(rest)

def modelIds(models: List<&2, Models.Model()>) -> String: String.join(references(models), ",")

def present(model: Maybe<&2, Models.Model()>) -> String:
  match model:
    case None{}: "undefined"
    case Some{found}: reference(found)

# Auth fixtures (upstream ambientAuth, envKeyAuth and testOAuth)
# ---------------------------------------------------------------

def ambient(unit: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, None{}, None{}}}})

def ambientAuth() -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~ambient, Unit{})
    return Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Ambient", None{}, resolve, None{}}}, None{}}

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case _: None{}

# upstream envKeyAuth: the stored key, else the ambient one; the source says
# which.
def keyOutcome(resolved: Maybe<&2, String>, stored: Bool) -> Auth.AuthOutcome():
  match resolved:
    case None{}: Done{None{}}
    case Some{value}: Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{value}, None{}, None{}}, None{}, Some{Bool.pick(String, stored, "stored", "env")}}}}

def keyed(key: Maybe<&2, String>, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{_, +credential, _}: IO.pure(Auth.AuthOutcome(), keyOutcome(Maybe.or(&2, String, storedKey(credential), key), Maybe.is_some(&2, Auth.Credential, credential)))

def envKey(key: Maybe<&2, String>) -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Maybe<&2, String>, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~keyed, key)
    return Auth.ApiKeyAuth{"Test API key", None{}, resolve, None{}}

def envKeyAuth(key: Maybe<&2, String>) -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    apiKey : Auth.ApiKeyAuth <- envKey(key)
    return Auth.ProviderAuth{Some{apiKey}, None{}}

# The refresh behaviours of the cases' testOAuth({ refresh }).
type Refresh is Data:
  Echo{count: R.Ref<Nat>}
  Rotate{}
  NewToken{count: R.Ref<Nat>}
  FailWith{message: String}
  Slow{count: R.Ref<Nat>}

def incremented(+value: Nat) -> Nat & Nat: (Nat.add(value, 1n), Nat.add(value, 1n))

def withAccess(credential: Auth.Credential, +access: String, expires: F64) -> Auth.Credential:
  match credential:
    case Auth.OAuthCredential{refresh, _, _, extra}: Auth.OAuthCredential{refresh, access, expires, extra}
    case other: other

def refreshed(script: Refresh, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match script input:
    case Echo{count} Auth.RefreshInput{credential, _}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        seen : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
        return Done{credential}
    case Rotate{} _:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        now : F64 <- Date.now()
        return Done{Auth.OAuthCredential{"rotated", "fresh", F64.add(now, U32.to_f64(60000)), Rec.new(V.Value)}}
    case NewToken{count} Auth.RefreshInput{credential, _}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        seen : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
        now : F64 <- Date.now()
        return Done{withAccess(credential, "new-token", F64.add(now, U32.to_f64(3600000)))}
    case FailWith{message} _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{message})
    case Slow{count} _:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        +seen : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
        IO.sleep(10)
        now : F64 <- Date.now()
        return Done{Auth.OAuthCredential{"r2", "new-" ++ Nat.show(seen), F64.add(now, U32.to_f64(3600000)), Rec.new(V.Value)}}

def accessKey(unit: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"not oauth"})

def unusedLogin(_: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  IO.pure(Auth.LoginOutcome(), Fail{"not used"})

def oauthOf(script: Refresh) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~unusedLogin, Unit{})
    refresh : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Refresh, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refreshed, script)
    toAuth : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~accessKey, Unit{})
    return Auth.OAuthAuth{"Test OAuth", False{}, None{}, login, refresh, toAuth}

def testOAuth(script: Refresh) -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    oauth : Auth.OAuthAuth <- oauthOf(script)
    return Auth.ProviderAuth{None{}, Some{oauth}}

# Refresh behaviours (upstream refreshModels)
# -------------------------------------------

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

def publish(context: Models.RefreshModelsContext, publication: Models.ModelsPublication) -> IO(Bool):
  match context:
    case Models.RefreshModelsContext{_, _, callback, _, _, _}: C.call(Models.ModelsPublication, Bool, callback, publication)

def networkOf(context: Models.RefreshModelsContext) -> Bool:
  match context:
    case Models.RefreshModelsContext{_, _, _, network, _, _}: network

def storedIds(stored: Maybe<&2, Store.ModelsStoreEntry>) -> String:
  match stored:
    case None{}: "undefined"
    case Some{Store.ModelsStoreEntry{models, _, _, _}}: modelIds(models)

def credentialText(credential: Maybe<&2, Auth.Credential>) -> String:
  match credential:
    case None{}: "undefined"
    case Some{Auth.ApiKeyCredential{key, env}}: "api_key " ++ Maybe.default(&2, String, key, "undefined") ++ " env " ++ Bool.show(Maybe.is_some(&2, Rec.Record<String>, env))
    case Some{Auth.OAuthCredential{refresh, access, _, _}}: "oauth " ++ access ++ " " ++ refresh

def forceText(force: Maybe<&2, Bool>) -> String:
  match force:
    case None{}: "undefined"
    case Some{value}: Bool.show(value)

def deletedThenEphemeral(+store: Store.ModelsStore, +seen: R.Ref<List<&2, String>>, +context: Models.RefreshModelsContext) -> IO(Outcome()):
  match context:
    case Models.RefreshModelsContext{_, stored, _, _, _, _}:
      do IO<Outcome()>:
        append(seen, "stored " ++ storedIds(stored))
        deleted : Bool <- publish(context, Models.ModelsPublication{Models.DeleteStored{}, Some{[testModel("dynamic", "deleted")]}})
        after : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
        append(seen, "entry " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, after, None{})))
        ephemeral : Bool <- publish(context, Models.ModelsPublication{Models.KeepStored{}, Some{[testModel("dynamic", "ephemeral")]}})
        return Done{Unit{}}

def waitIfFirst(first: Bool, started: Chan(Unit), release: Chan(Unit)) -> IO(Unit):
  match first:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        received : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Unit{}

def generationPublication(+value: String) -> Models.ModelsPublication:
  Models.ModelsPublication{Models.StoreEntry{Store.ModelsStoreEntry{[testModel("dynamic", value)], None{}, None{}, None{}}}, Some{[testModel("dynamic", value)]}}

def gatedNetwork(+count: R.Ref<Nat>, started: Chan(Unit), release: Chan(Unit), +context: Models.RefreshModelsContext) -> IO(Outcome()):
  do IO<Outcome()>:
    +current : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
    waitIfFirst(Nat.is_eq(current, 1n), started, release)
    accepted : Bool <- publish(context, generationPublication("generation-" ++ Nat.show(current)))
    return Done{Unit{}}

def onNetwork(script: Script, +context: Models.RefreshModelsContext) -> IO(Outcome()):
  match script:
    case PublishOnNetwork{count, models}:
      do IO<Outcome()>:
        increased : Nat <- R.modify(Nat, Nat, count, value => incremented(value))
        accepted : Bool <- publish(context, Models.ModelsPublication{Models.KeepStored{}, Some{models}})
        return Done{Unit{}}
    case FailOnNetwork{message}: IO.pure(Outcome(), Fail{message})
    case CaptureNetwork{seen}:
      match context:
        case Models.RefreshModelsContext{credential, _, _, _, force, _}:
          do IO<Outcome()>:
            append(seen, credentialText(credential) ++ " force " ++ forceText(force))
            return Done{Unit{}}
    case Gated{count, started, release}: gatedNetwork(count, started, release, context)
    case _: IO.pure(Outcome(), Done{Unit{}})

def networkOnly(network: Bool, script: Script, context: Models.RefreshModelsContext) -> IO(Outcome()):
  match network:
    case True{}: onNetwork(script, context)
    case False{}: IO.pure(Outcome(), Done{Unit{}})

def refreshWith(script: Script, +context: Models.RefreshModelsContext) -> IO(Outcome()):
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
        case Models.RefreshModelsContext{_, _, _, _, _, signal}:
          do IO<Outcome()>:
            aborted : Bool <- Abort.aborted(Unit, signal)
            append(seen, "signal aborted " ++ Bool.show(aborted))
            return Done{Unit{}}
    case other: networkOnly(networkOf(context), other, context)

def refreshing(script: Script, context: Models.RefreshModelsContext) -> IO(Outcome()): refreshWith(script, context)

# upstream testProvider({ id, models?, auth?, refreshModels? }).
def testProvider(+id: String, auth: Auth.ProviderAuth, models: List<&2, Models.Model()>, script: Maybe<&2, Script>) -> IO(Models.Provider):
  match script:
    case None{}: IO.pure(Models.Provider, Models.Provider{id, id, "https://example.test/v1", auth, models, Models.ApiStreams{}, None{}, None{}})
    case Some{script}:
      do IO<Models.Provider>:
        refresh : Models.RefreshModels() <- C.create(~Script, ~Models.RefreshModelsContext, ~Outcome(), ~refreshing, script)
        return Models.Provider{id, id, "https://example.test/v1", auth, models, Models.ApiStreams{}, Some{refresh}, None{}}

def ambientProvider(+id: String) -> IO(Models.Provider):
  do IO<Models.Provider>:
    auth : Auth.ProviderAuth <- ambientAuth()
    testProvider(id, auth, [testModel(id, "model-a")], None{})

def storing(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

# upstream credentials.modify(id, async () => credential)
def storeCredential(+store: Auth.CredentialStore, +id: String, credential: Auth.Credential) -> IO(Unit):
  do IO<Unit>:
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~storing, credential)
    written : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, id, update, None{})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    return Unit{}

def readCredential(+store: Auth.CredentialStore, +id: String) -> IO(Maybe<&2, Auth.Credential>):
  do IO<Maybe<&2, Auth.Credential>>:
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, id, None{})
    return Result.default(&2, &2, String, Maybe<&2, Auth.Credential>, stored, None{})

def withStores(credentials: Auth.CredentialStore, store: Store.ModelsStore) -> IO(Models.Models):
  Models.createModels(Models.CreateModelsOptions{Some{credentials}, Some{store}, None{}})

def withCredentials(credentials: Auth.CredentialStore) -> IO(Models.Models):
  Models.createModels(Models.CreateModelsOptions{Some{credentials}, None{}, None{}})

def fresh() -> IO(Models.Models): Models.createModels(Models.createModelsOptions())

def setAll(+models: Models.Models, providers: List<&2, Models.Provider>) -> IO(Unit):
  match providers:
    case Nil{}: IO.pure(Unit, Unit{})
    case provider <> rest:
      do IO<Unit>:
        Models.setProvider(models, provider)
        setAll(models, rest)

def errorEntries(entries: List<&2, Rec.Property<String>>) -> String:
  match entries:
    case Nil{}: ""
    case Rec.Property{key, value} <> rest: " " ++ key ++ "=" ++ value ++ errorEntries(rest)

def errorsText(result: Models.ModelsRefreshResult) -> String:
  match result:
    case Models.ModelsRefreshResult{aborted, +errors}: "aborted " ++ Bool.show(aborted) ++ " errors " ++ Nat.show(List.length(&2, Rec.Property<String>, Rec.entries(String, errors))) ++ errorEntries(Rec.entries(String, errors))

def options(allowNetwork: Maybe<&2, Bool>, providers: Maybe<&2, List<&2, String>>, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> Models.ModelsRefreshOptions:
  Models.ModelsRefreshOptions{allowNetwork, providers, force, signal}

def all() -> Models.ModelsRefreshOptions: Models.modelsRefreshOptions()

def ids(providers: List<&2, Models.Provider>) -> String: String.join(Models.providerIds(providers), ",")

def providerUrl(provider: Maybe<&2, Models.Provider>) -> String:
  match provider:
    case None{}: "undefined"
    case Some{Models.Provider{_, _, url, _, _, _, _, _}}: url

# Registry cases
# --------------

def infoText(infos: List<&2, Auth.CredentialInfo>) -> String:
  match infos:
    case Nil{}: ""
    case Auth.CredentialInfo{id, kind} <> rest: id ++ ":" ++ Auth.typeName(kind) ++ " " ++ infoText(rest)

def enumeratesCredentialMetadata() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    storeCredential(credentials, "api-provider", Auth.ApiKeyCredential{Some{"secret"}, None{}})
    now : F64 <- Date.now()
    storeCredential(credentials, "oauth-provider", Auth.OAuthCredential{"refresh", "access", F64.add(now, U32.to_f64(60000)), Rec.new(V.Value)})
    listed : Auth.StoreResult(List<&2, Auth.CredentialInfo>) <- Auth.list(credentials, None{})
    same(infoText(Result.default(&2, &2, String, List<&2, Auth.CredentialInfo>, listed, Nil{})), "api-provider:api_key oauth-provider:oauth ", "enumerates credential metadata without exposing secrets")

# `toBe(replacement)`: the replacement is told apart by its base URL.
def registersReplacesAndDeletesProviders() -> IO(Unit):
  do IO<Unit>:
    +models : Models.Models <- fresh()
    p1 : Models.Provider <- ambientProvider("p1")
    p2 : Models.Provider <- ambientProvider("p2")
    setAll(models, [p1, p2])
    first : List<&2, Models.Provider> <- Models.getProviders(models)
    auth : Auth.ProviderAuth <- ambientAuth()
    Models.setProvider(models, Models.Provider{"p1", "p1", "https://replacement.test/v1", auth, [testModel("p1", "model-a")], Models.ApiStreams{}, None{}, None{}})
    replaced : Maybe<&2, Models.Provider> <- Models.getProvider(models, "p1")
    second : List<&2, Models.Provider> <- Models.getProviders(models)
    Models.deleteProvider(models, "p1")
    deleted : Maybe<&2, Models.Provider> <- Models.getProvider(models, "p1")
    Models.clearProviders(models)
    cleared : List<&2, Models.Provider> <- Models.getProviders(models)
    same(ids(first) ++ " | " ++ providerUrl(replaced) ++ " " ++ ids(second) ++ " | " ++ providerUrl(deleted) ++ " | " ++ Nat.show(List.length(&2, Models.Provider, cleared)), "p1,p2 | https://replacement.test/v1 p1,p2 | undefined | 0", "registers, replaces, and deletes providers")

def hasApiText(model: Maybe<&2, Models.Model()>, api: String) -> String:
  match model:
    case None{}: "undefined"
    case Some{found}: Bool.show(Models.hasApi(Ai.JsonValue, found, api))

def listsAndFindsModelsPerProvider() -> IO(Unit):
  do IO<Unit>:
    +models : Models.Models <- fresh()
    auth1 : Auth.ProviderAuth <- ambientAuth()
    auth2 : Auth.ProviderAuth <- ambientAuth()
    p1 : Models.Provider <- testProvider("p1", auth1, [testModel("p1", "m1"), testModel("p1", "m2")], None{})
    p2 : Models.Provider <- testProvider("p2", auth2, [testModel("p2", "m3")], None{})
    setAll(models, [p1, p2])
    everything : List<&2, Models.Model()> <- Models.getModels(models, None{})
    first : List<&2, Models.Model()> <- Models.getModels(models, Some{"p1"})
    none : List<&2, Models.Model()> <- Models.getModels(models, Some{"nope"})
    +found : Maybe<&2, Models.Model()> <- Models.getModel(models, "p2", "m3")
    missing : Maybe<&2, Models.Model()> <- Models.getModel(models, "p2", "missing")
    same(modelIds(everything) ++ " | " ++ modelIds(first) ++ " | " ++ Nat.show(List.length(&2, Models.Model(), none)) ++ " | " ++ present(found) ++ " " ++ present(missing) ++ " | " ++ hasApiText(found, "openai-completions") ++ " " ++ hasApiText(found, "test-api"), "p1/m1,p1/m2,p2/m3 | p1/m1,p1/m2 | 0 | p2/m3 undefined | False True", "lists and finds models per provider")

# Refresh cases
# -------------

def updatesEveryConfiguredDynamicProvider() -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    +models : Models.Models <- fresh()
    dynamicAuth : Auth.ProviderAuth <- ambientAuth()
    staticAuth : Auth.ProviderAuth <- ambientAuth()
    dyn : Models.Provider <- testProvider("dyn", dynamicAuth, [testModel("dyn", "before")], Some{PublishOnNetwork{count, [testModel("dyn", "after")]}})
    fixed : Models.Provider <- testProvider("static", staticAuth, [testModel("static", "s1")], None{})
    setAll(models, [dyn, fixed])
    before : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "before")
    first : Models.ModelsRefreshResult <- Models.refresh(models, all())
    refreshes : Nat <- R.read(Nat, count)
    after : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "after")
    gone : Maybe<&2, Models.Model()> <- Models.getModel(models, "dyn", "before")
    flakyAuth : Auth.ProviderAuth <- ambientAuth()
    flaky : Models.Provider <- testProvider("flaky", flakyAuth, [testModel("flaky", "model-a")], Some{FailOnNetwork{"fetch failed"}})
    Models.setProvider(models, flaky)
    second : Models.ModelsRefreshResult <- Models.refresh(models, all())
    total : Nat <- R.read(Nat, count)
    same(present(before) ++ " | " ++ errorsText(first) ++ " | " ++ Nat.show(refreshes) ++ " | " ++ present(after) ++ " " ++ present(gone) ++ " | " ++ Nat.show(total) ++ " | " ++ errorsText(second), "dyn/before | aborted False errors 0 | 1 | dyn/after undefined | 2 | aborted False errors 1 flaky=fetch failed", "refresh() updates every configured dynamic provider and reports failures")

def restrictsRefreshWorkToSelectedProviders() -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +models : Models.Models <- fresh()
    oneAuth : Auth.ProviderAuth <- ambientAuth()
    twoAuth : Auth.ProviderAuth <- ambientAuth()
    one : Models.Provider <- testProvider("one", oneAuth, [testModel("one", "model-a")], Some{RecordPhases{"one", calls}})
    two : Models.Provider <- testProvider("two", twoAuth, [testModel("two", "model-a")], Some{RecordPhases{"two", calls}})
    setAll(models, [one, two])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(None{}, Some{["two", "unknown"]}, None{}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, calls)
    same(errorsText(result) ++ " | " ++ String.join(recorded, ","), "aborted False errors 0 | two:cache,two:network", "restricts refresh work to selected providers")

def letsProvidersChoosePersistentDeletionAndEphemeralPublication() -> IO(Unit):
  do IO<Unit>:
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    written : Store.StoreResult(Unit) <- Store.write(store, "dynamic", Store.ModelsStoreEntry{[testModel("dynamic", "stored")], None{}, None{}, None{}}, None{})
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +models : Models.Models <- Models.createModels(Models.CreateModelsOptions{None{}, Some{store}, None{}})
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : Models.Provider <- testProvider("dynamic", auth, [testModel("dynamic", "model-a")], Some{DeleteThenEphemeral{store, seen}})
    Models.setProvider(models, dynamic)
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(Some{False{}}, None{}, None{}, None{}))
    entry : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    catalog : List<&2, Models.Model()> <- Models.getModels(models, None{})
    same(errorsText(result) ++ " | " ++ String.join(recorded, ",") ++ " | " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, entry, None{})) ++ " | " ++ modelIds(catalog), "aborted False errors 0 | stored dynamic/stored,entry undefined | undefined | dynamic/ephemeral", "lets providers choose persistent deletion and ephemeral publication atomically")

def failFetch(unit: Unit, context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, List<&2, Models.Model()>>):
  IO.pure(Result<&2, &2, String, List<&2, Models.Model()>>, Fail{"must not fetch"})

def fetched(unit: Unit, context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, List<&2, Models.Model()>>):
  IO.pure(Result<&2, &2, String, List<&2, Models.Model()>>, Done{[testModel("dynamic", "fetched")]})

# upstream createProvider({ fetchModels }).
def fetchingProvider(online: Bool) -> IO(Models.Provider):
  do IO<Models.Provider>:
    auth : Auth.ProviderAuth <- envKeyAuth(None{})
    fetch : Models.FetchModels() <- Bool.pick(Unit -> IO(Models.FetchModels()), online, _ => C.create(~Unit, ~Models.RefreshModelsContext, ~Result<&2, &2, String, List<&2, Models.Model()>>, ~fetched, Unit{}), _ => C.create(~Unit, ~Models.RefreshModelsContext, ~Result<&2, &2, String, List<&2, Models.Model()>>, ~failFetch, Unit{}))(Unit{})
    refresh : Models.RefreshModels() <- Models.fetchedRefresh("dynamic", Nil{}, fetch)
    return Models.Provider{"dynamic", "dynamic", "https://example.test/v1", auth, Nil{}, Models.ApiStreams{}, Some{refresh}, None{}}

def persistsDynamicCatalogsAndRestoresThemWithoutNetworkAccess() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    storeCredential(credentials, "dynamic", Auth.ApiKeyCredential{Some{"key"}, None{}})
    +online : Models.Models <- withStores(credentials, store)
    onlineProvider : Models.Provider <- fetchingProvider(True{})
    Models.setProvider(online, onlineProvider)
    first : Models.ModelsRefreshResult <- Models.refresh(online, all())
    found : Maybe<&2, Models.Model()> <- Models.getModel(online, "dynamic", "fetched")
    +offline : Models.Models <- withStores(credentials, store)
    offlineProvider : Models.Provider <- fetchingProvider(False{})
    Models.setProvider(offline, offlineProvider)
    second : Models.ModelsRefreshResult <- Models.refresh(offline, options(Some{False{}}, None{}, None{}, None{}))
    restored : Maybe<&2, Models.Model()> <- Models.getModel(offline, "dynamic", "fetched")
    same(errorsText(first) ++ " " ++ present(found) ++ " | " ++ errorsText(second) ++ " " ++ present(restored), "aborted False errors 0 dynamic/fetched | aborted False errors 0 dynamic/fetched", "persists dynamic catalogs and restores them without network access")

def passesEffectiveApiKeyCredentials() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +models : Models.Models <- fresh()
    configuredAuth : Auth.ProviderAuth <- envKeyAuth(Some{"ambient-key"})
    unconfiguredAuth : Auth.ProviderAuth <- envKeyAuth(None{})
    configured : Models.Provider <- testProvider("configured", configuredAuth, [testModel("configured", "model-a")], Some{CaptureNetwork{seen}})
    unconfigured : Models.Provider <- testProvider("unconfigured", unconfiguredAuth, [testModel("unconfigured", "model-a")], Some{CaptureNetwork{seen}})
    setAll(models, [configured, unconfigured])
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(None{}, None{}, Some{True{}}, None{}))
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    same(String.join(recorded, ","), "api_key ambient-key env False force True", "passes effective API-key credentials and refresh options while skipping unconfigured providers")

def refreshesExpiredOAuthBeforeRefreshingModels() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    storeCredential(credentials, "oauth-dynamic", Auth.OAuthCredential{"refresh", "expired", U32.to_f64(0), Rec.new(V.Value)})
    +models : Models.Models <- withCredentials(credentials)
    auth : Auth.ProviderAuth <- testOAuth(Rotate{})
    dynamic : Models.Provider <- testProvider("oauth-dynamic", auth, [testModel("oauth-dynamic", "model-a")], Some{CaptureNetwork{seen}})
    Models.setProvider(models, dynamic)
    result : Models.ModelsRefreshResult <- Models.refresh(models, all())
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    persisted : Maybe<&2, Auth.Credential> <- readCredential(credentials, "oauth-dynamic")
    same(errorsText(result) ++ " | " ++ String.join(recorded, ",") ++ " | " ++ credentialText(persisted), "aborted False errors 0 | oauth fresh rotated force undefined | oauth fresh rotated", "refreshes expired OAuth before refreshing models")

def alwaysGivesProvidersAConcreteSignal() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +models : Models.Models <- fresh()
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : Models.Provider <- testProvider("dynamic", auth, [testModel("dynamic", "model-a")], Some{CaptureSignal{seen}})
    Models.setProvider(models, dynamic)
    result : Models.ModelsRefreshResult <- Models.refresh(models, all())
    recorded : List<&2, String> <- R.read(List<&2, String>, seen)
    same(errorsText(result) ++ " | " ++ String.join(recorded, ","), "aborted False errors 0 | signal aborted False,signal aborted False", "always gives providers a concrete signal")

def returnsAbortedStateWithoutReportingCancellation() -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +models : Models.Models <- fresh()
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : Models.Provider <- testProvider("dynamic", auth, [testModel("dynamic", "model-a")], Some{AbortCaller{controller}})
    Models.setProvider(models, dynamic)
    result : Models.ModelsRefreshResult <- Models.refresh(models, options(None{}, None{}, None{}, Some{Abort.signal(Unit, controller)}))
    same(errorsText(result), "aborted True errors 0", "returns aborted state without reporting cancellation as a provider error")

def rejectsLatePublicationFromASupersededProvider() -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +store : Store.ModelsStore <- Store.inMemoryModelsStore()
    +models : Models.Models <- Models.createModels(Models.CreateModelsOptions{None{}, Some{store}, None{}})
    auth : Auth.ProviderAuth <- ambientAuth()
    dynamic : Models.Provider <- testProvider("dynamic", auth, Nil{}, Some{Gated{count, started, release}})
    Models.setProvider(models, dynamic)
    +first : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult, Models.refresh(models, options(None{}, Some{["dynamic"]}, None{}, None{})))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : Models.ModelsRefreshResult <- Models.refresh(models, options(None{}, Some{["dynamic"]}, None{}, None{}))
    released : Bool <- Chan.send(Unit, release, Unit{})
    late : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult, first)
    catalog : List<&2, Models.Model()> <- Models.getModels(models, None{})
    entry : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "dynamic", None{})
    same(errorsText(second) ++ " | " ++ errorsText(late) ++ " | " ++ modelIds(catalog) ++ " | " ++ storedIds(Result.default(&2, &2, String, Maybe<&2, Store.ModelsStoreEntry>, entry, None{})), "aborted False errors 0 | aborted False errors 0 | dynamic/generation-2 | dynamic/generation-2", "rejects late publication from a superseded non-cooperative provider")

# Auth cases
# ----------

# Each callback records whether the signal it received is still live, and
# keeps it; after the caller aborts, every kept signal must report the abort
# (upstream: the received signals are the caller's).
type Signals is Data:
  Signals{kept: R.Ref<List<&2, Abort.AbortSignal<Unit>>>}

def kept(signals: Signals, signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match signals:
    case Signals{slot}: R.modify(List<&2, Abort.AbortSignal<Unit>>, Unit, slot, current => (List.append(&2, Abort.AbortSignal<Unit>, current, [signal]), Unit{}))

def signalLogin(signals: Signals, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}:
      do IO<Auth.LoginOutcome()>:
        kept(signals, signal)
        return Done{Auth.ApiKeyCredential{Some{"saved"}, None{}}}

def signalCheck(signals: Signals, input: Auth.ResolveInput) -> IO(Auth.CheckOutcome()):
  match input:
    case Auth.ResolveInput{_, _, signal}:
      do IO<Auth.CheckOutcome()>:
        kept(signals, signal)
        return Done{Some{Auth.AuthCheck{None{}, Auth.ApiKeyType{}}}}

def signalResolve(signals: Signals, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{_, _, signal}:
      do IO<Auth.AuthOutcome()>:
        kept(signals, signal)
        return Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{"resolved"}, None{}, None{}}, None{}, None{}}}}

def abortedAll(signals: List<&2, Abort.AbortSignal<Unit>>) -> IO(List<&2, String>):
  match signals:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case signal <> rest:
      do IO<List<&2, String>>:
        aborted : Bool <- Abort.aborted(Unit, signal)
        others : List<&2, String> <- abortedAll(rest)
        return Bool.show(aborted) <> others

def unusedPrompt(unit: Unit, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>): IO.pure(Result<&2, &2, String, String>, Done{"unused"})
def ignored(unit: Unit, event: Auth.AuthEvent) -> IO(Unit): IO.pure(Unit, Unit{})

def interaction(signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Auth.AuthInteraction):
  do IO<Auth.AuthInteraction>:
    prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Unit, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~unusedPrompt, Unit{})
    notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~ignored, Unit{})
    return Auth.AuthInteraction{signal, prompt, notify}

def withSignal(+signal: Abort.AbortSignal<Unit>) -> Resolve.AuthResolutionOverrides: Resolve.AuthResolutionOverrides{None{}, None{}, None{}, Some{signal}}

def passesCallerSignalsToProviderAuthCallbacks() -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +slot : R.Ref<List<&2, Abort.AbortSignal<Unit>>> <- R.new(List<&2, Abort.AbortSignal<Unit>>, Nil{})
    +signals : Signals <- IO.pure(Signals, Signals{slot})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Signals, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~signalLogin, signals)
    check : C.Callback<Auth.ResolveInput, Auth.CheckOutcome()> <- C.create(~Signals, ~Auth.ResolveInput, ~Auth.CheckOutcome(), ~signalCheck, signals)
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Signals, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~signalResolve, signals)
    +models : Models.Models <- fresh()
    provider : Models.Provider <- testProvider("p1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Signal auth", Some{login}, resolve, Some{check}}}, None{}}, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    +signal : Abort.AbortSignal<Unit> <- IO.pure(Abort.AbortSignal<Unit>, Abort.signal(Unit, controller))
    checked : Models.CheckResult() <- Models.checkAuth(models, "p1", Some{signal})
    resolved : Resolve.Resolution() <- Models.getAuth(models, "p1", withSignal(signal))
    asked : Auth.AuthInteraction <- interaction(Some{signal})
    logged : Auth.LoginOutcome() <- Models.login(models, "p1", Auth.ApiKeyType{}, asked)
    +received : List<&2, Abort.AbortSignal<Unit>> <- R.read(List<&2, Abort.AbortSignal<Unit>>, slot)
    before : List<&2, String> <- abortedAll(received)
    won : Bool <- Abort.abort(Unit, controller, None{})
    after : List<&2, String> <- abortedAll(received)
    same(String.join(before, ",") ++ " | " ++ String.join(after, ","), "False,False,False | True,True,True", "passes caller signals to provider auth callbacks")

def authText(resolution: Resolve.Resolution()) -> String:
  match resolution:
    case Fail{error}: "error " ++ Resolve.errorMessage(error)
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, _}, _, source}}}: Maybe.default(&2, String, key, "undefined") ++ " " ++ Maybe.default(&2, String, source, "undefined")

def codeText(code: Resolve.ModelsErrorCode) -> String:
  match code:
    case Resolve.ModelSource{}: "model_source"
    case Resolve.ModelValidation{}: "model_validation"
    case Resolve.ProviderError{}: "provider"
    case Resolve.StreamError{}: "stream"
    case Resolve.AuthError{}: "auth"
    case Resolve.OAuthError{}: "oauth"

def errorCode(resolution: Resolve.Resolution()) -> String:
  match resolution:
    case Fail{error}: codeText(Resolve.errorCode(error))
    case Done{_}: "resolved"

def minutes(n: U32) -> F64: U32.to_f64(U32.mul(n, 60000))

def resolvesAuthStoredCredentialOwnsTheProvider() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +models : Models.Models <- withCredentials(credentials)
    apiKey : Auth.ApiKeyAuth <- envKey(Some{"env-key"})
    oauth : Auth.OAuthAuth <- oauthOf(Rotate{})
    provider : Models.Provider <- testProvider("p1", Auth.ProviderAuth{Some{apiKey}, Some{oauth}}, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    +model : Models.Model() <- IO.pure(Models.Model(), testModel("p1", "model-a"))
    byModel : Resolve.Resolution() <- Models.getModelAuth(models, model, Resolve.noOverrides())
    byId : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    explicit : Resolve.Resolution() <- Models.getModelAuth(models, model, Resolve.AuthResolutionOverrides{Some{"explicit-key"}, None{}, None{}, None{}})
    now : F64 <- Date.now()
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "oauth-token", F64.add(now, minutes(10)), Rec.new(V.Value)})
    viaOAuth : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    storeCredential(credentials, "p1", Auth.ApiKeyCredential{Some{"stored-key"}, None{}})
    viaKey : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    same(String.join([authText(byModel), authText(byId), authText(explicit), authText(viaOAuth), authText(viaKey)], " | "), "env-key env | env-key env | explicit-key stored | oauth-token OAuth | stored-key stored", "resolves auth: stored credential owns the provider, ambient only when nothing stored")

def checkText(result: Models.CheckResult()) -> String:
  match result:
    case Fail{error}: "error " ++ Resolve.errorMessage(error)
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthCheck{source, kind}}}: Maybe.default(&2, String, source, "undefined") ++ " " ++ Auth.typeName(kind)

def providersOf(models: List<&2, Models.Model()>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: Ai.modelProvider(model) <> providersOf(rest)

def availableText(result: Models.AvailableResult()) -> String:
  match result:
    case Fail{error}: "error " ++ Resolve.errorMessage(error)
    case Done{models}: String.join(providersOf(models), ",")

def checksProviderAuthWithoutRefreshingOAuth() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    +models : Models.Models <- withCredentials(credentials)
    ambientKey : Auth.ProviderAuth <- envKeyAuth(Some{"env-key"})
    missingKey : Auth.ProviderAuth <- envKeyAuth(None{})
    oauth : Auth.ProviderAuth <- testOAuth(Echo{count})
    ambientProvider : Models.Provider <- testProvider("ambient", ambientKey, [testModel("ambient", "model-a")], None{})
    missingProvider : Models.Provider <- testProvider("missing", missingKey, [testModel("missing", "model-a")], None{})
    oauthProvider : Models.Provider <- testProvider("oauth", oauth, [testModel("oauth", "model-a")], None{})
    setAll(models, [ambientProvider, missingProvider, oauthProvider])
    storeCredential(credentials, "oauth", Auth.OAuthCredential{"refresh", "expired", U32.to_f64(0), Rec.new(V.Value)})
    ambientCheck : Models.CheckResult() <- Models.checkAuth(models, "ambient", None{})
    missingCheck : Models.CheckResult() <- Models.checkAuth(models, "missing", None{})
    oauthCheck : Models.CheckResult() <- Models.checkAuth(models, "oauth", None{})
    refreshes : Nat <- R.read(Nat, count)
    everything : Models.AvailableResult() <- Models.getAvailable(models, None{}, None{})
    selected : Models.AvailableResult() <- Models.getAvailable(models, Some{"ambient"}, None{})
    same(String.join([checkText(ambientCheck), checkText(missingCheck), checkText(oauthCheck), Nat.show(refreshes), availableText(everything), availableText(selected)], " | "), "env api_key | undefined | OAuth oauth | 0 | ambient,oauth | ambient", "checks provider auth without refreshing OAuth and filters available models")

def loggedIn(unit: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  IO.pure(Auth.LoginOutcome(), Done{Auth.ApiKeyCredential{Some{"logged-in"}, None{}}})

def loginText(result: Auth.LoginOutcome()) -> String:
  match result:
    case Fail{message}: "error " ++ message
    case Done{credential}: credentialText(Some{credential})

def withLogin(auth: Auth.ApiKeyAuth, login: C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()>) -> Auth.ApiKeyAuth:
  match auth:
    case Auth.ApiKeyAuth{name, _, resolve, check}: Auth.ApiKeyAuth{name, Some{login}, resolve, check}

def runsProviderLoginAndLogout() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +models : Models.Models <- withCredentials(credentials)
    base : Auth.ApiKeyAuth <- envKey(None{})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~loggedIn, Unit{})
    provider : Models.Provider <- testProvider("p1", Auth.ProviderAuth{Some{withLogin(base, login)}, None{}}, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    asked : Auth.AuthInteraction <- interaction(None{})
    +credential : Auth.LoginOutcome() <- Models.login(models, "p1", Auth.ApiKeyType{}, asked)
    stored : Maybe<&2, Auth.Credential> <- readCredential(credentials, "p1")
    removed : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.logout(models, "p1", None{})
    after : Maybe<&2, Auth.Credential> <- readCredential(credentials, "p1")
    same(loginText(credential) ++ " | " ++ credentialText(stored) ++ " | " ++ credentialText(after), "api_key logged-in env False | api_key logged-in env False | undefined", "runs provider login and logout through the credential store")


def storedCredentialWithoutHandlerBlocksAmbient() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +models : Models.Models <- withCredentials(credentials)
    auth : Auth.ProviderAuth <- envKeyAuth(Some{"env-key"})
    provider : Models.Provider <- testProvider("p1", auth, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "a", U32.to_f64(0), Rec.new(V.Value)})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    same(authText(resolution), "undefined", "a stored credential without a matching handler blocks ambient fallback")

def oauthModels(+credentials: Auth.CredentialStore, script: Refresh) -> IO(Models.Models):
  do IO<Models.Models>:
    +models : Models.Models <- withCredentials(credentials)
    auth : Auth.ProviderAuth <- testOAuth(script)
    provider : Models.Provider <- testProvider("p1", auth, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    return models

def accessOf(credential: Maybe<&2, Auth.Credential>) -> String:
  match credential:
    case Some{Auth.OAuthCredential{_, access, _, _}}: access
    case _: "undefined"

def refreshesExpiredOAuthAndPersistsTheRotatedCredential() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    models : Models.Models <- oauthModels(credentials, NewToken{count})
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "old-token", U32.to_f64(0), Rec.new(V.Value)})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    stored : Maybe<&2, Auth.Credential> <- readCredential(credentials, "p1")
    same(authText(resolution) ++ " | " ++ accessOf(stored), "new-token OAuth | new-token", "refreshes expired oauth credentials and persists the rotated credential")

def refreshesWithLessThanFiveMinutesRemaining() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    models : Models.Models <- oauthModels(credentials, NewToken{count})
    now : F64 <- Date.now()
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "old-token", F64.add(now, U32.to_f64(60000)), Rec.new(V.Value)})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    refreshes : Nat <- R.read(Nat, count)
    same(authText(resolution) ++ " | " ++ Nat.show(refreshes), "new-token OAuth | 1", "refreshes oauth credentials with less than five minutes remaining")

def honorsLongerMinimumValidity() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    models : Models.Models <- oauthModels(credentials, NewToken{count})
    now : F64 <- Date.now()
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "old-token", F64.add(now, minutes(10)), Rec.new(V.Value)})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.AuthResolutionOverrides{None{}, None{}, Some{minutes(30)}, None{}})
    refreshes : Nat <- R.read(Nat, count)
    same(authText(resolution) ++ " | " ++ Nat.show(refreshes), "new-token OAuth | 1", "honors a caller's longer OAuth minimum validity")

def rejectsWithCodeOAuthWhenRefreshFails() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    models : Models.Models <- oauthModels(credentials, FailWith{"invalid_grant"})
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "old", U32.to_f64(0), Rec.new(V.Value)})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    stored : Maybe<&2, Auth.Credential> <- readCredential(credentials, "p1")
    same(errorCode(resolution) ++ " | " ++ accessOf(stored), "oauth | old", "rejects with code oauth when refresh fails, preserving the stored credential")

def serializesConcurrentOAuthRefreshes() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r1", "old", U32.to_f64(0), Rec.new(V.Value)})
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    +models : Models.Models <- oauthModels(credentials, Slow{count})
    first : Chan(Resolve.Resolution()) <- IO.fork(Resolve.Resolution(), Models.getAuth(models, "p1", Resolve.noOverrides()))
    second : Chan(Resolve.Resolution()) <- IO.fork(Resolve.Resolution(), Models.getAuth(models, "p1", Resolve.noOverrides()))
    a : Resolve.Resolution() <- IO.join(Resolve.Resolution(), first)
    b : Resolve.Resolution() <- IO.join(Resolve.Resolution(), second)
    refreshes : Nat <- R.read(Nat, count)
    same(Nat.show(refreshes) ++ " | " ++ authText(a) ++ " | " ++ authText(b), "1 | new-1 OAuth | new-1 OAuth", "serializes concurrent OAuth refreshes through store.modify (no double refresh)")

# A store whose modify counts its calls before delegating.
type Counting is Data:
  Counting{base: Auth.CredentialStore, modifies: R.Ref<Nat>}

def countingRead(store: Counting, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match store request:
    case Counting{base, _} Auth.Request{id, signal}: Auth.read(base, id, signal)

def countingList(store: Counting, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  match store:
    case Counting{base, _}: Auth.list(base, signal)

def countingModify(store: Counting, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match store request:
    case Counting{base, modifies} Auth.Modify{id, update, signal}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        seen : Nat <- R.modify(Nat, Nat, modifies, value => incremented(value))
        Auth.modify(base, id, update, signal)

def countingDelete(store: Counting, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match store request:
    case Counting{base, _} Auth.Request{id, signal}: Auth.delete(base, id, signal)

def countingStore(+counting: Counting) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Counting, ~Auth.Request, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~countingRead, counting)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Counting, ~Auth.Signal(), ~Auth.StoreResult(List<&2, Auth.CredentialInfo>), ~countingList, counting)
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Counting, ~Auth.Modify, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~countingModify, counting)
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Counting, ~Auth.Request, ~Auth.StoreResult(Unit), ~countingDelete, counting)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def validOAuthTokensResolveWithoutModify() -> IO(Unit):
  do IO<Unit>:
    +base : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +modifies : R.Ref<Nat> <- R.new(Nat, 0n)
    now : F64 <- Date.now()
    storeCredential(base, "p1", Auth.OAuthCredential{"r", "valid", F64.add(now, minutes(10)), Rec.new(V.Value)})
    credentials : Auth.CredentialStore <- countingStore(Counting{base, modifies})
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    models : Models.Models <- oauthModels(credentials, Echo{count})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    total : Nat <- R.read(Nat, modifies)
    same(authText(resolution) ++ " | " ++ Nat.show(total), "valid OAuth | 0", "valid oauth tokens resolve without touching modify")

# upstream's failing stores: read fails; or read answers an expired OAuth
# credential and modify fails.
type Failing is Data:
  ReadFails{}
  ModifyFails{}

def failingRead(store: Failing, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match store:
    case ReadFails{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Fail{"disk on fire"})
    case ModifyFails{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{Auth.OAuthCredential{"r", "old", U32.to_f64(0), Rec.new(V.Value)}}})

def failingList(store: Failing, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  match store:
    case ReadFails{}: IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{Nil{}})
    case ModifyFails{}: IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{[Auth.CredentialInfo{"p1", Auth.OAuthType{}}]})

def failingModify(store: Failing, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match store:
    case ReadFails{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})
    case ModifyFails{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Fail{"disk on fire"})

def failingDelete(store: Failing, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  IO.pure(Auth.StoreResult(Unit), Done{Unit{}})

def failingStore(+failing: Failing) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Failing, ~Auth.Request, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~failingRead, failing)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Failing, ~Auth.Signal(), ~Auth.StoreResult(List<&2, Auth.CredentialInfo>), ~failingList, failing)
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Failing, ~Auth.Modify, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~failingModify, failing)
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Failing, ~Auth.Request, ~Auth.StoreResult(Unit), ~failingDelete, failing)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def wrapsCredentialStoreFailures() -> IO(Unit):
  do IO<Unit>:
    readFailing : Auth.CredentialStore <- failingStore(ReadFails{})
    +models : Models.Models <- withCredentials(readFailing)
    auth : Auth.ProviderAuth <- envKeyAuth(Some{"env-key"})
    provider : Models.Provider <- testProvider("p1", auth, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    read : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    modifyFailing : Auth.CredentialStore <- failingStore(ModifyFails{})
    +count : R.Ref<Nat> <- R.new(Nat, 0n)
    oauthModels : Models.Models <- oauthModels(modifyFailing, Echo{count})
    modified : Resolve.Resolution() <- Models.getAuth(oauthModels, "p1", Resolve.noOverrides())
    same(errorCode(read) ++ " | " ++ errorCode(modified), "auth | auth", "wraps credential store failures in ModelsError")

def keepsTheUnderlyingReasonInOAuthRefreshErrors() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    storeCredential(credentials, "p1", Auth.OAuthCredential{"r", "old", U32.to_f64(0), Rec.new(V.Value)})
    models : Models.Models <- oauthModels(credentials, FailWith{"token refresh failed (400): invalid_grant"})
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    same(authText(resolution), "error OAuth refresh failed for p1: token refresh failed (400): invalid_grant", "keeps the underlying reason in wrapped oauth refresh errors")

def failingResolve(unit: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()): IO.pure(Auth.AuthOutcome(), Fail{"nope"})

def wrapsApiKeyAuthFailures() -> IO(Unit):
  do IO<Unit>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~failingResolve, Unit{})
    +models : Models.Models <- fresh()
    provider : Models.Provider <- testProvider("p1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Failing", None{}, resolve, None{}}}, None{}}, [testModel("p1", "model-a")], None{})
    Models.setProvider(models, provider)
    resolution : Resolve.Resolution() <- Models.getAuth(models, "p1", Resolve.noOverrides())
    same(errorCode(resolution), "auth", "wraps api-key auth failures in ModelsError")

# Supplemental: getAvailable applies a provider's filterModels to its catalog
# for the stored credential, after its auth check.
def onlyFirst(unit: Unit, input: Models.FilterModelsInput) -> IO(List<&2, Models.Model()>):
  match input:
    case Models.FilterModelsInput{first <> _, Some{_}}: IO.pure(List<&2, Models.Model()>, [first])
    case Models.FilterModelsInput{models, _}: IO.pure(List<&2, Models.Model()>, models)

def availableModels(result: Models.AvailableResult()) -> String:
  match result:
    case Fail{error}: "error " ++ Resolve.errorMessage(error)
    case Done{models}: modelIds(models)

def appliesFilterModelsToAvailableModels() -> IO(Unit):
  do IO<Unit>:
    +credentials : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +models : Models.Models <- withCredentials(credentials)
    auth : Auth.ProviderAuth <- envKeyAuth(Some{"env-key"})
    filter : Models.FilterModels() <- C.create(~Unit, ~Models.FilterModelsInput, ~List<&2, Models.Model()>, ~onlyFirst, Unit{})
    Models.setProvider(models, Models.Provider{"p1", "p1", "https://example.test/v1", auth, [testModel("p1", "m1"), testModel("p1", "m2")], Models.ApiStreams{}, None{}, Some{filter}})
    ambient : Models.AvailableResult() <- Models.getAvailable(models, None{}, None{})
    storeCredential(credentials, "p1", Auth.ApiKeyCredential{Some{"stored-key"}, None{}})
    stored : Models.AvailableResult() <- Models.getAvailable(models, None{}, None{})
    same(availableModels(ambient) ++ " | " ++ availableModels(stored), "p1/m1,p1/m2 | p1/m1", "getAvailable applies filterModels for the stored credential")


# upstream createProvider getModels: dynamic models replace baseline models of
# their id in place (the last one wins) and the others are appended.
def mergesDynamicModelsOverTheBaseline() -> IO(Unit):
  same(modelIds(Models.mergeModels([testModel("p", "a"), testModel("p", "b")], [testModel("q", "c"), testModel("q", "a"), testModel("r", "c")])), "q/a,p/b,r/c", "createProvider merges dynamic models over the baseline")

def main() -> IO(Unit):
  do IO<Unit>:
    enumeratesCredentialMetadata()
    registersReplacesAndDeletesProviders()
    listsAndFindsModelsPerProvider()
    updatesEveryConfiguredDynamicProvider()
    restrictsRefreshWorkToSelectedProviders()
    letsProvidersChoosePersistentDeletionAndEphemeralPublication()
    persistsDynamicCatalogsAndRestoresThemWithoutNetworkAccess()
    passesEffectiveApiKeyCredentials()
    refreshesExpiredOAuthBeforeRefreshingModels()
    alwaysGivesProvidersAConcreteSignal()
    returnsAbortedStateWithoutReportingCancellation()
    rejectsLatePublicationFromASupersededProvider()
    passesCallerSignalsToProviderAuthCallbacks()
    resolvesAuthStoredCredentialOwnsTheProvider()
    checksProviderAuthWithoutRefreshingOAuth()
    runsProviderLoginAndLogout()
    storedCredentialWithoutHandlerBlocksAmbient()
    refreshesExpiredOAuthAndPersistsTheRotatedCredential()
    refreshesWithLessThanFiveMinutesRemaining()
    honorsLongerMinimumValidity()
    rejectsWithCodeOAuthWhenRefreshFails()
    serializesConcurrentOAuthRefreshes()
    validOAuthTokensResolveWithoutModify()
    wrapsCredentialStoreFailures()
    keepsTheUnderlyingReasonInOAuthRefreshErrors()
    wrapsApiKeyAuthFailures()
    appliesFilterModelsToAvailableModels()
    mergesDynamicModelsOverTheBaseline()
