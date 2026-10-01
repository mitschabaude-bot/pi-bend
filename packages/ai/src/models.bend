import Base
import ./types.bend as T
import ./utils/model-api.bend as Api
import ./utils/thinking-levels.bend as Thinking
import ./utils/cost.bend as Cost
import ../../runtime/src/utf16.bend as U
import ./auth/types.bend as Auth
import ./providers/cloudflare-stream.bend as Cloudflare
import ./providers/opencode-headers.bend as OpenCode
import ./models-store.bend as Store
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/f64.bend as F
import ./auth/resolve.bend as Resolve
import ./auth/context.bend as Context
import ./auth/credential-store.bend as Credentials

# upstream Provider.api, reduced to what differs between providers: requests
# stream through the shared implementation of the model's api, the
# Cloudflare providers first materialize endpoint placeholders for the APIs
# they wrap (upstream cloudflareStreams), and the OpenCode providers add the
# session routing header for theirs (upstream withOpenCodeSessionHeader).
type ProviderStreams is Data:
  ApiStreams{}
  CloudflareStreams{apis: List<&2, T.ModelApi>}
  OpenCodeStreams{apis: List<&2, T.ModelApi>}

# Dynamic catalogs (upstream RefreshModelsContext and ModelsPublication)
# -------------------------------------------------------------------------

def Model() -> Data: T.Model<T.JsonValue>

# upstream `persist`: omitted leaves storage unchanged, null deletes it.
type Persist is Data:
  KeepStored{}
  DeleteStored{}
  StoreEntry{entry: Store.ModelsStoreEntry}

# upstream ModelsPublication. `update` is a closure that replaces the
# provider's private catalog; here it is the value of that catalog: the list
# the provider's getModels() returns once the publication is accepted.
type ModelsPublication is Data:
  ModelsPublication{persist: Persist, models: Maybe<&2, List<&2, Model()>>}

# upstream RefreshModelsContext. `publish` answers False when the refresh was
# superseded or aborted; the provider then stops.
type RefreshModelsContext is Data:
  RefreshModelsContext{credential: Maybe<&2, Auth.Credential>, stored: Maybe<&2, Store.ModelsStoreEntry>, publish: C.Callback<ModelsPublication, Bool>, allowNetwork: Bool, force: Maybe<&2, Bool>, signal: Abort.AbortSignal<Unit>}

# Failures are the message of upstream's rejected promise.
def RefreshModels() -> Data: C.Callback<RefreshModelsContext, Result<&2, &2, String, Unit>>

# upstream Provider.filterModels: the models of the complete catalog that a
# credential may use (Models.getAvailable applies it once the provider's auth
# is configured).
type FilterModelsInput is Data:
  FilterModelsInput{models: List<&2, Model()>, credential: Maybe<&2, Auth.Credential>}

def FilterModels() -> Data: C.Callback<FilterModelsInput, List<&2, Model()>>

# A model provider (upstream Provider): providers/<id>.bend construct the
# built-in ones and providers/all.bend lists them. Upstream's optional baseUrl
# is "" when absent. `models` is the catalog getModels() returns before any
# refresh; a Models collection keeps the catalogs a dynamic provider
# publishes. Not carried: headers (no built-in provider sets them).
type Provider is Data:
  Provider{id: String, name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, Model()>, streams: ProviderStreams, refreshModels: Maybe<&2, RefreshModels()>, filterModels: Maybe<&2, FilterModels()>}

def providerId(provider: Provider) -> String:
  match provider:
    case Provider{id, _, _, _, _, _, _, _}: id

def providerName(provider: Provider) -> String:
  match provider:
    case Provider{_, name, _, _, _, _, _, _}: name

def providerAuth(provider: Provider) -> Auth.ProviderAuth:
  match provider:
    case Provider{_, _, _, auth, _, _, _, _}: auth

def providerModels(provider: Provider) -> List<&2, Model()>:
  match provider:
    case Provider{_, _, _, _, models, _, _, _}: models

def providerStreams(provider: Provider) -> ProviderStreams:
  match provider:
    case Provider{_, _, _, _, _, streams, _, _}: streams

def providerRefresh(provider: Provider) -> Maybe<&2, RefreshModels()>:
  match provider:
    case Provider{_, _, _, _, _, _, refresher, _}: refresher

def providerFilter(provider: Provider) -> Maybe<&2, FilterModels()>:
  match provider:
    case Provider{_, _, _, _, _, _, _, filter}: filter

# The provider with `models` as its current catalog.
def withModels(provider: Provider, models: List<&2, Model()>) -> Provider:
  match provider:
    case Provider{id, name, url, auth, _, streams, refresher, filter}: Provider{id, name, url, auth, models, streams, refresher, filter}

# upstream provider.filterModels?.(models, credential) ?? models
def filterModels(provider: Provider, models: List<&2, Model()>, credential: Maybe<&2, Auth.Credential>) -> IO(List<&2, Model()>):
  match provider:
    case Provider{_, _, _, _, _, _, _, None{}}: IO.pure(List<&2, Model()>, models)
    case Provider{_, _, _, _, _, _, _, Some{filter}}: C.call(FilterModelsInput, List<&2, Model()>, filter, FilterModelsInput{models, credential})

def wraps(apis: List<&2, T.ModelApi>, +api: String) -> Bool:
  match apis:
    case Nil{}: False{}
    case wrapped <> rest: U.equal(Api.name(wrapped), api) || wraps(rest, api)

def streamedWith(-SamplingValue: Data, wrapped: Bool, model: T.Model<SamplingValue>, env: Maybe<&2, T.ProviderEnv()>) -> T.Model<SamplingValue>:
  match wrapped:
    case True{}: Cloudflare.resolveCloudflareModel(SamplingValue, model, env)
    case False{}: model

# The model a provider's stream dispatches for a request with the resolved
# provider env.
def streamModel(-SamplingValue: Data, streams: ProviderStreams, +model: T.Model<SamplingValue>, env: Maybe<&2, T.ProviderEnv()>) -> T.Model<SamplingValue>:
  match streams:
    case CloudflareStreams{apis}: streamedWith(SamplingValue, wraps(apis, Api.name(Api.modelApi(SamplingValue, model))), model, env)
    case _: model

