import Base
import ../packages/runtime/src/http-response.bend as Buffer
import ../packages/runtime/src/bounded.bend as Bytes
import ../packages/runtime/src/http-response.bend as Progress
import ../packages/runtime/src/http-response.bend as Source
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-message.bend as Header
import ../packages/runtime/src/sse.bend as SSE
import ../packages/runtime/src/http-response.bend as Metadata
import ../packages/runtime/src/http-message.bend as Head
import ../packages/runtime/src/http-message.bend as Status
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-response.bend as Stream
import ../packages/runtime/src/http-response.bend as Classify

# Http body buffer

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


# Http body source

law bytes_are_not_decoded_or_changed:
  for -T: Data
  for -E: Data
  for map: Progress.ResponseProgressError<T> -> E
  for +bytes: List<&2, U32>
  {Source.chunk(T, E, map, Done{Some{bytes}}) == Done{Some{SSE.Bytes{bytes}}} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law eof_is_not_an_empty_chunk:
  for -T: Data
  for -E: Data
  for map: Progress.ResponseProgressError<T> -> E
  {Source.chunk(T, E, map, Done{None{}}) == Done{None{}} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law read_failure_uses_the_mapping:
  for -T: Data
  for -E: Data
  for map: Progress.ResponseProgressError<T> -> E
  for +error: Progress.ResponseProgressError<T>
  {Source.chunk(T, E, map, Fail{error}) == Fail{map(error)} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law close_failure_uses_the_mapping:
  for -T: Data
  for -E: Data
  for map: Progress.ResponseProgressError<T> -> E
  for +error: Progress.ResponseProgressError<T>
  {Source.closeResult(T, E, map, Fail{error}) == Fail{map(error)} : Result<&2, &2, E, Unit>}

law closed_owner_release_has_no_transport_io:
  for -T: Data
  for -State: Type
  for -E: Data
  for map: Progress.ResponseProgressError<T> -> E
  for close: State -> IO(Result<&2, &2, T, Unit>)
  for fields: Maybe<&2, List<&2, Header.Header>>
  {Source.releaseBody(T, State, E, map, close, Response.Closed{fields}) == IO.pure(Result<&2, &2, E, Unit>, Done{Unit{}}) : IO(Result<&2, &2, E, Unit>)}


# Http response metadata

law fields_partition:
  for +left: List<&2, Header.Header>
  for +initial: Headers.Headers
  for +right: List<&2, Header.Header>
  {Metadata.appendFields(List.append(&2, Header.Header, left, right), initial) == Metadata.appendFields(right, Metadata.appendFields(left, initial)) : Headers.Headers}

law empty_fields_preserve_headers:
  for +initial: Headers.Headers
  {Metadata.appendFields(Nil{}, initial) == initial : Headers.Headers}

law original_head_retained:
  for +head: Head.ResponseHead
  for expose: Bool
  {Metadata.original(Metadata.fromHead(head, expose)) == head : Head.ResponseHead}

law exposure_retained:
  for head: Head.ResponseHead
  for +expose: Bool
  {Metadata.bodyPresent(Metadata.fromHead(head, expose)) == expose : Bool}

law status_retained:
  for major: U32
  for minor: U32
  for +code: U32
  for reason: List<&2, U32>
  for fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.metadataStatus(Metadata.fromHead(Head.ResponseHead{Status.StatusLine{major, minor, code, reason}, fields}, expose)) == code : U32}

law success_classification:
  for major: U32
  for minor: U32
  for +code: U32
  for reason: List<&2, U32>
  for fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.ok(Metadata.fromHead(Head.ResponseHead{Status.StatusLine{major, minor, code, reason}, fields}, expose)) == (U32.is_ge(code, 200) && U32.is_lt(code, 300)) : Bool}

law one_field_preserved:
  for +initial: Headers.Headers
  for +field: Header.Header
  {Metadata.appendFields(field <> Nil{}, initial) == Headers.appendField(initial, field) : Headers.Headers}

law received_headers_retained:
  for line: Status.StatusLine
  for +fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.headers(Metadata.fromHead(Head.ResponseHead{line, fields}, expose)) == Metadata.appendFields(fields, Headers.new()) : Headers.Headers}


