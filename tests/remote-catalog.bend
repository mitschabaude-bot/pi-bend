import Base
import ../packages/coding-agent/src/core/remote-catalog-provider.bend as Remote
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/config.bend as Config
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/models-store.bend as Store
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/auth/helpers.bend as Helpers
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ./loopback-fetch.bend as Loop

# upstream packages/coding-agent/test/remote-catalog-provider.test.ts. The
# provider's https://pi.dev requests go through a logging fetch to
# tests/remote_catalog_check.py's server, whose first path segment names the
# case and serves that case's responses in order. refreshProvider publishes
# like upstream's helper: persist writes (or deletes) the store entry, and the
# published models become the provider's catalog. Args: <server base>
# <localGeneratedAt ms for the "newer" case>.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def model(+id: String) -> T.Model<T.JsonValue>:
  T.Model{id, id, T.OpenAICompletionsApi{}, "test-provider", "https://example.test/v1", False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def testProvider(+inner: Fetch.Fetch(Unit), local: Maybe<&2, F64>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Test", ["TEST_PROVIDER_KEY"])
    Remote.withRemoteCatalog(AiModels.Provider{"test-provider", "Test", "https://example.test/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, [model("static")], AiModels.ApiStreams{}, None{}}, Remote.RemoteCatalogTransport{inner, Loop.urlContext()}, "https://pi.dev", local)

# The provider's current catalog, as its getModels() would answer.
def Catalog() -> Data: Ref.Ref<List<&2, T.Model<T.JsonValue>>>

type Publisher is Data:
  Publisher{store: Store.ModelsStore, catalog: Catalog()}

def persisted(store: Store.ModelsStore, persist: AiModels.Persist) -> IO(Unit):
  match persist:
    case AiModels.KeepStored{}: IO.pure(Unit, Unit{})
    case AiModels.DeleteStored{}:
      do IO<Unit>:
        deleted : Store.StoreResult(Unit) <- Store.delete(store, "test-provider", None{})
        return Unit{}
    case AiModels.StoreEntry{entry}:
      do IO<Unit>:
        written : Store.StoreResult(Unit) <- Store.write(store, "test-provider", entry, None{})
        return Unit{}

def updated(catalog: Catalog(), models: Maybe<&2, List<&2, T.Model<T.JsonValue>>>) -> IO(Unit):
  match models:
    case Some{list}: Ref.write(List<&2, T.Model<T.JsonValue>>, catalog, list)
    case None{}: IO.pure(Unit, Unit{})

def publish(publisher: Publisher, publication: AiModels.ModelsPublication) -> IO(Bool):
  match publisher publication:
    case Publisher{store, catalog} AiModels.ModelsPublication{persist, models}:
      do IO<Bool>:
        persisted(store, persist)
        updated(catalog, models)
        return True{}

def refreshCallback(provider: AiModels.Provider) -> Maybe<&2, AiModels.RefreshModels()>:
  match provider:
    case AiModels.Provider{_, _, _, _, _, _, refresh}: refresh

def storedEntry(result: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)) -> Maybe<&2, Store.ModelsStoreEntry>:
  match result:
    case Done{entry}: entry
    case Fail{_}: None{}

def called(refresh: Maybe<&2, AiModels.RefreshModels()>, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match refresh:
    case Some{callback}: C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, callback, context)
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"no refresh"})

# upstream refreshProvider.
def refreshProvider(provider: AiModels.Provider, +store: Store.ModelsStore, +catalog: Catalog(), force: Bool) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "test-provider", None{})
    +publisher : C.Callback<AiModels.ModelsPublication, Bool> <- C.create(~Publisher, ~AiModels.ModelsPublication, ~Bool, ~publish, Publisher{store, catalog})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Result<&2, &2, String, Unit> <- called(refreshCallback(provider), AiModels.RefreshModelsContext{Some{Auth.ApiKeyCredential{None{}, None{}}}, storedEntry(stored), publisher, True{}, Some{force}, Abort.signal(Unit, controller)})
    Abort.dispose(Unit, controller)
    C.dispose(AiModels.ModelsPublication, Bool, publisher)
    return result

