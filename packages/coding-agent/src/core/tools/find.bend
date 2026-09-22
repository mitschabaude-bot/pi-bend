import Base
import ../../utils/paths.bend as Paths
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/path-glob.bend as Glob
import ../../../../runtime/src/ignore.bend as Ignore
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/stable-sort.bend as Sort
import ./truncate.bend as Truncate

type FindToolInput is Data:
  FindToolInput{pattern: String, path: Maybe<&2,String>, limit: Maybe<&2,Nat>}
type FindToolDetails is Data:
  FindToolDetails{truncation: Maybe<&2,Truncate.TruncationResult>, resultLimitReached: Maybe<&2,Nat>}
type FindGlobOptions is Data:
  FindGlobOptions{ignore: List<&2,String>, limit: Nat}
type FindGlobInput is Data:
  FindGlobInput{pattern: String, cwd: String, options: FindGlobOptions}
type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  InvalidArguments{}
  InvalidPath{cause: Paths.Error}
  PathNotFound{path: String}
  InvalidPattern{cause: Glob.Error}
  InvalidIgnore{path: String, cause: Ignore.Error}
  InvalidEncoding{path: String}
  InvalidGitConfig{path: String}
  Aborted{}

def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<Maybe<&2,FindToolDetails>>)
def DEFAULT_LIMIT() -> Nat: 1000n

type FindOperations is Data:
  FindOperations{exists: Callback.Callback<String,ResultOf(Bool)>, glob: Callback.Callback<FindGlobInput,ResultOf(List<&2,String>)>}
type FindToolOptions is Data:
  FindToolOptions{operations: Maybe<&2,FindOperations>}
type FindContext is Data:
  FindContext{cwd: Maybe<&2,String>}
type Invocation is Data:
  Invocation{paths: Paths.Environment, cwd: String, operations: Maybe<&2,FindOperations>}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,FindToolDetails>,Error>}

def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{FS.System{code,message}}: "Error " ++ U32.show(code) ++ ": " ++ message
    case Filesystem{FS.InvalidPathEncoding{_}}: "Invalid UTF-8 path"
    case Filesystem{FS.ReadAndClose{_,read,_,close}}: read ++ "; close: " ++ close
    case Filesystem{FS.WriteAndClose{_,write,_,close}}: write ++ "; close: " ++ close
    case Operation{message}: message
    case InvalidArguments{}: "Find tool input is invalid. Expected a pattern, optional path and natural limit."
    case InvalidPath{_}: "Invalid file path"
    case PathNotFound{path}: "Path not found: " ++ path
    case InvalidPattern{_}: "Error parsing glob pattern"
    case InvalidIgnore{path,cause}: path ++ ": " ++ Ignore.errorMessage(cause)
    case InvalidEncoding{path}: path ++ ": invalid UTF-8"
    case InvalidGitConfig{path}: path ++ ": invalid Git configuration"
    case Aborted{}: "Operation aborted"

