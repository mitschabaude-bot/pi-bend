import Base
import ../../utils/paths.bend as Paths
import ../../utils/tools-manager.bend as Tools
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/json.bend as Json
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/callback.bend as Callback
import ../extensions/context.bend as Ctx
import ../../../../runtime/src/abort.bend as Abort
import ./truncate.bend as Truncate

type GrepToolInput is Data:
  GrepToolInput{pattern: String,path: Maybe<&2,String>,glob: Maybe<&2,String>,ignoreCase: Maybe<&2,Bool>,literal: Maybe<&2,Bool>,context: Maybe<&2,Nat>,limit: Maybe<&2,Nat>}
type GrepToolDetails is Data:
  GrepToolDetails{truncation: Maybe<&2,Truncate.TruncationResult>,matchLimitReached: Maybe<&2,Nat>,linesTruncated: Maybe<&2,Bool>}
type Error is Data:
  Filesystem{cause: FS.Error}
  InvalidArguments{}
  InvalidPath{cause: Paths.Error}
  PathNotFound{path: String}
  Operation{message: String}
  Aborted{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<GrepToolDetails>)
def DEFAULT_LIMIT() -> Nat: 100n
def promptSnippet() -> String: "Search file contents for patterns (respects .gitignore)"

type GrepOperations is Data:
  GrepOperations{isDirectory: Callback.Callback<String,ResultOf(Bool)>,readFile: Callback.Callback<String,ResultOf(String)>}
type GrepToolOptions is Data:
  GrepToolOptions{operations: Maybe<&2,GrepOperations>}
type GrepContext is Data:
  GrepContext{cwd: Maybe<&2,String>}
type Invocation is Data:
  Invocation{paths: Paths.Environment,tools: Tools.ToolsManager,cwd: String,operations: Maybe<&2,GrepOperations>}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<GrepToolDetails,Error>}

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

# A match event of rg's JSON output. rg reports non-UTF-8 lines as bytes, so
# their text is absent and the line is read from the file instead.
type Match is Data:
  Match{path: String,line: Nat,text: Maybe<&2,String>}

# Output collected while rg runs: the unfinished stdout line (reversed bytes),
# the matches in reverse, the match count, whether the limit stopped rg, and
# stderr (reversed bytes).
type Collected is Data:
  Collected{pending: List<&2,U32>,matches: List<&2,Match>,count: Nat,limitReached: Bool,stderr: List<&2,U32>}

def field(-A: Data,value: Maybe<&2,Value.Value>,decode: Value.Value -> Maybe<&2,A>) -> Maybe<&2,A>:
  match value:
    case None{}: None{}
    case Some{value}: decode(value)
def objectOf(value: Value.Value) -> Maybe<&2,Record.Record<Value.Value>>:
  match value:
    case Value.ObjectValue{properties}: Some{properties}
    case _: None{}
def textOf(value: Value.Value) -> Maybe<&2,String>:
  match value:
    case Value.Text{text}: Some{text}
    case _: None{}
def wholeNumber(value: Result<&2,&2,Number.Error,Nat>) -> Maybe<&2,Nat>:
  match value:
    case Done{number}: Some{number}
    case Fail{_}: None{}
def lineNumber(value: Value.Value) -> Maybe<&2,Nat>:
  match value:
    case Value.Number{number}: wholeNumber(Number.convert(number))
    case _: None{}
def member(value: Maybe<&2,Record.Record<Value.Value>>,key: String) -> Maybe<&2,Value.Value>:
  match value:
    case None{}: None{}
    case Some{record}: Record.get(Value.Value,record,key)
def nested(object: Maybe<&2,Record.Record<Value.Value>>,key: String,+name: String) -> Maybe<&2,String>:
  field(String,member(field(Record.Record<Value.Value>,member(object,key),objectOf),name),textOf)

def matchFrom(path: Maybe<&2,String>,line: Maybe<&2,Nat>,text: Maybe<&2,String>) -> Maybe<&2,Match>:
  match path line:
    case Some{SCon{first,rest}} Some{line}: Some{Match{SCon{first,rest},line,text}}
    case _ _: None{}
def matchOf(+data: Maybe<&2,Record.Record<Value.Value>>) -> Maybe<&2,Match>:
  matchFrom(nested(data,"path","text"),field(Nat,member(data,"line_number"),lineNumber),nested(data,"lines","text"))

