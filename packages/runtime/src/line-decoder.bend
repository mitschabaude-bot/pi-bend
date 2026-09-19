import Base
import ./utf8.bend as Utf8

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

def line(reversed: List<&2, U32>) -> String:
  Utf8.decodeBytes(List.reverse(&2, U32, reversed))

def afterNewline(before: List<&2, U32>, after: List<&2, U32>) -> Decoded:
  match after:
    case Nil{}: Decoded{create(), line(before) <> Nil{}}
    case head <> tail: Decoded{create(), line(before) <> line(head <> tail) <> Nil{}}

# A CR stays pending until the next newline, even if ordinary bytes arrive.
# This preserves the SDK's emission timing for CR, CRLF and CR-text-LF.
def consume(decoder: LineDecoder, byte: U32) -> Decoded:
  match decoder byte:
    case LineDecoder{Reading{reversed}} 10: Decoded{create(), line(reversed) <> Nil{}}
    case LineDecoder{Reading{reversed}} 13: Decoded{LineDecoder{AfterCarriageReturn{reversed, Nil{}}}, Nil{}}
    case LineDecoder{Reading{reversed}} byte: Decoded{LineDecoder{Reading{byte <> reversed}}, Nil{}}
    case LineDecoder{AfterCarriageReturn{before, after}} 10: afterNewline(before, after)
    case LineDecoder{AfterCarriageReturn{before, after}} 13: Decoded{LineDecoder{AfterCarriageReturn{after, Nil{}}}, line(before) <> Nil{}}
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
