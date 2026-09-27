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
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/url.bend as URL

# pi-mono auth/oauth/xai.ts: the xAI OAuth device-code flow.

def XAI_CLIENT_ID() -> String: "b1a00492-073a-47ea-816f-4c329264a828"
def XAI_SCOPE() -> String: "openid profile email offline_access grok-cli:access api:access"
def XAI_DEVICE_CODE_URL() -> String: "https://auth.x.ai/oauth2/device/code"
def XAI_TOKEN_URL() -> String: "https://auth.x.ai/oauth2/token"
# Refresh slightly before the reported expiry to avoid using a token that dies mid-request.
def REFRESH_SKEW_MS() -> F64: F.fromU32(300000)
def DEFAULT_TOKEN_LIFETIME_SECONDS() -> F64: F.fromU32(3600)

def Json() -> Data: Maybe<&2, V.Value>

type OAuthHttpResponse is Data:
  OAuthHttpResponse{ok: Bool, status: U32, body: Json()}

type XaiDeviceCode is Data:
  XaiDeviceCode{deviceCode: String, userCode: String, verificationUri: String, verificationUriComplete: Maybe<&2, String>, intervalSeconds: Maybe<&2, F64>, expiresInSeconds: F64}

def invalidField(+field: String) -> String: "Invalid xAI OAuth response field: " ++ field

def requiredString(body: Json(), +field: String) -> Result<&2, &2, String, String>:
  H.orFail(String, H.nonEmptyField(body, field), invalidField(field))

def positiveNumber(body: Json(), +field: String) -> Result<&2, &2, String, F64>:
  H.orFail(F64, H.positiveField(body, field), invalidField(field))

def UNTRUSTED() -> String: "Untrusted verification URI in xAI OAuth response"

# The verification URI is opened in the user's browser; force it to be an
# https URL so a malicious response cannot make `open` launch something else.
def validateVerificationUri(context: URL.Context, raw: String) -> Result<&2, &2, String, String>:
  H.orFail(String, H.trustedUrl(context, Some{raw}, True{}), UNTRUSTED())

# postForm: a network failure is "Login cancelled" once the signal aborted;
# a body that is not JSON is an error (unless aborted); a JSON non-object is {}.
def formFailure(aborted: Bool, failure: Http.Failure) -> String:
  Bool.pick(String, aborted, "Login cancelled", H.failureText(failure))

def formJson(aborted: Bool, ok: Bool, +status: U32, json: Json()) -> Result<&2, &2, String, OAuthHttpResponse>:
  match json:
    case Some{V.ObjectValue{fields}}: Done{OAuthHttpResponse{ok, status, Some{V.ObjectValue{fields}}}}
    case Some{_}: Done{OAuthHttpResponse{ok, status, None{}}}
    case None{}: Fail{Bool.pick(String, aborted, "Login cancelled", "xAI OAuth returned invalid JSON (HTTP " ++ U32.show(status) ++ ")")}

def formReply(aborted: Bool, reply: H.Reply) -> Result<&2, &2, String, OAuthHttpResponse>:
  match reply:
    case H.Reply{+status, headers, text, +json}: formJson(aborted, H.ok(H.Reply{status, headers, text, json}), status, json)

def formOutcome(aborted: Bool, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, OAuthHttpResponse>:
  match result:
    case Fail{failure}: Fail{formFailure(aborted, failure)}
    case Done{reply}: formReply(aborted, reply)

def postForm(flow: H.Flow, url: String, fields: List<&2, R.Property<String>>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, OAuthHttpResponse>):
  do IO<Result<&2, &2, String, OAuthHttpResponse>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, "POST", url, [R.Property{"Accept", "application/json"}, R.Property{"Content-Type", "application/x-www-form-urlencoded"}], H.form(fields), Http.NO_TIMEOUT())
    aborted : Bool <- Abort.aborted(Unit, signal)
    return formOutcome(aborted, result)

def joinedDetail(error: Maybe<&2, String>, description: Maybe<&2, String>) -> String:
  match error description:
    case Some{SCon{e, es}} Some{SCon{d, ds}}: SCon{e, es} ++ ": " ++ SCon{d, ds}
    case Some{SCon{e, es}} _: SCon{e, es}
    case _ Some{SCon{d, ds}}: SCon{d, ds}
    case _ _: ""

def detailSuffix(+detail: String) -> String:
  match detail:
    case SNil{}: ""
    case other: ": " ++ other

def requestFailure(+action: String, response: OAuthHttpResponse) -> String:
  match response:
    case OAuthHttpResponse{_, status, +body}: "xAI OAuth " ++ action ++ " failed (HTTP " ++ U32.show(status) ++ ")" ++ detailSuffix(joinedDetail(H.stringField(body, "error"), H.stringField(body, "error_description")))

