import Base
import ../types.bend as T
import ./openai-responses-native-session-error.bend as Errors
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-cleartext-request.bend as Request
import ./openai-responses-configured-acquire.bend as Acquire
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-fetch.bend as Fetch
import ./openai-responses-prepare.bend as Preparation
import ./openai-request-headers.bend as Headers
import ./openai-responses-scoped-process.bend as Process
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-responses-session.bend as Session
import ./openai-sse-reader.bend as SSE
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-config.bend as RetryConfig
import ../utils/provider-retry-options.bend as RetryOptions
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/url-absolute.bend as URL
import ../../../runtime/src/callback.bend as C

# Borrowed provider dependencies. Their owner must outlive Session.wait.
# This assembly currently uses the native cleartext transport; TLS selection
# belongs to the future public provider factory, not this body/session layer.
type Context<-Reason: Data, -SourceError: Data, -HookError: Data> is Data:
  Context{url: URL.Context, headers: Headers.Defaults, fetch: C.Callback<Fetch.Input<Reason>, Attempt.FetchResult(Reason, SourceError)>, retry: Retry.Effects<Reason>, pricing: Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>, hooks: SSE.Hooks<Scoped.TransportError(Reason)>, diagnosticLimit: Nat, synthesize: Bool}

def Options(-Reason: Data, -SourceError: Data, -HookError: Data, -Telemetry: Data, -CustomFetch: Data) -> Data:
  T.ProviderRequestOptions<T.Model<T.JsonValue>, Abort.AbortSignal<Reason>, Telemetry, CustomFetch, T.JsonValue, Errors.Error<Reason, SourceError, HookError>>
def Outcome(-Reason: Data, -SourceError: Data, -HookError: Data) -> Type:
  Result<&2, &1, Errors.Error<Reason, SourceError, HookError>, Response.Response<Attempt.State(Reason)>>

type SignalOwner<-Reason: Data> is Type:
  Supplied{signal: Abort.AbortSignal<Reason>}
  Local{controller: Abort.AbortController<Reason>}

def select(-Reason: Data, value: Maybe<&2, Abort.AbortSignal<Reason>>) -> IO(SignalOwner<Reason>):
  match value:
    case Some{signal}: IO.pure(SignalOwner<Reason>, Supplied{signal})
    case None{}:
      do IO<SignalOwner<Reason>>:
        controller : Abort.AbortController<Reason> <- Abort.new(Reason)
        return Local{controller}

def signal(-Reason: Data, owner: SignalOwner<Reason>) -> SignalOwner<Reason> & Abort.AbortSignal<Reason>:
  match owner:
    case Supplied{+value}: (Supplied{value}, value)
    case Local{+controller}: (Local{controller}, Abort.signal(Reason, controller))

def retireSignal(-Reason: Data, owner: SignalOwner<Reason>) -> IO(Unit):
  match owner:
    case Supplied{_}: IO.pure(Unit, Unit{})
    case Local{controller}: Abort.dispose(Reason, controller)

def aborted(~Reason: Data, parent: Abort.AbortSignal<Reason>, unused: Unit) -> IO(Bool): Abort.aborted(Reason, parent)

def cleanup(-Reason: Data, owner: SignalOwner<Reason>, query: C.Callback<Unit, Bool>) -> IO(Unit):
  do IO<Unit>:
    C.dispose(Unit, Bool, query)
    retireSignal(Reason, owner)

def requestedSignal(-Reason: Data, -SourceError: Data, -HookError: Data, -Telemetry: Data, -CustomFetch: Data, options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch)) -> Maybe<&2, Abort.AbortSignal<Reason>>:
  match options:
    case T.ProviderRequestOptions{value, _, _, _, _, _, _, _, _, _, _}: value

# Bind the selected parent once: retries, HTTP attempts and final classification
# observe the same cancellation. Every other option and borrowed hook survives.
def withSignal(-Reason: Data, -SourceError: Data, -HookError: Data, -Telemetry: Data, -CustomFetch: Data, parent: Abort.AbortSignal<Reason>, options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch)) -> Options(Reason, SourceError, HookError, Telemetry, CustomFetch):
  match options:
    case T.ProviderRequestOptions{_, telemetry, key, fetch, env, payload, response, headers, timeout, count, delay}:
      T.ProviderRequestOptions{Some{parent}, telemetry, key, fetch, env, payload, response, headers, timeout, count, delay}

def acquired(-Reason: Data, -SourceError: Data, -HookError: Data, value: Acquire.Outcome(Errors.Error<Reason, SourceError, HookError>, Attempt.State(Reason))) -> Outcome(Reason, SourceError, HookError):
  match value:
    case Fail{cause}: Fail{Errors.AcquisitionFailure{cause}}
    case Done{response}: Done{response}

