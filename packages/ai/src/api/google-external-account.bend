import Base
import ./credential-http.bend as Http
import ../utils/provider-env.bend as Env
import ../utils/json.bend as JsonWire
import ../types.bend as T
import ../../../runtime/src/aws-sigv4.bend as SigV4
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/child-process.bend as Process
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8

# google-auth-library 10.6.2's workload and workforce identity federation:
# "external_account" credentials (IdentityPoolClient with file and URL
# subject tokens, AwsClient, PluggableAuthClient) exchanged for a Google
# access token at the STS token endpoint, optionally impersonating a service
# account, and "external_account_authorized_user" refresh tokens.
# Certificate (mTLS) subject tokens are not provided: the TLS client has no
# client certificates.

def DEFAULT_SCOPE() -> String: "https://www.googleapis.com/auth/cloud-platform"

def STS_GRANT_TYPE() -> String: "urn:ietf:params:oauth:grant-type:token-exchange"

def STS_REQUEST_TOKEN_TYPE() -> String: "urn:ietf:params:oauth:token-type:access_token"

def AUTH_VERSION() -> String: "10.6.2"

def env(+name: String) -> IO(Maybe<&2, String>): Env.getProviderEnvValue(name, None{})

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def orFail(value: Maybe<&2, String>, message: String) -> Result<&2, &2, String, String>:
  match value:
    case Some{found}: Done{found}
    case None{}: Fail{message}

def orFailJson(value: Maybe<&2, V.Value>, message: String) -> Result<&2, &2, String, V.Value>:
  match value:
    case Some{found}: Done{found}
    case None{}: Fail{message}

# The first occurrence of `pattern` replaced (String.prototype.replace with a
# string pattern).
def replaceFirst(text: String, +pattern: String, +value: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+c, +rest}: Bool.pick(String, String.starts_with(SCon{c, rest}, pattern), value ++ String.drop(SCon{c, rest}, String.length(pattern)), SCon{c, replaceFirst(rest, pattern, value)})

# JSON options
# ------------

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def upperIf(upper: Bool, +c: Char) -> Char: Bool.pick(Char, upper, Char.to_upper(c), c)

def camelChars(text: String, upper: Bool) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'_', rest}: camelChars(rest, True{})
    case SCon{c, rest}: SCon{upperIf(upper, c), camelChars(rest, False{})}

def orCamel(found: Maybe<&2, V.Value>, value: V.Value, +name: String) -> Maybe<&2, V.Value>:
  match found:
    case Some{V.Null{}}: field(value, camelChars(name, False{}))
    case Some{other}: Some{other}
    case None{}: field(value, camelChars(name, False{}))

# originalOrCamelOptions(options).get(name): the snake_case member, else its
# camelCase spelling.
def opt(+value: V.Value, +name: String) -> Maybe<&2, V.Value>: orCamel(field(value, name), value, name)

# A truthy string member.
def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{n}}: Some{n}
    case _: None{}

def present(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Null{}}: False{}
    case Some{V.Text{SNil{}}}: False{}
    case Some{V.Boolean{False{}}}: False{}
    case Some{_}: True{}
    case None{}: False{}

