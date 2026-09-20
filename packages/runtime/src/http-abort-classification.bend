import Base
import ./http-response-progress.bend as Progress

# A lone transport failure may represent cancellation. Protocol failures and
# compound failures must not be hidden merely because one cause is an abort.
def primary(-E: Data, classify: E -> Bool, error: Progress.PrimaryError<E>) -> Bool:
  match error:
    case Progress.TransportFailure{cause}: classify(cause)
    case _: False{}

def standalone(-E: Data, classify: E -> Bool, error: Progress.Error<E>) -> Bool:
  match error:
    case Progress.PrimaryFailure{cause}: primary(E, classify, cause)
    case Progress.CleanupFailure{cause}: classify(cause)
    case Progress.FailureWithCleanup{_, _}: False{}
