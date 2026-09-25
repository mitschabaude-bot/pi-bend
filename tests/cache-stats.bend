import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as Agent
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/cache-stats.bend as Cache

# upstream test/cache-stats.test.ts. Misses are compared by entry id, which
# replaces upstream's message-reference keys; `toBeCloseTo(x, 5)` becomes an
# absolute difference below 5e-6.
def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def n(value: U32) -> F64: F.fromU32(value)
def ratio(top: U32, bottom: U32) -> F64: F.divide(F.fromU32(top), F.fromU32(bottom))
def close(+actual: F64, +expected: F64) -> Bool: F64.is_lt(F.maximum(F.subtract(actual, expected), F.subtract(expected, actual)), ratio(5, 1000000))
def same(+actual: F64, +expected: F64) -> Bool: F64.is_eq(actual, expected)

# $/million tokens, the cache-read price fallback on full-miss turns.
def models(source: Unit, provider: String) -> String -> Maybe<&2, F64>: _ => Some{ratio(3, 10)}

type Turn is Data: Turn{input: F64, cacheRead: F64, cacheWrite: F64, costRead: F64, costWrite: F64, model: String, timestamp: F64}
def zero() -> F64: n(0)
def assistant(turn: Turn) -> Ai.AssistantMessage<Schema.Value, Unit>:
  match turn:
    case Turn{input, cacheRead, cacheWrite, costRead, costWrite, model, timestamp}:
      Ai.AssistantMessage{Nil{}, "anthropic-messages", "test", model, None{}, None{}, None{}, None{}, Ai.Usage{input, n(10), cacheRead, cacheWrite, None{}, None{}, zero(), Ai.UsageCost{zero(), zero(), costRead, costWrite, zero()}}, Ai.Stop{}, None{}, None{}, None{}, None{}, timestamp}
def entryWith(+id: String, message: Ai.AssistantMessage<Schema.Value, Unit>) -> S.SessionEntry<Unit, Unit, Unit>:
  S.SessionMessageEntry{S.SessionEntryBase{id, None{}, ""}, Agent.LlmMessage{Ai.Assistant{message}}}
def entry(message: Ai.AssistantMessage<Schema.Value, Unit>) -> S.SessionEntry<Unit, Unit, Unit>: entryWith("x", message)
def reset() -> S.SessionEntry<Unit, Unit, Unit>:
  S.Compaction{S.CompactionEntry{S.SessionEntryBase{"c", None{}, ""}, "", "", 0n, None{}, None{}, None{}, None{}}}

# Turn 1: fresh 100k cache write at $3.75/M.
def turn1() -> Ai.AssistantMessage<Schema.Value, Unit>: assistant(Turn{zero(), zero(), n(100000), zero(), ratio(375, 1000), "test-model", zero()})
# Turn 2: healthy, everything read back at $0.30/M.
def turn2() -> Ai.AssistantMessage<Schema.Value, Unit>: assistant(Turn{zero(), n(100000), n(5000), ratio(3, 100), ratio(19, 1000), "test-model", n(60000)})
def missTurn(model: String, timestamp: F64) -> Ai.AssistantMessage<Schema.Value, Unit>:
  assistant(Turn{zero(), zero(), n(110000), zero(), ratio(4125, 10000), model, timestamp})
def healthyHistory() -> List<&2, S.SessionEntry<Unit, Unit, Unit>>: [entry(turn1()), entry(turn2())]

def waste(entries: List<&2, S.SessionEntry<Unit, Unit, Unit>>) -> Cache.CacheWasteTotals:
  Cache.computeCacheWaste(~Unit, ~models, Unit, Unit, Unit, Unit{}, entries)
def wasteTokens(totals: Cache.CacheWasteTotals) -> F64:
  match totals: case Cache.CacheWasteTotals{tokens, _, _}: tokens
def wasteCost(totals: Cache.CacheWasteTotals) -> F64:
  match totals: case Cache.CacheWasteTotals{_, cost, _}: cost
def wasteCount(totals: Cache.CacheWasteTotals) -> Nat:
  match totals: case Cache.CacheWasteTotals{_, _, count}: count

def missTokens(miss: Maybe<&2, Cache.CacheMiss>) -> F64:
  match miss:
    case Some{Cache.CacheMiss{tokens, _, _, _}}: tokens
    case None{}: n(4294967295)
def detected(message: Ai.AssistantMessage<Schema.Value, Unit>) -> Maybe<&2, Cache.CacheMiss>:
  Cache.detectCacheMiss(~Unit, ~models, Unit, Unit, Unit, Schema.Value, Unit{}, healthyHistory(), message)
