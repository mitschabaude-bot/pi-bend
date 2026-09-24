import Base
import ./output-accumulator.bend as Output
import ./truncate.bend as Truncate
import ../../utils/shell.bend as Shell
import ../../../../runtime/src/child-process.bend as Child
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/ref.bend as Ref
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../extensions/context.bend as Ctx

# Typed operations are shared by local and injected (for example remote) shells.
type BashToolInput is Data:
  BashToolInput{command: String, timeout: Maybe<&2,F64>}
type BashToolDetails is Data:
  BashToolDetails{truncation: Maybe<&2,Truncate.TruncationResult>, fullOutputPath: Maybe<&2,String>}
type FormattedOutput is Data:
  FormattedOutput{text: String, details: Maybe<&2,BashToolDetails>}
type OperationError is Data:
  Aborted{}
  TimedOut{seconds: F64}
  Operation{message: String}
  Native{errors: List<&2,Child.Error>}
  ShellError{cause: Shell.Error}
type Error is Data:
  InvalidArguments{}
  OutputError{cause: Output.Error}
  ExecutionError{cause: OperationError, output: String}
  ExitError{code: Maybe<&2,U32>, output: String}
type BashExecutionInput is Data:
  BashExecutionInput{command: String, cwd: String, onData: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeout: Maybe<&2,F64>, env: Maybe<&2,Shell.Environment()>}
type BashOperations is Data:
  BashOperations{exec: C.Callback<BashExecutionInput,Result<&2,&2,OperationError,Maybe<&2,U32>>>}
type BashSpawnContext is Data:
  BashSpawnContext{command: String, cwd: String, env: Shell.Environment()}
# Extension/session adapters supply values, not a JS session-manager object.
type BashContext is Data:
  BashContext{cwd: Maybe<&2,String>, sessionId: Maybe<&2,String>, sessionFile: Maybe<&2,String>, provider: Maybe<&2,String>, model: Maybe<&2,String>, thinkingLevel: Maybe<&2,String>}
type BashToolOptions is Data:
  BashToolOptions{operations: Maybe<&2,BashOperations>, commandPrefix: Maybe<&2,String>, shellPath: Maybe<&2,String>, exposeSessionEnvironment: Maybe<&2,Bool>, spawnHook: Maybe<&2,C.Callback<BashSpawnContext,Result<&2,&2,OperationError,BashSpawnContext>>>}
type LocalShell is Data:
  LocalShell{binDir: String, shellPath: Maybe<&2,String>}
# Injected operations may retain onData until the tool is disposed. Closed
# gates retain no output, and serialize retirement with in-flight appends.
type OutputConsumer is Type:
  OutputConsumer{gate: Serial.Owner<Maybe<&2,Output.StreamHandle>>, callback: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}
def Consumers() -> Type: List<&1,OutputConsumer>
type Invocation is Data:
  Invocation{binDir: String, cwd: String, options: BashToolOptions, operations: BashOperations, consumers: Maybe<&2,Ref.Ref<Consumers()>>}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,BashToolDetails>,Error>, ownedOperations: Maybe<&2,BashOperations>, consumers: Ref.Ref<Consumers()>}

def ToolResult() -> Data: Result<&2,&2,Error,Agent.AgentToolResult<Maybe<&2,BashToolDetails>>>
def defaults() -> BashToolOptions: BashToolOptions{None{},None{},None{},None{},None{}}
def noContext() -> BashContext: BashContext{None{},None{},None{},None{},None{},None{}}

