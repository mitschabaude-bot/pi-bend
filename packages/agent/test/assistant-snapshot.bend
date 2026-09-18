import Base
import ../../ai/src/utils/diagnostics.bend as Diag
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

def Diagnostics() -> Data: R.Ref<List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>>

def withDiagnostics(value: Message(), diagnostics: Diagnostics()) -> Message():
  match value:
    case Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, _, usage, reason, deferred, error, rawReason, endTurn, timestamp}: Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, Some{diagnostics}, usage, reason, deferred, error, rawReason, endTurn, timestamp}

def equalNumber(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{EQ{}}: True{}
    case _: False{}

def checkUsage(value: Ai.Usage) -> IO(Unit):
  match value:
    case Ai.Usage{input, _, _, _, _, _, _, _}: Test.assertion(equalNumber(F.compare(input, F.fromU32(7))), "snapshot lost usage-object mutation")

def checkDiagnostic(value: Diag.AssistantMessageDiagnostic<Unit>) -> IO(Unit):
  match value:
    case Diag.AssistantMessageDiagnostic{kind, _, _, _}: Test.assertion(String.eq(kind, "changed"), "snapshot lost diagnostic-object mutation")

def checkDiagnostics(values: List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, expected: R.Ref<Diag.AssistantMessageDiagnostic<Unit>>) -> IO(Unit):
  match values:
    case +value <> Nil{}:
      do IO<Unit>:
        Test.assertion(R.same(Diag.AssistantMessageDiagnostic<Unit>, value, expected), "snapshot copied diagnostic object")
        observed : Diag.AssistantMessageDiagnostic<Unit> <- R.read(Diag.AssistantMessageDiagnostic<Unit>, value)
        checkDiagnostic(observed)
    case _: IO.die(Unit, 1, "snapshot lost diagnostics-array mutation")

def checkNested(value: Message(), expectedUsage: R.Ref<Ai.Usage>, expectedDiagnostics: Diagnostics(), expectedDiagnostic: R.Ref<Diag.AssistantMessageDiagnostic<Unit>>) -> IO(Unit):
  match value:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, Some{+diagnostics}, +usage, _, _, _, _, _, _}:
      do IO<Unit>:
        Test.assertion(R.same(Ai.Usage, usage, expectedUsage), "snapshot followed original usage field replacement")
        Test.assertion(R.same(List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, diagnostics, expectedDiagnostics), "snapshot followed original diagnostics field replacement")
        observedUsage : Ai.Usage <- R.read(Ai.Usage, usage)
        checkUsage(observedUsage)
        observedDiagnostics : List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>> <- R.read(List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, diagnostics)
        checkDiagnostics(observedDiagnostics, expectedDiagnostic)
    case _: IO.die(Unit, 1, "snapshot diagnostics field was cleared")

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +assistantUsage : R.Ref<Ai.Usage> <- R.new(Ai.Usage, Test.usage(cost))
    +originalContents : Contents() <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +replacement : Contents() <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +text : R.Ref<Ai.TextContent> <- R.new(Ai.TextContent, Ai.TextContent{"before", None{}})
    +diagnostics : Diagnostics() <- R.new(List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, Nil{})
    +diagnostic : R.Ref<Diag.AssistantMessageDiagnostic<Unit>> <- R.new(Diag.AssistantMessageDiagnostic<Unit>, Diag.AssistantMessageDiagnostic{"before", zero, None{}, None{}})
    +replacementUsage : R.Ref<Ai.Usage> <- R.new(Ai.Usage, Test.usage(cost))
    +original : R.Ref<Message()> <- R.new(Message(), withDiagnostics(Test.assistant(originalContents, assistantUsage, Ai.Pending{}), diagnostics))
    +first : R.Ref<Message()> <- Loop.snapshotAssistantMessage(String, Unit, original)
    +second : R.Ref<Message()> <- Loop.snapshotAssistantMessage(String, Unit, original)
    Test.assertion(Bool.not(R.same(Message(), original, first)) && Bool.not(R.same(Message(), first, second)), "each event snapshot must be a fresh message object")
    R.write(List<&2, Ai.AssistantContent<String>>, originalContents, Ai.AssistantText{text} <> Nil{})
    R.write(Ai.TextContent, text, Ai.TextContent{"changed", None{}})
    R.write(Ai.Usage, assistantUsage, Ai.Usage{F.fromU32(7), zero, zero, zero, None{}, None{}, zero, cost})
    R.write(List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, diagnostics, diagnostic <> Nil{})
    R.write(Diag.AssistantMessageDiagnostic<Unit>, diagnostic, Diag.AssistantMessageDiagnostic{"changed", zero, None{}, None{}})
    R.write(Message(), original, Test.assistant(replacement, replacementUsage, Ai.Stop{}))
    +firstValue : Message() <- R.dispose(Message(), first)
    check(firstValue, originalContents, text)
    checkNested(firstValue, assistantUsage, diagnostics, diagnostic)
    +secondValue : Message() <- R.dispose(Message(), second)
    check(secondValue, originalContents, text)
    checkNested(secondValue, assistantUsage, diagnostics, diagnostic)
    originalValue : Message() <- R.dispose(Message(), original)
    Test.assertion(R.same(List<&2, Ai.AssistantContent<String>>, contents(originalValue), replacement), "snapshot operation changed original field replacement")
    values : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, originalContents)
    replacedValues : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, replacement)
    oldText : Ai.TextContent <- R.dispose(Ai.TextContent, text)
    oldAssistantUsage : Ai.Usage <- R.dispose(Ai.Usage, assistantUsage)
    oldReplacementUsage : Ai.Usage <- R.dispose(Ai.Usage, replacementUsage)
    oldDiagnostics : List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>> <- R.dispose(List<&2, R.Ref<Diag.AssistantMessageDiagnostic<Unit>>>, diagnostics)
    oldDiagnostic : Diag.AssistantMessageDiagnostic<Unit> <- R.dispose(Diag.AssistantMessageDiagnostic<Unit>, diagnostic)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    IO.print("PASS assistant snapshot identity, shared content/usage/diagnostics mutation and independent top-level fields")