def continued(-A: Data,-B: Data,result: ResultOf(A),next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  match result:
    case Fail{error}: IO.pure(ResultOf(B),Fail{error})
    case Done{value}: next(value)
def then(-A: Data,-B: Data,action: IO(ResultOf(A)),next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  IO.bind(ResultOf(A),ResultOf(B),action,result => continued(A,B,result,next))
def filesystem(-A: Data,result: Result<&2,&2,FS.Error,A>) -> ResultOf(A):
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: Done{value}
def check(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  match signal:
    case None{}: IO.pure(ResultOf(Unit),Done{Unit{}})
    case Some{signal}:
      do IO<ResultOf(Unit)>:
        aborted : Bool <- Abort.aborted(Unit,signal)
        return Bool.pick(ResultOf(Unit),aborted,Fail{Aborted{}},Done{Unit{}})
def settled(-A: Data,signal: Maybe<&2,Abort.AbortSignal<Unit>>,value: ResultOf(A)) -> IO(ResultOf(A)):
  then(Unit,A,check(signal),_ => IO.pure(ResultOf(A),value))

def common(a: List<&2,String>,b: List<&2,String>) -> List<&2,String> & List<&2,String>:
  match a b:
    case +first <> +restA +second <> +restB:
      Bool.pick(Unit -> List<&2,String> & List<&2,String>,Strings.equal(first,second),_ => common(restA,restB),_ => (first <> restA,second <> restB))(Unit{})
    case a b: (a,b)
def parents(parts: List<&2,String>,tail: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: tail
    case _ <> rest: parents(rest,".." <> tail)
def relativeParts(pair: List<&2,String> & List<&2,String>) -> String:
  match pair:
    case (left,right): String.join(parents(left,right),"/")
def relative(+root: String,+path: String) -> String:
  relativeParts(common(List.reverse(&2,String,Path.components(Strings.split(root,'/'),Nil{},True{})),List.reverse(&2,String,Path.components(Strings.split(path,'/'),Nil{},True{}))))
def relativizeFindResultPath(+resultPath: String,searchPath: String) -> String:
  +value = Bool.pick(Unit -> String,Path.isAbsolute(resultPath),_ => relative(searchPath,resultPath),_ => resultPath)(Unit{})
  value ++ Bool.pick(String,String.ends_with(resultPath,"/") && Bool.not(String.ends_with(value,"/")),"/","")
def dirnameParts(parts: List<&2,String>) -> String:
  match parts:
    case _ <> rest: Path.absolute(List.reverse(&2,String,rest))
    case Nil{}: "/"
def dirname(path: String) -> String:
  dirnameParts(Path.components(Strings.split(path,'/'),Nil{},True{}))
def ancestry(parts: List<&2,String>,+path: String,reversed: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: List.reverse(&2,String,path <> reversed)
    case name <> rest: ancestry(rest,Path.join(path,name),path <> reversed)
def ancestors(path: String) -> List<&2,String>:
  ancestry(List.reverse(&2,String,Path.components(Strings.split(path,'/'),Nil{},True{})),"/",Nil{})
def nonempty(value: Maybe<&2,String>,+fallback: String) -> String:
  match value:
    case None{}: fallback
    case Some{+value}: Bool.pick(String,String.is_empty(value),fallback,value)
def optionalEnvironment(value: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match value:
    case Fail{_}: None{}
    case Done{value}: Some{value}

def textDecoded(path: String,value: Result<&2,&2,Utf8.Error,String>) -> ResultOf(Maybe<&2,String>):
  match value:
    case Fail{_}: Fail{InvalidEncoding{path}}
    case Done{text}: Done{Some{text}}
def decoded(path: String,value: Result<&2,&2,FS.Error,List<&2,U32>>) -> ResultOf(Maybe<&2,String>):
  match value:
    case Fail{FS.System{_,_}}: Done{None{}}
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{bytes}:
      textDecoded(path,Utf8.decodeWith(Utf8.StripLeading{},bytes))
def optionalKind(+path: String,value: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(ResultOf(Maybe<&2,String>)):
  match value:
    case Fail{FS.System{_,_}}: IO.pure(ResultOf(Maybe<&2,String>),Done{None{}})
    case Fail{cause}: IO.pure(ResultOf(Maybe<&2,String>),Fail{Filesystem{cause}})
    case Done{FS.RegularFile{}}:
      do IO<ResultOf(Maybe<&2,String>)>:
        value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        return decoded(path,value)
    case Done{_}: IO.pure(ResultOf(Maybe<&2,String>),Done{None{}})
def optionalFile(+path: String) -> IO(ResultOf(Maybe<&2,String>)):
  do IO<ResultOf(Maybe<&2,String>)>:
    kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
    optionalKind(path,kind)
def localExists(path: String) -> IO(ResultOf(Bool)):
  do IO<ResultOf(Bool)>:
    value : Result<&1,&1,U32 & String,Unit> <- File.access(path,0)
    return Done{Paths.exists(value)}

def compiledIgnore(path: String,value: Result<&2,&2,Ignore.Error,Ignore.Matcher>) -> ResultOf(Ignore.Matcher):
  match value:
    case Fail{cause}: Fail{InvalidIgnore{path,cause}}
    case Done{matcher}: Done{matcher}
def readIgnore(+path: String) -> IO(ResultOf(Ignore.Matcher)):
  then(Maybe<&2,String>,Ignore.Matcher,optionalFile(path),text => IO.pure(ResultOf(Ignore.Matcher),compiledIgnore(path,Ignore.addText(Ignore.new(False{}),Maybe.default(&2,String,text,"")))))

# Ignore sources are ordered by source kind, then nearest containing directory.
# Git-only sources stop at a repository boundary when the search starts in Git.
type Scope is Data:
  Scope{root: String, fd: Ignore.Matcher, ordinary: Ignore.Matcher, git: Ignore.Matcher, exclude: Ignore.Matcher, boundary: Bool}
type Configuration is Data:
  Configuration{requireGit: Bool, globalGit: Ignore.Matcher, globalFd: Ignore.Matcher}

def firstLine(text: String) -> String:
  Maybe.default(&2,String,List.head(&2,String,Strings.split(text,'\n')) ,"")
def linkedGit(root: String,value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{text}:
      +line = Paths.trim(firstLine(text))
      Bool.pick(Unit -> Maybe<&2,String>,String.starts_with(line,"gitdir: "),_ => Path.resolve(root,String.drop(line,8n)),_ => None{})(Unit{})
def commonGit(+gitdir: String,value: Maybe<&2,String>) -> String:
  match value:
    case None{}: gitdir
    case Some{text}: Maybe.default(&2,String,Path.resolve(gitdir,Paths.trim(firstLine(text))),gitdir)
def linkedGitDirectory(value: Maybe<&2,String>) -> IO(ResultOf(Maybe<&2,String>)):
  match value:
    case None{}: IO.pure(ResultOf(Maybe<&2,String>),Done{None{}})
    case Some{+path}: then(Maybe<&2,String>,Maybe<&2,String>,optionalFile(Path.join(path,"commondir")),text => IO.pure(ResultOf(Maybe<&2,String>),Done{Some{commonGit(path,text)}}))
def gitDirectory(+root: String,kind: Result<&2,&2,FS.Error,FS.FileKind>,requireGit: Bool) -> IO(ResultOf(Maybe<&2,String>)):
  match kind requireGit:
    case Done{FS.RegularFile{}} True{}:
      then(Maybe<&2,String>,Maybe<&2,String>,optionalFile(Path.join(root,".git")),text => linkedGitDirectory(linkedGit(root,text)))
    case _ _: IO.pure(ResultOf(Maybe<&2,String>),Done{Some{Path.join(root,".git")}})
def gitExclude(value: Maybe<&2,String>) -> IO(ResultOf(Ignore.Matcher)):
  match value:
    case None{}: IO.pure(ResultOf(Ignore.Matcher),Done{Ignore.new(False{})})
    case Some{path}: readIgnore(Path.join(path,"info/exclude"))
def loadScope(+root: String,+requireGit: Bool) -> IO(ResultOf(Scope)):
  do IO<ResultOf(Scope)>:
    +kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(Path.join(root,".git"))
    then(Ignore.Matcher,Scope,readIgnore(Path.join(root,".fdignore")),fd =>
      then(Ignore.Matcher,Scope,readIgnore(Path.join(root,".ignore")),ordinary =>
        then(Ignore.Matcher,Scope,readIgnore(Path.join(root,".gitignore")),git =>
          then(Maybe<&2,String>,Scope,gitDirectory(root,kind,requireGit),directory =>
            then(Ignore.Matcher,Scope,gitExclude(directory),exclude => IO.pure(ResultOf(Scope),Done{Scope{root,fd,ordinary,git,exclude,requireGit && Result.is_done(&2,&2,FS.Error,FS.FileKind,kind)}}))))))

def source(scope: Scope,priority: U32) -> Ignore.Matcher:
  match scope priority:
    case Scope{_,fd,_,_,_,_} 0: fd
    case Scope{_,_,ordinary,_,_,_} 1: ordinary
    case Scope{_,_,_,git,_,_} 2: git
    case Scope{_,_,_,_,exclude,_} _: exclude
def scopeRoot(scope: Scope) -> String:
  match scope:
    case Scope{root,_,_,_,_,_}: root
def boundary(scope: Scope) -> Bool:
  match scope:
    case Scope{_,_,_,_,_,value}: value
def decision(value: Result<&2,&2,Ignore.Error,Ignore.Decision>) -> Maybe<&2,Bool>:
  match value:
    case Done{Ignore.Decision{True{},_}}: Some{True{}}
    case Done{Ignore.Decision{_,True{}}}: Some{False{}}
    case _: None{}
def matchAt(matcher: Ignore.Matcher,root: String,path: String,directory: Bool) -> Maybe<&2,Bool>:
  match matcher:
    case Ignore.Matcher{_,Nil{}}: None{}
    case matcher: decision(Ignore.testEntry(matcher,relative(root,path),directory))
def scoped(scopes: List<&2,Scope>,+priority: U32,+path: String,+directory: Bool) -> Maybe<&2,Bool>:
  match scopes:
    case Nil{}: None{}
    case +scope <> rest:
      +value = matchAt(source(scope,priority),scopeRoot(scope),path,directory)
      Bool.pick(Unit -> Maybe<&2,Bool>,Maybe.is_none(&2,Bool,value),_ => Bool.pick(Unit -> Maybe<&2,Bool>,U32.is_ge(priority,2) && boundary(scope),_ => None{},_ => scoped(rest,priority,path,directory))(Unit{}),_ => value)(Unit{})
def selectedIgnore(priorities: List<&2,U32>,+scopes: List<&2,Scope>,+path: String,+directory: Bool) -> Maybe<&2,Bool>:
  match priorities:
    case Nil{}: None{}
    case priority <> rest:
      +value = scoped(scopes,priority,path,directory)
      Bool.pick(Unit -> Maybe<&2,Bool>,Maybe.is_none(&2,Bool,value),_ => selectedIgnore(rest,scopes,path,directory),_ => value)(Unit{})
def globalIgnored(config: Configuration,+path: String,+directory: Bool,local: Maybe<&2,Bool>) -> Bool:
  match config local:
    case _ Some{value}: value
    case Configuration{_,git,fd} None{}:
      Maybe.default(&2,Bool,Maybe.or(&2,Bool,matchAt(git,"/",path,directory),matchAt(fd,"/",path,directory)),False{})
def ignored(config: Configuration,scopes: List<&2,Scope>,+path: String,+directory: Bool) -> Bool:
  globalIgnored(config,path,directory,selectedIgnore(0 <> 1 <> 2 <> 3 <> Nil{},scopes,path,directory))

# Global exclude configuration is parsed as configuration, not a regex over
# arbitrary sections. Quoted paths may contain whitespace; malformed values fail.
def configValue(path: String,text: String) -> ResultOf(String):
  match text:
    case SCon{'"',rest}:
      +rest = {rest: String}
      Bool.pick(ResultOf(String),String.ends_with(rest,"\""),Done{String.take(rest,String.length(rest) - 1n)},Fail{InvalidGitConfig{path}})
    case value: Done{value}
def configAssignment(path: String,parts: List<&2,String>) -> ResultOf(Maybe<&2,String>):
  match parts:
    case key <> values:
      Bool.pick(Unit -> ResultOf(Maybe<&2,String>),Strings.equal(String.to_lower(Paths.trim(key)),"excludesfile"),_ => Result.map(&2,&2,Error,String,Maybe<&2,String>,value => Some{value},configValue(path,Paths.trim(String.join(values,"=")))),_ => Done{None{}})(Unit{})
    case Nil{}: Done{None{}}
type ConfigValue is Data:
  ConfigValue{core: Bool, value: Maybe<&2,String>}
def configLine(+path: String,+line: String,+core: Bool,+value: Maybe<&2,String>) -> ResultOf(ConfigValue):
  match line:
    case SCon{'[',_}: Done{ConfigValue{Strings.equal(String.to_lower(line),"[core]"),value}}
    case SCon{'#',_}: Done{ConfigValue{core,value}}
    case SCon{';',_}: Done{ConfigValue{core,value}}
    case _:
      Bool.pick(Unit -> ResultOf(ConfigValue),core,_ => Result.map(&2,&2,Error,Maybe<&2,String>,ConfigValue,found => ConfigValue{core,Maybe.or(&2,String,found,value)},configAssignment(path,Strings.split(line,'='))),_ => Done{ConfigValue{core,value}})(Unit{})
def configLines(lines: List<&2,String>,+path: String,state: ConfigValue) -> ResultOf(Maybe<&2,String>):
  match lines state:
    case Nil{} ConfigValue{_,value}: Done{value}
    case line <> rest ConfigValue{core,value}:
      Result.bind(&2,&2,Error,ConfigValue,Maybe<&2,String>,configLine(path,Paths.trim(line),core,value),next => configLines(rest,path,next))
def configText(path: String,value: Maybe<&2,String>) -> ResultOf(Maybe<&2,String>):
  match value:
    case None{}: Done{None{}}
    case Some{text}: configLines(Strings.split(text,'\n'),path,ConfigValue{False{},None{}})
def configFile(+path: String) -> IO(ResultOf(Maybe<&2,String>)):
  then(Maybe<&2,String>,Maybe<&2,String>,optionalFile(path),text => IO.pure(ResultOf(Maybe<&2,String>),configText(path,text)))
def expandHome(+home: String,path: String) -> String:
  match path:
    case "~": home
    case SCon{'~',SCon{'/',rest}}: Path.join(home,rest)
    case value: value

def loadScopes(paths: List<&2,String>,+requireGit: Bool,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,scopes: List<&2,Scope>) -> IO(ResultOf(List<&2,Scope>)):
  match paths:
    case Nil{}: IO.pure(ResultOf(List<&2,Scope>),Done{scopes})
    case path <> rest:
      then(Unit,List<&2,Scope>,check(signal),_ => then(Scope,List<&2,Scope>,loadScope(path,requireGit),scope => loadScopes(rest,requireGit,signal,scope <> scopes)))
def insideGit(paths: List<&2,String>,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Bool)):
  match paths:
    case Nil{}: IO.pure(ResultOf(Bool),Done{False{}})
    case path <> rest:
      then(Unit,Bool,check(signal),_ => then(Bool,Bool,localExists(Path.join(path,".git")),found => Bool.pick(Unit -> IO(ResultOf(Bool)),found,_ => IO.pure(ResultOf(Bool),Done{True{}}),_ => insideGit(rest,signal))(Unit{})))

type Work is Data:
  Enter{path: String, scopes: List<&2,Scope>}
  Visit{parent: String, entry: FS.DirectoryEntry, scopes: List<&2,Scope>}
type Search is Data:
  Search{work: List<&2,Work>, results: List<&2,String>, count: Nat}
type SearchOptions is Data:
  SearchOptions{pattern: Glob.Pattern, fullPath: Bool, configuration: Configuration, limit: Nat, signal: Maybe<&2,Abort.AbortSignal<Unit>>}

def isDirectory(kind: FS.FileKind) -> Bool:
  match kind:
    case FS.Directory{}: True{}
    case _: False{}
def entryKey(entry: FS.DirectoryEntry) -> String:
  match entry:
    case FS.DirectoryEntry{name,kind}: name ++ Bool.pick(String,isDirectory(kind),"/","")
def scalarOrder(left: String,right: String) -> Bool:
  match left right:
    case SNil{} _: True{}
    case _ SNil{}: False{}
    case SCon{Chr{+a},restA} SCon{Chr{+b},restB}:
      Bool.pick(Unit -> Bool,U32.is_eq(a,b),_ => scalarOrder(restA,restB),_ => U32.is_lt(a,b))(Unit{})
def entryOrder(a: FS.DirectoryEntry,b: FS.DirectoryEntry) -> Bool: scalarOrder(entryKey(a),entryKey(b))
def visits(entries: List<&2,FS.DirectoryEntry>,+path: String,+scopes: List<&2,Scope>,work: List<&2,Work>) -> List<&2,Work>:
  match entries:
    case Nil{}: work
    case entry <> rest: visits(rest,path,scopes,Visit{path,entry,scopes} <> work)
def enterResult(path: String,scopes: List<&2,Scope>,state: Search,value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> ResultOf(Search):
  match state value:
    case Search{work,results,count} Done{entries}: Done{Search{visits(List.reverse(&2,FS.DirectoryEntry,Sort.sort(~FS.DirectoryEntry,~entryOrder,entries)),path,scopes,work),results,count}}
    case state Fail{FS.System{_,_}}: Done{state}
    case _ Fail{cause}: Fail{Filesystem{cause}}
def enter(path: String,+scopes: List<&2,Scope>,state: Search,config: Configuration) -> IO(ResultOf(Search)):
  match config:
    case Configuration{requireGit,_,_}:
      +path = {path: String}
      then(Scope,Search,loadScope(path,requireGit),scope =>
        do IO<ResultOf(Search)>:
          entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
          return enterResult(path,scope <> scopes,state,entries))
def visited(options: SearchOptions,+scopes: List<&2,Scope>,+path: String,name: String,+directory: Bool,state: Search) -> Search:
  match options state:
    case SearchOptions{pattern,full,configuration,_,_} Search{+work,+results,+count}:
      Bool.pick(Unit -> Search,ignored(configuration,scopes,path,directory),_ => Search{work,results,count},_ =>
        +matched = Glob.matches(pattern,Bool.pick(String,full,path,name))
        Search{Bool.pick(List<&2,Work>,directory,Enter{path,scopes} <> work,work),Bool.pick(List<&2,String>,matched,(path ++ Bool.pick(String,directory,"/","")) <> results,results),count + Bool.pick(Nat,matched,1n,0n)})(Unit{})
def searchStep(+options: SearchOptions,work: Work,state: Search) -> IO(ResultOf(Search)):
  match options work:
    case SearchOptions{_,_,configuration,_,_} Enter{path,scopes}: enter(path,scopes,state,configuration)
    case _ Visit{+parent,FS.DirectoryEntry{+name,kind},scopes}: IO.pure(ResultOf(Search),Done{visited(options,scopes,Path.join(parent,name),name,isDirectory(kind),state)})
def limitReached(+limit: Nat,count: Nat) -> Bool:
  Nat.is_gt(limit,0n) && Nat.is_ge(count,limit)
# The filesystem supplies new work; cancellation is checked before each visit.
# Directory symlinks are emitted but never followed, so cycles cannot recurse.
@unsafe def search(+options: SearchOptions,state: Search) -> IO(ResultOf(List<&2,String>)):
  match options state:
    case _ Search{Nil{},results,_}: IO.pure(ResultOf(List<&2,String>),Done{List.reverse(&2,String,results)})
    case SearchOptions{_,_,_,limit,+signal} Search{task <> rest,+results,+count}:
      then(Unit,List<&2,String>,check(signal),_ => Bool.pick(Unit -> IO(ResultOf(List<&2,String>)),limitReached(limit,count),_ => IO.pure(ResultOf(List<&2,String>),Done{List.reverse(&2,String,results)}),_ => then(Search,List<&2,String>,searchStep(options,task,Search{rest,results,count}),next => search(options,next)))(Unit{}))

def hasSlash(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'/',_}: True{}
    case SCon{_,rest}: hasSlash(rest)
def preparedPattern(+pattern: String) -> String:
  Bool.pick(String,String.is_empty(pattern),"**",Bool.pick(String,hasSlash(pattern) && Bool.not(String.starts_with(pattern,"/")) && Bool.not(String.starts_with(pattern,"**/")),"**/" ++ pattern,pattern))
def patternResult(value: Result<&2,&2,Glob.Error,Glob.Pattern>) -> ResultOf(Glob.Pattern):
  match value:
    case Fail{cause}: Fail{InvalidPattern{cause}}
    case Done{pattern}: Done{pattern}
def configured(+path: String,+home: String,+xdg: String,+requireGit: Bool,pattern: Glob.Pattern,fullPath: Bool,limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  then(Maybe<&2,String>,List<&2,String>,configFile(Path.join(home,".gitconfig")),homeConfig =>
    then(Maybe<&2,String>,List<&2,String>,configFile(Path.join(xdg,"git/config")),xdgConfig =>
      then(Ignore.Matcher,List<&2,String>,readIgnore(expandHome(home,nonempty(Maybe.or(&2,String,homeConfig,xdgConfig),Path.join(xdg,"git/ignore")))),globalGit =>
        then(Ignore.Matcher,List<&2,String>,readIgnore(Path.join(xdg,"fd/ignore")),globalFd =>
          then(List<&2,Scope>,List<&2,String>,loadScopes(Bool.pick(List<&2,String>,Strings.equal(path,"/"),Nil{},ancestors(dirname(path))),requireGit,signal,Nil{}),scopes => search(SearchOptions{pattern,fullPath,Configuration{requireGit,globalGit,globalFd},limit,signal},Search{Enter{path,scopes} <> Nil{},Nil{},0n}))))))
def searchDirectory(path: String,value: Result<&2,&2,FS.Error,FS.FileKind>) -> ResultOf(Unit):
  match value:
    case Done{FS.Directory{}}: Done{Unit{}}
    case Done{_}: Fail{Operation{"Search path is not a directory: " ++ path}}
    case Fail{cause}: Fail{Filesystem{cause}}

def nativeSearch(environment: Paths.Environment,+pattern: String,+path: String,limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  match environment:
    case Paths.Environment{_,+home,_}:
      continued(Glob.Pattern,List<&2,String>,patternResult(Glob.compile(preparedPattern(pattern))),compiled =>
        do IO<ResultOf(List<&2,String>)>:
          xdg : Result<&1,&1,U32 & String,String> <- IO.get_env("XDG_CONFIG_HOME")
          kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
          continued(Unit,List<&2,String>,searchDirectory(path,kind),_ => then(Bool,List<&2,String>,insideGit(ancestors(path),signal),requireGit => configured(path,home,nonempty(optionalEnvironment(xdg),Path.join(home,".config")),requireGit,compiled,hasSlash(pattern),limit,signal))))

def relativized(values: List<&2,String>,+root: String,reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case path <> rest: relativized(rest,root,relativizeFindResultPath(path,root) <> reversed)
def resultText(text: String,details: Maybe<&2,FindToolDetails>) -> ToolResult():
  Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},details,None{},None{}}}
def rendered(+limit: Nat,custom: Bool,+reached: Bool,+value: Truncate.TruncationResult) -> ToolResult():
  match value:
    case Truncate.TruncationResult{content,+cut,_,_,_,_,_,_,_,_,_}:
      entryNotice = Bool.pick(String,reached,Nat.show(limit) ++ " results limit reached" ++ Bool.pick(String,custom,"",". Use limit=" ++ Nat.show(limit * 2n) ++ " for more, or refine pattern"),"")
      byteNotice = Bool.pick(String,cut,Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit reached","")
      notices = entryNotice ++ Bool.pick(String,reached && cut,". ","") ++ byteNotice
      resultText(content ++ Bool.pick(String,reached || cut,"\n\n[" ++ notices ++ "]",""),Bool.pick(Maybe<&2,FindToolDetails>,reached || cut,Some{FindToolDetails{Bool.pick(Maybe<&2,Truncate.TruncationResult>,cut,Some{value},None{}),Bool.pick(Maybe<&2,Nat>,reached,Some{limit},None{})}},None{}))
def render(+values: List<&2,String>,root: String,+limit: Nat,custom: Bool) -> ToolResult():
  match values:
    case Nil{}: resultText("No files found matching pattern",None{})
    case values:
      rendered(limit,custom,Nat.is_ge(Sort.length(String,values,0n),limit),Truncate.truncateHead(String.join(relativized(values,root,Nil{}),"\n"),Truncate.TruncationOptions{Some{4294967295n},None{}}))

def customSearch(operations: FindOperations,pattern: String,+path: String,limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  match operations:
    case FindOperations{exists,glob}:
      then(Bool,List<&2,String>,Callback.call(String,ResultOf(Bool),exists,path),found =>
        then(Unit,List<&2,String>,check(signal),_ => Bool.pick(Unit -> IO(ResultOf(List<&2,String>)),found,
          _ => Callback.call(FindGlobInput,ResultOf(List<&2,String>),glob,FindGlobInput{pattern,path,FindGlobOptions{"**/node_modules/**" <> "**/.git/**" <> Nil{},limit}}),
          _ => IO.pure(ResultOf(List<&2,String>),Fail{PathNotFound{path}}))(Unit{})))
def execute(environment: Invocation,pattern: String,+path: String,+limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match environment:
    case Invocation{_,_,Some{operations}}:
      do IO<ToolResult()>:
        values : ResultOf(List<&2,String>) <- customSearch(operations,pattern,path,limit,signal)
        then(List<&2,String>,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,settled(List<&2,String>,signal,values),results => IO.pure(ToolResult(),render(results,path,limit,True{})))
    case Invocation{paths,_,None{}}:
      do IO<ToolResult()>:
        values : ResultOf(List<&2,String>) <- then(Bool,List<&2,String>,localExists(path),found => Bool.pick(Unit -> IO(ResultOf(List<&2,String>)),found,_ => nativeSearch(paths,pattern,path,limit,signal),_ => IO.pure(ResultOf(List<&2,String>),Fail{PathNotFound{path}}))(Unit{}))
        then(List<&2,String>,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,settled(List<&2,String>,signal,values),results => IO.pure(ToolResult(),render(results,path,limit,False{})))

def numeric(value: Result<&2,&2,Number.Error,Nat>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case Done{count}: Done{Some{count}}
    case Fail{_}: Fail{InvalidArguments{}}
def countArgument(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Number{number}}: numeric(Number.convert(number))
    case _: Fail{InvalidArguments{}}
def parameters(pattern: Maybe<&2,Value.Value>,path: Maybe<&2,Value.Value>,limit: ResultOf(Maybe<&2,Nat>)) -> ResultOf(FindToolInput):
  match pattern path limit:
    case Some{Value.Text{pattern}} None{} Done{limit}: Done{FindToolInput{pattern,None{},limit}}
    case Some{Value.Text{pattern}} Some{Value.Text{path}} Done{limit}: Done{FindToolInput{pattern,Some{path},limit}}
    case _ _ _: Fail{InvalidArguments{}}
def parseInput(value: Value.Value) -> ResultOf(FindToolInput):
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value,fields,"pattern"),Record.get(Value.Value,fields,"path"),countArgument(Record.get(Value.Value,fields,"limit")))
    case _: Fail{InvalidArguments{}}
def resolved(environment: Invocation,pattern: String,limit: Nat,signal: Maybe<&2,Abort.AbortSignal<Unit>>,value: Result<&2,&2,Paths.Error,String>) -> IO(ToolResult()):
  match value:
    case Fail{cause}: IO.pure(ToolResult(),Fail{InvalidPath{cause}})
    case Done{path}: execute(environment,pattern,path,limit,signal)
def invokeInput(+environment: Invocation,context: FindContext,signal: Maybe<&2,Abort.AbortSignal<Unit>>,input: FindToolInput) -> IO(ToolResult()):
  match environment context input:
    case Invocation{paths,cwd,_} FindContext{override} FindToolInput{pattern,path,limit}:
      resolved(environment,pattern,Maybe.default(&2,Nat,limit,DEFAULT_LIMIT()),signal,Paths.resolveToCwd(paths,nonempty(path,"."),nonempty(override,cwd)))
def invokeWithContext(environment: Invocation,context: FindContext,request: Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,arguments,+signal,_}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,check(signal),_ => continued(FindToolInput,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,parseInput(arguments),input => invokeInput(environment,context,signal,input)))
def invoke(environment: Invocation,request: Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>) -> IO(ToolResult()):
  invokeWithContext(environment,FindContext{None{}},request)

def parameter(kind: String,description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{kind}} <> Record.Property{"description",Value.Text{description}} <> Nil{}}}
def findSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{"object"}} <> Record.Property{"properties",Value.ObjectValue{Record.Record{
    Record.Property{"pattern",parameter("string","Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'")} <>
    Record.Property{"path",parameter("string","Directory to search in (default: current directory)")} <>
    Record.Property{"limit",parameter("number","Maximum number of results (default: 1000)")} <> Nil{}}}} <>
    Record.Property{"required",Value.ArrayValue{Value.Text{"pattern"} <> Nil{}}} <> Nil{}}}

def createFindTool(paths: Paths.Environment,cwd: String,options: FindToolOptions) -> IO(ToolOwner):
  match options:
    case FindToolOptions{operations}:
      do IO<ToolOwner>:
        callback : Callback.Callback<Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>,ToolResult()> <- Callback.create(~Invocation,~Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>,~ToolResult(),~invoke,Invocation{paths,cwd,operations})
        return ToolOwner{Agent.AgentTool{"find","Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).",findSchema(),Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"find",None{},callback,None{},None{}}}
def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Maybe<&2,FindToolDetails>,Error>:
  match owner:
    case ToolOwner{+tool}: (ToolOwner{tool},tool)
def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_}}: Callback.dispose(Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>,ToolResult(),callback)
def dispose(operations: FindOperations) -> IO(Unit):
  match operations:
    case FindOperations{exists,glob}:
      do IO<Unit>:
        Callback.dispose(String,ResultOf(Bool),exists)
        Callback.dispose(FindGlobInput,ResultOf(List<&2,String>),glob)