def kept(found: Maybe<&2,Match>,matches: List<&2,Match>) -> List<&2,Match>:
  match found:
    case None{}: matches
    case Some{value}: value <> matches
def matched(+limit: Nat,found: Maybe<&2,Match>,collected: Collected) -> Collected:
  match collected:
    case Collected{pending,matches,count,_,stderr}:
      +next = {Succ{count}: Nat}
      Collected{pending,kept(found,matches),next,Nat.is_ge(next,limit),stderr}
def eventOf(+limit: Nat,kind: Maybe<&2,String>,value: Maybe<&2,Record.Record<Value.Value>>,collected: Collected) -> Collected:
  match kind:
    case Some{"match"}: matched(limit,matchOf(field(Record.Record<Value.Value>,member(value,"data"),objectOf)),collected)
    case _: collected
def event(+limit: Nat,+value: Maybe<&2,Record.Record<Value.Value>>,collected: Collected) -> Collected:
  eventOf(limit,field(String,member(value,"type"),textOf),value,collected)

def parsed(+limit: Nat,value: Result<&2,&2,Json.ParseError,Value.Value>,collected: Collected) -> Collected:
  match value:
    case Fail{_}: collected
    case Done{value}: event(limit,objectOf(value),collected)

# Blank lines, lines after the limit and lines that are not JSON are skipped.
def acceptLine(+limit: Nat,+text: String,+collected: Collected) -> Collected:
  match collected:
    case Collected{_,_,count,_,_}: Bool.pick(Unit -> Collected,Nat.is_ge(count,limit) || Text.blank(text),_ => collected,_ => parsed(limit,Json.parse(text),collected))(Unit{})

def withoutFinalCR(reversed: String) -> String:
  match reversed:
    case SCon{'\r',rest}: String.reverse(rest)
    case _: String.reverse(reversed)
def withoutCR(text: String) -> String: withoutFinalCR(String.reverse(text))

def finishLine(+limit: Nat,collected: Collected) -> Collected:
  match collected:
    case Collected{pending,matches,count,reached,stderr}: acceptLine(limit,withoutCR(Utf8.decodeBuffer(List.reverse(&2,U32,pending))),Collected{Nil{},matches,count,reached,stderr})

def feed(+limit: Nat,bytes: List<&2,U32>,collected: Collected) -> Collected:
  match bytes collected:
    case Nil{} collected: collected
    case 10 <> rest collected: feed(limit,rest,finishLine(limit,collected))
    case byte <> rest Collected{pending,matches,count,reached,stderr}: feed(limit,rest,Collected{byte <> pending,matches,count,reached,stderr})

# The flag reports whether this chunk reached the limit.
def newlyReached(before: Bool,collected: Collected) -> Collected & Bool:
  match collected:
    case Collected{pending,matches,count,+after,stderr}: (Collected{pending,matches,count,after,stderr},after && Bool.not(before))
def received(+limit: Nat,bytes: List<&2,U32>,collected: Collected) -> Collected & Bool:
  match collected:
    case Collected{pending,matches,count,+before,stderr}: newlyReached(before,feed(limit,bytes,Collected{pending,matches,count,before,stderr}))

def fsResult(-A: Data,value: Result<&2,&2,FS.Error,A>) -> ResultOf(A):
  match value:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: Done{value}
def foundDirectory(path: String,result: ResultOf(Bool)) -> ResultOf(Bool):
  match result:
    case Fail{_}: Fail{PathNotFound{path}}
    case Done{value}: Done{value}
def isDirectory(operations: Maybe<&2,GrepOperations>,+path: String) -> IO(ResultOf(Bool)):
  match operations:
    case Some{GrepOperations{callback,_}}:
      do IO<ResultOf(Bool)>:
        result : ResultOf(Bool) <- Callback.call(String,ResultOf(Bool),callback,path)
        return foundDirectory(path,result)
    case None{}:
      do IO<ResultOf(Bool)>:
        result : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        return foundDirectory(path,Result.map(&2,&2,Error,FS.FileKind,Bool,FS.isDirectory,fsResult(FS.FileKind,result)))

