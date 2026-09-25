import Base
import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/agent/src/types.bend as AgentTypes
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/event-stream.bend as Stream
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/fetch.bend as Fetch
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

# The faux provider keeps a real prompt active long enough to steer, dequeue,
# and interrupt it through the mounted terminal.
def Input() -> Data: AgentTypes.StreamInput<Unit,Tools.ToolDetails,Runtime.LoopConfig()>
def Output() -> Type: Result<&2,&1,Tools.ToolError,AgentTypes.StreamLease<Unit,Tools.ToolError>>
def response(text: String,now: F64) -> Ai.AssistantMessage<Schema.Value,Unit>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Nil{},"openai-responses","fixture","theme-fixture",None{},None{},None{},None{},Agent.emptyUsage(),Ai.Stop{},None{},None{},None{},None{},now}
def signalOfOptions(options: Ai.SimpleStreamOptions<Ai.JsonValue,Abort.AbortSignal<Unit>,Unit,Fetch.Fetch(Unit),Tools.ToolError>) -> Maybe<&2,Abort.AbortSignal<Unit>>:
  match options:
    case Ai.SimpleStreamOptions{signal,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: signal
def signalOfConfig(config: Runtime.LoopConfig()) -> Maybe<&2,Abort.AbortSignal<Unit>>:
  match config:
    case AgentTypes.AgentLoopConfig{options,_,_,_,_,_,_,_,_,_,_,_,_}: signalOfOptions(options)
def signalOf(input: Input()) -> Maybe<&2,Abort.AbortSignal<Unit>>:
  match input:
    case AgentTypes.StreamInput{_,_,Some{config}}: signalOfConfig(config)
    case _: None{}
def wasAborted(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case Some{value}: Abort.aborted(Unit,value)
    case None{}: IO.pure(Bool,False{})
def ended(+stream: Stream.AssistantMessageEventStream(Schema.Value,Unit),+now: F64,aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}:
      Stream.push(Ai.AssistantMessageEvent<Schema.Value,Unit>,Ai.AssistantMessage<Schema.Value,Unit>,stream,Ai.StreamError{Ai.ErrorAborted{},Ai.AssistantMessage{Nil{},"openai-responses","fixture","theme-fixture",None{},None{},None{},None{},Agent.emptyUsage(),Ai.Aborted{},None{},Some{"Request was aborted"},None{},None{},now}})
    case False{}:
      do IO<Unit>:
        Stream.push(Ai.AssistantMessageEvent<Schema.Value,Unit>,Ai.AssistantMessage<Schema.Value,Unit>,stream,Ai.Start{response("",now)})
        Stream.push(Ai.AssistantMessageEvent<Schema.Value,Unit>,Ai.AssistantMessage<Schema.Value,Unit>,stream,Ai.StreamDone{Ai.DoneStop{},response("late-response",now)})
def delayedProvider(_: Unit,input: Input()) -> IO(Output()):
  do IO<Output()>:
    IO.print("fixture-prompt-started")
    IO.sleep(1800)
    +now : F64 <- Date.now()
    +stream : Stream.AssistantMessageEventStream(Schema.Value,Unit) <- Stream.createAssistantMessageEventStream(~Schema.Value,~Unit)
    aborted : Bool <- wasAborted(signalOf(input))
    ended(stream,now,aborted)
    return Done{AgentTypes.borrowedStream(Unit,Tools.ToolError,stream)}
def model() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"theme-fixture","Theme fixture",Ai.OpenAIResponsesApi{},"fixture","https://invalid.local",False{},None{},Ai.InputText{} <> Nil{},None{},Ai.ModelCost{U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),None{}},None{},U32.to_f64(128000),U32.to_f64(4096),None{},None{},None{}}
def otherModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"alternate","Alternate fixture",Ai.OpenAIResponsesApi{},"fixture","https://invalid.local",False{},None{},Ai.InputText{} <> Nil{},None{},Ai.ModelCost{U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),None{}},None{},U32.to_f64(128000),U32.to_f64(4096),None{},None{},None{}}
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
        +stream : Runtime.Stream() <- Callback.create(~Unit,~Input(),~Output(),~delayedProvider,Unit{})
        +registry : StreamFn.Registry(Unit,Tools.ToolDetails,Runtime.LoopConfig(),Tools.ToolError) <- StreamFn.create(Unit,Tools.ToolDetails,Runtime.LoopConfig(),Tools.ToolError)
        +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError,~Runtime.validationError)
        +converter : Runtime.Converter() <- Runtime.createConverter(False{})
        candidate : Result<&2,&2,StreamFn.MissingDefault,Runtime.Owner()> <- Agent.new(~Unit,~Tools.ToolDetails,~Runtime.Custom(),~Tools.ToolError,~Unit,options(stream,converter,Sessions.getSessionId(Unit,Tools.ToolDetails,Schema.Value,stored)),registry,validator,Tools.emptyDetails())
        +agent : Runtime.Owner() <- requireAgent(candidate)
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd,agentDir,Settings.options())
        models : Models.ModelRuntime <- ModelFixture.create(Nil{})
        +session : Session.AgentSession <- Session.create(agent,stored,settings(loaded),cwd,Runtime.Loadout{Record.new(String),Nil{},Nil{},Nil{},None{},Nil{}, None{}, Nil{}},models,Nil{})
        result : Result<&2,&2,Run.Error,Unit> <- Run.run(session,Nil{},cwd,None{},agentDir,assetsRoot,setting(choice),model() <> otherModel() <> Nil{})
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
