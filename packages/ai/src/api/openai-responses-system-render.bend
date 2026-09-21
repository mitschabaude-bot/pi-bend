import Base
import ./openai-responses-system-error.bend as Error
import ./openai-responses-cleartext-system-runtime.bend as System
import ./openai-responses-native-render.bend as Native
import ./openai-responses-stream-error.bend as Format
import ./openai-responses-stream.bend as Stream
import ./openai-responses-terminal.bend as Terminal
import ./constrained-sampling.bend as Sampling
import ../utils/provider-owned-acquire.bend as Owned

# System ownership adds initialization failures to the native request domain.
# Both renderers are affine pure functions, borrowed runtime handles are absent.
# Recursive processing failures retain this full domain rather than narrowing
# initialization or cleanup failures into an application hook error.
def render(-Reason: Data, -Hook: Data, leaves: Native.Leaves<Reason, System.SourceError(), Hook>, initialize: System.Error -> Format.Formatted(), error: Error.Error<Reason, Hook>) -> Format.Formatted():
  match error:
    case Error.AcquisitionFailure{Owned.InitializationFailure{cause}}: initialize(cause)
    case Error.AcquisitionFailure{Owned.AcquisitionFailure{cause}}: Native.render(Reason, System.SourceError(), Hook, leaves, cause)
    case Error.ReleaseFailure{cause}: Native.render(Reason, System.SourceError(), Hook, leaves, cause)
    case Error.ReaderFailure{cause}: Native.reader(Reason, System.SourceError(), Hook, leaves, cause)
    case Error.DisposalFailure{cause}: Native.disposal(Reason, System.SourceError(), Hook, leaves, cause)
    case Error.ProcessingFailure{Stream.ReadFailure{cause}}: render(Reason, Hook, leaves, initialize, cause)
    case Error.ProcessingFailure{Stream.EmitFailure{cause}}: render(Reason, Hook, leaves, initialize, cause)
    case Error.ProcessingFailure{Stream.ResolveServiceTierFailure{cause}}: render(Reason, Hook, leaves, initialize, cause)
    case Error.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{cause}}: render(Reason, Hook, leaves, initialize, cause)
    case Error.ProcessingFailure{Stream.ContentFailure{cause}}: Done{Sampling.errorMessage(cause)}
    case Error.ProcessingFailure{Stream.TerminalFailure{cause}}: Done{Terminal.errorMessage(cause)}
