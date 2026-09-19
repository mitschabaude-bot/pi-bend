import Base

def assertTrue(value: Bool, message: String) -> IO(Unit):
  Bool.pick(IO(Unit), value, IO.pure(Unit, Unit{}), IO.die(Unit, 1, message))

def closeResult(result: Timer & Bool, +expected: Bool) -> IO(Unit):
  match result:
    case Tuple{owner, elapsed}:
      do IO<Unit>:
        assertTrue(Bool.pick(Bool, elapsed, expected, Bool.not(expected)), "timer result")
        Timer.close(owner)

def immediate(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, +cancel}:
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(owner)
        won : Bool <- Timer.cancel(cancel)
        assertTrue(Bool.not(won), "cancel after expiry")
        closeResult(result, True{})
        stale : Bool <- Timer.cancel(cancel)
        assertTrue(Bool.not(stale), "cancel after close")

def beforeWait(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, +cancel}:
      do IO<Unit>:
        first : Bool <- Timer.cancel(cancel)
        second : Bool <- Timer.cancel(cancel)
        assertTrue(first && Bool.not(second), "cancel is one-shot")
        result : Timer & Bool <- Timer.wait(owner)
        closeResult(result, False{})

def waiting(owner: Timer, ready: Chan(Unit)) -> IO(Timer & Bool):
  do IO<Timer & Bool>:
    sent : Bool <- Chan.send(Unit, ready, Unit{})
    assertTrue(sent, "ready channel")
    Timer.wait(owner)

def duringWait(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, +cancel}:
      do IO<Unit>:
        +ready : Chan(Unit) <- Chan.new(Unit, 0)
        task : Chan(Timer & Bool) <- IO.fork(Timer & Bool, waiting(owner, ready))
        signal : Maybe<&1, Unit> <- Chan.recv(Unit, ready)
        won : Bool <- Timer.cancel(cancel)
        assertTrue(won, "cancel parked timer")
        result : Timer & Bool <- IO.join(Timer & Bool, task)
        Chan.close(Unit, ready)
        closeResult(result, False{})
        stale : Bool <- Timer.cancel(cancel)
        assertTrue(Bool.not(stale), "stale parked cancellation")

def reused(old: TimerCancel, pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, cancel}:
      do IO<Unit>:
        stale : Bool <- Timer.cancel(old)
        won : Bool <- Timer.cancel(cancel)
        assertTrue(Bool.not(stale) && won, "stale handle touched new timer")
        result : Timer & Bool <- Timer.wait(owner)
        closeResult(result, False{})

def retireForReuse(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, cancel}:
      do IO<Unit>:
        Timer.close(owner)
        next : Timer & TimerCancel <- Timer.new(60000)
        reused(cancel, next)

type Running is Type:
  Running{task: Chan(Timer & Bool), cancel: TimerCancel}

def started(pair: Timer & TimerCancel) -> IO(Running):
  match pair:
    case Tuple{owner, cancel}:
      do IO<Running>:
        +ready : Chan(Unit) <- Chan.new(Unit, 0)
        task : Chan(Timer & Bool) <- IO.fork(Timer & Bool, waiting(owner, ready))
        signal : Maybe<&1, Unit> <- Chan.recv(Unit, ready)
        Chan.close(Unit, ready)
        return Running{task, cancel}

def start() -> IO(Running):
  do IO<Running>:
    pair : Timer & TimerCancel <- Timer.new(60000)
    started(pair)

def cancelled(run: Running) -> IO(Chan(Timer & Bool)):
  match run:
    case Running{task, cancel}:
      do IO<Chan(Timer & Bool)>:
        won : Bool <- Timer.cancel(cancel)
        assertTrue(won, "cancel queued timer")
        return task

def joinCancelled(task: Chan(Timer & Bool)) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- IO.join(Timer & Bool, task)
    closeResult(result, False{})

def queueRemoval() -> IO(Unit):
  do IO<Unit>:
    first : Running <- start()
    middle : Running <- start()
    last : Running <- start()
    b : Chan(Timer & Bool) <- cancelled(middle)
    a : Chan(Timer & Bool) <- cancelled(first)
    c : Chan(Timer & Bool) <- cancelled(last)
    joinCancelled(b)
    joinCancelled(a)
    joinCancelled(c)
    # Queue reuse after removing its last node must work for ordinary IO too.
    IO.sleep(1)

def repeated(count: Nat) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        pair : Timer & TimerCancel <- Timer.new(60000)
        beforeWait(pair)
        repeated(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    zero : Timer & TimerCancel <- Timer.new(0)
    immediate(zero)
    normal : Timer & TimerCancel <- Timer.new(250)
    immediate(normal)
    before : Timer & TimerCancel <- Timer.new(60000)
    beforeWait(before)
    active : Timer & TimerCancel <- Timer.new(60000)
    duringWait(active)
    old : Timer & TimerCancel <- Timer.new(60000)
    retireForReuse(old)
    queueRemoval()
    repeated(10000n)
    IO.sleep(1)
    IO.print("PASS timer primitive")
