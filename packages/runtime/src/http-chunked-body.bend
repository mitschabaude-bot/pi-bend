import Base
import ./u64.bend as W
import ./http-line.bend as Line
import ./http-chunk-size.bend as Size
import ./http-field.bend as Field
import ./http-header.bend as H

type Limits is Data:
  Limits{sizeLineBytes: Nat, trailerLineBytes: Nat, trailerBytes: Nat, trailerFields: Nat}

type Phase is Data:
  SizeLine{line: Line.Reader}
  Payload{remaining: W.U64}
  PayloadCR{}
  PayloadLF{}
  Trailers{line: Line.Reader, remainingBytes: Nat, remainingFields: Nat, reversed: List<&2, H.Header>}
  Ended{trailers: List<&2, H.Header>}

type Reader is Data:
  Reader{phase: Phase, limits: Limits}

type BodyError is Data:
  InvalidByte{value: U32}
  LineError{error: Line.ReadError}
  SizeError{error: Size.SizeError}
  TrailerError{error: Field.FieldError}
  InvalidDelimiter{}
  TrailerTooLong{}
  TooManyTrailers{}
  IncompleteBody{}

type ReadResult is Data:
  More{reader: Reader, bytes: List<&2, U32>}
  Complete{bytes: List<&2, U32>, trailers: List<&2, H.Header>, rest: List<&2, U32>}
  Failed{error: BodyError, bytes: List<&2, U32>}

# A single-byte state transition, separate from per-call output accumulation.
type Emission is Data:
  Emission{reader: Reader, byte: Maybe<&2, U32>}

def sizeReader(limits: Limits) -> Line.Reader:
  match limits:
    case Limits{size, _, _, _}: Line.new(size)

def new(+limits: Limits) -> Reader: Reader{SizeLine{sizeReader(limits)}, limits}

def silent(phase: Phase, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  Done{Emission{Reader{phase, limits}, None{}}}

def startTrailers(+limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match limits:
    case Limits{_, line, bytes, fields}: silent(Trailers{Line.new(line), bytes, fields, Nil{}}, limits)

def parsedSize(result: Result<&2, &2, Size.SizeError, W.U64>, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match result:
    case Fail{error}: Fail{SizeError{error}}
    case Done{W.U64{0, 0}}: startTrailers(limits)
    case Done{size}: silent(Payload{size}, limits)

def sizeLine(result: Line.ReadResult, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match result:
    case Line.Failed{error}: Fail{LineError{error}}
    case Line.More{line}: silent(SizeLine{line}, limits)
    case Line.Line{bytes, _}: parsedSize(Size.parse(bytes), limits)

def afterPayload(remaining: W.U64) -> Phase:
  match remaining:
    case W.U64{0, 0}: PayloadCR{}
    case other: Payload{other}

def delimiter(valid: Bool, next: Phase, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match valid:
    case False{}: Fail{InvalidDelimiter{}}
    case True{}: silent(next, limits)

def trailerReader(limits: Limits) -> Line.Reader:
  match limits:
    case Limits{_, line, _, _}: Line.new(line)

def addTrailer(field: H.Header, bytes: Nat, fields: Nat, reversed: List<&2, H.Header>, +limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match fields:
    case Zero{}: Fail{TooManyTrailers{}}
    case Succ{remaining}: silent(Trailers{trailerReader(limits), bytes, remaining, field <> reversed}, limits)

def parsedTrailer(result: Result<&2, &2, Field.FieldError, Field.FieldLine>, bytes: Nat, fields: Nat, reversed: List<&2, H.Header>, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match result:
    case Fail{error}: Fail{TrailerError{error}}
    case Done{Field.EndOfHeaders{}}: silent(Ended{List.reverse(&2, H.Header, reversed)}, limits)
    case Done{Field.Field{field}}: addTrailer(field, bytes, fields, reversed, limits)

def trailerLine(result: Line.ReadResult, bytes: Nat, fields: Nat, reversed: List<&2, H.Header>, limits: Limits) -> Result<&2, &2, BodyError, Emission>:
  match result:
    case Line.Failed{error}: Fail{LineError{error}}
    case Line.More{line}: silent(Trailers{line, bytes, fields, reversed}, limits)
    case Line.Line{line, _}: parsedTrailer(Field.parse(line), bytes, fields, reversed, limits)

def step(reader: Reader, byte: U32) -> Result<&2, &2, BodyError, Emission>:
  match reader:
    case Reader{SizeLine{line}, limits}: sizeLine(Line.consume(line, byte), limits)
    case Reader{Payload{remaining}, limits}:
      Done{Emission{Reader{afterPayload(W.subtract(remaining, W.one())), limits}, Some{byte}}}
    case Reader{PayloadCR{}, limits}: delimiter(U32.is_eq(byte, 13), PayloadLF{}, limits)
    case Reader{PayloadLF{}, +limits}: delimiter(U32.is_eq(byte, 10), SizeLine{sizeReader(limits)}, limits)
    case Reader{Trailers{_, Zero{}, _, _}, _}: Fail{TrailerTooLong{}}
    case Reader{Trailers{line, Succ{bytes}, fields, reversed}, limits}: trailerLine(Line.consume(line, byte), bytes, fields, reversed, limits)
    case Reader{Ended{trailers}, limits}: silent(Ended{trailers}, limits)

def checked(valid: Bool, reader: Reader, byte: U32) -> Result<&2, &2, BodyError, Emission>:
  match valid:
    case False{}: Fail{InvalidByte{byte}}
    case True{}: step(reader, byte)

type ScanState is Data:
  Running{reader: Reader, reversed: List<&2, U32>}
  Broken{error: BodyError, reversed: List<&2, U32>}

def emitted(result: Result<&2, &2, BodyError, Emission>, reversed: List<&2, U32>) -> ScanState:
  match result:
    case Fail{error}: Broken{error, reversed}
    case Done{Emission{reader, None{}}}: Running{reader, reversed}
    case Done{Emission{reader, Some{byte}}}: Running{reader, byte <> reversed}

def collect(bytes: List<&2, U32>, state: ScanState) -> ReadResult:
  match bytes state:
    case _ Broken{error, reversed}: Failed{error, List.reverse(&2, U32, reversed)}
    case rest Running{Reader{Ended{trailers}, _}, reversed}: Complete{List.reverse(&2, U32, reversed), trailers, rest}
    case Nil{} Running{reader, reversed}: More{reader, List.reverse(&2, U32, reversed)}
    case +byte <> rest Running{reader, reversed}: collect(rest, emitted(checked(U32.is_le(byte, 255), reader, byte), reversed))

def read(reader: Reader, bytes: List<&2, U32>) -> ReadResult:
  collect(bytes, Running{reader, Nil{}})

def finish(reader: Reader) -> Result<&2, &2, BodyError, Unit>:
  match reader:
    case Reader{Ended{_}, _}: Done{Unit{}}
    case _: Fail{IncompleteBody{}}
