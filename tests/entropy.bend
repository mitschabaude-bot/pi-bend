import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def csv(bytes: List<&2, U32>, acc: String) -> String:
  match bytes:
    case Nil{}: acc
    case byte <> rest: csv(rest, acc ++ U32.show(byte) ++ ",")

def render(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match result:
    case Fail{Tuple{code, _}}: "error:" ++ U32.show(code)
    case Done{bytes}: "ok:" ++ csv(bytes, "")

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(Scalar.decimal(arg, 0))
        IO.print(render(result))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
