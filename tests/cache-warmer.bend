import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/providers/anthropic.models.bend as Anthropic
import ../packages/ai/src/providers/openai.models.bend as OpenAI
import ../packages/agent/src/types.bend as Agent
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/deferred.bend as D
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/timer.bend as Sleep
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/cache-warmer.bend as W
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools

# upstream test/cache-warmer.test.ts. The warmer is a pure state machine
# whose transitions take the clock, mode, conversation and prompt size as
# values; upstream's fake timers become explicit observation times (a timer
# armed for `delay` fires at `start + delay`). Calls, decision events and
# usage records are the transitions' effects. The I/O shell is exercised
# separately with real timers and a ten-second cache lifetime.

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def n(value: U32) -> F64: F.fromU32(value)
def zero() -> F64: n(0)
def ratio(top: U32, bottom: U32) -> F64: F.divide(n(top), n(bottom))
def same(+actual: F64, +expected: F64) -> Bool: F64.is_eq(actual, expected)
# toBeCloseTo's default precision: an absolute difference below 0.005.
def close(+actual: F64, +expected: F64) -> Bool: F64.is_lt(F.maximum(F.subtract(actual, expected), F.subtract(expected, actual)), ratio(5, 1000))

def Options() -> Data: W.Options()
def Model() -> Data: Ai.Model<Ai.JsonValue>

def withCache(model: Model(), cache: Maybe<&2, Ai.ModelPromptCache>) -> Model():
  match model:
    case Ai.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, _, window, maxTokens, sampling, headers, compat}:
      Ai.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def lifetimes(short: U32, long: U32) -> Maybe<&2, Ai.ModelPromptCache>: Some{Ai.ModelPromptCache{Some{n(short)}, Some{n(long)}}}
def adaptiveModel() -> Model(): withCache(Anthropic.model_claude_opus_4_6(), lifetimes(300, 3600))
def budgetModel() -> Model(): withCache(Anthropic.model_claude_sonnet_4_5(), lifetimes(300, 3600))
def openaiModel() -> Model(): withCache(OpenAI.model_gpt_5(), lifetimes(300, 86400))
def unknownModel() -> Model(): withCache(adaptiveModel(), None{})

def warmUsage() -> Ai.Usage: Ai.Usage{zero(), n(1), n(100), zero(), None{}, None{}, n(101), Ai.UsageCost{zero(), zero(), ratio(1, 100), zero(), ratio(1, 100)}}

def response(model: Model(), stop: Ai.StopReason) -> Ai.AssistantMessage<V.Value, Unit>:
  match model:
    case Ai.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: Ai.AssistantMessage{Nil{}, "anthropic-messages", provider, id, None{}, None{}, None{}, None{}, warmUsage(), stop, None{}, None{}, None{}, None{}, zero()}

def Entry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

# A branch whose last request had `prompt` cached prompt tokens.
def branchWithPrompt(+prompt: U32) -> List<&2, Entry()>:
  [S.SessionMessageEntry{S.SessionEntryBase{"a", None{}, "1970-01-01T00:00:00.000Z"}, Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Nil{}, "anthropic-messages", "anthropic", "claude-opus-4-6", None{}, None{}, None{}, None{}, Ai.Usage{zero(), n(10), n(prompt), zero(), None{}, None{}, F.add(n(prompt), n(10)), Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}, Ai.Length{}, None{}, None{}, None{}, None{}, zero()}}}}]

def options(signal: Maybe<&2, A.AbortSignal<Unit>>, reasoning: Maybe<&2, Ai.ThinkingLevel>, sessionId: Maybe<&2, String>, retention: Maybe<&2, Ai.CacheRetention>, env: Maybe<&2, Ai.ProviderEnv()>) -> Options():
  Ai.SimpleStreamOptions{signal, None{}, None{}, None{}, env, None{}, None{}, Some{Record.new(Ai.Nullable<String>)}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, sessionId, None{}, None{}, None{}, reasoning, None{}, None{}}

def plain() -> Options(): options(None{}, None{}, None{}, None{}, None{})

def config(+converter: Runtime.Converter(), options: Options(), model: Model()) -> Runtime.LoopConfig():
  Agent.AgentLoopConfig{options, model, converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def request(+converter: Runtime.Converter(), +model: Model(), options: Options()) -> W.CacheWarmRequest:
  W.CacheWarmRequest{model, Ai.TranscriptContext{Nil{}}, config(converter, options, model)}

def userMessage(text: String) -> W.Message(): Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, zero()}}}
def conversation() -> W.CacheContext: W.CacheContext{"anthropic", "claude-opus-4-6", [userMessage("hello")]}
def changed() -> W.CacheContext: W.CacheContext{"anthropic", "claude-opus-4-6", [userMessage("edited")]}

