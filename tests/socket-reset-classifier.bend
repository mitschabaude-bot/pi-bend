import Base
import ../packages/runtime/test/utf8-runner.bend as Text

def cases(values: List<&2, U32>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case +code <> rest:
      do IO<Unit>:
        reset : Bool <- Socket.isConnectionReset(code)
        IO.print(U32.show(code) ++ ":" ++ Bool.pick(String, reset, "reset", "other"))
        cases(rest)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{'c', values} <> rest:
      do IO<Unit>:
        cases(Text.parseNumbers(values))
        arguments(rest)
    case _ <> rest: arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
