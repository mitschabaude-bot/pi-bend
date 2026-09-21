import Base
import ../../../runtime/src/http-response-progress.bend as Progress
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-body-responses-reader.bend as Body
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-responses-process-result.bend as Result
import ./openai-responses-lifecycle.bend as Life
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-sse-reader.bend as SSE
import ../types.bend as T
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/callback.bend as C

# This is the owning processing callback required by the session driver.
# Acquisition has already delivered the response hook; metadata is consumed
# here, and the scoped SSE owner retires every body resource before returning.
def process(~Reason: Data, ~G: Data, ~E: Data, ~mapReader: Reader.Error<Scoped.TransportError(Reason)> -> E, response: Response.Response<Attempt.State(Reason)>, output: T.AssistantMessage<Value.Value, G>, sink: C.Callback<T.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: T.Model<T.JsonValue>, pricing: Pricing.OpenAIResponsesStreamOptions<E>, hooks: SSE.Hooks<Scoped.TransportError(Reason)>, synthesize: Bool, mapProcessing: Stream.Error<E> -> E, mapDisposal: Body.CloseError<Scoped.TransportError(Reason)> -> E) -> IO(Life.Processed<Value.Value, G, E>):
  match response:
    case Response.Response{_, body}:
      do IO<Life.Processed<Value.Value, G, E>>:
        owner : Body.Owner<Attempt.State(Reason), Scoped.TransportError(Reason), E> <- Scoped.create(~Reason, ~E, ~mapReader, body, hooks, synthesize)
        result : Body.Processed<Scoped.TransportError(Reason), G, E> <- Body.process(Attempt.State(Reason), Scoped.TransportError(Reason), G, E, T.JsonValue, owner, output, sink, model, pricing)
        return Result.completed(Scoped.TransportError(Reason), G, E, mapProcessing, mapDisposal, result)

def released(-Reason: Data, -E: Data, embed: Progress.Error<Attempt.ReadError(Reason)> -> E, value: Response.Next<Attempt.ReadError(Reason), Attempt.State(Reason)>) -> Result<&2, &2, E, Unit>:
  match value:
    case Response.Next{_, Done{_}}: Done{Unit{}}
    case Response.Next{_, Fail{cause}}: Fail{embed(cause)}

# Used when a start-event failure prevents processing. closeWith always returns
# a closed body; the scope retires transport before parent-cancellation state.
def release(-Reason: Data, -E: Data, embed: Progress.Error<Attempt.ReadError(Reason)> -> E, response: Response.Response<Attempt.State(Reason)>) -> IO(Result<&2, &2, E, Unit>):
  match response:
    case Response.Response{_, body}:
      do IO<Result<&2, &2, E, Unit>>:
        result : Response.Next<Attempt.ReadError(Reason), Attempt.State(Reason)> <- Response.closeWith(Attempt.ReadError(Reason), Attempt.State(Reason), Scoped.close(Reason), body)
        return released(Reason, E, embed, result)
