import Base
import ../laws/openai-responses-native-error.bend as Laws

def Laws.invalid_request_never_becomes_connection_retry(Reason, SourceError, cause): {==}
def Laws.rejected_transport_plan_is_terminal(Reason, SourceError, cause): {==}
def Laws.failed_hosts_snapshot_is_terminal(Reason, SourceError, cause): {==}
def Laws.socket_error_policy_ignores_platform_code_and_message(Reason, code, message): {==}
def Laws.explicit_parent_abort_is_terminal(Reason, cause): {==}
def Laws.dns_parent_retains_request_abort_policy(Reason, cause): {==}
def Laws.exhausted_dns_network_outcomes_are_retryable(Reason, cause): {==}
def Laws.invalid_dns_encoding_precedes_late_deadline(Reason, cause, why): {==}
def Laws.header_cleanup_failure_cannot_be_hidden_by_primary_classification(Reason, primary, cleanup): {==}
