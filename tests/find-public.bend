import Base
import ../packages/coding-agent/src/core/tools/find.bend as L
import ../packages/coding-agent/src/core/tools/truncate.bend as T
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/utils/tools-manager.bend as Tools
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
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}

def environment(cwd: String,home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,urlContext()}

# rg and fd come from the temporary home's bin directory; nothing downloads.
def manager(home: String) -> Tools.ToolsManager:
  Tools.ToolsManager{home ++ "/.pi/agent/bin",urlContext(),None{}}

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

def exists(env: Injection, path: String) -> IO(L.ResultOf(Bool)):
  match env:
    case Injection{+mode,_,controller}:
      do IO<L.ResultOf(Bool)>:
        IO.print("exists:" ++ encoded(path))
        cancel(mode,"abort-exists",controller)
        return Bool.pick(L.ResultOf(Bool),String.eq(mode,"exists-error"),Fail{L.Operation{"exists failed"}},Done{Bool.not(String.eq(mode,"missing"))})

def glob(env: Injection,input: L.FindGlobInput) -> IO(L.ResultOf(List<&2,String>)):
  match env input:
    case Injection{+mode,+entries,controller} L.FindGlobInput{pattern,cwd,L.FindGlobOptions{ignore,limit}}:
      do IO<L.ResultOf(List<&2,String>)>:
        check(S.equal(String.join(ignore,"|"),"**/node_modules/**|**/.git/**"),"injected ignore options")
        IO.print("glob:" ++ encoded(pattern ++ "|" ++ cwd ++ "|" ++ Nat.show(limit)))
        cancel(mode,"abort-glob",controller)
        return Bool.pick(L.ResultOf(List<&2,String>),String.eq(mode,"glob-error"),Fail{L.Operation{"glob failed"}},Done{Bool.pick(List<&2,String>,String.is_empty(entries),Nil{},S.split(entries,'\n'))})

def operations(+env: Injection) -> IO(L.FindOperations):
  do IO<L.FindOperations>:
    e : C.Callback<String,L.ResultOf(Bool)> <- C.create(~Injection,~String,~L.ResultOf(Bool),~exists,env)
    g : C.Callback<L.FindGlobInput,L.ResultOf(List<&2,String>)> <- C.create(~Injection,~L.FindGlobInput,~L.ResultOf(List<&2,String>),~glob,env)
    return L.FindOperations{e,g}

def count(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{n}: Nat.show(n)

def truncation(value: Maybe<&2,T.TruncationResult>) -> String:
  match value:
    case None{}: "none"
    case Some{T.TruncationResult{_,cut,by,totalLines,totalBytes,lines,bytes,partial,first,_,maxBytes}}:
      Bool.show(cut) ++ ":" ++ Nat.show(totalLines) ++ ":" ++ Nat.show(totalBytes) ++ ":" ++ Nat.show(lines) ++ ":" ++ Nat.show(bytes) ++ ":" ++ Bool.show(first) ++ ":" ++ Nat.show(maxBytes)

def details(value: Maybe<&2,L.FindToolDetails>) -> String:
  match value:
    case None{}: "none"
    case Some{L.FindToolDetails{truncationValue,limit}}: count(limit) ++ "|" ++ truncation(truncationValue)

def report(value: L.ToolResult()) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("error:" ++ encoded(L.errorMessage(error)))
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},value,None{},None{}}}:
      do IO<Unit>:
        IO.print("text:" ++ encoded(text))
        IO.print("details:" ++ details(value))
    case _: IO.die(Unit,1,"unexpected tool result shape")

def limit(value: String) -> List<&2,R.Property<V.Value>>:
  match value:
    case "none": Nil{}
    case "bad": R.Property{"limit",V.Text{"bad"}} <> Nil{}
    case _: R.Property{"limit",V.Number{Maybe.default(&2,F64,F64.read(value),F64{2146959360,0})}} <> Nil{}

def arguments(pattern: String,path: String, maximum: String) -> V.Value:
  match path:
    case "none": V.ObjectValue{R.Record{R.Property{"pattern",V.Text{pattern}} <> limit(maximum)}}
    case _: V.ObjectValue{R.Record{R.Property{"pattern",V.Text{pattern}} <> R.Property{"path",V.Text{path}} <> limit(maximum)}}

def call(pair: L.ToolOwner & Agent.AgentTool<L.FindToolDetails,L.Error>, args: V.Value, signal: A.AbortSignal<Unit>) -> IO(Unit):
  match pair:
    case (owner,Agent.AgentTool{name,_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},label,None{},callback,None{},None{}}):
      do IO<Unit>:
        check(String.eq(name,"find") && String.eq(label,"find"),"ls metadata")
        result : L.ToolResult() <- C.call(Agent.ToolExecutionInput<L.FindToolDetails>,L.ToolResult(),callback,Agent.ToolExecutionInput{"ls-1",args,Some{signal},None{}})
        report(result)
        L.disposeTool(owner)
    case _: IO.die(Unit,1,"unexpected tool shape")

def reuse(mode: String, operations: L.FindOperations) -> IO(Unit):
  match mode operations:
    case "reuse" L.FindOperations{exists,_}:
      do IO<Unit>:
        value : L.ResultOf(Bool) <- C.call(String,L.ResultOf(Bool),exists,"/virtual")
        check(Result.is_done(&2,&2,L.Error,Bool,value),"injected callbacks remain caller-owned")
    case _ _: IO.pure(Unit,Unit{})

def execute(mode: String,+cwd: String,+home: String,pattern: String,path: String,maximum: String,entries: String,+controller: A.AbortController<Unit>) -> IO(Unit):
  match mode:
    case "relative": IO.print("relative:" ++ encoded(L.relativizeFindResultPath(path,cwd)))
    case "native":
      do IO<Unit>:
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        owner : L.ToolOwner <- L.createFindTool(environment(cwd,home),manager(home),cwd,L.FindToolOptions{None{}},unbound1)
        call(L.borrowTool(owner),arguments(pattern,path,maximum),A.signal(Unit,controller))
    case "context":
      do IO<Unit>:
        result : L.ToolResult() <- L.invokeWithContext(L.Invocation{environment(cwd,home),manager(home),"/",None{}},L.FindContext{Some{cwd}},Agent.ToolExecutionInput{"find-context",arguments(pattern,path,maximum),Some{A.signal(Unit,controller)},None{}})
        report(result)
    case mode:
      +mode = {mode: String}
      do IO<Unit>:
        +ops : L.FindOperations <- operations(Injection{mode,entries,controller})
        cancel(mode,"preabort",controller)
        +unbound2 : Ctx.ContextSource() <- Ctx.create()
        owner : L.ToolOwner <- L.createFindTool(environment(cwd,home),manager(home),cwd,L.FindToolOptions{Some{ops}},unbound2)
        call(L.borrowTool(owner),arguments(pattern,path,maximum),A.signal(Unit,controller))
        reuse(mode,ops)
        L.dispose(ops)

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> cwd <> home <> pattern <> path <> maximum <> entries <> Nil{}:
      do IO<Unit>:
        +controller : A.AbortController<Unit> <- A.new(Unit)
        execute(mode,cwd,home,String.drop(pattern,8n),path,maximum,entries,controller)
        A.dispose(Unit,controller)
    case _: IO.die(Unit,1,"expected mode cwd home pattern path limit entries")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
