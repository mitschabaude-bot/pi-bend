import Base
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as A
import ../packages/ai/src/api/openai-responses-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-request-headers.bend as Header
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-options.bend as Options
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/url-absolute.bend as URL
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/callback.bend as C

def encode(value: Envelope.Error) -> String: "envelope"

# Templates require closed types. Every runtime argument is universal at the
# String reason/error, Unit telemetry/fetch/body-state instantiation.
law invalid_configuration_has_no_effects:
  for url: URL.Context
  for defaults: Header.Defaults
  for model: T.Model<T.JsonValue>
  for prepared: Preparation.Prepared
  for settings: T.ProviderRequestOptions<T.Model<T.JsonValue>, Abort.AbortSignal<String>, Unit, Unit, T.JsonValue, String>
  for request: C.Callback<Envelope.Request, Acquire.Outcome(String, Unit)>
  for effects: Retry.Effects<String>
  for release: Response.Response<Unit> -> IO(Result<&2, &2, String, Unit>)
  for cause: Options.Error
  {A.resolved(~String, ~Unit, ~Unit, ~String, ~Unit, ~encode, url, defaults, model, prepared, settings, request, effects, release, Fail{cause}) == IO.pure(A.Outcome(String, Unit), Fail{A.InvalidOptions{cause}}) : IO(A.Outcome(String, Unit))}

law successful_body_transfers_unchanged:
  for -E: Data
  for -State: Type
  for body: Response.Response<State>
  {A.completed(E, State, Done{body}) == Done{body} : A.Outcome(E, State)}

law acquisition_error_retains_cause:
  for -E: Data
  for -State: Type
  for cause: Request.Error<E>
  {A.completed(E, State, Fail{cause}) == Fail{A.AcquisitionFailed{cause}} : A.Outcome(E, State)}
