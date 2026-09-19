import Base
import ./http-body.bend as Body
import ./http-header.bend as H
import ./http-content-length.bend as Length
import ./u64.bend as W

type Transfer is Data:
  NoTransferEncoding{}
  ChunkedTransfer{}
  OtherTransfer{}

type Fields is Data:
  Fields{length: Maybe<&2, W.U64>, transfer: Transfer}

type FieldError is Data:
  LengthError{error: Length.LengthError}
  ConflictingFraming{}

def last(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case value <> Nil{}: value
    case _ <> rest: last(rest)

def spaces(text: String) -> String:
  match text:
    case SCon{' ', rest}: spaces(rest)
    case other: other

# This classifies the installed Fetch parser's wire framing. It is not a
# generic transfer-coding grammar or a compression decoder.
def classify(value: String) -> Transfer:
  token = H.lowercase(String.reverse(spaces(String.reverse(H.trimLeading(last(String.split(value, ',')))))))
  Bool.pick(Transfer, String.eq(token, "chunked"), ChunkedTransfer{}, OtherTransfer{})

def transferValue(previous: Transfer, value: String) -> Transfer:
  match value:
    case SNil{}: previous
    case other: classify(other)

def receivedTransfer(state: Fields, value: String) -> Result<&2, &2, FieldError, Fields>:
  match state:
    case Fields{Some{_}, _}: Fail{ConflictingFraming{}}
    case Fields{None{}, previous}: Done{Fields{None{}, transferValue(previous, H.trimLeading(value))}}

def parsedLength(result: Result<&2, &2, Length.LengthError, Maybe<&2, W.U64>>) -> Result<&2, &2, FieldError, Fields>:
  match result:
    case Fail{error}: Fail{LengthError{error}}
    case Done{value}: Done{Fields{value, NoTransferEncoding{}}}

def receivedLength(state: Fields, value: String) -> Result<&2, &2, FieldError, Fields>:
  match state:
    case Fields{previous, NoTransferEncoding{}}: parsedLength(Length.observed(previous, value))
    case _: Fail{ConflictingFraming{}}

def field(name: String, value: String, state: Fields) -> Result<&2, &2, FieldError, Fields>:
  match name:
    case "content-length": receivedLength(state, value)
    case "transfer-encoding": receivedTransfer(state, value)
    case _: Done{state}

def collect(fields: List<&2, H.Header>, state: Result<&2, &2, FieldError, Fields>) -> Result<&2, &2, FieldError, Fields>:
  match fields state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{result}: Done{result}
    case H.Header{name, value} <> rest Done{result}: collect(rest, field(H.lowercase(name), value, result))

# Consume validated received fields, before they are coalesced for public use.
def analyze(fields: List<&2, H.Header>) -> Result<&2, &2, FieldError, Fields>:
  collect(fields, Done{Fields{None{}, NoTransferEncoding{}}})

# Use only after method/status policy determines that this response carries a
# payload. HEAD, informational, upgrade and null-body decisions are separate.
def bodyFraming(fields: Fields) -> Body.Framing:
  match fields:
    case Fields{_, ChunkedTransfer{}}: Body.ChunkedEncoding{}
    case Fields{Some{size}, NoTransferEncoding{}}: Body.ContentLength{size}
    case _: Body.UntilClose{}
