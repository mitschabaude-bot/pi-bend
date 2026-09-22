import Base
import ../../utils/paths.bend as Paths
import ../../../../runtime/src/file-search.bend as Search
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/regex.bend as Regex
import ../../../../runtime/src/ignore.bend as Ignore
import ../../../../runtime/src/regex-bytes.bend as Bytes
import ../../../../runtime/src/text-decoder.bend as Text
import ../../../../runtime/src/file-fold.bend as FileFold
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
import ./truncate.bend as Truncate

type GrepToolInput is Data:
  GrepToolInput{pattern: String,path: Maybe<&2,String>,glob: Maybe<&2,String>,ignoreCase: Maybe<&2,Bool>,literal: Maybe<&2,Bool>,context: Maybe<&2,Nat>,limit: Maybe<&2,Nat>}
type GrepToolDetails is Data:
  GrepToolDetails{truncation: Maybe<&2,Truncate.TruncationResult>,matchLimitReached: Maybe<&2,Nat>,linesTruncated: Maybe<&2,Bool>}
type Error is Data:
  Filesystem{cause: FS.Error}
  SearchFailure{cause: Search.Error}
  FileFailure{cause: FileFold.Error}
  InvalidEncoding{path: String,cause: Text.Error}
  InvalidPattern{cause: Regex.Error}
  InvalidArguments{}
  InvalidPath{cause: Paths.Error}
  PathNotFound{path: String}
  UnsupportedConfiguration{path: String}
  Operation{message: String}
  Aborted{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>)
def DEFAULT_LIMIT() -> Nat: 100n
def promptSnippet() -> String: "Search file contents for patterns (respects .gitignore)"

type GrepOperations is Data:
  GrepOperations{isDirectory: Callback.Callback<String,ResultOf(Bool)>,readFile: Callback.Callback<String,ResultOf(String)>}
# A caller must choose explicitly; CLI default awaits the user's binary policy.
type BinaryPolicy is Data:
  MatchText{}
  SkipBinary{}
type GrepToolOptions is Data:
  GrepToolOptions{operations: Maybe<&2,GrepOperations>,binaryPolicy: BinaryPolicy}
type GrepContext is Data:
  GrepContext{cwd: Maybe<&2,String>}
type Invocation is Data:
  Invocation{paths: Paths.Environment,cwd: String,operations: Maybe<&2,GrepOperations>,binaryPolicy: BinaryPolicy}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,GrepToolDetails>,Error>}

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

type Match is Data:
  Match{path: String,line: Nat,text: String}
type Matches is Data:
  Matches{reversed: List<&2,Match>,count: Nat}

type Scan is Type:
  Scanning{regex: Bytes.Regex,decoder: Text.Decoder,cursor: Bytes.Cursor,line: Nat,prefix: String,prefixCount: Nat,hasData: Bool,matches: Matches}
  Validating{decoder: Text.Decoder,matches: Matches}
  Scanned{matches: Matches}
  Skipped{}
  ScanFailed{error: Error}

def limitReached(policy: BinaryPolicy,decoder: Text.Decoder,matches: Matches) -> Scan:
  match policy:
    case MatchText{}: Scanned{matches}
    case SkipBinary{}: Validating{decoder,matches}

def finishLine(+path: String,+limit: Nat,policy: BinaryPolicy,+regex: Bytes.Regex,+decoder: Text.Decoder,cursor: Bytes.Cursor,+line: Nat,prefix: String,matches: Matches) -> Scan:
  match matches:
    case Matches{+reversed,+count}:
      +matched = {Bytes.finish(cursor): Bool}
      +matches = {Matches{Bool.pick(List<&2,Match>,matched,Match{path,line,String.reverse(prefix)} <> reversed,reversed),count + Bool.pick(Nat,matched,1n,0n)}: Matches}
      Bool.pick(Unit -> Scan,matched && Nat.is_ge(Succ{count},limit),_ => limitReached(policy,decoder,matches),_ => Scanning{regex,decoder,Bytes.create(regex),Succ{line},"",0n,False{},matches})(Unit{})

