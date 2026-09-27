import Base
import ./device-code.bend as Device
import ./oauth-http.bend as H
import ../types.bend as Auth
import ../../api/credential-http.bend as Http
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/text.bend as Strings
import ../../../../runtime/src/url.bend as URL

# pi-mono auth/oauth/meta.ts: the Meta Model API OAuth flow. RFC 8628 device
# authorization against auth.meta.com; the identity token is exchanged for a
# Model API key at the Muse Code key-mint endpoint (keys live about a day).
# The identity token is stored as `refresh` and the minted key as `access`,
# so refreshing re-mints the key; a 401/403 from mint means the session is
# dead and the user must sign in again.

# Muse Code CLI client id.
def CLIENT_ID() -> String: "1031625952748946"
def DEVICE_AUTHORIZATION_URL() -> String: "https://auth.meta.com/oidc/device/authorization/"
def DEVICE_TOKEN_URL() -> String: "https://auth.meta.com/oidc/device/token/"
def API_KEY_MINT_URL() -> String: "https://api.meta.ai/muse-code/key"
def API_KEY_LIFETIME_MS() -> F64: F.fromU32(86400000)
def REQUEST_TIMEOUT_MS() -> U32: 30000

def Json() -> Data: Maybe<&2, V.Value>

type DeviceAuthorization is Data:
  DeviceAuthorization{deviceCode: String, userCode: String, verificationUri: String, intervalSeconds: Maybe<&2, F64>, expiresInSeconds: Maybe<&2, F64>}

