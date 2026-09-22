import Base
import ../src/sse.bend as Stream
import ../src/sse.bend as SSE
import ./sse-decoder-runner.bend as Events
import ./utf8-runner.bend as H

def showEvents(events: List<&2, SSE.ServerSentEvent>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case head <> tail: Events.showEvent(Some{head}) <> showEvents(tail)

def show(events: List<&2, SSE.ServerSentEvent>) -> String:
  String.join(showEvents(events), "~")

def instruction(decoder: Stream.StreamDecoder, operation: String) -> Stream.StreamDecoded:
  match operation:
    case SCon{Chr{98}, bytes}: Stream.decodeStream(decoder, H.parseNumbers(bytes))
    case SCon{Chr{116}, scalars}: Stream.decodeTextStream(decoder, H.fromScalars(H.parseNumbers(scalars)))
    case _: Stream.decodeOptionalStream(decoder, None{})

def execute(operations: List<&2, String>, result: Stream.StreamDecoded) -> List<&2, String>:
  match operations result:
    case Nil{} Stream.StreamDecoded{decoder, events}: show(events) <> show(Stream.finishStream(decoder)) <> Nil{}
    case operation <> rest Stream.StreamDecoded{decoder, events}: show(events) <> execute(rest, instruction(decoder, operation))

def start(operations: List<&2, String>) -> String:
  match operations:
    case Nil{}: show(Stream.finishStream(Stream.createStream()))
    case operation <> rest: String.join(execute(rest, instruction(Stream.createStream(), operation)), "|")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, text} <> rest:
      do IO<Unit>:
        IO.print(start(String.split(text, '|')))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
