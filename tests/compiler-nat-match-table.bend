import Base

# Runtime input keeps the Nat lookup-table path observable.
def table(n: Nat) -> U32:
  match n:
    case 0n: 91
    case 1n: 7
    case 2n: 44
    case rest: 5

def display(+n: Nat) -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(table(n)))
    IO.print(U32.show(table(n + 1n)))
    IO.print(U32.show(table(n + 2n)))
    IO.print(U32.show(table(n + 7n)))

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    display(List.length(&1, String, values))
