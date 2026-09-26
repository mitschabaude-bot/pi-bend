import Base
import ../config.bend as Config
import ./model-config.bend as ModelConfig
import ./provider-composer.bend as Composer
import ../utils/management-http.bend as Http
import ../utils/pi-user-agent.bend as UserAgent
import ../../../ai/src/types.bend as T
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/models-store.bend as Store
import ../../../ai/src/utils/model-api.bend as Api
import ../../../ai/src/utils/provider-retry.bend as Retry
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/uri-component.bend as URI
import ../../../runtime/src/url.bend as URL

# upstream core/remote-catalog-provider.ts: a built-in provider's catalog
# overlaid with pi.dev's persisted per-provider catalog. The overlay is the
# refreshModels publication (the provider's models once it is accepted).
# Transport is the caller's fetch.

def DEFAULT_CATALOG_BASE_URL() -> String: "https://pi.dev"
def REMOTE_CATALOG_ATTEMPT_TIMEOUT_MS() -> U32: 4000
def REMOTE_CATALOG_REFRESH_INTERVAL_MS() -> F64: F.fromU32(14400000)

# Upstream sets only a per-attempt timeout; the overall budget is unbounded.
def UNBOUNDED_MS() -> U32: 4294967295

def RESPONSE_LIMIT() -> Nat: 67108864n

def Model() -> Data: T.Model<T.JsonValue>

type RemoteCatalogTransport is Data:
  RemoteCatalogTransport{fetch: Fetch.Fetch(Unit), url: URL.Context}

type RemoteCatalog is Data:
  RemoteCatalog{providerId: String, baseline: List<&2, Model()>, transport: RemoteCatalogTransport, catalogBaseUrl: String, localGeneratedAt: Maybe<&2, F64>}

# Catalog parsing
# ---------------

def textEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, V.Text{value}} <> rest: R.Property{key, value} <> textEntries(rest)
    case _ <> rest: textEntries(rest)

def headersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{textEntries(R.entries(V.Value, properties))}}
    case _: None{}

def withHeaders(model: Model(), headers: Maybe<&2, R.Record<String>>) -> Model():
  match model:
    case T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, _, compat}: T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def definitionText(definition: ModelConfig.ModelsJsonModel, +field: String) -> String:
  match definition field:
    case ModelConfig.ModelsJsonModel{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _} "api": Maybe.default(&2, String, api, "")
    case ModelConfig.ModelsJsonModel{_, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _} _: Maybe.default(&2, String, baseUrl, "")

def fieldOf(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

# One catalog entry as a model of this provider (upstream `{...model, provider}`).
def catalogModel(+providerId: String, +value: V.Value) -> Model():
  +definition = ModelConfig.modelOf(value)
  withHeaders(Composer.builtModel(providerId, definition, None{}, Api.fromString(definitionText(definition, "api")), definitionText(definition, "baseUrl")), headersOf(fieldOf(value, "headers")))

def hasId(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{fields}: Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "id"))
    case _: False{}

def catalogModels(+providerId: String, entries: List<&2, V.Value>) -> List<&2, Model()>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = catalogModels(providerId, rest)
      Bool.pick(List<&2, Model()>, hasId(entry), catalogModel(providerId, entry) <> tail, tail)

def propertyValues(properties: List<&2, R.Property<V.Value>>) -> List<&2, V.Value>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{_, value} <> rest: value <> propertyValues(rest)

def modelsOrValues(models: Maybe<&2, V.Value>, +fields: R.Record<V.Value>) -> List<&2, V.Value>:
  match models:
    case Some{V.ArrayValue{entries}}: entries
    case _: propertyValues(R.entries(V.Value, fields))

def objectEntries(+fields: R.Record<V.Value>) -> List<&2, V.Value>: modelsOrValues(R.get(V.Value, fields, "models"), fields)

# upstream parseCatalog: an array of models, {models: [...]}, or a keyed object.
def parseCatalog(+providerId: String, value: V.Value) -> Result<&2, &2, String, List<&2, Model()>>:
  match value:
    case V.ArrayValue{entries}: Done{catalogModels(providerId, entries)}
    case V.ObjectValue{fields}: Done{catalogModels(providerId, objectEntries(fields))}
    case _: Fail{"Invalid model catalog for provider \"" ++ providerId ++ "\""}

def modelsOf(entry: Store.ModelsStoreEntry) -> List<&2, Model()>:
  match entry:
    case Store.ModelsStoreEntry{models, _, _, _}: models

