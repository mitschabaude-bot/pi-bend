import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/agent-loop.bend as E
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ./context.bend as H
import ./turn-update.bend as ConfigTest
import ./tool-execution.bend as Execute

def ValidationInput() -> Data: Loop.ToolValidationInput<Unit, String, U32>
def ValidationOutput() -> Data: Result<&2, &2, String, U32>
def HookInput() -> Data: T.ToolHookInput<H.Before(), Unit>
def HookOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<U32, H.Context()>>
def Hook() -> Data: C.Callback<HookInput(), HookOutput()>
def State() -> Data: Loop.ToolPreparationState<Unit, String, Unit, String, String, U32, Unit, String>
type Capture is Data:
  Capture{mode: U32, log: R.Ref<String>}

def record(log: R.Ref<String>, tag: String) -> IO(Unit):
  R.modify(String, Unit, log, old => (old ++ tag, Unit{}))

def adapter(state: Capture, raw: String) -> IO(ValidationOutput()):
  match state:
    case Capture{+mode, log}:
      do IO<ValidationOutput()>:
        record(log, "a")
        Test.assertion(String.eq(raw, "raw"), "adapter did not receive original args")
        return Bool.pick(ValidationOutput(), U32.is_eq(mode, 2), Fail{"adapter failed"}, Done{Bool.pick(U32, U32.is_eq(mode, 10), 999, 42)})

# A strict test decoder, not a substitute for the pending schema validator.
# It accepts only raw="raw" or adapted=42, and must run exactly once.
def decode(call: Loop.PreparedToolCallArguments<String, U32>) -> ValidationOutput():
  match call:
    case Loop.OriginalCall{Ai.ToolCall{_, _, raw, _, _}}: Bool.pick(ValidationOutput(), String.eq(raw, "raw"), Done{42}, Fail{"invalid raw"})
    case Loop.ReplacedCall{Ai.ToolCall{_, _, args, _, _}}: Bool.pick(ValidationOutput(), U32.is_eq(args, 42), Done{42}, Fail{"invalid adapted"})

def validate(state: Capture, input: ValidationInput()) -> IO(ValidationOutput()):
  match state input:
    case Capture{mode, log} Loop.ToolValidationInput{Ai.Tool{name, _, _, _}, call}:
      do IO<ValidationOutput()>:
        record(log, "v")
        Test.assertion(String.eq(name, "echo"), "validator got the wrong tool")
        return Bool.pick(ValidationOutput(), U32.is_eq(mode, 3), Fail{"validation failed"}, decode(call))

def decision(+mode: U32) -> Maybe<&2, T.BeforeToolCallResult>:
  Bool.pick(Maybe<&2, T.BeforeToolCallResult>, U32.is_eq(mode, 5) || U32.is_eq(mode, 6), Some{T.BeforeToolCallResult{Some{True{}}, Some{""}, Some{True{}}}}, Some{T.BeforeToolCallResult{Some{False{}}, Some{"unused"}, Some{True{}}}})

def before(state: Capture, input: HookInput()) -> IO(HookOutput()):
  match state input:
    case Capture{+mode, log} T.ToolHookInput{T.BeforeToolCallContext{_, Ai.ToolCall{id, name, raw, _, _}, args, T.AgentContext{_, tools}}, Some{Unit{}}}:
      do IO<HookOutput()>:
        record(log, "h")
        Test.assertion(U32.is_eq(args, 42) && String.eq(id, "call") && String.eq(name, "echo") && String.eq(raw, "raw"), "hook must receive original call and validated args")
        return Bool.pick(HookOutput(), U32.is_eq(mode, 4), Fail{"hook failed"}, Done{T.BeforeToolCallUpdate{123, T.AgentContext{Nil{}, None{}}, decision(mode)}})
    case _ _: IO.die(HookOutput(), 1, "before hook lost signal")