def stringFields(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> stringFields(rest)
    case _ <> rest: stringFields(rest)

def headerMap(value: Maybe<&2, V.Value>) -> List<&2, R.Property<String>>:
  match value:
    case Some{V.ObjectValue{R.Record{entries}}}: stringFields(entries)
    case _: Nil{}

# Configuration
# -------------

type Format is Data:
  TextFormat{}
  JsonFormat{field: String}

type Source is Data:
  FileSource{path: String, format: Format}
  UrlSource{url: String, headers: List<&2, R.Property<String>>, format: Format}
  AwsSource{regionUrl: Maybe<&2, String>, url: Maybe<&2, String>, sessionTokenUrl: Maybe<&2, String>, verificationUrl: String}
  ExecutableSource{command: String, timeoutMillis: F64, outputFile: Maybe<&2, String>}

type External is Data:
  External{audience: String, subjectTokenType: String, tokenUrl: String, source: Source, clientId: Maybe<&2, String>, clientSecret: Maybe<&2, String>, impersonationUrl: Maybe<&2, String>, lifetime: Maybe<&2, F64>, workforceUserProject: Maybe<&2, String>, quotaProjectId: Maybe<&2, String>}

type AuthorizedUser is Data:
  AuthorizedUser{clientId: String, clientSecret: String, refreshToken: String, tokenUrl: String, quotaProjectId: Maybe<&2, String>}

def sourceKind(source: Source) -> String:
  match source:
    case FileSource{_, _}: "file"
    case UrlSource{_, _, _}: "url"
    case AwsSource{_, _, _, _}: "aws"
    case ExecutableSource{_, _, _}: "executable"

def formatJson(name: Maybe<&2, String>) -> Result<&2, &2, String, Format>:
  match name:
    case Some{value}: Done{JsonFormat{value}}
    case None{}: Fail{"Missing subject_token_field_name for JSON credential_source format"}

# IdentityPoolClient's format checks.
def formatOf(+options: V.Value) -> Result<&2, &2, String, Format>:
  +formatType = Maybe.default(&2, String, text(opt(options, "type")), "text")
  +fieldName = text(opt(options, "subject_token_field_name"))
  Bool.pick(Result<&2, &2, String, Format>, String.eq(formatType, "text"), Done{TextFormat{}}, Bool.pick(Result<&2, &2, String, Format>, String.eq(formatType, "json"), formatJson(fieldName), Fail{"Invalid credential_source format \"" ++ formatType ++ "\""}))

def NO_POOL_SOURCE() -> String: "No valid Identity Pool \"credential_source\" provided, must be either file, url, or certificate."

def poolSource(format: Result<&2, &2, String, Format>, file: Maybe<&2, String>, url: Maybe<&2, String>, certificate: Bool, headers: List<&2, R.Property<String>>) -> Result<&2, &2, String, Source>:
  match format file url certificate:
    case Fail{message} _ _ _: Fail{message}
    case _ Some{_} Some{_} _: Fail{NO_POOL_SOURCE()}
    case _ _ Some{_} True{}: Fail{NO_POOL_SOURCE()}
    case _ Some{_} _ True{}: Fail{NO_POOL_SOURCE()}
    case Done{kind} Some{path} None{} False{}: Done{FileSource{path, kind}}
    case Done{kind} None{} Some{address} False{}: Done{UrlSource{address, headers, kind}}
    case _ None{} None{} True{}: Fail{"Certificate-based (mTLS) credential sources are not supported: the native TLS client has no client certificates"}
    case _ None{} None{} False{}: Fail{NO_POOL_SOURCE()}

def identityPool(+source: V.Value) -> Result<&2, &2, String, Source>:
  poolSource(formatOf(Maybe.default(&2, V.Value, opt(source, "format"), V.ObjectValue{R.new(V.Value)})), text(opt(source, "file")), text(opt(source, "url")), present(opt(source, "certificate")), headerMap(opt(source, "headers")))

def digitsOnly(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{c, SNil{}}: Char.is_digit(c)
    case SCon{c, rest}: Char.is_digit(c) && digitsOnly(rest)

def awsVersion(+id: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.starts_with(id, "aws") && digitsOnly(String.drop(id, 3n)), Some{String.drop(id, 3n)}, None{})

def trimZeros(text: String) -> String:
  match text:
    case SCon{'0', SCon{c, rest}}: trimZeros(SCon{c, rest})
    case other: other

# AwsClient.validateEnvironmentId.
def awsSource(version: Maybe<&2, String>, +source: V.Value, verification: Maybe<&2, String>) -> Result<&2, &2, String, Source>:
  match version verification:
    case Some{+digits} Some{url}: Bool.pick(Result<&2, &2, String, Source>, String.eq(trimZeros(digits), "1"), Done{AwsSource{text(opt(source, "region_url")), text(opt(source, "url")), text(opt(source, "imdsv2_session_token_url")), url}}, Fail{"aws version \"" ++ trimZeros(digits) ++ "\" is not supported in the current build."})
    case _ _: Fail{"No valid AWS \"credential_source\" provided"}

def timeoutChecked(+value: F64) -> Result<&2, &2, String, F64>:
  Bool.pick(Result<&2, &2, String, F64>, Bool.not(F.isAtLeast(F.compare(value, F.fromU32(5000)))) || F.isGreater(F.compare(value, F.fromU32(120000))), Fail{"Timeout must be between 5000 and 120000 milliseconds."}, Done{value})

def executableWith(command: Maybe<&2, String>, timeout: Maybe<&2, F64>, output: Maybe<&2, String>) -> Result<&2, &2, String, Source>:
  match command timeout:
    case None{} _: Fail{"No valid Pluggable Auth \"credential_source\" provided."}
    case Some{value} None{}: Done{ExecutableSource{value, F.fromU32(30000), output}}
    case Some{value} Some{+millis}: Result.map(&2, &2, String, F64, Source, checked => ExecutableSource{value, checked, output}, timeoutChecked(millis))

def executableSource(+executable: V.Value) -> Result<&2, &2, String, Source>:
  executableWith(text(opt(executable, "command")), number(opt(executable, "timeout_millis")), text(opt(executable, "output_file")))

def sourceFrom(+source: V.Value, environment: Maybe<&2, V.Value>, executable: Maybe<&2, V.Value>) -> Result<&2, &2, String, Source>:
  match environment executable:
    case Some{V.Text{SCon{c, cs}}} _: awsSource(awsVersion(SCon{c, cs}), source, text(opt(source, "regional_cred_verification_url")))
    case _ Some{V.ObjectValue{fields}}: executableSource(V.ObjectValue{fields})
    case _ _: identityPool(source)

# ExternalAccountClient.fromJSON: AWS when credential_source has an
# environment_id, an executable, else an identity pool.
def sourceOf(credentialSource: Maybe<&2, V.Value>) -> Result<&2, &2, String, Source>:
  match credentialSource:
    case Some{V.ObjectValue{+fields}}: sourceFrom(V.ObjectValue{fields}, opt(V.ObjectValue{fields}, "environment_id"), opt(V.ObjectValue{fields}, "executable"))
    case _: Fail{"A credential source or subject token supplier must be specified."}

def workforceAudience(+audience: String) -> Bool:
  String.starts_with(audience, "//iam.googleapis.com/locations/") && String.contains(audience, "/workforcePools/") && String.contains(audience, "/providers/")

def externalWith(+json: V.Value, audience: Maybe<&2, String>, source: Result<&2, &2, String, Source>) -> Result<&2, &2, String, External>:
  match audience source:
    case None{} _: Fail{"Cannot read properties of undefined (reading 'match')"}
    case _ Fail{message}: Fail{message}
    case Some{+value} Done{kind}:
      +workforce = text(opt(json, "workforce_pool_user_project"))
      Bool.pick(Result<&2, &2, String, External>, Maybe.is_some(&2, String, workforce) && Bool.not(workforceAudience(value)), Fail{"workforcePoolUserProject should not be set for non-workforce pool credentials."}, Done{External{value, Maybe.default(&2, String, text(opt(json, "subject_token_type")), ""), Maybe.default(&2, String, text(opt(json, "token_url")), "https://sts.googleapis.com/v1/token"), kind, text(opt(json, "client_id")), text(opt(json, "client_secret")), text(opt(json, "service_account_impersonation_url")), number(opt(Maybe.default(&2, V.Value, opt(json, "service_account_impersonation"), V.ObjectValue{R.new(V.Value)}), "token_lifetime_seconds")), workforce, text(opt(json, "quota_project_id"))}})

# An "external_account" credentials object, checked as the client
# constructors check it.
def external(+json: V.Value) -> Result<&2, &2, String, External>:
  externalWith(json, text(opt(json, "audience")), sourceOf(opt(json, "credential_source")))

# An "external_account_authorized_user" credentials object.
def authorizedUser(+json: V.Value) -> AuthorizedUser:
  AuthorizedUser{Maybe.default(&2, String, text(opt(json, "client_id")), "undefined"), Maybe.default(&2, String, text(opt(json, "client_secret")), ""), Maybe.default(&2, String, text(opt(json, "refresh_token")), "undefined"), Maybe.default(&2, String, text(opt(json, "token_url")), "https://sts.googleapis.com/v1/oauthtoken"), text(opt(json, "quota_project_id"))}

def quotaProject(config: External) -> Maybe<&2, String>:
  match config:
    case External{_, _, _, _, _, _, _, _, _, quota}: quota

def authorizedQuota(config: AuthorizedUser) -> Maybe<&2, String>:
  match config:
    case AuthorizedUser{_, _, _, _, quota}: quota

# Responses
# ---------

def jsonOf(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def oauthDescription(+message: String, value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{description}}: message ++ ": " ++ description
    case Some{V.Null{}}: message ++ ": null"
    case Some{_}: message ++ ": [object Object]"
    case None{}: message

def oauthUri(+message: String, value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{uri}}: message ++ " - " ++ uri
    case Some{_}: message ++ " - [object Object]"
    case None{}: message

def errorCode(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{code}}: code
    case Some{V.Null{}}: "null"
    case Some{V.Number{n}}: Maybe.default(&2, String, F.toJsonNumber(n), "NaN")
    case _: "undefined"

# getErrorFromOAuthErrorResponse: `Error code <error>[: <description>][ - <uri>]`.
def oauthErrorWith(json: Maybe<&2, V.Value>) -> String:
  match json:
    case Some{V.ObjectValue{+fields}}: oauthUri(oauthDescription("Error code " ++ errorCode(R.get(V.Value, fields, "error")), R.get(V.Value, fields, "error_description")), R.get(V.Value, fields, "error_uri"))
    case _: "Error code undefined"

def oauthError(+body: String) -> String: oauthErrorWith(jsonOf(Decode.parse(body)))

type Token is Data:
  Token{accessToken: String}

def tokenMember(json: Maybe<&2, V.Value>, name: String) -> Result<&2, &2, String, Token>:
  match json:
    case Some{value}: Done{Token{Maybe.default(&2, String, text(field(value, name)), "undefined")}}
    case None{}: Fail{"The token response is not valid JSON"}

# A JSON token response under gaxios; `oauth` failures are OAuth error
# responses.
def tokenReply(oauth: Bool, name: String, result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, String, Token>:
  match result:
    case Fail{failure}: Fail{Http.failureText(failure)}
    case Done{Http.Reply{+status, _, +body}}:
      Bool.pick(Result<&2, &2, String, Token>, U32.is_ge(status, 200) && U32.is_lt(status, 300), tokenMember(jsonOf(Decode.parse(body)), name), Fail{Bool.pick(String, oauth, oauthError(body), Http.apiError(status, body))})

# Subject tokens
# --------------

def decodedText(value: Utf8.Decoded) -> String:
  match value:
    case Utf8.Decoded{_, content}: content

def textOf(bytes: List<&2, U32>) -> String: decodedText(Utf8.decode(Utf8.create(), bytes))

def formattedJson(json: Maybe<&2, V.Value>, name: String, +origin: String) -> Result<&2, &2, String, String>:
  match json:
    case Some{value}: orFail(text(field(value, name)), "Unable to parse the subject_token from the credential_source " ++ origin)
    case None{}: Fail{"Unexpected token in JSON from the credential_source " ++ origin}

def formatted(format: Format, +raw: String, +origin: String) -> Result<&2, &2, String, String>:
  match format:
    case TextFormat{}: Bool.pick(Result<&2, &2, String, String>, String.is_empty(raw), Fail{"Unable to parse the subject_token from the credential_source " ++ origin}, Done{raw})
    case JsonFormat{name}: formattedJson(jsonOf(Decode.parse(raw)), name, origin)

def nodeError(error: FS.Error, syscall: String, path: String) -> String:
  match error:
    case FS.System{code, _}: FS.nodeMessage(code, syscall, path)
    case other: FS.errorMessage(other)

def fileRead(format: Format, bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, String>:
  match bytes:
    case Done{content}: formatted(format, textOf(content), "file")
    case Fail{error}: Fail{nodeError(error, "open", "")}

def fileKindChecked(format: Format, +path: String, kind: Result<&2, &2, FS.Error, FS.FileKind>) -> IO(Result<&2, &2, String, String>):
  match kind:
    case Done{FS.RegularFile{}}:
      do IO<Result<&2, &2, String, String>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        return fileRead(format, bytes)
    case _: IO.pure(Result<&2, &2, String, String>, Fail{"The file at " ++ path ++ " does not exist, or it is not a file. "})

def realFile(format: Format, +path: String, real: Result<&2, &2, FS.Error, String>) -> IO(Result<&2, &2, String, String>):
  match real:
    case Fail{error}: IO.pure(Result<&2, &2, String, String>, Fail{"The file at " ++ path ++ " does not exist, or it is not a file. " ++ nodeError(error, "lstat", path)})
    case Done{+resolved}:
      do IO<Result<&2, &2, String, String>>:
        kind : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(resolved)
        fileKindChecked(format, resolved, kind)

# FileSubjectTokenSupplier: the file's real path must be a regular file.
def fileToken(+path: String, format: Format) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    real : Result<&2, &2, FS.Error, String> <- FS.realpath(path)
    realFile(format, path, real)

def urlReply(format: Format, result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{failure}: Fail{Http.failureText(failure)}
    case Done{Http.Reply{+status, _, +body}}: Bool.pick(Result<&2, &2, String, String>, U32.is_ge(status, 200) && U32.is_lt(status, 300), formatted(format, body, "URL"), Fail{Http.apiError(status, body)})

# UrlSubjectTokenSupplier: a GET with the configured headers.
def urlToken(~Reason: Data, +transport: Http.Transport<Reason>, url: String, headers: List<&2, R.Property<String>>, format: Format) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.AUTH_RETRY(), "GET", url, headers, Headers.Absent{}, Http.NO_TIMEOUT())
    return urlReply(format, result)

# AWS (AwsClient, DefaultAwsSecurityCredentialsSupplier, AwsRequestSigner)
# ----------------------------------------------------------------------

type AwsKeys is Data:
  AwsKeys{accessKeyId: String, secretAccessKey: String, token: Maybe<&2, String>}

def plainText(result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{failure}: Fail{Http.failureText(failure)}
    case Done{Http.Reply{+status, _, +body}}: Bool.pick(Result<&2, &2, String, String>, U32.is_ge(status, 200) && U32.is_lt(status, 300), Done{body}, Fail{Http.apiError(status, body)})

def metadataGet(~Reason: Data, +transport: Http.Transport<Reason>, method: String, url: String, headers: List<&2, R.Property<String>>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.request(~Reason, transport, method, url, headers, Headers.Absent{}, Http.NO_TIMEOUT())
    return plainText(result)

def sessionHeaders(token: Result<&2, &2, String, String>) -> Result<&2, &2, String, List<&2, R.Property<String>>>:
  match token:
    case Fail{message}: Fail{message}
    case Done{value}: Done{[R.Property{"x-aws-ec2-metadata-token", value}]}

# #getImdsV2SessionToken when imdsv2_session_token_url is configured.
def sessionToken(~Reason: Data, +transport: Http.Transport<Reason>, url: Maybe<&2, String>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  match url:
    case None{}: IO.pure(Result<&2, &2, String, List<&2, R.Property<String>>>, Done{Nil{}})
    case Some{address}:
      do IO<Result<&2, &2, String, List<&2, R.Property<String>>>>:
        token : Result<&2, &2, String, String> <- metadataGet(~Reason, transport, "PUT", address, [R.Property{"x-aws-ec2-metadata-token-ttl-seconds", "300"}])
        return sessionHeaders(token)

def withoutLast(+text: String) -> String: String.take(text, Nat.sub(String.length(text), 1n))

def regionFrom(~Reason: Data, +transport: Http.Transport<Reason>, regionUrl: Maybe<&2, String>, headers: Result<&2, &2, String, List<&2, R.Property<String>>>) -> IO(Result<&2, &2, String, String>):
  match headers regionUrl:
    case Fail{message} _: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case _ None{}: IO.pure(Result<&2, &2, String, String>, Fail{"Unable to determine AWS region due to missing \"options.credential_source.region_url\""})
    case Done{fields} Some{url}:
      do IO<Result<&2, &2, String, String>>:
        zone : Result<&2, &2, String, String> <- metadataGet(~Reason, transport, "GET", url, fields)
        return Result.map(&2, &2, String, String, String, value => withoutLast(value), zone)

def regionWith(~Reason: Data, +transport: Http.Transport<Reason>, regionUrl: Maybe<&2, String>, sessionUrl: Maybe<&2, String>, configured: Maybe<&2, String>) -> IO(Result<&2, &2, String, String>):
  match configured:
    case Some{region}: IO.pure(Result<&2, &2, String, String>, Done{region})
    case None{}:
      do IO<Result<&2, &2, String, String>>:
        headers : Result<&2, &2, String, List<&2, R.Property<String>>> <- sessionToken(~Reason, transport, sessionUrl)
        regionFrom(~Reason, transport, regionUrl, headers)

# getAwsRegion: AWS_REGION or AWS_DEFAULT_REGION, else the availability zone
# from region_url without its letter.
def awsRegion(~Reason: Data, +transport: Http.Transport<Reason>, regionUrl: Maybe<&2, String>, sessionUrl: Maybe<&2, String>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    region : Maybe<&2, String> <- env("AWS_REGION")
    fallback : Maybe<&2, String> <- env("AWS_DEFAULT_REGION")
    regionWith(~Reason, transport, regionUrl, sessionUrl, Maybe.or(&2, String, nonempty(region), nonempty(fallback)))

def keysOf(json: Maybe<&2, V.Value>) -> Result<&2, &2, String, AwsKeys>:
  match json:
    case Some{+value}: Done{AwsKeys{Maybe.default(&2, String, text(field(value, "AccessKeyId")), "undefined"), Maybe.default(&2, String, text(field(value, "SecretAccessKey")), "undefined"), text(field(value, "Token"))}}
    case None{}: Fail{"The AWS security credentials response is not valid JSON"}

def credentialsRead(~Reason: Data, +transport: Http.Transport<Reason>, url: String, fields: List<&2, R.Property<String>>, role: Result<&2, &2, String, String>) -> IO(Result<&2, &2, String, AwsKeys>):
  match role:
    case Fail{message}: IO.pure(Result<&2, &2, String, AwsKeys>, Fail{message})
    case Done{name}:
      do IO<Result<&2, &2, String, AwsKeys>>:
        body : Result<&2, &2, String, String> <- metadataGet(~Reason, transport, "GET", url ++ "/" ++ name, fields)
        return Result.bind(&2, &2, String, String, AwsKeys, body, value => keysOf(jsonOf(Decode.parse(value))))

def credentialsWith(~Reason: Data, +transport: Http.Transport<Reason>, url: Maybe<&2, String>, headers: Result<&2, &2, String, List<&2, R.Property<String>>>) -> IO(Result<&2, &2, String, AwsKeys>):
  match headers url:
    case Fail{message} _: IO.pure(Result<&2, &2, String, AwsKeys>, Fail{message})
    case _ None{}: IO.pure(Result<&2, &2, String, AwsKeys>, Fail{"Unable to determine AWS role name due to missing \"options.credential_source.url\""})
    case Done{+fields} Some{+address}:
      do IO<Result<&2, &2, String, AwsKeys>>:
        role : Result<&2, &2, String, String> <- metadataGet(~Reason, transport, "GET", address, fields)
        credentialsRead(~Reason, transport, address, fields, role)

def envPair(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Maybe<&2, AwsKeys>:
  match access secret:
    case Some{a} Some{s}: Some{AwsKeys{a, s, nonempty(token)}}
    case _ _: None{}

def envKeys(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Maybe<&2, AwsKeys>: envPair(nonempty(access), nonempty(secret), token)

def keysWith(~Reason: Data, +transport: Http.Transport<Reason>, url: Maybe<&2, String>, sessionUrl: Maybe<&2, String>, fromEnv: Maybe<&2, AwsKeys>) -> IO(Result<&2, &2, String, AwsKeys>):
  match fromEnv:
    case Some{keys}: IO.pure(Result<&2, &2, String, AwsKeys>, Done{keys})
    case None{}:
      do IO<Result<&2, &2, String, AwsKeys>>:
        headers : Result<&2, &2, String, List<&2, R.Property<String>>> <- sessionToken(~Reason, transport, sessionUrl)
        credentialsWith(~Reason, transport, url, headers)

# getAwsSecurityCredentials: the environment's keys, else the role's
# credentials from the metadata service.
def awsKeys(~Reason: Data, +transport: Http.Transport<Reason>, url: Maybe<&2, String>, sessionUrl: Maybe<&2, String>) -> IO(Result<&2, &2, String, AwsKeys>):
  do IO<Result<&2, &2, String, AwsKeys>>:
    access : Maybe<&2, String> <- env("AWS_ACCESS_KEY_ID")
    secret : Maybe<&2, String> <- env("AWS_SECRET_ACCESS_KEY")
    token : Maybe<&2, String> <- env("AWS_SESSION_TOKEN")
    keysWith(~Reason, transport, url, sessionUrl, envKeys(access, secret, token))

def upperHex(+value: U32) -> Char: Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (55 + value : U32)))

def componentSafe(+byte: U32) -> Bool:
  (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122)) || (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || U32.is_eq(byte, 45) || U32.is_eq(byte, 95) || U32.is_eq(byte, 46) || U32.is_eq(byte, 33) || U32.is_eq(byte, 126) || U32.is_eq(byte, 42) || U32.is_eq(byte, 39) || U32.is_eq(byte, 40) || U32.is_eq(byte, 41)

def escapedByte(safe: Bool, +byte: U32, tail: String) -> String:
  match safe:
    case True{}: SCon{Char.from_u32(byte), tail}
    case False{}: SCon{'%', SCon{upperHex(U32.shrn(byte, 4n)), SCon{upperHex(U32.and(byte, 15)), tail}}}

def componentBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: SNil{}
    case +byte <> rest: escapedByte(componentSafe(byte), byte, componentBytes(rest))

# encodeURIComponent.
def encodeComponent(text: String) -> String: componentBytes(Utf8.encode(text))

def isoCompact(+iso: String) -> String: SigV4.amzDate(String.take(iso, 19n) ++ "Z")

def headerPairs(fields: List<&2, R.Property<String>>) -> List<&2, T.JsonValue>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: T.JsonObject{R.Record{[R.Property{"key", T.JsonString{key}}, R.Property{"value", T.JsonString{value}}]}} <> headerPairs(rest)

def tokenLine(token: Maybe<&2, String>) -> String:
  match token:
    case Some{value}: "x-amz-security-token:" ++ value ++ "\n"
    case None{}: ""

def tokenName(token: Maybe<&2, String>) -> String:
  match token:
    case Some{_}: ";x-amz-security-token"
    case None{}: ""

def tokenHeader(token: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match token:
    case Some{value}: [R.Property{"x-amz-security-token", value}]
    case None{}: Nil{}

def queryOf(query: Maybe<&2, String>) -> String: Maybe.default(&2, String, query, "")

def pathOf(url: URL.URL) -> String:
  match url:
    case URL.URL{_, _, _, _, _, path, _, _}: URL.serializePath(path)

def hostOf(url: URL.URL) -> String:
  match url:
    case URL.URL{_, _, _, Some{host}, port, _, _, _}: URL.serializeHost(host) ++ Maybe.default(&2, String, Maybe.map(&2, U32, String, number => ":" ++ U32.show(number), port), "")
    case _: ""

def queryText(url: URL.URL) -> String:
  match url:
    case URL.URL{_, _, _, _, _, _, query, _}: queryOf(query)

def firstLabel(+host: String) -> String: Maybe.default(&2, String, List.head(&2, String, String.split(host, '.')), host)

# AwsRequestSigner.getRequestOptions for the GetCallerIdentity POST, then
# the subject token: the URL-encoded JSON of the signed request's url,
# method and headers (sorted by name, with x-goog-cloud-target-resource).
def signedToken(+url: String, +address: URL.URL, keys: AwsKeys, +region: String, +audience: String, +iso: String) -> String:
  match keys:
    case AwsKeys{access, secret, +token}:
      +host = hostOf(address)
      +date = isoCompact(iso)
      +stamp = String.take(date, 8n)
      +service = firstLabel(host)
      +scope = stamp ++ "/" ++ region ++ "/" ++ service ++ "/aws4_request"
      +signedHeaders = "host;x-amz-date" ++ tokenName(token)
      +canonical = "POST\n" ++ pathOf(address) ++ "\n" ++ queryText(address) ++ "\nhost:" ++ host ++ "\nx-amz-date:" ++ date ++ "\n" ++ tokenLine(token) ++ "\n" ++ signedHeaders ++ "\n" ++ SigV4.sha256Hex(Nil{})
      +stringToSign = "AWS4-HMAC-SHA256\n" ++ date ++ "\n" ++ scope ++ "\n" ++ SigV4.sha256Hex(Utf8.encode(canonical))
      +signature = SigV4.hexBytes(SigV4.hmac(SigV4.signingKey(secret, stamp, region, service), stringToSign))
      +authorization = "AWS4-HMAC-SHA256 Credential=" ++ access ++ "/" ++ scope ++ ", SignedHeaders=" ++ signedHeaders ++ ", Signature=" ++ signature
      +headers = List.concat(&2, R.Property<String>, [[R.Property{"authorization", authorization}, R.Property{"host", host}, R.Property{"x-amz-date", date}], tokenHeader(token), [R.Property{"x-goog-cloud-target-resource", audience}]])
      encodeComponent(Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"url", T.JsonString{url}}, R.Property{"method", T.JsonString{"POST"}}, R.Property{"headers", T.JsonArray{headerPairs(headers)}}]}}), "{}"))

def signedParsed(+url: String, keys: Result<&2, &2, String, AwsKeys>, +region: String, +audience: String, +iso: String, parsed: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, String, String>:
  match keys parsed:
    case Fail{message} _: Fail{message}
    case _ Fail{_}: Fail{"Invalid URL"}
    case Done{value} Done{address}: Done{signedToken(url, address, value, region, audience, iso)}

def signedWith(context: URL.Context, +url: String, keys: Result<&2, &2, String, AwsKeys>, +region: String, +audience: String, +iso: String) -> Result<&2, &2, String, String>: signedParsed(url, keys, region, audience, iso, URL.parse(context, url))

def awsSigned(~Reason: Data, +transport: Http.Transport<Reason>, url: Maybe<&2, String>, sessionUrl: Maybe<&2, String>, verification: String, +audience: String, region: Result<&2, &2, String, String>) -> IO(Result<&2, &2, String, String>):
  match region:
    case Fail{message}: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case Done{+value}:
      do IO<Result<&2, &2, String, String>>:
        keys : Result<&2, &2, String, AwsKeys> <- awsKeys(~Reason, transport, url, sessionUrl)
        now : F64 <- Date.now()
        return signedWith(Http.contextOf(Reason, transport), replaceFirst(verification, "{region}", value), keys, value, audience, Maybe.default(&2, String, Date.formatIso(now), ""))

def awsToken(~Reason: Data, +transport: Http.Transport<Reason>, regionUrl: Maybe<&2, String>, url: Maybe<&2, String>, +sessionUrl: Maybe<&2, String>, verification: String, +audience: String) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    region : Result<&2, &2, String, String> <- awsRegion(~Reason, transport, regionUrl, sessionUrl)
    awsSigned(~Reason, transport, url, sessionUrl, verification, audience, region)

# Executables (PluggableAuthClient, PluggableAuthHandler)
# -------------------------------------------------------

def SAML() -> String: "urn:ietf:params:oauth:token-type:saml2"

def OIDC_ID_TOKEN() -> String: "urn:ietf:params:oauth:token-type:id_token"

def OIDC_JWT() -> String: "urn:ietf:params:oauth:token-type:jwt"

type ExecutableResponse is Data:
  Succeeded{version: F64, expirationTime: Maybe<&2, F64>, subjectToken: String}
  Failed{version: F64, code: String, message: String}

def isZero(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Number{n}}: F.isEqual(F.compare(n, F.fromU32(0)))
    case _: False{}

def truthyValue(+value: Maybe<&2, V.Value>) -> Bool: present(value) && Bool.not(isZero(value))

def valueText(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{t}}: t
    case Some{V.Number{n}}: Maybe.default(&2, String, F.toJsonNumber(n), "NaN")
    case Some{V.Boolean{b}}: Bool.pick(String, b, "true", "false")
    case _: ""

def successTyped(+json: V.Value, +version: F64, +tokenType: String) -> Result<&2, &2, String, ExecutableResponse>:
  Bool.pick(Result<&2, &2, String, ExecutableResponse>, String.eq(tokenType, SAML()),
    Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "saml_response")), Done{Succeeded{version, number(field(json, "expiration_time")), valueText(field(json, "saml_response"))}}, Fail{"Executable response must contain a 'saml_response' field when token_type=" ++ SAML() ++ "."}),
    Bool.pick(Result<&2, &2, String, ExecutableResponse>, String.eq(tokenType, OIDC_ID_TOKEN()) || String.eq(tokenType, OIDC_JWT()),
      Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "id_token")), Done{Succeeded{version, number(field(json, "expiration_time")), valueText(field(json, "id_token"))}}, Fail{"Executable response must contain a 'id_token' field when token_type=" ++ OIDC_ID_TOKEN() ++ " or " ++ OIDC_JWT() ++ "."}),
      Fail{"Executable response must contain a 'token_type' field when successful and it must be one of " ++ OIDC_ID_TOKEN() ++ ", " ++ OIDC_JWT() ++ ", or " ++ SAML() ++ "."}))

