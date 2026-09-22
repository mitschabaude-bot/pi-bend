import Base
import ../types.bend as T
import ../utils/json.bend as JSON
import ../utils/json-finite.bend as Finite
import ../utils/schema-json.bend as Convert
import ../utils/error-body.bend as Body
import ../utils/provider-headers.bend as Configuration
import ../utils/provider-header-state.bend as State
import ../utils/provider-http-response.bend as HTTP
import ../utils/provider-retry.bend as Retry
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64-decimal.bend as Decimal
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/http-header.bend as H
import ../../../runtime/src/http-fetch-scope.bend as Scope
import ../../../runtime/src/http-exchange-response.bend as Head
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-stream.bend as Stream
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/http-response-metadata.bend as Metadata
import ../../../runtime/src/http-body-consume.bend as Consume
import ../../../runtime/src/json-parse.bend as Parse
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/timer-milliseconds.bend as Duration
import ../../../runtime/src/url-absolute.bend as Absolute
import ../../../runtime/src/url-record.bend as URL
import ../../../runtime/src/url-form.bend as Form
import ../../../runtime/src/url-form-strict.bend as Strict
import ../../../runtime/src/url-query-encode.bend as Encode

# The request side of the OpenAI SDK client (openai 6.40.0), as used by pi
# with retries disabled: header assembly, the fixed Responses resource URL,
# request serialization, timeouts, APIError construction and the retry
# classification of one attempt. Streaming lives in openai-sse.bend.

def State(-Reason: Data) -> Type: Scope.State<Reason, Fetch.Transport(Reason)>
def ReadError(-Reason: Data) -> Data: Exchange.ReadError<Deadline.Cause<Reason>>

# Headers
# -------

# Runtime identity/platform fields are supplied by the native client.
type Defaults is Data:
  Defaults{userAgent: String, platform: R.Record<String>, organization: Maybe<&2, String>, project: Maybe<&2, String>}

type HeaderError is Data:
  TimeoutNotInteger{value: F.F64}
  TimeoutNegative{value: F.F64}
  TimeoutEncodingFailure{value: F.F64}
  HeaderFailure{cause: H.HeaderError}
  MissingAuthentication{}

def nullable(value: Maybe<&2, String>) -> T.Nullable<String>:
  match value:
    case None{}: T.NullValue{}
    case Some{text}: T.PresentValue{text}

