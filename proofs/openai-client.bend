import Base
import ../packages/ai/src/api/openai-client.bend as Client
import ../laws/openai-client.bend as Laws

law disjunction_commutes:
  for +left: Bool
  for +right: Bool
  {Bool.or(left, right) == Bool.or(right, left) : Bool}

def disjunction_commutes(left, right):
  match left right:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Laws.explicit_timeout_is_retained(value): {==}
def Laws.noninteger_timeout_is_rejected(value): {==}
def Laws.header_failure_preserves_cause(cause): {==}
def Laws.failed_authentication_has_no_headers(state): {==}
def Laws.accepted_authentication_preserves_headers(state): {==}
def Laws.removal_allows_authentication_override(other): {==}
def Laws.authentication_methods_are_interchangeable(authorization, apiKey):
  disjunction_commutes(Client.credentialAllows(authorization), Client.credentialAllows(apiKey))
def Laws.nonempty_credential_allows_authentication(head, tail, other): {==}
def Laws.absent_credentials_are_rejected(): {==}
def Laws.timeout_failure_bypasses_header_construction(configuration, apiKey, retryCount, client, body, request, cause): {==}
def Laws.diagnostic_read_failure_retains_cause(E, metadata, cause): {==}
def Laws.construction_retains_diagnostic(E, metadata, diagnostic, text): {==}
def Laws.encoding_failure_retains_diagnostic(E, metadata, diagnostic): {==}
def Laws.present_error_is_selected(fallback, error): {==}
def Laws.unrecognized_json_is_retained(value): {==}
def Laws.nonempty_message_text_is_retained(whole, head, tail): {==}
def Laws.text_normalization_preserves_rendered_message(metadata, text, message): {==}
def Laws.json_normalization_retains_input(metadata, value, message): {==}
def Laws.nonretryable_failures_stay_application_errors(E, original): {==}
def Laws.connection_failures_are_retryable(E, original): {==}
def Laws.expired_deadlines_are_retryable_timeouts(Reason, E, original): {==}
def Laws.parent_cancellation_is_never_retried(Reason, E, original, why): {==}
def Laws.cancellation_overrides_the_transport_category(Reason, E, original, why): {==}
def Laws.invalid_timeouts_are_never_retried(Reason, cause): {==}
