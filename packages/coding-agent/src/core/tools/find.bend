import Base
import ../../utils/paths.bend as Paths
import ../../utils/tools-manager.bend as Tools
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
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
  Invocation{paths: Paths.Environment, tools: Tools.ToolsManager, cwd: String, operations: Maybe<&2,FindOperations>}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,FindToolDetails>,Error>}

def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{cause}: FS.errorMessage(cause)
    case Operation{message}: message
    case InvalidArguments{}: "Find tool input is invalid. Expected a pattern, optional path and natural limit."
    case InvalidPath{_}: "Invalid file path"
    case PathNotFound{path}: "Path not found: " ++ path
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

def relativizeFindResultPath(+resultPath: String,searchPath: String) -> String:
  +value = Bool.pick(Unit -> String,Path.isAbsolute(resultPath),_ => Path.relative(searchPath,resultPath),_ => resultPath)(Unit{})
  value ++ Bool.pick(String,String.ends_with(resultPath,"/") && Bool.not(String.ends_with(value,"/")),"/","")

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
def listed(+values: List<&2,String>,root: String,+limit: Nat,custom: Bool) -> ToolResult():
  rendered(limit,custom,Nat.is_ge(List.length(&2,String,values),limit),Truncate.truncateHead(String.join(relativized(values,root,Nil{}),"\n"),Truncate.TruncationOptions{Some{4294967295n},None{}}))
def render(values: List<&2,String>,root: String,limit: Nat) -> ToolResult():
  match values:
    case Nil{}: resultText("No files found matching pattern",None{})
    case values: listed(values,root,limit,True{})

def customSearch(operations: FindOperations,pattern: String,+path: String,limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,String>)):
  match operations:
    case FindOperations{exists,glob}:
      then(Bool,List<&2,String>,Callback.call(String,ResultOf(Bool),exists,path),found =>
        then(Unit,List<&2,String>,check(signal),_ => Bool.pick(Unit -> IO(ResultOf(List<&2,String>)),found,
          _ => Callback.call(FindGlobInput,ResultOf(List<&2,String>),glob,FindGlobInput{pattern,path,FindGlobOptions{"**/node_modules/**" <> "**/.git/**" <> Nil{},limit}}),
          _ => IO.pure(ResultOf(List<&2,String>),Fail{PathNotFound{path}}))(Unit{})))

# fd
# --