def failureTyped(+json: V.Value, version: F64) -> Result<&2, &2, String, ExecutableResponse>:
  Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "code")), Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "message")), Done{Failed{version, valueText(field(json, "code")), valueText(field(json, "message"))}}, Fail{"Executable response must contain a 'message' field when unsuccessful."}), Fail{"Executable response must contain a 'code' field when unsuccessful."})

def versionOf(value: Maybe<&2, V.Value>) -> F64:
  match value:
    case Some{V.Number{n}}: n
    case _: F.fromU32(1)

def isFalse(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

# new ExecutableResponse(json): version and success are required; success
# needs a known token type and its token, failure a code and message.
def responseOf(+json: V.Value) -> Result<&2, &2, String, ExecutableResponse>:
  Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "version")),
    Bool.pick(Result<&2, &2, String, ExecutableResponse>, present(field(json, "success")) || isFalse(field(json, "success")),
      Bool.pick(Result<&2, &2, String, ExecutableResponse>, truthyValue(field(json, "success")), successTyped(json, versionOf(field(json, "version")), valueText(field(json, "token_type"))), failureTyped(json, versionOf(field(json, "version")))),
      Fail{"Executable response must contain a 'success' field."}),
    Fail{"Executable response must contain a 'version' field."})

def expired(response: ExecutableResponse, +nowSeconds: F64) -> Bool:
  match response:
    case Succeeded{_, Some{expiration}, _}: Bool.not(F.isAtLeast(F.compare(expiration, nowSeconds)))
    case _: False{}

