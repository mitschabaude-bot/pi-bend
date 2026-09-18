import Base
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test

def text(message: Ai.AssistantMessage<String, Unit>) -> String:
  match message:
    case Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{value, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
    case _: "invalid"

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +usage : Ai.Usage = Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero})
    original : Ai.AssistantMessage<String, Unit> = Test.assistant(Ai.AssistantText{Ai.TextContent{"before", None{}}} <> Nil{}, usage, Ai.Pending{})
    snapshot : Ai.AssistantMessage<String, Unit> = Loop.snapshotAssistantMessage(String, Unit, original)
    updated : Ai.AssistantMessage<String, Unit> = Test.assistant(Ai.AssistantText{Ai.TextContent{"after", None{}}} <> Nil{}, usage, Ai.Stop{})
    Test.assertion(String.eq(text(snapshot), "before") && String.eq(text(updated), "after"), "immutable snapshots must retain their emitted content")
    IO.print("PASS immutable assistant snapshot values")
