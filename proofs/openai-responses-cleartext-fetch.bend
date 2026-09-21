import Base
import ../laws/openai-responses-cleartext-fetch.bend as Laws

def Laws.successful_headers_transfer_response(Reason, SourceError, resolution, attempts, response): {==}
def Laws.header_failure_retains_trace_and_cause(Reason, SourceError, resolution, attempts, cause): {==}
def Laws.rejected_plan_has_no_header_effects(Reason, SourceError, acquireHeaders, cause): {==}
def Laws.unresolved_request_preserves_resolution(Reason, SourceError, acquireHeaders, resolution): {==}
def Laws.exchange_failure_precedes_header_read(Reason, SourceError, acquireHeaders, resolution, attempts, cause): {==}
