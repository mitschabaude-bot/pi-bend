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
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/rsa-sign.bend as Sign
import ../utils/json.bend as JsonWire
import ./credential-http.bend as CredentialHttp
import ./google-external-account.bend as External
import ./google-metadata.bend as Metadata
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/child-process.bend as Process
import ../../../runtime/src/ref.bend as Ref

# google-auth-library 10.6.2's Application Default Credentials as
# @google/genai uses them for Vertex AI without an API key: the credentials
# file (pi's GOOGLE_APPLICATION_CREDENTIALS keyFilename, else the well-known
# gcloud file) of type "authorized_user" (a refresh token),
# "service_account" (an RS256 JWT bearer assertion),
# "impersonated_service_account" (IAM Credentials generateAccessToken with
# the source credentials), "external_account" and
# "external_account_authorized_user" (google-external-account.bend), else
# the Compute Engine metadata server (google-metadata.bend), and the request
# headers they yield. Project ID discovery (GOOGLE_CLOUD_PROJECT, gcloud,
# the metadata server, Cloud Resource Manager), whose result the Vertex
# client does not use, is not performed.

def NO_ADC_FOUND() -> String: "Could not load the default credentials. Browse to https://cloud.google.com/docs/authentication/getting-started for more information."

def TOKEN_URL() -> String: "https://oauth2.googleapis.com/token"

# The credentials of an ADC file, or the Compute Engine default service
# account (google-auth-library's UserRefreshClient, JWT, Impersonated,
# ExternalAccountClient, ExternalAccountAuthorizedUserClient and Compute).
type AdcCredentials is Data:
  AuthorizedUser{clientId: String, clientSecret: String, refreshToken: String, quotaProjectId: Maybe<&2, String>}
  ServiceAccount{clientEmail: String, privateKey: String, quotaProjectId: Maybe<&2, String>}
  Impersonated{source: AdcCredentials, targetPrincipal: String, delegates: List<&2, String>, lifetime: F64, endpoint: String, quotaProjectId: Maybe<&2, String>}
  ExternalAccount{config: External.External}
  ExternalAuthorizedUser{config: External.AuthorizedUser}
  ComputeEngine{quotaProjectId: Maybe<&2, String>}
  KeyFile{path: String}

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

def userFrom(id: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>, quota: Maybe<&2, String>) -> Result<&2, &2, String, AdcCredentials>:
  match id secret token:
    case None{} _ _: Fail{missing("client_id")}
    case _ None{} _: Fail{missing("client_secret")}
    case _ _ None{}: Fail{missing("refresh_token")}
    case Some{a} Some{b} Some{c}: Done{AuthorizedUser{a, b, c, quota}}

def accountFrom(email: Maybe<&2, String>, key: Maybe<&2, String>, quota: Maybe<&2, String>) -> Result<&2, &2, String, AdcCredentials>:
  match email key:
    case None{} _: Fail{missing("client_email")}
    case _ None{}: Fail{missing("private_key")}
    case Some{a} Some{b}: Done{ServiceAccount{a, b, quota}}

# JWT.fromJSON's checks, in order.
def serviceAccount(+json: V.Value) -> Result<&2, &2, String, AdcCredentials>:
  accountFrom(text(field(json, "client_email")), text(field(json, "private_key")), text(field(json, "quota_project_id")))

# UserRefreshClient.fromJSON's checks, in order.
def authorizedUser(+json: V.Value) -> Result<&2, &2, String, AdcCredentials>:
  userFrom(text(field(json, "client_id")), text(field(json, "client_secret")), text(field(json, "refresh_token")), text(field(json, "quota_project_id")))

def typeName(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{name}}: name
    case _: ""

def stringList(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{value} <> rest: value <> stringList(rest)
    case _ <> rest: stringList(rest)

def delegatesOf(value: Maybe<&2, V.Value>) -> List<&2, String>:
  match value:
    case Some{V.ArrayValue{values}}: stringList(values)
    case _: Nil{}

def numberOr(value: Maybe<&2, V.Value>, +fallback: F64) -> F64:
  match value:
    case Some{V.Number{n}}: n
    case _: fallback

def principalSuffix(+segment: String, +access: Bool, id: Bool) -> Maybe<&2, String>:
  +target = String.take(segment, Nat.sub(String.length(segment), Bool.pick(Nat, access, 20n, 16n)))
  Bool.pick(Maybe<&2, String>, (access || id) && Bool.not(String.is_empty(target)), Some{target}, None{})

def principalOf(last: Maybe<&2, String>) -> Maybe<&2, String>:
  match last:
    case Some{+segment}: principalSuffix(segment, String.ends_with(segment, ":generateAccessToken"), String.ends_with(segment, ":generateIdToken"))
    case None{}: None{}

def principalIn(+url: String) -> Maybe<&2, String>:
  principalOf(List.last(&2, String, String.split(url, '/')))

def impersonatedTarget(+json: V.Value, +url: String, client: AdcCredentials, target: Maybe<&2, String>) -> Result<&2, &2, String, AdcCredentials>:
  match target:
    case None{}: Fail{"Cannot extract target principal from " ++ url}
    case Some{principal}: Done{Impersonated{client, principal, delegatesOf(field(json, "delegates")), numberOr(field(json, "lifetime"), F.fromU32(3600)), Maybe.default(&2, String, text(field(json, "endpoint")), "https://iamcredentials.googleapis.com"), text(field(json, "quota_project_id"))}}

# fromImpersonatedJSON after the source credentials parsed: the target
# principal from the impersonation URL.
def impersonatedWith(+json: V.Value, +url: String, source: Result<&2, &2, String, AdcCredentials>) -> Result<&2, &2, String, AdcCredentials>:
  match source:
    case Fail{message}: Fail{message}
    case Done{client}:
      Bool.pick(Result<&2, &2, String, AdcCredentials>, Nat.is_gt(String.length(url), 256n), Fail{"Target principal is too long: " ++ url}, impersonatedTarget(json, url, client, principalIn(url)))

def truthy(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.Null{}}: None{}
    case Some{V.Boolean{False{}}}: None{}
    case Some{V.Text{SNil{}}}: None{}
    case other: other

def impersonationChecks(+json: V.Value) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Maybe.is_some(&2, V.Value, truthy(field(json, "source_credentials"))), Bool.pick(Maybe<&2, String>, Maybe.is_some(&2, String, text(field(json, "service_account_impersonation_url"))), None{}, Some{missing("service_account_impersonation_url")}), Some{missing("source_credentials")})

