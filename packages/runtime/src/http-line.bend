import Base

# Incremental octet-level CRLF framing. HTTP syntax validation belongs to the
# status/header parsers; this reader neither decodes UTF-8 nor folds lines.
# The bound counts payload bytes, excluding the terminating CRLF.
type Reader is Data:
  Reader{reversed: List<&2, U32>, remaining: Nat, carriageReturn: Bool}

type ReadError is Data:
  LineTooLong{}
  InvalidByte{value: U32}
  IncompleteLine{}

type ReadResult is Data:
  More{reader: Reader}
  Line{bytes: List<&2, U32>, rest: List<&2, U32>}
  Failed{error: ReadError}

def new(limit: Nat) -> Reader: Reader{Nil{}, limit, False{}}

def buffered(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> ReadResult:
  match remaining:
    case Zero{}: Failed{LineTooLong{}}
    case Succ{capacity}: More{Reader{byte <> reversed, capacity, False{}}}

def ordinary(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> ReadResult:
  match byte:
    case 13: More{Reader{reversed, remaining, True{}}}
    case other: buffered(reversed, remaining, other)

# A pending CR is payload only once the following byte is known not to be LF.
# This lets an exactly-full line terminate across two separate chunks.
def afterCarriageReturn(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> ReadResult:
  match remaining:
    case Zero{}: Failed{LineTooLong{}}
    case Succ{capacity}: ordinary(13 <> reversed, capacity, byte)

def accepted(reader: Reader, byte: U32) -> ReadResult:
  match reader byte:
    case Reader{reversed, _, True{}} 10: Line{List.reverse(&2, U32, reversed), Nil{}}
    case Reader{reversed, remaining, True{}} other: afterCarriageReturn(reversed, remaining, other)
    case Reader{reversed, remaining, False{}} other: ordinary(reversed, remaining, other)

def checked(valid: Bool, reader: Reader, byte: U32) -> ReadResult:
  match valid:
    case False{}: Failed{InvalidByte{byte}}
    case True{}: accepted(reader, byte)

def consume(reader: Reader, +byte: U32) -> ReadResult:
  checked(U32.is_le(byte, 255), reader, byte)

def feed(bytes: List<&2, U32>, result: ReadResult) -> ReadResult:
  match bytes result:
    case rest Line{line, _}: Line{line, rest}
    case _ Failed{error}: Failed{error}
    case Nil{} More{reader}: More{reader}
    case head <> tail More{reader}: feed(tail, consume(reader, head))

def read(reader: Reader, bytes: List<&2, U32>) -> ReadResult:
  feed(bytes, More{reader})

def finish(reader: Reader) -> ReadResult: Failed{IncompleteLine{}}