def nativeMessages(values: List<&2,Child.Error>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case Child.Error{operation,code,message} <> rest:
      (operation ++ ": " ++ message ++ " (" ++ U32.show(code) ++ ")") <> nativeMessages(rest)

def shellMessage(cause: Shell.Error) -> String:
  match cause:
    case Shell.CustomShellNotFound{path}: "Custom shell path not found: " ++ path
    case Shell.InvalidEnvironment{_}: "Invalid shell environment entry"
    case Shell.DuplicateVariable{name}: "Duplicate shell environment variable: " ++ name

def operationMessage(cause: OperationError) -> String:
  match cause:
    case Aborted{}: "Command aborted"
    case TimedOut{seconds}: "Command timed out after " ++ Maybe.default(&2,String,F.toDecimal(seconds),"unknown") ++ " seconds"
    case Operation{message}: message
    case Native{errors}: String.join(nativeMessages(errors),"; ")
    case ShellError{cause}: shellMessage(cause)

def outputMessage(cause: Output.Error) -> String:
  match cause:
    case Output.Finished{}: "Output accumulator is finished"
    case Output.Closed{}: "Output accumulator is closed"
    case Output.InvalidByte{value}: "Invalid output byte: " ++ U32.show(value)
    case Output.System{operation,code,message}: operation ++ ": " ++ message ++ " (" ++ U32.show(code) ++ ")"
    case Output.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close

def appendStatus(text: String, status: String) -> String:
  match text:
    case "": status
    case value: value ++ "\n\n" ++ status

def exitMessage(code: Maybe<&2,U32>) -> String:
  match code:
    case None{}: "Command terminated without an exit code"
    case Some{value}: "Command exited with code " ++ U32.show(value)

def errorMessage(cause: Error) -> String:
  match cause:
    case InvalidArguments{}: "Bash tool input is invalid. Expected a command and optional numeric timeout."
    case OutputError{cause}: outputMessage(cause)
    case ExecutionError{Aborted{},text}: appendStatus(text,"Command aborted")
    case ExecutionError{TimedOut{seconds},text}: appendStatus(text,operationMessage(TimedOut{seconds}))
    case ExecutionError{cause,_}: operationMessage(cause)
    case ExitError{code,text}: appendStatus(text,exitMessage(code))

def parameters(command: Maybe<&2,Value.Value>, timeout: Maybe<&2,Value.Value>) -> Result<&2,&2,Error,BashToolInput>:
  match command timeout:
    case Some{Value.Text{text}} None{}: Done{BashToolInput{text,None{}}}
    case Some{Value.Text{text}} Some{Value.Number{seconds}}: Done{BashToolInput{text,Some{seconds}}}
    case _ _: Fail{InvalidArguments{}}

def parseInput(value: Value.Value) -> Result<&2,&2,Error,BashToolInput>:
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value,fields,"command"),Record.get(Value.Value,fields,"timeout"))
    case _: Fail{InvalidArguments{}}

def parameter(kind: String, description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{kind}} <> Record.Property{"description",Value.Text{description}} <> Nil{}}}

def bashSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{
    Record.Property{"type",Value.Text{"object"}} <>
    Record.Property{"properties",Value.ObjectValue{Record.Record{
      Record.Property{"command",parameter("string","Shell command to execute")} <>
      Record.Property{"timeout",parameter("number","Timeout in seconds (optional, no default timeout)")} <> Nil{}}}} <>
    Record.Property{"required",Value.ArrayValue{Value.Text{"command"} <> Nil{}}} <> Nil{}}}

def sessionName(name: String) -> Bool:
  match name:
    case "PI_SESSION_ID": True{}
    case "PI_SESSION_FILE": True{}
    case "PI_PROVIDER": True{}
    case "PI_MODEL": True{}
    case "PI_REASONING_LEVEL": True{}
    case _: False{}

def clearSession(environment: Shell.Environment()) -> Shell.Environment():
  match environment:
    case Nil{}: Nil{}
    case Shell.Variable{+name,+value} <> +rest:
      Bool.pick(Unit -> Shell.Environment(),sessionName(name),_ => clearSession(rest),_ => Shell.Variable{name,value} <> clearSession(rest))(Unit{})

def withVariable(name: String, value: Maybe<&2,String>, environment: Shell.Environment()) -> Shell.Environment():
  match value:
    case None{}: environment
    case Some{value}: Shell.updateEnvironment(name,value,environment,Nil{})

