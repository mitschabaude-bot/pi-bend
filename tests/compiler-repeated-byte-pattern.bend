import Base

# BEND-018 reduced type-checking cliff. Run with an external time limit.
# Replacing the second 10 with 11 or replacing recursion with None{} checks.
def search(bytes: List<&2, U32>, offset: Nat) -> Maybe<&2, Nat>:
  match bytes:
    case 10 <> 10 <> _: Some{offset + 2n}
    case _ <> tail: search(tail, offset + 1n)
    case Nil{}: None{}
