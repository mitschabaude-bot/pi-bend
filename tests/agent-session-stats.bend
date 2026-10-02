import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/session-stats.bend as Stats
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/usage-totals.bend as UsageTotals

# agent-session-stats.test.ts: billed totals range over the whole append-only
# session. Public context-usage cases run in the AgentSession harness.

def Entry() -> Data: S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def n(value: U32) -> F64: F.fromU32(value)
def zero() -> F64: n(0)
def same(+left: F64, +right: F64) -> Bool: F64.is_eq(left, right)
def parent(id: String) -> Maybe<&2, String>: Some{id}
def base(+id: String, +parentId: Maybe<&2, String>) -> S.SessionEntryBase:
  S.SessionEntryBase{id, parentId, "2026-01-01T00:00:00.000Z"}

def usage(+input: U32, +output: U32, +read: U32, +write: U32, cost: F64) -> Ai.Usage:
  Ai.Usage{n(input), n(output), n(read), n(write), None{}, None{}, F.add(F.add(n(input), n(output)), F.add(n(read), n(write))), Ai.UsageCost{zero(), zero(), zero(), zero(), cost}}

def tokens(total: U32) -> Ai.Usage: usage(total, 0, 0, 0, zero())
def billed(total: U32, cost: U32) -> Ai.Usage: usage(total, 0, 0, 0, n(cost))

def user(+id: String, +parentId: Maybe<&2, String>, +text: String) -> Entry():
  S.SessionMessageEntry{base(id, parentId), Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, zero()}}}}

def assistantMessage(value: Ai.Usage, stop: Ai.StopReason) -> Ai.AssistantMessage<V.Value, V.Value>:
  Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{"reply", None{}}}], "anthropic-messages", "anthropic", "claude-sonnet-4-5", None{}, None{}, None{}, None{}, value, stop, None{}, None{}, None{}, None{}, zero()}

def assistantWith(+id: String, +parentId: Maybe<&2, String>, value: Ai.Usage, stop: Ai.StopReason) -> Entry():
  S.SessionMessageEntry{base(id, parentId), Agent.LlmMessage{Ai.Assistant{assistantMessage(value, stop)}}}

def assistant(+id: String, +parentId: Maybe<&2, String>, total: U32, stop: Ai.StopReason) -> Entry():
  assistantWith(id, parentId, tokens(total), stop)

def toolMessage(value: Ai.Usage) -> Ai.ToolResultMessage<Tools.ToolDetails>:
  Ai.ToolResultMessage{"tool-call-1", "test_tool", [Ai.TextImageText{Ai.TextContent{"tool result", None{}}}], None{}, Some{value}, False{}, zero()}

def toolResult(+id: String, +parentId: Maybe<&2, String>, value: Ai.Usage) -> Entry():
  S.SessionMessageEntry{base(id, parentId), Agent.LlmMessage{Ai.ToolResult{toolMessage(value)}}}

def compaction(+id: String, +parentId: Maybe<&2, String>, +kept: String, value: Maybe<&2, Ai.Usage>) -> Entry():
  S.Compaction{S.CompactionEntry{base(id, parentId), "summary", kept, 1n, None{}, value, None{}, None{}}}

def branchSummary(+id: String, value: Ai.Usage) -> Entry():
  S.BranchSummaryEntry{base(id, None{}), "root", "summary", None{}, Some{value}, None{}}

def totals(entries: List<&2, Entry()>) -> Stats.Totals:
  Stats.aggregate(entries, Stats.empty())

def totalUsage(value: Stats.Totals, input: U32, output: U32, read: U32, write: U32, cost: F64) -> Bool:
  match value:
    case Stats.Totals{_, _, _, _, _, actualInput, actualOutput, actualRead, actualWrite, actualCost}:
      same(actualInput, n(input)) && same(actualOutput, n(output)) && same(actualRead, n(read)) && same(actualWrite, n(write)) && same(actualCost, cost)

def preCompaction() -> List<&2, Entry()>:
  [user("u1", None{}, "first"), assistant("a1", parent("u1"), 180000, Ai.Stop{}), user("u2", parent("a1"), "second"), assistant("a2", parent("u2"), 195000, Ai.Stop{})]

def compacted() -> List<&2, Entry()>:
  List.append(&2, Entry(), preCompaction(), [compaction("c1", parent("a2"), "u2", None{}), user("u3", parent("c1"), "third")])

def afterCompaction() -> List<&2, Entry()>:
  List.append(&2, Entry(), compacted(), [assistant("a3", parent("u3"), 25000, Ai.Stop{})])

def cacheWarm() -> Entry():
  S.UsageEntry{base("warm", None{}), "cache_warm", "anthropic", "claude-sonnet-4-5", usage(2, 1, 97, 0, F.divide(n(1), n(100))), Some{"extension override"}}

