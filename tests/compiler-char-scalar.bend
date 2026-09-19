import Base
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/test/utf8-runner.bend as Text

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(String.join(Text.showNumbers(Utf8.encode(SCon{Chr{Text.decimal(value, 0)}, ""})), ","))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
