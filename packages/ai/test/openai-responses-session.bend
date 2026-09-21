import Base
import ../src/types.bend as T
import ../src/api/openai-responses-session.bend as Session
import ../src/api/openai-responses-lifecycle.bend as Life
import ../src/utils/event-stream.bend as Events
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as F
import ./event-stream.bend as Test

type Failure is Data:
  AcquisitionRejected{code: U32}
  ProcessingRejected{code: U32}
  RetirementRejected{code: U32}

type Body is Type:
  Body{token: Chan(Unit)}

type Gate is Data:
  Gate{entered: Chan(Unit), release: Chan(Unit)}

def Message() -> Data: T.AssistantMessage<U32, String>
def AssistantEvent() -> Data: T.AssistantMessageEvent<U32, String>
def Stream() -> Data: Events.AssistantMessageEventStream(U32, String)
def Outcome() -> Data: Life.RunResult<U32, String, Failure>
def Owner() -> Type: Session.Run<U32, String, Failure>

def render(value: Failure) -> String:
  match value:
    case AcquisitionRejected{code}: "acquire:" ++ U32.show(code)
    case ProcessingRejected{code}: "process:" ++ U32.show(code)
    case RetirementRejected{code}: "retire:" ++ U32.show(code)

def message(+text: String, reason: T.StopReason) -> Message():
  +zero = F.fromU32(0)
  T.AssistantMessage{Bool.pick(List<&2, T.AssistantContent<U32>>, String.is_empty(text), Nil{}, T.AssistantText{T.TextContent{text, None{}}} <> Nil{}), "openai-responses", "openai", "test", None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}}, reason, None{}, None{}, None{}, None{}, F.fromU32(123)}

def received(rejected: Bool) -> IO(Result<&2, &1, Failure, Body>):
  match rejected:
    case True{}: IO.pure(Result<&2, &1, Failure, Body>, Fail{AcquisitionRejected{41}})
    case False{}:
      do IO<Result<&2, &1, Failure, Body>>:
        token : Chan(Unit) <- Chan.new(Unit, 1)
        return Done{Body{token}}

def acquire(mode: U32, gate: Gate) -> IO(Result<&2, &1, Failure, Body>):
  match gate:
    case Gate{entered, release}:
      do IO<Result<&2, &1, Failure, Body>>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        Ref.requireSent(sent)
        resumed : Unit <- IO.join(Unit, release)
        received(U32.is_eq(mode, 1))

def release(counter: Ref.Ref<U32>, body: Body) -> IO(Result<&2, &2, Failure, Unit>):
  match body:
    case Body{token}:
      do IO<Result<&2, &2, Failure, Unit>>:
        Chan.close(Unit, token)
        Ref.modify(U32, Unit, counter, n => (U32.add(n, 1), Unit{}))
        return Done{Unit{}}

def process(+mode: U32, counter: Ref.Ref<U32>, sink: C.Callback<AssistantEvent(), Result<&2, &2, Failure, Unit>>, body: Body, initial: Message()) -> IO(Life.Processed<U32, String, Failure>):
  do IO<Life.Processed<U32, String, Failure>>:
    emitted : Result<&2, &2, Failure, Unit> <- C.call(AssistantEvent(), Result<&2, &2, Failure, Unit>, sink, T.TextDelta{F.fromU32(0), "hello", message("hello", T.Pending{})})
    Test.assertion(Result.is_done(&2, &2, Failure, Unit, emitted), "canonical publication succeeds")
    retired : Result<&2, &2, Failure, Unit> <- release(counter, body)
    return Life.Processed{message("hello", T.Stop{}), Bool.pick(Maybe<&2, Failure>, U32.is_eq(mode, 2) || U32.is_eq(mode, 4), Some{ProcessingRejected{42}}, None{}), Bool.pick(Maybe<&2, Failure>, U32.is_eq(mode, 3) || U32.is_eq(mode, 4), Some{RetirementRejected{43}}, None{})}

def aborted(mode: U32, unused: Unit) -> IO(Bool): IO.pure(Bool, U32.is_eq(mode, 5))

