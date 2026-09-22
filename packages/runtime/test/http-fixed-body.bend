import Base
import ../src/http-message.bend as Body
import ../src/http-message.bend as Length
import ../src/u64.bend as W
import ./utf8-runner.bend as Text

def number(value: W.U64) -> String:
  match value:
    case W.U64{hi, lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def bytes(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def error(value: Body.FixedBodyBodyError) -> String:
  match value:
    case Body.FixedBodyInvalidByte{value}: "invalid:" ++ U32.show(value)
    case Body.FixedBodyIncompleteBody{remaining}: "incomplete:" ++ number(remaining)

def finished(result: Result<&2, &2, Body.FixedBodyBodyError, Unit>) -> String:
  match result:
    case Done{_}: "end"
    case Fail{value}: error(value)

def progress(reader: Body.FixedBodyReader, emitted: List<&2, U32>) -> String:
  match reader:
    case Body.FixedBodyReader{remaining}: "more:" ++ number(remaining) ++ ":" ++ bytes(emitted)

def stream(chunks: List<&2, String>, result: Body.FixedBodyReadResult) -> List<&2, String>:
  match chunks result:
    case _ Body.FixedBodyFailed{value}: error(value) <> Nil{}
    case _ Body.FixedBodyComplete{emitted, rest}: ("done:" ++ bytes(emitted) ++ ":" ++ bytes(rest)) <> Nil{}
    case Nil{} Body.FixedBodyMore{+reader, emitted}: progress(reader, emitted) <> finished(Body.finishFixedBody(reader)) <> Nil{}
    case head <> rest Body.FixedBodyMore{+reader, emitted}:
      progress(reader, emitted) <> stream(rest, Body.readFixedBody(reader, Text.parseNumbers(head)))

def parsed(result: Result<&2, &2, Length.LengthError, W.U64>, chunks: List<&2, String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid test length")
    case Done{length}: IO.print(String.join(stream(chunks, Body.FixedBodyMore{Body.newFixedBody(length), Nil{}}), "|"))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case length <> chunks: parsed(Length.parseContentLength(length), chunks)
    case _: IO.die(Unit, 1, "invalid body fixture")

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