# upstream remoteModels: the stored overlay unless the built-in catalog is at
# least as new.
def remoteModels(entry: Maybe<&2, Store.ModelsStoreEntry>, localGeneratedAt: Maybe<&2, F64>) -> List<&2, Model()>:
  match entry localGeneratedAt:
    case None{} _: Nil{}
    case Some{Store.ModelsStoreEntry{models, _, _, _}} None{}: models
    case Some{Store.ModelsStoreEntry{_, None{}, _, _}} Some{_}: Nil{}
    case Some{Store.ModelsStoreEntry{models, Some{modified}, _, _}} Some{local}: Bool.pick(List<&2, Model()>, F64.is_le(modified, local), Nil{}, models)

# Refresh
# -------

def persisted(entry: Store.ModelsStoreEntry) -> AiModels.ModelsPublication: AiModels.ModelsPublication{AiModels.StoreEntry{entry}, None{}}

def emptyEntry() -> Store.ModelsStoreEntry: Store.ModelsStoreEntry{Nil{}, None{}, None{}, None{}}

def checkedEntry(stored: Maybe<&2, Store.ModelsStoreEntry>, +checkedAt: F64) -> Store.ModelsStoreEntry:
  match stored:
    case Some{Store.ModelsStoreEntry{models, modified, _, etag}}: Store.ModelsStoreEntry{models, modified, Some{checkedAt}, etag}
    case None{}: Store.ModelsStoreEntry{Nil{}, None{}, Some{checkedAt}, None{}}

# 404/501: pi.dev has no catalog for the provider; the overlay becomes empty.
def unavailableEntry(stored: Maybe<&2, Store.ModelsStoreEntry>, +checkedAt: F64) -> Store.ModelsStoreEntry:
  match stored:
    case Some{Store.ModelsStoreEntry{models, _, _, _}}: Store.ModelsStoreEntry{models, Some{F.fromU32(0)}, Some{checkedAt}, None{}}
    case None{}: Store.ModelsStoreEntry{Nil{}, Some{F.fromU32(0)}, Some{checkedAt}, None{}}

def nanZero(+value: F64) -> F64: Bool.pick(F64, F.isNaN(value), F.fromU32(0), value)

# Date.parse of Last-Modified (HTTP dates), 0 when absent or invalid.
def lastModifiedOf(epoch: U32 & U32, header: Maybe<&2, String>) -> F64:
  match header:
    case None{}: F.fromU32(0)
    case Some{text}: nanZero(Retry.parseDateAt(Date.words(epoch), text))

def headerValue(+metadata: Response.Metadata, name: String) -> Maybe<&2, String>:
  Result.default(&2, &2, Message.HeaderSyntaxError, Maybe<&2, String>, Message.get(Response.headers(metadata), name), None{})

def withValidator(+headers: Message.Headers, validator: Maybe<&2, String>) -> Message.Headers:
  match validator:
    case Some{etag}: Result.default(&2, &2, Message.HeaderSyntaxError, Message.Headers, Message.set(headers, "if-none-match", etag), headers)
    case None{}: headers

def requestHeaders(+userAgent: String, validator: Maybe<&2, String>) -> Message.Headers:
  +base = Result.default(&2, &2, Message.HeaderSyntaxError, Message.Headers, Result.bind(&2, &2, Message.HeaderSyntaxError, Message.Headers, Message.Headers, Message.set(Message.new(), "accept", "application/json"), next => Message.set(next, "User-Agent", userAgent)), Message.new())
  withValidator(base, validator)

# Revalidate only when a cached body backs the validator.
def validatorOf(stored: Maybe<&2, Store.ModelsStoreEntry>) -> Maybe<&2, String>:
  match stored:
    case Some{Store.ModelsStoreEntry{_ <> _, _, _, etag}}: etag
    case _: None{}

def released(body: Response.Body<Http.Scoped()>) -> IO(Unit):
  do IO<Unit>:
    next : Response.Next<Http.ReadError(), Http.Scoped()> <- Response.closeWith(Http.ReadError(), Http.Scoped(), Http.close, body)
    return Unit{}

type Outcome is Data:
  Outcome{result: Result<&2, &2, String, Unit>}

def unit() -> Result<&2, &2, String, Unit>: Done{Unit{}}

def publishOnly(+context: AiModels.RefreshModelsContext, publication: AiModels.ModelsPublication) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    accepted : Bool <- AiModels.published(context, publication)
    return Done{Unit{}}

def publishRefreshed(+context: AiModels.RefreshModelsContext, +baseline: List<&2, Model()>, +local: Maybe<&2, F64>, +entry: Store.ModelsStoreEntry, aborted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match aborted:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, unit())
    case False{}: publishOnly(context, AiModels.ModelsPublication{AiModels.StoreEntry{entry}, Some{AiModels.mergeModels(baseline, remoteModels(Some{entry}, local))}})

