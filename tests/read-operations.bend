import Base
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/agent/src/types.bend as Agent
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as Record
import ./read-public.bend as Public
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

type Scenario is Data:
  Scenario{trace: Ref.Ref<String>, mode: String, controller: Abort.AbortController<Unit>}

def event(environment: Scenario, +stage: String) -> IO(Read.ResultOf(Unit)):
  match environment:
    case Scenario{+trace,+mode,controller}:
      do IO<Read.ResultOf(Unit)>:
        previous : String <- Ref.read(String,trace)
        Ref.write(String,trace,previous ++ stage ++ ";")
        ignored : Bool <- Bool.pick(Unit -> IO(Bool),String.eq(mode,"abort-" ++ stage),_ => Abort.abort(Unit,controller,None{}),_ => IO.pure(Bool,False{}))(Unit{})
        return Bool.pick(Read.ResultOf(Unit),String.eq(mode,"fail-" ++ stage),Fail{Read.Operation{stage ++ " failure"}},Done{Unit{}})

def access(environment: Scenario, path: String) -> IO(Read.ResultOf(Unit)):
  event(environment,"access:" ++ path)

def reader(environment: Scenario, path: String) -> IO(Read.ResultOf(List<&2,U32>)):
  Read.then(Unit,List<&2,U32>,event(environment,"read"),_ => IO.pure(Read.ResultOf(List<&2,U32>),Done{Utf8.encode("alpha\nbeta")}))

def detector(environment: Scenario, path: String) -> IO(Read.ResultOf(Maybe<&2,String>)):
  match environment:
    case Scenario{trace,+mode,controller}:
      Read.then(Unit,Maybe<&2,String>,event(Scenario{trace,mode,controller},"mime"),_ => IO.pure(Read.ResultOf(Maybe<&2,String>),Done{Bool.pick(Maybe<&2,String>,String.eq(mode,"empty-mime"),Some{""},Some{"image/gif"})}))

def processor(environment: Scenario, input: Read.ImageInput) -> IO(Read.ResultOf(Read.ProcessedImage)):
  match input:
    case Read.ImageInput{bytes,mime,resize,_}:
      Read.then(Unit,Read.ProcessedImage,event(environment,"image"),_ => IO.pure(Read.ResultOf(Read.ProcessedImage),Done{Read.Processed{"AQID",mime,Bool.pick(List<&2,String>,resize,"resized" <> Nil{},Nil{})}}))

def parameters() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"path",V.Text{"file"}} <> Nil{}}}

def call(pair: Read.ToolOwner & Agent.AgentTool<Read.ReadToolDetails,Read.Error>, signal: Abort.AbortSignal<Unit>) -> IO(Read.ToolResult()):
  match pair:
    case Tuple{owner,Agent.AgentTool{_,_,_,_,_,_,callback,_,_}}:
      do IO<Read.ToolResult()>:
        result : Read.ToolResult() <- C.call(Agent.ToolExecutionInput<Read.ReadToolDetails>,Read.ToolResult(),callback,Agent.ToolExecutionInput{"injected",parameters(),Some{signal},None{}})
        Read.disposeTool(owner)
        return result

