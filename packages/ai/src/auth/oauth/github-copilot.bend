import Base
import ./device-code.bend as Device
import ./oauth-http.bend as H
import ../types.bend as Auth
import ../../types.bend as T
import ../../api/credential-http.bend as Http
import ../../providers/github-copilot.models.bend as Catalog
import ../../utils/provider-retry.bend as Retry
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/parse-float.bend as Number
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/text.bend as Strings
import ../../../../runtime/src/timer.bend as Timer
import ../../../../runtime/src/url.bend as URL

# pi-mono auth/oauth/github-copilot.ts: the GitHub Copilot OAuth device flow,
# Copilot token exchange, the account's model catalog and model policy updates.

def CLIENT_ID() -> String: "Iv1.b507a08c87ecfe98"

def COPILOT_HEADERS() -> List<&2, R.Property<String>>:
  [R.Property{"User-Agent", "GitHubCopilotChat/0.35.0"}, R.Property{"Editor-Version", "vscode/1.107.0"}, R.Property{"Editor-Plugin-Version", "copilot-chat/0.35.0"}, R.Property{"Copilot-Integration-Id", "vscode-chat"}]

def COPILOT_API_VERSION() -> String: "2026-06-01"
def INDIVIDUAL_BASE_URL() -> String: "https://api.individual.githubcopilot.com"
def REQUEST_TIMEOUT_MS() -> U32: 5000

def Json() -> Data: Maybe<&2, V.Value>

type DeviceCodeResponse is Data:
  DeviceCodeResponse{deviceCode: String, userCode: String, verificationUri: String, interval: Maybe<&2, F64>, expiresIn: F64}

type RetryPolicy is Data:
  RetryPolicy{maxRetries: Nat, maxElapsedMs: U32}