def nativeText(+path: String) -> IO(ResultOf(String)):
  do IO<ResultOf(String)>:
    value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return Result.map(&2,&2,Error,List<&2,U32>,String,Utf8.decodeBuffer,fsResult(List<&2,U32>,value))
def readText(operations: Maybe<&2,GrepOperations>,path: String) -> IO(ResultOf(String)):
  match operations:
    case Some{GrepOperations{_,callback}}: Callback.call(String,ResultOf(String),callback,path)
    case None{}: nativeText(path)
def normalized(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',SCon{'\n',rest}}: normalized(rest,SCon{'\n',reversed})
    case SCon{'\r',rest}: normalized(rest,SCon{'\n',reversed})
    case SCon{char,rest}: normalized(rest,SCon{char,reversed})
def contextLines(value: ResultOf(String)) -> List<&2,String>:
  match value:
    case Fail{_}: Nil{}
    case Done{text}: Strings.split(normalized(text,""),'\n')

type Output is Data:
  Output{reversed: List<&2,String>,linesTruncated: Bool}
def appendLine(path: String,index: Nat,matched: Bool,line: Truncate.LineResult,output: Output) -> Output:
  match line output:
    case Truncate.LineResult{text,truncated} Output{reversed,wasTruncated}:
      +separator = Bool.pick(String,matched,":","-")
      Output{(path ++ separator ++ Nat.show(index) ++ separator ++ " " ++ text) <> reversed,wasTruncated || truncated}
def block(lines: List<&2,String>,+index: Nat,+start: Nat,+end: Nat,+target: Nat,+path: String,+output: Output) -> Output:
  match lines:
    case Nil{}: output
    case line <> rest:
      Bool.pick(Unit -> Output,Nat.is_gt(index,end),_ => output,
        _ => block(rest,Succ{index},start,end,target,path,Bool.pick(Unit -> Output,Nat.is_ge(index,start),_ => appendLine(path,index,Nat.is_eq(index,target),Truncate.truncateLine(line,None{}),output),_ => output)(Unit{})))(Unit{})
def contextBlock(lines: List<&2,String>,+number: Nat,+context: Nat,path: String,output: Output) -> Output:
  match lines output:
    case Nil{} Output{reversed,truncated}: Output{(path ++ ":" ++ Nat.show(number) ++ ": (unable to read file)") <> reversed,truncated}
    case lines output: block(lines,1n,Nat.max(1n,number - context),number + context,number,path,output)
def displayPath(+path: String,+root: String,directory: Bool) -> String:
  +relative = Path.relative(root,path)
  Bool.pick(String,directory && Bool.not(String.is_empty(relative)) && Bool.not(String.starts_with(relative,"..")),relative,Maybe.default(&2,String,List.head(&2,String,List.reverse(&2,String,Strings.split(path,'/'))),""))

def getLines(cached: Maybe<&2,List<&2,String>>,operations: Maybe<&2,GrepOperations>,path: String) -> IO(List<&2,String>):
  match cached:
    case Some{lines}: IO.pure(List<&2,String>,lines)
    case None{}:
      do IO<List<&2,String>>:
        value : ResultOf(String) <- readText(operations,path)
        return contextLines(value)

# rg's line keeps its terminator; CRs go, and so does the final newline.
def sanitized(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',rest}: sanitized(rest,reversed)
    case SCon{'\n',SNil{}}: String.reverse(reversed)
    case SCon{char,rest}: sanitized(rest,SCon{char,reversed})

def inline(context: Nat,text: Maybe<&2,String>) -> Bool:
  match context text:
    case 0n Some{_}: True{}
    case _ _: False{}

# Without context, rg's own line is shown; otherwise, or when rg reported the
# line as bytes, the file is read once and cached.
@unsafe def formatMatches(matches: List<&2,Match>,+root: String,+directory: Bool,+context: Nat,+operations: Maybe<&2,GrepOperations>,+cache: Record.Record<List<&2,String>>,+output: Output) -> IO(Output):
  match matches:
    case Nil{}: IO.pure(Output,output)
    case Match{+path,+line,+text} <> +rest:
      +display = displayPath(path,root,directory)
      Bool.pick(Unit -> IO(Output),inline(context,text),
        _ => formatMatches(rest,root,directory,context,operations,cache,appendLine(display,line,True{},Truncate.truncateLine(sanitized(Maybe.default(&2,String,text,""),""),None{}),output)),
        _ =>
          do IO<Output>:
            +lines : List<&2,String> <- getLines(Record.get(List<&2,String>,cache,path),operations,path)
            formatMatches(rest,root,directory,context,operations,Record.set(List<&2,String>,cache,path,lines),contextBlock(lines,line,context,display,output)))(Unit{})

def resultText(text: String,details: Maybe<&2,GrepToolDetails>) -> ToolResult():
  Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},details,None{},None{}}}
