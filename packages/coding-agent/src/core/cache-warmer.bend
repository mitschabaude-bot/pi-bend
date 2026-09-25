import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/provider-env.bend as Env
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deferred.bend as D
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/timer.bend as Sleep
import ./agent-runtime.bend as Runtime
import ./session-json.bend as SessionJson
import ./session-manager.bend as S
import ./settings-manager.bend as Settings
import ./tools/index.bend as Tools

# upstream core/cache-warmer.ts: keeps one prompt cache entry alive by
# re-sending its request with a one-token output cap before the entry expires.
#
# The warmer is an immutable state machine (`Warmer`) with explicit
# transitions; each takes the observations it depends on (clock, mode,
# current conversation, prompt size) as values. The I/O shell below runs one
# worker per run that sleeps, asks for the decision, replays the request and
# records its usage, applying each transition atomically. Upstream's
# `this.run === run` identity becomes a run generation number.

def n(value: U32) -> F64: F.fromU32(value)
def zero() -> F64: n(0)
def ratio(top: U32, bottom: U32) -> F64: F.divide(n(top), n(bottom))

# Streaming warming never continues past this long after the real request
# that started it.
def MAX_WARMING_AGE_MS() -> F64: n(3600000)
# Idle warming uses a shorter horizon because continuation estimates become
# less reliable with age.
def MAX_IDLE_WARMING_AGE_MS() -> F64: n(1800000)
# A refresh is sent only when it is expected to save at least this many dollars.
def CACHE_WARMING_MINIMUM_EXPECTED_SAVINGS() -> F64: ratio(5, 100)
# Chance that a real request arrives before the cache entry expires while the
# agent sits idle (measured by upstream; per-session estimates were not better).
def IDLE_CONTINUATION_PROBABILITY() -> F64: ratio(15, 100)

# Refresh at 90% of the TTL while preserving at least ten seconds of margin.
def getCacheWarmingDelayMs(+ttlMs: F64) -> Maybe<&2, F64>:
  Bool.pick(Unit -> Maybe<&2, F64>, F64.is_le(ttlMs, n(10000)),
    _ => None{},
    _ => Some{F.maximum(n(1), F64.floor(F.minimum(F.multiply(ttlMs, ratio(9, 10)), F.subtract(ttlMs, n(10000)))))})(Unit{})

# Request options as the agent sends them.
def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, A.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error()>

def promptCacheOf(model: Ai.Model<Ai.JsonValue>) -> Maybe<&2, Ai.ModelPromptCache>:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, cache, _, _, _, _, _}: cache

def tierSeconds(cache: Maybe<&2, Ai.ModelPromptCache>, retention: Ai.CacheRetention) -> Maybe<&2, F64>:
  match cache retention:
    case _ Ai.CacheNone{}: None{}
    case None{} _: None{}
    case Some{Ai.ModelPromptCache{short, _}} Ai.CacheShort{}: short
    case Some{Ai.ModelPromptCache{_, long}} Ai.CacheLong{}: long

# Lifetime of the prompt cache entry a request writes under `retention`:
# the model's `promptCache` tier, none when the tier is unknown or caching off.
def promptCacheTtlMs(model: Ai.Model<Ai.JsonValue>, retention: Ai.CacheRetention) -> Maybe<&2, F64>:
  Maybe.map(&2, F64, F64, seconds => F.multiply(seconds, n(1000)), tierSeconds(promptCacheOf(model), retention))

def retentionOption(options: Maybe<&2, Options()>) -> Maybe<&2, Ai.CacheRetention>:
  match options:
    case Some{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, retention, _, _, _, _, _, _, _}}: retention
    case None{}: None{}

