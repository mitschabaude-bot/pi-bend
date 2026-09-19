import Base
import ./u64.bend as W
import ./http-fixed-body.bend as Fixed
import ./http-chunked-body.bend as Chunked
import ./http-header.bend as H

# Framing selection belongs to the response policy, not the decoder. Explicit
# clean EOF ends UntilClose; socket failures must be propagated as failures.
type Framing is Data:
  NoBody{}
  ContentLength{length: W.U64}
  ChunkedEncoding{}
  UntilClose{}

type Reader is Data:
  Empty{}
  FixedReader{reader: Fixed.Reader}
  ChunkedReader{reader: Chunked.Reader}
  CloseReader{}

type BodyError is Data:
  FixedError{error: Fixed.BodyError}
  ChunkedError{error: Chunked.BodyError}
  InvalidByte{value: U32}

type ReadResult is Data:
  More{reader: Reader, bytes: List<&2, U32>}
  Complete{bytes: List<&2, U32>, trailers: List<&2, H.Header>, rest: List<&2, U32>}
  Failed{error: BodyError, bytes: List<&2, U32>}

def new(framing: Framing, limits: Chunked.Limits) -> Reader:
  match framing:
    case NoBody{}: Empty{}
    case ContentLength{length}: FixedReader{Fixed.new(length)}
    case ChunkedEncoding{}: ChunkedReader{Chunked.new(limits)}
    case UntilClose{}: CloseReader{}

def fixed(result: Fixed.ReadResult) -> ReadResult:
  match result:
    case Fixed.More{reader, bytes}: More{FixedReader{reader}, bytes}
    case Fixed.Complete{bytes, rest}: Complete{bytes, Nil{}, rest}
    case Fixed.Failed{error}: Failed{FixedError{error}, Nil{}}

def chunked(result: Chunked.ReadResult) -> ReadResult:
  match result:
    case Chunked.More{reader, bytes}: More{ChunkedReader{reader}, bytes}
    case Chunked.Complete{bytes, trailers, rest}: Complete{bytes, trailers, rest}
    case Chunked.Failed{error, bytes}: Failed{ChunkedError{error}, bytes}

def invalidByte(bytes: List<&2, U32>) -> Maybe<&2, U32>:
  match bytes:
    case Nil{}: None{}
    case +byte <> rest: Bool.pick(Maybe<&2, U32>, U32.is_le(byte, 255), invalidByte(rest), Some{byte})

def closeBytes(invalid: Maybe<&2, U32>, bytes: List<&2, U32>) -> ReadResult:
  match invalid:
    case None{}: More{CloseReader{}, bytes}
    case Some{byte}: Failed{InvalidByte{byte}, Nil{}}

def read(reader: Reader, +bytes: List<&2, U32>) -> ReadResult:
  match reader:
    case Empty{}: Complete{Nil{}, Nil{}, bytes}
    case FixedReader{state}: fixed(Fixed.read(state, bytes))
    case ChunkedReader{state}: chunked(Chunked.read(state, bytes))
    case CloseReader{}: closeBytes(invalidByte(bytes), bytes)

def fixedEOF(result: Result<&2, &2, Fixed.BodyError, Unit>) -> Result<&2, &2, BodyError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{FixedError{error}}

def chunkedEOF(result: Result<&2, &2, Chunked.BodyError, Unit>) -> Result<&2, &2, BodyError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{ChunkedError{error}}

def finish(reader: Reader) -> Result<&2, &2, BodyError, Unit>:
  match reader:
    case Empty{}: Done{Unit{}}
    case CloseReader{}: Done{Unit{}}
    case FixedReader{state}: fixedEOF(Fixed.finish(state))
    case ChunkedReader{state}: chunkedEOF(Chunked.finish(state))
