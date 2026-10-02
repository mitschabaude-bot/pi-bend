import Base
import ../../../runtime/src/cancellable-task.bend as Tasks
import ../../../runtime/src/keyed-serial.bend as KeyedSerial
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/context.bend as Context
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/providers/all.bend as Builtin
import ../../../ai/src/providers/radius.bend as Radius
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/glob.bend as Glob
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/filesystem.bend as FS
import ../config.bend as AppConfig
import ./model-config.bend as Config
import ./provider-composer.bend as Composer
import ../../../ai/src/models-store.bend as Store
import ./models-store.bend as Files
import ./runtime-credentials.bend as RuntimeCredentials
import ./remote-catalog-provider.bend as Remote
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/schema-value.bend as V
import ../../../agent/src/types.bend as AgentTypes
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../ai/src/utils/transcript.bend as Transcript
import ../../../ai/src/utils/model-api.bend as ModelApi
import ./tools/index.bend as Tools
import ../../../runtime/src/fetch.bend as Fetch

# The coding agent's ModelRuntime over pi-ai's Models collection
# (AiModels.Models, upstream `this.models`). Built-in providers are composed
# with their models.json entries and models.json custom providers are added.
# Extensions register native providers (registerNativeProvider) and dynamic
# providers publish catalogs through refresh(). Catalogs persist in the models
# store (models-store.json beside models.json unless one is injected) and
# built-in providers other than Radius carry pi.dev's remote catalog overlay.

def Model() -> Data: Ai.Model<Ai.JsonValue>

# What changes after creation besides the collection: extension providers in
# registration order and upstream's snapshot of the configured providers and
# the available models (computed at creation and refreshed after credential
# or provider changes, so availability queries do not read the credential
# store).
type Catalog is Data:
  Catalog{natives: List<&2, AiModels.Provider>, configured: List<&2, String>, available: List<&2, Model()>}

def emptyCatalog() -> Catalog: Catalog{Nil{}, Nil{}, Nil{}}

type AvailabilityStatus is Data:
  AvailabilityStatus{generation: Nat, error: Maybe<&2, String>}

# The read state of a FileModelsStore the runtime created. Upstream shares a
# module-level read state per path among FileModelsStore instances; Bend has
# no module state, and the state's Serial owner is affine (Type-kinded), so
# the runtime that creates the file store owns its read state here and
# retires it in dispose(), after the store's callbacks. Injected and
# in-memory stores have none.
def StoreState() -> Data: Ref.Ref<Maybe<&1, Files.FileModelsReadState>>

# A definition combines built-in and models.json providers. Each generation
# owns only the callbacks created by that composition; the baseline providers
# own their original callbacks. The collection owns the models store and auth
# context; extension providers belong to their registrations.
# Extension providers' own parts: each registration's config (for
# re-registration merges), its streamSimple, and the auth callbacks its
# composition created (the base provider owns the rest); and the stream the
# built-in apis dispatch through (upstream's api registry over the global
# fetch), installed by whoever owns the transport.
type OwnedAuth is Data:
  OwnedApiKey{auth: Auth.ApiKeyAuth}
  OwnedToAuth{toAuth: C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>>}

type ExtensionEntry is Data:
  ExtensionEntry{id: String, config: Maybe<&2, Composer.ProviderConfigInput>, stream: Maybe<&2, Composer.ProviderStream()>, owned: List<&2, OwnedAuth>}

type ExtensionState is Data:
  ExtensionState{entries: List<&2, ExtensionEntry>, apiStreams: Maybe<&2, Composer.ProviderStream()>}

def emptyExtensions() -> ExtensionState: ExtensionState{Nil{}, None{}}

type ModelsRefreshResult is Data:
  ModelsRefreshResult{aborted: Bool, errors: R.Record<String>}

def cancelledRefresh() -> ModelsRefreshResult: ModelsRefreshResult{True{},R.new(String)}

# Only interactive all-catalog requests share work. Provider-specific refreshes
# still use refresh() directly. The runtime owns this state, so no global map or
# identity-based lookup is needed.
type SharedRefresh is Data:
  RefreshIdle{next: Nat}
  RefreshActive{id: Nat, controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>, waiters: Nat, finished: Bool, closing: Bool}
  RefreshClosed{}

# A caller may leave a shared refresh before its detached provider work stops.
# The runtime waits for that work before releasing providers and their stores.
type RefreshWork is Data:
  RefreshWork{running: Nat, closing: Bool, drained: Deferred.Deferred<Unit>}

def newRefreshWork() -> IO(Ref.Ref<RefreshWork>):
  do IO<Ref.Ref<RefreshWork>>:
    drained : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    Ref.new(RefreshWork, RefreshWork{0n, False{}, drained})

type SourceMark is Data: Untracked{} SourceBytes{bytes: List<&2, U32>} SourceError{message: String}
type DefinitionSource is Data:
  StaticSource{baseline: List<&2, AiModels.Provider>}
  FileSource{path: String, baseline: List<&2, AiModels.Provider>, radius: Radius.RadiusTransport, mark: SourceMark}
type Generation is Data:
  Generation{owned: List<&2, OwnedAuth>, radius: List<&2, AiModels.Provider>, refreshes: List<&2, Composer.Retained>}
type Definition is Data:
  Definition{providers: List<&2, AiModels.Provider>, builtins: List<&2, String>, config: Config.ModelConfig, errors: List<&2, String>, generation: Generation, source: DefinitionSource, retired: List<&2, Generation>}
type ModelRuntime is Data:
  ModelRuntime{definition: Ref.Ref<Definition>, models: AiModels.Models, catalog: Ref.Ref<Catalog>, storeState: StoreState(), extensions: Ref.Ref<ExtensionState>, sharedRefresh: Ref.Ref<SharedRefresh>, availability: Ref.Ref<AvailabilityStatus>, credentials: RuntimeCredentials.RuntimeCredentials, refreshWork: Ref.Ref<RefreshWork>, credentialQueues: KeyedSerial.Registry}

# Composition (recomposeProvider/rebuildProviders)
# -----------------------------------------------

def providerId(provider: AiModels.Provider) -> String: AiModels.providerId(provider)

def findProvider(providers: List<&2, AiModels.Provider>, +id: String) -> Maybe<&2, AiModels.Provider>: AiModels.findProvider(providers, id)

def base(provider: Maybe<&2, AiModels.Provider>) -> Maybe<&2, Composer.Base>:
  match provider:
    case None{}: None{}
    case Some{AiModels.Provider{_, name, url, auth, models, _, _, _}}: Some{Composer.Base{name, url, auth, models}}

def maybeProviderAuth(provider: Maybe<&2, AiModels.Provider>) -> Auth.ProviderAuth:
  match provider:
    case Some{AiModels.Provider{_, _, _, auth, _, _, _, _}}: auth
    case None{}: Auth.ProviderAuth{None{}, None{}}

def sameResolve(left: Auth.ApiKeyAuth, right: Auth.ApiKeyAuth) -> Bool:
  match left right:
    case Auth.ApiKeyAuth{_, _, a, _} Auth.ApiKeyAuth{_, _, b, _}: C.same(Auth.ResolveInput, Auth.AuthOutcome(), a, b)

def ownedKey(composed: Maybe<&2, Auth.ApiKeyAuth>, base: Maybe<&2, Auth.ApiKeyAuth>) -> List<&2, OwnedAuth>:
  match composed base:
    case None{} _: Nil{}
    case Some{+auth} Some{inherited}: Bool.pick(List<&2, OwnedAuth>, sameResolve(auth, inherited), Nil{}, [OwnedApiKey{auth}])
    case Some{auth} None{}: [OwnedApiKey{auth}]

def ownedToAuth(composed: Maybe<&2, Auth.OAuthAuth>, base: Maybe<&2, Auth.OAuthAuth>) -> List<&2, OwnedAuth>:
  match composed base:
    case Some{Auth.OAuthAuth{_, _, _, _, _, +mine}} Some{Auth.OAuthAuth{_, _, _, _, _, theirs}}: Bool.pick(List<&2, OwnedAuth>, C.same(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, mine, theirs), Nil{}, [OwnedToAuth{mine}])
    case _ _: Nil{}

# The callbacks a composition created over its base's auth.
def ownedAuth(composed: Auth.ProviderAuth, base: Auth.ProviderAuth) -> List<&2, OwnedAuth>:
  match composed base:
    case Auth.ProviderAuth{key, oauth} Auth.ProviderAuth{baseKey, baseOAuth}: List.append(&2, OwnedAuth, ownedKey(key, baseKey), ownedToAuth(oauth, baseOAuth))

type Composition is Data:
  Composition{providers: List<&2, AiModels.Provider>, errors: List<&2, String>, refreshes: List<&2, Composer.Retained>, owned: List<&2, OwnedAuth>}

def added(provider: Maybe<&2, AiModels.Provider>, composition: Composition) -> Composition:
  match provider composition:
    case None{} composition: composition
    case Some{provider} Composition{providers, errors, refreshes, owned}: Composition{provider <> providers, errors, refreshes, owned}

def baseFilter(builtin: Maybe<&2, AiModels.Provider>) -> Maybe<&2, AiModels.FilterModels()>:
  match builtin:
    case Some{provider}: AiModels.providerFilter(provider)
    case None{}: None{}

# upstream composeProvider forwards refreshModels to the base provider; the
# base's publications reach the collection through the models.json overlay
# (Composer.overlaidRefresh), whose wrapper the composition retains.
def composedRefresh(+id: String, entry: Config.ModelsJsonProvider, +models: List<&2, Model()>, builtin: Maybe<&2, AiModels.Provider>) -> IO(Maybe<&2, AiModels.RefreshModels()> & List<&2, Composer.Retained>):
  match builtin:
    case Some{AiModels.Provider{_, _, _, _, _, _, Some{refresher}, _}}:
      do IO<Maybe<&2, AiModels.RefreshModels()> & List<&2, Composer.Retained>>:
        +wrapper : AiModels.RefreshModels() <- Composer.overlaidRefresh(id, entry, models, refresher)
        return (Some{wrapper}, [Composer.RetainedRefresh{wrapper}])
    case _: IO.pure(Maybe<&2, AiModels.RefreshModels()> & List<&2, Composer.Retained>, (None{}, Nil{}))

def composedProvider(+id: String, +builtin: Maybe<&2, AiModels.Provider>, composed: Composer.Composed, refreshing: Maybe<&2, AiModels.RefreshModels()> & List<&2, Composer.Retained>, composition: Composition) -> Composition:
  match composed refreshing composition:
    case Composer.Composed{name, url, +auth, models, _} Tuple{refresher, wrappers} Composition{providers, errors, refreshes, owned}:
      Composition{AiModels.Provider{id, name, url, auth, models, AiModels.inheritedStreams(builtin), refresher, baseFilter(builtin)} <> providers, errors, List.append(&2, Composer.Retained, wrappers, refreshes), List.append(&2, OwnedAuth, ownedAuth(auth, maybeProviderAuth(builtin)), owned)}

# A failed composition keeps the built-in provider untouched (or omits a
# custom one) and records the error.
def recomposed(+id: String, +builtin: Maybe<&2, AiModels.Provider>, +entry: Config.ModelsJsonProvider, result: Result<&2, &2, String, Composer.Composed>, composition: Composition) -> IO(Composition):
  match result composition:
    case Fail{error} Composition{providers, errors, refreshes, owned}: IO.pure(Composition, added(builtin, Composition{providers, ("Provider \"" ++ id ++ "\": " ++ error) <> errors, refreshes, owned}))
    case Done{Composer.Composed{name, url, auth, +models, owned}} composition:
      do IO<Composition>:
        refreshing : Maybe<&2, AiModels.RefreshModels()> & List<&2, Composer.Retained> <- composedRefresh(id, entry, models, builtin)
        return composedProvider(id, builtin, Composer.Composed{name, url, auth, models, owned}, refreshing, composition)

def recomposeProvider(+id: String, +builtin: Maybe<&2, AiModels.Provider>, entry: Maybe<&2, Config.ModelsJsonProvider>, composition: Composition) -> IO(Composition):
  match entry:
    # No overlay: the built-in provider is used untouched.
    case None{}: IO.pure(Composition, added(builtin, composition))
    case Some{+entry}:
      do IO<Composition>:
        result : Result<&2, &2, String, Composer.Composed> <- Composer.composeModelProvider(id, base(builtin), entry)
        recomposed(id, builtin, entry, result, composition)

def containsId(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, id) || containsId(rest, id)

def builtinIds(providers: List<&2, AiModels.Provider>) -> List<&2, String>: AiModels.providerIds(providers)

def newIds(ids: List<&2, String>, +known: List<&2, String>) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case +id <> rest:
      +tail = newIds(rest, known)
      Bool.pick(List<&2, String>, containsId(known, id), tail, id <> tail)

# Built-in ids first, then models.json ids, each once.
def composedIds(+builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig) -> List<&2, String>:
  List.append(&2, String, builtinIds(builtins), newIds(Config.getProviderIds(config), builtinIds(builtins)))

def rebuildProviders(ids: List<&2, String>, +builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig, composition: Composition) -> IO(Composition):
  match ids:
    case Nil{}: IO.pure(Composition, composition)
    case +id <> rest:
      do IO<Composition>:
        next : Composition <- recomposeProvider(id, findProvider(builtins, id), Config.getProvider(config, id), composition)
        rebuildProviders(rest, builtins, config, next)

def assembled(composition: Composition, builtins: List<&2, String>, config: Config.ModelConfig, source: DefinitionSource, radiusOwned: List<&2,AiModels.Provider>, models: AiModels.Models, catalog: Ref.Ref<Catalog>, storeState: StoreState(), extensions: Ref.Ref<ExtensionState>, sharedRefresh: Ref.Ref<SharedRefresh>, availability: Ref.Ref<AvailabilityStatus>, credentials: RuntimeCredentials.RuntimeCredentials, refreshWork: Ref.Ref<RefreshWork>) -> IO(ModelRuntime):
  match composition:
    case Composition{providers, errors, refreshes, owned}:
      do IO<ModelRuntime>:
        definition : Ref.Ref<Definition> <- Ref.new(Definition, Definition{List.reverse(&2,AiModels.Provider,providers), builtins, config, List.reverse(&2,String,errors), Generation{owned,radiusOwned,refreshes}, source, Nil{}})
        credentialQueues : KeyedSerial.Registry <- KeyedSerial.create()
        return ModelRuntime{definition, models, catalog, storeState, extensions, sharedRefresh, availability, credentials, refreshWork, credentialQueues}

def unknownProvider(id: String) -> Resolve.ModelsError:
  Resolve.ModelsError{Resolve.ProviderError{}, "Unknown provider: " ++ id}

# Current catalog
# ---------------

def modelsOf(runtime: ModelRuntime) -> AiModels.Models:
  match runtime:
    case ModelRuntime{_, models, _, _, _, _, _, _, _, _}: models

def definitionRef(runtime: ModelRuntime) -> Ref.Ref<Definition>:
  match runtime:
    case ModelRuntime{definition, _, _, _, _, _, _, _, _, credentialQueues}: definition

def credentialsOf(runtime: ModelRuntime) -> Auth.CredentialStore: AiModels.credentialsOf(modelsOf(runtime))

def runtimeCredentialsOf(runtime: ModelRuntime) -> RuntimeCredentials.RuntimeCredentials:
  match runtime:
    case ModelRuntime{_, _, _, _, _, _, _, credentials, _, _}: credentials

def contextOf(runtime: ModelRuntime) -> Auth.AuthContext: AiModels.authContextOf(modelsOf(runtime))

def storeOf(runtime: ModelRuntime) -> Store.ModelsStore: AiModels.modelsStoreOf(modelsOf(runtime))

def catalogRef(runtime: ModelRuntime) -> Ref.Ref<Catalog>:
  match runtime:
    case ModelRuntime{_, _, catalog, _, _, _, _, _, _, _}: catalog

def readCatalog(runtime: ModelRuntime) -> IO(Catalog):
  Ref.read(Catalog, catalogRef(runtime))

def withNative(+natives: List<&2, AiModels.Provider>, +provider: AiModels.Provider) -> AiModels.Provider:
  Maybe.default(&2, AiModels.Provider, findProvider(natives, providerId(provider)), provider)

# The providers of one part (built-in or not), each replaced by the
# extension provider of its id when one is registered.
def overridden(providers: List<&2, AiModels.Provider>, +natives: List<&2, AiModels.Provider>, +builtin: Bool, +builtins: List<&2, String>) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = overridden(rest, natives, builtin, builtins)
      Bool.pick(List<&2, AiModels.Provider>, Bool.xor(containsId(builtins, providerId(provider)), Bool.not(builtin)), withNative(natives, provider) <> tail, tail)

def addedNatives(natives: List<&2, AiModels.Provider>, +known: List<&2, String>) -> List<&2, AiModels.Provider>:
  match natives:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = addedNatives(rest, known)
      Bool.pick(List<&2, AiModels.Provider>, containsId(known, providerId(provider)), tail, provider <> tail)

# upstream providerIds() order: built-in providers, extension providers with
# new ids, then models.json providers. An extension provider replaces the
# provider of its id.
def effectiveProviders(+base: List<&2, AiModels.Provider>, +builtins: List<&2, String>, +natives: List<&2, AiModels.Provider>) -> List<&2, AiModels.Provider>:
  List.concat(&2, AiModels.Provider, [overridden(base, natives, True{}, builtins), addedNatives(natives, builtinIds(base)), overridden(base, natives, False{}, builtins)])

def nativesOf(catalog: Catalog) -> List<&2, AiModels.Provider>:
  match catalog:
    case Catalog{natives, _, _}: natives

def definitionProviders(definition: Definition,natives: List<&2,AiModels.Provider>) -> List<&2,AiModels.Provider>:
  match definition:
    case Definition{providers,builtins,_,_,_,_,_}: effectiveProviders(providers,builtins,natives)
def providersWith(runtime: ModelRuntime, +natives: List<&2, AiModels.Provider>) -> IO(List<&2, AiModels.Provider>):
  do IO<List<&2,AiModels.Provider>>:
    definition : Definition <- Ref.read(Definition,definitionRef(runtime))
    return definitionProviders(definition,natives)

