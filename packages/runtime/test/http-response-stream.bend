import Base
import ../src/http-message.bend as H
import ../src/http-response.bend as Stream
import ../src/http-message.bend as Head
import ../src/http-message.bend as Status
import ../src/http-message.bend as Chunked
import ./utf8-runner.bend as Text

def code(head: Head.ResponseHead) -> String:
  match head:
    case Head.ResponseHead{Status.StatusLine{_, _, status, _}, _}: U32.show(status)

def trailers(fields: List<&2, H.Header>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: (Text.showText(name) ++ ":" ++ Text.showText(value)) <> trailers(rest)

def completed(fields: List<&2, H.Header>) -> String:
  match fields:
    case Nil{}: "done"
    case head <> rest: "done:" ++ String.join(trailers(head <> rest), "/")

def event(value: Stream.StreamEvent) -> String:
  match value:
    case Stream.InformationalHead{head}: "info:" ++ code(head)
    case Stream.FinalHead{head, expose}: "head:" ++ code(head) ++ ":" ++ Bool.pick(String, expose, "body", "null")
    case Stream.BodyData{bytes}: "data:" ++ String.join(Text.showNumbers(bytes), ",")
    case Stream.Completed{fields}: completed(fields)

def events(values: List<&2, Stream.StreamEvent>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: event(head) <> events(rest)

def summary(status: String, values: List<&2, Stream.StreamEvent>, rest: List<&2, U32>) -> String:
  status ++ "|" ++ String.join(events(values), "~") ++ "|" ++ String.join(Text.showNumbers(rest), ",")

def terminal(result: Stream.ResponseStreamReadResult) -> String:
  match result:
    case Stream.ResponseStreamComplete{values, rest}: summary("complete", values, rest)
    case Stream.ResponseStreamFailed{_, values}: summary("error", values, Nil{})
    case Stream.More{_, values}: summary("more", values, Nil{})

def run(chunks: List<&2, String>, result: Stream.ResponseStreamReadResult) -> List<&2, String>:
  match chunks result:
    case _ Stream.ResponseStreamComplete{values, rest}: summary("complete", values, rest) <> Nil{}
    case _ Stream.ResponseStreamFailed{_, values}: summary("error", values, Nil{}) <> Nil{}
    case Nil{} Stream.More{reader, values}: summary("more", values, Nil{}) <> terminal(Stream.finish(reader)) <> Nil{}
    case head <> tail Stream.More{reader, values}:
      summary("more", values, Nil{}) <> run(tail, Stream.readResponseStream(reader, Text.parseNumbers(head)))

def start(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case method <> budget <> chunks:
      IO.print(String.join(run(chunks, Stream.More{Stream.new(method, Stream.Limits{4096n, 65536n, 100n, U32.to_nat(Text.decimal(budget, 0)), Chunked.Limits{1024n, 1024n, 16384n, 100n}}), Nil{}}), "#"))
    case _: IO.die(Unit, 1, "invalid response-stream fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        start(String.split(head, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
