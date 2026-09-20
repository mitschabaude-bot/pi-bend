import Base

# Reduced BEND-019: the recursive call in Base String.join.go is not tail.
def pieces(count: Nat, reversed: List<&2, String>) -> List<&2, String>:
  match count:
    case Zero{}: reversed
    case Succ{rest}: pieces(rest, "a" <> reversed)

def main() -> IO(Unit):
  IO.print(String.join(pieces(65536n, Nil{}), ""))
