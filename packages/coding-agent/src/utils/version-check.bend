import Base
import ./management-http.bend as Http
import ./pi-user-agent.bend as UserAgent
import ../../../runtime/src/semver.bend as Semver
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/text.bend as Text

# upstream utils/version-check.ts: ask pi.dev for the latest pi release. The
# transport is the caller's fetch (Bend has no global fetch); failures that
# upstream rejects with are the error message here.

def LATEST_VERSION_URL() -> String: "https://pi.dev/api/latest-version"
def DEFAULT_VERSION_CHECK_TIMEOUT_MS() -> U32: 10000

# The response body is small JSON; a larger one is a failed read.
def RESPONSE_LIMIT() -> Nat: 1048576n

type LatestPiRelease is Data:
  LatestPiRelease{version: String, packageName: Maybe<&2, String>, note: Maybe<&2, String>}

type VersionCheckOptions is Data:
  VersionCheckOptions{timeoutMs: Maybe<&2, U32>, retry: Bool}

def defaultOptions() -> VersionCheckOptions: VersionCheckOptions{None{}, False{}}

# upstream formatVersionCheckError adds the errno codes Node hides behind
# "fetch failed"; the native transport error carries no errno names, so this
# is the management request's message.
def formatVersionCheckError(error: Http.Error) -> String: Http.errorMessage(error)

# comparePackageVersions: semver order of two valid versions, else None.
def comparedVersions(left: Maybe<&2, Semver.SemVer>, right: Maybe<&2, Semver.SemVer>) -> Maybe<&2, Cmp>:
  match left right:
    case Some{a} Some{b}: Some{Semver.compareSemVer(a, b)}
    case _ _: None{}

def comparePackageVersions(leftVersion: String, rightVersion: String) -> Maybe<&2, Cmp>:
  comparedVersions(Semver.parse(Text.trim(leftVersion)), Semver.parse(Text.trim(rightVersion)))

def greater(order: Maybe<&2, Cmp>, +candidate: String, +current: String) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case Some{_}: False{}
    case None{}: Bool.not(String.eq(Text.trim(candidate), Text.trim(current)))

# A newer semver version, or any different text when either is not semver.
def isNewerPackageVersion(+candidateVersion: String, +currentVersion: String) -> Bool:
  greater(comparePackageVersions(candidateVersion, currentVersion), candidateVersion, currentVersion)

# Response data
# ------------

