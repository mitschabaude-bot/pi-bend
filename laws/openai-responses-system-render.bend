import Base
import ../packages/ai/src/api/openai-responses-system-render.bend as Render
import ../packages/ai/src/api/openai-responses-system-error.bend as E
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-native-render.bend as Native
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Inner
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/ai/src/utils/provider-owned-acquire.bend as Owned

law initialization_diagnostic_preserved:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: System.Error
  {Render.render(Reason, Hook, leaves, initialize, E.AcquisitionFailure{Owned.InitializationFailure{cause}}) == initialize(cause) : Format.Formatted()}

law request_diagnostic_preserved:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: Inner.Error<Reason, System.SourceError(), Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.AcquisitionFailure{Owned.AcquisitionFailure{cause}}) == Native.render(Reason, System.SourceError(), Hook, leaves, cause) : Format.Formatted()}

law release_diagnostic_preserved:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: Inner.Error<Reason, System.SourceError(), Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.ReleaseFailure{cause}) == Native.render(Reason, System.SourceError(), Hook, leaves, cause) : Format.Formatted()}

law read_wrapper_preserves_system_cause:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: E.Error<Reason, Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.ProcessingFailure{Stream.ReadFailure{cause}}) == Render.render(Reason, Hook, leaves, initialize, cause) : Format.Formatted()}

law emit_wrapper_preserves_system_cause:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: E.Error<Reason, Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.ProcessingFailure{Stream.EmitFailure{cause}}) == Render.render(Reason, Hook, leaves, initialize, cause) : Format.Formatted()}

law tier_wrapper_preserves_system_cause:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: E.Error<Reason, Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.ProcessingFailure{Stream.ResolveServiceTierFailure{cause}}) == Render.render(Reason, Hook, leaves, initialize, cause) : Format.Formatted()}

law pricing_wrapper_preserves_system_cause:
  for -Reason: Data
  for -Hook: Data
  for leaves: Native.Leaves<Reason, System.SourceError(), Hook>
  for initialize: System.Error -> Format.Formatted()
  for cause: E.Error<Reason, Hook>
  {Render.render(Reason, Hook, leaves, initialize, E.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{cause}}) == Render.render(Reason, Hook, leaves, initialize, cause) : Format.Formatted()}