def externalOf(result: Result<&2, &2, String, External.External>) -> Result<&2, &2, String, AdcCredentials>:
  match result:
    case Done{config}: Done{ExternalAccount{config}}
    case Fail{message}: Fail{message}

# GoogleAuth.fromJSON: the credential type decides the client; any other
# type is read as a service account. Impersonated credentials nest their
# source credentials (`depth` bounds the nesting).
def typedCredentials(depth: Nat, +json: V.Value) -> Result<&2, &2, String, AdcCredentials>:
  match depth:
    case 0n: Fail{"The impersonated credentials nest too deeply"}
    case 1n+left:
      +kind = typeName(field(json, "type"))
      +checks = impersonationChecks(json)
      Bool.pick(Unit -> Result<&2, &2, String, AdcCredentials>, String.eq(kind, "impersonated_service_account"), _ =>
        Bool.pick(Unit -> Result<&2, &2, String, AdcCredentials>, Maybe.is_some(&2, String, checks), _ => Fail{Maybe.default(&2, String, checks, "")}, _ => impersonatedWith(json, Maybe.default(&2, String, text(field(json, "service_account_impersonation_url")), ""), typedCredentials(left, Maybe.default(&2, V.Value, field(json, "source_credentials"), V.Null{}))))(Unit{}), _ =>
        Bool.pick(Result<&2, &2, String, AdcCredentials>, String.eq(kind, "authorized_user"), authorizedUser(json),
          Bool.pick(Result<&2, &2, String, AdcCredentials>, String.eq(kind, "external_account"), externalOf(External.external(json)),
            Bool.pick(Result<&2, &2, String, AdcCredentials>, String.eq(kind, "external_account_authorized_user"), Done{ExternalAuthorizedUser{External.authorizedUser(json)}}, serviceAccount(json)))))(Unit{})

