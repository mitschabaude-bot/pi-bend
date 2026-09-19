import Base
import ./u64.bend as W

# Pure chunk transform for a body whose framing policy selected Content-Length.
# The retained state is only a counter; previously emitted bytes are not kept.
type Reader is Data:
  Reader{remaining: W.U64}

type BodyError is Data:
  InvalidByte{value: U32}
  IncompleteBody{remaining: W.U64}

type ReadResult is Data:
  More{reader: Reader, bytes: List<&2, U32>}
  Complete{bytes: List<&2, U32>, rest: List<&2, U32>}
  Failed{error: BodyError}

type Buffer is Data:
  Buffer{remaining: W.U64, reversed: List<&2, U32>}

def new(length: W.U64) -> Reader: Reader{length}

def isComplete(reader: Reader) -> Bool:
  match reader:
    case Reader{remaining}: W.equal(remaining, W.zero())

def accepted(valid: Bool, remaining: W.U64, reversed: List<&2, U32>, byte: U32) -> Result<&2, &2, BodyError, Buffer>:
  match valid:
    case False{}: Fail{InvalidByte{byte}}
    case True{}: Done{Buffer{W.subtract(remaining, W.one()), byte <> reversed}}

def collect(bytes: List<&2, U32>, result: Result<&2, &2, BodyError, Buffer>) -> ReadResult:
  match bytes result:
    case _ Fail{error}: Failed{error}
    case rest Done{Buffer{W.U64{0, 0}, reversed}}: Complete{List.reverse(&2, U32, reversed), rest}
    case Nil{} Done{Buffer{remaining, reversed}}: More{Reader{remaining}, List.reverse(&2, U32, reversed)}
    case +byte <> rest Done{Buffer{remaining, reversed}}:
      collect(rest, accepted(U32.is_le(byte, 255), remaining, reversed, byte))

def read(reader: Reader, bytes: List<&2, U32>) -> ReadResult:
  match reader:
    case Reader{remaining}: collect(bytes, Done{Buffer{remaining, Nil{}}})

def finish(reader: Reader) -> Result<&2, &2, BodyError, Unit>:
  match reader:
    case Reader{W.U64{0, 0}}: Done{Unit{}}
    case Reader{remaining}: Fail{IncompleteBody{remaining}}
