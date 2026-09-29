import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/context.bend as Context
import ../packages/coding-agent/src/core/tools/grep.bend as Grep
import ../packages/coding-agent/src/core/tools/find.bend as Find
import ../packages/coding-agent/src/core/tools/ls.bend as Ls
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/utils/tools-manager.bend as Manager
import ../packages/runtime/src/collation.bend as Collation
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as AuthContext
import ../packages/ai/src/auth/credential-store.bend as Credentials
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai

def output(value: Tools.Output()) -> String:
  match value:
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,_}} <> _,_,_,_}}: text
    case Fail{error}: "error: " ++ Tools.errorMessage(error)
    case _: "missing text result"

def checked(definition: Ext.ToolDefinition, +expected: String, +arguments: Value.Value, +needle: String, +context: Context.ExtensionContext) -> IO(Unit):
  match definition:
    case Ext.ToolDefinition{name,label,_,Some{_},_,_,None{},None{},+execute,Ext.NativeBuiltin{renderName},None{},None{},None{}}:
      do IO<Unit>:
        result : Tools.Output() <- Callback.call(Ext.ToolCallInput,Tools.Output(),execute,Ext.ToolCallInput{Agent.ToolExecutionInput{"search-definition",arguments,None{},None{}},context})
        repeated : Tools.Output() <- Callback.call(Ext.ToolCallInput,Tools.Output(),execute,Ext.ToolCallInput{Agent.ToolExecutionInput{"search-definition-repeat",arguments,None{},None{}},context})
        Callback.dispose(Ext.ToolCallInput,Tools.Output(),execute)
        +text : String <- IO.pure(String,output(result))
        Bool.pick(Unit -> IO(Unit),String.eq(name,expected) && String.eq(label,expected) && String.eq(renderName,expected) && String.contains(text,needle) && String.contains(output(repeated),needle),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"search definition " ++ expected ++ ": " ++ String.take(text,120n)))(Unit{})
    case _: IO.die(Unit,1,"search definition shape")

def args(key: String,value: String,second: String,extra: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{key,Value.Text{value}} <> Record.Property{second,Value.Text{extra}} <> Nil{}}}

def withCollator(paths: Paths.Environment,cwd: String,context: Context.ExtensionContext,loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(Unit):
  match loaded:
    case Fail{_}: IO.die(Unit,1,"ls collation data missing")
    case Done{collator}:
      do IO<Unit>:
        definition : Ext.ToolDefinition <- Loader.createLsToolDefinition(collator,paths,cwd,Ls.LsToolOptions{None{}})
        checked(definition,"ls",Value.ObjectValue{Record.Record{Record.Property{"path",Value.Text{"packages/coding-agent/src/core/extensions"}} <> Nil{}}},"loader.bend",context)

def exercised(+cwd: String,+paths: Paths.Environment,+manager: Manager.ToolsManager,+runtime: Models.ModelRuntime,+bindings: Ref.Ref<Context.Bindings>) -> IO(Unit):
  +context = {Context.ExtensionContext{cwd,runtime,bindings}: Context.ExtensionContext}
  do IO<Unit>:
    grep : Ext.ToolDefinition <- Loader.createGrepToolDefinition(paths,manager,cwd,Grep.GrepToolOptions{None{}})
    checked(grep,"grep",args("pattern","def builtinDefinition","path","packages/coding-agent/src/core/extensions/loader.bend"),"loader.bend",context)
    find : Ext.ToolDefinition <- Loader.createFindToolDefinition(paths,manager,cwd,Find.FindToolOptions{None{}})
    checked(find,"find",args("pattern","search-tool-definitions.bend","path","tests"),"search-tool-definitions.bend",context)
    loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(Path.join(cwd,"packages/runtime/data"))
    withCollator(paths,cwd,context,loaded)

def run(+cwd: String,+home: String) -> IO(Unit):
  +paths = {Paths.Environment{cwd,home,Runtime.urlContext()}: Paths.Environment}
  +manager = {Manager.ToolsManager{Path.join(home,".pi/agent/bin"),Runtime.urlContext(),None{}}: Manager.ToolsManager}
  do IO<Unit>:
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +authContext : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders(Nil{},store,authContext)
    +bindings : Ref.Ref<Context.Bindings> <- Ref.new(Context.Bindings,Context.unbound())
    exercised(cwd,paths,manager,runtime,bindings)
    Models.dispose(runtime)
    unused : Context.Bindings <- Ref.dispose(Context.Bindings,bindings)
    IO.print("ok search tool definitions")

def main() -> IO(Unit):
  do IO<Unit>:
    current : Result<&2,&2,FS.Error,String> <- FS.cwd()
    home : Result<&2,&2,FS.Error,String> <- FS.homedir()
    run(Result.default(&2,&2,FS.Error,String,current,"."),Result.default(&2,&2,FS.Error,String,home,"."))