def parsedFile(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, AdcCredentials>:
  match result:
    case Fail{_}: Fail{"The credentials file is not valid JSON"}
    case Done{+json}: typedCredentials(8n, json)

def decodedFile(value: Result<&2, &2, Utf8.Error, String>) -> Result<&2, &2, String, AdcCredentials>:
  match value:
    case Fail{_}: Fail{"The credentials file is not valid UTF-8"}
    case Done{content}: parsedFile(Decode.parse(content))

def fileText(bytes: List<&2, U32>) -> Result<&2, &2, String, AdcCredentials>: decodedFile(Utf8.decodeStrict(bytes))

# fs.createReadStream's error for the key file.
def readFailure(error: FS.Error, path: String) -> String:
  match error:
    case FS.System{2, _}: "ENOENT: no such file or directory, open '" ++ path ++ "'"
    case FS.System{_, message}: message ++ ", open '" ++ path ++ "'"
    case _: "Could not read '" ++ path ++ "'"

# fromStreamAsync: a key file that does not construct a client is read as a
# JWT key file (gtoken's getCredentials) when the token is requested.
def keyFileFallback(+path: String, parsed: Result<&2, &2, String, AdcCredentials>) -> Result<&2, &2, String, AdcCredentials>:
  match parsed:
    case Done{credentials}: Done{credentials}
    case Fail{_}: Done{KeyFile{path}}

def readResult(+path: String, result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, AdcCredentials>:
  match result:
    case Fail{error}: Fail{readFailure(error, path)}
    case Done{bytes}: keyFileFallback(path, fileText(bytes))

def readCredentials(+path: String) -> IO(Result<&2, &2, String, AdcCredentials>):
  do IO<Result<&2, &2, String, AdcCredentials>>:
    result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return readResult(path, result)

# _tryGetApplicationCredentialsFromWellKnownFile: a missing file passes on.
def wellKnownResult(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, Result<&2, &2, String, AdcCredentials>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{fileText(bytes)}

def wellKnown(home: Maybe<&2, String>) -> IO(Maybe<&2, Result<&2, &2, String, AdcCredentials>>):
  match home:
    case Some{SCon{c, cs}}:
      do IO<Maybe<&2, Result<&2, &2, String, AdcCredentials>>>:
        result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(SCon{c, cs} ++ "/.config/gcloud/application_default_credentials.json")
        return wellKnownResult(result)
    case _: IO.pure(Maybe<&2, Result<&2, &2, String, AdcCredentials>>, None{})

def withQuota(override: Maybe<&2, String>, credentials: AdcCredentials) -> AdcCredentials:
  match override credentials:
    case None{} other: other
    case Some{quota} AuthorizedUser{id, secret, token, _}: AuthorizedUser{id, secret, token, Some{quota}}
    case Some{quota} ServiceAccount{email, key, _}: ServiceAccount{email, key, Some{quota}}
    case Some{quota} Impersonated{source, target, delegates, lifetime, endpoint, _}: Impersonated{source, target, delegates, lifetime, endpoint, Some{quota}}
    case Some{quota} ExternalAccount{External.External{a, b, c, d, e, f, g, h, i, _}}: ExternalAccount{External.External{a, b, c, d, e, f, g, h, i, Some{quota}}}
    case Some{quota} ExternalAuthorizedUser{External.AuthorizedUser{a, b, c, d, _}}: ExternalAuthorizedUser{External.AuthorizedUser{a, b, c, d, Some{quota}}}
    case Some{quota} ComputeEngine{_}: ComputeEngine{Some{quota}}
    case Some{_} KeyFile{path}: KeyFile{path}

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

type Loaded is Data:
  Loaded{credentials: AdcCredentials, applicationDefault: Bool}

# #prepareAndCacheClient: GOOGLE_CLOUD_QUOTA_PROJECT overrides the quota
# project of Application Default Credentials.
def prepared(result: Result<&2, &2, String, AdcCredentials>) -> IO(Result<&2, &2, String, Loaded>):
  do IO<Result<&2, &2, String, Loaded>>:
    override : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_CLOUD_QUOTA_PROJECT", None{})
    return Result.map(&2, &2, String, AdcCredentials, Loaded, credentials => Loaded{withQuota(nonempty(override), credentials), True{}}, result)

def computeOr(gce: Result<&2, &2, String, Bool>) -> Result<&2, &2, String, AdcCredentials>:
  match gce:
    case Fail{message}: Fail{message}
    case Done{True{}}: Done{ComputeEngine{None{}}}
    case Done{False{}}: Fail{NO_ADC_FOUND()}

def defaultOr(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, found: Maybe<&2, Result<&2, &2, String, AdcCredentials>>) -> IO(Result<&2, &2, String, Loaded>):
  match found:
    case Some{result}: prepared(result)
    case None{}:
      do IO<Result<&2, &2, String, Loaded>>:
        resident : Bool <- Metadata.residency()
        gce : Result<&2, &2, String, Bool> <- Metadata.isGce(~Reason, transport, resident)
        prepared(computeOr(gce))

# The credentials the Vertex client authenticates with: the keyFilename pi
# passes (GOOGLE_APPLICATION_CREDENTIALS from the provider env or process),
# else getApplicationDefaultAsync: the well-known gcloud file
# ($HOME/.config/gcloud/application_default_credentials.json), else the
# Compute Engine default service account when running on Google Cloud.
# Relative key files resolve against the working directory as path.resolve
# does.
def keyFileLoaded(result: Result<&2, &2, String, AdcCredentials>) -> Result<&2, &2, String, Loaded>:
  match result:
    case Done{credentials}: Done{Loaded{credentials, False{}}}
    case Fail{message}: Fail{message}

def loadCredentials(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, keyFilename: Maybe<&2, String>) -> IO(Result<&2, &2, String, Loaded>):
  match keyFilename:
    case Some{SCon{c, cs}}:
      do IO<Result<&2, &2, String, Loaded>>:
        result : Result<&2, &2, String, AdcCredentials> <- readCredentials(SCon{c, cs})
        return keyFileLoaded(result)
    case _:
      do IO<Result<&2, &2, String, Loaded>>:
        home : Maybe<&2, String> <- Env.getProviderEnvValue("HOME", None{})
        found : Maybe<&2, Result<&2, &2, String, AdcCredentials>> <- wellKnown(home)
        defaultOr(~Reason, transport, found)

# Token exchange
# --------------

def SCOPE() -> String: "https://www.googleapis.com/auth/cloud-platform"

def JWT_GRANT() -> String: "urn:ietf:params:oauth:grant-type:jwt-bearer"

def base64Url(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'+', rest}: SCon{'-', base64Url(rest)}
    case SCon{'/', rest}: SCon{'_', base64Url(rest)}
    case SCon{'=', _}: SNil{}
    case SCon{c, rest}: SCon{c, base64Url(rest)}

def encodedText(value: Result<&2, &2, Base64.Error, String>) -> String:
  match value:
    case Done{encoded}: base64Url(encoded)
    case Fail{_}: ""

def encodedSegment(bytes: List<&2, U32>) -> String: encodedText(Base64.encode(bytes))

def jsonSegment(value: T.JsonValue) -> String: encodedSegment(Utf8.encode(Maybe.default(&2, String, JsonWire.stringify(value), "{}")))

def num(value: F64) -> T.JsonValue: T.JsonNumber{value}

def str(value: String) -> T.JsonValue: T.JsonString{value}

# gtoken's claims: iss, scope, aud, exp, iat (seconds).
def claims(email: String, +iat: F64) -> T.JsonValue:
  T.JsonObject{R.Record{[R.Property{"iss", str(email)}, R.Property{"scope", str(SCOPE())}, R.Property{"aud", str(TOKEN_URL())}, R.Property{"exp", num(F.add(iat, F.fromU32(3600)))}, R.Property{"iat", num(iat)}]}}

def signedAssertion(+unsigned: String, signature: Result<&2, &2, Sign.Error, List<&2, U32>>) -> Result<&2, &2, String, String>:
  match signature:
    case Fail{_}: Fail{"The service account private key could not sign the token assertion"}
    case Done{bytes}: Done{unsigned ++ "." ++ encodedSegment(bytes)}

def assertionWith(+unsigned: String, key: Result<&2, &2, Sign.Error, Sign.PrivateKey>) -> Result<&2, &2, String, String>:
  match key:
    case Fail{_}: Fail{"The service account private_key is not a supported RSA private key"}
    case Done{privateKey}: signedAssertion(unsigned, Sign.signPkcs1Sha256(privateKey, Utf8.encode(unsigned)))

# jws.sign({ header: { alg: "RS256" }, payload, secret }).
def assertion(email: String, privateKey: String, iat: F64) -> Result<&2, &2, String, String>:
  assertionWith(jsonSegment(T.JsonObject{R.Record{[R.Property{"alg", str("RS256")}]}}) ++ "." ++ jsonSegment(claims(email, iat)), Sign.parsePrivateKeyPem(privateKey))

def jwtForm(+token: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match token:
    case Fail{message}: Fail{message}
    case Done{value}: Done{URL.serializeSearchParams([URL.Entry{"grant_type", JWT_GRANT()}, URL.Entry{"assertion", value}])}

# The token request body: refreshTokenNoCache's form (refresh_token,
# client_id, client_secret, grant_type), or gtoken's JWT bearer grant with
# the assertion signed at `now` (milliseconds).
def tokenForm(user: AdcCredentials, now: F64) -> Result<&2, &2, String, String>:
  match user:
    case AuthorizedUser{id, secret, token, _}: Done{URL.serializeSearchParams([URL.Entry{"refresh_token", token}, URL.Entry{"client_id", id}, URL.Entry{"client_secret", secret}, URL.Entry{"grant_type", "refresh_token"}])}
    case ServiceAccount{email, key, _}: jwtForm(assertion(email, key, F.truncate(F.divide(now, F.fromU32(1000)))))
    case _: Fail{"These credentials do not use the OAuth2 token endpoint"}

# gaxios' error message for a failed token request: an OAuth `error` string,
# an `error.message`, else the status.
def errorField(value: Maybe<&2, V.Value>, status: U32) -> String:
  match value:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs}
    case Some{V.ObjectValue{fields}}: Maybe.default(&2, String, text(R.get(V.Value, fields, "message")), "Request failed with status code " ++ U32.show(status))
    case _: "Request failed with status code " ++ U32.show(status)

def describedField(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{description}}: description
    case _: "undefined"

# gtoken rewrites the message to `${error}: ${error_description}`.
def gtokenWith(fallback: String, error: Maybe<&2, V.Value>, description: Maybe<&2, V.Value>) -> String:
  match error:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs} ++ ": " ++ describedField(description)
    case _: fallback

def gtokenText(fallback: String, +json: V.Value) -> String: gtokenWith(fallback, field(json, "error"), field(json, "error_description"))

def failureText(jwt: Bool, +status: U32, body: Result<&2, &2, Decode.ParseError, V.Value>) -> String:
  match body:
    case Done{+json}: Bool.pick(String, jwt, gtokenText(errorField(field(json, "error"), status), json), errorField(field(json, "error"), status))
    case Fail{_}: "Request failed with status code " ++ U32.show(status)

type Token is Data:
  Token{accessToken: String}

# The `error.status` and `error.message` of a Google API error response.
type ApiError is Data:
  ApiError{status: String, message: String}

# A failed token request: the response status, if one came, and the error
# message.
type TokenFailure is Data:
  TokenFailure{status: Maybe<&2, U32>, message: String, apiError: Maybe<&2, ApiError>}

def plainFailure(message: String) -> TokenFailure: TokenFailure{None{}, message, None{}}

def apiErrorOf(status: Maybe<&2, String>, message: Maybe<&2, String>) -> Maybe<&2, ApiError>:
  match status message:
    case Some{code} Some{text}: Some{ApiError{code, text}}
    case _ _: None{}

def errorObjectField(error: Maybe<&2, V.Value>, name: String) -> Maybe<&2, String>:
  match error:
    case Some{V.ObjectValue{fields}}: text(R.get(V.Value, fields, name))
    case _: None{}

def errorStatus(json: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match json:
    case Some{V.ObjectValue{fields}}: errorObjectField(R.get(V.Value, fields, "error"), "status")
    case _: None{}

def errorMessage(json: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match json:
    case Some{V.ObjectValue{fields}}: errorObjectField(R.get(V.Value, fields, "error"), "message")
    case _: None{}

def jsonOf(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def responseFailure(+status: U32, message: String, +body: String) -> TokenFailure:
  +json = jsonOf(Decode.parse(body))
  TokenFailure{Some{status}, message, apiErrorOf(errorStatus(json), errorMessage(json))}

def messageOf(failure: TokenFailure) -> String:
  match failure:
    case TokenFailure{_, message, _}: message

def tokenOf(body: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, TokenFailure, Token>:
  match body:
    case Done{+json}: Done{Token{Maybe.default(&2, String, text(field(json, "access_token")), "undefined")}}
    case Fail{_}: Fail{plainFailure("The token response is not valid JSON")}

def tokenReply(jwt: Bool, result: Result<&2, &2, CredentialHttp.Failure, CredentialHttp.Reply>) -> Result<&2, &2, TokenFailure, Token>:
  match result:
    case Fail{failure}: Fail{plainFailure(CredentialHttp.failureText(failure))}
    case Done{CredentialHttp.Reply{+status, _, +body}}:
      Bool.pick(Result<&2, &2, TokenFailure, Token>, U32.is_ge(status, 200) && U32.is_lt(status, 300), tokenOf(Decode.parse(body)), Fail{responseFailure(status, failureText(jwt, status, Decode.parse(body)), body)})

def FORM() -> R.Property<String>: R.Property{"Content-Type", "application/x-www-form-urlencoded;charset=UTF-8"}

# gtoken retries the assertion grant as a POST under gaxios' defaults.
def JWT_RETRY() -> CredentialHttp.Retry: CredentialHttp.Retry{3n, 2n, ["POST"]}

def posted(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +jwt: Bool, form: Result<&2, &2, String, String>) -> IO(Result<&2, &2, TokenFailure, Token>):
  match form:
    case Fail{message}: IO.pure(Result<&2, &2, TokenFailure, Token>, Fail{plainFailure(message)})
    case Done{body}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        result : Result<&2, &2, CredentialHttp.Failure, CredentialHttp.Reply> <- CredentialHttp.requestRetrying(~Reason, transport, Bool.pick(CredentialHttp.Retry, jwt, JWT_RETRY(), CredentialHttp.AUTH_RETRY()), "POST", TOKEN_URL(), [FORM()], Headers.Text{body}, CredentialHttp.NO_TIMEOUT())
        return tokenReply(jwt, result)

def isJwt(user: AdcCredentials) -> Bool:
  match user:
    case ServiceAccount{_, _, _}: True{}
    case _: False{}

# UserRefreshClient.refreshTokenNoCache, or gtoken's JWT bearer grant signed
# now.
def oauthToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +user: AdcCredentials) -> IO(Result<&2, &2, TokenFailure, Token>):
  do IO<Result<&2, &2, TokenFailure, Token>>:
    now : F64 <- Date.now()
    posted(~Reason, transport, isJwt(user), tokenForm(user, now))

def quotaProject(user: AdcCredentials) -> Maybe<&2, String>:
  match user:
    case AuthorizedUser{_, _, _, quota}: quota
    case ServiceAccount{_, _, quota}: quota
    case Impersonated{_, _, _, _, _, quota}: quota
    case ExternalAccount{config}: External.quotaProject(config)
    case ExternalAuthorizedUser{config}: External.authorizedQuota(config)
    case ComputeEngine{quota}: quota
    case KeyFile{_}: None{}

# getRequestHeaders: `authorization: Bearer <access_token>` and the
# credentials' quota project as x-goog-user-project.
def authHeaders(token: Token, quota: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match token quota:
    case Token{access} Some{project}: [R.Property{"x-goog-user-project", project}, R.Property{"authorization", "Bearer " ++ access}]
    case Token{access} None{}: [R.Property{"authorization", "Bearer " ++ access}]

# Impersonated
# ------------

def strings(values: List<&2, String>) -> List<&2, T.JsonValue>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: str(value) <> strings(rest)

def impersonationBody(delegates: List<&2, String>, lifetime: F64) -> String:
  Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"delegates", T.JsonArray{strings(delegates)}}, R.Property{"scope", T.JsonArray{[str(SCOPE())]}}, R.Property{"lifetime", str(Maybe.default(&2, String, F.toJsonNumber(lifetime), "3600") ++ "s")}]}}), "{}")

