import Base

# Indexed field layouts below, at, and above the native 32-bit boundary.
def digit(bit: Bool) -> String:
  match bit:
    case False{}: "0"
    case True{}: "1"
def render(n: Nat, word: Word(n)) -> String:
  match n:
    case 0n: ""
    case 1n+p:
      match word:
        case WCon{bit, tail}:
          digit(bit) ++ render(p, tail)

def sample(+n: Nat, bit: Bool) -> IO(Unit):
  IO.print(render(n, Word.shl.put(n, bit, Word.zero(n))))

def run(+bit: Bool) -> IO(Unit):
  do IO<Unit>:
    sample(0n, bit)
    sample(1n, bit)
    sample(31n, bit)
    sample(32n, bit)
    sample(33n, bit)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.eq(head, "1"))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
