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

# A model provider (upstream Provider): providers/<id>.bend construct the
# built-in ones and providers/all.bend lists them. Upstream's optional baseUrl
# is "" when absent. `models` is the catalog getModels() returns before any
# refresh; the model runtime keeps the catalogs a dynamic provider publishes.
# Not carried: headers (no built-in provider sets them) and filterModels.
type Provider is Data:
  Provider{id: String, name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, Model()>, streams: ProviderStreams, refreshModels: Maybe<&2, RefreshModels()>}

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
    case Some{Provider{_, _, _, _, _, ApiStreams{}, _}}: ApiStreams{}
    case Some{Provider{_, _, _, _, models, CloudflareStreams{apis}, _}}: CloudflareStreams{usedApis(apis, models)}
    case Some{Provider{_, _, _, _, models, OpenCodeStreams{apis}, _}}: OpenCodeStreams{usedApis(apis, models)}

# Leaf utilities from models.ts. The Models registry and runtime
# specialization remain pending; hasApi currently returns a boolean predicate.
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
