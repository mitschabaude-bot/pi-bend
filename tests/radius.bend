import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/models-store.bend as Store
import ../packages/ai/src/auth/oauth/radius.bend as RadiusOAuth
import ../packages/ai/src/providers/radius.bend as Radius
import ../packages/ai/src/providers/radius-config.bend as Config
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/model-json.bend as ModelJson
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/url.bend as URL

# The Radius suites (ai radius-provider.test.ts and radius-oauth.test.ts,
# coding-agent radius.test.ts) against a loopback gateway run by
# tests/radius_check.py: `radius <case> <loopback> [models.json]`. Upstream
# stubs the global fetch; here requests reach the loopback gateway, and
# requests for the public gateway (https://radius.pi.dev) or the custom
# test gateway (http://localhost:8788) are sent there too. Each request is
# printed as `request <method> <original url> <authorization>` and each
# case prints `PASS <name>` after its assertions.

def Log() -> Data: Ref.Ref<List<&2, String>>

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def pass(name: String) -> IO(Unit): IO.print("PASS " ++ name)

def num(+value: F64) -> String: Maybe.default(&2, String, F.toJsonNumber(value), "NaN")

def credentialText(result: Auth.LoginOutcome()) -> String:
  match result:
    case Fail{message}: "error " ++ message
    case Done{Auth.OAuthCredential{refresh, access, expires, extra}}: access ++ " " ++ refresh ++ " " ++ num(expires) ++ " " ++ Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(V.ObjectValue{extra})), "")
    case Done{_}: "api_key"

def answer(method: String, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>): IO.pure(Result<&2, &2, String, String>, Done{method})

def eventText(event: Auth.AuthEvent) -> String:
  match event:
    case Auth.DeviceCodeEvent{user, uri, interval, expires}: "device_code " ++ user ++ " " ++ uri ++ " " ++ num(Maybe.default(&2, F64, interval, F.fromU32(0))) ++ " " ++ num(Maybe.default(&2, F64, expires, F.fromU32(0)))
    case Auth.AuthUrlEvent{url, _}: "auth_url " ++ url
    case Auth.ProgressEvent{message}: "progress " ++ message
    case _: "other"

def recordText(events: Log(), +text: String) -> IO(Unit):
  do IO<Unit>:
    IO.print("event " ++ text)
    Ref.modify(List<&2, String>, Unit, events, list => (List.append(&2, String, list, [text]), Unit{}))

def recordEvent(events: Log(), event: Auth.AuthEvent) -> IO(Unit): recordText(events, eventText(event))

def login(oauth: Auth.OAuthAuth, method: String, events: Log()) -> IO(Auth.LoginOutcome()):
  match oauth:
    case Auth.OAuthAuth{_, _, _, authenticate, _, _}:
      do IO<Auth.LoginOutcome()>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~String, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~answer, method)
        notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Log(), ~Auth.AuthEvent, ~Unit, ~recordEvent, events)
        result : Auth.LoginOutcome() <- C.call(Auth.ProviderAuthInteraction, Auth.LoginOutcome(), authenticate, Auth.ProviderAuthInteraction{Abort.signal(Unit, controller), prompt, notify})
        Abort.dispose(Unit, controller)
        return result

# The browser flow: tests/radius_check.py opens the callback URL it reads
# from the auth_url event.
def browserLogin(fetch: Fetch.Fetch(Unit), gateway: String) -> IO(Unit):
  do IO<Unit>:
    oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth("Radius", gateway, fetch, urlContext())
    events : Log() <- Ref.new(List<&2, String>, Nil{})
    result : Auth.LoginOutcome() <- login(oauth, "browser", events)
    IO.print("credential " ++ credentialText(result))
    pass("browser login exchanges the callback code")

def J() -> Data: Ai.JsonValue

def Model() -> Data: Ai.Model<J()>

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def check(+ok: Bool, +message: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "FAIL " ++ message))

# Redirecting fetch
# -----------------

type Redirect is Data:
  Redirect{inner: Fetch.Fetch(Unit), loopback: String, log: Log()}

def swapped(+url: String, +prefix: String, +loopback: String) -> String:
  Bool.pick(String, String.starts_with(url, prefix), loopback ++ String.drop(url, String.length(prefix)), url)

def target(+url: String, +loopback: String) -> String:
  swapped(swapped(url, "https://radius.pi.dev", loopback), "http://localhost:8788", loopback)

