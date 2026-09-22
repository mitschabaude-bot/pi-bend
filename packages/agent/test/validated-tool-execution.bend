import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/agent-loop.bend as E
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/validation.bend as Validation
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort

def Context() -> Data: T.AgentContext<Unit, String, String, String>
def Messages() -> Data: List<&2, T.AgentMessage<Unit, String, String>>
def Converted() -> Data: Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, String>>>
def Config() -> Data: T.AgentLoopConfig<Unit, String, String, String, Unit>
def Input() -> Data: Loop.ToolValidationInput
def Checked() -> Data: Result<&2, &2, String, V.Value>
def ExecuteInput() -> Data: T.ToolExecutionInput<String>
def ExecuteOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def EventValue() -> Data: T.AgentEvent<Unit, String, String, T.AgentToolResult<String>, T.AgentToolResult<String>>
def Preparation() -> Data: Loop.ToolPreparationState<Unit, String, String, String>

def field(value: V.Value) -> V.Value: V.ObjectValue{R.Record{R.Property{"value", value} <> Nil{}}}

def convert(unused: Unit, messages: Messages()) -> IO(Converted()):
  IO.die(Converted(), 1, "tool preparation must not call message conversion")

def rejected(message: Maybe<&2, String>) -> IO(Checked()):
  match message:
    case Some{message}: IO.pure(Checked(), Fail{message})
    case None{}: IO.die(Checked(), 1, "unexpected native validation failure category or rendering failure")

def validationResult(result: Validation.ToolValidation()) -> IO(Checked()):
  match result:
    case Done{value}: IO.pure(Checked(), Done{value})
    case Fail{error}: rejected(Validation.formatToolValidationError(error))

def validate(unused: Unit, input: Input()) -> IO(Checked()):
  match input:
    case Loop.ToolValidationInput{tool, Loop.OriginalCall{call}}: validationResult(Validation.validatePlainToolArguments(tool, call))
    case Loop.ToolValidationInput{tool, Loop.ReplacedCall{call}}: validationResult(Validation.validatePlainToolArguments(tool, call))

def execute(counter: Ref.Ref<U32>, input: ExecuteInput()) -> IO(ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{id, args, Some{_}, Some{_}}:
      do IO<ExecuteOutput()>:
        Test.assertion(String.eq(id, "call") && V.equal(args, field(V.Number{F.fromU32(42)})), "executor must receive actual normalized/validated arguments")
        Ref.modify(U32, Unit, counter, count => ((count + 1 : U32), Unit{}))
        return Done{T.AgentToolResult{Nil{}, "done", None{}, None{}}}
    case _: IO.die(ExecuteOutput(), 1, "execution signal/update callback missing")

def emit(unused: Unit, event: EventValue()) -> IO(E.Emission<String>):
  IO.die(E.Emission<String>, 1, "this executor emits no updates")

def config(converter: C.Callback<Messages(), Converted()>) -> Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def executed(result: Result<&2, &2, String, Loop.ExecutedToolCallOutcome<String>>) -> IO(Unit):
  match result:
    case Done{Loop.ExecutedToolCallOutcome{T.AgentToolResult{_, details, _, _}, False{}}}: Test.assertion(String.eq(details, "done"), "validated executor result")
    case _: Test.assertion(False{}, "validated execution failed")

def runPrepared(+prepared: Loop.PreparedToolCall<String, String>, emitter: C.Callback<EventValue(), E.Emission<String>>) -> IO(Unit):
  match prepared:
    case Loop.PreparedToolCall{call, _, _}:
      do IO<Unit>:
        +updates : Loop.ToolUpdateRun<String, String> <- Loop.createToolUpdateRun(~Unit, ~String, ~String, ~String, call, emitter)
        controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Result<&2, &2, String, Loop.ExecutedToolCallOutcome<String>> <- Loop.executePreparedToolCall(String, String, prepared, Some{Abort.signal(Unit, controller)}, updates, "empty", error => error)
        executed(result)
        Loop.disposeToolUpdateRun(String, String, updates)

def check(valid: Bool, state: Preparation(), emitter: C.Callback<EventValue(), E.Emission<String>>) -> IO(Unit):
  match valid state:
    case True{} Loop.ToolPreparationState{_, Loop.Prepared{prepared}}: runPrepared(prepared, emitter)
    case False{} Loop.ToolPreparationState{_, Loop.Immediate{Loop.ImmediateToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, _}} <> Nil{}, _, _, _}, True{}}}}: Test.assertion(String.eq(message, "Validation failed for tool \"echo\":\n  - value: must be number\n\nReceived arguments:\n{\n  \"value\": \"bad\"\n}"), "preparation must expose native argument rejection")
    case _ _: Test.assertion(False{}, "validation/preparation outcome differs")

def run(+valid: Bool) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
    +executor : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~Ref.Ref<U32>, ~ExecuteInput(), ~ExecuteOutput(), ~execute, counter)
    +validator : C.Callback<Input(), Checked()> <- C.create(~Unit, ~Input(), ~Checked(), ~validate, Unit{})
    +converter : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~convert, Unit{})
    +emitter : C.Callback<EventValue(), E.Emission<String>> <- C.create(~Unit, ~EventValue(), ~E.Emission<String>, ~emit, Unit{})
    schema : V.Value = V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", field(V.ObjectValue{R.Record{R.Property{"type", V.Text{"number"}} <> Nil{}}})} <> R.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    call : Ai.ToolCall<V.Value> = Ai.ToolCall{"call", "echo", field(V.Text{Bool.pick(String, valid, "42", "bad")}), None{}, None{}}
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{Nil{}, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    controller2 : Abort.AbortController<Unit> <- Abort.new(Unit)
    state : Preparation() <- Loop.prepareToolCallWith(Unit, String, String, String, Unit, context, assistant, call, config(converter), Some{Abort.signal(Unit, controller2)}, validator, signal => IO.pure(Bool, False{}), "empty", error => error)
    check(valid, state, emitter)
    calls : U32 <- Ref.read(U32, counter)
    Test.assertion(U32.is_eq(calls, Bool.pick(U32, valid, 1, 0)), "invalid arguments must never reach the executor")
    C.dispose(ExecuteInput(), ExecuteOutput(), executor)
    C.dispose(Input(), Checked(), validator)
    C.dispose(Messages(), Converted(), converter)
    C.dispose(EventValue(), E.Emission<String>, emitter)
    unused : U32 <- Ref.dispose(U32, counter)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run(True{})
    run(False{})
    IO.print("PASS native schema validation through tool preparation/execution; invalid calls never execute")