def decoded(path: String,limit: Nat,policy: BinaryPolicy,regex: Bytes.Regex,cursor: Bytes.Cursor,line: Nat,prefix: String,prefixCount: Nat,hasData: Bool,matches: Matches,result: Result<&2,&2,Text.Error,Text.Step>) -> Scan:
  match policy result:
    case _ Fail{cause}: ScanFailed{InvalidEncoding{path,cause}}
    case _ Done{Text.Step{decoder,None{}}}: Scanning{regex,decoder,cursor,line,prefix,prefixCount,hasData,matches}
    case SkipBinary{} Done{Text.Step{_,Some{Chr{0}}}}: Skipped{}
    case policy Done{Text.Step{decoder,Some{'\n'}}}: finishLine(path,limit,policy,regex,decoder,cursor,line,prefix,matches)
    case _ Done{Text.Step{decoder,Some{char}}}:
      +char = {char: Char}
      +prefix = {prefix: String}
      +prefixCount = {prefixCount: Nat}
      Scanning{regex,decoder,Bytes.feedScalar(char,cursor),line,
        Bool.pick(String,Char.is_eq(char,'\r') || Nat.is_ge(prefixCount,501n),prefix,SCon{char,prefix}),
        prefixCount + Bool.pick(Nat,Char.is_eq(char,'\r') || Nat.is_ge(prefixCount,501n),0n,1n),True{},matches}

# Once the requested matches are collected, SkipBinary still validates the
# remaining file without running the matcher or retaining more text.
def validated(matches: Matches,result: Result<&2,&2,Text.Error,Text.Step>,path: String) -> Scan:
  match result:
    case Fail{cause}: ScanFailed{InvalidEncoding{path,cause}}
    case Done{Text.Step{_,Some{Chr{0}}}}: Skipped{}
    case Done{Text.Step{decoder,_}}: Validating{decoder,matches}

def scanBytes(bytes: List<&2,U32>,+path: String,+limit: Nat,+policy: BinaryPolicy,state: Scan) -> FileFold.Control<Scan>:
  match bytes state:
    case _ Scanned{matches}: FileFold.Stop{Scanned{matches}}
    case _ Skipped{}: FileFold.Stop{Skipped{}}
    case _ ScanFailed{error}: FileFold.Stop{ScanFailed{error}}
    case Nil{} state: FileFold.Continue{state}
    case byte <> rest Validating{decoder,matches}: scanBytes(rest,path,limit,policy,validated(matches,Text.step(decoder,byte),path))
    case byte <> rest Scanning{regex,decoder,cursor,line,prefix,prefixCount,hasData,matches}:
      scanBytes(rest,path,limit,policy,decoded(path,limit,policy,regex,cursor,line,prefix,prefixCount,hasData,matches,Text.step(decoder,byte)))

def endChecked(path: String,limit: Nat,policy: BinaryPolicy,result: Result<&2,&2,Text.Error,Unit>,state: Scan) -> Scan:
  match result state:
    case Fail{cause} _: ScanFailed{InvalidEncoding{path,cause}}
    case Done{_} Scanning{regex,decoder,cursor,line,prefix,_,True{},matches}: finishLine(path,limit,policy,regex,decoder,cursor,line,prefix,matches)
    case Done{_} Scanning{_,_,_,_,_,_,False{},matches}: Scanned{matches}
    case _ state: state

def fileEnded(path: String,limit: Nat,policy: BinaryPolicy,state: Scan) -> Scan:
  match state:
    case Validating{+decoder,matches}: endChecked(path,limit,policy,Text.finish(decoder),Scanned{matches})
    case Scanning{regex,+decoder,cursor,line,prefix,count,hasData,matches}: endChecked(path,limit,policy,Text.finish(decoder),Scanning{regex,decoder,cursor,line,prefix,count,hasData,matches})
    case state: state

def scanResult(state: Scan) -> ResultOf(Matches):
  match state:
    case ScanFailed{error}: Fail{error}
    case Skipped{}: Done{Matches{Nil{},0n}}
    case Scanned{matches}: Done{matches}
    case Validating{_,matches}: Done{matches}
    case Scanning{_,_,_,_,_,_,_,matches}: Done{matches}
def fileResult(path: String,limit: Nat,policy: BinaryPolicy,outcome: FileFold.Outcome<Scan>) -> ResultOf(Matches):
  match outcome:
    case FileFold.Outcome{ScanFailed{Aborted{}},_}: Fail{Aborted{}}
    case FileFold.Outcome{_,Fail{cause}}: Fail{FileFailure{cause}}
    case FileFold.Outcome{state,Done{_}}: scanResult(fileEnded(path,limit,policy,state))