def refreshedCatalog(+context: AiModels.RefreshModelsContext, +id: String, +baseline: List<&2, Model()>, +local: Maybe<&2, F64>, +checkedAt: F64, +metadata: Response.Metadata, parsed: Result<&2, &2, String, List<&2, Model()>>) -> IO(Result<&2, &2, String, Unit>):
  match parsed:
    case Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case Done{refreshed}:
      do IO<Result<&2, &2, String, Unit>>:
        epoch : U32 & U32 <- IO.unixMilliseconds()
        aborted : Bool <- Abort.aborted(Unit, AiModels.signalOf(context))
        publishRefreshed(context, baseline, local, Store.ModelsStoreEntry{refreshed, Some{lastModifiedOf(epoch, headerValue(metadata, "last-modified"))}, Some{checkedAt}, headerValue(metadata, "etag")}, aborted)

def parsedBody(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +checkedAt: F64, +metadata: Response.Metadata, json: Result<&2, &2, Response.JSONError<Http.ReadError()>, V.Value>) -> IO(Result<&2, &2, String, Unit>):
  match catalog json:
    case _ Fail{Response.InvalidJSON{_}}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Unexpected token in JSON model catalog"})
    case _ Fail{_}: IO.pure(Result<&2, &2, String, Unit>, Fail{"Failed to read the model catalog response"})
    case RemoteCatalog{+id, baseline, _, _, local} Done{value}: refreshedCatalog(context, id, baseline, local, checkedAt, metadata, parseCatalog(id, value))

type Answer is Data:
  NotModified{}
  Unavailable{}
  Success{}
  Failure{}

def answerOf(+code: U32, ok: Bool, hasStored: Bool) -> Answer:
  Bool.pick(Answer, U32.is_eq(code, 304) && hasStored, NotModified{}, Bool.pick(Answer, U32.is_eq(code, 404) || U32.is_eq(code, 501), Unavailable{}, Bool.pick(Answer, ok, Success{}, Failure{})))

def catalogId(catalog: RemoteCatalog) -> String:
  match catalog:
    case RemoteCatalog{id, _, _, _, _}: id

def handled(answer: Answer, +catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +stored: Maybe<&2, Store.ModelsStoreEntry>, +checkedAt: F64, +code: U32, +metadata: Response.Metadata, body: Response.Body<Http.Scoped()>) -> IO(Result<&2, &2, String, Unit>):
  match answer:
    case NotModified{}:
      do IO<Result<&2, &2, String, Unit>>:
        released(body)
        publishOnly(context, persisted(checkedEntry(stored, checkedAt)))
    case Unavailable{}:
      do IO<Result<&2, &2, String, Unit>>:
        released(body)
        publishOnly(context, persisted(unavailableEntry(stored, checkedAt)))
    case Success{}:
      do IO<Result<&2, &2, String, Unit>>:
        json : Result<&2, &2, Response.JSONError<Http.ReadError()>, V.Value> <- Response.jsonWith(~Http.ReadError(), ~Http.Scoped(), ~Http.read, ~Http.close, RESPONSE_LIMIT(), body)
        parsedBody(catalog, context, checkedAt, metadata, json)
    case Failure{}:
      do IO<Result<&2, &2, String, Unit>>:
        released(body)
        published : Result<&2, &2, String, Unit> <- publishOnly(context, persisted(checkedEntry(stored, checkedAt)))
        return Fail{"Model catalog request failed for " ++ catalogId(catalog) ++ ": " ++ U32.show(code)}

def answered(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +stored: Maybe<&2, Store.ModelsStoreEntry>, +checkedAt: F64, +code: U32, +metadata: Response.Metadata, body: Response.Body<Http.Scoped()>) -> IO(Result<&2, &2, String, Unit>):
  handled(answerOf(code, Response.ok(metadata), Maybe.is_some(&2, Store.ModelsStoreEntry, stored)), catalog, context, stored, checkedAt, code, metadata, body)

def afterResponse(aborted: Bool, +catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +stored: Maybe<&2, Store.ModelsStoreEntry>, +checkedAt: F64, +metadata: Response.Metadata, body: Response.Body<Http.Scoped()>) -> IO(Result<&2, &2, String, Unit>):
  match aborted:
    case True{}:
      do IO<Result<&2, &2, String, Unit>>:
        released(body)
        return unit()
    case False{}: answered(catalog, context, stored, checkedAt, Response.metadataStatus(metadata), metadata, body)

def responded(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +stored: Maybe<&2, Store.ModelsStoreEntry>, result: Http.ScopedOutcome()) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{Http.errorMessage(error)})
    case Done{Response.Response{+metadata, body}}:
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, AiModels.signalOf(context))
        checkedAt : F64 <- Date.now()
        afterResponse(aborted, catalog, context, stored, checkedAt, metadata, body)

def resolvedPath(result: Result<&2, &2, URL.ResolveError, URL.URL>) -> Result<&2, &2, String, URL.URL>:
  match result:
    case Fail{_}: Fail{"Invalid URL"}
    case Done{url}: Done{url}

