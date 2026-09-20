import Base
import ../types.bend as T
import ../utils/error-body.bend as Body
import ../utils/json.bend as JSON
import ../utils/schema-json.bend as Convert
import ../utils/provider-http-response.bend as Provider
import ../utils/provider-retry.bend as Retry
import ../../../runtime/src/json-parse.bend as Parse
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/http-body-consume.bend as Consume
import ../../../runtime/src/http-response-metadata.bend as Metadata
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/f64.bend as F

# Native data replaces SDK Error subclasses and reflective field probing.
# JSON diagnostic values remain ordinary immutable trees, not JS objects.
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
    case Headers.Headers{fields}: Headers.joined(name, Record.get(List<&2, String>, fields, name))

def requestID(value: APIError) -> Maybe<&2, String>:
  match value:
    case APIError{metadata, _, _}: header("x-request-id", Metadata.headers(metadata))

def jsonField(name: String, value: T.JsonValue) -> Maybe<&2, T.JsonValue>:
  match value:
    case T.JsonObject{fields}: Record.get(T.JsonValue, fields, name)
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

def parsed(raw: String, value: Result<&2, &2, Parse.Error, V.Value>) -> Diagnostic:
  match value:
    case Fail{_}: TextDiagnostic{raw}
    case Done{value}: JSONDiagnostic{unwrap(Convert.toJson(value))}

def decode(+raw: String) -> Diagnostic:
  parsed(raw, Parse.parse(raw))

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

def fromResponse(-E: Data, value: Provider.Failure<E>) -> Result<&2, &2, ConstructionError<E>, APIError>:
  match value:
    case Provider.StatusFailure{metadata, Fail{cause}}: Fail{DiagnosticReadFailure{metadata, cause}}
    case Provider.StatusFailure{metadata, Done{text}}: create(E, metadata, decode(text))

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

# The same immutable APIError is retained by the canonical retry result.
def retryFailure(value: APIError) -> Retry.RequestFailure<APIError>:
  match value:
    case APIError{+metadata, diagnostic, +message}: Provider.retryFailure(APIError, APIError{metadata, diagnostic, message}, message, metadata)
