import Base
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema

def text(message: Ai.AssistantMessage<Schema.Value, Unit>) -> String:
  match message:
    case Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{value, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
    case _: "invalid"

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F64 = F.fromU32(0)
    +usage : Ai.Usage = Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero})
    original : Ai.AssistantMessage<Schema.Value, Unit> = Test.assistant(Ai.AssistantText{Ai.TextContent{"before", None{}}} <> Nil{}, usage, Ai.Pending{})
    snapshot : Ai.AssistantMessage<Schema.Value, Unit> = Loop.snapshotAssistantMessage(Unit, original)
    updated : Ai.AssistantMessage<Schema.Value, Unit> = Test.assistant(Ai.AssistantText{Ai.TextContent{"after", None{}}} <> Nil{}, usage, Ai.Stop{})
    Test.assertion(String.eq(text(snapshot), "before") && String.eq(text(updated), "after"), "immutable snapshots must retain their emitted content")
    IO.print("PASS immutable assistant snapshot values")
