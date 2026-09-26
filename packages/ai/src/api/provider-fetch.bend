import Base
import ../types.bend as T
import ../utils/headers.bend as HeaderUtils
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-exchange.bend as Exchange
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/sse.bend as SSE
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8

# The WHATWG fetch surface used directly by the providers that call
# `fetch` themselves (pi-messages, mistral-conversations, openrouter-images):
# one POST through the caller's fetch, the response's status, statusText and
# headers, `response.text()` and `response.body.getReader()` over raw chunks.

def Transport(-Reason: Data) -> Type: Fetch.Transport(Reason)
def ReadError(-Reason: Data) -> Data: Response.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>
def Body(-Reason: Data) -> Type: Response.Body<Transport(Reason)>
def ExchangeError(-Reason: Data) -> Data: Exchange.ReadError<Deadline.Cause<Reason>>

type Request is Data:
  Request{url: URL.URL, headers: Headers.Headers, body: String}

def post(~Reason: Data, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason), request: Request) -> IO(Fetch.Result_(Reason)):
  match request:
    case Request{url, headers, body}: C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, "POST", headers, Headers.Text{body}, signal})

# The status and headers handed to onResponse (upstream headersToRecord).
def providerResponse(+metadata: Response.Metadata) -> T.ProviderResponse:
  T.ProviderResponse{F.fromU32(Response.metadataStatus(metadata)), HeaderUtils.headersToRecord(Response.headers(metadata))}

def layered(result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, name: String, value: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{headers}: Headers.set(headers, name, value)

# `new Headers(init)` from ordered name/value pairs.
def headersFrom(entries: List<&2, R.Property<String>>, result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match entries:
    case Nil{}: result
    case R.Property{name, value} <> rest: headersFrom(rest, layered(result, name, value))

def headerList(entries: List<&2, R.Property<String>>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  headersFrom(entries, Done{Headers.new()})

# Header overrides where null deletes (upstream applyXHeaderOverrides).
def overridden(result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, overrides: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{current}: HeaderUtils.apply(current, overrides)

# Spread overrides where null values are dropped first (upstream
# `...providerHeadersToRecord(headers)`).
def spreadRecord(result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, record: Maybe<&2, R.Record<String>>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match record:
    case None{}: result
    case Some{R.Record{entries}}: headersFrom(entries, result)

def spread(result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, overrides: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  spreadRecord(result, HeaderUtils.providerHeadersToRecord(overrides))

# response.text(): the whole body, decoded as UTF-8, under a byte budget.
def responseText(~Reason: Data, limit: Nat, body: Body(Reason)) -> IO(Result<&2, &2, Response.TextError<Exchange.ReadError<Deadline.Cause<Reason>>>, String>):
  Exchange.text(~(Deadline.Cause<Reason>), limit, body)

def identity(-Reason: Data, value: ReadError(Reason)) -> ReadError(Reason): value

# response.body.getReader(): an owner that retires the transport and a
# source whose reads return raw chunks until None at the end of the body.
def Owner(-Reason: Data) -> Type: Response.Owner<Transport(Reason), ReadError(Reason)>
def Source(-Reason: Data) -> Data: SSE.Source<ReadError(Reason)>

def reader(~Reason: Data, body: Body(Reason)) -> IO(Owner(Reason) & Source(Reason)):
  do IO<Owner(Reason) & Source(Reason)>:
    owner : Owner(Reason) <- Exchange.responseSource(~(Deadline.Cause<Reason>), ~ReadError(Reason), ~identity(Reason), body)
    return Response.borrow(Transport(Reason), ReadError(Reason), owner)

def chunkBytes(chunk: SSE.Chunk) -> List<&2, U32>:
  match chunk:
    case SSE.Bytes{bytes}: bytes
    case SSE.Text{value}: Utf8.encode(value)
    case SSE.EmptyChunk{}: Nil{}

def chunkResult(-Reason: Data, result: Result<&2, &2, ReadError(Reason), Maybe<&2, SSE.Chunk>>) -> Result<&2, &2, ReadError(Reason), Maybe<&2, List<&2, U32>>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{None{}}: Done{None{}}
    case Done{Some{chunk}}: Done{Some{chunkBytes(chunk)}}

def read(~Reason: Data, source: Source(Reason)) -> IO(Result<&2, &2, ReadError(Reason), Maybe<&2, List<&2, U32>>>):
  do IO<Result<&2, &2, ReadError(Reason), Maybe<&2, List<&2, U32>>>>:
    result : Result<&2, &2, ReadError(Reason), Maybe<&2, SSE.Chunk>> <- SSE.read(ReadError(Reason), source)
    return chunkResult(Reason, result)

def release(~Reason: Data, owner: Owner(Reason)) -> IO(Unit):
  do IO<Unit>:
    released : Result<&2, &2, ReadError(Reason), Unit> <- Response.dispose(Transport(Reason), ReadError(Reason), owner)
    return Unit{}
