import Base
import ../../../ai/src/types.bend as Ai
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/schema-value.bend as Schema
import ./session-manager.bend as S

# upstream core/usage-totals.ts
type UsageTotals is Data: UsageTotals{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, cost: F64}

def createUsageTotals() -> UsageTotals: UsageTotals{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}

def addUsageToTotals(totals: UsageTotals, usage: Ai.Usage) -> UsageTotals:
  match totals usage:
    case UsageTotals{input, output, cacheRead, cacheWrite, cost} Ai.Usage{addedInput, addedOutput, addedRead, addedWrite, _, _, _, Ai.UsageCost{_, _, _, _, total}}:
      UsageTotals{F.add(input, addedInput), F.add(output, addedOutput), F.add(cacheRead, addedRead), F.add(cacheWrite, addedWrite), F.add(cost, total)}

type UsageCostBreakdownEntry is Data: UsageCostBreakdownEntry{key: String, cost: F64, tokens: F64}

type Keyed is Data: Keyed{key: String, usage: Ai.Usage}

def assistantKey(-A: Data, -D: Data, message: Ai.AssistantMessage<A, D>) -> Keyed:
  match message:
    case Ai.AssistantMessage{_, _, provider, model, responseModel, _, _, _, usage, _, _, _, _, _, _}:
      Keyed{provider ++ "/" ++ Maybe.default(&2, String, responseModel, model), usage}

def summaryUsage(usage: Maybe<&2, Ai.Usage>) -> Maybe<&2, Keyed>:
  Maybe.map(&2, Ai.Usage, Keyed, value => Keyed{"Tools/summaries", value}, usage)

# Assistant and usage-entry usage is attributed to its provider/model;
# tool-result, branch summary and compaction usage share one bucket.
def keyedUsage(-D: Data, -T: Data, -C: Data, entry: S.SessionEntry<D, T, C>) -> Maybe<&2, Keyed>:
  match entry:
    case S.SessionMessageEntry{_, Agent.LlmMessage{Ai.Assistant{message}}}: Some{assistantKey(Schema.Value, D, message)}
    case S.UsageEntry{_, _, provider, model, usage, _}: Some{Keyed{provider ++ "/" ++ model, usage}}
    case S.SessionMessageEntry{_, Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, _, _, usage, _, _}}}}: summaryUsage(usage)
    case S.BranchSummaryEntry{_, _, _, _, usage, _}: summaryUsage(usage)
    case S.Compaction{S.CompactionEntry{_, _, _, _, _, usage, _, _}}: summaryUsage(usage)
    case _: None{}

type Bucket is Data: Bucket{key: String, totals: UsageTotals}

# Buckets keep first-seen order, as upstream's Map does.
def hasKey(buckets: List<&2, Bucket>, +wanted: String) -> Bool:
  match buckets:
    case Nil{}: False{}
    case Bucket{key, _} <> rest: String.eq(key, wanted) || hasKey(rest, wanted)

def addedIfSame(same: Bool, totals: UsageTotals, usage: Ai.Usage) -> UsageTotals:
  match same:
    case True{}: addUsageToTotals(totals, usage)
    case False{}: totals

def updatedBucket(bucket: Bucket, keyed: Keyed) -> Bucket:
  match bucket keyed:
    case Bucket{+key, totals} Keyed{wanted, usage}: Bucket{key, addedIfSame(String.eq(key, wanted), totals, usage)}

def updated(buckets: List<&2, Bucket>, +keyed: Keyed) -> List<&2, Bucket>:
  match buckets:
    case Nil{}: Nil{}
    case bucket <> rest: updatedBucket(bucket, keyed) <> updated(rest, keyed)

def newBucket(keyed: Keyed) -> Bucket:
  match keyed: case Keyed{key, usage}: Bucket{key, addUsageToTotals(createUsageTotals(), usage)}

def keyOf(keyed: Keyed) -> String:
  match keyed: case Keyed{key, _}: key

def added(+buckets: List<&2, Bucket>, +keyed: Keyed) -> List<&2, Bucket>:
  Bool.pick(Unit -> List<&2, Bucket>, hasKey(buckets, keyOf(keyed)), _ => updated(buckets, keyed), _ => List.append(&2, Bucket, buckets, [newBucket(keyed)]))(Unit{})

def addedIf(buckets: List<&2, Bucket>, keyed: Maybe<&2, Keyed>) -> List<&2, Bucket>:
  match keyed:
    case None{}: buckets
    case Some{value}: added(buckets, value)

def collected(-D: Data, -T: Data, -C: Data, entries: List<&2, S.SessionEntry<D, T, C>>, buckets: List<&2, Bucket>) -> List<&2, Bucket>:
  match entries:
    case Nil{}: buckets
    case entry <> rest: collected(D, T, C, rest, addedIf(buckets, keyedUsage(D, T, C, entry)))

def breakdownEntry(bucket: Bucket) -> UsageCostBreakdownEntry:
  match bucket:
    case Bucket{key, UsageTotals{input, output, cacheRead, cacheWrite, cost}}: UsageCostBreakdownEntry{key, cost, F.add(F.add(input, output), F.add(cacheRead, cacheWrite))}

def counted(entry: UsageCostBreakdownEntry) -> Bool:
  match entry:
    case UsageCostBreakdownEntry{_, cost, tokens}: F64.is_gt(cost, F.fromU32(0)) || F64.is_gt(tokens, F.fromU32(0))

def meaningful(entries: List<&2, Bucket>) -> List<&2, UsageCostBreakdownEntry>:
  match entries:
    case Nil{}: Nil{}
    case bucket <> rest:
      +entry = breakdownEntry(bucket)
      +tail = meaningful(rest)
      Bool.pick(List<&2, UsageCostBreakdownEntry>, counted(entry), entry <> tail, tail)

def entryCost(entry: UsageCostBreakdownEntry) -> F64:
  match entry: case UsageCostBreakdownEntry{_, cost, _}: cost

# A stable insertion by descending cost (upstream's Array.sort is stable).
def inserted(+entry: UsageCostBreakdownEntry, sorted: List<&2, UsageCostBreakdownEntry>) -> List<&2, UsageCostBreakdownEntry>:
  match sorted:
    case Nil{}: [entry]
    case +first <> +rest:
      Bool.pick(Unit -> List<&2, UsageCostBreakdownEntry>, F64.is_gt(entryCost(entry), entryCost(first)), _ => entry <> first <> rest, _ => first <> inserted(entry, rest))(Unit{})

def byCost(entries: List<&2, UsageCostBreakdownEntry>, sorted: List<&2, UsageCostBreakdownEntry>) -> List<&2, UsageCostBreakdownEntry>:
  match entries:
    case Nil{}: sorted
    case entry <> rest: byCost(rest, inserted(entry, sorted))

# Model-attributed usage by model and all other usage in one bucket, most
# expensive first.
def getUsageCostBreakdown(-D: Data, -T: Data, -C: Data, entries: List<&2, S.SessionEntry<D, T, C>>) -> List<&2, UsageCostBreakdownEntry>:
  byCost(meaningful(collected(D, T, C, entries, Nil{})), Nil{})
