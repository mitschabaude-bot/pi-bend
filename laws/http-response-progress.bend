import Base
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-head.bend as Head
import ../packages/runtime/src/http-header.bend as Header

law final_head_transfers_metadata:
  for -E: Data
  for +head: Head.ResponseHead
  for +expose: Bool
  {Progress.head(E, Done{Some{Stream.FinalHead{head, expose}}}) == Progress.Ready{Metadata.fromHead(head, expose)} : Progress.HeadDecision<E>}

law informational_heads_do_not_finish:
  for -E: Data
  for head: Head.ResponseHead
  {Progress.head(E, Done{Some{Stream.InformationalHead{head}}}) == Progress.SeekHead{} : Progress.HeadDecision<E>}

law nonempty_chunks_preserve_bytes:
  for -E: Data
  for +first: U32
  for +rest: List<&2, U32>
  {Progress.body(E, True{}, Done{Some{Stream.BodyData{first <> rest}}}) == Progress.Chunk{first <> rest} : Progress.BodyDecision<E>}

law hidden_body_does_not_expose_bytes:
  for -E: Data
  for bytes: List<&2, U32>
  {Progress.body(E, False{}, Done{Some{Stream.BodyData{bytes}}}) == Progress.ReadMore{} : Progress.BodyDecision<E>}

law empty_chunk_is_not_completion:
  for -E: Data
  for expose: Bool
  {Progress.body(E, expose, Done{Some{Stream.BodyData{Nil{}}}}) == Progress.ReadMore{} : Progress.BodyDecision<E>}

law completion_retains_trailers:
  for -E: Data
  for expose: Bool
  for +fields: List<&2, Header.Header>
  {Progress.body(E, expose, Done{Some{Stream.Completed{fields}}}) == Progress.Complete{fields} : Progress.BodyDecision<E>}

law hidden_body_does_not_hide_failure:
  for -E: Data
  for expose: Bool
  for +error: E
  {Progress.body(E, expose, Fail{error}) == Progress.BodyFailure{Progress.TransportFailure{error}} : Progress.BodyDecision<E>}

law cleanup_retains_primary:
  for -E: Data
  for +error: Progress.PrimaryError<E>
  {Progress.outcome(E, Some{error}, Done{Unit{}}) == Fail{Progress.PrimaryFailure{error}} : Result<&2, &2, Progress.Error<E>, Unit>}

law dual_failure_retains_both:
  for -E: Data
  for +error: Progress.PrimaryError<E>
  for +cleanup: E
  {Progress.outcome(E, Some{error}, Fail{cleanup}) == Fail{Progress.FailureWithCleanup{error, cleanup}} : Result<&2, &2, Progress.Error<E>, Unit>}

law cleanup_failure_is_not_success:
  for -E: Data
  for +cleanup: E
  {Progress.outcome(E, None{}, Fail{cleanup}) == Fail{Progress.CleanupFailure{cleanup}} : Result<&2, &2, Progress.Error<E>, Unit>}