def headerText(value: Result<&2, &2, Headers.HeaderSyntaxError, Maybe<&2, String>>) -> String:
  match value:
    case Done{Some{text}}: text
    case _: "-"

def authorization(headers: Headers.Headers) -> String: headerText(Headers.get(headers, "authorization"))

def rewritten(parsed: Result<&2, &2, URL.Error, URL.URL>, input: Fetch.Input<Unit>) -> Maybe<&2, Fetch.Input<Unit>>:
  match parsed input:
    case Done{url} Fetch.Input{_, method, headers, body, signal}: Some{Fetch.Input{url, method, headers, body, signal}}
    case _ _: None{}

def forward(inner: Fetch.Fetch(Unit), input: Maybe<&2, Fetch.Input<Unit>>) -> IO(Fetch.Result_(Unit)):
  match input:
    case Some{value}: C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), inner, value)
    case None{}: IO.pure(Fetch.Result_(Unit), Fail{Fetch.InvalidRequest{Headers.BufferedRequestHeaderError{Headers.InvalidName{}}}})

def redirected(redirect: Redirect, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  match redirect input:
    case Redirect{inner, loopback, log} Fetch.Input{+url, +method, +headers, body, signal}:
      +original = URL.serialize(url, False{})
      do IO<Fetch.Result_(Unit)>:
        +line : String <- IO.pure(String, "request " ++ method ++ " " ++ original ++ " " ++ authorization(headers))
        IO.print(line)
        Ref.modify(List<&2, String>, Unit, log, list => (List.append(&2, String, list, [line]), Unit{}))
        forward(inner, rewritten(URL.parse(urlContext(), target(original, loopback)), Fetch.Input{url, method, headers, body, signal}))

def requests(log: Log()) -> IO(List<&2, String>): Ref.read(List<&2, String>, log)

# Models
# ------

def modelId(model: Model()) -> String: Ai.modelId(model)

def find(models: List<&2, Model()>, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Unit -> Maybe<&2, Model()>, String.eq(modelId(model), id), _ => Some{model}, _ => find(rest, id))(Unit{})

def modelJson(model: Maybe<&2, Model()>) -> String:
  match model:
    case Some{value}: Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(ModelJson.model(value))), "null")
    case None{}: "undefined"

def contains(+text: String, part: String) -> Bool: String.contains(text, part)

def providerModels(provider: AiModels.Provider) -> List<&2, Model()>:
  match provider:
    case AiModels.Provider{_, _, _, _, models, _, _}: models

def providerRefresh(provider: AiModels.Provider) -> Maybe<&2, AiModels.RefreshModels()>:
  match provider:
    case AiModels.Provider{_, _, _, _, _, _, refresher}: refresher

def providerName(provider: Maybe<&2, AiModels.Provider>) -> String:
  match provider:
    case Some{AiModels.Provider{_, name, _, _, _, _, _}}: name
    case None{}: "undefined"

# ai radius-provider.test.ts
# --------------------------

def defaultProvider(transport: Radius.RadiusTransport) -> IO(AiModels.Provider): Radius.radiusProvider(Radius.defaultOptions(), transport)

def staticCatalog(transport: Radius.RadiusTransport) -> IO(Unit):
  do IO<Unit>:
    +provider : AiModels.Provider <- defaultProvider(transport)
    +balanced : String <- IO.pure(String, modelJson(find(providerModels(provider), "balanced")))
    check(Bool.not(List.is_empty(&2, Model(), providerModels(provider))) && contains(balanced, "\"provider\":\"radius\"") && contains(balanced, "\"api\":\"pi-messages\""), balanced)
    pass("ships a static public catalog for the default gateway")

def customGateway(transport: Radius.RadiusTransport) -> IO(Unit):
  do IO<Unit>:
    provider : AiModels.Provider <- Radius.radiusProvider(Radius.RadiusProviderOptions{Some{"radius-dev"}, None{}, Some{"http://localhost:8788"}}, transport)
    check(List.is_empty(&2, Model(), providerModels(provider)), "custom gateway has a catalog")
    pass("does not apply the public Radius catalog to custom gateways")

# The publish callback records every publication's model list.
def record(published: Ref.Ref<List<&2, List<&2, Model()>>>, publication: AiModels.ModelsPublication) -> IO(Bool):
  match publication:
    case AiModels.ModelsPublication{_, Some{models}}:
      do IO<Bool>:
        Ref.modify(List<&2, List<&2, Model()>>, Unit, published, list => (List.append(&2, List<&2, Model()>, list, [models]), Unit{}))
        return True{}
    case AiModels.ModelsPublication{_, None{}}: IO.pure(Bool, True{})

