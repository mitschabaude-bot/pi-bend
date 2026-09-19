import Base
import ./http-line.bend as Line
import ./http-status.bend as Status
import ./http-field.bend as Field
import ./http-header.bend as Header
import ./headers.bend as Headers

# Preserve ordered individual fields for later body-framing validation. A
# coalesced Headers view alone would erase duplicate framing declarations.
type ResponseHead is Data:
  ResponseHead{status: Status.StatusLine, fields: List<&2, Header.Header>}

type Phase is Data:
  ReadingStatus{}
  ReadingFields{status: Status.StatusLine, reversed: List<&2, Header.Header>}

type Budget is Data:
  Budget{lineLimit: Nat, remainingBytes: Nat, remainingFields: Nat}

type Reader is Data:
  Reader{line: Line.Reader, phase: Phase, budget: Budget}

type ReadError is Data:
  FramingError{error: Line.ReadError}
  StatusError{error: Status.SyntaxError}
  FieldError{error: Field.FieldError}
  HeadTooLong{}
  TooManyFields{}
  IncompleteHead{}

type ReadResult is Data:
  More{reader: Reader}
  Complete{head: ResponseHead, rest: List<&2, U32>}
  Failed{error: ReadError}

# Header-byte limits include status line, all delimiters and the empty line.
# Line limits exclude CRLF. Field limits count individual occurrences.
def new(+lineLimit: Nat, headLimit: Nat, fieldLimit: Nat) -> Reader:
  Reader{Line.new(lineLimit), ReadingStatus{}, Budget{lineLimit, headLimit, fieldLimit}}

def nextLine(phase: Phase, budget: Budget) -> ReadResult:
  match budget:
    case Budget{+lineLimit, bytes, fields}:
      More{Reader{Line.new(lineLimit), phase, Budget{lineLimit, bytes, fields}}}

def parsedStatus(result: Result<&2, &2, Status.SyntaxError, Status.StatusLine>, budget: Budget) -> ReadResult:
  match result:
    case Fail{error}: Failed{StatusError{error}}
    case Done{status}: nextLine(ReadingFields{status, Nil{}}, budget)

def addField(status: Status.StatusLine, reversed: List<&2, Header.Header>, field: Header.Header, budget: Budget) -> ReadResult:
  match budget:
    case Budget{_, _, Zero{}}: Failed{TooManyFields{}}
    case Budget{limit, bytes, Succ{fields}}:
      nextLine(ReadingFields{status, field <> reversed}, Budget{limit, bytes, fields})

def parsedField(result: Result<&2, &2, Field.FieldError, Field.FieldLine>, status: Status.StatusLine, reversed: List<&2, Header.Header>, budget: Budget) -> ReadResult:
  match result:
    case Fail{error}: Failed{FieldError{error}}
    case Done{Field.EndOfHeaders{}}: Complete{ResponseHead{status, List.reverse(&2, Header.Header, reversed)}, Nil{}}
    case Done{Field.Field{field}}: addField(status, reversed, field, budget)

def completedLine(bytes: List<&2, U32>, phase: Phase, budget: Budget) -> ReadResult:
  match phase:
    case ReadingStatus{}: parsedStatus(Status.parse(bytes), budget)
    case ReadingFields{status, reversed}: parsedField(Field.parse(bytes), status, reversed, budget)

def framed(result: Line.ReadResult, phase: Phase, budget: Budget) -> ReadResult:
  match result:
    case Line.Failed{error}: Failed{FramingError{error}}
    case Line.More{reader}: More{Reader{reader, phase, budget}}
    case Line.Line{bytes, _}: completedLine(bytes, phase, budget)

def consume(reader: Reader, byte: U32) -> ReadResult:
  match reader:
    case Reader{_, _, Budget{_, Zero{}, _}}: Failed{HeadTooLong{}}
    case Reader{line, phase, Budget{limit, Succ{remaining}, fields}}:
      framed(Line.consume(line, byte), phase, Budget{limit, remaining, fields})

def feed(bytes: List<&2, U32>, result: ReadResult) -> ReadResult:
  match bytes result:
    case rest Complete{head, _}: Complete{head, rest}
    case _ Failed{error}: Failed{error}
    case Nil{} More{reader}: More{reader}
    case byte <> rest More{reader}: feed(rest, consume(reader, byte))

def read(reader: Reader, bytes: List<&2, U32>) -> ReadResult:
  feed(bytes, More{reader})

def finish(reader: Reader) -> ReadResult: Failed{IncompleteHead{}}

def collect(fields: List<&2, Header.Header>, headers: Headers.Headers) -> Headers.Headers:
  match fields:
    case Nil{}: headers
    case field <> rest: collect(rest, Headers.appendField(headers, field))

def headers(head: ResponseHead) -> Headers.Headers:
  match head:
    case ResponseHead{_, fields}: collect(fields, Headers.new())