def observation(mode: Settings.CacheWarmingMode, now: F64, context: W.CacheContext, prompt: U32) -> W.Observation:
  W.Observation{mode, now, context, W.lastPromptTokens(Unit, Tools.ToolDetails, V.Value, branchWithPrompt(prompt))}
def idle(now: F64, prompt: U32) -> W.Observation: observation(Settings.CacheWarmingIdle{}, now, conversation(), prompt)

# The pure run of the warmer: its state, the replayed requests, the decision
# events, the recorded usage and the worker's next action.
type Trace is Data:
  Trace{state: W.Warmer, calls: List<&2, W.CacheWarmRequest>, events: List<&2, W.CacheWarmingDecisionEvent>, records: List<&2, W.UsageRecord>, next: W.Next}

def withRecord(records: List<&2, W.UsageRecord>, record: Maybe<&2, W.UsageRecord>) -> List<&2, W.UsageRecord>:
  match record:
    case None{}: records
    case Some{value}: List.append(&2, W.UsageRecord, records, [value])

def afterReplay(calls: List<&2, W.CacheWarmRequest>, events: List<&2, W.CacheWarmingDecisionEvent>, records: List<&2, W.UsageRecord>, pair: W.Warmer & W.Step) -> Trace:
  match pair:
    case (state, W.Step{_, record, next}): Trace{state, calls, events, withRecord(records, record), next}

def afterDecision(generation: Nat, calls: List<&2, W.CacheWarmRequest>, events: List<&2, W.CacheWarmingDecisionEvent>, records: List<&2, W.UsageRecord>, message: Ai.AssistantMessage<V.Value, Unit>, replayedAt: W.Observation, pair: W.Warmer & W.Step) -> Trace:
  match pair:
    case (state, W.Step{_, record, W.Replay{+sent}}): afterReplay(List.append(&2, W.CacheWarmRequest, calls, [sent]), events, withRecord(records, record), W.replayed(state, generation, message, replayedAt))
    case (state, W.Step{_, record, next}): Trace{state, calls, events, withRecord(records, record), next}

# One timer expiry: fire, ask `decide`, replay and record, each transition at
# its own observation.
def afterFired(+generation: Nat, calls: List<&2, W.CacheWarmRequest>, events: List<&2, W.CacheWarmingDecisionEvent>, records: List<&2, W.UsageRecord>, decide: W.CacheWarmingDecisionEvent -> W.CacheWarmingAction, decidedAt: W.Observation, message: Ai.AssistantMessage<V.Value, Unit>, replayedAt: W.Observation, pair: W.Warmer & W.Step) -> Trace:
  match pair:
    case (fired, W.Step{_, _, W.Decide{+event}}): afterDecision(generation, calls, List.append(&2, W.CacheWarmingDecisionEvent, events, [event]), records, message, replayedAt, W.decided(fired, generation, decide(event), decidedAt))
    case (fired, W.Step{_, _, next}): Trace{fired, calls, events, records, next}

def refresh(trace: Trace, +generation: Nat, firedAt: W.Observation, decide: W.CacheWarmingDecisionEvent -> W.CacheWarmingAction, decidedAt: W.Observation, message: Ai.AssistantMessage<V.Value, Unit>, replayedAt: W.Observation) -> Trace:
  match trace:
    case Trace{state, calls, events, records, _}: afterFired(generation, calls, events, records, decide, decidedAt, message, replayedAt, W.fired(state, generation, firedAt))

def piDecides(event: W.CacheWarmingDecisionEvent) -> W.CacheWarmingAction: W.eventAction(event)
def alwaysWarm(event: W.CacheWarmingDecisionEvent) -> W.CacheWarmingAction: W.Warm{}
def alwaysStop(event: W.CacheWarmingDecisionEvent) -> W.CacheWarmingAction: W.Stop{}

# A start: the state, whether a previous run was replaced, and the new run's
# first timer (Exit when nothing was armed).
type Begun is Data:
  Begun{state: W.Warmer, previous: Bool, next: W.Next}

def begun(pair: W.Warmer & W.Started) -> Begun:
  match pair:
    case (state, W.Started{previous, Some{W.Launch{_, delay}}}): Begun{state, Maybe.is_some(&2, A.AbortController<Unit>, previous), W.Wait{delay}}
    case (state, W.Started{previous, None{}}): Begun{state, Maybe.is_some(&2, A.AbortController<Unit>, previous), W.Exit{}}

def startedState(value: Begun) -> W.Warmer:
  match value:
    case Begun{state, _, _}: state

def previousOf(value: Begun) -> Bool:
  match value:
    case Begun{_, previous, _}: previous

def launched(value: Begun) -> Trace:
  match value:
    case Begun{state, _, next}: Trace{state, Nil{}, Nil{}, Nil{}, next}

