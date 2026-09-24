import Base
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/coding-agent/src/core/tools/truncate.bend as T
import ../packages/coding-agent/src/utils/shell.bend as Shell
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/base64.bend as B64
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

# One public call drives real callbacks; the host runner checks the wire frames.
# UTF-8 encoding already guarantees valid octets; use the direct encoder.
def wire(text: String) -> String: B64.encoded(Utf8.encode(text), "")
def check(value: Bool, message: String) -> IO(Unit):
  Bool.pick(IO(Unit),value,IO.pure(Unit,Unit{}),IO.die(Unit,1,message))
def flag(value: Bool) -> String: Bool.pick(String,value,"true","false")
def path(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: wire(text)
def limit(value: Maybe<&2,T.Limit>) -> String:
  match value:
    case None{}: "none"
    case Some{T.Lines{}}: "lines"
    case Some{T.Bytes{}}: "bytes"
def details(value: Maybe<&2,Bash.BashToolDetails>) -> String:
  match value:
    case None{}: "none"
    case Some{Bash.BashToolDetails{None{},file}}: "present|" ++ path(file)
    case Some{Bash.BashToolDetails{Some{T.TruncationResult{_,truncated,cause,totalLines,totalBytes,lines,bytes,partial,_,_,_}},file}}:
      String.join(["trunc",flag(truncated),limit(cause),Nat.show(totalLines),Nat.show(totalBytes),Nat.show(lines),Nat.show(bytes),flag(partial),path(file)],"|")
def content(values: List<&2,Ai.TextImageContent>, acc: String, count: Nat) -> String & Nat:
  match values:
    case Nil{}: (acc,count)
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: content(rest,acc ++ text,count+1n)
    case _ <> rest: content(rest,acc,count)
def rendered(prefix: String, detail: Maybe<&2,Bash.BashToolDetails>, pair: String & Nat) -> String:
  match pair:
    case (text,count): prefix ++ "|" ++ Nat.show(count) ++ "|" ++ wire(text) ++ "|" ++ details(detail)
def frame(prefix: String, result: Agent.AgentToolResult<Bash.BashToolDetails>) -> String:
  match result:
    case Agent.AgentToolResult{items,detail,None{},None{}}: rendered(prefix,detail,content(items,"",0n))
    case _: "unexpected-result-shape"
def update(unused: Unit, value: Agent.AgentToolResult<Bash.BashToolDetails>) -> IO(Unit): IO.print(frame("update",value))
def report(value: Bash.ToolResult()) -> IO(Unit):
  match value:
    case Done{result}: IO.print(frame("result",result))
    case Fail{error}: IO.print("error|" ++ wire(Bash.errorMessage(error)))
def variable(+name: String, environment: Shell.Environment()) -> Maybe<&2,String>:
  match environment:
    case Nil{}: None{}
    case Shell.Variable{key,value} <> rest: Bool.pick(Maybe<&2,String>,String.eq(name,key),Some{value},variable(name,rest))
def envFrame(+env: Shell.Environment()) -> String:
  String.join([path(variable("PI_SESSION_ID",env)),path(variable("PI_SESSION_FILE",env)),path(variable("PI_PROVIDER",env)),path(variable("PI_MODEL",env)),path(variable("PI_REASONING_LEVEL",env)),path(variable("HOOK_MARKER",env))],"|")
def send(onData: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, bytes: List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,Unit> <- C.call(List<&2,U32>,Result<&2,&2,String,Unit>,onData,bytes)
    check(Result.is_done(&2,&2,String,Unit,result),"onData failed")
def repeatByte(count: Nat, acc: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: acc
    case 1n+rest: repeatByte(rest,120 <> acc)
def lines(count: Nat, +index: Nat, +onData: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        send(onData,Utf8.encode(Nat.show(index) ++ "\n"))
        lines(rest,index+1n,onData)
def output(mode: String, +onData: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Unit):
  match mode:
    case "mock-empty": IO.pure(Unit,Unit{})
    case "mock-split":
      do IO<Unit>:
        send(onData,[226])
        send(onData,[130,172,10])
    case "mock-partial": send(onData,repeatByte(60000n,Nil{}))
    case "mock-lines": lines(3000n,1n,onData)
    case "mock-lines-abort": lines(3000n,1n,onData)
    case "mock-lines-timeout": lines(3000n,1n,onData)
    case "mock-chatty": lines(5000n,1n,onData)
    case _: send(onData,Utf8.encode("partial\n"))
def outcome(mode: String) -> Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>:
  match mode:
    case "mock-nonzero": Done{Some{7}}
    case "mock-null": Done{None{}}
    case "mock-abort": Fail{Bash.Aborted{}}
    case "mock-lines-abort": Fail{Bash.Aborted{}}
    case "mock-timeout": Fail{Bash.TimedOut{U32.to_f64(5)}}
    case "mock-lines-timeout": Fail{Bash.TimedOut{U32.to_f64(5)}}
    case "mock-error": Fail{Bash.Operation{"injected failure"}}
    case _: Done{Some{0}}
type Injection is Data:
  Injection{mode: String, retained: Ref.Ref<Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>>}
def injected(environment: Injection, input: Bash.BashExecutionInput) -> IO(Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>):
  match environment input:
    case Injection{+mode,retained} Bash.BashExecutionInput{command,cwd,+onData,_,_,env}:
      do IO<Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>>:
        IO.print("call|" ++ wire(command) ++ "|" ++ wire(cwd) ++ "|" ++ envFrame(Maybe.default(&2,Shell.Environment(),env,Nil{})))
        Ref.write(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained,Some{onData})
        output(mode,onData)
        return outcome(mode)
def hook(mode: String, context: Bash.BashSpawnContext) -> IO(Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>):
  match mode context:
    case "mock-hook-fail" _: IO.pure(Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,Fail{Bash.Operation{"hook failed"}})
    case _ Bash.BashSpawnContext{+command,+cwd,+env}:
      do IO<Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>>:
        IO.print("hook|" ++ wire(command) ++ "|" ++ wire(cwd) ++ "|" ++ envFrame(env))
        return Done{Bash.BashSpawnContext{command ++ "\nhooked",cwd ++ "/hooked",Shell.updateEnvironment("HOOK_MARKER","yes",env,Nil{})}}
def native(mode: String) -> Bool:
  match mode:
    case "native": True{}
    case "native-prefix": True{}
    case "native-abort": True{}
    case "native-preabort": True{}
    case _: False{}
def prefix(mode: String) -> Maybe<&2,String>:
  match mode:
    case "native-prefix": Some{"printf 'prefix-output\\n'"}
    case "mock-prefix": Some{"prefix"}
    case "mock-hook": Some{"prefix"}
    case _: None{}
def spawnHook(mode: String, callback: C.Callback<Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>>) -> Maybe<&2,C.Callback<Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>>>:
  match mode:
    case "mock-hook": Some{callback}
    case "mock-hook-fail": Some{callback}
    case _: None{}
def number(text: String) -> Maybe<&2,F64>:
  match text:
    case "none": None{}
    case "nan": Some{F64{2146959360,0}}
    case "inf": Some{F64{2146435072,0}}
    case _: F64.read(text)
def timeoutProperty(value: Maybe<&2,F64>) -> List<&2,R.Property<V.Value>>:
  match value:
    case None{}: Nil{}
    case Some{seconds}: [R.Property{"timeout",V.Number{seconds}}]
def arguments(mode: String, command: String, seconds: String) -> V.Value:
  match mode seconds:
    case "mock-invalid" _: V.ObjectValue{R.Record{[R.Property{"command",V.Boolean{True{}}}]}}
    case _ "bad-type": V.ObjectValue{R.Record{[R.Property{"command",V.Text{command}},R.Property{"timeout",V.Text{"bad"}}]}}
    case _ seconds:
      V.ObjectValue{R.Record{R.Property{"command",V.Text{command}} <> timeoutProperty(number(seconds))}}
def delayedAbort(controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(100)
    won : Bool <- A.abort(Unit,controller,None{})
    return Unit{}
def prepareAbort(mode: String, controller: A.AbortController<Unit>) -> IO(Maybe<&2,Chan(Unit)>):
  match mode:
    case "native-preabort":
      do IO<Maybe<&2,Chan(Unit)>>:
        won : Bool <- A.abort(Unit,controller,None{})
        return None{}
    case "native-abort":
      do IO<Maybe<&2,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,delayedAbort(controller))
        return Some{task}
    case _: IO.pure(Maybe<&2,Chan(Unit)>,None{})
def join(task: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match task:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: IO.join(Unit,value)
def late(mode: String, value: Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>) -> IO(Unit):
  match mode value:
    case "mock-late" Some{callback}:
      do IO<Unit>:
        send(callback,Utf8.encode("late output"))
        IO.print("late|ignored")
    case _ _: IO.pure(Unit,Unit{})

def context(+cwd: String) -> Bash.BashContext:
  Bash.BashContext{Some{cwd ++ "/context"},Some{"session-A"},Some{"/tmp/session.json"},Some{"openai"},Some{"model-A"},Some{"high"}}
def request(mode: String, invocation: Bash.Invocation, cwd: String, input: Agent.ToolExecutionInput<Bash.BashToolDetails>, callback: C.Callback<Agent.ToolExecutionInput<Bash.BashToolDetails>,Bash.ToolResult()>) -> IO(Bash.ToolResult()):
  match mode:
    case "mock-context": Bash.invokeWithContext(invocation,context(cwd),input)
    case "mock-hidden": Bash.invokeWithContext(invocation,context(cwd),input)
    case _: C.call(Agent.ToolExecutionInput<Bash.BashToolDetails>,Bash.ToolResult(),callback,input)

def call(+mode: String, binDir: String, +cwd: String, options: Bash.BashToolOptions, operations: Bash.BashOperations, params: V.Value, signal: A.AbortSignal<Unit>, update: Agent.AgentToolUpdateCallback(Bash.BashToolDetails), retained: Ref.Ref<Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>>, pair: Bash.ToolOwner & Agent.AgentTool<Bash.BashToolDetails,Bash.Error>) -> IO(Unit):
  match pair:
    case (owner,Agent.AgentTool{name,_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},label,None{},callback,None{},None{}}):
      do IO<Unit>:
        check(String.eq(name,"bash") && String.eq(label,"bash"),"public metadata")
        result : Bash.ToolResult() <- request(mode,Bash.Invocation{binDir,cwd,options,operations,None{}},cwd,Agent.ToolExecutionInput{"bash-fixture",params,Some{signal},Some{update}},callback)
        report(result)
        saved : Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>> <- Ref.read(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained)
        late(mode,saved)
        Bash.disposeTool(owner)
        IO.print("closed")
    case _: IO.die(Unit,1,"unexpected public metadata")

def runCase(+mode: String,+binDir: String,+cwd: String,shell: String,command: String,seconds: String) -> IO(Unit):
  do IO<Unit>:
    +retained : Ref.Ref<Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>> <- Ref.new(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,None{})
    +exec : C.Callback<Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>> <- C.create(~Injection,~Bash.BashExecutionInput,~Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,~injected,Injection{mode,retained})
    +hookCallback : C.Callback<Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>> <- C.create(~String,~Bash.BashSpawnContext,~Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,~hook,mode)
    +updateCallback : Agent.AgentToolUpdateCallback(Bash.BashToolDetails) <- C.create(~Unit,~Agent.AgentToolResult<Bash.BashToolDetails>,~Unit,~update,Unit{})
    +controller : A.AbortController<Unit> <- A.new(Unit)
    abortTask : Maybe<&2,Chan(Unit)> <- prepareAbort(mode,controller)
    +options : Bash.BashToolOptions = Bash.BashToolOptions{Bool.pick(Maybe<&2,Bash.BashOperations>,native(mode),None{},Some{Bash.BashOperations{exec}}),prefix(mode),Some{shell},Some{Bool.not(String.eq(mode,"mock-hidden"))},spawnHook(mode,hookCallback)}
    +unbound1 : Ctx.ContextSource() <- Ctx.create()
    owner : Bash.ToolOwner <- Bash.createBashTool(binDir,cwd,options,unbound1)
    call(mode,binDir,cwd,options,Bash.BashOperations{exec},arguments(mode,command,seconds),A.signal(Unit,controller),updateCallback,retained,Bash.borrowTool(owner))
    join(abortTask)
    A.dispose(Unit,controller)
    C.dispose(Agent.AgentToolResult<Bash.BashToolDetails>,Unit,updateCallback)
    C.dispose(Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,hookCallback)
    C.dispose(Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,exec)
    unused : Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>> <- Ref.dispose(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained)
    return Unit{}
def repeat(count: Nat,+mode: String,+binDir: String,+cwd: String,+shell: String,+command: String,+seconds: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        runCase(mode,binDir,cwd,shell,command,seconds)
        repeat(rest,mode,binDir,cwd,shell,command,seconds)
def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> binDir <> cwd <> shell <> command <> seconds <> count <> Nil{}: repeat(Maybe.default(&2,Nat,Nat.read(count),0n),mode,binDir,cwd,shell,command,seconds)
    case _: IO.die(Unit,1,"usage: MODE BIN_DIR CWD SHELL COMMAND TIMEOUT COUNT")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
