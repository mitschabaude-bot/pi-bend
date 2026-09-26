import Base
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
import ../../../runtime/src/filesystem.bend as FS
import ../config.bend as AppConfig
import ./model-config.bend as Config
import ./provider-composer.bend as Composer
import ../../../ai/src/models-store.bend as Store
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date

# The provider catalog with auth resolution: pi-ai's Models collection and the
# coding agent's ModelRuntime. Built-in providers are composed with their
# models.json entries and models.json custom providers are added. Extensions
# register native providers (registerNativeProvider) and dynamic providers
# publish catalogs through refresh(). Not ported: models-store.json (catalogs
# persist in an in-memory ModelsStore), reloading models.json on refresh,
# models.json overlays on extension providers and config-form extension
# providers (registerProvider(name, config)).

def Model() -> Data: Ai.Model<Ai.JsonValue>

# What changes after creation: extension providers in registration order,
# the catalogs dynamic providers published, each provider's refresh
# generation, and upstream's snapshot.configuredProviders (computed at
# creation and refreshed after credential or provider changes, so
# availability queries do not read the credential store).
type Catalog is Data:
  Catalog{natives: List<&2, AiModels.Provider>, published: R.Record<List<&2, Model()>>, generations: R.Record<Nat>, configured: List<&2, String>}

def emptyCatalog() -> Catalog: Catalog{Nil{}, R.new(List<&2, Model()>), R.new(Nat), Nil{}}

# `providers` is the composition of built-in and models.json providers;
# `builtins` are the built-in ids among them. `retained` owns the built-in
# auth parts that composed providers wrap. Extension providers are owned by
# the extensions that registered them.
type ModelRuntime is Data:
  ModelRuntime{providers: List<&2, AiModels.Provider>, builtins: List<&2, String>, credentials: Auth.CredentialStore, context: Auth.AuthContext, config: Config.ModelConfig, compositionErrors: List<&2, String>, retained: List<&2, Composer.Retained>, catalog: Ref.Ref<Catalog>, store: Store.ModelsStore}

# Composition (recomposeProvider/rebuildProviders)
# -----------------------------------------------

def providerId(provider: AiModels.Provider) -> String:
  match provider:
    case AiModels.Provider{id, _, _, _, _, _, _}: id

def providerModels(provider: AiModels.Provider) -> List<&2, Model()>:
  match provider:
    case AiModels.Provider{_, _, _, _, models, _, _}: models

def findProvider(providers: List<&2, AiModels.Provider>, +id: String) -> Maybe<&2, AiModels.Provider>:
  match providers:
    case Nil{}: None{}
    case +provider <> rest: Bool.pick(Maybe<&2, AiModels.Provider>, String.eq(providerId(provider), id), Some{provider}, findProvider(rest, id))

def base(provider: Maybe<&2, AiModels.Provider>) -> Maybe<&2, Composer.Base>:
  match provider:
    case None{}: None{}
    case Some{AiModels.Provider{_, name, url, auth, models, _, _}}: Some{Composer.Base{name, url, auth, models}}

type Composition is Data:
  Composition{providers: List<&2, AiModels.Provider>, errors: List<&2, String>, retained: List<&2, Composer.Retained>}

def added(provider: Maybe<&2, AiModels.Provider>, composition: Composition) -> Composition:
  match provider composition:
    case None{} composition: composition
    case Some{provider} Composition{providers, errors, retained}: Composition{provider <> providers, errors, retained}

# upstream composeProvider forwards refreshModels to the base provider. Here
# the base's publications replace the composed provider's catalog, so a
# models.json overlay is not re-applied to a refreshed catalog.
def baseRefresh(builtin: Maybe<&2, AiModels.Provider>) -> Maybe<&2, AiModels.RefreshModels()>:
  match builtin:
    case Some{AiModels.Provider{_, _, _, _, _, _, refresher}}: refresher
    case None{}: None{}

# A failed composition keeps the built-in provider untouched (or omits a
# custom one) and records the error.
def recomposed(+id: String, +builtin: Maybe<&2, AiModels.Provider>, result: Result<&2, &2, String, Composer.Composed>, composition: Composition) -> Composition:
  match result composition:
    case Fail{error} Composition{providers, errors, retained}: added(builtin, Composition{providers, ("Provider \"" ++ id ++ "\": " ++ error) <> errors, retained})
    case Done{Composer.Composed{name, url, auth, models, owned}} Composition{providers, errors, retained}: Composition{AiModels.Provider{id, name, url, auth, models, AiModels.inheritedStreams(builtin), baseRefresh(builtin)} <> providers, errors, List.append(&2, Composer.Retained, owned, retained)}

def recomposeProvider(+id: String, +builtin: Maybe<&2, AiModels.Provider>, entry: Maybe<&2, Config.ModelsJsonProvider>, composition: Composition) -> IO(Composition):
  match entry:
    # No overlay: the built-in provider is used untouched.
    case None{}: IO.pure(Composition, added(builtin, composition))
    case Some{entry}:
      do IO<Composition>:
        result : Result<&2, &2, String, Composer.Composed> <- Composer.composeModelProvider(id, base(builtin), entry)
        return recomposed(id, builtin, result, composition)

def containsId(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, id) || containsId(rest, id)

def builtinIds(providers: List<&2, AiModels.Provider>) -> List<&2, String>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: providerId(provider) <> builtinIds(rest)

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

def assembled(composition: Composition, builtins: List<&2, String>, credentials: Auth.CredentialStore, context: Auth.AuthContext, config: Config.ModelConfig, catalog: Ref.Ref<Catalog>, store: Store.ModelsStore) -> ModelRuntime:
  match composition:
    case Composition{providers, errors, retained}: ModelRuntime{List.reverse(&2, AiModels.Provider, providers), builtins, credentials, context, config, List.reverse(&2, String, errors), retained, catalog, store}

def supportsOAuth(provider: Maybe<&2, AiModels.Provider>) -> Bool:
  match provider:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{_, Some{_}}, _, _, _}}: True{}
    case _: False{}

def unknownProvider(id: String) -> Resolve.ModelsError:
  Resolve.ModelsError{Resolve.ProviderError{}, "Unknown provider: " ++ id}

def providerRef(provider: AiModels.Provider) -> Resolve.ProviderRef:
  match provider:
    case AiModels.Provider{id, _, _, auth, _, _, _}: Resolve.ProviderRef{id, auth}

