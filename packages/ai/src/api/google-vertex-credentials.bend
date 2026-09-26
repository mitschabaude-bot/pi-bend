import Base
import ../types.bend as T
import ../utils/provider-env.bend as Env
import ../utils/headers.bend as HeaderUtils
import ./provider-fetch.bend as Http
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8

# The part of google-auth-library 10.6.2's Application Default Credentials
# that @google/genai uses for Vertex AI without an API key: the credentials
# file (pi's GOOGLE_APPLICATION_CREDENTIALS keyFilename, else the
# well-known gcloud file), an "authorized_user" refresh-token exchange at the
# OAuth2 token endpoint, and the request headers it yields. Service accounts,
# impersonation, external accounts and the Compute Engine metadata server are
# not provided; a credentials file of those types reports that, and without a
# file the library's "no ADC found" error is reported.

def NO_ADC_FOUND() -> String: "Could not load the default credentials. Browse to https://cloud.google.com/docs/authentication/getting-started for more information."

def TOKEN_URL() -> String: "https://oauth2.googleapis.com/token"

type AuthorizedUser is Data:
  AuthorizedUser{clientId: String, clientSecret: String, refreshToken: String, quotaProjectId: Maybe<&2, String>}

# Credentials files
# -----------------

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

# `json.x` used as a truthy string.
def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def missing(name: String) -> String: "The incoming JSON object does not contain a " ++ name ++ " field"

def userFrom(id: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>, quota: Maybe<&2, String>) -> Result<&2, &2, String, AuthorizedUser>:
  match id secret token:
    case None{} _ _: Fail{missing("client_id")}
    case _ None{} _: Fail{missing("client_secret")}
    case _ _ None{}: Fail{missing("refresh_token")}
    case Some{a} Some{b} Some{c}: Done{AuthorizedUser{a, b, c, quota}}

# UserRefreshClient.fromJSON's checks, in order.
def authorizedUser(+json: V.Value) -> Result<&2, &2, String, AuthorizedUser>:
  userFrom(text(field(json, "client_id")), text(field(json, "client_secret")), text(field(json, "refresh_token")), text(field(json, "quota_project_id")))

def typeName(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{name}}: name
    case _: ""

# GoogleAuth.fromJSON: the credential type decides the client.
def typedCredentials(+kind: String, json: V.Value) -> Result<&2, &2, String, AuthorizedUser>:
  match kind:
    case "authorized_user": authorizedUser(json)
    case "service_account": Fail{"Service account credentials are not supported natively: the RS256-signed token assertion needs RSA signing"}
    case "impersonated_service_account": Fail{"Impersonated service account credentials are not supported natively"}
    case "external_account": Fail{"External account credentials are not supported natively"}
    case "external_account_authorized_user": Fail{"External account authorized user credentials are not supported natively"}
    case _: Fail{"Credentials of type \"" ++ kind ++ "\" are not supported natively"}

