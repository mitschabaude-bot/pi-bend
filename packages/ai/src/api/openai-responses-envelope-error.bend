import Base
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-url.bend as Address
import ./openai-request-headers.bend as Header
import ../../../runtime/src/http-header.bend as HTTP
import ../../../runtime/src/url-form-strict.bend as Query

# Engine-independent diagnostics for native validation. Typed causes retain
# their details; messages never interpolate credentials or entire request URLs.
def field(error: HTTP.HeaderError) -> String:
  match error:
    case HTTP.InvalidName{}: "Invalid HTTP header name"
    case HTTP.InvalidValue{}: "Invalid HTTP header value"
    case HTTP.NonByteValue{}: "HTTP header value contains a non-byte character"

def header(error: Header.Error) -> String:
  match error:
    case Header.TimeoutNotInteger{_}: "timeout must be an integer"
    case Header.TimeoutNegative{_}: "timeout must be a positive integer"
    case Header.TimeoutEncodingFailure{_}: "Could not encode request timeout"
    case Header.HeaderFailure{cause}: field(cause)
    case Header.MissingAuthentication{}: "Could not resolve authentication method. Expected either apiKey or adminAPIKey to be set. Or for one of the \"Authorization\" or \"api-key\" headers to be explicitly omitted"

def query(error: Query.Error) -> String:
  match error:
    case Query.InvalidName{index}: "Invalid URL query name in field " ++ Nat.show(index)
    case Query.InvalidValue{index}: "Invalid URL query value in field " ++ Nat.show(index)

def address(error: Address.Error) -> String:
  match error:
    case Address.InvalidURL{_}: "Invalid URL"
    case Address.InvalidQuery{cause}: query(cause)

def format(error: Envelope.Error) -> String:
  match error:
    case Envelope.URLFailure{cause}: address(cause)
    case Envelope.HeaderFailure{cause}: header(cause)
    case Envelope.NonFinitePayload{}: "Request payload contains a non-finite number"
    case Envelope.PayloadEncodingFailure{}: "Could not encode request payload as JSON"
