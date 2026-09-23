import Base
import ../../utils/paths.bend as Paths
import ../../../../runtime/src/file-search.bend as Search
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/path-glob.bend as Glob
import ../../../../runtime/src/ignore.bend as Ignore
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
def check(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  match signal:
    case None{}: IO.pure(ResultOf(Unit),Done{Unit{}})
    case Some{signal}:
      do IO<ResultOf(Unit)>:
        aborted : Bool <- Abort.aborted(Unit,signal)
        return Bool.pick(ResultOf(Unit),aborted,Fail{Aborted{}},Done{Unit{}})
def settled(-A: Data,signal: Maybe<&2,Abort.AbortSignal<Unit>>,value: ResultOf(A)) -> IO(ResultOf(A)):
  then(Unit,A,check(signal),_ => IO.pure(ResultOf(A),value))

def localExists(path: String) -> IO(ResultOf(Bool)):
  do IO<ResultOf(Bool)>:
    found : Bool <- FS.accessible(path,0)
    return Done{found}

def relativizeFindResultPath(+resultPath: String,searchPath: String) -> String:
  +value = Bool.pick(Unit -> String,Path.isAbsolute(resultPath),_ => Search.relative(searchPath,resultPath),_ => resultPath)(Unit{})
  value ++ Bool.pick(String,String.ends_with(resultPath,"/") && Bool.not(String.ends_with(value,"/")),"/","")
def searchError(error: Search.Error) -> Error:
  match error:
    case Search.Filesystem{cause}: Filesystem{cause}
    case Search.Operation{message}: Operation{message}
    case Search.InvalidPattern{cause}: InvalidPattern{cause}
    case Search.InvalidIgnore{path,cause}: InvalidIgnore{path,cause}
    case Search.InvalidEncoding{path}: InvalidEncoding{path}
    case Search.InvalidGitConfig{path}: InvalidGitConfig{path}
    case Search.Aborted{}: Aborted{}

def searchResult(value: Search.ResultOf(List<&2,String>)) -> ResultOf(List<&2,String>):
  match value:
    case Fail{error}: Fail{searchError(error)}
    case Done{values}: Done{values}

def nativeSearch(environment: Paths.Environment,pattern: String,path: String,limit: Nat,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  match environment:
    case Paths.Environment{_,home,_}:
      do IO<ResultOf(List<&2,String>)>:
        value : Search.ResultOf(List<&2,String>) <- Search.nativeSearch(home,pattern,path,limit,signal)
        return searchResult(value)

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
      resolved(environment,pattern,Maybe.default(&2,Nat,limit,DEFAULT_LIMIT()),signal,Paths.resolveToCwd(paths,Search.nonempty(path,"."),Search.nonempty(override,cwd)))
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
