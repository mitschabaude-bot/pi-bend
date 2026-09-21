import Base
import ../types.bend as T
import ./openai-responses-options.bend as Options
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-prepared-acquire.bend as Ready
import ./openai-responses-native-session.bend as Native
import ./openai-responses-native-session-error.bend as Errors
import ./openai-responses-default-session.bend as Default
import ./openai-responses-stream-defaults.bend as Defaults
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-scoped-process.bend as Process
import ./openai-responses-lifecycle.bend as Life
import ./openai-responses-session.bend as Session
import ./openai-request-headers.bend as Headers
import ../utils/provider-hook-map.bend as Hooks
import ../utils/provider-hook-options.bend as HookOptions
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as Value

def Error(-Reason: Data, -Source: Data, -Hook: Data) -> Data: Errors.Error<Reason, Source, Hook>
def Run(-Reason: Data, -Source: Data, -Hook: Data, -G: Data) -> Type: Session.Run<Value.Value, G, Error(Reason, Source, Hook)>
def PricingCallback(-Reason: Data, -Source: Data, -Hook: Data) -> Data: C.Callback<Pricing.PricingRequest, Result<&2, &2, Error(Reason, Source, Hook), T.Usage>>
def RequestOptions(-Choice: Data, -Reason: Data, -Telemetry: Data, -Fetch: Data, -Hook: Data) -> Data:
  Options.OpenAIResponsesOptions<T.JsonValue, Choice, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook>

def hookError(-Reason: Data, -Source: Data, -Hook: Data, cause: Hook) -> Error(Reason, Source, Hook): Errors.HookFailure{cause}

def tier(value: Maybe<&2, T.Nullable<Options.ServiceTier>>) -> Maybe<&2, String>:
  match value:
    case Some{T.PresentValue{selected}}: Some{Options.tierName(selected)}
    case _: None{}

def requestedTier(-Choice: Data, settings: Options.ResponsesSettings<Choice>) -> Maybe<&2, String>:
  match settings:
    case Options.ResponsesSettings{_, _, value, _}: tier(value)

def userAgent(-Reason: Data, -Source: Data, dependencies: Default.Dependencies<Reason, Source>) -> String:
  match dependencies:
    case Default.Dependencies{_, Headers.Defaults{name, _, _, _}, _, _, _, _, _}: name

def retire(-Reason: Data, -Source: Data, -Hook: Data, signalOwner: Native.SignalOwner<Reason>, query: C.Callback<Unit, Bool>, hooks: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook)>, pricing: Defaults.Owner<Error(Reason, Source, Hook)>, dependencies: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Native.cleanup(Reason, signalOwner, query)
    Hooks.dispose(T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook), hooks)
    Defaults.dispose(Error(Reason, Source, Hook), pricing)
    dependencies

# The successful acquisition owner carries the original preparation. Payload
# hook replacement cannot overwrite the grammar map used to decode tool calls.
def process(~Reason: Data, ~Source: Data, ~Hook: Data, ~G: Data, dependencies: Default.Dependencies<Reason, Source>, model: T.Model<T.JsonValue>, requested: Maybe<&2, String>, pricing: PricingCallback(Reason, Source, Hook), sink: C.Callback<T.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, Error(Reason, Source, Hook), Unit>>, owner: Ready.Owner<Attempt.State(Reason)>, output: T.AssistantMessage<Value.Value, G>) -> IO(Life.Processed<Value.Value, G, Error(Reason, Source, Hook)>):
  match dependencies owner:
    case Default.Dependencies{_, _, _, _, hooks, _, synthesize} Ready.Owner{prepared, response}:
      Process.process(~Reason, ~G, ~(Error(Reason, Source, Hook)), ~(Errors.reader(Reason, Source, Hook)), response, output, sink, model, Defaults.options(Error(Reason, Source, Hook), requested, Default.grammar(prepared), pricing), hooks, synthesize, Errors.processing(Reason, Source, Hook), Errors.disposal(Reason, Source, Hook))

def release(-Reason: Data, -Source: Data, -Hook: Data, owner: Ready.Owner<Attempt.State(Reason)>) -> IO(Result<&2, &2, Error(Reason, Source, Hook), Unit>):
  Ready.release(Error(Reason, Source, Hook), Attempt.State(Reason), Process.release(Reason, Error(Reason, Source, Hook), Errors.release(Reason, Source, Hook)), owner)