# Current catalog
# ---------------

def credentialsOf(runtime: ModelRuntime) -> Auth.CredentialStore:
  match runtime:
    case ModelRuntime{_, _, credentials, _, _, _, _, _, _}: credentials

def contextOf(runtime: ModelRuntime) -> Auth.AuthContext:
  match runtime:
    case ModelRuntime{_, _, _, context, _, _, _, _, _}: context

def catalogRef(runtime: ModelRuntime) -> Ref.Ref<Catalog>:
  match runtime:
    case ModelRuntime{_, _, _, _, _, _, _, catalog, _}: catalog

def storeOf(runtime: ModelRuntime) -> Store.ModelsStore:
  match runtime:
    case ModelRuntime{_, _, _, _, _, _, _, _, store}: store

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

def publishedModels(+published: R.Record<List<&2, Model()>>, provider: AiModels.Provider) -> AiModels.Provider:
  match provider:
    case AiModels.Provider{+id, name, url, auth, models, streams, refresher}: AiModels.Provider{id, name, url, auth, Maybe.default(&2, List<&2, Model()>, R.get(List<&2, Model()>, published, id), models), streams, refresher}

def withPublished(providers: List<&2, AiModels.Provider>, +published: R.Record<List<&2, Model()>>) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: publishedModels(published, provider) <> withPublished(rest, published)

# upstream providerIds() order: built-in providers, extension providers with
# new ids, then models.json providers. An extension provider replaces the
# provider of its id, and a dynamic provider's models are its published
# catalog.
def effectiveProviders(+base: List<&2, AiModels.Provider>, +builtins: List<&2, String>, catalog: Catalog) -> List<&2, AiModels.Provider>:
  match catalog:
    case Catalog{+natives, +published, _, _}:
      withPublished(List.concat(&2, AiModels.Provider, [overridden(base, natives, True{}, builtins), addedNatives(natives, builtinIds(base)), overridden(base, natives, False{}, builtins)]), published)

def providersIn(runtime: ModelRuntime, catalog: Catalog) -> List<&2, AiModels.Provider>:
  match runtime:
    case ModelRuntime{providers, builtins, _, _, _, _, _, _, _}: effectiveProviders(providers, builtins, catalog)

def getProviders(+runtime: ModelRuntime) -> IO(List<&2, AiModels.Provider>):
  do IO<List<&2, AiModels.Provider>>:
    catalog : Catalog <- readCatalog(runtime)
    return providersIn(runtime, catalog)

def getProvider(+runtime: ModelRuntime, +id: String) -> IO(Maybe<&2, AiModels.Provider>):
  do IO<Maybe<&2, AiModels.Provider>>:
    providers : List<&2, AiModels.Provider> <- getProviders(runtime)
    return findProvider(providers, id)

# Auth
# ----

def resolveFor(credentials: Auth.CredentialStore, context: Auth.AuthContext, id: String, +provider: Maybe<&2, AiModels.Provider>, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Fail{unknownProvider(id)})
    case Some{provider}: Resolve.resolveProviderAuth(providerRef(provider), credentials, context, overrides)

def getAuth(+runtime: ModelRuntime, +id: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
    resolveFor(credentialsOf(runtime), contextOf(runtime), id, provider, overrides)

def resolvedAuth(resolution: Resolve.Resolution()) -> Bool:
  match resolution:
    case Done{Some{_}}: True{}
    case _: False{}

def resolvesAuth(+runtime: ModelRuntime, +id: String) -> IO(Bool):
  do IO<Bool>:
    resolution : Resolve.Resolution() <- getAuth(runtime, id, Resolve.noOverrides())
    return resolvedAuth(resolution)

# A models.json apiKey is checked without resolving it, so a command-backed
# key is never run for availability (upstream composed ApiKeyAuth.check).
def checkedConfigured(+runtime: ModelRuntime, +id: String, key: Maybe<&2, String>) -> IO(Bool):
  match key:
    case Some{key}: Composer.checkConfiguredApiKey(key, contextOf(runtime))
    case None{}: resolvesAuth(runtime, id)

def configuredKey(entry: Maybe<&2, Config.ModelsJsonProvider>) -> Maybe<&2, String>:
  match entry:
    case Some{Config.ModelsJsonProvider{_, _, apiKey, _, _, _, _, _, _, _}}: apiKey
    case None{}: None{}

def getModelConfig(runtime: ModelRuntime) -> Config.ModelConfig:
  match runtime:
    case ModelRuntime{_, _, _, _, config, _, _, _, _}: config

def checkedStored(+runtime: ModelRuntime, +id: String, +providers: List<&2, AiModels.Provider>, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Bool):
  match stored:
    case Done{Some{Auth.OAuthCredential{_, _, _, _}}}: IO.pure(Bool, supportsOAuth(findProvider(providers, id)))
    case Done{None{}}: checkedConfigured(runtime, id, configuredKey(Config.getProvider(getModelConfig(runtime), id)))
    case _: resolvesAuth(runtime, id)

def checkAmong(+runtime: ModelRuntime, +id: String, +providers: List<&2, AiModels.Provider>) -> IO(Bool):
  do IO<Bool>:
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(runtime), id, None{})
    checkedStored(runtime, id, providers, stored)

# upstream Models.checkProviderAuth: a stored OAuth credential counts when the
# provider supports OAuth, without refreshing it; otherwise the provider's
# API key must resolve.
def checkProviderAuth(+runtime: ModelRuntime, +id: String) -> IO(Bool):
  do IO<Bool>:
    providers : List<&2, AiModels.Provider> <- getProviders(runtime)
    checkAmong(runtime, id, providers)

# upstream AuthCheck: how a provider's auth is configured (and where from).
type AuthCheck is Data:
  AuthCheck{source: Maybe<&2, String>, kind: Auth.CredentialType}

def checkOf(resolution: Resolve.Resolution()) -> Result<&2, &2, String, Maybe<&2, AuthCheck>>:
  match resolution:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{None{}}: Done{None{}}
    case Done{Some{Auth.AuthResult{_, _, source}}}: Done{Some{AuthCheck{source, Auth.ApiKeyType{}}}}

def resolvedCheck(+runtime: ModelRuntime, +id: String) -> IO(Result<&2, &2, String, Maybe<&2, AuthCheck>>):
  do IO<Result<&2, &2, String, Maybe<&2, AuthCheck>>>:
    resolution : Resolve.Resolution() <- getAuth(runtime, id, Resolve.noOverrides())
    return checkOf(resolution)