def unableWith(+status: U32, +body: String, statusText: Maybe<&2, String>, message: Maybe<&2, String>) -> TokenFailure:
  match statusText message:
    case Some{code} Some{text}: TokenFailure{Some{status}, code ++ ": unable to impersonate: " ++ text, None{}}
    case _ _: TokenFailure{Some{status}, "unable to impersonate: Error: " ++ CredentialHttp.apiError(status, body), None{}}

# Impersonated.refreshToken's error: `<status>: unable to impersonate:
# <message>` from a Google API error, else `unable to impersonate: <error>`.
def unable(failure: TokenFailure) -> TokenFailure:
  match failure:
    case TokenFailure{status, _, Some{ApiError{code, text}}}: TokenFailure{status, code ++ ": unable to impersonate: " ++ text, None{}}
    case TokenFailure{status, message, None{}}: TokenFailure{status, "unable to impersonate: Error: " ++ message, None{}}

def impersonationReply(result: Result<&2, &2, CredentialHttp.Failure, CredentialHttp.Reply>) -> Result<&2, &2, TokenFailure, Token>:
  match result:
    case Fail{failure}: Fail{unable(plainFailure(CredentialHttp.failureText(failure)))}
    case Done{CredentialHttp.Reply{+status, _, +body}}:
      +json = jsonOf(Decode.parse(body))
      Bool.pick(Result<&2, &2, TokenFailure, Token>, U32.is_ge(status, 200) && U32.is_lt(status, 300), Done{Token{Maybe.default(&2, String, Maybe.bind(&2, V.Value, String, json, value => text(field(value, "accessToken"))), "undefined")}}, Fail{unableWith(status, body, errorStatus(json), errorMessage(json))})

