import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test

def Tool() -> Data: T.AgentTool<Unit, U32, String, String, Unit, String>
def Preparation() -> Data: Loop.ToolCallPreparation<Unit, U32, String, String, Unit, String>
def Input() -> Data: T.ToolExecutionInput<U32, Unit, String>
def Output() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def forbidden(unused: Unit, input: Input()) -> IO(Output):
  IO.die(Output(), 1, "preparation records must not execute tools")

def checkPrepared(value: Preparation(), expectedCall: T.AgentToolCall(String), expectedTool: R.Ref<Tool()>) -> IO(Unit):
  match value:
    case Loop.Prepared{Loop.PreparedToolCall{+call, tool, args}}:
      do IO<Unit>:
        Test.assertion(R.same(Ai.ToolCall<String>, call, expectedCall) && R.same(Tool(), tool, expectedTool) && U32.is_eq(args, 7), "prepared call lost identities or validated arguments")
        current : Ai.ToolCall<String> <- R.read(Ai.ToolCall<String>, call)
        Test.assertion(String.eq(Loop.callArguments(String, current), "changed raw"), "prepared call lost live raw arguments")
    case _: IO.die(Unit, 1, "wrong preparation variant")

def checkImmediate(value: Preparation(), expected: R.Ref<T.AgentToolResult<String>>) -> IO(Unit):
  match value:
    case Loop.Immediate{Loop.ImmediateToolCallOutcome{result, isError}}:
      Test.assertion(R.same(T.AgentToolResult<String>, result, expected) && isError, "immediate outcome lost result identity or error flag")
    case _: IO.die(Unit, 1, "wrong immediate variant")

def main() -> IO(Unit):
  do IO<Unit>:
    +execute : C.Callback<Input(), Output()> <- C.create(~Unit, ~Input(), ~Output(), ~forbidden, Unit{})
    +tool : R.Ref<Tool()> <- R.new(Tool(), T.AgentTool{"tool", "description", Unit{}, None{}, "label", None{}, execute, None{}, None{}})
    +call : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"id", "tool", "raw", None{}, None{}})
    +result : R.Ref<T.AgentToolResult<String>> <- R.new(T.AgentToolResult<String>, T.AgentToolResult{Nil{}, "details", None{}, None{}})
    +prepared : Preparation() = Loop.Prepared{Loop.PreparedToolCall{call, tool, 7}}
    +immediate : Preparation() = Loop.Immediate{Loop.ImmediateToolCallOutcome{result, True{}}}
    Test.assertion(String.eq(Loop.preparationKind(Unit, U32, String, String, Unit, String, prepared), "prepared"), "prepared discriminator differs")
    Test.assertion(String.eq(Loop.preparationKind(Unit, U32, String, String, Unit, String, immediate), "immediate"), "immediate discriminator differs")
    R.write(Ai.ToolCall<String>, call, Ai.ToolCall{"id", "tool", "changed raw", None{}, None{}})
    checkPrepared(prepared, call, tool)
    checkImmediate(immediate, result)
    oldCall : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, call)
    oldTool : Tool() <- R.dispose(Tool(), tool)
    oldResult : T.AgentToolResult<String> <- R.dispose(T.AgentToolResult<String>, result)
    C.dispose(Input(), Output(), execute)
    IO.print("PASS prepared/immediate contracts and shared identities")