def startIn(state: W.Warmer, +converter: Runtime.Converter(), controller: A.AbortController<Unit>, mode: Settings.CacheWarmingMode, now: F64, +model: Model(), options: Options(), context: W.CacheContext) -> IO(Begun):
  do IO<Begun>:
    +sent : W.CacheWarmRequest = request(converter, model, options)
    facts : W.StartFacts <- W.startFacts(mode, now, sent)
    return begun(W.started(state, sent, context, controller, facts))

def reason(status: W.CacheWarmingStatus) -> String:
  match status:
    case W.CacheWarmingStatus{_, Some{text}, _, _, _}: text
    case _: ""

def isInactive(status: W.CacheWarmingStatus) -> Bool:
  match status:
    case W.CacheWarmingStatus{W.Inactive{}, _, _, _, _}: True{}
    case _: False{}

def overridden(status: W.CacheWarmingStatus) -> Bool:
  match status:
    case W.CacheWarmingStatus{_, _, _, _, extensionOverride}: extensionOverride

def stoppedEconomic(status: W.CacheWarmingStatus) -> Bool:
  match status:
    case W.CacheWarmingStatus{W.Inactive{}, _, _, Some{W.CacheWarmingDecision{_, _, _, _, _, True{}, W.Stop{}}}, False{}}: True{}
    case _: False{}

def stateOf(trace: Trace) -> W.Warmer:
  match trace:
    case Trace{state, _, _, _, _}: state
def callCount(trace: Trace) -> Nat:
  match trace:
    case Trace{_, calls, _, _, _}: List.length(&2, W.CacheWarmRequest, calls)
def eventsOf(trace: Trace) -> List<&2, W.CacheWarmingDecisionEvent>:
  match trace:
    case Trace{_, _, events, _, _}: events
def recordsOf(trace: Trace) -> List<&2, W.UsageRecord>:
  match trace:
    case Trace{_, _, _, records, _}: records
def callsOf(trace: Trace) -> List<&2, W.CacheWarmRequest>:
  match trace:
    case Trace{_, calls, _, _, _}: calls
def waitOf(trace: Trace) -> Maybe<&2, F64>:
  match trace:
    case Trace{_, _, _, _, W.Wait{delay}}: Some{delay}
    case _: None{}

def isNothing(value: Maybe<&2, F64>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}
def isSome(value: Maybe<&2, F64>, +expected: F64) -> Bool:
  match value:
    case Some{actual}: same(actual, expected)
    case None{}: False{}

def eligibility() -> IO(Unit):
  do IO<Unit>:
    defaultShort : Maybe<&2, F64> <- W.getPromptCacheTtlMs(adaptiveModel(), None{})
    long : Maybe<&2, F64> <- W.getPromptCacheTtlMs(adaptiveModel(), Some{options(None{}, None{}, None{}, Some{Ai.CacheLong{}}, None{})})
    none : Maybe<&2, F64> <- W.getPromptCacheTtlMs(adaptiveModel(), Some{options(None{}, None{}, None{}, Some{Ai.CacheNone{}}, None{})})
    fromEnv : Maybe<&2, F64> <- W.getPromptCacheTtlMs(adaptiveModel(), Some{options(None{}, None{}, None{}, None{}, Some{Record.set(String, Record.new(String), "PI_CACHE_RETENTION", "long")})})
    openaiLong : Maybe<&2, F64> <- W.getPromptCacheTtlMs(openaiModel(), Some{options(None{}, None{}, None{}, Some{Ai.CacheLong{}}, None{})})
    unknown : Maybe<&2, F64> <- W.getPromptCacheTtlMs(unknownModel(), None{})
    check(isSome(defaultShort, n(300000)) && isSome(long, n(3600000)) && isNothing(none) && isSome(fromEnv, n(3600000)) && isSome(openaiLong, n(86400000)) && isNothing(unknown)
      && isSome(W.getCacheWarmingDelayMs(n(300000)), n(270000)) && isSome(W.getCacheWarmingDelayMs(n(60000)), n(50000)) && isNothing(W.getCacheWarmingDelayMs(n(10000)))
      && Bool.not(W.isReplayable(budgetModel(), Some{options(None{}, Some{Ai.Medium{}}, None{}, None{}, None{})})) && W.isReplayable(budgetModel(), None{})
      && W.isReplayable(adaptiveModel(), Some{options(None{}, Some{Ai.Medium{}}, None{}, None{}, None{})}) && W.isReplayable(openaiModel(), Some{options(None{}, Some{Ai.Medium{}}, None{}, None{}, None{})}),
      "derives eligibility and timing from retention and provider behavior")

def replayOptions(sent: W.CacheWarmRequest) -> Options():
  match sent:
    case W.CacheWarmRequest{_, _, Agent.AgentLoopConfig{value, _, _, _, _, _, _, _, _, _, _, _, _}}: value

