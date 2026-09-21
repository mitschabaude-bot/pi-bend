import Base
import ../laws/openai-responses-cleartext-runtime.bend as Laws

def Laws.resolver_failure_does_not_allocate_dependencies(hosts, options, date, cause): {==}
def Laws.retry_failure_retires_resolver_before_returning_cause(hosts, options, resolver, cause): {==}
def Laws.borrowing_preserves_fetch_and_retry_handles(Reason, Source, resolver, fetch, retry, effects): {==}
def Laws.fetch_retires_before_retry_and_resolver(Reason, Source, resolver, fetch, retry): {==}
