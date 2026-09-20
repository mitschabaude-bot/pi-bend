import Base
import ./bounded-bytes.bend as Bytes
import ./http-response-progress.bend as Progress

# A limit applies to decoded HTTP body bytes, not headers/chunk delimiters.
# It is supplied by the caller; overflow never becomes successful truncation.
type PrimaryError<-E: Data> is Data:
  ReadFailure{error: Progress.Error<E>}
  ByteLimitExceeded{}

type Error<-E: Data> is Data:
  PrimaryFailure{error: PrimaryError<E>}
  CleanupFailure{error: Progress.Error<E>}
  FailureWithCleanup{primary: PrimaryError<E>, cleanup: Progress.Error<E>}

type Decision<-E: Data> is Data:
  Continue{buffer: Bytes.State}
  Finished{result: Result<&2, &2, PrimaryError<E>, List<&2, U32>>}

def buffered(-E: Data, buffer: Bytes.State) -> Decision<E>:
  match buffer:
    case Bytes.State{_, _, True{}}: Finished{Fail{ByteLimitExceeded{}}}
    case other: Continue{other}

def completed(-E: Data, result: Result<&2, &2, Bytes.Error, List<&2, U32>>) -> Decision<E>:
  match result:
    case Fail{_}: Finished{Fail{ByteLimitExceeded{}}}
    case Done{bytes}: Finished{Done{bytes}}

def next(-E: Data, buffer: Bytes.State, result: Result<&2, &2, Progress.Error<E>, Maybe<&2, List<&2, U32>>>) -> Decision<E>:
  match result:
    case Fail{error}: Finished{Fail{ReadFailure{error}}}
    case Done{None{}}: completed(E, Bytes.finish(buffer))
    case Done{Some{bytes}}: buffered(E, Bytes.consumed(bytes, buffer))

# Preserve both causes if early close itself fails. Normal EOF/read failure
# already closes the response body; its second close is an idempotent no-op.
def outcome(-E: Data, result: Result<&2, &2, PrimaryError<E>, List<&2, U32>>, cleanup: Result<&2, &2, Progress.Error<E>, Unit>) -> Result<&2, &2, Error<E>, List<&2, U32>>:
  match result cleanup:
    case Done{bytes} Done{_}: Done{bytes}
    case Fail{error} Done{_}: Fail{PrimaryFailure{error}}
    case Done{_} Fail{error}: Fail{CleanupFailure{error}}
    case Fail{primary} Fail{cleanup}: Fail{FailureWithCleanup{primary, cleanup}}
