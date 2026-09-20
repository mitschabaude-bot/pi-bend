import Base
import ../packages/ai/src/api/openai-http-error.bend as Error
import ../packages/ai/src/utils/provider-http-response.bend as Provider
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/error-body.bend as Body
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/f64.bend as F

law diagnostic_read_failure_retains_cause:
  for -E: Data
  for metadata: Metadata.Metadata
  for cause: Consume.TextError<E>
  {Error.fromResponse(E, Provider.StatusFailure{metadata, Fail{cause}}) == Fail{Error.DiagnosticReadFailure{metadata, cause}} : Result<&2, &2, Error.ConstructionError<E>, Error.APIError>}

law construction_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Error.Diagnostic
  for text: String
  {Error.constructed(E, metadata, diagnostic, Some{text}) == Done{Error.APIError{metadata, diagnostic, Error.statusMessage(Metadata.status(metadata), text)}} : Result<&2, &2, Error.ConstructionError<E>, Error.APIError>}

law encoding_failure_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Error.Diagnostic
  {Error.constructed(E, metadata, diagnostic, None{}) == Fail{Error.DiagnosticEncodingFailure{metadata, diagnostic}} : Result<&2, &2, Error.ConstructionError<E>, Error.APIError>}

law present_error_is_selected:
  for fallback: T.JsonValue
  for error: T.JsonValue
  {Error.selected(fallback, Some{error}) == error : T.JsonValue}

law unrecognized_json_is_retained:
  for value: T.JsonValue
  {Error.selected(value, None{}) == value : T.JsonValue}

law nonempty_message_text_is_retained:
  for whole: T.JsonValue
  for head: Char
  for tail: String
  {Error.jsonMessage(whole, Some{T.JsonString{SCon{head, tail}}}) == Some{SCon{head, tail}} : Maybe<&2, String>}

law retry_retains_original_error:
  for metadata: Metadata.Metadata
  for diagnostic: Error.Diagnostic
  for message: String
  {Error.retryFailure(Error.APIError{metadata, diagnostic, message}) == Provider.retryFailure(Error.APIError, Error.APIError{metadata, diagnostic, message}, message, metadata) : Retry.RequestFailure<Error.APIError>}

law text_normalization_preserves_rendered_message:
  for metadata: Metadata.Metadata
  for text: String
  for message: String
  {Error.providerFailure(Error.APIError{metadata, Error.TextDiagnostic{text}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.status(metadata))}, message, Nil{}} : Body.ProviderFailure}

law json_normalization_retains_input:
  for metadata: Metadata.Metadata
  for value: T.JsonValue
  for message: String
  {Error.providerFailure(Error.APIError{metadata, Error.JSONDiagnostic{value}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.status(metadata))}, message, Body.ParsedBody{value} <> Nil{}} : Body.ProviderFailure}
