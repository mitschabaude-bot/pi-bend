import Base
import ./browser.bend as Browser
import ./device-code.bend as Device
import ../types.bend as Auth
import ../../api/provider-fetch.bend as Http
import ../../providers/radius-config.bend as Config
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/deadline.bend as Deadline
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/http-response.bend as Response
import ../../../../runtime/src/json.bend as Json
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/utf8.bend as Utf8

# upstream auth/oauth/radius.ts: the Radius gateway OAuth flow. The OAuth
# client APIs live on the configured gateway; only the browser authorization
# endpoint is discovered (GET /v1/oauth). Browser login is PKCE with a local
# callback on 127.0.0.1:1456; device login polls the gateway's token endpoint
# (device-code.bend). The success/error pages are plain HTML with upstream's
# messages; upstream's styled oauth-page template is not ported.

def CALLBACK_HOST() -> String: "127.0.0.1"

def CALLBACK_PORT() -> U32: 1456

def CALLBACK_PATH() -> String: "/oauth/callback"

def REDIRECT_URI() -> String: "http://127.0.0.1:1456/oauth/callback"

def TOKEN_EXPIRY_SKEW_MS() -> F64: F.fromU32(60000)

def OAUTH_CLIENT_ID() -> String: "pi-gateway"

def OAUTH_SCOPE() -> String: "gateway offline_access"

def OAUTH_DEVICE_CODE_GRANT_TYPE() -> String: "urn:ietf:params:oauth:grant-type:device_code"

# The gateway, its HTTP client and the URL tables.
type Gateway is Data:
  Gateway{name: String, gateway: String, fetch: Fetch.Fetch(Unit), urlContext: URL.Context}

# HTTP
# ----

type HttpText is Data:
  HttpText{status: U32, body: String}

# A request failure: an OAuth error response, or any other thrown error.
type RequestError is Data:
  OAuthResponseError{status: U32, oauthError: Maybe<&2, String>, message: String}
  OtherError{message: String}

def errorMessage(error: RequestError) -> String:
  match error:
    case OAuthResponseError{_, _, message}: message
    case OtherError{message}: message

def bodyOf(text: Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String>) -> String:
  match text:
    case Done{body}: body
    case Fail{_}: ""

def responded(response: Fetch.Result_(Unit), aborted: Bool) -> IO(Result<&2, &2, RequestError, HttpText>):
  match response aborted:
    case Fail{_} True{}: IO.pure(Result<&2, &2, RequestError, HttpText>, Fail{OtherError{"Login cancelled"}})
    case Fail{_} False{}: IO.pure(Result<&2, &2, RequestError, HttpText>, Fail{OtherError{"fetch failed"}})
    case Done{Response.Response{+metadata, body}} _:
      do IO<Result<&2, &2, RequestError, HttpText>>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String> <- Http.responseText(~Unit, 16777216n, body)
        return Done{HttpText{Response.metadataStatus(metadata), bodyOf(text)}}

def exchanged(fetch: Fetch.Fetch(Unit), +parent: Abort.AbortSignal<Unit>, input: Fetch.Signal(Unit) -> Fetch.Input<Unit>, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Result<&2, &2, RequestError, HttpText>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, RequestError, HttpText>>:
        response : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, input(signal))
        aborted : Bool <- Abort.aborted(Unit, parent)
        result : Result<&2, &2, RequestError, HttpText> <- responded(response, aborted)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        return result

def send(fetch: Fetch.Fetch(Unit), +parent: Abort.AbortSignal<Unit>, input: Fetch.Signal(Unit) -> Fetch.Input<Unit>) -> IO(Result<&2, &2, RequestError, HttpText>):
  do IO<Result<&2, &2, RequestError, HttpText>>:
    scope : Deadline.Scope<Unit> <- Deadline.create(Unit, 4294967295, parent)
    exchanged(fetch, parent, input, Deadline.borrow(Unit, scope))

def validRequest(fetch: Fetch.Fetch(Unit), +parent: Abort.AbortSignal<Unit>, method: String, url: Result<&2, &2, String, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: Headers.Input) -> IO(Result<&2, &2, RequestError, HttpText>):
  match url headers:
    case Fail{message} _: IO.pure(Result<&2, &2, RequestError, HttpText>, Fail{OtherError{message}})
    case _ Fail{_}: IO.pure(Result<&2, &2, RequestError, HttpText>, Fail{OtherError{"Invalid header value"}})
    case Done{address} Done{fields}: send(fetch, parent, signal => Fetch.Input{address, method, fields, body, signal})

