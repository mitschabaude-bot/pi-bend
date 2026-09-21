import Base
import ./timer-primitive.bend as Check

def pause(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{timer, _}:
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(timer)
        Check.closeResult(result, True{})

def delayedCancel(handle: TimerCancel) -> IO(Bool):
  do IO<Bool>:
    timer : Timer & TimerCancel <- Timer.new(20)
    pause(timer)
    Timer.cancel(handle)

def verify(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, handle}:
      do IO<Unit>:
        task : Chan(Bool) <- IO.fork(Bool, delayedCancel(handle))
        result : Timer & Bool <- Timer.wait(owner)
        won : Bool <- IO.join(Bool, task)
        Check.closeResult(result, False{})
        Check.assertTrue(won, "large timer expired before cancellation")

def main() -> IO(Unit):
  do IO<Unit>:
    aboveSigned : Timer & TimerCancel <- Timer.new(2147483648)
    verify(aboveSigned)
    maximum : Timer & TimerCancel <- Timer.new(4294967295)
    verify(maximum)
    IO.print("PASS full U32 timer range")