def lastPublished(lists: List<&2, List<&2, Model()>>) -> List<&2, Model()>:
  match lists:
    case Nil{}: Nil{}
    case last <> Nil{}: last
    case _ <> rest: lastPublished(rest)

def refreshedWith(refresh: Maybe<&2, AiModels.RefreshModels()>, credential: Maybe<&2, Auth.Credential>, stored: Maybe<&2, Store.ModelsStoreEntry>, allowNetwork: Bool) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match refresh:
    case None{}: IO.pure(Result<&2, &2, String, List<&2, Model()>>, Fail{"no refresh"})
    case Some{refresher}:
      do IO<Result<&2, &2, String, List<&2, Model()>>>:
        +published : Ref.Ref<List<&2, List<&2, Model()>>> <- Ref.new(List<&2, List<&2, Model()>>, Nil{})
        publish : C.Callback<AiModels.ModelsPublication, Bool> <- C.create(~Ref.Ref<List<&2, List<&2, Model()>>>, ~AiModels.ModelsPublication, ~Bool, ~record, published)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Result<&2, &2, String, Unit> <- C.call(AiModels.RefreshModelsContext, Result<&2, &2, String, Unit>, refresher, AiModels.RefreshModelsContext{credential, stored, publish, allowNetwork, None{}, Abort.signal(Unit, controller)})
        Abort.dispose(Unit, controller)
        lists : List<&2, List<&2, Model()>> <- Ref.read(List<&2, List<&2, Model()>>, published)
        return Result.map(&2, &2, String, Unit, List<&2, Model()>, unused => lastPublished(lists), result)

def refreshed(provider: AiModels.Provider, credential: Maybe<&2, Auth.Credential>, stored: Maybe<&2, Store.ModelsStoreEntry>, allowNetwork: Bool) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  refreshedWith(providerRefresh(provider), credential, stored, allowNetwork)

def freshCatalog(models: Result<&2, &2, String, List<&2, Model()>>) -> IO(Unit):
  match models:
    case Fail{message}: check(False{}, message)
    case Done{+list}:
      +balanced = modelJson(find(list, "balanced"))
      check(contains(balanced, "\"name\":\"Fresh Balanced\"") && contains(balanced, "\"baseUrl\":\"https://radius.example/v1\"") && contains(balanced, "\"contextWindow\":424242") && Maybe.is_some(&2, Model(), find(list, "organization-only")) && Nat.is_gt(List.length(&2, Model(), list), 2n), balanced)