def formHeaders() -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  Http.headerList([R.Property{"accept", "application/json"}, R.Property{"content-type", "application/x-www-form-urlencoded"}])

def postForm(gateway: Gateway, path: String, form: List<&2, URL.Entry>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, RequestError, HttpText>):
  match gateway:
    case Gateway{_, base, fetch, context}: validRequest(fetch, signal, "POST", Config.gatewayUrl(context, base, path), formHeaders(), Headers.Text{URL.serializeSearchParams(form)})

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def ok(+status: U32) -> Bool: U32.is_ge(status, 200) && U32.is_lt(status, 300)

# `${error}: ${description}`, else the error, else the description or status.
def detail(status: U32, oauthError: Maybe<&2, String>, description: Maybe<&2, String>) -> String:
  match oauthError description:
    case Some{error} Some{text}: error ++ ": " ++ text
    case Some{error} None{}: error
    case None{} Some{SCon{c, cs}}: SCon{c, cs}
    case None{} _: U32.show(status)

def fromFields(+status: U32, message: String, +oauthError: Maybe<&2, String>, description: Maybe<&2, String>) -> RequestError:
  OAuthResponseError{status, oauthError, message ++ ": " ++ detail(status, oauthError, description)}

def parsedError(+status: U32, +message: String, +text: String, value: Result<&2, &2, Json.ParseError, V.Value>) -> RequestError:
  match value:
    case Done{+json}: fromFields(status, message, textOf(field(json, "error")), textOf(field(json, "error_description")))
    case Fail{_}: fromFields(status, message, None{}, Bool.pick(Maybe<&2, String>, String.is_empty(text), None{}, Some{text}))

# upstream readOAuthResponseError.
def readOAuthResponseError(response: HttpText, +message: String) -> RequestError:
  match response:
    case HttpText{+status, +body}: Bool.pick(RequestError, String.is_empty(body), fromFields(status, message, None{}, None{}), parsedError(status, message, body, Json.parse(body)))

# Tokens
# ------

def scopeExtra(scope: Maybe<&2, String>) -> R.Record<V.Value>:
  match scope:
    case Some{text}: R.Record{[R.Property{"scope", V.Text{text}}]}
    case None{}: R.new(V.Value)

def tokenFields(now: F64, access: Maybe<&2, String>, refreshed: Maybe<&2, String>, expires: Maybe<&2, F64>, scope: Maybe<&2, String>) -> Result<&2, &2, RequestError, Auth.Credential>:
  match access refreshed expires:
    case Some{a} Some{r} Some{seconds}: Done{Auth.OAuthCredential{r, a, F.subtract(F.add(now, F.multiply(seconds, F.fromU32(1000))), TOKEN_EXPIRY_SKEW_MS()), scopeExtra(scope)}}
    case _ _ _: Fail{OtherError{"Radius OAuth token response is missing required fields"}}