# Http response progress

law final_head_transfers_metadata:
  for -E: Data
  for +head: Head.ResponseHead
  for +expose: Bool
  {Progress.headDecision(E, Done{Some{Stream.FinalHead{head, expose}}}) == Progress.Ready{Metadata.fromHead(head, expose)} : Progress.HeadDecision<E>}

law informational_heads_do_not_finish:
  for -E: Data
  for head: Head.ResponseHead
  {Progress.headDecision(E, Done{Some{Stream.InformationalHead{head}}}) == Progress.SeekHead{} : Progress.HeadDecision<E>}

law nonempty_chunks_preserve_bytes:
  for -E: Data
  for +first: U32
  for +rest: List<&2, U32>
  {Progress.bodyDecision(E, True{}, Done{Some{Stream.BodyData{first <> rest}}}) == Progress.Chunk{first <> rest} : Progress.BodyDecision<E>}

law hidden_body_does_not_expose_bytes:
  for -E: Data
  for bytes: List<&2, U32>
  {Progress.bodyDecision(E, False{}, Done{Some{Stream.BodyData{bytes}}}) == Progress.ReadMore{} : Progress.BodyDecision<E>}

law empty_chunk_is_not_completion:
  for -E: Data
  for expose: Bool
  {Progress.bodyDecision(E, expose, Done{Some{Stream.BodyData{Nil{}}}}) == Progress.ReadMore{} : Progress.BodyDecision<E>}

law completion_retains_trailers:
  for -E: Data
  for expose: Bool
  for +fields: List<&2, Header.Header>
  {Progress.bodyDecision(E, expose, Done{Some{Stream.Completed{fields}}}) == Progress.Complete{fields} : Progress.BodyDecision<E>}

law hidden_body_does_not_hide_failure:
  for -E: Data
  for expose: Bool
  for +error: E
  {Progress.bodyDecision(E, expose, Fail{error}) == Progress.ResponseProgressBodyFailure{Progress.TransportFailure{error}} : Progress.BodyDecision<E>}

law cleanup_retains_primary:
  for -E: Data
  for +error: Progress.ResponseProgressPrimaryError<E>
  {Progress.progressOutcome(E, Some{error}, Done{Unit{}}) == Fail{Progress.ResponseProgressPrimaryFailure{error}} : Result<&2, &2, Progress.ResponseProgressError<E>, Unit>}

law dual_failure_retains_both:
  for -E: Data
  for +error: Progress.ResponseProgressPrimaryError<E>
  for +cleanup: E
  {Progress.progressOutcome(E, Some{error}, Fail{cleanup}) == Fail{Progress.ResponseProgressFailureWithCleanup{error, cleanup}} : Result<&2, &2, Progress.ResponseProgressError<E>, Unit>}

law cleanup_failure_is_not_success:
  for -E: Data
  for +cleanup: E
  {Progress.progressOutcome(E, None{}, Fail{cleanup}) == Fail{Progress.ResponseProgressCleanupFailure{cleanup}} : Result<&2, &2, Progress.ResponseProgressError<E>, Unit>}


# Http abort classification

law lone_transport_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.TransportFailure{error}}) == classify(error) : Bool}

law lone_cleanup_uses_classifier:
  for -E: Data
  for classify: E -> Bool
  for +error: E
  {Classify.standalone(E, classify, Progress.ResponseProgressCleanupFailure{error}) == classify(error) : Bool}

law combined_failures_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for error: Progress.ResponseProgressPrimaryError<E>
  for cleanup: E
  {Classify.standalone(E, classify, Progress.ResponseProgressFailureWithCleanup{error, cleanup}) == False{} : Bool}

law unexpected_events_are_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  for event: Stream.StreamEvent
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.UnexpectedEvent{event}}) == False{} : Bool}

law missing_head_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.MissingHead{}}) == False{} : Bool}

law missing_completion_is_not_cancellation:
  for -E: Data
  for classify: E -> Bool
  {Classify.standalone(E, classify, Progress.ResponseProgressPrimaryFailure{Progress.MissingCompletion{}}) == False{} : Bool}
