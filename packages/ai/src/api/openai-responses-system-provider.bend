import Base
import ../types.bend as T
import ./openai-responses-options.bend as Options
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-prepared-acquire.bend as Ready
import ./openai-responses-owned-acquire.bend as Acquire
import ./openai-responses-system-error.bend as Errors
import ./openai-responses-cleartext-system-runtime.bend as System
import ./openai-responses-native-session.bend as Native
import ./openai-responses-provider-core.bend as Core
import ./openai-responses-default-session.bend as Default
import ./openai-responses-stream-defaults.bend as Defaults
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-responses-scoped-process.bend as Process
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-sse-reader.bend as SSE
import ./openai-responses-lifecycle.bend as Life
import ./openai-responses-session.bend as Session
import ./openai-request-headers.bend as Headers
import ../utils/provider-owned-acquire.bend as Owned
import ../utils/provider-hook-map.bend as Hooks
import ../utils/provider-hook-options.bend as HookOptions
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as Value

def Error(-Reason: Data, -Hook: Data) -> Data: Errors.Error<Reason, Hook>
def Inner(-Reason: Data, -Hook: Data) -> Data: Acquire.Inner(Reason, Hook)
def Run(-Reason: Data, -Hook: Data, -G: Data) -> Type: Session.Run<Value.Value, G, Error(Reason, Hook)>
def PricingCallback(-Reason: Data, -Hook: Data) -> Data: C.Callback<Pricing.PricingRequest, Result<&2, &2, Error(Reason, Hook), T.Usage>>

# System settings are data, not already-created transport dependencies. The
# producer initializes its runtime only after preparation and payload hooks.
# SSE callbacks remain explicit and borrowed until the producer finalizer.
type Dependencies<-Reason: Data> is Data:
  Dependencies{acquisition: Acquire.Context, hooks: SSE.Hooks<Scoped.TransportError(Reason)>, synthesize: Bool}

def userAgent(context: Acquire.Context) -> String:
  match context:
    case Acquire.Context{_, Headers.Defaults{name, _, _, _}, _, _, _}: name

def retire(-Reason: Data, -Hook: Data, signalOwner: Native.SignalOwner<Reason>, query: C.Callback<Unit, Bool>, hooks: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook)>, pricing: Defaults.Owner<Error(Reason, Hook)>, cleanup: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Native.cleanup(Reason, signalOwner, query)
    Hooks.dispose(T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook), hooks)
    Defaults.dispose(Error(Reason, Hook), pricing)
    cleanup

# The scoped processor closes the body on every result. Its borrowed runtime
# stays alive until that IO completes, including error and early-close paths.
def process(~Reason: Data, ~Hook: Data, ~G: Data, dependencies: Dependencies<Reason>, model: T.Model<T.JsonValue>, requested: Maybe<&2, String>, pricing: PricingCallback(Reason, Hook), sink: C.Callback<T.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, Error(Reason, Hook), Unit>>, owner: Acquire.Owner(Reason), output: T.AssistantMessage<Value.Value, G>) -> IO(Life.Processed<Value.Value, G, Error(Reason, Hook)>):
  match dependencies owner:
    case Dependencies{_, hooks, synthesize} Owned.Owner{runtime, Ready.Owner{prepared, response}}:
      do IO<Life.Processed<Value.Value, G, Error(Reason, Hook)>>:
        result : Life.Processed<Value.Value, G, Error(Reason, Hook)> <- Process.process(~Reason, ~G, ~(Error(Reason, Hook)), ~(Errors.reader(Reason, Hook)), response, output, sink, model, Defaults.options(Error(Reason, Hook), requested, Default.grammar(prepared), pricing), hooks, synthesize, Errors.processing(Reason, Hook), Errors.disposal(Reason, Hook))
        System.dispose(Reason, runtime)
        return result

def release(-Reason: Data, -Hook: Data, owner: Acquire.Owner(Reason)) -> IO(Result<&2, &2, Error(Reason, Hook), Unit>):
  do IO<Result<&2, &2, Error(Reason, Hook), Unit>>:
    result : Result<&2, &2, Inner(Reason, Hook), Unit> <- Acquire.release(Reason, Hook, owner)
    return Errors.released(Reason, Hook, result)

