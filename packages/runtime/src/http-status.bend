import Base
import ./utf8.bend as Utf8
import ./http-line.bend as Line

# Byte-preserving HTTP/1.x status-line syntax. The transport decides supported
# versions, informational handling and which status codes can become responses.
type StatusLine is Data:
  StatusLine{major: U32, minor: U32, status: U32, reasonBytes: List<&2, U32>}

type SyntaxError is Data:
  InvalidVersion{}
  InvalidStatus{}
  InvalidReason{}

def digit(+byte: U32) -> Bool: U32.is_ge(byte, 48) && U32.is_le(byte, 57)

def reasonByte(+byte: U32) -> Bool:
  U32.is_eq(byte, 9) || (U32.is_ge(byte, 32) && U32.is_le(byte, 126)) || (U32.is_ge(byte, 128) && U32.is_le(byte, 255))

def validReason(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: reasonByte(byte) && validReason(rest)

# Node Fetch exposes UTF-8 decoded statusText; keep wire octets separately.
def statusText(line: StatusLine) -> String:
  match line:
    case StatusLine{_, _, _, bytes}: Utf8.decodeBytes(bytes)

def finishReason(valid: Bool, major: U32, minor: U32, status: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case True{}: Done{StatusLine{major, minor, status, bytes}}
    case False{}: Fail{InvalidReason{}}

def reason(major: U32, minor: U32, status: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    # Node Fetch also accepts an absent separator when the reason is empty.
    case Nil{}: Done{StatusLine{major, minor, status, Nil{}}}
    case 32 <> +rest: finishReason(validReason(rest), major, minor, status, rest)
    case _: Fail{InvalidStatus{}}

def checkedCode(valid: Bool, major: U32, minor: U32, code: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidStatus{}}
    case True{}: reason(major, minor, code, bytes)

def code(major: U32, minor: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    case +a <> +b <> +c <> rest:
      checkedCode(digit(a) && digit(b) && digit(c), major, minor, ((a - 48) * 100 + (b - 48) * 10 + c - 48 : U32), rest)
    case _: Fail{InvalidStatus{}}

def checkedVersion(valid: Bool, major: U32, minor: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidVersion{}}
    case True{}: code((major - 48 : U32), (minor - 48 : U32), bytes)

def version(bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    case +major <> 46 <> +minor <> 32 <> rest:
      checkedVersion(digit(major) && digit(minor), major, minor, rest)
    case _: Fail{InvalidVersion{}}

def prefix(expected: List<&2, U32>, bytes: List<&2, U32>) -> Bool:
  match expected bytes:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case first <> tail head <> rest: U32.is_eq(first, head) && prefix(tail, rest)

def checkedPrefix(valid: Bool, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidVersion{}}
    case True{}: version(List.drop(&2, U32, bytes, 5n))

def parse(+bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  checkedPrefix(prefix(72 <> 84 <> 84 <> 80 <> 47 <> Nil{}, bytes), bytes)

type ReadError is Data:
  FramingError{error: Line.ReadError}
  StatusError{error: SyntaxError}

type ReadResult is Data:
  More{reader: Line.Reader}
  Complete{status: StatusLine, rest: List<&2, U32>}
  Failed{error: ReadError}

def parsed(result: Result<&2, &2, SyntaxError, StatusLine>, rest: List<&2, U32>) -> ReadResult:
  match result:
    case Fail{error}: Failed{StatusError{error}}
    case Done{status}: Complete{status, rest}

def framed(result: Line.ReadResult) -> ReadResult:
  match result:
    case Line.More{reader}: More{reader}
    case Line.Failed{error}: Failed{FramingError{error}}
    case Line.Line{bytes, rest}: parsed(parse(bytes), rest)

def read(reader: Line.Reader, bytes: List<&2, U32>) -> ReadResult:
  framed(Line.read(reader, bytes))