# Domains and URLs
# ----------------
def hostnameOf(parsed: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, String>:
  match parsed:
    case Done{url}: Some{URL.hostname(url)}
    case Fail{_}: None{}

# The hostname of a GitHub Enterprise URL or domain; None when blank or invalid.
def normalizedTrimmed(context: URL.Context, trimmed: String) -> Maybe<&2, String>:
  match trimmed:
    case SNil{}: None{}
    case +text: hostnameOf(URL.parse(context, Bool.pick(String, String.contains(text, "://"), text, "https://" ++ text)))

def normalizeDomain(context: URL.Context, input: String) -> Maybe<&2, String>: normalizedTrimmed(context, Strings.trim(input))

def deviceCodeUrl(+domain: String) -> String: "https://" ++ domain ++ "/login/device/code"
def accessTokenUrl(+domain: String) -> String: "https://" ++ domain ++ "/login/oauth/access_token"
def copilotTokenUrl(+domain: String) -> String: "https://api." ++ domain ++ "/copilot_internal/v2/token"

# The first `proxy-ep=` value of a Copilot token (up to `;`).
def proxyValue(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{';', _}: String.reverse(reversed)
    case SCon{c, rest}: proxyValue(rest, SCon{c, reversed})

def proxyEndpoint(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{'p', SCon{'r', SCon{'o', SCon{'x', SCon{'y', SCon{'-', SCon{'e', SCon{'p', SCon{'=', SCon{+c, +rest}}}}}}}}}}: Bool.pick(Maybe<&2, String>, String.eq(SCon{c, SNil{}}, ";"), proxyEndpoint(SCon{c, rest}), Some{proxyValue(SCon{c, rest}, "")})
    case SCon{_, rest}: proxyEndpoint(rest)

def apiHost(host: String) -> String:
  match host:
    case SCon{'p', SCon{'r', SCon{'o', SCon{'x', SCon{'y', SCon{'.', rest}}}}}}: "api." ++ rest
    case other: other

# proxy-ep=proxy.xxx → https://api.xxx
def getBaseUrlFromToken(token: String) -> Maybe<&2, String>:
  Maybe.map(&2, String, String, host => "https://" ++ apiHost(host), proxyEndpoint(token))

def baseUrlWith(fromToken: Maybe<&2, String>, enterpriseDomain: Maybe<&2, String>) -> String:
  match fromToken enterpriseDomain:
    case Some{url} _: url
    case None{} Some{domain}: "https://copilot-api." ++ domain
    case None{} None{}: INDIVIDUAL_BASE_URL()

def tokenBaseUrl(token: Maybe<&2, String>) -> Maybe<&2, String>:
  match token:
    case Some{text}: getBaseUrlFromToken(text)
    case None{}: None{}

def getGitHubCopilotBaseUrl(token: Maybe<&2, String>, enterpriseDomain: Maybe<&2, String>) -> String:
  baseUrlWith(tokenBaseUrl(token), enterpriseDomain)

# Messages
# --------
def reasonPhrase(+status: U32) -> String:
  match status:
    case 200: "OK"
    case 201: "Created"
    case 204: "No Content"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 409: "Conflict"
    case 422: "Unprocessable Entity"
    case 429: "Too Many Requests"
    case 500: "Internal Server Error"
    case 502: "Bad Gateway"
    case 503: "Service Unavailable"
    case 504: "Gateway Timeout"
    case _: ""

# `${response.status} ${response.statusText}: ${await response.text()}`
def statusMessage(+reply: H.Reply) -> String:
  U32.show(H.replyStatus(reply)) ++ " " ++ reasonPhrase(H.replyStatus(reply)) ++ ": " ++ H.replyText(reply)

# fetchJson: the parsed body, or the status message.
def jsonOutcome(result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, Json()>:
  match result:
    case Fail{failure}: Fail{H.failureText(failure)}
    case Done{+reply}: Bool.pick(Result<&2, &2, String, Json()>, H.ok(reply), Done{H.replyJson(reply)}, Fail{statusMessage(reply)})

def FORM_HEADERS() -> List<&2, R.Property<String>>: [R.Property{"Accept", "application/json"}, R.Property{"Content-Type", "application/x-www-form-urlencoded"}, R.Property{"User-Agent", "GitHubCopilotChat/0.35.0"}]

def fetchForm(flow: H.Flow, +signal: Abort.AbortSignal<Unit>, url: String, fields: List<&2, R.Property<String>>) -> IO(Result<&2, &2, String, Json()>):
  do IO<Result<&2, &2, String, Json()>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, "POST", url, FORM_HEADERS(), H.form(fields), Http.NO_TIMEOUT())
    return jsonOutcome(result)

# Rate-limited requests
# ---------------------
# fetchWithRateLimitRetry: each request is bounded by 5 s; a 429 is retried
# after Retry-After (seconds, or an HTTP date) or 500·2^n ms, within
# `maxElapsedMs` from the first request, and returned as is once retries or
# the budget are exhausted or the delay is unusable.
type Rate is Data:
  Rate{flow: H.Flow, signal: Abort.AbortSignal<Unit>, method: String, url: String, headers: List<&2, R.Property<String>>, body: String, policy: RetryPolicy, deadline: Maybe<&2, F64>}

def rateDelay(+retry: Nat, retryAfter: Maybe<&2, String>) -> IO(F64):
  match retryAfter:
    case None{}: IO.pure(F64, F.fromU32((500 * U32.shln(1, retry) : U32)))
    case Some{+text}:
      +seconds = Number.parseFloat(text)
      Bool.pick(Unit -> IO(F64), F.isNaN(seconds),
        _ => do IO<F64>:
          epoch : F64 <- Retry.dateBody(Unit{}, text)
          now : F64 <- Date.now()
          return F.subtract(epoch, now),
        _ => IO.pure(F64, F.multiply(seconds, F.fromU32(1000))))(Unit{})

def finiteValue(+value: F64) -> Bool: Bool.not(F.isNaN(value)) && F.isGreater(F.compare(F.infinity(False{}), value)) && F.isGreater(F.compare(value, F.infinity(True{})))

def withinBudget(deadline: Maybe<&2, F64>, +delay: F64, now: F64) -> Bool:
  match deadline:
    case None{}: True{}
    case Some{end}: F.isGreater(F.compare(F.subtract(end, now), delay))

type RateStep is Data:
  Return{result: Result<&2, &2, Http.Failure, H.Reply>}
  Again{delay: F64}

def lastRetry(+retry: Nat, policy: RetryPolicy) -> Bool:
  match policy:
    case RetryPolicy{maxRetries, _}: Nat.is_eq(retry, maxRetries)

def afterAttempt(+retry: Nat, policy: RetryPolicy, deadline: Maybe<&2, F64>, result: Result<&2, &2, Http.Failure, H.Reply>) -> IO(RateStep):
  match result:
    case Fail{failure}: IO.pure(RateStep, Return{Fail{failure}})
    case Done{+reply}:
      Bool.pick(Unit -> IO(RateStep), Bool.not(U32.is_eq(H.replyStatus(reply), 429)) || lastRetry(retry, policy),
        _ => IO.pure(RateStep, Return{Done{reply}}),
        _ => do IO<RateStep>:
          +raw : F64 <- rateDelay(retry, H.replyHeader(reply, "retry-after"))
          now : F64 <- Date.now()
          +delay : F64 <- IO.pure(F64, F.maximum(F.fromU32(0), raw))
          return Bool.pick(RateStep, finiteValue(raw) && withinBudget(deadline, delay, now), Again{delay}, Return{Done{reply}}))(Unit{})

def sleptOk(result: Result<&2, &2, Abort.AbortReason<Unit>, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

type RatePhase is Data:
  Send{}
  Decided{step: RateStep}

def afterSleep(slept: Result<&2, &2, Abort.AbortReason<Unit>, Unit>) -> RatePhase:
  Bool.pick(RatePhase, sleptOk(slept), Send{}, Decided{Return{Fail{Http.Aborted{}}}})

def retryAfterSleep(slept: Result<&2, &2, Abort.AbortReason<Unit>, Unit>, +retry: Nat) -> Nat: Bool.pick(Nat, sleptOk(slept), 1n + retry, retry)

@unsafe def rateLoop(state: Rate, +retry: Nat, phase: RatePhase) -> IO(Result<&2, &2, Http.Failure, H.Reply>):
  match phase state:
    case Decided{Return{result}} _: IO.pure(Result<&2, &2, Http.Failure, H.Reply>, result)
    case Decided{Again{delay}} Rate{+flow, +signal, +method, +url, +headers, +body, policy, +deadline}:
      do IO<Result<&2, &2, Http.Failure, H.Reply>>:
        +slept : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, F64.to_u32(F64.floor(delay)), signal)
        rateLoop(Rate{flow, signal, method, url, headers, body, policy, deadline}, retryAfterSleep(slept, retry), afterSleep(slept))
    case Send{} Rate{+flow, +signal, +method, +url, +headers, +body, +policy, +deadline}:
      do IO<Result<&2, &2, Http.Failure, H.Reply>>:
        result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, method, url, headers, Bool.pick(Headers.Input, String.eq(body, ""), Headers.Absent{}, Headers.Text{body}), REQUEST_TIMEOUT_MS())
        step : RateStep <- afterAttempt(retry, policy, deadline, result)
        rateLoop(Rate{flow, signal, method, url, headers, body, policy, deadline}, retry, Decided{step})

def budgetDeadline(policy: RetryPolicy, +now: F64) -> Maybe<&2, F64>:
  match policy:
    case RetryPolicy{retries, +elapsed}: Bool.pick(Maybe<&2, F64>, Nat.is_gt(retries, 0n) && U32.is_gt(elapsed, 0), Some{F.add(now, F.fromU32(elapsed))}, None{})

def fetchWithRateLimitRetry(flow: H.Flow, +signal: Abort.AbortSignal<Unit>, method: String, url: String, headers: List<&2, R.Property<String>>, body: String, +policy: RetryPolicy) -> IO(Result<&2, &2, Http.Failure, H.Reply>):
  do IO<Result<&2, &2, Http.Failure, H.Reply>>:
    now : F64 <- Date.now()
    rateLoop(Rate{flow, signal, method, url, headers, body, policy, budgetDeadline(policy, now)}, 0n, Send{})

# Model catalog
# -------------
type AccountModel is Data:
  AccountModel{id: String, pickerEnabled: Bool, policyState: Maybe<&2, String>}

type Catalog is Data:
  Catalog{availableModelIds: List<&2, String>, policyModelIds: List<&2, String>}

def isFalse(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{False{}}}: True{}
    case _: False{}

def nested(json: Json(), name: String) -> Json(): Some{V.ObjectValue{H.objectFields(H.field(json, name))}}

def toolCallsDisabled(item: Json()) -> Bool: isFalse(H.field(nested(nested(item, "capabilities"), "supports"), "tool_calls"))

def pickerEnabled(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{True{}}}: True{}
    case _: False{}

def accountWith(id: Maybe<&2, String>, object: Bool, +item: Json()) -> Maybe<&2, AccountModel>:
  match id object:
    case Some{name} True{}: Bool.pick(Maybe<&2, AccountModel>, toolCallsDisabled(item), None{}, Some{AccountModel{name, pickerEnabled(H.field(item, "model_picker_enabled")), H.stringField(nested(item, "policy"), "state")}})
    case _ _: None{}

def accountModel(+item: V.Value) -> Maybe<&2, AccountModel>: accountWith(H.stringField(Some{item}, "id"), H.isObject(Some{item}), Some{item})

def prependAccount(model: Maybe<&2, AccountModel>, rest: List<&2, AccountModel>) -> List<&2, AccountModel>:
  match model:
    case Some{found}: found <> rest
    case None{}: rest

def accountModels(items: List<&2, V.Value>) -> List<&2, AccountModel>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: prependAccount(accountModel(item), accountModels(rest))

def stateIs(state: Maybe<&2, String>, +expected: String) -> Bool: Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, value => String.eq(value, expected), state), False{})