def scenario(+mode: String) -> IO(Unit):
  do IO<Unit>:
    +trace : Ref.Ref<String> <- Ref.new(String,"")
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +env : Scenario = Scenario{trace,mode,controller}
    +reader : C.Callback<String,Read.ResultOf(List<&2,U32>)> <- C.create(~Scenario,~String,~Read.ResultOf(List<&2,U32>),~reader,env)
    +access : C.Callback<String,Read.ResultOf(Unit)> <- C.create(~Scenario,~String,~Read.ResultOf(Unit),~access,env)
    +detect : C.Callback<String,Read.ResultOf(Maybe<&2,String>)> <- C.create(~Scenario,~String,~Read.ResultOf(Maybe<&2,String>),~detector,env)
    +process : C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)> <- C.create(~Scenario,~Read.ImageInput,~Read.ResultOf(Read.ProcessedImage),~processor,env)
    +operations : Read.ReadOperations = Read.ReadOperations{reader,access,Bool.pick(Maybe<&2,C.Callback<String,Read.ResultOf(Maybe<&2,String>)>>,String.eq(mode,"text"),None{},Some{detect})}
    ignored : Bool <- Bool.pick(Unit -> IO(Bool),String.eq(mode,"pre-abort"),_ => Abort.abort(Unit,controller,None{}),_ => IO.pure(Bool,False{}))(Unit{})
    +unbound1 : Ctx.ContextSource() <- Ctx.create()
    tool : Read.ToolOwner <- Read.createReadTool(Public.environment("/tmp/read-test","/tmp"),"/tmp/read-test",Read.ReadToolOptions{None{},None{},Some{operations},Some{process}},unbound1)
    result : Read.ToolResult() <- call(Read.borrowTool(tool),Abort.signal(Unit,controller))
    log : String <- Ref.read(String,trace)
    IO.print("[" ++ Json.quote(mode) ++ "," ++ Public.report(result) ++ "," ++ Json.quote(log) ++ "]")
    # Disposal of the tool must not retire borrowed operation callbacks.
    stillLive : Read.ResultOf(List<&2,U32>) <- C.call(String,Read.ResultOf(List<&2,U32>),reader,"ignored")
    context : Read.ToolResult() <- Read.invokeWithContext(Read.Invocation{Public.environment("/tmp/read-test","/tmp"),"/tmp/read-test",operations,False{},None{},Some{process}},Read.ReadContext{Some{"/tmp/override"},Some{False{}},None{}},Agent.ToolExecutionInput{"context",parameters(),None{},None{}})
    contextLog : String <- Ref.read(String,trace)
    IO.print("[" ++ Json.quote(mode ++ "-context") ++ "," ++ Public.report(context) ++ "," ++ Json.quote(contextLog) ++ "]")
    C.dispose(String,Read.ResultOf(List<&2,U32>),reader)
    C.dispose(String,Read.ResultOf(Unit),access)
    C.dispose(String,Read.ResultOf(Maybe<&2,String>),detect)
    C.dispose(Read.ImageInput,Read.ResultOf(Read.ProcessedImage),process)
    retired : String <- Ref.dispose(String,trace)
    Abort.dispose(Unit,controller)

def cases(values: List<&2,String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case mode <> rest:
      do IO<Unit>:
        scenario(mode)
        cases(rest)

def scenarios() -> IO(Unit):
  cases("text" <> "image" <> "empty-mime" <> "pre-abort" <> "fail-access:/tmp/read-test/file" <> "fail-mime" <> "fail-read" <> "fail-image" <> "abort-access:/tmp/read-test/file" <> "abort-read" <> Nil{})


type Gate is Data:
  Gate{entered: Chan(Unit), resume: Chan(Unit), finished: Ref.Ref<Bool>}

def gated(environment: Gate, path: String) -> IO(Read.ResultOf(List<&2,U32>)):
  match environment:
    case Gate{entered,resume,finished}:
      do IO<Read.ResultOf(List<&2,U32>)>:
        sent : Bool <- Chan.send(Unit,entered,Unit{})
        IO.join(Unit,resume)
        Ref.write(Bool,finished,True{})
        return Done{Utf8.encode("settled")}

def allowed(environment: Unit, path: String) -> IO(Read.ResultOf(Unit)):
  IO.pure(Read.ResultOf(Unit),Done{Unit{}})

def finish(value: Read.ToolResult(), settled: Bool) -> IO(Unit):
  match value settled:
    case Fail{Read.Aborted{}} True{}: IO.print("gated read settled before cancellation returned")
    case _ _: IO.die(Unit,1,"read returned before its callback settled")

def inflight() -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit,1)
    +resume : Chan(Unit) <- Chan.new(Unit,1)
    +finished : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +reader : C.Callback<String,Read.ResultOf(List<&2,U32>)> <- C.create(~Gate,~String,~Read.ResultOf(List<&2,U32>),~gated,Gate{entered,resume,finished})
    +access : C.Callback<String,Read.ResultOf(Unit)> <- C.create(~Unit,~String,~Read.ResultOf(Unit),~allowed,Unit{})
    +operations : Read.ReadOperations = Read.ReadOperations{reader,access,None{}}
    channel : Chan(Read.ToolResult()) <- IO.fork(Read.ToolResult(),Read.execute(Read.Invocation{Public.environment("/tmp","/tmp"),"/tmp",operations,True{},None{},None{}},Read.ReadToolInput{"file",None{},None{}},None{},None{},Some{Abort.signal(Unit,controller)},Done{"/tmp/read-test/file"}))
    IO.join(Unit,entered)
    aborted : Bool <- Abort.abort(Unit,controller,None{})
    sent : Bool <- Chan.send(Unit,resume,Unit{})
    value : Read.ToolResult() <- IO.join(Read.ToolResult(),channel)
    state : Bool <- Ref.read(Bool,finished)
    finish(value,state)
    Read.dispose(operations)
    Abort.dispose(Unit,controller)
    retired : Bool <- Ref.dispose(Bool,finished)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenarios()
    inflight()
