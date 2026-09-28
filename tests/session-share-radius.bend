import Base
import ../packages/coding-agent/src/modes/interactive/session-share.bend as Share
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/ai/src/api/credential-http.bend as Http
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/utf8.bend as Utf8

def display(result: Share.ShareResult) -> IO(Unit):
  match result:
    case Share.RadiusShared{url}: IO.print("SHARED " ++ url)
    case Share.Failed{message}: IO.print("FAILED " ++ message)
    case Share.Cancelled{}: IO.print("CANCELLED")
    case Share.GistShared{_,_}: IO.die(Unit,1,"unexpected gist result")

def borrowed(url: String,token: String,content: String,pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned,+fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Share.ShareResult <- Share.uploadRadius(Http.Transport{fetch,Runtime.urlContext(),Abort.signal(Unit,controller)},token,Utf8.encode(content),url)
        display(result)
        Abort.dispose(Unit,controller)
        Fetch.retire(Unit,fetch)
        Fetch.dispose(owned)

def initialized(url: String,token: String,content: String,created: Result<&2,&1,Fetch.InitError,Fetch.Runtime>) -> IO(Unit):
  match created:
    case Fail{_}: IO.die(Unit,1,"network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit,runtime)
        borrowed(url,token,content,pair)

def run(url: String,token: String,content: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&2,&1,Fetch.InitError,Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(),Runtime.httpOptions())
    initialized(url,token,content,created)

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case url <> token <> content <> Nil{}: run(url,token,content)
    case _: IO.die(Unit,1,"expected url, token and content")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
