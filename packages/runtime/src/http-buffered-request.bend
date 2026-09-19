import Base
import ./headers.bend as Headers
import ./http-buffered-body.bend as Body
import ./http-buffered-framing.bend as Framing
import ./http-request-head.bend as Head
import ./http-url.bend as HTTPURL
import ./url-record.bend as URL
import ./http-header.bend as Header

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


# Retain the typed connection endpoint alongside the fully framed request.
# Fetch derives Host from the URL, overriding any caller-supplied Host field.
type URLPrepared is Data:
  URLPrepared{endpoint: HTTPURL.Endpoint, request: Prepared}

type URLRequestError is Data:
  URLError{error: HTTPURL.Error}
  HeaderError{error: Header.HeaderError}
  PreparationError{error: RequestError}

def urlPrepared(endpoint: HTTPURL.Endpoint, result: Result<&2, &2, RequestError, Prepared>) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{PreparationError{error}}
    case Done{request}: Done{URLPrepared{endpoint, request}}

def urlHeaders(endpoint: HTTPURL.Endpoint, method: String, target: String, body: Body.Input, result: Result<&2, &2, Header.HeaderError, Headers.Headers>) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{headers}: urlPrepared(endpoint, prepare(method, target, headers, body))

def urlEndpoint(result: Result<&2, &2, HTTPURL.Error, HTTPURL.Endpoint>, method: String, headers: Headers.Headers, body: Body.Input) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{URLError{error}}
    case Done{HTTPURL.Endpoint{transport, host, port, +authority, +target}}: urlHeaders(HTTPURL.Endpoint{transport, host, port, authority, target}, method, target, body, Headers.set(headers, "host", authority))

def prepareURL(value: URL.URL, method: String, headers: Headers.Headers, body: Body.Input) -> Result<&2, &2, URLRequestError, URLPrepared>:
  urlEndpoint(HTTPURL.prepare(value), method, headers, body)