def received(path: String,limit: Nat,policy: BinaryPolicy,state: Scan,pair: File & Result<&1,&1,U32 & String,List<&2,U32>>) -> FileFold.Progress<Scan>:
  match pair:
    case Tuple{file,Fail{(code,message)}}: FileFold.Finished{file,state,Fail{FileFold.Read{code,message}}}
    case Tuple{file,Done{Nil{}}}: FileFold.Finished{file,state,Done{FileFold.EndOfFile{}}}
    case Tuple{file,Done{bytes}}: FileFold.consumed(Scan,file,scanBytes(bytes,path,limit,policy,state))
def aborted(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool,False{})
    case Some{signal}: Abort.aborted(Unit,signal)
def readUnless(stopped: Bool,file: File,state: Scan,path: String,limit: Nat,policy: BinaryPolicy) -> IO(FileFold.Progress<Scan>):
  match stopped:
    case True{}: IO.pure(FileFold.Progress<Scan>,FileFold.Finished{file,ScanFailed{Aborted{}},Done{FileFold.Stopped{}}})
    case False{}:
      do IO<FileFold.Progress<Scan>>:
        pair : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,65536)
        return received(path,limit,policy,state,pair)

@unsafe def drive(progress: FileFold.Progress<Scan>,+path: String,+limit: Nat,+policy: BinaryPolicy,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(FileFold.Outcome<Scan>):
  match progress:
    case FileFold.Finished{file,state,result}: FileFold.completed(Scan,state,result,file)
    case FileFold.ReadMore{file,state}:
      do IO<FileFold.Outcome<Scan>>:
        # File reads can complete synchronously; yield so cancellation can run.
        IO.sleep(0)
        stopped : Bool <- aborted(signal)
        next : FileFold.Progress<Scan> <- readUnless(stopped,file,state,path,limit,policy)
        drive(next,path,limit,policy,signal)

def opened(path: String,regex: Bytes.Regex,limit: Nat,policy: BinaryPolicy,signal: Maybe<&2,Abort.AbortSignal<Unit>>,result: Result<&1,&1,U32 & String,File>) -> IO(FileFold.Outcome<Scan>):
  match result:
    case Fail{(code,message)}: IO.pure(FileFold.Outcome<Scan>,FileFold.Outcome{Skipped{},Fail{FileFold.Open{code,message}}})
    case Done{file}:
      +regex = {regex: Bytes.Regex}
      drive(FileFold.ReadMore{file,Scanning{regex,Text.create(),Bytes.create(regex),1n,"",0n,False{},Matches{Nil{},0n}}},path,limit,policy,signal)
def scanFile(+path: String,regex: Bytes.Regex,+limit: Nat,+policy: BinaryPolicy,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Matches)):
  do IO<ResultOf(Matches)>:
    result : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    outcome : FileFold.Outcome<Scan> <- opened(path,regex,limit,policy,signal,result)
    return fileResult(path,limit,policy,outcome)

def searchResult(-A: Data,result: Search.ResultOf(A)) -> ResultOf(A):
  match result:
    case Fail{Search.Aborted{}}: Fail{Aborted{}}
    case Fail{cause}: Fail{SearchFailure{cause}}
    case Done{value}: Done{value}
def next(cursor: Search.Cursor) -> IO(ResultOf(Search.Step)):
  do IO<ResultOf(Search.Step)>:
    result : Search.ResultOf(Search.Step) <- Search.next(cursor)
    return searchResult(Search.Step,result)
def merge(previous: Matches,current: Matches) -> Matches:
  match previous current:
    case Matches{older,n} Matches{newer,m}: Matches{List.append(&2,Match,newer,older),n + m}

type Walk is Data:
  Advance{cursor: Search.Cursor}
  Visit{entry: Search.Entry,cursor: Search.Cursor}
  End{}
def searchStep(step: Search.Step) -> Walk:
  match step:
    case Search.End{}: End{}
    case Search.Yield{entry,cursor}: Visit{entry,cursor}

# Regular entries are read; symlinks and special files are not followed during
# traversal. An explicitly supplied file path is classified with following stat.
@unsafe def walk(work: Walk,+regex: Bytes.Regex,+limit: Nat,+policy: BinaryPolicy,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,+matches: Matches) -> IO(ResultOf(Matches)):
  match work matches:
    case End{} _: IO.pure(ResultOf(Matches),Done{matches})
    case Advance{cursor} Matches{_,count}:
      Bool.pick(Unit -> IO(ResultOf(Matches)),Nat.is_ge(count,limit),_ => IO.pure(ResultOf(Matches),Done{matches}),
        _ => then(Search.Step,Matches,next(cursor),step => walk(searchStep(step),regex,limit,policy,signal,matches)))(Unit{})
    case Visit{Search.Entry{path,_,FS.RegularFile{}},cursor} Matches{_,count}:
      then(Matches,Matches,scanFile(path,regex,limit - count,policy,signal),found => walk(Advance{cursor},regex,limit,policy,signal,merge(matches,found)))
    case Visit{_,cursor} _: walk(Advance{cursor},regex,limit,policy,signal,matches)

