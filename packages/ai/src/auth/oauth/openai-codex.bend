import Base
import ../types.bend as Auth
import ../../types.bend as T
import ../../api/openai-client.bend as Client
import ../../api/openai-responses.bend as Responses
import ../../utils/provider-retry.bend as Retry
import ../../utils/jwt.bend as Jwt
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/http-response.bend as Response
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/json.bend as Json
import ../../utils/json.bend as Encode
import ../../utils/schema-json.bend as SchemaJson
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/parse-float.bend as Number
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/timer.bend as Timer

# OpenAI Codex (ChatGPT OAuth): device login, token refresh and request auth
# through the native HTTPS client. Browser callback login remains separate.

def CLIENT_ID() -> String: "app_EMoamEEZ73f0CkXaXp7hrann"
def TOKEN_URL() -> String: "https://auth.openai.com/oauth/token"
def JWT_CLAIM_PATH() -> String: "https://api.openai.com/auth"
def REFRESH_TIMEOUT_MS() -> F64: F.fromU32(15000)
def DEVICE_USER_CODE_URL() -> String: "https://auth.openai.com/api/accounts/deviceauth/usercode"
def DEVICE_TOKEN_URL() -> String: "https://auth.openai.com/api/accounts/deviceauth/token"
def DEVICE_VERIFICATION_URI() -> String: "https://auth.openai.com/codex/device"
def DEVICE_REDIRECT_URI() -> String: "https://auth.openai.com/deviceauth/callback"

type DeviceEndpoints is Data:
  DeviceEndpoints{userCodeUrl: String, tokenUrl: String, exchangeUrl: String, verificationUri: String}

def deviceEndpoints() -> DeviceEndpoints:
  DeviceEndpoints{DEVICE_USER_CODE_URL(), DEVICE_TOKEN_URL(), TOKEN_URL(), DEVICE_VERIFICATION_URI()}

type DeviceCode is Data:
  DeviceCode{authId: String, userCode: String, interval: U32, verificationUri: String}

def deviceUserCode(device: DeviceCode) -> String:
  match device:
    case DeviceCode{_, code, _, _}: code

def deviceVerificationUri(device: DeviceCode) -> String:
  match device:
    case DeviceCode{_, _, _, uri}: uri

type AuthorizationCode is Data:
  AuthorizationCode{code: String, verifier: String}

type HttpText is Data:
  HttpText{status: U32, body: String}

type Flow is Data:
  Flow{fetch: Fetch.Fetch(Unit), url: URL.Context}

# JWT payload
# -----------

def getAccountId(accessToken: String) -> Maybe<&2, String>:
  Jwt.chatgptAccountId(accessToken)

# Token responses
# ---------------

def nonemptyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{first, rest}}}: Some{SCon{first, rest}}
    case _: None{}

type OAuthToken is Data:
  OAuthToken{access: String, refresh: String, expires: F64}

def tokenFields(now: F64, access: Maybe<&2, String>, refresh: Maybe<&2, String>, expiresIn: Maybe<&2, V.Value>, raw: String) -> Result<&2, &2, String, OAuthToken>:
  match access refresh expiresIn:
    case Some{access} Some{refresh} Some{V.Number{seconds}}: Done{OAuthToken{access, refresh, F.add(now, F.multiply(seconds, F.fromU32(1000)))}}
    case _ _ _: Fail{"OpenAI Codex token refresh response missing fields: " ++ raw}

