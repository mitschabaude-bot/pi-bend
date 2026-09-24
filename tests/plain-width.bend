import Base
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/unicode-17-display.bend as Display

# Every character plainWidth accepts measures the same through grapheme
# segmentation measure (clusterWidth), over all Unicode scalar values.
def agrees(+point: U32) -> Bool:
  +cells = U.plainCells(point,Display.properties(point))
  Nat.is_eq(cells,0n) || Nat.is_eq(cells,U.clusterWidth(SCon{Chr{point},SNil{}}))
def scalar(+point: U32) -> Bool: U32.is_lt(point,55296) || U32.is_gt(point,57343)
def agreesIf(valid: Bool,+point: U32) -> Bool:
  match valid:
    case True{}: agrees(point)
    case False{}: True{}
def check(remaining: Nat,+point: U32,accepted: Nat,+failures: List<&2,U32>) -> Nat & List<&2,U32>:
  match remaining:
    case Zero{}: (accepted,failures)
    case Succ{rest}:
      +ok = agreesIf(scalar(point),point)
      +plain = scalar(point) && U32.is_ne(point,127) && U32.is_ge(point,32) && Nat.is_gt(U.plainCells(point,Display.properties(point)),0n)
      check(rest,U32.add(point,1),accepted + Bool.pick(Nat,plain,1n,0n),Bool.pick(List<&2,U32>,ok,failures,point <> failures))
def report(result: Nat & List<&2,U32>) -> IO(Unit):
  match result:
    case (accepted,failures): IO.print("plain characters " ++ Nat.show(accepted) ++ ", disagreements " ++ Nat.show(List.length(&2,U32,failures)))
def main() -> IO(Unit): report(check(1114112n,0,0n,Nil{}))