# upstream rebuildProviders on the collection after the provider of `changed`
# was registered, replaced or removed.
def rebuildCollection(+runtime: ModelRuntime, changed: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    catalog : Catalog <- readCatalog(runtime)
    providers : List<&2,AiModels.Provider> <- providersWith(runtime,nativesOf(catalog))
    AiModels.rebuildProviders(modelsOf(runtime), providers, changed)

def getProviders(+runtime: ModelRuntime) -> IO(List<&2, AiModels.Provider>):
  AiModels.getProviders(modelsOf(runtime))

def getProvider(+runtime: ModelRuntime, +id: String) -> IO(Maybe<&2, AiModels.Provider>):
  AiModels.getProvider(modelsOf(runtime), id)

# Auth
# ----

def resolveFor(+runtime: ModelRuntime, id: String, provider: Maybe<&2, AiModels.Provider>, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Fail{unknownProvider(id)})
    case Some{_}: AiModels.getAuth(modelsOf(runtime), id, overrides)

# upstream getAuth(providerId); an unknown provider is an error.
def getAuth(+runtime: ModelRuntime, +id: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
    resolveFor(runtime, id, provider, overrides)

def configOfDefinition(definition: Definition) -> Config.ModelConfig:
  match definition:
    case Definition{_,_,config,_,_,_,_}: config
def getModelConfig(runtime: ModelRuntime) -> IO(Config.ModelConfig):
  do IO<Config.ModelConfig>:
    definition : Definition <- Ref.read(Definition,definitionRef(runtime))
    return configOfDefinition(definition)

def checkFailure(result: AiModels.CheckResult()) -> Result<&2, &2, String, Maybe<&2, Auth.AuthCheck>>:
  match result:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{check}: Done{check}

# upstream ModelRuntime.checkAuth: how the provider is configured, without
# refreshing OAuth; nothing for an unknown or unconfigured provider, and an
# error when the credential store cannot be read.
def checkAuth(+runtime: ModelRuntime, +id: String) -> IO(Result<&2, &2, String, Maybe<&2, Auth.AuthCheck>>):
  do IO<Result<&2, &2, String, Maybe<&2, Auth.AuthCheck>>>:
    result : AiModels.CheckResult() <- AiModels.checkAuth(modelsOf(runtime), id, None{})
    return checkFailure(result)

def oauthConfigured(result: Result<&2,&2,String,Maybe<&2,Auth.AuthCheck>>) -> Bool:
  match result:
    case Done{Some{Auth.AuthCheck{_,Auth.OAuthType{}}}}: True{}
    case _: False{}
def isUsingOAuth(runtime: ModelRuntime,id: String) -> IO(Bool):
  do IO<Bool>:
    checked : Result<&2,&2,String,Maybe<&2,Auth.AuthCheck>> <- checkAuth(runtime,id)
    return oauthConfigured(checked)
def subscriptionProvider(provider: Maybe<&2,AiModels.Provider>) -> Bool:
  match provider:
    case Some{AiModels.Provider{_,_,_,Auth.ProviderAuth{_,Some{Auth.OAuthAuth{_,subscription,_,_,_,_}}},_,_,_,_}}: subscription
    case _: False{}
def isUsingSubscription(+runtime: ModelRuntime,+id: String) -> IO(Bool):
  do IO<Bool>:
    oauth : Bool <- isUsingOAuth(runtime,id)
    Bool.pick(Unit -> IO(Bool),oauth,
      _ => do IO<Bool>:
        provider : Maybe<&2,AiModels.Provider> <- getProvider(runtime,id)
        return subscriptionProvider(provider),
      _ => IO.pure(Bool,False{}))(Unit{})

def configuredCheck(result: AiModels.CheckResult()) -> Bool:
  match result:
    case Done{Some{_}}: True{}
    case _: False{}

# Whether the provider's auth is configured now (a failed check counts as
# not configured).
def checkProviderAuth(+runtime: ModelRuntime, +id: String) -> IO(Bool):
  do IO<Bool>:
    result : AiModels.CheckResult() <- AiModels.checkAuth(modelsOf(runtime), id, None{})
    return configuredCheck(result)

def configuredEntry(+ids: List<&2, String>, entry: AiModels.Availability) -> List<&2, String>:
  match entry:
    case AiModels.Availability{id, Some{_}, _}: id <> ids
    case AiModels.Availability{_, None{}, _}: ids

def configuredIds(entries: List<&2, AiModels.Availability>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: configuredEntry(configuredIds(rest), entry)

def availableModels(entries: List<&2, AiModels.Availability>) -> List<&2, Model()>:
  match entries:
    case Nil{}: Nil{}
    case AiModels.Availability{_, _, models} <> rest: List.append(&2, Model(), models, availableModels(rest))

def withAvailability(catalog: Catalog, +entries: List<&2, AiModels.Availability>) -> Catalog:
  match catalog:
    case Catalog{natives, _, _}: Catalog{natives, configuredIds(entries), availableModels(entries)}


def withRadius(providers: List<&2, AiModels.Provider>, +provider: AiModels.Provider) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: [provider]
    case +first <> +rest: Bool.pick(Unit -> List<&2, AiModels.Provider>, String.eq(providerId(first), providerId(provider)), _ => provider <> rest, _ => first <> withRadius(rest, provider))(Unit{})

def withoutV1(+url: String) -> String:
  Bool.pick(String, String.ends_with(url, "/v1/"), String.take(url, Nat.sub(String.length(url), 4n)), Bool.pick(String, String.ends_with(url, "/v1"), String.take(url, Nat.sub(String.length(url), 3n)), url))

def radiusEntry(+id: String, entry: Maybe<&2, Config.ModelsJsonProvider>) -> Maybe<&2, Radius.RadiusProviderOptions>:
  match entry:
    case Some{Config.ModelsJsonProvider{name, Some{url}, _, _, Some{Config.RadiusOAuth{}}, _, _, _, _, _}}: Some{Radius.RadiusProviderOptions{Some{id}, Some{Maybe.default(&2, String, name, id)}, Some{withoutV1(url)}}}
    case _: None{}

def configuredRadius(builtins: List<&2, AiModels.Provider>, radius: Radius.RadiusTransport, options: Maybe<&2, Radius.RadiusProviderOptions>) -> IO(List<&2, AiModels.Provider>):
  match options:
    case None{}: IO.pure(List<&2, AiModels.Provider>, builtins)
    case Some{selected}:
      do IO<List<&2, AiModels.Provider>>:
        provider : AiModels.Provider <- Radius.radiusProvider(selected, radius)
        return withRadius(builtins, provider)

# upstream configureRadiusProviders: a models.json provider with
# `oauth: "radius"` and a baseUrl becomes a built-in Radius provider for that
# gateway (the baseUrl without its /v1 suffix).
def configureRadiusProviders(ids: List<&2, String>, +builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig, +radius: Radius.RadiusTransport) -> IO(List<&2, AiModels.Provider>):
  match ids:
    case Nil{}: IO.pure(List<&2, AiModels.Provider>, builtins)
    case +id <> rest:
      do IO<List<&2, AiModels.Provider>>:
        next : List<&2, AiModels.Provider> <- configuredRadius(builtins, radius, radiusEntry(id, Config.getProvider(config, id)))
        configureRadiusProviders(rest, next, config, radius)

def includedRadius(entry: Maybe<&2, Radius.RadiusProviderOptions>, provider: Maybe<&2, AiModels.Provider>, +tail: List<&2, AiModels.Provider>) -> List<&2, AiModels.Provider>:
  match entry:
    case None{}: tail
    case Some{_}: Maybe.default(&2, List<&2, AiModels.Provider>, Maybe.map(&2, AiModels.Provider, List<&2, AiModels.Provider>, value => value <> tail, provider), tail)

def radiusOwners(ids: List<&2, String>, +config: Config.ModelConfig, +builtins: List<&2, AiModels.Provider>) -> List<&2, AiModels.Provider>:
  match ids:
    case Nil{}: Nil{}
    case +id <> rest:
      +tail = radiusOwners(rest, config, builtins)
      includedRadius(radiusEntry(id, Config.getProvider(config, id)), findProvider(builtins, id), tail)

def compositionProviders(composition: Composition) -> List<&2, AiModels.Provider>:
  match composition:
    case Composition{providers, _, _, _}: List.reverse(&2, AiModels.Provider, providers)

def composedDefinition(composition: Composition, +builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig, source: DefinitionSource, retired: List<&2, Generation>) -> Definition:
  match composition:
    case Composition{providers, errors, refreshes, owned}:
      Definition{List.reverse(&2, AiModels.Provider, providers), builtinIds(builtins), config, List.reverse(&2, String, errors), Generation{owned, radiusOwners(Config.getProviderIds(config), config, builtins), refreshes}, source, retired}

def sameBytes(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> restA b <> restB: U32.is_eq(a, b) && sameBytes(restA, restB)
    case _ _: False{}

def sameMark(left: SourceMark, right: SourceMark) -> Bool:
  match left right:
    case Untracked{} Untracked{}: True{}
    case SourceBytes{a} SourceBytes{b}: sameBytes(a, b)
    case SourceError{a} SourceError{b}: String.eq(a, b)
    case _ _: False{}

def marked(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> SourceMark:
  match result:
    case Done{bytes}: SourceBytes{bytes}
    case Fail{error}: SourceError{FS.errorMessage(error)}

def sourceMark(path: Maybe<&2, String>) -> IO(SourceMark):
  match path:
    case None{}: IO.pure(SourceMark, Untracked{})
    case Some{value}:
      do IO<SourceMark>:
        result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(value)
        return marked(result)

def sourceFromPath(path: Maybe<&2, String>, baseline: List<&2, AiModels.Provider>, radius: Radius.RadiusTransport, mark: SourceMark) -> DefinitionSource:
  match path:
    case None{}: StaticSource{baseline}
    case Some{value}: FileSource{value, baseline, radius, mark}

def configFromMark(mark: SourceMark, path: String) -> IO(Config.ModelConfig):
  match mark:
    case SourceBytes{bytes}: IO.pure(Config.ModelConfig, Config.loaded(Done{bytes}, path))
    case _: Config.load(Some{path})

# upstream CreateModelRuntimeOptions, the fields that choose the models store
# and the create-time refresh (credentials, OAuth handlers, transport and the
# models path are the create functions' arguments). An injected modelsStore
# is owned by the runtime from here on. Not ported: modelRefreshTimeoutMs,
# which no non-experimental caller sets.
type CreateModelRuntimeOptions is Data:
  CreateModelRuntimeOptions{modelsStore: Maybe<&2, Store.ModelsStore>, modelsStorePath: Maybe<&2, String>, allowModelNetwork: Bool, catalogBaseUrl: Maybe<&2, String>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, refreshOnCreate: Bool}

# upstream's defaults: the store beside models.json, a create-time refresh
# without network access, pi.dev's catalog.
def createOptions() -> CreateModelRuntimeOptions: CreateModelRuntimeOptions{None{}, None{}, False{}, None{}, None{}, True{}}

def StoreChoice() -> Type: Store.ModelsStore & Maybe<&1, Files.FileModelsReadState>

def fileStore(+path: String, pair: Files.FileModelsReadState & Serial.Handle<Files.ReadState>) -> IO(StoreChoice()):
  match pair:
    case (state, handle):
      do IO<StoreChoice()>:
        store : Store.ModelsStore <- Files.fileModelsStore(path, handle)
        return (store, Some{state})

def storePathBeside(modelsPath: String) -> String: Path.join(Path.join(modelsPath, ".."), "models-store.json")

# upstream: the injected store, else a FileModelsStore (modelsStorePath, or
# models-store.json beside models.json), else an in-memory store when
# models.json is disabled.
def modelsStoreFor(injected: Maybe<&2, Store.ModelsStore>, storePath: Maybe<&2, String>, modelsPath: Maybe<&2, String>) -> IO(StoreChoice()):
  match injected modelsPath:
    case Some{store} _: IO.pure(StoreChoice(), (store, None{}))
    case None{} Some{path}:
      do IO<StoreChoice()>:
        state : Files.FileModelsReadState <- Files.newReadState()
        fileStore(Maybe.default(&2, String, storePath, storePathBeside(path)), Files.borrowReadState(state))
    case None{} None{}:
      do IO<StoreChoice()>:
        store : Store.ModelsStore <- Store.inMemoryModelsStore()
        return (store, None{})

def remoteCatalogOf(+provider: AiModels.Provider, +transport: Remote.RemoteCatalogTransport, +baseUrl: String) -> IO(AiModels.Provider):
  Bool.pick(Unit -> IO(AiModels.Provider), String.eq(providerId(provider), "radius"), _ => IO.pure(AiModels.Provider, provider), _ => Remote.withRemoteCatalog(provider, transport, baseUrl, Builtin.getBuiltinModelDataGeneratedAt()))(Unit{})

# upstream builtinProviders().map(withRemoteCatalog), Radius excepted.
def withRemoteCatalogs(providers: List<&2, AiModels.Provider>, +transport: Remote.RemoteCatalogTransport, +baseUrl: String) -> IO(List<&2, AiModels.Provider>):
  match providers:
    case Nil{}: IO.pure(List<&2, AiModels.Provider>, Nil{})
    case provider <> rest:
      do IO<List<&2, AiModels.Provider>>:
        wrapped : AiModels.Provider <- remoteCatalogOf(provider, transport, baseUrl)
        tail : List<&2, AiModels.Provider> <- withRemoteCatalogs(rest, transport, baseUrl)
        return wrapped <> tail

def remoteTransport(radius: Radius.RadiusTransport) -> Remote.RemoteCatalogTransport:
  match radius:
    case Radius.RadiusTransport{fetch, url}: Remote.RemoteCatalogTransport{fetch, url}

def locatedPath(path: Result<&2, &2, FS.Error, String>) -> Maybe<&2, String>:
  match path:
    case Done{path}: Some{path}
    case Fail{_}: None{}

# `<agentDir>/models.json`, the default models path.
def defaultModelsPath() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    path : Result<&2, &2, FS.Error, String> <- AppConfig.getModelsPath()
    return locatedPath(path)

def disposeProviders(providers: List<&2, AiModels.Provider>) -> IO(Unit):
  match providers:
    case Nil{}: IO.pure(Unit, Unit{})
    case provider <> rest:
      do IO<Unit>:
        AiModels.disposeProvider(provider)
        disposeProviders(rest)

def disposeOwned(items: List<&2, OwnedAuth>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit, Unit{})
    case OwnedApiKey{auth} <> rest:
      do IO<Unit>:
        Auth.disposeApiKeyAuth(auth)
        disposeOwned(rest)
    case OwnedToAuth{toAuth} <> rest:
      do IO<Unit>:
        C.dispose(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth)
        disposeOwned(rest)

def disposeGeneration(generation: Generation) -> IO(Unit):
  match generation:
    case Generation{owned, radius, refreshes}:
      do IO<Unit>:
        disposeOwned(owned)
        Composer.disposeRetained(refreshes)
        disposeProviders(radius)

def disposeGenerations(generations: List<&2, Generation>) -> IO(Unit):
  match generations:
    case Nil{}: IO.pure(Unit, Unit{})
    case generation <> rest:
      do IO<Unit>:
        disposeGeneration(generation)
        disposeGenerations(rest)

def baselineOf(source: DefinitionSource) -> List<&2, AiModels.Provider>:
  match source:
    case StaticSource{baseline}: baseline
    case FileSource{_, baseline, _, _}: baseline

def disposeDefinition(definition: Definition) -> IO(Unit):
  match definition:
    case Definition{_, _, _, _, generation, source, retired}:
      do IO<Unit>:
        disposeGeneration(generation)
        disposeGenerations(retired)
        disposeProviders(baselineOf(source))

def retireStoreState(state: Maybe<&1, Files.FileModelsReadState>) -> IO(Unit):
  match state:
    case None{}: IO.pure(Unit, Unit{})
    case Some{owner}: Files.disposeReadState(owner)

def disposeEntries(entries: List<&2, ExtensionEntry>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case ExtensionEntry{_, _, _, owned} <> rest:
      do IO<Unit>:
        disposeOwned(owned)
        disposeEntries(rest)

def extensionEntries(state: ExtensionState) -> List<&2, ExtensionEntry>:
  match state:
    case ExtensionState{entries, _}: entries

def apiStreamsOf(state: ExtensionState) -> Maybe<&2, Composer.ProviderStream()>:
  match state:
    case ExtensionState{_, streams}: streams

def disposeApiStreamsOf(streams: Maybe<&2, Composer.ProviderStream()>) -> IO(Unit):
  match streams:
    case None{}: IO.pure(Unit, Unit{})
    case Some{stream}: C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), stream)

def extensionsRef(runtime: ModelRuntime) -> Ref.Ref<ExtensionState>:
  match runtime:
    case ModelRuntime{_, _, _, _, extensions, _, _, _, _, _}: extensions

def entryId(entry: ExtensionEntry) -> String:
  match entry:
    case ExtensionEntry{id, _, _, _}: id

def findEntry(entries: List<&2, ExtensionEntry>, +id: String) -> Maybe<&2, ExtensionEntry>:
  match entries:
    case Nil{}: None{}
    case +entry <> rest: Bool.pick(Maybe<&2, ExtensionEntry>, String.eq(entryId(entry), id), Some{entry}, findEntry(rest, id))

def entryConfig(entry: Maybe<&2, ExtensionEntry>) -> Maybe<&2, Composer.ProviderConfigInput>:
  match entry:
    case Some{ExtensionEntry{_, config, _, _}}: config
    case None{}: None{}

# models.json load and provider composition errors, as upstream getError().
def joinedErrors(configError: Maybe<&2, String>, errors: List<&2, String>) -> Maybe<&2, String>:
  match configError errors:
    case None{} Nil{}: None{}
    case None{} errors: Some{String.join(errors, "\n\n")}
    case Some{error} errors: Some{String.join(error <> errors, "\n\n")}

def availabilityRef(runtime: ModelRuntime) -> Ref.Ref<AvailabilityStatus>:
  match runtime:
    case ModelRuntime{_, _, _, _, _, _, availability, _, _, _}: availability

def errorWithAvailability(base: Maybe<&2, String>, status: AvailabilityStatus) -> Maybe<&2, String>:
  match status base:
    case AvailabilityStatus{_, None{}} value: value
    case AvailabilityStatus{_, Some{error}} None{}: Some{"Availability refresh: " ++ error}
    case AvailabilityStatus{_, Some{error}} Some{previous}: Some{previous ++ "\n\nAvailability refresh: " ++ error}

def definitionError(definition: Definition) -> Maybe<&2,String>:
  match definition:
    case Definition{_,_,config,errors,_,_,_}: joinedErrors(Config.getError(config),errors)
def getError(+runtime: ModelRuntime) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2,String>>:
    definition : Definition <- Ref.read(Definition,definitionRef(runtime))
    status : AvailabilityStatus <- Ref.read(AvailabilityStatus,availabilityRef(runtime))
    return errorWithAvailability(definitionError(definition),status)

# Catalog
# -------

def streamsOf(provider: Maybe<&2, AiModels.Provider>) -> AiModels.ProviderStreams:
  match provider:
    case None{}: AiModels.ApiStreams{}
    case Some{found}: AiModels.providerStreams(found)

# How the provider's requests stream (upstream prepareRequest's provider).
def getProviderStreams(+runtime: ModelRuntime, +id: String) -> IO(AiModels.ProviderStreams):
  do IO<AiModels.ProviderStreams>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
    return streamsOf(provider)

def allModels(providers: List<&2, AiModels.Provider>) -> List<&2, Model()>: AiModels.allModels(providers)

def getModels(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  AiModels.getModels(modelsOf(runtime), None{})

def modelId(model: Model()) -> String:
  match model:
    case Ai.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def modelName(model: Model()) -> String:
  match model:
    case Ai.Model{_, name, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: name

def modelProvider(model: Model()) -> String:
  match model:
    case Ai.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def reference(+model: Model()) -> String: modelProvider(model) ++ "/" ++ modelId(model)

def findModel(models: List<&2, Model()>, +provider: String, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, Model()>, String.eq(modelProvider(model), provider) && String.eq(modelId(model), id), Some{model}, findModel(rest, provider, id))

def modelCacheRead(model: Model()) -> F64:
  match model: case Ai.Model{_, _, _, _, _, _, _, _, _, Ai.ModelCost{_, _, cacheRead, _, _}, _, _, _, _, _, _}: cacheRead

def getModel(+runtime: ModelRuntime, +provider: String, +id: String) -> IO(Maybe<&2, Model()>):
  do IO<Maybe<&2, Model()>>:
    models : List<&2, Model()> <- getModels(runtime)
    return findModel(models, provider, id)

# Cache statistics price the currently published model catalog.
def cacheReadPrice(models: List<&2, Model()>, provider: String) -> String -> Maybe<&2, F64>:
  id => Maybe.map(&2, Model(), F64, modelCacheRead, findModel(models, provider, id))

# Auth
# ----

def presentHeaders(values: List<&2, R.Property<String>>) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Ai.PresentValue{value}} <> presentHeaders(rest)

def configuredHeaders(configured: Maybe<&2, R.Record<String>>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match configured:
    case None{}: None{}
    case Some{values}: Some{R.Record{presentHeaders(R.entries(String, values))}}

def modelHeaders(resolution: Resolve.Resolution(), headers: Result<&2, &2, String, Maybe<&2, R.Record<String>>>) -> Resolve.Resolution():
  match resolution headers:
    case Fail{error} _: Fail{error}
    case Done{None{}} _: Done{None{}}
    case _ Fail{error}: Fail{Resolve.ModelsError{Resolve.AuthError{}, error}}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, existing, url}, env, source}}} Done{configured}: Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, AiModels.mergeHeaders(existing, configuredHeaders(configured)), url}, env, source}}}