def rendered(+limit: Nat,+reached: Bool,+linesTruncated: Bool,+value: Truncate.TruncationResult) -> ToolResult():
  match value:
    case Truncate.TruncationResult{content,+cut,_,_,_,_,_,_,_,_,_}:
      +notices = List.append(&2,String,Bool.pick(List<&2,String>,reached,(Nat.show(limit) ++ " matches limit reached. Use limit=" ++ Nat.show(limit * 2n) ++ " for more, or refine pattern") <> Nil{},Nil{}),
        List.append(&2,String,Bool.pick(List<&2,String>,cut,(Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit reached") <> Nil{},Nil{}),
          Bool.pick(List<&2,String>,linesTruncated,"Some lines truncated to 500 chars. Use read tool to see full lines" <> Nil{},Nil{})))
      resultText(content ++ Bool.pick(String,List.is_empty(&2,String,notices),"","\n\n[" ++ String.join(notices,". ") ++ "]"),
        Bool.pick(Maybe<&2,GrepToolDetails>,reached || cut || linesTruncated,
          Some{GrepToolDetails{Bool.pick(Maybe<&2,Truncate.TruncationResult>,cut,Some{value},None{}),Bool.pick(Maybe<&2,Nat>,reached,Some{limit},None{}),Bool.pick(Maybe<&2,Bool>,linesTruncated,Some{True{}},None{})}},None{}))
def renderOutput(limit: Nat,reached: Bool,output: Output) -> ToolResult():
  match output:
    case Output{reversed,truncated}: rendered(limit,reached,truncated,Truncate.truncateHead(String.join(List.reverse(&2,String,reversed),"\n"),Truncate.TruncationOptions{Some{4294967295n},None{}}))
def format(+root: String,+directory: Bool,+context: Nat,+limit: Nat,operations: Maybe<&2,GrepOperations>,collected: Collected) -> IO(ToolResult()):
  match collected:
    case Collected{_,_,0n,_,_}: IO.pure(ToolResult(),resultText("No matches found",None{}))
    case Collected{_,matches,_,reached,_}:
      do IO<ToolResult()>:
        output : Output <- formatMatches(List.reverse(&2,Match,matches),root,directory,context,operations,Record.Record{Nil{}},Output{Nil{},False{}})
        return renderOutput(limit,reached,output)

def globArguments(glob: Maybe<&2,String>) -> List<String>:
  match glob:
    case None{}: []
    case Some{SNil{}}: []
    case Some{value}: ["--glob",value]

def rgArguments(ignoreCase: Bool,literal: Bool,glob: Maybe<&2,String>,+pattern: String,+path: String) -> List<String>:
  List.concat(&1,String,[["--json","--line-number","--color=never","--hidden"],Bool.pick(List<String>,ignoreCase,["--ignore-case"],[]),Bool.pick(List<String>,literal,["--fixed-strings"],[]),globArguments(glob),["--",pattern,path]])

type Scanner is Data:
  Scanner{state: Ref.Ref<Collected>,limit: Nat,stop: Abort.AbortController<Unit>}

def stopAt(reached: Bool,stop: Abort.AbortController<Unit>) -> IO(Unit):
  match reached:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit,stop,None{})
        return Unit{}

# Reaching the limit stops rg, as upstream kills the child.
def onStdout(scanner: Scanner,bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  match scanner:
    case Scanner{state,+limit,stop}:
      do IO<Result<&2,&2,String,Unit>>:
        reached : Bool <- Ref.modify(Collected,Bool,state,collected => received(limit,bytes,collected))
        stopAt(reached,stop)
        return Done{Unit{}}

def appendStderr(bytes: List<&2,U32>,collected: Collected) -> Collected & Unit:
  match collected:
    case Collected{pending,matches,count,reached,stderr}: (Collected{pending,matches,count,reached,List.append(&2,U32,List.reverse(&2,U32,bytes),stderr)},Unit{})

def onStderr(state: Ref.Ref<Collected>,bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    Ref.modify(Collected,Unit,state,collected => appendStderr(bytes,collected))
    return Done{Unit{}}

def signalsWith(signal: Maybe<&2,Abort.AbortSignal<Unit>>,stop: Abort.AbortSignal<Unit>) -> List<&2,Abort.AbortSignal<Unit>>:
  match signal:
    case None{}: [stop]
    case Some{parent}: [parent,stop]

type Run is Data:
  Run{result: Result<&2,&2,Child.ExecutionError,U32>,collected: Collected,watched: Maybe<&2,Abort.AbortSignal<Unit>>}

def unlessAborted(signal: Abort.AbortSignal<Unit>,aborted: Bool) -> Maybe<&2,Abort.AbortSignal<Unit>>:
  match aborted:
    case True{}: None{}
    case False{}: Some{signal}

# Upstream subscribes to the signal once rg has started; an abort that came
# earlier never reaches the listener, so the search runs to completion.
def watchable(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Maybe<&2,Abort.AbortSignal<Unit>>):
  match signal:
    case None{}: IO.pure(Maybe<&2,Abort.AbortSignal<Unit>>,None{})
    case Some{+value}:
      do IO<Maybe<&2,Abort.AbortSignal<Unit>>>:
        aborted : Bool <- Abort.aborted(Unit,value)
        return unlessAborted(value,aborted)

# rg runs in the process's own working directory and environment.
def search(rgPath: String,args: List<String>,+limit: Nat,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Run):
  do IO<Run>:
    +watched : Maybe<&2,Abort.AbortSignal<Unit>> <- watchable(signal)
    +state : Ref.Ref<Collected> <- Ref.new(Collected,Collected{Nil{},Nil{},0n,False{},Nil{}})
    +stop : Abort.AbortController<Unit> <- Abort.new(Unit)
    +stdout : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Scanner,~List<&2,U32>,~Result<&2,&2,String,Unit>,~onStdout,Scanner{state,limit,stop})
    +stderr : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Ref.Ref<Collected>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~onStderr,state)
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    env : List<String> <- IO.environment()
    +result : Result<&2,&2,Child.ExecutionError,U32> <- Child.spawn(rgPath,args,Result.default(&2,&2,FS.Error,String,cwd,"."),env,signalsWith(watched,Abort.signal(Unit,stop)),stdout,stderr)
    Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,stdout)
    Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,stderr)
    collected : Collected <- Ref.dispose(Collected,state)
    Abort.dispose(Unit,stop)
    return Run{result,finishLine(limit,collected),watched}