def fsResult(-A: Data,value: Result<&2,&2,FS.Error,A>) -> ResultOf(A):
  match value:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: Done{value}
def literalCompiled(value: Result<&2,&2,Regex.Error,Regex.Regex>) -> Result<&2,&2,Regex.Error,Bytes.Regex>:
  match value:
    case Fail{error}: Fail{error}
    case Done{regex}: Done{Bytes.LiteralRegex{regex}}
def hasNewline(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'\n',_}: True{}
    case SCon{_,rest}: hasNewline(rest)
def compiledMatcher(value: Result<&2,&2,Regex.Error,Bytes.Regex>) -> ResultOf(Bytes.Regex):
  match value:
    case Fail{cause}: Fail{InvalidPattern{cause}}
    case Done{regex}: Done{regex}
def matcher(+pattern: String,+insensitive: Bool,literal: Bool) -> ResultOf(Bytes.Regex):
  +result = Bool.pick(Unit -> Result<&2,&2,Regex.Error,Bytes.Regex>,literal,
    _ => Bool.pick(Unit -> Result<&2,&2,Regex.Error,Bytes.Regex>,hasNewline(pattern),_ => Fail{Regex.Syntax{"Newline literals require multiline search"}},_ => literalCompiled(Regex.compileLiteral(pattern,insensitive)))(Unit{}),
    _ => Bytes.compileLine(pattern,insensitive))(Unit{})
  compiledMatcher(result)

def configuration(value: Result<&1,&1,U32 & String,String>) -> ResultOf(Unit):
  match value:
    case Done{SNil{}}: Done{Unit{}}
    case Done{path}: Fail{UnsupportedConfiguration{path}}
    case Fail{_}: Done{Unit{}}
def nativeDirectory(environment: Paths.Environment,+path: String,override: Maybe<&2,Search.Override>,regex: Bytes.Regex,limit: Nat,policy: BinaryPolicy,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Matches)):
  match environment:
    case Paths.Environment{_,+home,_}:
      do IO<ResultOf(Matches)>:
        cwdResult : Result<&2,&2,FS.Error,String> <- FS.cwd()
        xdgResult : Result<&1,&1,U32 & String,String> <- IO.get_env("XDG_CONFIG_HOME")
        continued(String,Matches,fsResult(String,cwdResult),cwd =>
          do IO<ResultOf(Matches)>:
            value : Search.ResultOf(Search.Cursor) <- Search.create(path,home,Search.nonempty(Search.optionalEnvironment(xdgResult),Path.join(home,".config")),True{},Search.Grep{cwd,override},signal)
            continued(Search.Cursor,Matches,searchResult(Search.Cursor,value),cursor => walk(Advance{cursor},regex,limit,policy,signal,Matches{Nil{},0n})))
def nativeKind(environment: Paths.Environment,+path: String,override: Maybe<&2,Search.Override>,regex: Bytes.Regex,limit: Nat,policy: BinaryPolicy,signal: Maybe<&2,Abort.AbortSignal<Unit>>,kind: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(ResultOf(Matches)):
  match kind:
    case Fail{cause}: IO.pure(ResultOf(Matches),Fail{Filesystem{cause}})
    case Done{FS.Directory{}}: nativeDirectory(environment,path,override,regex,limit,policy,signal)
    case Done{FS.RegularFile{}}: scanFile(path,regex,limit,policy,signal)
    case Done{_}: IO.pure(ResultOf(Matches),Fail{Operation{"Search path is not a regular file or directory: " ++ path}})
def nativeSearch(environment: Paths.Environment,+path: String,glob: Maybe<&2,String>,regex: Bytes.Regex,limit: Nat,policy: BinaryPolicy,signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Matches)):
  continued(Maybe<&2,Search.Override>,Matches,searchResult(Maybe<&2,Search.Override>,Search.compileOverride(glob)),override =>
    do IO<ResultOf(Matches)>:
      config : Result<&1,&1,U32 & String,String> <- IO.get_env("RIPGREP_CONFIG_PATH")
      then(Unit,Matches,IO.pure(ResultOf(Unit),configuration(config)),_ =>
        do IO<ResultOf(Matches)>:
          kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
          nativeKind(environment,path,override,regex,limit,policy,signal,kind)))

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
        return foundDirectory(path,Result.map(&2,&2,Error,FS.FileKind,Bool,Search.isDirectory,fsResult(FS.FileKind,result)))

