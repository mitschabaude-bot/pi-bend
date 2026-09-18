import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def ordered(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{LT{}}: True{}
    case Some{EQ{}}: True{}
    case _: False{}

def contentOk(content: List<&2, Ai.TextImageContent>) -> Bool:
  match content:
    case Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}: String.eq(text, "tool output")
    case _: False{}

def usageOk(value: Maybe<&2, Ai.Usage>, cost: R.Ref<Ai.UsageCost>) -> Bool:
  match value:
    case Some{Ai.Usage{_, _, _, _, _, _, _, actual}}: R.same(Ai.UsageCost, actual, cost)
    case _: False{}

def check(value: Ai.ToolResultMessage<R.Ref<String>>, expected: R.Ref<String>, cost: R.Ref<Ai.UsageCost>, lower: F.F64, upper: F.F64) -> IO(Unit):
  match value:
    case Ai.ToolResultMessage{id, name, content, Some{+details}, usage, isError, +timestamp}:
      do IO<Unit>:
        assertion(String.eq(id, "call-id") && String.eq(name, "echo") && contentOk(content) && isError, "tool-result message lost source fields")
        assertion(R.same(String, details, expected) && usageOk(usage, cost), "tool-result message cloned payload references")
        assertion(ordered(F.compare(lower, timestamp)) && ordered(F.compare(timestamp, upper)), "tool-result message must use current Unix wall-clock time")
        current : String <- R.read(String, details)
        assertion(String.eq(current, "after"), "tool-result message must observe shared details mutation")
    case _: IO.die(Unit, 1, "tool result details missing")

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +details : R.Ref<String> <- R.new(String, "before")
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +call : T.AgentToolCall(Unit) <- R.new(Ai.ToolCall<Unit>, Ai.ToolCall{"call-id", "echo", Unit{}, None{}, None{}})
    +result : R.Ref<T.AgentToolResult<R.Ref<String>>> <- R.new(T.AgentToolResult<R.Ref<String>>, T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"tool output", None{}}} <> Nil{}, details, Some{Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}}, Some{True{}}})
    +finalized : Loop.FinalizedToolCallOutcome<Unit, R.Ref<String>> = Loop.FinalizedToolCallOutcome{call, result, True{}}
    +lower : F.F64 <- Date.now()
    +first : R.Ref<Ai.ToolResultMessage<R.Ref<String>>> <- Loop.createToolResultMessage(Unit, R.Ref<String>, finalized)
    +second : R.Ref<Ai.ToolResultMessage<R.Ref<String>>> <- Loop.createToolResultMessage(Unit, R.Ref<String>, finalized)
    +upper : F.F64 <- Date.now()
    assertion(Bool.not(R.same(Ai.ToolResultMessage<R.Ref<String>>, first, second)), "each finalized artifact must be a fresh message")
    R.write(String, details, "after")
    firstValue : Ai.ToolResultMessage<R.Ref<String>> <- R.read(Ai.ToolResultMessage<R.Ref<String>>, first)
    secondValue : Ai.ToolResultMessage<R.Ref<String>> <- R.read(Ai.ToolResultMessage<R.Ref<String>>, second)
    check(firstValue, details, cost, lower, upper)
    check(secondValue, details, cost, lower, upper)
    oldFirst : Ai.ToolResultMessage<R.Ref<String>> <- R.dispose(Ai.ToolResultMessage<R.Ref<String>>, first)
    oldSecond : Ai.ToolResultMessage<R.Ref<String>> <- R.dispose(Ai.ToolResultMessage<R.Ref<String>>, second)
    retained : String <- R.read(String, details)
    assertion(String.eq(retained, "after"), "message disposal must not dispose supplied details")
    oldResult : T.AgentToolResult<R.Ref<String>> <- R.dispose(T.AgentToolResult<R.Ref<String>>, result)
    oldCall : Ai.ToolCall<Unit> <- R.dispose(Ai.ToolCall<Unit>, call)
    oldDetails : String <- R.dispose(String, details)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    IO.print("PASS tool-result artifact fields, wall-clock timestamps, fresh identity and shared payloads")
