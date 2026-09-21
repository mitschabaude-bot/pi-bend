import Base
import ../packages/ai/src/api/openai-responses-process-result.bend as Result
import ../packages/ai/src/api/openai-body-responses-reader.bend as Body
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/schema-value.bend as Value

law successful_processing_retains_message:
  for -Transport: Data
  for -G: Data
  for -E: Data
  for message: T.AssistantMessage<Value.Value, G>
  for processing: Stream.Error<E> -> E
  for disposal: Body.CloseError<Transport> -> E
  {Result.completed(Transport, G, E, processing, disposal, Body.Processed{Stream.RunResult{message, None{}}, Done{Unit{}}}) == Life.Processed{message, None{}, None{}} : Life.Processed<Value.Value, G, E>}

law simultaneous_failures_retain_message_and_both_causes:
  for -Transport: Data
  for -G: Data
  for -E: Data
  for message: T.AssistantMessage<Value.Value, G>
  for processing: Stream.Error<E> -> E
  for disposal: Body.CloseError<Transport> -> E
  for primary: Stream.Error<E>
  for secondary: Body.CloseError<Transport>
  {Result.completed(Transport, G, E, processing, disposal, Body.Processed{Stream.RunResult{message, Some{primary}}, Fail{secondary}}) == Life.Processed{message, Some{processing(primary)}, Some{disposal(secondary)}} : Life.Processed<Value.Value, G, E>}
