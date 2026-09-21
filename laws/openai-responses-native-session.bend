import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-native-session.bend as Session
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Errors
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/http-response.bend as Response

law supplied_signal_selection_has_no_effects:
  for -Reason: Data
  for signal: Abort.AbortSignal<Reason>
  {Session.select(Reason, Some{signal}) == IO.pure(Session.SignalOwner<Reason>, Session.Supplied{signal}) : IO(Session.SignalOwner<Reason>)}

law supplied_signal_retirement_has_no_effects:
  for -Reason: Data
  for signal: Abort.AbortSignal<Reason>
  {Session.retireSignal(Reason, Session.Supplied{signal}) == IO.pure(Unit, Unit{}) : IO(Unit)}

law borrowing_preserves_supplied_signal:
  for -Reason: Data
  for signal: Abort.AbortSignal<Reason>
  {Session.signal(Reason, Session.Supplied{signal}) == (Session.Supplied{signal}, signal) : Session.SignalOwner<Reason> & Abort.AbortSignal<Reason>}

law borrowing_preserves_local_controller:
  for -Reason: Data
  for controller: Abort.AbortController<Reason>
  {Session.signal(Reason, Session.Local{controller}) == (Session.Local{controller}, Abort.signal(Reason, controller)) : Session.SignalOwner<Reason> & Abort.AbortSignal<Reason>}

law acquisition_preserves_owned_response:
  for -Reason: Data
  for -SourceError: Data
  for -HookError: Data
  for response: Response.Response<Attempt.State(Reason)>
  {Session.acquired(Reason, SourceError, HookError, Done{response}) == Done{response} : Session.Outcome(Reason, SourceError, HookError)}

law acquisition_preserves_typed_failure:
  for -Reason: Data
  for -SourceError: Data
  for -HookError: Data
  for cause: Acquire.Error<Errors.Error<Reason, SourceError, HookError>>
  {Session.acquired(Reason, SourceError, HookError, Fail{cause}) == Fail{Errors.AcquisitionFailure{cause}} : Session.Outcome(Reason, SourceError, HookError)}

law chosen_signal_reaches_retry_options:
  for -Reason: Data
  for -SourceError: Data
  for -HookError: Data
  for -Telemetry: Data
  for -CustomFetch: Data
  for signal: Abort.AbortSignal<Reason>
  for options: Session.Options(Reason, SourceError, HookError, Telemetry, CustomFetch)
  {Session.requestedSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, Session.withSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, signal, options)) == Some{signal} : Maybe<&2, Abort.AbortSignal<Reason>>}

# Independent projection: discard only cancellation, retaining every other
# canonical option and hook. Together with chosen_signal_reaches_retry_options,
# this specifies the complete signal-binding transformation.
def withoutSignal(-Reason: Data, -SourceError: Data, -HookError: Data, -Telemetry: Data, -CustomFetch: Data, value: Session.Options(Reason, SourceError, HookError, Telemetry, CustomFetch)) -> Session.Options(Reason, SourceError, HookError, Telemetry, CustomFetch):
  match value:
    case T.ProviderRequestOptions{_, telemetry, key, fetch, env, payload, response, headers, timeout, count, delay}:
      T.ProviderRequestOptions{None{}, telemetry, key, fetch, env, payload, response, headers, timeout, count, delay}

law binding_preserves_other_options:
  for -Reason: Data
  for -SourceError: Data
  for -HookError: Data
  for -Telemetry: Data
  for -CustomFetch: Data
  for signal: Abort.AbortSignal<Reason>
  for options: Session.Options(Reason, SourceError, HookError, Telemetry, CustomFetch)
  {withoutSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, Session.withSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, signal, options)) == withoutSignal(Reason, SourceError, HookError, Telemetry, CustomFetch, options) : Session.Options(Reason, SourceError, HookError, Telemetry, CustomFetch)}
