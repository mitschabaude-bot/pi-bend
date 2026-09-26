import Base

# Conversion of two calls whose arguments share structure (BEND-061). The
# former congruence step (patches/bend-compare-congruence.patch) compared the
# arguments of equal heads recursively without a budget, so dag(40n, z)'s
# shared cells were walked as a 2^40-leaf tree and the check never finished.
# The identity walk of patches/bend-conversion-identity.patch (bendlang/bend
# PR #1075, whose checker bench this case comes from) stops after 4,096
# visits and falls back to normalization. Expected: All terms check.
type Box is Data:
  Box{v: Nat}

def pair(a: Nat, b: Nat, c: Nat, d: Nat) -> Nat:
  0n

def dag(n: Nat, +y: Nat) -> Box:
  match n:
    case 0n: Box{y}
    case 1n+p: dag(p, pair(y, y, 0n, 0n))

def wrap(n: Nat, +y: Nat) -> Box:
  dag(n, y)

def shared(+z: Nat) -> {dag(40n, z) == wrap(40n, z) : Box}:
  {==}