def configuredCheck(+runtime: ModelRuntime, +id: String, key: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, AuthCheck>>):
  match key:
    case None{}: resolvedCheck(runtime, id)
    case Some{configured}:
      do IO<Result<&2, &2, String, Maybe<&2, AuthCheck>>>:
        ready : Bool <- Composer.checkConfiguredApiKey(configured, contextOf(runtime))
        return Done{Bool.pick(Maybe<&2, AuthCheck>, ready, Some{AuthCheck{None{}, Auth.ApiKeyType{}}}, None{})}

def storedCheck(+runtime: ModelRuntime, +id: String, provider: Maybe<&2, AiModels.Provider>, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Result<&2, &2, String, Maybe<&2, AuthCheck>>):
  match stored:
    case Fail{_}: IO.pure(Result<&2, &2, String, Maybe<&2, AuthCheck>>, Fail{"Credential store read failed for " ++ id})
    case Done{Some{Auth.OAuthCredential{_, _, _, _}}}: IO.pure(Result<&2, &2, String, Maybe<&2, AuthCheck>>, Done{Bool.pick(Maybe<&2, AuthCheck>, supportsOAuth(provider), Some{AuthCheck{Some{"OAuth"}, Auth.OAuthType{}}}, None{})})
    case Done{None{}}: configuredCheck(runtime, id, configuredKey(Config.getProvider(getModelConfig(runtime), id)))
    case Done{Some{_}}: resolvedCheck(runtime, id)

def checkKnown(+runtime: ModelRuntime, +id: String, provider: Maybe<&2, AiModels.Provider>) -> IO(Result<&2, &2, String, Maybe<&2, AuthCheck>>):
  match provider:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, AuthCheck>>, Done{None{}})
    case Some{found}:
      do IO<Result<&2, &2, String, Maybe<&2, AuthCheck>>>:
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(runtime), id, None{})
        storedCheck(runtime, id, Some{found}, stored)

# upstream ModelRuntime.checkAuth: how the provider is configured, without
# refreshing OAuth; nothing for an unknown or unconfigured provider, and an
# error when the credential store cannot be read.
def checkAuth(+runtime: ModelRuntime, +id: String) -> IO(Result<&2, &2, String, Maybe<&2, AuthCheck>>):
  do IO<Result<&2, &2, String, Maybe<&2, AuthCheck>>>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
    checkKnown(runtime, id, provider)

def configuredIds(+runtime: ModelRuntime, +all: List<&2, AiModels.Provider>, providers: List<&2, AiModels.Provider>) -> IO(List<&2, String>):
  match providers:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case provider <> rest:
      +id = providerId(provider)
      do IO<List<&2, String>>:
        ready : Bool <- checkAmong(runtime, id, all)
        +others : List<&2, String> <- configuredIds(runtime, all, rest)
        return Bool.pick(List<&2, String>, ready, id <> others, others)

def withConfigured(catalog: Catalog, configured: List<&2, String>) -> Catalog:
  match catalog:
    case Catalog{natives, published, generations, _}: Catalog{natives, published, generations, configured}

# upstream runAvailabilityRefresh: every provider's auth is checked again.
def refreshAvailability(+runtime: ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    +providers : List<&2, AiModels.Provider> <- getProviders(runtime)
    ids : List<&2, String> <- configuredIds(runtime, providers, providers)
    Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (withConfigured(catalog, ids), Unit{}))

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

# The credential store is borrowed; the built-in providers are owned from here on.
def createWithProviders(credentials: Auth.CredentialStore, +defaults: List<&2, AiModels.Provider>, modelsPath: Maybe<&2, String>, radius: Radius.RadiusTransport) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    +config : Config.ModelConfig <- Config.load(modelsPath)
    +builtins : List<&2, AiModels.Provider> <- configureRadiusProviders(Config.getProviderIds(config), defaults, config, radius)
    composition : Composition <- rebuildProviders(composedIds(builtins, config), builtins, config, Composition{Nil{}, Nil{}, Nil{}})
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    catalog : Ref.Ref<Catalog> <- Ref.new(Catalog, emptyCatalog())
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    +runtime : ModelRuntime <- IO.pure(ModelRuntime, assembled(composition, builtinIds(builtins), credentials, context, config, catalog, store))
    refreshAvailability(runtime)
    return runtime

# Providers without models.json, as test fixtures build them. The runtime
# owns the store.
def fromProvidersWithStore(+providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext, store: Store.ModelsStore) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    catalog : Ref.Ref<Catalog> <- Ref.new(Catalog, emptyCatalog())
    +runtime : ModelRuntime <- IO.pure(ModelRuntime, ModelRuntime{providers, builtinIds(providers), credentials, context, Config.empty(), Nil{}, Nil{}, catalog, store})
    refreshAvailability(runtime)
    return runtime

