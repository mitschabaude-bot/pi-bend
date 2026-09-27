import Base
import ./device-code.bend as Device
import ./oauth-http.bend as H
import ../types.bend as Auth
import ../../types.bend as T
import ../../api/credential-http.bend as Http
import ../../utils/provider-env.bend as ProviderEnv
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/timer.bend as Timer
import ../../../../runtime/src/url.bend as URL

# pi-mono auth/oauth/kimi-coding.ts: Kimi Code (subscription) OAuth. RFC 8628
# device authorization against auth.kimi.com (KIMI_CODE_OAUTH_HOST or
# KIMI_OAUTH_HOST override it) with JSON responses; the access token is sent
# as an `Authorization: Bearer` header.

def CLIENT_ID() -> String: "17e5f671-d194-4dfb-9706-5516cb48c098"
def DEFAULT_OAUTH_HOST() -> String: "https://auth.kimi.com"
def DEVICE_CODE_TIMEOUT_SECONDS() -> F64: F.fromU32(900)
def DEFAULT_POLL_INTERVAL_SECONDS() -> F64: F.fromU32(5)
def REQUEST_TIMEOUT_MS() -> U32: 30000
def REFRESH_MAX_RETRIES() -> Nat: 3n

def Json() -> Data: Maybe<&2, V.Value>

type DeviceAuthorization is Data:
  DeviceAuthorization{deviceCode: String, userCode: String, verificationUri: String, verificationUriComplete: String, intervalSeconds: F64, expiresInSeconds: F64}

type TokenResponse is Data:
  TokenResponse{access: String, refresh: String, expires: F64}

def withoutTrailingSlashes(reversed: String) -> String:
  match reversed:
    case SCon{'/', rest}: withoutTrailingSlashes(rest)
    case other: String.reverse(other)

def hostFrom(override: Maybe<&2, String>) -> String:
  withoutTrailingSlashes(String.reverse(Maybe.default(&2, String, override, DEFAULT_OAUTH_HOST())))

def firstPresent(first: Maybe<&2, String>, second: Maybe<&2, String>) -> Maybe<&2, String>: Maybe.or(&2, String, first, second)

def getOauthHost() -> IO(String):
  do IO<String>:
    code : Maybe<&2, String> <- ProviderEnv.getProviderEnvValue("KIMI_CODE_OAUTH_HOST", None{})
    legacy : Maybe<&2, String> <- ProviderEnv.getProviderEnvValue("KIMI_OAUTH_HOST", None{})
    return hostFrom(firstPresent(code, legacy))

def FORM_HEADERS() -> List<&2, R.Property<String>>: [R.Property{"Content-Type", "application/x-www-form-urlencoded"}, R.Property{"Accept", "application/json"}]

def formPost(flow: H.Flow, +signal: Abort.AbortSignal<Unit>, url: String, fields: List<&2, R.Property<String>>) -> IO(Result<&2, &2, Http.Failure, H.Reply>):
  H.send(flow, signal, "POST", url, FORM_HEADERS(), Headers.Text{H.formText(fields)}, REQUEST_TIMEOUT_MS())

def textSuffix(+text: String) -> String:
  match text:
    case SNil{}: ""
    case other: ": " ++ other

# Device authorization
# --------------------
def orDefault(value: Maybe<&2, F64>, fallback: F64) -> F64: Maybe.default(&2, F64, value, fallback)

def deviceWith(+json: Json(), device: Maybe<&2, String>, user: Maybe<&2, String>, uri: Maybe<&2, String>, complete: Maybe<&2, String>, trusted: Bool) -> Result<&2, &2, String, DeviceAuthorization>:
  match device user uri complete trusted:
    case Some{code} Some{userCode} Some{verification} Some{full} True{}: Done{DeviceAuthorization{code, userCode, verification, full, orDefault(H.positiveField(json, "interval"), DEFAULT_POLL_INTERVAL_SECONDS()), orDefault(H.positiveField(json, "expires_in"), DEVICE_CODE_TIMEOUT_SECONDS())}}
    case _ _ _ _ _: Fail{"Invalid Kimi Code device authorization response: " ++ H.jsonText(json)}

