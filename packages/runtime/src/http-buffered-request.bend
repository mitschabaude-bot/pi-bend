import Base
import ./headers.bend as Headers
import ./http-buffered-body.bend as Body
import ./http-buffered-framing.bend as Framing
import ./http-request-head.bend as Head

type Prepared is Data:
  Prepared{head: Head.Head, body: Framing.Prepared}

type RequestError is Data:
  BodyError{error: Body.BodyError}
  FramingError{error: Framing.FramingError}
  HeadError{error: Head.HeadError}

def headed(body: Framing.Prepared, value: Result<&2, &2, Head.HeadError, Head.Head>) -> Result<&2, &2, RequestError, Prepared>:
  match value:
    case Fail{error}: Fail{HeadError{error}}
    case Done{head}: Done{Prepared{head, body}}

def framed(target: String, value: Result<&2, &2, Framing.FramingError, Framing.Prepared>) -> Result<&2, &2, RequestError, Prepared>:
  match value:
    case Fail{error}: Fail{FramingError{error}}
    case Done{Framing.Prepared{Body.Prepared{+method, +headers, +content}, +encoding}}:
      headed(Framing.Prepared{Body.Prepared{method, headers, content}, encoding}, Head.encode(method, target, Headers.entries(headers)))

def prepared(target: String, value: Result<&2, &2, Body.BodyError, Body.Prepared>) -> Result<&2, &2, RequestError, Prepared>:
  match value:
    case Fail{error}: Fail{BodyError{error}}
    case Done{body}: framed(target, Framing.prepare(body))

# Pure preparation can run before opening a connection. The caller supplies
# an encoded origin-form target and endpoint/default headers, including Host.
def prepare(method: String, target: String, headers: Headers.Headers, body: Body.Input) -> Result<&2, &2, RequestError, Prepared>:
  prepared(target, Body.prepare(method, headers, body))
