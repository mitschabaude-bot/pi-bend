import Base
import ./openai-responses-session.bend as Session
import ./openai-responses-scoped-process.bend as Process
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-body-responses-reader.bend as Body
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-sse-reader.bend as SSE
import ../types.bend as T
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/callback.bend as C

# Compose the existing session state machine with the scoped owning processor.
# Acquisition is an IO program, not an already-acquired body: session.start
# forks it and returns the canonical event stream immediately. The caller must
# retain all borrowed hooks/effects/signals until Session.wait completes.
def start(~Reason: Data, ~G: Data, ~E: Data, ~mapReader: Reader.Error<Scoped.TransportError(Reason)> -> E, ~render: E -> String, initial: T.AssistantMessage<Value.Value, G>, signal: C.Callback<Unit, Bool>, acquire: IO(Result<&2, &1, E, Response.Response<Attempt.State(Reason)>>), model: T.Model<T.JsonValue>, pricing: Pricing.OpenAIResponsesStreamOptions<E>, hooks: SSE.Hooks<Scoped.TransportError(Reason)>, synthesize: Bool, mapProcessing: Stream.Error<E> -> E, mapDisposal: Body.CloseError<Scoped.TransportError(Reason)> -> E, mapRelease: Progress.Error<Attempt.ReadError(Reason)> -> E) -> IO(Session.Run<Value.Value, G, E>):
  Session.start(~Value.Value, ~G, ~E, ~render, Response.Response<Attempt.State(Reason)>, initial, signal, acquire, sink => owner => output => Process.process(~Reason, ~G, ~E, ~mapReader, owner, output, sink, model, pricing, hooks, synthesize, mapProcessing, mapDisposal), owner => Process.release(Reason, E, mapRelease, owner))
