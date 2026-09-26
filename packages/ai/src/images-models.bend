import Base
import ./types.bend as T
import ./auth/types.bend as Auth
import ./auth/resolve.bend as Resolve
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref

# upstream images-models.ts: image-generation providers (the image-side
# counterpart of Provider) and the ImagesModels collection with auth
# resolution and generation.
#
# Language-driven shape: the collection is an immutable value whose
# setProvider/deleteProvider/clearProviders return the next collection
# (upstream mutates a Map; replacement keeps the provider's position, as
# Map.set does). A provider's last-known catalog and its refresh state are
# shared references, because refreshes run concurrently with reads. Requests
# use the native option types: signals and fetch over the Unit abort reason,
# no telemetry context, and hook errors of type E. createImagesModels takes
# the credential store and auth context explicitly; the default in-memory
# store (auth/credential-store.ts) is not ported.

def Model() -> Data: T.ImagesModel<T.JsonValue>

def Options(-E: Data) -> Data: T.ImagesOptions<Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), E>

# One generateImages call: upstream's (model, context, options?) arguments.
type ImagesRequest<-E: Data> is Data:
  ImagesRequest{model: Model(), context: T.ImagesContext, options: Maybe<&2, Options(E)>}

# upstream ProviderImages: the api a provider generates through.
def ProviderImages(-E: Data) -> Data: C.Callback<ImagesRequest<E>, T.AssistantImages>

# upstream CreateImagesProviderOptions.refreshModels: the fetched list, or the
# message of the rejection.
def RefreshImagesModels() -> Data: C.Callback<Unit, Result<&2, &2, String, List<&2, Model()>>>

# A refresh runs while holding `outcome`, which keeps the latest refresh's
# result; `completed` counts finished refreshes and is read without waiting.
# A call that had to wait for a refresh which completed meanwhile shares its
# outcome (upstream's in-flight promise); a later call fetches again.
type Refresh is Data:
  Refresh{fetch: RefreshImagesModels(), outcome: Ref.Ref<Result<&2, &2, String, Unit>>, completed: Ref.Ref<Nat>}

type ImagesProvider<-E: Data> is Data:
  ImagesProvider{id: String, name: String, auth: Auth.ProviderAuth, models: Ref.Ref<List<&2, Model()>>, refresh: Maybe<&2, Refresh>, api: ProviderImages(E)}

type CreateImagesProviderOptions<-E: Data> is Data:
  CreateImagesProviderOptions{id: String, name: Maybe<&2, String>, auth: Auth.ProviderAuth, models: List<&2, Model()>, refreshModels: Maybe<&2, RefreshImagesModels()>, api: ProviderImages(E)}

type ImagesModels<-E: Data> is Data:
  ImagesModels{providers: List<&2, ImagesProvider<E>>, credentials: Auth.CredentialStore, authContext: Auth.AuthContext}

def getProviders(-E: Data, models: ImagesModels<E>) -> List<&2, ImagesProvider<E>>:
  match models:
    case ImagesModels{providers, _, _}: providers

def providerId(-E: Data, provider: ImagesProvider<E>) -> String:
  match provider:
    case ImagesProvider{id, _, _, _, _, _}: id

def findProvider(-E: Data, providers: List<&2, ImagesProvider<E>>, +id: String) -> Maybe<&2, ImagesProvider<E>>:
  match providers:
    case Nil{}: None{}
    case +provider <> rest: Bool.pick(Unit -> Maybe<&2, ImagesProvider<E>>, String.eq(providerId(E, provider), id), _ => Some{provider}, _ => findProvider(E, rest, id))(Unit{})

def getProvider(-E: Data, models: ImagesModels<E>, id: String) -> Maybe<&2, ImagesProvider<E>>:
  findProvider(E, getProviders(E, models), id)

def Outcome() -> Data: Result<&2, &2, String, Unit>

def bumped(n: Nat) -> Nat & Nat: Ref.copied(Nat, 1n + n)

def fetched(models: Ref.Ref<List<&2, Model()>>, completed: Ref.Ref<Nat>, result: Result<&2, &2, String, List<&2, Model()>>) -> IO(Outcome() & Outcome()):
  match result:
    case Fail{+message}:
      do IO<Outcome() & Outcome()>:
        count : Nat <- Ref.modify(Nat, Nat, completed, bumped)
        return (Fail{message}, Fail{message})
    case Done{list}:
      do IO<Outcome() & Outcome()>:
        Ref.write(List<&2, Model()>, models, list)
        count : Nat <- Ref.modify(Nat, Nat, completed, bumped)
        return (Done{Unit{}}, Done{Unit{}})

