
# Owned timer and independently copyable cancellation capability.
# Wait returns the owner with True for expiry or False for cancellation.
# Cancellation wins until completion is committed by the IO loop. Close
# consumes the idle/completed owner; stale cancellation handles return False.
law Timer:
  Type

law TimerCancel:
  Data

def Timer.new(ms: U32) -> IO(Timer & TimerCancel):
  import "./effs/timer.c"
  import "./effs/timer.js"

def Timer.wait(timer: Timer) -> IO(Timer & Bool):
  import "./effs/timer.c"
  import "./effs/timer.js"

def Timer.cancel(handle: TimerCancel) -> IO(Bool):
  import "./effs/timer.c"
  import "./effs/timer.js"

def Timer.close(timer: Timer) -> IO(Unit):
  import "./effs/timer.c"
  import "./effs/timer.js"