def ids(models: List<&2, T.Model<T.JsonValue>>) -> String:
  match models:
    case Nil{}: ""
    case model <> Nil{}: T.modelId(model)
    case model <> rest: T.modelId(model) ++ "," ++ ids(rest)

def catalogIds(catalog: Catalog()) -> IO(String):
  do IO<String>:
    models : List<&2, T.Model<T.JsonValue>> <- Ref.read(List<&2, T.Model<T.JsonValue>>, catalog)
    return ids(models)

def entryOf(+store: Store.ModelsStore) -> IO(Maybe<&2, Store.ModelsStoreEntry>):
  do IO<Maybe<&2, Store.ModelsStoreEntry>>:
    stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(store, "test-provider", None{})
    return storedEntry(stored)

def storedIds(entry: Maybe<&2, Store.ModelsStoreEntry>) -> String:
  match entry:
    case Some{Store.ModelsStoreEntry{models, _, _, _}}: ids(models)
    case None{}: "<none>"

def storedEtag(entry: Maybe<&2, Store.ModelsStoreEntry>) -> String:
  match entry:
    case Some{Store.ModelsStoreEntry{_, _, _, Some{etag}}}: etag
    case _: "<none>"

def storedChecked(entry: Maybe<&2, Store.ModelsStoreEntry>) -> F64:
  match entry:
    case Some{Store.ModelsStoreEntry{_, _, Some{checkedAt}, _}}: checkedAt
    case _: F.fromU32(0)

def storedModified(entry: Maybe<&2, Store.ModelsStoreEntry>) -> Maybe<&2, F64>:
  match entry:
    case Some{Store.ModelsStoreEntry{_, modified, _, _}}: modified
    case None{}: None{}

def fieldIn(fields: List<&2, String>, +name: String) -> Maybe<&2, String>:
  match fields:
    case Nil{}: None{}
    case +value <> rest: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(value, name ++ ": "), _ => Some{String.drop(value, Nat.add(String.length(name), 2n))}, _ => fieldIn(rest, name))(Unit{})

def field(+line: String, +name: String) -> Maybe<&2, String>: fieldIn(String.split(line, '\t'), name)

def nth(lines: List<&2, String>, index: Nat) -> String:
  match lines index:
    case Nil{} _: ""
    case line <> _ 0n: line
    case _ <> rest 1n+previous: nth(rest, previous)

def failedWith(result: Result<&2, &2, String, Unit>, +text: String) -> Bool:
  match result:
    case Fail{message}: String.contains(message, text)
    case Done{_}: False{}

def succeeded(result: Result<&2, &2, String, Unit>) -> Bool: Result.is_done(&2, &2, String, Unit, result)

type Harness is Data:
  Harness{provider: AiModels.Provider, store: Store.ModelsStore, catalog: Catalog(), fetch: Fetch.Fetch(Unit), log: Loop.Log()}

def harnessWith(provider: AiModels.Provider, pair: Fetch.Fetch(Unit) & Loop.Log()) -> IO(Harness):
  match pair:
    case (fetch, log):
      do IO<Harness>:
        store : Store.ModelsStore <- Store.inMemoryModelsStore()
        catalog : Catalog() <- Ref.new(List<&2, T.Model<T.JsonValue>>, [model("static")])
        return Harness{provider, store, catalog, fetch, log}

def built(pair: Fetch.Fetch(Unit) & Loop.Log(), local: Maybe<&2, F64>) -> IO(Harness):
  match pair:
    case (+fetch, log):
      do IO<Harness>:
        provider : AiModels.Provider <- testProvider(fetch, local)
        harnessWith(provider, (fetch, log))