def fromProviders(providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    store : Store.ModelsStore <- Store.inMemoryModelsStore()
    fromProvidersWithStore(providers, credentials, context, store)

def locatedPath(path: Result<&2, &2, FS.Error, String>) -> Maybe<&2, String>:
  match path:
    case Done{path}: Some{path}
    case Fail{_}: None{}

# `<agentDir>/models.json`, the default models path.
def defaultModelsPath() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    path : Result<&2, &2, FS.Error, String> <- AppConfig.getModelsPath()
    return locatedPath(path)

# The credential store is borrowed; the OAuth handlers are owned from here on.
def createWithModelsPath(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, +radius: Radius.RadiusTransport, modelsPath: Maybe<&2, String>) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    builtins : List<&2, AiModels.Provider> <- Builtin.builtinProviders(codex, anthropicOAuth, radius)
    createWithProviders(credentials, builtins, modelsPath, radius)

# Upstream's default models path: <agentDir>/models.json.
def createWithAnthropic(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, radius: Radius.RadiusTransport) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    modelsPath : Maybe<&2, String> <- defaultModelsPath()
    createWithModelsPath(credentials, codex, anthropicOAuth, radius, modelsPath)

def disposeProviders(providers: List<&2, AiModels.Provider>) -> IO(Unit):
  match providers:
    case Nil{}: IO.pure(Unit, Unit{})
    case AiModels.Provider{_, _, _, auth, _, _, _} <> rest:
      do IO<Unit>:
        Auth.disposeProviderAuth(auth)
        disposeProviders(rest)

# Extension providers stay with the extensions that registered them.
def dispose(runtime: ModelRuntime) -> IO(Unit):
  match runtime:
    case ModelRuntime{providers, _, _, context, _, _, retained, catalog, store}:
      do IO<Unit>:
        disposeProviders(providers)
        Composer.disposeRetained(retained)
        Auth.disposeContext(context)
        Store.dispose(store)
        old : Catalog <- Ref.dispose(Catalog, catalog)
        return Unit{}

# models.json load and provider composition errors, as upstream getError().
def joinedErrors(configError: Maybe<&2, String>, errors: List<&2, String>) -> Maybe<&2, String>:
  match configError errors:
    case None{} Nil{}: None{}
    case None{} errors: Some{String.join(errors, "\n\n")}
    case Some{error} errors: Some{String.join(error <> errors, "\n\n")}

def getError(runtime: ModelRuntime) -> Maybe<&2, String>:
  match runtime:
    case ModelRuntime{_, _, _, _, config, errors, _, _, _}: joinedErrors(Config.getError(config), errors)

# Catalog
# -------

def streamsOf(provider: Maybe<&2, AiModels.Provider>) -> AiModels.ProviderStreams:
  match provider:
    case None{}: AiModels.ApiStreams{}
    case Some{AiModels.Provider{_, _, _, _, _, streams, _}}: streams

# How the provider's requests stream (upstream prepareRequest's provider).
def getProviderStreams(+runtime: ModelRuntime, +id: String) -> IO(AiModels.ProviderStreams):
  do IO<AiModels.ProviderStreams>:
    provider : Maybe<&2, AiModels.Provider> <- getProvider(runtime, id)
    return streamsOf(provider)

def allModels(providers: List<&2, AiModels.Provider>) -> List<&2, Model()>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: List.append(&2, Model(), providerModels(provider), allModels(rest))

def getModels(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    providers : List<&2, AiModels.Provider> <- getProviders(runtime)
    return allModels(providers)

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

def baseModels(runtime: ModelRuntime) -> List<&2, Model()>:
  match runtime:
    case ModelRuntime{providers, _, _, _, _, _, _, _, _}: allModels(providers)

# Auth
# ----

# upstream ModelPriceSource (cache-stats): a model's cache-read price, $ per
# million tokens. The price source is synchronous, so it prices the built-in
# and models.json catalog; extension and refreshed catalogs are not consulted.
def cacheReadPrice(runtime: ModelRuntime, provider: String) -> String -> Maybe<&2, F64>:
  id => Maybe.map(&2, Model(), F64, modelCacheRead, findModel(baseModels(runtime), provider, id))

def sameHeaderName(+left: String, +right: String) -> Bool: String.eq(String.to_lower(left), String.to_lower(right))

def withoutHeader(entries: List<&2, R.Property<Ai.Nullable<String>>>, +name: String) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutHeader(rest, name)
      Bool.pick(List<&2, R.Property<Ai.Nullable<String>>>, sameHeaderName(key, name), tail, R.Property{key, value} <> tail)

def overrideHeaders(overrides: List<&2, R.Property<Ai.Nullable<String>>>, entries: List<&2, R.Property<Ai.Nullable<String>>>) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match overrides:
    case Nil{}: entries
    case R.Property{+name, value} <> rest: overrideHeaders(rest, List.append(&2, R.Property<Ai.Nullable<String>>, withoutHeader(entries, name), R.Property{name, value} <> Nil{}))

# upstream mergeHeaders: an override replaces any header whose name differs
# only in case.
def mergeHeaders(base: Maybe<&2, Ai.ProviderHeaders()>, override: Maybe<&2, Ai.ProviderHeaders()>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match base override:
    case base None{}: base
    case None{} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, Nil{})}}
    case Some{R.Record{entries}} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, entries)}}

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
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, existing, url}, env, source}}} Done{configured}: Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, mergeHeaders(existing, configuredHeaders(configured)), url}, env, source}}}

def resolutionEnv(resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match resolution overrides:
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} Some{extra}: Some{Composer.spread(String, env, R.entries(String, extra))}
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} None{}: Some{env}
    case _ extra: extra

