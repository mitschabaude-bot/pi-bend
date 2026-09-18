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
def HookOutput() -> Data: Result<&2, &2, String, Bool>
def Hook() -> Data: C.Callback<R.Ref<H.Turn()>, HookOutput()>
def Outcome() -> Data: Result<&2, &2, String, Maybe<&2, H.Messages()>>
def Event() -> Data: T.AgentEvent<Unit, String, Unit, String, String, Unit, Unit>
def Emitted() -> Data: Result<&2, &2, String, Unit>
def Sink() -> Data: Loop.AgentEventSink(Unit, String, Unit, String, String, Unit, Unit, String)
type Gate is Data:
  Gate{entered: D.Deferred<Unit>, release: D.Deferred<Unit>}
type QueueEnvironment is Data:
  QueueEnvironment{mode: U32, queued: H.Messages(), trace: R.Ref<String>, gate: Gate}
type HookEnvironment is Data:
  HookEnvironment{mode: U32, expected: R.Ref<H.Turn()>, replacement: H.Messages(), config: R.Ref<U.Config()>, queue: Q.Queue(), trace: R.Ref<String>, gate: Gate}
type EmitEnvironment is Data:
  EmitEnvironment{mode: U32, messages: H.Messages(), trace: R.Ref<String>, gate: Gate}

def withHook(value: U.Config(), hook: Maybe<&2, Hook()>) -> U.Config():
  match value:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, _, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, hook, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}


def append(trace: R.Ref<String>, phase: String) -> IO(Unit):
  R.modify(String, Unit, trace, old => (old ++ phase, Unit{}))

def suspend(gate: Gate) -> IO(Unit):
  match gate:
    case Gate{entered, release}:
      do IO<Unit>:
        won : Bool <- D.resolve(Unit, entered, Unit{})
        D.result(Unit, release)

def advance(gate: Gate, done: D.Deferred<Unit>) -> IO(Unit):
  match gate:
    case Gate{entered, release}:
      do IO<Unit>:
        D.result(Unit, entered)
        status : Maybe<&2, Unit> <- D.peek(Unit, done)
        Test.assertion(Maybe.is_none(&2, Unit, status), "completed-turn callback was not awaited")
        won : Bool <- D.resolve(Unit, release, Unit{})
        return Unit{}

def replaceMessages(value: H.Turn(), messages: H.Messages()) -> H.Turn():
  match value:
    case T.ShouldStopAfterTurnContext{message, results, context, _}: T.ShouldStopAfterTurnContext{message, results, context, messages}

def sharedHookBody(environment: HookEnvironment, +input: R.Ref<H.Turn()>) -> IO(HookOutput()):
  match environment:
    case HookEnvironment{+mode, expected, replacement, config, queue, trace, gate}:
      do IO<HookOutput()>:
        Test.assertion(R.same(H.Turn(), input, expected), "stop hook context identity changed")
        append(trace, "hook|")
        R.modify(H.Turn(), Unit, input, value => (replaceMessages(value, replacement), Unit{}))
        R.modify(U.Config(), Unit, config, value => (Q.withQueues(value, Some{queue}, None{}), Unit{}))
        suspend(gate)
        return Bool.pick(HookOutput(), U32.is_eq(mode, 3), Fail{"hook failure"}, Done{U32.is_eq(mode, 2) || U32.is_eq(mode, 4)})

def hookBody(environment: HookEnvironment, input: R.Ref<H.Turn()>) -> IO(HookOutput()):
  sharedHookBody(environment, input)

def queueBody(environment: QueueEnvironment, input: Unit) -> IO(Q.Outcome()):
  match environment:
    case QueueEnvironment{mode, queued, trace, gate}:
      do IO<Q.Outcome()>:
        append(trace, "queue|")
        suspend(gate)
        return Bool.pick(Q.Outcome(), U32.is_eq(mode, 5), Fail{"queue failure"}, Done{queued})

def emitBody(environment: EmitEnvironment, event: Event()) -> IO(Emitted()):
  match environment event:
    case EmitEnvironment{mode, messages, trace, gate} T.AgentEnd{actual}:
      do IO<Emitted()>:
        Test.assertion(R.same(List<&2, H.Message()>, actual, messages), "agent_end must retain original local message array")
        append(trace, "end|")
        suspend(gate)
        return Bool.pick(Emitted(), U32.is_eq(mode, 4), Fail{"emit failure"}, Done{Unit{}})
    case _ _: IO.die(Emitted(), 1, "unexpected event after completed turn")

