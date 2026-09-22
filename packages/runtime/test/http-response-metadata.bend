import Base
import ../src/http-response.bend as Metadata
import ../src/http-response.bend as Stream
import ../src/http-message.bend as Chunked
import ../src/http-message.bend as Header
import ../src/http-message.bend as Headers
import ./utf8-runner.bend as Text

def fields(values: List<&2, Header.Header>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Header.Header{name, value} <> rest: (Text.showText(name) ++ ":" ++ Text.showText(value)) <> fields(rest)

def strings(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Text.showText(value) <> strings(rest)

def shown(+value: Metadata.Metadata) -> String:
  U32.show(Metadata.metadataStatus(value)) ++ "#" ++ Text.showText(Metadata.statusText(value)) ++ "#" ++ Bool.pick(String, Metadata.ok(value), "true", "false") ++ "#" ++ Bool.pick(String, Metadata.bodyPresent(value), "body", "null") ++ "#" ++ String.join(fields(Headers.entries(Metadata.headers(value))), "|") ++ "#" ++ String.join(strings(Headers.getSetCookie(Metadata.headers(value))), "|")

def events(values: List<&2, Stream.StreamEvent>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Stream.FinalHead{head, expose} <> rest: shown(Metadata.fromHead(head, expose)) <> events(rest)
    case _ <> rest: events(rest)

def terminal(result: Stream.ResponseStreamReadResult) -> List<&2, String>:
  match result:
    case Stream.ResponseStreamComplete{values, _}: events(values)
    case Stream.ResponseStreamFailed{_, _}: "error" <> Nil{}
    case Stream.More{_, _}: "incomplete" <> Nil{}

def run(chunks: List<&2, String>, result: Stream.ResponseStreamReadResult) -> List<&2, String>:
  match chunks result:
    case _ Stream.ResponseStreamComplete{values, _}: events(values)
    case _ Stream.ResponseStreamFailed{_, _}: "error" <> Nil{}
    case Nil{} Stream.More{reader, values}: List.append(&2, String, events(values), terminal(Stream.finish(reader)))
    case head <> tail Stream.More{reader, values}: List.append(&2, String, events(values), run(tail, Stream.readResponseStream(reader, Text.parseNumbers(head))))

def start(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case method <> chunks:
      IO.print(String.join(run(chunks, Stream.More{Stream.new(method, Stream.Limits{4096n, 65536n, 100n, 16n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}), Nil{}}), "~"))
    case _: IO.die(Unit, 1, "invalid metadata fixture")

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
