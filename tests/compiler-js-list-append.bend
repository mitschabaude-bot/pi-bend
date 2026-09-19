import Base

# Reduced from a 65,536-byte TCP test payload. Native succeeds; investigate
# JS backend stack use when repeatedly appending large immutable lists.
def block(remaining: Nat, +byte: U32) -> List<&2, U32>:
  match remaining:
    case 0n: Nil{}
    case 1n+rest: byte <> block(rest, (byte + 1 : U32))

def repeat(rounds: Nat, +bytes: List<&2, U32>) -> List<&2, U32>:
  match rounds:
    case 0n: bytes
    case 1n+rest: repeat(rest, List.append(&2, U32, bytes, bytes))

def report(bytes: List<&2, U32>) -> IO(Unit):
  match bytes:
    case Nil{}: IO.die(Unit, 1, "missing payload")
    case _ <> _: IO.print("constructed")

def main() -> IO(Unit): report(repeat(8n, block(256n, 0)))
