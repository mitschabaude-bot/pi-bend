import Base
import ../packages/ai/src/api/openai-responses-attempt.bend as Attempt
import ../packages/ai/src/api/openai-http-error.bend as HTTPError
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-http-response.bend as HTTP
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/http-fetch-scope.bend as Scope
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-body-consume.bend as Consume

# Deterministic configuration failures remain terminal even if cancellation
# races with dispatch. Every original typed failure survives classification.
law configuration_failure_is_terminal:
  for -Reason: Data
  for -E: Data
  for original: E
  for reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>
  {Attempt.dispatchCategory(Reason, E, original, Attempt.NonRetryable{}, reason) == Retry.Other{original} : Retry.RequestFailure<E>}

law parent_abort_is_not_a_connection_failure:
  for -Reason: Data
  for -E: Data
  for original: E
  for reason: Abort.AbortReason<Reason>
  {Attempt.aborted(Reason, E, original, Abort.Supplied{Deadline.ParentAbort{reason}}) == Retry.Other{original} : Retry.RequestFailure<E>}

law expiration_retains_original_failure:
  for -Reason: Data
  for -E: Data
  for original: E
  {Attempt.aborted(Reason, E, original, Abort.Supplied{Deadline.Expired{}}) == Retry.Provider{Retry.ProviderError{original, "Request timed out.", None{}, None{}, None{}, None{}}} : Retry.RequestFailure<E>}

# Reading a diagnostic can fail independently of the server's retry policy.
# Keep both the typed cause and the policy-bearing response metadata.
law unreadable_diagnostic_keeps_retry_metadata:
  for -Reason: Data
  for -FetchError: Data
  for -ReadError: Data
  for metadata: Metadata.Metadata
  for cause: Consume.TextError<ReadError>
  {Attempt.diagnostic(Reason, FetchError, ReadError, HTTPError.DiagnosticReadFailure{metadata, cause}) == HTTP.retryFailure(Attempt.Error<Reason, FetchError, ReadError>, Attempt.DiagnosticFailure{HTTPError.DiagnosticReadFailure{metadata, cause}}, "Could not read the error response diagnostic.", metadata) : Retry.RequestFailure<Attempt.Error<Reason, FetchError, ReadError>>}

law http_failure_retains_diagnostic_and_policy:
  for -Reason: Data
  for -FetchError: Data
  for -ReadError: Data
  for metadata: Metadata.Metadata
  for diagnostic: HTTPError.Diagnostic
  for message: String
  {Attempt.constructed(Reason, FetchError, ReadError, Done{HTTPError.APIError{metadata, diagnostic, message}}) == HTTP.retryFailure(Attempt.Error<Reason, FetchError, ReadError>, Attempt.HTTPFailure{HTTPError.APIError{metadata, diagnostic, message}}, message, metadata) : Retry.RequestFailure<Attempt.Error<Reason, FetchError, ReadError>>}

law successful_response_transfers_unchanged:
  for -Reason: Data
  for -FetchError: Data
  for -ReadError: Data
  for -Transport: Type
  for response: Response.Response<Scope.State<Reason, Transport>>
  {Attempt.accepted(Reason, FetchError, ReadError, Transport, Done{response}) == Done{response} : Result<&2, &1, Retry.RequestFailure<Attempt.Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>}