def textFinished(path: String,text: String,result: Result<&2,&2,Text.Error,Unit>) -> ResultOf(String):
  match result:
    case Fail{cause}: Fail{InvalidEncoding{path,cause}}
    case Done{_}: Done{text}
def finishedText(path: String,result: Result<&2,&2,Text.Error,Text.Decoded>) -> ResultOf(String):
  match result:
    case Fail{cause}: Fail{InvalidEncoding{path,cause}}
    case Done{Text.Decoded{decoder,text}}:
      textFinished(path,text,Text.finish(decoder))
def nativeText(+path: String) -> IO(ResultOf(String)):
  do IO<ResultOf(String)>:
    value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return Result.bind(&2,&2,Error,List<&2,U32>,String,fsResult(List<&2,U32>,value),bytes => finishedText(path,Text.feed(bytes,Text.create())))
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
  +relative = Search.relative(root,path)
  Bool.pick(String,directory && Bool.not(String.is_empty(relative)) && Bool.not(String.starts_with(relative,"..")),relative,Maybe.default(&2,String,List.head(&2,String,List.reverse(&2,String,Strings.split(path,'/'))),""))

def getLines(cached: Maybe<&2,List<&2,String>>,operations: Maybe<&2,GrepOperations>,path: String) -> IO(List<&2,String>):
  match cached:
    case Some{lines}: IO.pure(List<&2,String>,lines)
    case None{}:
      do IO<List<&2,String>>:
        value : ResultOf(String) <- readText(operations,path)
        return contextLines(value)

@unsafe def formatMatches(matches: List<&2,Match>,+root: String,+directory: Bool,+context: Nat,+operations: Maybe<&2,GrepOperations>,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,+cache: Record.Record<List<&2,String>>,+output: Output) -> IO(ResultOf(Output)):
  match matches:
    case Nil{}: IO.pure(ResultOf(Output),Done{output})
    case Match{+path,+line,text} <> +rest:
      +display = displayPath(path,root,directory)
      then(Unit,Output,check(signal),_ => Bool.pick(Unit -> IO(ResultOf(Output)),Nat.is_eq(context,0n),
        _ => formatMatches(rest,root,directory,context,operations,signal,cache,appendLine(display,line,True{},Truncate.truncateLine(text,None{}),output)),
        _ =>
          do IO<ResultOf(Output)>:
            +lines : List<&2,String> <- getLines(Record.get(List<&2,String>,cache,path),operations,path)
            formatMatches(rest,root,directory,context,operations,signal,Record.set(List<&2,String>,cache,path,lines),contextBlock(lines,line,context,display,output)))(Unit{}))

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
def format(+root: String,+directory: Bool,+context: Nat,+limit: Nat,operations: Maybe<&2,GrepOperations>,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,matches: Matches) -> IO(ToolResult()):
  match matches:
    case Matches{Nil{},_}: then(Unit,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,check(signal),_ => IO.pure(ToolResult(),resultText("No matches found",None{})))
    case Matches{reversed,+count}:
      then(Output,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,formatMatches(List.reverse(&2,Match,reversed),root,directory,context,operations,signal,Record.Record{Nil{}},Output{Nil{},False{}}),output =>
        then(Unit,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,check(signal),_ => IO.pure(ToolResult(),renderOutput(limit,Nat.is_ge(count,limit),output))))