def sessionEnvironment(expose: Bool, context: BashContext, environment: Shell.Environment()) -> Shell.Environment():
  match expose context:
    case False{} _: clearSession(environment)
    case True{} BashContext{_,session,file,provider,model,thinking}:
      withVariable("PI_REASONING_LEVEL",thinking,withVariable("PI_MODEL",model,withVariable("PI_PROVIDER",provider,
        withVariable("PI_SESSION_FILE",file,withVariable("PI_SESSION_ID",session,clearSession(environment))))))

def prefixed(command: String, prefix: Maybe<&2,String>) -> String:
  match prefix:
    case None{}: command
    case Some{""}: command
    case Some{value}: value ++ "\n" ++ command

def contextCwd(fallback: String, context: BashContext) -> String:
  match context:
    case BashContext{Some{SCon{first,rest}},_,_,_,_,_}: SCon{first,rest}
    case _: fallback

def resultContent(text: String, details: Maybe<&2,BashToolDetails>) -> Agent.AgentToolResult<Maybe<&2,BashToolDetails>>:
  Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},details,None{},None{}}

def updateDetails(truncation: Truncate.TruncationResult, path: Maybe<&2,String>) -> BashToolDetails:
  match truncation:
    case Truncate.TruncationResult{content,+truncated,cause,totalLines,totalBytes,lines,bytes,partial,first,maxLines,maxBytes}:
      BashToolDetails{Bool.pick(Maybe<&2,Truncate.TruncationResult>,truncated,Some{Truncate.TruncationResult{content,truncated,cause,totalLines,totalBytes,lines,bytes,partial,first,maxLines,maxBytes}},None{}),path}

def publish(callback: Agent.AgentToolUpdateCallback(Maybe<&2,BashToolDetails>), snapshot: Output.OutputSnapshot) -> IO(Unit):
  match snapshot:
    case Output.OutputSnapshot{content,truncation,path}:
      C.call(Agent.AgentToolResult<Maybe<&2,BashToolDetails>>,Unit,callback,resultContent(content,Some{updateDetails(truncation,path)}))

def lineLimit(cause: Maybe<&2,Truncate.Limit>) -> String:
  match cause:
    case Some{Truncate.Lines{}}: ""
    case _: " (" ++ Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit)"

def truncationNote(lastLine: Nat, path: Maybe<&2,String>, result: Truncate.TruncationResult) -> String:
  match result:
    case Truncate.TruncationResult{_,_,cause,+total,_,+lines,bytes,partial,_,_,_}:
      +location = Maybe.default(&2,String,path,"undefined")
      +range = Nat.show(total - lines + 1n) ++ "-" ++ Nat.show(total) ++ " of " ++ Nat.show(total)
      Bool.pick(String,partial,
        "\n\n[Showing last " ++ Truncate.formatSize(bytes) ++ " of line " ++ Nat.show(total) ++ " (line is " ++ Truncate.formatSize(lastLine) ++ "). Full output: " ++ location ++ "]",
        "\n\n[Showing lines " ++ range ++ lineLimit(cause) ++ ". Full output: " ++ location ++ "]")

def formatted(lastLine: Nat, text: String, truncation: Truncate.TruncationResult, +path: Maybe<&2,String>) -> FormattedOutput:
  match truncation:
    case Truncate.TruncationResult{content,True{},cause,total,bytes,lines,output,partial,first,maxLines,maxBytes}:
      +truncation = {Truncate.TruncationResult{content,True{},cause,total,bytes,lines,output,partial,first,maxLines,maxBytes} : Truncate.TruncationResult}
      FormattedOutput{text ++ truncationNote(lastLine,path,truncation),Some{BashToolDetails{Some{truncation},path}}}
    case _: FormattedOutput{text,None{}}

def formatOutput(lastLine: Nat, empty: String, snapshot: Output.OutputSnapshot) -> FormattedOutput:
  match snapshot:
    case Output.OutputSnapshot{+content,+truncation,+path}:
      formatted(lastLine,Bool.pick(String,String.eq(content,""),empty,content),truncation,path)


