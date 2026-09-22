import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as R
import ../../runtime/src/deferred.bend as D
import ./message-events.bend as Test
import ./context.bend as H
import ./turn-update.bend as ConfigTest
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

def Config() -> Data: ConfigTest.Config()
def Input() -> Data: T.ToolHookInput<H.After()>
def Output() -> Data: Result<&2, &2, String, Maybe<&2, T.AfterToolCallResult<String>>>
def Hook() -> Data: C.Callback<Input(), Output()>
def ToolInput() -> Data: T.ToolExecutionInput<String>
def ToolOutput() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
type State is Data:
  State{calls: R.Ref<U32>, mode: U32, originallyError: Bool, entered: Chan(Unit), release: Chan(Unit)}

def text(value: List<&2, Ai.TextImageContent>) -> String:
  match value:
    case Ai.TextImageText{Ai.TextContent{value, _}} <> Nil{}: value
    case _: "invalid"

def inspect(input: Input(), expectedError: Bool) -> IO(Unit):
  match input:
    case T.ToolHookInput{T.AfterToolCallContext{_, Ai.ToolCall{id, name, raw, _, _}, args, T.AgentToolResult{content, details, _, _}, isError, T.AgentContext{T.CustomMessage{context} <> Nil{}, _}}, Some{_}}:
      Test.assertion(String.eq(id, "call-id") && String.eq(name, "echo") && Schema.equal(raw, Schema.Text{"raw args"}) && Schema.equal(args, Schema.Number{F.fromU32(123)}) && String.eq(text(content), "original") && String.eq(details, "original details") && Bool.not(Bool.xor(isError, expectedError)) && String.eq(context, "context"), "after hook input lost execution data")
    case _: Test.assertion(False{}, "after hook input or signal shape")

def response(mode: U32) -> Output():
  match mode:
    case 0: Done{None{}}
    case 1: Done{Some{T.AfterToolCallResult{None{}, None{}, None{}, None{}, Some{True{}}}}}
    case 2: Done{Some{T.AfterToolCallResult{Some{Ai.TextImageText{Ai.TextContent{"patched", None{}}} <> Nil{}}, Some{"patched details"}, Some{False{}}, None{}, Some{False{}}}}}
    case _: Fail{"hook failed"}

def hook(state: State, input: Input()) -> IO(Output()):
  match state:
    case State{calls, mode, expectedError, entered, release}:
      do IO<Output()>:
        inspect(input, expectedError)
        R.modify(U32, Unit, calls, n => (U32.add(n, 1), Unit{}))
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        token : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return response(mode)

def forbidden(unused: Unit, input: ToolInput()) -> IO(ToolOutput()):
  IO.die(ToolOutput(), 1, "finalization must not execute tool twice")

def configuration(converter: ConfigTest.Converter(), after: Maybe<&2, Hook()>) -> Config():
  T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, after}

def check(finalized: Loop.FinalizedToolCallOutcome<String>, expectedText: String, expectedDetails: String, expectedError: Bool, expectedTerminate: Bool) -> IO(Unit):
  match finalized:
    case Loop.FinalizedToolCallOutcome{Ai.ToolCall{id, name, raw, _, _}, T.AgentToolResult{content, details, _, terminate}, isError}:
      Test.assertion(String.eq(id, "call-id") && String.eq(name, "echo") && Schema.equal(raw, Schema.Text{"raw args"}) && String.eq(text(content), expectedText) && String.eq(details, expectedDetails) && Bool.not(Bool.xor(isError, expectedError)) && Bool.not(Bool.xor(Loop.resultTerminates(String, T.AgentToolResult{Nil{}, "", None{}, terminate}), expectedTerminate)), "finalized fields differ")

def optional(present: Bool, hook: Hook()) -> Maybe<&2, Hook()>:
  match present:
    case True{}: Some{hook}
    case False{}: None{}

