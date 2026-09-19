import Base
import ../src/http-chunk-size.bend as Size
import ../src/u64.bend as W
import ./utf8-runner.bend as Text

def shown(result: Result<&2, &2, Size.SizeError, W.U64>) -> String:
  match result:
    case Fail{Size.SizeOverflow{}}: "overflow"
    case Fail{_}: "invalid"
    case Done{W.U64{hi, lo}}: U32.show(hi) ++ "," ++ U32.show(lo)

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(shown(Size.parse(Text.parseNumbers(head))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
