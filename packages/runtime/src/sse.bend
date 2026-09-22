import Base
import ./utf8.bend as Utf8
import ./callback.bend as Callback

# Behavioral port of openai 6.40.0 internal/decoders/line.ts.
# See licenses/openai-sdk.txt. Storage and transitions are native immutable Bend.
type Pending is Data:
  Reading{reversed: List<&2, U32>}
  AfterCarriageReturn{before: List<&2, U32>, after: List<&2, U32>}

type LineDecoder is Data:
  LineDecoder{pending: Pending}

type Decoded is Data:
  Decoded{decoder: LineDecoder, lines: List<&2, String>}

def create() -> LineDecoder: LineDecoder{Reading{Nil{}}}

def lineText(reversed: List<&2, U32>) -> String:
  Utf8.decodeBytes(List.reverse(&2, U32, reversed))

def afterNewline(before: List<&2, U32>, after: List<&2, U32>) -> Decoded:
  match after:
    case Nil{}: Decoded{create(), lineText(before) <> Nil{}}
    case head <> tail: Decoded{create(), lineText(before) <> lineText(head <> tail) <> Nil{}}

# A CR stays pending until the next newline, even if ordinary bytes arrive.
# This preserves the SDK's emission timing for CR, CRLF and CR-text-LF.
def consume(decoder: LineDecoder, byte: U32) -> Decoded:
  match decoder byte:
    case LineDecoder{Reading{reversed}} 10: Decoded{create(), lineText(reversed) <> Nil{}}
    case LineDecoder{Reading{reversed}} 13: Decoded{LineDecoder{AfterCarriageReturn{reversed, Nil{}}}, Nil{}}
    case LineDecoder{Reading{reversed}} byte: Decoded{LineDecoder{Reading{byte <> reversed}}, Nil{}}
    case LineDecoder{AfterCarriageReturn{before, after}} 10: afterNewline(before, after)
    case LineDecoder{AfterCarriageReturn{before, after}} 13: Decoded{LineDecoder{AfterCarriageReturn{after, Nil{}}}, lineText(before) <> Nil{}}
    case LineDecoder{AfterCarriageReturn{before, after}} byte: Decoded{LineDecoder{AfterCarriageReturn{before, byte <> after}}, Nil{}}

