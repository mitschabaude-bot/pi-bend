import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./turn-update.bend as U
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as F

import ./queue-poll.bend as Q
import ./stop-turn.bend as S
def Outcome() -> Data: Result<&2, &2, String, Maybe<&2, String>>
def Request() -> Data: Result<&2, &2, String, R.Ref<U.Config()>>

def Resolver() -> Data: C.Callback<String, Outcome()>
type Environment is Data:
  Environment{mode: U32, rotate: Bool, config: R.Ref<U.Config()>, calls: R.Ref<U32>, gate: S.Gate}

def withKey(value: U.Config(), key: Maybe<&2, String>, resolver: Maybe<&2, Resolver()>) -> U.Config():
  match value:
    case T.AgentLoopConfig{signal, telemetryContext, _, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, _, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, key, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, resolver, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def rotateKey(+value: U.Config()) -> U.Config():
  withKey(value, Some{"rotated"}, Loop.selectedApiKeyResolver(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, value))

def mutate(rotate: Bool, config: R.Ref<U.Config()>) -> IO(Unit):
  match rotate:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: R.modify(U.Config(), Unit, config, value => (rotateKey(value), Unit{}))

def returned(mode: U32) -> Outcome():
  match mode:
    case 1: Done{None{}}
    case 2: Done{Some{""}}
    case 3: Done{Some{"resolved"}}
    case _: Fail{"resolver failure"}

def body(environment: Environment, provider: String) -> IO(Outcome()):
  match environment:
    case Environment{mode, rotate, config, calls, gate}:
      do IO<Outcome()>:
        Test.assertion(String.eq(provider, "test-provider"), "resolver received incorrect provider")
        R.modify(U32, Unit, calls, n => (U32.add(n, 1), Unit{}))
        mutate(rotate, config)
        S.suspend(gate)
        return returned(mode)

def signalPresent(value: U.Config()) -> Bool:
  match value:
    case T.AgentLoopConfig{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: Bool.not(Maybe.is_none(&2, Unit, signal))

def checkSnapshot(result: Request(), +original: R.Ref<U.Config()>, signaled: Bool) -> IO(Outcome()):
  match result:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{+copied}:
      do IO<Outcome()>:
        Test.assertion(Bool.not(R.same(U.Config(), original, copied)), "request must allocate a new config")
        +oldConfig : U.Config() <- R.read(U.Config(), original)
        +current : U.Config() <- R.dispose(U.Config(), copied)
        Test.assertion(String.eq(U.boolean(signalPresent(current)), U.boolean(signaled)), "request signal override differs")
        Test.assertion(signalPresent(oldConfig), "request snapshot mutated original signal")
        +expectedModel : R.Ref<Ai.Model<Unit>> = Loop.selectedRequestModel(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, oldConfig)
        +expectedConvert : U.Converter() = Loop.selectedMessageConverter(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, oldConfig)
        retained : String <- U.view(current, expectedModel, expectedConvert)
        Test.assertion(String.eq(retained, "none|true"), "request snapshot changed unrelated fields")
        return Done{Loop.selectedApiKey(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, current)}

def task(+config: R.Ref<U.Config()>, +signaled: Bool, done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    snapshot : Request() <- Loop.resolveRequestConfig(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config, U.selected(Unit, signaled, Unit{}))
    result : Outcome() <- checkSnapshot(snapshot, config, signaled)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def advance(mode: U32, gate: S.Gate, done: D.Deferred<Unit>) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case _: S.advance(gate, done)

def showKey(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{key}: "key:" ++ key

def showResult(value: Outcome()) -> String:
  match value:
    case Fail{error}: "error:" ++ error
    case Done{key}: showKey(key)

def run(+mode: U32, +fallback: Maybe<&2, String>, rotate: Bool, signaled: Bool, expectedCalls: U32, expected: String, retained: String) -> IO(Unit):
  do IO<Unit>:
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +convert : U.Converter() <- C.create(~Unit, ~H.Messages(), ~U.Output(), ~U.forbidden, Unit{})
    +config : R.Ref<U.Config()> <- R.new(U.Config(), withKey(U.config(model, None{}, convert), fallback, None{}))
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +resolver : Resolver() <- C.create(~Environment, ~String, ~Outcome(), ~body, Environment{mode, rotate, config, calls, S.Gate{entered, release}})
    R.modify(U.Config(), Unit, config, value => (withKey(value, fallback, U.selected(Resolver(), Bool.not(U32.is_eq(mode, 0)), resolver)), Unit{}))
    R.modify(U.Config(), Unit, config, value => (Loop.withRequestOverrides(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, value, fallback, Some{Unit{}}), Unit{}))
    running : Chan(Outcome()) <- IO.fork(Outcome(), task(config, signaled, done))
    advance(mode, S.Gate{entered, release}, done)
    result : Outcome() <- IO.join(Outcome(), running)
    Test.assertion(String.eq(showResult(result), expected), "API-key resolution differs from upstream")
    actualCalls : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(actualCalls, expectedCalls), "API-key callback invocation count differs")
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    Test.assertion(String.eq(showKey(Loop.selectedApiKey(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, oldConfig)), retained), "resolver-side config mutation lost")
    C.dispose(String, Outcome(), resolver)
    C.dispose(H.Messages(), U.Output(), convert)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    D.dispose(Unit, entered)
    D.dispose(Unit, release)
    D.dispose(Unit, done)
