import Base
import ./openai-body-responses-reader.bend as Body
import ./openai-responses-stream.bend as Stream
import ./openai-responses-lifecycle.bend as Life
import ../../../runtime/src/schema-value.bend as Value

# Keep the final immutable message, primary processing failure and subsequent
# disposal failure independent. The lifecycle driver determines terminal status.
def failure(-E: Data, embed: Stream.Error<E> -> E, value: Maybe<&2, Stream.Error<E>>) -> Maybe<&2, E>:
  match value:
    case None{}: None{}
    case Some{cause}: Some{embed(cause)}

def cleanup(-Transport: Data, -E: Data, embed: Body.CloseError<Transport> -> E, value: Result<&2, &2, Body.CloseError<Transport>, Unit>) -> Maybe<&2, E>:
  match value:
    case Done{_}: None{}
    case Fail{cause}: Some{embed(cause)}

def completed(-Transport: Data, -G: Data, -E: Data, processingError: Stream.Error<E> -> E, disposalError: Body.CloseError<Transport> -> E, value: Body.Processed<Transport, G, E>) -> Life.Processed<Value.Value, G, E>:
  match value:
    case Body.Processed{Stream.RunResult{output, error}, disposal}:
      Life.Processed{output, failure(E, processingError, error), cleanup(Transport, E, disposalError, disposal)}
