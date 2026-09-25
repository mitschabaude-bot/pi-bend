# BEND-039 follow-up: one wide segment (48 words, framed) in a program whose other
# segments are narrow. The register bank must still hold its BEND_BANK register
# words. Expected: no, no, no, yes for 0, 1, 2 and 3 arguments, natively and on Bun.
import Base

type W is Data:
  W{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32, x8: U32, x9: U32, x10: U32, x11: U32, x12: U32, x13: U32, x14: U32, x15: U32, x16: U32, x17: U32, x18: U32, x19: U32, x20: U32, x21: U32, x22: U32, x23: U32}

def total(a: W, b: W) -> U32:
  match a b:
    case W{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19, x20, x21, x22, x23} W{y0, y1, y2, y3, y4, y5, y6, y7, y8, y9, y10, y11, y12, y13, y14, y15, y16, y17, y18, y19, y20, y21, y22, y23}: (x0 + x1 + x2 + x3 + x4 + x5 + x6 + x7 + x8 + x9 + x10 + x11 + x12 + x13 + x14 + x15 + x16 + x17 + x18 + x19 + x20 + x21 + x22 + x23 + y0 + y1 + y2 + y3 + y4 + y5 + y6 + y7 + y8 + y9 + y10 + y11 + y12 + y13 + y14 + y15 + y16 + y17 + y18 + y19 + y20 + y21 + y22 + y23 : U32)

def count(n: Nat) -> U32:
  match n:
    case 0n: 0
    case 1n+m: (1 + count(m) : U32)

def wide(allowed: Bool, a: W, b: W, +n: U32) -> Bool:
  match allowed:
    case False{}: False{}
    case True{}: U32.is_eq(total(a, b), (n + count(U32.to_nat(n)) : U32))

def make(+k: U32) -> W: W{k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k}

def show(b: Bool) -> String:
  match b:
    case True{}: "yes"
    case False{}: "no"

def run(+k: U32) -> String: show(U32.is_eq(k, 3) || wide(U32.is_eq(k, 0), make(k), make((k + 1 : U32)), 7))

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    IO.print(run(U32.from_nat(List.length(&1, String, values))))