def isNone(miss: Maybe<&2, Cache.CacheMiss>) -> Bool:
  match miss:
    case None{}: True{}
    case Some{_}: False{}

def computeCacheWaste() -> IO(Unit):
  +accumulated = waste([entry(turn1()), entry(turn2()), entry(missTurn("test-model", n(120000)))])
  +healthy = waste(healthyHistory())
  +afterReset = waste([entry(turn1()), reset(), entry(assistant(Turn{zero(), zero(), n(20000), zero(), ratio(75, 1000), "test-model", zero()}))])
  +switched = waste([entry(turn1()), entry(assistant(Turn{zero(), zero(), n(100000), zero(), ratio(375, 1000), "other-model", zero()}))])
  +uncached = waste([entry(assistant(Turn{n(100000), zero(), zero(), zero(), zero(), "test-model", zero()})), entry(assistant(Turn{n(110000), zero(), zero(), zero(), zero(), "test-model", zero()}))])
  do IO<Unit>:
    check(same(wasteTokens(accumulated), n(105000)) && close(wasteCost(accumulated), ratio(36225, 100000)), "accumulates missed tokens and cost across turns")
    check(same(wasteTokens(healthy), zero()) && same(wasteCost(healthy), zero()), "counts nothing for healthy sessions")
    check(same(wasteTokens(afterReset), zero()), "skips the turn after a compaction reset")
    check(same(wasteTokens(switched), n(100000)) && Nat.is_eq(wasteCount(switched), 1n), "counts misses caused by model switches")
    check(same(wasteTokens(uncached), zero()), "skips providers that report no cache activity")

def missFor(misses: List<&2, Cache.CacheMissEntry>, +id: String) -> Maybe<&2, Cache.CacheMiss>:
  match misses:
    case Nil{}: None{}
    case Cache.CacheMissEntry{+entryId, miss} <> rest: Bool.pick(Unit -> Maybe<&2, Cache.CacheMiss>, String.eq(entryId, id), _ => Some{miss}, _ => missFor(rest, id))(Unit{})

def collectCacheMisses() -> IO(Unit):
  +misses = Cache.collectCacheMisses(~Unit, ~models, Unit, Unit, Unit, Unit{}, [entryWith("t1", turn1()), entryWith("t2", turn2()), entryWith("miss", missTurn("test-model", n(120000)))])
  check(Nat.is_eq(List.length(&2, Cache.CacheMissEntry, misses), 1n) && same(missTokens(missFor(misses, "miss")), n(105000)), "maps counted misses to their assistant messages by reference")

def idleOf(miss: Maybe<&2, Cache.CacheMiss>) -> F64:
  match miss:
    case Some{Cache.CacheMiss{_, _, idle, _}}: idle
    case None{}: zero()
def costOf(miss: Maybe<&2, Cache.CacheMiss>) -> F64:
  match miss:
    case Some{Cache.CacheMiss{_, cost, _, _}}: cost
    case None{}: zero()
def changedOf(miss: Maybe<&2, Cache.CacheMiss>) -> Maybe<&2, Bool>:
  match miss:
    case Some{Cache.CacheMiss{_, _, _, changed}}: Some{changed}
    case None{}: None{}
def isFalse(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{False{}}: True{}
    case _: False{}
def isTrue(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{True{}}: True{}
    case _: False{}

def detectCacheMiss() -> IO(Unit):
  +idle = detected(missTurn("test-model", n(600000)))
  +switched = detected(missTurn("other-model", n(120000)))
  +healthy = detected(assistant(Turn{zero(), n(105000), n(2000), ratio(315, 10000), ratio(75, 10000), "test-model", n(120000)}))
  +first = Cache.detectCacheMiss(~Unit, ~models, Unit, Unit, Unit, Schema.Value, Unit{}, Nil{}, turn1())
  do IO<Unit>:
    check(same(missTokens(idle), n(105000)) && close(costOf(idle), ratio(36225, 100000)) && same(idleOf(idle), n(540000)) && isFalse(changedOf(idle)), "detects a miss on a just-completed message with idle time")
    check(same(missTokens(switched), n(105000)) && isTrue(changedOf(switched)), "flags model switches on detected misses")
    check(isNone(healthy), "returns undefined for healthy turns")
    check(isNone(first), "returns undefined for the first turn of a session")

def main() -> IO(Unit):
  do IO<Unit>:
    computeCacheWaste()
    collectCacheMisses()
    detectCacheMiss()
