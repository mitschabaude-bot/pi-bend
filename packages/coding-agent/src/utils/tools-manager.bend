import Base
import ../config.bend as Config
import ./management-http.bend as Http
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/uri-component.bend as URI
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as Number

# External search tools: the agent's bin directory first, then the system
# PATH, then a download of the latest GitHub release. Bend has no global fetch:
# the manager holds the process's fetch (None where nothing may be downloaded).
type ToolsManager is Data:
  ToolsManager{binDir: String, url: URL.Context, fetch: Maybe<&2,Fetch.Fetch(Unit)>}

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

# spawnSync in the process's working directory and environment.
def run(command: String, args: List<String>) -> IO(Child.Completed):
  do IO<Child.Completed>:
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    env : List<String> <- IO.environment()
    Child.spawnSync(command,args,Result.default(&2,&2,FS.Error,String,cwd,"."),env,Nil{})

def spawnError(command: String, errors: List<&2,Child.Error>) -> Maybe<&2,String>:
  match errors:
    case Nil{}: None{}
    case Child.Error{"spawn",code,_} <> _: Some{"spawnSync " ++ command ++ " " ++ FS.errnoName(code)}
    case _ <> rest: spawnError(command,rest)

def started(completed: Child.Completed) -> Bool:
  match completed:
    case Child.Completed{Fail{Child.ExecutionFailed{errors}},_,_}: Maybe.is_none(&2,String,spawnError("",errors))
    case _: True{}

# A command exists when it can be started; its --version output is discarded.
def commandExists(command: String) -> IO(Bool):
  do IO<Bool>:
    completed : Child.Completed <- run(command,["--version"])
    return started(completed)

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

# The tools directory first; a system command is returned by name.
def localToolPath(binDir: String, config: ToolConfig) -> IO(Maybe<&2,String>):
  match config:
    case ToolConfig{_,_,binaryName,names,_}:
      +localPath = Path.join(binDir,binaryName)
      do IO<Maybe<&2,String>>:
        local : Bool <- FS.accessible(localPath,0)
        systemPath(localPath,local,names)

def getToolPath(binDir: String, tool: Tool) -> IO(Maybe<&2,String>): localToolPath(binDir,toolConfig(tool))

# Download
# --------

def Outcome(-A: Data) -> Data: Result<&2,&2,String,A>

def urlOutcome(+address: String, result: Result<&2,&2,URL.Error,URL.URL>) -> Outcome(URL.URL):
  match result:
    case Fail{_}: Fail{"Invalid URL: " ++ address}
    case Done{url}: Done{url}

def parsed(context: URL.Context, +address: String) -> Outcome(URL.URL): urlOutcome(address,URL.parse(context,address))

def withHeader(+name: String, +value: String) -> Message.Headers:
  Result.default(&2,&2,Message.HeaderSyntaxError,Message.Headers,Message.set(Message.new(),name,value),Message.new())

def release(response: Response.Response<Http.Scoped()>) -> IO(Unit):
  match response:
    case Response.Response{_,body}:
      do IO<Unit>:
        next : Response.Next<Http.ReadError(),Http.Scoped()> <- Response.closeWith(Http.ReadError(),Http.Scoped(),Http.close,body)
        return Unit{}

def lastSegment(url: URL.URL) -> String:
  match url:
    case URL.URL{_,_,_,_,_,URL.Hierarchical{segments},_,_}: Maybe.default(&2,String,List.last(&2,String,segments),"")
    case _: ""

def withoutV(tag: String) -> String:
  match tag:
    case SCon{'v',rest}: rest
    case other: other

def decodedTag(tag: Maybe<&2,String>) -> Outcome(String):
  match tag:
    case None{}: Fail{"URI malformed"}
    case Some{value}: Done{withoutV(value)}

def taggedVersion(+repo: String, +location: String, tag: String) -> Outcome(String):
  match tag:
    case SNil{}: Fail{"Failed to resolve latest " ++ repo ++ " release: unexpected redirect to " ++ location}
    case value: Bool.pick(Outcome(String),String.contains(location,"/releases/tag/"),decodedTag(URI.decode(value)),Fail{"Failed to resolve latest " ++ repo ++ " release: unexpected redirect to " ++ location})