# The request factory lives across retries but is retired before response-body
# processing. Returned bodies own their transport independently of the factory.
def validated(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, context: Context<Reason, SourceError, HookError>, parent: Abort.AbortSignal<Reason>, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch), validation: Result<&2, &2, RetryOptions.Error, Retry.ProviderRetryOptions<Reason>>) -> IO(Outcome(Reason, SourceError, HookError)):
  match context validation:
    case _ Fail{cause}: IO.pure(Outcome(Reason, SourceError, HookError), Fail{Errors.AcquisitionFailure{Acquire.InvalidOptions{cause}}})
    case Context{url, headers, fetch, retry, _, _, limit, _} Done{retryOptions}:
      do IO<Outcome(Reason, SourceError, HookError)>:
        +request : C.Callback<Envelope.Request, Request.Outcome(Reason, Errors.Error<Reason, SourceError, HookError>)> <- Request.create(~Reason, ~SourceError, ~(Errors.Error<Reason, SourceError, HookError>), ~(Errors.attempt(Reason, SourceError, HookError)), parent, fetch, limit)
        result : Acquire.Outcome(Errors.Error<Reason, SourceError, HookError>, Attempt.State(Reason)) <- Acquire.resolved(~Reason, ~Telemetry, ~CustomFetch, ~(Errors.Error<Reason, SourceError, HookError>), ~(Attempt.State(Reason)), ~(Errors.envelope(Reason, SourceError, HookError)), url, headers, model, prepared, options, request, retry, Process.release(Reason, Errors.Error<Reason, SourceError, HookError>, Errors.release(Reason, SourceError, HookError)), Done{retryOptions})
        C.dispose(Envelope.Request, Request.Outcome(Reason, Errors.Error<Reason, SourceError, HookError>), request)
        return acquired(Reason, SourceError, HookError, result)

def acquire(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, context: Context<Reason, SourceError, HookError>, parent: Abort.AbortSignal<Reason>, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, +options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch)) -> IO(Outcome(Reason, SourceError, HookError)):
  validated(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, context, parent, model, prepared, options, RetryConfig.request(T.Model<T.JsonValue>, Reason, Telemetry, CustomFetch, T.JsonValue, Errors.Error<Reason, SourceError, HookError>, options))

# Retire the selected signal/query before the provider dependencies they used.
def cleanupWithDependencies(-Reason: Data, owner: SignalOwner<Reason>, query: C.Callback<Unit, Bool>, dependencies: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    cleanup(Reason, owner, query)
    dependencies

def selectedWithContextAndCleanup(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~Environment: Data, ~render: Environment -> Errors.Error<Reason, SourceError, HookError> -> String, +context: Context<Reason, SourceError, HookError>, initial: T.AssistantMessage<Value.Value, G>, +model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch), pair: SignalOwner<Reason> & Abort.AbortSignal<Reason>, environment: Environment, dependencies: IO(Unit)) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  match context pair:
    case Context{_, _, _, _, pricing, hooks, _, synthesize} Tuple{owner, +parent}:
      do IO<Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>>:
        +query : C.Callback<Unit, Bool> <- C.create(~Abort.AbortSignal<Reason>, ~Unit, ~Bool, ~(aborted(~Reason)), parent)
        Session.startWithContextAndCleanup(~Value.Value, ~G, ~(Errors.Error<Reason, SourceError, HookError>), ~Environment, ~render, Response.Response<Attempt.State(Reason)>, initial, query, acquire(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, context, parent, model, prepared, withSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, parent, options)), sink => response => output => Process.process(~Reason, ~G, ~(Errors.Error<Reason, SourceError, HookError>), ~(Errors.reader(Reason, SourceError, HookError)), response, output, sink, model, pricing, hooks, synthesize, Errors.processing(Reason, SourceError, HookError), Errors.disposal(Reason, SourceError, HookError)), Process.release(Reason, Errors.Error<Reason, SourceError, HookError>, Errors.release(Reason, SourceError, HookError)), cleanupWithDependencies(Reason, owner, query, dependencies), environment)

# Preparation is explicit at this modular boundary. Typed acquisition failures
# settle the same canonical stream through the existing driver.
def selected(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~render: Errors.Error<Reason, SourceError, HookError> -> String, +context: Context<Reason, SourceError, HookError>, initial: T.AssistantMessage<Value.Value, G>, +model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch), pair: SignalOwner<Reason> & Abort.AbortSignal<Reason>) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  selectedWithContextAndCleanup(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, ~G, ~Unit, ~(unused => render), context, initial, model, prepared, options, pair, Unit{}, IO.pure(Unit, Unit{}))

def startWithContextAndCleanup(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~Environment: Data, ~render: Environment -> Errors.Error<Reason, SourceError, HookError> -> String, context: Context<Reason, SourceError, HookError>, initial: T.AssistantMessage<Value.Value, G>, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, +options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch), environment: Environment, dependencies: IO(Unit)) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  do IO<Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>>:
    owner : SignalOwner<Reason> <- select(Reason, requestedSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, options))
    selectedWithContextAndCleanup(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, ~G, ~Environment, ~render, context, initial, model, prepared, options, signal(Reason, owner), environment, dependencies)
def start(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~render: Errors.Error<Reason, SourceError, HookError> -> String, context: Context<Reason, SourceError, HookError>, initial: T.AssistantMessage<Value.Value, G>, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, +options: Options(Reason, SourceError, HookError, Telemetry, CustomFetch)) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  startWithContextAndCleanup(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, ~G, ~Unit, ~(unused => render), context, initial, model, prepared, options, Unit{}, IO.pure(Unit, Unit{}))
