import Base
import ../types.bend as T
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-prepare.bend as Preparation
import ./openai-request-headers.bend as Header
import ../utils/provider-request.bend as Request
import ../utils/provider-retry.bend as Retry
import ../utils/provider-response-view.bend as View
import ../../../runtime/src/url-absolute.bend as URL
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F

# Immutable client configuration is separate from the hook-selected payload.
# The caller's error domain embeds envelope, transport and hook errors without
# flattening them to strings. The attempt callback owns failed response bodies.
type Client is Data:
  Client{url: URL.Context, defaults: Header.Defaults, apiKey: String, headers: T.ProviderHeaders(), baseUrl: String, timeout: Maybe<&2, F.F64>}

def prepared(url: URL.Context, defaults: Header.Defaults, timeout: Maybe<&2, F.F64>, value: Preparation.Prepared) -> Client & T.JsonValue:
  match value:
    case Preparation.Prepared{apiKey, baseUrl, headers, payload, _, _, _}:
      (Client{url, defaults, apiKey, headers, baseUrl, timeout}, payload)

def envelope(client: Client, payload: T.JsonValue) -> Result<&2, &2, Envelope.Error, Envelope.Request>:
  match client:
    case Client{url, defaults, apiKey, headers, baseUrl, timeout}:
      Envelope.prepare(url, defaults, apiKey, headers, baseUrl, timeout, payload)

def Outcome(-E: Data, -State: Type) -> Type:
  Result<&2, &1, Retry.RequestFailure<E>, Response.Response<State>>

type Environment<-E: Data, -State: Type> is Data:
  Environment{client: Client, request: C.Callback<Envelope.Request, Outcome(E, State)>}

# Invalid serialization/configuration is terminal and never invokes transport.
# A successful envelope is passed unchanged to the borrowed attempt callback.
def dispatch(-E: Data, -State: Type, encodeError: Envelope.Error -> E, request: C.Callback<Envelope.Request, Outcome(E, State)>, value: Result<&2, &2, Envelope.Error, Envelope.Request>) -> IO(Outcome(E, State)):
  match value:
    case Fail{cause}: IO.pure(Outcome(E, State), Fail{Retry.Other{encodeError(cause)}})
    case Done{wire}: C.call(Envelope.Request, Outcome(E, State), request, wire)

def invoke(~E: Data, ~State: Type, ~encodeError: Envelope.Error -> E, environment: Environment<E, State>, payload: T.JsonValue) -> IO(Outcome(E, State)):
  match environment:
    case Environment{client, request}: dispatch(E, State, encodeError, request, envelope(client, payload))

# Both hooks and the attempt callback are borrowed. The bridge exists only
# during acquisition; a returned response owns its body independently of it.
# The existing hook driver selects payload once, retries with that same value,
# invokes the response hook once, and releases a body rejected by that hook.
def run(~Reason: Data, ~E: Data, ~State: Type, ~encodeError: Envelope.Error -> E, client: Client, model: T.Model<T.JsonValue>, payload: T.JsonValue, onPayload: Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, request: C.Callback<Envelope.Request, Outcome(E, State)>, effects: Retry.Effects<Reason>, options: Retry.ProviderRetryOptions<Reason>, release: Response.Response<State> -> IO(Result<&2, &2, E, Unit>)) -> IO(Result<&2, &1, Request.Error<E>, Response.Response<State>>):
  do IO<Result<&2, &1, Request.Error<E>, Response.Response<State>>>:
    +bridge : C.Callback<T.JsonValue, Outcome(E, State)> <- C.create(~Environment<E, State>, ~T.JsonValue, ~Outcome(E, State), ~(invoke(~E, ~State, ~encodeError)), Environment{client, request})
    result : Result<&2, &1, Request.Error<E>, Response.Response<State>> <- Request.run(~Reason, ~T.JsonValue, ~(T.Model<T.JsonValue>), ~E, ~(Response.Response<State>), model, payload, onPayload, onResponse, bridge, effects, options, View.inspect(State), release)
    C.dispose(T.JsonValue, Outcome(E, State), bridge)
    return result
