import Base
import ../packages/runtime/src/collation.bend as Collation
import ../packages/coding-agent/src/core/tools/ls.bend as L
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
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

def environment(+cwd: String) -> Paths.Environment:
  Paths.Environment{cwd,cwd,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}

# Explicit fixture comparator; no locale-collation claim.
def lessEqual(left: String, right: String) -> Bool:
  String.is_le(left,right)

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

def entryStat(name: String) -> L.ResultOf(L.LsStat):
  match name:
    case SCon{'!',_}: Fail{L.Operation{"entry disappeared"}}
    case SCon{'d',_}: Done{L.LsStat{True{}}}
    case _: Done{L.LsStat{False{}}}

def stat(env: Injection, path: String) -> IO(L.ResultOf(L.LsStat)):
  match env:
    case Injection{+mode,_,controller}:
      +path = {path: String}
      do IO<L.ResultOf(L.LsStat)>:
        IO.print("stat:" ++ encoded(path))
        cancel(mode,Bool.pick(String,String.eq(path,"/virtual"),"abort-stat","abort-entry"),controller)
        return Bool.pick(Unit -> L.ResultOf(L.LsStat),String.eq(path,"/virtual"),
          _ => Bool.pick(L.ResultOf(L.LsStat),String.eq(mode,"stat-error"),Fail{L.Operation{"stat failed"}},Done{L.LsStat{Bool.not(String.eq(mode,"file"))}}),
          _ => entryStat(Maybe.default(&2,String,List.head(&2,String,List.reverse(&2,String,S.split(path,'/'))),"")))(Unit{})

def readdir(env: Injection, path: String) -> IO(L.ResultOf(List<&2,String>)):
  match env:
    case Injection{+mode,+entries,controller}:
      do IO<L.ResultOf(List<&2,String>)>:
        IO.print("readdir:" ++ encoded(path))
        cancel(mode,"abort-readdir",controller)
        return Bool.pick(L.ResultOf(List<&2,String>),String.eq(mode,"readdir-error"),Fail{L.Operation{"denied"}},Done{Bool.pick(List<&2,String>,String.is_empty(entries),Nil{},S.split(entries,'\n'))})

def operations(+env: Injection) -> IO(L.LsOperations):
  do IO<L.LsOperations>:
    e : C.Callback<String,L.ResultOf(Bool)> <- C.create(~Injection,~String,~L.ResultOf(Bool),~exists,env)
    s : C.Callback<String,L.ResultOf(L.LsStat)> <- C.create(~Injection,~String,~L.ResultOf(L.LsStat),~stat,env)
    r : C.Callback<String,L.ResultOf(List<&2,String>)> <- C.create(~Injection,~String,~L.ResultOf(List<&2,String>),~readdir,env)
    return L.LsOperations{e,s,r}

def count(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{n}: Nat.show(n)

def truncation(value: Maybe<&2,T.TruncationResult>) -> String:
  match value:
    case None{}: "none"
    case Some{T.TruncationResult{_,cut,by,totalLines,totalBytes,lines,bytes,partial,first,_,maxBytes}}:
      Bool.show(cut) ++ ":" ++ Nat.show(totalLines) ++ ":" ++ Nat.show(totalBytes) ++ ":" ++ Nat.show(lines) ++ ":" ++ Nat.show(bytes) ++ ":" ++ Bool.show(first) ++ ":" ++ Nat.show(maxBytes)

def details(value: Maybe<&2,L.LsToolDetails>) -> String:
  match value:
    case None{}: "none"
    case Some{L.LsToolDetails{truncationValue,limit}}: count(limit) ++ "|" ++ truncation(truncationValue)

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

def arguments(path: String, maximum: String) -> V.Value:
  match path:
    case "none": V.ObjectValue{R.Record{limit(maximum)}}
    case _: V.ObjectValue{R.Record{R.Property{"path",V.Text{path}} <> limit(maximum)}}

def call(pair: L.ToolOwner & Agent.AgentTool<L.LsToolDetails,L.Error>, args: V.Value, signal: A.AbortSignal<Unit>) -> IO(Unit):
  match pair:
    case (owner,Agent.AgentTool{name,_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},label,None{},callback,None{},None{}}):
      do IO<Unit>:
        check(String.eq(name,"ls") && String.eq(label,"ls"),"ls metadata")
        result : L.ToolResult() <- C.call(Agent.ToolExecutionInput<L.LsToolDetails>,L.ToolResult(),callback,Agent.ToolExecutionInput{"ls-1",args,Some{signal},None{}})
        report(result)
        L.disposeTool(owner)
    case _: IO.die(Unit,1,"unexpected tool shape")

def reuse(mode: String, operations: L.LsOperations) -> IO(Unit):
  match mode operations:
    case "reuse" L.LsOperations{exists,_,_}:
      do IO<Unit>:
        value : L.ResultOf(Bool) <- C.call(String,L.ResultOf(Bool),exists,"/virtual")
        check(Result.is_done(&2,&2,L.Error,Bool,value),"injected callbacks remain caller-owned")
    case _ _: IO.pure(Unit,Unit{})

# The default order: lowercase names in root collation, loaded from <entries>.
def collated(+cwd: String, path: String, maximum: String, signal: A.AbortSignal<Unit>, loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(Unit):
  match loaded:
    case Fail{_}: IO.die(Unit,1,"collation data missing")
    case Done{collator}:
      do IO<Unit>:
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        owner : L.ToolOwner <- L.createLsTool(collator,environment(cwd),cwd,L.LsToolOptions{None{}},unbound1)
        call(L.borrowTool(owner),arguments(path,maximum),signal)

def execute(mode: String, +cwd: String, path: String, maximum: String, entries: String, +controller: A.AbortController<Unit>) -> IO(Unit):
  match mode:
    case "native":
      do IO<Unit>:
        +unbound2 : Ctx.ContextSource() <- Ctx.create()
        owner : L.ToolOwner <- L.createLsToolWithComparator(~lessEqual,environment(cwd),cwd,L.LsToolOptions{None{}},unbound2)
        call(L.borrowTool(owner),arguments(path,maximum),A.signal(Unit,controller))
    case "collated":
      do IO<Unit>:
        loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(entries)
        collated(cwd,path,maximum,A.signal(Unit,controller),loaded)
    case "context":
      do IO<Unit>:
        +ops : L.LsOperations <- L.defaultLsOperations()
        result : L.ToolResult() <- L.invokeWithContext(~lessEqual,L.Invocation{environment(cwd),"/",ops,L.ByComparator{}},L.LsContext{Some{cwd}},Agent.ToolExecutionInput{"ls-context",arguments(path,maximum),Some{A.signal(Unit,controller)},None{}})
        report(result)
        L.dispose(ops)
    case mode:
      +mode = {mode: String}
      do IO<Unit>:
        +ops : L.LsOperations <- operations(Injection{mode,entries,controller})
        cancel(mode,"preabort",controller)
        +unbound3 : Ctx.ContextSource() <- Ctx.create()
        owner : L.ToolOwner <- L.createLsToolWithComparator(~lessEqual,environment(cwd),cwd,L.LsToolOptions{Some{ops}},unbound3)
        call(L.borrowTool(owner),arguments(path,maximum),A.signal(Unit,controller))
        reuse(mode,ops)
        L.dispose(ops)

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> cwd <> path <> maximum <> entries <> Nil{}:
      do IO<Unit>:
        +controller : A.AbortController<Unit> <- A.new(Unit)
        execute(mode,cwd,path,maximum,entries,controller)
        A.dispose(Unit,controller)
    case _: IO.die(Unit,1,"expected mode cwd path limit entries")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