def nonBlank(+text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case other: Some{other}

def trimmedText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: nonBlank(Strings.trim(text))
    case _: None{}

def detailFrom(+json: Json(), keys: List<&2, String>) -> String:
  match keys:
    case Nil{}: ""
    case key <> rest: Maybe.default(&2, String, Maybe.map(&2, String, String, text => ": " ++ text, trimmedText(H.field(json, key))), detailFrom(json, rest))

def errorDetail(json: Json()) -> String: detailFrom(json, ["error_description", "detail", "message", "error"])

def status(reply: H.Reply) -> String: U32.show(H.replyStatus(reply))

def FORM_HEADERS() -> List<&2, R.Property<String>>: [R.Property{"Content-Type", "application/x-www-form-urlencoded"}, R.Property{"Accept", "application/json"}]

def formPost(flow: H.Flow, +signal: Abort.AbortSignal<Unit>, url: String, fields: List<&2, R.Property<String>>) -> IO(Result<&2, &2, Http.Failure, H.Reply>):
  H.send(flow, signal, "POST", url, FORM_HEADERS(), Headers.Text{H.formText(fields)}, REQUEST_TIMEOUT_MS())

# Device authorization
# --------------------
def deviceWith(device: Maybe<&2, String>, user: Maybe<&2, String>, uri: Maybe<&2, String>, +json: Json()) -> Result<&2, &2, String, DeviceAuthorization>:
  match device user uri:
    case Some{code} Some{userCode} Some{verification}: Done{DeviceAuthorization{code, userCode, verification, H.positiveField(json, "interval"), H.positiveField(json, "expires_in")}}
    case _ _ _: Fail{"Invalid Meta device authorization response: " ++ H.jsonText(json)}

def deviceFrom(+context: URL.Context, +json: Json()) -> Result<&2, &2, String, DeviceAuthorization>:
  deviceWith(H.nonEmptyField(json, "device_code"), H.nonEmptyField(json, "user_code"), Maybe.or(&2, String, H.trustedUrl(context, H.stringField(json, "verification_uri_complete"), False{}), H.trustedUrl(context, H.stringField(json, "verification_uri"), False{})), json)

def authorized(context: URL.Context, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, DeviceAuthorization>:
  match result:
    case Fail{failure}: Fail{H.failureText(failure)}
    case Done{+reply}: Bool.pick(Result<&2, &2, String, DeviceAuthorization>, H.ok(reply), deviceFrom(context, H.replyJson(reply)), Fail{"Meta device authorization failed with status " ++ status(reply) ++ errorDetail(H.replyJson(reply))})

def startDeviceAuthorization(+flow: H.Flow, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, DeviceAuthorization>):
  do IO<Result<&2, &2, String, DeviceAuthorization>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- formPost(flow, signal, DEVICE_AUTHORIZATION_URL(), [R.Property{"client_id", CLIENT_ID()}])
    return authorized(H.flowContext(flow), result)

# Polling
# -------
type Poll is Data:
  Poll{flow: H.Flow, deviceCode: String, signal: Abort.AbortSignal<Unit>}

def PollResult() -> Data: Device.OAuthDeviceCodePollResult<String>

def pollFailure(+status: String, json: Json(), error: Maybe<&2, String>) -> PollResult():
  match error:
    case Some{"authorization_pending"}: Device.PollPending{}
    case Some{"slow_down"}: Device.PollSlowDown{H.positiveField(json, "interval")}
    case Some{"access_denied"}: Device.PollFailed{"Meta login was denied."}
    case Some{"expired_token"}: Device.PollFailed{"Meta device authorization expired. Please restart login."}
    case _: Device.PollFailed{"Meta device token request failed with status " ++ status ++ errorDetail(json)}

def pollReply(ok: Bool, +status: String, +json: Json(), token: Maybe<&2, String>) -> PollResult():
  match ok token:
    case True{} Some{value}: Device.PollComplete{value}
    case _ _: pollFailure(status, json, H.stringField(json, "error"))

def polled(result: Result<&2, &2, Http.Failure, H.Reply>) -> PollResult():
  match result:
    case Fail{failure}: Device.PollFailed{H.failureText(failure)}
    case Done{+reply}: pollReply(H.ok(reply), status(reply), H.replyJson(reply), H.nonEmptyField(H.replyJson(reply), "access_token"))

def poll(state: Poll, unused: Unit) -> IO(PollResult()):
  match state:
    case Poll{flow, deviceCode, signal}:
      do IO<PollResult()>:
        result : Result<&2, &2, Http.Failure, H.Reply> <- formPost(flow, signal, DEVICE_TOKEN_URL(), [R.Property{"grant_type", "urn:ietf:params:oauth:grant-type:device_code"}, R.Property{"device_code", deviceCode}, R.Property{"client_id", CLIENT_ID()}])
        return polled(result)

def pollForIdentityToken(flow: H.Flow, device: DeviceAuthorization, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, String>):
  match device:
    case DeviceAuthorization{deviceCode, _, _, interval, expires}:
      do IO<Result<&2, &2, String, String>>:
        poller : C.Callback<Unit, PollResult()> <- C.create(~Poll, ~Unit, ~PollResult(), ~poll, Poll{flow, deviceCode, signal})
        Device.pollOAuthDeviceCodeFlow(~String, Device.OAuthDeviceCodePollOptions{interval, expires, True{}, poller, signal})

def setupSuffix(url: Maybe<&2, String>) -> String:
  match url:
    case Some{action}: " Complete setup at " ++ action
    case None{}: ""

def issuedKey(key: Maybe<&2, String>, +now: F64, identity: String, context: URL.Context, json: Json()) -> Result<&2, &2, String, Auth.Credential>:
  match key:
    case Some{value}: Done{Auth.OAuthCredential{identity, value, F.add(now, API_KEY_LIFETIME_MS()), R.new(V.Value)}}
    case None{}: Fail{"Meta did not issue an API key." ++ setupSuffix(H.trustedUrl(context, H.stringField(json, "action_url"), False{}))}

def issued(+now: F64, identity: String, context: URL.Context, +json: Json()) -> Result<&2, &2, String, Auth.Credential>:
  issuedKey(H.nonEmptyField(json, "api_key"), now, identity, context, json)

# Key mint
# --------
def mintedStatus(+code: U32, +now: F64, +identity: String, context: URL.Context, +reply: H.Reply) -> Result<&2, &2, String, Auth.Credential>:
  Bool.pick(Result<&2, &2, String, Auth.Credential>, U32.is_eq(code, 401) || U32.is_eq(code, 403), Fail{"Meta session expired (status " ++ U32.show(code) ++ "). Run `/login meta` to sign in again." ++ errorDetail(H.replyJson(reply))}, Bool.pick(Result<&2, &2, String, Auth.Credential>, H.ok(reply), issued(now, identity, context, H.replyJson(reply)), Fail{"Meta API key mint failed with status " ++ status(reply) ++ errorDetail(H.replyJson(reply))}))

def minted(+now: F64, +identity: String, context: URL.Context, +reply: H.Reply) -> Result<&2, &2, String, Auth.Credential>:
  mintedStatus(H.replyStatus(reply), now, identity, context, reply)

def mintOutcome(+now: F64, +identity: String, context: URL.Context, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, Auth.Credential>:
  match result:
    case Fail{failure}: Fail{H.failureText(failure)}
    case Done{reply}: minted(now, identity, context, reply)

# Exchange an identity token for a Model API key.
def mintApiKey(+flow: H.Flow, +identityToken: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  do IO<Result<&2, &2, String, Auth.Credential>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, "POST", API_KEY_MINT_URL(), [R.Property{"Accept", "application/json"}, R.Property{"Authorization", "Bearer " ++ identityToken}, R.Property{"Content-Type", "application/json"}, R.Property{"x-api-version", "1.0.0"}], Headers.Text{"{}"}, REQUEST_TIMEOUT_MS())
    now : F64 <- Date.now()
    return mintOutcome(now, identityToken, H.flowContext(flow), result)

# Login
# -----
# An in-flight fetch rejects on abort; the login UI matches on "Login cancelled".
def cancelledOr(aborted: Bool, result: Auth.LoginOutcome()) -> Auth.LoginOutcome():
  match result:
    case Fail{message}: Fail{Bool.pick(String, aborted, "Login cancelled", message)}
    case done: done

def settled(+signal: Abort.AbortSignal<Unit>, result: Auth.LoginOutcome()) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    return cancelledOr(aborted, result)

def withIdentity(flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, +signal: Abort.AbortSignal<Unit>, identity: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match identity:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{token}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.ProgressEvent{"Enabling Meta Model API access..."})
        mintApiKey(flow, token, signal)

def withDevice(+flow: H.Flow, +notify: C.Callback<Auth.AuthEvent, Unit>, +signal: Abort.AbortSignal<Unit>, device: Result<&2, &2, String, DeviceAuthorization>) -> IO(Auth.LoginOutcome()):
  match device:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{DeviceAuthorization{deviceCode, +userCode, +uri, +interval, +expires}}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.DeviceCodeEvent{userCode, uri, interval, expires})
        identity : Result<&2, &2, String, String> <- pollForIdentityToken(flow, DeviceAuthorization{deviceCode, userCode, uri, interval, expires}, signal)
        withIdentity(flow, notify, signal, identity)

def loginWith(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{+signal, _, +notify}:
      do IO<Auth.LoginOutcome()>:
        device : Result<&2, &2, String, DeviceAuthorization> <- startDeviceAuthorization(flow, signal)
        result : Auth.LoginOutcome() <- withDevice(flow, notify, signal, device)
        settled(signal, result)

def login(flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginWith(flow, interaction)

def refresh(flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{identity, _, _, _}, signal}: mintApiKey(flow, identity, signal)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Meta OAuth refresh requires an OAuth credential"})

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"Meta OAuth requires an OAuth credential"})

def metaOAuth(+fetch: Fetch.Fetch(Unit), +url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~H.Flow, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, H.Flow{fetch, url})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~H.Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, H.Flow{fetch, url})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"Meta (Muse subscription)", True{}, Some{"Sign in with Meta"}, authenticate, refresher, deriver}
