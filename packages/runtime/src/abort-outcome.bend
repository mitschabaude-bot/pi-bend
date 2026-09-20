import Base
import ./abort.bend as Abort

# Pure arbitration at the final observation boundary. Cancellation without a
# retained abort is distinct from a successful operation with an empty value.
type Outcome<-Reason: Data, -Failure: Data, -Value: Data> is Data:
  Aborted{reason: Abort.AbortReason<Reason>}
  Completed{result: Result<&2, &2, Failure, Value>}
  Cancelled{}

def choose(-Reason: Data, -Failure: Data, -Value: Data, observed: Maybe<&2, Abort.AbortReason<Reason>>, operation: Maybe<&2, Result<&2, &2, Failure, Value>>) -> Outcome<Reason, Failure, Value>:
  match observed operation:
    case Some{why} _: Aborted{why}
    case None{} Some{result}: Completed{result}
    case None{} None{}: Cancelled{}
