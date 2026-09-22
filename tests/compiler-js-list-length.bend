import Base

# Base List.length and String.split are structural, non-tail recursions.
# 200,000 elements overflowed the JS backend's stack before the explicit
# continuation stack; native runs were always fine.
def block(remaining: Nat, +byte: U32) -> List<&2, U32>:
  match remaining:
    case 0n: Nil{}
    case 1n+rest: byte <> block(rest, (byte + 1 : U32))

def commas(remaining: Nat) -> String:
  match remaining:
    case 0n: "x"
    case 1n+rest: "x," ++ commas(rest)

def main() -> IO(Unit):
  IO.print(Nat.show(List.length(&2, U32, block(200000n, 0))) ++ " " ++ Nat.show(List.length(&2, String, String.split(commas(50000n), ','))) ++ " " ++ Nat.show(String.length(String.join(String.split(commas(20000n), ','), "-"))))
