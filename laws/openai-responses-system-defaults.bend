import Base
import ../packages/ai/src/api/openai-responses-system-defaults.bend as D
import ../packages/ai/src/api/openai-responses-system-provider.bend as Provider
import ../packages/ai/src/api/openai-responses-provider-core.bend as Core
import ../packages/ai/src/api/openai-responses-scoped-reader.bend as Scoped
import ../packages/ai/src/api/openai-sse-default-hooks.bend as Hooks
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V

law owned_hooks_retire_before_caller_finalizer:
  for -Reason: Data
  for owner: Hooks.Owner<Scoped.TransportError(Reason)>
  for cleanup: IO(Unit)
  {D.retire(Reason, owner, cleanup) == IO.bind(Unit, Unit, Hooks.dispose(Scoped.TransportError(Reason), owner), ignored => cleanup) : IO(Unit)}

def identity(value: T.JsonValue) -> T.JsonValue: value
def render(environment: String, error: Provider.Error(String, String)) -> String: environment

# Callback templates require closed type arguments. Configuration, canonical
# inputs, clock effect and finalizer remain arbitrary in this specialization.
law clock_runs_once_before_provider_initialization:
  for configuration: D.Configuration
  for model: T.Model<T.JsonValue>
  for transcript: T.TranscriptContext<V.Value, R.Record<V.Value>, Unit, Unit>
  for options: Core.RequestOptions(T.JsonValue, String, Unit, Unit, String)
  for clock: IO(F.F64)
  for environment: String
  for cleanup: IO(Unit)
  {D.streamWithClock(~T.JsonValue, ~identity, ~String, ~String, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ~render, configuration, model, transcript, options, clock, environment, cleanup) == IO.bind(F.F64, Provider.Run(String, String, Unit), clock, timestamp => D.streamAt(~T.JsonValue, ~identity, ~String, ~String, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ~render, configuration, model, transcript, options, timestamp, environment, cleanup)) : IO(Provider.Run(String, String, Unit))}
