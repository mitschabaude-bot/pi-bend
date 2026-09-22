import Base
import ../laws/fetch.bend as Laws

def Laws.expired_request_deadline_is_a_timeout(Reason): {==}
def Laws.parent_cancellation_is_not_retried(Reason, why): {==}
def Laws.default_cancellation_is_not_retried(Reason): {==}
def Laws.expired_dns_deadline_is_a_timeout(Reason): {==}
def Laws.dns_inherits_the_request_classification(Reason, why): {==}
def Laws.resolver_setup_failures_are_not_retried(Reason): {==}
def Laws.unanswered_lookups_are_connection_failures(Reason, error): {==}
def Laws.terminal_query_failures_are_not_retried(Reason, reports): {==}
def Laws.dns_deadline_overrides_the_report(Reason, fallback, why): {==}
