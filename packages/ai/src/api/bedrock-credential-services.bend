import Base
import ./credential-http.bend as Http
import ../types.bend as T
import ../utils/json.bend as JsonWire
import ../../../runtime/src/aws-sigv4.bend as SigV4
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/timer.bend as Timer

# The AWS services the SDK's default credential chain calls, as the pinned
# @aws-sdk/nested-clients and credential providers use them: STS AssumeRole
# (signed with the source credentials) and AssumeRoleWithWebIdentity
# (awsQuery, XML responses), SSO GetRoleCredentials and SSO-OIDC CreateToken
# (JSON), the ECS/EKS container credentials endpoint and the EC2 instance
# metadata service. bedrock-credentials.bend composes them into the chain.

# HTTP
# ----

def httpErrorMessage(error: Http.Failure) -> String:
  match error:
    case Http.TimedOut{}: "TimeoutError"
    case Http.Unreachable{}: "fetch failed"
    case Http.Aborted{}: "Request aborted"
    case Http.InvalidRequest{message}: message

def properties(fields: List<&2, SigV4.Field>) -> List<&2, R.Property<String>>:
  match fields:
    case Nil{}: Nil{}
    case SigV4.Field{name, value} <> rest: R.Property{name, value} <> properties(rest)

# One request under a timeout (milliseconds), over credential-http.bend.
def request(~Reason: Data, +transport: Http.Transport<Reason>, method: String, url: String, fields: List<&2, SigV4.Field>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Http.Failure, Http.Reply>):
  Http.request(~Reason, transport, method, url, properties(fields), body, timeout)

def NO_TIMEOUT() -> U32: Http.NO_TIMEOUT()

# The SDK clients' standard retry strategy
# ---------------------------------------

# How a service reports its error code: awsQuery XML (STS) or JSON
# (SSO, SSO-OIDC).
type ErrorFormat is Data:
  QueryXml{}
  JsonBody{}

def THROTTLING_CODES() -> List<&2, String>: ["BandwidthLimitExceeded", "EC2ThrottledException", "LimitExceededException", "PriorRequestNotComplete", "ProvisionedThroughputExceededException", "RequestLimitExceeded", "RequestThrottled", "RequestThrottledException", "SlowDown", "ThrottledException", "Throttling", "ThrottlingException", "TooManyRequestsException", "TransactionInProgressException"]

def TRANSIENT_CODES() -> List<&2, String>: ["TimeoutError", "RequestTimeout", "RequestTimeoutException"]