def withModelHeaders(+model: Model(), config: Maybe<&2, Config.ModelsJsonProvider>, +resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> IO(Resolve.Resolution()):
  match resolution:
    case Done{Some{_}}:
      do IO<Resolve.Resolution()>:
        headers : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- Composer.resolveConfiguredModelHeaders(model, config, resolutionEnv(resolution, overrides))
        return modelHeaders(resolution, headers)
    case other: IO.pure(Resolve.Resolution(), other)

def overrideEnv(overrides: Resolve.AuthResolutionOverrides) -> Maybe<&2, Ai.ProviderEnv()>:
  match overrides:
    case Resolve.AuthResolutionOverrides{_, env, _, _}: env

# Request auth for a model (upstream getAuth(model)): the provider's auth
# plus the model's own configured headers.
def getModelAuth(+runtime: ModelRuntime, +model: Model(), +overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    resolution : Resolve.Resolution() <- getAuth(runtime, Ai.modelProvider(model), overrides)
    withModelHeaders(model, Config.getProvider(getModelConfig(runtime), Ai.modelProvider(model)), resolution, overrideEnv(overrides))

def withoutId(ids: List<&2, String>, +id: String) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case +other <> +rest: Bool.pick(List<&2, String>, String.eq(other, id), withoutId(rest, id), other <> withoutId(rest, id))

def withProvider(ready: Bool, id: String, others: List<&2, String>) -> List<&2, String>:
  match ready:
    case True{}: id <> others
    case False{}: others

def readied(catalog: Catalog, ready: Bool, +id: String) -> Catalog:
  match catalog:
    case Catalog{natives, published, generations, configured}: Catalog{natives, published, generations, withProvider(ready, id, withoutId(configured, id))}

# upstream refreshProviderAvailability: one provider after its credentials
# or its registration changed (login, logout, a runtime API key).
def refreshProviderAvailability(+runtime: ModelRuntime, +id: String) -> IO(Unit):
  do IO<Unit>:
    ready : Bool <- checkProviderAuth(runtime, id)
    Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (readied(catalog, ready, id), Unit{}))

def containsProvider(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case other <> rest: String.eq(other, id) || containsProvider(rest, id)

def configuredOf(catalog: Catalog) -> List<&2, String>:
  match catalog:
    case Catalog{_, _, _, configured}: configured

def hasConfiguredAuth(runtime: ModelRuntime, +id: String) -> IO(Bool):
  do IO<Bool>:
    catalog : Catalog <- readCatalog(runtime)
    return containsProvider(configuredOf(catalog), id)

def configuredProviders(+ids: List<&2, String>, providers: List<&2, AiModels.Provider>) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = configuredProviders(ids, rest)
      Bool.pick(List<&2, AiModels.Provider>, containsProvider(ids, providerId(provider)), provider <> tail, tail)

# Models whose provider had configured auth at the last availability refresh.
def getAvailable(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    +catalog : Catalog <- readCatalog(runtime)
    return allModels(configuredProviders(configuredOf(catalog), providersIn(runtime, catalog)))

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
        available : List<&2, Model()> <- getAvailable(runtime)
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

# A new provider for an id supersedes refreshes of the provider it replaces,
# whose published catalog belonged to it (upstream supersedeProviderRefresh
# in setProvider/deleteProvider).
def superseded(+id: String, catalog: Catalog) -> Catalog:
  match catalog:
    case Catalog{natives, published, +generations, configured}:
      Catalog{natives, R.remove(List<&2, Model()>, published, id), R.set(Nat, generations, id, Nat.add(Maybe.default(&2, Nat, R.get(Nat, generations, id), 0n), 1n)), configured}

def withoutProvider(providers: List<&2, AiModels.Provider>, +id: String) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = withoutProvider(rest, id)
      Bool.pick(List<&2, AiModels.Provider>, String.eq(providerId(provider), id), tail, provider <> tail)

# An id keeps its position when an extension registers it again.
def replacedIn(providers: List<&2, AiModels.Provider>, +provider: AiModels.Provider) -> List<&2, AiModels.Provider>:
  match providers:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(AiModels.Provider, String.eq(providerId(current), providerId(provider)), provider, current) <> replacedIn(rest, provider)

def replacedProvider(+providers: List<&2, AiModels.Provider>, +provider: AiModels.Provider) -> List<&2, AiModels.Provider>:
  Bool.pick(List<&2, AiModels.Provider>, containsId(builtinIds(providers), providerId(provider)), replacedIn(providers, provider), List.append(&2, AiModels.Provider, providers, [provider]))

def withNatives(catalog: Catalog, update: List<&2, AiModels.Provider> -> List<&2, AiModels.Provider>) -> Catalog:
  match catalog:
    case Catalog{natives, published, generations, configured}: Catalog{update(natives), published, generations, configured}

def registeredNative(+provider: AiModels.Provider, catalog: Catalog) -> Catalog:
  withNatives(superseded(providerId(provider), catalog), natives => replacedProvider(natives, provider))

def unregisteredNative(+id: String, catalog: Catalog) -> Catalog:
  withNatives(superseded(id, catalog), natives => withoutProvider(natives, id))

def isBlank(text: String) -> Bool: String.is_empty(String.trim(text))

type ModelsRefreshOptions is Data:
  ModelsRefreshOptions{allowNetwork: Maybe<&2, Bool>, providers: Maybe<&2, List<&2, String>>, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

def refreshOptions() -> ModelsRefreshOptions: ModelsRefreshOptions{None{}, None{}, None{}, None{}}

# `errors` maps provider ids to the refresh failure message.
type ModelsRefreshResult is Data:
  ModelsRefreshResult{aborted: Bool, errors: R.Record<String>}

type Publisher is Data:
  Publisher{catalog: Ref.Ref<Catalog>, store: Store.ModelsStore, id: String, generation: Nat, signal: Abort.AbortSignal<Unit>}

def generationOf(catalog: Catalog, id: String) -> Maybe<&2, Nat>:
  match catalog:
    case Catalog{_, _, generations, _}: R.get(Nat, generations, id)

def stillCurrent(+catalog: Ref.Ref<Catalog>, +id: String, generation: Nat, signal: Abort.AbortSignal<Unit>) -> IO(Bool):
  do IO<Bool>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    state : Catalog <- Ref.read(Catalog, catalog)
    return Bool.not(aborted) && Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, latest => Nat.is_eq(latest, generation), generationOf(state, id)), False{})

def persisted(store: Store.ModelsStore, id: String, persist: AiModels.Persist, signal: Abort.AbortSignal<Unit>) -> IO(Store.StoreResult(Unit)):
  match persist:
    case AiModels.KeepStored{}: IO.pure(Store.StoreResult(Unit), Done{Unit{}})
    case AiModels.DeleteStored{}: Store.delete(store, id, Some{signal})
    case AiModels.StoreEntry{entry}: Store.write(store, id, entry, Some{signal})

def withPublication(catalog: Catalog, +id: String, models: Maybe<&2, List<&2, Model()>>) -> Catalog:
  match catalog models:
    case catalog None{}: catalog
    case Catalog{natives, published, generations, configured} Some{list}: Catalog{natives, R.set(List<&2, Model()>, published, id, list), generations, configured}

def applied(+catalog: Ref.Ref<Catalog>, +id: String, models: Maybe<&2, List<&2, Model()>>, accepted: Bool) -> IO(Bool):
  match accepted:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        Ref.modify(Catalog, Unit, catalog, state => (withPublication(state, id, models), Unit{}))
        return True{}

def afterPersist(+catalog: Ref.Ref<Catalog>, +id: String, generation: Nat, +signal: Abort.AbortSignal<Unit>, models: Maybe<&2, List<&2, Model()>>, stored: Store.StoreResult(Unit)) -> IO(Bool):
  match stored:
    case Fail{_}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        accepted : Bool <- stillCurrent(catalog, id, generation, signal)
        applied(catalog, id, models, accepted)

def publishAccepted(accepted: Bool, publisher: Publisher, publication: AiModels.ModelsPublication) -> IO(Bool):
  match accepted publisher publication:
    case False{} _ _: IO.pure(Bool, False{})
    case True{} Publisher{+catalog, store, +id, +generation, +signal} AiModels.ModelsPublication{persist, models}:
      do IO<Bool>:
        stored : Store.StoreResult(Unit) <- persisted(store, id, persist, signal)
        afterPersist(catalog, id, generation, signal, models, stored)

# upstream publishProviderModels: a superseded or aborted refresh publishes
# nothing; otherwise the persistence change happens first and the catalog
# update only if the refresh is still current afterwards. A store failure
# rejects the publication.
def publishModels(publisher: Publisher, publication: AiModels.ModelsPublication) -> IO(Bool):
  match publisher:
    case Publisher{+catalog, store, +id, +generation, +signal}:
      do IO<Bool>:
        accepted : Bool <- stillCurrent(catalog, id, generation, signal)
        publishAccepted(accepted, Publisher{catalog, store, id, generation, signal}, publication)

def providerAuthOf(provider: AiModels.Provider) -> Auth.ProviderAuth:
  match provider:
    case AiModels.Provider{_, _, _, auth, _, _, _}: auth

def refreshOf(provider: AiModels.Provider) -> Maybe<&2, AiModels.RefreshModels()>:
  match provider:
    case AiModels.Provider{_, _, _, _, _, _, refresher}: refresher

def storedOAuth(stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Done{Some{Auth.OAuthCredential{refresher, access, expires, extra}}}: Some{Auth.OAuthCredential{refresher, access, expires, extra}}
    case _: None{}

def reread(+runtime: ModelRuntime, +id: String, resolution: Resolve.Resolution()) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match resolution:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Fail{Resolve.errorMessage(error)})
    case Done{_}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(runtime), id, None{})
        return Done{storedOAuth(stored)}

def refreshedOAuth(+runtime: ModelRuntime, +id: String, oauth: Auth.OAuthAuth, +credential: Auth.Credential, signal: Abort.AbortSignal<Unit>, fresh: Bool) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match fresh:
    case True{}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{Some{credential}})
    case False{}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        resolution : Resolve.Resolution() <- Resolve.refreshStored(credentialsOf(runtime), id, oauth, signal, None{}, F.fromU32(0))
        reread(runtime, id, resolution)

