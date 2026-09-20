import Base
import ./abortable-connect.bend as Connect
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Error<-Reason: Data> is Data:
  SocketFailure{code: U32, message: String}
  TimedOut{}
  Aborted{reason: Abort.AbortReason<Reason>}
  UnexpectedDefaultAbort{}

def timedError(-Reason: Data, error: Connect.Error<Deadline.Cause<Reason>>) -> Error<Reason>:
  match error:
    case Connect.SocketError{code, message}: SocketFailure{code, message}
    case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}: TimedOut{}
    case Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}: Aborted{reason}
    case Connect.Aborted{Abort.DefaultAbort{}}: UnexpectedDefaultAbort{}

def plainError(-Reason: Data, error: Connect.Error<Reason>) -> Error<Reason>:
  match error:
    case Connect.SocketError{code, message}: SocketFailure{code, message}
    case Connect.Aborted{reason}: Aborted{reason}

def timed(-Reason: Data, -Value: Type, result: Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>) -> Result<&2, &1, Error<Reason>, Value>:
  match result:
    case Fail{error}: Fail{timedError(Reason, error)}
    case Done{value}: Done{value}

def plain(-Reason: Data, -Value: Type, result: Result<&2, &1, Connect.Error<Reason>, Value>) -> Result<&2, &1, Error<Reason>, Value>:
  match result:
    case Fail{error}: Fail{plainError(Reason, error)}
    case Done{value}: Done{value}
