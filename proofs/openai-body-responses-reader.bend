import Base
import ../laws/openai-body-responses-reader.bend as Laws

def Laws.reader_disposal_failure_is_retained(Transport, cause): {==}
def Laws.body_disposal_failure_is_retained(Transport, cause): {==}
def Laws.simultaneous_disposal_failures_are_retained_in_order(Transport, reader, body): {==}