def hasExpiration(response: ExecutableResponse) -> Bool:
  match response:
    case Succeeded{_, Some{_}, _}: True{}
    case _: False{}

# retrieveSubjectToken's checks of an executable response.
def checkedResponse(response: ExecutableResponse, outputFile: Bool, +nowSeconds: F64) -> Result<&2, &2, String, String>:
  match response:
    case Failed{version, code, message}: Bool.pick(Result<&2, &2, String, String>, F.isGreater(F.compare(version, F.fromU32(1))), Fail{"Version of executable is not currently supported, maximum supported version is 1."}, Fail{"The executable failed with exit code: " ++ code ++ " and error message: " ++ message ++ "."})
    case Succeeded{+version, +expiration, +token}:
      Bool.pick(Result<&2, &2, String, String>, F.isGreater(F.compare(version, F.fromU32(1))), Fail{"Version of executable is not currently supported, maximum supported version is 1."},
        Bool.pick(Result<&2, &2, String, String>, outputFile && Bool.not(hasExpiration(Succeeded{version, expiration, token})), Fail{"The executable response must contain the `expiration_time` field for successful responses when an output_file has been specified in the configuration."},
          Bool.pick(Result<&2, &2, String, String>, expired(Succeeded{version, expiration, token}, nowSeconds), Fail{"Executable response is expired."}, Done{token})))