def isTrusted(context: URL.Context, value: Maybe<&2, String>) -> Bool: Maybe.is_some(&2, String, H.trustedUrl(context, value, False{}))

def deviceFrom(+context: URL.Context, +json: Json()) -> Result<&2, &2, String, DeviceAuthorization>:
  deviceWith(json, H.stringField(json, "device_code"), H.stringField(json, "user_code"), H.stringField(json, "verification_uri"), H.stringField(json, "verification_uri_complete"), isTrusted(context, H.stringField(json, "verification_uri_complete")) && isTrusted(context, H.stringField(json, "verification_uri")))

def authorized(context: URL.Context, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, DeviceAuthorization>:
  match result:
    case Fail{failure}: Fail{H.failureText(failure)}
    case Done{+reply}: Bool.pick(Result<&2, &2, String, DeviceAuthorization>, H.ok(reply), deviceFrom(context, H.replyJson(reply)), Fail{"Kimi Code device authorization failed with status " ++ U32.show(H.replyStatus(reply)) ++ textSuffix(H.replyText(reply))})

def startDeviceAuthorization(+flow: H.Flow, +host: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, DeviceAuthorization>):
  do IO<Result<&2, &2, String, DeviceAuthorization>>:
    result : Result<&2, &2, Http.Failure, H.Reply> <- formPost(flow, signal, host ++ "/api/oauth/device_authorization", [R.Property{"client_id", CLIENT_ID()}])
    return authorized(H.flowContext(flow), result)

# Tokens
# ------
def tokenWith(+now: F64, +operation: String, json: Json(), access: Maybe<&2, String>, refresh: Maybe<&2, String>, expires: Maybe<&2, F64>) -> Result<&2, &2, String, TokenResponse>:
  match access refresh expires:
    case Some{a} Some{r} Some{seconds}: Done{TokenResponse{a, r, F.add(now, F.multiply(seconds, F.fromU32(1000)))}}
    case _ _ _: Fail{"Kimi Code token " ++ operation ++ " response missing fields: " ++ H.jsonText(json)}

def parseTokenResponse(+now: F64, +json: Json(), +operation: String) -> Result<&2, &2, String, TokenResponse>:
  tokenWith(now, operation, json, H.nonEmptyField(json, "access_token"), H.nonEmptyField(json, "refresh_token"), H.positiveField(json, "expires_in"))

def credentialOf(token: TokenResponse) -> Auth.Credential:
  match token:
    case TokenResponse{access, refresh, expires}: Auth.OAuthCredential{refresh, access, expires, R.new(V.Value)}

# Polling
# -------
type Poll is Data:
  Poll{flow: H.Flow, host: String, deviceCode: String, signal: Abort.AbortSignal<Unit>}

def PollResult() -> Data: Device.OAuthDeviceCodePollResult<TokenResponse>

def fromToken(result: Result<&2, &2, String, TokenResponse>) -> PollResult():
  match result:
    case Done{token}: Device.PollComplete{token}
    case Fail{message}: Device.PollFailed{message}

def prefixed(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: ": " ++ text
    case None{}: ""

def descriptionOf(json: Json()) -> String: prefixed(H.stringField(json, "error_description"))

def errorResult(+status: U32, json: Json(), error: Maybe<&2, String>) -> PollResult():
  match error:
    case Some{"authorization_pending"}: Device.PollPending{}
    case Some{"slow_down"}: Device.PollSlowDown{H.positiveField(json, "interval")}
    case Some{"expired_token"}: Device.PollFailed{"Kimi Code device authorization expired. Please restart login."}
    case Some{"access_denied"}: Device.PollFailed{"Kimi Code login was denied."}
    case Some{other}: Device.PollFailed{"Kimi Code device token request failed (status " ++ U32.show(status) ++ "): " ++ other ++ descriptionOf(json)}
    case None{}: Device.PollFailed{"Kimi Code device token request failed (status " ++ U32.show(status) ++ ")"}

def pollReply(+now: F64, +reply: H.Reply) -> PollResult():
  Bool.pick(Unit -> PollResult(), U32.is_ge(H.replyStatus(reply), 500),
    _ => Device.PollFailed{"Kimi Code device token request failed with status " ++ U32.show(H.replyStatus(reply)) ++ textSuffix(H.replyText(reply))},
    _ => Bool.pick(Unit -> PollResult(), H.ok(reply) && Maybe.is_some(&2, String, H.stringField(H.replyJson(reply), "access_token")),
      _ => fromToken(parseTokenResponse(now, H.replyJson(reply), "poll")),
      _ => errorResult(H.replyStatus(reply), H.replyJson(reply), H.stringField(H.replyJson(reply), "error")))(Unit{}))(Unit{})

def polled(+now: F64, result: Result<&2, &2, Http.Failure, H.Reply>) -> PollResult():
  match result:
    case Fail{failure}: Device.PollFailed{H.failureText(failure)}
    case Done{reply}: pollReply(now, reply)

def poll(state: Poll, unused: Unit) -> IO(PollResult()):
  match state:
    case Poll{flow, host, deviceCode, signal}:
      do IO<PollResult()>:
        result : Result<&2, &2, Http.Failure, H.Reply> <- formPost(flow, signal, host ++ "/api/oauth/token", [R.Property{"client_id", CLIENT_ID()}, R.Property{"device_code", deviceCode}, R.Property{"grant_type", "urn:ietf:params:oauth:grant-type:device_code"}])
        now : F64 <- Date.now()
        return polled(now, result)

def pollForToken(flow: H.Flow, +host: String, device: DeviceAuthorization, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, TokenResponse>):
  match device:
    case DeviceAuthorization{deviceCode, _, _, _, interval, expires}:
      do IO<Result<&2, &2, String, TokenResponse>>:
        poller : C.Callback<Unit, PollResult()> <- C.create(~Poll, ~Unit, ~PollResult(), ~poll, Poll{flow, host, deviceCode, signal})
        Device.pollOAuthDeviceCodeFlow(~TokenResponse, Device.OAuthDeviceCodePollOptions{Some{interval}, Some{expires}, True{}, poller, signal})

# Refresh
# -------
type Refreshing is Data:
  Attempt{attempt: Nat, last: Maybe<&2, String>}
  Refreshed{result: Result<&2, &2, String, TokenResponse>}

def unauthorizedStatus(+status: U32, json: Json()) -> Bool:
  U32.is_eq(status, 401) || U32.is_eq(status, 403) || Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, error => String.eq(error, "invalid_grant"), H.stringField(json, "error")), False{})

