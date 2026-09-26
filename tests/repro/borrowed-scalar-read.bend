import Base

# BEND-054: a walk that reads the scalars of a shared List<U32> takes every
# node (`sumOf`, `ctr_take`); the same walk comparing them with literal
# patterns borrows the list (`countOf`, `term_peek`). Both scan a shared
# list of 1,000,000 scalars 100 times; `read` or `match` picks the walk.
def sumOf(codes: List<&2,U32>,+total: U32) -> U32:
  match codes:
    case Nil{}: total
    case code <> rest: sumOf(rest,(total + code : U32))
def countOf(codes: List<&2,U32>,+total: U32) -> U32:
  match codes:
    case Nil{}: total
    case 65 <> rest: countOf(rest,(total + 65 : U32))
    case _ <> rest: countOf(rest,total)
def build(n: Nat,acc: List<&2,U32>) -> List<&2,U32>:
  match n:
    case Zero{}: acc
    case Succ{+m}: build(m,65 <> acc)
def reading(+codes: List<&2,U32>,rounds: Nat,+total: U32) -> U32:
  match rounds:
    case Zero{}: total
    case Succ{more}: reading(codes,more,(total + sumOf(codes,0) : U32))
def matching(+codes: List<&2,U32>,rounds: Nat,+total: U32) -> U32:
  match rounds:
    case Zero{}: total
    case Succ{more}: matching(codes,more,(total + countOf(codes,0) : U32))
def run(args: List<String>,+codes: List<&2,U32>) -> U32:
  match args:
    case "read" <> _: reading(codes,100n,0)
    case _: matching(codes,100n,0)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    IO.print(U32.show(run(args,build(1000000n,Nil{}))))
