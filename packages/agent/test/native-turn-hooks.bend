import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ./context.bend as H
import ./turn-update.bend as ConfigTest

def Config() -> Data: ConfigTest.Config()
def QueueResult() -> Data: Result<&2, &2, String, H.Messages()>
def StopResult() -> Data: Result<&2, &2, String, Bool>
def PrepareResult() -> Data: Result<&2, &2, String, Maybe<&2, H.Update()>>
def StateResult() -> Data: Result<&2, &2, String, ConfigTest.State()>
def Log() -> Data: R.Ref<List<&2, String>>

def log(value: Log(), name: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, value, entries => (name <> entries, Unit{}))

def queue(logValue: Log(), input: Unit) -> IO(QueueResult()):
  do IO<QueueResult()>:
    log(logValue, "queue")
    return Done{T.CustomMessage{"queued"} <> Nil{}}

def stop(logValue: Log(), input: H.Turn()) -> IO(StopResult()):
  do IO<StopResult()>:
    log(logValue, "stop")
    return Done{True{}}

def prepare(logValue: Log(), input: H.Turn()) -> IO(PrepareResult()):
  match input:
    case T.ShouldStopAfterTurnContext{_, _, context, _}:
      do IO<PrepareResult()>:
        log(logValue, "prepare")
        return Done{Some{T.AgentLoopTurnUpdate{Some{context}, Some{T.CustomMessage{"updated guidance"} <> Nil{}}, None{}, Some{Ai.Off{}}}}}

def queueFailure(unused: Unit, input: Unit) -> IO(QueueResult()):
  IO.pure(QueueResult(), Fail{"queue failed"})

def checkQueue(result: QueueResult(), expected: String) -> IO(Unit):
  match result:
    case Fail{error}: Test.assertion(String.eq(error, expected), "queue error propagation")
    case Done{Nil{}}: Test.assertion(String.is_empty(expected), "absent queue must be empty")
    case Done{T.CustomMessage{text} <> Nil{}}: Test.assertion(String.eq(text, expected), "queue contents changed")
    case _: Test.assertion(False{}, "queue result shape")

def checkStop(result: StopResult(), expected: Bool) -> IO(Unit):
  match result:
    case Done{value}: Test.assertion(Bool.not(Bool.xor(value, expected)), "stop decision changed")
    case Fail{_}: Test.assertion(False{}, "unexpected stop error")

def checkPrepared(result: StateResult()) -> IO(Unit):
  match result:
    case Done{Loop.PreparedTurnState{_, config, T.CustomMessage{text} <> Nil{}}}:
      Test.assertion(String.eq(text, "updated guidance"), "prepareNextTurn must return explicit next-turn messages")
    case _: Test.assertion(False{}, "prepareNextTurn update was dropped")

def main() -> IO(Unit):
  do IO<Unit>:
    +logValue : Log() <- R.new(List<&2, String>, Nil{})
    +queued : C.Callback<Unit, QueueResult()> <- C.create(~Log(), ~Unit, ~QueueResult(), ~queue, logValue)
    +stopped : C.Callback<H.Turn(), StopResult()> <- C.create(~Log(), ~H.Turn(), ~StopResult(), ~stop, logValue)
    +prepared : C.Callback<H.Turn(), PrepareResult()> <- C.create(~Log(), ~H.Turn(), ~PrepareResult(), ~prepare, logValue)
    +converter : ConfigTest.Converter() <- C.create(~Unit, ~H.Messages(), ~ConfigTest.Output(), ~ConfigTest.forbidden, Unit{})
    +config : Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, Some{stopped}, Some{prepared}, Some{queued}, Some{queued}, None{}, None{}, None{}}
    steering : QueueResult() <- Loop.pollSteeringMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config)
    checkQueue(steering, "queued")
    pending : QueueResult() <- Loop.repollSteeringMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config, T.CustomMessage{"already pending"} <> Nil{})
    checkQueue(pending, "already pending")
    followup : QueueResult() <- Loop.pollFollowUpMessages(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config)
    checkQueue(followup, "queued")
    +zero : F.F64 = F.fromU32(0)
    +context : H.Context() = T.AgentContext{Nil{}, None{}}
    +completed : H.Turn() = T.ShouldStopAfterTurnContext{Test.assistant(Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.Stop{}), Nil{}, context, Nil{}}
    decision : StopResult() <- Loop.shouldStopAfterTurn(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, config, completed)
    checkStop(decision, True{})
    updated : StateResult() <- Loop.prepareNextTurn(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, config, completed)
    checkPrepared(updated)
    missing : QueueResult() <- Loop.readQueuedMessages(Unit, String, Unit, String, String, String, None{})
    checkQueue(missing, "")
    disabled : StopResult() <- Loop.invokeShouldStopAfterTurn(Unit, String, Unit, String, String, U32, Unit, String, completed, None{})
    checkStop(disabled, False{})
    +failed : C.Callback<Unit, QueueResult()> <- C.create(~Unit, ~Unit, ~QueueResult(), ~queueFailure, Unit{})
    failure : QueueResult() <- Loop.readQueuedMessages(Unit, String, Unit, String, String, String, Some{failed})
    checkQueue(failure, "queue failed")
    trace : List<&2, String> <- R.read(List<&2, String>, logValue)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), "queue|queue|stop|prepare"), "hook order or pending-queue short-circuit changed")
    C.dispose(Unit, QueueResult(), queued)
    C.dispose(Unit, QueueResult(), failed)
    C.dispose(H.Turn(), StopResult(), stopped)
    C.dispose(H.Turn(), PrepareResult(), prepared)
    C.dispose(H.Messages(), ConfigTest.Output(), converter)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, logValue)
    IO.print("PASS native queue polling, stop hooks, explicit next-turn updates and failures")
