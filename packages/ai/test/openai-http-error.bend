import Base
import ../src/api/openai-client.bend as Client
import ../src/types.bend as T
import ../src/utils/json.bend as JSON
import ../src/utils/error-body.bend as Body
import ../src/api/openai-client.bend as Provider
import ../../runtime/src/http-response-metadata.bend as Metadata
import ../../runtime/src/http-head.bend as Head
import ../../runtime/src/http-status.bend as Status
import ../../runtime/src/http-header.bend as Header
import ../../runtime/src/http-body-consume.bend as Consume
import ../../runtime/src/http-body-buffer.bend as Buffer
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as Text

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some:" ++ Text.showText(text)

def json(value: Maybe<&2, T.JsonValue>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: optional(JSON.stringify(value))

def name(value: Client.ErrorKind) -> String:
  match value:
    case Client.BadRequestError{}: "BadRequestError"
    case Client.AuthenticationError{}: "AuthenticationError"
    case Client.PermissionDeniedError{}: "PermissionDeniedError"
    case Client.NotFoundError{}: "NotFoundError"
    case Client.ConflictError{}: "ConflictError"
    case Client.UnprocessableEntityError{}: "UnprocessableEntityError"
    case Client.RateLimitError{}: "RateLimitError"
    case Client.InternalServerError{}: "InternalServerError"
    case Client.GenericAPIError{}: "APIError"

def formatted(value: Result<&2, &2, Body.NormalizationError, String>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "normalization failed")
    case Done{text}: IO.print("format:" ++ Text.showText(text))

def shown(provider: String, +value: Client.APIError) -> IO(Unit):
  match value:
    case Client.APIError{_, _, message}:
      do IO<Unit>:
        IO.print("kind:" ++ name(Client.kind(value)))
        IO.print("status:" ++ U32.show(Client.status(value)))
        IO.print("request-id:" ++ optional(Client.requestID(value)))
        IO.print("code:" ++ json(Client.code(value)))
        IO.print("param:" ++ json(Client.param(value)))
        IO.print("type:" ++ json(Client.errorType(value)))
        IO.print("message:" ++ Text.showText(message))
        formatted(Client.format(value, provider))

def constructed(provider: String, value: Result<&2, &2, Client.ConstructionError<String>, Client.APIError>) -> IO(Unit):
  match value:
    case Done{value}: shown(provider, value)
    case Fail{Client.DiagnosticReadFailure{metadata, Consume.BodyFailure{Buffer.PrimaryFailure{Buffer.ByteLimitExceeded{}}}}}: IO.print("read-limit:" ++ U32.show(Metadata.status(metadata)))
    case Fail{Client.DiagnosticEncodingFailure{metadata, Client.TextDiagnostic{text}}}:
      IO.print("encoding:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Text.showText(text))
    case Fail{_}: IO.die(Unit, 1, "unexpected construction error")

def run(provider: String, mode: String, metadata: Metadata.Metadata, raw: String) -> IO(Unit):
  match mode:
    case "truncate": IO.print("truncated:" ++ Text.showText(Body.truncateErrorText(raw, U32.to_nat(Metadata.status(metadata)))))
    case "read": constructed(provider, Client.fromResponse(String, Provider.StatusFailure{metadata, Fail{Consume.BodyFailure{Buffer.PrimaryFailure{Buffer.ByteLimitExceeded{}}}}}))
    case "encoding": constructed(provider, Client.constructed(String, metadata, Client.TextDiagnostic{raw}, None{}))
    case _: constructed(provider, Client.fromResponse(String, Provider.StatusFailure{metadata, Done{raw}}))

def headers(id: String) -> List<&2, Header.Header>:
  match id:
    case "-": Nil{}
    case value: Header.Header{"x-request-id", value} <> Nil{}

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case code <> provider <> id <> mode <> raw <> rest:
      do IO<Unit>:
        IO.print("case")
        run(provider, mode, Metadata.fromHead(Head.ResponseHead{Status.StatusLine{1, 1, Text.decimal(code, 0), Nil{}}, headers(id)}, True{}), raw)
        cases(rest)
    case _: IO.die(Unit, 1, "expected status provider request-id mode body groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