def retryableStatus(+status: U32) -> Bool: U32.is_eq(status, 429) || U32.is_ge(status, 500)

def refreshReply(+now: F64, +attempt: Nat, +reply: H.Reply) -> Refreshing:
  Bool.pick(Unit -> Refreshing, H.ok(reply),
    _ => Refreshed{parseTokenResponse(now, H.replyJson(reply), "refresh")},
    _ => Bool.pick(Unit -> Refreshing, unauthorizedStatus(H.replyStatus(reply), H.replyJson(reply)),
      _ => Refreshed{Fail{"Kimi Code token refresh unauthorized (status " ++ U32.show(H.replyStatus(reply)) ++ ")" ++ descriptionOf(H.replyJson(reply))}},
      _ => Bool.pick(Unit -> Refreshing, retryableStatus(H.replyStatus(reply)) && Nat.is_lt(attempt, REFRESH_MAX_RETRIES()),
        _ => Attempt{1n + attempt, Some{"Kimi Code token refresh failed with status " ++ U32.show(H.replyStatus(reply))}},
        _ => Refreshed{Fail{"Kimi Code token refresh failed with status " ++ U32.show(H.replyStatus(reply)) ++ textSuffix(H.jsonText(H.replyJson(reply)))}})(Unit{}))(Unit{}))(Unit{})

def refreshStep(+now: F64, +attempt: Nat, result: Result<&2, &2, Http.Failure, H.Reply>) -> Refreshing:
  match result:
    case Fail{failure}: Attempt{1n + attempt, Some{H.failureText(failure)}}
    case Done{reply}: refreshReply(now, attempt, reply)

def backoffMs(attempt: Nat) -> U32: (1000 * U32.shln(1, Nat.sub(attempt, 1n)) : U32)