def envOption(options: Maybe<&2, Options()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match options:
    case Some{Ai.SimpleStreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: env
    case None{}: None{}

def reasoningOf(options: Maybe<&2, Options()>) -> Maybe<&2, Ai.ThinkingLevel>:
  match options:
    case Some{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reasoning, _, _}}: reasoning
    case None{}: None{}

def isLong(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{text}: String.eq(text, "long")
    case None{}: False{}

# The request's retention, else PI_CACHE_RETENTION=long, else short.
def resolvedRetention(explicit: Maybe<&2, Ai.CacheRetention>, env: Maybe<&2, String>) -> Ai.CacheRetention:
  match explicit:
    case Some{retention}: retention
    case None{}: Bool.pick(Ai.CacheRetention, isLong(env), Ai.CacheLong{}, Ai.CacheShort{})

# Lifetime of the prompt cache entry a request writes, from the model's
# `promptCache` tier for the retention the request used.
def getPromptCacheTtlMs(model: Ai.Model<Ai.JsonValue>, +options: Maybe<&2, Options()>) -> IO(Maybe<&2, F64>):
  do IO<Maybe<&2, F64>>:
    env : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", envOption(options))
    return promptCacheTtlMs(model, resolvedRetention(retentionOption(options), env))

def anthropicMessages(model: Ai.Model<Ai.JsonValue>) -> Bool:
  match model:
    case Ai.Model{_, _, Ai.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def forcesAdaptiveThinking(model: Ai.Model<Ai.JsonValue>) -> Bool:
  match model:
    case Ai.Model{_, _, Ai.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{Ai.AnthropicMessagesCompat{_, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _}}}: True{}
    case _: False{}

# Whether replaying the request with a one-token output cap leaves its cache
# entry untouched. Anthropic's budget-based thinking derives `budget_tokens`
# from `max_tokens`; the replay would get a different budget, which Anthropic
# keys the message cache on, and could still think for thousands of tokens.
def replayableWith(+model: Ai.Model<Ai.JsonValue>, reasoning: Maybe<&2, Ai.ThinkingLevel>) -> Bool:
  match reasoning:
    case None{}: True{}
    case Some{_}: Bool.not(anthropicMessages(model)) || forcesAdaptiveThinking(model)

def isReplayable(model: Ai.Model<Ai.JsonValue>, options: Maybe<&2, Options()>) -> Bool:
  replayableWith(model, reasoningOf(options))

def promptTokensOf(usage: Ai.Usage) -> F64:
  match usage:
    case Ai.Usage{input, _, cacheRead, cacheWrite, _, _, _, _}: F.add(F.add(input, cacheRead), cacheWrite)

def latestPrompt(-D: Data, -T: Data, -C: Data, entries: List<&2, S.SessionEntry<D, T, C>>, found: F64) -> F64:
  match entries:
    case Nil{}: found
    case S.SessionMessageEntry{_, Agent.LlmMessage{Ai.Assistant{message}}} <> rest: latestPrompt(D, T, C, rest, promptTokensOf(Ai.assistantUsage(V.Value, D, message)))
    case _ <> rest: latestPrompt(D, T, C, rest, found)

# Prompt size of the most recent real request on the branch, as reported by the provider.
def lastPromptTokens(-D: Data, -T: Data, -C: Data, entries: List<&2, S.SessionEntry<D, T, C>>) -> F64:
  latestPrompt(D, T, C, entries, zero())

def totalOf(cost: Ai.UsageCost) -> F64:
  match cost:
    case Ai.UsageCost{_, _, _, _, total}: total

def price(model: Ai.Model<Ai.JsonValue>, input: F64, output: F64, cacheRead: F64, cacheWrite: F64) -> F64:
  totalOf(AiModels.calculateCost(Ai.JsonValue, model, Ai.Usage{input, output, cacheRead, cacheWrite, None{}, None{}, zero(), Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}))

def cacheWriteRate(model: Ai.Model<Ai.JsonValue>) -> F64:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, Ai.ModelCost{_, _, _, cacheWrite, _}, _, _, _, _, _, _}: cacheWrite

# Decisions
# ---------

type CacheWarmingPhase is Data:
  Streaming{}
  Idle{}

type CacheWarmingAction is Data:
  Warm{}
  Stop{}

# Inputs and outcome of one warm-or-stop decision, as shown by `/session`.
# `phase` is streaming while the agent run that sent the request is active;
# `warmCost` is a cache read of the prompt plus one output token; `missCost`
# is the extra price of the next real request if the entry is lost;
# `expectedSavings` is `continuationProbability * missCost - warmCost`;
# `economicsAvailable` is false when the prompt size or prices are unknown.
type CacheWarmingDecision is Data:
  CacheWarmingDecision{phase: CacheWarmingPhase, warmCost: F64, missCost: F64, continuationProbability: F64, expectedSavings: F64, economicsAvailable: Bool, action: CacheWarmingAction}

# Fired before each refresh with pi's decision filled in. Upstream lets
# extensions override `action` ("stop" ends warming until the next real request).
type CacheWarmingDecisionEvent is Data:
  CacheWarmingDecisionEvent{warmCost: F64, missCost: F64, continuationProbability: F64, action: CacheWarmingAction}

type CacheWarmingState is Data:
  Inactive{}
  Scheduled{}
  Refreshing{}

# "scheduled": a refresh timer is armed; "refreshing": a warm request is in
# flight. `decision` is the pending decision, or the decision that stopped
# warming; `extensionOverride` is true when the decide hook changed its action
# (upstream's optional flag; absent reads as false).
type CacheWarmingStatus is Data:
  CacheWarmingStatus{state: CacheWarmingState, reason: Maybe<&2, String>, nextWarmAt: Maybe<&2, F64>, decision: Maybe<&2, CacheWarmingDecision>, extensionOverride: Bool}

def isIdle(phase: CacheWarmingPhase) -> Bool:
  match phase:
    case Idle{}: True{}
    case Streaming{}: False{}

def evaluate(+model: Ai.Model<Ai.JsonValue>, +phase: CacheWarmingPhase, +promptTokens: F64) -> CacheWarmingDecision:
  +cacheHitCost = price(model, zero(), zero(), promptTokens, zero())
  +cacheMissCost = Bool.pick(F64, F64.is_gt(cacheWriteRate(model), zero()), price(model, zero(), zero(), zero(), promptTokens), price(model, promptTokens, zero(), zero(), zero()))
  +warmCost = price(model, zero(), n(1), promptTokens, zero())
  +missCost = F.maximum(zero(), F.subtract(cacheMissCost, cacheHitCost))
  +continuationProbability = Bool.pick(F64, isIdle(phase), IDLE_CONTINUATION_PROBABILITY(), n(1))
  +expectedSavings = F.subtract(F.multiply(continuationProbability, missCost), warmCost)
  CacheWarmingDecision{phase, warmCost, missCost, continuationProbability, expectedSavings, F64.is_gt(promptTokens, zero()) && (F64.is_gt(cacheHitCost, zero()) || F64.is_gt(cacheMissCost, zero())), Bool.pick(CacheWarmingAction, F64.is_ge(expectedSavings, CACHE_WARMING_MINIMUM_EXPECTED_SAVINGS()), Warm{}, Stop{})}

def decisionEvent(decision: CacheWarmingDecision) -> CacheWarmingDecisionEvent:
  match decision:
    case CacheWarmingDecision{_, warmCost, missCost, continuationProbability, _, _, action}: CacheWarmingDecisionEvent{warmCost, missCost, continuationProbability, action}

def eventAction(event: CacheWarmingDecisionEvent) -> CacheWarmingAction:
  match event:
    case CacheWarmingDecisionEvent{_, _, _, action}: action

def economics(decision: CacheWarmingDecision) -> Bool:
  match decision:
    case CacheWarmingDecision{_, _, _, _, _, economicsAvailable, _}: economicsAvailable

def sameAction(left: CacheWarmingAction, right: CacheWarmingAction) -> Bool:
  match left right:
    case Warm{} Warm{}: True{}
    case Stop{} Stop{}: True{}
    case _ _: False{}

# Requests
# --------

# The request whose prompt cache entry should be kept warm, exactly as the
# agent sent it: the model, the provider context and the request's loop
# configuration (its stream options and hooks).
type CacheWarmRequest is Data:
  CacheWarmRequest{model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<V.Value, V.Value, Unit, Runtime.Details()>, options: Runtime.LoopConfig()}

def Message() -> Data: Agent.AgentMessage<Unit, Runtime.Details(), Runtime.Custom()>

# The conversation a request was sent from: its model and the agent's
# transcript. Upstream's closure compares message identity; values have none,
# so equal transcripts compare equal.
type CacheContext is Data:
  CacheContext{provider: String, modelId: String, messages: List<&2, Message()>}

def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def encoded(+message: Message()) -> V.Value:
  SessionJson.agentMessage(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, message)

def extendsPrefix(prefix: List<&2, Message()>, messages: List<&2, Message()>) -> Bool:
  match prefix messages:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case first <> rest current <> later: V.equal(encoded(first), encoded(current)) && extendsPrefix(rest, later)

# Warming continues while the session's model is the request's and the
# current transcript still extends the request's prefix.
def cacheContextIsCurrent(request: CacheContext, current: CacheContext) -> Bool:
  match request current:
    case CacheContext{provider, modelId, messages} CacheContext{currentProvider, currentModel, currentMessages}:
      String.eq(provider, currentProvider) && String.eq(modelId, currentModel) && extendsPrefix(messages, currentMessages)

def withReplayOptions(options: Options(), signal: A.AbortSignal<Unit>) -> Options():
  match options:
    case Ai.SimpleStreamOptions{_, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, _, maxRetryDelayMs, temperature, samplingParams, _, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}:
      Ai.SimpleStreamOptions{Some{signal}, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, Some{zero()}, maxRetryDelayMs, temperature, samplingParams, Some{n(1)}, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

# The refresh: the request with a one-token output cap, no retries and the
# run's own abort signal.
def replayRequest(request: CacheWarmRequest, signal: A.AbortSignal<Unit>) -> CacheWarmRequest:
  match request:
    case CacheWarmRequest{model, context, Agent.AgentLoopConfig{options, loopModel, convert, transform, key, finish, prepare, next, steering, followUp, execution, before, after}}:
      CacheWarmRequest{model, context, Agent.AgentLoopConfig{withReplayOptions(options, signal), loopModel, convert, transform, key, finish, prepare, next, steering, followUp, execution, before, after}}

def requestModel(request: CacheWarmRequest) -> Ai.Model<Ai.JsonValue>:
  match request:
    case CacheWarmRequest{model, _, _}: model

def requestOptions(request: CacheWarmRequest) -> Options():
  match request:
    case CacheWarmRequest{_, _, Agent.AgentLoopConfig{options, _, _, _, _, _, _, _, _, _, _, _, _}}: options

def noRetention(retention: Maybe<&2, Ai.CacheRetention>) -> Bool:
  match retention:
    case Some{Ai.CacheNone{}}: True{}
    case _: False{}

def disabledCaching(options: Maybe<&2, Options()>) -> Bool: noRetention(retentionOption(options))

# State machine
# -------------

# What the worker of the current run waits for: its timer, the decision, or
# the replayed request (upstream's `timer === undefined` is "refreshing").
type Pending is Data:
  Armed{}
  Deciding{decision: CacheWarmingDecision}
  Replaying{}

type ActiveRun is Data:
  ActiveRun{generation: Nat, request: CacheWarmRequest, context: CacheContext, ttlMs: F64, delayMs: F64, refreshDeadlineAt: F64, startedAt: F64, controller: A.AbortController<Unit>, phase: CacheWarmingPhase, nextWarmAt: F64, extensionOverride: Bool, pending: Pending}

def generationOf(run: ActiveRun) -> Nat:
  match run:
    case ActiveRun{generation, _, _, _, _, _, _, _, _, _, _, _}: generation

def requestOf(run: ActiveRun) -> CacheWarmRequest:
  match run:
    case ActiveRun{_, request, _, _, _, _, _, _, _, _, _, _}: request

def signalOf(run: ActiveRun) -> A.AbortSignal<Unit>:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, controller, _, _, _, _}: A.signal(Unit, controller)

def phaseOf(run: ActiveRun) -> CacheWarmingPhase:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, _, phase, _, _, _}: phase

def overrideOf(run: ActiveRun) -> Bool:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, _, _, _, extensionOverride, _}: extensionOverride

