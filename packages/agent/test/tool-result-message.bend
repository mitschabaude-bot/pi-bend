import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-cost.bend as Cost
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date
import ../../runtime/src/schema-value.bend as Schema

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

def usageOk(value: Maybe<&2, Ai.Usage>, cost: Ai.UsageCost) -> Bool:
  match value:
    case Some{Ai.Usage{_, _, _, _, _, _, _, actual}}: Cost.sameCost(actual, cost)
    case _: False{}

def check(value: Ai.ToolResultMessage<String>, expected: String, cost: Ai.UsageCost, lower: F64, upper: F64) -> IO(Unit):
  match value:
    case Ai.ToolResultMessage{id, name, content, Some{+details}, usage, isError, +timestamp}:
      do IO<Unit>:
        assertion(String.eq(id, "call-id") && String.eq(name, "echo") && contentOk(content) && isError, "tool-result message lost source fields")
        assertion(String.eq(details, expected) && usageOk(usage, cost), "tool-result message cloned payload references")
        assertion(ordered(F.compare(lower, timestamp)) && ordered(F.compare(timestamp, upper)), "tool-result message must use current Unix wall-clock time")
        current : String <- IO.pure(String, details)
        assertion(String.eq(current, "before"), "tool-result message must observe its supplied details value")
    case _: IO.die(Unit, 1, "tool result details missing")

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F64 = F.fromU32(0)
    +details : String <- IO.pure(String, "before")
    +cost : Ai.UsageCost = Ai.UsageCost{zero, zero, zero, zero, zero}
    +call : T.AgentToolCall = Ai.ToolCall{"call-id", "echo", Schema.Null{}, None{}, None{}}
    +result : T.AgentToolResult<String> = T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"tool output", None{}}} <> Nil{}, details, Some{Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}}, Some{True{}}}
    +finalized : Loop.FinalizedToolCallOutcome<String> = Loop.FinalizedToolCallOutcome{call, result, True{}}
    +lower : F64 <- Date.now()
    +first : Ai.ToolResultMessage<String> <- Loop.createToolResultMessage(String, finalized)
    +second : Ai.ToolResultMessage<String> <- Loop.createToolResultMessage(String, finalized)
    +upper : F64 <- Date.now()
    firstValue : Ai.ToolResultMessage<String> = first
    secondValue : Ai.ToolResultMessage<String> = second
    check(firstValue, details, cost, lower, upper)
    check(secondValue, details, cost, lower, upper)
    oldFirst : Ai.ToolResultMessage<String> = first
    oldSecond : Ai.ToolResultMessage<String> = second
    retained : String <- IO.pure(String, details)
    assertion(String.eq(retained, "before"), "message disposal must not dispose supplied details")
    oldResult : T.AgentToolResult<String> = result
    oldCall : Ai.ToolCall<Schema.Value> = call
    oldDetails : String <- IO.pure(String, details)
    oldCost : Ai.UsageCost = cost
    IO.print("PASS tool-result artifact fields, wall-clock timestamps, immutable payloads")