def checkFailure(+mode: U32, value: Life.Terminal<U32, String, Failure>) -> Bool:
  match value:
    case Life.Successful{T.DoneStop{}, _}: U32.is_eq(mode, 0) || U32.is_eq(mode, 6)
    case Life.Failed{T.ErrorError{}, _, Life.RequestFailure{AcquisitionRejected{41}}}: U32.is_eq(mode, 1)
    case Life.Failed{T.ErrorError{}, _, Life.ProcessingFailure{ProcessingRejected{42}}}: U32.is_eq(mode, 2) || U32.is_eq(mode, 4)
    case Life.Failed{T.ErrorError{}, _, Life.CleanupFailure{RetirementRejected{43}}}: U32.is_eq(mode, 3)
    case Life.Failed{T.ErrorAborted{}, _, Life.RequestAborted{}}: U32.is_eq(mode, 5)
    case _: False{}

def checkCleanup(+mode: U32, value: Maybe<&2, Failure>) -> Bool:
  match value:
    case None{}: Bool.not(U32.is_eq(mode, 3) || U32.is_eq(mode, 4))
    case Some{RetirementRejected{43}}: U32.is_eq(mode, 3) || U32.is_eq(mode, 4)
    case _: False{}

def checkOutcome(+mode: U32, value: Outcome()) -> IO(Unit):
  match value:
    case Life.RunResult{terminal, cleanup, delivery}:
      Test.assertion(checkFailure(mode, terminal) && checkCleanup(mode, cleanup) && Maybe.is_none(&2, Failure, delivery), "typed primary, cleanup and delivery results retained")

def text(value: Message()) -> String:
  match value:
    case T.AssistantMessage{Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: ""
    case T.AssistantMessage{T.AssistantText{T.TextContent{value, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
    case _: "invalid"

def reason(value: Message()) -> String:
  match value:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Pending{}, _, _, _, _, _}: "pending"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Stop{}, _, _, _, _, _}: "stop"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Aborted{}, _, _, _, _, _}: "aborted"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Error{}, _, _, _, _, _}: "error"
    case _: "unexpected"

def expectedReason(+mode: U32) -> String:
  Bool.pick(String, U32.is_eq(mode, 0) || U32.is_eq(mode, 6), "stop", Bool.pick(String, U32.is_eq(mode, 5), "aborted", "error"))

def checkMessage(+mode: U32, +value: Message()) -> IO(Unit):
  Test.assertion(String.eq(text(value), Bool.pick(String, U32.is_eq(mode, 1), "", "hello")) && String.eq(reason(value), expectedReason(mode)), "final message matches typed run")

def retained(values: List<&2, AssistantEvent()>, mode: U32) -> Bool:
  match values:
    case T.StreamError{T.ErrorError{}, output} <> Nil{}: U32.is_eq(mode, 1) && String.eq(text(output), "")
    case T.Start{+initial} <> T.TextDelta{_, _, +partial} <> T.StreamDone{T.DoneStop{}, +final} <> Nil{}:
      U32.is_eq(mode, 0) && String.eq(text(initial), "") && String.eq(reason(initial), "pending") && String.eq(text(partial), "hello") && String.eq(reason(partial), "pending") && String.eq(text(final), "hello") && String.eq(reason(final), "stop")
    case T.Start{+initial} <> T.TextDelta{_, _, +partial} <> T.StreamError{_, +final} <> Nil{}:
      String.eq(text(initial), "") && String.eq(reason(initial), "pending") && String.eq(text(partial), "hello") && String.eq(reason(partial), "pending") && String.eq(text(final), "hello") && String.eq(reason(final), expectedReason(mode))
    case _: False{}

@unsafe def collect(+cursor: Events.Iterator<AssistantEvent(), Message()>, value: Events.Iteration<AssistantEvent()>) -> IO(List<&2, AssistantEvent()>):
  match value:
    case Events.End{}: IO.pure(List<&2, AssistantEvent()>, Nil{})
    case Events.Yield{head}:
      do IO<List<&2, AssistantEvent()>>:
        next : Events.Iteration<AssistantEvent()> <- Events.nextValue(AssistantEvent(), Message(), cursor)
        tail : List<&2, AssistantEvent()> <- collect(cursor, next)
        return head <> tail

def waitedAgain(+mode: U32, pair: Owner() & Outcome()) -> IO(Unit):
  match pair:
    case (owner, result):
      do IO<Unit>:
        checkOutcome(mode, result)
        disposed : Outcome() <- Session.dispose(U32, String, Failure, owner)
        checkOutcome(mode, disposed)

