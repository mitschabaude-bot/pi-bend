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
def Input() -> Data: T.TransformContextInput<H.Messages(), Unit>
def Transformed() -> Data: Result<&2, &2, String, H.Messages()>
def Transform() -> Data: C.Callback<Input(), Transformed()>
def Prepared() -> Data: Result<&2, &2, String, R.Ref<Ai.TranscriptContext<Unit, String, Unit, String>>>

def LlmMessages() -> Data: R.Ref<List<&2, Ai.Message<Unit, String, Unit, String>>>
type ConvertEnvironment is Data:
  ConvertEnvironment{mode: U32, expected: H.Messages(), output: LlmMessages(), trace: R.Ref<String>, gate: S.Gate}
type TransformEnvironment is Data:
  TransformEnvironment{mode: U32, original: H.Messages(), replacement: H.Messages(), context: R.Ref<H.Context()>, config: R.Ref<U.Config()>, converter: U.Converter(), signal: Bool, trace: R.Ref<String>, gate: S.Gate}

def withConversion(value: U.Config(), convert: U.Converter(), transform: Maybe<&2, Transform()>) -> U.Config():
  match value:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, _, _, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convert, transform, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}

def withConverter(+value: U.Config(), convert: U.Converter()) -> U.Config():
  withConversion(value, convert, Loop.selectedContextTransform(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, value))

def convertBody(environment: ConvertEnvironment, input: H.Messages()) -> IO(U.Output()):
  match environment:
    case ConvertEnvironment{mode, expected, output, trace, gate}:
      do IO<U.Output()>:
        Test.assertion(R.same(List<&2, H.Message()>, input, expected), "converter received incorrect array")
        S.append(trace, "convert|")
        S.suspend(gate)
        return Bool.pick(U.Output(), U32.is_eq(mode, 4), Fail{"conversion failure"}, Done{output})

def transformBody(environment: TransformEnvironment, input: Input()) -> IO(Transformed()):
  match environment input:
    case TransformEnvironment{+mode, original, +replacement, context, config, converter, expectedSignal, trace, gate} T.TransformContextInput{+messages, signal}:
      do IO<Transformed()>:
        Test.assertion(R.same(List<&2, H.Message()>, messages, original), "transform received incorrect original array")
        Test.assertion(String.eq(U.boolean(Bool.not(Maybe.is_none(&2, Unit, signal))), U.boolean(expectedSignal)), "transform received incorrect signal")
        S.append(trace, "transform|")
        R.write(H.Context(), context, T.AgentContext{replacement, None{}})
        R.modify(U.Config(), Unit, config, value => (withConverter(value, converter), Unit{}))
        S.suspend(gate)
        return Bool.pick(Transformed(), U32.is_eq(mode, 3), Fail{"transform failure"}, Done{Bool.pick(H.Messages(), U32.is_eq(mode, 2), replacement, messages)})

def task(context: R.Ref<H.Context()>, config: R.Ref<U.Config()>, signal: Maybe<&2, Unit>, done: D.Deferred<Unit>) -> IO(Prepared()):
  do IO<Prepared()>:
    result : Prepared() <- Loop.prepareLlmContext(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, config, signal)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def advanceTransform(mode: U32, gate: S.Gate, done: D.Deferred<Unit>, trace: R.Ref<String>) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case _:
      match gate:
        case S.Gate{+entered, release}:
          do IO<Unit>:
            D.result(Unit, entered)
            actual : String <- R.read(String, trace)
            Test.assertion(String.eq(actual, "transform|"), "conversion started before transform settlement")
            S.advance(S.Gate{entered, release}, done)

def checkNormalized(context: Ai.TranscriptContext<Unit, String, Unit, String>, output: LlmMessages(), expected: String) -> IO(Unit):
  match context:
    case Ai.TranscriptContext{messages}: Test.assertion(String.eq(expected, "output") && R.same(List<&2, Ai.Message<Unit, String, Unit, String>>, messages, output), "normalized conversion output array was copied")

def check(outcome: Prepared(), output: LlmMessages(), expected: String) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(String.eq(error, expected), "conversion pipeline failure changed")
    case Done{context}:
      do IO<Unit>:
        normalized : Ai.TranscriptContext<Unit, String, Unit, String> <- R.dispose(Ai.TranscriptContext<Unit, String, Unit, String>, context)
        checkNormalized(normalized, output, expected)

def run(+mode: U32, +signaled: Bool, expected: String, expectedTrace: String, replaced: Bool) -> IO(Unit):
  do IO<Unit>:
    +original : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +replacement : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +output : LlmMessages() <- R.new(List<&2, Ai.Message<Unit, String, Unit, String>>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{original, None{}})
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +nextEntered : D.Deferred<Unit> <- D.new(Unit)
    +nextRelease : D.Deferred<Unit> <- D.new(Unit)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +trace : R.Ref<String> <- R.new(String, "")
    +convert : U.Converter() <- C.create(~ConvertEnvironment, ~H.Messages(), ~U.Output(), ~convertBody, ConvertEnvironment{mode, Bool.pick(H.Messages(), U32.is_eq(mode, 2), replacement, original), output, trace, S.Gate{nextEntered, nextRelease}})
    +forbidden : U.Converter() <- C.create(~Unit, ~H.Messages(), ~U.Output(), ~U.forbidden, Unit{})
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +config : R.Ref<U.Config()> <- R.new(U.Config(), U.config(model, None{}, Bool.pick(U.Converter(), U32.is_eq(mode, 0), convert, forbidden)))
    +transform : Transform() <- C.create(~TransformEnvironment, ~Input(), ~Transformed(), ~transformBody, TransformEnvironment{mode, original, replacement, context, config, convert, signaled, trace, S.Gate{entered, release}})
    R.modify(U.Config(), Unit, config, value => (withConversion(value, Bool.pick(U.Converter(), U32.is_eq(mode, 0), convert, forbidden), U.selected(Transform(), Bool.not(U32.is_eq(mode, 0)), transform)), Unit{}))
    running : Chan(Prepared()) <- IO.fork(Prepared(), task(context, config, U.selected(Unit, signaled, Unit{}), done))
    advanceTransform(mode, S.Gate{entered, release}, done, trace)
    S.advanceNext(mode, S.Gate{nextEntered, nextRelease}, done)
    outcome : Prepared() <- IO.join(Prepared(), running)
    check(outcome, output, expected)
    actualTrace : String <- R.dispose(String, trace)
    Test.assertion(String.eq(actualTrace, expectedTrace), "conversion callback trace changed")
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    actualMessages : H.Messages() = Loop.contextMessages(Unit, String, Unit, String, String, U32, Unit, String, oldContext)
    Test.assertion(String.eq(U.boolean(R.same(List<&2, H.Message()>, actualMessages, replacement)), U.boolean(replaced)), "transform context mutation lost")
    C.dispose(Input(), Transformed(), transform)
    C.dispose(H.Messages(), U.Output(), convert)
    C.dispose(H.Messages(), U.Output(), forbidden)
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    oldOriginal : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, original)
    oldReplacement : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, replacement)
    oldOutput : List<&2, Ai.Message<Unit, String, Unit, String>> <- R.dispose(List<&2, Ai.Message<Unit, String, Unit, String>>, output)
    D.dispose(Unit, entered)
    D.dispose(Unit, release)
    D.dispose(Unit, nextEntered)
    D.dispose(Unit, nextRelease)
    D.dispose(Unit, done)