def resolutionEnv(resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match resolution overrides:
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} Some{extra}: Some{Composer.spread(String, env, R.entries(String, extra))}
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} None{}: Some{env}
    case _ extra: extra

def ownHeaders(model: Model()) -> Maybe<&2, R.Record<String>>:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

# upstream Models.getAuth merges the model's own headers into the provider's
# request auth; ModelRuntime.getAuth then adds the model's configured
# headers (models.json and the extension registration).
def withModelHeaders(+model: Model(), config: Maybe<&2, Config.ModelsJsonProvider>, extension: Maybe<&2, Composer.ProviderConfigInput>, +resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> IO(Resolve.Resolution()):
  match resolution:
    case Done{Some{_}}:
      do IO<Resolve.Resolution()>:
        headers : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- Composer.resolveConfiguredModelHeaders(model, config, extension, resolutionEnv(resolution, overrides))
        return modelHeaders(modelHeaders(resolution, Done{ownHeaders(model)}), headers)
    case other: IO.pure(Resolve.Resolution(), other)

def overrideEnv(overrides: Resolve.AuthResolutionOverrides) -> Maybe<&2, Ai.ProviderEnv()>:
  match overrides:
    case Resolve.AuthResolutionOverrides{_, env, _, _}: env

def modelAuthFor(+runtime: ModelRuntime, +model: Model(), overrides: Resolve.AuthResolutionOverrides, provider: Maybe<&2, AiModels.Provider>) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Fail{unknownProvider(Ai.modelProvider(model))})
    case Some{_}: AiModels.getModelAuth(modelsOf(runtime), model, overrides)

# Request auth for a model (upstream getAuth(model)): the collection's
# (provider auth plus the model's static headers), then the model's
# configured models.json headers.
def getModelAuth(+runtime: ModelRuntime, +model: Model(), +overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, Ai.modelProvider(model))
    resolution : Resolve.Resolution() <- modelAuthFor(runtime, model, overrides, provider)
    state : ExtensionState <- Ref.read(ExtensionState, extensionsRef(runtime))
    config : Config.ModelConfig <- getModelConfig(runtime)
    withModelHeaders(model, Config.getProvider(config, Ai.modelProvider(model)), entryConfig(findEntry(extensionEntries(state), Ai.modelProvider(model))), resolution, overrideEnv(overrides))

def withoutId(ids: List<&2, String>, +id: String) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case +other <> +rest: Bool.pick(List<&2, String>, String.eq(other, id), withoutId(rest, id), other <> withoutId(rest, id))

def withProvider(ready: Bool, id: String, others: List<&2, String>) -> List<&2, String>:
  match ready:
    case True{}: id <> others
    case False{}: others

def sameKey(+left: Model(), +right: Model()) -> Bool: String.eq(modelProvider(left), modelProvider(right)) && String.eq(modelId(left), modelId(right))

def matching(models: List<&2, Model()>, +model: Model()) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +candidate <> rest: Bool.pick(Unit -> Maybe<&2, Model()>, sameKey(candidate, model), _ => Some{candidate}, _ => matching(rest, model))(Unit{})

# upstream refreshProviderAvailability's snapshot.available: every model in
# catalog order, the provider's from its new availability and the others'
# from the previous snapshot.
def mergedAvailable(all: List<&2, Model()>, +id: String, +fresh: List<&2, Model()>, +previous: List<&2, Model()>) -> List<&2, Model()>:
  match all:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = mergedAvailable(rest, id, fresh, previous)
      Maybe.default(&2, List<&2, Model()>, Maybe.map(&2, Model(), List<&2, Model()>, found => found <> tail, matching(Bool.pick(List<&2, Model()>, String.eq(modelProvider(model), id), fresh, previous), model)), tail)

def availabilityEntries(results: List<&2, AiModels.AvailabilityResult()>) -> List<&2, AiModels.Availability>:
  match results:
    case Nil{}: Nil{}
    case Done{entry} <> rest: entry <> availabilityEntries(rest)
    case Fail{_} <> rest: availabilityEntries(rest)

def entriesOf(result: AiModels.AvailabilitiesResult()) -> List<&2, AiModels.Availability>:
  match result:
    case Fail{_}: Nil{}
    case Done{results}: availabilityEntries(results)

def signalAborted(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{given}: Abort.aborted(Unit, given)

# upstream runAvailabilityRefresh: every provider's auth is checked again and
# the available models are those of the configured providers, narrowed by
# their filterModels. A provider whose check fails counts as unconfigured.
def publishAvailability(stopped: Bool, runtime: ModelRuntime, entries: List<&2, AiModels.Availability>) -> IO(Unit):
  match stopped:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (withAvailability(catalog, entries), Unit{}))

def refreshAvailability(+runtime: ModelRuntime, +signal: Auth.Signal()) -> IO(Unit):
  do IO<Unit>:
    result : AiModels.AvailabilitiesResult() <- AiModels.getAvailabilities(modelsOf(runtime), None{}, signal)
    stopped : Bool <- signalAborted(signal)
    publishAvailability(stopped, runtime, entriesOf(result))

def readied(catalog: Catalog, +id: String, +entries: List<&2, AiModels.Availability>, +all: List<&2, Model()>) -> Catalog:
  match catalog:
    case Catalog{natives, configured, +available}: Catalog{natives, withProvider(containsId(configuredIds(entries), id), id, withoutId(configured, id)), mergedAvailable(all, id, availableModels(entries), available)}

def publishProviderAvailability(stopped: Bool, runtime: ModelRuntime, id: String, entries: List<&2, AiModels.Availability>, all: List<&2, Model()>) -> IO(Unit):
  match stopped:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (readied(catalog, id, entries, all), Unit{}))

# Provider-local publication preserves unrelated availability and rejects a
# result that arrived after its caller cancelled.
def refreshProviderAvailability(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(Unit):
  do IO<Unit>:
    result : AiModels.AvailabilitiesResult() <- AiModels.getAvailabilities(modelsOf(runtime), Some{id}, signal)
    all : List<&2, Model()> <- getModels(runtime)
    stopped : Bool <- signalAborted(signal)
    publishProviderAvailability(stopped, runtime, id, entriesOf(result), all)

def configuredOf(catalog: Catalog) -> List<&2, String>:
  match catalog:
    case Catalog{_, configured, _}: configured

def hasConfiguredAuth(runtime: ModelRuntime, +id: String) -> IO(Bool):
  do IO<Bool>:
    catalog : Catalog <- readCatalog(runtime)
    return containsId(configuredOf(catalog), id)

def availableOf(catalog: Catalog) -> List<&2, Model()>:
  match catalog:
    case Catalog{_, _, available}: available

# The available models as of the last availability refresh (upstream
# snapshot.available): the configured providers' models, narrowed by their
# filterModels.
def getAvailableSnapshot(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    catalog : Catalog <- readCatalog(runtime)
    return availableOf(catalog)

def nextAvailability(status: AvailabilityStatus) -> AvailabilityStatus & Nat:
  match status:
    case AvailabilityStatus{generation, error}:
      +next = Nat.add(generation, 1n)
      (AvailabilityStatus{next, error}, next)

def availabilityAt(status: AvailabilityStatus, generation: Nat, error: Maybe<&2, String>) -> AvailabilityStatus & Unit:
  match status:
    case AvailabilityStatus{+current, previous}:
      (Bool.pick(AvailabilityStatus, Nat.is_eq(current, generation), AvailabilityStatus{current, error}, AvailabilityStatus{current, previous}), Unit{})

def finishAvailability(+runtime: ModelRuntime, generation: Nat, error: Maybe<&2, String>) -> IO(Unit):
  Ref.modify(AvailabilityStatus, Unit, availabilityRef(runtime), status => availabilityAt(status, generation, error))


def availableFailure(+runtime: ModelRuntime, generation: Nat, signal: Auth.Signal(), +error: Resolve.ModelsError) -> IO(AiModels.AvailableResult()):
  do IO<AiModels.AvailableResult()>:
    aborted : Bool <- signalAborted(signal)
    Bool.pick(Unit -> IO(Unit), aborted,
      _ => IO.pure(Unit, Unit{}),
      _ => finishAvailability(runtime, generation, Some{Resolve.errorMessage(error)}))(Unit{})
    return Fail{error}

def scopedResult(+runtime: ModelRuntime, signal: Auth.Signal(), generation: Nat, result: AiModels.AvailableResult()) -> IO(AiModels.AvailableResult()):
  match result:
    case Done{models}:
      do IO<AiModels.AvailableResult()>:
        finishAvailability(runtime, generation, None{})
        return Done{models}
    case Fail{error}: availableFailure(runtime, generation, signal, error)

def scopedAvailable(+runtime: ModelRuntime, id: String, +signal: Auth.Signal(), generation: Nat) -> IO(AiModels.AvailableResult()):
  do IO<AiModels.AvailableResult()>:
    result : AiModels.AvailableResult() <- AiModels.getAvailable(modelsOf(runtime), Some{id}, signal)
    scopedResult(runtime, signal, generation, result)

def refreshedEntries(+runtime: ModelRuntime, signal: Auth.Signal(), generation: Nat, entries: List<&2, AiModels.AvailabilityResult()>, result: AiModels.AvailableResult()) -> IO(AiModels.AvailableResult()):
  match result:
    case Fail{error}: availableFailure(runtime, generation, signal, error)
    case Done{models}:
      do IO<AiModels.AvailableResult()>:
        Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (withAvailability(catalog, availabilityEntries(entries)), Unit{}))
        finishAvailability(runtime, generation, None{})
        return Done{models}

def refreshedResult(+runtime: ModelRuntime, signal: Auth.Signal(), generation: Nat, result: AiModels.AvailabilitiesResult()) -> IO(AiModels.AvailableResult()):
  match result:
    case Fail{error}: availableFailure(runtime, generation, signal, error)
    case Done{+entries}: refreshedEntries(runtime, signal, generation, entries, AiModels.availableOf(Done{entries}))

def refreshedAvailable(+runtime: ModelRuntime, +signal: Auth.Signal(), generation: Nat) -> IO(AiModels.AvailableResult()):
  do IO<AiModels.AvailableResult()>:
    result : AiModels.AvailabilitiesResult() <- AiModels.getAvailabilities(modelsOf(runtime), None{}, signal)
    refreshedResult(runtime, signal, generation, result)

def availableFor(+runtime: ModelRuntime, id: Maybe<&2, String>, signal: Auth.Signal(), generation: Nat) -> IO(AiModels.AvailableResult()):
  match id:
    case Some{provider}: scopedAvailable(runtime, provider, signal, generation)
    case None{}: refreshedAvailable(runtime, signal, generation)

# A fresh availability read, optionally scoped to one provider. Scoped reads
# leave the shared snapshot unchanged; full reads replace it on success.
def getAvailable(+runtime: ModelRuntime, id: Maybe<&2, String>, signal: Auth.Signal()) -> IO(AiModels.AvailableResult()):
  do IO<AiModels.AvailableResult()>:
    generation : Nat <- Ref.modify(AvailabilityStatus, Nat, availabilityRef(runtime), nextAvailability)
    availableFor(runtime, id, signal, generation)

# Model resolution (model-resolver.ts)
# ------------------------------------

type DefaultModel is Data:
  DefaultModel{provider: String, id: String}

# upstream defaultModelPerProvider, in its key order, which
# findInitialModel follows. Entries for providers without a built-in port
# still apply to models.json providers of that id.
def defaultModelPerProvider() -> List<&2, DefaultModel>:
  [DefaultModel{"amazon-bedrock", "us.anthropic.claude-opus-4-6-v1"}, DefaultModel{"ant-ling", "Ring-2.6-1T"}, DefaultModel{"anthropic", "claude-opus-4-8"}, DefaultModel{"openai", "gpt-5.5"}, DefaultModel{"azure-openai-responses", "gpt-5.4"}, DefaultModel{"openai-codex", "gpt-5.5"}, DefaultModel{"radius", "balanced"}, DefaultModel{"nvidia", "nvidia/nemotron-3-super-120b-a12b"}, DefaultModel{"deepseek", "deepseek-v4-pro"}, DefaultModel{"google", "gemini-3.1-pro-preview"}, DefaultModel{"google-vertex", "gemini-3.1-pro-preview"}, DefaultModel{"github-copilot", "gpt-5.4"}, DefaultModel{"openrouter", "moonshotai/kimi-k2.6"}, DefaultModel{"vercel-ai-gateway", "zai/glm-5.1"}, DefaultModel{"xai", "grok-4.7"}, DefaultModel{"groq", "openai/gpt-oss-120b"}, DefaultModel{"cerebras", "gpt-oss-120b"}, DefaultModel{"zai", "glm-5.3"}, DefaultModel{"zai-coding-cn", "glm-5.3"}, DefaultModel{"mistral", "devstral-medium-latest"}, DefaultModel{"minimax", "MiniMax-M2.7"}, DefaultModel{"minimax-cn", "MiniMax-M2.7"}, DefaultModel{"moonshotai", "kimi-k2.6"}, DefaultModel{"moonshotai-cn", "kimi-k2.6"}, DefaultModel{"huggingface", "moonshotai/Kimi-K2.6"}, DefaultModel{"fireworks", "accounts/fireworks/models/kimi-k2p6"}, DefaultModel{"together", "moonshotai/Kimi-K2.6"}, DefaultModel{"baseten", "zai-org/GLM-5.2"}, DefaultModel{"opencode", "kimi-k2.6"}, DefaultModel{"opencode-go", "kimi-k2.6"}, DefaultModel{"kimi-coding", "kimi-for-coding"}, DefaultModel{"meta", "muse-spark-1.3"}, DefaultModel{"cloudflare-workers-ai", "@cf/moonshotai/kimi-k2.6"}, DefaultModel{"cloudflare-ai-gateway", "workers-ai/@cf/moonshotai/kimi-k2.6"}, DefaultModel{"qwen-token-plan", "qwen3.7-max"}, DefaultModel{"qwen-token-plan-cn", "qwen3.7-max"}, DefaultModel{"qwen-token-plan-individual", "qwen3.8-max"}, DefaultModel{"xiaomi", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-cn", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-ams", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-sgp", "mimo-v2.5-pro"}]

# A split text; tuples are affine types, so pairs of strings are data.
type Split is Data:
  Split{first: String, second: String}

def reversedDate(chars: List<&2, Char>) -> Bool:
  match chars:
    case a <> b <> c <> d <> e <> f <> g <> h <> '-' <> _: Char.is_digit(a) && Char.is_digit(b) && Char.is_digit(c) && Char.is_digit(d) && Char.is_digit(e) && Char.is_digit(f) && Char.is_digit(g) && Char.is_digit(h)
    case _: False{}

def endsWithDate(text: String) -> Bool:
  reversedDate(List.reverse(&2, Char, String.to_list(text)))

# -latest ids are aliases; -YYYYMMDD ids are dated versions.
def isAlias(+id: String) -> Bool:
  String.ends_with(id, "-latest") || Bool.not(endsWithDate(id))

def canonicalMatches(models: List<&2, Model()>, +normalized: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = canonicalMatches(rest, normalized)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(reference(model)), normalized), model <> tail, tail)

def idMatches(models: List<&2, Model()>, +normalized: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = idMatches(rest, normalized)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), normalized), model <> tail, tail)

# Zero matches fall through; more than one is ambiguous and rejects.
type Matched is Data:
  NoMatch{}
  OneMatch{model: Model()}
  Ambiguous{}

def matched(models: List<&2, Model()>) -> Matched:
  match models:
    case Nil{}: NoMatch{}
    case model <> Nil{}: OneMatch{model}
    case _: Ambiguous{}

def providerIdMatches(models: List<&2, Model()>, +provider: String, +id: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = providerIdMatches(rest, provider, id)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelProvider(model)), provider) && String.eq(String.to_lower(modelId(model)), id), model <> tail, tail)