def overlayRefreshed(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    provider : AiModels.Provider <- defaultProvider(transport)
    models : Result<&2, &2, String, List<&2, Model()>> <- refreshed(provider, Some{Auth.ApiKeyCredential{Some{"radius-key"}, None{}}}, None{}, True{})
    freshCatalog(models)
    +sent : List<&2, String> <- requests(log)
    check(Nat.is_eq(List.length(&2, String, sent), 1n) && String.eq(String.join(sent, ""), "request GET https://radius.pi.dev/v1/config Bearer radius-key"), String.join(sent, ";"))
    pass("overlays refreshed models on the static public catalog")

def freshConfig() -> Config.RadiusGatewayConfig:
  Config.RadiusGatewayConfig{"https://radius.example/v1", [Config.RadiusGatewayModel{"balanced", "Fresh Balanced", True{}, None{}, [Ai.InputText{}], Ai.ModelCost{F.fromU32(1), F.fromU32(2), F.divide(F.fromU32(1), F.fromU32(10)), F.fromU32(0), None{}}, F.fromU32(424242), F.fromU32(32000)}, Config.RadiusGatewayModel{"organization-only", "Organization Only", False{}, None{}, [Ai.InputText{}], Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, F.fromU32(128000), F.fromU32(16000)}]}

def overlayCached(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    provider : AiModels.Provider <- defaultProvider(transport)
    models : Result<&2, &2, String, List<&2, Model()>> <- refreshed(provider, None{}, Some{Store.ModelsStoreEntry{Config.getRadiusModelsFromConfig("radius", freshConfig()), None{}, Some{now}, None{}}}, False{})
    freshCatalog(models)
    +sent : List<&2, String> <- requests(log)
    check(List.is_empty(&2, String, sent), String.join(sent, ";"))
    pass("overlays a cached effective catalog without network access")

# ai radius-oauth.test.ts
# -----------------------

def deviceLogin(fetch: Fetch.Fetch(Unit), +gateway: String, log: Log()) -> IO(Unit):
  do IO<Unit>:
    oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth("Radius", gateway, fetch, urlContext())
    +events : Log() <- Ref.new(List<&2, String>, Nil{})
    before : F64 <- Date.now()
    result : Auth.LoginOutcome() <- login(oauth, "device-code", events)
    after : F64 <- Date.now()
    +seen : List<&2, String> <- Ref.read(List<&2, String>, events)
    +sent : List<&2, String> <- requests(log)
    IO.print("credential " ++ credentialText(result))
    IO.print("expires-window " ++ num(F.subtract(F.add(before, F.fromU32(3540000)), F.fromU32(0))) ++ " " ++ num(F.add(after, F.fromU32(3540000))))
    check(String.eq(String.join(seen, ";"), "device_code ABCD-1234 https://radius-ui.example/pair 5 600"), String.join(seen, ";"))
    check(String.eq(String.join(sent, ";"), "request POST " ++ gateway ++ "/v1/oauth/device -;request POST " ++ gateway ++ "/v1/oauth/token -"), String.join(sent, ";"))
    pass("uses gateway endpoints directly for device login")

def refreshText(result: Result<&2, &2, String, Auth.Credential>) -> String: credentialText(result)

def refreshWith(oauth: Auth.OAuthAuth, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match oauth:
    case Auth.OAuthAuth{_, _, _, _, refresher, _}: C.call(Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>, refresher, input)

def refreshOnce(fetch: Fetch.Fetch(Unit), +gateway: String, log: Log()) -> IO(Unit):
  do IO<Unit>:
    oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth("Radius", gateway, fetch, urlContext())
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Result<&2, &2, String, Auth.Credential> <- refreshWith(oauth, Auth.RefreshInput{Auth.OAuthCredential{"old-refresh", "old-access", F.fromU32(0), R.new(V.Value)}, Abort.signal(Unit, controller)})
    Abort.dispose(Unit, controller)
    +text : String <- IO.pure(String, refreshText(result))
    +sent : List<&2, String> <- requests(log)
    check(String.starts_with(text, "new-access new-refresh "), text)
    check(String.eq(String.join(sent, ";"), "request POST " ++ gateway ++ "/v1/oauth/token -"), String.join(sent, ";"))
    pass("refreshes directly through the gateway without discovery")

def discovery(fetch: Fetch.Fetch(Unit), +gateway: String, log: Log()) -> IO(Unit):
  do IO<Unit>:
    oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth("Radius", gateway, fetch, urlContext())
    events : Log() <- Ref.new(List<&2, String>, Nil{})
    result : Auth.LoginOutcome() <- login(oauth, "browser", events)
    +text : String <- IO.pure(String, credentialText(result))
    +sent : List<&2, String> <- requests(log)
    check(String.eq(text, "error Invalid Radius OAuth config from " ++ gateway), text)
    check(String.eq(String.join(sent, ";"), "request GET " ++ gateway ++ "/v1/oauth -"), String.join(sent, ";"))
    pass("discovers only the interactive browser authorization endpoint")

# coding-agent radius.test.ts
# ---------------------------

def gatewayConfig(baseUrl: String) -> V.Value:
  V.ObjectValue{R.Record{[R.Property{"baseUrl", V.Text{baseUrl}}, R.Property{"models", V.ArrayValue{[V.ObjectValue{R.Record{[R.Property{"id", V.Text{"auto"}}, R.Property{"name", V.Text{"Radius Auto"}}, R.Property{"reasoning", V.Boolean{False{}}}, R.Property{"input", V.ArrayValue{[V.Text{"text"}]}}, R.Property{"cost", V.ObjectValue{R.Record{[R.Property{"input", V.Number{F.fromU32(1)}}, R.Property{"output", V.Number{F.fromU32(2)}}, R.Property{"cacheRead", V.Number{F.divide(F.fromU32(1), F.fromU32(10))}}, R.Property{"cacheWrite", V.Number{F.divide(F.fromU32(2), F.fromU32(10))}}]}}}, R.Property{"contextWindow", V.Number{F.fromU32(128000)}}, R.Property{"maxTokens", V.Number{F.fromU32(16384)}}]}}]}}]}}

def oauthCredential(now: F64, extra: R.Record<V.Value>) -> Auth.Credential: Auth.OAuthCredential{"refresh-token", "access-token", F.add(now, F.fromU32(3600000)), extra}

def legacyCredential(now: F64, baseUrl: String) -> Auth.Credential: oauthCredential(now, R.Record{[R.Property{"gatewayConfig", gatewayConfig(baseUrl)}]})

def unusedLogin(unused: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): IO.pure(Auth.LoginOutcome(), Fail{"unused"})

def unusedRefresh(unused: Unit, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>): IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"unused"})

def unusedToAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>): IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"unused"})