def resolvedTag(+repo: String, +location: String, result: Result<&2,&2,URL.ResolveError,URL.URL>) -> Outcome(String):
  match result:
    case Fail{_}: Fail{"Invalid URL: " ++ location}
    case Done{url}: taggedVersion(repo,location,lastSegment(url))

def fromBase(+context: URL.Context, +repo: String, +location: String, base: Outcome(URL.URL)) -> Outcome(String):
  match base:
    case Fail{message}: Fail{message}
    case Done{url}: resolvedTag(repo,location,URL.parseResolve(context,url,location))

# new URL(location, "https://github.com"): the tag is its last path segment.
def redirectTarget(+context: URL.Context, repo: String, location: String) -> Outcome(String):
  fromBase(context,repo,location,parsed(context,"https://github.com"))

def latestFrom(context: URL.Context, +repo: String, code: U32, location: Maybe<&2,String>) -> Outcome(String):
  match location:
    case Some{SCon{c,cs}}: redirectTarget(context,repo,SCon{c,cs})
    case _: Fail{"Failed to resolve latest " ++ repo ++ " release: HTTP " ++ U32.show(code) ++ " without redirect"}

def redirectLocation(+code: U32, metadata: Response.Metadata) -> Maybe<&2,String>:
  Bool.pick(Maybe<&2,String>,U32.is_ge(code,300) && U32.is_lt(code,400),Result.default(&2,&2,Message.HeaderSyntaxError,Maybe<&2,String>,Message.get(Response.headers(metadata),"location"),None{}),None{})

# Only the status and headers matter; the body is released at once.
def latestResponse(context: URL.Context, repo: String, result: Http.ScopedOutcome()) -> IO(Outcome(String)):
  match result:
    case Fail{error}: IO.pure(Outcome(String),Fail{Http.errorMessage(error)})
    case Done{Response.Response{+metadata,body}}:
      +code = Response.metadataStatus(metadata)
      do IO<Outcome(String)>:
        release(Response.Response{metadata,body})
        return latestFrom(context,repo,code,redirectLocation(code,metadata))

# The release page redirects to the tagged release without spending the
# anonymous API quota.
def latestAt(fetch: Fetch.Fetch(Unit), +context: URL.Context, +repo: String, target: Outcome(URL.URL)) -> IO(Outcome(String)):
  match target:
    case Fail{message}: IO.pure(Outcome(String),Fail{message})
    case Done{url}:
      do IO<Outcome(String)>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Http.ScopedOutcome() <- Http.fetchWithRetry(fetch,context,Http.Request{url,withHeader("User-Agent",Config.appName() ++ "-coding-agent"),Http.Manual{}},Abort.signal(Unit,controller),Http.FetchRetryOptions{None{},None{},10000,None{}})
        version : Outcome(String) <- latestResponse(context,repo,result)
        Abort.dispose(Unit,controller)
        return version

def getLatestVersion(fetch: Fetch.Fetch(Unit), +context: URL.Context, +repo: String) -> IO(Outcome(String)):
  latestAt(fetch,context,repo,parsed(context,"https://github.com/" ++ repo ++ "/releases/latest"))

def closedWith(outcome: Outcome(Unit), closed: Result<&2,&2,FS.Error,Unit>) -> Outcome(Unit):
  match outcome closed:
    case Fail{message} _: Fail{message}
    case Done{_} Fail{error}: Fail{FS.errorMessage(error)}
    case Done{_} Done{_}: Done{Unit{}}

def closeFile(file: File, outcome: Outcome(Unit)) -> IO(Outcome(Unit)):
  do IO<Outcome(Unit)>:
    closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
    return closedWith(outcome,FS.unit(closed))

def released(body: Response.Body<Http.Scoped()>) -> IO(Unit):
  do IO<Unit>:
    next : Response.Next<Http.ReadError(),Http.Scoped()> <- Response.closeWith(Http.ReadError(),Http.Scoped(),Http.close,body)
    return Unit{}

def wrote(pair: File & Result<&1,&1,U32 & String,Unit>, body: Response.Body<Http.Scoped()>, again: File -> Response.Body<Http.Scoped()> -> IO(Outcome(Unit))) -> IO(Outcome(Unit)):
  match pair:
    case (file,Done{_}): again(file,body)
    case (file,Fail{(code,message)}):
      do IO<Outcome(Unit)>:
        released(body)
        closeFile(file,Fail{FS.errorMessage(FS.System{code,message})})

