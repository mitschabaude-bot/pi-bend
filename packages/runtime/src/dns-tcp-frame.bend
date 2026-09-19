import Base

# TCP segmentation is independent of DNS messages. This layer frames arbitrary
# octets; the DNS message parser validates the payload (including empty frames).
type Reader is Data:
  Prefix{}
  LengthLow{high: U32}
  Payload{remaining: U32, reversed: List<&2, U32>}

type Error is Data:
  InvalidByte{value: U32}
  TooLong{}
  IncompleteFrame{}

type ReadResult is Data:
  More{reader: Reader}
  Frame{bytes: List<&2, U32>, rest: List<&2, U32>}
  Failed{error: Error}

def new() -> Reader: Prefix{}

def length(value: U32) -> ReadResult:
  match value:
    case 0: Frame{Nil{}, Nil{}}
    case count: More{Payload{count, Nil{}}}

def consume(reader: Reader, byte: U32) -> ReadResult:
  match reader:
    case Prefix{}: More{LengthLow{byte}}
    case LengthLow{high}: length((high * 256 + byte : U32))
    case Payload{1, reversed}: Frame{List.reverse(&2, U32, byte <> reversed), Nil{}}
    case Payload{remaining, reversed}: More{Payload{(remaining - 1 : U32), byte <> reversed}}

def checked(valid: Bool, reader: Reader, byte: U32) -> ReadResult:
  match valid:
    case False{}: Failed{InvalidByte{byte}}
    case True{}: consume(reader, byte)

def feed(input: List<&2, U32>, state: ReadResult) -> ReadResult:
  match input state:
    case rest Frame{bytes, _}: Frame{bytes, rest}
    case _ Failed{error}: Failed{error}
    case Nil{} More{reader}: More{reader}
    case +byte <> rest More{reader}: feed(rest, checked(U32.is_le(byte, 255), reader, byte))

# Return at most one frame and the unread suffix, so the caller can process
# messages with backpressure rather than accumulating an unbounded event list.
def read(reader: Reader, input: List<&2, U32>) -> ReadResult:
  feed(input, More{reader})

def finish(reader: Reader) -> Result<&2, &2, Error, Unit>:
  match reader:
    case Prefix{}: Done{Unit{}}
    case _: Fail{IncompleteFrame{}}

def countByte(valid: Bool, value: U32, count: U32) -> Result<&2, &2, Error, U32>:
  match valid:
    case False{}: Fail{InvalidByte{value}}
    case True{}: Done{(count + 1 : U32)}

def increment(count: U32, +value: U32) -> Result<&2, &2, Error, U32>:
  match count:
    case 65535: Fail{TooLong{}}
    case size: countByte(U32.is_le(value, 255), value, size)

def count(bytes: List<&2, U32>, result: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, U32>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case byte <> rest Done{size}: count(rest, increment(size, byte))

def encoded(bytes: List<&2, U32>, size: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match size:
    case Fail{error}: Fail{error}
    case Done{+byteCount}: Done{(byteCount / 256 : U32) <> (byteCount % 256 : U32) <> bytes}

# Prefix and payload form one buffer for the socket writer. The caller owns
# DNS message validity and chooses when to pipeline another framed message.
def encode(+bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  encoded(bytes, count(bytes, Done{0}))