def tokenFrom(now: F64, +raw: String, value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, OAuthToken>:
  match value:
    case Done{V.ObjectValue{+fields}}: tokenFields(now, nonemptyText(R.get(V.Value, fields, "access_token")), nonemptyText(R.get(V.Value, fields, "refresh_token")), R.get(V.Value, fields, "expires_in"), raw)
    case _: Fail{"OpenAI Codex token refresh response missing fields: " ++ raw}

def withAccount(token: OAuthToken, accountId: Maybe<&2, String>) -> Result<&2, &2, String, Auth.Credential>:
  match token accountId:
    case _ None{}: Fail{"Failed to extract accountId from token"}
    case OAuthToken{access, refresh, expires} Some{account}: Done{Auth.OAuthCredential{refresh, access, expires, R.Record{[R.Property{"accountId", V.Text{account}}]}}}

def credentialsFromToken(token: OAuthToken) -> Result<&2, &2, String, Auth.Credential>:
  match token:
    case OAuthToken{+access, refresh, expires}: withAccount(OAuthToken{access, refresh, expires}, getAccountId(access))

# Refresh request
# ---------------

def formBody(refreshToken: String) -> String:
  URL.toString(URL.append(URL.append(URL.append(URL.new(), "grant_type", "refresh_token"), "refresh_token", refreshToken), "client_id", CLIENT_ID()))

def requestAt(url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: String) -> Result<&2, &2, String, Client.Request>:
  match url headers:
    case Fail{_} _: Fail{"OpenAI Codex token URL is invalid"}
    case _ Fail{_}: Fail{"OpenAI Codex token request headers are invalid"}
    case Done{url} Done{fields}: Done{Client.Request{url, "post", fields, body, REFRESH_TIMEOUT_MS()}}

def request(context: URL.Context, refreshToken: String) -> Result<&2, &2, String, Client.Request>:
  requestAt(URL.parse(context, TOKEN_URL()), Headers.set(Headers.new(), "content-type", "application/x-www-form-urlencoded"), formBody(refreshToken))

def textOutcome(result: Result<&2, &2, Response.TextError<Client.ReadError(Unit)>, String>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{_}: Fail{"OpenAI Codex token refresh error: could not read the response body"}
    case Done{text}: Done{text}

def textRead(reader: Response.Read(Client.ReadError(Unit), Client.State(Unit)), closer: Response.Close(Client.ReadError(Unit), Client.State(Unit)), body: Response.Body<Client.State(Unit)>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    result : Result<&2, &2, Response.TextError<Client.ReadError(Unit)>, String> <- Response.textUsing(Client.ReadError(Unit), Client.State(Unit), reader, closer, 65536n, body)
    return textOutcome(result)

def bodyText(body: Response.Body<Client.State(Unit)>) -> IO(Result<&2, &2, String, String>):
  Response.with(~(Client.ReadError(Unit)), ~(Client.State(Unit)), ~Result<&2, &2, String, String>, ~(Client.read(Unit)), ~(Client.close(Unit)), reader => closer => textRead(reader, closer, body))

def responded(outcome: Client.Outcome(Unit)) -> IO(Result<&2, &2, String, String>):
  match outcome:
    case Fail{failure}: IO.pure(Result<&2, &2, String, String>, Fail{"OpenAI Codex token refresh error: " ++ Responses.describeRetry(Unit, Retry.RequestFailed{failure}, "openai-codex")})
    case Done{Response.Response{_, body}}: bodyText(body)

def parsedToken(now: F64, text: Result<&2, &2, String, String>) -> Result<&2, &2, String, OAuthToken>:
  match text:
    case Fail{error}: Fail{error}
    case Done{+raw}: tokenFrom(now, raw, Json.parse(raw))

def dispatched(fetch: Fetch.Fetch(Unit), signal: Abort.AbortSignal<Unit>, prepared: Result<&2, &2, String, Client.Request>) -> IO(Result<&2, &2, String, OAuthToken>):
  match prepared:
    case Fail{error}: IO.pure(Result<&2, &2, String, OAuthToken>, Fail{error})
    case Done{ready}:
      do IO<Result<&2, &2, String, OAuthToken>>:
        outcome : Client.Outcome(Unit) <- Client.attempt(~Unit, ready, signal, fetch, 65536n)
        text : Result<&2, &2, String, String> <- responded(outcome)
        now : F64 <- Date.now()
        return parsedToken(now, text)

def refreshAccessToken(flow: Flow, refreshToken: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, OAuthToken>):
  match flow:
    case Flow{fetch, context}: dispatched(fetch, signal, request(context, refreshToken))

def refreshed(token: Result<&2, &2, String, OAuthToken>) -> Result<&2, &2, String, Auth.Credential>:
  match token:
    case Fail{error}: Fail{error}
    case Done{value}: credentialsFromToken(value)

# Device authorization follows the upstream user-code, poll, and authorization
# code exchange sequence. Endpoints are explicit to permit a local HTTP oracle.
def responseText(outcome: Result<&2, &1, Client.FetchError<Unit>, Response.Response<Client.State(Unit)>>) -> IO(Result<&2, &2, String, HttpText>):
  match outcome:
    case Fail{_}: IO.pure(Result<&2, &2, String, HttpText>, Fail{"OpenAI Codex login request failed or was cancelled"})
    case Done{Response.Response{metadata, body}}:
      do IO<Result<&2, &2, String, HttpText>>:
        raw : Result<&2, &2, String, String> <- bodyText(body)
        return Result.map(&2, &2, String, String, HttpText, text => HttpText{Response.metadataStatus(metadata), text}, raw)

def postPrepared(fetch: Fetch.Fetch(Unit), signal: Abort.AbortSignal<Unit>, prepared: Result<&2, &2, String, Client.Request>) -> IO(Result<&2, &2, String, HttpText>):
  match prepared:
    case Fail{error}: IO.pure(Result<&2, &2, String, HttpText>, Fail{error})
    case Done{+ready}:
      do IO<Result<&2, &2, String, HttpText>>:
        outcome : Result<&2, &1, Client.FetchError<Unit>, Response.Response<Client.State(Unit)>> <- Client.dispatch(Unit, ready, signal, fetch, Client.timeout(ready))
        responseText(outcome)

def post(fetch: Fetch.Fetch(Unit), context: URL.Context, endpoint: String, contentType: String, body: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, HttpText>):
  postPrepared(fetch, signal, requestAt(URL.parse(context, endpoint), Headers.set(Headers.new(), "content-type", contentType), body))

def intervalNumber(+number: F64) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, F.isFinite(F.decode(number)) && F.isAtLeast(F.compare(number, F.fromU32(0))) && F.isAtMost(F.compare(number, F.fromU32(4294966))), Some{F64.to_u32(number)}, None{})

def deviceInterval(value: Maybe<&2, V.Value>) -> Maybe<&2, U32>:
  match value:
    case Some{V.Number{number}}: intervalNumber(number)
    case Some{V.Text{text}}: intervalNumber(Number.parseFloat(String.trim(text)))
    case _: None{}

def deviceFields(id: Maybe<&2, String>, code: Maybe<&2, String>, interval: Maybe<&2, U32>, verificationUri: String) -> Result<&2, &2, String, DeviceCode>:
  match id code interval:
    case Some{id} Some{code} Some{interval}: Done{DeviceCode{id, code, U32.max(interval, 1), verificationUri}}
    case _ _ _: Fail{"Invalid OpenAI Codex device code response"}

def parsedDevice(value: Result<&2, &2, Json.ParseError, V.Value>, verificationUri: String) -> Result<&2, &2, String, DeviceCode>:
  match value:
    case Done{V.ObjectValue{+fields}}: deviceFields(nonemptyText(R.get(V.Value, fields, "device_auth_id")), nonemptyText(R.get(V.Value, fields, "user_code")), deviceInterval(R.get(V.Value, fields, "interval")), verificationUri)
    case _: Fail{"Invalid OpenAI Codex device code response"}

def startedStatus(+status: U32, +body: String, verificationUri: String) -> Result<&2, &2, String, DeviceCode>:
  match status:
    case 404: Fail{"OpenAI Codex device code login is not enabled for this server. Use browser login or verify the server URL."}
    case _: Bool.pick(Result<&2, &2, String, DeviceCode>, Response.successful(status), parsedDevice(Json.parse(body), verificationUri), Fail{"OpenAI Codex device code request failed with status " ++ U32.show(status) ++ ": " ++ body})

def started(result: Result<&2, &2, String, HttpText>, verificationUri: String) -> Result<&2, &2, String, DeviceCode>:
  match result:
    case Fail{error}: Fail{error}
    case Done{HttpText{status, body}}: startedStatus(status, body, verificationUri)

def startDevice(flow: Flow, endpoints: DeviceEndpoints, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, DeviceCode>):
  match flow endpoints:
    case Flow{fetch, context} DeviceEndpoints{userUrl, _, _, verificationUri}:
      do IO<Result<&2, &2, String, DeviceCode>>:
        response : Result<&2, &2, String, HttpText> <- post(fetch, context, userUrl, "application/json", "{\"client_id\":\"" ++ CLIENT_ID() ++ "\"}", signal)
        return started(response, verificationUri)

def authorizationFields(code: Maybe<&2, String>, verifier: Maybe<&2, String>) -> Result<&2, &2, String, AuthorizationCode>:
  match code verifier:
    case Some{code} Some{verifier}: Done{AuthorizationCode{code, verifier}}
    case _ _: Fail{"Invalid OpenAI Codex device auth token response"}

def authorization(value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, AuthorizationCode>:
  match value:
    case Done{V.ObjectValue{+fields}}: authorizationFields(nonemptyText(R.get(V.Value, fields, "authorization_code")), nonemptyText(R.get(V.Value, fields, "code_verifier")))
    case _: Fail{"Invalid OpenAI Codex device auth token response"}

type PollResult is Data:
  Pending{}
  SlowDown{}
  Authorized{value: AuthorizationCode}
  PollFailed{message: String}

def errorField(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case Some{V.ObjectValue{error}}: nonemptyText(R.get(V.Value, error, "code"))
    case _: None{}

def errorCode(value: Result<&2, &2, Json.ParseError, V.Value>) -> Maybe<&2, String>:
  match value:
    case Done{V.ObjectValue{fields}}: errorField(R.get(V.Value, fields, "error"))
    case _: None{}

def authorizedPoll(value: Result<&2, &2, String, AuthorizationCode>) -> PollResult:
  match value:
    case Done{code}: Authorized{code}
    case Fail{message}: PollFailed{message}

def failedPoll(status: U32, body: String, code: Maybe<&2, String>) -> PollResult:
  match code:
    case Some{"deviceauth_authorization_pending"}: Pending{}
    case Some{"slow_down"}: SlowDown{}
    case _: PollFailed{"OpenAI Codex device auth failed with status " ++ U32.show(status) ++ ": " ++ body}

def polledStatus(status: U32, +body: String, successful: Bool) -> PollResult:
  match successful:
    case True{}: authorizedPoll(authorization(Json.parse(body)))
    case False{}: failedPoll(status, body, errorCode(Json.parse(body)))

def polledHttp(+status: U32, body: String) -> PollResult:
  match status:
    case 403: Pending{}
    case 404: Pending{}
    case _: polledStatus(status, body, Response.successful(status))

def polled(result: Result<&2, &2, String, HttpText>) -> PollResult:
  match result:
    case Fail{error}: PollFailed{error}
    case Done{HttpText{status, body}}: polledHttp(status, body)

def pollBody(device: DeviceCode) -> String:
  match device:
    case DeviceCode{authId, userCode, _, _}:
      Maybe.default(&2, String, Encode.stringify(SchemaJson.toJson(V.ObjectValue{R.Record{[R.Property{"device_auth_id", V.Text{authId}}, R.Property{"user_code", V.Text{userCode}}]}})), "")

def polling(flow: Flow, endpoint: String, device: DeviceCode, signal: Abort.AbortSignal<Unit>) -> IO(PollResult):
  match flow:
    case Flow{fetch, context}:
      do IO<PollResult>:
        response : Result<&2, &2, String, HttpText> <- post(fetch, context, endpoint, "application/json", pollBody(device), signal)
        return polled(response)

def expiredMessage(slowed: Bool) -> String:
  Bool.pick(String, slowed, "Device flow timed out after one or more slow_down responses. Please check the server clock and try again.", "Device flow timed out")

type PollPlan is Data:
  PollPlan{completed: Maybe<&2, Result<&2, &2, String, AuthorizationCode>>, interval: U32, slowed: Bool}

def planPoll(outcome: PollResult, interval: U32, slowed: Bool) -> PollPlan:
  match outcome:
    case Authorized{value}: PollPlan{Some{Done{value}}, interval, slowed}
    case PollFailed{message}: PollPlan{Some{Fail{message}}, interval, slowed}
    case Pending{}: PollPlan{None{}, interval, slowed}
    case SlowDown{}: PollPlan{None{}, U32.min(60000, (interval + 5000 : U32)), True{}}

def planDone(plan: PollPlan) -> Bool:
  match plan:
    case PollPlan{Some{_}, _, _}: True{}
    case _: False{}

def planResult(plan: PollPlan) -> Result<&2, &2, String, AuthorizationCode>:
  match plan:
    case PollPlan{Some{result}, _, _}: result
    case _: Fail{"Device poll did not finish"}

def planInterval(plan: PollPlan) -> U32:
  match plan:
    case PollPlan{_, interval, _}: interval

def planSlowed(plan: PollPlan) -> Bool:
  match plan:
    case PollPlan{_, _, slowed}: slowed

def waitedOk(result: Result<&2, &2, Abort.AbortReason<Unit>, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def boundedWait(+deadline: F64, +now: F64, interval: U32) -> U32:
  Bool.pick(Unit -> U32, F.isAtLeast(F.compare(now, deadline)), _ => 0, _ => F64.to_u32(F.minimum(F.subtract(deadline, now), F.fromU32(interval))))(Unit{})

@unsafe def pollLoop(+flow: Flow, +endpoint: String, +device: DeviceCode, +signal: Abort.AbortSignal<Unit>, +deadline: F64, +interval: U32, +slowed: Bool) -> IO(Result<&2, &2, String, AuthorizationCode>):
  do IO<Result<&2, &2, String, AuthorizationCode>>:
    now : F64 <- Date.now()
    outcome : PollResult <- Bool.pick(Unit -> IO(PollResult), F.isAtLeast(F.compare(now, deadline)), _ => IO.pure(PollResult, PollFailed{expiredMessage(slowed)}), _ => polling(flow, endpoint, device, signal))(Unit{})
    +plan : PollPlan = planPoll(outcome, interval, slowed)
    Bool.pick(Unit -> IO(Result<&2, &2, String, AuthorizationCode>), planDone(plan), _ => IO.pure(Result<&2, &2, String, AuthorizationCode>, planResult(plan)), _ =>
      do IO<Result<&2, &2, String, AuthorizationCode>>:
        current : F64 <- Date.now()
        waited : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, boundedWait(deadline, current, planInterval(plan)), signal)
        Bool.pick(Unit -> IO(Result<&2, &2, String, AuthorizationCode>), waitedOk(waited), _ => pollLoop(flow, endpoint, device, signal, deadline, planInterval(plan), planSlowed(plan)), _ => IO.pure(Result<&2, &2, String, AuthorizationCode>, Fail{"Login cancelled"}))(Unit{}))(Unit{})

def pollDevice(flow: Flow, endpoints: DeviceEndpoints, +device: DeviceCode, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, AuthorizationCode>):
  match endpoints device:
    case DeviceEndpoints{_, endpoint, _, _} DeviceCode{_, _, +interval, _}:
      do IO<Result<&2, &2, String, AuthorizationCode>>:
        now : F64 <- Date.now()
        pollLoop(flow, endpoint, device, signal, F.add(now, F.fromU32(900000)), U32.max(1000, (interval * 1000 : U32)), False{})

def exchangeBody(code: AuthorizationCode) -> String:
  match code:
    case AuthorizationCode{code, verifier}:
      URL.toString(URL.append(URL.append(URL.append(URL.append(URL.append(URL.new(), "grant_type", "authorization_code"), "client_id", CLIENT_ID()), "code", code), "code_verifier", verifier), "redirect_uri", DEVICE_REDIRECT_URI()))

def exchangeStatus(now: F64, status: U32, +body: String, successful: Bool) -> Result<&2, &2, String, Auth.Credential>:
  match successful:
    case False{}: Fail{"OpenAI Codex token exchange failed (" ++ U32.show(status) ++ "): " ++ body}
    case True{}: refreshed(tokenFrom(now, body, Json.parse(body)))

def exchanged(now: F64, response: Result<&2, &2, String, HttpText>) -> Result<&2, &2, String, Auth.Credential>:
  match response:
    case Fail{error}: Fail{error}
    case Done{HttpText{+status, body}}: exchangeStatus(now, status, body, Response.successful(status))

def exchangeDevice(flow: Flow, endpoints: DeviceEndpoints, code: AuthorizationCode, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  match flow endpoints:
    case Flow{fetch, context} DeviceEndpoints{_, _, endpoint, _}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        response : Result<&2, &2, String, HttpText> <- post(fetch, context, endpoint, "application/x-www-form-urlencoded", exchangeBody(code), signal)
        now : F64 <- Date.now()
        return exchanged(now, response)

def refresh(flow: Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refreshToken, _, _, _}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        token : Result<&2, &2, String, OAuthToken> <- refreshAccessToken(flow, refreshToken, signal)
        return refreshed(token)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"OpenAI Codex refresh requires an OAuth credential"})

# The access token is the bearer key; the Codex API reads the account id from it.
def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"OpenAI Codex auth requires an OAuth credential"})

# The fetch callback is borrowed: retire the OAuthAuth before the fetch runtime.
def openaiCodexOAuth(fetch: Fetch.Fetch(Unit), url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, Flow{fetch, url})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"OpenAI (ChatGPT Plus/Pro)", True{}, None{}, refresher, deriver}
