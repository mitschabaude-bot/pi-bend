import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/json.bend as S
import ../packages/runtime/src/record.bend as R

def values(count: Nat, built: List<&2, T.JsonValue>) -> List<&2, T.JsonValue>:
  match count:
    case Zero{}: built
    case Succ{rest}: values(rest, T.JsonNull{} <> built)

def fields(count: Nat, built: List<&2, R.Property<T.JsonValue>>) -> List<&2, R.Property<T.JsonValue>>:
  match count:
    case Zero{}: built
    case Succ{+rest}: fields(rest, R.Property{Nat.show(rest), T.JsonNull{}} <> built)

def check(valid: Bool, label: String) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "FAIL " ++ label)
    case True{}: IO.print("PASS " ++ label)

def main() -> IO(Unit):
  do IO<Unit>:
    check(S.finite(T.JsonArray{values(65536n, Nil{})}), "finite array")
    check(S.finite(T.JsonObject{R.Record{fields(65536n, Nil{})}}), "finite object")