def execute(environment: Invocation,+path: String,pattern: String,glob: Maybe<&2,String>,insensitive: Bool,literal: Bool,+context: Nat,+limit: Nat,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match environment:
    case Invocation{paths,_,+operations,policy}:
      then(Bool,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,isDirectory(operations,path),directory =>
        continued(Bytes.Regex,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,matcher(pattern,insensitive,literal),regex =>
          then(Unit,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,check(signal),_ =>
            then(Matches,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,nativeSearch(paths,path,glob,regex,limit,policy,signal),matches => format(path,directory,context,limit,operations,signal,matches)))))

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
    case Invocation{paths,cwd,_,_} GrepContext{override} GrepToolInput{_,path,_,_,_,_,_}:
      resolved(environment,input,signal,Paths.resolveToCwd(paths,Search.nonempty(path,"."),Search.nonempty(override,cwd)))
def invokeWithContext(environment: Invocation,context: GrepContext,request: Agent.ToolExecutionInput<Maybe<&2,GrepToolDetails>>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,arguments,+signal,_}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,check(signal),_ => continued(GrepToolInput,Agent.AgentToolResult<Maybe<&2,GrepToolDetails>>,parseInput(arguments),input => invokeInput(environment,context,signal,input)))
def invoke(environment: Invocation,request: Agent.ToolExecutionInput<Maybe<&2,GrepToolDetails>>) -> IO(ToolResult()):
  invokeWithContext(environment,GrepContext{None{}},request)

def filesystemMessage(error: FS.Error) -> String:
  match error:
    case FS.System{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close
def fileMessage(error: FileFold.Error) -> String:
  match error:
    case FileFold.Open{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FileFold.Read{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FileFold.Close{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FileFold.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
    case FileFold.InvalidReadSize{}: "Invalid read size"
def encodingMessage(error: Text.Error) -> String:
  match error:
    case Text.InvalidByte{offset,_}: "invalid byte at offset " ++ Nat.show(offset)
    case Text.InvalidEncoding{offset}: "invalid text encoding at byte " ++ Nat.show(offset)
    case Text.IncompleteEncoding{offset}: "incomplete text encoding at byte " ++ Nat.show(offset)
def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{cause}: filesystemMessage(cause)
    case FileFailure{cause}: fileMessage(cause)
    case InvalidEncoding{path,cause}: path ++ ": " ++ encodingMessage(cause)
    case InvalidPattern{Regex.Syntax{message}}: "Error parsing regex: " ++ message
    case InvalidPattern{Regex.SizeLimit{}}: "Regex size limit exceeded"
    case InvalidPattern{Regex.RequiresByteInput{}}: "Pattern requires byte matching"
    case InvalidArguments{}: "Grep tool input is invalid. Expected a pattern, optional path/glob, booleans and natural context/limit."
    case InvalidPath{_}: "Invalid file path"
    case PathNotFound{path}: "Path not found: " ++ path
    case UnsupportedConfiguration{path}: "RIPGREP_CONFIG_PATH is not supported by native grep: " ++ path
    case Operation{message}: message
    case Aborted{}: "Operation aborted"
    case SearchFailure{Search.Filesystem{cause}}: filesystemMessage(cause)
    case SearchFailure{Search.Operation{message}}: message
    case SearchFailure{Search.InvalidPattern{_}}: "Error parsing glob pattern"
    case SearchFailure{Search.InvalidIgnore{path,cause}}: path ++ ": " ++ Ignore.errorMessage(cause)
    case SearchFailure{Search.InvalidEncoding{path}}: path ++ ": invalid UTF-8"
    case SearchFailure{Search.InvalidGitConfig{path}}: path ++ ": invalid Git configuration"
    case SearchFailure{Search.Aborted{}}: "Operation aborted"

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
def createGrepTool(paths: Paths.Environment,cwd: String,options: GrepToolOptions) -> IO(ToolOwner):
  match options:
    case GrepToolOptions{operations,policy}:
      do IO<ToolOwner>:
        callback : Callback.Callback<Agent.ToolExecutionInput<Maybe<&2,GrepToolDetails>>,ToolResult()> <- Callback.create(~Invocation,~Agent.ToolExecutionInput<Maybe<&2,GrepToolDetails>>,~ToolResult(),~invoke,Invocation{paths,cwd,operations,policy})
        return ToolOwner{Agent.AgentTool{"grep","Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",grepSchema(),Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"grep",None{},callback,None{},None{}}}
def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Maybe<&2,GrepToolDetails>,Error>:
  match owner:
    case ToolOwner{+tool}: (ToolOwner{tool},tool)
def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_}}: Callback.dispose(Agent.ToolExecutionInput<Maybe<&2,GrepToolDetails>>,ToolResult(),callback)
def dispose(operations: GrepOperations) -> IO(Unit):
  match operations:
    case GrepOperations{directoryCallback,readCallback}:
      do IO<Unit>:
        Callback.dispose(String,ResultOf(Bool),directoryCallback)
        Callback.dispose(String,ResultOf(String),readCallback)
