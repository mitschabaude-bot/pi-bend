import Base
import ../packages/runtime/src/utf8-strict.bend as UTF8
import ../packages/runtime/test/utf8-runner.bend as Scalar

def error(value: UTF8.Error) -> String:
  match value:
    case UTF8.InvalidByte{offset, byte}: "byte:" ++ U32.show(U32.from_nat(offset)) ++ ":" ++ U32.show(byte)
    case UTF8.InvalidSequence{offset, byte}: "invalid:" ++ U32.show(U32.from_nat(offset)) ++ ":" ++ U32.show(byte)
    case UTF8.IncompleteSequence{offset}: "incomplete:" ++ U32.show(U32.from_nat(offset))

def output(value: Result<&2, &2, UTF8.Error, String>) -> String:
  match value:
    case Fail{reason}: error(reason)
    case Done{text}: "ok:" ++ Scalar.showText(text)

def chunks(parts: List<&2, String>, state: Result<&2, &2, UTF8.Error, UTF8.State>) -> Result<&2, &2, UTF8.Error, String>:
  match parts:
    case Nil{}: UTF8.finish(state)
    case part <> rest: chunks(rest, UTF8.feed(Scalar.parseNumbers(part), state))

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case mode <> text <> rest:
      do IO<Unit>:
        IO.print(output(chunks(String.split(text, '|'), Done{UTF8.initial(Bool.pick(UTF8.BOM, String.eq(mode, "preserve"), UTF8.Preserve{}, UTF8.StripLeading{}))})))
        run(rest)
    case _: IO.die(Unit, 1, "expected BOM mode / byte chunks")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