def waited(+mode: U32, pair: Owner() & Outcome()) -> IO(Unit):
  match pair:
    case (owner, result):
      do IO<Unit>:
        checkOutcome(mode, result)
        next : Owner() & Outcome() <- Session.wait(U32, String, Failure, owner)
        waitedAgain(mode, next)

def observe(+mode: U32, gate: Gate, borrowed: Owner() & Stream()) -> IO(Unit):
  match gate borrowed:
    case Gate{entered, release} Tuple{owner, +stream}:
      do IO<Unit>:
        waiting : Unit <- IO.join(Unit, entered)
        ready : Maybe<&2, Message()> <- D.peek(Message(), Events.result(AssistantEvent(), Message(), stream))
        Test.assertion(Maybe.is_none(&2, Message(), ready), "start returns before gated acquisition")
        first : D.Ticket<Message()> <- D.subscribe(Message(), Events.result(AssistantEvent(), Message(), stream))
        second : D.Ticket<Message()> <- D.subscribe(Message(), Events.result(AssistantEvent(), Message(), stream))
        +cursor : Events.Iterator<AssistantEvent(), Message()> <- Events.iterator(AssistantEvent(), Message(), stream)
        +next : D.Deferred<Events.Iteration<AssistantEvent()>> <- Events.next(AssistantEvent(), Message(), cursor)
        sent : Bool <- Chan.send(Unit, release, Unit{})
        Ref.requireSent(sent)
        head : Events.Iteration<AssistantEvent()> <- D.result(Events.Iteration<AssistantEvent()>, next)
        D.dispose(Events.Iteration<AssistantEvent()>, next)
        events : List<&2, AssistantEvent()> <- collect(cursor, head)
        Test.assertion(retained(events, mode), "event order and retained immutable snapshots")
        a : Message() <- D.wait(Message(), first)
        b : Message() <- D.wait(Message(), second)
        c : Message() <- Events.resultValue(AssistantEvent(), Message(), stream)
        checkMessage(mode, a)
        checkMessage(mode, b)
        checkMessage(mode, c)
        Events.disposeIterator(AssistantEvent(), Message(), cursor)
        pair : Owner() & Outcome() <- Session.wait(U32, String, Failure, owner)
        waited(mode, pair)

def disposeRunning(gate: Gate, owner: Owner()) -> IO(Unit):
  match gate:
    case Gate{entered, release}:
      do IO<Unit>:
        waiting : Unit <- IO.join(Unit, entered)
        task : Chan(Outcome()) <- IO.fork(Outcome(), Session.dispose(U32, String, Failure, owner))
        sent : Bool <- Chan.send(Unit, release, Unit{})
        Ref.requireSent(sent)
        result : Outcome() <- IO.join(Outcome(), task)
        checkOutcome(6, result)

def selected(mode: U32, gate: Gate, owner: Owner()) -> IO(Unit):
  match mode:
    case 6: disposeRunning(gate, owner)
    case other: observe(other, gate, Session.borrow(U32, String, Failure, owner))

def run(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +resume : Chan(Unit) <- Chan.new(Unit, 1)
    +signal : C.Callback<Unit, Bool> <- C.create(~U32, ~Unit, ~Bool, ~aborted, mode)
    owner : Owner() <- Session.start(~U32, ~String, ~Failure, ~render, Body, message("", T.Pending{}), signal, acquire(mode, Gate{entered, resume}), process(mode, counter), release(counter))
    selected(mode, Gate{entered, resume}, owner)
    signalValue : Bool <- C.call(Unit, Bool, signal, Unit{})
    Test.assertion(Bool.not(Bool.xor(signalValue, U32.is_eq(mode, 5))), "borrowed signal remains live after owner disposal")
    count : U32 <- Ref.dispose(U32, counter)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, U32.is_eq(mode, 1), 0, 1)), "exactly one retirement per acquired owner")
    C.dispose(Unit, Bool, signal)
    IO.print("PASS session " ++ U32.show(mode))

def main() -> IO(Unit):
  do IO<Unit>:
    run(0)
    run(1)
    run(2)
    run(3)
    run(4)
    run(5)
    run(6)