def runFetch(fetch: RefreshImagesModels(), models: Ref.Ref<List<&2, Model()>>, completed: Ref.Ref<Nat>) -> IO(Outcome() & Outcome()):
  do IO<Outcome() & Outcome()>:
    result : Result<&2, &2, String, List<&2, Model()>> <- C.call(Unit, Result<&2, &2, String, List<&2, Model()>>, fetch, Unit{})
    fetched(models, completed, result)

def shared(+last: Outcome()) -> IO(Outcome() & Outcome()): IO.pure(Outcome() & Outcome(), (last, last))

def refreshed(fetch: RefreshImagesModels(), models: Ref.Ref<List<&2, Model()>>, +completed: Ref.Ref<Nat>, seen: Nat, +last: Outcome()) -> IO(Outcome() & Outcome()):
  do IO<Outcome() & Outcome()>:
    now : Nat <- Ref.read(Nat, completed)
    Bool.pick(Unit -> IO(Outcome() & Outcome()), Nat.is_eq(now, seen), _ => runFetch(fetch, models, completed), _ => shared(last))(Unit{})

def refreshWith(models: Ref.Ref<List<&2, Model()>>, pending: Refresh) -> IO(Outcome()):
  match pending:
    case Refresh{fetch, outcome, +completed}:
      do IO<Outcome()>:
        seen : Nat <- Ref.read(Nat, completed)
        Ref.update(Outcome(), Outcome(), outcome, last => refreshed(fetch, models, completed, seen, last))

# upstream provider.refreshModels(): static providers have none; a
# rejection leaves the last-known list in place.
def refreshModels(-E: Data, provider: ImagesProvider<E>) -> IO(Result<&2, &2, String, Unit>):
  match provider:
    case ImagesProvider{_, _, _, models, None{}, _}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case ImagesProvider{_, _, _, models, Some{refreshing}, _}: refreshWith(models, refreshing)

