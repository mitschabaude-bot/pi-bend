import Base

def slow(value: Nat) -> Nat:
  match value:
    case 0n: 0n
    case 1n+n: slow(n)

def constant(unused: Nat) -> Nat: 0n
law unused_argument:
  {constant(slow(100000000n)) == constant(0n) : Nat}
def unused_argument(): {==}
