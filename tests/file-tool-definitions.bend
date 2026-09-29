import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/context.bend as Context
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/coding-agent/src/core/tools/write.bend as Write
import ../packages/coding-agent/src/core/tools/edit.bend as Edit
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Queue
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as AuthContext
import ../packages/ai/src/auth/credential-store.bend as Credentials
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai

def arguments(fields: List<&2,Record.Property<Value.Value>>) -> Value.Value:
  Value.ObjectValue{Record.Record{fields}}

def output(value: Tools.Output()) -> String:
  match value:
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,_}} <> _,_,_,_}}: text
    case Fail{error}: "error: " ++ Tools.errorMessage(error)
    case _: "missing text result"

def call(execute: Ext.ToolExecute(), arguments: Value.Value, context: Context.ExtensionContext) -> IO(String):
  do IO<String>:
    result : Tools.Output() <- Callback.call(Ext.ToolCallInput,Tools.Output(),execute,Ext.ToolCallInput{Agent.ToolExecutionInput{"file-definition",arguments,None{},None{}},context})
    return output(result)

def requireContains(+text: String, +expected: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.contains(text,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"missing " ++ expected ++ " in " ++ String.take(text,140n)))(Unit{})

def writeFile(definition: Ext.ToolDefinition, +context: Context.ExtensionContext) -> IO(Unit):
  match definition:
    case Ext.ToolDefinition{"write","write",_,Some{_},_,_,Some{_},None{},+execute,Ext.NativeBuiltin{"write"},None{},None{},None{}}:
      do IO<Unit>:
        first : String <- call(execute,arguments(Record.Property{"path",Value.Text{"sample.txt"}} <> Record.Property{"content",Value.Text{"alpha"}} <> Nil{}),context)
        second : String <- call(execute,arguments(Record.Property{"path",Value.Text{"sample.txt"}} <> Record.Property{"content",Value.Text{"alpha beta"}} <> Nil{}),context)
        Callback.dispose(Ext.ToolCallInput,Tools.Output(),execute)
        requireContains(first,"Successfully wrote")
        requireContains(second,"Successfully wrote")
    case _: IO.die(Unit,1,"write definition shape")

def readFile(definition: Ext.ToolDefinition, context: Context.ExtensionContext, expected: String) -> IO(Unit):
  match definition:
    case Ext.ToolDefinition{"read","read",_,Some{_},_,_,Some{_},None{},+execute,Ext.NativeBuiltin{"read"},None{},None{},None{}}:
      do IO<Unit>:
        result : String <- call(execute,arguments(Record.Property{"path",Value.Text{"sample.txt"}} <> Nil{}),context)
        Callback.dispose(Ext.ToolCallInput,Tools.Output(),execute)
        requireContains(result,expected)
    case _: IO.die(Unit,1,"read definition shape")

def runPrepared(+execute: Ext.ToolExecute(), prepared: Result<&2,&2,Tools.ToolError,Value.Value>, context: Context.ExtensionContext) -> IO(Unit):
  match prepared:
    case Fail{error}:
      do IO<Unit>:
        Callback.dispose(Ext.ToolCallInput,Tools.Output(),execute)
        IO.die(Unit,1,"edit preparation: " ++ Tools.errorMessage(error))
    case Done{arguments}:
      do IO<Unit>:
        result : String <- call(execute,arguments,context)
        Callback.dispose(Ext.ToolCallInput,Tools.Output(),execute)
        requireContains(result,"Successfully replaced 1 block")

def editFile(definition: Ext.ToolDefinition, context: Context.ExtensionContext) -> IO(Unit):
  match definition:
    case Ext.ToolDefinition{"edit","edit",_,Some{_},_,_,Some{_},None{},+execute,Ext.NativeBuiltin{"edit"},None{},None{},Some{+prepare}}:
      do IO<Unit>:
        legacy : Value.Value <- IO.pure(Value.Value,arguments(Record.Property{"path",Value.Text{"sample.txt"}} <> Record.Property{"oldText",Value.Text{"beta"}} <> Record.Property{"newText",Value.Text{"gamma"}} <> Nil{}))
        prepared : Result<&2,&2,Tools.ToolError,Value.Value> <- Callback.call(Value.Value,Result<&2,&2,Tools.ToolError,Value.Value>,prepare,legacy)
        Callback.dispose(Value.Value,Result<&2,&2,Tools.ToolError,Value.Value>,prepare)
        runPrepared(execute,prepared,context)
    case _: IO.die(Unit,1,"edit definition shape")

def exercised(+cwd: String,+paths: Paths.Environment,+queue: Queue.Queue,+runtime: Models.ModelRuntime,+bindings: Ref.Ref<Context.Bindings>) -> IO(Unit):
  +context = {Context.ExtensionContext{cwd,runtime,bindings}: Context.ExtensionContext}
  +fallback = cwd ++ "/definition-fallback"
  do IO<Unit>:
    write : Ext.ToolDefinition <- Loader.createWriteToolDefinition(paths,queue,fallback,Write.WriteToolOptions{None{}})
    writeFile(write,context)
    edit : Ext.ToolDefinition <- Loader.createEditToolDefinition(paths,queue,fallback,Edit.EditToolOptions{None{}})
    editFile(edit,context)
    read : Ext.ToolDefinition <- Loader.createReadToolDefinition(paths,fallback,Read.ReadToolOptions{None{},None{},None{},None{}})
    readFile(read,context,"alpha gamma")

def exercisedWithQueue(cwd: String,paths: Paths.Environment,pair: Queue.Owner & Queue.Queue,runtime: Models.ModelRuntime,bindings: Ref.Ref<Context.Bindings>) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        exercised(cwd,paths,handle,runtime,bindings)
        Queue.dispose(owner)

def run(+cwd: String) -> IO(Unit):
  +paths = {Paths.Environment{cwd,cwd,Runtime.urlContext()}: Paths.Environment}
  do IO<Unit>:
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +authContext : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders(Nil{},store,authContext)
    +bindings : Ref.Ref<Context.Bindings> <- Ref.new(Context.Bindings,Context.unbound())
    queue : Queue.Owner <- Queue.create()
    exercisedWithQueue(cwd,paths,Queue.borrow(queue),runtime,bindings)
    Models.dispose(runtime)
    unused : Context.Bindings <- Ref.dispose(Context.Bindings,bindings)
    IO.print("ok file tool definitions")

def main() -> IO(Unit):
  do IO<Unit>:
    current : Result<&2,&2,FS.Error,String> <- FS.cwd()
    run(Result.default(&2,&2,FS.Error,String,current,"."))