def expiry(credential: Auth.Credential) -> F64:
  match credential:
    case Auth.OAuthCredential{_, _, expires, _}: expires
    case _: F.fromU32(0)

def resolvedKey(resolution: Resolve.Resolution()) -> Result<&2, &2, String, Maybe<&2, Auth.Credential>>:
  match resolution:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{None{}}: Done{None{}}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, _}, env, _}}}: Done{Some{Auth.ApiKeyCredential{key, env}}}

def apiKeyCredential(stored: Maybe<&2, Auth.Credential>) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Some{Auth.ApiKeyCredential{key, env}}: Some{Auth.ApiKeyCredential{key, env}}
    case _: None{}

# upstream resolveRefreshCredential: an OAuth credential is refreshed when it
# expired; otherwise the provider's API key auth must resolve.
def resolveRefreshCredential(+runtime: ModelRuntime, +id: String, stored: Maybe<&2, Auth.Credential>, auth: Auth.ProviderAuth, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Maybe<&2, Auth.Credential>>):
  match stored auth:
    case Some{Auth.OAuthCredential{refresher, access, expires, extra}} Auth.ProviderAuth{_, None{}}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{None{}})
    case Some{Auth.OAuthCredential{refresher, access, +expires, extra}} Auth.ProviderAuth{_, Some{oauth}}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        now : F64 <- Date.now()
        refreshedOAuth(runtime, id, oauth, Auth.OAuthCredential{refresher, access, expires, extra}, signal, F64.is_lt(now, expires))
    case stored Auth.ProviderAuth{None{}, _}: IO.pure(Result<&2, &2, String, Maybe<&2, Auth.Credential>>, Done{None{}})
    case stored Auth.ProviderAuth{Some{apiKey}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Auth.Credential>>>:
        resolution : Resolve.Resolution() <- Resolve.resolveApiKey(contextOf(runtime), apiKey, id, apiKeyCredential(stored), signal)
        return resolvedKey(resolution)

type Phase is Data:
  Phase{refresher: AiModels.RefreshModels(), publishing: C.Callback<AiModels.ModelsPublication, Bool>, signal: Abort.AbortSignal<Unit>}

def phaseStored(stored: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>), phase: Phase, credential: Maybe<&2, Auth.Credential>, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  match stored phase:
    case Fail{error} _: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{entry} Phase{refresher, publishing, signal}: C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, refresher, AiModels.RefreshModelsContext{credential, entry, publishing, allowNetwork, force, signal})

# upstream runProviderRefreshPhase: the provider sees the stored catalog as
# of this phase.
def runPhase(+runtime: ModelRuntime, +id: String, +phase: Phase, credential: Maybe<&2, Auth.Credential>, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  match phase:
    case Phase{+refresher, +publishing, +signal}:
      do IO<Result<&2, &2, String, Unit>>:
        stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(storeOf(runtime), id, Some{signal})
        phaseStored(stored, Phase{refresher, publishing, signal}, credential, allowNetwork, force)

def networkPhase(+runtime: ModelRuntime, +id: String, +phase: Phase, force: Maybe<&2, Bool>, credential: Result<&2, &2, String, Maybe<&2, Auth.Credential>>) -> IO(Result<&2, &2, String, Unit>):
  match credential:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{None{}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Done{Some{credential}}: runPhase(runtime, id, phase, Some{credential}, True{}, force)

def phaseSignal(phase: Phase) -> Abort.AbortSignal<Unit>:
  match phase:
    case Phase{_, _, signal}: signal

def afterCache(+runtime: ModelRuntime, +id: String, auth: Auth.ProviderAuth, +phase: Phase, allowNetwork: Bool, force: Maybe<&2, Bool>, cached: Result<&2, &2, String, Unit>, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Result<&2, &2, String, Unit>):
  match cached stored:
    case Fail{error} _: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{_} Fail{cause}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Credential store read failed for " ++ id ++ ": " ++ cause})
    case Done{_} Done{credential}:
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, phaseSignal(phase))
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), Bool.not(allowNetwork) || aborted, _ => IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}}), _ => do IO<Result<&2, &2, String, Unit>>:
          resolved : Result<&2, &2, String, Maybe<&2, Auth.Credential>> <- resolveRefreshCredential(runtime, id, credential, auth, phaseSignal(phase))
          networkPhase(runtime, id, phase, force, resolved))(Unit{})