def listed(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || listed(rest, name)

def afterPrefix(+text: String, +prefix: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{c, rest}: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(SCon{c, rest}, prefix), _ => Some{String.drop(SCon{c, rest}, String.length(prefix))}, _ => afterPrefix(rest, prefix))(Unit{})

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

def untilPrefix(+text: String, +prefix: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{c, rest}: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(SCon{c, rest}, prefix), _ => Some{""}, _ => Maybe.map(&2, String, String, tail => SCon{c, tail}, untilPrefix(rest, prefix)))(Unit{})

def within(value: Maybe<&2, String>, +tag: String) -> Maybe<&2, String>:
  match value:
    case Some{text}: untilPrefix(text, "</" ++ tag ++ ">")
    case None{}: None{}

# The text of the first `<tag>` element, entities decoded.
def xmlText(+body: String, +tag: String) -> Maybe<&2, String>:
  Maybe.map(&2, String, String, unescape, within(afterPrefix(body, "<" ++ tag ++ ">"), tag))

def parsedValue(value: Result<&2, &2, Decode.ParseError, V.Value>) -> V.Value:
  match value:
    case Done{item}: item
    case Fail{_}: V.Null{}

def parsed(+body: String) -> V.Value: parsedValue(Decode.parse(body))

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def errorCode(format: ErrorFormat, +body: String) -> String:
  match format:
    case QueryXml{}: Maybe.default(&2, String, xmlText(body, "Code"), "")
    case JsonBody{}: Maybe.default(&2, String, Maybe.or(&2, String, textOf(field(parsed(body), "__type")), textOf(field(parsed(body), "code"))), "")

# Why a failed attempt is retried: throttling (the longer base delay), a
# transient or server error, or not at all.
type RetryKind is Data:
  NoRetry{}
  Throttled{}
  Transient{}

def statusKind(+status: U32, +code: String) -> RetryKind:
  Bool.pick(RetryKind, U32.is_eq(status, 429) || listed(THROTTLING_CODES(), code), Throttled{}, Bool.pick(RetryKind, (U32.is_ge(status, 500) && U32.is_le(status, 599)) || listed(TRANSIENT_CODES(), code), Transient{}, NoRetry{}))

def retryKind(format: ErrorFormat, result: Result<&2, &2, Http.Failure, Http.Reply>) -> RetryKind:
  match result:
    case Fail{Http.TimedOut{}}: Transient{}
    case Fail{Http.Unreachable{}}: Transient{}
    case Fail{_}: NoRetry{}
    case Done{Http.Reply{+status, _, +body}}: Bool.pick(RetryKind, U32.is_ge(status, 200) && U32.is_lt(status, 300), NoRetry{}, statusKind(status, errorCode(format, body)))

def power(exponent: Nat, +base: Nat) -> Nat:
  match exponent:
    case 0n: base
    case 1n+left: power(left, Nat.mul(base, 2n))

# DefaultRetryBackoffStrategy: floor(random * min(base * 2^retries, 20 s)).
def backoffBound(kind: RetryKind, retries: Nat) -> Nat:
  match kind:
    case Throttled{}: Nat.min(power(retries, 500n), 20000n)
    case _: Nat.min(power(retries, 100n), 20000n)

def retryAllowed(kind: RetryKind) -> Bool:
  match kind:
    case NoRetry{}: False{}
    case _: True{}

def delayOf(drawn: Result<&2, &2, Random.Error, Nat>) -> U32:
  match drawn:
    case Done{n}: U32.from_nat(n)
    case Fail{_}: 0

# StandardRetryStrategy: three attempts in all, retrying throttling,
# transient and server errors after a jittered exponential backoff.
@unsafe def sdkAttempts(~Reason: Data, +transport: Http.Transport<Reason>, +format: ErrorFormat, +method: String, +url: String, +fields: List<&2, SigV4.Field>, +body: Headers.Input, +timeout: U32, +retries: Nat) -> IO(Result<&2, &2, Http.Failure, Http.Reply>):
  do IO<Result<&2, &2, Http.Failure, Http.Reply>>:
    +result : Result<&2, &2, Http.Failure, Http.Reply> <- request(~Reason, transport, method, url, fields, body, timeout)
    +kind : RetryKind <- IO.pure(RetryKind, retryKind(format, result))
    Bool.pick(Unit -> IO(Result<&2, &2, Http.Failure, Http.Reply>), retryAllowed(kind) && Nat.is_lt(retries, 2n), _ =>
      do IO<Result<&2, &2, Http.Failure, Http.Reply>>:
        drawn : Result<&2, &2, Random.Error, Nat> <- Random.randomIndex(backoffBound(kind, retries))
        slept : Result<&2, &2, Abort.AbortReason<Reason>, Unit> <- Timer.sleep(Reason, delayOf(drawn), Http.signalOf(Reason, transport))
        sdkAttempts(~Reason, transport, format, method, url, fields, body, timeout, 1n + retries), _ => IO.pure(Result<&2, &2, Http.Failure, Http.Reply>, result))(Unit{})

def sdkRequest(~Reason: Data, +transport: Http.Transport<Reason>, format: ErrorFormat, method: String, url: String, fields: List<&2, SigV4.Field>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Http.Failure, Http.Reply>):
  sdkAttempts(~Reason, transport, format, method, url, fields, body, timeout, 0n)

# XML (awsQuery responses)
# ------------------------

# SDK errors
# ----------

# A service error as the SDK throws it: its name (the error code) and message.
type ServiceError is Data:
  ServiceError{name: String, message: String}

def unknownError(status: U32) -> ServiceError: ServiceError{"Unknown", "UnknownError"}

# awsQuery: <ErrorResponse><Error><Code/><Message/></Error></ErrorResponse>.
def queryError(+body: String) -> ServiceError: ServiceError{Maybe.default(&2, String, xmlText(body, "Code"), "Unknown"), Maybe.default(&2, String, xmlText(body, "Message"), "UnknownError")}

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

def stsResponse(response: Result<&2, &2, Http.Failure, Http.Reply>, invalid: String) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{Http.Reply{+status, _, +body}}:
      Bool.pick(Unit -> Result<&2, &2, ServiceError, SigV4.Credentials>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => credentialsFrom(xmlText(body, "AccessKeyId"), xmlText(body, "SecretAccessKey"), xmlText(body, "SessionToken"), invalid), _ => Fail{queryError(body)})(Unit{})

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

# STS AssumeRole, signed with the source credentials.
def assumeRole(~Reason: Data, +transport: Http.Transport<Reason>, +endpoint: String, region: String, source: SigV4.Credentials, +roleArn: String, sessionName: String, externalId: Maybe<&2, String>, duration: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  +body = formBody(List.concat(&2, URL.Entry, [[URL.Entry{"Action", "AssumeRole"}, URL.Entry{"Version", "2011-06-15"}, URL.Entry{"RoleArn", roleArn}, URL.Entry{"RoleSessionName", sessionName}, URL.Entry{"DurationSeconds", duration}], optionalEntry("ExternalId", externalId)]))
  +parsed = URL.parse(Http.contextOf(Reason, transport), endpoint)
  +bytes = Utf8.encode(body)
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    now : F64 <- Date.now()
    +fields : List<&2, SigV4.Field> <- IO.pure(List<&2, SigV4.Field>, signedFields(SigV4.sign(source, region, "sts", SigV4.amzDate(Maybe.default(&2, String, Date.formatIso(now), "1970-01-01T00:00:00.000Z")), SigV4.Request{"POST", pathAndQuery(parsed), Nil{}, [SigV4.Field{"content-type", "application/x-www-form-urlencoded"}, SigV4.Field{"host", hostOf(parsed)}, SigV4.Field{"content-length", Nat.show(List.length(&2, U32, bytes))}], bytes})))
    response : Result<&2, &2, Http.Failure, Http.Reply> <- sdkRequest(~Reason, transport, QueryXml{}, "POST", endpoint, fields, Headers.Text{body}, NO_TIMEOUT())
    return stsResponse(response, "Invalid response from STS.assumeRole call with role " ++ roleArn)

# STS AssumeRoleWithWebIdentity (unsigned).
def assumeRoleWithWebIdentity(~Reason: Data, +transport: Http.Transport<Reason>, endpoint: String, +roleArn: String, sessionName: String, token: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  +body = formBody([URL.Entry{"Action", "AssumeRoleWithWebIdentity"}, URL.Entry{"Version", "2011-06-15"}, URL.Entry{"RoleArn", roleArn}, URL.Entry{"RoleSessionName", sessionName}, URL.Entry{"WebIdentityToken", token}])
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    response : Result<&2, &2, Http.Failure, Http.Reply> <- sdkRequest(~Reason, transport, QueryXml{}, "POST", endpoint, [SigV4.Field{"content-type", "application/x-www-form-urlencoded"}], Headers.Text{body}, NO_TIMEOUT())
    return stsResponse(response, "Invalid response from STS.assumeRoleWithWebIdentity call with role " ++ roleArn)

# JSON services
# -------------

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

def ssoResponse(response: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, ServiceError, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{Http.Reply{+status, _, +body}}: Bool.pick(Unit -> Result<&2, &2, ServiceError, SigV4.Credentials>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => roleCredentials(parsed(body)), _ => Fail{jsonError(body)})(Unit{})

# SSO GetRoleCredentials (bearer token header, no signature).
def getRoleCredentials(~Reason: Data, +transport: Http.Transport<Reason>, endpoint: String, accountId: String, roleName: String, accessToken: String) -> IO(Result<&2, &2, ServiceError, SigV4.Credentials>):
  do IO<Result<&2, &2, ServiceError, SigV4.Credentials>>:
    response : Result<&2, &2, Http.Failure, Http.Reply> <- sdkRequest(~Reason, transport, JsonBody{}, "GET", trimmedBase(endpoint) ++ "/federation/credentials?" ++ URL.serializeSearchParams([URL.Entry{"account_id", accountId}, URL.Entry{"role_name", roleName}]), [SigV4.Field{"x-amz-sso_bearer_token", accessToken}], Headers.Absent{}, NO_TIMEOUT())
    return ssoResponse(response)

type OidcToken is Data:
  OidcToken{accessToken: Maybe<&2, String>, expiresIn: Maybe<&2, F64>, refreshToken: Maybe<&2, String>}

def oidcResponse(response: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, ServiceError, OidcToken>:
  match response:
    case Fail{error}: Fail{ServiceError{"Error", httpErrorMessage(error)}}
    case Done{Http.Reply{+status, _, +body}}:
      +json = parsed(body)
      Bool.pick(Unit -> Result<&2, &2, ServiceError, OidcToken>, U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => Done{OidcToken{textOf(field(json, "accessToken")), numberOf(field(json, "expiresIn")), textOf(field(json, "refreshToken"))}}, _ => Fail{jsonError(body)})(Unit{})

# SSO-OIDC CreateToken with the refresh token grant.
def createToken(~Reason: Data, +transport: Http.Transport<Reason>, endpoint: String, clientId: String, clientSecret: String, refreshToken: String) -> IO(Result<&2, &2, ServiceError, OidcToken>):
  +body = Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"clientId", T.JsonString{clientId}}, R.Property{"clientSecret", T.JsonString{clientSecret}}, R.Property{"grantType", T.JsonString{"refresh_token"}}, R.Property{"refreshToken", T.JsonString{refreshToken}}]}}), "{}")
  do IO<Result<&2, &2, ServiceError, OidcToken>>:
    response : Result<&2, &2, Http.Failure, Http.Reply> <- sdkRequest(~Reason, transport, JsonBody{}, "POST", trimmedBase(endpoint) ++ "/token", [SigV4.Field{"content-type", "application/json"}], Headers.Text{body}, NO_TIMEOUT())
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
def containerResponse(response: Http.Reply) -> Result<&2, &2, String, SigV4.Credentials>:
  match response:
    case Http.Reply{+status, _, +body}:
      Bool.pick(Unit -> Result<&2, &2, String, SigV4.Credentials>, U32.is_eq(status, 200), _ => containerJson(metadataCredentials(parsed(body))), _ => Fail{"Server responded with status: " ++ U32.show(status)})(Unit{})