def impersonationHeaders(source: AdcCredentials, token: Token) -> List<&2, R.Property<String>>:
  List.append(&2, R.Property<String>, [R.Property{"content-type", "application/json"}], authHeaders(token, quotaProject(source)))

# generateAccessToken for the target principal, authorized as the source.
def impersonatedToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials, source: Result<&2, &2, TokenFailure, Token>) -> IO(Result<&2, &2, TokenFailure, Token>):
  match credentials source:
    case _ Fail{failure}: IO.pure(Result<&2, &2, TokenFailure, Token>, Fail{unable(failure)})
    case Impersonated{client, target, delegates, lifetime, endpoint, _} Done{token}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        result : Result<&2, &2, CredentialHttp.Failure, CredentialHttp.Reply> <- CredentialHttp.requestRetrying(~Reason, transport, CredentialHttp.AUTH_RETRY(), "POST", endpoint ++ "/v1/projects/-/serviceAccounts/" ++ target ++ ":generateAccessToken", impersonationHeaders(client, token), Headers.Text{impersonationBody(delegates, lifetime)}, CredentialHttp.NO_TIMEOUT())
        return impersonationReply(result)
    case _ Done{_}: IO.pure(Result<&2, &2, TokenFailure, Token>, Fail{plainFailure("Not impersonated credentials")})