def task(config: R.Ref<U.Config()>, completed: R.Ref<H.Turn()>, messages: H.Messages(), emit: Sink(), done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    result : Outcome() <- Loop.finishCompletedTurn(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, Unit, Unit, config, completed, messages, emit)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def advanceHook(mode: U32, gate: Gate, done: D.Deferred<Unit>, trace: R.Ref<String>) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case _:
      match gate:
        case Gate{+entered, release}:
          do IO<Unit>:
            D.result(Unit, entered)
            actual : String <- R.read(String, trace)
            Test.assertion(String.eq(actual, "hook|"), "queue/event ran before hook settlement")
            advance(Gate{entered, release}, done)

def advanceNext(mode: U32, gate: Gate, done: D.Deferred<Unit>) -> IO(Unit):
  match mode:
    case 3: IO.pure(Unit, Unit{})
    case _: advance(gate, done)

def check(outcome: Outcome(), queued: H.Messages(), expected: String) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(String.eq(error, expected), "completed-turn failure changed")
    case Done{None{}}: Test.assertion(String.eq(expected, "stopped"), "unexpected completed-turn stop")
    case Done{Some{messages}}: Test.assertion(String.eq(expected, "queued") && R.same(List<&2, H.Message()>, messages, queued), "completed-turn pending array changed")

def wasReplaced(value: H.Turn(), replacement: H.Messages()) -> Bool:
  match value:
    case T.ShouldStopAfterTurnContext{_, _, _, actual}: R.same(List<&2, H.Message()>, actual, replacement)

def run(+mode: U32, expected: String, expectedTrace: String, expectedReplacement: Bool) -> IO(Unit):
  do IO<Unit>:
    +messages : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +provided : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{messages, None{}})
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +assistantContent : R.Ref<List<&2, Ai.AssistantContent<String>>> <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +assistant : R.Ref<Ai.AssistantMessage<String, Unit>> <- R.new(Ai.AssistantMessage<String, Unit>, Test.assistant(assistantContent, cost, Ai.Stop{}))
    +results : R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<String>>>> <- R.new(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, Nil{})
    +completed : R.Ref<H.Turn()> <- R.new(H.Turn(), T.ShouldStopAfterTurnContext{assistant, results, context, messages})
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +convert : U.Converter() <- C.create(~Unit, ~H.Messages(), ~U.Output(), ~U.forbidden, Unit{})
    +config : R.Ref<U.Config()> <- R.new(U.Config(), U.config(model, Some{Ai.High{}}, convert))
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +nextEntered : D.Deferred<Unit> <- D.new(Unit)
    +nextRelease : D.Deferred<Unit> <- D.new(Unit)
    +trace : R.Ref<String> <- R.new(String, "")
    +queue : Q.Queue() <- C.create(~QueueEnvironment, ~Unit, ~Q.Outcome(), ~queueBody, QueueEnvironment{mode, provided, trace, Gate{nextEntered, nextRelease}})
    +forbidden : Q.Queue() <- C.create(~Unit, ~Unit, ~Q.Outcome(), ~Q.forbidden, Unit{})
    +emit : Sink() <- C.create(~EmitEnvironment, ~Event(), ~Emitted(), ~emitBody, EmitEnvironment{mode, messages, trace, Gate{nextEntered, nextRelease}})
    +hook : Hook() <- C.create(~HookEnvironment, ~R.Ref<H.Turn()>, ~HookOutput(), ~hookBody, HookEnvironment{mode, completed, provided, config, queue, trace, Gate{entered, release}})
    R.modify(U.Config(), Unit, config, value => (withHook(value, U.selected(Hook(), Bool.not(U32.is_eq(mode, 0)), hook)), Unit{}))
    R.modify(U.Config(), Unit, config, value => (Q.withQueues(value, Some{Bool.pick(Q.Queue(), U32.is_eq(mode, 0), queue, forbidden)}, None{}), Unit{}))
    running : Chan(Outcome()) <- IO.fork(Outcome(), task(config, completed, messages, emit, done))
    advanceHook(mode, Gate{entered, release}, done, trace)
    advanceNext(mode, Gate{nextEntered, nextRelease}, done)
    outcome : Outcome() <- IO.join(Outcome(), running)
    check(outcome, provided, expected)
    actualTrace : String <- R.dispose(String, trace)
    Test.assertion(String.eq(actualTrace, expectedTrace), "completed-turn callback order differs")
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    C.dispose(Unit, Q.Outcome(), queue)
    C.dispose(Unit, Q.Outcome(), forbidden)
    C.dispose(Event(), Emitted(), emit)
    C.dispose(R.Ref<H.Turn()>, HookOutput(), hook)
    C.dispose(H.Messages(), U.Output(), convert)
    oldCompleted : H.Turn() <- R.dispose(H.Turn(), completed)
    Test.assertion(String.eq(U.boolean(wasReplaced(oldCompleted, provided)), U.boolean(expectedReplacement)), "stop hook context mutations lost")
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    oldResults : List<&2, R.Ref<Ai.ToolResultMessage<String>>> <- R.dispose(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, results)
    oldAssistant : Ai.AssistantMessage<String, Unit> <- R.dispose(Ai.AssistantMessage<String, Unit>, assistant)
    oldAssistantContent : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, assistantContent)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    oldMessages : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, messages)
    oldProvided : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, provided)
    D.dispose(Unit, entered)
    D.dispose(Unit, release)
    D.dispose(Unit, done)
    D.dispose(Unit, nextEntered)
    D.dispose(Unit, nextRelease)