def lastError(last: Maybe<&2, String>) -> String: Maybe.default(&2, String, last, "Kimi Code token refresh failed")

@unsafe def refreshing(+flow: H.Flow, +host: String, +token: String, +signal: Abort.AbortSignal<Unit>, state: Refreshing) -> IO(Result<&2, &2, String, TokenResponse>):
  match state:
    case Refreshed{result}: IO.pure(Result<&2, &2, String, TokenResponse>, result)
    case Attempt{+attempt, last}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, TokenResponse>), Nat.is_gt(attempt, REFRESH_MAX_RETRIES()),
        _ => IO.pure(Result<&2, &2, String, TokenResponse>, Fail{lastError(last)}),
        _ => do IO<Result<&2, &2, String, TokenResponse>>:
          slept : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Bool.pick(IO(Result<&2, &2, Abort.AbortReason<Unit>, Unit>), Nat.is_gt(attempt, 0n), Timer.sleep(Unit, backoffMs(attempt), signal), IO.pure(Result<&2, &2, Abort.AbortReason<Unit>, Unit>, Done{Unit{}}))
          aborted : Bool <- Abort.aborted(Unit, signal)
          Bool.pick(Unit -> IO(Result<&2, &2, String, TokenResponse>), aborted,
            _ => IO.pure(Result<&2, &2, String, TokenResponse>, Fail{"Kimi Code token refresh aborted"}),
            _ => do IO<Result<&2, &2, String, TokenResponse>>:
              result : Result<&2, &2, Http.Failure, H.Reply> <- formPost(flow, signal, host ++ "/api/oauth/token", [R.Property{"client_id", CLIENT_ID()}, R.Property{"grant_type", "refresh_token"}, R.Property{"refresh_token", token}])
              now : F64 <- Date.now()
              refreshing(flow, host, token, signal, refreshStep(now, attempt, result)))(Unit{}))(Unit{})

def refreshToken(flow: H.Flow, +host: String, +token: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, TokenResponse>):
  refreshing(flow, host, token, signal, Attempt{0n, None{}})

# Login and requests
# ------------------
def withDevice(flow: H.Flow, +host: String, notify: C.Callback<Auth.AuthEvent, Unit>, +signal: Abort.AbortSignal<Unit>, device: Result<&2, &2, String, DeviceAuthorization>) -> IO(Auth.LoginOutcome()):
  match device:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{DeviceAuthorization{deviceCode, +userCode, uri, +complete, +interval, +expires}}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.DeviceCodeEvent{userCode, complete, Some{interval}, Some{expires}})
        token : Result<&2, &2, String, TokenResponse> <- pollForToken(flow, host, DeviceAuthorization{deviceCode, userCode, uri, complete, interval, expires}, signal)
        return Result.map(&2, &2, String, TokenResponse, Auth.Credential, credentialOf, token)

def loginWith(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{+signal, _, notify}:
      do IO<Auth.LoginOutcome()>:
        +host : String <- getOauthHost()
        device : Result<&2, &2, String, DeviceAuthorization> <- startDeviceAuthorization(flow, host, signal)
        withDevice(flow, host, notify, signal, device)

def login(flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginWith(flow, interaction)

def refreshWith(+flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{token, _, _, _}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        host : String <- getOauthHost()
        result : Result<&2, &2, String, TokenResponse> <- refreshToken(flow, host, token, signal)
        return Result.map(&2, &2, String, TokenResponse, Auth.Credential, credentialOf, result)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Kimi Code OAuth refresh requires an OAuth credential"})

def refresh(flow: H.Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>): refreshWith(flow, input)

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{None{}, Some{R.Record{[R.Property{"Authorization", T.PresentValue{"Bearer " ++ access}}]}}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"Kimi Code OAuth requires an OAuth credential"})

def kimiCodingOAuth(+fetch: Fetch.Fetch(Unit), +url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~H.Flow, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, H.Flow{fetch, url})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~H.Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, H.Flow{fetch, url})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"Kimi Code (subscription)", True{}, Some{"Sign in with Kimi Code"}, authenticate, refresher, deriver}