def contextOf(run: ActiveRun) -> CacheContext:
  match run:
    case ActiveRun{_, _, context, _, _, _, _, _, _, _, _, _}: context

def controllerOf(run: Maybe<&2, ActiveRun>) -> Maybe<&2, A.AbortController<Unit>>:
  match run:
    case Some{ActiveRun{_, _, _, _, _, _, _, controller, _, _, _, _}}: Some{controller}
    case None{}: None{}

# `live` counts running workers; `closing` is resolved when the last one
# exits after disposal began.
type Warmer is Data:
  Warmer{run: Maybe<&2, ActiveRun>, inactive: CacheWarmingStatus, generation: Nat, live: Nat, closing: Maybe<&2, D.Deferred<Unit>>}

def initial() -> Warmer:
  Warmer{None{}, CacheWarmingStatus{Inactive{}, Some{"waiting for first request"}, None{}, None{}, False{}}, 0n, 0n, None{}}

# The observations a transition depends on.
type Observation is Data:
  Observation{mode: Settings.CacheWarmingMode, now: F64, context: CacheContext, promptTokens: F64}

# A usage entry to persist for a successful refresh.
type UsageRecord is Data:
  UsageRecord{kind: String, provider: String, model: String, usage: Ai.Usage, note: Maybe<&2, String>}

# What a run's worker does next.
type Next is Data:
  Exit{}
  Wait{delayMs: F64}
  Decide{event: CacheWarmingDecisionEvent}
  Replay{request: CacheWarmRequest}

# A transition's effects: the controller of a run it removed (abort it), a
# usage entry to persist, and the worker's next action.
type Step is Data:
  Step{released: Maybe<&2, A.AbortController<Unit>>, record: Maybe<&2, UsageRecord>, next: Next}

type RunOutcome is Data:
  Kept{run: ActiveRun, next: Next, record: Maybe<&2, UsageRecord>}
  Ended{status: CacheWarmingStatus, controller: A.AbortController<Unit>, record: Maybe<&2, UsageRecord>}

def inactiveStatus(reason: String, decision: Maybe<&2, CacheWarmingDecision>, extensionOverride: Bool) -> CacheWarmingStatus:
  CacheWarmingStatus{Inactive{}, Some{reason}, None{}, decision, extensionOverride}

def ended(run: ActiveRun, reason: String, decision: Maybe<&2, CacheWarmingDecision>, extensionOverride: Bool, record: Maybe<&2, UsageRecord>) -> RunOutcome:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, controller, _, _, _, _}: Ended{inactiveStatus(reason, decision, extensionOverride), controller, record}

def modeStopReason(mode: Settings.CacheWarmingMode, phase: CacheWarmingPhase) -> Maybe<&2, String>:
  match mode phase:
    case Settings.CacheWarmingOff{} _: Some{"cache warming disabled"}
    case Settings.CacheWarmingStreaming{} Idle{}: Some{"agent run settled"}
    case _ _: None{}

def contextStopReason(current: Bool) -> Maybe<&2, String>:
  match current:
    case True{}: None{}
    case False{}: Some{"conversation context changed"}

def invalidity(run: ActiveRun, observation: Observation) -> Maybe<&2, String>:
  match run observation:
    case ActiveRun{_, _, context, _, _, _, _, _, phase, _, _, _} Observation{mode, _, current, _}:
      Maybe.or(&2, String, modeStopReason(mode, phase), contextStopReason(cacheContextIsCurrent(context, current)))

def rearmed(run: ActiveRun, +nextWarmAt: F64) -> ActiveRun:
  match run:
    case ActiveRun{generation, request, context, +ttlMs, +delayMs, _, startedAt, controller, phase, _, _, _}:
      ActiveRun{generation, request, context, ttlMs, delayMs, F.add(nextWarmAt, F64.floor(F.divide(F.subtract(ttlMs, delayMs), n(2)))), startedAt, controller, phase, nextWarmAt, False{}, Armed{}}

def delayMsOf(run: ActiveRun) -> F64:
  match run:
    case ActiveRun{_, _, _, _, delayMs, _, _, _, _, _, _, _}: delayMs

def startedAtOf(run: ActiveRun) -> F64:
  match run:
    case ActiveRun{_, _, _, _, _, _, startedAt, _, _, _, _, _}: startedAt

def safetyLimit(phase: CacheWarmingPhase) -> F64:
  match phase:
    case Idle{}: MAX_IDLE_WARMING_AGE_MS()
    case Streaming{}: MAX_WARMING_AGE_MS()

def limitReason(phase: CacheWarmingPhase) -> String:
  match phase:
    case Idle{}: "30-minute idle safety limit reached"
    case Streaming{}: "one-hour safety limit reached"

# Arm the next refresh. A timer can run late after sleep or event-loop
# blockage: half of the planned pre-expiry margin is kept for that delay and
# request dispatch; a later refresh is likely a full-price cache write.
def schedule(+run: ActiveRun, +now: F64, +record: Maybe<&2, UsageRecord>) -> RunOutcome:
  +nextWarmAt = F.add(now, delayMsOf(run))
  +deadline = F.add(startedAtOf(run), safetyLimit(phaseOf(run)))
  +next = rearmed(run, nextWarmAt)
  Bool.pick(Unit -> RunOutcome, F64.is_gt(nextWarmAt, deadline) || F64.is_ge(now, deadline),
    _ => ended(next, limitReason(phaseOf(run)), None{}, False{}, record),
    _ => Kept{next, Wait{F.maximum(zero(), F.subtract(nextWarmAt, now))}, record})(Unit{})