def finish(action: IO(Loop.FinalizedToolCallOutcome<String>), done: D.Deferred<Unit>) -> IO(Loop.FinalizedToolCallOutcome<String>):
  do IO<Loop.FinalizedToolCallOutcome<String>>:
    result : Loop.FinalizedToolCallOutcome<String> <- action
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def releaseHook(present: Bool, entered: Chan(Unit), release: Chan(Unit), done: D.Deferred<Unit>) -> IO(Unit):
  match present:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        token : Maybe<&1, Unit> <- Chan.recv(Unit, entered)
        completion : Maybe<&2, Unit> <- D.peek(Unit, done)
        Test.assertion(Maybe.is_none(&2, Unit, completion), "finalization returned before the async hook settled")
        sent : Bool <- Chan.send(Unit, release, Unit{})
        return Unit{}

def scenario(+present: Bool, mode: U32, +originallyError: Bool, expectedText: String, expectedDetails: String, expectedError: Bool, terminate: Bool) -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +after : Hook() <- C.create(~State, ~Input(), ~Output(), ~hook, State{calls, mode, originallyError, entered, release})
    +converter : ConfigTest.Converter() <- C.create(~Unit, ~H.Messages(), ~ConfigTest.Output(), ~ConfigTest.forbidden, Unit{})
    +execute : C.Callback<ToolInput(), ToolOutput()> <- C.create(~Unit, ~ToolInput(), ~ToolOutput(), ~forbidden, Unit{})
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<Schema.Value, Unit> = Test.assistant(Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{})
    prepared : Loop.PreparedToolCall<String, String> = Loop.PreparedToolCall{Ai.ToolCall{"call-id", "echo", Schema.Text{"raw args"}, None{}, None{}}, T.AgentTool{"echo", "", Schema.Null{}, None{}, "", None{}, execute, None{}, None{}}, Schema.Number{F.fromU32(123)}}
    executed : Loop.ExecutedToolCallOutcome<String> = Loop.ExecutedToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"original", None{}}} <> Nil{}, "original details", None{}, None{}}, originallyError}
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    running : Chan(Loop.FinalizedToolCallOutcome<String>) <- IO.fork(Loop.FinalizedToolCallOutcome<String>, finish(Loop.finalizeExecutedToolCall(Unit, String, String, String, Unit, T.AgentContext{T.CustomMessage{"context"} <> Nil{}, None{}}, assistant, prepared, executed, configuration(converter, optional(present, after)), Some{Abort.signal(Unit, controller)}, "empty details", error => error), done))
    releaseHook(present, entered, release, done)
    finalized : Loop.FinalizedToolCallOutcome<String> <- IO.join(Loop.FinalizedToolCallOutcome<String>, running)
    check(finalized, expectedText, expectedDetails, expectedError, terminate)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, present, 1, 0)), "hook invocation count differs")
    C.dispose(Input(), Output(), after)
    C.dispose(H.Messages(), ConfigTest.Output(), converter)
    C.dispose(ToolInput(), ToolOutput(), execute)
    Chan.close(Unit, entered)
    Chan.close(Unit, release)
    D.dispose(Unit, done)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, 3, False{}, "original", "original details", False{}, False{})
    scenario(False{}, 3, True{}, "original", "original details", True{}, False{})
    scenario(True{}, 0, False{}, "original", "original details", False{}, False{})
    scenario(True{}, 0, True{}, "original", "original details", True{}, False{})
    scenario(True{}, 1, False{}, "original", "original details", False{}, True{})
    scenario(True{}, 1, True{}, "original", "original details", True{}, True{})
    scenario(True{}, 2, True{}, "patched", "patched details", False{}, False{})
    scenario(True{}, 3, False{}, "hook failed", "empty details", True{}, False{})
    scenario(True{}, 3, True{}, "hook failed", "empty details", True{}, False{})
    IO.print("PASS after-tool hook inputs, overrides, termination, failure conversion, awaited settlement and exactly-once invocation")
