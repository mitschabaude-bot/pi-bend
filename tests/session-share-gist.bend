import Base
import ../packages/coding-agent/src/modes/interactive/session-share.bend as Share
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/filesystem.bend as FS

def display(result: Share.ShareResult) -> IO(Unit):
  match result:
    case Share.GistShared{viewer,gist}: IO.print("SHARED " ++ viewer ++ " " ++ gist)
    case Share.RadiusShared{url}: IO.print("RADIUS " ++ url)
    case Share.Failed{message}: IO.print("FAILED " ++ message)
    case Share.Cancelled{}: IO.print("CANCELLED")

def afterCheck(found: Result<&2,&2,String,String>,file: String,cwd: String,env: List<String>,signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match found:
    case Fail{message}: IO.print("CHECK " ++ message)
    case Done{program}:
      do IO<Unit>:
        result : Share.ShareResult <- Share.createGist(program,file,cwd,env,signal)
        display(result)

def run(file: String,+cwd: String) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    checkEnv : List<String> <- IO.environment()
    found : Result<&2,&2,String,String> <- Share.checkGithub(cwd,checkEnv)
    gistEnv : List<String> <- IO.environment()
    afterCheck(found,file,cwd,gistEnv,Abort.signal(Unit,controller))
    Abort.dispose(Unit,controller)

def dispatch(args: List<String>,cwdResult: Result<&2,&2,FS.Error,String>) -> IO(Unit):
  match args cwdResult:
    case file <> Nil{} Done{cwd}: run(file,cwd)
    case _ _: IO.die(Unit,1,"expected HTML path")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cwdResult : Result<&2,&2,FS.Error,String> <- FS.cwd()
    dispatch(args,cwdResult)
