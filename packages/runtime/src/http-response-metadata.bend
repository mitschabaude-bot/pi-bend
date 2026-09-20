import Base
import ./http-head.bend as Head
import ./http-status.bend as Status
import ./http-header.bend as Header
import ./headers.bend as Headers

type Metadata is Data:
  Metadata{head: Head.ResponseHead, fields: Headers.Headers, exposeBody: Bool}

# Received fields are already validated. Preserve their bytes/append order;
# caller-input normalization must not trim a received value a second time.
def appendFields(fields: List<&2, Header.Header>, initial: Headers.Headers) -> Headers.Headers:
  match fields:
    case Nil{}: initial
    case first <> rest: appendFields(rest, Headers.appendField(initial, first))

def fromHead(head: Head.ResponseHead, exposeBody: Bool) -> Metadata:
  match head:
    case Head.ResponseHead{line, +fields}: Metadata{Head.ResponseHead{line, fields}, appendFields(fields, Headers.new()), exposeBody}

def original(value: Metadata) -> Head.ResponseHead:
  match value:
    case Metadata{head, _, _}: head

def headers(value: Metadata) -> Headers.Headers:
  match value:
    case Metadata{_, fields, _}: fields

def bodyPresent(value: Metadata) -> Bool:
  match value:
    case Metadata{_, _, expose}: expose

def status(value: Metadata) -> U32:
  match value:
    case Metadata{Head.ResponseHead{Status.StatusLine{_, _, code, _}, _}, _, _}: code

def statusText(value: Metadata) -> String:
  match value:
    case Metadata{Head.ResponseHead{line, _}, _, _}: Status.statusText(line)

def successful(+code: U32) -> Bool:
  U32.is_ge(code, 200) && U32.is_lt(code, 300)

def ok(value: Metadata) -> Bool:
  successful(status(value))
