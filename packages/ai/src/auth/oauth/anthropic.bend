import Base
import ./browser.bend as Browser
import ./oauth-http.bend as H
import ../../api/credential-http.bend as Http
import ../types.bend as Auth
import ../../types.bend as T
import ../../utils/json.bend as Wire
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/url.bend as URL

# Native Anthropic OAuth refresh and authorization-code exchange.
def CLIENT_ID() -> String: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
def TOKEN_URL() -> String: "https://platform.claude.com/v1/oauth/token"
def AUTHORIZE_URL() -> String: "https://claude.ai/oauth/authorize"
def REDIRECT_URI() -> String: "http://localhost:53692/callback"
def SCOPES() -> String: "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
type Authorization is Data: Authorization{url: String, verifier: String}

type Flow is Data:
  Flow{fetch: Fetch.Fetch(Unit), url: URL.Context, tokenUrl: String}

type Token is Data:
  Token{access: String, refresh: String, expires: F64}

def authorizationUrl(verifier: String, hashed: String) -> String:
  +params = URL.fromEntries(URL.Entry{"code","true"} <> URL.Entry{"client_id",CLIENT_ID()} <> URL.Entry{"response_type","code"} <> URL.Entry{"redirect_uri",REDIRECT_URI()} <> URL.Entry{"scope",SCOPES()} <> URL.Entry{"code_challenge",hashed} <> URL.Entry{"code_challenge_method","S256"} <> URL.Entry{"state",verifier} <> Nil{})
  AUTHORIZE_URL() ++ "?" ++ URL.toString(params)
def authorizationWith(+verifier: String, result: Result<&2,&2,String,String>) -> Result<&2,&2,String,Authorization>:
  match result:
    case Fail{error}: Fail{error}
    case Done{hashed}: Done{Authorization{authorizationUrl(verifier,hashed),verifier}}
def authorization(+verifier: String) -> Result<&2,&2,String,Authorization>: authorizationWith(verifier,Browser.challenge(verifier))
def pkceAuthorization(result: Result<&2,&2,String,Browser.PKCE>) -> Result<&2,&2,String,Authorization>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Browser.PKCE{+verifier,hashed}}: Done{Authorization{authorizationUrl(verifier,hashed),verifier}}
def beginAuthorization() -> IO(Result<&2,&2,String,Authorization>):
  do IO<Result<&2,&2,String,Authorization>>:
    pkce : Result<&2,&2,String,Browser.PKCE> <- Browser.generatePKCE()
    return pkceAuthorization(pkce)

def nonempty(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{first, rest}}}: Some{SCon{first, rest}}
    case _: None{}

def fields(now: F64, access: Maybe<&2, String>, refresh: Maybe<&2, String>, expires: Maybe<&2, V.Value>) -> Result<&2, &2, String, Token>:
  match access refresh expires:
    case Some{access} Some{refresh} Some{V.Number{seconds}}:
      Done{Token{access, refresh, F.subtract(F.add(now, F.multiply(seconds, F.fromU32(1000))), F.fromU32(300000))}}
    case _ _ _: Fail{"Anthropic token response missing fields"}

# Token requests
# --------------
# upstream postJson and its callers' error messages. A failed request's
# details are the error's `name: message`; upstream also appends the JS
# stack, which has no native counterpart. JSON syntax errors are engine
# messages upstream; here "SyntaxError: invalid JSON".
type TokenRequest is Data:
  Exchanging{redirectUri: String}
  Refreshing{}

def requestFailed(kind: TokenRequest, tokenUrl: String, details: String) -> String:
  match kind:
    case Exchanging{redirectUri}: "Token exchange request failed. url=" ++ tokenUrl ++ "; redirect_uri=" ++ redirectUri ++ "; response_type=authorization_code; details=" ++ details
    case Refreshing{}: "Anthropic token refresh request failed. url=" ++ tokenUrl ++ "; details=" ++ details

