import Base

# Inspect a value, then extend it with no other owner of that result.
def observedThenExtended(+text: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(text)
    IO.print(text ++ "!")

# Keep both operands and the concatenation alive while inspecting the result.
# Equality and the empty predicate run before any IO materializes the text.
def describe(+a: String,+b: String) -> IO(Unit):
  do IO<Unit>:
    +text : String = a ++ b
    IO.print(Bool.show(String.eq(text,a ++ b)))
    IO.print(Bool.show(String.is_empty(text)))
    IO.print(text)
    IO.print(String.reverse(text))
    IO.print(String.take(text,3n))
    IO.print(String.drop(text,3n))
    IO.print(Bool.show(String.eq(text,a ++ b)))
    IO.print(text ++ "!")
    IO.print(text)
    observedThenExtended(a ++ b)

# Each append shares its prefix with a retained snapshot. Workers inspect the
# resulting string after an effect, rather than evaluating it in the parent.
def grow(n: Nat,+text: String,kept: List<&2,String>) -> String & List<&2,String>:
  match n:
    case 0n: (text,kept)
    case 1n+left:
      +next = text ++ "abcdefghijklmnopqrstuvwxyz🙂"
      grow(left,next,next <> Nil{})
def read(+text: String) -> IO(Nat):
  do IO<Nat>:
    IO.sleep(0)
    return String.length(text) + String.length(String.reverse(text))
def start(n: Nat,+text: String,jobs: List<Chan(Nat)>) -> IO(List<Chan(Nat)>):
  match n:
    case 0n: IO.pure(List<Chan(Nat)>,jobs)
    case 1n+left:
      do IO<List<Chan(Nat)>>:
        job : Chan(Nat) <- IO.fork(Nat,read(text))
        start(left,text,job <> jobs)
def join(jobs: List<Chan(Nat)>,total: Nat) -> IO(Nat):
  match jobs:
    case Nil{}: IO.pure(Nat,total)
    case job <> rest:
      do IO<Nat>:
        result : Nat <- IO.join(Nat,job)
        join(rest,total + result)
def parallel(pair: String & List<&2,String>) -> IO(Unit):
  match pair:
    case (text,_):
      do IO<Unit>:
        jobs : List<Chan(Nat)> <- start(32n,text,Nil{})
        result : Nat <- join(jobs,0n)
        IO.print(Nat.show(result))
def run(args: List<String>) -> IO(Unit):
  match args:
    case "parallel" <> Nil{}: parallel(grow(1000n,"",Nil{}))
    case a <> b <> rest:
      do IO<Unit>:
        describe(a,b)
        run(rest)
    case _: IO.pure(Unit,Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
