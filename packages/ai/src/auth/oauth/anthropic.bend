import Base
import ./browser.bend as Browser
import ../types.bend as Auth
import ../../types.bend as T
import ../../utils/json.bend as Wire
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/deadline.bend as Deadline
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-exchange.bend as Exchange
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/http-response.bend as Response
import ../../../../runtime/src/json.bend as Json
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
type Request is Data:
  Request{url: URL.URL, headers: Headers.Headers, body: String}

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

def parsed(now: F64, value: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, Token>:
  match value:
    case Done{V.ObjectValue{+record}}: fields(now, nonempty(R.get(V.Value, record, "access_token")), nonempty(R.get(V.Value, record, "refresh_token")), R.get(V.Value, record, "expires_in"))
    case _: Fail{"Anthropic token response returned invalid JSON"}

def encoded(value: Maybe<&2, String>, url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, String, Request>:
  match value url headers:
    case None{} _ _: Fail{"Anthropic token payload could not be encoded"}
    case _ Fail{_} _: Fail{"Anthropic token endpoint URL is invalid"}
    case _ _ Fail{_}: Fail{"Anthropic token request headers are invalid"}
    case Some{body} Done{address} Done{headerFields}: Done{Request{address, headerFields, body}}

def request(url: URL.Context, tokenUrl: String, refresh: String) -> Result<&2, &2, String, Request>:
  +body = {T.JsonObject{R.Record{R.Property{"grant_type", T.JsonString{"refresh_token"}} <> R.Property{"client_id", T.JsonString{CLIENT_ID()}} <> R.Property{"refresh_token", T.JsonString{refresh}} <> Nil{}}} : T.JsonValue}
  encoded(Wire.stringify(body), URL.parse(url, tokenUrl), Headers.set(Headers.new(), "content-type", "application/json"))

def authorizationRequest(url: URL.Context, tokenUrl: String, code: String, +verifier: String) -> Result<&2,&2,String,Request>:
  +body = {T.JsonObject{R.Record{R.Property{"grant_type",T.JsonString{"authorization_code"}} <> R.Property{"client_id",T.JsonString{CLIENT_ID()}} <> R.Property{"code",T.JsonString{code}} <> R.Property{"state",T.JsonString{verifier}} <> R.Property{"redirect_uri",T.JsonString{REDIRECT_URI()}} <> R.Property{"code_verifier",T.JsonString{verifier}} <> Nil{}}} : T.JsonValue}
  encoded(Wire.stringify(body),URL.parse(url,tokenUrl),Headers.set(Headers.new(),"content-type","application/json"))

def readResult(result: Result<&2, &2, Response.TextError<Exchange.ReadError<Deadline.Cause<Unit>>>, String>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{_}: Fail{"Could not read Anthropic token response"}
    case Done{value}: Done{value}

def bodyText(body: Response.Body<Fetch.Transport(Unit)>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    result : Result<&2, &2, Response.TextError<Exchange.ReadError<Deadline.Cause<Unit>>>, String> <- Exchange.text(~(Deadline.Cause<Unit>), 65536n, body)
    return readResult(result)

def statusBody(body: Response.Body<Fetch.Transport(Unit)>, successful: Bool) -> IO(Result<&2, &2, String, String>):
  match successful:
    case True{}: bodyText(body)
    case False{}:
      do IO<Result<&2, &2, String, String>>:
        discarded : Result<&2, &2, String, String> <- bodyText(body)
        return Fail{"Anthropic token request was rejected"}

def responded(outcome: Fetch.Result_(Unit)) -> IO(Result<&2, &2, String, String>):
  match outcome:
    case Fail{_}: IO.pure(Result<&2, &2, String, String>, Fail{"Anthropic token request failed"})
    case Done{Response.Response{metadata, body}}: statusBody(body, Response.successful(Response.metadataStatus(metadata)))

def parsedResponse(now: F64, response: Result<&2, &2, String, String>) -> Result<&2, &2, String, Token>:
  match response:
    case Fail{error}: Fail{error}
    case Done{value}: parsed(now, Json.parse(value))

def fetched(fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), ready: Request) -> IO(Result<&2, &2, String, String>):
  match ready:
    case Request{url, headers, body}:
      do IO<Result<&2, &2, String, String>>:
        outcome : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, Fetch.Input{url, "POST", headers, Headers.Text{body}, signal})
        responded(outcome)

def scoped(fetch: Fetch.Fetch(Unit), ready: Request, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Result<&2, &2, String, String>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, String, String>>:
        result : Result<&2, &2, String, String> <- fetched(fetch, signal, ready)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        return result

def sent(flow: Flow, signal: Abort.AbortSignal<Unit>, prepared: Result<&2, &2, String, Request>) -> IO(Result<&2, &2, String, Token>):
  match flow prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Token>, Fail{error})
    case Flow{fetch, _, _} Done{ready}:
      do IO<Result<&2, &2, String, Token>>:
        scope : Deadline.Scope<Unit> <- Deadline.create(Unit, 30000, signal)
        response : Result<&2, &2, String, String> <- scoped(fetch, ready, Deadline.borrow(Unit, scope))
        now : F64 <- Date.now()
        return parsedResponse(now, response)

def refreshToken(flow: Flow, +refresh: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Token>):
  match flow:
    case Flow{fetch, +url, +tokenUrl}: sent(Flow{fetch, url, tokenUrl}, signal, request(url, tokenUrl, refresh))

def credential(value: Result<&2, &2, String, Token>) -> Result<&2, &2, String, Auth.Credential>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Token{access, refresh, expires}}: Done{Auth.OAuthCredential{refresh, access, expires, R.new(V.Value)}}

def exchangeCode(flow: Flow, code: String, verifier: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2,&2,String,Auth.Credential>):
  match flow:
    case Flow{fetch,+url,+tokenUrl}:
      do IO<Result<&2,&2,String,Auth.Credential>>:
        token : Result<&2,&2,String,Token> <- sent(Flow{fetch,url,tokenUrl},signal,authorizationRequest(url,tokenUrl,code,verifier))
        return credential(token)

def refresh(flow: Flow, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refreshValue, _, _, _}, signal}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        token : Result<&2, &2, String, Token> <- refreshToken(flow, refreshValue, signal)
        return credential(token)
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Anthropic refresh requires an OAuth credential"})

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"Anthropic auth requires an OAuth credential"})

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
        code : Browser.CodeResult() <- Browser.promptCode(Browser.CallbackConfig{REDIRECT_URI(),"/callback",verifier},listener,interaction,url,"Complete login in your browser, or paste the authorization code / redirect URL here:","Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.")
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
