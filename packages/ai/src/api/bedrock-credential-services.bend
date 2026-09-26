import Base
import ./provider-fetch.bend as Http
import ../types.bend as T
import ../utils/json.bend as JsonWire
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/aws-sigv4.bend as SigV4
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8

# The AWS services the SDK's default credential chain calls, as the pinned
# @aws-sdk/nested-clients and credential providers use them: STS AssumeRole
# (signed with the source credentials) and AssumeRoleWithWebIdentity
# (awsQuery, XML responses), SSO GetRoleCredentials and SSO-OIDC CreateToken
# (JSON), the ECS/EKS container credentials endpoint and the EC2 instance
# metadata service. bedrock-credentials.bend composes them into the chain.
# The SDK clients' retries (standard mode, three attempts) are not ported.

# HTTP
# ----

type Transport<-Reason: Data> is Data:
  Transport{fetch: Fetch.Fetch(Reason), urlContext: URL.Context, signal: Abort.AbortSignal<Reason>}

type HttpText is Data:
  HttpText{status: U32, body: String}

type HttpError is Data:
  TimedOut{}
  Unreachable{}
  Aborted{}
  InvalidRequest{message: String}

def httpErrorMessage(error: HttpError) -> String:
  match error:
    case TimedOut{}: "TimeoutError"
    case Unreachable{}: "fetch failed"
    case Aborted{}: "Request aborted"
    case InvalidRequest{message}: message

def bodyText(~Reason: Data, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> String:
  match text:
    case Done{body}: body
    case Fail{_}: ""

def failedWith(expired: Bool, aborted: Bool) -> HttpError:
  Bool.pick(HttpError, aborted, Aborted{}, Bool.pick(HttpError, expired, TimedOut{}, Unreachable{}))

def isExpired(~Reason: Data, closed: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Bool:
  match closed:
    case Some{Abort.Supplied{Deadline.Expired{}}}: True{}
    case _: False{}

def received(~Reason: Data, response: Fetch.Result_(Reason)) -> IO(Result<&2, &2, Unit, HttpText>):
  match response:
    case Fail{_}: IO.pure(Result<&2, &2, Unit, HttpText>, Fail{Unit{}})
    case Done{Response.Response{+metadata, body}}:
      do IO<Result<&2, &2, Unit, HttpText>>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 16777216n, body)
        return Done{HttpText{Response.metadataStatus(metadata), bodyText(~Reason, text)}}

def classified(~Reason: Data, result: Result<&2, &2, Unit, HttpText>, closed: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>, aborted: Bool) -> Result<&2, &2, HttpError, HttpText>:
  match result:
    case Done{text}: Done{text}
    case Fail{_}: Fail{failedWith(isExpired(~Reason, closed), aborted)}

def exchanged(~Reason: Data, fetch: Fetch.Fetch(Reason), +parent: Abort.AbortSignal<Reason>, url: URL.URL, method: String, headers: Headers.Headers, body: Headers.Input, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Result<&2, &2, HttpError, HttpText>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, HttpError, HttpText>>:
        response : Fetch.Result_(Reason) <- C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, method, headers, body, signal})
        result : Result<&2, &2, Unit, HttpText> <- received(~Reason, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        aborted : Bool <- Abort.aborted(Reason, parent)
        return classified(~Reason, result, closed, aborted)

# Host and Content-Length are written by the transport from the URL and body.
def headerFields(fields: List<&2, SigV4.Field>) -> List<&2, R.Property<String>>:
  match fields:
    case Nil{}: Nil{}
    case SigV4.Field{+name, value} <> rest:
      +tail = headerFields(rest)
      Bool.pick(List<&2, R.Property<String>>, String.eq(String.to_lower(name), "host") || String.eq(String.to_lower(name), "content-length"), tail, R.Property{name, value} <> tail)

def sendHeaders(~Reason: Data, transport: Transport<Reason>, +method: String, url: Result<&2, &2, URL.Error, URL.URL>, built: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, HttpError, HttpText>):
  match transport url built:
    case _ Fail{_} _: IO.pure(Result<&2, &2, HttpError, HttpText>, Fail{InvalidRequest{"Invalid URL"}})
    case _ _ Fail{_}: IO.pure(Result<&2, &2, HttpError, HttpText>, Fail{InvalidRequest{"Invalid header value"}})
    case Transport{fetch, _, +signal} Done{address} Done{headers}:
      do IO<Result<&2, &2, HttpError, HttpText>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, timeout, signal)
        exchanged(~Reason, fetch, signal, address, method, headers, body, Deadline.borrow(Reason, scope))