def parsedFile(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, AuthorizedUser>:
  match result:
    case Fail{_}: Fail{"The credentials file is not valid JSON"}
    case Done{+json}: typedCredentials(typeName(field(json, "type")), json)

def decodedFile(value: Result<&2, &2, Utf8.Error, String>) -> Result<&2, &2, String, AuthorizedUser>:
  match value:
    case Fail{_}: Fail{"The credentials file is not valid UTF-8"}
    case Done{content}: parsedFile(Decode.parse(content))

def fileText(bytes: List<&2, U32>) -> Result<&2, &2, String, AuthorizedUser>: decodedFile(Utf8.decodeStrict(bytes))

# fs.createReadStream's error for the key file.
def readFailure(error: FS.Error, path: String) -> String:
  match error:
    case FS.System{2, _}: "ENOENT: no such file or directory, open '" ++ path ++ "'"
    case FS.System{_, message}: message ++ ", open '" ++ path ++ "'"
    case _: "Could not read '" ++ path ++ "'"

def readResult(path: String, result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, AuthorizedUser>:
  match result:
    case Fail{error}: Fail{readFailure(error, path)}
    case Done{bytes}: fileText(bytes)

def readCredentials(+path: String) -> IO(Result<&2, &2, String, AuthorizedUser>):
  do IO<Result<&2, &2, String, AuthorizedUser>>:
    result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return readResult(path, result)

def wellKnownResult(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, AuthorizedUser>:
  match result:
    case Fail{_}: Fail{NO_ADC_FOUND()}
    case Done{bytes}: fileText(bytes)

def wellKnown(home: Maybe<&2, String>) -> IO(Result<&2, &2, String, AuthorizedUser>):
  match home:
    case Some{SCon{c, cs}}:
      do IO<Result<&2, &2, String, AuthorizedUser>>:
        result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(SCon{c, cs} ++ "/.config/gcloud/application_default_credentials.json")
        return wellKnownResult(result)
    case _: IO.pure(Result<&2, &2, String, AuthorizedUser>, Fail{NO_ADC_FOUND()})

# The credentials the Vertex client authenticates with: the keyFilename pi
# passes (GOOGLE_APPLICATION_CREDENTIALS from the provider env or process),
# else $HOME/.config/gcloud/application_default_credentials.json. Relative
# key files resolve against the working directory as path.resolve does.
def loadCredentials(keyFilename: Maybe<&2, String>) -> IO(Result<&2, &2, String, AuthorizedUser>):
  match keyFilename:
    case Some{SCon{c, cs}}: readCredentials(SCon{c, cs})
    case _:
      do IO<Result<&2, &2, String, AuthorizedUser>>:
        home : Maybe<&2, String> <- Env.getProviderEnvValue("HOME", None{})
        wellKnown(home)

# Token exchange
# --------------

# refreshTokenNoCache's form: refresh_token, client_id, client_secret,
# grant_type.
def tokenForm(user: AuthorizedUser) -> String:
  match user:
    case AuthorizedUser{id, secret, token, _}: URL.serializeSearchParams([URL.Entry{"refresh_token", token}, URL.Entry{"client_id", id}, URL.Entry{"client_secret", secret}, URL.Entry{"grant_type", "refresh_token"}])

def tokenHeaders() -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  Http.headerList([R.Property{"Content-Type", "application/x-www-form-urlencoded;charset=UTF-8"}])

# gaxios' error message for a failed token request: an OAuth `error` string,
# an `error.message`, else the status.
def errorField(value: Maybe<&2, V.Value>, status: U32) -> String:
  match value:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs}
    case Some{V.ObjectValue{fields}}: Maybe.default(&2, String, text(R.get(V.Value, fields, "message")), "Request failed with status code " ++ U32.show(status))
    case _: "Request failed with status code " ++ U32.show(status)

def failureText(status: U32, body: Result<&2, &2, Decode.ParseError, V.Value>) -> String:
  match body:
    case Done{json}: errorField(field(json, "error"), status)
    case Fail{_}: "Request failed with status code " ++ U32.show(status)

type Token is Data:
  Token{accessToken: String, tokenType: String}

def accessToken(value: Maybe<&2, String>, kind: String) -> Result<&2, &2, String, Token>:
  match value:
    case Some{token}: Done{Token{token, kind}}
    case None{}: Fail{"The token response has no access_token"}

def tokenOf(body: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, Token>:
  match body:
    case Done{+json}: accessToken(text(field(json, "access_token")), Maybe.default(&2, String, text(field(json, "token_type")), "Bearer"))
    case Fail{_}: Fail{"The token response is not valid JSON"}

def tokenBody(-Reason: Data, +status: U32, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>, ok: Bool) -> Result<&2, &2, String, Token>:
  match text ok:
    case Fail{_} _: Fail{"Could not read the token response"}
    case Done{+body} True{}: tokenOf(Decode.parse(body))
    case Done{+body} False{}: Fail{failureText(status, Decode.parse(body))}

def tokenResponse(~Reason: Data, response: Fetch.Result_(Reason), aborted: Bool) -> IO(Result<&2, &2, String, Token>):
  match response aborted:
    case Fail{_} True{}: IO.pure(Result<&2, &2, String, Token>, Fail{"This operation was aborted"})
    case Fail{_} False{}: IO.pure(Result<&2, &2, String, Token>, Fail{"fetch failed"})
    case Done{Response.Response{+metadata, body}} _:
      do IO<Result<&2, &2, String, Token>>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 1048576n, body)
        return tokenBody(Reason, Response.metadataStatus(metadata), text, Response.ok(metadata))

def exchanged(~Reason: Data, fetch: Fetch.Fetch(Reason), +parent: Abort.AbortSignal<Reason>, request: Http.Request, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Result<&2, &2, String, Token>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, String, Token>>:
        response : Fetch.Result_(Reason) <- Http.post(~Reason, fetch, signal, request)
        aborted : Bool <- Abort.aborted(Reason, parent)
        result : Result<&2, &2, String, Token> <- tokenResponse(~Reason, response, aborted)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return result

def requested(~Reason: Data, fetch: Fetch.Fetch(Reason), +parent: Abort.AbortSignal<Reason>, url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: String) -> IO(Result<&2, &2, String, Token>):
  match url headers:
    case Fail{_} _: IO.pure(Result<&2, &2, String, Token>, Fail{"Invalid token URL"})
    case _ Fail{_}: IO.pure(Result<&2, &2, String, Token>, Fail{"Invalid header"})
    case Done{address} Done{fields}:
      do IO<Result<&2, &2, String, Token>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, 4294967295, parent)
        exchanged(~Reason, fetch, parent, Http.Request{address, fields, body}, Deadline.borrow(Reason, scope))

# UserRefreshClient.refreshTokenNoCache against `tokenUrl` (TOKEN_URL in
# production). gaxios' retries of the token request are not reproduced.
def refreshAccessToken(~Reason: Data, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, tokenUrl: String, user: AuthorizedUser) -> IO(Result<&2, &2, String, Token>):
  requested(~Reason, fetch, parent, URL.parse(urlContext, tokenUrl), tokenHeaders(), tokenForm(user))

def quotaProject(user: AuthorizedUser) -> Maybe<&2, String>:
  match user:
    case AuthorizedUser{_, _, _, quota}: quota

# getRequestHeaders: `authorization: <token_type> <access_token>` and the
# credentials' quota project as x-goog-user-project.
def authHeaders(token: Token, quota: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match token quota:
    case Token{access, kind} Some{project}: [R.Property{"x-goog-user-project", project}, R.Property{"authorization", kind ++ " " ++ access}]
    case Token{access, kind} None{}: [R.Property{"authorization", kind ++ " " ++ access}]

def headersFor(user: AuthorizedUser, token: Result<&2, &2, String, Token>) -> Result<&2, &2, String, List<&2, R.Property<String>>>:
  match token:
    case Fail{message}: Fail{message}
    case Done{value}: Done{authHeaders(value, quotaProject(user))}

def loaded(~Reason: Data, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, tokenUrl: String, credentials: Result<&2, &2, String, AuthorizedUser>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  match credentials:
    case Fail{message}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Fail{message})
    case Done{+user}:
      do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
        token : Result<&2, &2, String, Token> <- refreshAccessToken(~Reason, fetch, urlContext, parent, tokenUrl, user)
        return headersFor(user, token)

# The ADC request headers for one Vertex client.
def requestHeaders(~Reason: Data, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, tokenUrl: String, keyFilename: Maybe<&2, String>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
    credentials : Result<&2, &2, String, AuthorizedUser> <- loadCredentials(keyFilename)
    loaded(~Reason, fetch, urlContext, parent, tokenUrl, credentials)
