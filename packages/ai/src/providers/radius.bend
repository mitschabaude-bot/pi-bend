import Base
import ../models.bend as Models
import ../models-store.bend as Store
import ../types.bend as T
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ../auth/oauth/radius.bend as RadiusOAuth
import ./radius.models.bend as Catalog
import ./radius-config.bend as Config
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/url.bend as URL

# upstream providers/radius.ts: the Radius gateway provider with a persisted,
# dynamically refreshed catalog. The default gateway ships the static public
# catalog; refreshes restore the stored catalog, import one cached on a
# legacy OAuth credential, then load the gateway config when the network is
# allowed. Models stream through pi-messages. The HTTP client for the OAuth
# flow and the config is injected (upstream uses the global fetch).

def Model() -> Data: T.Model<T.JsonValue>

type RadiusProviderOptions is Data:
  RadiusProviderOptions{id: Maybe<&2, String>, name: Maybe<&2, String>, gateway: Maybe<&2, String>}

type RadiusTransport is Data:
  RadiusTransport{fetch: Fetch.Fetch(Unit), urlContext: URL.Context}

def defaultOptions() -> RadiusProviderOptions: RadiusProviderOptions{None{}, None{}, None{}}

def withProvider(+id: String, model: Model()) -> Model():
  match model:
    case T.Model{mid, name, api, _, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}: T.Model{mid, name, api, id, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def owned(+id: String, models: List<&2, Model()>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: withProvider(id, model) <> owned(id, rest)

# The public catalog applies only to the default gateway.
def baselineModels(+id: String, +gateway: String) -> List<&2, Model()>:
  Bool.pick(Unit -> List<&2, Model()>, String.eq(gateway, Config.normalizeRadiusGatewayUrl(Config.DEFAULT_RADIUS_GATEWAY())), _ => owned(id, Catalog.RADIUS_MODELS()), _ => Nil{})(Unit{})

# Refresh
# -------

type Refresh is Data:
  Refresh{id: String, gateway: String, baseline: List<&2, Model()>, transport: RadiusTransport}

def publish(context: Models.RefreshModelsContext, publication: Models.ModelsPublication) -> IO(Bool): Models.published(context, publication)

def storedEntry(context: Models.RefreshModelsContext) -> Maybe<&2, Store.ModelsStoreEntry>:
  match context:
    case Models.RefreshModelsContext{_, stored, _, _, _, _}: stored

def credentialOf(context: Models.RefreshModelsContext) -> Maybe<&2, Auth.Credential>:
  match context:
    case Models.RefreshModelsContext{credential, _, _, _, _, _}: credential

def isOAuth(credential: Maybe<&2, Auth.Credential>) -> Bool:
  match credential:
    case Some{Auth.OAuthCredential{_, _, _, _}}: True{}
    case _: False{}

# The OAuth access token, else the stored API key.
def apiKeyOf(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.OAuthCredential{_, access, _, _}}: Some{access}
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case None{}: None{}

def overlaid(refresh: Refresh, +dynamic: List<&2, Model()>) -> List<&2, Model()>:
  match refresh:
    case Refresh{_, _, baseline, _}: Models.mergeModels(baseline, dynamic)

def persisted(+models: List<&2, Model()>, now: F64) -> Models.Persist: Models.StoreEntry{Store.ModelsStoreEntry{models, None{}, Some{now}, None{}}}

def refreshId(refresh: Refresh) -> String:
  match refresh:
    case Refresh{id, _, _, _}: id

def publishConfig(+refresh: Refresh, +context: Models.RefreshModelsContext, value: Config.RadiusGatewayConfig) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    now : F64 <- Date.now()
    +refreshed : List<&2, Model()> <- IO.pure(List<&2, Model()>, Config.getRadiusModelsFromConfig(refreshId(refresh), value))
    accepted : Bool <- publish(context, Models.ModelsPublication{persisted(refreshed, now), Some{overlaid(refresh, refreshed)}})
    return Done{Unit{}}

def loadedChecked(refresh: Refresh, +context: Models.RefreshModelsContext, value: Config.RadiusGatewayConfig, aborted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match aborted:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{}: publishConfig(refresh, context, value)

def loaded(refresh: Refresh, +context: Models.RefreshModelsContext, config: Result<&2, &2, String, Config.RadiusGatewayConfig>) -> IO(Result<&2, &2, String, Unit>):
  match config:
    case Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case Done{value}:
      do IO<Result<&2, &2, String, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, Models.signalOf(context))
        loadedChecked(refresh, context, value, aborted)

def requestConfig(+refresh: Refresh, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match refresh:
    case Refresh{_, gateway, _, RadiusTransport{fetch, url}}:
      do IO<Result<&2, &2, String, Unit>>:
        config : Result<&2, &2, String, Config.RadiusGatewayConfig> <- Config.loadRadiusGatewayConfig(fetch, url, gateway, apiKeyOf(credentialOf(context)), Models.signalOf(context))
        loaded(refresh, context, config)

def networkChecked(refresh: Refresh, +context: Models.RefreshModelsContext, skip: Bool) -> IO(Result<&2, &2, String, Unit>):
  match skip:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case False{}: requestConfig(refresh, context)

def fromNetwork(refresh: Refresh, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    aborted : Bool <- Abort.aborted(Unit, Models.signalOf(context))
    networkChecked(refresh, context, Bool.not(Models.networkAllowed(context)) || aborted)

def afterLegacy(refresh: Refresh, +context: Models.RefreshModelsContext, accepted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match accepted:
    case False{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case True{}: fromNetwork(refresh, context)

def publishLegacy(+refresh: Refresh, +context: Models.RefreshModelsContext, +legacy: List<&2, Model()>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    now : F64 <- Date.now()
    accepted : Bool <- publish(context, Models.ModelsPublication{persisted(legacy, now), Some{overlaid(refresh, legacy)}})
    afterLegacy(refresh, context, accepted)

def legacyChecked(refresh: Refresh, +context: Models.RefreshModelsContext, +legacy: List<&2, Model()>, use: Bool) -> IO(Result<&2, &2, String, Unit>):
  match use:
    case True{}: publishLegacy(refresh, context, legacy)
    case False{}: fromNetwork(refresh, context)

# Catalogs cached on the credential by the pre-ModelsStore implementation.
def fromLegacy(+refresh: Refresh, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  +legacy = Config.getRadiusModels(refreshId(refresh), credentialOf(context))
  legacyChecked(refresh, context, legacy, Bool.not(Maybe.is_some(&2, Store.ModelsStoreEntry, storedEntry(context))) && isOAuth(credentialOf(context)) && Bool.not(List.is_empty(&2, Model(), legacy)))

def afterRestore(refresh: Refresh, +context: Models.RefreshModelsContext, accepted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match accepted:
    case False{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case True{}: fromLegacy(refresh, context)

def restored(+refresh: Refresh, +context: Models.RefreshModelsContext, stored: Maybe<&2, Store.ModelsStoreEntry>) -> IO(Result<&2, &2, String, Unit>):
  match stored:
    case None{}: fromLegacy(refresh, context)
    case Some{Store.ModelsStoreEntry{models, _, _, _}}:
      do IO<Result<&2, &2, String, Unit>>:
        accepted : Bool <- publish(context, Models.ModelsPublication{Models.KeepStored{}, Some{overlaid(refresh, Models.ownedBy(models, refreshId(refresh)))}})
        afterRestore(refresh, context, accepted)

# upstream refreshModels.
def refreshRun(refresh: Refresh, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  restored(refresh, context, storedEntry(context))

def refreshModels(refresh: Refresh, context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>): refreshRun(refresh, context)

# upstream radiusProvider. Transport callbacks are borrowed.
def radiusProvider(options: RadiusProviderOptions, transport: RadiusTransport) -> IO(Models.Provider):
  match options transport:
    case RadiusProviderOptions{id, name, gateway} RadiusTransport{+fetch, +url}:
      +pid = Maybe.default(&2, String, id, "radius")
      +pname = Maybe.default(&2, String, name, "Radius")
      +selected = Config.normalizeRadiusGatewayUrl(Maybe.default(&2, String, gateway, Config.DEFAULT_RADIUS_GATEWAY()))
      +baseline = baselineModels(pid, selected)
      do IO<Models.Provider>:
        apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Radius API key", ["RADIUS_API_KEY"])
        oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth(pname, selected, fetch, url)
        refresher : Models.RefreshModels() <- C.create(~Refresh, ~Models.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshModels, Refresh{pid, selected, baseline, RadiusTransport{fetch, url}})
        return Models.Provider{pid, pname, "", Auth.ProviderAuth{Some{apiKey}, Some{oauth}}, baseline, Models.ApiStreams{}, Some{refresher}}
