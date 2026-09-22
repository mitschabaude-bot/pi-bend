import Base
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/providers.bend as Providers
import ../packages/agent/src/stream-fn.bend as Selection
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/openai-responses.bend as Responses
import ../packages/ai/src/utils/event-stream.bend as Stream
import ../packages/ai/src/utils/validation.bend as Validation
import ../packages/ai/src/utils/tool-declaration.bend as Declaration
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/tls13-client.bend as TLS
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/x509.bend as X509
import ./native-openai.bend as Native

# An integration entry point for the real modular loop, not a second agent.
def Signal() -> Data: Abort.AbortSignal<Unit>
def Messages() -> Data: Loop.Messages(Unit, Unit, Unit)
def Converted() -> Data: Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, Unit>>>
def Config() -> Data: T.AgentLoopConfig<Unit, Unit, Unit, String, Unit>
def ToolInput() -> Data: T.ToolExecutionInput<Unit>
def ToolOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<Unit>>
def Run() -> Data: Loop.StreamRun<Unit, Unit, Unit, String>
def EventValue() -> Data: Loop.LoopEvent(Unit, Unit, Unit)
def Outcome() -> Data: Loop.StreamOutcome(Unit, Unit, Unit, String)
def Cursor() -> Data: Stream.Iterator<EventValue(), Outcome()>

def project(config: Config()) -> Responses.SimpleStreamOptions(Unit, Unit, String):
  T.toSimpleStreamOptions(Unit, Unit, Unit, String, Unit, config)

def convert(unused: Unit, messages: Messages()) -> IO(Converted()):
  IO.pure(Converted(), Done{Loop.llmMessages(Unit, Unit, Unit, messages)})

def isAborted(unused: Unit, signal: Maybe<&2, Signal()>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{signal}: Abort.aborted(Unit, signal)

def validationError(error: Validation.ToolValidationError) -> String:
  Maybe.default(&2, String, Validation.formatToolValidationError(error), "Tool schema validation failed")

def declarationError(error: Declaration.DeclarationError) -> String: "Tool declaration encoding failed"

def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"input", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"input"} <> Nil{}}} <> Nil{}}}

def echoValue(value: Maybe<&2, V.Value>) -> ToolOutput():
  match value:
    case Some{V.Text{text}}: Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, Unit{}, None{}, None{}}}
    case _: Fail{"echo expects an input string"}

def echo(counter: Ref.Ref<U32>, input: ToolInput()) -> IO(ToolOutput()):
  match input:
    case T.ToolExecutionInput{_, V.ObjectValue{fields}, _, _}:
      do IO<ToolOutput()>:
        Ref.modify(U32, Unit, counter, count => ((count + 1 : U32), Unit{}))
        return echoValue(R.get(V.Value, fields, "input"))
    case _: IO.pure(ToolOutput(), Fail{"echo expects an object"})

def configuration(model: Ai.Model<Ai.JsonValue>, key: String, converter: C.Callback<Messages(), Converted()>, maxTokens: U32, maxRetries: U32) -> Config():
  T.AgentLoopConfig{Ai.SimpleStreamOptions{None{}, None{}, Some{key}, None{}, Some{R.new(String)}, None{}, None{}, None{}, Some{F.fromU32(120000)}, Some{F.fromU32(maxRetries)}, None{}, None{}, None{}, Some{F.fromU32(maxTokens)}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, model, converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# Print the event sequence separately from the tool execution count, so the
# oracle can check ordering without depending on worker scheduling.
@unsafe def events(+cursor: Cursor(), step: Maybe<&2, Stream.Iteration<EventValue()>>) -> IO(Unit):
  match step:
    case None{}:
      do IO<Unit>:
        next : Stream.Iteration<EventValue()> <- Stream.nextValue(EventValue(), Outcome(), cursor)
        events(cursor, Some{next})
    case Some{Stream.End{}}: IO.pure(Unit, Unit{})
    case Some{Stream.Yield{value}}:
      do IO<Unit>:
        IO.print("event " ++ T.eventType(Unit, Unit, Unit, T.AgentToolResult<Unit>, T.AgentToolResult<Unit>, value))
        events(cursor, None{})

def reportAssistant(message: Ai.AssistantMessage<V.Value, Unit>) -> IO(Unit):
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, error, _, _, _}:
      IO.die(Unit, 1, Maybe.default(&2, String, error, "Model request failed"))
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, error, _, _, _}:
      IO.die(Unit, 1, Maybe.default(&2, String, error, "Model request aborted"))
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      IO.print("answer " ++ Native.text(content))

def reportMessages(messages: Messages()) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case T.LlmMessage{Ai.Assistant{message}} <> rest:
      do IO<Unit>:
        reportAssistant(message)
        reportMessages(rest)
    case _ <> rest: reportMessages(rest)

def report(result: Outcome()) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{messages}: reportMessages(messages)

# Test-host observation only: preserve Providers.released's result and ownership.
# Enabling this never changes the provider's normalized assistant error.
def observeCleanup(cause: Maybe<&2,Responses.Error<Unit,String>>) -> IO(Unit):
  match cause:
    case None{}: IO.pure(Unit,Unit{})
    case Some{cause}: IO.print("provider-diagnostic|cleanup|" ++ Native.diagnosticError(cause))

def observeResult(result: Responses.RunResult<Unit,Unit,String>) -> IO(Unit):
  match result:
    case Responses.RunResult{Responses.Failed{_,_,cause},cleanup}:
      do IO<Unit>:
        IO.print("provider-diagnostic|primary|" ++ Native.diagnosticError(cause))
        observeCleanup(cleanup)
    case Responses.RunResult{_,cleanup}: observeCleanup(cleanup)