def fixtureOAuth(name: String) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~unusedLogin, Unit{})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Unit, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~unusedRefresh, Unit{})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~unusedToAuth, Unit{})
    return Auth.OAuthAuth{name, True{}, None{}, authenticate, refresher, deriver}

def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

# upstream ModelRuntime.create with in-memory credentials and models store,
# then its refresh with `allowModelNetwork`.
def runtimeWith(transport: Radius.RadiusTransport, credentials: List<&2, R.Property<Auth.Credential>>, modelsPath: Maybe<&2, String>, allowNetwork: Bool) -> IO(Models.ModelRuntime):
  do IO<Models.ModelRuntime>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(R.Record{credentials})
    store : Auth.CredentialStore <- storeOf(AuthStorage.borrow(owner))
    codex : Auth.OAuthAuth <- fixtureOAuth("ChatGPT Plus/Pro (Codex Subscription)")
    anthropic : Auth.OAuthAuth <- fixtureOAuth("Anthropic (Claude Pro/Max)")
    +runtime : Models.ModelRuntime <- Models.createWithModelsPath(store, codex, Some{anthropic}, transport, modelsPath)
    result : Models.ModelsRefreshResult <- Models.refresh(runtime, Models.ModelsRefreshOptions{Some{allowNetwork}, None{}, None{}, None{}})
    return runtime

def legacyCatalog(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    +runtime : Models.ModelRuntime <- runtimeWith(transport, [R.Property{"radius", legacyCredential(now, "https://radius.example.com/v1")}], None{}, False{})
    model : Maybe<&2, Model()> <- Models.getModel(runtime, "radius", "auto")
    +provider : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "radius")
    configured : Bool <- Models.hasConfiguredAuth(runtime, "radius")
    +text : String <- IO.pure(String, modelJson(model))
    check(contains(text, "\"api\":\"pi-messages\"") && contains(text, "\"baseUrl\":\"https://radius.example.com/v1\""), text)
    check(String.eq(providerName(provider), "Radius") && configured, providerName(provider))
    pass("restores the legacy credential catalog without network access")

# A line equal to `text` (exact) or containing it.
def anyLine(lines: List<&2, String>, +text: String, +exact: Bool) -> Bool:
  match lines:
    case Nil{}: False{}
    case +line <> rest: Bool.pick(Bool, exact, String.eq(line, text), String.contains(line, text)) || anyLine(rest, text, exact)

def storedCount(stored: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)) -> Bool:
  match stored:
    case Done{Some{Store.ModelsStoreEntry{models, _, _, _}}}: Nat.is_eq(List.length(&2, Model(), models), 1n)
    case _: False{}

