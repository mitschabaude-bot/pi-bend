import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as Options
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/agent-loop.bend as Service
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/src/utils/validation.bend as Validation
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as F
import ./main-loop.bend as M
import ./message-events.bend as Test

def Owner() -> Data: Agent.Agent<V.Value, Unit, String, String, V.Value, String, Unit, Unit, Unit>
def Config() -> Data: Run.Config(V.Value, Unit, String, String, V.Value, String, Unit, Unit, Unit)
def Messages() -> Data: List<&2, Run.RunMessage(V.Value, Unit, String, String)>
def StreamValue() -> Data: Stream.AssistantMessageEventStream(V.Value, Unit)
def ProviderInput() -> Data: T.StreamInput<V.Value, V.Value, Unit, String, Unit, Config()>
def ProviderOutput() -> Type: Result<&2, &1, String, T.StreamLease<V.Value, Unit, String>>
def ExecuteInput() -> Data: T.ToolExecutionInput<V.Value, Run.RunSignal(), String>
def ExecuteOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def identity(value: String) -> String: value
def declarationError(error: Declaration.DeclarationError) -> String: "declaration failed"
def mapError(error: Validation.ToolValidationError) -> String:
  Maybe.default(&2, String, Validation.formatToolValidationError(error), "unexpected unsupported fixture schema")
def typedIdentity(error: Validation.ToolValidationError) -> Validation.ToolValidationError: error
def field(value: V.Value) -> V.Value: V.ObjectValue{Record.Record{Record.Property{"value", value} <> Nil{}}}
def raw(valid: Bool) -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"value", V.Text{Bool.pick(String, valid, "42", "bad")}} <> Record.Property{"note", V.Null{}} <> Nil{}}}
def kind(name: String) -> V.Value: V.ObjectValue{Record.Record{Record.Property{"type", V.Text{name}} <> Nil{}}}
def schema() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", V.ObjectValue{Record.Record{Record.Property{"value", kind("number")} <> Record.Property{"note", kind("string")} <> Nil{}}}} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Record.Property{"additionalProperties", V.Boolean{False{}}} <> Nil{}}}
def expected(valid: Bool) -> String:
  Bool.pick(String, valid, "accepted", "Validation failed for tool \"echo\":\n  - value: must be number\n\nReceived arguments:\n{\n  \"value\": \"bad\",\n  \"note\": null\n}")
def resultText(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>, +valid: Bool) -> Bool:
  match messages:
    case Ai.ToolResult{Ai.ToolResultMessage{"call", "echo", Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, _, _, +error, _}} <> _:
      String.eq(text, expected(valid)) && Bool.pick(Bool, valid, Bool.not(error), error)
    case _ <> rest: resultText(rest, valid)
    case Nil{}: False{}
def original(messages: Messages(), valid: Bool) -> Bool:
  match messages:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", args, _, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} <> _:
      V.equal(args, raw(valid))
    case _ <> rest: original(rest, valid)
    case Nil{}: False{}
def execute(counter: R.Ref<U32>, input: ExecuteInput()) -> IO(ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{"call", args, Some{_}, Some{_}}:
      do IO<ExecuteOutput()>:
        Test.assertion(V.equal(args, field(V.Number{F.fromU32(42)})), "executor receives coerced number with optional null removed")
        R.modify(U32, Unit, counter, old => (U32.add(old, 1), Unit{}))
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"accepted", None{}}} <> Nil{}, "done", None{}, None{}}}
    case _: IO.die(ExecuteOutput(), 1, "unexpected executor input")
type Capture is Data:
  Capture{valid: Bool, calls: R.Ref<U32>, streams: R.Ref<List<&2, StreamValue()>>}
