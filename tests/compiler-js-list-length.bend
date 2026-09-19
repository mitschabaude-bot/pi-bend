import Base

def grow(count: Nat, values: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: values
    case Succ{rest}: grow(rest, 1 <> values)

def main() -> IO(Unit): IO.print(Nat.show(List.length(&2, U32, grow(65536n, Nil{}))))
