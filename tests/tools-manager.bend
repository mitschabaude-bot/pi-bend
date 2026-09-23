import Base
import ../packages/coding-agent/src/utils/tools-manager.bend as Tools
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/base64.bend as B
import ../packages/runtime/src/utf8.bend as U

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

def run(args: List<String>) -> IO(Unit):
  match args:
    case "download" <> url <> dest <> Nil{}:
      do IO<Unit>:
        runtime : Result<&2,&1,Fetch.InitError,Fetch.Runtime> <- Fetch.create(Runtime.files(),Runtime.httpOptions())
        download(url,dest,runtime)
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