def increment(+old: U32) -> U32 & U32: (U32.add(old, 1), old)
def providerEvent(index: U32, valid: Bool) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, M.assistant(Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", raw(valid), None{}, None{}}} <> Nil{}, Ai.ToolUse{})}
    case _: Ai.StreamDone{Ai.DoneStop{}, M.assistant(M.text("done"), Ai.Stop{})}
def inspect(index: U32, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>, valid: Bool) -> IO(Unit):
  match index:
    case 0: IO.pure(Unit, Unit{})
    case 1: Test.assertion(resultText(messages, valid), "next provider request receives exact validation error or successful tool result")
    case _: Test.assertion(False{}, "unexpected provider request")
def provider(capture: Capture, input: ProviderInput()) -> IO(ProviderOutput()):
  match capture input:
    case Capture{+valid, calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<ProviderOutput()>:
        +index : U32 <- R.modify(U32, U32, calls, old => increment(old))
        inspect(index, messages, valid)
        +stream : StreamValue() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, providerEvent(index, valid))
        return Done{T.borrowedStream(V.Value, Unit, String, stream)}
def required(result: Result<&2, &2, Provider.MissingDefault, Owner()>) -> IO(Owner()):
  match result:
    case Done{agent}: IO.pure(Owner(), agent)
    case _: IO.die(Owner(), 1, "Agent construction failed")
def success(result: Result<&2, &2, Agent.AgentError<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "Agent execution failed")
def messages(state: T.AgentState<V.Value, V.Value, Unit, String, String, V.Value, Run.RunSignal(), String, Unit>) -> Messages():
  match state:
    case T.AgentState{_, _, _, history, _, _, _, _}: history
def disposeStreams(streams: List<&2, StreamValue()>) -> IO(Unit):
  match streams:
    case Nil{}: IO.pure(Unit, Unit{})
    case stream <> rest:
      do IO<Unit>:
        Stream.dispose(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream)
        disposeStreams(rest)
def scenario(+valid: Bool) -> IO(Unit):
  do IO<Unit>:
    +executions : R.Ref<U32> <- R.new(U32, 0)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, StreamValue()>> <- R.new(List<&2, StreamValue()>, Nil{})
    +validator : Service.Validator(String) <- Service.createPlain(~String, ~mapError)
    +executor : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~R.Ref<U32>, ~ExecuteInput(), ~ExecuteOutput(), ~execute, executions)
    +stream : T.StreamFn(V.Value, V.Value, Unit, String, Unit, Config(), String) <- C.create(~Capture, ~ProviderInput(), ~ProviderOutput(), ~provider, Capture{valid, calls, streams})
    +registry : Provider.Registry(V.Value, V.Value, Unit, String, Unit, Config(), String) <- Provider.create(V.Value, V.Value, Unit, String, Unit, Config(), String)
    initial : State.AgentInitialState<V.Value, V.Value, Unit, String, String, V.Value, Run.RunSignal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, Some{T.AgentTool{"echo", "Echo", schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}, None{}}
    options : Options.AgentOptions<V.Value, Unit, String, String, V.Value, String, Unit, Unit, Unit> = Options.AgentOptions{Some{initial}, None{}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
    created : Result<&2, &2, Provider.MissingDefault, Owner()> <- Agent.new(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~String, ~Unit, ~Unit, ~Unit, options, registry, validator, "empty")
    +agent : Owner() <- required(created)
    result : Result<&2, &2, Agent.AgentError<String>, Unit> <- Agent.prompt(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~String, ~Unit, ~Unit, ~Unit, ~identity, ~identity, ~declarationError, agent, Agent.Text{"run tool", Nil{}})
    success(result)
    snapshot : T.AgentState<V.Value, V.Value, Unit, String, String, V.Value, Run.RunSignal(), String, Unit> <- Agent.state(V.Value, Unit, String, String, V.Value, String, Unit, Unit, Unit, agent)
    Test.assertion(original(messages(snapshot), valid), "persisted assistant retains original unnormalized arguments")
    executed : U32 <- R.read(U32, executions)
    requests : U32 <- R.read(U32, calls)
    Test.assertion(U32.is_eq(executed, Bool.pick(U32, valid, 1, 0)) && U32.is_eq(requests, 2), "invalid arguments never execute; Agent continues after either outcome")
    Agent.dispose(V.Value, Unit, String, String, V.Value, String, Unit, Unit, Unit, agent)
    Service.disposeValidation(String, validator)
    C.dispose(ExecuteInput(), ExecuteOutput(), executor)
    C.dispose(ProviderInput(), ProviderOutput(), stream)
    Provider.dispose(V.Value, V.Value, Unit, String, Unit, Config(), String, registry)
    old : U32 <- R.dispose(U32, executions)
    old : U32 <- R.dispose(U32, calls)
    all : List<&2, StreamValue()> <- R.dispose(List<&2, StreamValue()>, streams)
    disposeStreams(all)
    IO.print("PASS Agent native plain-schema validation integration")
def invalidSchema(value: Service.ValidationOutput(Validation.ToolValidationError)) -> Bool:
  match value:
    case Fail{Validation.InvalidToolSchema{"echo", _}}: True{}
    case _: False{}
def typedFailure() -> IO(Unit):
  do IO<Unit>:
    +validator : Service.Validator(Validation.ToolValidationError) <- Service.createPlain(~Validation.ToolValidationError, ~typedIdentity)
    +tool : Ai.Tool<V.Value> = Ai.Tool{"echo", "Echo", V.ObjectValue{Record.Record{Record.Property{"$ref", V.Text{"https://fixture.invalid/schema"}} <> Nil{}}}, None{}}
    +call : Ai.ToolCall<V.Value> = Ai.ToolCall{"call", "echo", V.Null{}, None{}, None{}}
    first : Service.ValidationOutput(Validation.ToolValidationError) <- C.call(Service.ValidationInput(), Service.ValidationOutput(Validation.ToolValidationError), validator, Loop.ToolValidationInput{tool, Loop.OriginalCall{call}})
    second : Service.ValidationOutput(Validation.ToolValidationError) <- C.call(Service.ValidationInput(), Service.ValidationOutput(Validation.ToolValidationError), validator, Loop.ToolValidationInput{tool, Loop.ReplacedCall{call}})
    Test.assertion(invalidSchema(first) && invalidSchema(second), "both call paths preserve typed unsupported-schema failures")
    Service.disposeValidation(Validation.ToolValidationError, validator)
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(True{})
    scenario(False{})
    typedFailure()
