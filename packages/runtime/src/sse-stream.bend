import Base
import ./sse-chunks.bend as Chunks
import ./line-decoder.bend as Lines
import ./sse-decoder.bend as SSE
import ./utf8.bend as Utf8

# Pure byte-to-event transitions corresponding to _iterSSEMessages in openai
# 6.40.0. Pulling, cancellation and resource ownership belong to the IO driver.
type StreamDecoder is Data:
  StreamDecoder{chunks: Chunks.ChunkDecoder, lines: Lines.LineDecoder, fields: SSE.SSEDecoder}

type Decoded is Data:
  Decoded{decoder: StreamDecoder, events: List<&2, SSE.ServerSentEvent>}

type Fields is Data:
  Fields{decoder: SSE.SSEDecoder, reversed: List<&2, SSE.ServerSentEvent>}

type Stage is Data:
  Stage{lines: Lines.LineDecoder, fields: SSE.SSEDecoder, reversed: List<&2, SSE.ServerSentEvent>}

def create() -> StreamDecoder:
  StreamDecoder{Chunks.create(), Lines.create(), SSE.create()}

def prepend(event: Maybe<&2, SSE.ServerSentEvent>, reversed: List<&2, SSE.ServerSentEvent>) -> List<&2, SSE.ServerSentEvent>:
  match event:
    case None{}: reversed
    case Some{value}: value <> reversed

def consumeLines(lines: List<&2, String>, result: SSE.Decoded, reversed: List<&2, SSE.ServerSentEvent>) -> Fields:
  match lines result:
    case Nil{} SSE.Decoded{decoder, event}: Fields{decoder, prepend(event, reversed)}
    case head <> tail SSE.Decoded{decoder, event}: consumeLines(tail, SSE.decode(decoder, head), prepend(event, reversed))

def withLines(lines: Lines.LineDecoder, result: Fields) -> Stage:
  match result:
    case Fields{fields, reversed}: Stage{lines, fields, reversed}

def consumeFrame(result: Lines.Decoded, fields: SSE.SSEDecoder, reversed: List<&2, SSE.ServerSentEvent>) -> Stage:
  match result:
    case Lines.Decoded{lines, text}: withLines(lines, consumeLines(text, SSE.Decoded{fields, None{}}, reversed))

def consumeChunks(chunks: List<&2, List<&2, U32>>, stage: Stage) -> Stage:
  match chunks stage:
    case Nil{} stage: stage
    case head <> tail Stage{lines, fields, reversed}: consumeChunks(tail, consumeFrame(Lines.decode(lines, head), fields, reversed))

def output(chunks: Chunks.ChunkDecoder, stage: Stage) -> Decoded:
  match stage:
    case Stage{lines, fields, reversed}: Decoded{StreamDecoder{chunks, lines, fields}, List.reverse(&2, SSE.ServerSentEvent, reversed)}

def framed(result: Chunks.Decoded, lines: Lines.LineDecoder, fields: SSE.SSEDecoder) -> Decoded:
  match result:
    case Chunks.Decoded{chunks, frames}: output(chunks, consumeChunks(frames, Stage{lines, fields, Nil{}}))

def decode(decoder: StreamDecoder, bytes: List<&2, U32>) -> Decoded:
  match decoder:
    case StreamDecoder{chunks, lines, fields}: framed(Chunks.decode(chunks, bytes), lines, fields)

def decodeText(decoder: StreamDecoder, text: String) -> Decoded:
  decode(decoder, Utf8.encode(text))

def decodeOptional(decoder: StreamDecoder, bytes: Maybe<&2, List<&2, U32>>) -> Decoded:
  match bytes:
    case None{}: Decoded{decoder, Nil{}}
    case Some{chunk}: decode(decoder, chunk)

def finishLines(stage: Stage) -> List<&2, SSE.ServerSentEvent>:
  match stage:
    case Stage{_, _, reversed}: List.reverse(&2, SSE.ServerSentEvent, reversed)

def flushLines(stage: Stage) -> List<&2, SSE.ServerSentEvent>:
  match stage:
    case Stage{lines, fields, reversed}: finishLines(consumeFrame(Lines.flush(lines), fields, reversed))

def finishChunks(result: Chunks.Decoded, lines: Lines.LineDecoder, fields: SSE.SSEDecoder) -> List<&2, SSE.ServerSentEvent>:
  match result:
    case Chunks.Decoded{_, frames}: flushLines(consumeChunks(frames, Stage{lines, fields, Nil{}}))

# EOF flushes pending bytes and the final line, but does not invent a blank
# event separator. Consume the state; unfinished event fields are discarded.
def finish(decoder: StreamDecoder) -> List<&2, SSE.ServerSentEvent>:
  match decoder:
    case StreamDecoder{chunks, lines, fields}: finishChunks(Chunks.finish(chunks), lines, fields)
