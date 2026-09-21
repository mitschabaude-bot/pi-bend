import Base
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ./openai-responses-terminal.bend as Terminal
import ./openai-responses-preparation-error.bend as Preparation
import ./constrained-sampling.bend as Sampling
import ./openai-sse-reader.bend as SSE
import ./openai-sse-json.bend as Dispatch
import ./openai-http-error.bend as HTTP
import ../utils/schema-json.bend as Convert
import ../utils/error-body.bend as Body
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/json-decode.bend as Decode
import ../../../runtime/src/json-string.bend as StringJSON

# Formatting is separate from typed causes and retry decisions. A malformed
# diagnostic value remains a typed formatting failure, never a made-up message.
def Formatted() -> Data: Result<&2, &2, Body.NormalizationError, String>

def encoded(value: Maybe<&2, String>) -> Formatted():
  match value:
    case None{}: Fail{Body.NonJsonBody{}}
    case Some{SNil{}}: Done{"(no status code or body)"}
    case Some{SCon{head, tail}}: Done{SCon{head, tail}}

# Streaming API errors have no HTTP failure status, even though their body was
# delivered over HTTP 200. Reuse the established native message-field policy.
def api(value: V.Value) -> Formatted():
  encoded(HTTP.detail(HTTP.JSONDiagnostic{Convert.toJson(value)}))

def dispatch(error: Dispatch.Error) -> Formatted():
  match error:
    case Dispatch.InvalidJson{cause, _, _, _}: Done{"Invalid SSE JSON: " ++ Preparation.json(cause)}
    case Dispatch.ApiErrorPayload{value}: api(value)

# Bracketed quoted field names preserve literal keys containing dots, quotes
# or brackets. Array indices remain visibly distinct from numeric field names.
def segments(path: List<&2, Decode.Segment>) -> String:
  match path:
    case Nil{}: ""
    case Decode.Field{name} <> rest: "[" ++ StringJSON.quote(name) ++ "]" ++ segments(rest)
    case Decode.Index{index} <> rest: "[" ++ Nat.show(index) ++ "]" ++ segments(rest)

def protocol(error: Decode.Error) -> String:
  match error:
    case Decode.MissingField{path}: "Invalid Responses event at $" ++ segments(path) ++ ": missing field"
    case Decode.WrongType{path, expected}: "Invalid Responses event at $" ++ segments(path) ++ ": expected " ++ expected
    case Decode.InvalidValue{path, expected}: "Invalid Responses event at $" ++ segments(path) ++ ": invalid value; expected " ++ expected

def streaming(-E: Data, render: E -> Formatted(), error: SSE.Error<E>) -> Formatted():
  match error:
    case SSE.TransportFailure{cause}: render(cause)
    case SSE.DiagnosticFailure{cause}: render(cause)
    case SSE.DispatchFailure{cause}: dispatch(cause)

def reader(-E: Data, render: E -> Formatted(), error: Reader.Error<E>) -> Formatted():
  match error:
    case Reader.StreamingFailure{cause}: streaming(E, render, cause)
    case Reader.ProtocolFailure{cause}: Done{protocol(cause)}

def processing(-E: Data, render: E -> Formatted(), error: Stream.Error<E>) -> Formatted():
  match error:
    case Stream.ReadFailure{cause}: render(cause)
    case Stream.EmitFailure{cause}: render(cause)
    case Stream.ResolveServiceTierFailure{cause}: render(cause)
    case Stream.ApplyServiceTierPricingFailure{cause}: render(cause)
    case Stream.ContentFailure{cause}: Done{Sampling.errorMessage(cause)}
    case Stream.TerminalFailure{cause}: Done{Terminal.errorMessage(cause)}