def deadlineMissed(run: ActiveRun, now: F64) -> Bool:
  match run:
    case ActiveRun{_, _, _, _, _, refreshDeadlineAt, _, _, _, _, _, _}: F64.is_gt(now, refreshDeadlineAt)

def withPending(run: ActiveRun, pending: Pending) -> ActiveRun:
  match run:
    case ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, startedAt, controller, phase, nextWarmAt, extensionOverride, _}:
      ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, startedAt, controller, phase, nextWarmAt, extensionOverride, pending}

def deciding(+run: ActiveRun, promptTokens: F64) -> RunOutcome:
  +decision = evaluate(requestModel(requestOf(run)), phaseOf(run), promptTokens)
  Kept{withPending(run, Deciding{decision}), Decide{decisionEvent(decision)}, None{}}

def checkedDeadline(+run: ActiveRun, +now: F64, continued: ActiveRun -> RunOutcome) -> RunOutcome:
  Bool.pick(Unit -> RunOutcome, deadlineMissed(run, now), _ => ended(run, "cache refresh deadline missed", None{}, False{}, None{}), _ => continued(run))(Unit{})

def checkedWith(+run: ActiveRun, reason: Maybe<&2, String>, continued: ActiveRun -> RunOutcome) -> RunOutcome:
  match reason:
    case Some{text}: ended(run, text, None{}, False{}, None{})
    case None{}: continued(run)

def checkedRun(+run: ActiveRun, observation: Observation, continued: ActiveRun -> RunOutcome) -> RunOutcome:
  checkedWith(run, invalidity(run, observation), continued)

def nowOf(observation: Observation) -> F64:
  match observation:
    case Observation{_, now, _, _}: now

def promptOf(observation: Observation) -> F64:
  match observation:
    case Observation{_, _, _, promptTokens}: promptTokens

# The run's timer fired: validate, check the deadline, then evaluate.
def firedRun(run: ActiveRun, +observation: Observation) -> RunOutcome:
  checkedRun(withPending(run, Replaying{}), observation, valid => checkedDeadline(valid, nowOf(observation), fresh => deciding(fresh, promptOf(observation))))

def decisionOf(run: ActiveRun) -> Maybe<&2, CacheWarmingDecision>:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, _, _, _, _, Deciding{decision}}: Some{decision}
    case _: None{}

def withOverride(run: ActiveRun, extensionOverride: Bool) -> ActiveRun:
  match run:
    case ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, startedAt, controller, phase, nextWarmAt, _, _}:
      ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, startedAt, controller, phase, nextWarmAt, extensionOverride, Replaying{}}

def stopReason(extensionOverride: Bool, economicsAvailable: Bool) -> String:
  match extensionOverride economicsAvailable:
    case True{} _: "stopped by extension"
    case False{} True{}: "expected savings below threshold"
    case False{} False{}: "cache economics unavailable"

def actWith(+run: ActiveRun, action: CacheWarmingAction, +decision: CacheWarmingDecision, +extensionOverride: Bool) -> RunOutcome:
  match action:
    case Stop{}: ended(run, stopReason(extensionOverride, economics(decision)), Some{decision}, extensionOverride, None{})
    case Warm{}:
      +armed = withOverride(run, extensionOverride)
      Kept{armed, Replay{replayRequest(requestOf(armed), signalOf(armed))}, None{}}

def chosenAction(decision: CacheWarmingDecision) -> CacheWarmingAction:
  match decision:
    case CacheWarmingDecision{_, _, _, _, _, _, action}: action

def actOn(+run: ActiveRun, +action: CacheWarmingAction, +decision: CacheWarmingDecision) -> RunOutcome:
  actWith(run, action, decision, Bool.not(sameAction(action, chosenAction(decision))))

# Only a run whose timer fired awaits a decision; any other run is ended so
# that no run is left without a worker.
def decidedWith(+run: ActiveRun, action: CacheWarmingAction, decision: Maybe<&2, CacheWarmingDecision>) -> RunOutcome:
  match decision:
    case Some{value}: actOn(run, action, value)
    case None{}: ended(run, "inactive", None{}, False{}, None{})

# The decision arrived: validate and check the deadline again, then stop or
# replay. An action different from pi's is an extension override.
def decidedFor(+run: ActiveRun, action: CacheWarmingAction) -> RunOutcome: decidedWith(run, action, decisionOf(run))

def decidedRun(run: ActiveRun, action: CacheWarmingAction, +observation: Observation) -> RunOutcome:
  checkedRun(run, observation, valid => checkedDeadline(valid, nowOf(observation), fresh => decidedFor(fresh, action)))

def succeeded(stopReason: Ai.StopReason) -> Bool:
  match stopReason:
    case Ai.Error{}: False{}
    case Ai.Aborted{}: False{}
    case _: True{}

def overrideNote(extensionOverride: Bool) -> Maybe<&2, String>:
  match extensionOverride:
    case True{}: Some{"extension override"}
    case False{}: None{}

def warmRecord(message: Ai.AssistantMessage<V.Value, Unit>, extensionOverride: Bool) -> Maybe<&2, UsageRecord>:
  match message:
    case Ai.AssistantMessage{_, _, provider, model, responseModel, _, _, _, usage, outcome, _, _, _, _, _}:
      Bool.pick(Maybe<&2, UsageRecord>, succeeded(outcome), Some{UsageRecord{"cache_warm", provider, Maybe.default(&2, String, responseModel, model), usage, overrideNote(extensionOverride)}}, None{})

# The replay finished: a successful refresh is recorded (failures are not)
# and the next refresh is armed while the run is still valid.
def rescheduled(+run: ActiveRun, now: F64, message: Ai.AssistantMessage<V.Value, Unit>) -> RunOutcome:
  schedule(run, now, warmRecord(message, overrideOf(run)))

def replayedRun(run: ActiveRun, message: Ai.AssistantMessage<V.Value, Unit>, +observation: Observation) -> RunOutcome:
  checkedRun(run, observation, valid => rescheduled(valid, nowOf(observation), message))

def exitStep() -> Step: Step{None{}, None{}, Exit{}}

def applied(inactive: CacheWarmingStatus, generation: Nat, live: Nat, closing: Maybe<&2, D.Deferred<Unit>>, outcome: RunOutcome) -> Warmer & Step:
  match outcome:
    case Kept{run, next, record}: (Warmer{Some{run}, inactive, generation, live, closing}, Step{None{}, record, next})
    case Ended{final, controller, record}: (Warmer{None{}, final, generation, live, closing}, Step{Some{controller}, record, Exit{}})

# Apply a transition to the run of `generation`; a replaced or stopped run's
# worker exits.
def onRun(state: Warmer, +generation: Nat, transition: ActiveRun -> RunOutcome) -> Warmer & Step:
  match state:
    case Warmer{None{}, inactive, current, live, closing}: (Warmer{None{}, inactive, current, live, closing}, exitStep())
    case Warmer{Some{+run}, +inactive, +current, +live, +closing}:
      Bool.pick(Unit -> Warmer & Step, Nat.is_eq(generationOf(run), generation),
        _ => applied(inactive, current, live, closing, transition(run)),
        _ => (Warmer{Some{run}, inactive, current, live, closing}, exitStep()))(Unit{})

