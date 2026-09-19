import Base
import ./timer-primitive.bend as T
import ../packages/runtime/test/utf8-runner.bend as H

def cancelAfter(delay: U32, handle: TimerCancel) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(delay)
    Timer.cancel(handle)

def outcome(result: Timer & Bool, +first: Bool, +second: Bool) -> IO(Unit):
  match result:
    case Tuple{owner, +elapsed}:
      do IO<Unit>:
        # Exactly one canceller wins iff the timer did not expire.
        T.assertTrue(Bool.not(first && second), "two cancellation winners")
        T.assertTrue(Bool.pick(Bool, elapsed, Bool.not(first || second), first || second), "inconsistent race settlement")
        repeated : Timer & Bool <- Timer.wait(owner)
        T.closeResult(repeated, elapsed)

def racePair(pair: Timer & TimerCancel, firstDelay: U32, secondDelay: U32) -> IO(Unit):
  match pair:
    case Tuple{owner, +handle}:
      do IO<Unit>:
        timer : Chan(Timer & Bool) <- IO.fork(Timer & Bool, Timer.wait(owner))
        first : Chan(Bool) <- IO.fork(Bool, cancelAfter(firstDelay, handle))
        second : Chan(Bool) <- IO.fork(Bool, cancelAfter(secondDelay, handle))
        result : Timer & Bool <- IO.join(Timer & Bool, timer)
        a : Bool <- IO.join(Bool, first)
        b : Bool <- IO.join(Bool, second)
        outcome(result, a, b)
        stale : Bool <- Timer.cancel(handle)
        T.assertTrue(Bool.not(stale), "post-race stale cancellation")

def races(count: Nat, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        pair : Timer & TimerCancel <- Timer.new((index % 3 : U32))
        racePair(pair, ((index / 3) % 3 : U32), ((index / 9) % 3 : U32))
        races(rest, (index + 1 : U32))

def createMany(count: Nat, built: List<&1, T.Running>) -> IO(List<&1, T.Running>):
  match count:
    case Zero{}: IO.pure(List<&1, T.Running>, built)
    case Succ{rest}:
      do IO<List<&1, T.Running>>:
        timer : T.Running <- T.start()
        createMany(rest, timer <> built)

def retireMany(timers: List<&1, T.Running>) -> IO(Unit):
  match timers:
    case Nil{}: IO.pure(Unit, Unit{})
    case timer <> rest:
      do IO<Unit>:
        task : Chan(Timer & Bool) <- T.cancelled(timer)
        T.joinCancelled(task)
        retireMany(rest)

def batches(count: Nat, +size: Nat) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        timers : List<&1, T.Running> <- createMany(size, Nil{})
        retireMany(timers)
        batches(rest, size)

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case rounds <> size <> Nil{}:
      do IO<Unit>:
        races(270n, 0)
        forcedCancel : Timer & TimerCancel <- Timer.new(60000)
        racePair(forcedCancel, 0, 0)
        forcedExpiry : Timer & TimerCancel <- Timer.new(0)
        racePair(forcedExpiry, 3, 3)
        batches(U32.to_nat(H.decimal(rounds, 0)), U32.to_nat(H.decimal(size, 0)))
        IO.print("PASS timer races and batches")
    case _: IO.die(Unit, 1, "expected rounds and cohort size")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
