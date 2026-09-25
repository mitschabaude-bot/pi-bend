import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/session-json.bend as SessionJson
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/session-stats.bend as Stats
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/usage-totals.bend as UsageTotals

# upstream test/agent-session-stats.test.ts: the case added with cache
# warming. AgentSession.getSessionStats aggregates the stored entries with
# session-stats (Stats.aggregate), so the port checks that aggregation over
# a session holding one usage entry. The usage entry's JSONL form is a
# native supplement (docs/session-format.md).

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def n(value: U32) -> F64: F.fromU32(value)
def ratio(top: U32, bottom: U32) -> F64: F.divide(n(top), n(bottom))
def same(+actual: F64, +expected: F64) -> Bool: F64.is_eq(actual, expected)

def Manager() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Entry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

def usage() -> Ai.Usage: Ai.Usage{n(2), n(1), n(97), n(0), None{}, None{}, n(100), Ai.UsageCost{ratio(1, 1000), ratio(2, 1000), ratio(7, 1000), n(0), ratio(1, 100)}}

def session() -> Result<&2, &2, S.Error, Manager()>:
  Result.bind(&2, &2, S.Error, Manager(), Manager(), S.inMemory(Unit, Tools.ToolDetails, V.Value, S.SessionHeader{Some{3n}, "session", "2024-12-03T14:00:00.000Z", "/tmp", None{}}),
    state => S.appendUsage(Unit, Tools.ToolDetails, V.Value, state, S.EntryStamp{"f6g7h8i9", "2024-12-03T14:08:00.000Z"}, "cache_warm", "anthropic", "claude-sonnet-4-5", usage(), Some{"extension override"}))

def entriesOf(result: Result<&2, &2, S.Error, Manager()>) -> List<&2, Entry()>:
  match result:
    case Done{state}: S.getEntries(Unit, Tools.ToolDetails, V.Value, state)
    case Fail{_}: Nil{}

def firstIsWarm(entries: List<&2, Entry()>) -> Bool:
  match entries:
    case S.UsageEntry{_, kind, _, _, _, Some{note}} <> Nil{}: String.eq(kind, "cache_warm") && String.eq(note, "extension override")
    case _: False{}

def totalsMatch(totals: Stats.Totals) -> Bool:
  match totals:
    case Stats.Totals{users, assistants, calls, results, messages, +input, +output, +read, +write, _}:
      same(input, n(2)) && same(output, n(1)) && same(read, n(97)) && same(write, n(0)) && same(F.add(F.add(input, output), F.add(read, write)), n(100)) && Nat.is_eq(messages, 0n) && Nat.is_eq(users + assistants + calls + results, 0n)

def noContext(result: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>) -> Bool:
  match result:
    case Done{S.SessionContext{messages, _, _}}: List.is_empty(&2, S.Msg(Unit, Tools.ToolDetails, V.Value), messages)
    case Fail{_}: False{}

def breakdownMatches(entries: List<&2, UsageTotals.UsageCostBreakdownEntry>) -> Bool:
  match entries:
    case UsageTotals.UsageCostBreakdownEntry{key, cost, tokens} <> Nil{}: String.eq(key, "anthropic/claude-sonnet-4-5") && same(cost, ratio(1, 100)) && same(tokens, n(100))
    case _: False{}

def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def readUnit(value: V.Value) -> SessionJson.Decoded(Unit): Done{Unit{}}
def readRaw(value: V.Value) -> SessionJson.Decoded(V.Value): Done{value}
def readDetails(value: V.Value) -> SessionJson.Decoded(Tools.ToolDetails): Done{Tools.RawDetails{value}}

def encoded(entry: Entry()) -> V.Value:
  SessionJson.entry(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, entry)

# The documented example line (docs/session-format.md) decodes to the entry
# and encodes back to the same JSON value.
def example() -> String:
  "{\"type\":\"usage\",\"id\":\"f6g7h8i9\",\"parentId\":\"e5f6g7h8\",\"timestamp\":\"2024-12-03T14:08:00.000Z\",\"kind\":\"cache_warm\",\"provider\":\"anthropic\",\"model\":\"claude-sonnet-4-5\",\"usage\":{\"input\":0,\"output\":0,\"cacheRead\":50000,\"cacheWrite\":0,\"totalTokens\":50000,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0.015,\"cacheWrite\":0,\"total\":0.015}}}"

def reencoded(parsed: V.Value, decoded: SessionJson.Decoded(S.FileEntry<Unit, Tools.ToolDetails, V.Value>)) -> Bool:
  match decoded:
    case Done{S.Entry{entry}}: V.equal(encoded(entry), parsed)
    case _: False{}

def fieldsMatch(decoded: SessionJson.Decoded(S.FileEntry<Unit, Tools.ToolDetails, V.Value>)) -> Bool:
  match decoded:
    case Done{S.Entry{S.UsageEntry{S.SessionEntryBase{id, Some{parent}, _}, kind, provider, model, Ai.Usage{_, _, read, _, _, _, _, _}, None{}}}}:
      String.eq(id, "f6g7h8i9") && String.eq(parent, "e5f6g7h8") && String.eq(kind, "cache_warm") && String.eq(provider, "anthropic") && String.eq(model, "claude-sonnet-4-5") && same(read, n(50000))
    case _: False{}

def roundTrip(+parsed: V.Value, +decoded: SessionJson.Decoded(S.FileEntry<Unit, Tools.ToolDetails, V.Value>)) -> Bool:
  fieldsMatch(decoded) && reencoded(parsed, decoded)

def jsonl(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> Bool:
  match parsed:
    case Done{+value}: roundTrip(value, SessionJson.decodeFileEntry(~Unit, ~Tools.ToolDetails, ~V.Value, ~readUnit, ~readDetails, ~readRaw, value))
    case Fail{_}: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +entries : List<&2, Entry()> = entriesOf(session())
    check(firstIsWarm(entries) && totalsMatch(Stats.aggregate(entries, Stats.empty())) && noContext(S.buildSessionContext(Unit, Tools.ToolDetails, V.Value, entries, S.Latest{})) && breakdownMatches(UsageTotals.getUsageCostBreakdown(Unit, Tools.ToolDetails, V.Value, entries)),
      "includes cache-warming usage exactly once without adding messages")
    check(jsonl(Decode.parse(example())), "usage entries read and write their documented JSONL form")