# The search path and its ancestors, nearest first.
def ancestors(+parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: ["/"]
    case _ <> +rest: Path.absolute(List.reverse(&2,String,parts)) <> ancestors(rest)

def anyGit(directories: List<&2,String>) -> IO(Bool):
  match directories:
    case Nil{}: IO.pure(Bool,False{})
    case directory <> rest:
      do IO<Bool>:
        found : Bool <- FS.accessible(Path.join(directory,".git"),0)
        Bool.pick(IO(Bool),found,IO.pure(Bool,True{}),anyGit(rest))

# fd honours .gitignore outside a repository only with --no-require-git;
# inside one, its git-aware default stops parent rules at nested repositories.
def insideGitRepo(path: String) -> IO(Bool):
  anyGit(ancestors(Path.components(String.split(path,'/'),Nil{},True{})))

def pathPattern(+pattern: String) -> String:
  Bool.pick(String,String.starts_with(pattern,"/") || String.starts_with(pattern,"**/") || String.eq(pattern,"**"),pattern,"**/" ++ pattern)

# fd --glob matches basenames unless --full-path, which matches the absolute
# path, so a pattern with a directory needs a leading **/.
def fdArguments(insideGit: Bool,+limit: Nat,+pattern: String,+path: String) -> List<String>:
  +full = String.contains(pattern,"/")
  List.concat(&1,String,[["--glob","--color=never","--hidden"],Bool.pick(List<String>,insideGit,[],["--no-require-git"]),["--max-results",Nat.show(limit)],Bool.pick(List<String>,full,["--full-path"],[]),["--",Bool.pick(String,full,pathPattern(pattern),pattern),path]])

# fd runs in the process's own working directory and environment; the abort
# signal stops it.
def runFd(fdPath: String,args: List<String>,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Child.Completed):
  do IO<Child.Completed>:
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    env : List<String> <- IO.environment()
    Child.spawnSync(fdPath,args,Result.default(&2,&2,FS.Error,String,cwd,"."),env,Child.signalList(signal))

# readline's lines: \n, \r\n and a lone \r end a line; a final empty line is
# not one.
def lastLine(current: String,reversed: List<&2,String>) -> List<&2,String>:
  match current:
    case SNil{}: reversed
    case line: String.reverse(line) <> reversed
def splitLines(text: String,current: String,reversed: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,lastLine(current,reversed))
    case SCon{'\r',SCon{'\n',rest}}: splitLines(rest,"",String.reverse(current) <> reversed)
    case SCon{'\r',rest}: splitLines(rest,"",String.reverse(current) <> reversed)
    case SCon{'\n',rest}: splitLines(rest,"",String.reverse(current) <> reversed)
    case SCon{char,rest}: splitLines(rest,SCon{char,current},reversed)

def kept(value: String,rest: List<&2,String>) -> List<&2,String>:
  match value:
    case SNil{}: rest
    case line: line <> rest
def trimmed(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: kept(Text.trim(line),trimmed(rest))

def fdFailure(fdPath: String,errors: List<&2,Child.Error>) -> String:
  match errors:
    case Child.Error{"spawn",code,_} <> _: "spawn " ++ fdPath ++ " " ++ FS.errnoName(code)
    case Child.Error{operation,_,message} <> _: operation ++ ": " ++ message
    case Nil{}: "unknown error"

def exitFailure(+code: U32,stderr: List<&2,U32>) -> String:
  +message = Text.trim(Utf8.decodeBuffer(stderr))
  Bool.pick(String,String.is_empty(message),"fd exited with code " ++ U32.show(code),message)

# A failing exit still lists what fd printed; without output it reports fd's
# stderr.
def fdOutput(output: String,+code: U32,lines: List<&2,String>,stderr: List<&2,U32>,root: String,limit: Nat) -> ToolResult():
  match output:
    case SNil{}: Bool.pick(ToolResult(),U32.is_eq(code,0),resultText("No files found matching pattern",None{}),Fail{Operation{exitFailure(code,stderr)}})
    case _: listed(trimmed(lines),root,limit,False{})
def fdResult(code: U32,+lines: List<&2,String>,stderr: List<&2,U32>,root: String,limit: Nat) -> ToolResult():
  fdOutput(String.join(lines,"\n"),code,lines,stderr,root,limit)

def finished(fdPath: String,aborted: Bool,+root: String,+limit: Nat,run: Child.Completed) -> ToolResult():
  match aborted run:
    case True{} _: Fail{Aborted{}}
    case _ Child.Completed{Fail{Child.ExecutionFailed{errors}},_,_}: Fail{Operation{"Failed to run fd: " ++ fdFailure(fdPath,errors)}}
    case _ Child.Completed{Fail{_},_,_}: Fail{Aborted{}}
    case _ Child.Completed{Done{code},stdout,stderr}: fdResult(code,splitLines(Utf8.decodeBuffer(stdout),"",Nil{}),stderr,root,limit)

def searched(+fdPath: String,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,+root: String,+limit: Nat,run: Child.Completed) -> IO(ToolResult()):
  do IO<ToolResult()>:
    aborted : Bool <- Child.parentAborted(signal)
    return finished(fdPath,aborted,root,limit,run)

def withFd(+pattern: String,+path: String,+limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,+fdPath: String) -> IO(ToolResult()):
  do IO<ToolResult()>:
    insideGit : Bool <- insideGitRepo(path)
    run : Child.Completed <- runFd(fdPath,fdArguments(insideGit,limit,pattern,path),signal)
    searched(fdPath,signal,path,limit,run)

def fdAvailable(fdPath: Maybe<&2,String>) -> ResultOf(String):
  match fdPath:
    case None{}: Fail{Operation{"fd is not available and could not be downloaded"}}
    case Some{path}: Done{path}

def ensureFd(tools: Tools.ToolsManager,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(String)):
  do IO<ResultOf(String)>:
    fdPath : Maybe<&2,String> <- Tools.ensureTool(tools,Tools.Fd{},None{})
    aborted : Bool <- Child.parentAborted(signal)
    return Bool.pick(ResultOf(String),aborted,Fail{Aborted{}},fdAvailable(fdPath))

def execute(environment: Invocation,pattern: String,+path: String,+limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match environment:
    case Invocation{_,_,_,Some{operations}}:
      do IO<ToolResult()>:
        values : ResultOf(List<&2,String>) <- customSearch(operations,pattern,path,limit,signal)
        then(List<&2,String>,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,settled(List<&2,String>,signal,values),results => IO.pure(ToolResult(),render(results,path,limit)))
    case Invocation{_,tools,_,None{}}:
      then(String,Agent.AgentToolResult<Maybe<&2,FindToolDetails>>,ensureFd(tools,signal),fdPath => withFd(pattern,path,limit,signal,fdPath))

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
    case Invocation{paths,_,cwd,_} FindContext{override} FindToolInput{pattern,path,limit}:
      resolved(environment,pattern,Maybe.default(&2,Nat,limit,DEFAULT_LIMIT()),signal,Paths.resolveToCwd(paths,Text.orElse(path,"."),Text.orElse(override,cwd)))
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

def createFindTool(paths: Paths.Environment,tools: Tools.ToolsManager,cwd: String,options: FindToolOptions) -> IO(ToolOwner):
  match options:
    case FindToolOptions{operations}:
      do IO<ToolOwner>:
        callback : Callback.Callback<Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>,ToolResult()> <- Callback.create(~Invocation,~Agent.ToolExecutionInput<Maybe<&2,FindToolDetails>>,~ToolResult(),~invoke,Invocation{paths,tools,cwd,operations})
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
