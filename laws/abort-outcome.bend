import Base
import ../packages/runtime/src/abort-outcome.bend as Outcome
import ../packages/runtime/src/abort.bend as Abort

law retained_abort_wins:
  for -Reason: Data
  for -Failure: Data
  for -Value: Data
  for +why: Abort.AbortReason<Reason>
  for operation: Maybe<&2, Result<&2, &2, Failure, Value>>
  {Outcome.choose(Reason, Failure, Value, Some{why}, operation) == Outcome.Aborted{why} : Outcome.Outcome<Reason, Failure, Value>}

law completion_preserved:
  for -Reason: Data
  for -Failure: Data
  for -Value: Data
  for +result: Result<&2, &2, Failure, Value>
  {Outcome.choose(Reason, Failure, Value, None{}, Some{result}) == Outcome.Completed{result} : Outcome.Outcome<Reason, Failure, Value>}