# Compute Engine
# --------------

def FORBIDDEN() -> String: "A Forbidden error was returned while attempting to retrieve an access token for the Compute Engine built-in service account. This may be because the Compute Engine instance does not have the correct permission scopes specified: "

def NOT_FOUND() -> String: "A Not Found error was returned while attempting to retrieve an accesstoken for the Compute Engine built-in service account. This may be because the Compute Engine instance does not have any permission scopes specified: "

def wrapped(+status: U32, +message: String) -> String:
  Bool.pick(String, U32.is_eq(status, 403), FORBIDDEN() ++ message, Bool.pick(String, U32.is_eq(status, 404), NOT_FOUND() ++ message, message))

def computeReply(result: Result<&2, &2, Metadata.MetadataError, CredentialHttp.Reply>) -> Result<&2, &2, TokenFailure, Token>:
  match result:
    case Done{CredentialHttp.Reply{_, _, +body}}: tokenOf(Decode.parse(body))
    case Fail{Metadata.NoResponse{failure}}: Fail{plainFailure("Could not refresh access token: " ++ CredentialHttp.failureText(failure))}
    case Fail{Metadata.ErrorStatus{+status, message}}: Fail{TokenFailure{Some{status}, wrapped(status, "Could not refresh access token: " ++ message), None{}}}
    case Fail{Metadata.WrongFlavor{message}}: Fail{plainFailure(message)}

# Compute.refreshTokenNoCache: the default service account's token for the
# cloud-platform scope.
def computeToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>) -> IO(Result<&2, &2, TokenFailure, Token>):
  do IO<Result<&2, &2, TokenFailure, Token>>:
    resident : Bool <- Metadata.residency()
    result : Result<&2, &2, Metadata.MetadataError, CredentialHttp.Reply> <- Metadata.instance(~Reason, transport, "/service-accounts/default/token?" ++ URL.serializeSearchParams([URL.Entry{"scopes", SCOPE()}]), resident, 3n)
    return computeReply(result)

# JWT key files
# -------------

def extensionIn(+base: String, last: Maybe<&2, String>, dotted: Bool) -> String:
  match last:
    case Some{+part}: Bool.pick(String, dotted && Bool.not(String.starts_with(base, ".") && Nat.is_eq(String.length(base), 1n + String.length(part))), "." ++ part, "")
    case None{}: ""

def extensionOf(+path: String) -> String:
  +base = Maybe.default(&2, String, List.last(&2, String, String.split(path, '/')), path)
  extensionIn(base, List.last(&2, String, String.split(base, '.')), Nat.is_gt(List.length(&2, String, String.split(base, '.')), 1n))

def jsonKeyFields(key: Maybe<&2, String>, email: Maybe<&2, String>) -> Result<&2, &2, String, AdcCredentials>:
  match key email:
    case Some{privateKey} Some{clientEmail}: Done{ServiceAccount{clientEmail, privateKey, None{}}}
    case _ _: Fail{"private_key and client_email are required."}

def jsonKey(json: Maybe<&2, V.Value>) -> Result<&2, &2, String, AdcCredentials>:
  match json:
    case None{}: Fail{"Invalid JSON key file: Unexpected token in JSON"}
    case Some{+value}: jsonKeyFields(text(field(value, "private_key")), text(field(value, "client_email")))

def decodedText(value: Utf8.Decoded) -> String:
  match value:
    case Utf8.Decoded{_, content}: content

def decodedLossy(bytes: List<&2, U32>) -> String: decodedText(Utf8.decode(Utf8.create(), bytes))

