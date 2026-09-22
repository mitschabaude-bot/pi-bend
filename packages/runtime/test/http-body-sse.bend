import Base
import ../src/http-message.bend as Body
import ../src/http-message.bend as Chunked
import ../src/http-message.bend as Length
import ../src/sse.bend as Stream
import ../src/sse.bend as SSE
import ../src/u64.bend as W
import ./utf8-runner.bend as Text

def eventName(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some:" ++ Text.showText(text)

def events(values: List<&2, SSE.ServerSentEvent>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case SSE.ServerSentEvent{name, data, _} <> rest: (eventName(name) ++ ":" ++ Text.showText(data)) <> events(rest)

def next(result: Stream.StreamDecoded) -> Stream.StreamDecoder:
  match result:
    case Stream.StreamDecoded{decoder, _}: decoder

def collected(previous: List<&2, SSE.ServerSentEvent>, result: Stream.StreamDecoded) -> List<&2, SSE.ServerSentEvent>:
  match result:
    case Stream.StreamDecoded{_, fresh}: List.append(&2, SSE.ServerSentEvent, previous, fresh)

def shown(status: String, values: List<&2, SSE.ServerSentEvent>, rest: List<&2, U32>) -> String:
  status ++ "|" ++ String.join(events(values), "#") ++ "|" ++ String.join(Text.showNumbers(rest), ",")

def complete(result: Stream.StreamDecoded, previous: List<&2, SSE.ServerSentEvent>, rest: List<&2, U32>) -> String:
  match result:
    case Stream.StreamDecoded{decoder, fresh}:
      shown("ok", List.append(&2, SSE.ServerSentEvent, previous, List.append(&2, SSE.ServerSentEvent, fresh, Stream.finishStream(decoder))), rest)

def eof(result: Result<&2, &2, Body.BodyError, Unit>, +decoded: Stream.StreamDecoded, previous: List<&2, SSE.ServerSentEvent>) -> String:
  match result:
    case Done{_}: complete(decoded, previous, Nil{})
    case Fail{_}: shown("error", collected(previous, decoded), Nil{})

def run(chunks: List<&2, String>, result: Body.ReadResult, decoder: Stream.StreamDecoder, previous: List<&2, SSE.ServerSentEvent>) -> String:
  match chunks result:
    case _ Body.Failed{_, bytes}: shown("error", collected(previous, Stream.decodeStream(decoder, bytes)), Nil{})
    case _ Body.Complete{bytes, _, rest}: complete(Stream.decodeStream(decoder, bytes), previous, rest)
    case Nil{} Body.More{reader, bytes}: eof(Body.finish(reader), Stream.decodeStream(decoder, bytes), previous)
    case head <> tail Body.More{reader, bytes}:
      +decoded = Stream.decodeStream(decoder, bytes)
      run(tail, Body.read(reader, Text.parseNumbers(head)), next(decoded), collected(previous, decoded))

def fixed(result: Result<&2, &2, Length.LengthError, W.U64>) -> Body.Framing:
  match result:
    case Done{size}: Body.ContentLength{size}
    case Fail{_}: Body.NoBody{}

def framing(mode: String) -> Body.Framing:
  match mode:
    case "close": Body.UntilClose{}
    case "chunked": Body.ChunkedEncoding{}
    case "empty": Body.NoBody{}
    case size: fixed(Length.parseContentLength(size))

def start(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case mode <> chunks:
      IO.print(run(chunks, Body.More{Body.newBody(framing(mode), Chunked.Limits{1024n, 1024n, 16384n, 100n}), Nil{}}, Stream.createStream(), Nil{}))
    case _: IO.die(Unit, 1, "invalid body SSE fixture")

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
