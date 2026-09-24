import Base
import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/agent/src/types.bend as AgentTypes
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ./model-runtime-fixture.bend as ModelFixture
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/run.bend as Run

# A real mounted runner with an unused provider; the PTY drives only theme
# queries, scheme notifications, rendering and /exit.
def Input() -> Data: AgentTypes.StreamInput<Unit,Tools.ToolDetails,Runtime.LoopConfig()>
def Output() -> Type: Result<&2,&1,Tools.ToolError,AgentTypes.StreamLease<Unit,Tools.ToolError>>
def unusedProvider(_: Unit,_: Input()) -> IO(Output()): IO.die(Output(),1,"unexpected prompt")
def model() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"theme-fixture","Theme fixture",Ai.OpenAIResponsesApi{},"fixture","https://invalid.local",False{},None{},Ai.InputText{} <> Nil{},None{},Ai.ModelCost{U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),None{}},None{},U32.to_f64(128000),U32.to_f64(4096),None{},None{},None{}}
def options(stream: Runtime.Stream(),converter: Runtime.Converter(),sessionId: String) -> Agent.AgentOptions<Unit,Tools.ToolDetails,Runtime.Custom(),Tools.ToolError,Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{""}, Some{model()}, Some{Ai.Off{}}, Some{Nil{}}, None{}}}, Some{converter}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{sessionId}, None{}, None{}, None{}, None{}}
def requireAgent(result: Result<&2,&2,StreamFn.MissingDefault,Runtime.Owner()>) -> IO(Runtime.Owner()):
  match result:
    case Done{owner}: IO.pure(Runtime.Owner(),owner)
    case Fail{_}: IO.die(Runtime.Owner(),1,"cannot create fixture agent")
def requireSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(),session)
    case Fail{error}: IO.die(Session.Session(),1,Sessions.message(error))
def settings(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair: case (_,manager): manager
def setting(+value: String) -> Maybe<&2,String>:
  Bool.pick(Maybe<&2,String>,String.eq(value,"-"),None{},Some{value})
def checked(result: Result<&2,&2,Run.Error,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{error}: IO.die(Unit,1,Run.errorMessage(error))
def run(args: List<String>) -> IO(Unit):
  match args:
    case assetsRoot <> +cwd <> +agentDir <> choice <> Nil{}:
      do IO<Unit>:
        created : Sessions.Outcome(Session.Session()) <- Session.memorySession(cwd,Sessions.noOptions())
        +stored : Session.Session() <- requireSession(created)
        +stream : Runtime.Stream() <- Callback.create(~Unit,~Input(),~Output(),~unusedProvider,Unit{})
        +registry : StreamFn.Registry(Unit,Tools.ToolDetails,Runtime.LoopConfig(),Tools.ToolError) <- StreamFn.create(Unit,Tools.ToolDetails,Runtime.LoopConfig(),Tools.ToolError)
        +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError,~Runtime.validationError)
        +converter : Runtime.Converter() <- Runtime.createConverter(False{})
        candidate : Result<&2,&2,StreamFn.MissingDefault,Runtime.Owner()> <- Agent.new(~Unit,~Tools.ToolDetails,~Runtime.Custom(),~Tools.ToolError,~Unit,options(stream,converter,Sessions.getSessionId(Unit,Tools.ToolDetails,Schema.Value,stored)),registry,validator,Tools.WriteDetails{})
        +agent : Runtime.Owner() <- requireAgent(candidate)
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd,agentDir,Settings.options())
        models : Models.ModelRuntime <- ModelFixture.create(Nil{})
        +session : Session.AgentSession <- Session.create(agent,stored,settings(loaded),cwd,Runtime.Loadout{Record.new(String),Nil{},Nil{},Nil{}},models,Nil{})
        result : Result<&2,&2,Run.Error,Unit> <- Run.run(session,Nil{},cwd,None{},agentDir,assetsRoot,setting(choice),model() <> Nil{})
        Session.dispose(session)
        Agent.dispose(Unit,Tools.ToolDetails,Runtime.Custom(),Tools.ToolError,Unit,agent)
        StreamFn.dispose(Unit,Tools.ToolDetails,Runtime.LoopConfig(),Tools.ToolError,registry)
        Loop.disposeValidation(Tools.ToolError,validator)
        Runtime.disposeConverter(converter)
        Callback.dispose(Input(),Output(),stream)
        checked(result)
    case _: IO.die(Unit,1,"expected assetsRoot cwd agentDir themeSetting")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
