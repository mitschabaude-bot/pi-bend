import Base
import ../config.bend as Config
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/text.bend as Text

# External search tools: the agent's bin directory first, then the system
# PATH, then a download of the latest GitHub release.
type Tool is Data:
  Fd{}
  Rg{}

type ToolConfig is Data:
  ToolConfig{name: String, repo: String, binaryName: String, systemBinaryNames: List<&2,String>, tagPrefix: String}

def toolConfig(tool: Tool) -> ToolConfig:
  match tool:
    case Fd{}: ToolConfig{"fd","sharkdp/fd","fd",["fd","fdfind"],"v"}
    case Rg{}: ToolConfig{"ripgrep","BurntSushi/ripgrep","rg",["rg"],""}

def toolName(config: ToolConfig) -> String:
  match config:
    case ToolConfig{name,_,_,_,_}: name

type ToolStatusType is Data:
  Info{}
  Warning{}

type ToolStatus is Data:
  ToolStatus{kind: ToolStatusType, message: String}

def StatusCallback() -> Data: Maybe<&2,Callback.Callback<ToolStatus,Unit>>

def report(onStatus: StatusCallback(), status: ToolStatus) -> IO(Unit):
  match onStatus:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(ToolStatus,Unit,callback,status)

def offline(value: Result<&1,&1,U32 & String,String>) -> Bool:
  match value:
    case Fail{_}: False{}
    case Done{+text}:
      # Only ASCII letters lowercase to the letters of "true" and "yes".
      +lower = Text.asciiLower(text)
      String.eq(text,"1") || String.eq(lower,"true") || String.eq(lower,"yes")

def isOfflineModeEnabled() -> IO(Bool):
  do IO<Bool>:
    value : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_OFFLINE")
    return offline(value)

def ignored(unit: Unit, bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})

def spawnFailed(errors: List<&2,Child.Error>) -> Bool:
  match errors:
    case Nil{}: False{}
    case Child.Error{operation,_,_} <> rest: String.eq(operation,"spawn") || spawnFailed(rest)

def started(result: Result<&2,&2,Child.ExecutionError,U32>) -> Bool:
  match result:
    case Fail{Child.ExecutionFailed{errors}}: Bool.not(spawnFailed(errors))
    case _: True{}

# A command exists when it can be started; its --version output is discarded.
def commandExists(command: String) -> IO(Bool):
  do IO<Bool>:
    +discard : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~List<&2,U32>,~Result<&2,&2,String,Unit>,~ignored,Unit{})
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    env : List<String> <- IO.environment()
    result : Result<&2,&2,Child.ExecutionError,U32> <- Child.spawn(command,["--version"],Result.default(&2,&2,FS.Error,String,cwd,"."),env,Nil{},discard,discard)
    Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,discard)
    return started(result)

def firstCommand(names: List<&2,String>) -> IO(Maybe<&2,String>):
  match names:
    case Nil{}: IO.pure(Maybe<&2,String>,None{})
    case +name <> rest:
      do IO<Maybe<&2,String>>:
        exists : Bool <- commandExists(name)
        Bool.pick(IO(Maybe<&2,String>),exists,IO.pure(Maybe<&2,String>,Some{name}),firstCommand(rest))

def systemPath(+localPath: String, local: Bool, names: List<&2,String>) -> IO(Maybe<&2,String>):
  match local:
    case True{}: IO.pure(Maybe<&2,String>,Some{localPath})
    case False{}: firstCommand(names)

def localToolPath(config: ToolConfig, binDir: Result<&2,&2,FS.Error,String>) -> IO(Maybe<&2,String>):
  match config binDir:
    case ToolConfig{_,_,_,names,_} Fail{_}: firstCommand(names)
    case ToolConfig{_,_,binaryName,names,_} Done{directory}:
      +localPath = Path.join(directory,binaryName)
      do IO<Maybe<&2,String>>:
        local : Bool <- FS.accessible(localPath,0)
        systemPath(localPath,local,names)

# The tools directory first; a system command is returned by name.
def getToolPath(tool: Tool) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    binDir : Result<&2,&2,FS.Error,String> <- Config.getBinDir()
    localToolPath(toolConfig(tool),binDir)

def downloadTool(tool: Tool) -> IO(Result<&2,&2,String,String>):
  IO.pure(Result<&2,&2,String,String>,Fail{"downloading is not ported yet"})

def downloaded(name: String, onStatus: StatusCallback(), result: Result<&2,&2,String,String>) -> IO(Maybe<&2,String>):
  match result:
    case Done{+path}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Info{},name ++ " installed to " ++ path})
        return Some{path}
    case Fail{message}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Warning{},"Failed to download " ++ name ++ ": " ++ message})
        return None{}

def download(tool: Tool, +name: String, +onStatus: StatusCallback(), isOffline: Bool) -> IO(Maybe<&2,String>):
  match isOffline:
    case True{}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Warning{},name ++ " not found. Offline mode enabled, skipping download."})
        return None{}
    case False{}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Info{},name ++ " not found. Downloading..."})
        result : Result<&2,&2,String,String> <- downloadTool(tool)
        downloaded(name,onStatus,result)

def missing(+tool: Tool, onStatus: StatusCallback(), existing: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match existing:
    case Some{path}: IO.pure(Maybe<&2,String>,Some{path})
    case None{}:
      do IO<Maybe<&2,String>>:
        isOffline : Bool <- isOfflineModeEnabled()
        download(tool,toolName(toolConfig(tool)),onStatus,isOffline)

# The tool's path, downloading it when needed; None when it stays unavailable.
# Progress reaches onStatus, which otherwise stays silent.
def ensureTool(+tool: Tool, onStatus: StatusCallback()) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    existing : Maybe<&2,String> <- getToolPath(tool)
    missing(tool,onStatus,existing)