def tokenJson(now: F64, value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, RequestError, Auth.Credential>:
  match value:
    case Done{+json}: tokenFields(now, textOf(field(json, "access_token")), textOf(field(json, "refresh_token")), numberOf(field(json, "expires_in")), textOf(field(json, "scope")))
    case Fail{_}: Fail{OtherError{"Radius OAuth token response is not valid JSON"}}

def tokenResponse(now: F64, response: Result<&2, &2, RequestError, HttpText>) -> Result<&2, &2, RequestError, Auth.Credential>:
  match response:
    case Fail{error}: Fail{error}
    case Done{HttpText{+status, +body}}: Bool.pick(Unit -> Result<&2, &2, RequestError, Auth.Credential>, ok(status), _ => tokenJson(now, Json.parse(body)), _ => Fail{readOAuthResponseError(HttpText{status, body}, "Radius OAuth token request failed")})(Unit{})

# upstream requestOAuthToken: POST /v1/oauth/token.
def requestOAuthToken(gateway: Gateway, form: List<&2, URL.Entry>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, RequestError, Auth.Credential>):
  do IO<Result<&2, &2, RequestError, Auth.Credential>>:
    response : Result<&2, &2, RequestError, HttpText> <- postForm(gateway, "/v1/oauth/token", form, signal)
    now : F64 <- Date.now()
    return tokenResponse(now, response)

def plainError(-A: Data, result: Result<&2, &2, RequestError, A>) -> Result<&2, &2, String, A>:
  match result:
    case Fail{error}: Fail{errorMessage(error)}
    case Done{value}: Done{value}

def refresh(gateway: Gateway, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refreshToken, _, _, _}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        token : Result<&2, &2, RequestError, Auth.Credential> <- requestOAuthToken(gateway, [URL.Entry{"grant_type", "refresh_token"}, URL.Entry{"client_id", OAUTH_CLIENT_ID()}, URL.Entry{"refresh_token", refreshToken}], signal)
        return plainError(Auth.Credential, token)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Radius refresh requires an OAuth credential"})

# Device login
# ------------

type DeviceAuthorization is Data:
  DeviceAuthorization{deviceCode: String, userCode: String, verificationUri: String, expiresIn: F64, interval: Maybe<&2, F64>}

def truthyNumber(value: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match value:
    case Some{+n}: Bool.pick(Maybe<&2, F64>, F.isNaN(n) || F.isEqual(F.compare(n, F.fromU32(0))), None{}, Some{n})
    case None{}: None{}

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def deviceFields(code: Maybe<&2, String>, user: Maybe<&2, String>, uri: Maybe<&2, String>, expires: Maybe<&2, F64>, interval: Maybe<&2, F64>) -> Result<&2, &2, String, DeviceAuthorization>:
  match code user uri expires:
    case Some{a} Some{b} Some{c} Some{d}: Done{DeviceAuthorization{a, b, c, d, interval}}
    case _ _ _ _: Fail{"Radius OAuth device authorization response is missing required fields"}

def deviceJson(value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, DeviceAuthorization>:
  match value:
    case Done{+json}: deviceFields(nonempty(textOf(field(json, "device_code"))), nonempty(textOf(field(json, "user_code"))), nonempty(textOf(field(json, "verification_uri"))), truthyNumber(numberOf(field(json, "expires_in"))), numberOf(field(json, "interval")))
    case Fail{_}: Fail{"Radius OAuth device authorization response is not valid JSON"}

def deviceResponse(response: Result<&2, &2, RequestError, HttpText>) -> Result<&2, &2, String, DeviceAuthorization>:
  match response:
    case Fail{error}: Fail{errorMessage(error)}
    case Done{HttpText{+status, +body}}: Bool.pick(Unit -> Result<&2, &2, String, DeviceAuthorization>, ok(status), _ => deviceJson(Json.parse(body)), _ => Fail{errorMessage(readOAuthResponseError(HttpText{status, body}, "Radius OAuth device authorization failed"))})(Unit{})

def requestDeviceAuthorization(gateway: Gateway, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, DeviceAuthorization>):
  do IO<Result<&2, &2, String, DeviceAuthorization>>:
    response : Result<&2, &2, RequestError, HttpText> <- postForm(gateway, "/v1/oauth/device", [URL.Entry{"client_id", OAUTH_CLIENT_ID()}, URL.Entry{"scope", OAUTH_SCOPE()}], signal)
    return deviceResponse(response)

type Poller is Data:
  Poller{gateway: Gateway, deviceCode: String, signal: Abort.AbortSignal<Unit>}

def pollOutcome(result: Result<&2, &2, RequestError, Auth.Credential>) -> Result<&2, &2, String, Device.OAuthDeviceCodePollResult<Auth.Credential>>:
  match result:
    case Done{credential}: Done{Device.PollComplete{credential}}
    case Fail{OAuthResponseError{_, Some{"authorization_pending"}, _}}: Done{Device.PollPending{}}
    case Fail{OAuthResponseError{_, Some{"slow_down"}, _}}: Done{Device.PollSlowDown{None{}}}
    case Fail{OAuthResponseError{_, Some{"expired_token"}, _}}: Done{Device.PollFailed{"Device authorization expired."}}
    case Fail{OAuthResponseError{_, Some{"access_denied"}, _}}: Done{Device.PollFailed{"Device authorization was denied."}}
    case Fail{error}: Fail{errorMessage(error)}

# A thrown poll error ends the flow with its message.
def asPoll(result: Result<&2, &2, String, Device.OAuthDeviceCodePollResult<Auth.Credential>>) -> Device.OAuthDeviceCodePollResult<Auth.Credential>:
  match result:
    case Done{value}: value
    case Fail{message}: Device.PollFailed{message}

def pollOnce(poller: Poller, unused: Unit) -> IO(Device.OAuthDeviceCodePollResult<Auth.Credential>):
  match poller:
    case Poller{gateway, code, signal}:
      do IO<Device.OAuthDeviceCodePollResult<Auth.Credential>>:
        result : Result<&2, &2, RequestError, Auth.Credential> <- requestOAuthToken(gateway, [URL.Entry{"grant_type", OAUTH_DEVICE_CODE_GRANT_TYPE()}, URL.Entry{"client_id", OAUTH_CLIENT_ID()}, URL.Entry{"device_code", code}], signal)
        return asPoll(pollOutcome(result))

def notify(interaction: Auth.ProviderAuthInteraction, event: Auth.AuthEvent) -> IO(Unit):
  match interaction:
    case Auth.ProviderAuthInteraction{_, _, callback}: C.call(Auth.AuthEvent, Unit, callback, event)

def signalOf(interaction: Auth.ProviderAuthInteraction) -> Abort.AbortSignal<Unit>:
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}: signal

def deviceStarted(gateway: Gateway, +interaction: Auth.ProviderAuthInteraction, device: Result<&2, &2, String, DeviceAuthorization>) -> IO(Auth.LoginOutcome()):
  match device:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{DeviceAuthorization{code, user, uri, +expires, +interval}}:
      do IO<Auth.LoginOutcome()>:
        notify(interaction, Auth.DeviceCodeEvent{user, uri, interval, Some{expires}})
        +poll : C.Callback<Unit, Device.OAuthDeviceCodePollResult<Auth.Credential>> <- C.create(~Poller, ~Unit, ~(Device.OAuthDeviceCodePollResult<Auth.Credential>), ~pollOnce, Poller{gateway, code, signalOf(interaction)})
        result : Result<&2, &2, String, Auth.Credential> <- Device.pollOAuthDeviceCodeFlow(~Auth.Credential, Device.OAuthDeviceCodePollOptions{interval, Some{expires}, False{}, poll, signalOf(interaction)})
        C.dispose(Unit, Device.OAuthDeviceCodePollResult<Auth.Credential>, poll)
        return result

def loginWithDeviceCode(+gateway: Gateway, +interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    device : Result<&2, &2, String, DeviceAuthorization> <- requestDeviceAuthorization(gateway, signalOf(interaction))
    deviceStarted(gateway, interaction, device)

# Browser login
# -------------

def endpointText(gateway: String, value: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match value:
    case Some{endpoint}: Done{endpoint}
    case None{}: Fail{"Invalid Radius OAuth config from " ++ gateway}

def endpointOf(gateway: String, value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, String>:
  match value:
    case Done{+json}: endpointText(gateway, textOf(field(json, "authorizationEndpoint")))
    case Fail{_}: Fail{"Invalid Radius OAuth config from " ++ gateway}

def discovered(+gateway: String, response: Result<&2, &2, RequestError, HttpText>) -> Result<&2, &2, String, String>:
  match response:
    case Fail{error}: Fail{errorMessage(error)}
    case Done{HttpText{+status, +body}}: Bool.pick(Unit -> Result<&2, &2, String, String>, ok(status), _ => endpointOf(gateway, Json.parse(body)), _ => Fail{"Could not load Radius OAuth config from " ++ gateway ++ ": " ++ U32.show(status) ++ " " ++ body})(Unit{})

def jsonHeaders() -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>: Http.headerList([R.Property{"accept", "application/json"}])

# upstream loadRadiusOAuthDiscovery: GET /v1/oauth.
def loadRadiusOAuthDiscovery(gateway: Gateway, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, String>):
  match gateway:
    case Gateway{_, +base, fetch, context}:
      do IO<Result<&2, &2, String, String>>:
        response : Result<&2, &2, RequestError, HttpText> <- validRequest(fetch, signal, "GET", Config.gatewayUrl(context, base, "/v1/oauth"), jsonHeaders(), Headers.Absent{})
        return discovered(base, response)

def hexDigit(+value: U32) -> Char: Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hex(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +b <> rest: SCon{hexDigit(U32.div(b, 16)), SCon{hexDigit(U32.mod(b, 16)), hex(rest)}}

def uuidVersion(bytes: List<&2, U32>, +index: Nat) -> List<&2, U32>:
  match bytes:
    case Nil{}: Nil{}
    case +b <> rest: Bool.pick(U32, Nat.is_eq(index, 6n), U32.or(U32.and(b, 15), 64), Bool.pick(U32, Nat.is_eq(index, 8n), U32.or(U32.and(b, 63), 128), b)) <> uuidVersion(rest, 1n + index)

# crypto.randomUUID(): a version 4 UUID in 8-4-4-4-12 form.
def uuid(bytes: List<&2, U32>) -> String:
  +text = hex(uuidVersion(bytes, 0n))
  String.take(text, 8n) ++ "-" ++ String.take(String.drop(text, 8n), 4n) ++ "-" ++ String.take(String.drop(text, 12n), 4n) ++ "-" ++ String.take(String.drop(text, 16n), 4n) ++ "-" ++ String.drop(text, 20n)

def withoutQuery(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'?', _}: SNil{}
    case SCon{'#', _}: SNil{}
    case SCon{c, rest}: SCon{c, withoutQuery(rest)}

def fragmentOf(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'#', rest}: SCon{'#', rest}
    case SCon{_, rest}: fragmentOf(rest)

def authorizeUrl(+endpoint: String, challenge: String, state: String) -> String:
  withoutQuery(endpoint) ++ "?" ++ URL.serializeSearchParams([URL.Entry{"response_type", "code"}, URL.Entry{"client_id", OAUTH_CLIENT_ID()}, URL.Entry{"redirect_uri", REDIRECT_URI()}, URL.Entry{"scope", OAUTH_SCOPE()}, URL.Entry{"code_challenge", challenge}, URL.Entry{"code_challenge_method", "S256"}, URL.Entry{"handoff", "url"}, URL.Entry{"state", state}]) ++ fragmentOf(endpoint)

# The callback server
# -------------------

# A request's outcome: the code, a rejected request (the server keeps
# waiting), or an OAuth error that ends the wait without a code.
type Callback is Data:
  CallbackCode{code: String}
  CallbackRejected{status: U32, message: String}
  CallbackError{message: String}

def page(title: String, message: String) -> String: "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\" /><title>" ++ title ++ "</title></head><body><p>" ++ message ++ "</p></body></html>"

def escapedChar(+c: Char) -> String:
  +code = Char.to_u32(c)
  Bool.pick(String, U32.is_eq(code, 38), "&amp;", Bool.pick(String, U32.is_eq(code, 60), "&lt;", Bool.pick(String, U32.is_eq(code, 62), "&gt;", Bool.pick(String, U32.is_eq(code, 34), "&quot;", Bool.pick(String, U32.is_eq(code, 39), "&#39;", SCon{c, SNil{}})))))

def escaped(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{c, rest}: escapedChar(c) ++ escaped(rest)

def reason(+status: U32) -> String: Bool.pick(String, U32.is_eq(status, 200), "OK", Bool.pick(String, U32.is_eq(status, 404), "Not Found", "Bad Request"))

def httpPage(+status: U32, +html: String) -> String:
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ reason(status) ++ "\r\ncontent-type: text/html; charset=utf-8\r\nContent-Length: " ++ Nat.show(List.length(&2, U32, Utf8.encode(html))) ++ "\r\nConnection: close\r\n\r\n" ++ html

def errorPage(message: String) -> String: page("Authentication failed", escaped(message))

def successPage() -> String: page("Authentication successful", "Signed in to Radius. You may now close this page.")

def codeOf(code: Maybe<&2, String>) -> Callback:
  match code:
    case Some{SCon{c, cs}}: CallbackCode{SCon{c, cs}}
    case _: CallbackRejected{400, "Missing authorization code."}

def errorChecked(+params: URL.URLSearchParams, error: Maybe<&2, String>) -> Callback:
  match error:
    case Some{SCon{c, cs}}: CallbackError{Maybe.default(&2, String, URL.get(params, "error_description"), SCon{c, cs})}
    case _: codeOf(URL.get(params, "code"))

def afterState(+params: URL.URLSearchParams) -> Callback: errorChecked(params, URL.get(params, "error"))

def stateChecked(+params: URL.URLSearchParams, received: Maybe<&2, String>, state: String) -> Callback:
  match received:
    case Some{value}: Bool.pick(Unit -> Callback, String.eq(value, state), _ => afterState(params), _ => CallbackRejected{400, "OAuth state mismatch."})(Unit{})
    case None{}: CallbackRejected{400, "OAuth state mismatch."}

def paramsCallback(+params: URL.URLSearchParams, state: String) -> Callback: stateChecked(params, URL.get(params, "state"), state)

def splitTarget(target: String, reversed: String) -> String & String:
  match target:
    case SNil{}: (String.reverse(reversed), "")
    case SCon{'?', rest}: (String.reverse(reversed), rest)
    case SCon{c, rest}: splitTarget(rest, SCon{c, reversed})

def targetCallback(pair: String & String, state: String) -> Callback:
  match pair:
    case (+path, query): Bool.pick(Unit -> Callback, String.eq(path, CALLBACK_PATH()), _ => paramsCallback(URL.parseSearchParams(query), state), _ => CallbackRejected{404, "Callback route not found."})(Unit{})

def lineCallback(parts: List<&2, String>, state: String) -> Callback:
  match parts:
    case _ <> target <> _: targetCallback(splitTarget(target, ""), state)
    case _: CallbackRejected{400, "Callback route not found."}

type Step is Type:
  Listening{listener: Listener}
  Checked{listener: Listener, done: Bool}
  Accepted{pair: Listener & Result<&1, &1, U32 & String, Socket>}
  Reading{listener: Listener, socket: Socket, bytes: List<&2, U32>}
  Readable{listener: Listener, pair: Socket & Result<&1, &1, U32 & String, Bool>, bytes: List<&2, U32>}
  Received{listener: Listener, pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, bytes: List<&2, U32>}
  Answered{listener: Listener, socket: Socket, callback: Callback}

def respond(socket: Socket, response: String) -> IO(Unit):
  do IO<Unit>:
    pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, response)
    Browser.closeCallbackWrite(pair)

def settle(answer: Deferred.Deferred<Maybe<&2, String>>, +code: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    settled : Bool <- Deferred.resolve(Maybe<&2, String>, answer, code)
    return Unit{}

def finishedWait(answer: Deferred.Deferred<Maybe<&2, String>>, signal: Abort.AbortSignal<Unit>) -> IO(Bool):
  do IO<Bool>:
    current : Maybe<&2, Maybe<&2, String>> <- Deferred.peek(Maybe<&2, String>, answer)
    stopped : Bool <- Abort.aborted(Unit, signal)
    return Maybe.is_some(&2, Maybe<&2, String>, current) || stopped

def lined(listener: Listener, socket: Socket, bytes: List<&2, U32>, line: Maybe<&2, String>, state: String) -> Step:
  match line:
    case Some{text}: Answered{listener, socket, lineCallback(Strings.split(text, ' '), state)}
    case None{}: Reading{listener, socket, bytes}

@unsafe def serve(step: Step, +answer: Deferred.Deferred<Maybe<&2, String>>, +state: String, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match step:
    case Listening{+listener}:
      do IO<Unit>:
        done : Bool <- finishedWait(answer, signal)
        serve(Checked{listener, done}, answer, state, signal)
    case Checked{+listener, True{}}:
      do IO<Unit>:
        Listener.close(listener)
        settle(answer, None{})
    case Checked{+listener, False{}}:
      do IO<Unit>:
        pair : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept_try(listener)
        serve(Accepted{pair}, answer, state, signal)
    case Accepted{(listener, Fail{(11, _)})}:
      do IO<Unit>:
        IO.sleep(30)
        serve(Listening{listener}, answer, state, signal)
    case Accepted{(listener, Fail{_})}:
      do IO<Unit>:
        Listener.close(listener)
        settle(answer, None{})
    case Accepted{(listener, Done{+socket})}: serve(Reading{listener, socket, Nil{}}, answer, state, signal)
    case Reading{+listener, +socket, bytes}:
      do IO<Unit>:
        done : Bool <- finishedWait(answer, signal)
        Bool.pick(Unit -> IO(Unit), done, _ =>
          do IO<Unit>:
            Socket.close(socket)
            serve(Checked{listener, True{}}, answer, state, signal), _ =>
          do IO<Unit>:
            pair : Socket & Result<&1, &1, U32 & String, Bool> <- TCP.readable(socket)
            serve(Readable{listener, pair, bytes}, answer, state, signal))(Unit{})
    case Readable{+listener, (socket, Done{False{}}), bytes}:
      do IO<Unit>:
        IO.sleep(30)
        serve(Reading{listener, socket, bytes}, answer, state, signal)
    case Readable{+listener, (socket, Fail{_}), _}:
      do IO<Unit>:
        Socket.close(socket)
        serve(Listening{listener}, answer, state, signal)
    case Readable{+listener, (socket, Done{True{}}), bytes}:
      do IO<Unit>:
        pair : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 4096)
        serve(Received{listener, pair, bytes}, answer, state, signal)
    case Received{+listener, (socket, Fail{_}), _}:
      do IO<Unit>:
        Socket.close(socket)
        serve(Listening{listener}, answer, state, signal)
    case Received{+listener, (socket, Done{Nil{}}), _}:
      do IO<Unit>:
        Socket.close(socket)
        serve(Listening{listener}, answer, state, signal)
    case Received{+listener, (socket, Done{chunk}), bytes}:
      +joined = List.append(&2, U32, bytes, chunk)
      serve(lined(listener, socket, joined, Browser.callbackLine(joined), state), answer, state, signal)
    case Answered{+listener, +socket, CallbackRejected{status, message}}:
      do IO<Unit>:
        respond(socket, httpPage(status, errorPage(message)))
        serve(Listening{listener}, answer, state, signal)
    case Answered{+listener, +socket, CallbackError{message}}:
      do IO<Unit>:
        respond(socket, httpPage(400, errorPage(message)))
        Listener.close(listener)
        settle(answer, None{})
    case Answered{+listener, +socket, CallbackCode{code}}:
      do IO<Unit>:
        respond(socket, httpPage(200, successPage()))
        Listener.close(listener)
        settle(answer, Some{code})

def listening(listener: Result<&1, &1, U32 & String, Listener>, +answer: Deferred.Deferred<Maybe<&2, String>>, +state: String, +signal: Abort.AbortSignal<Unit>) -> IO(Maybe<&1, Chan(Unit)>):
  match listener:
    case Fail{_}:
      do IO<Maybe<&1, Chan(Unit)>>:
        settle(answer, None{})
        return None{}
    case Done{socket}:
      do IO<Maybe<&1, Chan(Unit)>>:
        worker : Chan(Unit) <- IO.fork(Unit, serve(Listening{socket}, answer, state, signal))
        return Some{worker}

def exchangeCode(gateway: Gateway, code: Maybe<&2, String>, verifier: String, aborted: Bool, signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  match code:
    case None{}: IO.pure(Auth.LoginOutcome(), Fail{Bool.pick(String, aborted, "Login cancelled", "OAuth callback did not complete.")})
    case Some{value}:
      do IO<Auth.LoginOutcome()>:
        token : Result<&2, &2, RequestError, Auth.Credential> <- requestOAuthToken(gateway, [URL.Entry{"grant_type", "authorization_code"}, URL.Entry{"client_id", OAUTH_CLIENT_ID()}, URL.Entry{"redirect_uri", REDIRECT_URI()}, URL.Entry{"code", value}, URL.Entry{"code_verifier", verifier}], signal)
        return plainError(Auth.Credential, token)

def joinWorker(worker: Maybe<&1, Chan(Unit)>) -> IO(Unit):
  match worker:
    case None{}: IO.pure(Unit, Unit{})
    case Some{task}: IO.join(Unit, task)

def browserReady(gateway: Gateway, +endpoint: String, +interaction: Auth.ProviderAuthInteraction, pkce: Result<&2, &2, String, Browser.PKCE>, random: Result<&2, &2, String, List<&2, U32>>) -> IO(Auth.LoginOutcome()):
  match pkce random:
    case Fail{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case _ Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{Browser.PKCE{verifier, challenge}} Done{bytes}:
      +state = uuid(bytes)
      do IO<Auth.LoginOutcome()>:
        +answer : Deferred.Deferred<Maybe<&2, String>> <- Deferred.new(Maybe<&2, String>)
        +stop : Abort.AbortController<Unit> <- Abort.new(Unit)
        link : Abort.Link<Unit> <- Abort.link(Unit, signalOf(interaction), stop)
        listener : Result<&1, &1, U32 & String, Listener> <- TCP.listen_host(CALLBACK_HOST(), CALLBACK_PORT())
        worker : Maybe<&1, Chan(Unit)> <- listening(listener, answer, state, Abort.signal(Unit, stop))
        notify(interaction, Auth.ProgressEvent{"Listening for OAuth callback on " ++ REDIRECT_URI()})
        notify(interaction, Auth.AuthUrlEvent{authorizeUrl(endpoint, challenge, state), Some{"Continue in your browser."}})
        code : Maybe<&2, String> <- Deferred.result(Maybe<&2, String>, answer)
        aborted : Bool <- Abort.aborted(Unit, signalOf(interaction))
        stopped : Bool <- Abort.abort(Unit, stop, None{})
        joinWorker(worker)
        Abort.unlink(Unit, link)
        Abort.dispose(Unit, stop)
        Deferred.dispose(Maybe<&2, String>, answer)
        exchangeCode(gateway, code, verifier, aborted, signalOf(interaction))

def loginWithBrowser(gateway: Gateway, +endpoint: String, +interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    pkce : Result<&2, &2, String, Browser.PKCE> <- Browser.generatePKCE()
    random : Result<&2, &2, String, List<&2, U32>> <- Browser.randomBytes(16)
    browserReady(gateway, endpoint, interaction, pkce, random)

def discoveredLogin(gateway: Gateway, +interaction: Auth.ProviderAuthInteraction, discovery: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match discovery:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{endpoint}: loginWithBrowser(gateway, endpoint, interaction)

# OAuthAuth
# ---------

def gatewayName(gateway: Gateway) -> String:
  match gateway:
    case Gateway{name, _, _, _}: name

def methodChosen(+gateway: Gateway, +interaction: Auth.ProviderAuthInteraction, method: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match method:
    case Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{"device-code"}: loginWithDeviceCode(gateway, interaction)
    case Done{"browser"}:
      do IO<Auth.LoginOutcome()>:
        discovery : Result<&2, &2, String, String> <- loadRadiusOAuthDiscovery(gateway, signalOf(interaction))
        discoveredLogin(gateway, interaction, discovery)
    case Done{other}: IO.pure(Auth.LoginOutcome(), Fail{"Unknown " ++ gatewayName(gateway) ++ " sign-in method: " ++ other})

def loginRun(+gateway: Gateway, +interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{signal, prompt, notifier}:
      do IO<Auth.LoginOutcome()>:
        method : Result<&2, &2, String, String> <- C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt, Auth.SelectPrompt{"Sign in to " ++ gatewayName(gateway) ++ ":", [Auth.AuthSelectOption{"browser", "Sign in with browser (recommended)", None{}}, Auth.AuthSelectOption{"device-code", "Sign in with device code (when signing in from another device)", None{}}], None{}})
        methodChosen(gateway, Auth.ProviderAuthInteraction{signal, prompt, notifier}, method)

def login(gateway: Gateway, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginRun(gateway, interaction)

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"Radius auth requires an OAuth credential"})

# upstream createRadiusOAuth. The fetch callback is borrowed: retire the
# OAuthAuth before the fetch runtime.
def createRadiusOAuth(+name: String, gateway: String, fetch: Fetch.Fetch(Unit), urlContext: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    +selected : Gateway <- IO.pure(Gateway, Gateway{name, Config.normalizeRadiusGatewayUrl(gateway), fetch, urlContext})
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Gateway, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, selected)
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Gateway, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, selected)
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{name, False{}, None{}, authenticate, refresher, deriver}
