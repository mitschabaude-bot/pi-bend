import Base

# A later scrutinee skipped with `_` in an earlier case and destructured in a
# later one is refused as "a match on a parameter or field". Swapping the
# scrutinee order compiles. See docs/bend-issues.md (BEND-050).
type Setup is Data:
  Setup{value: U32}

def f(setup: Setup, x: Maybe<&2, U32>) -> U32:
  match x setup:
    case None{} _: 0
    case Some{_} Setup{w}: w

def main() -> IO(Unit): IO.print(U32.show(f(Setup{1}, Some{2})))
