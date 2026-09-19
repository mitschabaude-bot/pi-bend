import Base
import ./http-buffered-body.bend as Body
import ./headers.bend as Headers
import ./http-header.bend as H
import ./big-nat.bend as N
import ./http-chunked-upload.bend as Chunked

type Encoding is Data:
  Plain{}
  Chunked{}

type Prepared is Data:
  Prepared{request: Body.Prepared, encoding: Encoding}

type Selection is Data:
  Selection{length: Maybe<&2, N.BigNat>, encoding: Encoding}

type FramingError is Data:
  InvalidLength{}
  LengthMismatch{actual: N.BigNat, declared: N.BigNat}
  UnsupportedTransferEncoding{}
  HeaderError{error: H.HeaderError}

# These method spellings have payload semantics in the installed transport.
# Common methods were already normalized by buffered-body preparation.
def expectsPayload(method: String) -> Bool:
  match method:
    case "POST": True{}
    case "PUT": True{}
    case "PATCH": True{}
    case "QUERY": True{}
    case "PROPFIND": True{}
    case "PROPPATCH": True{}
    case _: False{}

def parsed(value: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>:
  match value:
    case None{}: Fail{InvalidLength{}}
    case Some{length}: Done{Some{length}}

def declared(value: Result<&2, &2, H.HeaderError, Maybe<&2, String>>) -> Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>:
  match value:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{None{}}: Done{None{}}
    case Done{Some{text}}: parsed(N.fromDecimal(text))

def zeroLength(payload: Bool) -> Selection:
  match payload:
    case True{}: Selection{Some{N.zero()}, Plain{}}
    case False{}: Selection{None{}, Plain{}}

def wireLength(method: String, +length: N.BigNat) -> Selection:
  Bool.pick(Selection, N.isZero(length), zeroLength(expectsPayload(method)), Selection{Some{length}, Plain{}})

def matching(matches: Bool, fallbackChunked: Bool, method: String, actual: N.BigNat, supplied: N.BigNat) -> Result<&2, &2, FramingError, Selection>:
  match matches fallbackChunked:
    case True{} _: Done{wireLength(method, actual)}
    case False{} True{}: Done{Selection{None{}, Chunked{}}}
    case False{} False{}: Fail{LengthMismatch{actual, supplied}}

def present(+method: String, +length: N.BigNat, supplied: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Selection>:
  match supplied:
    case None{}: Done{wireLength(method, length)}
    case Some{+value}: matching(N.equal(length, value), N.isZero(value) && Bool.not(expectsPayload(method)), method, length, value)

def selected(method: String, content: Maybe<&2, Body.Content>, supplied: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Selection>:
  match content:
    case None{}: Done{zeroLength(expectsPayload(method))}
    case Some{Body.Content{_, length}}: present(method, length, supplied)

def updated(method: String, content: Maybe<&2, Body.Content>, encoding: Encoding, headers: Result<&2, &2, H.HeaderError, Headers.Headers>) -> Result<&2, &2, FramingError, Prepared>:
  match headers:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{fields}: Done{Prepared{Body.Prepared{method, fields, content}, encoding}}

def chunked(method: String, content: Maybe<&2, Body.Content>, result: Result<&2, &2, H.HeaderError, Headers.Headers>) -> Result<&2, &2, FramingError, Prepared>:
  match result:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{headers}: updated(method, content, Chunked{}, Headers.set(headers, "transfer-encoding", "chunked"))

def canonical(method: String, headers: Headers.Headers, content: Maybe<&2, Body.Content>, length: Result<&2, &2, FramingError, Selection>) -> Result<&2, &2, FramingError, Prepared>:
  match length:
    case Fail{error}: Fail{error}
    case Done{Selection{_, Chunked{}}}: chunked(method, content, Headers.delete(headers, "content-length"))
    case Done{Selection{None{}, Plain{}}}: updated(method, content, Plain{}, Headers.delete(headers, "content-length"))
    case Done{Selection{Some{value}, Plain{}}}: updated(method, content, Plain{}, Headers.set(headers, "content-length", N.toDecimal(value)))

def lengths(request: Body.Prepared, value: Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>) -> Result<&2, &2, FramingError, Prepared>:
  match request value:
    case _ Fail{error}: Fail{error}
    case Body.Prepared{+method, headers, +content} Done{supplied}: canonical(method, headers, content, selected(method, content, supplied))

def transfer(request: Body.Prepared, provided: Result<&2, &2, H.HeaderError, Bool>) -> Result<&2, &2, FramingError, Prepared>:
  match request provided:
    case _ Fail{error}: Fail{HeaderError{error}}
    case _ Done{True{}}: Fail{UnsupportedTransferEncoding{}}
    case Body.Prepared{method, +headers, content} Done{False{}}: lengths(Body.Prepared{method, headers, content}, declared(Headers.get(headers, "content-length")))

# A supplied zero length can select chunked framing for methods without
# payload semantics, matching the transport. The encoding is explicit so the
# sender cannot mistake entity bytes for an already framed chunked body.
# Validate a supplied length even with absent content; the transport then
# canonicalizes absent-body framing independently of its numeric value.
def prepare(request: Body.Prepared) -> Result<&2, &2, FramingError, Prepared>:
  match request:
    case Body.Prepared{method, +headers, content}: transfer(Body.Prepared{method, headers, content}, Headers.has(headers, "transfer-encoding"))

# Produce the selected wire representation. Entity content and length remain
# available in Prepared for retries and request metadata.
def wireContent(content: Maybe<&2, Body.Content>, encoding: Encoding) -> List<&2, U32>:
  match content encoding:
    case None{} _: Nil{}
    case Some{Body.Content{bytes, _}} Plain{}: bytes
    case Some{value} Chunked{}: Chunked.encode(value)

def wireBody(prepared: Prepared) -> List<&2, U32>:
  match prepared:
    case Prepared{Body.Prepared{_, _, content}, encoding}: wireContent(content, encoding)
