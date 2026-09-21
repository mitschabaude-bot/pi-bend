import Base
import ../types.bend as T
import ./openai-responses-acquire.bend as Acquire
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-prepare.bend as Preparation
import ./openai-request-headers.bend as Header
import ../utils/provider-request.bend as Request
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-config.bend as Config
import ../utils/provider-retry-options.bend as Options
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/url-absolute.bend as URL
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/callback.bend as C

type Error<-E: Data> is Data:
  InvalidOptions{cause: Options.Error}
  AcquisitionFailed{cause: Request.Error<E>}

def Outcome(-E: Data, -State: Type) -> Type:
  Result<&2, &1, Error<E>, Response.Response<State>>

# Failure wrapping does not inspect or retire a successfully transferred body.
def completed(-E: Data, -State: Type, value: Result<&2, &1, Request.Error<E>, Response.Response<State>>) -> Outcome(E, State):
  match value:
    case Fail{cause}: Fail{AcquisitionFailed{cause}}
    case Done{response}: Done{response}

def acquirePair(~Reason: Data, ~E: Data, ~State: Type, ~encodeError: Envelope.Error -> E, pair: Acquire.Client & T.JsonValue, model: T.Model<T.JsonValue>, onPayload: Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, request: C.Callback<Envelope.Request, Acquire.Outcome(E, State)>, effects: Retry.Effects<Reason>, retryOptions: Retry.ProviderRetryOptions<Reason>, release: Response.Response<State> -> IO(Result<&2, &2, E, Unit>)) -> IO(Outcome(E, State)):
  match pair:
    case Tuple{client, payload}:
      do IO<Outcome(E, State)>:
        result : Result<&2, &1, Request.Error<E>, Response.Response<State>> <- Acquire.run(~Reason, ~E, ~State, ~encodeError, client, model, payload, onPayload, onResponse, request, effects, retryOptions, release)
        return completed(E, State, result)

# Validation precedes hooks, bridge allocation and request effects. Preparation
# retains payload/credential policy; canonical options supply timeout and hooks.
# The caller borrows transport/effects configured for the same caller signal.
def resolved(~Reason: Data, ~Telemetry: Data, ~Fetch: Data, ~E: Data, ~State: Type, ~encodeError: Envelope.Error -> E, url: URL.Context, defaults: Header.Defaults, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, requestSettings: T.ProviderRequestOptions<T.Model<T.JsonValue>, Abort.AbortSignal<Reason>, Telemetry, Fetch, T.JsonValue, E>, request: C.Callback<Envelope.Request, Acquire.Outcome(E, State)>, effects: Retry.Effects<Reason>, release: Response.Response<State> -> IO(Result<&2, &2, E, Unit>), retryResult: Result<&2, &2, Options.Error, Retry.ProviderRetryOptions<Reason>>) -> IO(Outcome(E, State)):
  match requestSettings retryResult:
    case _ Fail{cause}: IO.pure(Outcome(E, State), Fail{InvalidOptions{cause}})
    case T.ProviderRequestOptions{_, _, _, _, _, onPayload, onResponse, _, timeout, _, _} Done{retryOptions}:
      acquirePair(~Reason, ~E, ~State, ~encodeError, Acquire.prepared(url, defaults, timeout, prepared), model, onPayload, onResponse, request, effects, retryOptions, release)

def run(~Reason: Data, ~Telemetry: Data, ~Fetch: Data, ~E: Data, ~State: Type, ~encodeError: Envelope.Error -> E, url: URL.Context, defaults: Header.Defaults, model: T.Model<T.JsonValue>, prepared: Preparation.Prepared, +requestSettings: T.ProviderRequestOptions<T.Model<T.JsonValue>, Abort.AbortSignal<Reason>, Telemetry, Fetch, T.JsonValue, E>, request: C.Callback<Envelope.Request, Acquire.Outcome(E, State)>, effects: Retry.Effects<Reason>, release: Response.Response<State> -> IO(Result<&2, &2, E, Unit>)) -> IO(Outcome(E, State)):
  resolved(~Reason, ~Telemetry, ~Fetch, ~E, ~State, ~encodeError, url, defaults, model, prepared, requestSettings, request, effects, release, Config.request(T.Model<T.JsonValue>, Reason, Telemetry, Fetch, T.JsonValue, E, requestSettings))
