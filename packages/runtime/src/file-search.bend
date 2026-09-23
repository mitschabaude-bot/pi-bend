import Base
import ./text.bend as Text
import ./filesystem.bend as FS
import ./posix-path.bend as Path
import ./path-glob.bend as Glob
import ./ignore.bend as Ignore
import ./string.bend as Strings
import ./utf8.bend as Utf8
import ./abort.bend as Abort
import ./stable-sort.bend as Sort



# Shared native filesystem traversal and ignore policy.
type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  InvalidPattern{cause: Glob.Error}
  InvalidIgnore{path: String,cause: Ignore.Error}
  InvalidEncoding{path: String}
  InvalidGitConfig{path: String}
  Aborted{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>

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
def relative(+root: String,+path: String) -> String: Path.relative(root,path)
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
    found : Bool <- FS.accessible(path,0)
    return Done{found}

def compiledIgnore(path: String,value: Result<&2,&2,Ignore.Error,Ignore.Matcher>) -> ResultOf(Ignore.Matcher):
  match value:
    case Fail{cause}: Fail{InvalidIgnore{path,cause}}
    case Done{matcher}: Done{matcher}
def readIgnore(+path: String) -> IO(ResultOf(Ignore.Matcher)):
  then(Maybe<&2,String>,Ignore.Matcher,optionalFile(path),text => IO.pure(ResultOf(Ignore.Matcher),compiledIgnore(path,Ignore.addText(Ignore.new(False{}),Maybe.default(&2,String,text,"")))))

# Ignore sources are ordered by source kind, then nearest containing directory.
# Git-only sources stop at a repository boundary when the search starts in Git.
type Scope is Data:
  Scope{root: String, custom: Ignore.Matcher, ordinary: Ignore.Matcher, git: Ignore.Matcher, exclude: Ignore.Matcher, boundary: Bool}
type Override is Data:
  Override{pattern: Glob.Pattern,negative: Bool}
type Mode is Data:
  Find{}
  Completion{}
  Grep{root: String,glob: Maybe<&2,Override>}

type Configuration is Data:
  Configuration{requireGit: Bool, mode: Mode, globalGit: Ignore.Matcher, globalCustom: Ignore.Matcher}

def firstLine(text: String) -> String:
  Maybe.default(&2,String,List.head(&2,String,Strings.split(text,'\n')) ,"")
def linkedGit(root: String,value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{text}:
      +line = Text.trim(firstLine(text))
      Bool.pick(Unit -> Maybe<&2,String>,String.starts_with(line,"gitdir: "),_ => Path.resolve(root,String.drop(line,8n)),_ => None{})(Unit{})
def commonGit(+gitdir: String,value: Maybe<&2,String>) -> String:
  match value:
    case None{}: gitdir
    case Some{text}: Maybe.default(&2,String,Path.resolve(gitdir,Text.trim(firstLine(text))),gitdir)
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
def hasRepository(scopes: List<&2,Scope>) -> Bool:
  match scopes:
    case Nil{}: False{}
    case Scope{_,_,_,_,_,True{}} <> _: True{}
    case _ <> rest: hasRepository(rest)
def isFind(mode: Mode) -> Bool:
  match mode:
    case Find{}: True{}
    case _: False{}
def usesFdIgnores(mode: Mode) -> Bool:
  match mode:
    case Grep{_,_}: False{}
    case _: True{}
def customName(mode: Mode) -> String:
  match mode:
    case Find{}: ".fdignore"
    case Completion{}: ".fdignore"
    case _: ".rgignore"
def conditionalIgnore(enabled: Bool,path: String) -> IO(ResultOf(Ignore.Matcher)):
  match enabled:
    case True{}: readIgnore(path)
    case False{}: IO.pure(ResultOf(Ignore.Matcher),Done{Ignore.new(False{})})
def loadScope(+root: String,+requireGit: Bool,+mode: Mode,ancestors: List<&2,Scope>) -> IO(ResultOf(Scope)):
  do IO<ResultOf(Scope)>:
    +kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(Path.join(root,".git"))
    then(Ignore.Matcher,Scope,readIgnore(Path.join(root,customName(mode))),custom =>
      then(Ignore.Matcher,Scope,readIgnore(Path.join(root,".ignore")),ordinary =>
        then(Ignore.Matcher,Scope,conditionalIgnore(isFind(mode) || hasRepository(ancestors) || Result.is_done(&2,&2,FS.Error,FS.FileKind,kind),Path.join(root,".gitignore")),git =>
          then(Maybe<&2,String>,Scope,gitDirectory(root,kind,requireGit),directory =>
            then(Ignore.Matcher,Scope,gitExclude(directory),exclude => IO.pure(ResultOf(Scope),Done{Scope{root,custom,ordinary,git,exclude,requireGit && Result.is_done(&2,&2,FS.Error,FS.FileKind,kind)}}))))))

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
def globalIgnored(config: Configuration,scopes: List<&2,Scope>,+path: String,+directory: Bool,local: Maybe<&2,Bool>) -> Bool:
  match config local:
    case _ Some{value}: value
    case Configuration{_,mode,git,fd} None{}:
      Maybe.default(&2,Bool,Maybe.or(&2,Bool,Bool.pick(Unit -> Maybe<&2,Bool>,isFind(mode) || hasRepository(scopes),_ => matchAt(git,"/",path,directory),_ => None{})(Unit{}),matchAt(fd,"/",path,directory)),False{})
def ignored(config: Configuration,+scopes: List<&2,Scope>,+path: String,+directory: Bool) -> Bool:
  globalIgnored(config,scopes,path,directory,selectedIgnore(0 <> 1 <> 2 <> 3 <> Nil{},scopes,path,directory))

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
      Bool.pick(Unit -> ResultOf(Maybe<&2,String>),Strings.equal(String.to_lower(Text.trim(key)),"excludesfile"),_ => Result.map(&2,&2,Error,String,Maybe<&2,String>,value => Some{value},configValue(path,Text.trim(String.join(values,"=")))),_ => Done{None{}})(Unit{})
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
      Result.bind(&2,&2,Error,ConfigValue,Maybe<&2,String>,configLine(path,Text.trim(line),core,value),next => configLines(rest,path,next))
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

def loadScopes(paths: List<&2,String>,+requireGit: Bool,+mode: Mode,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,+scopes: List<&2,Scope>) -> IO(ResultOf(List<&2,Scope>)):
  match paths:
    case Nil{}: IO.pure(ResultOf(List<&2,Scope>),Done{scopes})
    case path <> rest:
      then(Unit,List<&2,Scope>,check(signal),_ => then(Scope,List<&2,Scope>,loadScope(path,requireGit,mode,scopes),scope => loadScopes(rest,requireGit,mode,signal,scope <> scopes)))
def insideGit(paths: List<&2,String>,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Bool)):
  match paths:
    case Nil{}: IO.pure(ResultOf(Bool),Done{False{}})
    case path <> rest:
      then(Unit,Bool,check(signal),_ => then(Bool,Bool,localExists(Path.join(path,".git")),found => Bool.pick(Unit -> IO(ResultOf(Bool)),found,_ => IO.pure(ResultOf(Bool),Done{True{}}),_ => insideGit(rest,signal))(Unit{})))

# Symlink identity is tracked only along the current ancestry: aliases remain
# visible, while a link to a containing directory cannot recurse forever.
type WalkPolicy is Data:
  WalkPolicy{followLinks: Bool,maxDepth: Maybe<&2,Nat>,excludeGit: Bool}
def ordinaryWalk() -> WalkPolicy: WalkPolicy{False{},None{},False{}}
type WalkFrame is Data:
  WalkFrame{depth: Nat,ancestors: List<&2,String>}
type Work is Data:
  Enter{path: String, scopes: List<&2,Scope>,frame: WalkFrame}
  Visit{parent: String, entry: FS.DirectoryEntry, scopes: List<&2,Scope>,frame: WalkFrame}
type Cursor is Data:
  Cursor{work: List<&2,Work>,configuration: Configuration,signal: Maybe<&2,Abort.AbortSignal<Unit>>,policy: WalkPolicy}
type Entry is Data:
  Entry{path: String,name: String,kind: FS.FileKind}
type Step is Data:
  End{}
  Yield{entry: Entry,cursor: Cursor}

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
def visits(entries: List<&2,FS.DirectoryEntry>,+path: String,+scopes: List<&2,Scope>,+frame: WalkFrame,work: List<&2,Work>) -> List<&2,Work>:
  match entries:
    case Nil{}: work
    case entry <> rest: visits(rest,path,scopes,frame,Visit{path,entry,scopes,frame} <> work)
def enterResult(path: String,scopes: List<&2,Scope>,frame: WalkFrame,state: Cursor,value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> ResultOf(Cursor):
  match state value:
    case Cursor{work,config,signal,policy} Done{entries}: Done{Cursor{visits(List.reverse(&2,FS.DirectoryEntry,Sort.sort(~FS.DirectoryEntry,~entryOrder,entries)),path,scopes,frame,work),config,signal,policy}}
    case Cursor{_,Configuration{_,Grep{_,_},_,_},_,_} Fail{cause}: Fail{Filesystem{cause}}
    case state Fail{FS.System{_,_}}: Done{state}
    case _ Fail{cause}: Fail{Filesystem{cause}}
def loadDirectory(+path: String,+scopes: List<&2,Scope>,frame: WalkFrame,state: Cursor,config: Configuration) -> IO(ResultOf(Cursor)):
  match config:
    case Configuration{requireGit,mode,_,_}:
      then(Scope,Cursor,loadScope(path,requireGit,mode,scopes),scope =>
        do IO<ResultOf(Cursor)>:
          entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
          return enterResult(path,scope <> scopes,frame,state,entries))
def containsPath(paths: List<&2,String>,+path: String) -> Bool:
  match paths:
    case Nil{}: False{}
    case first <> +rest: Bool.pick(Unit -> Bool,Strings.equal(first,path),_ => True{},_ => containsPath(rest,path))(Unit{})
def resolvedPathDirectory(path: String,scopes: List<&2,Scope>,frame: WalkFrame,+state: Cursor,config: Configuration,value: Result<&2,&2,FS.Error,String>) -> IO(ResultOf(Cursor)):
  match frame value:
    case _ Fail{FS.System{_,_}}: IO.pure(ResultOf(Cursor),Done{state})
    case _ Fail{cause}: IO.pure(ResultOf(Cursor),Fail{Filesystem{cause}})
    case WalkFrame{depth,ancestorPaths} Done{directoryPath}:
      +ancestorPaths = {ancestorPaths: List<&2,String>}
      +directoryPath = {directoryPath: String}
      Bool.pick(Unit -> IO(ResultOf(Cursor)),containsPath(ancestorPaths,directoryPath),_ => IO.pure(ResultOf(Cursor),Done{state}),_ => loadDirectory(path,scopes,WalkFrame{depth,directoryPath <> ancestorPaths},state,config))(Unit{})
def atDepthLimit(depth: Nat,maximum: Maybe<&2,Nat>) -> Bool:
  match maximum:
    case None{}: False{}
    case Some{maximum}: Nat.is_ge(depth,maximum)
def enter(+path: String,+scopes: List<&2,Scope>,+frame: WalkFrame,+state: Cursor,+config: Configuration,policy: WalkPolicy) -> IO(ResultOf(Cursor)):
  match frame policy:
    case WalkFrame{depth,_} WalkPolicy{follow,maximum,_}:
      Bool.pick(Unit -> IO(ResultOf(Cursor)),atDepthLimit(depth,maximum),_ => IO.pure(ResultOf(Cursor),Done{state}),
        _ => Bool.pick(Unit -> IO(ResultOf(Cursor)),follow,
          _ => do IO<ResultOf(Cursor)>:
            resolvedPath : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
            resolvedPathDirectory(path,scopes,frame,state,config,resolvedPath),
          _ => loadDirectory(path,scopes,frame,state,config))(Unit{}))(Unit{})
def followedKind(path: String,+kind: FS.FileKind,policy: WalkPolicy) -> IO(Result<&2,&2,FS.Error,FS.FileKind>):
  match kind policy:
    case FS.SymbolicLink{} WalkPolicy{True{},_,_}: FS.fileKind(path)
    case _ _: IO.pure(Result<&2,&2,FS.Error,FS.FileKind>,Done{kind})
def omittedGit(name: String,policy: WalkPolicy) -> Bool:
  match policy:
    case WalkPolicy{_,_,exclude}: exclude && Strings.equal(name,".git")

def overrideDecision(mode: Mode,+path: String,+directory: Bool) -> Maybe<&2,Bool>:
  match mode:
    case Grep{root,Some{Override{+pattern,+negative}}}:
      +relativePath = relative(root,path)
      +matched = Glob.matches(pattern,relativePath) || (directory && Glob.matches(pattern,relativePath ++ "/"))
      Bool.pick(Maybe<&2,Bool>,matched,Some{negative},Bool.pick(Maybe<&2,Bool>,Bool.not(negative) && Bool.not(directory),Some{True{}},None{}))
    case _: None{}
def excluded(+config: Configuration,+scopes: List<&2,Scope>,+path: String,+directory: Bool) -> Bool:
  match config:
    case Configuration{_,mode,_,_}: Maybe.default(&2,Bool,overrideDecision(mode,path,directory),ignored(config,scopes,path,directory))

def visitResolved(resume: Cursor -> IO(ResultOf(Step)),+path: String,name: String,+scopes: List<&2,Scope>,frame: WalkFrame,+state: Cursor,value: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(ResultOf(Step)):
  match state value:
    case _ Fail{FS.System{_,_}}: resume(state)
    case _ Fail{cause}: IO.pure(ResultOf(Step),Fail{Filesystem{cause}})
    case Cursor{+rest,+config,signal,policy} Done{+kind}:
      +directory = isDirectory(kind)
      Bool.pick(Unit -> IO(ResultOf(Step)),excluded(config,scopes,path,directory),_ => resume(state),
        _ => IO.pure(ResultOf(Step),Done{Yield{Entry{path,name,kind},Cursor{Bool.pick(List<&2,Work>,directory,Enter{path,scopes,frame} <> rest,rest),config,signal,policy}}}))(Unit{})

# The cursor owns immutable work snapshots, never open directory handles.
# Find/Grep use ordinaryWalk; followed links and depth limits are explicit.
@unsafe def next(cursor: Cursor) -> IO(ResultOf(Step)):
  match cursor:
    case Cursor{Nil{},_,_,_}: IO.pure(ResultOf(Step),Done{End{}})
    case Cursor{Enter{path,scopes,frame} <> rest,+config,+signal,+policy}:
      then(Unit,Step,check(signal),_ => then(Cursor,Step,enter(path,scopes,frame,Cursor{rest,config,signal,policy},config,policy),cursor => next(cursor)))
    case Cursor{Visit{parent,FS.DirectoryEntry{+name,kind},+scopes,WalkFrame{depth,ancestorPaths}} <> +rest,+config,+signal,+policy}:
      +path = Path.join(parent,name)
      then(Unit,Step,check(signal),_ => Bool.pick(Unit -> IO(ResultOf(Step)),omittedGit(name,policy),
        _ => next(Cursor{rest,config,signal,policy}),
        _ => do IO<ResultOf(Step)>:
          value : Result<&2,&2,FS.Error,FS.FileKind> <- followedKind(path,kind,policy)
          visitResolved(cursor => next(cursor),path,name,scopes,WalkFrame{depth + 1n,ancestorPaths},Cursor{rest,config,signal,policy},value))(Unit{}))

def limitReached(+limit: Nat,count: Nat) -> Bool:
  Nat.is_gt(limit,0n) && Nat.is_ge(count,limit)

# Find limits count selected entries; grep can consume the same cursor while
# limiting matching lines instead, without materializing the whole directory.
@unsafe def findEntries(step: Step,+pattern: Glob.Pattern,+fullPath: Bool,+limit: Nat,+count: Nat,+reversed: List<&2,String>) -> IO(ResultOf(List<&2,String>)):
  match step:
    case End{}: IO.pure(ResultOf(List<&2,String>),Done{List.reverse(&2,String,reversed)})
    case Yield{Entry{+path,name,kind},cursor}:
      +matched = Glob.matches(pattern,Bool.pick(String,fullPath,path,name))
      +results = Bool.pick(List<&2,String>,matched,(path ++ Bool.pick(String,isDirectory(kind),"/","")) <> reversed,reversed)
      +count = count + Bool.pick(Nat,matched,1n,0n)
      Bool.pick(Unit -> IO(ResultOf(List<&2,String>)),limitReached(limit,count),_ => IO.pure(ResultOf(List<&2,String>),Done{List.reverse(&2,String,results)}),_ => then(Step,List<&2,String>,next(cursor),step => findEntries(step,pattern,fullPath,limit,count,results)))(Unit{})

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
def create(+path: String,+home: String,+xdg: String,+requireGit: Bool,+mode: Mode,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Cursor)):
  then(Maybe<&2,String>,Cursor,configFile(Path.join(home,".gitconfig")),homeConfig =>
    then(Maybe<&2,String>,Cursor,configFile(Path.join(xdg,"git/config")),xdgConfig =>
      then(Ignore.Matcher,Cursor,readIgnore(expandHome(home,nonempty(Maybe.or(&2,String,homeConfig,xdgConfig),Path.join(xdg,"git/ignore")))),globalGit =>
        then(Ignore.Matcher,Cursor,conditionalIgnore(usesFdIgnores(mode),Path.join(xdg,"fd/ignore")),globalFd =>
          then(List<&2,Scope>,Cursor,loadScopes(Bool.pick(List<&2,String>,Strings.equal(path,"/"),Nil{},ancestors(dirname(path))),requireGit,mode,signal,Nil{}),scopes => IO.pure(ResultOf(Cursor),Done{Cursor{Enter{path,scopes,WalkFrame{0n,Nil{}}} <> Nil{},Configuration{requireGit,mode,globalGit,globalFd},signal,ordinaryWalk()}}))))))
def searchDirectory(path: String,value: Result<&2,&2,FS.Error,FS.FileKind>) -> ResultOf(Unit):
  match value:
    case Done{FS.Directory{}}: Done{Unit{}}
    case Done{_}: Fail{Operation{"Search path is not a directory: " ++ path}}
    case Fail{cause}: Fail{Filesystem{cause}}

def nativeSearch(+home: String,+pattern: String,+path: String,limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  continued(Glob.Pattern,List<&2,String>,patternResult(Glob.compile(preparedPattern(pattern))),compiled =>
    do IO<ResultOf(List<&2,String>)>:
      xdg : Result<&1,&1,U32 & String,String> <- IO.get_env("XDG_CONFIG_HOME")
      kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
      continued(Unit,List<&2,String>,searchDirectory(path,kind),_ => then(Bool,List<&2,String>,insideGit(ancestors(path),signal),requireGit => then(Cursor,List<&2,String>,create(path,home,nonempty(optionalEnvironment(xdg),Path.join(home,".config")),requireGit,Find{},signal),cursor => then(Step,List<&2,String>,next(cursor),step => findEntries(step,compiled,hasSlash(pattern),limit,0n,Nil{}))))))

def overrideCompiled(negative: Bool,result: Result<&2,&2,Glob.Error,Glob.Pattern>) -> ResultOf(Maybe<&2,Override>):
  match result:
    case Fail{cause}: Fail{InvalidPattern{cause}}
    case Done{Glob.Pattern{tokens,_}}: Done{Some{Override{Glob.Pattern{tokens,False{}},negative}}}
def overrideText(+text: String,negative: Bool) -> ResultOf(Maybe<&2,Override>):
  +pattern = Bool.pick(String,String.starts_with(text,"/"),String.drop(text,1n),Bool.pick(String,hasSlash(text),text,"**/" ++ text))
  overrideCompiled(negative,Glob.compile(pattern))
def compileOverride(value: Maybe<&2,String>) -> ResultOf(Maybe<&2,Override>):
  match value:
    case None{}: Done{None{}}
    case Some{SNil{}}: Done{None{}}
    case Some{SCon{'!',rest}}: overrideText(rest,True{})
    case Some{text}: overrideText(text,False{})

def withPolicy(cursor: Cursor,policy: WalkPolicy) -> Cursor:
  match cursor:
    case Cursor{work,configuration,signal,_}: Cursor{work,configuration,signal,policy}
