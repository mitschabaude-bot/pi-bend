import Base
import ../../utils/paths.bend as Paths
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Posix
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/stable-sort.bend as Sort
import ./truncate.bend as Truncate

# Native tool execution. Extension ToolDefinition and terminal rendering remain
# shared public-boundary integration work, as with the other native tools.
type LsToolInput is Data:
  LsToolInput{path: Maybe<&2,String>, limit: Maybe<&2,Nat>}
type LsToolDetails is Data:
  LsToolDetails{truncation: Maybe<&2,Truncate.TruncationResult>, entryLimitReached: Maybe<&2,Nat>}
type LsStat is Data:
  LsStat{isDirectory: Bool}
type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  Aborted{}
  InvalidArguments{}
  InvalidPath{cause: Paths.Error}
  PathNotFound{path: String}
  NotDirectory{path: String}
  CannotReadDirectory{message: String}

def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<Maybe<&2,LsToolDetails>>)
def DEFAULT_LIMIT() -> Nat: 500n

type LsOperations is Data:
  LsOperations{exists: Callback.Callback<String,ResultOf(Bool)>, stat: Callback.Callback<String,ResultOf(LsStat)>, readdir: Callback.Callback<String,ResultOf(List<&2,String>)>}
type LsToolOptions is Data:
  LsToolOptions{operations: Maybe<&2,LsOperations>}
type LsContext is Data:
  LsContext{cwd: Maybe<&2,String>}
type Invocation is Data:
  Invocation{paths: Paths.Environment, cwd: String, operations: LsOperations}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,LsToolDetails>,Error>, ownedOperations: Maybe<&2,LsOperations>}

