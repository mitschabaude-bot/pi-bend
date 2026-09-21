import Base
import ../types.bend as T
import ./openai-responses-system-provider.bend as Provider
import ./openai-responses-provider-core.bend as Core
import ./openai-responses-owned-acquire.bend as Acquire
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-sse-default-hooks.bend as Hooks
import ./openai-sse-reader.bend as SSE
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# Native default effects are installed here; configuration and error rendering
# remain explicit. The provider producer owns the hook finalizer after start.
type Configuration is Data:
  Configuration{acquisition: Acquire.Context, synthesize: Bool}

def retire(-Reason: Data, owner: Hooks.Owner<Scoped.TransportError(Reason)>, cleanup: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Hooks.dispose(Scoped.TransportError(Reason), owner)
    cleanup

def owned(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Provider.Error(Reason, Hook) -> String, configuration: Configuration, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), pair: Hooks.Owner<Scoped.TransportError(Reason)> & SSE.Hooks<Scoped.TransportError(Reason)>) -> IO(Provider.Run(Reason, Hook, G)):
  match configuration pair:
    case Configuration{acquisition, synthesize} Tuple{owner, hooks}:
      Provider.streamAt(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, Provider.Dependencies{acquisition, hooks, synthesize}, model, transcript, options, timestamp, environment, retire(Reason, owner, cleanup))

# Retain an explicit timestamp entry for deterministic embedders and tests.
def streamAt(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Provider.Error(Reason, Hook) -> String, configuration: Configuration, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit)) -> IO(Provider.Run(Reason, Hook, G)):
  do IO<Provider.Run(Reason, Hook, G)>:
    owner : Hooks.Owner<Scoped.TransportError(Reason)> <- Hooks.create(~(Scoped.TransportError(Reason)))
    owned(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, configuration, model, transcript, options, timestamp, environment, cleanup, Hooks.borrow(Scoped.TransportError(Reason), owner))

# Timestamp acquisition precedes hook/runtime initialization and request
# preparation, matching the upstream assistant-message initialization point.
def streamWithClock(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Provider.Error(Reason, Hook) -> String, configuration: Configuration, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), clock: IO(F.F64), environment: Environment, cleanup: IO(Unit)) -> IO(Provider.Run(Reason, Hook, G)):
  do IO<Provider.Run(Reason, Hook, G)>:
    timestamp : F.F64 <- clock
    streamAt(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, configuration, model, transcript, options, timestamp, environment, cleanup)

def stream(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Provider.Error(Reason, Hook) -> String, configuration: Configuration, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), environment: Environment, cleanup: IO(Unit)) -> IO(Provider.Run(Reason, Hook, G)):
  streamWithClock(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, configuration, model, transcript, options, Date.now(), environment, cleanup)
