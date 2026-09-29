import Base

# Exercise scalar equality through retained roots, generic storage and closures.
# The oracle supplies dynamic Unicode/control strings and checks lengths after
# comparison, including passing the same retained root twice.
type Box<-A: Data> is Data: Box{value: A}
def unbox(-A: Data,value: Box<A>) -> A:
  match value: case Box{value}: value
def apply(f: Unit -> String) -> String: f(Unit{})
def report(+a: String,+b: String) -> String:
  U32.show(Bool.to_u32(String.eq(a,b))) ++ ":" ++ Nat.show(String.length(a)) ++ ":" ++ Nat.show(String.length(b)) ++ ":" ++ U32.show(Bool.to_u32(String.eq(a,a))) ++ ":" ++ U32.show(Bool.to_u32(False{} || String.eq(a,b))) ++ ":" ++ U32.show(Bool.to_u32(String.eq(a,b) || False{}))
def run(args: List<String>) -> IO(Unit):
  match args:
    case "nul" <> rest:
      do IO<Unit>:
        IO.print(report("\0x","\0x"))
        IO.print(report("\0x","\0y"))
        run(rest)
    case a <> b <> rest:
      do IO<Unit>:
        IO.print(report(apply(_ => unbox(String,Box{a})),b))
        run(rest)
    case _: IO.pure(Unit,Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