def isHigh(level: Maybe<&2, Ai.ThinkingLevel>) -> Bool:
  match level:
    case Some{Ai.High{}}: True{}
    case _: False{}
def isText(value: Maybe<&2, String>, +expected: String) -> Bool:
  match value:
    case Some{text}: String.eq(text, expected)
    case None{}: False{}
def isNumber(value: Maybe<&2, F64>, +expected: F64) -> Bool: isSome(value, expected)

# Signals are compared by the identity of their settlement channel.
def settlementRef(signal: A.AbortSignal<Unit>) -> R.Ref<D.State<A.AbortReason<Unit>>>:
  match signal:
    case A.AbortSignal{D.Deferred{state}}: state

# The replay keeps the request's options (reasoning, session id, headers)
# and caps output at one token without retries under the run's own signal.
def preserved(value: Options(), +original: A.AbortSignal<Unit>) -> Bool:
  match value:
    case Ai.SimpleStreamOptions{Some{signal}, _, _, _, _, _, _, Some{_}, _, maxRetries, _, _, _, maxTokens, _, _, sessionId, _, _, _, reasoning, _, _}:
      Bool.not(R.same(D.State<A.AbortReason<Unit>>, settlementRef(signal), settlementRef(original))) && isNumber(maxRetries, zero()) && isNumber(maxTokens, n(1)) && isText(sessionId, "s") && isHigh(reasoning)
    case _: False{}

def firstPreserved(calls: List<&2, W.CacheWarmRequest>, +original: A.AbortSignal<Unit>) -> Bool:
  match calls:
    case sent <> _: preserved(replayOptions(sent), original)
    case Nil{}: False{}

def firstEvent(events: List<&2, W.CacheWarmingDecisionEvent>) -> Bool:
  match events:
    case W.CacheWarmingDecisionEvent{warmCost, missCost, probability, W.Warm{}} <> _: same(probability, n(1)) && close(missCost, ratio(575, 1000)) && close(warmCost, ratio(50025, 1000000))
    case _: False{}

def recordedWarm(records: List<&2, W.UsageRecord>) -> Bool:
  match records:
    case W.UsageRecord{kind, provider, model, Ai.Usage{input, output, read, write, _, _, total, Ai.UsageCost{_, _, _, _, cost}}, None{}} <> Nil{}:
      String.eq(kind, "cache_warm") && String.eq(provider, "anthropic") && String.eq(model, "claude-opus-4-6") && same(input, zero()) && same(output, n(1)) && same(read, n(100)) && same(write, zero()) && same(total, n(101)) && same(cost, ratio(1, 100))
    case _: False{}

def replays(+converter: Runtime.Converter(), +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +original : A.AbortController<Unit> <- A.new(Unit)
    +started : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), options(Some{A.signal(Unit, original)}, Some{Ai.High{}}, Some{"s"}, None{}, None{}), conversation())
    +first : Trace = refresh(launched(started), 1n, idle(n(270000), 100000), piDecides, idle(n(270000), 100000), response(adaptiveModel(), Ai.Length{}), idle(n(270000), 100000))
    +second : Trace = refresh(first, 1n, idle(n(540000), 100000), piDecides, idle(n(540000), 100000), response(adaptiveModel(), Ai.Length{}), idle(n(540000), 100000))
    check(isSome(waitOf(launched(started)), n(270000)) && firstPreserved(callsOf(first), A.signal(Unit, original)) && firstEvent(eventsOf(first)) && recordedWarm(recordsOf(first)) && isSome(waitOf(first), n(270000)) && Nat.is_eq(callCount(second), 2n),
      "replays profitable requests and preserves options across repeated refreshes")

