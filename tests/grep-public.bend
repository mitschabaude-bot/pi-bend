import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/json.bend as Json
import ../packages/coding-agent/src/core/tools/grep.bend as L
import ../packages/coding-agent/src/core/tools/truncate.bend as T
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/string.bend as S
import ../packages/runtime/src/utf8.bend as U
import ../packages/runtime/src/base64.bend as B

def environment(cwd: String,home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}

def encoded(value: String) -> String: B.encoded(U.encode(value),"")
def check(value: Bool, message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

type Injection is Data:
  Injection{mode: String, entries: String, controller: A.AbortController<Unit>}

def cancelled(value: Bool, controller: A.AbortController<Unit>) -> IO(Unit):
  match value:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- A.abort(Unit,controller,None{})
        return Unit{}

def cancel(mode: String, step: String, controller: A.AbortController<Unit>) -> IO(Unit):
  cancelled(String.eq(mode,step),controller)

def isDirectory(env: Injection,path: String) -> IO(L.ResultOf(Bool)):
  match env:
    case Injection{+mode,_,controller}:
      +path = {path: String}
      do IO<L.ResultOf(Bool)>:
        IO.print("isDirectory:" ++ encoded(path))
        cancel(mode,"abort-isDirectory",controller)
        Bool.pick(Unit -> IO(L.ResultOf(Bool)),String.eq(mode,"missing") || String.eq(mode,"directory-error"),_ => IO.pure(L.ResultOf(Bool),Fail{L.Operation{"directory failed"}}),_ => L.isDirectory(None{},path))(Unit{})

def readFile(env: Injection,path: String) -> IO(L.ResultOf(String)):
  match env:
    case Injection{+mode,+entries,controller}:
      +path = {path: String}
      do IO<L.ResultOf(String)>:
        IO.print("readFile:" ++ encoded(path))
        cancel(mode,"abort-readFile",controller)
        Bool.pick(Unit -> IO(L.ResultOf(String)),String.eq(mode,"read-error"),_ => IO.pure(L.ResultOf(String),Fail{L.Operation{"read failed"}}),_ => Bool.pick(Unit -> IO(L.ResultOf(String)),String.eq(entries,":native"),_ => L.nativeText(path),_ => IO.pure(L.ResultOf(String),Done{entries}))(Unit{}))(Unit{})

def operations(+env: Injection) -> IO(L.GrepOperations):
  do IO<L.GrepOperations>:
    directory : C.Callback<String,L.ResultOf(Bool)> <- C.create(~Injection,~String,~L.ResultOf(Bool),~isDirectory,env)
    read : C.Callback<String,L.ResultOf(String)> <- C.create(~Injection,~String,~L.ResultOf(String),~readFile,env)
    return L.GrepOperations{directory,read}

def count(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{n}: Nat.show(n)

def truncation(value: Maybe<&2,T.TruncationResult>) -> String:
  match value:
    case None{}: "none"
    case Some{T.TruncationResult{_,cut,by,totalLines,totalBytes,lines,bytes,partial,first,_,maxBytes}}:
      Bool.show(cut) ++ ":" ++ Nat.show(totalLines) ++ ":" ++ Nat.show(totalBytes) ++ ":" ++ Nat.show(lines) ++ ":" ++ Nat.show(bytes) ++ ":" ++ Bool.show(first) ++ ":" ++ Nat.show(maxBytes)

def flag(value: Maybe<&2,Bool>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: Bool.show(value)
def details(value: Maybe<&2,L.GrepToolDetails>) -> String:
  match value:
    case None{}: "none"
    case Some{L.GrepToolDetails{truncationValue,limit,lines}}: count(limit) ++ "|" ++ truncation(truncationValue) ++ "|" ++ flag(lines)

def report(value: L.ToolResult()) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("error:" ++ encoded(L.errorMessage(error)))
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},value,None{},None{}}}:
      do IO<Unit>:
        IO.print("text:" ++ encoded(text))
        IO.print("details:" ++ details(value))
    case _: IO.die(Unit,1,"unexpected tool result shape")

def parsed(result: Result<&2,&2,Json.ParseError,V.Value>) -> V.Value:
  match result:
    case Done{value}: value
    case Fail{_}: V.Null{}

def call(pair: L.ToolOwner & Agent.AgentTool<Maybe<&2,L.GrepToolDetails>,L.Error>, args: V.Value, signal: A.AbortSignal<Unit>) -> IO(Unit):
  match pair:
    case (owner,Agent.AgentTool{name,_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},label,None{},callback,None{},None{}}):
      do IO<Unit>:
        check(String.eq(name,"grep") && String.eq(label,"grep"),"grep metadata")
        result : L.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2,L.GrepToolDetails>>,L.ToolResult(),callback,Agent.ToolExecutionInput{"grep-1",args,Some{signal},None{}})
        report(result)
        L.disposeTool(owner)
    case _: IO.die(Unit,1,"unexpected tool shape")

