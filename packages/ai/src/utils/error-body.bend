import Base
import ../types.bend as T
import ./json.bend as Json
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64.bend as Decimal
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/text.bend as Budget

# Provider adapters supply bodies in their documented preference order.
# Unread streams and transport-private objects are never diagnostic data.
type Body is Data:
  TextBody{text: String}
  ParsedBody{value: T.JsonValue}
  UnavailableBody{}

type ProviderFailure is Data:
  ProviderFailure{status: Maybe<&2, F64>, message: String, bodies: List<&2, Body>}

type NormalizedProviderError is Data:
  NormalizedProviderError{status: Maybe<&2, F64>, body: Maybe<&2, String>, message: String, messageCarriesBody: Bool}

type NormalizationError is Data:
  NonJsonBody{}
  NumberFormattingFailure{}

def MAX_PROVIDER_ERROR_BODY_CHARS() -> Nat: 4000n

# Preserve the upstream UTF-16 unit budget over native characters. A boundary
# never creates a lone surrogate; omitted counts the actual discarded units.
def truncated(cut: Budget.Cut) -> String:
  match cut:
    case Budget.Cut{prefix, 0n}: prefix
    case Budget.Cut{prefix, omitted}: prefix ++ "... [truncated " ++ Nat.show(omitted) ++ " chars]"

def truncateErrorText(text: String, maxChars: Nat) -> String:
  truncated(Budget.take(text, maxChars))

def trimLeading(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, +rest}: Bool.pick(String, Space.whitespace(code), trimLeading(rest), SCon{Chr{code}, rest})

def trim(text: String) -> String:
  String.reverse(trimLeading(String.reverse(trimLeading(text))))

def encodedBody(value: Maybe<&2, String>) -> Result<&2, &2, NormalizationError, Maybe<&2, String>>:
  match value:
    case None{}: Fail{NonJsonBody{}}
    case Some{text}: Done{Some{text}}

# A present text body wins even when trimming later makes it empty. Parsed
# arrays/scalars and empty objects are not usable error-body explanations.
def pickBodyText(bodies: List<&2, Body>) -> Result<&2, &2, NormalizationError, Maybe<&2, String>>:
  match bodies:
    case Nil{}: Done{None{}}
    case TextBody{text} <> _: Done{Some{text}}
    case ParsedBody{T.JsonObject{Record.Record{Nil{}}}} <> rest: pickBodyText(rest)
    case ParsedBody{T.JsonObject{fields}} <> _: encodedBody(Json.stringify(T.JsonObject{fields}))
    case _ <> rest: pickBodyText(rest)

def nonemptyBody(empty: Bool, text: String) -> Maybe<&2, String>:
  match empty:
    case True{}: None{}
    case False{}: Some{truncateErrorText(text, MAX_PROVIDER_ERROR_BODY_CHARS())}

def cleanBody(body: Maybe<&2, String>) -> Maybe<&2, String>:
  match body:
    case None{}: None{}
    case Some{text}:
      +cleaned = trim(text)
      nonemptyBody(String.is_empty(cleaned), cleaned)

def carries(message: String, body: Maybe<&2, String>) -> Bool:
  match body:
    case None{}: True{}
    case Some{text}: String.contains(message, text)

def normalizeProviderError(error: ProviderFailure) -> Result<&2, &2, NormalizationError, NormalizedProviderError>:
  match error:
    case ProviderFailure{status, +message, bodies}:
      do Result<&2, &2, NormalizationError, NormalizedProviderError>:
        selected : Maybe<&2, String> <- pickBodyText(bodies)
        +body : Maybe<&2, String> = cleanBody(selected)
        return NormalizedProviderError{status, body, message, carries(message, body)}

def displayBody(alreadyPresent: Bool, body: Maybe<&2, String>, message: String) -> String:
  match alreadyPresent body:
    case False{} Some{text}: text
    case _ _: message

def statusText(value: Maybe<&2, String>) -> Result<&2, &2, NormalizationError, String>:
  match value:
    case None{}: Fail{NumberFormattingFailure{}}
    case Some{text}: Done{text}

def formatProviderError(norm: NormalizedProviderError, prefix: Maybe<&2, String>) -> Result<&2, &2, NormalizationError, String>:
  match norm prefix:
    case NormalizedProviderError{None{}, _, message, _} _: Done{message}
    case NormalizedProviderError{Some{status}, body, message, alreadyPresent} Some{name}:
      do Result<&2, &2, NormalizationError, String>:
        text : String <- statusText(Decimal.toDecimal(status))
        return name ++ " (" ++ text ++ "): " ++ displayBody(alreadyPresent, body, message)
    case NormalizedProviderError{Some{status}, Some{body}, _, False{}} None{}:
      do Result<&2, &2, NormalizationError, String>:
        text : String <- statusText(Decimal.toDecimal(status))
        return text ++ ": " ++ body
    case NormalizedProviderError{_, _, message, _} None{}: Done{message}

# Native callers return typed failures; JSON-valued extension failures have a
# separate entry point instead of pretending all failures are JS Error objects.
def normalizedValue(encoded: Maybe<&2, String>) -> Result<&2, &2, NormalizationError, NormalizedProviderError>:
  match encoded:
    case None{}: Fail{NonJsonBody{}}
    case Some{text}: Done{NormalizedProviderError{None{}, None{}, text, False{}}}

def normalizeValue(value: T.JsonValue) -> Result<&2, &2, NormalizationError, NormalizedProviderError>:
  normalizedValue(Json.stringify(value))
