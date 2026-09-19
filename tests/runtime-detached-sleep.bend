import Base

# BEND-020: spawn returns no task handle and sleep has no cancellation handle.
# Finishing the caller does not cancel or retire the outstanding timer.
def sleeper() -> IO(Unit):
  do IO<Unit>:
    IO.sleep(250)
    IO.print("timer finished")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, sleeper())
    IO.print("caller finished")