def fired(state: Warmer, generation: Nat, observation: Observation) -> Warmer & Step:
  onRun(state, generation, run => firedRun(run, observation))

def decided(state: Warmer, generation: Nat, action: CacheWarmingAction, observation: Observation) -> Warmer & Step:
  onRun(state, generation, run => decidedRun(run, action, observation))

def replayed(state: Warmer, generation: Nat, message: Ai.AssistantMessage<V.Value, Unit>, observation: Observation) -> Warmer & Step:
  onRun(state, generation, run => replayedRun(run, message, observation))

# The outcome of `start`: the replaced run's controller (abort it) and the
# new run's worker, if one was armed.
type Launch is Data:
  Launch{generation: Nat, delayMs: F64}
type Started is Data:
  Started{previous: Maybe<&2, A.AbortController<Unit>>, launch: Maybe<&2, Launch>}

# What decides a start before any run exists.
type StartFacts is Data:
  StartFacts{mode: Settings.CacheWarmingMode, now: F64, replayable: Bool, ttlMs: Maybe<&2, F64>, cachingDisabled: Bool}

def startStopReason(mode: Settings.CacheWarmingMode, replayable: Bool, ttlMs: Maybe<&2, F64>, cachingDisabled: Bool) -> Maybe<&2, String>:
  match mode replayable ttlMs:
    case Settings.CacheWarmingOff{} _ _: Some{"cache warming disabled"}
    case _ False{} _: Some{"request cannot be replayed safely"}
    case _ _ None{}: Some{Bool.pick(String, cachingDisabled, "request disabled prompt caching", "cache lifetime unavailable")}
    case _ _ Some{_}: None{}

def launched(previous: Maybe<&2, A.AbortController<Unit>>, +generation: Nat, live: Nat, closing: Maybe<&2, D.Deferred<Unit>>, inactive: CacheWarmingStatus, outcome: RunOutcome) -> Warmer & Started:
  match outcome:
    case Kept{run, Wait{delayMs}, _}: (Warmer{Some{run}, inactive, generation, live + 1n, closing}, Started{previous, Some{Launch{generation, delayMs}}})
    case Kept{_, _, _}: (Warmer{None{}, inactive, generation, live, closing}, Started{previous, None{}})
    case Ended{final, _, _}: (Warmer{None{}, final, generation, live, closing}, Started{previous, None{}})

def startWithDelay(previous: Maybe<&2, A.AbortController<Unit>>, +generation: Nat, live: Nat, closing: Maybe<&2, D.Deferred<Unit>>, inactive: CacheWarmingStatus, request: CacheWarmRequest, context: CacheContext, controller: A.AbortController<Unit>, +now: F64, ttlMs: F64, delay: Maybe<&2, F64>) -> Warmer & Started:
  match delay:
    case None{}: (Warmer{None{}, inactiveStatus("cache lifetime unavailable", None{}, False{}), generation, live, closing}, Started{previous, None{}})
    case Some{delayMs}: launched(previous, generation, live, closing, inactive, schedule(ActiveRun{generation, request, context, ttlMs, delayMs, zero(), now, controller, Streaming{}, zero(), False{}, Armed{}}, now, None{}))

def startChecked(previous: Maybe<&2, A.AbortController<Unit>>, generation: Nat, live: Nat, closing: Maybe<&2, D.Deferred<Unit>>, inactive: CacheWarmingStatus, request: CacheWarmRequest, context: CacheContext, controller: A.AbortController<Unit>, now: F64, ttlMs: Maybe<&2, F64>, refusal: Maybe<&2, String>) -> Warmer & Started:
  match ttlMs refusal:
    case _ Some{reason}: (Warmer{None{}, inactiveStatus(reason, None{}, False{}), generation, live, closing}, Started{previous, None{}})
    case Some{+ttl} None{}: startWithDelay(previous, generation, live, closing, inactive, request, context, controller, now, ttl, getCacheWarmingDelayMs(ttl))
    case None{} None{}: (Warmer{None{}, inactiveStatus("cache lifetime unavailable", None{}, False{}), generation, live, closing}, Started{previous, None{}})

# Keep the prompt cache entry written by `request` warm while the session's
# conversation extends `context`. Replaces any previous run; when nothing is
# armed the caller keeps (and retires) the new controller.
def started(state: Warmer, request: CacheWarmRequest, context: CacheContext, controller: A.AbortController<Unit>, facts: StartFacts) -> Warmer & Started:
  match state facts:
    case Warmer{run, inactive, generation, live, closing} StartFacts{mode, now, replayable, +ttlMs, cachingDisabled}:
      startChecked(controllerOf(run), generation + 1n, live, closing, inactive, request, context, controller, now, ttlMs, startStopReason(mode, replayable, ttlMs, cachingDisabled))

def stoppedState(state: Warmer, status: CacheWarmingStatus) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  match state:
    case Warmer{run, _, generation, live, closing}: (Warmer{None{}, status, generation, live, closing}, controllerOf(run))

def settledRun(run: ActiveRun, +now: F64) -> Maybe<&2, ActiveRun>:
  match run:
    case ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, +startedAt, controller, _, +nextWarmAt, extensionOverride, pending}:
      +deadline = F.add(startedAt, MAX_IDLE_WARMING_AGE_MS())
      Bool.pick(Unit -> Maybe<&2, ActiveRun>, F64.is_gt(nextWarmAt, deadline) || F64.is_ge(now, deadline),
        _ => None{},
        _ => Some{ActiveRun{generation, request, context, ttlMs, delayMs, refreshDeadlineAt, startedAt, controller, Idle{}, nextWarmAt, extensionOverride, pending}})(Unit{})

def idled(state: Warmer, settled: Maybe<&2, ActiveRun>) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  match state settled:
    case _ None{}: stoppedState(state, inactiveStatus("30-minute idle safety limit reached", None{}, False{}))
    case Warmer{_, inactive, generation, live, closing} Some{run}: (Warmer{Some{run}, inactive, generation, live, closing}, None{})

def settledWith(state: Warmer, mode: Settings.CacheWarmingMode, now: F64, run: Maybe<&2, ActiveRun>) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  match mode run:
    case _ None{}: (state, None{})
    case Settings.CacheWarmingStreaming{} Some{_}: stoppedState(state, inactiveStatus("agent run settled", None{}, False{}))
    case _ Some{value}: idled(state, settledRun(value, now))

def runOf(state: Warmer) -> Maybe<&2, ActiveRun>:
  match state:
    case Warmer{run, _, _, _, _}: run

# The agent run settled: streaming mode stops; idle mode keeps warming with
# the idle continuation probability within the idle safety limit.
def settledState(+state: Warmer, mode: Settings.CacheWarmingMode, now: F64) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  settledWith(state, mode, now, runOf(state))

def modeStop(state: Warmer, reason: Maybe<&2, String>) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  match reason:
    case None{}: (state, None{})
    case Some{text}: stoppedState(state, inactiveStatus(text, None{}, False{}))

def modeChangedWith(state: Warmer, mode: Settings.CacheWarmingMode, run: Maybe<&2, ActiveRun>) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  match run:
    case None{}: (state, None{})
    case Some{value}: modeStop(state, modeStopReason(mode, phaseOf(value)))

