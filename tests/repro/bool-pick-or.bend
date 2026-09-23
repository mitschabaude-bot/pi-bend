import Base

# Expected output: true. Before patches/bend-intrinsic-word-arguments.patch, native C combined a boxed Bool.pick result
# with a raw Boolean OR, yielding false.
def choose(+previous: U32, +high: U32, included: Bool) -> Bool:
  Bool.not(included) || Bool.pick(Bool,U32.is_eq(high,0),U32.is_eq(previous,255),U32.is_eq(previous,high))
def answer(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"
def main() -> IO(Unit): IO.print(answer(choose(255,0,True{})))
