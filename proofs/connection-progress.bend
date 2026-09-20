import Base
import ../laws/connection-progress.bend as Laws
import ../packages/runtime/src/connection-attempt-result.bend as Attempt

def Laws.parent_abort_wins(R, outcome, reason):
  match outcome:
    case Done{_}: {==}
    case Fail{Attempt.SocketFailure{_, _}}: {==}
    case Fail{Attempt.TimedOut{}}: {==}
    case Fail{Attempt.Aborted{_}}: {==}
    case Fail{Attempt.UnexpectedDefaultAbort{}}: {==}
def Laws.socket_failure_advances(R, code, message): {==}
def Laws.expiry_advances(R): {==}
def Laws.reported_abort_stops(R, reason): {==}
def Laws.unexpected_abort_stops(R): {==}
def Laws.settled_success_accepted(R): {==}
def Laws.last_attempt_untimed(A): {==}
def Laws.nonfinal_attempt_timed(A, first, rest): {==}