def resolvedUrl(+base: String, parsed: Result<&2, &2, URL.Error, URL.URL>, context: URL.Context, path: String) -> Result<&2, &2, String, URL.URL>:
  match parsed:
    case Fail{_}: Fail{"Invalid URL: " ++ base}
    case Done{url}: resolvedPath(URL.parseResolve(context, url, path))

def catalogUrl(+catalog: RemoteCatalog) -> Result<&2, &2, String, URL.URL>:
  match catalog:
    case RemoteCatalog{id, _, RemoteCatalogTransport{_, context}, +base, _}: resolvedUrl(base, URL.parse(context, base), context, "/api/models/providers/" ++ URL.encode(URL.EcmaUri{}, id))

def requested(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, +stored: Maybe<&2, Store.ModelsStoreEntry>, url: Result<&2, &2, String, URL.URL>) -> IO(Result<&2, &2, String, Unit>):
  match catalog url:
    case _ Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case RemoteCatalog{_, _, RemoteCatalogTransport{fetch, urlContext}, _, _} Done{address}:
      do IO<Result<&2, &2, String, Unit>>:
        userAgent : String <- UserAgent.getPiUserAgent(Config.version())
        result : Http.ScopedOutcome() <- Http.fetchWithRetry(fetch, urlContext, Http.Request{address, requestHeaders(userAgent, validatorOf(stored)), Http.Follow{}}, AiModels.signalOf(context), Http.FetchRetryOptions{None{}, None{}, UNBOUNDED_MS(), Some{REMOTE_CATALOG_ATTEMPT_TIMEOUT_MS()}})
        responded(catalog, context, stored, result)

# A fresh stored catalog (checked within the interval, with a known
# modification time) is not requested again unless the refresh is forced.
def fresh(+now: F64, forced: Bool, stored: Maybe<&2, Store.ModelsStoreEntry>) -> Bool:
  match forced stored:
    case True{} _: False{}
    case False{} Some{Store.ModelsStoreEntry{_, Some{_}, Some{checkedAt}, _}}: F64.is_lt(F.subtract(now, checkedAt), REMOTE_CATALOG_REFRESH_INTERVAL_MS())
    case _ _: False{}

def forcedOf(context: AiModels.RefreshModelsContext) -> Bool:
  match context:
    case AiModels.RefreshModelsContext{_, _, _, _, force, _}: Maybe.default(&2, Bool, force, False{})

def storedOf(context: AiModels.RefreshModelsContext) -> Maybe<&2, Store.ModelsStoreEntry>:
  match context:
    case AiModels.RefreshModelsContext{_, stored, _, _, _, _}: stored

def afterRestore(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext, accepted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match accepted:
    case False{}: IO.pure(Result<&2, &2, String, Unit>, unit())
    case True{}:
      +stored = storedOf(context)
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, AiModels.signalOf(context))
        now : F64 <- Date.now()
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), Bool.not(AiModels.networkAllowed(context)) || aborted || fresh(now, forcedOf(context), stored),
          _ => IO.pure(Result<&2, &2, String, Unit>, unit()),
          _ => requested(catalog, context, stored, catalogUrl(catalog)))(Unit{})

# upstream withRemoteCatalog refreshModels: restore the stored overlay, then
# (network allowed, not fresh) request pi.dev's catalog and persist it.
def refreshWith(+catalog: RemoteCatalog, +context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match catalog:
    case RemoteCatalog{+id, +baseline, _, _, +local}:
      do IO<Result<&2, &2, String, Unit>>:
        accepted : Bool <- AiModels.published(context, AiModels.ModelsPublication{AiModels.KeepStored{}, Some{AiModels.mergeModels(baseline, AiModels.ownedBy(remoteModels(storedOf(context), local), id))}})
        afterRestore(catalog, context, accepted)

def refreshCatalog(catalog: RemoteCatalog, context: AiModels.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>): refreshWith(catalog, context)

# upstream withRemoteCatalog: the provider with a pi.dev catalog overlay.
def withRemoteCatalog(provider: AiModels.Provider, transport: RemoteCatalogTransport, catalogBaseUrl: String, localGeneratedAt: Maybe<&2, F64>) -> IO(AiModels.Provider):
  match provider:
    case AiModels.Provider{+id, name, baseUrl, auth, +models, streams, _}:
      do IO<AiModels.Provider>:
        refresh : AiModels.RefreshModels() <- C.create(~RemoteCatalog, ~AiModels.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshCatalog, RemoteCatalog{id, models, transport, catalogBaseUrl, localGeneratedAt})
        return AiModels.Provider{id, name, baseUrl, auth, models, streams, Some{refresh}}