def collect(sink: Ref.Ref<List<&2, U32>>, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Ref.modify(List<&2, U32>, Unit, sink, previous => (List.append(&2, U32, previous, bytes), Unit{}))
    return Done{Unit{}}

def unquoted(+part: String) -> String:
  Bool.pick(String, String.length(part) >= 2n && String.starts_with(part, "\"") && String.ends_with(part, "\""), String.drop(String.take(part, Nat.sub(String.length(part), 1n)), 1n), part)

type CommandChar is Data:
  Separator{}
  Quote{}
  Plain{char: Char}

def classify(+c: Char) -> CommandChar:
  Bool.pick(CommandChar, Char.is_eq(c, '"'), Quote{}, Bool.pick(CommandChar, Char.is_eq(c, ' ') || Char.is_eq(c, '\t') || Char.is_eq(c, '\n') || Char.is_eq(c, '\r'), Separator{}, Plain{c}))

def commandChars(text: String) -> List<&2, CommandChar>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: classify(c) <> commandChars(rest)

def pushed(+current: String, +parts: List<&2, String>) -> List<&2, String>: Bool.pick(List<&2, String>, String.is_empty(current), parts, current <> parts)

# `(?:[^\s"]+|"[^"]*")+`: runs of non-space characters and quoted spans.
def component(chars: List<&2, CommandChar>, +current: String, +quoted: Bool, +parts: List<&2, String>) -> List<&2, String>:
  match chars:
    case Nil{}: List.reverse(&2, String, pushed(current, parts))
    case Quote{} <> +rest: component(rest, current ++ "\"", Bool.not(quoted), parts)
    case Separator{} <> +rest: Bool.pick(Unit -> List<&2, String>, quoted, _ => component(rest, current ++ " ", quoted, parts), _ => component(rest, "", quoted, pushed(current, parts)))(Unit{})
    case Plain{c} <> +rest: component(rest, current ++ String.from_list([c]), quoted, parts)

# PluggableAuthHandler.parseCommand.
def unquotedAll(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: unquoted(part) <> unquotedAll(rest)

def parseCommand(text: String) -> List<&2, String>: unquotedAll(component(commandChars(text), "", False{}, Nil{}))

def entryName(+entry: String) -> String: Maybe.default(&2, String, List.head(&2, String, String.split(entry, '=')), entry)

def listedName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || listedName(rest, name)

def prependUnless(skip: Bool, entry: String, rest: List<String>) -> List<String>:
  match skip:
    case True{}: rest
    case False{}: entry <> rest

def overridden(entries: List<String>, +names: List<&2, String>) -> List<String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest: prependUnless(listedName(names, entryName(entry)), entry, overridden(rest, names))

def pairNames(pairs: List<&2, R.Property<String>>) -> List<&2, String>:
  match pairs:
    case Nil{}: Nil{}
    case R.Property{name, _} <> rest: name <> pairNames(rest)

def pairEntries(pairs: List<&2, R.Property<String>>) -> List<String>:
  match pairs:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ "=" ++ value) <> pairEntries(rest)

def executed(status: Result<&2, &2, Process.ExecutionError, U32>, +output: String) -> Result<&2, &2, String, ExecutableResponse>:
  match status:
    case Done{0}: Result.bind(&2, &2, String, V.Value, ExecutableResponse, orFailJson(jsonOf(Decode.parse(output)), "The executable returned an invalid response: " ++ output), json => responseOf(json))
    case Done{code}: Fail{"The executable failed with exit code: " ++ U32.show(code) ++ " and error message: " ++ output ++ "."}
    case Fail{Process.ExecutionTimedOut{}}: Fail{"The executable failed to finish within the timeout specified."}
    case Fail{_}: Fail{"spawn " ++ output ++ " ENOENT"}

def arguments(values: List<&2, String>) -> List<String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> arguments(rest)

def runResolved(parts: List<&2, String>, env: List<String>, +timeout: U32, resolved: Maybe<&2, String>) -> IO(Result<&2, &2, String, ExecutableResponse>):
  match resolved parts:
    case None{} first <> _: IO.pure(Result<&2, &2, String, ExecutableResponse>, Fail{"spawn " ++ first ++ " ENOENT"})
    case None{} Nil{}: IO.pure(Result<&2, &2, String, ExecutableResponse>, Fail{"spawn ENOENT"})
    case Some{path} _:
      do IO<Result<&2, &2, String, ExecutableResponse>>:
        +sink : Ref.Ref<List<&2, U32>> <- Ref.new(List<&2, U32>, Nil{})
        +onData : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<List<&2, U32>>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~collect, sink)
        cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
        status : Result<&2, &2, Process.ExecutionError, U32> <- Process.executeValidated(Process.Merged{}, False{}, path, arguments(List.drop(&2, String, parts, 1n)), "", Result.default(&2, &2, FS.Error, String, cwd, "/"), env, Nil{}, onData, Done{Some{timeout}})
        C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, onData)
        bytes : List<&2, U32> <- Ref.dispose(List<&2, U32>, sink)
        return executed(status, textOf(bytes))