def keyRead(+path: String, bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, AdcCredentials>:
  match bytes:
    case Fail{error}: Fail{readFailure(error, path)}
    case Done{content}: jsonKey(jsonOf(Decode.parse(decodedLossy(content))))

# gtoken's CredentialsProviderFactory by extension: a JSON service account
# key; PEM keys carry no client email (not supported here); p12 is refused.
def keyFileCredentials(+path: String) -> IO(Result<&2, &2, String, AdcCredentials>):
  +extension = extensionOf(path)
  Bool.pick(Unit -> IO(Result<&2, &2, String, AdcCredentials>), String.eq(extension, ".json"), _ =>
    do IO<Result<&2, &2, String, AdcCredentials>>:
      bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
      return keyRead(path, bytes), _ =>
    IO.pure(Result<&2, &2, String, AdcCredentials>, Fail{Bool.pick(String, String.eq(extension, ".pem") || String.eq(extension, ".crt") || String.eq(extension, ".der"), "A PEM key file has no client_email; only JSON service account key files are supported", Bool.pick(String, String.eq(extension, ".p12") || String.eq(extension, ".pfx"), "*.p12 certificates are not supported after v6.1.2. Consider utilizing *.json format or converting *.p12 to *.pem using the OpenSSL CLI.", "Unknown certificate type. Type is determined based on file extension. Current supported extensions are *.json, and *.pem."))}))(Unit{})

def keyFileToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: Result<&2, &2, String, AdcCredentials>) -> IO(Result<&2, &2, TokenFailure, Token>):
  match credentials:
    case Fail{message}: IO.pure(Result<&2, &2, TokenFailure, Token>, Fail{plainFailure(message)})
    case Done{+account}: oauthToken(~Reason, transport, account)

# Access tokens
# -------------

def plainResult(result: Result<&2, &2, String, External.Token>) -> Result<&2, &2, TokenFailure, Token>:
  match result:
    case Done{External.Token{access}}: Done{Token{access}}
    case Fail{message}: Fail{plainFailure(message)}

def externalToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials) -> IO(Result<&2, &2, TokenFailure, Token>):
  match credentials:
    case ExternalAccount{config}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        result : Result<&2, &2, String, External.Token> <- External.accessToken(~Reason, transport, config)
        return plainResult(result)
    case ExternalAuthorizedUser{config}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        result : Result<&2, &2, String, External.Token> <- External.refreshAuthorizedUser(~Reason, transport, config)
        return plainResult(result)
    case ComputeEngine{_}: computeToken(~Reason, transport)
    case KeyFile{path}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        account : Result<&2, &2, String, AdcCredentials> <- keyFileCredentials(path)
        keyFileToken(~Reason, transport, account)
    case other: oauthToken(~Reason, transport, other)

# The access token of the credentials; impersonated credentials first get
# their source's token.
@unsafe def accessToken(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +credentials: AdcCredentials) -> IO(Result<&2, &2, TokenFailure, Token>):
  match credentials:
    case Impersonated{+source, target, delegates, lifetime, endpoint, quota}:
      do IO<Result<&2, &2, TokenFailure, Token>>:
        sourceToken : Result<&2, &2, TokenFailure, Token> <- accessToken(~Reason, transport, source)
        impersonatedToken(~Reason, transport, Impersonated{source, target, delegates, lifetime, endpoint, quota}, sourceToken)
    case other: externalToken(~Reason, transport, other)

def refreshes(credentials: AdcCredentials) -> Bool:
  match credentials:
    case ExternalAccount{_}: False{}
    case ExternalAuthorizedUser{_}: False{}
    case _: True{}

# OAuth2Client.getRequestMetadataAsync: a refresh answered with 403 or 404
# is reported as "Could not refresh access token: ...".
def refreshMessage(oauth: Bool, failure: TokenFailure) -> String:
  match failure:
    case TokenFailure{Some{+status}, +message, _}: Bool.pick(String, oauth && (U32.is_eq(status, 403) || U32.is_eq(status, 404)), "Could not refresh access token: " ++ message, message)
    case TokenFailure{None{}, +message, _}: message

def headersFor(user: AdcCredentials, token: Result<&2, &2, TokenFailure, Token>) -> Result<&2, &2, String, List<&2, R.Property<String>>>:
  match token:
    case Fail{failure}: Fail{refreshMessage(refreshes(user), failure)}
    case Done{value}: Done{authHeaders(value, quotaProject(user))}

def tokenHeaders(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +user: AdcCredentials) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
    token : Result<&2, &2, TokenFailure, Token> <- accessToken(~Reason, transport, user)
    return headersFor(user, token)

# Project discovery (GoogleAuth.findAndCacheProjectId)
# ----------------------------------------------------

def gcloudProject(bytes: List<&2, U32>, status: Result<&2, &2, Process.ExecutionError, U32>) -> Maybe<&2, String>:
  match status:
    case Done{0}: Maybe.bind(&2, V.Value, String, jsonOf(Decode.parse(decodedLossy(bytes))), json => Maybe.bind(&2, V.Value, String, field(json, "configuration"), configuration => Maybe.bind(&2, V.Value, String, field(configuration, "properties"), properties => Maybe.bind(&2, V.Value, String, field(properties, "core"), core => text(field(core, "project"))))))
    case _: None{}

def collect(sink: Ref.Ref<List<&2, U32>>, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Ref.modify(List<&2, U32>, Unit, sink, previous => (List.append(&2, U32, previous, bytes), Unit{}))
    return Done{Unit{}}

# getDefaultServiceProjectId: `gcloud config config-helper --format json`
# through the shell; any failure is no project.
def defaultServiceProject() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    +sink : Ref.Ref<List<&2, U32>> <- Ref.new(List<&2, U32>, Nil{})
    +onData : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<List<&2, U32>>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~collect, sink)
    entries : List<String> <- IO.environment()
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    status : Result<&2, &2, Process.ExecutionError, U32> <- Process.executeSelected(Process.Stdout{}, "/bin/sh", ["-c"], "gcloud config config-helper --format json", Result.default(&2, &2, FS.Error, String, cwd, "/"), entries, None{}, None{}, onData)
    C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, onData)
    bytes : List<&2, U32> <- Ref.dispose(List<&2, U32>, sink)
    return gcloudProject(bytes, status)