def invalidJson(kind: TokenRequest, tokenUrl: String, body: String) -> String:
  match kind:
    case Exchanging{_}: "Token exchange returned invalid JSON. url=" ++ tokenUrl ++ "; body=" ++ body ++ "; details=SyntaxError: invalid JSON"
    case Refreshing{}: "Anthropic token refresh returned invalid JSON. url=" ++ tokenUrl ++ "; body=" ++ body ++ "; details=SyntaxError: invalid JSON"

# The name of the error fetch rejects with.
def errorName(failure: Http.Failure) -> String:
  match failure:
    case Http.TimedOut{}: "TimeoutError"
    case Http.Aborted{}: "AbortError"
    case _: "TypeError"

def tokenOf(kind: TokenRequest, tokenUrl: String, now: F64, body: String, json: Maybe<&2, V.Value>) -> Result<&2, &2, String, Token>:
  match json:
    case Some{V.ObjectValue{+record}}: fields(now, nonempty(R.get(V.Value, record, "access_token")), nonempty(R.get(V.Value, record, "refresh_token")), R.get(V.Value, record, "expires_in"))
    case Some{_}: Fail{"Anthropic token response missing fields"}
    case None{}: Fail{invalidJson(kind, tokenUrl, body)}

def replied(+kind: TokenRequest, +tokenUrl: String, now: F64, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, Token>:
  match result:
    case Fail{+failure}: Fail{requestFailed(kind, tokenUrl, errorName(failure) ++ ": " ++ Http.failureText(failure))}
    case Done{H.Reply{+status, headers, +text, json}}:
      Bool.pick(Result<&2, &2, String, Token>, U32.is_ge(status, 200) && U32.is_lt(status, 300), tokenOf(kind, tokenUrl, now, text, json), Fail{requestFailed(kind, tokenUrl, "Error: HTTP request failed. status=" ++ U32.show(status) ++ "; url=" ++ tokenUrl ++ "; body=" ++ text)})

def postJson(flow: Flow, kind: TokenRequest, signal: Abort.AbortSignal<Unit>, body: Maybe<&2, String>) -> IO(Result<&2, &2, String, Token>):
  match flow body:
    case _ None{}: IO.pure(Result<&2, &2, String, Token>, Fail{"Anthropic token payload could not be encoded"})
    case Flow{fetch, url, +tokenUrl} Some{text}:
      do IO<Result<&2, &2, String, Token>>:
        result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(H.Flow{fetch, url}, signal, "POST", tokenUrl, [R.Property{"Content-Type", "application/json"}, R.Property{"Accept", "application/json"}], Headers.Text{text}, 30000)
        now : F64 <- Date.now()
        return replied(kind, tokenUrl, now, result)

def refreshBody(refresh: String) -> Maybe<&2, String>:
  Wire.stringify({T.JsonObject{R.Record{[R.Property{"grant_type", T.JsonString{"refresh_token"}}, R.Property{"client_id", T.JsonString{CLIENT_ID()}}, R.Property{"refresh_token", T.JsonString{refresh}}]}} : T.JsonValue})

def exchangeBody(code: String, +verifier: String) -> Maybe<&2, String>:
  Wire.stringify({T.JsonObject{R.Record{[R.Property{"grant_type", T.JsonString{"authorization_code"}}, R.Property{"client_id", T.JsonString{CLIENT_ID()}}, R.Property{"code", T.JsonString{code}}, R.Property{"state", T.JsonString{verifier}}, R.Property{"redirect_uri", T.JsonString{REDIRECT_URI()}}, R.Property{"code_verifier", T.JsonString{verifier}}]}} : T.JsonValue})

def credential(value: Result<&2, &2, String, Token>) -> Result<&2, &2, String, Auth.Credential>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Token{access, refresh, expires}}: Done{Auth.OAuthCredential{refresh, access, expires, R.new(V.Value)}}

def exchangeCode(flow: Flow, code: String, verifier: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2,&2,String,Auth.Credential>):
  do IO<Result<&2,&2,String,Auth.Credential>>:
    token : Result<&2,&2,String,Token> <- postJson(flow, Exchanging{REDIRECT_URI()}, signal, exchangeBody(code, verifier))
    return credential(token)

