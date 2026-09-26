import Base

# A Nat constant of 65,536 or more used to overflow the checker's stack when
# two stuck terms mentioning it were compared: both sides unfolded to a Succ
# chain before comparison (BEND-052, fixed by
# patches/bend-compare-congruence.patch). Expected: All terms check.
def big() -> Nat: 65536n

law instance:
  for +n: Nat
  {Nat.is_eq(n, big()) == Nat.is_eq(n, big()) : Bool}

def instance(n): {==}