def optionsWith(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, wrapped: Bool, options: T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match wrapped:
    case True{}: OpenCode.withSimpleSessionHeader(Value, Signal, Telemetry, Fetch, Error, options)
    case False{}: options

# The options a provider's streamSimple dispatches the model's api with.
def streamSimpleOptions(-SamplingValue: Data, -Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, streams: ProviderStreams, model: T.Model<SamplingValue>, options: T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match streams:
    case OpenCodeStreams{apis}: optionsWith(Value, Signal, Telemetry, Fetch, Error, wraps(apis, Api.name(Api.modelApi(SamplingValue, model))), options)
    case _: options

# Raw requests use the same provider session affinity without converting
# their API-specific options through streamSimple.
def streamOptions(-SamplingValue: Data, -Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, streams: ProviderStreams, model: T.Model<SamplingValue>, +options: T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match streams:
    case OpenCodeStreams{apis}: Bool.pick(T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>, wraps(apis, Api.name(Api.modelApi(SamplingValue, model))), OpenCode.withSessionHeader(Value, Signal, Telemetry, Fetch, Error, options), options)
    case _: options

def usedBy(models: List<&2, T.Model<T.JsonValue>>, +api: String) -> Bool:
  match models:
    case Nil{}: False{}
    case model <> rest: U.equal(Api.name(Api.modelApi(T.JsonValue, model)), api) || usedBy(rest, api)

def usedApis(apis: List<&2, T.ModelApi>, +models: List<&2, T.Model<T.JsonValue>>) -> List<&2, T.ModelApi>:
  match apis:
    case Nil{}: Nil{}
    case +api <> rest:
      +tail = usedApis(rest, models)
      Bool.pick(List<&2, T.ModelApi>, usedBy(models, Api.name(api)), api <> tail, tail)

# upstream composeProvider: a models.json overlay streams through its base
# provider only for APIs the base provider's models use.
def inheritedStreams(base: Maybe<&2, Provider>) -> ProviderStreams:
  match base:
    case None{}: ApiStreams{}
    case Some{Provider{_, _, _, _, _, ApiStreams{}, _, _}}: ApiStreams{}
    case Some{Provider{_, _, _, _, models, CloudflareStreams{apis}, _, _}}: CloudflareStreams{usedApis(apis, models)}
    case Some{Provider{_, _, _, _, models, OpenCodeStreams{apis}, _, _}}: OpenCodeStreams{usedApis(apis, models)}

# Leaf utilities from models.ts. upstream hasApi is a type guard; here it is
# the predicate alone.
def hasApi(-SamplingValue: Data, model: T.Model<SamplingValue>, api: String) -> Bool:
  U.equal(Api.name(Api.modelApi(SamplingValue, model)), api)

def getSupportedThinkingLevels(-SamplingValue: Data, model: T.Model<SamplingValue>) -> List<&2, T.ModelThinkingLevel>:
  match model:
    case T.Model{_, _, _, _, _, reasoning, mapping, _, _, _, _, _, _, _, _, _}: Thinking.available(reasoning, mapping)

def clampThinkingLevel(-SamplingValue: Data, model: T.Model<SamplingValue>, level: T.ModelThinkingLevel) -> T.ModelThinkingLevel:
  Thinking.closest(getSupportedThinkingLevels(SamplingValue, model), Thinking.rank(level), T.Off{})

def modelsAreEqual(-SamplingValue: Data, a: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>, b: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>) -> Bool:
  match a b:
    case Some{T.PresentValue{T.Model{idA, _, _, providerA, _, _, _, _, _, _, _, _, _, _, _, _}}} Some{T.PresentValue{T.Model{idB, _, _, providerB, _, _, _, _, _, _, _, _, _, _, _, _}}}: U.equal(idA, idB) && U.equal(providerA, providerB)
    case _ _: False{}

def calculateCost(-SamplingValue: Data, model: T.Model<SamplingValue>, usage: T.Usage) -> T.UsageCost:
  Cost.calculate(SamplingValue, model, usage)

# createProvider with fetchModels
# -------------------------------

def lastWithId(models: List<&2, Model()>, +id: String, found: Maybe<&2, Model()>) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: found
    case +model <> rest: lastWithId(rest, id, Bool.pick(Maybe<&2, Model()>, U.equal(T.modelId(model), id), Some{model}, found))

def hasId(models: List<&2, Model()>, +id: String) -> Bool:
  match models:
    case Nil{}: False{}
    case model <> rest: U.equal(T.modelId(model), id) || hasId(rest, id)

def containsText(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case first <> rest: U.equal(first, value) || containsText(rest, value)

def replacedBaseline(baseline: List<&2, Model()>, +dynamic: List<&2, Model()>) -> List<&2, Model()>:
  match baseline:
    case Nil{}: Nil{}
    case +model <> rest: Maybe.default(&2, Model(), lastWithId(dynamic, T.modelId(model), None{}), model) <> replacedBaseline(rest, dynamic)

def appended(pending: List<&2, Model()>, +dynamic: List<&2, Model()>, +baseline: List<&2, Model()>, +seen: List<&2, String>) -> List<&2, Model()>:
  match pending:
    case Nil{}: Nil{}
    case +model <> rest:
      +id = T.modelId(model)
      +skip = hasId(baseline, id) || containsText(seen, id)
      +tail = appended(rest, dynamic, baseline, Bool.pick(List<&2, String>, skip, seen, id <> seen))
      Bool.pick(List<&2, Model()>, skip, tail, Maybe.default(&2, Model(), lastWithId(dynamic, id, None{}), model) <> tail)

# upstream createProvider's getModels: each dynamic model replaces the model
# of the same id in place (the last one wins), others are appended.
def mergeModels(+baseline: List<&2, Model()>, +dynamic: List<&2, Model()>) -> List<&2, Model()>:
  List.append(&2, Model(), replacedBaseline(baseline, dynamic), appended(dynamic, dynamic, baseline, Nil{}))

def ownedBy(models: List<&2, Model()>, +provider: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = ownedBy(rest, provider)
      Bool.pick(List<&2, Model()>, U.equal(T.modelProvider(model), provider), model <> tail, tail)

def FetchModels() -> Data: C.Callback<RefreshModelsContext, Result<&2, &2, String, List<&2, Model()>>>

type Fetched is Data:
  Fetched{id: String, baseline: List<&2, Model()>, fetch: FetchModels()}

def published(context: RefreshModelsContext, publication: ModelsPublication) -> IO(Bool):
  match context:
    case RefreshModelsContext{_, _, publish, _, _, _}: C.call(ModelsPublication, Bool, publish, publication)

def signalOf(context: RefreshModelsContext) -> Abort.AbortSignal<Unit>:
  match context:
    case RefreshModelsContext{_, _, _, _, _, signal}: signal

def networkAllowed(context: RefreshModelsContext) -> Bool:
  match context:
    case RefreshModelsContext{_, _, _, allowNetwork, _, _}: allowNetwork

def publishFetched(+context: RefreshModelsContext, baseline: List<&2, Model()>, +refreshed: List<&2, Model()>, aborted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match aborted:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{}:
      do IO<Result<&2, &2, String, Unit>>:
        now : F64 <- Date.now()
        accepted : Bool <- published(context, ModelsPublication{StoreEntry{Store.ModelsStoreEntry{refreshed, None{}, Some{now}, None{}}}, Some{mergeModels(baseline, refreshed)}})
        return Done{Unit{}}

def fetchedResult(+context: RefreshModelsContext, baseline: List<&2, Model()>, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{refreshed}:
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, signalOf(context))
        publishFetched(context, baseline, refreshed, aborted)

def fetchUnlessOffline(+context: RefreshModelsContext, baseline: List<&2, Model()>, fetch: FetchModels(), offline: Bool) -> IO(Result<&2, &2, String, Unit>):
  match offline:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, List<&2, Model()>> <- C.call(RefreshModelsContext, Result<&2, &2, String, List<&2, Model()>>, fetch, context)
        fetchedResult(context, baseline, result)

def fetchAfterRestore(+context: RefreshModelsContext, baseline: List<&2, Model()>, fetch: FetchModels(), restored: Bool) -> IO(Result<&2, &2, String, Unit>):
  match restored:
    case False{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case True{}:
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, signalOf(context))
        fetchUnlessOffline(context, baseline, fetch, Bool.not(networkAllowed(context)) || aborted)

def restoreStored(+context: RefreshModelsContext, +id: String, +baseline: List<&2, Model()>) -> IO(Bool):
  match context:
    case RefreshModelsContext{_, None{}, _, _, _, _}: IO.pure(Bool, True{})
    case RefreshModelsContext{_, Some{Store.ModelsStoreEntry{models, _, _, _}}, _, _, _, _}: published(context, ModelsPublication{KeepStored{}, Some{mergeModels(baseline, ownedBy(models, id))}})

# upstream createProvider's refreshModels: restore the stored overlay, then,
# when the network is allowed, fetch a new one and persist it.
def refreshWith(source: Fetched, +context: RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match source:
    case Fetched{+id, +baseline, fetch}:
      do IO<Result<&2, &2, String, Unit>>:
        +restored : Bool <- restoreStored(context, id, baseline)
        fetchAfterRestore(context, baseline, fetch, restored)

def refreshFetched(source: Fetched, context: RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>): refreshWith(source, context)

# The refresh owns `fetch`; disposing the refresh callback does not dispose it.
def fetchedRefresh(id: String, baseline: List<&2, Model()>, fetch: FetchModels()) -> IO(RefreshModels()):
  C.create(~Fetched, ~RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshFetched, Fetched{id, baseline, fetch})

# Models collection (upstream Models, MutableModels and createModels)
# -------------------------------------------------------------------
#
# The runtime collection of providers with auth application. Providers are
# kept in registration order (setProvider replaces a provider in place, as
# Map.set does). Upstream providers hold the catalog they published in their
# own closures; here the collection keeps each provider's published catalog,
# which belongs to the provider registered under that id: replacing or
# deleting the provider drops it and supersedes the provider's refreshes.
# Refreshes run one provider at a time; a superseded refresh keeps running
# but can no longer publish. Request dispatch (upstream stream/streamSimple
# and the deferred calls) stays with the application's stream functions,
# which apply getAuth themselves (coding-agent agent-runtime).

type ModelsState is Data:
  ModelsState{providers: List<&2, Provider>, published: R.Record<List<&2, Model()>>, generations: R.Record<Nat>}

# `ownsCredentials`: the store was created by createModels (the default
# InMemoryCredentialStore) and is released with the collection; an injected
# credential store stays with its owner. The models store and auth context
# are owned by the collection.
type Models is Data:
  Models{state: Ref.Ref<ModelsState>, credentials: Auth.CredentialStore, modelsStore: Store.ModelsStore, authContext: Auth.AuthContext, ownsCredentials: Bool}

type CreateModelsOptions is Data:
  CreateModelsOptions{credentials: Maybe<&2, Auth.CredentialStore>, modelsStore: Maybe<&2, Store.ModelsStore>, authContext: Maybe<&2, Auth.AuthContext>}

def createModelsOptions() -> CreateModelsOptions: CreateModelsOptions{None{}, None{}, None{}}

def credentialsOr(given: Maybe<&2, Auth.CredentialStore>) -> IO(Auth.CredentialStore):
  match given:
    case Some{store}: IO.pure(Auth.CredentialStore, store)
    case None{}: Credentials.inMemoryCredentialStore()

def modelsStoreOr(given: Maybe<&2, Store.ModelsStore>) -> IO(Store.ModelsStore):
  match given:
    case Some{store}: IO.pure(Store.ModelsStore, store)
    case None{}: Store.inMemoryModelsStore()

def authContextOr(given: Maybe<&2, Auth.AuthContext>) -> IO(Auth.AuthContext):
  match given:
    case Some{context}: IO.pure(Auth.AuthContext, context)
    case None{}: Context.defaultProviderAuthContext()

def emptyModelsState() -> ModelsState: ModelsState{Nil{}, R.new(List<&2, Model()>), R.new(Nat)}

# upstream createModels: an in-memory credential store, an in-memory models
# store and the process auth context unless given.
def createModels(options: CreateModelsOptions) -> IO(Models):
  match options:
    case CreateModelsOptions{+credentials, store, context}:
      do IO<Models>:
        chosen : Auth.CredentialStore <- credentialsOr(credentials)
        catalogs : Store.ModelsStore <- modelsStoreOr(store)
        environment : Auth.AuthContext <- authContextOr(context)
        state : Ref.Ref<ModelsState> <- Ref.new(ModelsState, emptyModelsState())
        return Models{state, chosen, catalogs, environment, Bool.not(Maybe.is_some(&2, Auth.CredentialStore, credentials))}

def credentialsOf(+models: Models) -> Auth.CredentialStore:
  match models:
    case Models{_, credentials, _, _, _}: credentials

def modelsStoreOf(+models: Models) -> Store.ModelsStore:
  match models:
    case Models{_, _, store, _, _}: store

def authContextOf(+models: Models) -> Auth.AuthContext:
  match models:
    case Models{_, _, _, context, _}: context

def stateOf(+models: Models) -> Ref.Ref<ModelsState>:
  match models:
    case Models{state, _, _, _, _}: state

def disposeOwnedCredentials(owned: Bool, credentials: Auth.CredentialStore) -> IO(Unit):
  match owned:
    case True{}: Auth.disposeStore(credentials)
    case False{}: IO.pure(Unit, Unit{})

# Releases the collection's state, models store and auth context (and the
# default credential store). Providers stay with whoever created them.
def disposeModels(models: Models) -> IO(Unit):
  match models:
    case Models{state, credentials, store, context, owned}:
      do IO<Unit>:
        old : ModelsState <- Ref.dispose(ModelsState, state)
        Store.dispose(store)
        Auth.disposeContext(context)
        disposeOwnedCredentials(owned, credentials)

def disposeFilter(filter: Maybe<&2, FilterModels()>) -> IO(Unit):
  match filter:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.dispose(FilterModelsInput, List<&2, Model()>, callback)


# Releases a provider's auth callbacks and model filter.
def disposeProvider(provider: Provider) -> IO(Unit):
  match provider:
    case Provider{_, _, _, auth, _, _, _, filter}:
      do IO<Unit>:
        Auth.disposeProviderAuth(auth)
        disposeFilter(filter)

# Registration (setProvider/deleteProvider/clearProviders)
# ---------------------------------------------------------

def findProvider(providers: List<&2, Provider>, +id: String) -> Maybe<&2, Provider>:
  match providers:
    case Nil{}: None{}
    case +provider <> rest: Bool.pick(Unit -> Maybe<&2, Provider>, U.equal(providerId(provider), id), _ => Some{provider}, _ => findProvider(rest, id))(Unit{})

def providerIds(providers: List<&2, Provider>) -> List<&2, String>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: providerId(provider) <> providerIds(rest)

def replacedProvider(providers: List<&2, Provider>, +provider: Provider) -> List<&2, Provider>:
  match providers:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(Provider, U.equal(providerId(current), providerId(provider)), provider, current) <> replacedProvider(rest, provider)

# Upsert by id: a known id keeps its position, a new one is appended.
def upserted(+providers: List<&2, Provider>, +provider: Provider) -> List<&2, Provider>:
  Bool.pick(List<&2, Provider>, containsText(providerIds(providers), providerId(provider)), replacedProvider(providers, provider), List.append(&2, Provider, providers, [provider]))

def withoutProvider(providers: List<&2, Provider>, +id: String) -> List<&2, Provider>:
  match providers:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = withoutProvider(rest, id)
      Bool.pick(List<&2, Provider>, U.equal(providerId(provider), id), tail, provider <> tail)

def nextGeneration(generations: R.Record<Nat>, id: String) -> Nat:
  Nat.add(Maybe.default(&2, Nat, R.get(Nat, generations, id), 0n), 1n)

# upstream supersedeProviderRefresh: refreshes of the provider registered
# under the id can no longer publish, and its published catalog goes with it.
def superseded(+id: String, state: ModelsState) -> ModelsState:
  match state:
    case ModelsState{providers, published, +generations}:
      ModelsState{providers, R.remove(List<&2, Model()>, published, id), R.set(Nat, generations, id, nextGeneration(generations, id))}

def supersededAll(ids: List<&2, String>, state: ModelsState) -> ModelsState:
  match ids:
    case Nil{}: state
    case +id <> rest: supersededAll(rest, superseded(id, state))

def withProviders(state: ModelsState, update: List<&2, Provider> -> List<&2, Provider>) -> ModelsState:
  match state:
    case ModelsState{providers, published, generations}: ModelsState{update(providers), published, generations}

def keysOf(entries: List<&2, R.Property<Nat>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: key <> keysOf(rest)

def generationIds(state: ModelsState) -> List<&2, String>:
  match state:
    case ModelsState{_, _, generations}: keysOf(R.entries(Nat, generations))

def stateProviders(state: ModelsState) -> List<&2, Provider>:
  match state:
    case ModelsState{providers, _, _}: providers

def setProvider(+models: Models, +provider: Provider) -> IO(Unit):
  Ref.modify(ModelsState, Unit, stateOf(models), state => (withProviders(superseded(providerId(provider), state), providers => upserted(providers, provider)), Unit{}))

def deleteProvider(+models: Models, +id: String) -> IO(Unit):
  Ref.modify(ModelsState, Unit, stateOf(models), state => (withProviders(superseded(id, state), providers => withoutProvider(providers, id)), Unit{}))

def cleared(+state: ModelsState) -> ModelsState:
  withProviders(supersededAll(List.append(&2, String, providerIds(stateProviders(state)), generationIds(state)), state), providers => Nil{})

def clearProviders(+models: Models) -> IO(Unit):
  Ref.modify(ModelsState, Unit, stateOf(models), state => (cleared(state), Unit{}))

def bumped(ids: List<&2, String>, +generations: R.Record<Nat>) -> R.Record<Nat>:
  match ids:
    case Nil{}: generations
    case +id <> rest: bumped(rest, R.set(Nat, generations, id, nextGeneration(generations, id)))

def withoutPublished(ids: List<&2, String>, published: R.Record<List<&2, Model()>>) -> R.Record<List<&2, Model()>>:
  match ids:
    case Nil{}: published
    case +id <> rest: withoutPublished(rest, R.remove(List<&2, Model()>, published, id))

def rebuilt(+providers: List<&2, Provider>, changed: List<&2, String>, state: ModelsState) -> ModelsState:
  match state:
    case ModelsState{old, published, +generations}: ModelsState{providers, withoutPublished(changed, published), bumped(List.concat(&2, String, [providerIds(old), providerIds(providers), keysOf(R.entries(Nat, generations))]), generations)}

# upstream rebuildProviders' effect on the collection (clearProviders, then
# setProvider for each provider in order): every refresh in flight is
# superseded. Upstream providers keep the catalogs they published across
# re-registration; here the collection keeps them by id, so the caller names
# the ids whose provider was replaced or removed (`changed`), and only those
# lose theirs.
def rebuildProviders(+models: Models, +providers: List<&2, Provider>, changed: List<&2, String>) -> IO(Unit):
  Ref.modify(ModelsState, Unit, stateOf(models), state => (rebuilt(providers, changed, state), Unit{}))

# Catalog reads
# -------------

# A provider as upstream's getModels() sees it: its published catalog, if any.
def current(+published: R.Record<List<&2, Model()>>, +provider: Provider) -> Provider:
  Maybe.default(&2, Provider, Maybe.map(&2, List<&2, Model()>, Provider, models => withModels(provider, models), R.get(List<&2, Model()>, published, providerId(provider))), provider)

def currentAll(providers: List<&2, Provider>, +published: R.Record<List<&2, Model()>>) -> List<&2, Provider>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: current(published, provider) <> currentAll(rest, published)

def currentProviders(state: ModelsState) -> List<&2, Provider>:
  match state:
    case ModelsState{providers, published, _}: currentAll(providers, published)

def getProviders(+models: Models) -> IO(List<&2, Provider>):
  do IO<List<&2, Provider>>:
    state : ModelsState <- Ref.read(ModelsState, stateOf(models))
    return currentProviders(state)

def getProvider(+models: Models, +id: String) -> IO(Maybe<&2, Provider>):
  do IO<Maybe<&2, Provider>>:
    providers : List<&2, Provider> <- getProviders(models)
    return findProvider(providers, id)

def allModels(providers: List<&2, Provider>) -> List<&2, Model()>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: List.append(&2, Model(), providerModels(provider), allModels(rest))

def selectedModels(provider: Maybe<&2, Provider>) -> List<&2, Model()>:
  match provider:
    case None{}: Nil{}
    case Some{found}: providerModels(found)

def modelsOf(+providers: List<&2, Provider>, provider: Maybe<&2, String>) -> List<&2, Model()>:
  match provider:
    case None{}: allModels(providers)
    case Some{id}: selectedModels(findProvider(providers, id))

# upstream getModels(provider?): the last-known models of one provider (none
# for an unknown id) or of all providers in registration order.
def getModels(+models: Models, provider: Maybe<&2, String>) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    providers : List<&2, Provider> <- getProviders(models)
    return modelsOf(providers, provider)

def modelWithId(models: List<&2, Model()>, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Unit -> Maybe<&2, Model()>, U.equal(T.modelId(model), id), _ => Some{model}, _ => modelWithId(rest, id))(Unit{})

def getModel(+models: Models, provider: String, +id: String) -> IO(Maybe<&2, Model()>):
  do IO<Maybe<&2, Model()>>:
    found : List<&2, Model()> <- getModels(models, Some{provider})
    return modelWithId(found, id)

# Signals
# -------

# upstream operationSignal: operations always run under a concrete signal.
def signalled(-A: Data, signal: Auth.Signal(), run: Abort.AbortSignal<Unit> -> IO(A)) -> IO(A):
  match signal:
    case Some{given}: run(given)
    case None{}:
      do IO<A>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : A <- run(Abort.signal(Unit, controller))
        Abort.dispose(Unit, controller)
        return result

def abortedError() -> Resolve.ModelsError: Resolve.ModelsError{Resolve.AuthError{}, "This operation was aborted"}

# Auth
# ----

def providerRef(provider: Provider) -> Resolve.ProviderRef:
  match provider:
    case Provider{id, _, _, auth, _, _, _, _}: Resolve.ProviderRef{id, auth}

def readFailure(+id: String, cause: String) -> Resolve.ModelsError:
  Resolve.failure(Resolve.AuthError{}, "Credential store read failed for " ++ id, cause)

def readOutcome(+id: String, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>>:
  match stored:
    case Fail{cause}: Fail{readFailure(id, cause)}
    case Done{credential}: Done{credential}


# upstream readCredential: a store failure is a ModelsError with code "auth".
def readCredential(+models: Models, +id: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>>):
  do IO<Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>>>:
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(models), id, Some{signal})
    return readOutcome(id, stored)

def apiKeyCredential(stored: Maybe<&2, Auth.Credential>) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Some{Auth.ApiKeyCredential{key, env}}: Some{Auth.ApiKeyCredential{key, env}}
    case _: None{}

def CheckResult() -> Data: Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.AuthCheck>>

def checkOf(resolution: Resolve.Resolution()) -> CheckResult():
  match resolution:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{None{}}
    case Done{Some{Auth.AuthResult{_, _, source}}}: Done{Some{Auth.AuthCheck{source, Auth.ApiKeyType{}}}}

def checkedByProvider(+id: String, outcome: Auth.CheckOutcome()) -> CheckResult():
  match outcome:
    case Fail{cause}: Fail{Resolve.failure(Resolve.AuthError{}, "API key auth check failed for provider " ++ id, cause)}
    case Done{check}: Done{check}

def hasOAuth(auth: Auth.ProviderAuth) -> Bool:
  match auth:
    case Auth.ProviderAuth{_, Some{_}}: True{}
    case _: False{}

# upstream checkProviderAuth: a stored OAuth credential counts when the
# provider supports OAuth, without refreshing it; otherwise the provider's
# API-key check decides, or resolving its auth does.
def checkWithAuth(+models: Models, +provider: Provider, auth: Auth.ProviderAuth, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(CheckResult()):
  match credential auth:
    case Some{Auth.OAuthCredential{_, _, _, _}} auth: IO.pure(CheckResult(), Done{Bool.pick(Maybe<&2, Auth.AuthCheck>, hasOAuth(auth), Some{Auth.AuthCheck{Some{"OAuth"}, Auth.OAuthType{}}}, None{})})
    case _ Auth.ProviderAuth{None{}, _}: IO.pure(CheckResult(), Done{None{}})
    case credential Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, _, _, Some{check}}}, _}:
      do IO<CheckResult()>:
        outcome : Auth.CheckOutcome() <- C.call(Auth.ResolveInput, Auth.CheckOutcome(), check, Auth.ResolveInput{authContextOf(models), apiKeyCredential(credential), signal})
        return checkedByProvider(providerId(provider), outcome)
    case _ Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, _, _, None{}}}, _}:
      do IO<CheckResult()>:
        resolution : Resolve.Resolution() <- Resolve.resolveProviderAuth(providerRef(provider), credentialsOf(models), authContextOf(models), Resolve.AuthResolutionOverrides{None{}, None{}, None{}, Some{signal}})
        return checkOf(resolution)


def checkProviderAuth(+models: Models, +provider: Provider, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(CheckResult()):
  checkWithAuth(models, provider, providerAuth(provider), credential, signal)

def checkRead(+models: Models, +provider: Provider, signal: Abort.AbortSignal<Unit>, stored: Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>>) -> IO(CheckResult()):
  match stored:
    case Fail{error}: IO.pure(CheckResult(), Fail{error})
    case Done{credential}: checkProviderAuth(models, provider, credential, signal)

def checkKnown(+models: Models, provider: Maybe<&2, Provider>, +signal: Abort.AbortSignal<Unit>) -> IO(CheckResult()):
  match provider:
    case None{}: IO.pure(CheckResult(), Done{None{}})
    case Some{+found}:
      do IO<CheckResult()>:
        stored : Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>> <- readCredential(models, providerId(found), signal)
        checkRead(models, found, signal, stored)

def checkSignalled(+models: Models, +id: String, +signal: Abort.AbortSignal<Unit>) -> IO(CheckResult()):
  do IO<CheckResult()>:
    stopped : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(CheckResult()), stopped, _ => IO.pure(CheckResult(), Fail{abortedError()}), _ => do IO<CheckResult()>:
      provider : Maybe<&2, Provider> <- getProvider(models, id)
      checkKnown(models, provider, signal))(Unit{})

# upstream checkAuth: whether the provider has complete auth configuration,
# without refreshing OAuth; nothing for an unknown or unconfigured provider.
def checkAuth(+models: Models, +id: String, signal: Auth.Signal()) -> IO(CheckResult()):
  signalled(CheckResult(), signal, given => checkSignalled(models, id, given))

# One provider's availability: its auth check and, when configured, its
# models narrowed by filterModels for the stored credential.
type Availability is Data:
  Availability{provider: String, check: Maybe<&2, Auth.AuthCheck>, models: List<&2, Model()>}

def AvailabilityResult() -> Data: Result<&2, &2, Resolve.ModelsError, Availability>

def availableFrom(+provider: Provider, credential: Maybe<&2, Auth.Credential>, check: CheckResult()) -> IO(AvailabilityResult()):
  match check:
    case Fail{error}: IO.pure(AvailabilityResult(), Fail{error})
    case Done{None{}}: IO.pure(AvailabilityResult(), Done{Availability{providerId(provider), None{}, Nil{}}})
    case Done{Some{found}}:
      do IO<AvailabilityResult()>:
        models : List<&2, Model()> <- filterModels(provider, providerModels(provider), credential)
        return Done{Availability{providerId(provider), Some{found}, models}}

def availableRead(+models: Models, +provider: Provider, signal: Abort.AbortSignal<Unit>, stored: Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>>) -> IO(AvailabilityResult()):
  match stored:
    case Fail{error}: IO.pure(AvailabilityResult(), Fail{error})
    case Done{+credential}:
      do IO<AvailabilityResult()>:
        check : CheckResult() <- checkProviderAuth(models, provider, credential, signal)
        availableFrom(provider, credential, check)

def availabilityOf(+models: Models, +provider: Provider, +signal: Abort.AbortSignal<Unit>) -> IO(AvailabilityResult()):
  do IO<AvailabilityResult()>:
    stored : Result<&2, &2, Resolve.ModelsError, Maybe<&2, Auth.Credential>> <- readCredential(models, providerId(provider), signal)
    availableRead(models, provider, signal, stored)

def availabilityAll(+models: Models, providers: List<&2, Provider>, +signal: Abort.AbortSignal<Unit>) -> IO(List<&2, AvailabilityResult()>):
  match providers:
    case Nil{}: IO.pure(List<&2, AvailabilityResult()>, Nil{})
    case provider <> rest:
      do IO<List<&2, AvailabilityResult()>>:
        head : AvailabilityResult() <- availabilityOf(models, provider, signal)
        tail : List<&2, AvailabilityResult()> <- availabilityAll(models, rest, signal)
        return head <> tail

def listed(found: Maybe<&2, Provider>) -> List<&2, Provider>:
  match found:
    case None{}: Nil{}
    case Some{provider}: [provider]

def selectedProviders(+providers: List<&2, Provider>, id: Maybe<&2, String>) -> List<&2, Provider>:
  match id:
    case None{}: providers
    case Some{wanted}: listed(findProvider(providers, wanted))

def AvailabilitiesResult() -> Data: Result<&2, &2, Resolve.ModelsError, List<&2, AvailabilityResult()>>

def availabilitiesSignalled(+models: Models, id: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>) -> IO(AvailabilitiesResult()):
  do IO<AvailabilitiesResult()>:
    stopped : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(AvailabilitiesResult()), stopped, _ => IO.pure(AvailabilitiesResult(), Fail{abortedError()}), _ => do IO<AvailabilitiesResult()>:
      providers : List<&2, Provider> <- getProviders(models)
      entries : List<&2, AvailabilityResult()> <- availabilityAll(models, selectedProviders(providers, id), signal)
      return Done{entries})(Unit{})

# Each selected provider's availability (all providers, or the one with the
# id), in registration order; a failed check or credential read is that
# provider's entry.
def getAvailabilities(+models: Models, id: Maybe<&2, String>, signal: Auth.Signal()) -> IO(AvailabilitiesResult()):
  signalled(AvailabilitiesResult(), signal, given => availabilitiesSignalled(models, id, given))

def AvailableResult() -> Data: Result<&2, &2, Resolve.ModelsError, List<&2, Model()>>

def collectedAvailable(entries: List<&2, AvailabilityResult()>) -> AvailableResult():
  match entries:
    case Nil{}: Done{Nil{}}
    case Fail{error} <> _: Fail{error}
    case Done{Availability{_, _, models}} <> rest: Result.bind(&2, &2, Resolve.ModelsError, List<&2, Model()>, List<&2, Model()>, collectedAvailable(rest), others => Done{List.append(&2, Model(), models, others)})

def availableOf(result: AvailabilitiesResult()) -> AvailableResult():
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: collectedAvailable(entries)

# upstream getAvailable(providerId?): the models of the providers whose auth
# is configured, narrowed by each provider's filterModels for its stored
# credential; the first failure rejects.
def getAvailable(+models: Models, id: Maybe<&2, String>, signal: Auth.Signal()) -> IO(AvailableResult()):
  do IO<AvailableResult()>:
    result : AvailabilitiesResult() <- getAvailabilities(models, id, signal)
    return availableOf(result)

def resolveKnown(+models: Models, provider: Maybe<&2, Provider>, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Done{None{}})
    case Some{found}: Resolve.resolveProviderAuth(providerRef(found), credentialsOf(models), authContextOf(models), overrides)

# upstream getAuth(providerId): provider-scoped auth, nothing for an unknown
# or unconfigured provider.
def getAuth(+models: Models, +id: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    provider : Maybe<&2, Provider> <- getProvider(models, id)
    resolveKnown(models, provider, overrides)

def sameHeaderName(+left: String, +right: String) -> Bool: U.equal(String.to_lower(left), String.to_lower(right))

def withoutHeader(entries: List<&2, R.Property<T.Nullable<String>>>, +name: String) -> List<&2, R.Property<T.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutHeader(rest, name)
      Bool.pick(List<&2, R.Property<T.Nullable<String>>>, sameHeaderName(key, name), tail, R.Property{key, value} <> tail)

def overrideHeaders(overrides: List<&2, R.Property<T.Nullable<String>>>, entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match overrides:
    case Nil{}: entries
    case R.Property{+name, value} <> rest: overrideHeaders(rest, List.append(&2, R.Property<T.Nullable<String>>, withoutHeader(entries, name), R.Property{name, value} <> Nil{}))

# upstream mergeHeaders: an override replaces any header whose name differs
# only in case.
def mergeHeaders(base: Maybe<&2, T.ProviderHeaders()>, override: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.ProviderHeaders()>:
  match base override:
    case base None{}: base
    case None{} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, Nil{})}}
    case Some{R.Record{entries}} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, entries)}}

