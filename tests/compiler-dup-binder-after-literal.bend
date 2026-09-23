import Base

# BEND-034: a `+` binder in a fallback arm after a literal-headed list
# pattern fails to infer; the same match without `+` compiles.
def pick(values: List<&2, U32>) -> U32:
  match values:
    case 92 <> +code <> Nil{}: code
    case +code <> Nil{}: code
    case _: 0

def main() -> IO(Unit): IO.print(U32.show(pick(92 <> 7 <> Nil{})))