# retrieveResponseFromExecutable: the command (no shell) with the process
# environment and the GOOGLE_EXTERNAL_ACCOUNT_* variables.
def runExecutable(+command: String, +pairs: List<&2, R.Property<String>>, +timeout: U32) -> IO(Result<&2, &2, String, ExecutableResponse>):
  +parts = parseCommand(command)
  do IO<Result<&2, &2, String, ExecutableResponse>>:
    entries : List<String> <- IO.environment()
    path : Maybe<&2, String> <- env("PATH")
    resolved : Maybe<&2, String> <- Process.resolveCommand(Maybe.default(&2, String, List.head(&2, String, parts), ""), Maybe.default(&2, String, path, ""))
    runResolved(parts, List.append(&1, String, overridden(entries, pairNames(pairs)), pairEntries(pairs)), timeout, resolved)

def validCached(response: ExecutableResponse, +nowSeconds: F64) -> Maybe<&2, ExecutableResponse>:
  match response:
    case Succeeded{+version, +expiration, +token}: Bool.pick(Maybe<&2, ExecutableResponse>, expired(Succeeded{version, expiration, token}, nowSeconds), None{}, Some{Succeeded{version, expiration, token}})
    case Failed{_, _, _}: None{}

def cachedJson(json: Maybe<&2, V.Value>, +content: String, +nowSeconds: F64) -> Result<&2, &2, String, Maybe<&2, ExecutableResponse>>:
  match json:
    case None{}: Fail{"The output file contained an invalid response: " ++ content}
    case Some{value}: Result.map(&2, &2, String, ExecutableResponse, Maybe<&2, ExecutableResponse>, response => validCached(response, nowSeconds), responseOf(value))