def presentHeaders(values: List<&2, R.Property<String>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, T.PresentValue{value}} <> presentHeaders(rest)

def modelHeaders(model: Model()) -> Maybe<&2, T.ProviderHeaders()>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{headers}, _}: Some{R.Record{presentHeaders(R.entries(String, headers))}}
    case _: None{}

# The resolved auth with `headers` merged over its own.
def withAuthHeaders(resolution: Resolve.Resolution(), headers: Maybe<&2, T.ProviderHeaders()>) -> Resolve.Resolution():
  match resolution headers:
    case resolution None{}: resolution
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, existing, url}, env, source}}} headers: Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, mergeHeaders(existing, headers), url}, env, source}}}
    case other _: other

# upstream getAuth(model): the provider's auth plus the model's static
# headers.
def getModelAuth(+models: Models, +model: Model(), overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    resolution : Resolve.Resolution() <- getAuth(models, T.modelProvider(model), overrides)
    return withAuthHeaders(resolution, modelHeaders(model))

# Login and logout
# ----------------

def loginMethod(auth: Auth.ProviderAuth, kind: Auth.CredentialType) -> Maybe<&2, C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()>>:
  match auth kind:
    case Auth.ProviderAuth{_, Some{Auth.OAuthAuth{_, _, _, login, _, _}}} Auth.OAuthType{}: Some{login}
    case Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, login, _, _}}, _} Auth.ApiKeyType{}: login
    case _ _: None{}

