import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./dns-udp-timeout.bend as Timeout

type End<-Reason: Data> is Data:
  Active{}
  AttemptExpired{}
  ParentAborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  UnexpectedDefaultAbort{}

# The parent is the caller's existing total-deadline signal. Creating an
# attempt does not restart that deadline or replace its original abort reason.
def checked(-Reason: Data, parent: Abort.AbortSignal<Deadline.Cause<Reason>>, budget: Result<&2, &2, Timeout.MillisecondsError, U32>) -> IO(Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>):
  match budget:
    case Fail{error}: IO.pure(Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>, Fail{error})
    case Done{milliseconds}:
      do IO<Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>>:
        scope : Deadline.Scope<Deadline.Cause<Reason>> <- Deadline.create(Deadline.Cause<Reason>, milliseconds, parent)
        return Done{scope}

def create(-Reason: Data, duration: Timeout.Duration, parent: Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>):
  checked(Reason, parent, Timeout.milliseconds(duration))

def classify(-Reason: Data, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>>) -> End<Reason>:
  match reason:
    case None{}: Active{}
    case Some{Abort.Supplied{Deadline.Expired{}}}: AttemptExpired{}
    case Some{Abort.Supplied{Deadline.ParentAbort{why}}}: ParentAborted{why}
    case Some{Abort.DefaultAbort{}}: UnexpectedDefaultAbort{}

# Call after all operations borrowing the child signal have settled. Deadline
# closure cancels its timer/observation and joins both watcher tasks.
def close(-Reason: Data, scope: Deadline.Scope<Deadline.Cause<Reason>>) -> IO(End<Reason>):
  do IO<End<Reason>>:
    reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>> <- Deadline.close(Deadline.Cause<Reason>, scope)
    return classify(Reason, reason)
