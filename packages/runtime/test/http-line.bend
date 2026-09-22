import Base
import ../src/http-message.bend as Line
import ./utf8-runner.bend as Text

def numbers(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def error(value: Line.LineReadError) -> String:
  match value:
    case Line.LineTooLong{}: "long"
    case Line.LineInvalidByte{byte}: "invalid:" ++ numbers(byte <> Nil{})
    case Line.IncompleteLine{}: "incomplete"

def shown(result: Line.LineReadResult) -> String:
  match result:
    case Line.LineMore{_}: "more"
    case Line.Line{bytes, rest}: "line:" ++ numbers(bytes) ++ ";" ++ numbers(rest)
    case Line.LineFailed{value}: error(value)

def next(chunks: List<&2, String>, result: Line.LineReadResult) -> List<&2, String>:
  match chunks result:
    case _ Line.LineFailed{value}: error(value) <> Nil{}
    case _ Line.Line{bytes, rest}: ("line:" ++ numbers(bytes) ++ ";" ++ numbers(rest)) <> Nil{}
    case Nil{} Line.LineMore{reader}: shown(Line.finishLine(reader)) <> Nil{}
    case head <> tail Line.LineMore{reader}: "more" <> next(tail, Line.readLine(reader, Text.parseNumbers(head)))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case limit <> chunks: IO.print(String.join(next(chunks, Line.LineMore{Line.newLine(U32.to_nat(Text.decimal(limit, 0)))}), "|"))
    case _: IO.die(Unit, 1, "invalid line fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