# Reconcile an active run after the persisted warming mode changes.
def modeChangedState(+state: Warmer, mode: Settings.CacheWarmingMode) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  modeChangedWith(state, mode, runOf(state))

def cancelled(state: Warmer) -> Warmer & Maybe<&2, A.AbortController<Unit>>:
  stoppedState(state, inactiveStatus("inactive", None{}, False{}))

def isArmed(pending: Pending) -> Bool:
  match pending:
    case Armed{}: True{}
    case _: False{}

def activeStatus(run: ActiveRun, +decision: CacheWarmingDecision) -> CacheWarmingStatus:
  match run:
    case ActiveRun{_, _, _, _, _, _, _, _, _, nextWarmAt, extensionOverride, +pending}:
      Bool.pick(Unit -> CacheWarmingStatus, Bool.not(economics(decision)) && isArmed(pending),
        _ => inactiveStatus("cache economics unavailable", None{}, False{}),
        _ => CacheWarmingStatus{Bool.pick(CacheWarmingState, isArmed(pending), Scheduled{}, Refreshing{}), None{}, Some{nextWarmAt}, Some{decision}, extensionOverride})(Unit{})

def currentStatus(+run: ActiveRun, observation: Observation) -> CacheWarmingStatus:
  match observation:
    case Observation{_, _, current, promptTokens}:
      Bool.pick(Unit -> CacheWarmingStatus, cacheContextIsCurrent(contextOf(run), current),
        _ => activeStatus(run, evaluate(requestModel(requestOf(run)), phaseOf(run), promptTokens)),
        _ => inactiveStatus("conversation context changed", None{}, False{}))(Unit{})

def runStatus(run: Maybe<&2, ActiveRun>, inactive: CacheWarmingStatus, observation: Observation) -> CacheWarmingStatus:
  match run:
    case None{}: inactive
    case Some{value}: currentStatus(value, observation)

def modeOf(observation: Observation) -> Settings.CacheWarmingMode:
  match observation:
    case Observation{mode, _, _, _}: mode

def statusFor(state: Warmer, mode: Settings.CacheWarmingMode, +observation: Observation) -> CacheWarmingStatus:
  match state mode:
    case _ Settings.CacheWarmingOff{}: inactiveStatus("cache warming disabled", None{}, False{})
    case Warmer{run, inactive, _, _, _} _: runStatus(run, inactive, observation)

# upstream `status`: the current warming state and the policy inputs behind it.
def statusOf(state: Warmer, +observation: Observation) -> CacheWarmingStatus:
  statusFor(state, modeOf(observation), observation)

# Formatting
# ----------

def fixed(value: F64, digits: Nat) -> String: Maybe.default(&2, String, NumberString.formatFixed(value, digits), "")

def formatDollars(+value: F64) -> String:
  Bool.pick(String, F64.is_lt(value, zero()), "-$" ++ fixed(F.negate(value), 3n), "$" ++ fixed(value, 3n))

def actionName(action: CacheWarmingAction) -> String:
  match action:
    case Warm{}: "warm"
    case Stop{}: "stop"

def comparison(action: CacheWarmingAction) -> String:
  match action:
    case Warm{}: ">="
    case Stop{}: "<"

# Math.round of a nonnegative percentage.
def percent(probability: F64) -> String: fixed(F64.floor(F.add(F.multiply(probability, n(100)), ratio(1, 2))), 0n)

def probabilityText(phase: CacheWarmingPhase, +probability: String) -> String:
  match phase:
    case Streaming{}: probability ++ "% continuation probability while agent is running"
    case Idle{}: probability ++ "% continuation probability"

def formatCacheWarmingEconomics(decision: CacheWarmingDecision) -> String:
  match decision:
    case CacheWarmingDecision{_, _, _, _, _, False{}, _}: "cache economics unavailable"
    case CacheWarmingDecision{phase, _, _, continuationProbability, expectedSavings, True{}, action}:
      probabilityText(phase, percent(continuationProbability)) ++ ", expected savings " ++ formatDollars(expectedSavings) ++ " " ++ comparison(action) ++ " $" ++ fixed(CACHE_WARMING_MINIMUM_EXPECTED_SAVINGS(), 3n)

def count(value: F64) -> Nat: Result.default(&2, &2, F.Error, Nat, F.convert(value), 0n)

def timePart(+value: Nat, unit: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Nat.is_gt(value, 0n), [Nat.show(value) ++ unit], Nil{})

def remainingText(+remaining: Nat) -> String:
  +hours = remaining / 3600n
  +minutes = (remaining % 3600n) / 60n
  +seconds = remaining % 60n
  +larger = List.append(&2, String, timePart(hours, "h"), timePart(minutes, "m"))
  +parts = List.append(&2, String, larger, Bool.pick(List<&2, String>, Nat.is_gt(seconds, 0n) || List.is_empty(&2, String, larger), [Nat.show(seconds) ++ "s"], Nil{}))
  "Decision in " ++ String.join(parts, " ")

def formatCacheWarmingDecisionTime(nextWarmAt: Maybe<&2, F64>, +now: F64) -> String:
  match nextWarmAt:
    case None{}: "Decision now"
    case Some{+next}:
      Bool.pick(Unit -> String, F64.is_le(next, now), _ => "Decision now", _ => remainingText(count(F.ceil(F.divide(F.subtract(next, now), n(1000))))))(Unit{})

def details(extensionOverride: Bool, +decision: CacheWarmingDecision) -> String:
  match extensionOverride:
    case True{}: "extension override, " ++ formatCacheWarmingEconomics(decision)
    case False{}:
      match decision:
        case CacheWarmingDecision{phase, warmCost, missCost, continuationProbability, expectedSavings, economicsAvailable, +action}:
          formatCacheWarmingEconomics(CacheWarmingDecision{phase, warmCost, missCost, continuationProbability, expectedSavings, economicsAvailable, action}) ++ " -> " ++ actionName(action)

def reasonText(reason: Maybe<&2, String>) -> String: "Inactive (" ++ Maybe.default(&2, String, reason, "unknown reason") ++ ")"

def isInactive(state: CacheWarmingState) -> Bool:
  match state:
    case Inactive{}: True{}
    case _: False{}

def stateText(state: CacheWarmingState, nextWarmAt: Maybe<&2, F64>, now: F64, +text: String) -> String:
  match state:
    case Inactive{}: "Stopped (" ++ text ++ ")"
    case Refreshing{}: "Warming cache (" ++ text ++ ")"
    case Scheduled{}: formatCacheWarmingDecisionTime(nextWarmAt, now) ++ " (" ++ text ++ ")"

def withDecision(+state: CacheWarmingState, reason: Maybe<&2, String>, nextWarmAt: Maybe<&2, F64>, +decision: CacheWarmingDecision, +extensionOverride: Bool, now: F64) -> String:
  Bool.pick(Unit -> String, isInactive(state) && Bool.not(economics(decision)) && Bool.not(extensionOverride),
    _ => reasonText(reason),
    _ => stateText(state, nextWarmAt, now, details(extensionOverride, decision)))(Unit{})