def refreshFailure(id: String, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, Resolve.ModelsError, Unit>:
  match result:
    case Fail{cause}: Fail{Resolve.failure(Resolve.ModelSource{}, "Model refresh failed for " ++ id, cause)}
    case Done{_}: Done{Unit{}}

def refreshOne(-E: Data, +id: String, provider: Maybe<&2, ImagesProvider<E>>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match provider:
    case None{}: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Done{Unit{}})
    case Some{value}:
      do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        result : Result<&2, &2, String, Unit> <- refreshModels(E, value)
        return refreshFailure(id, result)

def forked(-E: Data, providers: List<&2, ImagesProvider<E>>) -> IO(List<&2, Chan(Result<&2, &2, String, Unit>)>):
  match providers:
    case Nil{}: IO.pure(List<&2, Chan(Result<&2, &2, String, Unit>)>, Nil{})
    case provider <> rest:
      do IO<List<&2, Chan(Result<&2, &2, String, Unit>)>>:
        task : Chan(Result<&2, &2, String, Unit>) <- IO.fork(Result<&2, &2, String, Unit>, refreshModels(E, provider))
        tasks : List<&2, Chan(Result<&2, &2, String, Unit>)> <- forked(E, rest)
        return task <> tasks

def joined(tasks: List<&2, Chan(Result<&2, &2, String, Unit>)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case task <> rest:
      do IO<Unit>:
        settled : Result<&2, &2, String, Unit> <- IO.join(Result<&2, &2, String, Unit>, task)
        joined(rest)

# upstream refresh(provider?): one provider's failure rejects with a
# model_source ModelsError; without an id every provider refreshes
# concurrently and failures are ignored.
def refresh(-E: Data, models: ImagesModels<E>, provider: Maybe<&2, String>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match provider:
    case Some{+id}: refreshOne(E, id, getProvider(E, models, id))
    case None{}:
      do IO<Result<&2, &2, Resolve.ModelsError, Unit>>:
        tasks : List<&2, Chan(Result<&2, &2, String, Unit>)> <- forked(E, getProviders(E, models))
        joined(tasks)
        return Done{Unit{}}

def createdRefresh(fetch: Maybe<&2, RefreshImagesModels()>) -> IO(Maybe<&2, Refresh>):
  match fetch:
    case None{}: IO.pure(Maybe<&2, Refresh>, None{})
    case Some{callback}:
      do IO<Maybe<&2, Refresh>>:
        outcome : Ref.Ref<Outcome()> <- Ref.new(Outcome(), Done{Unit{}})
        completed : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
        return Some{Refresh{callback, outcome, completed}}

# upstream createImagesProvider; the name defaults to the id.
def createImagesProvider(-E: Data, input: CreateImagesProviderOptions<E>) -> IO(ImagesProvider<E>):
  match input:
    case CreateImagesProviderOptions{+id, name, auth, initial, fetchModels, api}:
      do IO<ImagesProvider<E>>:
        catalog : Ref.Ref<List<&2, Model()>> <- Ref.new(List<&2, Model()>, initial)
        refreshing : Maybe<&2, Refresh> <- createdRefresh(fetchModels)
        return ImagesProvider{id, Maybe.default(&2, String, name, id), auth, catalog, refreshing, api}

def providerAuth(-E: Data, provider: ImagesProvider<E>) -> Auth.ProviderAuth:
  match provider:
    case ImagesProvider{_, _, auth, _, _, _}: auth

# upstream provider.getModels(): the last-known list.
def providerModels(-E: Data, provider: ImagesProvider<E>) -> IO(List<&2, Model()>):
  match provider:
    case ImagesProvider{_, _, _, models, _, _}: Ref.read(List<&2, Model()>, models)

def hasRefresh(-E: Data, provider: ImagesProvider<E>) -> Bool:
  match provider:
    case ImagesProvider{_, _, _, _, Some{_}, _}: True{}
    case _: False{}

def callApi(-E: Data, api: ProviderImages(E), request: ImagesRequest<E>) -> IO(T.AssistantImages):
  C.call(ImagesRequest<E>, T.AssistantImages, api, request)

# upstream provider.generateImages.
def generateWith(-E: Data, provider: ImagesProvider<E>, request: ImagesRequest<E>) -> IO(T.AssistantImages):
  match provider:
    case ImagesProvider{_, _, _, _, _, api}: callApi(E, api, request)

def disposeRefresh(value: Maybe<&2, Refresh>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Refresh{fetch, outcome, completed}}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, String, List<&2, Model()>>, fetch)
        last : Outcome() <- Ref.dispose(Outcome(), outcome)
        count : Nat <- Ref.dispose(Nat, completed)
        return Unit{}

# Releases the provider's auth callbacks, api, refresh and catalog.
def disposeImagesProvider(-E: Data, provider: ImagesProvider<E>) -> IO(Unit):
  match provider:
    case ImagesProvider{_, _, auth, models, refreshing, api}:
      do IO<Unit>:
        Auth.disposeProviderAuth(auth)
        C.dispose(ImagesRequest<E>, T.AssistantImages, api)
        disposeRefresh(refreshing)
        last : List<&2, Model()> <- Ref.dispose(List<&2, Model()>, models)
        return Unit{}

# ImagesModels
# ------------

# upstream createImagesModels.
def createImagesModels(-E: Data, credentials: Auth.CredentialStore, authContext: Auth.AuthContext) -> ImagesModels<E>:
  ImagesModels{Nil{}, credentials, authContext}

def prepended(-E: Data, head: ImagesProvider<E>, pair: List<&2, ImagesProvider<E>> & Bool) -> List<&2, ImagesProvider<E>> & Bool:
  match pair:
    case (rest, found): (head <> rest, found)

def replaced(-E: Data, providers: List<&2, ImagesProvider<E>>, +provider: ImagesProvider<E>) -> List<&2, ImagesProvider<E>> & Bool:
  match providers:
    case Nil{}: (Nil{}, False{})
    case +current <> +rest:
      Bool.pick(Unit -> List<&2, ImagesProvider<E>> & Bool, String.eq(providerId(E, current), providerId(E, provider)), _ => (provider <> rest, True{}), _ => prepended(E, current, replaced(E, rest, provider)))(Unit{})

def appendedUnlessFound(-E: Data, +provider: ImagesProvider<E>, pair: List<&2, ImagesProvider<E>> & Bool) -> List<&2, ImagesProvider<E>>:
  match pair:
    case (list, True{}): list
    case (list, False{}): List.append(&2, ImagesProvider<E>, list, [provider])

# Upsert/replace by provider id; ids are unique.
def setProvider(-E: Data, models: ImagesModels<E>, +provider: ImagesProvider<E>) -> ImagesModels<E>:
  match models:
    case ImagesModels{providers, credentials, context}: ImagesModels{appendedUnlessFound(E, provider, replaced(E, providers, provider)), credentials, context}

def withoutId(-E: Data, providers: List<&2, ImagesProvider<E>>, +id: String) -> List<&2, ImagesProvider<E>>:
  match providers:
    case Nil{}: Nil{}
    case +provider <> rest:
      +tail = withoutId(E, rest, id)
      Bool.pick(List<&2, ImagesProvider<E>>, String.eq(providerId(E, provider), id), tail, provider <> tail)

def deleteProvider(-E: Data, models: ImagesModels<E>, id: String) -> ImagesModels<E>:
  match models:
    case ImagesModels{providers, credentials, context}: ImagesModels{withoutId(E, providers, id), credentials, context}

def clearProviders(-E: Data, models: ImagesModels<E>) -> ImagesModels<E>:
  match models:
    case ImagesModels{_, credentials, context}: ImagesModels{Nil{}, credentials, context}

def allModels(-E: Data, providers: List<&2, ImagesProvider<E>>) -> IO(List<&2, Model()>):
  match providers:
    case Nil{}: IO.pure(List<&2, Model()>, Nil{})
    case provider <> rest:
      do IO<List<&2, Model()>>:
        head : List<&2, Model()> <- providerModels(E, provider)
        tail : List<&2, Model()> <- allModels(E, rest)
        return List.append(&2, Model(), head, tail)

def selectedModels(-E: Data, provider: Maybe<&2, ImagesProvider<E>>) -> IO(List<&2, Model()>):
  match provider:
    case None{}: IO.pure(List<&2, Model()>, Nil{})
    case Some{value}: providerModels(E, value)

# upstream getModels(provider?): last-known models of one provider (none for
# an unknown id) or of all providers in registration order.
def getModels(-E: Data, models: ImagesModels<E>, provider: Maybe<&2, String>) -> IO(List<&2, Model()>):
  match provider:
    case None{}: allModels(E, getProviders(E, models))
    case Some{id}: selectedModels(E, getProvider(E, models, id))

def modelId(model: Model()) -> String:
  match model:
    case T.ImagesModel{id, _, _, _, _, _, _, _, _, _, _, _, _}: id

def modelProvider(model: Model()) -> String:
  match model:
    case T.ImagesModel{_, _, _, provider, _, _, _, _, _, _, _, _, _}: provider

def findModel(models: List<&2, Model()>, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Unit -> Maybe<&2, Model()>, String.eq(modelId(model), id), _ => Some{model}, _ => findModel(rest, id))(Unit{})

def getModel(-E: Data, models: ImagesModels<E>, provider: String, id: String) -> IO(Maybe<&2, Model()>):
  do IO<Maybe<&2, Model()>>:
    list : List<&2, Model()> <- getModels(E, models, Some{provider})
    return findModel(list, id)

def resolvedFor(-E: Data, credentials: Auth.CredentialStore, context: Auth.AuthContext, +overrides: Resolve.AuthResolutionOverrides, provider: Maybe<&2, ImagesProvider<E>>) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Done{None{}})
    case Some{+value}: Resolve.resolveProviderAuth(Resolve.ProviderRef{providerId(E, value), providerAuth(E, value)}, credentials, context, overrides)

# upstream getAuth(providerId | model, overrides?): undefined for an unknown
# or unconfigured provider.
def getAuth(-E: Data, models: ImagesModels<E>, providerId: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match models:
    case ImagesModels{providers, credentials, context}: resolvedFor(E, credentials, context, overrides, findProvider(E, providers, providerId))

def getModelAuth(-E: Data, models: ImagesModels<E>, model: Model(), overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  getAuth(E, models, modelProvider(model), overrides)

# Generation
# ----------

def errorImages(model: Model(), message: String, timestamp: F64) -> T.AssistantImages:
  match model:
    case T.ImagesModel{id, _, api, provider, _, _, _, _, _, _, _, _, _}: T.AssistantImages{api, provider, id, Nil{}, None{}, None{}, T.ImagesError{}, Some{message}, timestamp}

def withBaseUrl(model: Model(), baseUrl: Maybe<&2, String>) -> Model():
  match model baseUrl:
    case T.ImagesModel{id, name, api, provider, _, levels, input, limits, cost, cache, sampling, headers, output} Some{SCon{c, cs}}: T.ImagesModel{id, name, api, provider, SCon{c, cs}, levels, input, limits, cost, cache, sampling, headers, output}
    case model _: model

def prefer(-A: Data, first: Maybe<&2, A>, second: Maybe<&2, A>) -> Maybe<&2, A>:
  match first:
    case Some{value}: Some{value}
    case None{}: second

# `{ ...base, ...overlay }`: overlay values replace base values in place and
# new keys follow.
def spreadEntries(-V: Data, entries: List<&2, R.Property<V>>, base: R.Record<V>) -> R.Record<V>:
  match entries:
    case Nil{}: base
    case R.Property{key, value} <> rest: spreadEntries(V, rest, R.set(V, base, key, value))

def spread(-V: Data, base: R.Record<V>, overlay: R.Record<V>) -> R.Record<V>:
  match overlay:
    case R.Record{entries}: spreadEntries(V, entries, base)

# `auth.headers || options.headers ? { ...auth.headers, ...options.headers } : undefined`
def mergedHeaders(auth: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.ProviderHeaders()>:
  match auth request:
    case None{} None{}: None{}
    case None{} Some{value}: Some{value}
    case Some{value} None{}: Some{value}
    case Some{base} Some{value}: Some{spread(T.Nullable<String>, base, value)}

def authBaseUrl(auth: Auth.ModelAuth) -> Maybe<&2, String>:
  match auth:
    case Auth.ModelAuth{_, _, baseUrl}: baseUrl

def nowMs() -> IO(F64): Date.now()

def mergedEnv(fromAuth: Maybe<&2, T.ProviderEnv()>, request: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, T.ProviderEnv()>:
  match fromAuth request:
    case None{} None{}: None{}
    case None{} Some{value}: Some{value}
    case Some{value} None{}: Some{value}
    case Some{base} Some{value}: Some{spread(String, base, value)}

# Explicit request options win per field; headers and env merge per key.
def mergedOptions(-E: Data, options: Maybe<&2, Options(E)>, auth: Auth.ModelAuth, env: Maybe<&2, T.ProviderEnv()>) -> Options(E):
  match options auth:
    case None{} Auth.ModelAuth{apiKey, headers, _}: T.ImagesOptions{None{}, None{}, apiKey, None{}, mergedEnv(env, None{}), None{}, None{}, mergedHeaders(headers, None{}), None{}, None{}, None{}, None{}}
    case Some{T.ImagesOptions{signal, telemetry, requestKey, fetch, requestEnv, onPayload, onResponse, requestHeaders, timeoutMs, maxRetries, maxRetryDelayMs, metadata}} Auth.ModelAuth{apiKey, headers, _}:
      T.ImagesOptions{signal, telemetry, prefer(String, requestKey, apiKey), fetch, mergedEnv(env, requestEnv), onPayload, onResponse, mergedHeaders(headers, requestHeaders), timeoutMs, maxRetries, maxRetryDelayMs, metadata}

def authorized(-E: Data, provider: ImagesProvider<E>, model: Model(), context: T.ImagesContext, options: Maybe<&2, Options(E)>, resolution: Maybe<&2, Auth.AuthResult>) -> IO(T.AssistantImages):
  match resolution:
    case None{}: generateWith(E, provider, ImagesRequest{model, context, options})
    case Some{Auth.AuthResult{+auth, env, _}}: generateWith(E, provider, ImagesRequest{withBaseUrl(model, authBaseUrl(auth)), context, Some{mergedOptions(E, options, auth, env)}})

def resolved(-E: Data, provider: ImagesProvider<E>, +model: Model(), context: T.ImagesContext, options: Maybe<&2, Options(E)>, result: Resolve.Resolution()) -> IO(T.AssistantImages):
  match result:
    case Fail{error}:
      do IO<T.AssistantImages>:
        timestamp : F64 <- nowMs()
        return errorImages(model, Resolve.errorMessage(error), timestamp)
    case Done{resolution}: authorized(E, provider, model, context, options, resolution)

def optionOverrides(-E: Data, options: Maybe<&2, Options(E)>) -> Resolve.AuthResolutionOverrides:
  match options:
    case None{}: Resolve.noOverrides()
    case Some{T.ImagesOptions{signal, _, apiKey, _, env, _, _, _, _, _, _, _}}: Resolve.AuthResolutionOverrides{apiKey, env, None{}, signal}

def dispatched(-E: Data, models: ImagesModels<E>, +model: Model(), context: T.ImagesContext, +options: Maybe<&2, Options(E)>, provider: Maybe<&2, ImagesProvider<E>>) -> IO(T.AssistantImages):
  match provider:
    case None{}:
      do IO<T.AssistantImages>:
        timestamp : F64 <- nowMs()
        return errorImages(model, "Unknown provider: " ++ modelProvider(model), timestamp)
    case Some{value}:
      do IO<T.AssistantImages>:
        result : Resolve.Resolution() <- getModelAuth(E, models, model, optionOverrides(E, options))
        resolved(E, value, model, context, options, result)

# upstream ImagesModels.generateImages: generation through the owning
# provider with auth resolved and merged. Never fails: an unknown provider or
# an auth rejection becomes an AssistantImages with stopReason "error".
def generateImages(-E: Data, +models: ImagesModels<E>, +model: Model(), context: T.ImagesContext, options: Maybe<&2, Options(E)>) -> IO(T.AssistantImages):
  dispatched(E, models, model, context, options, getProvider(E, models, modelProvider(model)))