def prepend(lines: List<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: reversed
    case head <> tail: prepend(tail, head <> reversed)

def collect(bytes: List<&2, U32>, result: Decoded, reversed: List<&2, String>) -> Decoded:
  match bytes result:
    case Nil{} Decoded{decoder, lines}: Decoded{decoder, List.reverse(&2, String, prepend(lines, reversed))}
    case head <> tail Decoded{decoder, lines}: collect(tail, consume(decoder, head), prepend(lines, reversed))

def decode(decoder: LineDecoder, bytes: List<&2, U32>) -> Decoded:
  collect(bytes, Decoded{decoder, Nil{}}, Nil{})

def decodeText(decoder: LineDecoder, text: String) -> Decoded:
  decode(decoder, Utf8.encode(text))

def decodeOptional(decoder: LineDecoder, chunk: Maybe<&2, List<&2, U32>>) -> Decoded:
  match chunk:
    case None{}: Decoded{decoder, Nil{}}
    case Some{bytes}: decode(decoder, bytes)

def flush(decoder: LineDecoder) -> Decoded:
  match decoder:
    case LineDecoder{Reading{Nil{}}}: Decoded{create(), Nil{}}
    case LineDecoder{pending}: consume(LineDecoder{pending}, 10)

# A small prefix automaton finds boundaries without rescanning buffered bytes.
type BoundaryPrefix is Data:
  EmptyPrefix{}
  LineFeed{}
  CarriageReturn{}
  CarriageLineFeed{}
  CarriageLineFeedCarriage{}

type BoundaryStep is Data:
  Continue{prefix: BoundaryPrefix}
  Found{}

def boundaryStep(prefix: BoundaryPrefix, byte: U32) -> BoundaryStep:
  match prefix byte:
    case LineFeed{} 10: Found{}
    case CarriageReturn{} 13: Found{}
    case CarriageReturn{} 10: Continue{CarriageLineFeed{}}
    case CarriageLineFeed{} 10: Found{}
    case CarriageLineFeed{} 13: Continue{CarriageLineFeedCarriage{}}
    case CarriageLineFeedCarriage{} 10: Found{}
    case CarriageLineFeedCarriage{} 13: Found{}
    case _ 10: Continue{LineFeed{}}
    case _ 13: Continue{CarriageReturn{}}
    case _ _: Continue{EmptyPrefix{}}

def findBoundary(bytes: List<&2, U32>, step: BoundaryStep, offset: Nat) -> Maybe<&2, Nat>:
  match bytes step:
    case _ Found{}: Some{offset}
    case Nil{} _: None{}
    case head <> tail Continue{prefix}: findBoundary(tail, boundaryStep(prefix, head), offset + 1n)

# Return the byte index after the first CRCR, LFLF or CRLFCRLF boundary.
# An absent boundary is None, rather than a negative array index.
def findDoubleNewlineIndex(bytes: List<&2, U32>) -> Maybe<&2, Nat>:
  findBoundary(bytes, Continue{EmptyPrefix{}}, 0n)

# Event fields from openai 6.40.0 SSEDecoder (licenses/openai-sdk.txt).
# Approved difference: empty blocks discard diagnostic-only lines.
type ServerSentEvent is Data:
  ServerSentEvent{event: Maybe<&2, String>, data: String, raw: List<&2, String>}

type SSEDecoder is Data:
  SSEDecoder{event: Maybe<&2, String>, dataReversed: List<&2, String>, rawReversed: List<&2, String>}

type DecoderDecoded is Data:
  DecoderDecoded{decoder: SSEDecoder, event: Maybe<&2, ServerSentEvent>}

type Field is Data:
  Field{name: String, value: String}

def createDecoder() -> SSEDecoder: SSEDecoder{None{}, Nil{}, Nil{}}

def dropCarriage(reversed: String) -> String:
  match reversed:
    case SCon{Chr{13}, rest}: String.reverse(rest)
    case rest: String.reverse(rest)

def dropSpace(text: String) -> String:
  match text:
    case SCon{Chr{32}, rest}: rest
    case rest: rest

def partition(text: String, reversed: String) -> Field:
  match text:
    case SNil{}: Field{String.reverse(reversed), ""}
    case SCon{Chr{58}, rest}: Field{String.reverse(reversed), dropSpace(rest)}
    case SCon{head, rest}: partition(rest, SCon{head, reversed})

def emit(event: Maybe<&2, String>, reversed: List<&2, String>, raw: List<&2, String>) -> DecoderDecoded:
  DecoderDecoded{createDecoder(), Some{ServerSentEvent{event, String.join(List.reverse(&2, String, reversed), "\n"), List.reverse(&2, String, raw)}}}

def blank(state: SSEDecoder) -> DecoderDecoded:
  match state:
    case SSEDecoder{None{}, Nil{}, _}: DecoderDecoded{createDecoder(), None{}}
    case SSEDecoder{Some{SNil{}}, Nil{}, _}: DecoderDecoded{SSEDecoder{Some{""}, Nil{}, Nil{}}, None{}}
    case SSEDecoder{event, data, raw}: emit(event, data, raw)

def field(isData: Bool, isEvent: Bool, value: String, state: SSEDecoder, line: String) -> DecoderDecoded:
  match isData isEvent state:
    case True{} _ SSEDecoder{event, data, raw}: DecoderDecoded{SSEDecoder{event, value <> data, line <> raw}, None{}}
    case _ True{} SSEDecoder{_, data, raw}: DecoderDecoded{SSEDecoder{Some{value}, data, line <> raw}, None{}}
    case _ _ SSEDecoder{event, data, raw}: DecoderDecoded{SSEDecoder{event, data, line <> raw}, None{}}

def parsed(value: Field, state: SSEDecoder, line: String) -> DecoderDecoded:
  match value:
    case Field{+name, value}: field(String.eq(name, "data"), String.eq(name, "event"), value, state, line)

def decodeLine(line: String, state: SSEDecoder) -> DecoderDecoded:
  match line:
    case SNil{}: blank(state)
    case +line: parsed(partition(line, ""), state, line)

def decoderStep(state: SSEDecoder, line: String) -> DecoderDecoded:
  decodeLine(dropCarriage(String.reverse(line)), state)

# Framing used by openai 6.40.0 iterSSEChunks (licenses/openai-sdk.txt).
# Keep bytes intact until CRCR, LFLF or CRLFCRLF, including across input chunks.
type ChunkDecoder is Data:
  ChunkDecoder{prefix: BoundaryPrefix, reversed: List<&2, U32>}

type ChunksDecoded is Data:
  ChunksDecoded{decoder: ChunkDecoder, chunks: List<&2, List<&2, U32>>}

def createChunks() -> ChunkDecoder:
  ChunkDecoder{EmptyPrefix{}, Nil{}}

def advance(step: BoundaryStep, reversed: List<&2, U32>) -> ChunksDecoded:
  match step:
    case Found{}: ChunksDecoded{createChunks(), List.reverse(&2, U32, reversed) <> Nil{}}
    case Continue{prefix}: ChunksDecoded{ChunkDecoder{prefix, reversed}, Nil{}}

def chunksConsume(decoder: ChunkDecoder, +byte: U32) -> ChunksDecoded:
  match decoder:
    case ChunkDecoder{prefix, reversed}: advance(boundaryStep(prefix, byte), byte <> reversed)

def prependChunks(chunks: List<&2, List<&2, U32>>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match chunks:
    case Nil{}: reversed
    case head <> tail: prependChunks(tail, head <> reversed)

def collectChunks(bytes: List<&2, U32>, result: ChunksDecoded, reversed: List<&2, List<&2, U32>>) -> ChunksDecoded:
  match bytes result:
    case Nil{} ChunksDecoded{decoder, chunks}: ChunksDecoded{decoder, List.reverse(&2, List<&2, U32>, prependChunks(chunks, reversed))}
    case head <> tail ChunksDecoded{decoder, chunks}: collectChunks(tail, chunksConsume(decoder, head), prependChunks(chunks, reversed))

def decodeChunks(decoder: ChunkDecoder, bytes: List<&2, U32>) -> ChunksDecoded:
  collectChunks(bytes, ChunksDecoded{decoder, Nil{}}, Nil{})

def decodeTextChunks(decoder: ChunkDecoder, text: String) -> ChunksDecoded:
  decodeChunks(decoder, Utf8.encode(text))

def decodeOptionalChunks(decoder: ChunkDecoder, bytes: Maybe<&2, List<&2, U32>>) -> ChunksDecoded:
  match bytes:
    case None{}: ChunksDecoded{decoder, Nil{}}
    case Some{chunk}: decodeChunks(decoder, chunk)

def finish(decoder: ChunkDecoder) -> ChunksDecoded:
  match decoder:
    case ChunkDecoder{_, Nil{}}: ChunksDecoded{createChunks(), Nil{}}
    case ChunkDecoder{_, head <> tail}: ChunksDecoded{createChunks(), List.reverse(&2, U32, head <> tail) <> Nil{}}

# Pure byte-to-event transitions corresponding to _iterSSEMessages in openai
# 6.40.0. Pulling, cancellation and resource ownership belong to the IO driver.
type StreamDecoder is Data:
  StreamDecoder{chunks: ChunkDecoder, lines: LineDecoder, fields: SSEDecoder}

type StreamDecoded is Data:
  StreamDecoded{decoder: StreamDecoder, events: List<&2, ServerSentEvent>}

type Fields is Data:
  Fields{decoder: SSEDecoder, reversed: List<&2, ServerSentEvent>}

type Stage is Data:
  Stage{lines: LineDecoder, fields: SSEDecoder, reversed: List<&2, ServerSentEvent>}

def createStream() -> StreamDecoder:
  StreamDecoder{createChunks(), create(), createDecoder()}

def prependStream(event: Maybe<&2, ServerSentEvent>, reversed: List<&2, ServerSentEvent>) -> List<&2, ServerSentEvent>:
  match event:
    case None{}: reversed
    case Some{value}: value <> reversed

def consumeLines(lines: List<&2, String>, result: DecoderDecoded, reversed: List<&2, ServerSentEvent>) -> Fields:
  match lines result:
    case Nil{} DecoderDecoded{decoder, event}: Fields{decoder, prependStream(event, reversed)}
    case head <> tail DecoderDecoded{decoder, event}: consumeLines(tail, decoderStep(decoder, head), prependStream(event, reversed))

def withLines(lines: LineDecoder, result: Fields) -> Stage:
  match result:
    case Fields{fields, reversed}: Stage{lines, fields, reversed}

def consumeFrame(result: Decoded, fields: SSEDecoder, reversed: List<&2, ServerSentEvent>) -> Stage:
  match result:
    case Decoded{lines, text}: withLines(lines, consumeLines(text, DecoderDecoded{fields, None{}}, reversed))

def consumeChunks(chunks: List<&2, List<&2, U32>>, stage: Stage) -> Stage:
  match chunks stage:
    case Nil{} stage: stage
    case head <> tail Stage{lines, fields, reversed}: consumeChunks(tail, consumeFrame(decode(lines, head), fields, reversed))

def output(chunks: ChunkDecoder, stage: Stage) -> StreamDecoded:
  match stage:
    case Stage{lines, fields, reversed}: StreamDecoded{StreamDecoder{chunks, lines, fields}, List.reverse(&2, ServerSentEvent, reversed)}

def framed(result: ChunksDecoded, lines: LineDecoder, fields: SSEDecoder) -> StreamDecoded:
  match result:
    case ChunksDecoded{chunks, frames}: output(chunks, consumeChunks(frames, Stage{lines, fields, Nil{}}))

def decodeStream(decoder: StreamDecoder, bytes: List<&2, U32>) -> StreamDecoded:
  match decoder:
    case StreamDecoder{chunks, lines, fields}: framed(decodeChunks(chunks, bytes), lines, fields)

def decodeTextStream(decoder: StreamDecoder, text: String) -> StreamDecoded:
  decodeStream(decoder, Utf8.encode(text))

def decodeOptionalStream(decoder: StreamDecoder, bytes: Maybe<&2, List<&2, U32>>) -> StreamDecoded:
  match bytes:
    case None{}: StreamDecoded{decoder, Nil{}}
    case Some{chunk}: decodeStream(decoder, chunk)

def finishLines(stage: Stage) -> List<&2, ServerSentEvent>:
  match stage:
    case Stage{_, _, reversed}: List.reverse(&2, ServerSentEvent, reversed)

def flushLines(stage: Stage) -> List<&2, ServerSentEvent>:
  match stage:
    case Stage{lines, fields, reversed}: finishLines(consumeFrame(flush(lines), fields, reversed))

def finishChunks(result: ChunksDecoded, lines: LineDecoder, fields: SSEDecoder) -> List<&2, ServerSentEvent>:
  match result:
    case ChunksDecoded{_, frames}: flushLines(consumeChunks(frames, Stage{lines, fields, Nil{}}))

# EOF flushes pending bytes and the final line, but does not invent a blank
# event separator. Consume the state; unfinished event fields are discarded.
def finishStream(decoder: StreamDecoder) -> List<&2, ServerSentEvent>:
  match decoder:
    case StreamDecoder{chunks, lines, fields}: finishChunks(finish(chunks), lines, fields)

type Chunk is Data:
  Bytes{value: List<&2, U32>}
  Text{value: String}
  EmptyChunk{}

# One acquired input iterator. Callback handles are borrowed; the owner is
# responsible for retiring them after this cursor is no longer used.
type Source<-E: Data> is Data:
  Source{nextReader: Callback.Callback<Unit, Result<&2, &2, E, Maybe<&2, Chunk>>>, closeReader: Callback.Callback<Unit, Result<&2, &2, E, Unit>>}

type Position is Data:
  Fresh{}
  ReaderReading{decoder: StreamDecoder, pending: List<&2, ServerSentEvent>}
  Drained{pending: List<&2, ServerSentEvent>}
  Closed{}

# The cursor is affine: advance/close returns its successor rather than
# sharing a mutable decoder or allowing two calls to race over one cursor.
type Cursor<-E: Data> is Type:
  Cursor{source: Source<E>, position: Position}

type Next<-E: Data> is Type:
  Next{cursor: Cursor<E>, result: Result<&2, &2, E, Maybe<&2, ServerSentEvent>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, E, Unit>}

type Decision<-E: Data> is Data:
  Available{position: Position, result: Result<&2, &2, E, Maybe<&2, ServerSentEvent>>}
  ReadMore{decoder: StreamDecoder}

def createReader(-E: Data, source: Source<E>) -> Cursor<E>:
  Cursor{source, Fresh{}}

def decide(-E: Data, position: Position) -> Decision<E>:
  match position:
    case Fresh{}: ReadMore{createStream()}
    case ReaderReading{decoder, Nil{}}: ReadMore{decoder}
    case ReaderReading{decoder, head <> tail}: Available{ReaderReading{decoder, tail}, Done{Some{head}}}
    case Drained{head <> tail}: Available{Drained{tail}, Done{Some{head}}}
    case _: Available{Closed{}, Done{None{}}}

def decoded(-E: Data, result: StreamDecoded) -> Decision<E>:
  match result:
    case StreamDecoded{decoder, events}: decide(E, ReaderReading{decoder, events})

def received(-E: Data, decoder: StreamDecoder, result: Result<&2, &2, E, Maybe<&2, Chunk>>) -> Decision<E>:
  match result:
    case Fail{error}: Available{Closed{}, Fail{error}}
    case Done{None{}}: decide(E, Drained{finishStream(decoder)})
    case Done{Some{Bytes{bytes}}}: decoded(E, decodeStream(decoder, bytes))
    case Done{Some{Text{text}}}: decoded(E, decodeTextStream(decoder, text))
    case Done{Some{EmptyChunk{}}}: ReadMore{decoder}

def read(-E: Data, source: Source<E>) -> IO(Result<&2, &2, E, Maybe<&2, Chunk>>):
  match source:
    case Source{nextReader, _}: Callback.call(Unit, Result<&2, &2, E, Maybe<&2, Chunk>>, nextReader, Unit{})

# An external iterator determines when another event or EOF becomes available.
@unsafe def drive(-E: Data, +source: Source<E>, decision: Decision<E>) -> IO(Next<E>):
  match decision:
    case Available{position, result}: IO.pure(Next<E>, Next{Cursor{source, position}, result})
    case ReadMore{decoder}:
      do IO<Next<E>>:
        result : Result<&2, &2, E, Maybe<&2, Chunk>> <- read(E, source)
        drive(E, source, received(E, decoder, result))

def nextReader(-E: Data, cursor: Cursor<E>) -> IO(Next<E>):
  match cursor:
    case Cursor{source, position}: drive(E, source, decide(E, position))

def closeSource(-E: Data, source: Source<E>) -> IO(Result<&2, &2, E, Unit>):
  match source:
    case Source{_, closeReader}: Callback.call(Unit, Result<&2, &2, E, Unit>, closeReader, Unit{})

# No underlying return on unopened, exhausted or failed iteration. An early
# close of an active input calls return once; its error is returned, and the
# successor cursor is closed even when return failed.
def closeReader(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{+source, ReaderReading{_, _}}:
      do IO<CloseResult<E>>:
        result : Result<&2, &2, E, Unit> <- closeSource(E, source)
        return CloseResult{Cursor{source, Closed{}}, result}
    case Cursor{source, _}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, Closed{}}, Done{Unit{}}})
