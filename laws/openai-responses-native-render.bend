import Base
import ../packages/ai/src/api/openai-responses-native-render.bend as Render
import ../packages/ai/src/api/openai-responses-native-session-error.bend as E
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/f64.bend as F

law payload_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.PayloadFailure{cause}}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law response_cleanup_cannot_replace_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  for cleanup: Result<&2, &2, E.Error<Reason, Source, Hook>, Unit>
  {Render.render(Reason, Source, Hook, leaves, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.ResponseFailure{cause, cleanup}}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law provider_retry_metadata_does_not_replace_original_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  for message: String
  for status: Maybe<&2, F.F64>
  for retry: Maybe<&2, String>
  for milliseconds: Maybe<&2, String>
  for seconds: Maybe<&2, String>
  {Render.render(Reason, Source, Hook, leaves, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause, message, status, retry, milliseconds, seconds}}}}}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law ordinary_request_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{cause}}}}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law read_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.ProcessingFailure{Stream.ReadFailure{cause}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law emit_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.ProcessingFailure{Stream.EmitFailure{cause}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law tier_resolution_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.ProcessingFailure{Stream.ResolveServiceTierFailure{cause}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}

law pricing_wrapper_preserves_primary_diagnostic:
  for -Reason: Data
  for -Source: Data
  for -Hook: Data
  for leaves: Render.Leaves<Reason, Source, Hook>
  for cause: E.Error<Reason, Source, Hook>
  {Render.render(Reason, Source, Hook, leaves, E.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{cause}}) == Render.render(Reason, Source, Hook, leaves, cause) : Format.Formatted()}
