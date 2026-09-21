import Base
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-configured-acquire.bend as Acquire
import ./openai-responses-reader.bend as Reader
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-responses-stream.bend as Stream
import ./openai-body-responses-reader.bend as Body
import ../../../runtime/src/http-response-progress.bend as Progress

# A finite immutable cause tree. Hook errors keep their application type;
# transport, request policy and processing stages retain their typed causes.
# Rendering belongs to the provider boundary and never controls retry policy.
type Error<-Reason: Data, -SourceError: Data, -HookError: Data> is Data:
  HookFailure{cause: HookError}
  EnvelopeFailure{cause: Envelope.Error}
  AttemptFailure{cause: Attempt.Error(Reason, SourceError)}
  AcquisitionFailure{cause: Acquire.Error<Error<Reason, SourceError, HookError>>}
  ReaderFailure{cause: Reader.Error<Scoped.TransportError(Reason)>}
  ProcessingFailure{cause: Stream.Error<Error<Reason, SourceError, HookError>>}
  DisposalFailure{cause: Body.CloseError<Scoped.TransportError(Reason)>}
  ReleaseFailure{cause: Progress.Error<Attempt.ReadError(Reason)>}

def envelope(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Envelope.Error) -> Error<Reason, SourceError, HookError>: EnvelopeFailure{cause}
def attempt(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Attempt.Error(Reason, SourceError)) -> Error<Reason, SourceError, HookError>: AttemptFailure{cause}
def reader(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Reader.Error<Scoped.TransportError(Reason)>) -> Error<Reason, SourceError, HookError>: ReaderFailure{cause}
def processing(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Stream.Error<Error<Reason, SourceError, HookError>>) -> Error<Reason, SourceError, HookError>: ProcessingFailure{cause}
def disposal(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Body.CloseError<Scoped.TransportError(Reason)>) -> Error<Reason, SourceError, HookError>: DisposalFailure{cause}
def release(-Reason: Data, -SourceError: Data, -HookError: Data, cause: Progress.Error<Attempt.ReadError(Reason)>) -> Error<Reason, SourceError, HookError>: ReleaseFailure{cause}