def streamed(file: File, next: Response.Next<Http.ReadError(),Http.Scoped()>, again: File -> Response.Body<Http.Scoped()> -> IO(Outcome(Unit))) -> IO(Outcome(Unit)):
  match next:
    case Response.Next{_,Done{None{}}}: closeFile(file,Done{Unit{}})
    case Response.Next{_,Fail{_}}: closeFile(file,Fail{"terminated"})
    case Response.Next{body,Done{Some{bytes}}}:
      do IO<Outcome(Unit)>:
        pair : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        wrote(pair,body,again)

# The body streams into the file as it arrives; the server bounds its length.
@unsafe def stream(file: File, body: Response.Body<Http.Scoped()>) -> IO(Outcome(Unit)):
  do IO<Outcome(Unit)>:
    next : Response.Next<Http.ReadError(),Http.Scoped()> <- Response.nextWith(~Http.ReadError(),~Http.Scoped(),~Http.read,~Http.close,body)
    streamed(file,next,file => body => stream(file,body))

def opened(body: Response.Body<Http.Scoped()>, result: Result<&1,&1,U32 & String,File>) -> IO(Outcome(Unit)):
  match result:
    case Done{file}: stream(file,body)
    case Fail{(code,message)}:
      do IO<Outcome(Unit)>:
        released(body)
        return Fail{FS.errorMessage(FS.System{code,message})}

def saveBody(ok: Bool, +code: U32, dest: String, url: String, body: Response.Body<Http.Scoped()>) -> IO(Outcome(Unit)):
  match ok:
    case True{}:
      do IO<Outcome(Unit)>:
        file : Result<&1,&1,U32 & String,File> <- File.open_mode(dest,"w",438)
        opened(body,file)
    case False{}:
      do IO<Outcome(Unit)>:
        released(body)
        return Fail{"Download failed with HTTP " ++ U32.show(code) ++ ": " ++ url}

def save(dest: String, url: String, result: Http.ScopedOutcome()) -> IO(Outcome(Unit)):
  match result:
    case Fail{error}: IO.pure(Outcome(Unit),Fail{Http.errorMessage(error)})
    case Done{Response.Response{+metadata,body}}: saveBody(Response.ok(metadata),Response.metadataStatus(metadata),dest,url,body)

def downloadTo(fetch: Fetch.Fetch(Unit), +context: URL.Context, +url: String, +dest: String, target: Outcome(URL.URL)) -> IO(Outcome(Unit)):
  match target:
    case Fail{message}: IO.pure(Outcome(Unit),Fail{message})
    case Done{address}:
      do IO<Outcome(Unit)>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Http.ScopedOutcome() <- Http.fetchWithRetry(fetch,context,Http.Request{address,Message.new(),Http.Follow{}},Abort.signal(Unit,controller),Http.FetchRetryOptions{None{},None{},120000,None{}})
        saved : Outcome(Unit) <- save(dest,url,result)
        Abort.dispose(Unit,controller)
        return saved

def downloadFile(fetch: Fetch.Fetch(Unit), +context: URL.Context, +url: String, dest: String) -> IO(Outcome(Unit)):
  downloadTo(fetch,context,url,dest,parsed(context,url))

# Install
# -------

# Node's os.arch() is the architecture this process was built for; the ELF
# header of the running executable names it (e_machine 183 is aarch64).
def archOf(header: Result<&2,&2,FS.Error,List<&2,U32>>) -> String:
  match header:
    case Done{bytes}: Bool.pick(String,U32.is_eq(Maybe.default(&2,U32,List.get(&2,U32,bytes,18n),0),183),"aarch64","x86_64")
    case Fail{_}: "x86_64"

def machineArch() -> IO(String):
  do IO<String>:
    header : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readPrefix("/proc/self/exe",20)
    return archOf(header)

# The Linux release assets; other platforms are outside this POSIX port.
def assetName(tool: Tool, +version: String, +arch: String) -> String:
  match tool:
    case Fd{}: "fd-v" ++ version ++ "-" ++ arch ++ "-unknown-linux-musl.tar.gz"
    case Rg{}: "ripgrep-" ++ version ++ "-" ++ arch ++ "-unknown-linux-musl.tar.gz"

