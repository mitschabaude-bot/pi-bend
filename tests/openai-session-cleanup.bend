import Base
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/f64.bend as F

def identity(value: String) -> String: value
def live(environment: Unit, input: Unit) -> IO(Bool): IO.pure(Bool, False{})
def assert(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "session cleanup invariant")

def message() -> T.AssistantMessage<Unit, Unit>:
  T.AssistantMessage{Nil{}, "openai-responses", "openai", "test", None{}, None{}, None{}, None{}, T.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), T.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}

def acquire(mode: U32) -> IO(Result<&2, &1, String, Unit>):
  IO.pure(Result<&2, &1, String, Unit>, Bool.pick(Result<&2, &1, String, Unit>, U32.is_eq(mode, 1), Fail{"request"}, Done{Unit{}}))
def process(+mode: U32, sink: C.Callback<T.AssistantMessageEvent<Unit, Unit>, Result<&2, &2, String, Unit>>, owner: Unit, output: T.AssistantMessage<Unit, Unit>) -> IO(Life.Processed<Unit, Unit, String>):
  IO.pure(Life.Processed<Unit, Unit, String>, Life.Processed{output, Bool.pick(Maybe<&2, String>, U32.is_eq(mode, 2), Some{"processing"}, None{}), Bool.pick(Maybe<&2, String>, U32.is_eq(mode, 3), Some{"body cleanup"}, None{})})
def release(owner: Unit) -> IO(Result<&2, &2, String, Unit>): IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

def cleanup(+gate: Chan(Unit), +count: R.Ref<U32>, signal: C.Callback<Unit, Bool>) -> IO(Unit):
  do IO<Unit>:
    permit : Maybe<&1, Unit> <- Chan.recv(Unit, gate)
    assert(Bool.not(Maybe.is_none(&1, Unit, permit)))
    previous : U32 <- R.modify(U32, U32, count, +n => (U32.add(n, 1), n))
    assert(U32.is_eq(previous, 0))
    C.dispose(Unit, Bool, signal)

def completed(+count: R.Ref<U32>, pair: Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String>) -> IO(Unit):
  match pair:
    case (owner, _):
      do IO<Unit>:
        n : U32 <- R.read(U32, count)
        assert(U32.is_eq(n, 1))
        ignored : Life.RunResult<Unit, Unit, String> <- Session.dispose(Unit, Unit, String, owner)
        final : U32 <- R.read(U32, count)
        assert(U32.is_eq(final, 1))

def waited(count: R.Ref<U32>, pair: Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String>) -> IO(Unit):
  match pair:
    case (owner, _):
      do IO<Unit>:
        again : Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String> <- Session.wait(Unit, Unit, String, owner)
        completed(count, again)

def observe(+gate: Chan(Unit), +count: R.Ref<U32>, pair: Session.Run<Unit, Unit, String> & Events.AssistantMessageEventStream(Unit, Unit)) -> IO(Unit):
  match pair:
    case (owner, stream):
      do IO<Unit>:
        result : T.AssistantMessage<Unit, Unit> <- Events.resultValue(T.AssistantMessageEvent<Unit, Unit>, T.AssistantMessage<Unit, Unit>, stream)
        before : U32 <- R.read(U32, count)
        assert(U32.is_eq(before, 0))
        task : Chan(Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String>) <- IO.fork(Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String>, Session.wait(Unit, Unit, String, owner))
        sent : Bool <- Chan.send(Unit, gate, Unit{})
        assert(sent)
        joined : Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String> <- IO.join(Session.Run<Unit, Unit, String> & Life.RunResult<Unit, Unit, String>, task)
        waited(count, joined)

def run(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    +gate : Chan(Unit) <- Chan.new(Unit, 0)
    +count : R.Ref<U32> <- R.new(U32, 0)
    +signal : C.Callback<Unit, Bool> <- C.create(~Unit, ~Unit, ~Bool, ~live, Unit{})
    owner : Session.Run<Unit, Unit, String> <- Session.startWithCleanup(~Unit, ~Unit, ~String, ~identity, Unit, message(), signal, acquire(mode), process(mode), release, cleanup(gate, count, signal))
    observe(gate, count, Session.borrow(Unit, Unit, String, owner))
    Chan.close(Unit, gate)
    discarded : U32 <- R.dispose(U32, count)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run(0)
    run(1)
    run(2)
    run(3)
    IO.print("PASS session cleanup ordering and single retirement")