# One-line status for `/session`. A decision is attached once pi (or an
# extension) acted on it; "inactive" without one never got that far.
def formatCacheWarmingStatus(status: CacheWarmingStatus, now: F64) -> String:
  match status:
    case CacheWarmingStatus{_, reason, _, None{}, _}: reasonText(reason)
    case CacheWarmingStatus{state, reason, nextWarmAt, Some{decision}, extensionOverride}: withDecision(state, reason, nextWarmAt, decision, extensionOverride, now)

def dropZeros(reversed: String, removable: Nat) -> String:
  match reversed removable:
    case SNil{} _: SNil{}
    case SCon{first, rest} 0n: SCon{first, rest}
    case SCon{+first, +rest} 1n+left: Bool.pick(Unit -> String, Char.is_eq(first, '0'), _ => dropZeros(rest, left), _ => SCon{first, rest})(Unit{})

def noteText(note: Maybe<&2, String>) -> String:
  match note:
    case None{}: ""
    case Some{SNil{}}: ""
    case Some{text}: " (" ++ text ++ ")"

# One-line transcript text for persisted cache-warming usage (a usage
# entry's note and usage): the cost with six decimals, trailing zeros
# trimmed to at least three.
def formatCacheWarmingUsage(note: Maybe<&2, String>, usage: Ai.Usage) -> String:
  match usage:
    case Ai.Usage{_, _, _, _, _, _, _, cost}: "Cache warmed" ++ noteText(note) ++ ": $" ++ String.reverse(dropZeros(String.reverse(fixed(totalOf(cost), 6n)), 3n))

# I/O shell
# ---------

def Entry() -> Data: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>

# upstream's Pick<SessionManager, "appendUsage" | "getBranch">: appending
# returns the persisted entry, None when it could not be persisted.
type CacheWarmerSession is Data:
  CacheWarmerSession{appendUsage: C.Callback<UsageRecord, Maybe<&2, Entry()>>, getBranch: C.Callback<Unit, List<&2, Entry()>>}

# The warmer's injected interfaces: `streamSimple` sends a request and
# returns its final message (upstream's models.streamSimple(...).result());
# `context` reads the session's current model and transcript; `decide` lets
# a hook override pi's action; `onWarmed` receives each persisted entry.
type CacheWarmer is Data:
  CacheWarmer{state: R.Ref<Warmer>, streamSimple: C.Callback<CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>>, session: CacheWarmerSession, getMode: C.Callback<Unit, Settings.CacheWarmingMode>, context: C.Callback<Unit, CacheContext>, decide: C.Callback<CacheWarmingDecisionEvent, CacheWarmingAction>, onWarmed: C.Callback<Entry(), Unit>}

def create(streamSimple: C.Callback<CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>>, session: CacheWarmerSession, getMode: C.Callback<Unit, Settings.CacheWarmingMode>, context: C.Callback<Unit, CacheContext>, decide: C.Callback<CacheWarmingDecisionEvent, CacheWarmingAction>, onWarmed: C.Callback<Entry(), Unit>) -> IO(CacheWarmer):
  do IO<CacheWarmer>:
    state : R.Ref<Warmer> <- R.new(Warmer, initial())
    return CacheWarmer{state, streamSimple, session, getMode, context, decide, onWarmed}

# pi's own decision, for callers without a decide hook.
def piDecision(unit: Unit, event: CacheWarmingDecisionEvent) -> IO(CacheWarmingAction):
  IO.pure(CacheWarmingAction, eventAction(event))

def stateOf(warmer: CacheWarmer) -> R.Ref<Warmer>:
  match warmer:
    case CacheWarmer{state, _, _, _, _, _, _}: state

def modeNow(warmer: CacheWarmer) -> IO(Settings.CacheWarmingMode):
  match warmer:
    case CacheWarmer{_, _, _, getMode, _, _, _}: C.call(Unit, Settings.CacheWarmingMode, getMode, Unit{})

def observe(warmer: CacheWarmer) -> IO(Observation):
  match warmer:
    case CacheWarmer{_, _, CacheWarmerSession{_, getBranch}, getMode, context, _, _}:
      do IO<Observation>:
        mode : Settings.CacheWarmingMode <- C.call(Unit, Settings.CacheWarmingMode, getMode, Unit{})
        now : F64 <- Date.now()
        current : CacheContext <- C.call(Unit, CacheContext, context, Unit{})
        branch : List<&2, Entry()> <- C.call(Unit, List<&2, Entry()>, getBranch, Unit{})
        return Observation{mode, now, current, lastPromptTokens(Unit, Tools.ToolDetails, V.Value, branch)}

def release(controller: Maybe<&2, A.AbortController<Unit>>) -> IO(Unit):
  match controller:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        won : Bool <- A.abort(Unit, value, None{})
        return Unit{}

def announced(onWarmed: C.Callback<Entry(), Unit>, entry: Maybe<&2, Entry()>) -> IO(Unit):
  match entry:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: C.call(Entry(), Unit, onWarmed, value)

def recorded(warmer: CacheWarmer, record: Maybe<&2, UsageRecord>) -> IO(Unit):
  match warmer record:
    case _ None{}: IO.pure(Unit, Unit{})
    case CacheWarmer{_, _, CacheWarmerSession{appendUsage, _}, _, _, _, onWarmed} Some{value}:
      do IO<Unit>:
        entry : Maybe<&2, Entry()> <- C.call(UsageRecord, Maybe<&2, Entry()>, appendUsage, value)
        announced(onWarmed, entry)

def delayOf(delay: F64) -> U32: Result.default(&2, &2, Sleep.Error, U32, Sleep.milliseconds(delay), 0)

def woke(+warmer: CacheWarmer, generation: Nat, slept: Result<&2, &2, A.AbortReason<Unit>, Unit>) -> IO(Step):
  match slept:
    case Fail{_}: IO.pure(Step, exitStep())
    case Done{_}:
      do IO<Step>:
        observation : Observation <- observe(warmer)
        R.modify(Warmer, Step, stateOf(warmer), current => fired(current, generation, observation))

def askedDecision(+warmer: CacheWarmer, generation: Nat, action: CacheWarmingAction) -> IO(Step):
  do IO<Step>:
    observation : Observation <- observe(warmer)
    R.modify(Warmer, Step, stateOf(warmer), current => decided(current, generation, action, observation))

def replayedMessage(+warmer: CacheWarmer, generation: Nat, message: Ai.AssistantMessage<V.Value, Unit>) -> IO(Step):
  do IO<Step>:
    observation : Observation <- observe(warmer)
    R.modify(Warmer, Step, stateOf(warmer), current => replayed(current, generation, message, observation))

def decideOf(warmer: CacheWarmer) -> C.Callback<CacheWarmingDecisionEvent, CacheWarmingAction>:
  match warmer:
    case CacheWarmer{_, _, _, _, _, decide, _}: decide

def streamOf(warmer: CacheWarmer) -> C.Callback<CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>>:
  match warmer:
    case CacheWarmer{_, streamSimple, _, _, _, _, _}: streamSimple

