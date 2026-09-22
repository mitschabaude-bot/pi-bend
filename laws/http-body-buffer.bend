import Base
import ../packages/runtime/src/http-response.bend as Buffer
import ../packages/runtime/src/bounded-bytes.bend as Bytes
import ../packages/runtime/src/http-response.bend as Progress

law successful_body_preserved:
  for -E: Data
  for +bytes: List<&2, U32>
  {Buffer.outcome(E, Done{bytes}, Done{Unit{}}) == Done{bytes} : Result<&2, &2, Buffer.Error<E>, List<&2, U32>>}

law primary_failure_preserved:
  for -E: Data
  for +error: Buffer.PrimaryError<E>
  {Buffer.outcome(E, Fail{error}, Done{Unit{}}) == Fail{Buffer.PrimaryFailure{error}} : Result<&2, &2, Buffer.Error<E>, List<&2, U32>>}

law cleanup_failure_rejects_body:
  for -E: Data
  for bytes: List<&2, U32>
  for +error: Progress.ResponseProgressError<E>
  {Buffer.outcome(E, Done{bytes}, Fail{error}) == Fail{Buffer.CleanupFailure{error}} : Result<&2, &2, Buffer.Error<E>, List<&2, U32>>}

law simultaneous_failures_preserved:
  for -E: Data
  for +primary: Buffer.PrimaryError<E>
  for +cleanup: Progress.ResponseProgressError<E>
  {Buffer.outcome(E, Fail{primary}, Fail{cleanup}) == Fail{Buffer.FailureWithCleanup{primary, cleanup}} : Result<&2, &2, Buffer.Error<E>, List<&2, U32>>}

law read_failure_rejects_prefix:
  for -E: Data
  for buffer: Bytes.State
  for +error: Progress.ResponseProgressError<E>
  {Buffer.nextBodyBuffer(E, buffer, Fail{error}) == Buffer.Finished{Fail{Buffer.ReadFailure{error}}} : Buffer.Decision<E>}

law any_excess_stops:
  for -E: Data
  for +prefix: List<&2, U32>
  for byte: U32
  for suffix: List<&2, U32>
  {Buffer.buffered(E, Bytes.consumed(List.append(&2, U32, prefix, byte <> suffix), Bytes.create(List.length(&2, U32, prefix)))) == Buffer.Finished{Fail{Buffer.ByteLimitExceeded{}}} : Buffer.Decision<E>}