def containerResult(response: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, String, SigV4.Credentials>:
  match response:
    case Fail{error}: Fail{httpErrorMessage(error)}
    case Done{text}: containerResponse(text)

# One container credentials request (fromHttp's GET with the authorization
# token), under the one second timeout.
def containerRequest(~Reason: Data, +transport: Http.Transport<Reason>, url: String, token: Maybe<&2, String>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  do IO<Result<&2, &2, String, SigV4.Credentials>>:
    response : Result<&2, &2, Http.Failure, Http.Reply> <- request(~Reason, transport, "GET", url, Maybe.default(&2, List<&2, SigV4.Field>, Maybe.map(&2, String, List<&2, SigV4.Field>, value => [SigV4.Field{"Authorization", value}], token), Nil{}), Headers.Absent{}, 1000)
    return containerResult(response)

# IMDS: the metadata token, the role name, the role's credentials.
type Imds is Data:
  ImdsText{status: U32, body: String}
  ImdsFailed{error: Http.Failure}

def imdsOf(response: Result<&2, &2, Http.Failure, Http.Reply>) -> Imds:
  match response:
    case Fail{error}: ImdsFailed{error}
    case Done{Http.Reply{status, _, body}}: ImdsText{status, body}

def imdsRequest(~Reason: Data, +transport: Http.Transport<Reason>, method: String, url: String, fields: List<&2, SigV4.Field>) -> IO(Imds):
  do IO<Imds>:
    response : Result<&2, &2, Http.Failure, Http.Reply> <- request(~Reason, transport, method, url, fields, Headers.Absent{}, 1000)
    return imdsOf(response)

def imdsCredentials(+body: String) -> Maybe<&2, SigV4.Credentials>: metadataCredentials(parsed(body))
