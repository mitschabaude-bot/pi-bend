import Base
import ../packages/runtime/src/unicode-17-category.bend as Category

# Runs of Category.category over every Unicode scalar, as `start:class`
# lines (tests/unicode_category_check.py compares them with JavaScript's
# `\p{L}` and `\p{N}`).
def runs(count: Nat,+code: U32,+previous: U32,+reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{more}:
      +value = Category.category(code)
      runs(more,(code + 1 : U32),value,Bool.pick(List<&2,String>,U32.is_eq(value,previous),reversed,(Nat.show(U32.to_nat(code)) ++ ":" ++ Nat.show(U32.to_nat(value))) <> reversed))
def main() -> IO(Unit):
  IO.print(String.join(runs(1114112n,0,99,Nil{}),"\n"))
