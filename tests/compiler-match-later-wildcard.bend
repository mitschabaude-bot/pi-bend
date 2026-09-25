import Base

# A later scrutinee skipped with `_` in an earlier case and destructured in a
# later one was refused as "a match on a parameter or field" (BEND-050, fixed
# by patches/bend-match-binder-order.patch). Expected: 21 0.
type Setup is Data:
  Setup{value: U32}

def f(setup: Setup, x: Maybe<&2, U32>) -> U32:
  match x setup:
    case None{} _: 0
    case Some{y} Setup{w}: (y * 10 + w : U32)

def main() -> IO(Unit): IO.print(U32.show(f(Setup{1}, Some{2})) ++ " " ++ U32.show(f(Setup{3}, None{})))