def sendParsed(~Reason: Data, transport: Transport<Reason>, +method: String, url: Result<&2, &2, URL.Error, URL.URL>, fields: List<&2, SigV4.Field>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, HttpError, HttpText>):
  sendHeaders(~Reason, transport, method, url, Http.headerList(headerFields(fields)), body, timeout)

def contextOf(~Reason: Data, transport: Transport<Reason>) -> URL.Context:
  match transport:
    case Transport{_, context, _}: context

def signalOf(~Reason: Data, transport: Transport<Reason>) -> Abort.AbortSignal<Reason>:
  match transport:
    case Transport{_, _, signal}: signal

# One request under a timeout (milliseconds).
def request(~Reason: Data, +transport: Transport<Reason>, method: String, url: String, fields: List<&2, SigV4.Field>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, HttpError, HttpText>):
  sendParsed(~Reason, transport, method, URL.parse(contextOf(~Reason, transport), url), fields, body, timeout)

def NO_TIMEOUT() -> U32: 4294967295

# XML (awsQuery responses)
# ------------------------

def afterPrefix(+text: String, +prefix: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{c, rest}: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(SCon{c, rest}, prefix), _ => Some{String.drop(SCon{c, rest}, String.length(prefix))}, _ => afterPrefix(rest, prefix))(Unit{})

def untilPrefix(+text: String, +prefix: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{c, rest}: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(SCon{c, rest}, prefix), _ => Some{""}, _ => Maybe.map(&2, String, String, tail => SCon{c, tail}, untilPrefix(rest, prefix)))(Unit{})

def entity(+text: String) -> String & String:
  Bool.pick(String & String, String.starts_with(text, "&amp;"), ("&", String.drop(text, 5n)), Bool.pick(String & String, String.starts_with(text, "&lt;"), ("<", String.drop(text, 4n)), Bool.pick(String & String, String.starts_with(text, "&gt;"), (">", String.drop(text, 4n)), Bool.pick(String & String, String.starts_with(text, "&quot;"), ("\"", String.drop(text, 6n)), Bool.pick(String & String, String.starts_with(text, "&apos;"), ("'", String.drop(text, 6n)), ("&", String.drop(text, 1n)))))))

def firstOf(pair: String & String) -> String:
  match pair:
    case (first, _): first

def secondOf(pair: String & String) -> String:
  match pair:
    case (_, second): second

@unsafe def unescape(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'&', rest}:
      +pair = entity(SCon{'&', rest})
      firstOf(pair) ++ unescape(secondOf(pair))
    case SCon{c, rest}: SCon{c, unescape(rest)}

def within(value: Maybe<&2, String>, +tag: String) -> Maybe<&2, String>:
  match value:
    case Some{text}: untilPrefix(text, "</" ++ tag ++ ">")
    case None{}: None{}

# The text of the first `<tag>` element, entities decoded.
def xmlText(+body: String, +tag: String) -> Maybe<&2, String>:
  Maybe.map(&2, String, String, unescape, within(afterPrefix(body, "<" ++ tag ++ ">"), tag))

# SDK errors
# ----------

# A service error as the SDK throws it: its name (the error code) and message.
type ServiceError is Data:
  ServiceError{name: String, message: String}

def unknownError(status: U32) -> ServiceError: ServiceError{"Unknown", "UnknownError"}

# awsQuery: <ErrorResponse><Error><Code/><Message/></Error></ErrorResponse>.
def queryError(response: HttpText) -> ServiceError:
  match response:
    case HttpText{status, +body}: ServiceError{Maybe.default(&2, String, xmlText(body, "Code"), "Unknown"), Maybe.default(&2, String, xmlText(body, "Message"), "UnknownError")}

# STS
# ---

