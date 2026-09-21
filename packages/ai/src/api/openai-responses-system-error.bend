import Base
import ./openai-responses-owned-acquire.bend as Acquire
import ./openai-responses-reader.bend as Reader
import ./openai-responses-scoped-reader.bend as Scoped
import ./openai-body-responses-reader.bend as Body
import ./openai-responses-stream.bend as Stream

# Acquisition preserves both runtime-initialization and native request causes.
# Processing can additionally contain recursive sink/pricing failures from this
# provider domain. Never narrow those causes back into the acquisition domain.
type Error<-Reason: Data, -Hook: Data> is Data:
  AcquisitionFailure{cause: Acquire.Error(Reason, Hook)}
  ReaderFailure{cause: Reader.Error<Scoped.TransportError(Reason)>}
  ProcessingFailure{cause: Stream.Error<Error<Reason, Hook>>}
  DisposalFailure{cause: Body.CloseError<Scoped.TransportError(Reason)>}
  ReleaseFailure{cause: Acquire.Inner(Reason, Hook)}

def acquired(-Reason: Data, -Hook: Data, -Owner: Type, result: Result<&2, &1, Acquire.Error(Reason, Hook), Owner>) -> Result<&2, &1, Error<Reason, Hook>, Owner>:
  match result:
    case Fail{cause}: Fail{AcquisitionFailure{cause}}
    case Done{owner}: Done{owner}

def released(-Reason: Data, -Hook: Data, result: Result<&2, &2, Acquire.Inner(Reason, Hook), Unit>) -> Result<&2, &2, Error<Reason, Hook>, Unit>:
  match result:
    case Fail{cause}: Fail{ReleaseFailure{cause}}
    case Done{value}: Done{value}

def reader(-Reason: Data, -Hook: Data, cause: Reader.Error<Scoped.TransportError(Reason)>) -> Error<Reason, Hook>: ReaderFailure{cause}
def processing(-Reason: Data, -Hook: Data, cause: Stream.Error<Error<Reason, Hook>>) -> Error<Reason, Hook>: ProcessingFailure{cause}
def disposal(-Reason: Data, -Hook: Data, cause: Body.CloseError<Scoped.TransportError(Reason)>) -> Error<Reason, Hook>: DisposalFailure{cause}