def base36(index: Result<&2,&2,Random.Error,Nat>) -> Char:
  match index:
    case Done{value}: Maybe.default(&2,Char,String.get("0123456789abcdefghijklmnopqrstuvwxyz",value),'0')
    case Fail{_}: '0'

def randomSuffix(count: Nat) -> IO(String):
  match count:
    case 0n: IO.pure(String,"")
    case 1n+rest:
      do IO<String>:
        index : Result<&2,&2,Random.Error,Nat> <- Random.randomIndex(36n)
        suffix : String <- randomSuffix(rest)
        return SCon{base36(index),suffix}

def pidOf(path: Result<&2,&2,FS.Error,String>) -> String:
  match path:
    case Done{value}: Maybe.default(&2,String,List.last(&2,String,String.split(value,'/')),"0")
    case Fail{_}: "0"

# fd and rg downloads can run concurrently, so each extraction gets its own
# directory: extract_tmp_<binary>_<pid>_<Date.now()>_<random>.
def extractDirName(+binaryName: String) -> IO(String):
  do IO<String>:
    self : Result<&2,&2,FS.Error,String> <- FS.realpath("/proc/self")
    now : F64 <- Date.now()
    suffix : String <- randomSuffix(8n)
    return "extract_tmp_" ++ binaryName ++ "_" ++ pidOf(self) ++ "_" ++ Maybe.default(&2,String,Number.toDecimal(now),"0") ++ "_" ++ suffix

def trimmedText(bytes: List<&2,U32>) -> String: Text.trim(Utf8.decodeBuffer(bytes))

def formatSpawnFailure(+command: String, completed: Child.Completed) -> String:
  match completed:
    case Child.Completed{Fail{Child.ExecutionFailed{errors}},_,_}: Maybe.default(&2,String,spawnError(command,errors),"spawnSync " ++ command ++ " failed")
    case Child.Completed{result,stdout,stderr}:
      +err = trimmedText(stderr)
      +out = trimmedText(stdout)
      Bool.pick(String,Bool.not(String.is_empty(err)),err,Bool.pick(String,Bool.not(String.is_empty(out)),out,"exit status " ++ Result.default(&2,&2,Child.ExecutionError,String,Result.map(&2,&2,Child.ExecutionError,U32,String,U32.show,result),"unknown")))

def extractionFailure(+command: String, completed: Child.Completed) -> Maybe<&2,String>:
  match completed:
    case Child.Completed{Done{0},_,_}: None{}
    case failed: Some{command ++ ": " ++ formatSpawnFailure(command,failed)}

def extracted(asset: String, failure: Maybe<&2,String>) -> Outcome(Unit):
  match failure:
    case None{}: Done{Unit{}}
    case Some{message}: Fail{"Failed to extract " ++ asset ++ ": " ++ message}

def extractTarGzArchive(+archivePath: String, +extractDir: String, +asset: String) -> IO(Outcome(Unit)):
  do IO<Outcome(Unit)>:
    completed : Child.Completed <- run("tar",["xzf",archivePath,"-C",extractDir])
    return extracted(asset,extractionFailure("tar",completed))

# Depth-first, as upstream: the first matching regular file of a directory
# wins; its subdirectories are searched last-found first.
def scanEntries(+directory: String, +binaryFileName: String, entries: List<&2,FS.DirectoryEntry>, +stack: List<&2,String>) -> Maybe<&2,String> & List<&2,String>:
  match entries:
    case Nil{}: (None{},stack)
    case FS.DirectoryEntry{+name,FS.RegularFile{}} <> rest: Bool.pick(Unit -> Maybe<&2,String> & List<&2,String>,String.eq(name,binaryFileName),_ => (Some{Path.join(directory,name)},stack),_ => scanEntries(directory,binaryFileName,rest,stack))(Unit{})
    case FS.DirectoryEntry{name,FS.Directory{}} <> rest: scanEntries(directory,binaryFileName,rest,Path.join(directory,name) <> stack)
    case _ <> rest: scanEntries(directory,binaryFileName,rest,stack)

def scanned(pair: Maybe<&2,String> & List<&2,String>, again: List<&2,String> -> IO(Outcome(Maybe<&2,String>))) -> IO(Outcome(Maybe<&2,String>)):
  match pair:
    case (Some{path},_): IO.pure(Outcome(Maybe<&2,String>),Done{Some{path}})
    case (None{},stack): again(stack)

