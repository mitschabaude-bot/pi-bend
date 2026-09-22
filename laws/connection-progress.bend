import Base
import ../packages/runtime/src/connection-driver.bend as Progress
import ../packages/runtime/src/connection-driver.bend as Attempt
import ../packages/runtime/src/abort.bend as Abort

law parent_abort_wins:
  for -R: Data
  for outcome: Result<&2, &2, Attempt.Error<R>, Unit>
  for +reason: Abort.AbortReason<R>
  {Progress.decide(R, outcome, Some{reason}) == Progress.Stop{Progress.ProgressAborted{reason}} : Progress.Decision<R>}

law socket_failure_advances:
  for -R: Data
  for code: U32
  for message: String
  {Progress.decide(R, Fail{Attempt.SocketFailure{code, message}}, None{}) == Progress.Advance{} : Progress.Decision<R>}

law expiry_advances:
  for -R: Data
  {Progress.decide(R, Fail{Attempt.TimedOut{}}, None{}) == Progress.Advance{} : Progress.Decision<R>}

law reported_abort_stops:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Progress.decide(R, Fail{Attempt.Aborted{reason}}, None{}) == Progress.Stop{Progress.ProgressAborted{reason}} : Progress.Decision<R>}

law unexpected_abort_stops:
  for -R: Data
  {Progress.decide(R, Fail{Attempt.UnexpectedDefaultAbort{}}, None{}) == Progress.Stop{Progress.ProgressUnexpectedDefaultAbort{}} : Progress.Decision<R>}

law settled_success_accepted:
  for -R: Data
  {Progress.decide(R, Done{Unit{}}, None{}) == Progress.Accept{} : Progress.Decision<R>}

law last_attempt_untimed:
  for -A: Data
  {Progress.mode(A, Nil{}) == Progress.Final{} : Progress.Mode}

law nonfinal_attempt_timed:
  for -A: Data
  for first: A
  for rest: List<&2, A>
  {Progress.mode(A, first <> rest) == Progress.NonFinal{} : Progress.Mode}