def credentialOf(stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Maybe<&2, Auth.Credential>:
  match stored:
    case Done{credential}: credential
    case Fail{_}: None{}

# upstream Models.refresh for one provider: restore the cached catalog before
# auth resolution or network access, then refresh with the effective
# credential when the network is allowed.
def refreshPhases(+runtime: ModelRuntime, +id: String, auth: Auth.ProviderAuth, +phase: Phase, allowNetwork: Bool, force: Maybe<&2, Bool>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    +stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentialsOf(runtime), id, Some{phaseSignal(phase)})
    cached : Result<&2, &2, String, Unit> <- runPhase(runtime, id, phase, credentialOf(stored), False{}, None{})
    afterCache(runtime, id, auth, phase, allowNetwork, force, cached, stored)

# Starting a refresh supersedes an older one without discarding the catalog
# it published.
def begun(+id: String, catalog: Catalog) -> Catalog & Nat:
  match catalog:
    case Catalog{natives, published, +generations, configured}:
      +next = Nat.add(Maybe.default(&2, Nat, R.get(Nat, generations, id), 0n), 1n)
      (Catalog{natives, published, R.set(Nat, generations, id, next), configured}, next)

def recordedError(errors: R.Record<String>, +id: String, aborted: Bool, result: Result<&2, &2, String, Unit>) -> R.Record<String>:
  match aborted result:
    case False{} Fail{error}: R.set(String, errors, id, error)
    case _ _: errors

def refreshProvider(+runtime: ModelRuntime, +provider: AiModels.Provider, refresher: AiModels.RefreshModels(), allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  +id = providerId(provider)
  do IO<R.Record<String>>:
    generation : Nat <- Ref.modify(Catalog, Nat, catalogRef(runtime), catalog => begun(id, catalog))
    +publishing : C.Callback<AiModels.ModelsPublication, Bool> <- C.create(~Publisher, ~AiModels.ModelsPublication, ~Bool, ~publishModels, Publisher{catalogRef(runtime), storeOf(runtime), id, generation, signal})
    result : Result<&2, &2, String, Unit> <- refreshPhases(runtime, id, providerAuthOf(provider), Phase{refresher, publishing, signal}, allowNetwork, force)
    C.dispose(AiModels.ModelsPublication, Bool, publishing)
    aborted : Bool <- Abort.aborted(Unit, signal)
    return recordedError(errors, id, aborted, result)

def selected(filter: Maybe<&2, List<&2, String>>, +id: String) -> Bool:
  match filter:
    case None{}: True{}
    case Some{ids}: containsId(ids, id)

def refreshSelected(+runtime: ModelRuntime, provider: AiModels.Provider, chosen: Bool, refresher: Maybe<&2, AiModels.RefreshModels()>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  match chosen refresher:
    case True{} Some{refresher}: refreshProvider(runtime, provider, refresher, allowNetwork, force, signal, errors)
    case _ _: IO.pure(R.Record<String>, errors)

def refreshEach(+runtime: ModelRuntime, providers: List<&2, AiModels.Provider>, +filter: Maybe<&2, List<&2, String>>, +allowNetwork: Bool, +force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, errors: R.Record<String>) -> IO(R.Record<String>):
  match providers:
    case Nil{}: IO.pure(R.Record<String>, errors)
    case +provider <> rest:
      do IO<R.Record<String>>:
        next : R.Record<String> <- refreshSelected(runtime, provider, selected(filter, providerId(provider)), refreshOf(provider), allowNetwork, force, signal, errors)
        refreshEach(runtime, rest, filter, allowNetwork, force, signal, next)

def availabilityOf(+runtime: ModelRuntime, ids: List<&2, String>) -> IO(Unit):
  match ids:
    case Nil{}: IO.pure(Unit, Unit{})
    case id <> rest:
      do IO<Unit>:
        refreshProviderAvailability(runtime, id)
        availabilityOf(runtime, rest)

def refreshedAvailability(+runtime: ModelRuntime, filter: Maybe<&2, List<&2, String>>) -> IO(Unit):
  match filter:
    case None{}: refreshAvailability(runtime)
    case Some{ids}: availabilityOf(runtime, ids)

def refreshSignalled(+runtime: ModelRuntime, +filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    providers : List<&2, AiModels.Provider> <- getProviders(runtime)
    errors : R.Record<String> <- refreshEach(runtime, providers, filter, allowNetwork, force, signal, R.new(String))
    refreshedAvailability(runtime, filter)
    aborted : Bool <- Abort.aborted(Unit, signal)
    return ModelsRefreshResult{aborted, errors}

def refreshUnlessAborted(+runtime: ModelRuntime, filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>, aborted: Bool) -> IO(ModelsRefreshResult):
  match aborted:
    case True{}: IO.pure(ModelsRefreshResult, ModelsRefreshResult{True{}, R.new(String)})
    case False{}: refreshSignalled(runtime, filter, allowNetwork, force, signal)

def refreshWithSignal(+runtime: ModelRuntime, filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, +signal: Abort.AbortSignal<Unit>) -> IO(ModelsRefreshResult):
  do IO<ModelsRefreshResult>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    refreshUnlessAborted(runtime, filter, allowNetwork, force, signal, aborted)

# upstream operationSignal: providers always receive a concrete signal.
def refreshOwned(+runtime: ModelRuntime, filter: Maybe<&2, List<&2, String>>, allowNetwork: Bool, force: Maybe<&2, Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ModelsRefreshResult):
  match signal:
    case Some{signal}: refreshWithSignal(runtime, filter, allowNetwork, force, signal)
    case None{}:
      do IO<ModelsRefreshResult>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : ModelsRefreshResult <- refreshWithSignal(runtime, filter, allowNetwork, force, Abort.signal(Unit, controller))
        Abort.dispose(Unit, controller)
        return result

def networkEnabled(offline: Result<&1, &1, U32 & String, String>) -> Bool:
  match offline:
    case Done{_}: False{}
    case Fail{_}: True{}

# upstream ModelRuntime.refresh: dynamic providers (all, or the selected
# ones) restore their stored catalog and refresh it when the network is
# allowed (by default unless PI_OFFLINE is set); then availability is
# checked again. Refreshes run one provider at a time, and a superseded
# refresh keeps running but can no longer publish.
def refresh(+runtime: ModelRuntime, options: ModelsRefreshOptions) -> IO(ModelsRefreshResult):
  match options:
    case ModelsRefreshOptions{allowNetwork, filter, force, signal}:
      do IO<ModelsRefreshResult>:
        offline : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_OFFLINE")
        refreshOwned(runtime, filter, Maybe.default(&2, Bool, allowNetwork, networkEnabled(offline)), force, signal)

# upstream registerNativeProvider: the extension provider replaces any
# provider of its id until it is unregistered, and the cached catalogs are
# restored without network access.
def registerUnlessBlank(+runtime: ModelRuntime, +provider: AiModels.Provider, blank: Bool) -> IO(Result<&2, &2, String, Unit>):
  match blank:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Provider id must not be empty."})
    case False{}:
      do IO<Result<&2, &2, String, Unit>>:
        Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (registeredNative(provider, catalog), Unit{}))
        result : ModelsRefreshResult <- refresh(runtime, ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}})
        return Done{Unit{}}

def registerNativeProvider(+runtime: ModelRuntime, +provider: AiModels.Provider) -> IO(Result<&2, &2, String, Unit>):
  registerUnlessBlank(runtime, provider, isBlank(providerId(provider)))

# upstream unregisterProvider: the built-in or models.json provider of the id,
# if any, is restored.
def unregisterProvider(+runtime: ModelRuntime, +id: String) -> IO(Unit):
  do IO<Unit>:
    Ref.modify(Catalog, Unit, catalogRef(runtime), catalog => (unregisteredNative(id, catalog), Unit{}))
    result : ModelsRefreshResult <- refresh(runtime, ModelsRefreshOptions{Some{False{}}, None{}, None{}, None{}})
    return Unit{}

def nativeIdsOf(catalog: Catalog) -> List<&2, String>:
  match catalog:
    case Catalog{natives, _, _, _}: builtinIds(natives)

# upstream getRegisteredProviderIds (native extension providers).
def getRegisteredProviderIds(runtime: ModelRuntime) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    catalog : Catalog <- readCatalog(runtime)
    return nativeIdsOf(catalog)

# Provider-directed login. The interaction borrows its callbacks and optional
# signal; the runtime owns credential persistence and availability updates.
def loginMethod(auth: Auth.ProviderAuth, kind: Auth.CredentialType) -> Maybe<&2,C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()>>:
  match auth kind:
    case Auth.ProviderAuth{_,Some{Auth.OAuthAuth{_,_,_,login,_,_}}} Auth.OAuthType{}: Some{login}
    case Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_,login,_}},_} Auth.ApiKeyType{}: login
    case _ _: None{}