# One action of a run's worker and the transition it leads to.
def advance(+warmer: CacheWarmer, generation: Nat, controller: A.AbortController<Unit>, next: Next) -> IO(Step):
  match next:
    case Exit{}: IO.pure(Step, exitStep())
    case Wait{delay}:
      do IO<Step>:
        slept : Result<&2, &2, A.AbortReason<Unit>, Unit> <- Sleep.sleep(Unit, delayOf(delay), A.signal(Unit, controller))
        woke(warmer, generation, slept)
    case Decide{event}:
      do IO<Step>:
        action : CacheWarmingAction <- C.call(CacheWarmingDecisionEvent, CacheWarmingAction, decideOf(warmer), event)
        askedDecision(warmer, generation, action)
    case Replay{request}:
      do IO<Step>:
        message : Ai.AssistantMessage<V.Value, Unit> <- C.call(CacheWarmRequest, Ai.AssistantMessage<V.Value, Unit>, streamOf(warmer), request)
        replayedMessage(warmer, generation, message)

def settlementOf(controller: A.AbortController<Unit>) -> D.Deferred<A.AbortReason<Unit>>:
  match controller:
    case A.AbortController{A.AbortSignal{settlement}}: settlement

def withoutWorker(state: Warmer) -> Warmer & Maybe<&2, D.Deferred<Unit>>:
  match state:
    case Warmer{run, inactive, generation, live, +closing}:
      +remaining = live - 1n
      (Warmer{run, inactive, generation, remaining, closing}, Bool.pick(Maybe<&2, D.Deferred<Unit>>, Nat.is_eq(remaining, 0n), closing, None{}))

def resolveClosing(closing: Maybe<&2, D.Deferred<Unit>>) -> IO(Unit):
  match closing:
    case None{}: IO.pure(Unit, Unit{})
    case Some{deferred}:
      do IO<Unit>:
        won : Bool <- D.resolve(Unit, deferred, Unit{})
        return Unit{}

# A worker exits once its run was removed; whoever removed it aborts the
# controller, so the controller is retired after that abort.
def retire(warmer: CacheWarmer, +controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    reason : A.AbortReason<Unit> <- D.result(A.AbortReason<Unit>, settlementOf(controller))
    A.dispose(Unit, controller)
    closing : Maybe<&2, D.Deferred<Unit>> <- R.modify(Warmer, Maybe<&2, D.Deferred<Unit>>, stateOf(warmer), current => withoutWorker(current))
    resolveClosing(closing)

def nextOf(step: Step) -> Next:
  match step:
    case Step{_, _, next}: next

def releasedOf(step: Step) -> Maybe<&2, A.AbortController<Unit>>:
  match step:
    case Step{released, _, _}: released

def recordOf(step: Step) -> Maybe<&2, UsageRecord>:
  match step:
    case Step{_, record, _}: record

# A worker runs until its run is replaced or stopped; that is not structural.
@unsafe def work(+warmer: CacheWarmer, +generation: Nat, +controller: A.AbortController<Unit>, next: Next) -> IO(Unit):
  match next:
    case Exit{}: retire(warmer, controller)
    case other:
      do IO<Unit>:
        +step : Step <- advance(warmer, generation, controller, other)
        release(releasedOf(step))
        recorded(warmer, recordOf(step))
        work(warmer, generation, controller, nextOf(step))

def spawned(+warmer: CacheWarmer, controller: A.AbortController<Unit>, launch: Maybe<&2, Launch>) -> IO(Unit):
  match launch:
    case None{}: A.dispose(Unit, controller)
    case Some{Launch{generation, delayMs}}: IO.spawn(Unit, work(warmer, generation, controller, Wait{delayMs}))

def launchStarted(+warmer: CacheWarmer, controller: A.AbortController<Unit>, value: Started) -> IO(Unit):
  match value:
    case Started{previous, launch}:
      do IO<Unit>:
        release(previous)
        spawned(warmer, controller, launch)

# upstream start(request, isCurrent): `context` is the conversation the
# request was sent from.
# What `start` knows before touching the state: the mode and clock, whether
# the request can be replayed and its prompt cache lifetime.
def startFacts(mode: Settings.CacheWarmingMode, now: F64, +request: CacheWarmRequest) -> IO(StartFacts):
  do IO<StartFacts>:
    +options : Maybe<&2, Options()> = Some{requestOptions(request)}
    +model : Ai.Model<Ai.JsonValue> = requestModel(request)
    ttlMs : Maybe<&2, F64> <- getPromptCacheTtlMs(model, options)
    return StartFacts{mode, now, isReplayable(model, options), ttlMs, disabledCaching(options)}

def start(+warmer: CacheWarmer, +request: CacheWarmRequest, context: CacheContext) -> IO(Unit):
  do IO<Unit>:
    mode : Settings.CacheWarmingMode <- modeNow(warmer)
    now : F64 <- Date.now()
    facts : StartFacts <- startFacts(mode, now, request)
    +controller : A.AbortController<Unit> <- A.new(Unit)
    value : Started <- R.modify(Warmer, Started, stateOf(warmer), current => started(current, request, context, controller, facts))
    launchStarted(warmer, controller, value)

def onAgentSettled(+warmer: CacheWarmer) -> IO(Unit):
  do IO<Unit>:
    mode : Settings.CacheWarmingMode <- modeNow(warmer)
    now : F64 <- Date.now()
    released : Maybe<&2, A.AbortController<Unit>> <- R.modify(Warmer, Maybe<&2, A.AbortController<Unit>>, stateOf(warmer), current => settledState(current, mode, now))
    release(released)

def onModeChanged(+warmer: CacheWarmer) -> IO(Unit):
  do IO<Unit>:
    mode : Settings.CacheWarmingMode <- modeNow(warmer)
    released : Maybe<&2, A.AbortController<Unit>> <- R.modify(Warmer, Maybe<&2, A.AbortController<Unit>>, stateOf(warmer), current => modeChangedState(current, mode))
    release(released)

def cancel(warmer: CacheWarmer) -> IO(Unit):
  do IO<Unit>:
    released : Maybe<&2, A.AbortController<Unit>> <- R.modify(Warmer, Maybe<&2, A.AbortController<Unit>>, stateOf(warmer), current => cancelled(current))
    release(released)

def status(+warmer: CacheWarmer) -> IO(CacheWarmingStatus):
  do IO<CacheWarmingStatus>:
    observation : Observation <- observe(warmer)
    state : Warmer <- R.read(Warmer, stateOf(warmer))
    return statusOf(state, observation)

def closingState(state: Warmer, closing: D.Deferred<Unit>) -> Warmer & Nat:
  match state:
    case Warmer{run, inactive, generation, +live, _}: (Warmer{run, inactive, generation, live, Some{closing}}, live)

def awaitWorkers(live: Nat, +closing: D.Deferred<Unit>) -> IO(Unit):
  match live:
    case 0n: D.dispose(Unit, closing)
    case _:
      do IO<Unit>:
        D.result(Unit, closing)
        D.dispose(Unit, closing)

# Cancel warming and wait until every worker has exited, so no refresh
# touches the session afterwards. The injected callbacks remain the caller's.
def dispose(+warmer: CacheWarmer) -> IO(Unit):
  do IO<Unit>:
    cancel(warmer)
    +closing : D.Deferred<Unit> <- D.new(Unit)
    live : Nat <- R.modify(Warmer, Nat, stateOf(warmer), current => closingState(current, closing))
    awaitWorkers(live, closing)
    released : Warmer <- R.dispose(Warmer, stateOf(warmer))
    return Unit{}
