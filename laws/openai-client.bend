import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/utils/error-body.bend as Body
import ../packages/ai/src/utils/provider-header-state.bend as S
import ../packages/ai/src/utils/provider-http-response.bend as HTTP
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/timer-milliseconds.bend as Duration

# Request headers: the SDK's timeout validation and authentication policy.

law explicit_timeout_is_retained:
  for value: F.F64
  {Client.effectiveTimeout(Some{value}) == value : F.F64}

law noninteger_timeout_is_rejected:
  for value: F.F64
  {Client.checkedTimeout(value, False{}) == Fail{Client.TimeoutNotInteger{value}} : Result<&2, &2, Client.HeaderError, F.F64>}

law header_failure_preserves_cause:
  for cause: H.HeaderError
  {Client.assembled(Fail{cause}) == Fail{Client.HeaderFailure{cause}} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law failed_authentication_has_no_headers:
  for state: S.State
  {Client.authenticate(state, False{}) == Fail{Client.MissingAuthentication{}} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law accepted_authentication_preserves_headers:
  for state: S.State
  {Client.authenticate(state, True{}) == Done{S.headers(state)} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law removal_allows_authentication_override:
  for other: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(Some{T.NullValue{}}, other) == True{} : Bool}

law authentication_methods_are_interchangeable:
  for +authorization: Maybe<&2, T.Nullable<String>>
  for +apiKey: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(authorization, apiKey) == Client.authenticationAllowed(apiKey, authorization) : Bool}

law nonempty_credential_allows_authentication:
  for head: Char
  for tail: String
  for other: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(Some{T.PresentValue{SCon{head, tail}}}, other) == True{} : Bool}

law absent_credentials_are_rejected:
  {Client.authenticationAllowed(None{}, None{}) == False{} : Bool}

law timeout_failure_bypasses_header_construction:
  for configuration: Client.Defaults
  for apiKey: String
  for retryCount: Nat
  for client: Maybe<&2, T.ProviderHeaders()>
  for body: Maybe<&2, T.ProviderHeaders()>
  for request: Maybe<&2, T.ProviderHeaders()>
  for cause: Client.HeaderError
  {Client.validated(configuration, apiKey, retryCount, client, body, request, Fail{cause}) == Fail{cause} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

# APIError: every diagnostic and construction failure keeps its evidence.

law diagnostic_read_failure_retains_cause:
  for -E: Data
  for metadata: Metadata.Metadata
  for cause: Consume.TextError<E>
  {Client.fromResponse(E, HTTP.StatusFailure{metadata, Fail{cause}}) == Fail{Client.DiagnosticReadFailure{metadata, cause}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law construction_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Client.Diagnostic
  for text: String
  {Client.constructed(E, metadata, diagnostic, Some{text}) == Done{Client.APIError{metadata, diagnostic, Client.statusMessage(Metadata.status(metadata), text)}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law encoding_failure_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Client.Diagnostic
  {Client.constructed(E, metadata, diagnostic, None{}) == Fail{Client.DiagnosticEncodingFailure{metadata, diagnostic}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law present_error_is_selected:
  for fallback: T.JsonValue
  for error: T.JsonValue
  {Client.selected(fallback, Some{error}) == error : T.JsonValue}

law unrecognized_json_is_retained:
  for value: T.JsonValue
  {Client.selected(value, None{}) == value : T.JsonValue}

law nonempty_message_text_is_retained:
  for whole: T.JsonValue
  for head: Char
  for tail: String
  {Client.jsonMessage(whole, Some{T.JsonString{SCon{head, tail}}}) == Some{SCon{head, tail}} : Maybe<&2, String>}

law text_normalization_preserves_rendered_message:
  for metadata: Metadata.Metadata
  for text: String
  for message: String
  {Client.providerFailure(Client.APIError{metadata, Client.TextDiagnostic{text}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.status(metadata))}, message, Nil{}} : Body.ProviderFailure}

law json_normalization_retains_input:
  for metadata: Metadata.Metadata
  for value: T.JsonValue
  for message: String
  {Client.providerFailure(Client.APIError{metadata, Client.JSONDiagnostic{value}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.status(metadata))}, message, Body.ParsedBody{value} <> Nil{}} : Body.ProviderFailure}

# Retry classification of an attempt: only connection failures and deadline
# expiry become retryable provider errors; every original failure survives.

law nonretryable_failures_stay_application_errors:
  for -E: Data
  for original: E
  {Client.categorized(E, original, Fetch.NonRetryable{}) == Retry.Other{original} : Retry.RequestFailure<E>}

law connection_failures_are_retryable:
  for -E: Data
  for original: E
  {Client.categorized(E, original, Fetch.Connection{}) == Retry.Provider{Retry.ProviderError{original, "Connection error.", None{}, None{}, None{}, None{}}} : Retry.RequestFailure<E>}

law expired_deadlines_are_retryable_timeouts:
  for -Reason: Data
  for -E: Data
  for original: E
  {Client.aborted(Reason, E, original, Abort.Supplied{Deadline.Expired{}}) == Retry.Provider{Retry.ProviderError{original, "Request timed out.", None{}, None{}, None{}, None{}}} : Retry.RequestFailure<E>}

law parent_cancellation_is_never_retried:
  for -Reason: Data
  for -E: Data
  for original: E
  for why: Abort.AbortReason<Reason>
  {Client.aborted(Reason, E, original, Abort.Supplied{Deadline.ParentAbort{why}}) == Retry.Other{original} : Retry.RequestFailure<E>}

law cancellation_overrides_the_transport_category:
  for -Reason: Data
  for -E: Data
  for original: E
  for why: Abort.AbortReason<Deadline.Cause<Reason>>
  {Client.dispatched(Reason, E, original, Fetch.Connection{}, Some{why}) == Client.aborted(Reason, E, original, why) : Retry.RequestFailure<E>}

law invalid_timeouts_are_never_retried:
  for -Reason: Data
  for cause: Duration.Error
  {Client.fetchFailure(Reason, Client.InvalidTimeout{cause}) == Retry.Other{Client.TransportFailure{Client.InvalidTimeout{cause}}} : Retry.RequestFailure<Client.AttemptError<Reason>>}
