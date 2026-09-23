import Base

# A multi-scrutinee match flattens only when its scrutinees appear in the
# same order as the def's parameters. `first` is the last parameter here and
# `second` an earlier one; swapping the two scrutinees fixes the error.
type Choice is Data:
  Left{}
  Right{}

def pick(second: Choice, unused: Unit, first: Maybe<&2, U32>) -> U32:
  match first second:
    case Some{value} Left{}: value
    case Some{value} Right{}: value + 1
    case None{} _: 0

def main() -> IO(Unit):
  IO.print(U32.show(pick(Right{}, Unit{}, Some{41})))
