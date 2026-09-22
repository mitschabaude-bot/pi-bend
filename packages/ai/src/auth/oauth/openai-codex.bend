import Base
import ../types.bend as Auth
import ../../types.bend as T
import ../../api/openai-client.bend as Client
import ../../api/openai-responses.bend as Responses
import ../../utils/provider-retry.bend as Retry
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/http-response.bend as Response
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/json.bend as Json
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/base64.bend as Base64
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/date.bend as Date

# OpenAI Codex (ChatGPT OAuth): token refresh and request auth derivation
# through the native HTTPS client. The browser and device-code login flows
# (local callback server, PKCE) are not ported yet; credentials come from
# auth.json written by pi.

def CLIENT_ID() -> String: "app_EMoamEEZ73f0CkXaXp7hrann"
def TOKEN_URL() -> String: "https://auth.openai.com/oauth/token"
def JWT_CLAIM_PATH() -> String: "https://api.openai.com/auth"
def REFRESH_TIMEOUT_MS() -> F64: F.fromU32(15000)

type Flow is Data:
  Flow{fetch: Fetch.Fetch(Unit), url: URL.Context}

# JWT payload
# -----------

# JWT segments are base64url without padding; atob-style decoding expects the
# standard alphabet, so translate before decoding.
def standardAlphabet(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'-', rest}: SCon{'+', standardAlphabet(rest)}
    case SCon{'_', rest}: SCon{'/', standardAlphabet(rest)}
    case SCon{c, rest}: SCon{c, standardAlphabet(rest)}

def padding(remainder: Nat) -> String:
  match remainder:
    case 2n: "=="
    case 3n: "="
    case _: ""

def padded(+text: String) -> String:
  text ++ padding(Nat.mod(String.length(text), 4n))

def parsedJson(text: Result<&2, &2, Utf8.Error, String>) -> Maybe<&2, V.Value>:
  match text:
    case Fail{_}: None{}
    case Done{value}: Result.default(&2, &2, Json.ParseError, Maybe<&2, V.Value>, Result.map(&2, &2, Json.ParseError, V.Value, Maybe<&2, V.Value>, value => Some{value}, Json.parse(value)), None{})

def decodedJson(bytes: Result<&2, &2, Base64.Error, List<&2, U32>>) -> Maybe<&2, V.Value>:
  match bytes:
    case Fail{_}: None{}
    case Done{octets}: parsedJson(Utf8.decodeStrict(octets))

def payloadSegment(segments: List<&2, String>) -> Maybe<&2, String>:
  match segments:
    case _ <> payload <> _ <> Nil{}: Some{payload}
    case _: None{}

def decodeSegment(segment: Maybe<&2, String>) -> Maybe<&2, V.Value>:
  match segment:
    case None{}: None{}
    case Some{payload}: decodedJson(Base64.decode(padded(standardAlphabet(payload))))

def decodeJwt(token: String) -> Maybe<&2, V.Value>:
  decodeSegment(payloadSegment(Strings.split(token, '.')))

def nonemptyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{first, rest}}}: Some{SCon{first, rest}}
    case _: None{}

def claimField(claims: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match claims:
    case Some{V.ObjectValue{fields}}: nonemptyText(R.get(V.Value, fields, "chatgpt_account_id"))
    case _: None{}

def accountClaim(payload: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match payload:
    case Some{V.ObjectValue{fields}}: claimField(R.get(V.Value, fields, JWT_CLAIM_PATH()))
    case _: None{}

def getAccountId(accessToken: String) -> Maybe<&2, String>:
  accountClaim(decodeJwt(accessToken))

# Token responses
# ---------------

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
    case Done{request}:
      do IO<Result<&2, &2, String, OAuthToken>>:
        outcome : Client.Outcome(Unit) <- Client.attempt(~Unit, request, signal, fetch, 65536n)
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