def filesystemMessage(error: FS.Error) -> String:
  match error:
    case FS.System{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close

def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{cause}: filesystemMessage(cause)
    case Operation{message}: message
    case Aborted{}: "Operation aborted"
    case InvalidArguments{}: "Ls tool input is invalid. Expected an optional path and natural limit."
    case InvalidPath{_}: "Invalid file path"
    case PathNotFound{path}: "Path not found: " ++ path
    case NotDirectory{path}: "Not a directory: " ++ path
    case CannotReadDirectory{message}: "Cannot read directory: " ++ message

def localExists(environment: Unit, path: String) -> IO(ResultOf(Bool)):
  do IO<ResultOf(Bool)>:
    found : Bool <- FS.accessible(path,0)
    return Done{found}

def statResult(result: Result<&2,&2,FS.Error,FS.FileKind>) -> ResultOf(LsStat):
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{FS.Directory{}}: Done{LsStat{True{}}}
    case Done{_}: Done{LsStat{False{}}}

def localStat(environment: Unit, path: String) -> IO(ResultOf(LsStat)):
  do IO<ResultOf(LsStat)>:
    value : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
    return statResult(value)

def entryNames(entries: List<&2,FS.DirectoryEntry>, reversed: List<&2,String>) -> List<&2,String>:
  match entries:
    case Nil{}: List.reverse(&2,String,reversed)
    case FS.DirectoryEntry{name,_} <> rest: entryNames(rest,name <> reversed)

def directoryResult(result: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> ResultOf(List<&2,String>):
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{entries}: Done{entryNames(entries,Nil{})}

def localReaddir(environment: Unit, path: String) -> IO(ResultOf(List<&2,String>)):
  do IO<ResultOf(List<&2,String>)>:
    value : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
    return directoryResult(value)

def defaultLsOperations() -> IO(LsOperations):
  do IO<LsOperations>:
    exists : Callback.Callback<String,ResultOf(Bool)> <- Callback.create(~Unit,~String,~ResultOf(Bool),~localExists,Unit{})
    stat : Callback.Callback<String,ResultOf(LsStat)> <- Callback.create(~Unit,~String,~ResultOf(LsStat),~localStat,Unit{})
    readdir : Callback.Callback<String,ResultOf(List<&2,String>)> <- Callback.create(~Unit,~String,~ResultOf(List<&2,String>),~localReaddir,Unit{})
    return LsOperations{exists,stat,readdir}

def dispose(operations: LsOperations) -> IO(Unit):
  match operations:
    case LsOperations{exists,stat,readdir}:
      do IO<Unit>:
        Callback.dispose(String,ResultOf(Bool),exists)
        Callback.dispose(String,ResultOf(LsStat),stat)
        Callback.dispose(String,ResultOf(List<&2,String>),readdir)

def continued(-A: Data, -B: Data, result: ResultOf(A), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  match result:
    case Fail{error}: IO.pure(ResultOf(B),Fail{error})
    case Done{value}: next(value)

def then(-A: Data, -B: Data, action: IO(ResultOf(A)), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  IO.bind(ResultOf(A),ResultOf(B),action,result => continued(A,B,result,next))

def check(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  match signal:
    case None{}: IO.pure(ResultOf(Unit),Done{Unit{}})
    case Some{signal}:
      do IO<ResultOf(Unit)>:
        aborted : Bool <- Abort.aborted(Unit,signal)
        return Bool.pick(ResultOf(Unit),aborted,Fail{Aborted{}},Done{Unit{}})

# An in-flight filesystem callback is joined before cancellation settles. No
# detached callback can outlive the owner of its injected operations.
def settled(-A: Data, signal: Maybe<&2,Abort.AbortSignal<Unit>>, result: ResultOf(A)) -> IO(ResultOf(A)):
  then(Unit,A,check(signal),_ => IO.pure(ResultOf(A),result))

type Listing is Data:
  Listing{entries: List<&2,String>, reached: Bool}

type Selection is Data:
  Selection{remaining: Nat, reversed: List<&2,String>}

def selected(result: ResultOf(LsStat), name: String, left: Nat, remaining: Nat, reversed: List<&2,String>) -> ResultOf(Selection):
  match result:
    case Fail{Aborted{}}: Fail{Aborted{}}
    case Fail{_}: Done{Selection{remaining,reversed}}
    case Done{LsStat{isDirectory}}: Done{Selection{left,(name ++ Bool.pick(String,isDirectory,"/","")) <> reversed}}

def collect(entries: List<&2,String>, +selection: Selection, +stat: Callback.Callback<String,ResultOf(LsStat)>, +directory: String, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Listing)):
  match entries selection:
    case Nil{} Selection{_,reversed}: IO.pure(ResultOf(Listing),Done{Listing{List.reverse(&2,String,reversed),False{}}})
    case _ Selection{Zero{},reversed}: IO.pure(ResultOf(Listing),Done{Listing{List.reverse(&2,String,reversed),True{}}})
    case +name <> rest Selection{Succ{+left},reversed}:
      then(Unit,Listing,check(signal),_ =>
        do IO<ResultOf(Listing)>:
          result : ResultOf(LsStat) <- Callback.call(String,ResultOf(LsStat),stat,Posix.join(directory,name))
          ready : ResultOf(LsStat) <- settled(LsStat,signal,result)
          continued(Selection,Listing,selected(ready,name,left,Succ{left},reversed),next => collect(rest,next,stat,directory,signal)))

def resultText(text: String, details: Maybe<&2,LsToolDetails>) -> ToolResult():
  Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},details,None{},None{}}}

def truncated(+limit: Nat, +reached: Bool, +value: Truncate.TruncationResult) -> ToolResult():
  match value:
    case Truncate.TruncationResult{content,+cut,_,_,_,_,_,_,_,_,_}:
      entryNotice = Bool.pick(String,reached,Nat.show(limit) ++ " entries limit reached. Use limit=" ++ Nat.show(limit * 2n) ++ " for more","")
      byteNotice = Bool.pick(String,cut,Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit reached","")
      notices = entryNotice ++ Bool.pick(String,reached && cut,". ","") ++ byteNotice
      resultText(content ++ Bool.pick(String,reached || cut,"\n\n[" ++ notices ++ "]",""),Bool.pick(Maybe<&2,LsToolDetails>,reached || cut,Some{LsToolDetails{Bool.pick(Maybe<&2,Truncate.TruncationResult>,cut,Some{value},None{}),Bool.pick(Maybe<&2,Nat>,reached,Some{limit},None{})}},None{}))

def render(limit: Nat, listing: Listing) -> ToolResult():
  match listing:
    case Listing{Nil{},_}: resultText("(empty directory)",None{})
    case Listing{entries,reached}:
      # The byte cap is reached long before this native line-count sentinel.
      truncated(limit,reached,Truncate.truncateHead(String.join(entries,"\n"),Truncate.TruncationOptions{Some{4294967295n},None{}}))

def readResult(value: ResultOf(List<&2,String>)) -> ResultOf(List<&2,String>):
  match value:
    case Done{entries}: Done{entries}
    case Fail{Aborted{}}: Fail{Aborted{}}
    case Fail{error}: Fail{CannotReadDirectory{errorMessage(error)}}

def checkedDirectory(~le: String -> String -> Bool, info: LsStat, stat: Callback.Callback<String,ResultOf(LsStat)>, readdir: Callback.Callback<String,ResultOf(List<&2,String>)>, +path: String, +limit: Nat, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match info:
    case LsStat{False{}}: IO.pure(ToolResult(),Fail{NotDirectory{path}})
    case LsStat{True{}}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,check(signal),_ =>
        do IO<ToolResult()>:
          entries : ResultOf(List<&2,String>) <- Callback.call(String,ResultOf(List<&2,String>),readdir,path)
          then(List<&2,String>,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,settled(List<&2,String>,signal,readResult(entries)),names =>
            then(Listing,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,collect(Sort.sort(~String,~le,names),Selection{limit,Nil{}},stat,path,signal),listing => IO.pure(ToolResult(),render(limit,listing)))))

def listDirectory(~le: String -> String -> Bool, operations: LsOperations, +path: String, +limit: Nat, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match operations:
    case LsOperations{exists,+stat,readdir}:
      then(Bool,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,Callback.call(String,ResultOf(Bool),exists,path),found =>
        then(Unit,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,check(signal),_ =>
          Bool.pick(Unit -> IO(ToolResult()),found,
            _ => then(LsStat,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,Callback.call(String,ResultOf(LsStat),stat,path),info => checkedDirectory(~le,info,stat,readdir,path,limit,signal)),
            _ => IO.pure(ToolResult(),Fail{PathNotFound{path}}))(Unit{})))

def numeric(value: Result<&2,&2,Number.Error,Nat>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case Done{count}: Done{Some{count}}
    case Fail{_}: Fail{InvalidArguments{}}

def countArgument(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Number{number}}: numeric(Number.convert(number))
    case _: Fail{InvalidArguments{}}

def parameters(path: Maybe<&2,Value.Value>, limit: ResultOf(Maybe<&2,Nat>)) -> ResultOf(LsToolInput):
  match path limit:
    case None{} Done{limit}: Done{LsToolInput{None{},limit}}
    case Some{Value.Text{path}} Done{limit}: Done{LsToolInput{Some{path},limit}}
    case _ _: Fail{InvalidArguments{}}

def parseInput(value: Value.Value) -> ResultOf(LsToolInput):
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value,fields,"path"),countArgument(Record.get(Value.Value,fields,"limit")))
    case _: Fail{InvalidArguments{}}

def nonempty(value: Maybe<&2,String>, +fallback: String) -> String:
  match value:
    case None{}: fallback
    case Some{+value}: Bool.pick(String,String.is_empty(value),fallback,value)

def resolved(~le: String -> String -> Bool, operations: LsOperations, limit: Nat, +signal: Maybe<&2,Abort.AbortSignal<Unit>>, path: Result<&2,&2,Paths.Error,String>) -> IO(ToolResult()):
  match path:
    case Fail{cause}: IO.pure(ToolResult(),Fail{InvalidPath{cause}})
    case Done{path}:
      do IO<ToolResult()>:
        value : ToolResult() <- listDirectory(~le,operations,path,limit,signal)
        settled(Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,signal,value)

def invokeInput(~le: String -> String -> Bool, environment: Invocation, context: LsContext, +signal: Maybe<&2,Abort.AbortSignal<Unit>>, input: ResultOf(LsToolInput)) -> IO(ToolResult()):
  match environment context input:
    case _ _ Fail{error}: IO.pure(ToolResult(),Fail{error})
    case Invocation{paths,cwd,operations} LsContext{override} Done{LsToolInput{path,limit}}:
      resolved(~le,operations,Maybe.default(&2,Nat,limit,DEFAULT_LIMIT()),signal,Paths.resolveToCwd(paths,nonempty(path,"."),nonempty(override,cwd)))

def invokeWithContext(~le: String -> String -> Bool, environment: Invocation, context: LsContext, request: Agent.ToolExecutionInput<Maybe<&2,LsToolDetails>>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,arguments,+signal,_}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,LsToolDetails>>,check(signal),_ => invokeInput(~le,environment,context,signal,parseInput(arguments)))

def invoke(~le: String -> String -> Bool, environment: Invocation, request: Agent.ToolExecutionInput<Maybe<&2,LsToolDetails>>) -> IO(ToolResult()):
  invokeWithContext(~le,environment,LsContext{None{}},request)

def parameter(kind: String, description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{kind}} <> Record.Property{"description",Value.Text{description}} <> Nil{}}}

def lsSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{"object"}} <> Record.Property{"properties",Value.ObjectValue{Record.Record{
    Record.Property{"path",parameter("string","Directory to list (default: current directory)")} <>
    Record.Property{"limit",parameter("number","Maximum number of entries to return (default: 500)")} <> Nil{}}}} <> Nil{}}}

def created(~le: String -> String -> Bool, environment: Invocation, owned: Maybe<&2,LsOperations>) -> IO(ToolOwner):
  do IO<ToolOwner>:
    callback : Callback.Callback<Agent.ToolExecutionInput<Maybe<&2,LsToolDetails>>,ToolResult()> <- Callback.create(~Invocation,~Agent.ToolExecutionInput<Maybe<&2,LsToolDetails>>,~ToolResult(),~invoke(~le),environment)
    return ToolOwner{Agent.AgentTool{"ls","List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).",lsSchema(),Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"ls",None{},callback,None{},None{}},owned}

# Comparator injection also makes the ordering contract explicit for consumers.
def createLsToolWithComparator(~le: String -> String -> Bool, paths: Paths.Environment, cwd: String, options: LsToolOptions) -> IO(ToolOwner):
  match options:
    case LsToolOptions{Some{operations}}: created(~le,Invocation{paths,cwd,operations},None{})
    case LsToolOptions{None{}}:
      do IO<ToolOwner>:
        +operations : LsOperations <- defaultLsOperations()
        created(~le,Invocation{paths,cwd,operations},Some{operations})

def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Maybe<&2,LsToolDetails>,Error>:
  match owner:
    case ToolOwner{+tool,operations}: (ToolOwner{tool,operations},tool)

def disposeOwned(owned: Maybe<&2,LsOperations>) -> IO(Unit):
  match owned:
    case None{}: IO.pure(Unit,Unit{})
    case Some{operations}: dispose(operations)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_},operations}:
      do IO<Unit>:
        Callback.dispose(Agent.ToolExecutionInput<Maybe<&2,LsToolDetails>>,ToolResult(),callback)
        disposeOwned(operations)
