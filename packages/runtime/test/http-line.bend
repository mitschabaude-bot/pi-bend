import Base
import ../src/http-line.bend as Line
import ./utf8-runner.bend as Text

def numbers(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def error(value: Line.ReadError) -> String:
  match value:
    case Line.LineTooLong{}: "long"
    case Line.InvalidByte{byte}: "invalid:" ++ numbers(byte <> Nil{})
    case Line.IncompleteLine{}: "incomplete"

def shown(result: Line.ReadResult) -> String:
  match result:
    case Line.More{_}: "more"
    case Line.Line{bytes, rest}: "line:" ++ numbers(bytes) ++ ";" ++ numbers(rest)
    case Line.Failed{value}: error(value)

def next(chunks: List<&2, String>, result: Line.ReadResult) -> List<&2, String>:
  match chunks result:
    case _ Line.Failed{value}: error(value) <> Nil{}
    case _ Line.Line{bytes, rest}: ("line:" ++ numbers(bytes) ++ ";" ++ numbers(rest)) <> Nil{}
    case Nil{} Line.More{reader}: shown(Line.finish(reader)) <> Nil{}
    case head <> tail Line.More{reader}: "more" <> next(tail, Line.read(reader, Text.parseNumbers(head)))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case limit <> chunks: IO.print(String.join(next(chunks, Line.More{Line.new(U32.to_nat(Text.decimal(limit, 0)))}), "|"))
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
