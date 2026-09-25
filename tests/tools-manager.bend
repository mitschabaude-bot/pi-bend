import Base
import ../packages/coding-agent/src/utils/tools-manager.bend as Tools
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/base64.bend as B
import ../packages/runtime/src/utf8.bend as U
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/url.bend as URL
import ../packages/coding-agent/src/utils/management-http.bend as Http

def encoded(value: String) -> String: B.encoded(U.encode(value),"")

def outcome(value: Tools.Outcome(Unit)) -> IO(Unit):
  match value:
    case Done{_}: IO.print("ok")
    case Fail{message}: IO.print("error:" ++ encoded(message))

def installed(value: Tools.Outcome(String)) -> IO(Unit):
  match value:
    case Done{path}: IO.print("installed:" ++ encoded(path))
    case Fail{message}: IO.print("error:" ++ encoded(message))

def found(value: Maybe<&2,String>) -> IO(Unit):
  match value:
    case Some{path}: IO.print("path:" ++ encoded(path))
    case None{}: IO.print("none")

def status(unused: Unit, value: Tools.ToolStatus) -> IO(Unit):
  match value:
    case Tools.ToolStatus{Tools.Info{},message}: IO.print("info:" ++ encoded(message))
    case Tools.ToolStatus{Tools.Warning{},message}: IO.print("warning:" ++ encoded(message))

def tool(name: String) -> Tools.Tool:
  match name:
    case "fd": Tools.Fd{}
    case _: Tools.Rg{}

def downloaded(+url: String,+dest: String,pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime,+fetch):
      do IO<Unit>:
        result : Tools.Outcome(Unit) <- Tools.downloadFile(fetch,Runtime.urlContext(),url,dest)
        outcome(result)
        Fetch.retire(Unit,fetch)
        Fetch.dispose(runtime)

# Plain HTTP against the checker's local server.
def download(+url: String,+dest: String,runtime: Result<&2,&1,Fetch.InitError,Fetch.Runtime>) -> IO(Unit):
  match runtime:
    case Fail{_}: IO.print("error:" ++ encoded("runtime"))
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit,runtime)
        downloaded(url,dest,pair)

def ensure(manager: Tools.ToolsManager,+name: String) -> IO(Unit):
  do IO<Unit>:
    +callback : C.Callback<Tools.ToolStatus,Unit> <- C.create(~Unit,~Tools.ToolStatus,~Unit,~status,Unit{})
    path : Maybe<&2,String> <- Tools.ensureTool(manager,tool(name),Some{callback})
    found(path)
    C.dispose(Tools.ToolStatus,Unit,callback)

# The CLI's own HTTPS transport, for the live GitHub download.
def live(+binDir: String,+name: String,transport: Runtime.Outcome(Runtime.Transport)) -> IO(Unit):
  match transport:
    case Fail{message}: IO.print("error:" ++ encoded(message))
    case Done{Runtime.Transport{authorizer,runtime,+fetch}}:
      do IO<Unit>:
        ensure(Tools.ToolsManager{binDir,Runtime.urlContext(),Some{fetch}},name)
        Runtime.disposeTransport(Runtime.Transport{authorizer,runtime,fetch})

# management-http.test.ts: fetchWithRetry with a per-attempt timeout, or
# with a caller signal aborted before the call. Prints the final status or
# the error.
def probed(result: Http.ScopedOutcome()) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error:" ++ encoded(Http.errorMessage(error)))
    case Done{Response.Response{+metadata,body}}:
      +code = Response.metadataStatus(metadata)
      do IO<Unit>:
        Tools.release(Response.Response{metadata,body})
        IO.print("status:" ++ encoded(U32.show(code)))

def probeAt(fetch: Fetch.Fetch(Unit), target: Tools.Outcome(URL.URL), +attempt: U32, +budget: U32, cancelled: Bool) -> IO(Unit):
  match target:
    case Fail{message}: IO.print("error:" ++ encoded(message))
    case Done{url}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        Bool.pick(Unit -> IO(Unit), cancelled, _ => IO.bind(Bool, Unit, Abort.abort(Unit, controller, None{}), _ => IO.pure(Unit, Unit{})), _ => IO.pure(Unit, Unit{}))(Unit{})
        result : Http.ScopedOutcome() <- Http.fetchWithRetry(fetch,Runtime.urlContext(),Http.Request{url,Message.new(),Http.Follow{}},Abort.signal(Unit,controller),Http.FetchRetryOptions{None{},None{},budget,Bool.pick(Maybe<&2,U32>,U32.is_eq(attempt,0),None{},Some{attempt})})
        probed(result)
        Abort.dispose(Unit,controller)

def probeWith(+url: String, +attempt: U32, +budget: U32, cancelled: Bool, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime,+fetch):
      do IO<Unit>:
        probeAt(fetch,Tools.parsed(Runtime.urlContext(),url),attempt,budget,cancelled)
        Fetch.retire(Unit,fetch)
        Fetch.dispose(runtime)

def probe(+url: String, +attempt: U32, +budget: U32, cancelled: Bool, runtime: Result<&2,&1,Fetch.InitError,Fetch.Runtime>) -> IO(Unit):
  match runtime:
    case Fail{_}: IO.print("error:" ++ encoded("runtime"))
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit,runtime)
        probeWith(url,attempt,budget,cancelled,pair)

def number(+text: String) -> U32: U32.from_nat(Maybe.default(&2,Nat,Nat.read(text),0n))

def run(args: List<String>) -> IO(Unit):
  match args:
    case "download" <> url <> dest <> Nil{}:
      do IO<Unit>:
        runtime : Result<&2,&1,Fetch.InitError,Fetch.Runtime> <- Fetch.create(Runtime.files(),Runtime.httpOptions())
        download(url,dest,runtime)
    case "probe" <> url <> attempt <> budget <> cancelled <> Nil{}:
      do IO<Unit>:
        runtime : Result<&2,&1,Fetch.InitError,Fetch.Runtime> <- Fetch.create(Runtime.files(),Runtime.httpOptions())
        probe(url,number(attempt),number(budget),String.eq(cancelled,"cancelled"),runtime)
    case "install" <> archive <> extractDir <> asset <> binary <> target <> Nil{}:
      do IO<Unit>:
        result : Tools.Outcome(String) <- Tools.extractAndInstall(archive,extractDir,asset,binary,target)
        installed(result)
    case "ensure" <> binDir <> name <> Nil{}: ensure(Tools.ToolsManager{binDir,Runtime.urlContext(),None{}},name)
    case "live" <> binDir <> name <> bundle <> Nil{}:
      do IO<Unit>:
        transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(bundle)
        live(binDir,name,transport)
    case _: IO.die(Unit,1,"usage: download URL DEST | install ARCHIVE DIR ASSET BINARY TARGET | ensure BINDIR TOOL | live BINDIR TOOL BUNDLE")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
