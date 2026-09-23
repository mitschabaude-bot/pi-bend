import Base
import ../src/deferred.bend as D
import ../src/ref.bend as R
import ../src/big-nat.bend as N

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def isValue(value: Maybe<&2, U32>, expected: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{actual}: U32.is_eq(actual, expected)

def pendingEmpty(state: D.State<U32>) -> Bool:
  match state:
    case D.Pending{_, Nil{}}: True{}
    case _: False{}

def checkRemoved(value: D.Deferred<U32>) -> IO(Unit):
  match value:
    case D.Deferred{state}:
      do IO<Unit>:
        current : D.State<U32> <- R.read(D.State<U32>, state)
        assertion(pendingEmpty(current), "cancellation must unlink its waiter from an unresolved deferred")

def cancelPending(+source: D.Deferred<U32>, observation: D.Observation<U32>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, +cancellation}:
      do IO<Unit>:
        receiver : Chan(Maybe<&2, U32>) <- IO.fork(Maybe<&2, U32>, D.wait(Maybe<&2, U32>, ticket))
        won : Bool <- D.cancel(U32, cancellation)
        assertion(won, "pending cancellation must win")
        wonAgain : Bool <- D.cancel(U32, cancellation)
        assertion(Bool.not(wonAgain), "duplicate cancellation must not deliver again")
        value : Maybe<&2, U32> <- IO.join(Maybe<&2, U32>, receiver)
        assertion(Maybe.is_none(&2, U32, value), "cancelled receiver must finish with None")
        checkRemoved(source)

def checkLate(observation: D.Observation<U32>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, cancellation}:
      do IO<Unit>:
        won : Bool <- D.cancel(U32, cancellation)
        assertion(Bool.not(won), "settlement must win over cancellation of a late observation")
        value : Maybe<&2, U32> <- D.wait(Maybe<&2, U32>, ticket)
        assertion(isValue(value, 42), "late observation must retain settled value")

def mixed(+source: D.Deferred<U32>, first: D.Observation<U32>, second: D.Observation<U32>, required: D.Ticket<U32>) -> IO(Unit):
  match first second:
    case D.Observation{firstTicket, +firstCancel} D.Observation{secondTicket, secondCancel}:
      do IO<Unit>:
        cancelled : Bool <- D.cancel(U32, firstCancel)
        assertion(cancelled, "removing an older waiter must succeed")
        firstValue : Maybe<&2, U32> <- D.wait(Maybe<&2, U32>, firstTicket)
        assertion(Maybe.is_none(&2, U32, firstValue), "first waiter must be cancelled")
        third : D.Observation<U32> <- D.observe(U32, source)
        again : Bool <- D.cancel(U32, firstCancel)
        assertion(Bool.not(again), "stale key must not cancel a new observation")
        settled : Bool <- D.resolve(U32, source, 42)
        assertion(settled, "cancellation must not settle the deferred itself")
        lost : Bool <- D.cancel(U32, secondCancel)
        assertion(Bool.not(lost), "already claimed delivery must not be cancelled")
        secondValue : Maybe<&2, U32> <- D.wait(Maybe<&2, U32>, secondTicket)
        assertion(isValue(secondValue, 42), "removing one observation must preserve its neighbors")
        requiredValue : U32 <- D.wait(U32, required)
        assertion(U32.is_eq(requiredValue, 42), "required tickets must survive removable observations")
        checkLate(third)

def raceOutcome(cancelled: Bool, value: Maybe<&2, U32>) -> Bool:
  match cancelled value:
    case True{} None{}: True{}
    case False{} Some{actual}: U32.is_eq(actual, 42)
    case _ _: False{}

def runRace(+source: D.Deferred<U32>, observation: D.Observation<U32>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, +cancellation}:
      do IO<Unit>:
        canceller : Chan(Bool) <- IO.fork(Bool, D.cancel(U32, cancellation))
        resolver : Chan(Bool) <- IO.fork(Bool, D.resolve(U32, source, 42))
        value : Maybe<&2, U32> <- D.wait(Maybe<&2, U32>, ticket)
        cancelled : Bool <- IO.join(Bool, canceller)
        settled : Bool <- IO.join(Bool, resolver)
        assertion(settled && raceOutcome(cancelled, value), "exactly the atomic winner must deliver")
        duplicate : Bool <- D.cancel(U32, cancellation)
        assertion(Bool.not(duplicate), "race completion must retire the cancellation key")
        stored : U32 <- D.result(U32, source)
        assertion(U32.is_eq(stored, 42), "observation cancellation must not alter stored settlement")

def races(count: Nat) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+ n:
      do IO<Unit>:
        +source : D.Deferred<U32> <- D.new(U32)
        observation : D.Observation<U32> <- D.observe(U32, source)
        runRace(source, observation)
        D.dispose(U32, source)
        races(n)

def competingCancellations(count: Nat, +cancellation: D.Cancellation<U32>) -> IO(List<&2, Chan(Bool)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(Bool)>, Nil{})
    case 1n+ n:
      do IO<List<&2, Chan(Bool)>>:
        task : Chan(Bool) <- IO.fork(Bool, D.cancel(U32, cancellation))
        rest : List<&2, Chan(Bool)> <- competingCancellations(n, cancellation)
        return task <> rest

def countWinners(tasks: List<&2, Chan(Bool)>) -> IO(U32):
  match tasks:
    case Nil{}: IO.pure(U32, 0)
    case task <> rest:
      do IO<U32>:
        won : Bool <- IO.join(Bool, task)
        others : U32 <- countWinners(rest)
        return (others + Bool.pick(U32, won, 1, 0) : U32)

def cancelTogether(observation: D.Observation<U32>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, cancellation}:
      do IO<Unit>:
        tasks : List<&2, Chan(Bool)> <- competingCancellations(64n, cancellation)
        value : Maybe<&2, U32> <- D.wait(Maybe<&2, U32>, ticket)
        winners : U32 <- countWinners(tasks)
        assertion(U32.is_eq(winners, 1) && Maybe.is_none(&2, U32, value), "concurrent cancellation must have exactly one delivery owner")

def settledNone(value: Maybe<&2, Maybe<&2, U32>>) -> Bool:
  match value:
    case Some{None{}}: True{}
    case _: False{}

def checkNone(observation: D.Observation<Maybe<&2, U32>>) -> IO(Unit):
  match observation:
    case D.Observation{ticket, cancellation}:
      do IO<Unit>:
        cancelled : Bool <- D.cancel(Maybe<&2, U32>, cancellation)
        assertion(Bool.not(cancelled), "resolved None is a value, not cancellation")
        value : Maybe<&2, Maybe<&2, U32>> <- D.wait(Maybe<&2, Maybe<&2, U32>>, ticket)
        assertion(settledNone(value), "resolved None must be wrapped in Some")

# Exercise a counter carry beyond both machine Nat and U64 capacity. Keys must
# never wrap and let an old cancellation handle remove a newer observation.
def seedLargeCounter(source: D.Deferred<U32>) -> IO(Unit):
  match source:
    case D.Deferred{state}:
      R.write(D.State<U32>, state, D.Pending{N.BigNat{65535 <> 65535 <> 65535 <> 65535 <> Nil{}}, Nil{}})

def main() -> IO(Unit):
  do IO<Unit>:
    +pending : D.Deferred<U32> <- D.new(U32)
    observation : D.Observation<U32> <- D.observe(U32, pending)
    cancelPending(pending, observation)
    competing : D.Observation<U32> <- D.observe(U32, pending)
    cancelTogether(competing)
    checkRemoved(pending)
    D.dispose(U32, pending)
    +source : D.Deferred<U32> <- D.new(U32)
    seedLargeCounter(source)
    first : D.Observation<U32> <- D.observe(U32, source)
    required : D.Ticket<U32> <- D.subscribe(U32, source)
    second : D.Observation<U32> <- D.observe(U32, source)
    mixed(source, first, second, required)
    late : D.Observation<U32> <- D.observe(U32, source)
    checkLate(late)
    D.dispose(U32, source)
    +optional : D.Deferred<Maybe<&2, U32>> <- D.new(Maybe<&2, U32>)
    noneObserver : D.Observation<Maybe<&2, U32>> <- D.observe(Maybe<&2, U32>, optional)
    settled : Bool <- D.resolve(Maybe<&2, U32>, optional, None{})
    assertion(settled, "optional value settlement")
    checkNone(noneObserver)
    D.dispose(Maybe<&2, U32>, optional)
    races(128n)
    IO.print("PASS removable deferred observations, cleanup, stale keys and 128 settlement races")