def warmShape(entries: List<&2, Entry()>, value: Stats.Totals) -> Bool:
  match entries value:
    case S.UsageEntry{_, "cache_warm", _, _, _, Some{"extension override"}} <> Nil{} Stats.Totals{users, assistants, calls, results, messages, input, output, read, write, cost}:
      same(input, n(2)) && same(output, n(1)) && same(read, n(97)) && same(write, zero()) && same(cost, F.divide(n(1), n(100))) && Nat.is_eq(users, 0n) && Nat.is_eq(assistants, 0n) && Nat.is_eq(calls, 0n) && Nat.is_eq(results, 0n) && Nat.is_eq(messages, 0n)
    case _ _: False{}

def emptyContextOf(result: Result<&2, &2, S.Error, S.SessionContext<V.Value, Tools.ToolDetails, V.Value>>) -> Bool:
  match result:
    case Done{S.SessionContext{messages, _, _}}: List.is_empty(&2, S.Msg(V.Value, Tools.ToolDetails, V.Value), messages)
    case _: False{}

def emptyContext(entries: List<&2, Entry()>) -> Bool:
  emptyContextOf(S.buildSessionContext(V.Value, Tools.ToolDetails, V.Value, entries, S.Latest{}))

def warmBreakdownOf(values: List<&2, UsageTotals.UsageCostBreakdownEntry>) -> Bool:
  match values:
    case UsageTotals.UsageCostBreakdownEntry{key, cost, value} <> Nil{}:
      String.eq(key, "anthropic/claude-sonnet-4-5") && same(cost, F.divide(n(1), n(100))) && same(value, n(100))
    case _: False{}

def warmBreakdown(entries: List<&2, Entry()>) -> Bool:
  warmBreakdownOf(UsageTotals.getUsageCostBreakdown(V.Value, Tools.ToolDetails, V.Value, entries))

def groupedBreakdownOf(values: List<&2, UsageTotals.UsageCostBreakdownEntry>) -> Bool:
  match values:
    case UsageTotals.UsageCostBreakdownEntry{"Tools/summaries", summaryCost, summaryTokens} <> UsageTotals.UsageCostBreakdownEntry{"anthropic/claude-sonnet-4-5", modelCost, modelTokens} <> Nil{}:
      same(summaryCost, n(6)) && same(summaryTokens, n(300)) && same(modelCost, F.divide(n(1), n(2))) && same(modelTokens, n(100))
    case _: False{}

def groupedEntries() -> List<&2, Entry()>:
  [assistantWith("model", None{}, usage(100, 0, 0, 0, F.divide(n(1), n(2))), Ai.Stop{}), toolResult("tool", parent("model"), billed(100, 1)), compaction("compact", parent("tool"), "model", Some{billed(100, 2)}), branchSummary("branch", billed(100, 3))]

def groupedBreakdown() -> Bool:
  groupedBreakdownOf(UsageTotals.getUsageCostBreakdown(V.Value, Tools.ToolDetails, V.Value, groupedEntries()))

def currentCase() -> Bool:
  totalUsage(totals([user("u", None{}, "hello"), assistant("a", parent("u"), 200, Ai.Stop{})]), 200, 0, 0, 0, zero())

def compactedCase() -> Bool:
  totalUsage(totals(compacted()), 375000, 0, 0, 0, zero())

def postCompactionCase() -> Bool:
  totalUsage(totals(afterCompaction()), 400000, 0, 0, 0, zero())

def branchCase() -> Bool:
  totalUsage(totals([branchSummary("branch", usage(10, 20, 30, 40, n(1)))]), 10, 20, 30, 40, n(1))

def compactionCase() -> Bool:
  totalUsage(totals([compaction("compact", None{}, "compact", Some{usage(10, 20, 30, 40, n(1))})]), 10, 20, 30, 40, n(1))

def warmEntries() -> List<&2, Entry()>: [cacheWarm()]

def warmingCase() -> Bool:
  +entries = warmEntries()
  warmShape(entries, totals(entries)) && emptyContext(entries) && warmBreakdown(entries)

def toolCase() -> Bool:
  totalUsage(totals([toolResult("tool", None{}, usage(10, 20, 30, 40, n(1)))]), 10, 20, 30, 40, n(1))

def main() -> IO(Unit):
  do IO<Unit>:
    check(currentCase(), "exposes the current context usage alongside token totals")
    check(compactedCase(), "reports unknown current context usage immediately after compaction")
    check(postCompactionCase(), "uses post-compaction usage for current context instead of stale kept usage")
    check(branchCase(), "includes branch summary usage in session totals")
    check(compactionCase(), "includes compaction usage in session totals")
    check(warmingCase(), "includes cache-warming usage exactly once without adding messages")
    check(toolCase(), "includes tool result usage in session totals")
    check(groupedBreakdown(), "groups tool and summary usage separately from model-attributed usage")