def loginReplacement(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

def loginStored(+id: String, credential: Auth.Credential, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Auth.LoginOutcome():
  match stored:
    case Fail{cause}: Fail{Resolve.errorMessage(Resolve.failure(Resolve.AuthError{}, "Credential store modify failed for " ++ id, cause))}
    case Done{_}: Done{credential}

def loginPersisted(+models: Models, +id: String, result: Auth.LoginOutcome(), signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  match result:
    case Fail{error}: IO.pure(Auth.LoginOutcome(), Fail{error})
    case Done{+credential}:
      do IO<Auth.LoginOutcome()>:
        +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~loginReplacement, credential)
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(credentialsOf(models), id, update, Some{signal})
        C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
        return loginStored(id, credential, stored)

def loginWith(+models: Models, +id: String, method: Maybe<&2, C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()>>, interaction: Auth.ProviderAuthInteraction, name: String, kind: Auth.CredentialType) -> IO(Auth.LoginOutcome()):
  match method interaction:
    case None{} _: IO.pure(Auth.LoginOutcome(), Fail{name ++ " does not support " ++ Auth.typeName(kind) ++ " login"})
    case Some{callback} Auth.ProviderAuthInteraction{+signal, prompt, notify}:
      do IO<Auth.LoginOutcome()>:
        result : Auth.LoginOutcome() <- C.call(Auth.ProviderAuthInteraction, Auth.LoginOutcome(), callback, Auth.ProviderAuthInteraction{signal, prompt, notify})
        loginPersisted(models, id, result, signal)

def loginProvider(+models: Models, +id: String, provider: Maybe<&2, Provider>, +kind: Auth.CredentialType, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match provider:
    case None{}: IO.pure(Auth.LoginOutcome(), Fail{"Unknown provider: " ++ id})
    case Some{Provider{_, name, _, auth, _, _, _, _}}: loginWith(models, id, loginMethod(auth, kind), interaction, name, kind)

def loginSignalled(+models: Models, +id: String, kind: Auth.CredentialType, +interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}:
      do IO<Auth.LoginOutcome()>:
        stopped : Bool <- Abort.aborted(Unit, signal)
        Bool.pick(Unit -> IO(Auth.LoginOutcome()), stopped, _ => IO.pure(Auth.LoginOutcome(), Fail{"This operation was aborted"}), _ => do IO<Auth.LoginOutcome()>:
          provider : Maybe<&2, Provider> <- getProvider(models, id)
          loginProvider(models, id, provider, kind, interaction))(Unit{})

def loginWithSignal(+models: Models, +id: String, kind: Auth.CredentialType, prompt: C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>>, notify: C.Callback<Auth.AuthEvent, Unit>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  loginSignalled(models, id, kind, Auth.ProviderAuthInteraction{signal, prompt, notify})

# upstream login: run the provider-owned login flow of the given type and
# persist the credential it returns.
def login(+models: Models, +id: String, kind: Auth.CredentialType, interaction: Auth.AuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.AuthInteraction{signal, +prompt, +notify}: signalled(Auth.LoginOutcome(), signal, given => loginWithSignal(models, id, kind, prompt, notify, given))

def loggedOut(+id: String, deleted: Auth.StoreResult(Unit)) -> Result<&2, &2, Resolve.ModelsError, Unit>:
  match deleted:
    case Fail{cause}: Fail{Resolve.failure(Resolve.AuthError{}, "Credential store delete failed for " ++ id, cause)}
    case Done{_}: Done{Unit{}}

def logoutSignalled(+models: Models, +id: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
    stopped : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(Result<&2, &2, Resolve.ModelsError, Unit>), stopped, _ => IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{abortedError()}), _ => do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
      deleted : Auth.StoreResult(Unit) <- Auth.delete(credentialsOf(models), id, Some{signal})
      return loggedOut(id, deleted))(Unit{})

# upstream logout: remove the stored credential of a provider.
def logout(+models: Models, +id: String, signal: Auth.Signal()) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  signalled(Result<&2, &2, Resolve.ModelsError, Unit>, signal, given => logoutSignalled(models, id, given))

# Refresh (upstream Models.refresh)
# --------------------------------

type ModelsRefreshOptions is Data:
  ModelsRefreshOptions{allowNetwork: Maybe<&2, Bool>, providers: Maybe<&2, List<&2, String>>, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

def modelsRefreshOptions() -> ModelsRefreshOptions: ModelsRefreshOptions{None{}, None{}, None{}, None{}}

# `errors` maps provider ids to the refresh failure message.
type ModelsRefreshResult is Data:
  ModelsRefreshResult{aborted: Bool, errors: R.Record<String>}

type Publisher is Data:
  Publisher{state: Ref.Ref<ModelsState>, store: Store.ModelsStore, id: String, generation: Nat, signal: Abort.AbortSignal<Unit>}

def generationOf(state: ModelsState, id: String) -> Maybe<&2, Nat>:
  match state:
    case ModelsState{_, _, generations}: R.get(Nat, generations, id)

def stillCurrent(+state: Ref.Ref<ModelsState>, +id: String, generation: Nat, signal: Abort.AbortSignal<Unit>) -> IO(Bool):
  do IO<Bool>:
    stopped : Bool <- Abort.aborted(Unit, signal)
    now : ModelsState <- Ref.read(ModelsState, state)
    return Bool.not(stopped) && Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, latest => Nat.is_eq(latest, generation), generationOf(now, id)), False{})

def persisted(store: Store.ModelsStore, id: String, persist: Persist, signal: Abort.AbortSignal<Unit>) -> IO(Store.StoreResult(Unit)):
  match persist:
    case KeepStored{}: IO.pure(Store.StoreResult(Unit), Done{Unit{}})
    case DeleteStored{}: Store.delete(store, id, Some{signal})
    case StoreEntry{entry}: Store.write(store, id, entry, Some{signal})

def withPublication(state: ModelsState, +id: String, models: Maybe<&2, List<&2, Model()>>) -> ModelsState:
  match state models:
    case state None{}: state
    case ModelsState{providers, published, generations} Some{list}: ModelsState{providers, R.set(List<&2, Model()>, published, id, list), generations}

def applied(+state: Ref.Ref<ModelsState>, +id: String, models: Maybe<&2, List<&2, Model()>>, accepted: Bool) -> IO(Bool):
  match accepted:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        Ref.modify(ModelsState, Unit, state, now => (withPublication(now, id, models), Unit{}))
        return True{}

def afterPersist(+state: Ref.Ref<ModelsState>, +id: String, generation: Nat, +signal: Abort.AbortSignal<Unit>, models: Maybe<&2, List<&2, Model()>>, stored: Store.StoreResult(Unit)) -> IO(Bool):
  match stored:
    case Fail{_}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        accepted : Bool <- stillCurrent(state, id, generation, signal)
        applied(state, id, models, accepted)

def publishAccepted(accepted: Bool, publisher: Publisher, publication: ModelsPublication) -> IO(Bool):
  match accepted publisher publication:
    case False{} _ _: IO.pure(Bool, False{})
    case True{} Publisher{+state, store, +id, +generation, +signal} ModelsPublication{persist, models}:
      do IO<Bool>:
        stored : Store.StoreResult(Unit) <- persisted(store, id, persist, signal)
        afterPersist(state, id, generation, signal, models, stored)

# upstream publishProviderModels: a superseded or aborted refresh publishes
# nothing; otherwise the persistence change happens first and the catalog
# update only if the refresh is still current afterwards. A store failure
# rejects the publication.
def publishModels(publisher: Publisher, publication: ModelsPublication) -> IO(Bool):
  match publisher:
    case Publisher{+state, store, +id, +generation, +signal}:
      do IO<Bool>:
        accepted : Bool <- stillCurrent(state, id, generation, signal)
        publishAccepted(accepted, Publisher{state, store, id, generation, signal}, publication)

def storedOAuth(stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Done{Some{Auth.OAuthCredential{refresher, access, expires, extra}}}: Some{Auth.OAuthCredential{refresher, access, expires, extra}}
    case _: None{}

def reread(+models: Models, +id: String, resolution: Resolve.Resolution()) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match resolution:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Fail{Resolve.errorMessage(error)})
    case Done{_}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(models), id, None{})
        return Done{storedOAuth(stored)}

def refreshedOAuth(+models: Models, +id: String, oauth: Auth.OAuthAuth, +credential: Auth.Credential, signal: Abort.AbortSignal<Unit>, fresh: Bool) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match fresh:
    case True{}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{Some{credential}})
    case False{}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        resolution : Resolve.Resolution() <- Resolve.refreshStored(credentialsOf(models), id, oauth, signal, None{}, F.fromU32(0))
        reread(models, id, resolution)

def resolvedKey(resolution: Resolve.Resolution()) -> Result<&2, &2, String, Maybe<&2, Auth.Credential>>:
  match resolution:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{None{}}: Done{None{}}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, _}, env, _}}}: Done{Some{Auth.ApiKeyCredential{key, env}}}