def productionProject() -> IO(Bool):
  do IO<Bool>:
    a : Maybe<&2, String> <- Env.getProviderEnvValue("GCLOUD_PROJECT", None{})
    b : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_CLOUD_PROJECT", None{})
    c : Maybe<&2, String> <- Env.getProviderEnvValue("gcloud_project", None{})
    d : Maybe<&2, String> <- Env.getProviderEnvValue("google_cloud_project", None{})
    return Maybe.is_some(&2, String, Maybe.or(&2, String, nonempty(a), Maybe.or(&2, String, nonempty(b), Maybe.or(&2, String, nonempty(c), nonempty(d)))))

def gceProject(result: Result<&2, &2, Metadata.MetadataError, CredentialHttp.Reply>) -> Bool:
  match result:
    case Done{CredentialHttp.Reply{_, _, body}}: Bool.not(String.is_empty(body))
    case Fail{_}: False{}

def lookedUp(token: External.Token, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Maybe<&2, Token>>:
  match token result:
    case _ Fail{message}: Fail{message}
    case External.Token{access} Done{_}: Done{Some{Token{access}}}

def lookupWith(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, config: External.External, +number: String, token: Result<&2, &2, String, External.Token>) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  match token:
    case Fail{message}: IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Fail{message})
    case Done{+value}:
      do IO<Result<&2, &2, String, Maybe<&2, Token>>>:
        result : Result<&2, &2, String, Unit> <- External.lookupProject(~Reason, transport, config, number, value)
        return lookedUp(value, result)

def externalNumbered(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +config: External.External, number: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  match number:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Done{None{}})
    case Some{+value}:
      do IO<Result<&2, &2, String, Maybe<&2, Token>>>:
        token : Result<&2, &2, String, External.Token> <- External.accessToken(~Reason, transport, config)
        lookupWith(~Reason, transport, config, value, token)

# getExternalAccountClientProjectId: its token, then the project lookup.
def externalProject(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  match credentials:
    case ExternalAccount{+config}: externalNumbered(~Reason, transport, config, External.projectNumber(config))
    case _: IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Done{None{}})

def afterGce(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials, found: Bool) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  match found:
    case True{}: IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Done{None{}})
    case False{}: externalProject(~Reason, transport, credentials)

def afterGcloud(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials, found: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  match found:
    case Some{_}: IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Done{None{}})
    case None{}:
      do IO<Result<&2, &2, String, Maybe<&2, Token>>>:
        resident : Bool <- Metadata.residency()
        project : Result<&2, &2, Metadata.MetadataError, CredentialHttp.Reply> <- Metadata.accessor(~Reason, transport, "project/project-id", resident, 3n)
        afterGce(~Reason, transport, credentials, gceProject(project))

# #prepareAndCacheClient's getProjectIdOptional: the environment, gcloud,
# the metadata server, then an external account's Cloud Resource Manager
# project. The project is not used by the Vertex client, but the lookups run
# as upstream runs them, and an external account's lookup fetches the token
# that the request then reuses.
def discoverProject(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: AdcCredentials) -> IO(Result<&2, &2, String, Maybe<&2, Token>>):
  do IO<Result<&2, &2, String, Maybe<&2, Token>>>:
    fromEnv : Bool <- productionProject()
    Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, Token>>), fromEnv, _ => IO.pure(Result<&2, &2, String, Maybe<&2, Token>>, Done{None{}}), _ =>
      do IO<Result<&2, &2, String, Maybe<&2, Token>>>:
        gcloud : Maybe<&2, String> <- defaultServiceProject()
        afterGcloud(~Reason, transport, credentials, gcloud))(Unit{})

def discovered(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, +user: AdcCredentials, discovery: Result<&2, &2, String, Maybe<&2, Token>>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  match discovery:
    case Fail{message}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Fail{message})
    case Done{Some{token}}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Done{authHeaders(token, quotaProject(user))})
    case Done{None{}}: tokenHeaders(~Reason, transport, user)

def loaded(~Reason: Data, +transport: CredentialHttp.Transport<Reason>, credentials: Result<&2, &2, String, Loaded>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  match credentials:
    case Fail{message}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Fail{message})
    case Done{Loaded{+user, False{}}}: tokenHeaders(~Reason, transport, user)
    case Done{Loaded{+user, True{}}}:
      do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
        discovery : Result<&2, &2, String, Maybe<&2, Token>> <- discoverProject(~Reason, transport, user)
        discovered(~Reason, transport, user, discovery)

# The ADC request headers for one Vertex client.
def requestHeaders(~Reason: Data, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, keyFilename: Maybe<&2, String>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
    +transport : CredentialHttp.Transport<Reason> <- IO.pure(CredentialHttp.Transport<Reason>, CredentialHttp.Transport{fetch, urlContext, parent})
    credentials : Result<&2, &2, String, Loaded> <- loadCredentials(~Reason, transport, keyFilename)
    loaded(~Reason, transport, credentials)
