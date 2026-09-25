import Base
import ../../../ai/src/types.bend as Ai
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/schema-value.bend as Schema
import ./session-manager.bend as S

# upstream core/cache-stats.ts: prompt-cache misses across a session.

# Idle gaps longer than the prompt-cache TTL are the likely cause of a miss
# (Anthropic's default TTL is 5 minutes).
def CACHE_TTL_MS() -> F64: F.fromU32(300000)

# Per-turn misses at or below this are cache breakpoint granularity noise.
def NOISE_FLOOR_TOKENS() -> F64: F.fromU32(1024)

# A counted cache miss on one assistant message: prompt tokens that were in
# the previous turn's prompt but not read from cache, the extra dollars paid
# for them (0 when pricing is unknown), the idle time since the previous
# request and whether the model changed.
type CacheMiss is Data: CacheMiss{missedTokens: F64, missedCost: F64, idleMs: F64, modelChanged: Bool}

type CacheWasteTotals is Data: CacheWasteTotals{missedTokens: F64, missedCost: F64, missCount: Nat}

# upstream's ModelPriceSource: a model's cache-read price in $ per million
# tokens by provider and model id, read from a source value (ModelRuntime
# satisfies it).
def ModelPriceSource(Source: Data) -> Type: Source -> String -> String -> Maybe<&2, F64>

# The last request of the scan; everything in its prompt should be cached.
# `reportedCache` is sticky within a scan segment: some earlier request
# reported cache activity, so a zero-cache turn on a cache-read-only provider
# is a total miss rather than a provider that never reports caching.
type PreviousRequest is Data: PreviousRequest{promptTokens: F64, modelKey: String, timestamp: F64, reportedCache: Bool}

def zero() -> F64: F.fromU32(0)
def promptTokensOf(usage: Ai.Usage) -> F64:
  match usage: case Ai.Usage{input, _, cacheRead, cacheWrite, _, _, _, _}: F.add(input, F.add(cacheRead, cacheWrite))
def cacheActivity(usage: Ai.Usage) -> F64:
  match usage: case Ai.Usage{_, _, cacheRead, cacheWrite, _, _, _, _}: F.add(cacheRead, cacheWrite)
def modelKeyOf(-A: Data, -D: Data, message: Ai.AssistantMessage<A, D>) -> String:
  match message: case Ai.AssistantMessage{_, _, provider, model, _, _, _, _, _, _, _, _, _, _, _}: provider ++ "/" ++ model

def paidPerToken(usage: Ai.Usage) -> F64:
  match usage:
    case Ai.Usage{+input, _, _, +cacheWrite, _, _, _, Ai.UsageCost{costInput, _, _, costWrite, _}}:
      +paid = F.add(input, cacheWrite)
      Bool.pick(F64, F64.is_gt(paid, zero()), F.divide(F.add(costInput, costWrite), paid), zero())

def listedReadRate(price: Maybe<&2, F64>) -> F64:
  F.divide(Maybe.default(&2, F64, price, zero()), F.fromU32(1000000))

def readPerToken(~Source: Data, ~prices: ModelPriceSource(Source), -A: Data, -D: Data, +source: Source, message: Ai.AssistantMessage<A, D>) -> F64:
  match message:
    case Ai.AssistantMessage{_, _, provider, model, _, _, _, _, Ai.Usage{_, _, +cacheRead, _, _, _, _, Ai.UsageCost{_, _, costRead, _, _}}, _, _, _, _, _, _}:
      Bool.pick(Unit -> F64, F64.is_gt(cacheRead, zero()), _ => F.divide(costRead, cacheRead), _ => listedReadRate(prices(source)(provider)(model)))(Unit{})

def countedMiss(~Source: Data, ~prices: ModelPriceSource(Source), -A: Data, -D: Data, +source: Source, +missedTokens: F64, previous: PreviousRequest, +message: Ai.AssistantMessage<A, D>) -> Maybe<&2, CacheMiss>:
  match previous message:
    case PreviousRequest{_, modelKey, before, _} Ai.AssistantMessage{_, _, _, _, _, _, _, _, usage, _, _, _, _, _, timestamp}:
      Bool.pick(Unit -> Maybe<&2, CacheMiss>, F64.is_gt(missedTokens, NOISE_FLOOR_TOKENS()),
        _ => Some{CacheMiss{missedTokens, F.multiply(missedTokens, F.maximum(zero(), F.subtract(paidPerToken(usage), readPerToken(~Source, ~prices, A, D, source, message)))), F.maximum(zero(), F.subtract(timestamp, before)), Bool.not(String.eq(modelKeyOf(A, D, message), modelKey))}},
        _ => None{})(Unit{})

def readTokens(usage: Ai.Usage) -> F64:
  match usage: case Ai.Usage{_, _, cacheRead, _, _, _, _, _}: cacheRead

# The miss of one assistant message relative to the previous request; none on
# the first turn, after a reset, when no cache activity was ever reported, or
# below the noise floor.
def detectMiss(~Source: Data, ~prices: ModelPriceSource(Source), -A: Data, -D: Data, +source: Source, previous: Maybe<&2, PreviousRequest>, +message: Ai.AssistantMessage<A, D>) -> Maybe<&2, CacheMiss>:
  match previous:
    case None{}: None{}
    case Some{PreviousRequest{+promptBefore, modelKey, before, +reported}}:
      +usage = Ai.assistantUsage(A, D, message)
      +prompt = promptTokensOf(usage)
      Bool.pick(Unit -> Maybe<&2, CacheMiss>, Bool.not(F64.is_gt(prompt, zero())) || (Bool.not(F64.is_gt(cacheActivity(usage), zero())) && Bool.not(reported)),
        _ => None{},
        _ => countedMiss(~Source, ~prices, A, D, source, F.subtract(F.minimum(promptBefore, prompt), readTokens(usage)), PreviousRequest{promptBefore, modelKey, before, reported}, message))(Unit{})

