import Base
import ../packages/runtime/src/http-response.bend as Classify
import ../packages/runtime/src/http-response.bend as Progress
import ../packages/runtime/src/http-response.bend as Stream

law lone_transport_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.TransportFailure{error}}) == classify(error) : Bool}

law lone_cleanup_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.ResponseProgressCleanupFailure{error}) == classify(error) : Bool}

law combined_failures_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for error: Progress.ResponseProgressPrimaryError<E>
  for cleanup: E
  {Classify.standalone(E, classify, Progress.ResponseProgressFailureWithCleanup{error, cleanup}) == False{} : Bool}

law unexpected_events_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for event: Stream.StreamEvent
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.UnexpectedEvent{event}}) == False{} : Bool}

law missing_head_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.MissingHead{}}) == False{} : Bool}

law missing_completion_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.MissingCompletion{}}) == False{} : Bool}