def keepIf(keep: Bool, id: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}: id <> rest
    case False{}: rest

def pickerIds(models: List<&2, AccountModel>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case AccountModel{id, picker, state} <> rest: keepIf(picker && Bool.not(stateIs(state, "disabled")), id, pickerIds(rest))

def enabledIds(models: List<&2, AccountModel>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case AccountModel{id, _, state} <> rest: keepIf(stateIs(state, "enabled"), id, enabledIds(rest))

def knownModel(models: List<&2, T.Model<T.JsonValue>>, +id: String) -> Bool:
  match models:
    case Nil{}: False{}
    case model <> rest: String.eq(T.modelId(model), id) || knownModel(rest, id)

def policyIds(models: List<&2, AccountModel>, +fallback: Bool) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case AccountModel{+id, picker, state} <> rest: keepIf(stateIs(state, "unconfigured") && knownModel(Catalog.GITHUB_COPILOT_MODELS(), id) && (picker || fallback), id, policyIds(rest, fallback))

def catalogOf(+models: List<&2, AccountModel>, +allowPolicyFallback: Bool) -> Catalog:
  +picker = pickerIds(models)
  +fallback = allowPolicyFallback && List.is_empty(&2, String, picker)
  Catalog{Bool.pick(List<&2, String>, List.is_empty(&2, String, picker) && allowPolicyFallback, enabledIds(models), picker), policyIds(models, fallback)}

def catalogData(data: Maybe<&2, V.Value>, allowPolicyFallback: Bool) -> Result<&2, &2, String, Catalog>:
  match data:
    case Some{V.ArrayValue{items}}: Done{catalogOf(accountModels(items), allowPolicyFallback)}
    case _: Fail{"Invalid Copilot models response"}

def parseGitHubCopilotModelCatalog(raw: Json(), allowPolicyFallback: Bool) -> Result<&2, &2, String, Catalog>: catalogData(H.field(raw, "data"), allowPolicyFallback)

def modelsOutcome(allowPolicyFallback: Bool, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, Catalog>:
  Result.bind(&2, &2, String, Json(), Catalog, jsonOutcome(result), json => parseGitHubCopilotModelCatalog(json, allowPolicyFallback))

def fetchGitHubCopilotModels(flow: H.Flow, +token: String, enterpriseDomain: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, policy: RetryPolicy) -> IO(Result<&2, &2, String, Catalog>):
  +baseUrl = getGitHubCopilotBaseUrl(Some{token}, enterpriseDomain)
  do IO<Result<&2, &2, String, Catalog>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- fetchWithRateLimitRetry(flow, signal, "GET", baseUrl ++ "/models", R.Property{"Accept", "application/json"} <> R.Property{"Authorization", "Bearer " ++ token} <> List.append(&2, R.Property<String>, COPILOT_HEADERS(), R.Property{"X-GitHub-Api-Version", COPILOT_API_VERSION()} <> Nil{}), "", policy)
    return modelsOutcome(String.eq(baseUrl, INDIVIDUAL_BASE_URL()), result)

# Device flow
# -----------
def UNTRUSTED() -> String: "Untrusted verification_uri in device code response"

def deviceFields(context: URL.Context, device: Maybe<&2, String>, user: Maybe<&2, String>, uri: Maybe<&2, String>, valid: Bool, interval: Maybe<&2, F64>, expires: Maybe<&2, F64>) -> Result<&2, &2, String, DeviceCodeResponse>:
  match device user uri valid expires:
    case Some{code} Some{userCode} Some{raw} True{} Some{expiresIn}: Result.map(&2, &2, String, String, DeviceCodeResponse, href => DeviceCodeResponse{code, userCode, href, interval, expiresIn}, H.orFail(String, H.trustedUrl(context, Some{raw}, False{}), UNTRUSTED()))
    case _ _ _ _ _: Fail{"Invalid device code response fields"}

def intervalValid(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{V.Number{_}}: True{}
    case Some{_}: False{}

def deviceWith(context: URL.Context, device: Maybe<&2, String>, user: Maybe<&2, String>, uri: Maybe<&2, String>, +interval: Maybe<&2, V.Value>, expires: Maybe<&2, V.Value>) -> Result<&2, &2, String, DeviceCodeResponse>:
  deviceFields(context, device, user, uri, intervalValid(interval), H.numberOf(interval), H.numberOf(expires))

def deviceFrom(context: URL.Context, +json: Json()) -> Result<&2, &2, String, DeviceCodeResponse>:
  Bool.pick(Result<&2, &2, String, DeviceCodeResponse>, H.isObject(json), deviceWith(context, H.stringField(json, "device_code"), H.stringField(json, "user_code"), H.stringField(json, "verification_uri"), H.field(json, "interval"), H.field(json, "expires_in")), Fail{"Invalid device code response"})

def startDeviceFlow(+flow: H.Flow, +domain: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, DeviceCodeResponse>):
  do IO<Result<&2, &2, String, DeviceCodeResponse>>:
    data : Result<&2, &2, String, Json()> <- fetchForm(flow, signal, deviceCodeUrl(domain), [R.Property{"client_id", CLIENT_ID()}, R.Property{"scope", "read:user"}])
    return Result.bind(&2, &2, String, Json(), DeviceCodeResponse, data, json => deviceFrom(H.flowContext(flow), json))

type Poll is Data:
  Poll{flow: H.Flow, domain: String, deviceCode: String, signal: Abort.AbortSignal<Unit>}

def PollResult() -> Data: Device.OAuthDeviceCodePollResult<String>

def suffixed(description: Maybe<&2, String>) -> String:
  match description:
    case Some{SCon{c, cs}}: ": " ++ SCon{c, cs}
    case _: ""

def tokenError(error: Maybe<&2, String>, json: Json()) -> PollResult():
  match error:
    case Some{"authorization_pending"}: Device.PollPending{}
    case Some{"slow_down"}: Device.PollSlowDown{H.numberField(json, "interval")}
    case Some{other}: Device.PollFailed{"Device flow failed: " ++ other ++ suffixed(H.stringField(json, "error_description"))}
    case None{}: Device.PollFailed{"Invalid device token response"}

def tokenWith(token: Maybe<&2, String>, +json: Json()) -> PollResult():
  match token:
    case Some{value}: Device.PollComplete{value}
    case None{}: tokenError(H.stringField(json, "error"), json)

def tokenPolled(+json: Json()) -> PollResult(): tokenWith(H.stringField(json, "access_token"), json)

def polled(result: Result<&2, &2, String, Json()>) -> PollResult():
  match result:
    case Fail{message}: Device.PollFailed{message}
    case Done{json}: tokenPolled(json)

def poll(state: Poll, unused: Unit) -> IO(PollResult()):
  match state:
    case Poll{flow, domain, deviceCode, signal}:
      do IO<PollResult()>:
        result : Result<&2, &2, String, Json()> <- fetchForm(flow, signal, accessTokenUrl(domain), [R.Property{"client_id", CLIENT_ID()}, R.Property{"device_code", deviceCode}, R.Property{"grant_type", "urn:ietf:params:oauth:grant-type:device_code"}])
        return polled(result)

def pollForGitHubAccessToken(flow: H.Flow, +domain: String, device: DeviceCodeResponse, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, String>):
  match device:
    case DeviceCodeResponse{deviceCode, _, _, interval, expires}:
      do IO<Result<&2, &2, String, String>>:
        poller : C.Callback<Unit, PollResult()> <- C.create(~Poll, ~Unit, ~PollResult(), ~poll, Poll{flow, domain, deviceCode, signal})
        Device.pollOAuthDeviceCodeFlow(~String, Device.OAuthDeviceCodePollOptions{interval, Some{expires}, True{}, poller, signal})

# Copilot token
# -------------
type Credentials is Data:
  Credentials{refresh: String, access: String, expires: F64, enterpriseUrl: Maybe<&2, String>}

def tokenFields(+refresh: String, enterprise: Maybe<&2, String>, token: Maybe<&2, String>, expiresAt: Maybe<&2, F64>) -> Result<&2, &2, String, Credentials>:
  match token expiresAt:
    case Some{access} Some{at}: Done{Credentials{refresh, access, F.subtract(F.multiply(at, F.fromU32(1000)), F.fromU32(300000)), enterprise}}
    case _ _: Fail{"Invalid Copilot token response fields"}

def tokenFrom(+refresh: String, enterprise: Maybe<&2, String>, +json: Json()) -> Result<&2, &2, String, Credentials>:
  Bool.pick(Result<&2, &2, String, Credentials>, H.isObject(json), tokenFields(refresh, enterprise, H.stringField(json, "token"), H.numberField(json, "expires_at")), Fail{"Invalid Copilot token response"})

def refreshGitHubCopilotAccessToken(flow: H.Flow, +refreshToken: String, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Credentials>):
  do IO<Result<&2, &2, String, Credentials>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, "GET", copilotTokenUrl(Maybe.default(&2, String, enterprise, "github.com")), R.Property{"Accept", "application/json"} <> R.Property{"Authorization", "Bearer " ++ refreshToken} <> COPILOT_HEADERS(), Headers.Absent{}, Http.NO_TIMEOUT())
    return Result.bind(&2, &2, String, Json(), Credentials, jsonOutcome(result), json => tokenFrom(refreshToken, enterprise, json))

def textValues(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> textValues(rest)

def enterpriseField(enterprise: Maybe<&2, String>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match enterprise:
    case Some{domain}: R.Property{"enterpriseUrl", V.Text{domain}} <> rest
    case None{}: rest

def credentialOf(credentials: Credentials, available: List<&2, String>) -> Auth.Credential:
  match credentials:
    case Credentials{refresh, access, expires, enterprise}: Auth.OAuthCredential{refresh, access, expires, R.Record{enterpriseField(enterprise, R.Property{"availableModelIds", V.ArrayValue{textValues(available)}} <> Nil{})}}

def accessOf(credentials: Credentials) -> String:
  match credentials:
    case Credentials{_, access, _, _}: access

def refreshedWith(credentials: Credentials, catalog: Result<&2, &2, String, Catalog>) -> Result<&2, &2, String, Auth.Credential>:
  match catalog:
    case Fail{message}: Fail{message}
    case Done{Catalog{available, _}}: Done{credentialOf(credentials, available)}

def withToken(flow: H.Flow, enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, token: Result<&2, &2, String, Credentials>) -> IO(Result<&2, &2, String, Auth.Credential>):
  match token:
    case Fail{message}: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{message})
    case Done{+credentials}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        catalog : Result<&2, &2, String, Catalog> <- fetchGitHubCopilotModels(flow, accessOf(credentials), enterprise, signal, RetryPolicy{0n, 0})
        return refreshedWith(credentials, catalog)

def refreshGitHubCopilotToken(+flow: H.Flow, +refreshToken: String, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  do IO<Result<&2, &2, String, Auth.Credential>>:
    token : Result<&2, &2, String, Credentials> <- refreshGitHubCopilotAccessToken(flow, refreshToken, enterprise, signal)
    withToken(flow, enterprise, signal, token)

# Model policies
# --------------
type PolicyOutcome is Data:
  Enabled{}
  NotEnabled{}
  Stop{}

def policyOutcome(aborted: Bool, result: Result<&2, &2, Http.Failure, H.Reply>) -> PolicyOutcome:
  match result:
    case Fail{_}: Bool.pick(PolicyOutcome, aborted, Stop{}, NotEnabled{})
    case Done{+reply}: Bool.pick(PolicyOutcome, U32.is_eq(H.replyStatus(reply), 429) || aborted, Stop{}, Bool.pick(PolicyOutcome, H.ok(reply), Enabled{}, NotEnabled{}))

def enableGitHubCopilotModel(flow: H.Flow, +token: String, +modelId: String, enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>) -> IO(PolicyOutcome):
  do IO<PolicyOutcome>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- fetchWithRateLimitRetry(flow, signal, "POST", getGitHubCopilotBaseUrl(Some{token}, enterprise) ++ "/models/" ++ modelId ++ "/policy", R.Property{"Content-Type", "application/json"} <> R.Property{"Authorization", "Bearer " ++ token} <> List.append(&2, R.Property<String>, COPILOT_HEADERS(), R.Property{"openai-intent", "chat-policy"} <> R.Property{"x-interaction-type", "chat-policy"} <> Nil{}), "{\"state\":\"enabled\"}", RetryPolicy{2n, 5000})
    aborted : Bool <- Abort.aborted(Unit, signal)
    return policyOutcome(aborted, result)

# Best effort: failures skip a model; exhausted rate limiting stops the batch.
# Best effort: failures skip a model; exhausted rate limiting stops the batch.
def withOutcome(+id: String, enabled: List<&2, String>, outcome: PolicyOutcome) -> List<&2, String>:
  match outcome:
    case Enabled{}: id <> enabled
    case _: enabled

def isStop(outcome: PolicyOutcome) -> Bool:
  match outcome:
    case Stop{}: True{}
    case _: False{}

@unsafe def enableGitHubCopilotModels(+flow: H.Flow, +token: String, modelIds: List<&2, String>, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, enabled: List<&2, String>) -> IO(List<&2, String>):
  match modelIds:
    case Nil{}: IO.pure(List<&2, String>, List.reverse(&2, String, enabled))
    case +id <> rest:
      do IO<List<&2, String>>:
        +outcome : PolicyOutcome <- enableGitHubCopilotModel(flow, token, id, enterprise, signal)
        +updated : List<&2, String> <- IO.pure(List<&2, String>, withOutcome(id, enabled, outcome))
        Bool.pick(Unit -> IO(List<&2, String>), isStop(outcome), _ => IO.pure(List<&2, String>, List.reverse(&2, String, updated)), _ => enableGitHubCopilotModels(flow, token, rest, enterprise, signal, updated))(Unit{})

def contains(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case first <> rest: String.eq(first, value) || contains(rest, value)

def unique(values: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, seen)
    case +value <> rest: unique(rest, Bool.pick(List<&2, String>, contains(seen, value), seen, value <> seen))

# Login
# -----
def loginCancelled() -> String: "Login cancelled"

def withCatalog(flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, +credentials: Credentials, catalog: Result<&2, &2, String, Catalog>) -> IO(Auth.LoginOutcome()):
  match catalog:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{Catalog{available, Nil{}}}: IO.pure(Auth.LoginOutcome(), Done{credentialOf(credentials, unique(available, Nil{}))})
    case Done{Catalog{available, policies}}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.ProgressEvent{"Enabling models..."})
        enabled : List<&2, String> <- enableGitHubCopilotModels(flow, accessOf(credentials), policies, enterprise, signal, Nil{})
        return Done{credentialOf(credentials, unique(List.append(&2, String, available, enabled), Nil{}))}

def withCopilotToken(+flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, token: Result<&2, &2, String, Credentials>) -> IO(Auth.LoginOutcome()):
  match token:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{+credentials}:
      do IO<Auth.LoginOutcome()>:
        catalog : Result<&2, &2, String, Catalog> <- fetchGitHubCopilotModels(flow, accessOf(credentials), enterprise, signal, RetryPolicy{2n, 5000})
        withCatalog(flow, notify, enterprise, signal, credentials, catalog)

def withAccessToken(+flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, access: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match access:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{githubToken}:
      do IO<Auth.LoginOutcome()>:
        token : Result<&2, &2, String, Credentials> <- refreshGitHubCopilotAccessToken(flow, githubToken, enterprise, signal)
        withCopilotToken(flow, notify, enterprise, signal, token)

def withDevice(+flow: H.Flow, +notify: C.Callback<Auth.AuthEvent, Unit>, +domain: String, +enterprise: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>, device: Result<&2, &2, String, DeviceCodeResponse>) -> IO(Auth.LoginOutcome()):
  match device:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{DeviceCodeResponse{code, +user, +uri, +interval, +expires}}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.DeviceCodeEvent{user, uri, interval, Some{expires}})
        access : Result<&2, &2, String, String> <- pollForGitHubAccessToken(flow, domain, DeviceCodeResponse{code, user, uri, interval, expires}, signal)
        withAccessToken(flow, notify, enterprise, signal, access)

def withInput(+flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, +signal: Abort.AbortSignal<Unit>, aborted: Bool, input: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match input aborted:
    case Fail{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case _ True{}: IO.pure(Auth.LoginOutcome(), Fail{loginCancelled()})
    case Done{+text} False{}:
      +enterprise = normalizeDomain(H.flowContext(flow), text)
      Bool.pick(Unit -> IO(Auth.LoginOutcome()), Bool.not(String.eq(Strings.trim(text), "")) && Maybe.is_none(&2, String, enterprise),
        _ => IO.pure(Auth.LoginOutcome(), Fail{"Invalid GitHub Enterprise URL/domain"}),
        _ => do IO<Auth.LoginOutcome()>:
          +domain : String <- IO.pure(String, Maybe.default(&2, String, enterprise, "github.com"))
          device : Result<&2, &2, String, DeviceCodeResponse> <- startDeviceFlow(flow, domain, signal)
          withDevice(flow, notify, domain, enterprise, signal, device))(Unit{})

def loginWith(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{+signal, prompt, notify}:
      do IO<Auth.LoginOutcome()>:
        input : Result<&2, &2, String, String> <- C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt, Auth.TextPrompt{"GitHub Enterprise URL/domain (blank for github.com)", Some{"company.ghe.com"}, Some{signal}})
        aborted : Bool <- Abort.aborted(Unit, signal)
        withInput(flow, notify, signal, aborted, input)

def login(flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginWith(flow, interaction)

# Refresh and request auth
# ------------------------
def enterpriseText(context: URL.Context, value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: normalizeDomain(context, SCon{c, cs})
    case _: None{}

def enterpriseOf(context: URL.Context, extra: R.Record<V.Value>) -> Maybe<&2, String>: enterpriseText(context, R.get(V.Value, extra, "enterpriseUrl"))

def refreshWith(+flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{token, _, _, extra}, signal}: refreshGitHubCopilotToken(flow, token, enterpriseOf(H.flowContext(flow), extra), signal)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"GitHub Copilot OAuth refresh requires an OAuth credential"})

def refresh(flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>): refreshWith(flow, input)

# Derive the credential-specific proxy endpoint for each request.
def toAuth(context: URL.Context, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, +access, _, extra}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, Some{getGitHubCopilotBaseUrl(Some{access}, enterpriseOf(context, extra))}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"GitHub Copilot OAuth requires an OAuth credential"})

def githubCopilotOAuth(+fetch: Fetch.Fetch(Unit), +url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~H.Flow, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, H.Flow{fetch, url})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~H.Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, H.Flow{fetch, url})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~URL.Context, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, url)
    return Auth.OAuthAuth{"GitHub Copilot", True{}, None{}, authenticate, refresher, deriver}
