import Base
import ../src/agent-loop.bend as Loop
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F

def Message() -> Data: Ai.AssistantMessage<String, Unit>
def Contents() -> Data: R.Ref<List<&2, Ai.AssistantContent<String>>>

def contents(message: Message()) -> Contents():
  match message:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def checkText(value: Ai.TextContent) -> IO(Unit):
  match value:
    case Ai.TextContent{text, _}: Test.assertion(String.eq(text, "changed"), "snapshot lost content-object mutation")

def checkArray(values: List<&2, Ai.AssistantContent<String>>, expected: R.Ref<Ai.TextContent>) -> IO(Unit):
  match values:
    case Ai.AssistantText{+text} <> Nil{}:
      do IO<Unit>:
        Test.assertion(R.same(Ai.TextContent, text, expected), "snapshot copied content object")
        value : Ai.TextContent <- R.read(Ai.TextContent, text)
        checkText(value)
    case _: IO.die(Unit, 1, "snapshot lost content-array mutation")

def check(value: Message(), expected: Contents(), text: R.Ref<Ai.TextContent>) -> IO(Unit):
  match value:
    case Ai.AssistantMessage{+content, _, _, _, _, _, _, _, _, Ai.Pending{}, _, _, _, _, _}:
      do IO<Unit>:
        Test.assertion(R.same(List<&2, Ai.AssistantContent<String>>, content, expected), "snapshot followed replacement of original content field")
        values : List<&2, Ai.AssistantContent<String>> <- R.read(List<&2, Ai.AssistantContent<String>>, content)
        checkArray(values, text)
    case _: IO.die(Unit, 1, "snapshot followed replacement of original top-level fields")

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +originalContents : Contents() <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +replacement : Contents() <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +text : R.Ref<Ai.TextContent> <- R.new(Ai.TextContent, Ai.TextContent{"before", None{}})
    +original : R.Ref<Message()> <- R.new(Message(), Test.assistant(originalContents, cost, Ai.Pending{}))
    +first : R.Ref<Message()> <- Loop.snapshotAssistantMessage(String, Unit, original)
    +second : R.Ref<Message()> <- Loop.snapshotAssistantMessage(String, Unit, original)
    Test.assertion(Bool.not(R.same(Message(), original, first)) && Bool.not(R.same(Message(), first, second)), "each event snapshot must be a fresh message object")
    R.write(List<&2, Ai.AssistantContent<String>>, originalContents, Ai.AssistantText{text} <> Nil{})
    R.write(Ai.TextContent, text, Ai.TextContent{"changed", None{}})
    R.write(Message(), original, Test.assistant(replacement, cost, Ai.Stop{}))
    firstValue : Message() <- R.dispose(Message(), first)
    check(firstValue, originalContents, text)
    secondValue : Message() <- R.dispose(Message(), second)
    check(secondValue, originalContents, text)
    originalValue : Message() <- R.dispose(Message(), original)
    Test.assertion(R.same(List<&2, Ai.AssistantContent<String>>, contents(originalValue), replacement), "snapshot operation changed original field replacement")
    values : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, originalContents)
    replacedValues : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, replacement)
    oldText : Ai.TextContent <- R.dispose(Ai.TextContent, text)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    IO.print("PASS assistant snapshot identity, shared content-array/object mutation and independent top-level fields")
