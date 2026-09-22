import Base
import ../packages/runtime/src/connection-driver.bend as Result
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline

law timed_socket_failure_retained:
  for -R: Data
  for +code: U32
  for +message: String
  {Result.timedError(R, Connect.SocketError{code, message}) == Result.SocketFailure{code, message} : Result.Error<R>}

law plain_socket_failure_retained:
  for -R: Data
  for +code: U32
  for +message: String
  {Result.plainError(R, Connect.SocketError{code, message}) == Result.SocketFailure{code, message} : Result.Error<R>}

law timed_parent_reason_retained:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Result.timedError(R, Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}) == Result.Aborted{reason} : Result.Error<R>}

law plain_parent_reason_retained:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Result.plainError(R, Connect.Aborted{reason}) == Result.Aborted{reason} : Result.Error<R>}

law expiry_distinguished:
  for -R: Data
  {Result.timedError(R, Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}) == Result.TimedOut{} : Result.Error<R>}

law unexpected_default_distinguished:
  for -R: Data
  {Result.timedError(R, Connect.Aborted{Abort.DefaultAbort{}}) == Result.UnexpectedDefaultAbort{} : Result.Error<R>}