def spawnFailure(rgPath: String,errors: List<&2,Child.Error>) -> String:
  match errors:
    case Child.Error{"spawn",code,_} <> _: "spawn " ++ rgPath ++ " " ++ FS.errnoName(code)
    case Child.Error{operation,_,message} <> _: operation ++ ": " ++ message
    case Nil{}: "unknown error"

def exitFailure(+code: U32,stderr: List<&2,U32>) -> String:
  +message = Text.trim(Utf8.decodeBuffer(List.reverse(&2,U32,stderr)))
  Bool.pick(String,String.is_empty(message),"ripgrep exited with code " ++ U32.show(code),message)

# After rg exits: an abort wins, then a failure to run it, then an exit status
# other than 0 (matches) or 1 (none) unless the limit stopped it.
def finished(rgPath: String,aborted: Bool,run: Run) -> ResultOf(Collected):
  match aborted run:
    case True{} _: Fail{Aborted{}}
    case _ Run{Fail{Child.ExecutionFailed{errors}},_,_}: Fail{Operation{"Failed to run ripgrep: " ++ spawnFailure(rgPath,errors)}}
    case _ Run{Done{+code},Collected{pending,matches,count,False{},+stderr},_}:
      Bool.pick(ResultOf(Collected),U32.is_le(code,1),Done{Collected{pending,matches,count,False{},stderr}},Fail{Operation{exitFailure(code,stderr)}})
    case _ Run{_,collected,_}: Done{collected}

