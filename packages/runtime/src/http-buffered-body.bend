import Base
import ./http-request-method.bend as Method
import ./http-header.bend as H
import ./headers.bend as Headers
import ./utf8.bend as UTF8
import ./big-nat.bend as N

# Buffered request inputs. Streaming uploads, form data and blob ownership
# have different lifetimes and are not represented by this value type.
type Input is Data:
  Absent{}
  Text{text: String}
  Bytes{bytes: List<&2, U32>}

type Content is Data:
  Content{bytes: List<&2, U32>, length: N.BigNat}

type Prepared is Data:
  Prepared{method: String, headers: Headers.Headers, content: Maybe<&2, Content>}

type BodyError is Data:
  MethodError{error: Method.MethodError}
  BodyNotAllowed{}
  InvalidByte{value: U32}
  HeaderError{error: H.HeaderError}

def countedByte(valid: Bool, byte: U32, length: N.BigNat) -> Result<&2, &2, BodyError, N.BigNat>:
  match valid:
    case False{}: Fail{InvalidByte{byte}}
    case True{}: Done{N.add(length, N.one())}

def counted(bytes: List<&2, U32>, result: Result<&2, &2, BodyError, N.BigNat>) -> Result<&2, &2, BodyError, N.BigNat>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{length}: Done{length}
    case +byte <> rest Done{length}: counted(rest, countedByte(U32.is_le(byte, 255), byte, length))

def withLength(method: String, headers: Headers.Headers, bytes: List<&2, U32>, length: Result<&2, &2, BodyError, N.BigNat>) -> Result<&2, &2, BodyError, Prepared>:
  match length:
    case Fail{error}: Fail{error}
    case Done{size}: Done{Prepared{method, headers, Some{Content{bytes, size}}}}

def buffered(method: String, headers: Headers.Headers, +bytes: List<&2, U32>) -> Result<&2, &2, BodyError, Prepared>:
  withLength(method, headers, bytes, counted(bytes, Done{N.zero()}))

def textHeaders(method: String, headers: Result<&2, &2, H.HeaderError, Headers.Headers>, text: String) -> Result<&2, &2, BodyError, Prepared>:
  match headers:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{fields}: buffered(method, fields, UTF8.encode(text))

def textType(method: String, headers: Headers.Headers, text: String, existing: Result<&2, &2, H.HeaderError, Bool>) -> Result<&2, &2, BodyError, Prepared>:
  match existing:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{True{}}: buffered(method, headers, UTF8.encode(text))
    case Done{False{}}: textHeaders(method, Headers.set(headers, "content-type", "text/plain;charset=UTF-8"), text)

def body(method: String, +headers: Headers.Headers, input: Input) -> Result<&2, &2, BodyError, Prepared>:
  match input:
    case Absent{}: Done{Prepared{method, headers, None{}}}
    case Bytes{bytes}: buffered(method, headers, bytes)
    case Text{text}: textType(method, headers, text, Headers.has(headers, "content-type"))

def permitted(method: String, headers: Headers.Headers, input: Input, disallowed: Bool) -> Result<&2, &2, BodyError, Prepared>:
  match input disallowed:
    case Absent{} _: Done{Prepared{method, headers, None{}}}
    case _ True{}: Fail{BodyNotAllowed{}}
    case value False{}: body(method, headers, value)

def normalized(method: Result<&2, &2, Method.MethodError, String>, headers: Headers.Headers, input: Input) -> Result<&2, &2, BodyError, Prepared>:
  match method:
    case Fail{error}: Fail{MethodError{error}}
    case Done{+name}: permitted(name, headers, input, String.eq(name, "GET") || String.eq(name, "HEAD"))

# Empty text/bytes are present bodies, so GET/HEAD reject them too. Keep absent
# content distinct from a zero-length body; wire framing is a later step.
def prepare(method: String, headers: Headers.Headers, input: Input) -> Result<&2, &2, BodyError, Prepared>:
  normalized(Method.normalize(method), headers, input)