def acquire(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, +context: Acquire.Context, parent: Abort.AbortSignal<Reason>, +model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), requestOptions: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch)) -> IO(Result<&2, &1, Error(Reason, Hook), Acquire.Owner(Reason)>):
  do IO<Result<&2, &1, Error(Reason, Hook), Acquire.Owner(Reason)>>:
    result : Result<&2, &1, Acquire.Error(Reason, Hook), Acquire.Owner(Reason)> <- Acquire.run(~Reason, ~Hook, ~Telemetry, ~Fetch, context, parent, model, requestOptions, Preparation.prepare(~Choice, ~encodeChoice, ~G, ~D, ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch, ~Hook, model, transcript, options, userAgent(context)))
    return Errors.acquired(Reason, Hook, Acquire.Owner(Reason), result)

def priced(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Hook) -> String, +dependencies: Dependencies<Reason>, +model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, +options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), requestOptions: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), hookOwner: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook)>, signalOwner: Native.SignalOwner<Reason>, +parent: Abort.AbortSignal<Reason>, pricingOwner: Defaults.Owner<Error(Reason, Hook)>) -> IO(Run(Reason, Hook, G)):
  match dependencies pricingOwner:
    case Dependencies{context, _, _} Defaults.Owner{+pricing}:
      do IO<Run(Reason, Hook, G)>:
        +query : C.Callback<Unit, Bool> <- C.create(~Abort.AbortSignal<Reason>, ~Unit, ~Bool, ~(Native.aborted(~Reason)), parent)
        requested : Maybe<&2, String> = Core.requestedTier(Choice, Options.settings(T.JsonValue, Choice, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, options))
        request : IO(Result<&2, &1, Error(Reason, Hook), Acquire.Owner(Reason)>) = acquire(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, context, parent, model, transcript, options, requestOptions)
        Session.startWithContextAndCleanup(~Value.Value, ~G, ~(Error(Reason, Hook)), ~Environment, ~render, Acquire.Owner(Reason), Life.initial(Value.Value, G, T.JsonValue, model, timestamp), query, request, sink => owner => output => process(~Reason, ~Hook, ~G, dependencies, model, requested, pricing, sink, owner, output), release(Reason, Hook), retire(Reason, Hook, signalOwner, query, hookOwner, Defaults.Owner{pricing}, cleanup), environment)

def selected(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Hook) -> String, dependencies: Dependencies<Reason>, +model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), requestOptions: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), hookOwner: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook)>, pair: Native.SignalOwner<Reason> & Abort.AbortSignal<Reason>) -> IO(Run(Reason, Hook, G)):
  match pair:
    case Tuple{signalOwner, parent}:
      do IO<Run(Reason, Hook, G)>:
        pricingOwner : Defaults.Owner<Error(Reason, Hook)> <- Defaults.create(~(Error(Reason, Hook)), Default.modelId(model))
        priced(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, requestOptions, timestamp, environment, cleanup, hookOwner, signalOwner, parent, pricingOwner)

def adapted(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Hook) -> String, dependencies: Dependencies<Reason>, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), pair: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook)> & Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch)) -> IO(Run(Reason, Hook, G)):
  match pair:
    case Tuple{hookOwner, +requestOptions}:
      do IO<Run(Reason, Hook, G)>:
        signalOwner : Native.SignalOwner<Reason> <- Native.select(Reason, Native.requestedSignal(Reason, System.SourceError(), Hook, Telemetry, Fetch, requestOptions))
        selected(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, requestOptions, timestamp, environment, cleanup, hookOwner, Native.signal(Reason, signalOwner))

# Native system-owned transport assembly. The provider timestamp, SSE policy,
# error renderer and finalizer remain explicit at this internal boundary.
def streamAt(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Hook) -> String, dependencies: Dependencies<Reason>, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, +options: Core.RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit)) -> IO(Run(Reason, Hook, G)):
  do IO<Run(Reason, Hook, G)>:
    pair : Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Inner(Reason, Hook)> & Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch) <- HookOptions.create(~T.JsonValue, ~(T.Model<T.JsonValue>), ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch, ~Hook, ~(Inner(Reason, Hook)), ~(Core.hookError(Reason, System.SourceError(), Hook)), T.toProviderRequestOptions(T.JsonValue, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, Options.toStreamOptions(T.JsonValue, Choice, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, options)))
    adapted(~Choice, ~encodeChoice, ~Reason, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, timestamp, environment, cleanup, pair)