def listed(+directory: String, +binaryFileName: String, stack: List<&2,String>, entries: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>, again: List<&2,String> -> IO(Outcome(Maybe<&2,String>))) -> IO(Outcome(Maybe<&2,String>)):
  match entries:
    case Fail{error}: IO.pure(Outcome(Maybe<&2,String>),Fail{FS.errorMessage(error)})
    case Done{values}: scanned(scanEntries(directory,binaryFileName,values,stack),again)

# The extracted archive bounds the search.
@unsafe def findBinaryRecursively(+binaryFileName: String, stack: List<&2,String>) -> IO(Outcome(Maybe<&2,String>)):
  match stack:
    case Nil{}: IO.pure(Outcome(Maybe<&2,String>),Done{None{}})
    case +directory <> rest:
      do IO<Outcome(Maybe<&2,String>)>:
        entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(directory)
        listed(directory,binaryFileName,rest,entries,next => findBinaryRecursively(binaryFileName,next))

def firstExisting(candidates: List<&2,String>) -> IO(Maybe<&2,String>):
  match candidates:
    case Nil{}: IO.pure(Maybe<&2,String>,None{})
    case +candidate <> rest:
      do IO<Maybe<&2,String>>:
        found : Bool <- FS.accessible(candidate,0)
        Bool.pick(IO(Maybe<&2,String>),found,IO.pure(Maybe<&2,String>,Some{candidate}),firstExisting(rest))

def continued(-A: Data, -B: Data, result: Outcome(A), next: A -> IO(Outcome(B))) -> IO(Outcome(B)):
  match result:
    case Fail{message}: IO.pure(Outcome(B),Fail{message})
    case Done{value}: next(value)

def then(-A: Data, -B: Data, action: IO(Outcome(A)), next: A -> IO(Outcome(B))) -> IO(Outcome(B)):
  IO.bind(Outcome(A),Outcome(B),action,result => continued(A,B,result,next))

def fsOutcome(-A: Data, result: Result<&2,&2,FS.Error,A>) -> Outcome(A):
  match result:
    case Fail{error}: Fail{FS.errorMessage(error)}
    case Done{value}: Done{value}

def fsAction(action: IO(Result<&2,&2,FS.Error,Unit>)) -> IO(Outcome(Unit)):
  IO.bind(Result<&2,&2,FS.Error,Unit>,Outcome(Unit),action,result => IO.pure(Outcome(Unit),fsOutcome(Unit,result)))

def mkdirs(path: String) -> IO(Outcome(Unit)): fsAction(FS.mkdir(path))

def located(+binaryFileName: String, +extractDir: String, found: Maybe<&2,String>) -> IO(Outcome(Maybe<&2,String>)):
  match found:
    case Some{path}: IO.pure(Outcome(Maybe<&2,String>),Done{Some{path}})
    case None{}: findBinaryRecursively(binaryFileName,[extractDir])

def withoutArchiveSuffix(+asset: String) -> String:
  Bool.pick(String,String.ends_with(asset,".tar.gz"),String.take(asset,String.length(asset) - 7n),asset)

# Some archives hold the binary at their root, others under a versioned
# directory; anything else is searched for.
def locate(+binaryFileName: String, +extractDir: String, asset: String) -> IO(Outcome(Maybe<&2,String>)):
  do IO<Outcome(Maybe<&2,String>)>:
    found : Maybe<&2,String> <- firstExisting([Path.join(Path.join(extractDir,withoutArchiveSuffix(asset)),binaryFileName),Path.join(extractDir,binaryFileName)])
    located(binaryFileName,extractDir,found)

def installed(+binaryPath: String, +binaryFileName: String, +extractDir: String, found: Maybe<&2,String>) -> IO(Outcome(String)):
  match found:
    case None{}: IO.pure(Outcome(String),Fail{"Binary not found in archive: expected " ++ binaryFileName ++ " under " ++ extractDir})
    case Some{source}:
      then(Unit,String,fsAction(FS.rename(source,binaryPath)),_ =>
        then(Unit,String,fsAction(FS.chmod(binaryPath,493)),_ => IO.pure(Outcome(String),Done{binaryPath})))

