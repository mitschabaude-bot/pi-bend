import Base
import ../packages/coding-agent/src/utils/version-check.bend as VC
import ../packages/coding-agent/src/utils/pi-user-agent.bend as UA
import ../packages/runtime/src/fetch.bend as Fetch
import ./loopback-fetch.bend as Loop

# upstream packages/coding-agent/test/version-check.test.ts and
# pi-user-agent.test.ts. Instead of stubbing the global fetch, the library's
# request to https://pi.dev goes through a logging fetch to the local server
# of tests/version_check_check.py, whose path prefix selects the answer:
# /same, /ua, /meta and /note answer JSON; /flaky drops two connections and
# then answers; /down drops every connection. Args: <server base> <platform>
# <arch> (Node's process.platform and process.arch for this machine).

def setEnv(name: String, value: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, Unit> <- IO.set_env(name, value)
    return Unit{}

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def yields(order: Maybe<&2, Cmp>, wanted: Cmp) -> Bool:
  match order wanted:
    case Some{GT{}} GT{}: True{}
    case Some{EQ{}} EQ{}: True{}
    case Some{LT{}} LT{}: True{}
    case _ _: False{}

def compares() -> IO(Unit):
  check(yields(VC.comparePackageVersions("0.70.6", "0.70.5"), GT{}) && yields(VC.comparePackageVersions("0.70.5", "0.70.5"), EQ{}) && yields(VC.comparePackageVersions("0.70.4", "0.70.5"), LT{}) && yields(VC.comparePackageVersions("5.0.0-beta.20", "5.0.0-beta.9"), GT{}) && Bool.not(VC.isNewerPackageVersion("0.70.5", "0.70.5")) && VC.isNewerPackageVersion("0.70.6", "0.70.5"), "version checks compares package versions")

def sameMaybe(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

# toEqual on the release object.
def release(value: Maybe<&2, VC.LatestPiRelease>, +version: String, packageName: Maybe<&2, String>, note: Maybe<&2, String>) -> Bool:
  match value:
    case Some{VC.LatestPiRelease{v, p, n}}: String.eq(v, version) && sameMaybe(p, packageName) && sameMaybe(n, note)
    case None{}: False{}

def fetched(value: Result<&2, &2, String, Maybe<&2, VC.LatestPiRelease>>, +version: String, packageName: Maybe<&2, String>, note: Maybe<&2, String>) -> Bool:
  match value:
    case Done{found}: release(found, version, packageName, note)
    case Fail{_}: False{}

def versionIs(value: Result<&2, &2, String, Maybe<&2, String>>, +version: String) -> Bool:
  match value:
    case Done{Some{found}}: String.eq(found, version)
    case _: False{}

def count(+log: Loop.Log()) -> IO(Nat):
  do IO<Nat>:
    lines : List<&2, String> <- Loop.requests(log)
    return List.length(&2, String, lines)

def firstRequest(lines: List<&2, String>) -> String:
  match lines:
    case line <> _: line
    case Nil{}: ""

def fieldValue(fields: List<&2, String>, +name: String) -> Maybe<&2, String>:
  match fields:
    case Nil{}: None{}
    case +field <> rest: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(field, name ++ ": "), _ => Some{String.drop(field, Nat.add(String.length(name), 2n))}, _ => fieldValue(rest, name))(Unit{})

def requestFields(+line: String) -> List<&2, String>: String.split(line, '\t')

def userAgentMatches(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{text}: String.starts_with(text, "pi/1.2.3 ")
    case None{}: False{}

def acceptJson(value: Maybe<&2, String>) -> Bool: sameMaybe(value, Some{"application/json"})

def requested(+line: String) -> Bool:
  +fields = requestFields(line)
  String.starts_with(line, "GET https://pi.dev/api/latest-version\t") && userAgentMatches(fieldValue(fields, "user-agent")) && acceptJson(fieldValue(fields, "accept"))

def onlyNewer(+fetch: Fetch.Fetch(Unit), log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    same : Maybe<&2, VC.LatestPiRelease> <- VC.checkForNewPiVersion(fetch, Loop.urlContext(), "1.2.3")
    older : Maybe<&2, VC.LatestPiRelease> <- VC.checkForNewPiVersion(fetch, Loop.urlContext(), "1.2.2")
    check(Maybe.is_none(&2, VC.LatestPiRelease, same) && release(older, "1.2.3", None{}, None{}), "version checks returns only newer versions")

def piUserAgent(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    version : Result<&2, &2, String, Maybe<&2, String>> <- VC.getLatestPiVersion(fetch, Loop.urlContext(), "1.2.3", VC.defaultOptions())
    lines : List<&2, String> <- Loop.requests(log)
    check(versionIs(version, "1.2.4") && requested(firstRequest(lines)), "version checks uses the pi.dev version check api with a pi user agent")

def retried(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Maybe<&2, VC.LatestPiRelease>> <- VC.getLatestPiRelease(fetch, Loop.urlContext(), "1.2.3", VC.VersionCheckOptions{None{}, True{}})
    calls : Nat <- count(log)
    check(fetched(result, "1.2.4", None{}, None{}) && Nat.is_eq(calls, 3n), "version checks retries a transient version request when explicitly requested")

def oneRequest(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    result : Maybe<&2, VC.LatestPiRelease> <- VC.checkForNewPiVersion(fetch, Loop.urlContext(), "1.2.3")
    calls : Nat <- count(log)
    check(Maybe.is_none(&2, VC.LatestPiRelease, result) && Nat.is_eq(calls, 1n), "version checks keeps automatic version checks to one request")

def metadata(+fetch: Fetch.Fetch(Unit), log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Maybe<&2, VC.LatestPiRelease>> <- VC.getLatestPiRelease(fetch, Loop.urlContext(), "1.2.3", VC.defaultOptions())
    check(fetched(result, "1.2.4", Some{"@new-scope/pi"}, None{}), "version checks returns the active package metadata from the version check api")

def notes(+fetch: Fetch.Fetch(Unit), log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Maybe<&2, VC.LatestPiRelease>> <- VC.getLatestPiRelease(fetch, Loop.urlContext(), "1.2.3", VC.defaultOptions())
    check(fetched(result, "1.2.4", None{}, Some{"**Read this**"}), "version checks returns update notes from the version check api")

def skipped(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    setEnv("PI_SKIP_VERSION_CHECK", "1")
    result : Maybe<&2, VC.LatestPiRelease> <- VC.checkForNewPiVersion(fetch, Loop.urlContext(), "1.2.3")
    calls : Nat <- count(log)
    check(Maybe.is_none(&2, VC.LatestPiRelease, result) && Nat.is_eq(calls, 0n), "version checks skips automatic api calls when version checks are disabled")

def direct(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    setEnv("PI_SKIP_VERSION_CHECK", "1")
    version : Result<&2, &2, String, Maybe<&2, String>> <- VC.getLatestPiVersion(fetch, Loop.urlContext(), "1.2.3", VC.defaultOptions())
    calls : Nat <- count(log)
    setEnv("PI_SKIP_VERSION_CHECK", "")
    check(versionIs(version, "1.2.4") && Nat.is_eq(calls, 1n), "version checks allows direct api calls when automatic version checks are disabled")

def act(name: String, +fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  match name:
    case "onlyNewer": onlyNewer(fetch, log)
    case "piUserAgent": piUserAgent(fetch, log)
    case "retried": retried(fetch, log)
    case "oneRequest": oneRequest(fetch, log)
    case "metadata": metadata(fetch, log)
    case "notes": notes(fetch, log)
    case "skipped": skipped(fetch, log)
    case _: direct(fetch, log)

def run(+name: String, pair: Fetch.Fetch(Unit) & Loop.Log()) -> IO(Unit):
  match pair:
    case (+fetch, +log):
      do IO<Unit>:
        act(name, fetch, log)
        Loop.retired(fetch)

# One redirecting fetch per case, so each case counts its own requests.
def scenario(+inner: Fetch.Fetch(Unit), +base: String, +route: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Fetch(Unit) & Loop.Log() <- Loop.redirecting(inner, "https://pi.dev", base ++ "/" ++ route)
    run(name, pair)

def cases(+base: String, +inner: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    compares()
    scenario(inner, base, "same", "onlyNewer")
    scenario(inner, base, "ua", "piUserAgent")
    scenario(inner, base, "flaky", "retried")
    scenario(inner, base, "down", "oneRequest")
    scenario(inner, base, "meta", "metadata")
    scenario(inner, base, "note", "notes")
    scenario(inner, base, "ua", "skipped")
    scenario(inner, base, "ua", "direct")

# pi-user-agent.test.ts: the exact value for this runtime, and upstream's
# shape /^pi\/[^\s()]+ \([^;()]+;\s*[^;()]+;\s*[^()]+\)$/.
def userAgentCase(+platform: String, +arch: String) -> IO(Unit):
  do IO<Unit>:
    agent : String <- UA.getPiUserAgent("1.2.3")
    check(String.eq(agent, "pi/1.2.3 (" ++ platform ++ "; " ++ UA.runtime() ++ "; " ++ arch ++ ")"), "getPiUserAgent formats the user agent expected by pi.dev")

def started(args: List<String>) -> IO(Unit):
  match args:
    case base <> platform <> arch <> Nil{}:
      do IO<Unit>:
        userAgentCase(platform, arch)
        setEnv("PI_OFFLINE", "")
        setEnv("PI_SKIP_VERSION_CHECK", "")
        Loop.withNetwork(inner => cases(base, inner))
    case _: IO.die(Unit, 2, "usage: version-check <server base> <platform> <arch>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