def observedRelease(enabled: Bool,owner: Responses.Run<Unit,Unit,String>) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    +result : Responses.RunResult<Unit,Unit,String> <- Responses.dispose(Unit,Unit,String,owner)
    Bool.pick(Unit -> IO(Unit),enabled,_ => observeResult(result),_ => IO.pure(Unit,Unit{}))(Unit{})
    return Providers.released(~Unit,~String,~Native.error,result)

def observedLease(enabled: Bool,pair: Responses.Run<Unit,Unit,String> & Stream.AssistantMessageEventStream(V.Value,Unit)) -> Providers.Output(Unit,String):
  match pair:
    case (owner,streamEvents): Done{T.StreamLease{streamEvents,observedRelease(enabled,owner)}}

type ObservedConfig is Data:
  ObservedConfig{config: Responses.Config,enabled: Bool}

def openObserved(config: ObservedConfig,input: Providers.Input(Config(),Unit,Unit)) -> IO(Providers.Output(Unit,String)):
  match config input:
    case ObservedConfig{config,enabled} T.StreamInput{model,context,options}:
      do IO<Providers.Output(Unit,String)>:
        owner : Responses.Run<Unit,Unit,String> <- Responses.streamSimple(~Unit,~Unit,~Unit,~Unit,~String,~Native.identity,config,model,context,Maybe.map(&2,Config(),Responses.SimpleStreamOptions(Unit,Unit,String),project,options))
        return observedLease(enabled,Responses.borrow(Unit,Unit,String,owner))

# Missing environment variables are ordinary disabled settings in this host.
def optionalFlag(value: Result<&1,&1,U32 & String,String>) -> Bool:
  match value:
    case Done{value}: String.eq(value,"1")
    case Fail{_}: False{}

def runTools(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, tools: List<&2, T.AgentTool<Unit, String>>, maxTokens: U32) -> IO(Outcome()):
  do IO<Outcome()>:
    +authorizer : C.Callback<URL.Host, TLS.Authorization> <- Trust.newSAN(Trust.SANPolicy{bundle, 256n})
    diagnostics : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_BEND_PROVIDER_DIAGNOSTICS")
    +provider : T.StreamFn(Unit, Unit, Config(), String) <- C.create(~ObservedConfig,~Providers.Input(Config(),Unit,Unit),~Providers.Output(Unit,String),~openObserved,ObservedConfig{Native.config(authorizer),optionalFlag(diagnostics)})
    +converter : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~convert, Unit{})
    +validator : Loop.Validator(String) <- Loop.createPlain(~String, ~validationError)
    +cancel : C.Callback<Maybe<&2, Signal()>, Bool> <- C.create(~Unit, ~Maybe<&2, Signal()>, ~Bool, ~isAborted, Unit{})
    retries : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_BEND_RETRY_REQUESTS")
    key : String <- IO.try(String, IO.get_env("OPENAI_API_KEY"))
    context : T.AgentContext<Unit, Unit, Unit, String> = T.AgentContext{Nil{}, Some{tools}}
    prompts : Messages() = T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{prompt}, F.fromU32(0)}}} <> Nil{}
    +owner : Run() <- Loop.agentLoop(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~Native.identity, ~declarationError, ~Selection.errorMessage, ~Loop.errorMessage, prompts, context, configuration(Native.model(name, base), key, converter, maxTokens, Bool.pick(U32,optionalFlag(retries),2,0)), Loop.Options{None{}, validator, cancel, Unit{}, Selection.Explicit{provider}})
    +cursor : Cursor() <- Loop.iterator(Unit, Unit, Unit, String, owner)
    events(cursor, None{})
    Stream.disposeIterator(EventValue(), Outcome(), cursor)
    result : Outcome() <- Loop.streamOutcome(Unit, Unit, Unit, String, owner)
    Loop.disposeStreamRun(Unit, Unit, Unit, String, owner)
    C.dispose(Providers.Input(Config(), Unit, Unit), Providers.Output(Unit, String), provider)
    C.dispose(Messages(), Converted(), converter)
    Loop.disposeValidation(String, validator)
    C.dispose(Maybe<&2, Signal()>, Bool, cancel)
    C.dispose(URL.Host, TLS.Authorization, authorizer)
    return result

# Compatibility for the existing echo and write integration fixtures.
def runTool(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, tool: T.AgentTool<Unit, String>, maxTokens: U32) -> IO(Outcome()):
  runTools(bundle, name, base, prompt, tool <> Nil{}, maxTokens)

def run(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
    +callback : C.Callback<ToolInput(), ToolOutput()> <- C.create(~Ref.Ref<U32>, ~ToolInput(), ~ToolOutput(), ~echo, counter)
    tool : T.AgentTool<Unit, String> = T.AgentTool{"echo", "Return the input text unchanged", schema(), None{}, "Echo", None{}, callback, None{}, None{}}
    result : Outcome() <- runTool(bundle, name, base, prompt, tool, 128)
    C.dispose(ToolInput(), ToolOutput(), callback)
    count : U32 <- Ref.dispose(U32, counter)
    IO.print("executions " ++ U32.show(count))
    report(result)

def loaded(name: String, base: String, prompt: String, certificates: Result<&2, &2, Trust.Error, List<&2, X509.Certificate>>) -> IO(Unit):
  match certificates:
    case Fail{_}: IO.die(Unit, 1, "trust bundle failed")
    case Done{bundle}: run(bundle, name, base, prompt)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case bundle <> name <> base <> prompt <> Nil{}:
      do IO<Unit>:
        certificates : Result<&2, &2, Trust.Error, List<&2, X509.Certificate>> <- Trust.load(bundle, 1048576n)
        loaded(name, base, prompt, certificates)
    case _: IO.die(Unit, 1, "expected trust-bundle model base-url prompt")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
