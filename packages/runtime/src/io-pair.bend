import Base

# Start both operations before waiting for either, then join both children.
# Return values in argument order, independent of completion order. Typed
# errors are ordinary values: one error never abandons the other operation.
# Each operation must handle its own cancellation and close its own resources.
# Like IO.join, this does not recover from IO.die or a runtime trap.
def both(-Left: Type, -Right: Type, left: IO(Left), right: IO(Right)) -> IO(Left & Right):
  do IO<Left & Right>:
    leftTask : Chan(Left) <- IO.fork(Left, left)
    rightTask : Chan(Right) <- IO.fork(Right, right)
    leftValue : Left <- IO.join(Left, leftTask)
    rightValue : Right <- IO.join(Right, rightTask)
    return (leftValue, rightValue)