def aborted(state: Capture, signal: Maybe<&2, Unit>) -> IO(Bool):
  match state:
    case Capture{mode, log}:
      do IO<Bool>:
        record(log, "c")
        return U32.is_eq(mode, 6)

def execute(state: Capture, input: Execute.Input()) -> IO(Execute.Output()):
  match state input:
    case Capture{+mode, log} T.ToolExecutionInput{id, args, Some{Unit{}}, Some{_}}:
      do IO<Execute.Output()>:
        record(log, "e")
        Test.assertion(String.eq(id, "call") && U32.is_eq(args, Bool.pick(U32, U32.is_eq(mode, 0) || U32.is_eq(mode, 8), 42, 123)), "hook args must reach execution without revalidation")
        return Done{Execute.partial("done")}
    case _ _: IO.die(Execute.Output(), 1, "execution input differs")

def forbidden(unused: Unit, input: Execute.Input()) -> IO(Execute.Output()):
  IO.die(Execute.Output(), 1, "lookup must select first matching tool")

def emit(unused: Unit, event: Execute.EventValue()) -> IO(E.Emission<String>):
  IO.die(E.Emission<String>, 1, "test executor emits no updates")

def configuration(converter: ConfigTest.Converter(), hook: Maybe<&2, Hook()>) -> ConfigTest.Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, hook, None{}}

def expectedMessage(mode: U32) -> String:
  match mode:
    case 2: "adapter failed"
    case 3: "validation failed"
    case 4: "hook failed"
    case 5: "Tool execution was blocked"
    case 6: "Operation aborted"
    case 7: "Tool absent not found"
    case 9: "invalid raw"
    case 10: "invalid adapted"
    case _: "unexpected immediate outcome"

def runPrepared(+prepared: Loop.PreparedToolCall<Unit, U32, String, String, Unit, String>, emitter: C.Callback<Execute.EventValue(), E.Emission<String>>) -> IO(Unit):
  match prepared:
    case Loop.PreparedToolCall{call, _, _}:
      do IO<Unit>:
        +updates : Loop.ToolUpdateRun<String, String> <- Loop.createToolUpdateRun(~Unit, ~String, ~Unit, ~String, ~String, ~String, call, emitter)
        outcome : Execute.Outcome() <- Loop.executePreparedToolCall(Unit, U32, String, String, Unit, String, prepared, Some{Unit{}}, updates, "empty", error => error)
        Execute.check(outcome, False{}, False{})
        Loop.disposeToolUpdateRun(String, String, updates)

def check(+mode: U32, state: State(), emitter: C.Callback<Execute.EventValue(), E.Emission<String>>) -> IO(Unit):
  match state:
    case Loop.ToolPreparationState{_, Loop.Prepared{prepared}}: runPrepared(prepared, emitter)
    case Loop.ToolPreparationState{_, Loop.Immediate{Loop.ImmediateToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, _}} <> Nil{}, details, _, terminate}, True{}}}}:
      do IO<Unit>:
        expected : String = expectedMessage(mode)
        Test.assertion(String.eq(message, expected) && String.eq(details, "empty"), "preparation error conversion")
        Test.assertion(Bool.not(Bool.xor(Maybe.is_some(&2, Bool, terminate), U32.is_eq(mode, 5))), "abort must override block/terminate")
    case _: Test.assertion(False{}, "unexpected preparation state")

def expectedLog(mode: U32) -> String:
  match mode:
    case 0: "vce"
    case 1: "avhce"
    case 2: "a"
    case 3: "v"
    case 4: "vh"
    case 5: "vhc"
    case 6: "vhc"
    case 7: ""
    case 8: "vce"
    case 9: "v"
    case 10: "av"
    case _: "vhce"