# upstream resolveRefreshCredential: an OAuth credential is refreshed when it
# expired; otherwise the provider's API key auth must resolve.
def resolveRefreshCredential(+models: Models, +id: String, stored: Maybe<&2, Auth.Credential>, auth: Auth.ProviderAuth, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match stored auth:
    case Some{Auth.OAuthCredential{refresher, access, expires, extra}} Auth.ProviderAuth{_, None{}}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{None{}})
    case Some{Auth.OAuthCredential{refresher, access, +expires, extra}} Auth.ProviderAuth{_, Some{oauth}}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        now : F64 <- Date.now()
        refreshedOAuth(models, id, oauth, Auth.OAuthCredential{refresher, access, expires, extra}, signal, F64.is_lt(now, expires))
    case stored Auth.ProviderAuth{None{}, _}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{None{}})
    case stored Auth.ProviderAuth{Some{apiKey}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        resolution : Resolve.Resolution() <- Resolve.resolveApiKey(authContextOf(models), apiKey, id, apiKeyCredential(stored), signal)
        return resolvedKey(resolution)

type Phase is Data:
  Phase{refresher: RefreshModels(), publishing: C.Callback<ModelsPublication, Bool>, signal: Abort.AbortSignal<Unit>}

def phaseStored(stored: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>), phase: Phase, credential: Maybe<&2, Auth.Credential>, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  match stored phase:
    case Fail{error} _: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{entry} Phase{refresher, publishing, signal}: C.call(RefreshModelsContext, Result<&2, &2, String, Unit>, refresher, RefreshModelsContext{credential, entry, publishing, allowNetwork, force, signal})

# upstream runProviderRefreshPhase: the provider sees the stored catalog as
# of this phase.
def runPhase(+models: Models, +id: String, +phase: Phase, credential: Maybe<&2, Auth.Credential>, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  match phase:
    case Phase{+refresher, +publishing, +signal}:
      do IO<Result<&2, &2, String, Unit>>:
        stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(modelsStoreOf(models), id, Some{signal})
        phaseStored(stored, Phase{refresher, publishing, signal}, credential, allowNetwork, force)

def networkPhase(+models: Models, +id: String, +phase: Phase, force: Maybe<&2, Bool>, credential: Result<&2, &2, String, Maybe<&2, Auth.Credential>>) -> IO(Result<&2, &2, String, Unit>):
  match credential:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{None{}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Done{Some{credential}}: runPhase(models, id, phase, Some{credential}, True{}, force)

def phaseSignal(phase: Phase) -> Abort.AbortSignal<Unit>:
  match phase:
    case Phase{_, _, signal}: signal

def afterCache(+models: Models, +id: String, auth: Auth.ProviderAuth, +phase: Phase, allowNetwork: Bool, force: Maybe<&2, Bool>, cached: Result<&2, &2, String, Unit>, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Result<&2, &2, String, Unit>):
  match cached stored:
    case Fail{error} _: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{_} Fail{cause}: IO.pure(Result<&2, &2, String, Unit>, Fail{Resolve.errorMessage(readFailure(id, cause))})
    case Done{_} Done{credential}:
      do IO<Result<&2, &2, String, Unit>>:
        stopped : Bool <- Abort.aborted(Unit, phaseSignal(phase))
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), Bool.not(allowNetwork) || stopped, _ => IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}}), _ => do IO<Result<&2, &2, String, Unit>>:
          resolved : Result<&2, &2, String, Maybe<&2, Auth.Credential>> <- resolveRefreshCredential(models, id, credential, auth, phaseSignal(phase))
          networkPhase(models, id, phase, force, resolved))(Unit{})