def deadlines(+converter: Runtime.Converter(), +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +started : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +late : Trace = refresh(launched(started), 1n, idle(n(285001), 100000), piDecides, idle(n(285001), 100000), response(adaptiveModel(), Ai.Length{}), idle(n(285001), 100000))
    check(Nat.is_eq(callCount(late), 0n) && isInactive(W.statusOf(stateOf(late), idle(n(285001), 100000))) && String.eq(reason(W.statusOf(stateOf(late), idle(n(285001), 100000))), "cache refresh deadline missed"),
      "does not issue refreshes after their safe deadline")
    +again : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +rechecked : Trace = refresh(launched(again), 1n, idle(zero(), 100000), alwaysWarm, idle(n(285001), 100000), response(adaptiveModel(), Ai.Length{}), idle(n(285001), 100000))
    check(Nat.is_eq(callCount(rechecked), 0n) && String.eq(reason(W.statusOf(stateOf(rechecked), idle(n(285001), 100000))), "cache refresh deadline missed"),
      "rechecks the deadline after an extension decision")

def firstNote(records: List<&2, W.UsageRecord>) -> Bool:
  match records:
    case W.UsageRecord{_, _, _, _, Some{note}} <> _: String.eq(note, "extension override")
    case _: False{}

def economics(+converter: Runtime.Converter(), +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +unprofitableStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +unprofitable : Trace = refresh(launched(unprofitableStart), 1n, idle(n(270000), 5000), piDecides, idle(n(270000), 5000), response(adaptiveModel(), Ai.Length{}), idle(n(270000), 5000))
    +forcedStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +forced : Trace = refresh(launched(forcedStart), 1n, idle(n(270000), 5000), alwaysWarm, idle(n(270000), 5000), response(adaptiveModel(), Ai.Length{}), idle(n(270000), 5000))
    +vetoedStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +vetoed : Trace = refresh(launched(vetoedStart), 1n, idle(n(270000), 100000), alwaysStop, idle(n(270000), 100000), response(adaptiveModel(), Ai.Length{}), idle(n(270000), 100000))
    +unavailableStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +unavailable : Trace = refresh(launched(unavailableStart), 1n, idle(n(270000), 0), piDecides, idle(n(270000), 0), response(adaptiveModel(), Ai.Length{}), idle(n(270000), 0))
    check(Nat.is_eq(callCount(unprofitable), 0n) && stoppedEconomic(W.statusOf(stateOf(unprofitable), idle(n(270000), 5000)))
      && Nat.is_eq(callCount(forced), 1n) && firstNote(recordsOf(forced))
      && Nat.is_eq(callCount(vetoed), 0n) && isInactive(W.statusOf(stateOf(vetoed), idle(n(270000), 100000))) && overridden(W.statusOf(stateOf(vetoed), idle(n(270000), 100000)))
      && isInactive(W.statusOf(startedState(unavailableStart), idle(zero(), 0))) && String.eq(reason(W.statusOf(startedState(unavailableStart), idle(zero(), 0))), "cache economics unavailable") && Nat.is_eq(callCount(unavailable), 0n),
      "applies economic decisions and extension overrides")

def off(now: F64) -> W.Observation: observation(Settings.CacheWarmingOff{}, now, conversation(), 100000)

def stops(+converter: Runtime.Converter(), +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +disabled : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingOff{}, zero(), adaptiveModel(), plain(), conversation())
    +disabledState : W.Warmer = startedState(disabled)
    +unknown : Begun <- startIn(disabledState, converter, controller, Settings.CacheWarmingIdle{}, zero(), unknownModel(), plain(), conversation())
    +unknownState : W.Warmer = startedState(unknown)
    +budget : Begun <- startIn(unknownState, converter, controller, Settings.CacheWarmingIdle{}, zero(), budgetModel(), options(None{}, Some{Ai.High{}}, None{}, None{}, None{}), conversation())
    +budgetState : W.Warmer = startedState(budget)
    +current : Begun <- startIn(budgetState, converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +moved : W.Observation = observation(Settings.CacheWarmingIdle{}, zero(), changed(), 100000)
    +afterChange : Trace = refresh(launched(current), 1n, observation(Settings.CacheWarmingIdle{}, n(270000), changed(), 100000), piDecides, moved, response(adaptiveModel(), Ai.Length{}), moved)
    +restarted : Begun <- startIn(stateOf(afterChange), converter, controller, Settings.CacheWarmingIdle{}, n(270000), adaptiveModel(), plain(), conversation())
    +afterOff : Trace = refresh(launched(restarted), 2n, off(n(540000)), piDecides, off(n(540000)), response(adaptiveModel(), Ai.Length{}), off(n(540000)))
    +streamingStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingStreaming{}, zero(), adaptiveModel(), plain(), conversation())
    +settled : W.Warmer = Pair.fst(W.Warmer, Maybe<&2, A.AbortController<Unit>>, W.settledState(startedState(streamingStart), Settings.CacheWarmingStreaming{}, zero()))
    check(String.eq(reason(W.statusOf(disabledState, off(zero()))), "cache warming disabled")
      && String.eq(reason(W.statusOf(unknownState, idle(zero(), 100000))), "cache lifetime unavailable")
      && String.eq(reason(W.statusOf(budgetState, idle(zero(), 100000))), "request cannot be replayed safely")
      && String.eq(reason(W.statusOf(startedState(current), moved)), "conversation context changed")
      && Nat.is_eq(callCount(afterChange), 0n) && Nat.is_eq(callCount(afterOff), 0n)
      && String.eq(reason(W.statusOf(settled, observation(Settings.CacheWarmingStreaming{}, zero(), conversation(), 400000))), "agent run settled"),
      "stops for unsupported requests, context changes, and mode changes")

def exited(pair: W.Warmer & W.Step) -> Bool:
  match pair:
    case (_, W.Step{None{}, None{}, W.Exit{}}): True{}
    case _: False{}

def replaced(+converter: Runtime.Converter(), +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +pendingStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +fired : W.Warmer = Pair.fst(W.Warmer, W.Step, W.fired(startedState(pendingStart), 1n, idle(n(270000), 100000)))
    +inFlight : W.Warmer = Pair.fst(W.Warmer, W.Step, W.decided(fired, 1n, W.Warm{}, idle(n(270000), 100000)))
    +replacement : Begun <- startIn(inFlight, converter, controller, Settings.CacheWarmingIdle{}, n(270000), adaptiveModel(), plain(), conversation())
    +failedStart : Begun <- startIn(W.initial(), converter, controller, Settings.CacheWarmingIdle{}, zero(), adaptiveModel(), plain(), conversation())
    +failed : Trace = refresh(launched(failedStart), 1n, idle(n(270000), 100000), piDecides, idle(n(270000), 100000), response(adaptiveModel(), Ai.Error{}), idle(n(270000), 100000))
    check(previousOf(replacement) && exited(W.replayed(startedState(replacement), 1n, response(adaptiveModel(), Ai.Length{}), idle(n(270000), 100000))) && Nat.is_eq(callCount(failed), 1n) && List.is_empty(&2, W.UsageRecord, recordsOf(failed)) && isSome(waitOf(failed), n(270000)),
      "aborts replaced requests and does not record failed refreshes")

def leafText(entry: Maybe<&2, Entry()>) -> String:
  match entry:
    case Some{S.UsageEntry{_, _, _, _, usage, note}}: W.formatCacheWarmingUsage(note, usage)
    case _: ""

def usageText(appended: Result<&2, &2, S.Error, S.SessionManager<Unit, Tools.ToolDetails, V.Value>>) -> String:
  match appended:
    case Done{state}: leafText(S.getLeafEntry(Unit, Tools.ToolDetails, V.Value, state))
    case Fail{_}: ""

def formats() -> IO(Unit):
  do IO<Unit>:
    +decision : W.CacheWarmingDecision = W.CacheWarmingDecision{W.Idle{}, ratio(13, 1000), ratio(621, 1000), ratio(6, 10), ratio(36, 100), True{}, W.Warm{}}
    +usage : Ai.Usage = Ai.Usage{zero(), n(1), n(100), zero(), None{}, None{}, n(101), Ai.UsageCost{ratio(4, 100000), ratio(5, 100000), ratio(2940725, 100000000), zero(), ratio(2949725, 100000000)}}
    appended : Result<&2, &2, S.Error, S.SessionManager<Unit, Tools.ToolDetails, V.Value>> = Result.bind(&2, &2, S.Error, S.SessionManager<Unit, Tools.ToolDetails, V.Value>, S.SessionManager<Unit, Tools.ToolDetails, V.Value>, S.inMemory(Unit, Tools.ToolDetails, V.Value, S.SessionHeader{Some{3n}, "session", "1970-01-01T00:00:00.000Z", "/tmp", None{}}), state => S.appendUsage(Unit, Tools.ToolDetails, V.Value, state, S.EntryStamp{"u", "1970-01-01T00:00:00.000Z"}, "cache_warm", "anthropic", "claude-opus-4-6", usage, Some{"extension override"}))
    check(String.eq(W.formatCacheWarmingStatus(W.CacheWarmingStatus{W.Scheduled{}, None{}, Some{n(222000)}, Some{decision}, False{}}, zero()), "Decision in 3m 42s (60% continuation probability, expected savings $0.360 >= $0.050 -> warm)")
      && String.eq(usageText(appended), "Cache warmed (extension override): $0.029497"),
      "formats status and usage entries")


# The I/O shell with real timers: a 10.05-second cache lifetime arms each
# refresh 50 ms after the previous one.
def shortModel() -> Model(): withCache(adaptiveModel(), Some{Ai.ModelPromptCache{Some{ratio(1005, 100)}, None{}}})

# A blocking fake holds each request until its signal aborts and counts the
# aborts it observed (a retired run's signal is disposed with its worker).
type Fake is Data:
  Fake{calls: R.Ref<List<&2, W.CacheWarmRequest>>, records: R.Ref<List<&2, W.UsageRecord>>, warmed: R.Ref<List<&2, Entry()>>, aborts: R.Ref<Nat>, blocking: Bool}

def signalOption(options: Options()) -> Maybe<&2, A.AbortSignal<Unit>>:
  match options:
    case Ai.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: signal

def signalIn(sent: W.CacheWarmRequest) -> Maybe<&2, A.AbortSignal<Unit>>: signalOption(replayOptions(sent))

def waitAborted(signal: Maybe<&2, A.AbortSignal<Unit>>) -> IO(Unit):
  match signal:
    case None{}: IO.pure(Unit, Unit{})
    case Some{A.AbortSignal{settlement}}:
      do IO<Unit>:
        reason : A.AbortReason<Unit> <- D.result(A.AbortReason<Unit>, settlement)
        return Unit{}

def settle(blocking: Bool, aborts: R.Ref<Nat>, +sent: W.CacheWarmRequest) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match blocking:
    case False{}: IO.pure(Ai.AssistantMessage<V.Value, Unit>, response(shortModel(), Ai.Length{}))
    case True{}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        waitAborted(signalIn(sent))
        R.modify(Nat, Unit, aborts, count => (count + 1n, Unit{}))
        return response(shortModel(), Ai.Aborted{})

def recordedCall(calls: R.Ref<List<&2, W.CacheWarmRequest>>, aborts: R.Ref<Nat>, blocking: Bool, +sent: W.CacheWarmRequest) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    R.modify(List<&2, W.CacheWarmRequest>, Unit, calls, list => (List.append(&2, W.CacheWarmRequest, list, [sent]), Unit{}))
    settle(blocking, aborts, sent)

def fakeStream(fake: Fake, sent: W.CacheWarmRequest) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match fake:
    case Fake{calls, _, _, aborts, blocking}: recordedCall(calls, aborts, blocking, sent)

def usageEntry(record: W.UsageRecord) -> Entry():
  match record:
    case W.UsageRecord{kind, provider, model, usage, note}: S.UsageEntry{S.SessionEntryBase{"u", None{}, "1970-01-01T00:00:00.000Z"}, kind, provider, model, usage, note}

def storedRecord(records: R.Ref<List<&2, W.UsageRecord>>, +record: W.UsageRecord) -> IO(Maybe<&2, Entry()>):
  do IO<Maybe<&2, Entry()>>:
    R.modify(List<&2, W.UsageRecord>, Unit, records, list => (List.append(&2, W.UsageRecord, list, [record]), Unit{}))
    return Some{usageEntry(record)}

def fakeAppend(fake: Fake, record: W.UsageRecord) -> IO(Maybe<&2, Entry()>):
  match fake:
    case Fake{_, records, _, _, _}: storedRecord(records, record)

def fakeBranch(fake: Fake, unit: Unit) -> IO(List<&2, Entry()>): IO.pure(List<&2, Entry()>, branchWithPrompt(100000))
def fakeMode(fake: Fake, unit: Unit) -> IO(Settings.CacheWarmingMode): IO.pure(Settings.CacheWarmingMode, Settings.CacheWarmingIdle{})
def fakeContext(fake: Fake, unit: Unit) -> IO(W.CacheContext): IO.pure(W.CacheContext, conversation())
def fakeWarmed(fake: Fake, entry: Entry()) -> IO(Unit):
  match fake:
    case Fake{_, _, warmed, _, _}: R.modify(List<&2, Entry()>, Unit, warmed, list => (List.append(&2, Entry(), list, [entry]), Unit{}))

def fake(blocking: Bool) -> IO(Fake):
  do IO<Fake>:
    calls : R.Ref<List<&2, W.CacheWarmRequest>> <- R.new(List<&2, W.CacheWarmRequest>, Nil{})
    records : R.Ref<List<&2, W.UsageRecord>> <- R.new(List<&2, W.UsageRecord>, Nil{})
    warmed : R.Ref<List<&2, Entry()>> <- R.new(List<&2, Entry()>, Nil{})
    aborts : R.Ref<Nat> <- R.new(Nat, 0n)
    return Fake{calls, records, warmed, aborts, blocking}

def warmerFor(+fake: Fake) -> IO(W.CacheWarmer):
  do IO<W.CacheWarmer>:
    streamSimple : C.Callback<W.CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>> <- C.create(~Fake, ~W.CacheWarmRequest, ~Ai.AssistantMessage<V.Value, Unit>, ~fakeStream, fake)
    append : C.Callback<W.UsageRecord, Maybe<&2, Entry()>> <- C.create(~Fake, ~W.UsageRecord, ~Maybe<&2, Entry()>, ~fakeAppend, fake)
    branch : C.Callback<Unit, List<&2, Entry()>> <- C.create(~Fake, ~Unit, ~List<&2, Entry()>, ~fakeBranch, fake)
    mode : C.Callback<Unit, Settings.CacheWarmingMode> <- C.create(~Fake, ~Unit, ~Settings.CacheWarmingMode, ~fakeMode, fake)
    context : C.Callback<Unit, W.CacheContext> <- C.create(~Fake, ~Unit, ~W.CacheContext, ~fakeContext, fake)
    decide : C.Callback<W.CacheWarmingDecisionEvent, W.CacheWarmingAction> <- C.create(~Unit, ~W.CacheWarmingDecisionEvent, ~W.CacheWarmingAction, ~W.piDecision, Unit{})
    warmed : C.Callback<Entry(), Unit> <- C.create(~Fake, ~Entry(), ~Unit, ~fakeWarmed, fake)
    W.create(streamSimple, W.CacheWarmerSession{append, branch}, mode, context, decide, warmed)

def pause(milliseconds: U32) -> IO(Unit):
  do IO<Unit>:
    +never : A.AbortController<Unit> <- A.new(Unit)
    slept : Result<&2, &2, A.AbortReason<Unit>, Unit> <- Sleep.sleep(Unit, milliseconds, A.signal(Unit, never))
    A.dispose(Unit, never)

type Counts is Data: Counts{sent: Nat, stored: Nat, announced: Nat}

def counts(fake: Fake) -> IO(Counts):
  match fake:
    case Fake{calls, records, warmed, _, _}:
      do IO<Counts>:
        sent : List<&2, W.CacheWarmRequest> <- R.read(List<&2, W.CacheWarmRequest>, calls)
        stored : List<&2, W.UsageRecord> <- R.read(List<&2, W.UsageRecord>, records)
        announced : List<&2, Entry()> <- R.read(List<&2, Entry()>, warmed)
        return Counts{List.length(&2, W.CacheWarmRequest, sent), List.length(&2, W.UsageRecord, stored), List.length(&2, Entry(), announced)}

def consistent(value: Counts) -> Bool:
  match value:
    case Counts{+sent, +stored, announced}: Nat.is_gt(sent, 1n) && Nat.is_eq(sent, stored) && Nat.is_eq(stored, announced)

def sentOf(value: Counts) -> Nat:
  match value:
    case Counts{sent, _, _}: sent

def isScheduled(status: W.CacheWarmingStatus) -> Bool:
  match status:
    case W.CacheWarmingStatus{W.Inactive{}, _, _, _, _}: False{}
    case _: True{}

def shellWarms(+converter: Runtime.Converter()) -> IO(Unit):
  do IO<Unit>:
    +observed : Fake <- fake(False{})
    +warmer : W.CacheWarmer <- warmerFor(observed)
    W.start(warmer, request(converter, shortModel(), plain()), conversation())
    pause(400)
    status : W.CacheWarmingStatus <- W.status(warmer)
    W.dispose(warmer)
    +disposed : Counts <- counts(observed)
    pause(150)
    later : Counts <- counts(observed)
    check(isScheduled(status) && consistent(disposed) && Nat.is_eq(sentOf(disposed), sentOf(later)), "shell refreshes on its timer, records each refresh and stops when disposed")

def recordsEmpty(fake: Fake) -> IO(Bool):
  match fake:
    case Fake{_, records, _, _, _}:
      do IO<Bool>:
        stored : List<&2, W.UsageRecord> <- R.read(List<&2, W.UsageRecord>, records)
        return List.is_empty(&2, W.UsageRecord, stored)

def abortsOf(fake: Fake) -> R.Ref<Nat>:
  match fake:
    case Fake{_, _, _, aborts, _}: aborts

def shellAborts(+converter: Runtime.Converter()) -> IO(Unit):
  do IO<Unit>:
    +observed : Fake <- fake(True{})
    +warmer : W.CacheWarmer <- warmerFor(observed)
    W.start(warmer, request(converter, shortModel(), plain()), conversation())
    pause(200)
    W.start(warmer, request(converter, shortModel(), plain()), conversation())
    pause(100)
    aborted : Nat <- R.read(Nat, abortsOf(observed))
    W.dispose(warmer)
    empty : Bool <- recordsEmpty(observed)
    check(Nat.is_eq(aborted, 1n) && empty, "shell aborts a replaced run's request in flight and records nothing for it")

def unitMessages(value: Unit, messages: Agent.AgentMessageArray(Unit, Runtime.Details(), Runtime.Custom())) -> IO(Result<&2, &2, Runtime.Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Runtime.Details()>>>):
  IO.pure(Result<&2, &2, Runtime.Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Runtime.Details()>>>, Done{Nil{}})

def main() -> IO(Unit):
  do IO<Unit>:
    +converter : Runtime.Converter() <- C.create(~Unit, ~Agent.AgentMessageArray(Unit, Runtime.Details(), Runtime.Custom()), ~Result<&2, &2, Runtime.Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Runtime.Details()>>>, ~unitMessages, Unit{})
    +controller : A.AbortController<Unit> <- A.new(Unit)
    eligibility()
    replays(converter, controller)
    deadlines(converter, controller)
    economics(converter, controller)
    stops(converter, controller)
    replaced(converter, controller)
    formats()
    shellWarms(converter)
    shellAborts(converter)
