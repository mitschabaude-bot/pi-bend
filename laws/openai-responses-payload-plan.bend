import Base
import ../packages/ai/src/api/openai-responses-payload-plan.bend as P
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/api/openai-responses-native-session.bend as Native
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Errors
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as Acquire
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/record.bend as R

law validated_wire_retains_original_preparation_and_callbacks:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for original: Preparation.Prepared
  for wire: Envelope.Request
  for response: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>)>
  for retry: Retry.ProviderRetryOptions<Reason>
  {P.checked(Reason, Source, Hook, original, response, retry, False{}, Done{wire}) == Done{P.Wire{original, wire, response, retry}} : Result<&2, &2, Errors.Error<Reason, Source, Hook>, P.Wire<Reason, Source, Hook>>}

law payload_failure_preserves_typed_cause:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for -Telemetry: Data
  for -Fetch: Data
  for original: Preparation.Prepared
  for options: Native.Options(Reason, Source, Hook, Telemetry, Fetch)
  for retry: Retry.ProviderRetryOptions<Reason>
  for cause: Request.Error<Errors.Error<Reason, Source, Hook>>
  {P.selected(Reason, Source, Hook, Telemetry, Fetch, original, options, retry, Fail{cause}) == Fail{Errors.AcquisitionFailure{Acquire.AcquisitionFailed{cause}}} : Result<&2, &2, Errors.Error<Reason, Source, Hook>, P.Plan<Reason, Source, Hook, Telemetry, Fetch>>}

# Independent specification of the options that may reach a later request:
# only the payload callback disappears; every other field is retained.
def subsequent(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, options: Native.Options(Reason, Source, Hook, Telemetry, Fetch)) -> Native.Options(Reason, Source, Hook, Telemetry, Fetch):
  match options:
    case T.ProviderRequestOptions{signal, telemetry, key, fetch, env, _, response, headers, timeout, count, delay}:
      T.ProviderRequestOptions{signal, telemetry, key, fetch, env, None{}, response, headers, timeout, count, delay}

law selected_payload_cannot_invoke_payload_hook_again:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for -Telemetry: Data
  for -Fetch: Data
  for +options: Native.Options(Reason, Source, Hook, Telemetry, Fetch)
  {P.withoutPayload(Reason, Source, Hook, Telemetry, Fetch, options) == subsequent(Reason, Source, Hook, Telemetry, Fetch, options) : Native.Options(Reason, Source, Hook, Telemetry, Fetch)}

law envelope_failure_retains_cause_without_cancellation:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for cause: Envelope.Error
  {P.rejected(Reason, Source, Hook, cause, False{}) == Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{Errors.EnvelopeFailure{cause}}}}}} : Errors.Error<Reason, Source, Hook>}

law observed_cancellation_takes_precedence_over_envelope_failure:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for cause: Envelope.Error
  {P.rejected(Reason, Source, Hook, cause, True{}) == Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}} : Errors.Error<Reason, Source, Hook>}

law observed_cancellation_prevents_runtime_initialization:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for original: Preparation.Prepared
  for response: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>)>
  for retry: Retry.ProviderRetryOptions<Reason>
  for result: Result<&2, &2, Envelope.Error, Envelope.Request>
  {P.checked(Reason, Source, Hook, original, response, retry, True{}, result) == Fail{Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}}} : Result<&2, &2, Errors.Error<Reason, Source, Hook>, P.Wire<Reason, Source, Hook>>}