def ran(+rgPath: String,run: Run) -> IO(ResultOf(Collected)):
  match run:
    case Run{result,collected,+watched}:
      do IO<ResultOf(Collected)>:
        aborted : Bool <- Child.parentAborted(watched)
        return finished(rgPath,aborted,Run{result,collected,watched})

def withRg(rgPath: Maybe<&2,String>) -> ResultOf(String):
  match rgPath:
    case None{}: Fail{Operation{"ripgrep (rg) is not available and could not be downloaded"}}
    case Some{path}: Done{path}
def ensureRg(tools: Tools.ToolsManager) -> IO(ResultOf(String)):
  do IO<ResultOf(String)>:
    rgPath : Maybe<&2,String> <- Tools.ensureTool(tools,Tools.Rg{},None{})
    return withRg(rgPath)

def execute(environment: Invocation,+path: String,pattern: String,glob: Maybe<&2,String>,insensitive: Bool,literal: Bool,+context: Nat,+limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match environment:
    case Invocation{_,tools,_,+operations}:
      then(String,Agent.AgentToolResult<GrepToolDetails>,ensureRg(tools),+rgPath =>
        then(Bool,Agent.AgentToolResult<GrepToolDetails>,isDirectory(operations,path),directory =>
          then(Collected,Agent.AgentToolResult<GrepToolDetails>,IO.bind(Run,ResultOf(Collected),search(rgPath,rgArguments(insensitive,literal,glob,pattern,path),limit,signal),run => ran(rgPath,run)),collected =>
            format(path,directory,context,limit,operations,collected))))

def optionalText(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,String>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Text{text}}: Done{Some{text}}
    case _: Fail{InvalidArguments{}}
def optionalBoolean(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,Bool>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Boolean{boolean}}: Done{Some{boolean}}
    case _: Fail{InvalidArguments{}}
def natural(value: Result<&2,&2,Number.Error,Nat>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case Done{value}: Done{Some{value}}
    case Fail{_}: Fail{InvalidArguments{}}
def optionalNatural(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Number{number}}: natural(Number.convert(number))
    case _: Fail{InvalidArguments{}}
def parameters(pattern: Maybe<&2,Value.Value>,path: ResultOf(Maybe<&2,String>),glob: ResultOf(Maybe<&2,String>),ignoreCase: ResultOf(Maybe<&2,Bool>),literal: ResultOf(Maybe<&2,Bool>),context: ResultOf(Maybe<&2,Nat>),limit: ResultOf(Maybe<&2,Nat>)) -> ResultOf(GrepToolInput):
  match pattern path glob ignoreCase literal context limit:
    case Some{Value.Text{pattern}} Done{path} Done{glob} Done{ignoreCase} Done{literal} Done{context} Done{limit}: Done{GrepToolInput{pattern,path,glob,ignoreCase,literal,context,limit}}
    case _ _ _ _ _ _ _: Fail{InvalidArguments{}}
def parseInput(value: Value.Value) -> ResultOf(GrepToolInput):
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value,fields,"pattern"),optionalText(Record.get(Value.Value,fields,"path")),optionalText(Record.get(Value.Value,fields,"glob")),optionalBoolean(Record.get(Value.Value,fields,"ignoreCase")),optionalBoolean(Record.get(Value.Value,fields,"literal")),optionalNatural(Record.get(Value.Value,fields,"context")),optionalNatural(Record.get(Value.Value,fields,"limit")))
    case _: Fail{InvalidArguments{}}
def resolved(environment: Invocation,input: GrepToolInput,signal: Maybe<&2,Abort.AbortSignal<Unit>>,value: Result<&2,&2,Paths.Error,String>) -> IO(ToolResult()):
  match input value:
    case _ Fail{cause}: IO.pure(ToolResult(),Fail{InvalidPath{cause}})
    case GrepToolInput{pattern,_,glob,insensitive,literal,context,limit} Done{path}: execute(environment,path,pattern,glob,Maybe.default(&2,Bool,insensitive,False{}),Maybe.default(&2,Bool,literal,False{}),Maybe.default(&2,Nat,context,0n),Nat.max(1n,Maybe.default(&2,Nat,limit,DEFAULT_LIMIT())),signal)