def install(+archivePath: String, +extractDir: String, +asset: String, +binaryFileName: String, +binaryPath: String) -> IO(Outcome(String)):
  then(Unit,String,extractTarGzArchive(archivePath,extractDir,asset),_ =>
    then(Maybe<&2,String>,String,locate(binaryFileName,extractDir,asset),found => installed(binaryPath,binaryFileName,extractDir,found)))

# The archive and extraction directory are removed whatever happened.
def extractAndInstall(+archivePath: String, +extractDir: String, +asset: String, +binaryFileName: String, +binaryPath: String) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    made : Outcome(Unit) <- mkdirs(extractDir)
    result : Outcome(String) <- continued(Unit,String,made,_ => install(archivePath,extractDir,asset,binaryFileName,binaryPath))
    archiveRemoved : Result<&2,&2,FS.Error,Unit> <- FS.remove(archivePath,False{},True{})
    directoryRemoved : Result<&2,&2,FS.Error,Unit> <- FS.remove(extractDir,True{},True{})
    return result

def fetched(+manager: ToolsManager, +config: ToolConfig, +tool: Tool, +version: String, +arch: String) -> IO(Outcome(String)):
  match manager config:
    case ToolsManager{binDir,context,Some{fetch}} ToolConfig{_,repo,binaryName,_,tagPrefix}:
      +asset = assetName(tool,version,arch)
      +archivePath = Path.join(binDir,asset)
      then(Unit,String,mkdirs(binDir),_ =>
        then(Unit,String,downloadFile(fetch,context,"https://github.com/" ++ repo ++ "/releases/download/" ++ tagPrefix ++ version ++ "/" ++ asset,archivePath),_ =>
          IO.bind(String,Outcome(String),extractDirName(binaryName),name => extractAndInstall(archivePath,Path.join(binDir,name),asset,binaryName,Path.join(binDir,binaryName)))))
    case _ _: IO.pure(Outcome(String),Fail{"fetch failed: no network transport"})

def latestRelease(+manager: ToolsManager, +config: ToolConfig, +tool: Tool) -> IO(Outcome(String)):
  match manager config:
    case ToolsManager{_,context,Some{fetch}} ToolConfig{_,repo,_,_,_}:
      then(String,String,getLatestVersion(fetch,context,repo),version =>
        IO.bind(String,Outcome(String),machineArch(),arch => fetched(manager,config,tool,version,arch)))
    case _ _: IO.pure(Outcome(String),Fail{"fetch failed: no network transport"})

# The latest release for this architecture, installed into the bin directory.
def downloadTool(manager: ToolsManager, +tool: Tool) -> IO(Outcome(String)): latestRelease(manager,toolConfig(tool),tool)

def downloaded(name: String, onStatus: StatusCallback(), result: Outcome(String)) -> IO(Maybe<&2,String>):
  match result:
    case Done{+path}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Info{},name ++ " installed to " ++ path})
        return Some{path}
    case Fail{message}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Warning{},"Failed to download " ++ name ++ ": " ++ message})
        return None{}

def download(manager: ToolsManager, tool: Tool, +name: String, +onStatus: StatusCallback(), isOffline: Bool) -> IO(Maybe<&2,String>):
  match isOffline:
    case True{}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Warning{},name ++ " not found. Offline mode enabled, skipping download."})
        return None{}
    case False{}:
      do IO<Maybe<&2,String>>:
        report(onStatus,ToolStatus{Info{},name ++ " not found. Downloading..."})
        result : Outcome(String) <- downloadTool(manager,tool)
        downloaded(name,onStatus,result)

def missing(manager: ToolsManager, +tool: Tool, onStatus: StatusCallback(), existing: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match existing:
    case Some{path}: IO.pure(Maybe<&2,String>,Some{path})
    case None{}:
      do IO<Maybe<&2,String>>:
        isOffline : Bool <- isOfflineModeEnabled()
        download(manager,tool,toolName(toolConfig(tool)),onStatus,isOffline)

# The tool's path, downloading it when needed; None when it stays unavailable.
# Progress reaches onStatus, which otherwise stays silent.
def ensureTool(+manager: ToolsManager, +tool: Tool, onStatus: StatusCallback()) -> IO(Maybe<&2,String>):
  match manager:
    case ToolsManager{binDir,_,_}:
      do IO<Maybe<&2,String>>:
        existing : Maybe<&2,String> <- getToolPath(binDir,tool)
        missing(manager,tool,onStatus,existing)
