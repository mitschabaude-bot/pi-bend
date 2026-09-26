import Base
import ../packages/coding-agent/src/utils/tools-manager.bend as Tools
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/ref.bend as Ref
import ./loopback-fetch.bend as Loop

# upstream packages/coding-agent/test/tools-manager.test.ts. Instead of a
# stubbed global fetch, the library's https://github.com requests go through a
# logging fetch to tests/tools_manager_latest_check.py's local server, which
# answers per repository path. Args: <server base> <empty bin directory>.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def version(result: Tools.Outcome(String), +expected: String) -> Bool:
  match result:
    case Done{value}: String.eq(value, expected)
    case Fail{_}: False{}

def failure(result: Tools.Outcome(String), +expected: String) -> Bool:
  match result:
    case Fail{message}: String.eq(message, expected)
    case Done{_}: False{}

def onlyRequest(lines: List<&2, String>, +url: String) -> Bool:
  match lines:
    case line <> Nil{}: String.starts_with(line, "GET " ++ url ++ "\t")
    case _: False{}

def latest(+fetch: Fetch.Fetch(Unit), repo: String) -> IO(Tools.Outcome(String)): Tools.getLatestVersion(fetch, Loop.urlContext(), repo)

def latestCases(+fetch: Fetch.Fetch(Unit), +log: Loop.Log()) -> IO(Unit):
  do IO<Unit>:
    fd : Tools.Outcome(String) <- latest(fetch, "sharkdp/fd")
    lines : List<&2, String> <- Loop.requests(log)
    check(version(fd, "10.4.2") && onlyRequest(lines, "https://github.com/sharkdp/fd/releases/latest"), "getLatestVersion resolves the version from the release page redirect")
    rg : Tools.Outcome(String) <- latest(fetch, "BurntSushi/ripgrep")
    check(version(rg, "15.2.0"), "getLatestVersion keeps tags without a v prefix intact")
    relative : Tools.Outcome(String) <- latest(fetch, "relative/fd")
    check(version(relative, "10.4.2"), "getLatestVersion resolves relative redirect targets")
    body : Tools.Outcome(String) <- latest(fetch, "body/fd")
    check(version(body, "10.4.2"), "getLatestVersion discards the redirect response body")
    missing : Tools.Outcome(String) <- latest(fetch, "missing/fd")
    check(failure(missing, "Failed to resolve latest missing/fd release: HTTP 404 without redirect"), "getLatestVersion fails clearly when the endpoint does not redirect")
    login : Tools.Outcome(String) <- latest(fetch, "login/fd")
    check(failure(login, "Failed to resolve latest login/fd release: unexpected redirect to https://github.com/login"), "getLatestVersion fails clearly when the redirect does not point at a release tag")

def Statuses() -> Data: Ref.Ref<List<&2, String>>

def kindName(kind: Tools.ToolStatusType) -> String:
  match kind:
    case Tools.Info{}: "info"
    case Tools.Warning{}: "warning"

def recorded(statuses: Statuses(), status: Tools.ToolStatus) -> IO(Unit):
  match status:
    case Tools.ToolStatus{kind, message}: Ref.modify(List<&2, String>, Unit, statuses, list => (List.append(&2, String, list, [kindName(kind) ++ ": " ++ message]), Unit{}))

def statusesAre(values: List<&2, String>, expected: List<&2, String>) -> Bool:
  match values expected:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: String.eq(a, b) && statusesAre(as, bs)
    case _ _: False{}

def ensureOffline(+binDir: String, +fetch: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    set : Result<&1, &1, U32 & String, Unit> <- IO.set_env("PI_OFFLINE", "1")
    +statuses : Statuses() <- Ref.new(List<&2, String>, Nil{})
    +callback : C.Callback<Tools.ToolStatus, Unit> <- C.create(~Statuses(), ~Tools.ToolStatus, ~Unit, ~recorded, statuses)
    result : Maybe<&2, String> <- Tools.ensureTool(Tools.ToolsManager{binDir, Loop.urlContext(), Some{fetch}}, Tools.Fd{}, Some{callback})
    C.dispose(Tools.ToolStatus, Unit, callback)
    seen : List<&2, String> <- Ref.dispose(List<&2, String>, statuses)
    check(Maybe.is_none(&2, String, result) && statusesAre(seen, ["warning: fd not found. Offline mode enabled, skipping download."]), "ensureTool reports status through a callback without writing to the console")

def run(+binDir: String, pair: Fetch.Fetch(Unit) & Loop.Log()) -> IO(Unit):
  match pair:
    case (+fetch, log):
      do IO<Unit>:
        latestCases(fetch, log)
        ensureOffline(binDir, fetch)
        Loop.retired(fetch)

def cases(+base: String, +binDir: String, +inner: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Fetch(Unit) & Loop.Log() <- Loop.redirecting(inner, "https://github.com", base)
    run(binDir, pair)

def started(args: List<String>) -> IO(Unit):
  match args:
    case base <> binDir <> Nil{}: Loop.withNetwork(inner => cases(base, binDir, inner))
    case _: IO.die(Unit, 2, "usage: tools-manager-latest <server base> <bin dir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
