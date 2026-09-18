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

def Outcome() -> Data: Result<&2, &2, String, H.Messages()>
def Queue() -> Data: C.Callback<Unit, Outcome()>
type Environment is Data:
  Environment{mode: U32, supplied: H.Messages(), entered: D.Deferred<Unit>, release: D.Deferred<Unit>, calls: R.Ref<U32>}

def forbidden(environment: Unit, input: Unit) -> IO(Outcome()):
  IO.die(Outcome(), 1, "wrong queue callback invoked")

def body(environment: Environment, input: Unit) -> IO(Outcome()):
  match environment:
    case Environment{mode, supplied, entered, release, calls}:
      do IO<Outcome()>:
        R.modify(U32, Unit, calls, n => (U32.add(n, 1), Unit{}))
        won : Bool <- D.resolve(Unit, entered, Unit{})
        D.result(Unit, release)
        return Bool.pick(Outcome(), U32.is_eq(mode, 3), Fail{"queue failure"}, Done{supplied})

def withQueues(value: U.Config(), steering: Maybe<&2, Queue()>, followUp: Maybe<&2, Queue()>) -> U.Config():
  match value:
    case T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, _, _, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, steering, followUp, toolExecution, beforeToolCall, afterToolCall}

def poll(route: U32, config: R.Ref<U.Config()>, pending: H.Messages()) -> IO(Outcome()):
  match route:
    case 0: Loop.pollSteeringMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config)
    case 1: Loop.pollFollowUpMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config)
    case _: Loop.repollSteeringMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config, pending)

def task(route: U32, config: R.Ref<U.Config()>, pending: H.Messages(), done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    result : Outcome() <- poll(route, config, pending)
    won : Bool <- D.resolve(Unit, done, Unit{})
    return result

def fill(populated: Bool, target: H.Messages(), item: R.Ref<String>) -> IO(Unit):
  match populated:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: R.write(List<&2, H.Message()>, target, T.CustomMessage{item} <> Nil{})

def drive(invoke: Bool, route: U32, mode: U32, config: R.Ref<U.Config()>, pending: H.Messages(), supplied: H.Messages(), item: R.Ref<String>, entered: D.Deferred<Unit>, release: D.Deferred<Unit>, +done: D.Deferred<Unit>) -> IO(Outcome()):
  match invoke:
    case False{}: task(route, config, pending, done)
    case True{}:
      do IO<Outcome()>:
        running : Chan(Outcome()) <- IO.fork(Outcome(), task(route, config, pending, done))
        D.result(Unit, entered)
        status : Maybe<&2, Unit> <- D.peek(Unit, done)
        Test.assertion(Maybe.is_none(&2, Unit, status), "queue callback was not awaited")
        fill(U32.is_eq(mode, 2), supplied, item)
        won : Bool <- D.resolve(Unit, release, Unit{})
        IO.join(Outcome(), running)

def contents(values: List<&2, H.Message()>, item: R.Ref<String>) -> IO(String):
  match values:
    case Nil{}: IO.pure(String, "0")
    case message <> Nil{}:
      do IO<String>:
        Test.assertion(H.sharedElement(message, item), "queue message identity lost")
        return "1"
    case _: IO.die(String, 1, "unexpected queue array length")

def check(outcome: Outcome(), pending: H.Messages(), supplied: H.Messages(), item: R.Ref<String>, expected: String) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(String.eq(error, expected), "queue failure changed")
    case Done{+messages}:
      do IO<Unit>:
        +samePending : Bool = R.same(List<&2, H.Message()>, messages, pending)
        +sameSupplied : Bool = R.same(List<&2, H.Message()>, messages, supplied)
        values : List<&2, H.Message()> <- R.read(List<&2, H.Message()>, messages)
        length : String <- contents(values, item)
        actual : String = U.boolean(samePending) ++ "|" ++ U.boolean(sameSupplied) ++ "|" ++ length
        Test.assertion(String.eq(actual, expected), "queue result differs from upstream")
        U.releaseNew(List<&2, H.Message()>, samePending || sameSupplied, messages)

def run(+route: U32, +populated: Bool, +mode: U32, expectedCalls: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    +item : R.Ref<String> <- R.new(String, "queued")
    +pending : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +supplied : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    fill(populated, pending, item)
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +callback : Queue() <- C.create(~Environment, ~Unit, ~Outcome(), ~body, Environment{mode, supplied, entered, release, calls})
    +other : Queue() <- C.create(~Unit, ~Unit, ~Outcome(), ~forbidden, Unit{})
    +selected : Maybe<&2, Queue()> = U.selected(Queue(), Bool.not(U32.is_eq(mode, 0)), callback)
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))
    +convert : U.Converter() <- C.create(~Unit, ~H.Messages(), ~U.Output(), ~U.forbidden, Unit{})
    +isFollow : Bool = U32.is_eq(route, 1)
    +config : R.Ref<U.Config()> <- R.new(U.Config(), withQueues(U.config(model, None{}, convert), Bool.pick(Maybe<&2, Queue()>, isFollow, Some{other}, selected), Bool.pick(Maybe<&2, Queue()>, isFollow, selected, Some{other})))
    invoke : Bool = Bool.not(U32.is_eq(mode, 0)) && Bool.not(U32.is_eq(route, 2) && populated)
    outcome : Outcome() <- drive(invoke, route, mode, config, pending, supplied, item, entered, release, done)
    check(outcome, pending, supplied, item, expected)
    actualCalls : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(actualCalls, expectedCalls), "queue polled incorrect number of times")
    C.dispose(Unit, Outcome(), callback)
    C.dispose(Unit, Outcome(), other)
    C.dispose(H.Messages(), U.Output(), convert)
    oldConfig : U.Config() <- R.dispose(U.Config(), config)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    oldPending : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, pending)
    oldSupplied : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, supplied)
    oldItem : String <- R.dispose(String, item)
    D.dispose(Unit, entered)
    D.dispose(Unit, release)
    D.dispose(Unit, done)
