import Base
import ../src/http-fixed-body.bend as Body
import ../src/http-content-length.bend as Length
import ../src/u64.bend as W
import ./utf8-runner.bend as Text

def number(value: W.U64) -> String:
  match value:
    case W.U64{hi, lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def bytes(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def error(value: Body.BodyError) -> String:
  match value:
    case Body.InvalidByte{value}: "invalid:" ++ U32.show(value)
    case Body.IncompleteBody{remaining}: "incomplete:" ++ number(remaining)

def finished(result: Result<&2, &2, Body.BodyError, Unit>) -> String:
  match result:
    case Done{_}: "end"
    case Fail{value}: error(value)

def progress(reader: Body.Reader, emitted: List<&2, U32>) -> String:
  match reader:
    case Body.Reader{remaining}: "more:" ++ number(remaining) ++ ":" ++ bytes(emitted)

def stream(chunks: List<&2, String>, result: Body.ReadResult) -> List<&2, String>:
  match chunks result:
    case _ Body.Failed{value}: error(value) <> Nil{}
    case _ Body.Complete{emitted, rest}: ("done:" ++ bytes(emitted) ++ ":" ++ bytes(rest)) <> Nil{}
    case Nil{} Body.More{+reader, emitted}: progress(reader, emitted) <> finished(Body.finish(reader)) <> Nil{}
    case head <> rest Body.More{+reader, emitted}:
      progress(reader, emitted) <> stream(rest, Body.read(reader, Text.parseNumbers(head)))

def parsed(result: Result<&2, &2, Length.LengthError, W.U64>, chunks: List<&2, String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid test length")
    case Done{length}: IO.print(String.join(stream(chunks, Body.More{Body.new(length), Nil{}}), "|"))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case length <> chunks: parsed(Length.parse(length), chunks)
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
