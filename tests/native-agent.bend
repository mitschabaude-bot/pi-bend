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

def configuration(model: Ai.Model<Ai.JsonValue>, key: String, converter: C.Callback<Messages(), Converted()>) -> Config():
  T.AgentLoopConfig{Ai.SimpleStreamOptions{None{}, None{}, Some{key}, None{}, Some{R.new(String)}, None{}, None{}, None{}, Some{F.fromU32(120000)}, Some{F.fromU32(0)}, None{}, None{}, None{}, Some{F.fromU32(128)}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, model, converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

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

def reportMessages(messages: Messages()) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case T.LlmMessage{Ai.Assistant{message}} <> rest:
      do IO<Unit>:
        IO.print("answer " ++ Native.message(message))
        reportMessages(rest)
    case _ <> rest: reportMessages(rest)

def report(result: Outcome()) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{messages}: reportMessages(messages)

def run(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String) -> IO(Unit):
  do IO<Unit>:
    +authorizer : C.Callback<URL.Host, TLS.Authorization> <- Trust.newSAN(Trust.SANPolicy{bundle, 256n})
    +provider : T.StreamFn(Unit, Unit, Config(), String) <- Providers.responses(~Config(), ~Unit, ~Unit, ~Unit, ~String, ~project, ~Native.identity, ~Native.error, Native.config(authorizer))
    +converter : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~convert, Unit{})
    +validator : Loop.Validator(String) <- Loop.createPlain(~String, ~validationError)
    +cancel : C.Callback<Maybe<&2, Signal()>, Bool> <- C.create(~Unit, ~Maybe<&2, Signal()>, ~Bool, ~isAborted, Unit{})
    +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
    +execute : C.Callback<ToolInput(), ToolOutput()> <- C.create(~Ref.Ref<U32>, ~ToolInput(), ~ToolOutput(), ~echo, counter)
    key : String <- IO.try(String, IO.get_env("OPENAI_API_KEY"))
    tool : T.AgentTool<Unit, String> = T.AgentTool{"echo", "Return the input text unchanged", schema(), None{}, "Echo", None{}, execute, None{}, None{}}
    context : T.AgentContext<Unit, Unit, Unit, String> = T.AgentContext{Nil{}, Some{tool <> Nil{}}}
    prompts : Messages() = T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{prompt}, F.fromU32(0)}}} <> Nil{}
    +owner : Run() <- Loop.agentLoop(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~Native.identity, ~declarationError, ~Selection.errorMessage, ~Loop.errorMessage, prompts, context, configuration(Native.model(name, base), key, converter), Loop.Options{None{}, validator, cancel, Unit{}, Selection.Explicit{provider}})
    +cursor : Cursor() <- Loop.iterator(Unit, Unit, Unit, String, owner)
    events(cursor, None{})
    Stream.disposeIterator(EventValue(), Outcome(), cursor)
    result : Outcome() <- Loop.resultStream(Unit, Unit, Unit, String, owner)
    Loop.disposeStreamRun(Unit, Unit, Unit, String, owner)
    C.dispose(Providers.Input(Config(), Unit, Unit), Providers.Output(Unit, String), provider)
    C.dispose(Messages(), Converted(), converter)
    Loop.disposeValidation(String, validator)
    C.dispose(Maybe<&2, Signal()>, Bool, cancel)
    C.dispose(ToolInput(), ToolOutput(), execute)
    count : U32 <- Ref.dispose(U32, counter)
    C.dispose(URL.Host, TLS.Authorization, authorizer)
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