def invokeInput(+environment: Invocation,context: GrepContext,signal: Maybe<&2,Abort.AbortSignal<Unit>>,+input: GrepToolInput) -> IO(ToolResult()):
  match environment context input:
    case Invocation{paths,_,cwd,_} GrepContext{override} GrepToolInput{_,path,_,_,_,_,_}:
      resolved(environment,input,signal,Paths.resolveToCwd(paths,Text.orElse(path,"."),Text.orElse(override,cwd)))
def invokeWithContext(environment: Invocation,context: GrepContext,request: Agent.ToolExecutionInput<GrepToolDetails>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,arguments,+signal,_}:
      then(Unit,Agent.AgentToolResult<GrepToolDetails>,check(signal),_ => continued(GrepToolInput,Agent.AgentToolResult<GrepToolDetails>,parseInput(arguments),input => invokeInput(environment,context,signal,input)))
# upstream wrapToolDefinition: the registered tool reads the session's
# context when it runs; without a bound session it keeps its own cwd.
type Registered is Data: Registered{environment: Invocation, source: Ctx.ContextSource()}
def toolContext(context: Maybe<&2,Ctx.ExtensionContext>) -> GrepContext: GrepContext{Ctx.cwdOf(context)}
def invoke(registered: Registered, request: Agent.ToolExecutionInput<GrepToolDetails>) -> IO(ToolResult()):
  match registered:
    case Registered{environment,source}:
      do IO<ToolResult()>:
        context : Maybe<&2,Ctx.ExtensionContext> <- Ctx.current(source)
        invokeWithContext(environment,toolContext(context),request)

def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{cause}: FS.errorMessage(cause)
    case InvalidArguments{}: "Grep tool input is invalid. Expected a pattern, optional path/glob, booleans and natural context/limit."
    case InvalidPath{_}: "Invalid file path"
    case PathNotFound{path}: "Path not found: " ++ path
    case Operation{message}: message
    case Aborted{}: "Operation aborted"

def parameter(kind: String,description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{kind}} <> Record.Property{"description",Value.Text{description}} <> Nil{}}}
def grepSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{"object"}} <> Record.Property{"properties",Value.ObjectValue{Record.Record{
    Record.Property{"pattern",parameter("string","Search pattern (regex or literal string)")} <>
    Record.Property{"path",parameter("string","Directory or file to search (default: current directory)")} <>
    Record.Property{"glob",parameter("string","Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'")} <>
    Record.Property{"ignoreCase",parameter("boolean","Case-insensitive search (default: false)")} <>
    Record.Property{"literal",parameter("boolean","Treat pattern as literal string instead of regex (default: false)")} <>
    Record.Property{"context",parameter("number","Number of lines to show before and after each match (default: 0)")} <>
    Record.Property{"limit",parameter("number","Maximum number of matches to return (default: 100)")} <> Nil{}}}} <>
    Record.Property{"required",Value.ArrayValue{Value.Text{"pattern"} <> Nil{}}} <> Nil{}}}
def createGrepTool(paths: Paths.Environment,tools: Tools.ToolsManager,cwd: String,options: GrepToolOptions,source: Ctx.ContextSource()) -> IO(ToolOwner):
  match options:
    case GrepToolOptions{operations}:
      do IO<ToolOwner>:
        callback : Callback.Callback<Agent.ToolExecutionInput<GrepToolDetails>,ToolResult()> <- Callback.create(~Registered,~Agent.ToolExecutionInput<GrepToolDetails>,~ToolResult(),~invoke,Registered{Invocation{paths,tools,cwd,operations},source})
        return ToolOwner{Agent.AgentTool{"grep","Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",grepSchema(),None{},"grep",None{},callback,None{},None{}}}
def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<GrepToolDetails,Error>:
  match owner:
    case ToolOwner{+tool}: (ToolOwner{tool},tool)
def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_}}: Callback.dispose(Agent.ToolExecutionInput<GrepToolDetails>,ToolResult(),callback)
def dispose(operations: GrepOperations) -> IO(Unit):
  match operations:
    case GrepOperations{directoryCallback,readCallback}:
      do IO<Unit>:
        Callback.dispose(String,ResultOf(Bool),directoryCallback)
        Callback.dispose(String,ResultOf(String),readCallback)