def loginReplacement(credential: Auth.Credential,old: Maybe<&2,Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2,Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2,Auth.Credential>),Done{Some{credential}})
def loginStored(+runtime: ModelRuntime,id: String,credential: Auth.Credential,stored: Auth.StoreResult(Maybe<&2,Auth.Credential>)) -> IO(Auth.LoginOutcome()):
  match stored:
    case Fail{error}: IO.pure(Auth.LoginOutcome(),Fail{"Could not save credentials: " ++ error})
    case Done{_}:
      do IO<Auth.LoginOutcome()>:
        refreshProviderAvailability(runtime,id)
        return Done{credential}
def loginCredential(+runtime: ModelRuntime,+id: String,result: Auth.LoginOutcome(),signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  match result:
    case Fail{error}: IO.pure(Auth.LoginOutcome(),Fail{error})
    case Done{+credential}:
      do IO<Auth.LoginOutcome()>:
        +update : Auth.Modification() <- C.create(~Auth.Credential,~Maybe<&2,Auth.Credential>,~Auth.StoreResult(Maybe<&2,Auth.Credential>),~loginReplacement,credential)
        stored : Auth.StoreResult(Maybe<&2,Auth.Credential>) <- Auth.modify(credentialsOf(runtime),id,update,Some{signal})
        C.dispose(Maybe<&2,Auth.Credential>,Auth.StoreResult(Maybe<&2,Auth.Credential>),update)
        loginStored(runtime,id,credential,stored)
def loginSupported(+runtime: ModelRuntime,+id: String,method: Maybe<&2,C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()>>,interaction: Auth.ProviderAuthInteraction,name: String,kind: Auth.CredentialType) -> IO(Auth.LoginOutcome()):
  match method interaction:
    case None{} _: IO.pure(Auth.LoginOutcome(),Fail{name ++ " does not support " ++ Auth.typeName(kind) ++ " login"})
    case Some{callback} Auth.ProviderAuthInteraction{+signal,prompt,notify}:
      do IO<Auth.LoginOutcome()>:
        result : Auth.LoginOutcome() <- C.call(Auth.ProviderAuthInteraction,Auth.LoginOutcome(),callback,Auth.ProviderAuthInteraction{signal,prompt,notify})
        loginCredential(runtime,id,result,signal)
def loginProvider(runtime: ModelRuntime,id: String,provider: Maybe<&2,AiModels.Provider>,+kind: Auth.CredentialType,interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match provider:
    case None{}: IO.pure(Auth.LoginOutcome(),Fail{"Unknown provider: " ++ id})
    case Some{AiModels.Provider{_,name,_,auth,_,_,_}}:
      loginSupported(runtime,id,loginMethod(auth,kind),interaction,name,kind)
def loginUnlessAborted(+runtime: ModelRuntime,+id: String,kind: Auth.CredentialType,interaction: Auth.ProviderAuthInteraction,aborted: Bool) -> IO(Auth.LoginOutcome()):
  match aborted:
    case True{}: IO.pure(Auth.LoginOutcome(),Fail{"Login cancelled"})
    case False{}:
      do IO<Auth.LoginOutcome()>:
        provider : Maybe<&2,AiModels.Provider> <- getProvider(runtime,id)
        loginProvider(runtime,id,provider,kind,interaction)
def loginSignalled(runtime: ModelRuntime,id: String,kind: Auth.CredentialType,+interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{signal,_,_}:
      do IO<Auth.LoginOutcome()>:
        aborted : Bool <- Abort.aborted(Unit,signal)
        loginUnlessAborted(runtime,id,kind,interaction,aborted)
def login(runtime: ModelRuntime,id: String,kind: Auth.CredentialType,interaction: Auth.AuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.AuthInteraction{Some{signal},prompt,notify}: loginSignalled(runtime,id,kind,Auth.ProviderAuthInteraction{signal,prompt,notify})
    case Auth.AuthInteraction{None{},prompt,notify}:
      do IO<Auth.LoginOutcome()>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Auth.LoginOutcome() <- loginSignalled(runtime,id,kind,Auth.ProviderAuthInteraction{Abort.signal(Unit,controller),prompt,notify})
        Abort.dispose(Unit,controller)
        return result