def effectiveTimeout(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: F.fromU32(600000)
    case Some{milliseconds}: milliseconds

def negative(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{LT{}}: True{}
    case _: False{}

def checkedTimeout(+value: F.F64, integral: Bool) -> Result<&2, &2, HeaderError, F.F64>:
  match integral:
    case False{}: Fail{TimeoutNotInteger{value}}
    case True{}: Bool.pick(Result<&2, &2, HeaderError, F.F64>, negative(F.compare(value, F.fromU32(0))), Fail{TimeoutNegative{value}}, Done{value})

def validateTimeout(+value: F.F64) -> Result<&2, &2, HeaderError, F.F64>:
  checkedTimeout(value, F.isInteger(value))

def encodedTimeout(value: F.F64, encoded: Maybe<&2, String>) -> Result<&2, &2, HeaderError, Maybe<&2, String>>:
  match encoded:
    case None{}: Fail{TimeoutEncodingFailure{value}}
    case Some{text}: Done{Some{text}}

# X-Stainless-Timeout carries whole seconds; a zero timeout sends no header.
def timeoutField(+value: F.F64, ordering: Maybe<&2, Cmp>) -> Result<&2, &2, HeaderError, Maybe<&2, String>>:
  match ordering:
    case Some{EQ{}}: Done{None{}}
    case _: encodedTimeout(value, Decimal.toDecimal(F.truncate(F.divide(value, F.fromU32(1000)))))

def timeoutHeader(original: Maybe<&2, F.F64>) -> Result<&2, &2, HeaderError, Maybe<&2, String>>:
  match original:
    case None{}: Done{None{}}
    case Some{+value}: timeoutField(value, F.compare(value, F.fromU32(0)))

def optionalTimeout(fields: T.ProviderHeaders(), value: Maybe<&2, String>) -> T.ProviderHeaders():
  match value:
    case None{}: fields
    case Some{text}: R.set(T.Nullable<String>, fields, "X-Stainless-Timeout", T.PresentValue{text})

def defaultHeaders(configuration: Defaults, retryCount: Nat, timeout: Maybe<&2, String>) -> T.ProviderHeaders():
  match configuration:
    case Defaults{userAgent, platform, organization, project}:
      base = {R.Record{R.Property{"Accept", T.PresentValue{"application/json"}} <> R.Property{"User-Agent", T.PresentValue{userAgent}} <> R.Property{"X-Stainless-Retry-Count", T.PresentValue{Nat.show(retryCount)}} <> Nil{}} : T.ProviderHeaders()}
      decorated = Configuration.overlayStrings(optionalTimeout(base, timeout), Some{platform})
      R.set(T.Nullable<String>, R.set(T.Nullable<String>, decorated, "OpenAI-Organization", nullable(organization)), "OpenAI-Project", nullable(project))

def authorization(apiKey: String) -> T.ProviderHeaders():
  R.Record{R.Property{"Authorization", T.PresentValue{"Bearer " ++ apiKey}} <> Nil{}}

def credentialAllows(+value: Maybe<&2, T.Nullable<String>>) -> Bool:
  State.nonempty(value) || State.removed(value)

def authenticationAllowed(authorization: Maybe<&2, T.Nullable<String>>, apiKey: Maybe<&2, T.Nullable<String>>) -> Bool:
  credentialAllows(authorization) || credentialAllows(apiKey)

def authenticated(+state: State.State) -> Bool:
  authenticationAllowed(State.lookup(state, "authorization"), State.lookup(state, "api-key"))

def authenticate(state: State.State, accepted: Bool) -> Result<&2, &2, HeaderError, Headers.Headers>:
  match accepted:
    case False{}: Fail{MissingAuthentication{}}
    case True{}: Done{State.headers(state)}

def assembled(result: Result<&2, &2, H.HeaderError, State.State>) -> Result<&2, &2, HeaderError, Headers.Headers>:
  match result:
    case Fail{cause}: Fail{HeaderFailure{cause}}
    case Done{+state}: authenticate(state, authenticated(state))

def layered(configuration: Defaults, apiKey: String, retryCount: Nat, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>, timeout: Result<&2, &2, HeaderError, Maybe<&2, String>>) -> Result<&2, &2, HeaderError, Headers.Headers>:
  match timeout:
    case Fail{cause}: Fail{cause}
    case Done{value}: assembled(State.build(Some{defaultHeaders(configuration, retryCount, value)} <> Some{authorization(apiKey)} <> client <> body <> request <> Nil{}))

def validated(configuration: Defaults, apiKey: String, retryCount: Nat, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>, timeout: Result<&2, &2, HeaderError, F.F64>) -> Result<&2, &2, HeaderError, Headers.Headers>:
  match timeout:
    case Fail{cause}: Fail{cause}
    case Done{+value}: layered(configuration, apiKey, retryCount, client, body, request, timeoutField(value, F.compare(value, F.fromU32(0))))

# SDK request order: defaults/platform, credentials, client defaults, serializer
# headers, per-request overrides, then authentication validation. Pi disables
# SDK retries, so its adapter supplies retryCount = 0.
def buildHeaders(configuration: Defaults, apiKey: String, retryCount: Nat, timeout: Maybe<&2, F.F64>, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, HeaderError, Headers.Headers>:
  validated(configuration, apiKey, retryCount, client, body, request, validateTimeout(effectiveTimeout(timeout)))

# URL
# ---

type URLError is Data:
  InvalidURL{cause: Absolute.Error}
  InvalidQuery{cause: Strict.Error}

# Responses uses a fixed SDK resource path, not general relative resolution.
def suffix(base: String, reversed: String) -> String:
  match reversed:
    case SCon{'/', _}: base ++ "responses"
    case _: base ++ "/responses"

def address(+base: String) -> String: suffix(base, String.reverse(base))

# The SDK's query dictionary retains the last value of a repeated name.
def collect(tuples: List<&2, Form.Entry>, fields: R.Record<String>) -> R.Record<String>:
  match tuples:
    case Nil{}: fields
    case Form.Entry{name, value} <> rest: collect(rest, R.set(String, fields, name, value))

def encoded(properties: List<&2, R.Property<String>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (Encode.encode(name) ++ "=" ++ Encode.encode(value)) <> encoded(rest)

def serializeQuery(fields: R.Record<String>) -> String:
  String.join(encoded(R.entries(String, fields)), "&")

def withQuery(url: URL.URL, query: Maybe<&2, String>) -> URL.URL:
  match url:
    case URL.URL{scheme, username, password, host, port, path, _, fragment}: URL.URL{scheme, username, password, host, port, path, query, fragment}

def normalizedQuery(url: URL.URL, parsed: Result<&2, &2, Strict.Error, List<&2, Form.Entry>>) -> Result<&2, &2, URLError, URL.URL>:
  match parsed:
    case Fail{cause}: Fail{InvalidQuery{cause}}
    case Done{Nil{}}: Done{url}
    case Done{tuples}: Done{withQuery(url, Some{serializeQuery(collect(tuples, R.new(String)))})}

def queried(url: URL.URL, query: Maybe<&2, String>) -> Result<&2, &2, URLError, URL.URL>:
  match query:
    case None{}: Done{url}
    case Some{text}: normalizedQuery(url, Strict.parse(text))

def parsedURL(result: Result<&2, &2, Absolute.Error, URL.URL>) -> Result<&2, &2, URLError, URL.URL>:
  match result:
    case Fail{cause}: Fail{InvalidURL{cause}}
    case Done{URL.URL{scheme, username, password, host, port, path, +query, fragment}}:
      queried(URL.URL{scheme, username, password, host, port, path, query, fragment}, query)

# The URL parser receives its immutable Unicode/IDNA tables from the caller.
def responsesURL(context: Absolute.Context, base: String) -> Result<&2, &2, URLError, URL.URL>:
  parsedURL(Absolute.parse(context, address(base)))

# Requests
# --------

# An immutable, unframed request works with either custom fetch or native HTTP.
type Request is Data:
  Request{url: URL.URL, method: String, headers: Headers.Headers, body: String, timeout: F.F64}

type RequestError is Data:
  URLFailure{cause: URLError}
  HeaderRejected{cause: HeaderError}
  NonFinitePayload{}
  PayloadEncodingFailure{}

def bodyHeaders() -> T.ProviderHeaders():
  R.Record{R.Property{"content-type", T.PresentValue{"application/json"}} <> Nil{}}

def encoding(result: Maybe<&2, String>) -> Result<&2, &2, RequestError, String>:
  match result:
    case None{}: Fail{PayloadEncodingFailure{}}
    case Some{text}: Done{text}

def encodedPayload(payload: T.JsonValue, valid: Bool) -> Result<&2, &2, RequestError, String>:
  match valid:
    case False{}: Fail{NonFinitePayload{}}
    case True{}: encoding(JSON.stringify(payload))

def serialize(+payload: T.JsonValue) -> Result<&2, &2, RequestError, String>:
  encodedPayload(payload, Finite.valid(payload))

def completed(url: URL.URL, body: String, timeout: F.F64, headers: Result<&2, &2, HeaderError, Headers.Headers>) -> Result<&2, &2, RequestError, Request>:
  match headers:
    case Fail{cause}: Fail{HeaderRejected{cause}}
    case Done{fields}: Done{Request{url, "post", fields, body, timeout}}

def serialized(configuration: Defaults, apiKey: String, client: T.ProviderHeaders(), url: URL.URL, timeout: F.F64, original: Maybe<&2, F.F64>, body: Result<&2, &2, RequestError, String>) -> Result<&2, &2, RequestError, Request>:
  match body:
    case Fail{cause}: Fail{cause}
    case Done{text}: completed(url, text, timeout, layered(configuration, apiKey, 0n, Some{client}, Some{bodyHeaders()}, None{}, timeoutHeader(original)))

def timed(configuration: Defaults, apiKey: String, client: T.ProviderHeaders(), url: URL.URL, payload: T.JsonValue, original: Maybe<&2, F.F64>, timeout: Result<&2, &2, HeaderError, F.F64>) -> Result<&2, &2, RequestError, Request>:
  match timeout:
    case Fail{cause}: Fail{HeaderRejected{cause}}
    case Done{value}: serialized(configuration, apiKey, client, url, value, original, serialize(payload))

def addressed(configuration: Defaults, apiKey: String, client: T.ProviderHeaders(), +timeout: Maybe<&2, F.F64>, payload: T.JsonValue, url: Result<&2, &2, URLError, URL.URL>) -> Result<&2, &2, RequestError, Request>:
  match url:
    case Fail{cause}: Fail{URLFailure{cause}}
    case Done{value}: timed(configuration, apiKey, client, value, payload, timeout, validateTimeout(effectiveTimeout(timeout)))

# SDK preparation order is URL, timeout, body, headers. The payload is the
# hook-selected one; this layer neither invokes nor retries hooks.
def prepareRequest(context: Absolute.Context, configuration: Defaults, apiKey: String, client: T.ProviderHeaders(), baseUrl: String, timeout: Maybe<&2, F.F64>, payload: T.JsonValue) -> Result<&2, &2, RequestError, Request>:
  addressed(configuration, apiKey, client, timeout, payload, responsesURL(context, baseUrl))

# APIError
# --------

# Native data replaces SDK Error subclasses and reflective field probing.
type Diagnostic is Data:
  TextDiagnostic{text: String}
  JSONDiagnostic{value: T.JsonValue}

type APIError is Data:
  APIError{metadata: Metadata.Metadata, diagnostic: Diagnostic, message: String}

type ErrorKind is Data:
  BadRequestError{}
  AuthenticationError{}
  PermissionDeniedError{}
  NotFoundError{}
  ConflictError{}
  UnprocessableEntityError{}
  RateLimitError{}
  InternalServerError{}
  GenericAPIError{}

type ConstructionError<-E: Data> is Data:
  DiagnosticReadFailure{metadata: Metadata.Metadata, cause: Consume.TextError<E>}
  DiagnosticEncodingFailure{metadata: Metadata.Metadata, diagnostic: Diagnostic}

def statusKind(status: U32) -> ErrorKind:
  match status:
    case 400: BadRequestError{}
    case 401: AuthenticationError{}
    case 403: PermissionDeniedError{}
    case 404: NotFoundError{}
    case 409: ConflictError{}
    case 422: UnprocessableEntityError{}
    case 429: RateLimitError{}
    case value: Bool.pick(ErrorKind, U32.is_ge(value, 500), InternalServerError{}, GenericAPIError{})

def kind(value: APIError) -> ErrorKind:
  match value:
    case APIError{metadata, _, _}: statusKind(Metadata.status(metadata))

def status(value: APIError) -> U32:
  match value:
    case APIError{metadata, _, _}: Metadata.status(metadata)

def header(+name: String, headers: Headers.Headers) -> Maybe<&2, String>:
  match headers:
    case Headers.Headers{fields}: Headers.joined(name, R.get(List<&2, String>, fields, name))

def requestID(value: APIError) -> Maybe<&2, String>:
  match value:
    case APIError{metadata, _, _}: header("x-request-id", Metadata.headers(metadata))

def jsonField(name: String, value: T.JsonValue) -> Maybe<&2, T.JsonValue>:
  match value:
    case T.JsonObject{fields}: R.get(T.JsonValue, fields, name)
    case _: None{}

def field(name: String, value: APIError) -> Maybe<&2, T.JsonValue>:
  match value:
    case APIError{_, JSONDiagnostic{value}, _}: jsonField(name, value)
    case _: None{}

def code(value: APIError) -> Maybe<&2, T.JsonValue>: field("code", value)
def param(value: APIError) -> Maybe<&2, T.JsonValue>: field("param", value)
def errorType(value: APIError) -> Maybe<&2, T.JsonValue>: field("type", value)

# An ordinary OpenAI envelope selects its error. Unrecognized JSON keeps its
# complete diagnostic instead of silently becoming "status code (no body)".
def selected(fallback: T.JsonValue, value: Maybe<&2, T.JsonValue>) -> T.JsonValue:
  match value:
    case None{}: fallback
    case Some{value}: value

def unwrap(+value: T.JsonValue) -> T.JsonValue:
  selected(value, jsonField("error", value))

def parsedDiagnostic(raw: String, value: Result<&2, &2, Parse.Error, V.Value>) -> Diagnostic:
  match value:
    case Fail{_}: TextDiagnostic{raw}
    case Done{value}: JSONDiagnostic{unwrap(Convert.toJson(value))}

def decode(+raw: String) -> Diagnostic:
  parsedDiagnostic(raw, Parse.parse(raw))

# Empty/null messages fall back to the diagnostic. Other JSON messages are
# serialized explicitly, including false and zero; no truthiness coercion.
def jsonMessage(whole: T.JsonValue, message: Maybe<&2, T.JsonValue>) -> Maybe<&2, String>:
  match message:
    case Some{T.JsonString{SCon{head, tail}}}: Some{SCon{head, tail}}
    case Some{T.JsonString{SNil{}}}: JSON.stringify(whole)
    case Some{T.JsonNull{}}: JSON.stringify(whole)
    case Some{value}: JSON.stringify(value)
    case None{}: JSON.stringify(whole)

def detail(value: Diagnostic) -> Maybe<&2, String>:
  match value:
    case TextDiagnostic{text}: Some{text}
    case JSONDiagnostic{+value}: jsonMessage(value, jsonField("message", value))

def statusMessage(status: U32, text: String) -> String:
  match text:
    case SNil{}: U32.show(status) ++ " status code (no body)"
    case SCon{head, tail}: U32.show(status) ++ " " ++ SCon{head, tail}

def constructed(-E: Data, +metadata: Metadata.Metadata, diagnostic: Diagnostic, text: Maybe<&2, String>) -> Result<&2, &2, ConstructionError<E>, APIError>:
  match text:
    case None{}: Fail{DiagnosticEncodingFailure{metadata, diagnostic}}
    case Some{text}: Done{APIError{metadata, diagnostic, statusMessage(Metadata.status(metadata), text)}}

def create(-E: Data, metadata: Metadata.Metadata, +diagnostic: Diagnostic) -> Result<&2, &2, ConstructionError<E>, APIError>:
  constructed(E, metadata, diagnostic, detail(diagnostic))

def fromResponse(-E: Data, value: HTTP.Failure<E>) -> Result<&2, &2, ConstructionError<E>, APIError>:
  match value:
    case HTTP.StatusFailure{metadata, Fail{cause}}: Fail{DiagnosticReadFailure{metadata, cause}}
    case HTTP.StatusFailure{metadata, Done{text}}: create(E, metadata, decode(text))

# The SDK puts plain text only in its message; exposing it again as a body
# would change pi's truncation and message-preservation behavior.
def bodies(value: Diagnostic) -> List<&2, Body.Body>:
  match value:
    case TextDiagnostic{_}: Nil{}
    case JSONDiagnostic{value}: Body.ParsedBody{value} <> Nil{}

def providerFailure(value: APIError) -> Body.ProviderFailure:
  match value:
    case APIError{metadata, diagnostic, message}: Body.ProviderFailure{Some{F.fromU32(Metadata.status(metadata))}, message, bodies(diagnostic)}

def normalize(value: APIError) -> Result<&2, &2, Body.NormalizationError, Body.NormalizedProviderError>:
  Body.normalizeProviderError(providerFailure(value))

def prefix(provider: String) -> String:
  match provider:
    case "openai": "OpenAI API error"
    case name: name ++ " API error"

def format(value: APIError, provider: String) -> Result<&2, &2, Body.NormalizationError, String>:
  do Result<&2, &2, Body.NormalizationError, String>:
    normalized : Body.NormalizedProviderError <- normalize(value)
    Body.formatProviderError(normalized, Some{prefix(provider)})

# One attempt
# -----------

type FetchError<-Reason: Data> is Data:
  InvalidTimeout{cause: Duration.Error}
  FetchFailure{cause: Scope.Error<Reason, Fetch.Error<Reason>>}

type AttemptError<-Reason: Data> is Data:
  TransportFailure{cause: FetchError<Reason>}
  HTTPFailure{cause: APIError}
  DiagnosticFailure{cause: ConstructionError<ReadError(Reason)>}

def Outcome(-Reason: Data) -> Type: Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<State(Reason)>>

def input(-Reason: Data, request: Request, signal: Fetch.Signal(Reason)) -> Fetch.Input<Reason>:
  match request:
    case Request{url, method, headers, body, _}: Fetch.Input{url, String.to_upper(method), headers, body, signal}

def timeout(request: Request) -> Result<&2, &2, Duration.Error, U32>:
  match request:
    case Request{_, _, _, _, milliseconds}: Duration.milliseconds(milliseconds)

def connection(-E: Data, original: E, message: String) -> Retry.RequestFailure<E>:
  Retry.Provider{Retry.ProviderError{original, message, None{}, None{}, None{}, None{}}}

def categorized(-E: Data, original: E, category: Fetch.Category) -> Retry.RequestFailure<E>:
  match category:
    case Fetch.NonRetryable{}: Retry.Other{original}
    case Fetch.Connection{}: connection(E, original, "Connection error.")
    case Fetch.Timeout{}: connection(E, original, "Request timed out.")

# A request deadline is a timeout; a parent's cancellation is terminal.
def aborted(-Reason: Data, -E: Data, original: E, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> Retry.RequestFailure<E>:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: categorized(E, original, Fetch.Timeout{})
    case _: Retry.Other{original}

def dispatched(-Reason: Data, -E: Data, original: E, category: Fetch.Category, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Retry.RequestFailure<E>:
  match category reason:
    case Fetch.NonRetryable{} _: Retry.Other{original}
    case other None{}: categorized(E, original, other)
    case _ Some{why}: aborted(Reason, E, original, why)

# Configuration failures never become network retries merely because the
# transport returned them. Every original typed failure survives.
def fetchFailure(-Reason: Data, failure: FetchError<Reason>) -> Retry.RequestFailure<AttemptError<Reason>>:
  match failure:
    case InvalidTimeout{cause}: Retry.Other{TransportFailure{InvalidTimeout{cause}}}
    case FetchFailure{Scope.Aborted{+why}}: aborted(Reason, AttemptError<Reason>, TransportFailure{FetchFailure{Scope.Aborted{why}}}, why)
    case FetchFailure{Scope.DispatchFailure{+cause, +why}}: dispatched(Reason, AttemptError<Reason>, TransportFailure{FetchFailure{Scope.DispatchFailure{cause, why}}}, Fetch.classify(Reason, cause), why)

def diagnosticFailure(-Reason: Data, failure: ConstructionError<ReadError(Reason)>) -> Retry.RequestFailure<AttemptError<Reason>>:
  match failure:
    case DiagnosticReadFailure{+metadata, cause}: HTTP.retryFailure(AttemptError<Reason>, DiagnosticFailure{DiagnosticReadFailure{metadata, cause}}, "Could not read the error response diagnostic.", metadata)
    case DiagnosticEncodingFailure{+metadata, value}: HTTP.retryFailure(AttemptError<Reason>, DiagnosticFailure{DiagnosticEncodingFailure{metadata, value}}, "Could not encode the error response diagnostic.", metadata)

def constructedFailure(-Reason: Data, result: Result<&2, &2, ConstructionError<ReadError(Reason)>, APIError>) -> Retry.RequestFailure<AttemptError<Reason>>:
  match result:
    case Fail{cause}: diagnosticFailure(Reason, cause)
    case Done{APIError{+metadata, value, +message}}: HTTP.retryFailure(AttemptError<Reason>, HTTPFailure{APIError{metadata, value, message}}, message, metadata)

def accepted(-Reason: Data, result: Result<&2, &1, HTTP.Failure<ReadError(Reason)>, Response.Response<State(Reason)>>) -> Outcome(Reason):
  match result:
    case Fail{cause}: Fail{constructedFailure(Reason, fromResponse(ReadError(Reason), cause))}
    case Done{response}: Done{response}

def read(-Reason: Data, state: State(Reason)) -> IO(State(Reason) & Result<&2, &2, ReadError(Reason), Maybe<&2, Stream.Event>>):
  Scope.read(Reason, ReadError(Reason), Fetch.Transport(Reason), Head.read(Deadline.Cause<Reason>), state)

def close(-Reason: Data, state: State(Reason)) -> IO(Result<&2, &2, ReadError(Reason), Unit>):
  Scope.close(Reason, ReadError(Reason), Fetch.Transport(Reason), Exchange.close(Deadline.Cause<Reason>), state)

# Failed HTTP statuses consume and close their diagnostics before returning a
# retryable value. Successful responses transfer without reading their bodies.
def fetched(~Reason: Data, diagnosticLimit: Nat, result: Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>>) -> IO(Outcome(Reason)):
  match result:
    case Fail{cause}: IO.pure(Outcome(Reason), Fail{fetchFailure(Reason, cause)})
    case Done{response}:
      do IO<Outcome(Reason)>:
        result : Result<&2, &1, HTTP.Failure<ReadError(Reason)>, Response.Response<State(Reason)>> <- HTTP.acceptWith(~(ReadError(Reason)), ~(State(Reason)), ~(read(Reason)), ~(close(Reason)), diagnosticLimit, response)
        return accepted(Reason, result)

def scoped(-Reason: Data, result: Result<&2, &1, Scope.Error<Reason, Fetch.Error<Reason>>, Response.Response<State(Reason)>>) -> Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>>:
  match result:
    case Fail{cause}: Fail{FetchFailure{cause}}
    case Done{response}: Done{response}

def dispatch(-Reason: Data, request: Request, parent: Abort.AbortSignal<Reason>, fetch: Fetch.Fetch(Reason), duration: Result<&2, &2, Duration.Error, U32>) -> IO(Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>>):
  match duration:
    case Fail{cause}: IO.pure(Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>>, Fail{InvalidTimeout{cause}})
    case Done{milliseconds}:
      do IO<Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>>>:
        result : Result<&2, &1, Scope.Error<Reason, Fetch.Error<Reason>>, Response.Response<State(Reason)>> <- Scope.start(Reason, Fetch.Error<Reason>, Fetch.Transport(Reason), milliseconds, parent, signal => C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, input(Reason, request, signal)))
        return scoped(Reason, result)

# Exactly one HTTP attempt under the request timeout: dispatch through the
# borrowed fetch callback, then interpret the status. The caller's retry loop,
# hooks and response streaming remain composable around it.
def attempt(~Reason: Data, +request: Request, parent: Abort.AbortSignal<Reason>, fetch: Fetch.Fetch(Reason), diagnosticLimit: Nat) -> IO(Outcome(Reason)):
  do IO<Outcome(Reason)>:
    result : Result<&2, &1, FetchError<Reason>, Response.Response<State(Reason)>> <- dispatch(Reason, request, parent, fetch, timeout(request))
    fetched(~Reason, diagnosticLimit, result)

# The body is released when the caller cannot consume it, e.g. after a failed
# response hook. The scope retires transport before parent-cancellation state.
def released(-Reason: Data, value: Response.Next<ReadError(Reason), State(Reason)>) -> Result<&2, &2, Progress.Error<ReadError(Reason)>, Unit>:
  match value:
    case Response.Next{_, Done{_}}: Done{Unit{}}
    case Response.Next{_, Fail{cause}}: Fail{cause}

def release(-Reason: Data, response: Response.Response<State(Reason)>) -> IO(Result<&2, &2, Progress.Error<ReadError(Reason)>, Unit>):
  match response:
    case Response.Response{_, body}:
      do IO<Result<&2, &2, Progress.Error<ReadError(Reason)>, Unit>>:
        result : Response.Next<ReadError(Reason), State(Reason)> <- Response.closeWith(ReadError(Reason), State(Reason), close(Reason), body)
        return released(Reason, result)
