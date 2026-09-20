import Base
import ../laws/http-abort-classification.bend as Laws

def Laws.lone_transport_uses_classifier(E, classify, error): {==}
def Laws.lone_cleanup_uses_classifier(E, classify, error): {==}
def Laws.combined_failures_are_not_cancellation(E, classify, error, cleanup): {==}
def Laws.unexpected_events_are_not_cancellation(E, classify, event): {==}
def Laws.missing_head_is_not_cancellation(E, classify): {==}
def Laws.missing_completion_is_not_cancellation(E, classify): {==}