def refresh(flow: Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refreshValue, _, _, _}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        token : Result<&2, &2, String, Token> <- postJson(flow, Refreshing{}, signal, refreshBody(refreshValue))
        return credential(token)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Anthropic refresh requires an OAuth credential"})

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"Anthropic auth requires an OAuth credential"})

# upstream startCallbackServer's request handler: its pages, in its order of
# checks. An OAuth error, a missing code or state and a state mismatch leave
# the server waiting.
def stateChecked(+code: String, +received: String, state: String) -> Browser.CallbackReply:
  Bool.pick(Browser.CallbackReply,String.eq(received,state),Browser.completed("Anthropic authentication completed. You can close this window.",code),Browser.rejected(400,"State mismatch.",None{}))
def codeAndState(code: Maybe<&2,String>, received: Maybe<&2,String>, state: String) -> Browser.CallbackReply:
  match code received:
    case Some{value} Some{found}: stateChecked(value,found,state)
    case _ _: Browser.rejected(400,"Missing code or state parameter.",None{})
def errorChecked(error: Maybe<&2,String>, +params: URL.URLSearchParams, state: String) -> Browser.CallbackReply:
  match error:
    case Some{message}: Browser.rejected(400,"Anthropic authentication did not complete.",Some{"Error: " ++ message})
    case None{}: codeAndState(Browser.truthy(URL.get(params,"code")),Browser.truthy(URL.get(params,"state")),state)
def callbackReply(request: Browser.CallbackRequest) -> Browser.CallbackReply:
  match request:
    case Browser.CallbackRequest{+path,+params,state}: Bool.pick(Unit -> Browser.CallbackReply,String.eq(path,"/callback"),_ => errorChecked(Browser.truthy(URL.get(params,"error")),params,state),_ => Browser.rejected(404,"Callback route not found.",None{}))(Unit{})

def loginCode(flow: Flow,code: Browser.CodeResult(),verifier: String,notify: C.Callback<Auth.AuthEvent,Unit>,signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  match code:
    case Fail{message}: IO.pure(Auth.LoginOutcome(),Fail{message})
    case Done{value}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent,Unit,notify,Auth.ProgressEvent{"Exchanging authorization code for tokens..."})
        exchangeCode(flow,value,verifier,signal)
def loginStarted(flow: Flow,started: Result<&2,&2,String,Authorization>,+interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match started interaction:
    case Fail{message} _: IO.pure(Auth.LoginOutcome(),Fail{message})
    case Done{Authorization{url,+verifier}} Auth.ProviderAuthInteraction{signal,_,notify}:
      do IO<Auth.LoginOutcome()>:
        listener : Result<&1,&1,U32 & String,Listener> <- Browser.listenCallback(53692)
        code : Browser.CodeResult() <- Browser.promptCode(~callbackReply,Browser.CallbackConfig{REDIRECT_URI(),verifier},listener,interaction,url,"Complete login in your browser, or paste the authorization code / redirect URL here:","Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.")
        loginCode(flow,code,verifier,notify,signal)
def login(flow: Flow,interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    authorization : Result<&2,&2,String,Authorization> <- beginAuthorization()
    loginStarted(flow,authorization,interaction)

def anthropicOAuthWithTokenURL(+fetch: Fetch.Fetch(Unit), +url: URL.Context, +tokenUrl: String) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()> <- C.create(~Flow,~Auth.ProviderAuthInteraction,~Auth.LoginOutcome(),~login,Flow{fetch, url, tokenUrl})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Flow, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, Flow{fetch, url, tokenUrl})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"Anthropic (Claude Pro/Max)", True{}, None{}, authenticate, refresher, deriver}

def anthropicOAuth(fetch: Fetch.Fetch(Unit), url: URL.Context) -> IO(Auth.OAuthAuth):
  anthropicOAuthWithTokenURL(fetch, url, TOKEN_URL())
