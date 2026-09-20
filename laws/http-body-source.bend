import Base
import ../packages/runtime/src/http-body-source.bend as Source
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/sse-reader.bend as SSE

law bytes_are_not_decoded_or_changed:
  for -T: Data
  for -E: Data
  for map: Progress.Error<T> -> E
  for +bytes: List<&2, U32>
  {Source.chunk(T, E, map, Done{Some{bytes}}) == Done{Some{SSE.Bytes{bytes}}} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law eof_is_not_an_empty_chunk:
  for -T: Data
  for -E: Data
  for map: Progress.Error<T> -> E
  {Source.chunk(T, E, map, Done{None{}}) == Done{None{}} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law read_failure_uses_the_mapping:
  for -T: Data
  for -E: Data
  for map: Progress.Error<T> -> E
  for +error: Progress.Error<T>
  {Source.chunk(T, E, map, Fail{error}) == Fail{map(error)} : Result<&2, &2, E, Maybe<&2, SSE.Chunk>>}

law close_failure_uses_the_mapping:
  for -T: Data
  for -E: Data
  for map: Progress.Error<T> -> E
  for +error: Progress.Error<T>
  {Source.closeResult(T, E, map, Fail{error}) == Fail{map(error)} : Result<&2, &2, E, Unit>}

law closed_owner_release_has_no_transport_io:
  for -T: Data
  for -State: Type
  for -E: Data
  for map: Progress.Error<T> -> E
  for close: State -> IO(Result<&2, &2, T, Unit>)
  for fields: Maybe<&2, List<&2, Header.Header>>
  {Source.releaseBody(T, State, E, map, close, Response.Closed{fields}) == IO.pure(Result<&2, &2, E, Unit>, Done{Unit{}}) : IO(Result<&2, &2, E, Unit>)}
