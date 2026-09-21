import Base
import ../packages/ai/src/api/openai-responses-system-provider.bend as P
import ../packages/ai/src/api/openai-responses-system-error.bend as Errors
import ../packages/ai/src/api/openai-responses-owned-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-prepared-acquire.bend as Ready
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-scoped-process.bend as Process
import ../packages/ai/src/api/openai-responses-scoped-reader.bend as Scoped
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-responses-stream-defaults.bend as Defaults
import ../packages/ai/src/api/openai-responses-default-session.bend as Default
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/utils/provider-owned-acquire.bend as Owned
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/schema-value.bend as V

# Closed callback templates fix these type parameters to the ordinary string
# reason/hook and unit-metadata provider. Every runtime, response, callback,
# model, message and preparation remains universally quantified. This proves
# composition order, not termination of the underlying body processor.
law body_processing_precedes_runtime_retirement_and_preserves_result:
  for context: Acquire.Context
  for hooks: SSE.Hooks<Scoped.TransportError(String)>
  for synthesize: Bool
  for model: T.Model<T.JsonValue>
  for requested: Maybe<&2, String>
  for pricing: P.PricingCallback(String, String)
  for sink: C.Callback<T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, P.Error(String, String), Unit>>
  for runtime: System.Owner<String>
  for prepared: Preparation.Prepared
  for response: Response.Response<Attempt.State(String)>
  for output: T.AssistantMessage<V.Value, Unit>
  {P.process(~String, ~String, ~Unit, P.Dependencies{context, hooks, synthesize}, model, requested, pricing, sink, Owned.Owner{runtime, Ready.Owner{prepared, response}}, output) == IO.bind(Life.Processed<V.Value, Unit, P.Error(String, String)>, Life.Processed<V.Value, Unit, P.Error(String, String)>, Process.process(~String, ~Unit, ~(P.Error(String, String)), ~(Errors.reader(String, String)), response, output, sink, model, Defaults.options(P.Error(String, String), requested, Default.grammar(prepared), pricing), hooks, synthesize, Errors.processing(String, String), Errors.disposal(String, String)), result => IO.bind(Unit, Life.Processed<V.Value, Unit, P.Error(String, String)>, System.dispose(String, runtime), ignored => IO.pure(Life.Processed<V.Value, Unit, P.Error(String, String)>, result))) : IO(Life.Processed<V.Value, Unit, P.Error(String, String)>)}