def cachedText(+content: String, +nowSeconds: F64) -> Result<&2, &2, String, Maybe<&2, ExecutableResponse>>:
  Bool.pick(Result<&2, &2, String, Maybe<&2, ExecutableResponse>>, String.is_empty(content), Done{None{}}, cachedJson(jsonOf(Decode.parse(content)), content, nowSeconds))

def cachedResponse(bytes: Result<&2, &2, FS.Error, List<&2, U32>>, +nowSeconds: F64) -> Result<&2, &2, String, Maybe<&2, ExecutableResponse>>:
  match bytes:
    case Fail{_}: Done{None{}}
    case Done{content}: cachedText(textOf(content), nowSeconds)

# retrieveCachedResponse: a valid, unexpired response in the output file.
def cached(output: Maybe<&2, String>, +nowSeconds: F64) -> IO(Result<&2, &2, String, Maybe<&2, ExecutableResponse>>):
  match output:
    case Some{SCon{c, cs}}:
      do IO<Result<&2, &2, String, Maybe<&2, ExecutableResponse>>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(SCon{c, cs})
        return cachedResponse(bytes, nowSeconds)
    case _: IO.pure(Result<&2, &2, String, Maybe<&2, ExecutableResponse>>, Done{None{}})

def emailIn(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case "serviceAccounts" <> +last <> Nil{}: Bool.pick(Maybe<&2, String>, String.ends_with(last, ":generateAccessToken") && Bool.not(String.contains(String.take(last, Nat.sub(String.length(last), 20n)), ":")), Some{String.take(last, Nat.sub(String.length(last), 20n))}, None{})
    case _ <> rest: emailIn(rest)
    case Nil{}: None{}

def impersonatedEmail(url: Maybe<&2, String>) -> Maybe<&2, String>:
  match url:
    case Some{+address}: emailIn(String.split(address, '/'))
    case None{}: None{}

def executablePairs(+audience: String, +tokenType: String, output: Maybe<&2, String>, email: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  List.concat(&2, R.Property<String>, [[R.Property{"GOOGLE_EXTERNAL_ACCOUNT_AUDIENCE", audience}, R.Property{"GOOGLE_EXTERNAL_ACCOUNT_TOKEN_TYPE", tokenType}, R.Property{"GOOGLE_EXTERNAL_ACCOUNT_INTERACTIVE", "0"}], Maybe.default(&2, List<&2, R.Property<String>>, Maybe.map(&2, String, List<&2, R.Property<String>>, file => [R.Property{"GOOGLE_EXTERNAL_ACCOUNT_OUTPUT_FILE", file}], output), Nil{}), Maybe.default(&2, List<&2, R.Property<String>>, Maybe.map(&2, String, List<&2, R.Property<String>>, value => [R.Property{"GOOGLE_EXTERNAL_ACCOUNT_IMPERSONATED_EMAIL", value}], email), Nil{})])

def fromCache(cache: Result<&2, &2, String, Maybe<&2, ExecutableResponse>>, +command: String, pairs: List<&2, R.Property<String>>, +timeout: U32) -> IO(Result<&2, &2, String, ExecutableResponse>):
  match cache:
    case Fail{message}: IO.pure(Result<&2, &2, String, ExecutableResponse>, Fail{message})
    case Done{Some{response}}: IO.pure(Result<&2, &2, String, ExecutableResponse>, Done{response})
    case Done{None{}}: runExecutable(command, pairs, timeout)

def seconds(+ms: F64) -> F64: F.truncate(F.add(F.divide(ms, F.fromU32(1000)), F.divide(F.fromU32(1), F.fromU32(2))))

def executableToken(+command: String, +timeoutMillis: F64, +output: Maybe<&2, String>, +audience: String, +tokenType: String, impersonation: Maybe<&2, String>) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    allowed : Maybe<&2, String> <- env("GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES")
    +isAllowed : Bool <- IO.pure(Bool, String.eq(Maybe.default(&2, String, allowed, ""), "1"))
    Bool.pick(Unit -> IO(Result<&2, &2, String, String>), isAllowed, _ =>
      do IO<Result<&2, &2, String, String>>:
        now : F64 <- Date.now()
        +nowSeconds : F64 <- IO.pure(F64, seconds(now))
        cache : Result<&2, &2, String, Maybe<&2, ExecutableResponse>> <- cached(output, nowSeconds)
        response : Result<&2, &2, String, ExecutableResponse> <- fromCache(cache, command, executablePairs(audience, tokenType, output, impersonatedEmail(impersonation)), F64.to_u32(timeoutMillis))
        return Result.bind(&2, &2, String, ExecutableResponse, String, response, value => checkedResponse(value, Maybe.is_some(&2, String, output), nowSeconds)), _ => IO.pure(Result<&2, &2, String, String>, Fail{"Pluggable Auth executables need to be explicitly allowed to run by setting the GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES environment Variable to 1."}))(Unit{})

# retrieveSubjectToken.
def subjectToken(~Reason: Data, +transport: Http.Transport<Reason>, config: External) -> IO(Result<&2, &2, String, String>):
  match config:
    case External{+audience, +tokenType, _, source, _, _, impersonation, _, _, _}:
      match source:
        case FileSource{path, format}: fileToken(path, format)
        case UrlSource{url, headers, format}: urlToken(~Reason, transport, url, headers, format)
        case AwsSource{regionUrl, url, sessionUrl, verification}: awsToken(~Reason, transport, regionUrl, url, sessionUrl, verification, audience)
        case ExecutableSource{command, timeout, output}: executableToken(command, timeout, output, audience, tokenType, impersonation)

# Token exchange
# --------------

def base64Text(value: Result<&2, &2, Base64.Error, String>) -> String:
  match value:
    case Done{encoded}: encoded
    case Fail{_}: ""

def basicAuth(clientId: Maybe<&2, String>, clientSecret: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match clientId:
    case Some{id}: [R.Property{"authorization", "Basic " ++ base64Text(Base64.encode(Utf8.encode(id ++ ":" ++ Maybe.default(&2, String, clientSecret, ""))))}]
    case None{}: Nil{}

def FORM() -> R.Property<String>: R.Property{"content-type", "application/x-www-form-urlencoded;charset=UTF-8"}

# getMetricsHeaderValue, without the gl-node/<version> part (no Node.js
# runtime here).
def metricsHeader(+kind: String, impersonated: Bool, lifetime: Bool) -> String:
  "auth/" ++ AUTH_VERSION() ++ " google-byoid-sdk source/" ++ kind ++ " sa-impersonation/" ++ Bool.pick(String, impersonated, "true", "false") ++ " config-lifetime/" ++ Bool.pick(String, lifetime, "true", "false")

def userProjectOption(clientId: Maybe<&2, String>, project: Maybe<&2, String>) -> List<&2, URL.Entry>:
  match clientId project:
    case None{} Some{value}: [URL.Entry{"options", Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"userProject", T.JsonString{value}}]}}), "{}")}]
    case _ _: Nil{}