type StsCredentials is Data:
  StsCredentials{credentials: SigV4.Credentials}

def stsEndpoint(override: Maybe<&2, String>, +region: String) -> String:
  match override:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "https://sts." ++ region ++ Bool.pick(String, String.starts_with(region, "cn-"), ".amazonaws.com.cn", ".amazonaws.com")

def formBody(entries: List<&2, URL.Entry>) -> String: URL.serializeSearchParams(entries)

def optionalEntry(name: String, value: Maybe<&2, String>) -> List<&2, URL.Entry>:
  match value:
    case Some{text}: [URL.Entry{name, text}]
    case None{}: Nil{}

def credentialsFrom(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>, message: String) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match access secret:
    case Some{SCon{a, as}} Some{SCon{s, ss}}: Done{SigV4.Credentials{SCon{a, as}, SCon{s, ss}, token}}
    case _ _: Fail{ServiceError{"Error", message}}

def stsResponse(response: Result<&2, &2, HttpError, HttpText>, invalid: String) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{HttpText{+status, +body}}:
      Bool.pick(Unit -> Result<&2, &2, ServiceError, SigV4.Credentials>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => credentialsFrom(xmlText(body, "AccessKeyId"), xmlText(body, "SecretAccessKey"), xmlText(body, "SessionToken"), invalid), _ => Fail{queryError(HttpText{status, body})})(Unit{})

def pathAndQuery(url: Result<&2, &2, URL.Error, URL.URL>) -> String:
  match url:
    case Done{URL.URL{_, _, _, _, _, path, _, _}}: URL.serializePath(path)
    case Fail{_}: "/"

def hostOf(url: Result<&2, &2, URL.Error, URL.URL>) -> String:
  match url:
    case Done{URL.URL{_, _, _, Some{host}, None{}, _, _, _}}: URL.serializeHost(host)
    case Done{URL.URL{_, _, _, Some{host}, Some{port}, _, _, _}}: URL.serializeHost(host) ++ ":" ++ U32.show(port)
    case _: ""

def signedFields(signed: SigV4.Signed) -> List<&2, SigV4.Field>:
  match signed:
    case SigV4.Signed{headers, _, _}: headers

def parsedValue(value: Result<&2, &2, Decode.ParseError, V.Value>) -> V.Value:
  match value:
    case Done{item}: item
    case Fail{_}: V.Null{}

def parsed(+body: String) -> V.Value: parsedValue(Decode.parse(body))

# STS AssumeRole, signed with the source credentials.
def assumeRole(~Reason: Data, +transport: Transport<Reason>, +endpoint: String, region: String, source: SigV4.Credentials, +roleArn: String, sessionName: String, externalId: Maybe<&2, String>, duration: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  +body = formBody(List.concat(&2, URL.Entry, [[URL.Entry{"Action", "AssumeRole"}, URL.Entry{"Version", "2011-06-15"}, URL.Entry{"RoleArn", roleArn}, URL.Entry{"RoleSessionName", sessionName}, URL.Entry{"DurationSeconds", duration}], optionalEntry("ExternalId", externalId)]))
  +parsed = URL.parse(contextOf(~Reason, transport), endpoint)
  +bytes = Utf8.encode(body)
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    now : F64 <- Date.now()
    +fields : List<&2, SigV4.Field> <- IO.pure(List<&2, SigV4.Field>, signedFields(SigV4.sign(source, region, "sts", SigV4.amzDate(Maybe.default(&2, String, Date.formatIso(now), "1970-01-01T00:00:00.000Z")), SigV4.Request{"POST", pathAndQuery(parsed), Nil{}, [SigV4.Field{"content-type", "application/x-www-form-urlencoded"}, SigV4.Field{"host", hostOf(parsed)}, SigV4.Field{"content-length", Nat.show(List.length(&2, U32, bytes))}], bytes})))
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, "POST", endpoint, fields, Headers.Text{body}, NO_TIMEOUT())
    return stsResponse(response, "Invalid response from STS.assumeRole call with role " ++ roleArn)