def trimmedParts(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case head <> rest: Some{Split{String.trim(head), String.trim(String.join(rest, "/"))}}

def slashParts(text: String) -> Maybe<&2, Split>:
  trimmedParts(Strings.split(text, '/'))

def bareMatched(result: Matched) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case _: None{}

def bareMatch(models: List<&2, Model()>, normalized: String) -> Maybe<&2, Model()>:
  bareMatched(matched(idMatches(models, normalized)))

def providerMatched(result: Matched, models: List<&2, Model()>, normalized: String) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case Ambiguous{}: None{}
    case NoMatch{}: bareMatch(models, normalized)

def providerMatch(split: Maybe<&2, Split>, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match split:
    case Some{Split{SCon{p, ps}, SCon{i, ids}}}: providerMatched(matched(providerIdMatches(models, String.to_lower(SCon{p, ps}), String.to_lower(SCon{i, ids}))), models, normalized)
    case _: bareMatch(models, normalized)

def canonicalMatched(result: Matched, +reference: String, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case Ambiguous{}: None{}
    case NoMatch{}: providerMatch(slashParts(reference), models, normalized)

def exactReference(+reference: String, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match normalized:
    case SNil{}: None{}
    case _: canonicalMatched(matched(canonicalMatches(models, normalized)), reference, models, normalized)

# A bare id or canonical provider/id reference; ambiguous matches reject.
def findExactModelReferenceMatch(+reference: String, models: List<&2, Model()>) -> Maybe<&2, Model()>:
  exactReference(String.trim(reference), models, String.to_lower(String.trim(reference)))

def partialMatches(models: List<&2, Model()>, +pattern: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = partialMatches(rest, pattern)
      Bool.pick(List<&2, Model()>, String.contains(String.to_lower(modelId(model)), pattern) || String.contains(String.to_lower(modelName(model)), pattern), model <> tail, tail)

def aliases(models: List<&2, Model()>, +wanted: Bool) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = aliases(rest, wanted)
      Bool.pick(List<&2, Model()>, Bool.pick(Bool, wanted, isAlias(modelId(model)), Bool.not(isAlias(modelId(model)))), model <> tail, tail)

def notGreater(compared: (String & String) & Cmp) -> Bool:
  match compared:
    case Tuple{_, GT{}}: False{}
    case Tuple{_, _}: True{}

# left sorts at or after right in descending id order
def descending(left: Model(), right: Model()) -> Bool:
  notGreater(String.cmp(modelId(right), modelId(left)))

def highestFrom(models: List<&2, Model()>, +best: Model()) -> Model():
  match models:
    case Nil{}: best
    case +candidate <> rest: highestFrom(rest, Bool.pick(Model(), descending(best, candidate), best, candidate))

def highest(models: List<&2, Model()>) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case first <> rest: Some{highestFrom(rest, first)}

def preferredAlias(found: List<&2, Model()>, dated: List<&2, Model()>) -> Maybe<&2, Model()>:
  match found:
    case Nil{}: highest(dated)
    case aliased: highest(aliased)

# Prefer an alias; otherwise the latest dated version.
def preferred(+matches: List<&2, Model()>) -> Maybe<&2, Model()>:
  preferredAlias(aliases(matches, True{}), aliases(matches, False{}))

def tryMatchModel(+pattern: String, +models: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.or(&2, Model(), findExactModelReferenceMatch(pattern, models), preferred(partialMatches(models, String.to_lower(pattern))))

type ParsedModelResult is Data:
  ParsedModelResult{model: Maybe<&2, Model()>, thinkingLevel: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>}

def noMatch() -> ParsedModelResult: ParsedModelResult{None{}, None{}, None{}}

def splitReversed(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case suffix <> reversed: Some{Split{String.join(List.reverse(&2, String, reversed), ":"), suffix}}

def lastColonSplit(pattern: String) -> Maybe<&2, Split>:
  splitReversed(List.reverse(&2, String, Strings.split(pattern, ':')))

def thinkingLevel(value: String) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match value:
    case "off": Some{Ai.Off{}}
    case "minimal": Some{Ai.Thinking{Ai.Minimal{}}}
    case "low": Some{Ai.Thinking{Ai.Low{}}}
    case "medium": Some{Ai.Thinking{Ai.Medium{}}}
    case "high": Some{Ai.Thinking{Ai.High{}}}
    case "xhigh": Some{Ai.Thinking{Ai.XHigh{}}}
    case "max": Some{Ai.Thinking{Ai.Max{}}}
    case _: None{}

def withLevel(result: ParsedModelResult, level: Ai.ModelThinkingLevel) -> ParsedModelResult:
  match result:
    case ParsedModelResult{Some{model}, _, None{}}: ParsedModelResult{Some{model}, Some{level}, None{}}
    case other: other

def withWarning(result: ParsedModelResult, +suffix: String, +pattern: String) -> ParsedModelResult:
  match result:
    case ParsedModelResult{Some{model}, _, _}: ParsedModelResult{Some{model}, None{}, Some{"Invalid thinking level \"" ++ suffix ++ "\" in pattern \"" ++ pattern ++ "\". Using default instead."}}
    case other: other

# "pattern:level" parsing. Bend has no mutual recursion, so the loop carries
# the exact match and the last-colon split of each candidate as data and
# recurses on fuel; ids with colons still match when the full text does.
type PatternStep is Data:
  PatternStep{pattern: String, exact: Maybe<&2, Model()>, split: Maybe<&2, Split>}

def stepOf(+pattern: String, models: List<&2, Model()>) -> PatternStep:
  PatternStep{pattern, tryMatchModel(pattern, models), lastColonSplit(pattern)}

def combined(+level: Maybe<&2, Ai.ModelThinkingLevel>, +inner: ParsedModelResult, suffix: String, pattern: String, allowFallback: Bool) -> ParsedModelResult:
  match level allowFallback:
    case Some{level} _: withLevel(inner, level)
    case None{} True{}: withWarning(inner, suffix, pattern)
    case None{} False{}: noMatch()

def parseLoop(fuel: Nat, step: PatternStep, +models: List<&2, Model()>, +allowFallback: Bool) -> ParsedModelResult:
  match fuel step:
    case _ PatternStep{_, Some{model}, _}: ParsedModelResult{Some{model}, None{}, None{}}
    case _ PatternStep{_, None{}, None{}}: noMatch()
    case 0n PatternStep{_, None{}, Some{_}}: noMatch()
    case 1n+n PatternStep{pattern, None{}, Some{Split{prefix, +suffix}}}: combined(thinkingLevel(suffix), parseLoop(n, stepOf(prefix, models), models, allowFallback), suffix, pattern, allowFallback)

def parsePattern(+pattern: String, +models: List<&2, Model()>, allowFallback: Bool) -> ParsedModelResult:
  parseLoop(1n + String.length(pattern), stepOf(pattern, models), models, allowFallback)

# Resolve the authenticated --models scope in CLI order. An invalid pattern
# fails startup rather than silently widening the cycling set.
type ScopedModel is Data: ScopedModel{model: Model(), thinking: Maybe<&2,Ai.ModelThinkingLevel>}

def scopedContains(items: List<&2,ScopedModel>,+model: Model()) -> Bool:
  match items:
    case Nil{}: False{}
    case ScopedModel{+previous,_} <> rest:
      (String.eq(modelProvider(previous),modelProvider(model)) && String.eq(modelId(previous),modelId(model))) || scopedContains(rest,model)
def addScoped(+items: List<&2,ScopedModel>,+model: Model(),thinking: Maybe<&2,Ai.ModelThinkingLevel>) -> List<&2,ScopedModel>:
  Bool.pick(List<&2,ScopedModel>,scopedContains(items,model),items,List.append(&2,ScopedModel,items,ScopedModel{model,thinking} <> Nil{}))
def globMatches(models: List<&2,Model()>,+pattern: Glob.Pattern) -> List<&2,Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = globMatches(rest,pattern)
      +id = String.to_lower(modelId(model))
      +full = String.to_lower(reference(model))
      Bool.pick(List<&2,Model()>,Glob.matches(pattern,id) || Glob.matches(pattern,full),model <> tail,tail)
def addGlobMatches(models: List<&2,Model()>,+thinking: Maybe<&2,Ai.ModelThinkingLevel>,items: List<&2,ScopedModel>) -> List<&2,ScopedModel>:
  match models:
    case Nil{}: items
    case model <> rest: addGlobMatches(rest,thinking,addScoped(items,model,thinking))
def scopedGlobResult(pattern: String,thinking: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>,compiled: Result<&2,&2,Glob.Error,Glob.Pattern>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match compiled:
    case Fail{_}: Fail{"Invalid model glob pattern: " ++ pattern}
    case Done{glob}:
      +matches = globMatches(models,glob)
      Bool.pick(Result<&2,&2,String,List<&2,ScopedModel>>,List.is_empty(&2,Model(),matches),Fail{"No models match pattern: " ++ pattern},Done{addGlobMatches(matches,thinking,items)})
def scopedGlob(pattern: String,globText: String,thinking: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  scopedGlobResult(pattern,thinking,models,items,Glob.compile(String.to_lower(globText)))
def scopedGlobLevel(+pattern: String,prefix: String,level: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match level:
    case Some{chosen}: scopedGlob(pattern,prefix,Some{chosen},models,items)
    case None{}: scopedGlob(pattern,pattern,None{},models,items)
def scopedGlobSuffix(+pattern: String,split: Maybe<&2,Split>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match split:
    case Some{Split{prefix,suffix}}: scopedGlobLevel(pattern,prefix,thinkingLevel(suffix),models,items)
    case None{}: scopedGlob(pattern,pattern,None{},models,items)
def scopedParsed(pattern: String,items: List<&2,ScopedModel>,parsed: ParsedModelResult) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match parsed:
    case ParsedModelResult{Some{model},thinking,None{}}: Done{addScoped(items,model,thinking)}
    case ParsedModelResult{_,_,Some{_}}: Fail{"Invalid thinking level in model pattern: " ++ pattern}
    case _: Fail{"No models match pattern: " ++ pattern}
def scopedPlain(+pattern: String,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  scopedParsed(pattern,items,parsePattern(pattern,models,True{}))
def scopedOne(+pattern: String,+models: List<&2,Model()>,+items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  Bool.pick(Unit -> Result<&2,&2,String,List<&2,ScopedModel>>,String.contains(pattern,"*") || String.contains(pattern,"?") || String.contains(pattern,"["),_ => scopedGlobSuffix(pattern,lastColonSplit(pattern),models,items),_ => scopedPlain(pattern,models,items))(Unit{})
def resolveScope(patterns: List<&2,String>,+models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match patterns:
    case Nil{}: Done{items}
    case pattern <> rest:
      Result.bind(&2,&2,String,List<&2,ScopedModel>,List<&2,ScopedModel>,scopedOne(pattern,models,items),next => resolveScope(rest,models,next))

# Keep stale settings references visible in the scope picker while still
# resolving every valid pattern. Invalid pattern syntax remains an error.
type ScopeResolution is Data: ScopeResolution{scoped: List<&2,ScopedModel>, unmatched: List<&2,String>}
def scopeStep(+pattern: String,+scoped: List<&2,ScopedModel>,+unmatched: List<&2,String>,result: Result<&2,&2,String,List<&2,ScopedModel>>) -> Result<&2,&2,String,ScopeResolution>:
  match result:
    case Done{next}: Done{ScopeResolution{next,unmatched}}
    case Fail{+error}:
      Bool.pick(Unit -> Result<&2,&2,String,ScopeResolution>,String.starts_with(error,"No models match pattern: "),_ => Done{ScopeResolution{scoped,List.append(&2,String,unmatched,[pattern])}},_ => Fail{error})(Unit{})
def resolvedModels(result: ScopeResolution) -> List<&2,ScopedModel>:
  match result: case ScopeResolution{scoped,_}: scoped
def unresolvedPatterns(result: ScopeResolution) -> List<&2,String>:
  match result: case ScopeResolution{_,unmatched}: unmatched
def resolveScopeWithMissing(patterns: List<&2,String>, +models: List<&2,Model()>, +scoped: List<&2,ScopedModel>, unmatched: List<&2,String>) -> Result<&2,&2,String,ScopeResolution>:
  match patterns:
    case Nil{}: Done{ScopeResolution{scoped,unmatched}}
    case +pattern <> rest:
      Result.bind(&2,&2,String,ScopeResolution,ScopeResolution,scopeStep(pattern,scoped,unmatched,scopedOne(pattern,models,scoped)),+next => resolveScopeWithMissing(rest,models,resolvedModels(next),unresolvedPatterns(next)))

type ResolveCliModelResult is Data:
  ResolveCliModelResult{model: Maybe<&2, Model()>, thinkingLevel: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, error: Maybe<&2, String>}

def cliError(message: String) -> ResolveCliModelResult: ResolveCliModelResult{None{}, None{}, None{}, Some{message}}

def canonicalProvider(models: List<&2, Model()>, +wanted: String) -> Maybe<&2, String>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, String>, String.eq(String.to_lower(modelProvider(model)), wanted), Some{modelProvider(model)}, canonicalProvider(rest, wanted))

def providerModelsOf(models: List<&2, Model()>, +provider: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = providerModelsOf(rest, provider)
      Bool.pick(List<&2, Model()>, String.eq(modelProvider(model), provider), model <> tail, tail)

def splitSlash(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case head <> rest: Some{Split{head, String.join(rest, "/")}}

def slashSplit(text: String) -> Maybe<&2, Split>:
  splitSlash(Strings.split(text, '/'))

def stripPrefix(+pattern: String, +prefix: String) -> String:
  Bool.pick(String, String.starts_with(String.to_lower(pattern), String.to_lower(prefix)), String.drop(pattern, String.length(prefix)), pattern)

def resolved(parsed: ParsedModelResult) -> ResolveCliModelResult:
  match parsed:
    case ParsedModelResult{model, level, warning}: ResolveCliModelResult{model, level, warning, None{}}

def resolveWithin(provider: String, pattern: String, models: List<&2, Model()>) -> ResolveCliModelResult:
  resolved(parsePattern(pattern, providerModelsOf(models, provider), False{}))

# upstream buildFallbackModel: an unknown id on a known provider borrows the
# provider's default model (else its first) under the requested id.
def renamed(model: Model(), +id: String) -> Model():
  match model:
    case Ai.Model{_, _, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}:
      Ai.Model{id, id, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def defaultIdOf(defaults: List<&2, DefaultModel>, +provider: String) -> Maybe<&2, String>:
  match defaults:
    case Nil{}: None{}
    case DefaultModel{name, id} <> rest: Bool.pick(Maybe<&2, String>, String.eq(name, provider), Some{id}, defaultIdOf(rest, provider))

def baseModelOf(+provider: String, +candidates: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.or(&2, Model(), Maybe.bind(&2, String, Model(), defaultIdOf(defaultModelPerProvider(), provider), id => findModel(candidates, provider, id)), List.head(&2, Model(), candidates))

def buildFallbackModel(+provider: String, +modelId: String, models: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.map(&2, Model(), Model(), model => renamed(model, modelId), baseModelOf(provider, providerModelsOf(models, provider)))

def withReasoning(model: Model(), requested: Maybe<&2, Ai.ModelThinkingLevel>) -> Model():
  match model requested:
    case Ai.Model{id, name, api, provider, baseUrl, _, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} Some{Ai.Thinking{_}}:
      Ai.Model{id, name, api, provider, baseUrl, True{}, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}
    case _ _: model

def notFound(+display: String, warning: Maybe<&2, String>) -> ResolveCliModelResult:
  ResolveCliModelResult{None{}, None{}, warning, Some{"Model \"" ++ display ++ "\" not found. Use --list-models to see available models."}}

def fallbackWarning(warning: Maybe<&2, String>, +message: String) -> String:
  match warning:
    case None{}: message
    case Some{earlier}: earlier ++ " " ++ message

# The id and a thinking level from a trailing ":<level>", unless --thinking
# was given.
def suffixLevel(split: Maybe<&2, Split>) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match split:
    case Some{Split{_, suffix}}: thinkingLevel(suffix)
    case None{}: None{}

def suffixPrefix(split: Maybe<&2, Split>, +pattern: String) -> String:
  match split:
    case Some{Split{prefix, _}}: prefix
    case None{}: pattern

def fallbackBuilt(+provider: String, +pattern: String, +id: String, +level: Maybe<&2, Ai.ModelThinkingLevel>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, built: Maybe<&2, Model()>) -> ResolveCliModelResult:
  match built:
    case None{}: notFound(provider ++ "/" ++ pattern, warning)
    case Some{model}: ResolveCliModelResult{Some{withReasoning(model, Maybe.or(&2, Ai.ModelThinkingLevel, cliThinking, level))}, level, Some{fallbackWarning(warning, "Model \"" ++ id ++ "\" not found for provider \"" ++ provider ++ "\". Using custom model id.")}, None{}}

def fallbackSplit(+provider: String, +pattern: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, +split: Maybe<&2, Split>, models: List<&2, Model()>) -> ResolveCliModelResult:
  +level = suffixLevel(split)
  +id = Bool.pick(String, Maybe.is_some(&2, Ai.ModelThinkingLevel, level), suffixPrefix(split, pattern), pattern)
  fallbackBuilt(provider, pattern, id, level, cliThinking, warning, buildFallbackModel(provider, id, models))

def fallbackResult(+provider: String, +pattern: String, +cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, models: List<&2, Model()>) -> ResolveCliModelResult:
  fallbackSplit(provider, pattern, cliThinking, warning, Bool.pick(Maybe<&2, Split>, Maybe.is_some(&2, Ai.ModelThinkingLevel, cliThinking), None{}, lastColonSplit(pattern)), models)

# upstream resolveCliModel's tail: a known provider without a match falls back
# to a custom model id; otherwise the model is not found.
def orFallback(+provider: String, +pattern: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, models: List<&2, Model()>, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{None{}, _, warning, None{}}: fallbackResult(provider, pattern, cliThinking, warning, models)
    case other: other

def orNotFound(+display: String, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{None{}, _, warning, None{}}: notFound(display, warning)
    case other: other

def resolveAcross(pattern: String, models: List<&2, Model()>) -> ResolveCliModelResult:
  resolved(parsePattern(pattern, models, False{}))

# The pure resolution; an ambiguous bare id carries its matches so the caller
# can order them as upstream's localeCompare does.
type Resolution is Data:
  Resolved{result: ResolveCliModelResult}
  AmbiguousAcross{cliModel: String, matches: List<&2, String>, hint: String}

def found(model: Model()) -> ResolveCliModelResult: ResolveCliModelResult{Some{model}, None{}, None{}, None{}}
def authedIn(authed: List<&2, String>, +provider: String) -> Bool:
  match authed:
    case Nil{}: False{}
    case name <> rest: String.eq(name, provider) || authedIn(rest, provider)
def authenticatedAmong(models: List<&2, Model()>, +authed: List<&2, String>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = authenticatedAmong(rest, authed)
      Bool.pick(List<&2, Model()>, authedIn(authed, modelProvider(model)), model <> tail, tail)
def referenceOf(+model: Model()) -> String: modelProvider(model) ++ "/" ++ modelId(model)
def references(models: List<&2, Model()>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: referenceOf(model) <> references(rest)
def ambiguousBare(+cliModel: String, +matches: List<&2, Model()>, authenticated: List<&2, Model()>) -> Resolution:
  match authenticated:
    case one <> Nil{}: Resolved{found(one)}
    case Nil{}: AmbiguousAcross{cliModel, references(matches), "No matching provider is authenticated."}
    case _: AmbiguousAcross{cliModel, references(matches), "More than one matching provider is authenticated."}
def exactAmong(+cliModel: String, +one: Model(), +more: List<&2, Model()>, +authed: List<&2, String>) -> Resolution:
  match more:
    case Nil{}: Resolved{found(one)}
    case _: ambiguousBare(cliModel, one <> more, authenticatedAmong(one <> more, authed))
# upstream: without a provider, an exact id (or provider/id) match wins; several
# prefer the sole authenticated provider, otherwise the id is ambiguous.
def bareExact(+cliModel: String, exact: List<&2, Model()>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match exact:
    case Nil{}: Resolved{orNotFound(cliModel, resolveAcross(cliModel, models))}
    case +one <> more: exactAmong(cliModel, one, more, authed)
def exactMatches(models: List<&2, Model()>, +lower: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = exactMatches(rest, lower)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), lower) || String.eq(String.to_lower(referenceOf(model)), lower), model <> tail, tail)
def bareResolution(+cliModel: String, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  bareExact(cliModel, exactMatches(models, String.to_lower(cliModel)), authed, models)

# upstream: an inferred provider/model on an unauthenticated provider yields to
# the one authenticated model whose raw id is the whole input.
def sameModel(+left: Model(), +right: Model()) -> Bool: String.eq(modelProvider(left), modelProvider(right)) && String.eq(modelId(left), modelId(right))
def rawIdMatches(models: List<&2, Model()>, +lower: String, +chosen: Model()) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = rawIdMatches(rest, lower, chosen)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), lower) && Bool.not(sameModel(model, chosen)), model <> tail, tail)
def soleAuthenticated(candidates: List<&2, Model()>, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match candidates:
    case one <> Nil{}: found(one)
    case _: result
def preferAuthenticatedRaw(+cliModel: String, result: ResolveCliModelResult, +authed: List<&2, String>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{Some{+model}, +level, +warning, None{}}:
      Bool.pick(Unit -> ResolveCliModelResult, authedIn(authed, modelProvider(model)),
        _ => ResolveCliModelResult{Some{model}, level, warning, None{}},
        _ => soleAuthenticated(authenticatedAmong(rawIdMatches(models, String.to_lower(cliModel), model), authed), ResolveCliModelResult{Some{model}, level, warning, None{}}))(Unit{})
    case other: other

# upstream: when the inferred provider has no match, the whole input is tried as
# a raw id (first exact id or provider/id match), then as a pattern.
def firstExact(+cliModel: String, exact: List<&2, Model()>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match exact:
    case one <> _: found(one)
    case Nil{}: resolveAcross(cliModel, models)
def fallbackAcross(+cliModel: String, scoped: ResolveCliModelResult, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match scoped:
    case ResolveCliModelResult{None{}, _, _, None{}}: firstExact(cliModel, exactMatches(models, String.to_lower(cliModel)), models)
    case other: other

def resolveCandidate(+cliModel: String, +provider: Maybe<&2, String>, +rest: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match provider:
    case None{}: bareResolution(cliModel, authed, models)
    case Some{+provider}: Resolved{orFallback(provider, rest, cliThinking, models, fallbackAcross(cliModel, preferAuthenticatedRaw(cliModel, resolveWithin(provider, rest, models), authed, models), models))}

# "provider/model" prefers the provider interpretation when the prefix names a
# known provider; a failed provider-scoped match falls back to the full text.
def resolveInferred(+cliModel: String, split: Maybe<&2, Split>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match split:
    case None{}: bareResolution(cliModel, authed, models)
    case Some{Split{+head, +rest}}: resolveCandidate(cliModel, canonicalProvider(models, String.to_lower(head)), rest, cliThinking, authed, models)

def resolveKnown(+provider: Maybe<&2, String>, cliProvider: String, cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match provider:
    case None{}: cliError("Unknown provider \"" ++ cliProvider ++ "\". Use --list-models to see available providers/models.")
    case Some{+provider}:
      +pattern = stripPrefix(cliModel, provider ++ "/")
      orFallback(provider, pattern, cliThinking, models, resolveWithin(provider, pattern, models))

def resolveExplicit(+cliProvider: String, cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  resolveKnown(canonicalProvider(models, String.to_lower(cliProvider)), cliProvider, cliModel, cliThinking, models)

def resolveCliModelWith(cliProvider: Maybe<&2, String>, +cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match cliProvider models:
    case _ Nil{}: Resolved{cliError("No models available. Check your installation or add models to models.json.")}
    case Some{provider} _: Resolved{resolveExplicit(provider, cliModel, cliThinking, models)}
    case None{} _: resolveInferred(cliModel, slashSplit(cliModel), cliThinking, authed, models)

# Providers with configured auth among the models' providers.
def providersOf(models: List<&2, Model()>, +seen: List<&2, String>) -> List<&2, String>:
  match models:
    case Nil{}: List.reverse(&2, String, seen)
    case model <> rest:
      +provider = modelProvider(model)
      providersOf(rest, Bool.pick(List<&2, String>, authedIn(seen, provider), seen, provider <> seen))
def authenticatedProviders(+runtime: ModelRuntime, providers: List<&2, String>) -> IO(List<&2, String>):
  match providers:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +provider <> rest:
      do IO<List<&2, String>>:
        configured : Bool <- hasConfiguredAuth(runtime, provider)
        +more : List<&2, String> <- authenticatedProviders(runtime, rest)
        return Bool.pick(List<&2, String>, configured, provider <> more, more)

# Uses all models, not just authenticated ones, so --api-key works for
# first-time setup; configured auth only breaks ties between providers.
def resolveCliModel(+runtime: ModelRuntime, cliProvider: Maybe<&2, String>, cliModel: Maybe<&2, String>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>) -> IO(Resolution):
  match cliModel:
    case None{}: IO.pure(Resolution, Resolved{ResolveCliModelResult{None{}, None{}, None{}, None{}}})
    case Some{pattern}:
      do IO<Resolution>:
        +models : List<&2, Model()> <- getModels(runtime)
        authed : List<&2, String> <- authenticatedProviders(runtime, providersOf(models, Nil{}))
        return resolveCliModelWith(cliProvider, pattern, cliThinking, authed, models)

# The ambiguity message lists the matches in upstream's localeCompare order.
def ambiguityMessage(cliModel: String, sorted: List<&2, String>, hint: String) -> ResolveCliModelResult:
  cliError("Model \"" ++ cliModel ++ "\" is ambiguous across providers: " ++ String.join(sorted, ", ") ++ ". " ++ hint ++ " Use --provider or provider/model.")

def defaultAmong(defaults: List<&2, DefaultModel>, +models: List<&2, Model()>) -> Maybe<&2, Model()>:
  match defaults:
    case Nil{}: List.head(&2, Model(), models)
    case DefaultModel{provider, id} <> rest: Maybe.or(&2, Model(), findModel(models, provider, id), defaultAmong(rest, models))

def authorizedModel(+runtime: ModelRuntime, found: Maybe<&2, Model()>) -> IO(Maybe<&2, Model()>):
  match found:
    case None{}: IO.pure(Maybe<&2, Model()>, None{})
    case Some{+model}:
      do IO<Maybe<&2, Model()>>:
        configured : Bool <- hasConfiguredAuth(runtime, modelProvider(model))
        return Bool.pick(Maybe<&2, Model()>, configured, Some{model}, None{})

def savedDefault(+runtime: ModelRuntime, defaultProvider: Maybe<&2, String>, defaultModelId: Maybe<&2, String>) -> IO(Maybe<&2, Model()>):
  match defaultProvider defaultModelId:
    case Some{provider} Some{id}:
      do IO<Maybe<&2, Model()>>:
        found : Maybe<&2, Model()> <- getModel(runtime, provider, id)
        authorizedModel(runtime, found)
    case _ _: IO.pure(Maybe<&2, Model()>, None{})

def firstAvailable(+runtime: ModelRuntime, saved: Maybe<&2, Model()>) -> IO(Maybe<&2, Model()>):
  match saved:
    case Some{model}: IO.pure(Maybe<&2, Model()>, Some{model})
    case None{}:
      do IO<Maybe<&2, Model()>>:
        available : List<&2, Model()> <- getAvailableSnapshot(runtime)
        return defaultAmong(defaultModelPerProvider(), available)

# Without a CLI model: the settings' saved default when its provider is
# authenticated, else the first known default whose provider is
# authenticated, otherwise the first available model (upstream steps 3–4;
# scoped models are not ported).
def findInitialModel(+runtime: ModelRuntime, defaultProvider: Maybe<&2, String>, defaultModelId: Maybe<&2, String>) -> IO(Maybe<&2, Model()>):
  do IO<Maybe<&2, Model()>>:
    saved : Maybe<&2, Model()> <- savedDefault(runtime, defaultProvider, defaultModelId)
    firstAvailable(runtime, saved)

# Extension providers and dynamic catalogs
# ----------------------------------------

def withoutProvider(providers: List<&2, AiModels.Provider>, +id: String) -> List<&2, AiModels.Provider>: AiModels.withoutProvider(providers, id)

# An id keeps its position when an extension registers it again.
def replacedProvider(+providers: List<&2, AiModels.Provider>, +provider: AiModels.Provider) -> List<&2, AiModels.Provider>: AiModels.upserted(providers, provider)

def withNatives(catalog: Catalog, update: List<&2, AiModels.Provider> -> List<&2, AiModels.Provider>) -> Catalog:
  match catalog:
    case Catalog{natives, configured, available}: Catalog{update(natives), configured, available}

def registeredNative(+provider: AiModels.Provider, catalog: Catalog) -> Catalog:
  withNatives(catalog, natives => replacedProvider(natives, provider))

def unregisteredNative(+id: String, catalog: Catalog) -> Catalog:
  withNatives(catalog, natives => withoutProvider(natives, id))

def isBlank(text: String) -> Bool: String.is_empty(String.trim(text))

type ModelsRefreshOptions is Data:
  ModelsRefreshOptions{allowNetwork: Maybe<&2, Bool>, providers: Maybe<&2, List<&2, String>>, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

def refreshOptions() -> ModelsRefreshOptions: ModelsRefreshOptions{None{}, None{}, None{}, None{}}

# `errors` maps provider ids to the refresh failure message.

def availabilityOf(+runtime: ModelRuntime, ids: List<&2, String>, +signal: Auth.Signal()) -> IO(Unit):
  match ids:
    case Nil{}: IO.pure(Unit, Unit{})
    case id <> rest:
      do IO<Unit>:
        refreshProviderAvailability(runtime, id, signal)
        availabilityOf(runtime, rest, signal)

def refreshedAvailability(+runtime: ModelRuntime, filter: Maybe<&2, List<&2, String>>, signal: Auth.Signal()) -> IO(Unit):
  match filter:
    case None{}: refreshAvailability(runtime, signal)
    case Some{ids}: availabilityOf(runtime, ids, signal)

def refreshResult(result: AiModels.ModelsRefreshResult, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ModelsRefreshResult):
  match result signal:
    case AiModels.ModelsRefreshResult{aborted, errors} None{}: IO.pure(ModelsRefreshResult, ModelsRefreshResult{aborted, errors})
    case AiModels.ModelsRefreshResult{aborted, errors} Some{caller}:
      do IO<ModelsRefreshResult>:
        stopped : Bool <- Abort.aborted(Unit, caller)
        return ModelsRefreshResult{aborted || stopped, errors}

def networkEnabled(offline: Result<&1, &1, U32 & String, String>) -> Bool:
  match offline:
    case Done{_}: False{}
    case Fail{_}: True{}

def recomposeFile(+runtime: ModelRuntime, +oldProviders: List<&2, AiModels.Provider>, previous: Generation, retired: List<&2, Generation>, +path: String, +baseline: List<&2, AiModels.Provider>, +radius: Radius.RadiusTransport, +mark: SourceMark) -> IO(Definition & Bool):
  do IO<Definition & Bool>:
    +config : Config.ModelConfig <- configFromMark(mark, path)
    +builtins : List<&2, AiModels.Provider> <- configureRadiusProviders(Config.getProviderIds(config), baseline, config, radius)
    +composition : Composition <- rebuildProviders(composedIds(builtins, config), builtins, config, Composition{Nil{}, Nil{}, Nil{}, Nil{}})
    +providers : List<&2, AiModels.Provider> = compositionProviders(composition)
    catalog : Catalog <- readCatalog(runtime)
    AiModels.rebuildProviders(modelsOf(runtime), effectiveProviders(providers, builtinIds(builtins), nativesOf(catalog)), List.append(&2, String, AiModels.providerIds(oldProviders), AiModels.providerIds(providers)))
    return (composedDefinition(composition, builtins, config, FileSource{path, baseline, radius, mark}, previous <> retired), True{})

def reloadIfChanged(runtime: ModelRuntime, definition: Definition, observed: SourceMark, same: Bool) -> IO(Definition & Bool):
  match definition same:
    case definition True{}: IO.pure(Definition & Bool, (definition, False{}))
    case Definition{providers, _, _, _, generation, FileSource{path, baseline, radius, _}, retired} False{}:
      recomposeFile(runtime, providers, generation, retired, path, baseline, radius, observed)
    case definition False{}: IO.pure(Definition & Bool, (definition, False{}))

def reloadDefinition(runtime: ModelRuntime, +definition: Definition) -> IO(Definition & Bool):
  match definition:
    case Definition{_, _, _, _, _, StaticSource{_}, _}: IO.pure(Definition & Bool, (definition, False{}))
    case Definition{_, _, _, _, _, FileSource{path, _, _, +mark}, _}:
      do IO<Definition & Bool>:
        +observed : SourceMark <- sourceMark(Some{path})
        reloadIfChanged(runtime, definition, observed, sameMark(mark, observed))

def reloadConfig(+runtime: ModelRuntime) -> IO(Bool):
  Ref.update(Definition, Bool, definitionRef(runtime), definition => reloadDefinition(runtime, definition))

# upstream ModelRuntime.refresh: the collection refreshes the dynamic
# providers (all, or the selected ones) with the network allowed by default
# unless PI_OFFLINE is set; then availability is checked again.
def refreshTask(+runtime: ModelRuntime, options: ModelsRefreshOptions) -> IO(ModelsRefreshResult):
  match options:
    case ModelsRefreshOptions{allowNetwork, +filter, force, +signal}:
      do IO<ModelsRefreshResult>:
        changed : Bool <- reloadConfig(runtime)
        offline : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_OFFLINE")
        result : AiModels.ModelsRefreshResult <- AiModels.refresh(modelsOf(runtime), AiModels.ModelsRefreshOptions{Some{Maybe.default(&2, Bool, allowNetwork, networkEnabled(offline))}, filter, force, signal})
        refreshedAvailability(runtime, filter, signal)
        refreshResult(result, signal)

# One all-catalog network request serves concurrent interactive callers. A
# caller's signal stops only its own wait; the last departing caller aborts
# the request. A later caller can then start fresh immediately.
type SharedAdmission is Data:
  StartRefresh{id: Nat, controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>}
  JoinRefresh{id: Nat, result: Deferred.Deferred<ModelsRefreshResult>, unusedController: Abort.AbortController<Unit>, unusedResult: Deferred.Deferred<ModelsRefreshResult>}
  ClosedRefresh{unusedController: Abort.AbortController<Unit>, unusedResult: Deferred.Deferred<ModelsRefreshResult>}

def admitRefresh(state: SharedRefresh, +candidate: Abort.AbortController<Unit>, +outcome: Deferred.Deferred<ModelsRefreshResult>) -> SharedRefresh & SharedAdmission:
  match state:
    case RefreshIdle{+id}: (RefreshActive{id,candidate,outcome,1n,False{},False{}},StartRefresh{id,candidate,outcome})
    case RefreshActive{+id,+controller,+result,waiters,finished,closing}:
      (RefreshActive{id,controller,result,waiters + 1n,finished,closing},JoinRefresh{id,result,candidate,outcome})
    case RefreshClosed{}: (RefreshClosed{},ClosedRefresh{candidate,outcome})

def sharedRef(runtime: ModelRuntime) -> Ref.Ref<SharedRefresh>:
  match runtime:
    case ModelRuntime{_,_,_,_,_,sharedRefresh,_,_,_, _}: sharedRefresh

def workRef(runtime: ModelRuntime) -> Ref.Ref<RefreshWork>:
  match runtime:
    case ModelRuntime{_,_,_,_,_,_,_,_,work, _}: work

def workStarted(state: RefreshWork) -> RefreshWork & Bool:
  match state:
    case RefreshWork{running,True{},drained}: (RefreshWork{running,True{},drained},False{})
    case RefreshWork{running,False{},drained}: (RefreshWork{running + 1n,False{},drained},True{})

def workFinished(state: RefreshWork) -> RefreshWork & Bool:
  match state:
    case RefreshWork{0n,closing,drained}: (RefreshWork{0n,closing,drained},False{})
    case RefreshWork{1n,+closing,drained}: (RefreshWork{0n,closing,drained},closing)
    case RefreshWork{1n+(more),closing,drained}: (RefreshWork{more,closing,drained},False{})

def drainedOf(state: RefreshWork) -> Deferred.Deferred<Unit>:
  match state:
    case RefreshWork{_,_,drained}: drained

def resolveWorkDrain(work: Ref.Ref<RefreshWork>,ready: Bool) -> IO(Unit):
  match ready:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        state : RefreshWork <- Ref.read(RefreshWork,work)
        settled : Bool <- Deferred.resolve(Unit,drainedOf(state),Unit{})
        return Unit{}

def workLeft(+work: Ref.Ref<RefreshWork>) -> IO(Unit):
  do IO<Unit>:
    ready : Bool <- Ref.modify(RefreshWork,Bool,work,workFinished)
    resolveWorkDrain(work,ready)

def workClosing(state: RefreshWork) -> RefreshWork & Bool:
  match state:
    case RefreshWork{+running,_,drained}: (RefreshWork{running,True{},drained},Nat.is_eq(running,0n))

def closeRefreshWork(+work: Ref.Ref<RefreshWork>,ready: Bool) -> IO(Unit):
  do IO<Unit>:
    resolveWorkDrain(work,ready)
    state : RefreshWork <- Ref.read(RefreshWork,work)
    finished : Unit <- Deferred.result(Unit,drainedOf(state))
    previous : RefreshWork <- Ref.dispose(RefreshWork,work)
    Deferred.dispose(Unit,drainedOf(previous))

def workContinued(state: RefreshWork) -> RefreshWork & Unit:
  match state:
    case RefreshWork{running, closing, drained}: (RefreshWork{running + 1n, closing, drained}, Unit{})

def refreshLeased(+runtime: ModelRuntime, options: ModelsRefreshOptions) -> IO(ModelsRefreshResult):
  match options:
    case ModelsRefreshOptions{network, providers, force, None{}}:
      do IO<ModelsRefreshResult>:
        result : ModelsRefreshResult <- refreshTask(runtime, ModelsRefreshOptions{network, providers, force, None{}})
        workLeft(workRef(runtime))
        return result
    case ModelsRefreshOptions{network, providers, force, Some{caller}}:
      Tasks.run(ModelsRefreshResult, caller,
        signal => refreshTask(runtime, ModelsRefreshOptions{network, providers, force, Some{signal}}),
        IO.pure(Maybe<&2, ModelsRefreshResult>, Some{cancelledRefresh()}), workLeft(workRef(runtime)))

def refresh(+runtime: ModelRuntime, options: ModelsRefreshOptions) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    admitted : Bool <- Ref.modify(RefreshWork, Bool, workRef(runtime), workStarted)
    Bool.pick(Unit -> IO(ModelsRefreshResult), admitted,
      _ => refreshLeased(runtime, options),
      _ => IO.pure(ModelsRefreshResult, cancelledRefresh()))(Unit{})

type RefreshDeparture is Data:
  StillWaiting{}
  AbortRequest{controller: Abort.AbortController<Unit>}
  RetireRequest{controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>, close: Bool}
  RetireDetached{}

def departingActive(+id: Nat, +controller: Abort.AbortController<Unit>, +result: Deferred.Deferred<ModelsRefreshResult>, waiters: Nat, finished: Bool, closing: Bool) -> SharedRefresh & RefreshDeparture:
  match waiters:
    case 0n: (RefreshActive{id,controller,result,0n,finished,closing},StillWaiting{})
    case 1n:
      match finished closing:
        case True{} True{}: (RefreshClosed{},RetireRequest{controller,result,True{}})
        case True{} False{}: (RefreshIdle{id + 1n},RetireRequest{controller,result,False{}})
        case False{} True{}: (RefreshActive{id,controller,result,0n,False{},True{}},AbortRequest{controller})
        case False{} False{}: (RefreshIdle{id + 1n},AbortRequest{controller})
    case 1n+(more): (RefreshActive{id,controller,result,more,finished,closing},StillWaiting{})

def departRefresh(state: SharedRefresh, id: Nat) -> SharedRefresh & RefreshDeparture:
  match state:
    case RefreshActive{+active,+controller,+result,+waiters,+finished,+closing}:
      Bool.pick(Unit -> SharedRefresh & RefreshDeparture,Nat.is_eq(active,id),
        _ => departingActive(active,controller,result,waiters,finished,closing),
        _ => (RefreshActive{active,controller,result,waiters,finished,closing},StillWaiting{}))(Unit{})
    case other: (other,StillWaiting{})

def finishedActive(id: Nat, controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>, waiters: Nat, closing: Bool) -> SharedRefresh & RefreshDeparture:
  match waiters:
    case 0n: (RefreshClosed{},RetireRequest{controller,result,True{}})
    case _: (RefreshActive{id,controller,result,waiters,True{},closing},StillWaiting{})

def finishRefresh(state: SharedRefresh, id: Nat) -> SharedRefresh & RefreshDeparture:
  match state:
    case RefreshActive{+active,+controller,+result,+waiters,+finished,+closing}:
      Bool.pick(Unit -> SharedRefresh & RefreshDeparture,Nat.is_eq(active,id),
        _ => finishedActive(active,controller,result,waiters,closing),
        _ => (RefreshActive{active,controller,result,waiters,finished,closing},RetireDetached{}))(Unit{})
    case other: (other,RetireDetached{})

def retireRefresh(state: Ref.Ref<SharedRefresh>, action: RefreshDeparture) -> IO(Unit):
  match action:
    case StillWaiting{}: IO.pure(Unit,Unit{})
    case RetireDetached{}: IO.pure(Unit,Unit{})
    case AbortRequest{controller}:
      do IO<Unit>:
        stopped : Bool <- Abort.abort(Unit,controller,None{})
        return Unit{}
    case RetireRequest{controller,result,_}:
      do IO<Unit>:
        Abort.dispose(Unit,controller)
        Deferred.dispose(ModelsRefreshResult,result)
        return Unit{}

def retireOptionalRefresh(state: Ref.Ref<SharedRefresh>, action: Maybe<&1,RefreshDeparture>) -> IO(Unit):
  match action:
    case None{}: IO.pure(Unit,Unit{})
    case Some{departure}: retireRefresh(state,departure)

def releaseRefresh(+state: Ref.Ref<SharedRefresh>, id: Nat) -> IO(Unit):
  do IO<Unit>:
    action : Maybe<&1,RefreshDeparture> <- Ref.tryModify(SharedRefresh,RefreshDeparture,state,current => departRefresh(current,id))
    retireOptionalRefresh(state,action)

def completedAction(state: Ref.Ref<SharedRefresh>, controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>, action: Maybe<&1,RefreshDeparture>) -> IO(Unit):
  match action:
    case Some{RetireRequest{_,_,_}}: retireRefresh(state,RetireRequest{controller,result,True{}})
    case Some{StillWaiting{}}: IO.pure(Unit,Unit{})
    case Some{AbortRequest{_}}: IO.pure(Unit,Unit{})
    case _:
      do IO<Unit>:
        Abort.dispose(Unit,controller)
        Deferred.dispose(ModelsRefreshResult,result)

def completedRefresh(+state: Ref.Ref<SharedRefresh>, id: Nat, controller: Abort.AbortController<Unit>, result: Deferred.Deferred<ModelsRefreshResult>) -> IO(Unit):
  do IO<Unit>:
    action : Maybe<&1,RefreshDeparture> <- Ref.tryModify(SharedRefresh,RefreshDeparture,state,current => finishRefresh(current,id))
    completedAction(state,controller,result,action)

def performSharedRefresh(+runtime: ModelRuntime, id: Nat, +controller: Abort.AbortController<Unit>, +result: Deferred.Deferred<ModelsRefreshResult>) -> IO(Unit):
  do IO<Unit>:
    value : ModelsRefreshResult <- refresh(runtime,ModelsRefreshOptions{None{},None{},None{},Some{Abort.signal(Unit,controller)}})
    settled : Bool <- Deferred.resolve(ModelsRefreshResult,result,value)
    completedRefresh(sharedRef(runtime),id,controller,result)
    workLeft(workRef(runtime))

type RefreshArrival is Data:
  RefreshSucceeded{result: ModelsRefreshResult}
  RefreshAborted{}

def settleArrival(value: Maybe<&2,ModelsRefreshResult>, completion: Deferred.Deferred<RefreshArrival>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{result}:
      do IO<Unit>:
        won : Bool <- Deferred.resolve(RefreshArrival,completion,RefreshSucceeded{result})
        return Unit{}

def observeRefresh(ticket: Deferred.Ticket<Maybe<&2,ModelsRefreshResult>>, completion: Deferred.Deferred<RefreshArrival>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2,ModelsRefreshResult> <- Deferred.wait(Maybe<&2,ModelsRefreshResult>,ticket)
    settleArrival(value,completion)

def settleAbortArrival(value: Maybe<&2,Abort.AbortReason<Unit>>, completion: Deferred.Deferred<RefreshArrival>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- Deferred.resolve(RefreshArrival,completion,RefreshAborted{})
        return Unit{}

def observeRefreshAbort(ticket: Deferred.Ticket<Maybe<&2,Abort.AbortReason<Unit>>>, completion: Deferred.Deferred<RefreshArrival>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2,Abort.AbortReason<Unit>> <- Deferred.wait(Maybe<&2,Abort.AbortReason<Unit>>,ticket)
    settleAbortArrival(value,completion)


def arrivalValue(first: RefreshArrival) -> IO(ModelsRefreshResult):
  match first:
    case RefreshSucceeded{value}: IO.pure(ModelsRefreshResult,value)
    case RefreshAborted{}: IO.pure(ModelsRefreshResult,cancelledRefresh())

def awaitObservedRefresh(result: Deferred.Observation<ModelsRefreshResult>, aborted: Deferred.Observation<Abort.AbortReason<Unit>>, +completion: Deferred.Deferred<RefreshArrival>) -> IO(ModelsRefreshResult):
  match result aborted:
    case Deferred.Observation{resultTicket,resultCancellation} Deferred.Observation{abortTicket,abortCancellation}:
      do IO<ModelsRefreshResult>:
        valueTask : Chan(Unit) <- IO.fork(Unit,observeRefresh(resultTicket,completion))
        abortTask : Chan(Unit) <- IO.fork(Unit,observeRefreshAbort(abortTicket,completion))
        first : RefreshArrival <- Deferred.result(RefreshArrival,completion)
        valueCancelled : Bool <- Deferred.cancel(ModelsRefreshResult,resultCancellation)
        abortCancelled : Bool <- Deferred.cancel(Abort.AbortReason<Unit>,abortCancellation)
        IO.join(Unit,valueTask)
        IO.join(Unit,abortTask)
        Deferred.dispose(RefreshArrival,completion)
        arrivalValue(first)

def awaitSharedRefresh(result: Deferred.Deferred<ModelsRefreshResult>, signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ModelsRefreshResult):
  match signal:
    case None{}: Deferred.result(ModelsRefreshResult,result)
    case Some{caller}:
      do IO<ModelsRefreshResult>:
        completion : Deferred.Deferred<RefreshArrival> <- Deferred.new(RefreshArrival)
        observed : Deferred.Observation<ModelsRefreshResult> <- Deferred.observe(ModelsRefreshResult,result)
        aborted : Deferred.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit,caller)
        awaitObservedRefresh(observed,aborted,completion)

def beginSharedRefresh(+runtime: ModelRuntime, admission: SharedAdmission, signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ModelsRefreshResult):
  match admission:
    case StartRefresh{+id,controller,+result}:
      do IO<ModelsRefreshResult>:
        IO.spawn(Unit,performSharedRefresh(runtime,id,controller,result))
        value : ModelsRefreshResult <- awaitSharedRefresh(result,signal)
        releaseRefresh(sharedRef(runtime),id)
        return value
    case JoinRefresh{+id,result,unusedController,unusedResult}:
      do IO<ModelsRefreshResult>:
        Abort.dispose(Unit,unusedController)
        Deferred.dispose(ModelsRefreshResult,unusedResult)
        value : ModelsRefreshResult <- awaitSharedRefresh(result,signal)
        releaseRefresh(sharedRef(runtime),id)
        workLeft(workRef(runtime))
        return value
    case ClosedRefresh{unusedController,unusedResult}:
      do IO<ModelsRefreshResult>:
        Abort.dispose(Unit,unusedController)
        Deferred.dispose(ModelsRefreshResult,unusedResult)
        workLeft(workRef(runtime))
        return cancelledRefresh()

def sharedSignalAborted(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool,False{})
    case Some{value}: Abort.aborted(Unit,value)

def refreshShared(+runtime: ModelRuntime, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    callerAborted : Bool <- sharedSignalAborted(signal)
    Bool.pick(Unit -> IO(ModelsRefreshResult),callerAborted,
      _ => IO.pure(ModelsRefreshResult,cancelledRefresh()),
      _ => do IO<ModelsRefreshResult>:
        leased : Bool <- Ref.modify(RefreshWork,Bool,workRef(runtime),workStarted)
        Bool.pick(Unit -> IO(ModelsRefreshResult),leased,
          _ => do IO<ModelsRefreshResult>:
            controller : Abort.AbortController<Unit> <- Abort.new(Unit)
            result : Deferred.Deferred<ModelsRefreshResult> <- Deferred.new(ModelsRefreshResult)
            admission : SharedAdmission <- Ref.modify(SharedRefresh,SharedAdmission,sharedRef(runtime),state => admitRefresh(state,controller,result))
            beginSharedRefresh(runtime,admission,signal),
          _ => IO.pure(ModelsRefreshResult,cancelledRefresh()))(Unit{}))(Unit{})

def closingRefresh(state: SharedRefresh) -> SharedRefresh & Maybe<&2,Abort.AbortController<Unit>>:
  match state:
    case RefreshIdle{_}: (RefreshClosed{},None{})
    case RefreshActive{id,+controller,result,waiters,finished,_}:
      (RefreshActive{id,controller,result,waiters,finished,True{}},Some{controller})
    case RefreshClosed{}: (RefreshClosed{},None{})

def closeShared(state: Ref.Ref<SharedRefresh>, pending: Maybe<&2,Abort.AbortController<Unit>>) -> IO(Unit):
  match pending:
    case Some{controller}:
      do IO<Unit>:
        stopped : Bool <- Abort.abort(Unit,controller,None{})
        return Unit{}
    case None{}: IO.pure(Unit,Unit{})

# Extension providers stay with the extensions that registered them; the
# auth callbacks a config registration's composition created go with the
# runtime. The api stream belongs to whoever installed it.

def disposeSharedRefresh(+state: Ref.Ref<SharedRefresh>,+work: Ref.Ref<RefreshWork>) -> IO(Unit):
  do IO<Unit>:
    ready : Bool <- Ref.modify(RefreshWork,Bool,work,workClosing)
    pending : Maybe<&2,Abort.AbortController<Unit>> <- Ref.modify(SharedRefresh,Maybe<&2,Abort.AbortController<Unit>>,state,closingRefresh)
    closeShared(state,pending)
    closeRefreshWork(work,ready)
    previous : SharedRefresh <- Ref.dispose(SharedRefresh,state)
    return Unit{}

def dispose(runtime: ModelRuntime) -> IO(Unit):
  match runtime:
    case ModelRuntime{definition, +models, catalog, storeState, extensions, sharedRefresh, availability, credentials, refreshWork, credentialQueues}:
      do IO<Unit>:
        disposeSharedRefresh(sharedRefresh,refreshWork)
        KeyedSerial.dispose(credentialQueues)
        +registered : ExtensionState <- Ref.dispose(ExtensionState, extensions)
        disposeEntries(extensionEntries(registered))
        disposeApiStreamsOf(apiStreamsOf(registered))
        current : Definition <- Ref.dispose(Definition,definition)
        disposeDefinition(current)
        credentialStore : Auth.CredentialStore <- IO.pure(Auth.CredentialStore, AiModels.credentialsOf(models))
        AiModels.disposeModels(models)
        Auth.disposeStore(credentialStore)
        RuntimeCredentials.dispose(credentials)
        state : Maybe<&1, Files.FileModelsReadState> <- Ref.dispose(Maybe<&1, Files.FileModelsReadState>, storeState)
        retireStoreState(state)
        old : Catalog <- Ref.dispose(Catalog, catalog)
        status : AvailabilityStatus <- Ref.dispose(AvailabilityStatus, availability)
        return Unit{}

def withoutEntry(entries: List<&2, ExtensionEntry>, +id: String) -> List<&2, ExtensionEntry>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = withoutEntry(rest, id)
      Bool.pick(List<&2, ExtensionEntry>, String.eq(entryId(entry), id), tail, entry <> tail)

def ownedOf(entry: Maybe<&2, ExtensionEntry>) -> List<&2, OwnedAuth>:
  match entry:
    case None{}: Nil{}
    case Some{ExtensionEntry{_, _, _, owned}}: owned

# The entry of `id` replaced by `entry` (removed when None); the replaced
# entry's own auth parts are returned for disposal.
def replacedEntry(+id: String, entry: Maybe<&2, ExtensionEntry>, state: ExtensionState) -> ExtensionState & List<&2, OwnedAuth>:
  match state:
    case ExtensionState{+entries, streams}:
      (ExtensionState{List.append(&2, ExtensionEntry, withoutEntry(entries, id), Maybe.default(&2, List<&2, ExtensionEntry>, Maybe.map(&2, ExtensionEntry, List<&2, ExtensionEntry>, found => [found], entry), Nil{})), streams}, ownedOf(findEntry(entries, id)))

# A replaced generation may still be borrowed by auth work or a retained
# provider method. Retire its composed callbacks with the other generations.
def retiredAuth(definition: Definition, owned: List<&2, OwnedAuth>) -> Definition & Unit:
  match definition owned:
    case definition Nil{}: (definition, Unit{})
    case Definition{providers, builtins, config, errors, generation, source, retired} owned:
      (Definition{providers, builtins, config, errors, generation, source, Generation{owned, Nil{}, Nil{}} <> retired}, Unit{})

def setEntry(+runtime: ModelRuntime, +id: String, entry: Maybe<&2, ExtensionEntry>) -> IO(Unit):
  do IO<Unit>:
    previous : List<&2, OwnedAuth> <- Ref.modify(ExtensionState, List<&2, OwnedAuth>, extensionsRef(runtime), state => replacedEntry(id, entry, state))
    Ref.modify(Definition, Unit, definitionRef(runtime), definition => retiredAuth(definition, previous))

def noNetwork() -> ModelsRefreshOptions: ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}}

# upstream registerNativeProvider: the extension provider replaces any
# provider of its id (and any config registration) until it is
# unregistered, and the cached catalogs are restored without network access.
# `stream` is the provider's own streamSimple (upstream Provider.streamSimple);
# without one its models stream by api.
def registerUnlessBlank(+runtime: ModelRuntime, +provider: AiModels.Provider, stream: Maybe<&2, Composer.ProviderStream()>, blank: Bool) -> IO(Result<&2, &2, String, Unit>):
  match blank:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Provider id must not be empty."})
    case False{}:
      do IO<Result<&2, &2, String, Unit>>:
        setEntry(runtime, providerId(provider), Some{ExtensionEntry{providerId(provider), None{}, stream, Nil{}}})
        Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (registeredNative(provider, catalog), Unit{}))
        rebuildCollection(runtime, [providerId(provider)])
        result : ModelsRefreshResult <- refresh(runtime, ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}})
        return Done{Unit{}}

def registerNativeProviderStream(+runtime: ModelRuntime, +provider: AiModels.Provider, stream: Maybe<&2, Composer.ProviderStream()>) -> IO(Result<&2, &2, String, Unit>):
  registerUnlessBlank(runtime, provider, stream, isBlank(providerId(provider)))

def registerNativeProvider(+runtime: ModelRuntime, +provider: AiModels.Provider) -> IO(Result<&2, &2, String, Unit>):
  registerNativeProviderStream(runtime, provider, None{})

# upstream unregisterProvider: the built-in or models.json provider of the id,
# if any, is restored.
def unregisterProvider(+runtime: ModelRuntime, +id: String) -> IO(Unit):
  do IO<Unit>:
    setEntry(runtime, id, None{})
    Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (unregisteredNative(id, catalog), Unit{}))
    rebuildCollection(runtime, [id])
    result : ModelsRefreshResult <- refresh(runtime, noNetwork())
    return Unit{}

# Config registrations (upstream registerProvider(providerId, config))
# ------------------------------------------------------------------

def configOf(entry: Maybe<&2, ExtensionEntry>) -> Composer.ProviderConfigInput:
  match entry:
    case Some{ExtensionEntry{_, Some{config}, _, _}}: config
    case _: Composer.providerConfig()

def definitionProvider(definition: Definition,id: String) -> Maybe<&2,AiModels.Provider>:
  match definition:
    case Definition{providers,_,_,_,_,_,_}: findProvider(providers,id)
def baseProvider(runtime: ModelRuntime, +id: String) -> IO(Maybe<&2, AiModels.Provider>):
  do IO<Maybe<&2,AiModels.Provider>>:
    definition : Definition <- Ref.read(Definition,definitionRef(runtime))
    return definitionProvider(definition,id)

def modelsJsonOverrides(+config: Config.ModelConfig, +id: String) -> Maybe<&2, R.Record<Config.ModelsJsonModelOverride>>:
  Maybe.bind(&2, Config.ModelsJsonProvider, R.Record<Config.ModelsJsonModelOverride>, Config.getProvider(config, id), Composer.overridesOf)

def registeredConfig(+runtime: ModelRuntime, +id: String, +merged: Composer.ProviderConfigInput, +base: Maybe<&2, AiModels.Provider>, result: Result<&2, &2, String, Composer.Composed>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{Composer.Composed{name, url, +auth, models, _}}:
      do IO<Result<&2, &2, String, Unit>>:
        # modelOverrides are the topmost layer (upstream getModels).
        config : Config.ModelConfig <- getModelConfig(runtime)
        +provider : AiModels.Provider = AiModels.Provider{id, name, url, auth, Composer.applyOverrides(models, modelsJsonOverrides(config, id)), AiModels.inheritedStreams(base), Maybe.bind(&2, AiModels.Provider, AiModels.RefreshModels(), base, AiModels.providerRefresh), baseFilter(base)}
        setEntry(runtime, id, Some{ExtensionEntry{id, Some{merged}, Composer.configStream(merged), ownedAuth(auth, Composer.sourceAuth(Composer.Layers{None{}, Some{merged}}, maybeProviderAuth(base)))}})
        Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (registeredNative(provider, catalog), Unit{}))
        rebuildCollection(runtime, [id])
        refreshed : ModelsRefreshResult <- refresh(runtime, noNetwork())
        return Done{Unit{}}

def composedRegistration(+runtime: ModelRuntime, +id: String, +merged: Composer.ProviderConfigInput) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    +found : Maybe<&2, AiModels.Provider> <- baseProvider(runtime, id)
    result : Result<&2, &2, String, Composer.Composed> <- Composer.composeLayeredProvider(id, base(found), Composer.Layers{None{}, Some{merged}})
    registeredConfig(runtime, id, merged, found, result)

def validatedRegistration(+runtime: ModelRuntime, +id: String, +config: Composer.ProviderConfigInput, valid: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match valid:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, String, Unit>>:
        state : ExtensionState <- Ref.read(ExtensionState, extensionsRef(runtime))
        composedRegistration(runtime, id, Composer.mergeProviderConfig(configOf(findEntry(extensionEntries(state), id)), config))

# upstream ModelRuntime.registerProvider(providerId, config): the config
# layers over the built-in or models.json provider of the id (a native
# registration of the id is dropped). A re-registration merges its defined
# values over the previous registration's. An invalid registration fails
# without changing anything.
def registerProvider(+runtime: ModelRuntime, +id: String, +config: Composer.ProviderConfigInput) -> IO(Result<&2, &2, String, Unit>):
  Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), isBlank(id), _ => IO.pure(Result<&2, &2, String, Unit>, Fail{"Provider id must not be empty."}), _ => validatedRegistration(runtime, id, config, Composer.validateStream(id, config)))(Unit{})

# Streaming (upstream ModelRuntime.streamSimple and complete)
# ----------------------------------------------------------

# upstream ModelsRequestTransforms: transformHeaders sees the assembled
# request headers (auth, model and request headers) and returns the headers
# sent; it is not forwarded to the provider.
type RequestTransforms is Data:
  RequestTransforms{transformHeaders: Maybe<&2, C.Callback<Ai.ProviderHeaders(), Ai.ProviderHeaders()>>, fallbackStream: Maybe<&2, Composer.ProviderStream()>}

def noTransforms() -> RequestTransforms: RequestTransforms{None{}, None{}}

def withApiStreams(streams: Maybe<&2, Composer.ProviderStream()>, state: ExtensionState) -> ExtensionState & Maybe<&2, Composer.ProviderStream()>:
  match state:
    case ExtensionState{entries, previous}: (ExtensionState{entries, streams}, previous)

# Install the stream the built-in apis dispatch through (upstream's api
# registry over the global fetch); the runtime owns it from here on and
# disposes the one it replaces. None removes it.
def setApiStreams(runtime: ModelRuntime, streams: Maybe<&2, Composer.ProviderStream()>) -> IO(Unit):
  do IO<Unit>:
    previous : Maybe<&2, Composer.ProviderStream()> <- Ref.modify(ExtensionState, Maybe<&2, Composer.ProviderStream()>, extensionsRef(runtime), state => withApiStreams(streams, state))
    disposeApiStreamsOf(previous)

def failed(+message: String) -> Composer.StreamOutput(): Fail{Tools.Failure{message}}

def baseOverrides(options: Composer.BaseOptions()) -> Resolve.AuthResolutionOverrides:
  match options:
    case Ai.StreamOptions{signal, _, key, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: Resolve.AuthResolutionOverrides{key, env, None{}, signal}

def requestOverrides(options: Maybe<&2, Composer.RequestOptions>) -> Resolve.AuthResolutionOverrides:
  match options:
    case None{}: Resolve.noOverrides()
    case Some{value}: baseOverrides(Composer.requestBase(value))

def withAuthBaseUrl(model: Model(), url: Maybe<&2, String>) -> Model():
  match model url:
    case _ None{}: model
    case Ai.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} Some{replaced}:
      Ai.Model{id, name, api, provider, replaced, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def mergedEnv(auth: Maybe<&2, Ai.ProviderEnv()>, request: Maybe<&2, Ai.ProviderEnv()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match auth request:
    case None{} _: request
    case _ None{}: auth
    case Some{base} Some{extra}: Some{Composer.spread(String, base, R.entries(String, extra))}

# upstream prepareRequest's options: the request's key wins over the
# resolved one, auth headers come first, and the environments merge.
def authorizedBase(auth: Auth.AuthResult, options: Composer.BaseOptions()) -> Composer.BaseOptions():
  match auth options:
    case Auth.AuthResult{Auth.ModelAuth{key, authHeaders, _}, authEnv, _} Ai.StreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}:
      Ai.StreamOptions{signal, telemetry, Maybe.or(&2, String, apiKey, key), shared, mergedEnv(authEnv, env), onPayload, onResponse, AiModels.mergeHeaders(authHeaders, headers), timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}

def authorizedOptions(auth: Auth.AuthResult, +options: Composer.RequestOptions) -> Composer.RequestOptions:
  Composer.withRequestBase(options, authorizedBase(auth, Composer.requestBase(options)))

def baseHeaders(options: Composer.BaseOptions()) -> Maybe<&2, Ai.ProviderHeaders()>:
  match options:
    case Ai.StreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}: headers

def withBaseHeaders(options: Composer.BaseOptions(), headers: Maybe<&2, Ai.ProviderHeaders()>) -> Composer.BaseOptions():
  match options:
    case Ai.StreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, _, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}:
      Ai.StreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}

# upstream: `if (transformHeaders) headers = await transformHeaders(headers ?? {})`.
def transformedWith(transform: Maybe<&2, C.Callback<Ai.ProviderHeaders(), Ai.ProviderHeaders()>>, +options: Composer.RequestOptions) -> IO(Composer.RequestOptions):
  match transform:
    case None{}: IO.pure(Composer.RequestOptions, options)
    case Some{callback}:
      do IO<Composer.RequestOptions>:
        +headers : Ai.ProviderHeaders() <- C.call(Ai.ProviderHeaders(), Ai.ProviderHeaders(), callback, Maybe.default(&2, Ai.ProviderHeaders(), baseHeaders(Composer.requestBase(options)), R.new(Ai.Nullable<String>)))
        return Composer.withRequestBase(options, withBaseHeaders(Composer.requestBase(options), Some{headers}))

def transformed(transforms: RequestTransforms, options: Maybe<&2, Composer.RequestOptions>) -> IO(Maybe<&2, Composer.RequestOptions>):
  match transforms options:
    case _ None{}: IO.pure(Maybe<&2, Composer.RequestOptions>, None{})
    case RequestTransforms{transform, _} Some{value}:
      do IO<Maybe<&2, Composer.RequestOptions>>:
        found : Composer.RequestOptions <- transformedWith(transform, value)
        return Some{found}

def sameApi(configured: Maybe<&2, Ai.ModelApi>, +api: Ai.ModelApi) -> Bool:
  match configured:
    case None{}: False{}
    case Some{found}: String.eq(ModelApi.name(found), ModelApi.name(api))

# upstream composeModelProvider's stream: a config registration's
# streamSimple serves its api; a native provider's own stream serves all its
# models.
def entryStream(entry: Maybe<&2, ExtensionEntry>, +model: Model()) -> Maybe<&2, Composer.ProviderStream()>:
  match entry:
    case Some{ExtensionEntry{_, None{}, stream, _}}: stream
    case Some{ExtensionEntry{_, Some{config}, stream, _}}: Bool.pick(Maybe<&2, Composer.ProviderStream()>, sameApi(Composer.configApi(config), ModelApi.modelApi(Ai.JsonValue, model)), stream, None{})
    case None{}: None{}

def baseEnv(options: Composer.BaseOptions()) -> Maybe<&2, Ai.ProviderEnv()>:
  match options:
    case Ai.StreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: env

def optionsEnv(options: Composer.RequestOptions) -> Maybe<&2, Ai.ProviderEnv()>: baseEnv(Composer.requestBase(options))

# Apply provider routing to the common fields, preserving raw API settings.
def routedOptions(+options: Composer.RequestOptions, streams: AiModels.ProviderStreams, model: Model()) -> Composer.RequestOptions:
  Composer.withRequestBase(options, AiModels.streamOptions(Ai.JsonValue, Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError, streams, model, Composer.requestBase(options)))

def routedCall(stream: Composer.ProviderStream(), +routed: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, options: Maybe<&2, Composer.RequestOptions>, +streams: AiModels.ProviderStreams) -> IO(Composer.StreamOutput()):
  C.call(Composer.StreamRequest(), Composer.StreamOutput(), stream, AgentTypes.StreamInput{routed, context, Maybe.map(&2, Composer.RequestOptions, Composer.RequestOptions, value => routedOptions(value, streams, routed), options)})

# Built-in apis stream through the installed api stream, for the model the
# provider's streams dispatch (Cloudflare's resolved account URL, OpenCode's
# session header).
def viaApiStreams(apiStreams: Maybe<&2, Composer.ProviderStream()>, +model: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, +options: Maybe<&2, Composer.RequestOptions>, +streams: AiModels.ProviderStreams) -> IO(Composer.StreamOutput()):
  match apiStreams:
    case None{}: IO.pure(Composer.StreamOutput(), failed("No API provider registered for api: " ++ ModelApi.name(ModelApi.modelApi(Ai.JsonValue, model))))
    case Some{stream}: routedCall(stream, AiModels.streamModel(Ai.JsonValue, streams, model, Maybe.bind(&2, Composer.RequestOptions, Ai.ProviderEnv(), options, optionsEnv)), context, options, streams)

def dispatchedWith(custom: Maybe<&2, Composer.ProviderStream()>, apiStreams: Maybe<&2, Composer.ProviderStream()>, +model: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, options: Maybe<&2, Composer.RequestOptions>, streams: AiModels.ProviderStreams) -> IO(Composer.StreamOutput()):
  match custom:
    case Some{stream}: C.call(Composer.StreamRequest(), Composer.StreamOutput(), stream, AgentTypes.StreamInput{model, context, options})
    case None{}: viaApiStreams(apiStreams, model, context, options, streams)

def dispatched(state: ExtensionState, fallback: Maybe<&2, Composer.ProviderStream()>, +model: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, options: Maybe<&2, Composer.RequestOptions>, streams: AiModels.ProviderStreams) -> IO(Composer.StreamOutput()):
  match state:
    case ExtensionState{entries, apiStreams}: dispatchedWith(entryStream(findEntry(entries, Ai.modelProvider(model)), model), Maybe.or(&2, Composer.ProviderStream(), apiStreams, fallback), model, context, options, streams)

def fallbackStream(transforms: RequestTransforms) -> Maybe<&2, Composer.ProviderStream()>:
  match transforms: case RequestTransforms{_, fallback}: fallback

def preparedModel(resolution: Resolve.Resolution(), +model: Model()) -> Model():
  match resolution:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{_, _, url}, _, _}}}: withAuthBaseUrl(model, url)
    case _: model

def preparedOptions(resolution: Resolve.Resolution(), options: Maybe<&2, Composer.RequestOptions>) -> Maybe<&2, Composer.RequestOptions>:
  match resolution options:
    case Done{Some{auth}} Some{value}: Some{authorizedOptions(auth, value)}
    case Done{Some{auth}} None{}: Some{authorizedOptions(auth, Composer.SimpleOptions{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError)})}
    case _ other: other

def preparedStream(+runtime: ModelRuntime, +model: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, +transforms: RequestTransforms, +resolution: Resolve.Resolution(), options: Maybe<&2, Composer.RequestOptions>) -> IO(Composer.StreamOutput()):
  do IO<Composer.StreamOutput()>:
    final : Maybe<&2, Composer.RequestOptions> <- transformed(transforms, preparedOptions(resolution, options))
    streams : AiModels.ProviderStreams <- getProviderStreams(runtime, Ai.modelProvider(model))
    state : ExtensionState <- Ref.read(ExtensionState, extensionsRef(runtime))
    dispatched(state, fallbackStream(transforms), preparedModel(resolution, model), context, final, streams)

# upstream ModelRuntime.streamSimple: the request's auth is resolved for its
# model (the request's key, env and signal override), the auth base URL
# replaces the model's, headers are assembled and transformed, and the
# provider streams it: an extension stream, else the built-in api stream.
# An unknown provider, failed auth lookup, or missing configured auth
# stops before the transport is invoked.
def authenticatedStream(+runtime: ModelRuntime, +model: Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>, +transforms: RequestTransforms, options: Maybe<&2, Composer.RequestOptions>, resolution: Resolve.Resolution()) -> IO(Composer.StreamOutput()):
  match resolution:
    case Fail{error}: IO.pure(Composer.StreamOutput(), failed(Resolve.errorMessage(error)))
    case Done{None{}}: IO.pure(Composer.StreamOutput(), failed("Provider is not configured: " ++ Ai.modelProvider(model)))
    case Done{Some{auth}}: preparedStream(runtime, model, context, transforms, Done{Some{auth}}, options)

def streamRequest(+runtime: ModelRuntime, request: Composer.StreamRequest(), transforms: RequestTransforms) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{+model, context, +options}:
      do IO<Composer.StreamOutput()>:
        resolution : Resolve.Resolution() <- getModelAuth(runtime, model, requestOverrides(options))
        authenticatedStream(runtime, model, context, transforms, options, resolution)

# Both public methods share auth, routing and header preparation. The request
# variant remains intact until its provider selects raw or simple streaming.
def streamSimple(+runtime: ModelRuntime, request: Composer.SimpleStreamRequest(), transforms: RequestTransforms) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{model, context, options}: streamRequest(runtime, AgentTypes.StreamInput{model, context, Maybe.map(&2, Composer.StreamOptions(), Composer.RequestOptions, value => Composer.SimpleOptions{value}, options)}, transforms)

def stream(+runtime: ModelRuntime, request: Composer.RawStreamRequest(), transforms: RequestTransforms) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{model, context, options}: streamRequest(runtime, AgentTypes.StreamInput{model, context, Some{Composer.RawOptions{Maybe.default(&2, Composer.ApiStreamOptions, options, Composer.CommonOptions{Composer.emptyBase()})}}}, transforms)

def errorReply(model: Model(), message: String, now: F64) -> Ai.AssistantMessage<V.Value, V.Value>:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Ai.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, Ai.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, Ai.Error{}, None{}, Some{message}, None{}, None{}, now}

def completed(+model: Model(), response: Composer.StreamOutput()) -> IO(Ai.AssistantMessage<V.Value, V.Value>):
  match response:
    case Fail{error}:
      do IO<Ai.AssistantMessage<V.Value, V.Value>>:
        now : F64 <- Date.now()
        return errorReply(model, Tools.errorMessage(error), now)
    case Done{AgentTypes.StreamLease{events, release}}:
      do IO<Ai.AssistantMessage<V.Value, V.Value>>:
        message : Ai.AssistantMessage<V.Value, V.Value> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events)
        released : Result<&2, &2, Tools.ToolError, Unit> <- release
        return message

# Completion consumes the selected stream's final message and releases its run.
def completeSimple(+runtime: ModelRuntime, +model: Model(), context: Ai.Context<V.Value, V.Value, V.Value, Tools.ToolDetails>, options: Maybe<&2, Composer.StreamOptions()>, transforms: RequestTransforms) -> IO(Ai.AssistantMessage<V.Value, V.Value>):
  do IO<Ai.AssistantMessage<V.Value, V.Value>>:
    response : Composer.StreamOutput() <- streamSimple(runtime, AgentTypes.StreamInput{model, Transcript.normalizeContext(V.Value, V.Value, V.Value, Tools.ToolDetails, context), options}, transforms)
    completed(model, response)

def complete(+runtime: ModelRuntime, +model: Model(), context: Ai.Context<V.Value, V.Value, V.Value, Tools.ToolDetails>, options: Maybe<&2, Composer.ApiStreamOptions>, transforms: RequestTransforms) -> IO(Ai.AssistantMessage<V.Value, V.Value>):
  do IO<Ai.AssistantMessage<V.Value, V.Value>>:
    response : Composer.StreamOutput() <- stream(runtime, AgentTypes.StreamInput{model, Transcript.normalizeContext(V.Value, V.Value, V.Value, Tools.ToolDetails, context), options}, transforms)
    completed(model, response)

def nativeIdsOf(catalog: Catalog) -> List<&2, String>:
  match catalog:
    case Catalog{natives, _, _}: builtinIds(natives)

# upstream getRegisteredProviderIds (native extension providers).
def getRegisteredProviderIds(runtime: ModelRuntime) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    catalog : Catalog <- readCatalog(runtime)
    return builtinIds(nativesOf(catalog))

# A committed credential change can alter a dynamic provider's cached models.
# Refresh only that provider, without network access, then publish its new
# availability. Errors leave the last complete snapshot intact.
def synchronizationError(+id: String, +reason: String) -> Resolve.ModelsError:
  Resolve.ModelsError{Resolve.AuthError{}, "Credential synchronization failed for " ++ id ++ ": " ++ reason}

def synchronizationAborted(+id: String) -> Resolve.ModelsError:
  synchronizationError(id, "This operation was aborted")

def synchronizedChecked(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), entries: List<&2, AiModels.AvailabilityResult()>, available: AiModels.AvailableResult()) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match available:
    case Fail{error}: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationError(id, Resolve.errorMessage(error))})
    case Done{_}:
      do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        stopped : Bool <- signalAborted(signal)
        Bool.pick(Unit -> IO(Result<&2, &2, Resolve.ModelsError, Unit>), stopped,
          _ => IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationAborted(id)}),
          _ => do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
            all : List<&2, Model()> <- getModels(runtime)
            Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (readied(catalog, id, availabilityEntries(entries), all), Unit{}))
            return Done{Unit{}})(Unit{})

def synchronizedSnapshot(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), +entries: List<&2, AiModels.AvailabilityResult()>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  synchronizedChecked(runtime, id, signal, entries, AiModels.availableOf(Done{entries}))

def synchronizedAvailability(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), result: AiModels.AvailabilitiesResult()) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationError(id, Resolve.errorMessage(error))})
    case Done{entries}: synchronizedSnapshot(runtime, id, signal, entries)

def synchronizedRefreshError(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal(), error: Maybe<&2, String>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match error:
    case Some{reason}: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationError(id, reason)})
    case None{}:
      do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        available : AiModels.AvailabilitiesResult() <- AiModels.getAvailabilities(modelsOf(runtime), Some{id}, signal)
        synchronizedAvailability(runtime, id, signal, available)

def synchronizedRefresh(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), result: AiModels.ModelsRefreshResult) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match result:
    case AiModels.ModelsRefreshResult{True{}, _}: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationAborted(id)})
    case AiModels.ModelsRefreshResult{False{}, errors}: synchronizedRefreshError(runtime, id, signal, R.get(String, errors, id))

def synchronizeCredentialTask(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
    stopped : Bool <- signalAborted(signal)
    Bool.pick(Unit -> IO(Result<&2, &2, Resolve.ModelsError, Unit>), stopped,
      _ => IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Fail{synchronizationAborted(id)}),
      _ => do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        refreshed : AiModels.ModelsRefreshResult <- AiModels.refresh(modelsOf(runtime), AiModels.ModelsRefreshOptions{Some{False{}}, Some{[id]}, None{}, signal})
        synchronizedRefresh(runtime, id, signal, refreshed))(Unit{})

def synchronizeCredentialState(+runtime: ModelRuntime, +id: String, signal: Auth.Signal()) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match signal:
    case None{}: synchronizeCredentialTask(runtime, id, None{})
    case Some{caller}:
      do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        Ref.modify(RefreshWork, Unit, workRef(runtime), workContinued)
        Tasks.run(Result<&2, &2, Resolve.ModelsError, Unit>, caller,
          child => synchronizeCredentialTask(runtime, id, Some{child}),
          IO.pure(Maybe<&2, Result<&2, &2, Resolve.ModelsError, Unit>>, Some{Fail{synchronizationAborted(id)}}),
          workLeft(workRef(runtime)))

# A failed mutation and a committed mutation whose snapshot failed are
# different outcomes. The latter retains the credential and original cause.
type CredentialSynchronizationOperation is Data:
  LoginOperation{}
  LogoutOperation{}
  SetRuntimeApiKeyOperation{}
  RemoveRuntimeApiKeyOperation{}

type CredentialError is Data:
  CredentialFailure{cause: Resolve.ModelsError}
  CredentialSynchronizationError{providerId: String, operation: CredentialSynchronizationOperation, credential: Maybe<&2, Auth.Credential>, cause: Resolve.ModelsError}

def CredentialOutcome(-Value: Data) -> Data: Result<&2, &2, CredentialError, Value>
def LoginOutcome() -> Data: CredentialOutcome(Auth.Credential)

def credentialOperationName(operation: CredentialSynchronizationOperation) -> String:
  match operation:
    case LoginOperation{}: "login"
    case LogoutOperation{}: "logout"
    case SetRuntimeApiKeyOperation{}: "setRuntimeApiKey"
    case RemoveRuntimeApiKeyOperation{}: "removeRuntimeApiKey"

def credentialErrorMessage(error: CredentialError) -> String:
  match error:
    case CredentialFailure{cause}: Resolve.errorMessage(cause)
    case CredentialSynchronizationError{id, operation, _, _}: "Credential " ++ credentialOperationName(operation) ++ " committed for " ++ id ++ ", but local synchronization failed"

def credentialSynchronized(-Value: Data, id: String, operation: CredentialSynchronizationOperation, credential: Maybe<&2, Auth.Credential>, value: Value, result: Result<&2, &2, Resolve.ModelsError, Unit>) -> CredentialOutcome(Value):
  match result:
    case Done{_}: Done{value}
    case Fail{cause}: Fail{CredentialSynchronizationError{id, operation, credential, cause}}

# Provider-directed login waits for its store mutation before checking local
# synchronization, including when cancellation arrives after the commit.
def loginDone(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), result: Auth.LoginOutcome()) -> IO(LoginOutcome()):
  match result:
    case Fail{error}: IO.pure(LoginOutcome(), Fail{CredentialFailure{Resolve.ModelsError{Resolve.AuthError{}, error}}})
    case Done{+credential}:
      do IO<LoginOutcome()>:
        synchronized : Result<&2, &2, Resolve.ModelsError, Unit> <- synchronizeCredentialState(runtime, id, signal)
        return credentialSynchronized(Auth.Credential, id, LoginOperation{}, Some{credential}, credential, synchronized)

def loginUnlessAborted(+runtime: ModelRuntime, +id: String, kind: Auth.CredentialType, interaction: Auth.AuthInteraction, signal: Auth.Signal(), aborted: Bool) -> IO(LoginOutcome()):
  match aborted:
    case True{}: IO.pure(LoginOutcome(), Fail{CredentialFailure{Resolve.ModelsError{Resolve.AuthError{}, "Login cancelled"}}})
    case False{}:
      do IO<LoginOutcome()>:
        result : Auth.LoginOutcome() <- AiModels.login(modelsOf(runtime), id, kind, interaction)
        loginDone(runtime, id, signal, result)

def loginTask(+runtime: ModelRuntime, +id: String, kind: Auth.CredentialType, interaction: Auth.AuthInteraction) -> IO(LoginOutcome()):
  match interaction:
    case Auth.AuthInteraction{+signal, prompt, notify}:
      do IO<LoginOutcome()>:
        aborted : Bool <- signalAborted(signal)
        loginUnlessAborted(runtime, id, kind, Auth.AuthInteraction{signal, prompt, notify}, signal, aborted)

def logoutDone(+runtime: ModelRuntime, +id: String, signal: Auth.Signal(), result: Result<&2, &2, Resolve.ModelsError, Unit>) -> IO(CredentialOutcome(Unit)):
  match result:
    case Fail{error}: IO.pure(CredentialOutcome(Unit), Fail{CredentialFailure{error}})
    case Done{_}:
      do IO<CredentialOutcome(Unit)>:
        synchronized : Result<&2, &2, Resolve.ModelsError, Unit> <- synchronizeCredentialState(runtime, id, signal)
        return credentialSynchronized(Unit, id, LogoutOperation{}, None{}, Unit{}, synchronized)

# Deletion and provider availability settle before logout reports success.
def logoutTask(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  do IO<CredentialOutcome(Unit)>:
    result : Result<&2, &2, Resolve.ModelsError, Unit> <- AiModels.logout(modelsOf(runtime), id, signal)
    logoutDone(runtime, id, signal, result)

def setRuntimeApiKeyReady(+runtime: ModelRuntime, +id: String, +key: String, signal: Auth.Signal(), provider: Maybe<&2, AiModels.Provider>) -> IO(CredentialOutcome(Unit)):
  match provider:
    case None{}: IO.pure(CredentialOutcome(Unit), Fail{CredentialFailure{unknownProvider(id)}})
    case Some{_}:
      do IO<CredentialOutcome(Unit)>:
        RuntimeCredentials.setRuntimeApiKey(runtimeCredentialsOf(runtime), id, key)
        synchronized : Result<&2, &2, Resolve.ModelsError, Unit> <- synchronizeCredentialState(runtime, id, signal)
        return credentialSynchronized(Unit, id, SetRuntimeApiKeyOperation{}, Some{Auth.ApiKeyCredential{Some{key}, None{}}}, Unit{}, synchronized)

def setRuntimeApiKeyTask(+runtime: ModelRuntime, +id: String, +key: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  do IO<CredentialOutcome(Unit)>:
    stopped : Bool <- signalAborted(signal)
    Bool.pick(Unit -> IO(CredentialOutcome(Unit)), stopped,
      _ => IO.pure(CredentialOutcome(Unit), Fail{CredentialFailure{Resolve.ModelsError{Resolve.AuthError{}, "This operation was aborted"}}}),
      _ => do IO<CredentialOutcome(Unit)>:
        provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
        setRuntimeApiKeyReady(runtime, id, key, signal, provider))(Unit{})

def removeRuntimeApiKeyTask(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  do IO<CredentialOutcome(Unit)>:
    stopped : Bool <- signalAborted(signal)
    Bool.pick(Unit -> IO(CredentialOutcome(Unit)), stopped,
      _ => IO.pure(CredentialOutcome(Unit), Fail{CredentialFailure{Resolve.ModelsError{Resolve.AuthError{}, "This operation was aborted"}}}),
      _ => do IO<CredentialOutcome(Unit)>:
        RuntimeCredentials.removeRuntimeApiKey(runtimeCredentialsOf(runtime), id)
        synchronized : Result<&2, &2, Resolve.ModelsError, Unit> <- synchronizeCredentialState(runtime, id, signal)
        return credentialSynchronized(Unit, id, RemoveRuntimeApiKeyOperation{}, None{}, Unit{}, synchronized))(Unit{})

# The queue token spans the mutation and its local synchronization. Other
# providers obtain independent tokens; typed failures release the token too.
def credentialQueuesOf(runtime: ModelRuntime) -> KeyedSerial.Registry:
  match runtime:
    case ModelRuntime{_, _, _, _, _, _, _, _, _, queues}: queues

type CredentialPhase is Data:
  CredentialQueued{}
  CredentialStarted{}
  CredentialCancelled{}

def startCredential(phase: CredentialPhase) -> CredentialPhase & Bool:
  match phase:
    case CredentialQueued{}: (CredentialStarted{}, True{})
    case other: (other, False{})

def cancelCredential(phase: CredentialPhase) -> CredentialPhase & Bool:
  match phase:
    case CredentialQueued{}: (CredentialCancelled{}, True{})
    case CredentialCancelled{}: (CredentialCancelled{}, True{})
    case CredentialStarted{}: (CredentialStarted{}, False{})

def credentialAbort(-Outcome: Data, phase: Ref.Ref<CredentialPhase>, cancelled: Outcome) -> IO(Maybe<&2, Outcome>):
  do IO<Maybe<&2, Outcome>>:
    stopped : Bool <- Ref.modify(CredentialPhase, Bool, phase, cancelCredential)
    return Bool.pick(Maybe<&2, Outcome>, stopped, Some{cancelled}, None{})

def credentialCleanup(runtime: ModelRuntime, phase: Ref.Ref<CredentialPhase>) -> IO(Unit):
  do IO<Unit>:
    previous : CredentialPhase <- Ref.dispose(CredentialPhase, phase)
    workLeft(workRef(runtime))

def credentialStarted(-Outcome: Data, start: Bool, task: IO(Outcome), cancelled: Outcome) -> IO(Unit & Outcome):
  match start:
    case False{}: IO.pure(Unit & Outcome, (Unit{}, cancelled))
    case True{}:
      do IO<Unit & Outcome>:
        result : Outcome <- task
        return (Unit{}, result)

def credentialLocked(-Outcome: Data, phase: Ref.Ref<CredentialPhase>, task: IO(Outcome), cancelled: Outcome) -> IO(Unit & Outcome):
  do IO<Unit & Outcome>:
    start : Bool <- Ref.modify(CredentialPhase, Bool, phase, startCredential)
    credentialStarted(Outcome, start, task, cancelled)

def credentialLeased(-Outcome: Data, +runtime: ModelRuntime, id: String, signal: Auth.Signal(), task: IO(Outcome), +cancelled: Outcome) -> IO(Outcome):
  match signal:
    case None{}:
      do IO<Outcome>:
        queue : Serial.Handle<Unit> <- KeyedSerial.queue(credentialQueuesOf(runtime), id)
        result : Outcome <- Serial.run(Unit, Outcome, queue, _ => do IO<Unit & Outcome>:
          value : Outcome <- task
          return (Unit{}, value))
        workLeft(workRef(runtime))
        return result
    case Some{caller}:
      do IO<Outcome>:
        +phase : Ref.Ref<CredentialPhase> <- Ref.new(CredentialPhase, CredentialQueued{})
        Tasks.run(Outcome, caller,
          _ => do IO<Outcome>:
            queue : Serial.Handle<Unit> <- KeyedSerial.queue(credentialQueuesOf(runtime), id)
            Serial.run(Unit, Outcome, queue, _ => credentialLocked(Outcome, phase, task, cancelled)),
          credentialAbort(Outcome, phase, cancelled), credentialCleanup(runtime, phase))

def serializedCredential(-Outcome: Data, +runtime: ModelRuntime, id: String, signal: Auth.Signal(), task: IO(Outcome), +cancelled: Outcome) -> IO(Outcome):
  do IO<Outcome>:
    admitted : Bool <- Ref.modify(RefreshWork, Bool, workRef(runtime), workStarted)
    Bool.pick(Unit -> IO(Outcome), admitted,
      _ => credentialLeased(Outcome, runtime, id, signal, task, cancelled),
      _ => IO.pure(Outcome, cancelled))(Unit{})

def login(+runtime: ModelRuntime, +id: String, kind: Auth.CredentialType, +interaction: Auth.AuthInteraction) -> IO(LoginOutcome()):
  match interaction:
    case Auth.AuthInteraction{signal, _, _}:
      serializedCredential(LoginOutcome(), runtime, id, signal, loginTask(runtime, id, kind, interaction), Fail{CredentialFailure{Resolve.ModelsError{Resolve.AuthError{}, "Login cancelled"}}})

def logout(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  serializedCredential(CredentialOutcome(Unit), runtime, id, signal, logoutTask(runtime, id, signal), Fail{CredentialFailure{Resolve.abortedError()}})

def setRuntimeApiKey(+runtime: ModelRuntime, +id: String, key: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  serializedCredential(CredentialOutcome(Unit), runtime, id, signal, setRuntimeApiKeyTask(runtime, id, key, signal), Fail{CredentialFailure{Resolve.abortedError()}})

def removeRuntimeApiKey(+runtime: ModelRuntime, +id: String, +signal: Auth.Signal()) -> IO(CredentialOutcome(Unit)):
  serializedCredential(CredentialOutcome(Unit), runtime, id, signal, removeRuntimeApiKeyTask(runtime, id, signal), Fail{CredentialFailure{Resolve.abortedError()}})

# Creation
# --------

# Providers without models.json, as test fixtures build them. The runtime
# owns the store.
def fromProvidersWithStore(+providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext, store: Store.ModelsStore) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    catalog : Ref.Ref<Catalog> <- Ref.new(Catalog, emptyCatalog())
    storeState : StoreState() <- Ref.new(Maybe<&1, Files.FileModelsReadState>, None{})
    +runtimeCredentials : RuntimeCredentials.RuntimeCredentials <- RuntimeCredentials.create(credentials)
    +credentialStore : Auth.CredentialStore <- RuntimeCredentials.store(runtimeCredentials)
    +models : AiModels.Models <- AiModels.createModels(AiModels.CreateModelsOptions{Some{credentialStore}, Some{store}, Some{context}})
    AiModels.rebuildProviders(models, providers, Nil{})
    extensions : Ref.Ref<ExtensionState> <- Ref.new(ExtensionState, emptyExtensions())
    sharedRefresh : Ref.Ref<SharedRefresh> <- Ref.new(SharedRefresh, RefreshIdle{0n})
    refreshWork : Ref.Ref<RefreshWork> <- newRefreshWork()
    availability : Ref.Ref<AvailabilityStatus> <- Ref.new(AvailabilityStatus, AvailabilityStatus{0n, None{}})
    definition : Ref.Ref<Definition> <- Ref.new(Definition, Definition{providers,builtinIds(providers),Config.empty(),Nil{},Generation{Nil{},Nil{},Nil{}},StaticSource{providers},Nil{}})
    credentialQueues : KeyedSerial.Registry <- KeyedSerial.create()
    +runtime : ModelRuntime <- IO.pure(ModelRuntime, ModelRuntime{definition, models, catalog, storeState, extensions, sharedRefresh, availability, runtimeCredentials, refreshWork, credentialQueues})
    refreshAvailability(runtime, None{})
    return runtime

def fromProviders(providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    fromProvidersWithStore(providers, credentials, context, store)


def modelNetworkEnabled() -> IO(Bool):
  do IO<Bool>:
    offline : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_OFFLINE")
    return networkEnabled(offline)

# upstream create's initial refresh: cached catalogs are restored, and
# refreshed over the network only when allowModelNetwork is set and PI_OFFLINE
# is not; refreshOnCreate false skips it (static models remain available).
def initialRefresh(+runtime: ModelRuntime, options: CreateModelRuntimeOptions) -> IO(Unit):
  match options:
    case CreateModelRuntimeOptions{_, _, _, _, _, False{}}: IO.pure(Unit, Unit{})
    case CreateModelRuntimeOptions{_, _, allow, _, signal, True{}}:
      do IO<Unit>:
        enabled : Bool <- modelNetworkEnabled()
        result : ModelsRefreshResult <- refresh(runtime, ModelsRefreshOptions{Some{enabled && allow}, None{}, None{}, signal})
        return Unit{}

def assembledWith(composition: Composition, builtins: List<&2, String>, credentials: Auth.CredentialStore, config: Config.ModelConfig, source: DefinitionSource, radiusOwned: List<&2,AiModels.Provider>, choice: StoreChoice()) -> IO(ModelRuntime):
  match choice:
    case (store, state):
      do IO<ModelRuntime>:
        context : Auth.AuthContext <- Context.defaultProviderAuthContext()
        catalog : Ref.Ref<Catalog> <- Ref.new(Catalog, emptyCatalog())
        storeState : StoreState() <- Ref.new(Maybe<&1, Files.FileModelsReadState>, state)
        +runtimeCredentials : RuntimeCredentials.RuntimeCredentials <- RuntimeCredentials.create(credentials)
        +credentialStore : Auth.CredentialStore <- RuntimeCredentials.store(runtimeCredentials)
        models : AiModels.Models <- AiModels.createModels(AiModels.CreateModelsOptions{Some{credentialStore}, Some{store}, Some{context}})
        extensions : Ref.Ref<ExtensionState> <- Ref.new(ExtensionState, emptyExtensions())
        sharedRefresh : Ref.Ref<SharedRefresh> <- Ref.new(SharedRefresh, RefreshIdle{0n})
        refreshWork : Ref.Ref<RefreshWork> <- newRefreshWork()
        availability : Ref.Ref<AvailabilityStatus> <- Ref.new(AvailabilityStatus, AvailabilityStatus{0n, None{}})
        +runtime : ModelRuntime <- assembled(composition, builtins, config, source, radiusOwned, models, catalog, storeState, extensions, sharedRefresh, availability, runtimeCredentials, refreshWork)
        rebuildCollection(runtime, Nil{})
        return runtime

def optionsStore(options: CreateModelRuntimeOptions, modelsPath: Maybe<&2, String>) -> IO(StoreChoice()):
  match options:
    case CreateModelRuntimeOptions{injected, storePath, _, _, _, _}: modelsStoreFor(injected, storePath, modelsPath)

def catalogBaseUrlOf(options: CreateModelRuntimeOptions) -> String:
  match options:
    case CreateModelRuntimeOptions{_, _, _, baseUrl, _, _}: Maybe.default(&2, String, baseUrl, Remote.DEFAULT_CATALOG_BASE_URL())

# upstream ModelRuntime.create. The credential store is borrowed; the
# built-in providers are owned from here on.
def createWithProviders(credentials: Auth.CredentialStore, defaults: List<&2, AiModels.Provider>, +modelsPath: Maybe<&2, String>, +radius: Radius.RadiusTransport, +options: CreateModelRuntimeOptions) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    +config : Config.ModelConfig <- Config.load(modelsPath)
    mark : SourceMark <- sourceMark(modelsPath)
    choice : StoreChoice() <- optionsStore(options, modelsPath)
    +remote : List<&2, AiModels.Provider> <- withRemoteCatalogs(defaults, remoteTransport(radius), catalogBaseUrlOf(options))
    +builtins : List<&2, AiModels.Provider> <- configureRadiusProviders(Config.getProviderIds(config), remote, config, radius)
    composition : Composition <- rebuildProviders(composedIds(builtins, config), builtins, config, Composition{Nil{}, Nil{}, Nil{}, Nil{}})
    +runtime : ModelRuntime <- assembledWith(composition, builtinIds(builtins), credentials, config, sourceFromPath(modelsPath,remote,radius,mark), radiusOwners(Config.getProviderIds(config),config,builtins), choice)
    initialRefresh(runtime, options)
    return runtime

# The credential store is borrowed; the OAuth handlers are owned from here on.
def createWithOptions(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, +radius: Radius.RadiusTransport, modelsPath: Maybe<&2, String>, options: CreateModelRuntimeOptions) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    builtins : List<&2, AiModels.Provider> <- Builtin.builtinProviders(codex, anthropicOAuth, radius)
    createWithProviders(credentials, builtins, modelsPath, radius, options)

def createWithModelsPath(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, radius: Radius.RadiusTransport, modelsPath: Maybe<&2, String>) -> IO(ModelRuntime):
  createWithOptions(credentials, codex, anthropicOAuth, radius, modelsPath, createOptions())

# Upstream's default models path: <agentDir>/models.json.
def createWithAnthropicOptions(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, radius: Radius.RadiusTransport, options: CreateModelRuntimeOptions) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    modelsPath : Maybe<&2, String> <- defaultModelsPath()
    createWithOptions(credentials, codex, anthropicOAuth, radius, modelsPath, options)

def createWithAnthropic(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, radius: Radius.RadiusTransport) -> IO(ModelRuntime):
  createWithAnthropicOptions(credentials, codex, anthropicOAuth, radius, createOptions())
