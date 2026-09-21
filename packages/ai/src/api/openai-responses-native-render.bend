import Base
import ./openai-responses-native-session-error.bend as Error
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-preparation-error.bend as PrepareText
import ./openai-responses-envelope-error.bend as EnvelopeText
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-configured-acquire.bend as Acquire
import ./openai-responses-reader.bend as Reader
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-responses-stream.bend as Stream
import ./openai-responses-stream-error.bend as Format
import ./openai-responses-terminal.bend as Terminal
import ./constrained-sampling.bend as Sampling
import ./openai-body-responses-reader.bend as Body
import ../utils/provider-request.bend as Request
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-error.bend as RetryText
import ../utils/provider-retry-options.bend as Options
import ../utils/error-body.bend as Diagnostic
import ../../../runtime/src/http-response-progress.bend as Progress

# Pure functions are affine values. Only the selected leaf renderer is used;
# no callback server or shared mutable registry is needed for presentation.
type Leaves<-Reason: Data, -Source: Data, -Hook: Data> is Type:
  Leaves{hook: Hook -> Format.Formatted(), attempt: Attempt.Error(Reason, Source) -> Format.Formatted(), reader: Reader.Error<Scoped.TransportError(Reason)> -> Format.Formatted(), disposal: Body.CloseError<Scoped.TransportError(Reason)> -> Format.Formatted(), release: Progress.Error<Attempt.ReadError(Reason)> -> Format.Formatted()}

def hook(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, cause: Hook) -> Format.Formatted():
  match leaves:
    case Leaves{render, _, _, _, _}: render(cause)

def attempt(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, cause: Attempt.Error(Reason, Source)) -> Format.Formatted():
  match leaves:
    case Leaves{_, render, _, _, _}: render(cause)

def reader(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, cause: Reader.Error<Scoped.TransportError(Reason)>) -> Format.Formatted():
  match leaves:
    case Leaves{_, _, render, _, _}: render(cause)

def disposal(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, cause: Body.CloseError<Scoped.TransportError(Reason)>) -> Format.Formatted():
  match leaves:
    case Leaves{_, _, _, render, _}: render(cause)

def release(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, cause: Progress.Error<Attempt.ReadError(Reason)>) -> Format.Formatted():
  match leaves:
    case Leaves{_, _, _, _, render}: render(cause)

def retryText(result: Result<&2, &2, RetryText.FormattingError, RetryText.RenderedError>) -> Format.Formatted():
  match result:
    case Fail{RetryText.NumberFormattingFailure{}}: Fail{Diagnostic.NumberFormattingFailure{}}
    case Done{RetryText.RenderedError{_, message}}: Done{message}

def options(cause: Options.Error) -> String:
  match cause:
    case Options.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Options.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

# Traverse the finite immutable cause tree. Wrappers do not change the original
# request diagnostic; a response-hook cleanup error remains in the original
# typed value and never replaces the primary presentation.
def render(-Reason: Data, -Source: Data, -Hook: Data, leaves: Leaves<Reason, Source, Hook>, error: Error.Error<Reason, Source, Hook>) -> Format.Formatted():
  match error:
    case Error.PreparationFailure{cause}: Done{PrepareText.format(cause)}
    case Error.HookFailure{cause}: hook(Reason, Source, Hook, leaves, cause)
    case Error.EnvelopeFailure{cause}: Done{EnvelopeText.format(cause)}
    case Error.AttemptFailure{cause}: attempt(Reason, Source, Hook, leaves, cause)
    case Error.ReaderFailure{cause}: reader(Reason, Source, Hook, leaves, cause)
    case Error.DisposalFailure{cause}: disposal(Reason, Source, Hook, leaves, cause)
    case Error.ReleaseFailure{cause}: release(Reason, Source, Hook, leaves, cause)
    case Error.AcquisitionFailure{Acquire.InvalidOptions{cause}}: Done{options(cause)}
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.PayloadFailure{cause}}}: render(Reason, Source, Hook, leaves, cause)
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.ResponseFailure{cause, _}}}: render(Reason, Source, Hook, leaves, cause)
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{cause}}}}}: render(Reason, Source, Hook, leaves, cause)
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause, _, _, _, _, _}}}}}}: render(Reason, Source, Hook, leaves, cause)
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}}: Done{"Request aborted"}
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.SleepRejected{_}}}}: Done{"Retry delay is outside the native timer range"}
    case Error.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.DelayRejected{cause, message}}}}: retryText(RetryText.delayError(cause, message))
    case Error.ProcessingFailure{Stream.ReadFailure{cause}}: render(Reason, Source, Hook, leaves, cause)
    case Error.ProcessingFailure{Stream.EmitFailure{cause}}: render(Reason, Source, Hook, leaves, cause)
    case Error.ProcessingFailure{Stream.ResolveServiceTierFailure{cause}}: render(Reason, Source, Hook, leaves, cause)
    case Error.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{cause}}: render(Reason, Source, Hook, leaves, cause)
    case Error.ProcessingFailure{Stream.ContentFailure{cause}}: Done{Sampling.errorMessage(cause)}
    case Error.ProcessingFailure{Stream.TerminalFailure{cause}}: Done{Terminal.errorMessage(cause)}
