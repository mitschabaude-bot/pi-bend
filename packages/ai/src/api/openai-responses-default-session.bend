import Base
import ../types.bend as T
import ./openai-responses-native-session.bend as Native
import ./openai-responses-native-session-error.bend as Errors
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-fetch.bend as Fetch
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-stream-defaults.bend as Defaults
import ./openai-responses-stream-pricing.bend as Pricing
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-responses-session.bend as Session
import ./openai-request-headers.bend as Headers
import ./openai-sse-reader.bend as SSE
import ../utils/provider-retry.bend as Retry
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/url-absolute.bend as URL

# Transport dependencies remain explicit. The producer owns default pricing
# and the supplied dependency finalizer; all borrowers stop before retirement.
type Dependencies<-Reason: Data, -SourceError: Data> is Data:
  Dependencies{url: URL.Context, headers: Headers.Defaults, fetch: C.Callback<Fetch.Input<Reason>, Attempt.FetchResult(Reason, SourceError)>, retry: Retry.Effects<Reason>, hooks: SSE.Hooks<Scoped.TransportError(Reason)>, diagnosticLimit: Nat, synthesize: Bool}

def modelId(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def grammar(prepared: Preparation.Prepared) -> R.Record<String>:
  match prepared:
    case Preparation.Prepared{_, _, _, _, _, properties, _}: properties

def context(-Reason: Data, -SourceError: Data, -HookError: Data, dependencies: Dependencies<Reason, SourceError>, pricing: Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>) -> Native.Context<Reason, SourceError, HookError>:
  match dependencies:
    case Dependencies{url, headers, fetch, retry, hooks, limit, synthesize}: Native.Context{url, headers, fetch, retry, pricing, hooks, limit, synthesize}

def retire(-E: Data, owner: Defaults.Owner<E>, dependencies: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Defaults.dispose(E, owner)
    dependencies

def owned(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~Environment: Data, ~render: Environment -> Errors.Error<Reason, SourceError, HookError> -> String, dependencies: Dependencies<Reason, SourceError>, initial: T.AssistantMessage<Value.Value, G>, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, options: Native.Options(Reason, SourceError, HookError, Telemetry, CustomFetch), environment: Environment, cleanup: IO(Unit), pair: Defaults.Owner<Errors.Error<Reason, SourceError, HookError>> & Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  match pair:
    case Tuple{owner, pricing}:
      Native.startWithContextAndCleanup(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, ~G, ~Environment, ~render, context(Reason, SourceError, HookError, dependencies, pricing), initial, model, prepared, options, environment, retire(Errors.Error<Reason, SourceError, HookError>, owner, cleanup))

# Grammar mappings come from the same preparation result as the wire payload.
# The pricing policy captures this request's model ID, including custom IDs.
def startPrepared(~Reason: Data, ~SourceError: Data, ~HookError: Data, ~Telemetry: Data, ~CustomFetch: Data, ~G: Data, ~Environment: Data, ~render: Environment -> Errors.Error<Reason, SourceError, HookError> -> String, dependencies: Dependencies<Reason, SourceError>, initial: T.AssistantMessage<Value.Value, G>, +model: T.Model<T.JsonValue>, +prepared: Preparation.Prepared, options: Native.Options(Reason, SourceError, HookError, Telemetry, CustomFetch), requestedTier: Maybe<&2, String>, environment: Environment, cleanup: IO(Unit)) -> IO(Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>):
  do IO<Session.Run<Value.Value, G, Errors.Error<Reason, SourceError, HookError>>>:
    owner : Defaults.Owner<Errors.Error<Reason, SourceError, HookError>> <- Defaults.create(~(Errors.Error<Reason, SourceError, HookError>), modelId(model))
    owned(~Reason, ~SourceError, ~HookError, ~Telemetry, ~CustomFetch, ~G, ~Environment, ~render, dependencies, initial, model, prepared, options, environment, cleanup, Defaults.borrow(Errors.Error<Reason, SourceError, HookError>, owner, requestedTier, grammar(prepared)))