def priced(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Source: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Source, Hook) -> String, +dependencies: Default.Dependencies<Reason, Source>, +model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, +options: RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), requestOptions: Native.Options(Reason, Source, Hook, Telemetry, Fetch), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), hookOwner: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook)>, signalOwner: Native.SignalOwner<Reason>, +parent: Abort.AbortSignal<Reason>, pricingOwner: Defaults.Owner<Error(Reason, Source, Hook)>) -> IO(Run(Reason, Source, Hook, G)):
  match pricingOwner:
    case Defaults.Owner{+pricing}:
      do IO<Run(Reason, Source, Hook, G)>:
        +query : C.Callback<Unit, Bool> <- C.create(~Abort.AbortSignal<Reason>, ~Unit, ~Bool, ~(Native.aborted(~Reason)), parent)
        requested : Maybe<&2, String> = requestedTier(Choice, Options.settings(T.JsonValue, Choice, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, options))
        acquire : IO(Result<&2, &1, Error(Reason, Source, Hook), Ready.Owner<Attempt.State(Reason)>>) = Ready.run(Error(Reason, Source, Hook), Attempt.State(Reason), Preparation.prepare(~Choice, ~encodeChoice, ~G, ~D, ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch, ~Hook, model, transcript, options, userAgent(Reason, Source, dependencies)), Errors.preparation(Reason, Source, Hook), prepared => Native.acquire(~Reason, ~Source, ~Hook, ~Telemetry, ~Fetch, Default.context(Reason, Source, Hook, dependencies, Pricing.defaultOptions(Error(Reason, Source, Hook))), parent, model, prepared, Native.withSignal(Reason, Source, Hook, Telemetry, Fetch, parent, requestOptions)))
        Session.startWithContextAndCleanup(~Value.Value, ~G, ~(Error(Reason, Source, Hook)), ~Environment, ~render, Ready.Owner<Attempt.State(Reason)>, Life.initial(Value.Value, G, T.JsonValue, model, timestamp), query, acquire, sink => owner => output => process(~Reason, ~Source, ~Hook, ~G, dependencies, model, requested, pricing, sink, owner, output), release(Reason, Source, Hook), retire(Reason, Source, Hook, signalOwner, query, hookOwner, Defaults.Owner{pricing}, cleanup), environment)

def selected(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Source: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Source, Hook) -> String, dependencies: Default.Dependencies<Reason, Source>, +model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, options: RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), requestOptions: Native.Options(Reason, Source, Hook, Telemetry, Fetch), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), hookOwner: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook)>, pair: Native.SignalOwner<Reason> & Abort.AbortSignal<Reason>) -> IO(Run(Reason, Source, Hook, G)):
  match pair:
    case Tuple{signalOwner, parent}:
      do IO<Run(Reason, Source, Hook, G)>:
        pricingOwner : Defaults.Owner<Error(Reason, Source, Hook)> <- Defaults.create(~(Error(Reason, Source, Hook)), Default.modelId(model))
        priced(~Choice, ~encodeChoice, ~Reason, ~Source, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, requestOptions, timestamp, environment, cleanup, hookOwner, signalOwner, parent, pricingOwner)

def adapted(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Source: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Source, Hook) -> String, dependencies: Default.Dependencies<Reason, Source>, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, options: RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit), pair: Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook)> & Native.Options(Reason, Source, Hook, Telemetry, Fetch)) -> IO(Run(Reason, Source, Hook, G)):
  match pair:
    case Tuple{hookOwner, +requestOptions}:
      do IO<Run(Reason, Source, Hook, G)>:
        signalOwner : Native.SignalOwner<Reason> <- Native.select(Reason, Native.requestedSignal(Reason, Source, Hook, Telemetry, Fetch, requestOptions))
        selected(~Choice, ~encodeChoice, ~Reason, ~Source, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, requestOptions, timestamp, environment, cleanup, hookOwner, Native.signal(Reason, signalOwner))

# Native provider assembly with explicit runtime dependencies and clock value.
# The outer factory still supplies transport selection, default error rendering
# and error rendering. Preparation and user hooks retain their typed causes.
def streamAt(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~Reason: Data, ~Source: Data, ~Hook: Data, ~G: Data, ~D: Data, ~Telemetry: Data, ~Fetch: Data, ~Environment: Data, ~render: Environment -> Error(Reason, Source, Hook) -> String, dependencies: Default.Dependencies<Reason, Source>, model: T.Model<T.JsonValue>, transcript: T.TranscriptContext<Value.Value, R.Record<Value.Value>, G, D>, +options: RequestOptions(Choice, Reason, Telemetry, Fetch, Hook), timestamp: F.F64, environment: Environment, cleanup: IO(Unit)) -> IO(Run(Reason, Source, Hook, G)):
  do IO<Run(Reason, Source, Hook, G)>:
    pair : Hooks.Owner<T.JsonValue, T.Model<T.JsonValue>, Error(Reason, Source, Hook)> & Native.Options(Reason, Source, Hook, Telemetry, Fetch) <- HookOptions.create(~T.JsonValue, ~T.Model<T.JsonValue>, ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch, ~Hook, ~(Error(Reason, Source, Hook)), ~(hookError(Reason, Source, Hook)), T.toProviderRequestOptions(T.JsonValue, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, Options.toStreamOptions(T.JsonValue, Choice, Abort.AbortSignal<Reason>, Telemetry, Fetch, Hook, options)))
    adapted(~Choice, ~encodeChoice, ~Reason, ~Source, ~Hook, ~G, ~D, ~Telemetry, ~Fetch, ~Environment, ~render, dependencies, model, transcript, options, timestamp, environment, cleanup, pair)
