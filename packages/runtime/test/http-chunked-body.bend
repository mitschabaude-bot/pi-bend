import Base
import ../src/http-chunked-body.bend as Body
import ../src/http-header.bend as H
import ../src/http-line.bend as Line
import ./utf8-runner.bend as Text

def bytes(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def fields(values: List<&2, H.Header>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: (Text.showText(name) ++ ":" ++ Text.showText(value)) <> fields(rest)

def error(value: Body.BodyError) -> String:
  match value:
    case Body.InvalidByte{_}: "byte"
    case Body.LineError{Line.LineTooLong{}}: "line-limit"
    case Body.LineError{_}: "line"
    case Body.SizeError{_}: "size"
    case Body.TrailerError{_}: "trailer"
    case Body.InvalidDelimiter{}: "delimiter"
    case Body.TrailerTooLong{}: "trailer-limit"
    case Body.TooManyTrailers{}: "trailer-count"
    case Body.IncompleteBody{}: "incomplete"

def finished(result: Result<&2, &2, Body.BodyError, Unit>) -> String:
  match result:
    case Done{_}: "end"
    case Fail{value}: error(value)

def stream(chunks: List<&2, String>, result: Body.ReadResult) -> List<&2, String>:
  match chunks result:
    case _ Body.Failed{value, emitted}: ("error:" ++ error(value) ++ ":" ++ bytes(emitted)) <> Nil{}
    case _ Body.Complete{emitted, trailers, rest}: ("done:" ++ bytes(emitted) ++ "#" ++ String.join(fields(trailers), "|") ++ "#" ++ bytes(rest)) <> Nil{}
    case Nil{} Body.More{reader, emitted}: ("more:" ++ bytes(emitted)) <> finished(Body.finish(reader)) <> Nil{}
    case head <> rest Body.More{reader, emitted}: ("more:" ++ bytes(emitted)) <> stream(rest, Body.read(reader, Text.parseNumbers(head)))

def number(text: String) -> Nat: U32.to_nat(Text.decimal(text, 0))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case size <> line <> total <> count <> chunks:
      IO.print(String.join(stream(chunks, Body.More{Body.new(Body.Limits{number(size), number(line), number(total), number(count)}), Nil{}}), "~"))
    case _: IO.die(Unit, 1, "invalid chunked fixture")

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