def nonBlank(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case other: Some{other}

def trimmedText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: nonBlank(Text.trim(text))
    case _: None{}

def releaseWith(version: Maybe<&2, String>, +fields: R.Record<V.Value>) -> Maybe<&2, LatestPiRelease>:
  match version:
    case None{}: None{}
    case Some{value}: Some{LatestPiRelease{value, trimmedText(R.get(V.Value, fields, "packageName")), trimmedText(R.get(V.Value, fields, "note"))}}

# Only a non-empty string version counts; reading a field of JSON null
# throws in upstream.
def releaseOf(value: V.Value) -> Result<&2, &2, String, Maybe<&2, LatestPiRelease>>:
  match value:
    case V.ObjectValue{+fields}: Done{releaseWith(trimmedText(R.get(V.Value, fields, "version")), fields)}
    case V.Null{}: Fail{"Cannot read properties of null (reading 'version')"}
    case _: Done{None{}}

def bodyRelease(result: Result<&2, &2, Response.JSONError<Http.ReadError()>, V.Value>) -> Result<&2, &2, String, Maybe<&2, LatestPiRelease>>:
  match result:
    case Done{value}: releaseOf(value)
    case Fail{Response.InvalidJSON{_}}: Fail{"Unexpected token in JSON response"}
    case Fail{_}: Fail{"Failed to read the version check response"}

def released(body: Response.Body<Http.Scoped()>) -> IO(Unit):
  do IO<Unit>:
    next : Response.Next<Http.ReadError(), Http.Scoped()> <- Response.closeWith(Http.ReadError(), Http.Scoped(), Http.close, body)
    return Unit{}

def okResponse(ok: Bool, body: Response.Body<Http.Scoped()>) -> IO(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>):
  match ok:
    case False{}:
      do IO<Result<&2, &2, String, Maybe<&2, LatestPiRelease>>>:
        released(body)
        return Done{None{}}
    case True{}:
      do IO<Result<&2, &2, String, Maybe<&2, LatestPiRelease>>>:
        json : Result<&2, &2, Response.JSONError<Http.ReadError()>, V.Value> <- Response.jsonWith(~Http.ReadError(), ~Http.Scoped(), ~Http.read, ~Http.close, RESPONSE_LIMIT(), body)
        return bodyRelease(json)

def answered(result: Http.ScopedOutcome()) -> IO(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>, Fail{Http.errorMessage(error)})
    case Done{Response.Response{+metadata, body}}: okResponse(Response.ok(metadata), body)

def headers(+userAgent: String) -> Message.Headers:
  Result.default(&2, &2, Message.HeaderSyntaxError, Message.Headers, Result.bind(&2, &2, Message.HeaderSyntaxError, Message.Headers, Message.Headers, Message.set(Message.new(), "User-Agent", userAgent), withUserAgent => Message.set(withUserAgent, "accept", "application/json")), Message.new())

def retryOptions(options: VersionCheckOptions) -> Http.FetchRetryOptions:
  match options:
    case VersionCheckOptions{timeoutMs, retry}: Http.FetchRetryOptions{Some{Bool.pick(Nat, retry, 2n, 0n)}, None{}, Maybe.default(&2, U32, timeoutMs, DEFAULT_VERSION_CHECK_TIMEOUT_MS()), None{}}

def requested(fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String, options: VersionCheckOptions, url: Result<&2, &2, URL.Error, URL.URL>) -> IO(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>):
  match url:
    case Fail{_}: IO.pure(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>, Fail{"Invalid URL: " ++ LATEST_VERSION_URL()})
    case Done{address}:
      do IO<Result<&2, &2, String, Maybe<&2, LatestPiRelease>>>:
        userAgent : String <- UserAgent.getPiUserAgent(currentVersion)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Http.ScopedOutcome() <- Http.fetchWithRetry(fetch, context, Http.Request{address, headers(userAgent), Http.Follow{}}, Abort.signal(Unit, controller), retryOptions(options))
        release : Result<&2, &2, String, Maybe<&2, LatestPiRelease>> <- answered(result)
        Abort.dispose(Unit, controller)
        return release

def set(value: Result<&1, &1, U32 & String, String>) -> Bool:
  match value:
    case Done{SCon{_, _}}: True{}
    case _: False{}

def online(offline: Bool, fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String, options: VersionCheckOptions) -> IO(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>):
  match offline:
    case True{}: IO.pure(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>, Done{None{}})
    case False{}: requested(fetch, context, currentVersion, options, URL.parse(context, LATEST_VERSION_URL()))

# upstream getLatestPiRelease: nothing when PI_OFFLINE is set or the answer
# is not a successful response with a version; a failed request is an error.
def getLatestPiRelease(fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String, options: VersionCheckOptions) -> IO(Result<&2, &2, String, Maybe<&2, LatestPiRelease>>):
  do IO<Result<&2, &2, String, Maybe<&2, LatestPiRelease>>>:
    offline : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_OFFLINE")
    online(set(offline), fetch, context, currentVersion, options)

def versionOf(release: Maybe<&2, LatestPiRelease>) -> Maybe<&2, String>:
  match release:
    case Some{LatestPiRelease{version, _, _}}: Some{version}
    case None{}: None{}

def getLatestPiVersion(fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String, options: VersionCheckOptions) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    release : Result<&2, &2, String, Maybe<&2, LatestPiRelease>> <- getLatestPiRelease(fetch, context, currentVersion, options)
    return Result.map(&2, &2, String, Maybe<&2, LatestPiRelease>, Maybe<&2, String>, versionOf, release)

def newer(+currentVersion: String, result: Result<&2, &2, String, Maybe<&2, LatestPiRelease>>) -> Maybe<&2, LatestPiRelease>:
  match result:
    case Done{Some{LatestPiRelease{+version, packageName, note}}}: Bool.pick(Maybe<&2, LatestPiRelease>, isNewerPackageVersion(version, currentVersion), Some{LatestPiRelease{version, packageName, note}}, None{})
    case _: None{}

def automatic(skip: Bool, fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String) -> IO(Maybe<&2, LatestPiRelease>):
  match skip:
    case True{}: IO.pure(Maybe<&2, LatestPiRelease>, None{})
    case False{}:
      do IO<Maybe<&2, LatestPiRelease>>:
        release : Result<&2, &2, String, Maybe<&2, LatestPiRelease>> <- getLatestPiRelease(fetch, context, currentVersion, defaultOptions())
        return newer(currentVersion, release)

# upstream checkForNewPiVersion: one request unless PI_SKIP_VERSION_CHECK is
# set; the release only when it is newer, and nothing on any failure.
def checkForNewPiVersion(fetch: Fetch.Fetch(Unit), +context: URL.Context, +currentVersion: String) -> IO(Maybe<&2, LatestPiRelease>):
  do IO<Maybe<&2, LatestPiRelease>>:
    skip : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_SKIP_VERSION_CHECK")
    automatic(set(skip), fetch, context, currentVersion)