# StsCredentials.exchangeToken: the token-exchange grant for the subject
# token.
def exchange(~Reason: Data, +transport: Http.Transport<Reason>, config: External, subject: String) -> IO(Result<&2, &2, String, Token>):
  match config:
    case External{audience, tokenType, tokenUrl, +source, +clientId, clientSecret, +impersonation, lifetime, workforce, _}:
      +form = URL.serializeSearchParams(List.concat(&2, URL.Entry, [[URL.Entry{"grant_type", STS_GRANT_TYPE()}, URL.Entry{"audience", audience}, URL.Entry{"scope", DEFAULT_SCOPE()}, URL.Entry{"requested_token_type", STS_REQUEST_TOKEN_TYPE()}, URL.Entry{"subject_token", subject}, URL.Entry{"subject_token_type", tokenType}], userProjectOption(clientId, workforce)]))
      do IO<Result<&2, &2, String, Token>>:
        result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.AUTH_RETRY(), "POST", tokenUrl, List.concat(&2, R.Property<String>, [[R.Property{"x-goog-api-client", metricsHeader(sourceKind(source), Maybe.is_some(&2, String, impersonation), Maybe.is_some(&2, F64, lifetime))}, FORM()], basicAuth(clientId, clientSecret)]), Headers.Text{form}, Http.NO_TIMEOUT())
        return tokenReply(True{}, "access_token", result)

def lifetimeText(lifetime: Maybe<&2, F64>) -> String: Maybe.default(&2, String, F.toJsonNumber(Maybe.default(&2, F64, lifetime, F.fromU32(3600))), "3600") ++ "s"

def impersonationBody(lifetime: Maybe<&2, F64>) -> String:
  Maybe.default(&2, String, JsonWire.stringify(T.JsonObject{R.Record{[R.Property{"scope", T.JsonArray{[T.JsonString{DEFAULT_SCOPE()}]}}, R.Property{"lifetime", T.JsonString{lifetimeText(lifetime)}}]}}), "{}")

# getImpersonatedAccessToken: the service account token for the STS token.
def impersonate(~Reason: Data, +transport: Http.Transport<Reason>, url: String, lifetime: Maybe<&2, F64>, sts: Result<&2, &2, String, Token>) -> IO(Result<&2, &2, String, Token>):
  match sts:
    case Fail{message}: IO.pure(Result<&2, &2, String, Token>, Fail{message})
    case Done{Token{access}}:
      do IO<Result<&2, &2, String, Token>>:
        result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.AUTH_RETRY(), "POST", url, [R.Property{"content-type", "application/json"}, R.Property{"authorization", "Bearer " ++ access}], Headers.Text{impersonationBody(lifetime)}, Http.NO_TIMEOUT())
        return tokenReply(False{}, "accessToken", result)

def impersonatedOr(~Reason: Data, +transport: Http.Transport<Reason>, impersonation: Maybe<&2, String>, lifetime: Maybe<&2, F64>, sts: Result<&2, &2, String, Token>) -> IO(Result<&2, &2, String, Token>):
  match impersonation:
    case Some{url}: impersonate(~Reason, transport, url, lifetime, sts)
    case None{}: IO.pure(Result<&2, &2, String, Token>, sts)

def exchanged(~Reason: Data, +transport: Http.Transport<Reason>, config: External, subject: Result<&2, &2, String, String>) -> IO(Result<&2, &2, String, Token>):
  match subject config:
    case Fail{message} _: IO.pure(Result<&2, &2, String, Token>, Fail{message})
    case Done{token} External{a, b, c, d, e, f, +impersonation, +lifetime, g, h}:
      do IO<Result<&2, &2, String, Token>>:
        sts : Result<&2, &2, String, Token> <- exchange(~Reason, transport, External{a, b, c, d, e, f, impersonation, lifetime, g, h}, token)
        impersonatedOr(~Reason, transport, impersonation, lifetime, sts)

# BaseExternalAccountClient's access token: the subject token, the STS
# exchange, then service account impersonation when configured.
def accessToken(~Reason: Data, +transport: Http.Transport<Reason>, +config: External) -> IO(Result<&2, &2, String, Token>):
  do IO<Result<&2, &2, String, Token>>:
    subject : Result<&2, &2, String, String> <- subjectToken(~Reason, transport, config)
    exchanged(~Reason, transport, config, subject)

# ExternalAccountAuthorizedUserHandler.refreshToken.
def refreshAuthorizedUser(~Reason: Data, +transport: Http.Transport<Reason>, config: AuthorizedUser) -> IO(Result<&2, &2, String, Token>):
  match config:
    case AuthorizedUser{clientId, clientSecret, refreshToken, tokenUrl, _}:
      do IO<Result<&2, &2, String, Token>>:
        result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.AUTH_RETRY(), "POST", tokenUrl, List.concat(&2, R.Property<String>, [[FORM()], basicAuth(Some{clientId}, Some{clientSecret})]), Headers.Text{URL.serializeSearchParams([URL.Entry{"grant_type", "refresh_token"}, URL.Entry{"refresh_token", refreshToken}])}, Http.NO_TIMEOUT())
        return tokenReply(True{}, "access_token", result)

# Project lookup
# --------------

def numberIn(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case "projects" <> +next <> _: Bool.pick(Maybe<&2, String>, String.is_empty(next), None{}, Some{next})
    case _ <> rest: numberIn(rest)
    case Nil{}: None{}

# The project number of the audience (`/projects/<number>`), else the
# workforce pool user project.
def projectNumber(config: External) -> Maybe<&2, String>:
  match config:
    case External{+audience, _, _, _, _, _, _, _, workforce, _}: Maybe.or(&2, String, numberIn(String.split(audience, '/')), workforce)

def quotaHeader(quota: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match quota:
    case Some{project}: [R.Property{"x-goog-user-project", project}]
    case None{}: Nil{}

def lookupReply(result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{failure}: Fail{Http.failureText(failure)}
    case Done{Http.Reply{+status, _, +body}}: Bool.pick(Result<&2, &2, String, Unit>, U32.is_ge(status, 200) && U32.is_lt(status, 300), Done{Unit{}}, Fail{Http.apiError(status, body)})

# BaseExternalAccountClient.getProjectId: the Cloud Resource Manager project
# of the project number, fetched with the access token (the default
# cloud_resource_manager_url only).
def lookupProject(~Reason: Data, +transport: Http.Transport<Reason>, config: External, +number: String, token: Token) -> IO(Result<&2, &2, String, Unit>):
  match token:
    case Token{access}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.AUTH_RETRY(), "GET", "https://cloudresourcemanager.googleapis.com/v1/projects/" ++ number, List.append(&2, R.Property<String>, [R.Property{"authorization", "Bearer " ++ access}], quotaHeader(quotaProject(config))), Headers.Absent{}, Http.NO_TIMEOUT())
        return lookupReply(result)
