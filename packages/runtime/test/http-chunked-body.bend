import Base
import ../src/http-message.bend as Body
import ../src/http-message.bend as H
import ../src/http-message.bend as Line
import ./utf8-runner.bend as Text

def bytes(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def fields(values: List<&2, H.Header>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: (Text.showText(name) ++ ":" ++ Text.showText(value)) <> fields(rest)

def error(value: Body.ChunkedBodyError) -> String:
  match value:
    case Body.ChunkedBodyInvalidByte{_}: "byte"
    case Body.LineError{Line.LineTooLong{}}: "line-limit"
    case Body.LineError{_}: "line"
    case Body.ChunkedBodySizeError{_}: "size"
    case Body.TrailerError{_}: "trailer"
    case Body.InvalidDelimiter{}: "delimiter"
    case Body.TrailerTooLong{}: "trailer-limit"
    case Body.TooManyTrailers{}: "trailer-count"
    case Body.IncompleteBody{}: "incomplete"

def finished(result: Result<&2, &2, Body.ChunkedBodyError, Unit>) -> String:
  match result:
    case Done{_}: "end"
    case Fail{value}: error(value)

def stream(chunks: List<&2, String>, result: Body.ChunkedBodyReadResult) -> List<&2, String>:
  match chunks result:
    case _ Body.ChunkedBodyFailed{value, emitted}: ("error:" ++ error(value) ++ ":" ++ bytes(emitted)) <> Nil{}
    case _ Body.ChunkedBodyComplete{emitted, trailers, rest}: ("done:" ++ bytes(emitted) ++ "#" ++ String.join(fields(trailers), "|") ++ "#" ++ bytes(rest)) <> Nil{}
    case Nil{} Body.ChunkedBodyMore{reader, emitted}: ("more:" ++ bytes(emitted)) <> finished(Body.finishChunkedBody(reader)) <> Nil{}
    case head <> rest Body.ChunkedBodyMore{reader, emitted}: ("more:" ++ bytes(emitted)) <> stream(rest, Body.readChunkedBody(reader, Text.parseNumbers(head)))

def number(text: String) -> Nat: U32.to_nat(Text.decimal(text, 0))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case size <> line <> total <> count <> chunks:
      IO.print(String.join(stream(chunks, Body.ChunkedBodyMore{Body.newChunkedBody(Body.Limits{number(size), number(line), number(total), number(count)}), Nil{}}), "~"))
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