def asPreviousRequest(-A: Data, -D: Data, +message: Ai.AssistantMessage<A, D>, reportedCache: Bool) -> Maybe<&2, PreviousRequest>:
  +usage = Ai.assistantUsage(A, D, message)
  +prompt = promptTokensOf(usage)
  Bool.pick(Unit -> Maybe<&2, PreviousRequest>, F64.is_gt(prompt, zero()),
    _ => Some{PreviousRequest{prompt, modelKeyOf(A, D, message), Ai.assistantTimestamp(A, D, message), reportedCache || F64.is_gt(cacheActivity(usage), zero())}},
    _ => None{})(Unit{})

def reportedOf(previous: Maybe<&2, PreviousRequest>) -> Bool:
  match previous:
    case Some{PreviousRequest{_, _, _, reported}}: reported
    case None{}: False{}

# Misses are keyed by the entry id of the assistant message that paid them
# (upstream keys the message object itself).
type CacheMissEntry is Data: CacheMissEntry{entryId: String, miss: CacheMiss}
type Scan is Data: Scan{previous: Maybe<&2, PreviousRequest>, totals: CacheWasteTotals, misses: List<&2, CacheMissEntry>}

def counted(totals: CacheWasteTotals, miss: CacheMiss) -> CacheWasteTotals:
  match totals miss:
    case CacheWasteTotals{tokens, cost, count} CacheMiss{missedTokens, missedCost, _, _}: CacheWasteTotals{F.add(tokens, missedTokens), F.add(cost, missedCost), count + 1n}

def recorded(+id: String, miss: Maybe<&2, CacheMiss>, next: Maybe<&2, PreviousRequest>, totals: CacheWasteTotals, misses: List<&2, CacheMissEntry>) -> Scan:
  match miss:
    case None{}: Scan{next, totals, misses}
    case Some{+found}: Scan{next, counted(totals, found), CacheMissEntry{id, found} <> misses}

def assistantStep(~Source: Data, ~prices: ModelPriceSource(Source), -A: Data, -D: Data, +source: Source, +id: String, +message: Ai.AssistantMessage<A, D>, scan: Scan) -> Scan:
  match scan:
    case Scan{+previous, totals, misses}:
      recorded(id, detectMiss(~Source, ~prices, A, D, source, previous, message), Maybe.or(&2, PreviousRequest, asPreviousRequest(A, D, message, reportedOf(previous)), previous), totals, misses)

def resetScan(scan: Scan) -> Scan:
  match scan: case Scan{_, totals, misses}: Scan{None{}, totals, misses}

# Compactions and branch summaries change the context legitimately, so the
# next prompt is new content; model switches are not exempt.
def scanStep(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, +source: Source, entry: S.SessionEntry<D, T, C>, scan: Scan) -> Scan:
  match entry:
    case S.Compaction{_}: resetScan(scan)
    case S.BranchSummaryEntry{_, _, _, _, _, _}: resetScan(scan)
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, Agent.LlmMessage{Ai.Assistant{message}}}: assistantStep(~Source, ~prices, Schema.Value, D, source, id, message, scan)
    case _: scan

def scanned(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, +source: Source, entries: List<&2, S.SessionEntry<D, T, C>>, scan: Scan) -> Scan:
  match entries:
    case Nil{}: scan
    case entry <> rest: scanned(~Source, ~prices, D, T, C, source, rest, scanStep(~Source, ~prices, D, T, C, source, entry, scan))

def scan(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, +source: Source, entries: List<&2, S.SessionEntry<D, T, C>>) -> Scan:
  scanned(~Source, ~prices, D, T, C, source, entries, Scan{None{}, CacheWasteTotals{zero(), zero(), 0n}, Nil{}})

def totalsOf(value: Scan) -> CacheWasteTotals:
  match value: case Scan{_, totals, _}: totals
def missesOf(value: Scan) -> List<&2, CacheMissEntry>:
  match value: case Scan{_, _, misses}: misses
def previousOf(value: Scan) -> Maybe<&2, PreviousRequest>:
  match value: case Scan{previous, _, _}: previous

# Cumulative cache waste: prompt tokens that should have been cache reads
# but were re-billed.
def computeCacheWaste(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, +source: Source, entries: List<&2, S.SessionEntry<D, T, C>>) -> CacheWasteTotals:
  totalsOf(scan(~Source, ~prices, D, T, C, source, entries))

# Every counted miss, in session order (transcript notices when rebuilding).
def collectCacheMisses(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, +source: Source, entries: List<&2, S.SessionEntry<D, T, C>>) -> List<&2, CacheMissEntry>:
  List.reverse(&2, CacheMissEntry, missesOf(scan(~Source, ~prices, D, T, C, source, entries)))

# The miss of a just-completed assistant message; `entries` does not yet
# contain it (message_end precedes persistence).
def detectCacheMiss(~Source: Data, ~prices: ModelPriceSource(Source), -D: Data, -T: Data, -C: Data, -A: Data, +source: Source, entries: List<&2, S.SessionEntry<D, T, C>>, +message: Ai.AssistantMessage<A, D>) -> Maybe<&2, CacheMiss>:
  detectMiss(~Source, ~prices, A, D, source, previousOf(scan(~Source, ~prices, D, T, C, source, entries)), message)