def checkContext(+mode: U32, state: State()) -> IO(Unit):
  match state:
    case Loop.ToolPreparationState{T.AgentContext{_, tools}, _}:
      Test.assertion(Bool.not(Bool.xor(Maybe.is_none(&2, List<&2, T.AgentTool<Unit, U32, String, String, Unit, String>>, tools), U32.is_eq(mode, 1) || U32.is_eq(mode, 5) || U32.is_eq(mode, 6) || U32.is_eq(mode, 11))), "explicit hook context update must survive preparation/block/abort")

def run(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    +log : R.Ref<String> <- R.new(String, "")
    +capture : Capture = Capture{mode, log}
    +adapt : C.Callback<String, ValidationOutput()> <- C.create(~Capture, ~String, ~ValidationOutput(), ~adapter, capture)
    +validator : C.Callback<ValidationInput(), ValidationOutput()> <- C.create(~Capture, ~ValidationInput(), ~ValidationOutput(), ~validate, capture)
    +hook : Hook() <- C.create(~Capture, ~HookInput(), ~HookOutput(), ~before, capture)
    +executor : C.Callback<Execute.Input(), Execute.Output()> <- C.create(~Capture, ~Execute.Input(), ~Execute.Output(), ~execute, capture)
    +other : C.Callback<Execute.Input(), Execute.Output()> <- C.create(~Unit, ~Execute.Input(), ~Execute.Output(), ~forbidden, Unit{})
    +emitter : C.Callback<Execute.EventValue(), E.Emission<String>> <- C.create(~Unit, ~Execute.EventValue(), ~E.Emission<String>, ~emit, Unit{})
    +converter : ConfigTest.Converter() <- C.create(~Unit, ~H.Messages(), ~ConfigTest.Output(), ~ConfigTest.forbidden, Unit{})
    tools : List<&2, T.AgentTool<Unit, U32, String, String, Unit, String>> = T.AgentTool{"echo", "", Unit{}, None{}, "", ConfigTest.selected(C.Callback<String, ValidationOutput()>, U32.is_eq(mode, 1) || U32.is_eq(mode, 2) || U32.is_eq(mode, 10), adapt), executor, None{}, None{}} <> T.AgentTool{"echo", "", Unit{}, None{}, "", None{}, other, None{}, None{}} <> Nil{}
    call : Ai.ToolCall<String> = Ai.ToolCall{"call", Bool.pick(String, U32.is_eq(mode, 7), "absent", "echo"), Bool.pick(String, U32.is_eq(mode, 9), "invalid", "raw"), None{}, None{}}
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<String, Unit> = Test.assistant(Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{})
    config : ConfigTest.Config() = configuration(converter, ConfigTest.selected(Hook(), Bool.not(U32.is_eq(mode, 0) || U32.is_eq(mode, 8)), hook))
    +state : State() <- Loop.prepareToolCallWith(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, T.AgentContext{Nil{}, Some{tools}}, assistant, call, config, Some{Unit{}}, validator, aborted(capture), "empty", error => error)
    checkContext(mode, state)
    check(mode, state, emitter)
    actual : String <- R.read(String, log)
    Test.assertion(String.eq(actual, expectedLog(mode)), "preparation effect order / exactly-once validation")
    C.dispose(String, ValidationOutput(), adapt)
    C.dispose(ValidationInput(), ValidationOutput(), validator)
    C.dispose(HookInput(), HookOutput(), hook)
    C.dispose(Execute.Input(), Execute.Output(), executor)
    C.dispose(Execute.Input(), Execute.Output(), other)
    C.dispose(Execute.EventValue(), E.Emission<String>, emitter)
    C.dispose(H.Messages(), ConfigTest.Output(), converter)
    unused : String <- R.dispose(String, log)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run(0)
    run(1)
    run(2)
    run(3)
    run(4)
    run(5)
    run(6)
    run(7)
    run(8)
    run(9)
    run(10)
    run(11)
    IO.print("PASS 12 native tool preparation/execution cases: validation, hooks, blocking, cancellation, failure precedence and first-match lookup")
