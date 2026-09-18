import Base
import ../src/agent-runtime.bend as R
import ../src/agent-lifecycle.bend as L
import ../src/agent-state.bend as State
import ../../runtime/src/ref.bend as Ref
import ./agent-runtime.bend as Fixture
import ./agent-queues.bend as QueueTest
import ./message-events.bend as Test

def worker(runtime: Fixture.Runtime(), reply: Chan(Fixture.Claim())) -> IO(Unit):
  do IO<Unit>:
    result : Fixture.Claim() <- R.beginContinue(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    sent : Bool <- Chan.send(Fixture.Claim(), reply, result)
    Ref.requireSent(sent)
def accepted(value: L.Claimed<Fixture.Plan()>, expected: String) -> IO(L.ActiveRun):
  match value:
    case L.Claimed{run, plan}:
      do IO<L.ActiveRun>:
        Test.assertion(String.eq(Fixture.planKey(plan), expected), "winner consumes exactly the configured steering batch")
        return run
def winner(first: Fixture.Claim(), second: Fixture.Claim(), expected: String) -> IO(L.ActiveRun):
  match first second:
    case Done{value} Fail{L.Busy{}}: accepted(value, expected)
    case Fail{L.Busy{}} Done{value}: accepted(value, expected)
    case _ _: IO.die(L.ActiveRun, 1, "exactly one continuation must claim the run")
def scenario(+all: Bool) -> IO(Unit):
  do IO<Unit>:
    initial : State.AgentInitialState<Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit> = State.AgentInitialState{Some{"base"}, None{}, None{}, None{}, Some{QueueTest.assistant() <> Nil{}}}
    +runtime : Fixture.Runtime() <- R.new(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, initial, QueueTest.mode(Bool.pick(U32, all, 1, 0)), QueueTest.mode(0))
    R.steer(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s"))
    R.steer(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, QueueTest.user("s"))
    +firstReply : Chan(Fixture.Claim()) <- Chan.new(Fixture.Claim(), 1)
    +secondReply : Chan(Fixture.Claim()) <- Chan.new(Fixture.Claim(), 1)
    IO.spawn(Unit, worker(runtime, firstReply))
    IO.spawn(Unit, worker(runtime, secondReply))
    first : Fixture.Claim() <- IO.join(Fixture.Claim(), firstReply)
    second : Fixture.Claim() <- IO.join(Fixture.Claim(), secondReply)
    run : L.ActiveRun <- winner(first, second, Bool.pick(String, all, "prompt:s,s:1", "prompt:s:1"))
    current : Fixture.Owned() <- R.snapshot(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    Test.assertion(String.eq(Fixture.key(current), Bool.pick(String, all, "base|sa|1|-||all:|one:", "base|sa|1|-||one:s|one:")), "losing continuation preserves remaining queue and active state")
    won : Bool <- R.finishRun(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime, run)
    Test.assertion(won, "winner alone owns finishing the run")
    final : Fixture.Owned() <- R.dispose(Unit, Unit, Unit, Unit, String, Unit, Unit, String, Unit, runtime)
    Test.assertion(String.eq(Fixture.key(final), Bool.pick(String, all, "base|sa|0|-||all:|one:", "base|sa|0|-||one:s|one:")), "finishing does not discard remaining steering")
@unsafe def scenarios(count: U32) -> IO(Unit):
  match count:
    case 0: IO.pure(Unit, Unit{})
    case n:
      do IO<Unit>:
        scenario(False{})
        scenario(True{})
        scenarios(U32.sub(n, 1))
def main() -> IO(Unit):
  do IO<Unit>:
    scenarios(32)
    IO.print("PASS 64 atomic Agent continuation races")
