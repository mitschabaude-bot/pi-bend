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

def HookOutput() -> Data: Result<&2, &2, String, Maybe<&2, R.Ref<H.Update()>>>
def Hook() -> Data: C.Callback<R.Ref<H.Turn()>, HookOutput()>
def Outcome() -> Data: Result<&2, &2, String, U.State()>

type Environment is Data:
  Environment{mode: U32, expected: R.Ref<H.Turn()>, config: R.Ref<U.Config()>, update: R.Ref<H.Update()>, entered: D.Deferred<Unit>, release: D.Deferred<Unit>, count: R.Ref<U32>}

def withHook(value: U.Config(), hook: Maybe<&2, Hook()>) -> U.Config():
  match value:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, _, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, hook, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def returned(mode: U32, update: R.Ref<H.Update()>) -> HookOutput():
  match mode:
    case 1: Done{None{}}
    case 4: Fail{"hook failure"}
    case _: Done{Some{update}}

def body(environment: Environment, input: R.Ref<H.Turn()>) -> IO(HookOutput()):
  match environment:
    case Environment{mode, expected, config, update, entered, release, count}:
      do IO<HookOutput()>:
        Test.assertion(R.same(H.Turn(), input, expected), "prepare hook received a copied completed-turn context")
        R.modify(U32, Unit, count, n => (U32.add(n, 1), Unit{}))
        R.modify(U.Config(), Unit, config, value => (Loop.withTurnConfig(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, value, None{}, Some{Ai.Thinking{Ai.Low{}}}), Unit{}))
        won : Bool <- D.resolve(Unit, entered, Unit{})
        D.result(Unit, release)
        return returned(mode, update)

def task(context: R.Ref<H.Context()>, config: R.Ref<U.Config()>, completed: R.Ref<H.Turn()>, done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    outcome : Outcome() <- Loop.prepareNextTurn(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, config, completed)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return outcome

def drive(mode: U32, context: R.Ref<H.Context()>, config: R.Ref<U.Config()>, completed: R.Ref<H.Turn()>, entered: D.Deferred<Unit>, release: D.Deferred<Unit>, +done: D.Deferred<Unit>) -> IO(Outcome()):
  match mode:
    case 0: task(context, config, completed, done)
    case _:
      do IO<Outcome()>:
        running : Chan(Outcome()) <- IO.fork(Outcome(), task(context, config, completed, done))
        D.result(Unit, entered)
        status : Maybe<&2, Unit> <- D.peek(Unit, done)
        Test.assertion(Maybe.is_none(&2, Unit, status), "next-turn preparation did not await hook settlement")
        won : Bool <- D.resolve(Unit, release, Unit{})
        IO.join(Outcome(), running)

def check(outcome: Outcome(), oldContext: R.Ref<H.Context()>, oldConfig: R.Ref<U.Config()>, oldModel: R.Ref<Ai.Model<Unit>>, provided: H.Messages(), convert: U.Converter(), expected: String) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(String.eq(error, expected), "prepare hook error was replaced")
    case Done{Loop.PreparedTurnState{context, +config, +messages}}:
      do IO<Unit>:
        +sameConfig : Bool = R.same(U.Config(), config, oldConfig)
        +sameMessages : Bool = R.same(List<&2, H.Message()>, messages, provided)
        current : U.Config() <- R.read(U.Config(), config)
        view : String <- U.view(current, oldModel, convert)
        actual : String = U.boolean(sameConfig) ++ "|" ++ view ++ "|" ++ U.boolean(sameMessages) ++ "|" ++ U.boolean(R.same(H.Context(), context, oldContext))
        Test.assertion(String.eq(actual, expected), "prepare hook/update result differs from upstream")
        U.releaseNew(U.Config(), sameConfig, config)
        U.releaseNew(List<&2, H.Message()>, sameMessages, messages)

def replacement(mode: U32, provided: H.Messages()) -> H.Update():
  match mode:
    case 3: T.AgentLoopTurnUpdate{None{}, Some{provided}, None{}, Some{Ai.Off{}}}
    case _: T.AgentLoopTurnUpdate{None{}, None{}, None{}, None{}}

def run(+mode: U32, expected: String, expectedCalls: U32, originalReasoning: String) -> IO(Unit):
  do IO<Unit>:
    +messages : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +provided : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{messages, None{}})
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +assistant : R.Ref<Ai.AssistantMessage<String, Unit>> <- R.new(Ai.AssistantMessage<String, Unit>, Test.assistant(cost, Ai.Stop{}))
    +results : R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<String>>>> <- R.new(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, Nil{})
    +completed : R.Ref<H.Turn()> <- R.new(H.Turn(), T.ShouldStopAfterTurnContext{assistant, results, context, messages})
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +convert : U.Converter() <- C.create(~Unit, ~H.Messages(), ~U.Output(), ~U.forbidden, Unit{})
    +config : R.Ref<U.Config()> <- R.new(U.Config(), U.config(model, Some{Ai.High{}}, convert))
    +update : R.Ref<H.Update()> <- R.new(H.Update(), replacement(mode, provided))
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +count : R.Ref<U32> <- R.new(U32, 0)
    +hook : Hook() <- C.create(~Environment, ~R.Ref<H.Turn()>, ~HookOutput(), ~body, Environment{mode, completed, config, update, entered, release, count})
    R.modify(U.Config(), Unit, config, value => (withHook(value, U.selected(Hook(), Bool.not(U32.is_eq(mode, 0)), hook)), Unit{}))
    outcome : Outcome() <- drive(mode, context, config, completed, entered, release, done)
    check(outcome, context, config, model, provided, convert, expected)
    calls : U32 <- R.read(U32, count)
    Test.assertion(U32.is_eq(calls, expectedCalls), "prepare callback invocation count differs")
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    retained : String <- U.view(oldConfig, model, convert)
    Test.assertion(String.eq(retained, originalReasoning ++ "|true"), "callback-side configuration mutations were lost")
    C.dispose(R.Ref<H.Turn()>, HookOutput(), hook)
    C.dispose(H.Messages(), U.Output(), convert)
    oldCount : U32 <- R.dispose(U32, count)
    oldUpdate : H.Update() <- R.dispose(H.Update(), update)
    oldCompleted : H.Turn() <- R.dispose(H.Turn(), completed)
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    oldResults : List<&2, R.Ref<Ai.ToolResultMessage<String>>> <- R.dispose(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, results)
    oldAssistant : Ai.AssistantMessage<String, Unit> <- R.dispose(Ai.AssistantMessage<String, Unit>, assistant)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    oldMessages : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, messages)
    oldProvided : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, provided)
    D.dispose(Unit, entered)
    D.dispose(Unit, release)
    D.dispose(Unit, done)