def credentialOf(stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Done{credential}: credential
    case Fail{_}: None{}

# upstream refresh for one provider: restore the cached catalog before auth
# resolution or network access, then refresh with the effective credential
# when the network is allowed.
def refreshPhases(+models: Models, +id: String, auth: Auth.ProviderAuth, +phase: Phase, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    +stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(models), id, Some{phaseSignal(phase)})
    cached : Result<&2, &2, String, Unit> <- runPhase(models, id, phase, credentialOf(stored), False{}, None{})
    afterCache(models, id, auth, phase, allowNetwork, force, cached, stored)

# Starting a refresh supersedes an older one without discarding the catalog
# it published.
def begun(+id: String, state: ModelsState) -> ModelsState & Nat:
  match state:
    case ModelsState{providers, published, +generations}:
      +next = nextGeneration(generations, id)
      (ModelsState{providers, published, R.set(Nat, generations, id, next)}, next)

def recordedError(errors: R.Record<String>, +id: String, stopped: Bool, result: Result<&2, &2, String, Unit>) -> R.Record<String>:
  match stopped result:
    case False{} Fail{error}: R.set(String, errors, id, error)
    case _ _: errors

def refreshProvider(+models: Models, +provider: Provider, refresher: RefreshModels(), allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  +id = providerId(provider)
  do IO<R.Record<String>>:
    generation : Nat <- Ref.modify(ModelsState, Nat, stateOf(models), state => begun(id, state))
    +publishing : C.Callback<ModelsPublication, Bool> <- C.create(~Publisher, ~ModelsPublication, ~Bool, ~publishModels, Publisher{stateOf(models), modelsStoreOf(models), id, generation, signal})
    result : Result<&2, &2, String, Unit> <- refreshPhases(models, id, providerAuth(provider), Phase{refresher, publishing, signal}, allowNetwork, force)
    C.dispose(ModelsPublication, Bool, publishing)
    stopped : Bool <- Abort.aborted(Unit, signal)
    return recordedError(errors, id, stopped, result)

def selected(filter: Maybe<&2, List<&2, String>>, +id: String) -> Bool:
  match filter:
    case None{}: True{}
    case Some{ids}: containsText(ids, id)

def refreshSelected(+models: Models, provider: Provider, chosen: Bool, refresher: Maybe<&2, RefreshModels()>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  match chosen refresher:
    case True{} Some{refresher}: refreshProvider(models, provider, refresher, allowNetwork, force, signal, errors)
    case _ _: IO.pure(R.Record<String>, errors)

def refreshEach(+models: Models, providers: List<&2, Provider>, +filter: Maybe<&2, List<&2, String>>, +allowNetwork: Bool, +force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  match providers:
    case Nil{}: IO.pure(R.Record<String>, errors)
    case +provider <> rest:
      do IO<R.Record<String>>:
        next : R.Record<String> <- refreshSelected(models, provider, selected(filter, providerId(provider)), providerRefresh(provider), allowNetwork, force, signal, errors)
        refreshEach(models, rest, filter, allowNetwork, force, signal, next)

def refreshSignalled(+models: Models, +filter: Maybe<&2, List<&2, String>>, +allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    providers : List<&2, Provider> <- getProviders(models)
    errors : R.Record<String> <- refreshEach(models, providers, filter, allowNetwork, Bool.pick(Maybe<&2, Bool>, allowNetwork, force, None{}), signal, R.new(String))
    stopped : Bool <- Abort.aborted(Unit, signal)
    return ModelsRefreshResult{stopped, errors}

def refreshUnlessAborted(+models: Models, filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, stopped: Bool) -> IO(ModelsRefreshResult):
  match stopped:
    case True{}: IO.pure(ModelsRefreshResult, ModelsRefreshResult{True{}, R.new(String)})
    case False{}: refreshSignalled(models, filter, allowNetwork, force, signal)

def refreshWithSignal(+models: Models, filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    stopped : Bool <- Abort.aborted(Unit, signal)
    refreshUnlessAborted(models, filter, allowNetwork, force, signal, stopped)

# upstream refresh: the selected dynamic providers (all by default; unknown
# and static ones are skipped) restore their stored catalog, then refresh it
# over the network (allowed unless allowNetwork is false) with the effective
# credential; unconfigured providers skip the network phase. Provider
# failures are returned per provider id; cancellation is `aborted`.
def refresh(+models: Models, options: ModelsRefreshOptions) -> IO(ModelsRefreshResult):
  match options:
    case ModelsRefreshOptions{allowNetwork, filter, force, signal}: signalled(ModelsRefreshResult, signal, given => refreshWithSignal(models, filter, Maybe.default(&2, Bool, allowNetwork, True{}), force, given))
