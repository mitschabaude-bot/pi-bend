import Base
import ../src/agent-lifecycle.bend as L
import ../../runtime/src/abort.bend as A
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/ref.bend as R
import ./message-events.bend as Test

def Claim() -> Data: Result<&2, &2, L.ClaimError<String>, L.Claimed<U32>>
def prepare(+value: U32) -> Result<&2, &2, String, L.Prepared<U32, U32>>: Done{L.Prepared{U32.add(value, 1), value}}
def rejected(value: U32) -> Result<&2, &2, String, L.Prepared<U32, U32>>: Fail{"invalid transcript"}
def claimWorker(owner: L.Lifecycle<U32>, reply: Chan(Claim())) -> IO(Unit):
  do IO<Unit>:
    result : Claim() <- L.claim(U32, String, U32, owner, value => prepare(value))
    sent : Bool <- Chan.send(Claim(), reply, result)
    R.requireSent(sent)
def winner(first: Claim(), second: Claim()) -> IO(L.ActiveRun):
  match first second:
    case Done{L.Claimed{run, 0}} Fail{L.Busy{}}: IO.pure(L.ActiveRun, run)
    case Fail{L.Busy{}} Done{L.Claimed{run, 0}}: IO.pure(L.ActiveRun, run)
    case _ _: IO.die(L.ActiveRun, 1, "competing starts must prepare and claim exactly one run")
def requireRun(result: Claim(), expected: U32) -> IO(L.ActiveRun):
  match result:
    case Done{L.Claimed{run, value}}:
      do IO<L.ActiveRun>:
        Test.assertion(U32.is_eq(value, expected), "claim must return the atomically prepared value")
        return run
    case _: IO.die(L.ActiveRun, 1, "expected a successful claim")
def isRejected(result: Claim()) -> Bool:
  match result:
    case Fail{L.Rejected{message}}: String.eq(message, "invalid transcript")
    case _: False{}
def isBusy(result: Claim()) -> Bool:
  match result:
    case Fail{L.Busy{}}: True{}
    case _: False{}
def ticket(run: L.ActiveRun) -> IO(D.Ticket<Unit>):
  match run:
    case L.ActiveRun{completion, _}: D.subscribe(Unit, completion)
def pending(run: L.ActiveRun) -> IO(Bool):
  match run:
    case L.ActiveRun{completion, _}:
      do IO<Bool>:
        value : Maybe<&2, Unit> <- D.peek(Unit, completion)
        return Maybe.is_none(&2, Unit, value)
def activeIs(owner: L.Lifecycle<U32>, run: L.ActiveRun) -> IO(Bool):
  do IO<Bool>:
    active : Maybe<&2, L.ActiveRun> <- L.activeRun(U32, owner)
    return Maybe.default(&2, Bool, Maybe.map(&2, L.ActiveRun, Bool, other => L.same(other, run), active), False{})
def scenario() -> IO(Unit):
  do IO<Unit>:
    +owner : L.Lifecycle<U32> <- L.new(U32, 0)
    L.abort(U32, owner)
    L.waitForIdle(U32, owner)
    +firstReply : Chan(Claim()) <- Chan.new(Claim(), 1)
    +secondReply : Chan(Claim()) <- Chan.new(Claim(), 1)
    IO.spawn(Unit, claimWorker(owner, firstReply))
    IO.spawn(Unit, claimWorker(owner, secondReply))
    first : Claim() <- IO.join(Claim(), firstReply)
    second : Claim() <- IO.join(Claim(), secondReply)
    +run : L.ActiveRun <- winner(first, second)
    state : U32 <- L.read(U32, owner)
    Test.assertion(U32.is_eq(state, 1), "losing claim must not prepare or change state")
    busy : Claim() <- L.claim(U32, String, U32, owner, rejected)
    Test.assertion(isBusy(busy), "busy rejection must precede invalid-transcript preparation")
    before : Bool <- A.aborted(Unit, L.signal(run))
    Test.assertion(Bool.not(before), "new run signal starts uncancelled")
    waiterA : D.Ticket<Unit> <- ticket(run)
    waiterB : D.Ticket<Unit> <- ticket(run)
    unsettled : Bool <- pending(run)
    Test.assertion(unsettled, "active run remains pending before finish")
    L.abort(U32, owner)
    L.abort(U32, owner)
    after : Bool <- A.aborted(Unit, L.signal(run))
    Test.assertion(after, "abort reaches the active borrowed signal")
    stillPending : Bool <- pending(run)
    Test.assertion(stillPending, "abort requests cancellation without declaring idle")
    finished : Bool <- L.finish(U32, owner, run, value => U32.add(value, 10))
    Test.assertion(finished, "active run must finish once")
    D.wait(Unit, waiterA)
    D.wait(Unit, waiterB)
    L.waitForIdle(U32, owner)
    L.waitRun(Some{run})
    failed : Claim() <- L.claim(U32, String, U32, owner, rejected)
    Test.assertion(isRejected(failed), "preparation error is returned without claiming a run")
    unchanged : U32 <- L.read(U32, owner)
    Test.assertion(U32.is_eq(unchanged, 11), "rejected preparation preserves state")
    nextResult : Claim() <- L.claim(U32, String, U32, owner, value => prepare(value))
    +next : L.ActiveRun <- requireRun(nextResult, 11)
    fresh : Bool <- A.aborted(Unit, L.signal(next))
    Test.assertion(Bool.not(fresh), "restart has an independent uncancelled signal")
    stale : Bool <- L.finish(U32, owner, run, value => 999)
    Test.assertion(Bool.not(stale), "old completion cannot finish a new run")
    sameActive : Bool <- activeIs(owner, next)
    Test.assertion(sameActive, "new active run survives stale completion")
    current : U32 <- L.read(U32, owner)
    Test.assertion(U32.is_eq(current, 12), "stale finish cannot reduce state")
    last : Bool <- L.finish(U32, owner, next, value => U32.add(value, 10))
    Test.assertion(last, "second run finishes independently")
    repeated : Bool <- L.finish(U32, owner, next, value => 999)
    Test.assertion(Bool.not(repeated), "repeated finish is inert")
    retained : Bool <- A.aborted(Unit, L.signal(run))
    Test.assertion(retained, "completed signal remains inspectable")
    L.waitForIdle(U32, owner)
    final : U32 <- L.dispose(U32, owner)
    Test.assertion(U32.is_eq(final, 22), "final state includes exactly two start/finish transitions")