# STS AssumeRoleWithWebIdentity (unsigned).
def assumeRoleWithWebIdentity(~Reason: Data, +transport: Transport<Reason>, endpoint: String, +roleArn: String, sessionName: String, token: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  +body = formBody([URL.Entry{"Action", "AssumeRoleWithWebIdentity"}, URL.Entry{"Version", "2011-06-15"}, URL.Entry{"RoleArn", roleArn}, URL.Entry{"RoleSessionName", sessionName}, URL.Entry{"WebIdentityToken", token}])
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, "POST", endpoint, [SigV4.Field{"content-type", "application/x-www-form-urlencoded"}], Headers.Text{body}, NO_TIMEOUT())
    return stsResponse(response, "Invalid response from STS.assumeRoleWithWebIdentity call with role " ++ roleArn)

# JSON services
# -------------

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

def jsonErrorOf(+json: V.Value) -> ServiceError:
  ServiceError{Maybe.default(&2, String, Maybe.or(&2, String, textOf(field(json, "__type")), textOf(field(json, "code"))), "Unknown"), Maybe.default(&2, String, Maybe.or(&2, String, textOf(field(json, "message")), textOf(field(json, "Message"))), "UnknownError")}

# restJson errors: the x-amzn-errortype-style `__type`/`code`, and `message`.
def jsonError(+body: String) -> ServiceError: jsonErrorOf(parsed(body))

def ssoEndpoint(override: Maybe<&2, String>, +region: String) -> String:
  match override:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "https://portal.sso." ++ region ++ Bool.pick(String, String.starts_with(region, "cn-"), ".amazonaws.com.cn", ".amazonaws.com")

def oidcEndpoint(override: Maybe<&2, String>, +region: String) -> String:
  match override:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "https://oidc." ++ region ++ Bool.pick(String, String.starts_with(region, "cn-"), ".amazonaws.com.cn", ".amazonaws.com")

def trimmedBase(+base: String) -> String: Bool.pick(String, String.ends_with(base, "/"), String.take(base, Nat.sub(String.length(base), 1n)), base)

def ssoFields(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>, expiration: Maybe<&2, F64>) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match access secret token expiration:
    case Some{SCon{a, as}} Some{SCon{s, ss}} Some{SCon{t, ts}} Some{_}: Done{SigV4.Credentials{SCon{a, as}, SCon{s, ss}, Some{SCon{t, ts}}}}
    case _ _ _ _: Fail{ServiceError{"CredentialsProviderError", "SSO returns an invalid temporary credential."}}

def roleFields(value: Maybe<&2, V.Value>) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match value:
    case Some{+role}: ssoFields(textOf(field(role, "accessKeyId")), textOf(field(role, "secretAccessKey")), textOf(field(role, "sessionToken")), numberOf(field(role, "expiration")))
    case None{}: ssoFields(None{}, None{}, None{}, None{})

def roleCredentials(json: V.Value) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  roleFields(field(json, "roleCredentials"))

def ssoResponse(response: Result<&2, &2, HttpError, HttpText>) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{HttpText{+status, +body}}: Bool.pick(Unit -> Result<&2, &2, ServiceError, SigV4.Credentials>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => roleCredentials(parsed(body)), _ => Fail{jsonError(body)})(Unit{})

# SSO GetRoleCredentials (bearer token header, no signature).
def getRoleCredentials(~Reason: Data, +transport: Transport<Reason>, endpoint: String, accountId: String, roleName: String, accessToken: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, "GET", trimmedBase(endpoint) ++ "/federation/credentials?" ++ URL.serializeSearchParams([URL.Entry{"account_id", accountId}, URL.Entry{"role_name", roleName}]), [SigV4.Field{"x-amz-sso_bearer_token", accessToken}], Headers.Absent{}, NO_TIMEOUT())
    return ssoResponse(response)

type OidcToken is Data:
  OidcToken{accessToken: Maybe<&2, String>, expiresIn: Maybe<&2, F64>, refreshToken: Maybe<&2, String>}

def oidcResponse(response: Result<&2, &2, HttpError, HttpText>) -> Result<&2, &2, ServiceError, OidcToken>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{HttpText{+status, +body}}:
      +json = parsed(body)
      Bool.pick(Unit -> Result<&2, &2, ServiceError, OidcToken>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => Done{OidcToken{textOf(field(json, "accessToken")), numberOf(field(json, "expiresIn")), textOf(field(json, "refreshToken"))}}, _ => Fail{jsonError(body)})(Unit{})