def reuse(mode: String,operations: L.GrepOperations) -> IO(Unit):
  match mode operations:
    case "reuse" L.GrepOperations{_,read}:
      do IO<Unit>:
        value : L.ResultOf(String) <- C.call(String,L.ResultOf(String),read,"/virtual")
        check(Result.is_done(&2,&2,L.Error,String,value),"injected callbacks remain caller-owned")
    case _ _: IO.pure(Unit,Unit{})

def countEntries(value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> Nat:
  match value:
    case Done{entries}: List.length(&2,FS.DirectoryEntry,entries)
    case Fail{_}: 999999n

def repeat(fuel: Nat,+callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2,L.GrepToolDetails>>,L.ToolResult()>,+args: V.Value,+signal: A.AbortSignal<Unit>) -> IO(Unit):
  match fuel:
    case Zero{}: IO.pure(Unit,Unit{})
    case Succ{fuel}:
      do IO<Unit>:
        value : L.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2,L.GrepToolDetails>>,L.ToolResult(),callback,Agent.ToolExecutionInput{"repeat",args,Some{signal},None{}})
        check(Result.is_done(&2,&2,L.Error,Agent.AgentToolResult<Maybe<&2,L.GrepToolDetails>>,value),"repeated scan failed")
        repeat(fuel,callback,args,signal)

def repeated(pair: L.ToolOwner & Agent.AgentTool<Maybe<&2,L.GrepToolDetails>,L.Error>,+args: V.Value,+signal: A.AbortSignal<Unit>) -> IO(Unit):
  match pair:
    case (owner,Agent.AgentTool{_,_,_,_,_,_,+callback,_,_}):
      do IO<Unit>:
        repeat(1n,callback,args,signal)
        +before : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
        repeat(64n,callback,args,signal)
        +after : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
        check(Nat.is_eq(countEntries(before),countEntries(after)),"descriptor leak across repeated scans")
        IO.print("fds:" ++ encoded(Nat.show(countEntries(before)) ++ ":" ++ Nat.show(countEntries(after))))
        L.disposeTool(owner)

def abortLater(controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(30)
    won : Bool <- A.abort(Unit,controller,None{})
    return Unit{}

def execute(mode: String,+cwd: String,+home: String,args: V.Value,entries: String,+controller: A.AbortController<Unit>) -> IO(Unit):
  match mode:
    case "abort-native":
      do IO<Unit>:
        owner : L.ToolOwner <- L.createGrepTool(environment(cwd,home),cwd,L.GrepToolOptions{None{},L.MatchText{}})
        task : Chan(Unit) <- IO.fork(Unit,abortLater(controller))
        call(L.borrowTool(owner),args,A.signal(Unit,controller))
        IO.join(Unit,task)
    case "repeat":
      do IO<Unit>:
        owner : L.ToolOwner <- L.createGrepTool(environment(cwd,home),cwd,L.GrepToolOptions{None{},L.MatchText{}})
        repeated(L.borrowTool(owner),args,A.signal(Unit,controller))
    case "skip-binary":
      do IO<Unit>:
        owner : L.ToolOwner <- L.createGrepTool(environment(cwd,home),cwd,L.GrepToolOptions{None{},L.SkipBinary{}})
        call(L.borrowTool(owner),args,A.signal(Unit,controller))
    case "native":
      do IO<Unit>:
        owner : L.ToolOwner <- L.createGrepTool(environment(cwd,home),cwd,L.GrepToolOptions{None{},L.MatchText{}})
        call(L.borrowTool(owner),args,A.signal(Unit,controller))
    case "context":
      do IO<Unit>:
        result : L.ToolResult() <- L.invokeWithContext(L.Invocation{environment(cwd,home),"/",None{},L.MatchText{}},L.GrepContext{Some{cwd}},Agent.ToolExecutionInput{"grep-context",args,Some{A.signal(Unit,controller)},None{}})
        report(result)
    case mode:
      +mode = {mode: String}
      do IO<Unit>:
        +ops : L.GrepOperations <- operations(Injection{mode,entries,controller})
        cancel(mode,"preabort",controller)
        owner : L.ToolOwner <- L.createGrepTool(environment(cwd,home),cwd,L.GrepToolOptions{Some{ops},L.MatchText{}})
        call(L.borrowTool(owner),args,A.signal(Unit,controller))
        reuse(mode,ops)
        L.dispose(ops)

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> cwd <> home <> json <> entries <> Nil{}:
      do IO<Unit>:
        +controller : A.AbortController<Unit> <- A.new(Unit)
        execute(mode,cwd,home,parsed(Json.parse(json)),entries,controller)
        A.dispose(Unit,controller)
    case _: IO.die(Unit,1,"expected mode cwd home JSON injected-text")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