def abortIf(owner: L.Lifecycle<U32>, kind: U32) -> IO(Unit):
  match kind:
    case 2: L.abort(U32, owner)
    case _: IO.pure(Unit, Unit{})
def executeFixture(+owner: L.Lifecycle<U32>, log: R.Ref<String>, +kind: U32, claimed: L.Claimed<U32>) -> IO(Result<&2, &2, String, Unit>):
  match claimed:
    case L.Claimed{run, value}:
      do IO<Result<&2, &2, String, Unit>>:
        active : Bool <- activeIs(owner, run)
        Test.assertion(active && U32.is_eq(value, 0), "executor runs after atomic claim")
        R.write(String, log, "execute")
        abortIf(owner, kind)
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(kind, 0), Done{Unit{}}, Fail{"executor failed"})
def recoverFixture(+owner: L.Lifecycle<U32>, log: R.Ref<String>, kind: U32, failRecovery: Bool, +run: L.ActiveRun, error: String) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    active : Bool <- activeIs(owner, run)
    Test.assertion(active && String.eq(error, "executor failed"), "recovery keeps the active run and original error")
    state : U32 <- L.read(U32, owner)
    Test.assertion(U32.is_eq(state, 1), "finish reduction must follow recovery")
    aborted : Bool <- A.aborted(Unit, L.signal(run))
    Test.assertion(Bool.not(Bool.xor(aborted, U32.is_eq(kind, 2))), "recovery sees active cancellation state")
    R.write(String, log, "recover")
    return Bool.pick(Result<&2, &2, String, Unit>, failRecovery, Fail{"recovery failed"}, Done{Unit{}})
def expectedResult(result: Result<&2, &2, L.RunError<String>, Unit>, failed: Bool) -> Bool:
  match result:
    case Done{_}: Bool.not(failed)
    case Fail{L.CallbackFailed{message}}: failed && String.eq(message, "recovery failed")
    case _: False{}
def recoveryScenario(+kind: U32, +failRecovery: Bool) -> IO(Unit):
  do IO<Unit>:
    +owner : L.Lifecycle<U32> <- L.new(U32, 0)
    +log : R.Ref<String> <- R.new(String, "")
    result : Result<&2, &2, L.RunError<String>, Unit> <- L.runWithLifecycle(U32, String, U32, owner, value => prepare(value), claimed => executeFixture(owner, log, kind, claimed), run => error => recoverFixture(owner, log, kind, failRecovery, run, error), value => U32.add(value, 10))
    Test.assertion(expectedResult(result, Bool.not(U32.is_eq(kind, 0)) && failRecovery), "run result preserves recovery success/failure")
    L.waitForIdle(U32, owner)
    active : Maybe<&2, L.ActiveRun> <- L.activeRun(U32, owner)
    Test.assertion(Maybe.is_none(&2, L.ActiveRun, active), "finally releases active run even on recovery failure")
    trace : String <- R.dispose(String, log)
    Test.assertion(String.eq(trace, Bool.pick(String, U32.is_eq(kind, 0), "execute", "recover")), "recovery runs only after executor failure")
    final : U32 <- L.dispose(U32, owner)
    Test.assertion(U32.is_eq(final, 11), "finally commits the finish reduction on every path")
@unsafe def scenarios(count: U32) -> IO(Unit):
  match count:
    case 0: IO.pure(Unit, Unit{})
    case n:
      do IO<Unit>:
        scenario()
        scenarios(U32.sub(n, 1))
def main() -> IO(Unit):
  do IO<Unit>:
    recoveryScenario(0, False{})
    recoveryScenario(0, True{})
    recoveryScenario(1, False{})
    recoveryScenario(1, True{})
    recoveryScenario(2, False{})
    recoveryScenario(2, True{})
    scenarios(64)
    IO.print("PASS 64 Agent lifecycle claim/cancellation/settlement races")