def harness(+inner: Fetch.Fetch(Unit), +base: String, +route: String, local: Maybe<&2, F64>) -> IO(Harness):
  do IO<Harness>:
    pair : Fetch.Fetch(Unit) & Loop.Log() <- Loop.redirecting(inner, "https://pi.dev", base ++ "/" ++ route)
    providerFetch : Fetch.Fetch(Unit) & Loop.Log() <- IO.pure(Fetch.Fetch(Unit) & Loop.Log(), pair)
    built(providerFetch, local)

def refreshed(harness: Harness, force: Bool) -> IO(Result<&2, &2, String, Unit>):
  match harness:
    case Harness{provider, store, catalog, _, _}: refreshProvider(provider, store, catalog, force)

def catalogOf(harness: Harness) -> Catalog():
  match harness:
    case Harness{_, _, catalog, _, _}: catalog

def storeOf(harness: Harness) -> Store.ModelsStore:
  match harness:
    case Harness{_, store, _, _, _}: store

def logOf(harness: Harness) -> Loop.Log():
  match harness:
    case Harness{_, _, _, _, log}: log

def keyed(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "keyed", None{})
    first : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    second : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    third : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    models : String <- catalogIds(catalogOf(h))
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    +lines : List<&2, String> <- Loop.requests(logOf(h))
    check(succeeded(first) && succeeded(second) && succeeded(third) && String.eq(models, "static,dynamic") && String.eq(storedIds(entry), "dynamic") && Nat.is_eq(List.length(&2, String, lines), 2n) && Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, agent => String.contains(agent, "pi/" ++ Config.version()), field(nth(lines, 0n), "user-agent")), False{}), "remote catalog provider parses keyed catalogs, sends version headers, observes the refresh TTL, and supports forced refreshes")

def newer(+inner: Fetch.Fetch(Unit), +base: String, +local: F64) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "newer", Some{local})
    first : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    before : String <- catalogIds(catalogOf(h))
    second : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    after : String <- catalogIds(catalogOf(h))
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    check(String.eq(before, "static") && String.eq(after, "static,newer") && Maybe.default(&2, Bool, Maybe.map(&2, F64, Bool, modified => F64.is_eq(modified, F.add(local, F.fromU32(60000))), storedModified(entry)), False{}), "remote catalog provider prefers the newer of the generated and remote catalogs")

def sameText(value: Maybe<&2, String>, +expected: String) -> Bool:
  match value:
    case Some{text}: String.eq(text, expected)
    case None{}: False{}

def revalidates(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "etag", None{})
    first : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    +firstEntry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    second : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    models : String <- catalogIds(catalogOf(h))
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    +lines : List<&2, String> <- Loop.requests(logOf(h))
    check(Maybe.is_none(&2, String, field(nth(lines, 0n), "if-none-match")) && String.eq(storedEtag(firstEntry), "\"catalog-1\"") && sameText(field(nth(lines, 1n), "if-none-match"), "\"catalog-1\"") && String.eq(models, "static,dynamic") && String.eq(storedIds(entry), "dynamic") && String.eq(storedEtag(entry), "\"catalog-1\"") && F64.is_ge(storedChecked(entry), storedChecked(firstEntry)), "remote catalog provider revalidates a stored catalog with its etag and keeps the overlay on 304")

def dropsEtag(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "stale", None{})
    first : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    second : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    check(String.eq(storedEtag(entry), "<none>"), "remote catalog provider drops a stale etag when the overlay becomes unavailable")

def transient(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "transient", None{})
    first : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    failed : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    third : Result<&2, &2, String, Unit> <- refreshed(h, True{})
    +lines : List<&2, String> <- Loop.requests(logOf(h))
    models : String <- catalogIds(catalogOf(h))
    check(failedWith(failed, "429") && String.eq(storedEtag(entry), "\"catalog-1\"") && String.eq(storedIds(entry), "dynamic") && sameText(field(nth(lines, 4n), "if-none-match"), "\"catalog-1\"") && String.eq(models, "static,dynamic"), "remote catalog provider keeps the etag and overlay after a transient failure")