# SSO-OIDC CreateToken with the refresh token grant.
def createToken(~Reason: Data, +transport: Transport<Reason>, endpoint: String, clientId: String, clientSecret: String, refreshToken: String) -> IO(Result<&2, &2, ServiceError, OidcToken>):
  +body = Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"clientId", T.JsonString{clientId}}, R.Property{"clientSecret", T.JsonString{clientSecret}}, R.Property{"grantType", T.JsonString{"refresh_token"}}, R.Property{"refreshToken", T.JsonString{refreshToken}}]}}), "{}")
  do IO<Result<&2, &2, ServiceError, OidcToken>>:
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, "POST", trimmedBase(endpoint) ++ "/token", [SigV4.Field{"content-type", "application/json"}], Headers.Text{body}, NO_TIMEOUT())
    return oidcResponse(response)

# Container and instance metadata
# -------------------------------

def metadataFields(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>, expiration: Maybe<&2, String>) -> Maybe<&2, SigV4.Credentials>:
  match access secret token expiration:
    case Some{a} Some{s} Some{t} Some{_}: Some{SigV4.Credentials{a, s, Some{t}}}
    case _ _ _ _: None{}

def metadataCredentials(+json: V.Value) -> Maybe<&2, SigV4.Credentials>:
  metadataFields(textOf(field(json, "AccessKeyId")), textOf(field(json, "SecretAccessKey")), textOf(field(json, "Token")), textOf(field(json, "Expiration")))

def containerJson(credentials: Maybe<&2, SigV4.Credentials>) -> Result<&2, &2, String, SigV4.Credentials>:
  match credentials:
    case Some{value}: Done{value}
    case None{}: Fail{"HTTP credential provider response not of the required format, an object matching: { AccessKeyId: string, SecretAccessKey: string, Token: string, Expiration: string(rfc3339) }"}

# The container endpoint's response (@aws-sdk/credential-provider-http
# getCredentials): a Server responded message for other statuses.
def containerResponse(response: HttpText) -> Result<&2, &2, String, SigV4.Credentials>:
  match response:
    case HttpText{+status, +body}:
      Bool.pick(Unit -> Result<&2, &2, String, SigV4.Credentials>, U32.is_eq(status, 200), _ => containerJson(metadataCredentials(parsed(body))), _ => Fail{"Server responded with status: " ++ U32.show(status)})(Unit{})

def containerResult(response: Result<&2, &2, HttpError, HttpText>) -> Result<&2, &2, String, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{httpErrorMessage(error)}
    case Done{text}: containerResponse(text)

# One container credentials request (fromHttp's GET with the authorization
# token), under the one second timeout.
def containerRequest(~Reason: Data, +transport: Transport<Reason>, url: String, token: Maybe<&2, String>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  do IO<Result<&2, &2, String, SigV4.Credentials>>:
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, "GET", url, Maybe.default(&2, List<&2, SigV4.Field>, Maybe.map(&2, String, List<&2, SigV4.Field>, value => [SigV4.Field{"Authorization", value}], token), Nil{}), Headers.Absent{}, 1000)
    return containerResult(response)

# IMDS: the metadata token, the role name, the role's credentials.
type Imds is Data:
  ImdsText{status: U32, body: String}
  ImdsFailed{error: HttpError}

def imdsOf(response: Result<&2, &2, HttpError, HttpText>) -> Imds:
  match response:
    case Fail{error}: ImdsFailed{error}
    case Done{HttpText{status, body}}: ImdsText{status, body}

def imdsRequest(~Reason: Data, +transport: Transport<Reason>, method: String, url: String, fields: List<&2, SigV4.Field>) -> IO(Imds):
  do IO<Imds>:
    response : Result<&2, &2, HttpError, HttpText> <- request(~Reason, transport, method, url, fields, Headers.Absent{}, 1000)
    return imdsOf(response)

def imdsCredentials(+body: String) -> Maybe<&2, SigV4.Credentials>: metadataCredentials(parsed(body))
