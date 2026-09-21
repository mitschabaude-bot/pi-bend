import Base
import ../laws/openai-responses-attempt.bend as Laws

def Laws.configuration_failure_is_terminal(Reason, E, original, reason): {==}
def Laws.parent_abort_is_not_a_connection_failure(Reason, E, original, reason): {==}
def Laws.expiration_retains_original_failure(Reason, E, original): {==}
def Laws.unreadable_diagnostic_keeps_retry_metadata(Reason, FetchError, ReadError, metadata, cause): {==}
def Laws.http_failure_retains_diagnostic_and_policy(Reason, FetchError, ReadError, metadata, diagnostic, message): {==}
def Laws.successful_response_transfers_unchanged(Reason, FetchError, ReadError, Transport, response): {==}