def timeoutMessage(value: Maybe<&2,F64>) -> String:
  match value:
    case Some{+seconds}:
      Bool.pick(String,F64.is_gt(seconds,F.fromU32(0)) && F64.is_lt(seconds,F.infinity(False{})) && F64.is_gt(F64.mul(seconds,F.fromU32(1000)),F.fromU32(2147483647)),
        "Invalid timeout: maximum is 2147483.647 seconds","Invalid timeout: must be a finite number of seconds")
    case None{}: "Invalid timeout: must be a finite number of seconds"

def executed(timeout: Maybe<&2,F64>, result: Result<&2,&2,Child.ExecutionError,U32>) -> Result<&2,&2,OperationError,Maybe<&2,U32>>:
  match result:
    case Done{code}: Done{Some{code}}
    case Fail{Child.InvalidTimeout{}}: Fail{Operation{timeoutMessage(timeout)}}
    case Fail{Child.ExecutionAborted{}}: Fail{Aborted{}}
    case Fail{Child.ExecutionTimedOut{}}: Fail{TimedOut{Maybe.default(&2,F64,timeout,F.fromU32(0))}}
    case Fail{Child.ExecutionFailed{errors}}: Fail{Native{errors}}

def processArguments(values: List<&2,String>) -> List<String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> processArguments(rest)

def executeShell(shell: Shell.ShellConfig, input: BashExecutionInput, environment: Shell.Environment()) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match shell input:
    case Shell.ShellConfig{path,args,Some{Shell.Stdin{}}} BashExecutionInput{command,cwd,onData,signal,+timeout,_}:
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        result : Result<&2,&2,Child.ExecutionError,U32> <- Child.executeStdin(path,processArguments(args),command,cwd,Shell.toEntries(environment),signal,timeout,onData)
        return executed(timeout,result)
    case Shell.ShellConfig{path,args,_} BashExecutionInput{command,cwd,onData,signal,+timeout,_}:
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        result : Result<&2,&2,Child.ExecutionError,U32> <- Child.execute(path,processArguments(args),command,cwd,Shell.toEntries(environment),signal,timeout,onData)
        return executed(timeout,result)

def loadedEnvironment(shell: Shell.ShellConfig, input: BashExecutionInput, loaded: Result<&2,&2,Shell.Error,Shell.Environment()>) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,OperationError,Maybe<&2,U32>>,Fail{ShellError{cause}})
    case Done{env}: executeShell(shell,input,env)

def localEnvironment(binDir: String, shell: Shell.ShellConfig, +input: BashExecutionInput) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match input:
    case BashExecutionInput{_,_,_,_,_,Some{env}}: executeShell(shell,input,env)
    case BashExecutionInput{_,_,_,_,_,None{}}:
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        loaded : Result<&2,&2,Shell.Error,Shell.Environment()> <- Shell.loadShellEnv(binDir)
        loadedEnvironment(shell,input,loaded)

