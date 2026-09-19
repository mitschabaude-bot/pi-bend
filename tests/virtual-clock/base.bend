
# Test-only clock controls. Never appended to an installed compiler.
def TestClock.advance(ms: U32) -> IO(Unit):
  import "./effs/test_clock.c"

def TestClock.barrier() -> IO(Unit):
  import "./effs/test_clock.c"

def TestClock.pending() -> IO(U32):
  import "./effs/test_clock.c"
