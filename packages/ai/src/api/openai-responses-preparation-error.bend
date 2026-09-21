import Base
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-request.bend as Request
import ./openai-responses-shared.bend as Shared
import ./openai-responses-assistant.bend as Assistant
import ./openai-responses-auth.bend as Auth
import ./constrained-sampling.bend as Sampling
import ../utils/model-api.bend as Api
import ../../../runtime/src/json-parse.bend as Json

# Native parse causes remain available in the typed result. Diagnostics name
# the cause without reproducing a JavaScript engine's exception wording.
def json(cause: Json.Error) -> String:
  match cause:
    case Json.InvalidValue{}: "invalid value"
    case Json.InvalidEscape{}: "invalid escape"
    case Json.UnescapedControl{}: "unescaped control character"
    case Json.UnterminatedString{}: "unterminated string"
    case Json.UnexpectedToken{}: "unexpected token"
    case Json.UnexpectedEnd{}: "unexpected end"
    case Json.TrailingInput{}: "trailing input"
    case Json.InputLimit{}: "input limit exceeded"

def assistant(cause: Assistant.Error) -> String:
  match cause:
    case Assistant.InvalidReasoningSignature{why}: "Invalid reasoning signature JSON: " ++ json(why)
    case Assistant.InvalidGrammarInput{why}: Sampling.errorMessage(why)
    case Assistant.InvalidArguments{}: "Tool call arguments cannot be represented as JSON"

def message(cause: Shared.MessageError) -> String:
  match cause:
    case Shared.AssistantConversion{why}: assistant(why)
    case Shared.ToolConversion{why}: Sampling.errorMessage(why)

def payload(cause: Request.BuildError) -> String:
  match cause:
    case Request.MessageConversion{why}: message(why)
    case Request.ToolConversion{why}: Sampling.errorMessage(why)

def format(cause: Preparation.Error) -> String:
  match cause:
    case Preparation.UnsupportedApi{api}: "OpenAI Responses provider does not support API: " ++ Api.name(api)
    case Preparation.CredentialFailure{why}: Auth.errorMessage(why)
    case Preparation.GrammarFailure{why}: Sampling.errorMessage(why)
    case Preparation.PayloadFailure{why}: payload(why)