def checkedDirectory(binDir: String, shell: Shell.ShellConfig, input: BashExecutionInput, cwd: String, accessible: Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match accessible:
    case Fail{_}: IO.pure(Result<&2,&2,OperationError,Maybe<&2,U32>>,Fail{Operation{"Working directory does not exist: " ++ cwd ++ "\nCannot execute bash commands."}})
    case Done{Unit{}}: localEnvironment(binDir,shell,input)

def executionDirectory(input: BashExecutionInput) -> String:
  match input:
    case BashExecutionInput{_,cwd,_,_,_,_}: cwd

def executionSignal(input: BashExecutionInput) -> Maybe<&2,Abort.AbortSignal<Unit>>:
  match input:
    case BashExecutionInput{_,_,_,signal,_,_}: signal

def executionTimeout(input: BashExecutionInput) -> Maybe<&2,F64>:
  match input:
    case BashExecutionInput{_,_,_,_,timeout,_}: timeout

def selectedShell(binDir: String, +input: BashExecutionInput, selection: Result<&2,&2,Shell.Error,Shell.ShellConfig>) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match selection:
    case Fail{cause}: IO.pure(Result<&2,&2,OperationError,Maybe<&2,U32>>,Fail{ShellError{cause}})
    case Done{shell}:
      +cwd = executionDirectory(input)
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        accessible : Result<&1,&1,U32 & String,Unit> <- File.access(cwd,0)
        checkedDirectory(binDir,shell,input,cwd,accessible)

def selectUnlessAborted(environment: LocalShell, input: BashExecutionInput, aborted: Bool) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match environment aborted:
    case _ True{}: IO.pure(Result<&2,&2,OperationError,Maybe<&2,U32>>,Fail{Aborted{}})
    case LocalShell{binDir,path} False{}:
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        shell : Result<&2,&2,Shell.Error,Shell.ShellConfig> <- Shell.getShellConfig(path)
        selectedShell(binDir,input,shell)

def validatedExecution(environment: LocalShell, +input: BashExecutionInput, valid: Result<&2,&2,Child.ExecutionError,Maybe<&2,U32>>) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  match valid:
    case Fail{_}:
      IO.pure(Result<&2,&2,OperationError,Maybe<&2,U32>>,Fail{Operation{timeoutMessage(executionTimeout(input))}})
    case Done{_}:
      do IO<Result<&2,&2,OperationError,Maybe<&2,U32>>>:
        aborted : Bool <- Child.parentAborted(executionSignal(input))
        selectUnlessAborted(environment,input,aborted)

def localExec(environment: LocalShell, input: BashExecutionInput) -> IO(Result<&2,&2,OperationError,Maybe<&2,U32>>):
  +request = input
  validatedExecution(environment,request,Child.optionalTimeout(executionTimeout(request)))

def createLocalBashOperations(binDir: String, shellPath: Maybe<&2,String>) -> IO(BashOperations):
  do IO<BashOperations>:
    callback : C.Callback<BashExecutionInput,Result<&2,&2,OperationError,Maybe<&2,U32>>> <- C.create(~LocalShell,~BashExecutionInput,~Result<&2,&2,OperationError,Maybe<&2,U32>>,~localExec,LocalShell{binDir,shellPath})
    return BashOperations{callback}

def disposeOperations(operations: BashOperations) -> IO(Unit):
  match operations:
    case BashOperations{callback}: C.dispose(BashExecutionInput,Result<&2,&2,OperationError,Maybe<&2,U32>>,callback)

def finalResult(result: Result<&2,&2,OperationError,Maybe<&2,U32>>, formatted: FormattedOutput) -> ToolResult():
  match result formatted:
    case Fail{cause} FormattedOutput{text,_}: Fail{ExecutionError{cause,text}}
    case Done{Some{0}} FormattedOutput{text,details}: Done{resultContent(text,details)}
    case Done{code} FormattedOutput{text,_}: Fail{ExitError{code,text}}

def finishResult(+result: Result<&2,&2,OperationError,Maybe<&2,U32>>, output: Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat>) -> ToolResult():
  match result output:
    case _ Fail{cause}: Fail{OutputError{cause}}
    case Fail{_} Done{Tuple{snapshot,lastLine}}: finalResult(result,formatOutput(lastLine,"",snapshot))
    case Done{_} Done{Tuple{snapshot,lastLine}}: finalResult(result,formatOutput(lastLine,"(no output)",snapshot))

def appendResult(result: Result<&2,&2,Output.Error,Unit>) -> Result<&2,&2,String,Unit>:
  match result:
    case Done{Unit{}}: Done{Unit{}}
    case Fail{cause}: Fail{outputMessage(cause)}

def appendAccepted(bytes: List<&2,U32>, gate: Maybe<&2,Output.StreamHandle>) -> IO(Maybe<&2,Output.StreamHandle> & Result<&2,&2,String,Unit>):
  match gate:
    case None{}: IO.pure(Maybe<&2,Output.StreamHandle> & Result<&2,&2,String,Unit>,(None{},Done{Unit{}}))
    case Some{+handle}:
      do IO<Maybe<&2,Output.StreamHandle> & Result<&2,&2,String,Unit>>:
        result : Result<&2,&2,Output.Error,Unit> <- Output.appendStream(handle,bytes)
        return (Some{handle},appendResult(result))

def acceptOutput(gate: Serial.Handle<Maybe<&2,Output.StreamHandle>>, bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  Serial.run(Maybe<&2,Output.StreamHandle>,Result<&2,&2,String,Unit>,gate,value => appendAccepted(bytes,value))

def stopOutput(gate: Maybe<&2,Output.StreamHandle>) -> IO(Maybe<&2,Output.StreamHandle> & Unit):
  IO.pure(Maybe<&2,Output.StreamHandle> & Unit,(None{},Unit{}))

def publication(update: Maybe<&2,Agent.AgentToolUpdateCallback(Maybe<&2,BashToolDetails>)>) -> IO(Maybe<&2,C.Callback<Output.OutputSnapshot,Unit>>):
  match update:
    case None{}: IO.pure(Maybe<&2,C.Callback<Output.OutputSnapshot,Unit>>,None{})
    case Some{+callback}:
      do IO<Maybe<&2,C.Callback<Output.OutputSnapshot,Unit>>>:
        C.call(Agent.AgentToolResult<Maybe<&2,BashToolDetails>>,Unit,callback,Agent.AgentToolResult{Nil{},None{},None{},None{}})
        bridge : C.Callback<Output.OutputSnapshot,Unit> <- C.create(~Agent.AgentToolUpdateCallback(Maybe<&2,BashToolDetails>),~Output.OutputSnapshot,~Unit,~publish,callback)
        return Some{bridge}

def disposePublication(publication: Maybe<&2,C.Callback<Output.OutputSnapshot,Unit>>) -> IO(Unit):
  match publication:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.dispose(Output.OutputSnapshot,Unit,callback)

def retainConsumer(registry: Maybe<&2,Ref.Ref<Consumers()>>, consumer: OutputConsumer) -> IO(Unit):
  match registry consumer:
    case Some{registry} value: Ref.modify(Consumers(),Unit,registry,previous => (value <> previous,Unit{}))
    case None{} OutputConsumer{gate,callback}:
      do IO<Unit>:
        C.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
        retired : Maybe<&2,Output.StreamHandle> <- Serial.retire(Maybe<&2,Output.StreamHandle>,gate)
        return Unit{}

def executeObserved(operations: BashOperations, spawn: BashSpawnContext, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeout: Maybe<&2,F64>, consumers: Maybe<&2,Ref.Ref<Consumers()>>, owner: Output.StreamOwner, gate: Serial.Owner<Maybe<&2,Output.StreamHandle>> & Serial.Handle<Maybe<&2,Output.StreamHandle>>) -> IO(ToolResult()):
  match operations spawn gate:
    case BashOperations{exec} BashSpawnContext{command,cwd,env} Tuple{gateOwner,+handle}:
      do IO<ToolResult()>:
        +onData : C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- C.create(~Serial.Handle<Maybe<&2,Output.StreamHandle>>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~acceptOutput,handle)
        result : Result<&2,&2,OperationError,Maybe<&2,U32>> <- C.call(BashExecutionInput,Result<&2,&2,OperationError,Maybe<&2,U32>>,exec,BashExecutionInput{command,cwd,onData,signal,timeout,Some{env}})
        Serial.run(Maybe<&2,Output.StreamHandle>,Unit,handle,stopOutput)
        retainConsumer(consumers,OutputConsumer{gateOwner,onData})
        output : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        return finishResult(result,output)

def runOwned(operations: BashOperations, spawn: BashSpawnContext, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeout: Maybe<&2,F64>, consumers: Maybe<&2,Ref.Ref<Consumers()>>, stream: Output.StreamOwner & Output.StreamHandle) -> IO(ToolResult()):
  match stream:
    case (owner,handle):
      do IO<ToolResult()>:
        gate : Serial.Owner<Maybe<&2,Output.StreamHandle>> <- Serial.create(Maybe<&2,Output.StreamHandle>,Some{handle})
        executeObserved(operations,spawn,signal,timeout,consumers,owner,Serial.borrow(Maybe<&2,Output.StreamHandle>,gate))

def runPrepared(consumers: Maybe<&2,Ref.Ref<Consumers()>>, operations: BashOperations, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeout: Maybe<&2,F64>, update: Maybe<&2,Agent.AgentToolUpdateCallback(Maybe<&2,BashToolDetails>)>, spawn: Result<&2,&2,OperationError,BashSpawnContext>) -> IO(ToolResult()):
  match spawn:
    case Fail{cause}: IO.pure(ToolResult(),Fail{ExecutionError{cause,""}})
    case Done{context}:
      do IO<ToolResult()>:
        +observer : Maybe<&2,C.Callback<Output.OutputSnapshot,Unit>> <- publication(update)
        stream : Output.StreamOwner <- Output.createStream(Output.OutputAccumulatorOptions{None{},None{},Some{"pi-bash"}},observer)
        result : ToolResult() <- runOwned(operations,context,signal,timeout,consumers,Output.borrowStream(stream))
        disposePublication(observer)
        return result

def applyHook(hook: Maybe<&2,C.Callback<BashSpawnContext,Result<&2,&2,OperationError,BashSpawnContext>>>, context: BashSpawnContext) -> IO(Result<&2,&2,OperationError,BashSpawnContext>):
  match hook:
    case None{}: IO.pure(Result<&2,&2,OperationError,BashSpawnContext>,Done{context})
    case Some{callback}: C.call(BashSpawnContext,Result<&2,&2,OperationError,BashSpawnContext>,callback,context)

def preparedContext(cwd: String, command: String, options: BashToolOptions, +context: BashContext, environment: Result<&2,&2,Shell.Error,Shell.Environment()>) -> IO(Result<&2,&2,OperationError,BashSpawnContext>):
  match options environment:
    case _ Fail{cause}: IO.pure(Result<&2,&2,OperationError,BashSpawnContext>,Fail{ShellError{cause}})
    case BashToolOptions{_,prefix,_,expose,hook} Done{env}:
      applyHook(hook,BashSpawnContext{prefixed(command,prefix),contextCwd(cwd,context),sessionEnvironment(Maybe.default(&2,Bool,expose,True{}),context,env)})

def invokeInput(invocation: Invocation, context: BashContext, signal: Maybe<&2,Abort.AbortSignal<Unit>>, update: Maybe<&2,Agent.AgentToolUpdateCallback(Maybe<&2,BashToolDetails>)>, input: Result<&2,&2,Error,BashToolInput>) -> IO(ToolResult()):
  match invocation input:
    case _ Fail{cause}: IO.pure(ToolResult(),Fail{cause})
    case Invocation{binDir,cwd,options,operations,consumers} Done{BashToolInput{command,timeout}}:
      do IO<ToolResult()>:
        env : Result<&2,&2,Shell.Error,Shell.Environment()> <- Shell.loadShellEnv(binDir)
        spawn : Result<&2,&2,OperationError,BashSpawnContext> <- preparedContext(cwd,command,options,context,env)
        runPrepared(consumers,operations,signal,timeout,update,spawn)

def invokeWithContext(invocation: Invocation, context: BashContext, request: Agent.ToolExecutionInput<Maybe<&2,BashToolDetails>>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,params,signal,update}: invokeInput(invocation,context,signal,update,parseInput(params))

# upstream wrapToolDefinition: the registered tool reads the session's
# context when it runs, for its cwd and PI_* variables; without a bound
# session it keeps its own cwd and sets none.
type Registered is Data: Registered{invocation: Invocation, source: Ctx.ContextSource()}
def modelField(model: Maybe<&2,Ai.Model<Ai.JsonValue>>, provider: Bool) -> Maybe<&2,String>:
  match model:
    case None{}: None{}
    case Some{Ai.Model{id,_,_,owner,_,_,_,_,_,_,_,_,_,_,_,_}}: Some{Bool.pick(String,provider,owner,id)}
def toolContext(context: Maybe<&2,Ctx.ExtensionContext>) -> BashContext:
  match context:
    case None{}: noContext()
    case Some{Ctx.ExtensionContext{cwd,+model,session,file,thinking}}: BashContext{Some{cwd},Some{session},file,modelField(model,True{}),modelField(model,False{}),Some{Levels.name(thinking)}}
def invoke(registered: Registered, request: Agent.ToolExecutionInput<Maybe<&2,BashToolDetails>>) -> IO(ToolResult()):
  match registered:
    case Registered{invocation,source}:
      do IO<ToolResult()>:
        context : Maybe<&2,Ctx.ExtensionContext> <- Ctx.current(source)
        invokeWithContext(invocation,toolContext(context),request)

def created(invocation: Registered, owned: Maybe<&2,BashOperations>, consumers: Ref.Ref<Consumers()>) -> IO(ToolOwner):
  do IO<ToolOwner>:
    callback : C.Callback<Agent.ToolExecutionInput<Maybe<&2,BashToolDetails>>,ToolResult()> <- C.create(~Registered,~Agent.ToolExecutionInput<Maybe<&2,BashToolDetails>>,~ToolResult(),~invoke,invocation)
    return ToolOwner{Agent.AgentTool{"bash","Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",bashSchema(),Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"bash",None{},callback,None{},None{}},owned,consumers}

# The managed binary directory is an explicit runtime/configuration dependency.
# Injected operations and hooks remain borrowed; default operations are owned.
def createWithConsumers(+binDir: String, cwd: String, +options: BashToolOptions, +consumers: Ref.Ref<Consumers()>, source: Ctx.ContextSource()) -> IO(ToolOwner):
  match options:
    case BashToolOptions{Some{operations},_,_,_,_}: created(Registered{Invocation{binDir,cwd,options,operations,Some{consumers}},source},None{},consumers)
    case BashToolOptions{None{},_,shellPath,_,_}:
      do IO<ToolOwner>:
        +operations : BashOperations <- createLocalBashOperations(binDir,shellPath)
        created(Registered{Invocation{binDir,cwd,options,operations,None{}},source},Some{operations},consumers)

def createBashTool(binDir: String, cwd: String, options: BashToolOptions, source: Ctx.ContextSource()) -> IO(ToolOwner):
  do IO<ToolOwner>:
    consumers : Ref.Ref<Consumers()> <- Ref.new(Consumers(),Nil{})
    createWithConsumers(binDir,cwd,options,consumers,source)

def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Maybe<&2,BashToolDetails>,Error>:
  match owner:
    case ToolOwner{+tool,operations,consumers}: (ToolOwner{tool,operations,consumers},tool)

def disposeOwned(operations: Maybe<&2,BashOperations>) -> IO(Unit):
  match operations:
    case None{}: IO.pure(Unit,Unit{})
    case Some{operations}: disposeOperations(operations)

def disposeConsumers(values: Consumers()) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case OutputConsumer{gate,callback} <> rest:
      do IO<Unit>:
        C.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
        retired : Maybe<&2,Output.StreamHandle> <- Serial.retire(Maybe<&2,Output.StreamHandle>,gate)
        disposeConsumers(rest)

# As with other tool callbacks, callers retire borrowed aliases before disposal.
def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_},operations,consumers}:
      do IO<Unit>:
        C.dispose(Agent.ToolExecutionInput<Maybe<&2,BashToolDetails>>,ToolResult(),callback)
        disposeOwned(operations)
        retained : Consumers() <- Ref.dispose(Consumers(),consumers)
        disposeConsumers(retained)
