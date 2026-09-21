import Base
import ../packages/ai/src/api/openai-request-headers.bend as Request
import ../laws/openai-request-headers.bend as Laws

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
  disjunction_commutes(Request.credentialAllows(authorization), Request.credentialAllows(apiKey))
def Laws.nonempty_credential_allows_authentication(head, tail, other): {==}
def Laws.absent_credentials_are_rejected(): {==}
def Laws.timeout_failure_bypasses_header_construction(configuration, apiKey, retryCount, client, body, request, cause): {==}
