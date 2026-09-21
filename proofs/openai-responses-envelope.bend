import Base
import ../laws/openai-responses-envelope.bend as Laws

def Laws.invalid_payload_has_no_body(payload): {==}
def Laws.encoding_retains_text(text): {==}
def Laws.completed_request_retains_fields(url, body, timeout, headers): {==}
def Laws.completed_error_retains_cause(url, body, timeout, cause): {==}
def Laws.url_failure_precedes_other_validation(configuration, key, headers, timeout, payload, cause): {==}
def Laws.timeout_failure_precedes_payload(configuration, key, headers, url, payload, original, cause): {==}
def Laws.payload_failure_precedes_headers(configuration, key, headers, url, timeout, original, cause): {==}
def Laws.absent_timeout_has_no_header(): {==}
