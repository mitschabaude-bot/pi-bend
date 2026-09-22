import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/f64.bend as F

def Tool() -> Data: T.AgentTool<String, String>
def Preparation() -> Data: Loop.ToolCallPreparation<String, String>
def Input() -> Data: T.ToolExecutionInput<String>
def Output() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def forbidden(unused: Unit, input: Input()) -> IO(Output):
  IO.die(Output(), 1, "preparation records must not execute tools")

def checkPrepared(value: Preparation(), expectedCall: T.AgentToolCall, expectedTool: Tool()) -> IO(Unit):
  match value:
    case Loop.Prepared{Loop.PreparedToolCall{+call, tool, args}}:
      do IO<Unit>:
        Test.assertion(Schema.equal(args, Schema.Number{F.fromU32(7)}), "prepared call lost validated arguments")
        current : Ai.ToolCall<Schema.Value> = call
        Test.assertion(Schema.equal(Loop.callArguments(current), Schema.Text{"raw"}), "prepared call lost raw arguments")
    case _: IO.die(Unit, 1, "wrong preparation variant")

def checkImmediate(value: Preparation(), expected: T.AgentToolResult<String>) -> IO(Unit):
  match value:
    case Loop.Immediate{Loop.ImmediateToolCallOutcome{result, isError}}:
      Test.assertion(isError, "immediate outcome lost error flag")
    case _: IO.die(Unit, 1, "wrong immediate variant")

def main() -> IO(Unit):
  do IO<Unit>:
    +execute : C.Callback<Input(), Output()> <- C.create(~Unit, ~Input(), ~Output(), ~forbidden, Unit{})
    +tool : Tool() = T.AgentTool{"tool", "description", Schema.Null{}, None{}, "label", None{}, execute, None{}, None{}}
    +call : T.AgentToolCall = Ai.ToolCall{"id", "tool", Schema.Text{"raw"}, None{}, None{}}
    +result : T.AgentToolResult<String> = T.AgentToolResult{Nil{}, "details", None{}, None{}}
    +prepared : Preparation() = Loop.Prepared{Loop.PreparedToolCall{call, tool, Schema.Number{F.fromU32(7)}}}
    +immediate : Preparation() = Loop.Immediate{Loop.ImmediateToolCallOutcome{result, True{}}}
    Test.assertion(String.eq(Loop.preparationKind(String, String, prepared), "prepared"), "prepared discriminator differs")
    Test.assertion(String.eq(Loop.preparationKind(String, String, immediate), "immediate"), "immediate discriminator differs")
    checkPrepared(prepared, call, tool)
    checkImmediate(immediate, result)
    oldCall : Ai.ToolCall<Schema.Value> = call
    oldTool : Tool() = tool
    oldResult : T.AgentToolResult<String> = result
    C.dispose(Input(), Output(), execute)
    IO.print("PASS prepared/immediate value contracts")