# RFC 8628 allows interval 0 (no minimum wait); fall back to the poller's
# default instead of failing on non-positive or malformed values.
def optionalUri(context: URL.Context, raw: Maybe<&2, String>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match raw:
    case Some{text}: Result.map(&2, &2, String, String, Maybe<&2, String>, uri => Some{uri}, validateVerificationUri(context, text))
    case None{}: Done{None{}}

def completeUri(context: URL.Context, body: Json()) -> Result<&2, &2, String, Maybe<&2, String>>:
  optionalUri(context, H.nonEmptyField(body, "verification_uri_complete"))

def parseDeviceCode(+context: URL.Context, +body: Json()) -> Result<&2, &2, String, XaiDeviceCode>:
  Result.bind(&2, &2, String, Maybe<&2, String>, XaiDeviceCode, completeUri(context, body), complete =>
    Result.bind(&2, &2, String, String, XaiDeviceCode, requiredString(body, "device_code"), deviceCode =>
      Result.bind(&2, &2, String, String, XaiDeviceCode, requiredString(body, "user_code"), userCode =>
        Result.bind(&2, &2, String, String, XaiDeviceCode, Result.bind(&2, &2, String, String, String, requiredString(body, "verification_uri"), raw => validateVerificationUri(context, raw)), verificationUri =>
          Result.map(&2, &2, String, F64, XaiDeviceCode, expires => XaiDeviceCode{deviceCode, userCode, verificationUri, complete, H.positiveField(body, "interval"), expires}, positiveNumber(body, "expires_in"))))))

# xAI may omit refresh_token on refresh when the token is not rotated.
def refreshWith(present: Maybe<&2, V.Value>, previous: Maybe<&2, String>, body: Json()) -> Result<&2, &2, String, String>:
  match present previous:
    case None{} Some{SCon{p, ps}}: Done{SCon{p, ps}}
    case _ _: requiredString(body, "refresh_token")

def refreshOf(+body: Json(), previous: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  refreshWith(H.field(body, "refresh_token"), previous, body)

def lifetimeWith(present: Maybe<&2, V.Value>, body: Json()) -> Result<&2, &2, String, F64>:
  match present:
    case None{}: Done{DEFAULT_TOKEN_LIFETIME_SECONDS()}
    case Some{_}: positiveNumber(body, "expires_in")

def lifetimeOf(+body: Json()) -> Result<&2, &2, String, F64>: lifetimeWith(H.field(body, "expires_in"), body)

def credentialsFromTokenResponse(+now: F64, +body: Json(), previous: Maybe<&2, String>) -> Result<&2, &2, String, Auth.Credential>:
  Result.bind(&2, &2, String, String, Auth.Credential, requiredString(body, "access_token"), access =>
    Result.bind(&2, &2, String, String, Auth.Credential, refreshOf(body, previous), refresh =>
      Result.map(&2, &2, String, F64, Auth.Credential, seconds => Auth.OAuthCredential{refresh, access, F.subtract(F.add(now, F.multiply(seconds, F.fromU32(1000))), REFRESH_SKEW_MS()), R.new(V.Value)}, lifetimeOf(body))))

def deviceCodeFrom(context: URL.Context, response: Result<&2, &2, String, OAuthHttpResponse>) -> Result<&2, &2, String, XaiDeviceCode>:
  match response:
    case Fail{message}: Fail{message}
    case Done{OAuthHttpResponse{True{}, status, body}}: parseDeviceCode(context, body)
    case Done{failed}: Fail{requestFailure("device authorization", failed)}

def requestDeviceCode(+flow: H.Flow, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, XaiDeviceCode>):
  do IO<Result<&2, &2, String, XaiDeviceCode>>:
    response : Result<&2, &2, String, OAuthHttpResponse> <- postForm(flow, XAI_DEVICE_CODE_URL(), [R.Property{"client_id", XAI_CLIENT_ID()}, R.Property{"scope", XAI_SCOPE()}, R.Property{"referrer", "pi"}], signal)
    return deviceCodeFrom(H.flowContext(flow), response)

# Polling
# -------
type Poll is Data:
  Poll{flow: H.Flow, deviceCode: String, signal: Abort.AbortSignal<Unit>}

def PollResult() -> Data: Device.OAuthDeviceCodePollResult<Auth.Credential>

def completed(result: Result<&2, &2, String, Auth.Credential>) -> PollResult():
  match result:
    case Done{credential}: Device.PollComplete{credential}
    case Fail{message}: Device.PollFailed{message}

def responseBody(response: OAuthHttpResponse) -> Json():
  match response:
    case OAuthHttpResponse{_, _, body}: body

def pollError(error: Maybe<&2, String>, response: OAuthHttpResponse) -> PollResult():
  match error:
    case Some{"authorization_pending"}: Device.PollPending{}
    case Some{"slow_down"}: Device.PollSlowDown{H.numberField(responseBody(response), "interval")}
    case Some{"access_denied"}: Device.PollFailed{"xAI device authorization was denied"}
    case Some{"authorization_denied"}: Device.PollFailed{"xAI device authorization was denied"}
    case Some{"expired_token"}: Device.PollFailed{"xAI device code expired"}
    case _: Device.PollFailed{requestFailure("device token polling", response)}

def pollOutcome(+now: F64, response: Result<&2, &2, String, OAuthHttpResponse>) -> PollResult():
  match response:
    case Fail{message}: Device.PollFailed{message}
    case Done{OAuthHttpResponse{True{}, _, +body}}: completed(credentialsFromTokenResponse(now, body, None{}))
    case Done{OAuthHttpResponse{ok, status, +body}}: pollError(H.stringField(body, "error"), OAuthHttpResponse{ok, status, body})

def poll(state: Poll, unused: Unit) -> IO(PollResult()):
  match state:
    case Poll{flow, deviceCode, signal}:
      do IO<PollResult()>:
        response : Result<&2, &2, String, OAuthHttpResponse> <- postForm(flow, XAI_TOKEN_URL(), [R.Property{"grant_type", "urn:ietf:params:oauth:grant-type:device_code"}, R.Property{"client_id", XAI_CLIENT_ID()}, R.Property{"device_code", deviceCode}], signal)
        now : F64 <- Date.now()
        return pollOutcome(now, response)

def pollForTokens(flow: H.Flow, device: XaiDeviceCode, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  match device:
    case XaiDeviceCode{deviceCode, _, _, _, interval, expires}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        poller : C.Callback<Unit, PollResult()> <- C.create(~Poll, ~Unit, ~PollResult(), ~poll, Poll{flow, deviceCode, signal})
        Device.pollOAuthDeviceCodeFlow(~Auth.Credential, Device.OAuthDeviceCodePollOptions{interval, Some{expires}, True{}, poller, signal})

# Login and refresh
# -----------------
def shownUri(device: XaiDeviceCode) -> String:
  match device:
    case XaiDeviceCode{_, _, uri, complete, _, _}: Maybe.default(&2, String, complete, uri)

def deviceEvent(device: XaiDeviceCode) -> Auth.AuthEvent:
  match device:
    case XaiDeviceCode{_, userCode, uri, complete, interval, expires}: Auth.DeviceCodeEvent{userCode, Maybe.default(&2, String, complete, uri), interval, Some{expires}}

def loggedIn(flow: H.Flow, interaction: Auth.ProviderAuthInteraction, device: Result<&2, &2, String, XaiDeviceCode>) -> IO(Auth.LoginOutcome()):
  match device interaction:
    case Fail{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{+code} Auth.ProviderAuthInteraction{+signal, _, notify}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, deviceEvent(code))
        pollForTokens(flow, code, signal)

def loginWith(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{+signal, prompt, notify}:
      do IO<Auth.LoginOutcome()>:
        device : Result<&2, &2, String, XaiDeviceCode> <- requestDeviceCode(flow, signal)
        loggedIn(flow, Auth.ProviderAuthInteraction{signal, prompt, notify}, device)

def login(flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginWith(flow, interaction)

def refreshedFrom(+now: F64, +previous: String, response: Result<&2, &2, String, OAuthHttpResponse>) -> Result<&2, &2, String, Auth.Credential>:
  match response:
    case Fail{message}: Fail{message}
    case Done{OAuthHttpResponse{True{}, _, +body}}: credentialsFromTokenResponse(now, body, Some{previous})
    case Done{failed}: Fail{requestFailure("token refresh", failed)}

def refreshXaiToken(flow: H.Flow, +refreshToken: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  do IO<Result<&2, &2, String, Auth.Credential>>:
    response : Result<&2, &2, String, OAuthHttpResponse> <- postForm(flow, XAI_TOKEN_URL(), [R.Property{"grant_type", "refresh_token"}, R.Property{"client_id", XAI_CLIENT_ID()}, R.Property{"refresh_token", refreshToken}], signal)
    now : F64 <- Date.now()
    return refreshedFrom(now, refreshToken, response)

def refresh(flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refreshToken, _, _, _}, signal}: refreshXaiToken(flow, refreshToken, signal)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"xAI OAuth refresh requires an OAuth credential"})

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"xAI OAuth requires an OAuth credential"})

def xaiOAuth(+fetch: Fetch.Fetch(Unit), +url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~H.Flow, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, H.Flow{fetch, url})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~H.Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, H.Flow{fetch, url})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"xAI (Grok/X subscription)", True{}, Some{"Sign in with SuperGrok or X Premium"}, authenticate, refresher, deriver}
