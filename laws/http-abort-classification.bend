import Base
import ../packages/runtime/src/http-abort-classification.bend as Classify
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-stream.bend as Stream

law lone_transport_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.PrimaryFailure{Progress.TransportFailure{error}}) == classify(error) : Bool}

law lone_cleanup_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.CleanupFailure{error}) == classify(error) : Bool}

law combined_failures_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for error: Progress.PrimaryError<E>
  for cleanup: E
  {Classify.standalone(E, classify, Progress.FailureWithCleanup{error, cleanup}) == False{} : Bool}

law unexpected_events_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for event: Stream.Event
  {Classify.standalone(E, classify, Progress.PrimaryFailure{Progress.UnexpectedEvent{event}}) == False{} : Bool}

law missing_head_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.PrimaryFailure{Progress.MissingHead{}}) == False{} : Bool}

law missing_completion_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.PrimaryFailure{Progress.MissingCompletion{}}) == False{} : Bool}
