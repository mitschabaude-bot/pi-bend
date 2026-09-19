import Base
import ./line-decoder.bend as Lines
import ./utf8.bend as Utf8

# Framing used by openai 6.40.0 iterSSEChunks (licenses/openai-sdk.txt).
# Keep bytes intact until CRCR, LFLF or CRLFCRLF, including across input chunks.
type ChunkDecoder is Data:
  ChunkDecoder{prefix: Lines.BoundaryPrefix, reversed: List<&2, U32>}

type Decoded is Data:
  Decoded{decoder: ChunkDecoder, chunks: List<&2, List<&2, U32>>}

def create() -> ChunkDecoder:
  ChunkDecoder{Lines.EmptyPrefix{}, Nil{}}

def advance(step: Lines.BoundaryStep, reversed: List<&2, U32>) -> Decoded:
  match step:
    case Lines.Found{}: Decoded{create(), List.reverse(&2, U32, reversed) <> Nil{}}
    case Lines.Continue{prefix}: Decoded{ChunkDecoder{prefix, reversed}, Nil{}}

def consume(decoder: ChunkDecoder, +byte: U32) -> Decoded:
  match decoder:
    case ChunkDecoder{prefix, reversed}: advance(Lines.boundaryStep(prefix, byte), byte <> reversed)

def prepend(chunks: List<&2, List<&2, U32>>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match chunks:
    case Nil{}: reversed
    case head <> tail: prepend(tail, head <> reversed)

def collect(bytes: List<&2, U32>, result: Decoded, reversed: List<&2, List<&2, U32>>) -> Decoded:
  match bytes result:
    case Nil{} Decoded{decoder, chunks}: Decoded{decoder, List.reverse(&2, List<&2, U32>, prepend(chunks, reversed))}
    case head <> tail Decoded{decoder, chunks}: collect(tail, consume(decoder, head), prepend(chunks, reversed))

def decode(decoder: ChunkDecoder, bytes: List<&2, U32>) -> Decoded:
  collect(bytes, Decoded{decoder, Nil{}}, Nil{})

def decodeText(decoder: ChunkDecoder, text: String) -> Decoded:
  decode(decoder, Utf8.encode(text))

def decodeOptional(decoder: ChunkDecoder, bytes: Maybe<&2, List<&2, U32>>) -> Decoded:
  match bytes:
    case None{}: Decoded{decoder, Nil{}}
    case Some{chunk}: decode(decoder, chunk)

def finish(decoder: ChunkDecoder) -> Decoded:
  match decoder:
    case ChunkDecoder{_, Nil{}}: Decoded{create(), Nil{}}
    case ChunkDecoder{_, head <> tail}: Decoded{create(), List.reverse(&2, U32, head <> tail) <> Nil{}}