def unavailable(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    +h : Harness <- harness(inner, base, "unimplemented", None{})
    result : Result<&2, &2, String, Unit> <- refreshed(h, False{})
    models : String <- catalogIds(catalogOf(h))
    +entry : Maybe<&2, Store.ModelsStoreEntry> <- entryOf(storeOf(h))
    check(succeeded(result) && String.eq(models, "static") && String.eq(storedIds(entry), "") && F64.is_gt(storedChecked(entry), F.fromU32(0)), "remote catalog provider treats unimplemented pi.dev catalog routes as an unavailable overlay")

# "lets a newer catalog request bypass a stalled older request without stale
# publication": two concurrent forced refreshes through the model runtime; the
# server holds the first request's answer until it has answered the second.
def waitForRequest(fuel: Nat, +log: Loop.Log()) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        lines : List<&2, String> <- Loop.requests(log)
        Bool.pick(Unit -> IO(Unit), List.is_empty(&2, String, lines), _ => do IO<Unit>:
          IO.sleep(10)
          waitForRequest(rest, log), _ => IO.pure(Unit, Unit{}))(Unit{})

def forcedRefresh() -> Models.ModelsRefreshOptions: Models.ModelsRefreshOptions{Some{True{}}, Some{["test-provider"]}, Some{True{}}, None{}}

def runtimeIds(+runtime: Models.ModelRuntime) -> IO(String):
  do IO<String>:
    models : List<&2, T.Model<T.JsonValue>> <- Models.getModels(runtime)
    return ids(AiModels.ownedBy(models, "test-provider"))

def stalledWith(+runtime: Models.ModelRuntime, +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    first : Chan(Models.ModelsRefreshResult) <- IO.fork(Models.ModelsRefreshResult, Models.refresh(runtime, forcedRefresh()))
    waitForRequest(500n, log)
    second : Models.ModelsRefreshResult <- Models.refresh(runtime, forcedRefresh())
    afterSecond : String <- runtimeIds(runtime)
    finished : Models.ModelsRefreshResult <- IO.join(Models.ModelsRefreshResult, first)
    afterFirst : String <- runtimeIds(runtime)
    stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(Models.storeOf(runtime), "test-provider", None{})
    check(String.eq(afterSecond, "static,newer") && String.eq(afterFirst, "static,newer") && String.eq(storedIds(storedEntry(stored)), "newer"), "remote catalog provider lets a newer catalog request bypass a stalled older request without stale publication")

def credentialStore(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

def stalledPair(pair: Fetch.Fetch(Unit) & Loop.Log()) -> IO(Unit):
  match pair:
    case (+fetch, +log):
      do IO<Unit>:
        provider : AiModels.Provider <- testProvider(fetch, None{})
        store : Store.ModelsStore <- Store.inMemoryModelsStore()
        owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(R.new(Auth.Credential))
        credentials : Auth.CredentialStore <- credentialStore(AuthStorage.borrow(owner))
        context : Auth.AuthContext <- Context.defaultProviderAuthContext()
        +runtime : Models.ModelRuntime <- Models.fromProvidersWithStore([provider], credentials, context, store)
        stalledWith(runtime, log)

def stalled(+inner: Fetch.Fetch(Unit), +base: String) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Fetch(Unit) & Loop.Log() <- Loop.redirecting(inner, "https://pi.dev", base ++ "/stall")
    stalledPair(pair)

def cases(+base: String, +local: F64, +inner: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    keyed(inner, base)
    newer(inner, base, local)
    revalidates(inner, base)
    dropsEtag(inner, base)
    transient(inner, base)
    unavailable(inner, base)
    stalled(inner, base)

def started(args: List<String>) -> IO(Unit):
  match args:
    case base <> localText <> Nil{}: Loop.withNetwork(inner => cases(base, F.multiply(F.fromU32(Maybe.default(&2, U32, U32.read(localText), 0)), F.fromU32(1000)), inner))
    case _: IO.die(Unit, 2, "usage: remote-catalog <server base> <local generated seconds>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
