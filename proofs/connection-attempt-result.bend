import Base
import ../laws/connection-attempt-result.bend as Laws

def Laws.timed_socket_failure_retained(R, code, message): {==}
def Laws.plain_socket_failure_retained(R, code, message): {==}
def Laws.timed_parent_reason_retained(R, reason): {==}
def Laws.plain_parent_reason_retained(R, reason): {==}
def Laws.expiry_distinguished(R): {==}
def Laws.unexpected_default_distinguished(R): {==}