def storedCatalog(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    +runtime : Models.ModelRuntime <- runtimeWith(transport, [R.Property{"radius", oauthCredential(now, R.new(V.Value))}], None{}, True{})
    model : Maybe<&2, Model()> <- Models.getModel(runtime, "radius", "auto")
    stored : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(Models.storeOf(runtime), "radius", None{})
    +sent : List<&2, String> <- requests(log)
    check(Maybe.is_some(&2, Model(), model), "auto is missing")
    check(storedCount(stored), "stored catalog is not one model")
    check(anyLine(sent, "request GET https://radius.pi.dev/v1/config Bearer access-token", True{}), String.join(sent, ";"))
    pass("fetches and stores the catalog for configured Radius auth")

def offlineDefault(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    +runtime : Models.ModelRuntime <- runtimeWith(transport, [R.Property{"radius", legacyCredential(now, "https://radius.example.com/v1")}], None{}, False{})
    model : Maybe<&2, Model()> <- Models.getModel(runtime, "radius", "auto")
    +sent : List<&2, String> <- requests(log)
    check(Maybe.is_some(&2, Model(), model), "auto is missing")
    check(List.is_empty(&2, String, sent), String.join(sent, ";"))
    pass("does not refresh catalogs over the network by default")

def radiusModels(models: List<&2, Model()>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = radiusModels(rest)
      Bool.pick(List<&2, Model()>, String.eq(Ai.modelProvider(model), "radius"), model <> tail, tail)

def unconfigured(transport: Radius.RadiusTransport, log: Log()) -> IO(Unit):
  do IO<Unit>:
    +runtime : Models.ModelRuntime <- runtimeWith(transport, Nil{}, None{}, True{})
    available : List<&2, Model()> <- Models.getAvailable(runtime)
    +sent : List<&2, String> <- requests(log)
    check(List.is_empty(&2, Model(), radiusModels(available)), "radius models are available")
    check(Bool.not(anyLine(sent, "radius.pi.dev/v1/config", False{})), String.join(sent, ";"))
    pass("does not fetch or make Radius models available without configured auth")

def customGatewayRuntime(transport: Radius.RadiusTransport, log: Log(), path: String) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    +runtime : Models.ModelRuntime <- runtimeWith(transport, [R.Property{"radius-dev", oauthCredential(now, R.new(V.Value))}], Some{path}, True{})
    model : Maybe<&2, Model()> <- Models.getModel(runtime, "radius-dev", "auto")
    +provider : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "radius-dev")
    +text : String <- IO.pure(String, modelJson(model))
    check(contains(text, "\"api\":\"pi-messages\"") && contains(text, "\"baseUrl\":\"http://localhost:8788/v1\""), text)
    check(String.eq(providerName(provider), "Radius (dev)"), providerName(provider))
    pass("supports custom Radius gateways from models.json")

def errorText(error: Maybe<&2, String>) -> String:
  match error:
    case Some{text}: text
    case None{}: "undefined"

def requiresBaseUrl(transport: Radius.RadiusTransport, path: String) -> IO(Unit):
  do IO<Unit>:
    +runtime : Models.ModelRuntime <- runtimeWith(transport, Nil{}, Some{path}, False{})
    +error : String <- IO.pure(String, errorText(Models.getError(runtime)))
    check(String.contains(error, "\"baseUrl\" is required when \"oauth\" is set"), error)
    pass("requires baseUrl for custom Radius gateways")

# Running
# -------

def selectedWith(+mode: String, transport: Radius.RadiusTransport, fetch: Fetch.Fetch(Unit), loopback: String, log: Log(), path: String) -> IO(Unit):
  match mode:
    case "static": staticCatalog(transport)
    case "custom": customGateway(transport)
    case "overlay": overlayRefreshed(transport, log)
    case "cached": overlayCached(transport, log)
    case "device": deviceLogin(fetch, loopback, log)
    case "refresh": refreshOnce(fetch, loopback, log)
    case "discovery": discovery(fetch, loopback, log)
    case "browser": browserLogin(fetch, loopback)
    case "legacy": legacyCatalog(transport, log)
    case "stored": storedCatalog(transport, log)
    case "offline": offlineDefault(transport, log)
    case "unconfigured": unconfigured(transport, log)
    case "custom-gateway": customGatewayRuntime(transport, log, path)
    case "requires-base-url": requiresBaseUrl(transport, path)
    case _: IO.die(Unit, 2, "unknown case")

def selected(+mode: String, +fetch: Fetch.Fetch(Unit), loopback: String, log: Log(), path: String) -> IO(Unit):
  selectedWith(mode, Radius.RadiusTransport{fetch, urlContext()}, fetch, loopback, log, path)

def borrowed(mode: String, +loopback: String, path: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +inner):
      do IO<Unit>:
        +log : Log() <- Ref.new(List<&2, String>, Nil{})
        fetch : Fetch.Fetch(Unit) <- C.create(~Redirect, ~(Fetch.Input<Unit>), ~(Fetch.Result_(Unit)), ~redirected, Redirect{inner, loopback, log})
        selected(mode, fetch, loopback, log, path)
        Fetch.retire(Unit, inner)
        Fetch.dispose(owned)

def initialized(mode: String, loopback: String, path: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(mode, loopback, path, pair)

def run(mode: String, loopback: String, path: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(mode, loopback, path, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> loopback <> path <> Nil{}: run(mode, loopback, path)
    case mode <> loopback <> Nil{}: run(mode, loopback, "")
    case _: IO.die(Unit, 2, "usage: radius <case> <loopback> [models.json]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
